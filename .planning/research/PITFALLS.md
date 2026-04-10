# Pitfalls Research

**Domain:** GitOps Bridge Pattern on OCI/OKE — Terraform bootstrap + ArgoCD self-management
**Researched:** 2026-04-09
**Confidence:** HIGH (OCI-specific findings from official docs; ArgoCD pitfalls from GitHub issues + official docs)

---

## Critical Pitfalls

### Pitfall 1: OCI Workload Identity Requires Workload Policies, Not Dynamic Group Rules

**What goes wrong:**
The existing Terraform IAM module (terraform/infra/modules/oci-iam/main.tf) creates a dynamic group with `resource.type = 'workload'` and writes a dynamic group policy. This is the wrong mechanism for OKE pod-level identity. OKE Workload Identity does NOT work with dynamic groups. ESO pods configured with `principalType: Workload` will fail authentication silently — the ClusterSecretStore reports `Valid` but ExternalSecret syncs fail with a 401 or permissions error.

**Why it happens:**
Dynamic groups are the OCI-native pattern for instance principals. Developers familiar with OCI instance principals copy that pattern. The OCI docs distinguish between Instance Principal (uses dynamic groups) and Workload Identity (uses `any-user` policies with `request.principal.type = 'workload'`), but the distinction is easy to miss.

**How to avoid:**
Use the correct IAM policy format for Workload Identity:
```
Allow any-user to manage secret-bundles in compartment <compartment> where all {
  request.principal.type = 'workload',
  request.principal.namespace = 'external-secrets',
  request.principal.service_account = 'external-secrets',
  request.principal.cluster_id = '<cluster-ocid>'
}
```
Do NOT wrap this in a dynamic group. The ESO Helm values must set `serviceAccount.annotations` to cause `automountServiceAccountToken: true`, and the ESO ClusterSecretStore must set `spec.provider.oracle.principalType: Workload`. These three — policy, service account, and store spec — must be consistent.

**Warning signs:**
- ClusterSecretStore shows `Valid` but ExternalSecrets remain `SecretSyncedError`
- OCI audit logs show 401 from `external-secrets` service account
- kubectl describe clustersecretstore shows a permissions error on vault bundle reads
- The dynamic group exists in OCI console but no Workload Identity policy exists

**Phase to address:**
Phase creating ESO addon + ClusterSecretStore (immediately before any ExternalSecret is created). Verify end-to-end with a test ExternalSecret targeting a known vault secret before proceeding.

---

### Pitfall 2: ArgoCD Ingress Bootstrap — the Circular Dependency

**What goes wrong:**
ArgoCD Server is deployed with `--insecure` and ClusterIP service. The UI is only accessible after ingress-nginx is running and has obtained an OCI Load Balancer IP. But ingress-nginx is managed by ArgoCD as an addon. Before ingress-nginx syncs and the OCI LB provisions (which takes 3-8 minutes on OCI), ArgoCD is unreachable from outside the cluster. If the bootstrap Application (root app) includes the ArgoCD Ingress resource in the same sync as the ingress-nginx Application, ArgoCD will apply the Ingress object before ingress-nginx is Ready — the Ingress will have no address and ArgoCD will mark it as Progressing indefinitely.

**Why it happens:**
Engineers deploy everything in wave 0 assuming ArgoCD health checks will sequence things. ArgoCD's Ingress health check only tracks `status.loadBalancer.ingress` — an Ingress with no address is `Progressing`, not `Healthy`. This blocks downstream wave resources if sync waves are used, or causes the root app to sit in Progressing if not.

**How to avoid:**
Separate the ArgoCD Ingress resource from the ingress-nginx Application using sync waves:
- Wave -10: ingress-nginx Application (including its LoadBalancer service with OCI annotations)
- Wave 0: ArgoCD Ingress resource (only after ingress-nginx service has an IP)

Also, during initial bootstrap, access ArgoCD via `kubectl port-forward` for the first configuration steps. Do not depend on external access being available before wave ordering has completed. The OCI LB provisioning takes additional time on top of ingress-nginx pod startup — account for 5-10 minutes total.

**Warning signs:**
- ArgoCD root app stuck in `Progressing` after initial sync
- `kubectl get ingress -n argocd` shows no ADDRESS
- OCI console shows no Load Balancer in the networking section
- ArgoCD events show: `Progressing: Waiting for Ingress`

**Phase to address:**
Bootstrap phase — must be designed before the gitops-setup repo structure is created. The repo must encode sync waves from the first commit.

---

### Pitfall 3: ESO ClusterSecretStore CRD Race Condition

**What goes wrong:**
The GitOps repo deploys the ESO Helm chart (which installs CRDs) and the ClusterSecretStore manifest in the same ArgoCD Application or in separate Applications without a health gate. The CRD for `ClusterSecretStore` (external-secrets.io/v1beta1 or v1) may not be established by the Kubernetes API server before the ApplicationSet reconciler tries to apply the ClusterSecretStore CR. The sync fails with `no matches for kind "ClusterSecretStore"`.

**Why it happens:**
ArgoCD within a single Application respects sync waves for resources (CRD in wave -1, CR in wave 0), but only if both resources are in the same Application. When ESO CRDs are in one Application and the ClusterSecretStore is in another Application (common in ApplicationSet-based addon structures), ArgoCD has no cross-Application health gate by default. Progressive Syncs (Beta) can gate this but require explicit configuration.

**How to avoid:**
Two valid approaches:

Option A (preferred): Put the ClusterSecretStore manifest inside the ESO Application itself with a higher sync wave than the Helm chart resources. Use `argocd.argoproj.io/sync-wave: "10"` on the ClusterSecretStore. The ESO CRDs are installed by Helm in wave 0, the ClusterSecretStore waits for wave 10.

Option B: Use a separate Application for ClusterSecretStore with `syncPolicy.syncOptions: [SkipDryRunOnMissingResource=true]` and configure it to only sync after the ESO Application is Healthy using ApplicationSet Progressive Syncs or manual ordering during bootstrap.

Never place the ClusterSecretStore in a wave earlier than or equal to the ESO Helm release within the same Application.

**Warning signs:**
- ArgoCD sync fails with: `unable to recognize "clustersecretstore.yaml": no matches for kind "ClusterSecretStore" in version "external-secrets.io/v1beta1"`
- ESO Application shows Healthy but ClusterSecretStore Application is OutOfSync/SyncFailed
- `kubectl get crd | grep external-secrets` shows the CRD does not yet have `ESTABLISHED: True`

**Phase to address:**
Phase defining the gitops-setup repo structure — specifically the addon Application layout and sync wave assignments.

---

### Pitfall 4: Terraform helm_release Conflicts with ArgoCD Self-Management

**What goes wrong:**
Terraform installs ArgoCD via `helm_release`. ArgoCD then manages its own configuration via a self-managed Application in the gitops-setup repo. On subsequent `terraform apply` runs, Terraform detects drift between its `helm_release` state and what ArgoCD has changed (labels, annotations, replica counts, Helm values injected by ArgoCD). Terraform tries to reconcile by reinstalling or updating the chart, which either conflicts with ArgoCD's desired state or causes a rollback that ArgoCD immediately re-syncs forward — an infinite loop.

**Why it happens:**
Terraform's `helm_release` resource tracks installed chart values. When ArgoCD manages the release, it adds its own labels and may modify values. Terraform's next plan sees these as drift and wants to correct them. Without `lifecycle { ignore_changes = all }` on the `helm_release` resource, every `terraform apply` becomes a conflict.

**How to avoid:**
Add `lifecycle { ignore_changes = all }` to the ArgoCD `helm_release` resource in the Terraform k8s layer. This makes the resource effectively write-once. Terraform bootstraps ArgoCD once; from that point, all ArgoCD upgrades happen through the gitops-setup repo. Never run `terraform apply` on the k8s layer after the GitOps bridge is established — or explicitly document that it is safe only for non-ArgoCD modules.

After the bridge is established, the recommended workflow is: destroy the entire `terraform/k8s/` layer and never use Terraform k8s modules again. The gitops-setup repo becomes the single source of truth.

**Warning signs:**
- `terraform plan` shows changes to the ArgoCD `helm_release` resource after ArgoCD is running
- ArgoCD shows the self-managed Application OutOfSync after a `terraform apply`
- ArgoCD immediately re-syncs after Terraform modifies chart values
- Helm history shows alternating revisions with conflicting values

**Phase to address:**
Terraform refactor phase — before destroying the k8s layer, add `lifecycle { ignore_changes = all }` as an intermediate step. Document the handoff boundary clearly.

---

### Pitfall 5: Bridge Secret Annotation Drift — Infra Changes Not Reflected in GitOps

**What goes wrong:**
Terraform creates the GitOps Bridge Secret with infra metadata (compartment OCID, subnet IDs, vault OCID, etc.) as annotations. The ApplicationSet generator reads these annotations to drive addon configuration. If infra changes — e.g., the VCN subnet is recreated, the Vault is replaced, or the OKE cluster is rebuilt — the bridge secret annotations become stale. Addons continue to sync against old values (old subnet ID for ingress LB, old vault OCID for ESO). ArgoCD shows everything Healthy while the underlying infra references are broken.

**Why it happens:**
The bridge secret is created once during bootstrap. ArgoCD does not re-read Terraform outputs automatically. Infra changes require an explicit `terraform apply` to update the secret, and then the ApplicationSet must reconcile with new values. This handoff is manual and undocumented in most implementations.

**How to avoid:**
- Pin infra resources that appear in bridge secret annotations with `prevent_destroy = true` (already in scope for cluster, VCN, vault).
- Document in the runbook: any Terraform infra change that modifies an OCID or subnet ID MUST be followed by verifying the bridge secret is updated and ApplicationSet has reconciled.
- After `terraform apply` updates the bridge secret, trigger a manual ArgoCD sync of the root Application and watch the ApplicationSet regenerate with new values.
- Consider adding a Terraform output test that checks bridge secret annotations match current resource OCIDs.

**Warning signs:**
- ArgoCD shows all Applications Healthy but ESO ExternalSecrets fail with vault not found
- The OCI Load Balancer provisioned by ingress-nginx targets a deleted subnet
- `kubectl get secret -n argocd <bridge-secret> -o yaml` shows OCIDs that do not match current OCI console resources
- `terraform plan` shows changes to the bridge secret despite "no changes" in infra

**Phase to address:**
Bootstrap phase (secret creation design) and ongoing operations runbook.

---

### Pitfall 6: OCI Load Balancer Annotation Mismatch on ingress-nginx Service

**What goes wrong:**
ingress-nginx is deployed via ArgoCD with a `LoadBalancer` service. OCI CCM reads annotations on that service to provision the correct load balancer shape, subnet, and security rules. If the annotations are wrong, missing, or use deprecated keys, OCI provisions a default LB (smallest shape, potentially wrong subnet). Common mistakes:
- Missing `service.beta.kubernetes.io/oci-load-balancer-subnet1` pointing to the public subnet OCID — LB ends up in the wrong subnet
- Missing `service.beta.kubernetes.io/oci-load-balancer-shape: flexible` with min/max bandwidth — OCI provisions a 100Mbps fixed shape
- Using `service.beta.kubernetes.io/oci` prefix for newer annotations that require `oci.oraclecloud.com/` prefix
- The subnet OCID in the annotation is a private subnet — LB is created without a public IP and becomes unreachable

**Why it happens:**
OCI LB annotations differ from AWS/GCP patterns developers may copy. The subnet OCID must be the correct public subnet OCID — a value that comes from Terraform outputs, not a static string. When hardcoded incorrectly in the gitops-setup Helm values, the error only surfaces when OCI CCM provisions the LB and the networking is wrong.

**How to avoid:**
Pass the public subnet OCID from the bridge secret annotation into the ingress-nginx Helm values via ApplicationSet template substitution. Never hardcode OCIDs in the gitops-setup repo. Required annotations for OCI with flexible LB:
```yaml
service.beta.kubernetes.io/oci-load-balancer-subnet1: "<public-subnet-ocid>"
service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "100"
```

**Warning signs:**
- `kubectl get svc -n ingress-nginx` shows `EXTERNAL-IP: <pending>` for more than 10 minutes
- OCI console shows a Load Balancer in the wrong subnet or with the wrong shape
- OCI console shows no Load Balancer was created despite the service being `LoadBalancer` type
- OCI CCM logs show annotation parsing errors

**Phase to address:**
ingress-nginx addon phase — verify LB is provisioned with correct subnet and shape before moving forward.

---

### Pitfall 7: ArgoCD App-of-Apps Sync Wave Ordering for In-Cluster Bootstrap

**What goes wrong:**
The root Application manages child Applications via an App-of-Apps pattern. If all child Applications are created in wave 0, ArgoCD creates them simultaneously. Addons with CRD/CR ordering dependencies (ESO ClusterSecretStore after ESO Helm, ArgoCD Ingress after ingress-nginx, cert-manager ClusterIssuer after cert-manager Helm) will fail their first sync because dependencies are not yet Healthy. ArgoCD retries, but the initial chaos causes confusing error states.

Additionally, there is a known ArgoCD limitation: ApplicationSet does NOT natively support sync waves across Applications in the set — all Applications are created simultaneously unless Progressive Syncs (Beta) are enabled explicitly.

**Why it happens:**
Engineers apply sync wave annotations to their manifests but forget that ApplicationSet ignores `argocd.argoproj.io/sync-wave` on Application resources by default. The annotation is respected within a single Application's resources, not across Applications managed by an ApplicationSet.

**How to avoid:**
For cross-Application ordering, use one of:
1. App-of-Apps with explicit sync waves on the parent Application manifest (not ApplicationSet)
2. ApplicationSet with Progressive Syncs enabled (`spec.strategy.type: RollingSync`) — requires ArgoCD 2.6+ and feature flag
3. Manual ordering during initial bootstrap: sync Applications one at a time via CLI until the cluster is stable

The recommended wave ordering for this project:
- Wave -20: namespace creation jobs (if any)
- Wave -10: cert-manager (CRDs needed by other addons)
- Wave -5: ingress-nginx (must be Ready before ArgoCD Ingress exists)
- Wave 0: external-secrets-operator (CRDs)
- Wave 5: ClusterSecretStore (depends on ESO CRDs)
- Wave 10: ArgoCD self-managed Application (depends on GitOps repo access, ESO for secrets)
- Wave 20: ArgoCD Ingress, ExternalSecrets for ArgoCD config (depends on ingress-nginx IP)

**Warning signs:**
- Multiple Applications stuck in `SyncFailed` simultaneously after first bootstrap
- `cert-manager.io/cluster-issuer` annotation rejected because CRD not yet installed
- ESO ClusterSecretStore not found when ExternalSecret is applied
- ArgoCD shows wave numbers in annotations but Applications all sync at the same time

**Phase to address:**
gitops-setup repo structure phase — wave assignments must be designed before any manifest is written.

---

### Pitfall 8: BASIC OKE Tier Does Not Support Enhanced Cluster Features

**What goes wrong:**
The existing OKE cluster is provisioned as BASIC tier. Several advanced OKE features only work on Enhanced clusters:
- OKE Workload Identity requires Enhanced cluster tier
- OCI Native Ingress Controller (OCI's alternative to ingress-nginx) requires Enhanced tier
- Virtual nodes require Enhanced tier

If the existing cluster is BASIC, OKE Workload Identity will not work regardless of how correctly ESO and the IAM policy are configured. ESO will fail authentication and ClusterSecretStores will be permanently invalid.

**Why it happens:**
The OCI documentation for Workload Identity states "Enhanced clusters only" but this is easy to miss when following ESO setup guides that do not mention OKE tier requirements. The cluster OCID is already set; engineers assume the IAM config is wrong and iterate on policies instead of checking cluster tier.

**How to avoid:**
Before writing a single line of ESO or Workload Identity config, verify:
```
oci ce cluster get --cluster-id <ocid> | grep -i type
```
If `clusterType: BASIC` — Workload Identity is not available. The cluster must be recreated as Enhanced. This is a destructive operation that requires draining workloads, destroying the BASIC cluster, and creating an Enhanced cluster with the same VCN/subnet config.

**Warning signs:**
- ESO ClusterSecretStore is `Invalid` with an authentication error despite correct IAM policies
- OCI audit logs show no workload identity token requests from the ESO pod (token is never generated)
- kubectl exec into ESO pod and attempt to get workload identity token returns 404 or connection refused
- OKE documentation feature matrix shows the feature requires "Enhanced" cluster

**Phase to address:**
Pre-bootstrap verification — check cluster tier before designing the ESO/Workload Identity integration.

---

### Pitfall 9: GitHub OAuth / Dex Redirect URI Breaks Without TLS First

**What goes wrong:**
GitHub OAuth Apps require an HTTPS redirect URI. The ArgoCD Dex connector is configured with `redirectURI: https://argocd.assessforge.com/api/dex/callback`. If ArgoCD is deployed without a TLS certificate (cert-manager + Let's Encrypt not yet provisioned), GitHub OAuth App registration can be done but the callback will fail when accessed over HTTP. Additionally, if Dex is configured with the HTTPS redirect URI before cert-manager has issued a valid certificate, users cannot log in at all — even the admin password login may be disrupted.

**Why it happens:**
Engineers configure GitHub SSO in the gitops-setup repo before cert-manager and the TLS ClusterIssuer are Healthy. The Dex configuration is applied by ArgoCD before the TLS certificate is issued. The SSO redirect loop fails. The initial admin password login is unaffected (it does not go through Dex), but all GitHub org member logins fail.

**How to avoid:**
Bootstrap sequence must enforce:
1. cert-manager Application syncs and ClusterIssuer is Ready
2. ingress-nginx is Healthy with an LB IP
3. ArgoCD Ingress with TLS annotation is applied (triggers cert-manager to issue certificate)
4. Certificate reaches `Ready: True` (can take 2-5 minutes with Let's Encrypt HTTP01 challenge)
5. ONLY AFTER certificate is valid: enable Dex GitHub connector in ArgoCD config ExternalSecret

Keep the ArgoCD Dex connector config commented out or disabled in the initial bootstrap commit. Enable it in a second PR after TLS is verified.

**Warning signs:**
- GitHub OAuth callback shows `redirect_uri_mismatch` or `ERR_SSL_PROTOCOL_ERROR`
- `kubectl get certificate -n argocd` shows `Ready: False`
- `kubectl describe certificaterequest` shows HTTP01 challenge not completing
- cert-manager logs show ACME HTTP01 challenge failing (Cloudflare DNS must point to LB IP before challenge completes)

**Phase to address:**
Phase enabling ArgoCD SSO via GitHub/Dex — must come AFTER cert-manager and ingress phases are verified.

---

### Pitfall 10: Terraform k8s Layer Destruction Order

**What goes wrong:**
The existing `terraform/k8s/` layer manages ArgoCD, external-secrets, ingress-nginx, kyverno, and network-policies. When running `terraform destroy` on this layer to hand off to GitOps, resources may be destroyed in the wrong order. Specifically, if the Kubernetes provider tries to delete the `argocd` namespace before deleting the `external-secrets` module's ExternalSecret/ClusterSecretStore resources, the namespace deletion hangs because custom resources with finalizers block namespace termination. The destroy hangs indefinitely.

Also: if ArgoCD has already been bootstrapped with a root Application before the k8s layer is destroyed, ArgoCD will immediately re-create resources that Terraform is trying to delete — Terraform and ArgoCD fight.

**Why it happens:**
Terraform destroy order is determined by resource dependency graph, not by Kubernetes namespace deletion ordering. CRD-based resources with finalizers (ExternalSecret's finalizer on secret cleanup) block namespace deletion. Meanwhile ArgoCD's reconciler is actively working against the destroy.

**How to avoid:**
Correct order for the migration:
1. Pause ArgoCD auto-sync on the root Application (set `operation: nil` or sync policy to manual) BEFORE destroying k8s layer
2. Run `kubectl delete externalsecret --all -A` and `kubectl delete clustersecretstore --all` manually to trigger finalizer cleanup
3. Only then run `terraform destroy` on the k8s layer
4. Re-enable ArgoCD auto-sync once the gitops-setup root Application is in place

Do not run ArgoCD root Application bootstrap until AFTER the k8s layer is destroyed.

**Warning signs:**
- `terraform destroy` hangs on `kubernetes_namespace.argocd: Destruction in progress`
- `kubectl get namespace argocd -o yaml` shows `phase: Terminating` indefinitely
- ArgoCD re-creates a resource as soon as Terraform deletes it
- kubectl describe namespace shows finalizers blocking deletion

**Phase to address:**
Migration phase — the explicit sequence from Terraform k8s to GitOps must be documented as a runbook, not left to improvisation.

---

### Pitfall 11: ESO Using Deprecated v1beta1 API After Chart Upgrade

**What goes wrong:**
The existing codebase uses `apiVersion: external-secrets.io/v1beta1` for ClusterSecretStore and ExternalSecret. ESO is migrating to `external-secrets.io/v1` in newer chart versions. If the ESO chart is upgraded in the gitops-setup repo without simultaneously updating all manifests to `v1`, ESO will deprecation-warn then eventually reject `v1beta1` resources — breaking all secret syncs cluster-wide.

**Why it happens:**
The gitops-setup repo pins the ESO chart version, but someone bumps the version in a PR without auditing all dependent manifests. The v1beta1 API may continue to work for several chart versions (with deprecation warnings) until the version where it is removed.

**How to avoid:**
When the gitops-setup repo is created, use `external-secrets.io/v1` from the start — do not copy the v1beta1 manifests from the Terraform k8s layer. This avoids ever having a migration burden. Set the chart version to a version that supports v1 (ESO 0.10.x+).

**Warning signs:**
- ESO pod logs show: `v1beta1 is deprecated, please migrate to v1`
- After chart upgrade, ExternalSecrets fail with: `no matches for kind "ExternalSecret" in version "external-secrets.io/v1beta1"`
- `kubectl get crd externalsecrets.external-secrets.io -o yaml | grep served` shows v1beta1 as `served: false`

**Phase to address:**
ESO addon phase in gitops-setup — use v1 API from the beginning, document this explicitly.

---

### Pitfall 12: ArgoCD initial-admin-secret Lost Before GitOps Config Takes Over

**What goes wrong:**
During bootstrap, Terraform installs ArgoCD. ArgoCD generates `argocd-initial-admin-secret` with the admin password. If the operator forgets to retrieve this password before it is deleted (or before GitHub SSO is fully working), access to ArgoCD is lost. Recovery requires kubectl exec into the argocd-server pod to reset the password — only possible if the operator still has kubectl access via bastion.

**Why it happens:**
The bootstrap sequence is rushed. Engineers assume GitHub SSO will work immediately and delete the initial admin secret as a "security cleanup" step. GitHub SSO fails (see Pitfall 9), and there is no fallback.

**How to avoid:**
During bootstrap:
1. Retrieve and store the initial admin password immediately: `kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d`
2. Store it temporarily in OCI Vault as a manual secret
3. Do NOT delete the secret until GitHub SSO is verified end-to-end with at least one org member login
4. After SSO is working, disable the local admin account in ArgoCD config (`admin.enabled: "false"`) rather than just deleting the initial secret

**Warning signs:**
- GitHub SSO is not yet working and the initial-admin-secret was deleted
- kubectl access to the cluster is still available (recovery is possible)
- OCI console bastion sessions still available (can kubectl exec to reset password)

**Phase to address:**
Bootstrap phase — must be a checklist item before any security cleanup step.

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Dynamic group instead of Workload Identity policy for ESO | Familiar OCI IAM pattern | ESO cannot authenticate; entire secrets flow broken | Never — Workload Identity requires `any-user` policy |
| Hardcoding subnet/vault OCIDs in gitops-setup Helm values | Simple, no ApplicationSet templating needed | Bridge secret annotations serve no purpose; infra changes require manual gitops-setup PRs | Never — defeats the GitOps Bridge pattern |
| Skipping sync wave annotations during initial bootstrap | Faster first commit | First sync fails on CRD/CR ordering; confusing error states | Acceptable ONLY if manually syncing Applications one-by-one in correct order |
| Leaving `terraform/k8s/` layer active alongside ArgoCD | Partial rollback option | Terraform and ArgoCD fight over resource ownership; undefined state | Never beyond a 24-hour transition window |
| Committing ESO chart with `installCRDs: false` in Helm values | Control over CRD lifecycle | CRDs not installed; ClusterSecretStore CRs fail immediately | Only if CRDs are managed in a separate, lower-wave Application |
| Using `principalType: InstancePrincipal` instead of `Workload` | Works on node VMs | ESO authenticates as the node, not the pod; overly broad permissions | Never on OKE — use Workload Identity |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| OCI Vault + ESO | Setting `principalType: InstancePrincipal` when cluster is OKE | Set `principalType: Workload`; configure the ESO service account with `automountServiceAccountToken: true` |
| ESO ClusterSecretStore + OKE | Missing `namespace` field in `serviceAccountRef` when using ClusterSecretStore | ClusterSecretStore requires explicit namespace on serviceAccountRef; omitting it causes "namespace required" error |
| ingress-nginx + OCI CCM | Using wrong annotation prefix for load balancer shape | Use `service.beta.kubernetes.io/oci-load-balancer-shape` (not `oci.oraclecloud.com` prefix) for OKE CCM |
| ArgoCD Dex + GitHub OAuth | Registering GitHub OAuth App with HTTP callback URL | GitHub OAuth requires HTTPS. The callback must be `https://argocd.assessforge.com/api/dex/callback` — cert-manager must be working first |
| ArgoCD self-managed + Terraform | Running `terraform apply` on k8s layer after GitOps bridge is live | Add `lifecycle { ignore_changes = all }` to ArgoCD `helm_release` or destroy the k8s layer entirely |
| ApplicationSet cluster generator + bridge secret | Storing infra metadata in Secret `data` field instead of `metadata.annotations` | ApplicationSet cluster generator reads `metadata.annotations` and `metadata.labels`, not `data` fields; Terraform must write annotations to bridge secret |
| OCI Workload Identity + IAM | Using Dynamic Group policy (`instance.compartment.id`) | Use `any-user` policy with `request.principal.type = 'workload'` and `request.principal.cluster_id` |
| OKE private API + ArgoCD bootstrap | Running `helm install argocd` from local machine without bastion | Private API endpoint is not reachable directly; must use OCI Bastion port-forward or kubectl tunneled through bastion |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| ArgoCD repo-server OOMKilled on ARM nodes | Repo-server pod restarts; syncs fail mid-apply; ArgoCD UI shows "repo-server unavailable" | Set memory limit to at least 512Mi for repo-server; ARM (A1.Flex) has no known incompatibility but the 24GB total cluster limit is tight with 5+ addons | With more than 10 Applications or large Helm values files |
| OCI LB provisioning delay blocking health checks | ArgoCD root app stuck in Progressing for 10+ minutes after ingress-nginx sync | Account for 5-10 minute OCI LB provisioning time; do not health-gate on LB IP during initial bootstrap | Every bootstrap — not a scale issue, a timing issue |
| ApplicationSet regenerating all Applications on bridge secret change | All addon Applications restart simultaneously when any annotation changes | Make bridge secret annotations immutable for values that change frequently; only store truly static infra metadata | When Terraform infra changes cause bridge secret updates |
| ArgoCD application-controller OOM with many syncing apps | Application controller restarts; all Applications show Unknown status | Tune `--app-resync-period` and `--repo-server-timeout-seconds`; increase memory limit | Not likely with < 20 Applications |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| IAM policy uses compartment-level wildcard for ESO (`request.principal.namespace` omitted) | Any pod in any namespace can read vault secrets | Always specify `request.principal.namespace = 'external-secrets'` and `request.principal.service_account = 'external-secrets'` in the policy |
| GitHub OAuth App `clientSecret` stored in gitops-setup Git repo as plain text | Leaked secret allows anyone to impersonate GitHub OAuth App; all ArgoCD SSO sessions compromised | Store GitHub OAuth clientSecret in OCI Vault; pull via ExternalSecret into argocd namespace as Kubernetes secret |
| ArgoCD AppProject `sourceRepos: ['*']` — any repo can be deployed | Admin ArgoCD user can deploy from a malicious repo | Restrict to `https://github.com/AssessForge/*` in the AppProject manifest in gitops-setup |
| Bridge secret containing vault OCID committed to public gitops-setup repo | OCID is not a secret but reveals infra topology | Store bridge secret in-cluster only (Terraform creates it directly); never commit bridge secret values to gitops-setup repo |
| ArgoCD server `--insecure` with no TLS at ingress | Credentials and session cookies transmitted over HTTP from browser to LB | Acceptable only if cert-manager + Let's Encrypt is the next step; never ship to production without TLS at the ingress |

---

## "Looks Done But Isn't" Checklist

- [ ] **ESO Workload Identity:** ClusterSecretStore shows `Valid` — verify with an actual ExternalSecret sync, not just store status. A store can report `Valid` before the first sync attempt.
- [ ] **ingress-nginx bootstrap:** ArgoCD Application shows `Healthy` — verify `kubectl get svc -n ingress-nginx` shows a real IP in EXTERNAL-IP, not `<pending>`. Check OCI console that the LB exists in the correct public subnet.
- [ ] **ArgoCD self-managed Application:** ArgoCD manages itself — verify that a change to ArgoCD Helm values in gitops-setup repo actually reconciles. Run `terraform apply` on infra layer and confirm ArgoCD helm_release is NOT changed (lifecycle ignore_changes is working).
- [ ] **GitHub SSO:** Dex connector config applied — verify by logging out as admin and logging in with a GitHub org member account. Do not assume SSO works because the config was applied.
- [ ] **cert-manager TLS:** Certificate resource exists — verify `kubectl get certificate -n argocd` shows `Ready: True`. Browser must show a valid (not self-signed) certificate for argocd.assessforge.com.
- [ ] **Bridge secret annotations:** ApplicationSet is reading annotations — verify by running `argocd appset list` and checking that generated Applications have the correct `cluster-name`, `vault-ocid`, `subnet-id` values from the bridge secret (not hardcoded values from the gitops-setup Helm values).
- [ ] **Terraform k8s layer destroyed:** `terraform destroy` completed — verify by checking `kubectl get all --all-namespaces` no longer has resources from the old Terraform k8s modules that are not managed by the gitops-setup ArgoCD Applications.
- [ ] **OKE cluster is Enhanced tier:** Required for Workload Identity — verify with `oci ce cluster get --cluster-id <ocid> | grep clusterType` before any Workload Identity config is written.

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| OCI Workload Identity misconfiguration | LOW | Correct IAM policy in Terraform, re-apply; ESO ClusterSecretStore reconciles within 30 seconds |
| ArgoCD Ingress stuck Progressing | LOW | `argocd app sync <root-app> --force`; check OCI LB console; delete and re-create ingress if annotations wrong |
| ESO CRD race condition on bootstrap | LOW | `argocd app sync eso-app --force`; the second sync will succeed once CRDs are Established |
| Terraform vs ArgoCD self-managed conflict | MEDIUM | Add `lifecycle { ignore_changes = all }` to Terraform, `terraform apply`; ArgoCD re-sync self-managed app |
| Bridge secret annotations stale | MEDIUM | `terraform apply` to update secret; `argocd app sync root-app --force` to regenerate ApplicationSet Applications |
| Terraform k8s destroy hangs | MEDIUM | `kubectl delete externalsecret --all -A`; `kubectl patch namespace argocd -p '{"metadata":{"finalizers":[]}}' --type=merge` if namespace stuck; then retry destroy |
| OKE cluster is BASIC tier (Workload Identity broken) | HIGH | Recreate cluster as Enhanced (destructive); recreate node pool; re-bootstrap ArgoCD entirely |
| GitHub SSO broken, initial admin secret gone | MEDIUM | kubectl exec argocd-server; run `argocd admin password reset` or patch argocd-secret directly to reset admin password |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| OCI Workload Identity uses wrong IAM mechanism | Phase: Terraform IAM refactor (before ESO addon) | `oci iam policy list` shows `any-user` policy with `request.principal.type = 'workload'`; no dynamic group for ESO |
| ArgoCD Ingress circular dependency | Phase: gitops-setup repo structure design | Sync wave annotations present on ingress-nginx and ArgoCD Ingress manifests before first commit |
| ESO CRD race condition | Phase: gitops-setup repo structure design | ClusterSecretStore manifest has `argocd.argoproj.io/sync-wave: "10"` or higher; verified by first sync succeeding |
| Terraform helm_release conflict | Phase: Terraform k8s layer teardown | `lifecycle { ignore_changes = all }` added; confirmed by `terraform plan` showing no changes after ArgoCD self-manages |
| Bridge secret annotation drift | Phase: Bootstrap design + operational runbook | Runbook documents: any Terraform infra change → verify bridge secret → trigger ApplicationSet reconcile |
| OCI LB annotation mismatch | Phase: ingress-nginx addon authoring | OCI console shows LB in public subnet with flexible shape after first ingress-nginx sync |
| App-of-Apps sync ordering | Phase: gitops-setup repo structure design | First full bootstrap completes without manual intervention; no SyncFailed state |
| BASIC OKE tier incompatibility | Phase: Pre-bootstrap verification checklist | `oci ce cluster get` shows `clusterType: ENHANCED` before any Workload Identity config |
| GitHub OAuth without TLS | Phase: cert-manager addon (must precede SSO phase) | Certificate `Ready: True`; browser shows valid cert before SSO config is enabled |
| Terraform k8s destroy ordering | Phase: Migration from Terraform k8s to GitOps | Runbook executed; `terraform destroy` completes cleanly; no hanging namespaces |
| ESO v1beta1 API deprecation | Phase: ESO addon authoring in gitops-setup | All manifests use `external-secrets.io/v1` from the first commit |
| Initial admin secret lost | Phase: Bootstrap phase checklist | Password retrieved and stored in OCI Vault before SSO is enabled |

---

## Sources

- OCI OKE Workload Identity documentation: https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contenggrantingworkloadaccesstoresources.htm — Confirms: Enhanced cluster only, `any-user` policy with `request.principal.type = 'workload'`, dynamic groups NOT supported
- ESO Oracle Vault provider docs: https://external-secrets.io/latest/provider/oracle-vault/ — Confirms: `principalType: Workload`, namespace required in ClusterSecretStore serviceAccountRef
- ArgoCD Sync Waves documentation: https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/ — Official wave ordering behavior and CRD health gate
- ArgoCD CRD ordering issue: https://github.com/argoproj/argo-cd/discussions/11883 — Community confirmed CRD/CR ordering with sync waves
- ApplicationSet cluster generator: https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/ — Confirms annotations/labels read from cluster secret metadata (not data)
- ArgoCD ApplicationSet cluster generator bug (metadata not accessed): https://github.com/argoproj/argo-cd/issues/21293 — Known limitation with nested generators
- ArgoCD Progressive Syncs (Beta): https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/Progressive-Syncs/ — Cross-Application ordering mechanism
- ArgoCD self-managed Terraform module: https://registry.terraform.io/modules/lablabs/argocd/helm/latest — Confirms `lifecycle { ignore_changes }` pattern for self-managed ArgoCD
- OCI cloud-controller-manager LB annotations: https://github.com/oracle/oci-cloud-controller-manager/blob/master/docs/load-balancer-annotations.md — Correct annotation keys for OCI LB shape/subnet
- ArgoCD ingress stuck Progressing issue: https://github.com/argoproj/argo-cd/issues/14607 — Confirmed: empty loadBalancer.ingress causes Progressing health status
- ESO CRD cluster-wide toggle issue: https://github.com/external-secrets/external-secrets/issues/5744 — CRD readiness race condition confirmed
- ArgoCD Dex redirect URI issues: https://github.com/argoproj/argo-cd/issues/3761 — HTTPS requirement for GitHub OAuth callback
- OCI Workload Identity blog: https://blogs.oracle.com/cloud-infrastructure/oke-workload-identity-greater-control-access — OKE-specific workload identity setup
- Existing codebase CONCERNS.md — Known issues: broad IAM dynamic group, v1beta1 ESO API, ArgoCD namespace owned by ESO module, bastion single CIDR

---
*Pitfalls research for: GitOps Bridge Pattern on OCI/OKE (AssessForge infra-setup)*
*Researched: 2026-04-09*
