# Feature Research

**Domain:** GitOps Bridge Pattern on OCI/OKE — Infrastructure addons managed via ArgoCD
**Researched:** 2026-04-09
**Confidence:** MEDIUM (GitOps Bridge pattern is well-documented for AWS/EKS; OCI/OKE specifics rely on ESO OCI provider docs + existing project context)

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that are foundational to the GitOps Bridge Pattern. Missing any one of these means the pattern doesn't work — the bridge is broken.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Terraform bootstrap ArgoCD via `helm_release` | ArgoCD must exist before it can manage anything; Terraform is the one-time entry point | LOW | Minimal install — no SSO, no repo config, just the engine running |
| GitOps Bridge Secret with infra annotations | The secret is the literal bridge — ApplicationSet reads labels/annotations to populate Helm values for addons; without it the pattern is just manual ArgoCD | MEDIUM | Labels carry `enable_<addon>: "true"` feature flags; annotations carry infra OCIDs (compartment, subnet, vault), environment, region; 256 KB annotation limit applies |
| Root bootstrap Application (Terraform-created) | Points ArgoCD at the gitops-setup repo; this is the one-time handoff from Terraform to GitOps | LOW | Single `Application` resource pointing to `bootstrap/` path; must be idempotent |
| ApplicationSet with cluster generator | Reads bridge secret labels/annotations to dynamically generate per-addon `Application` resources; this is the mechanism that makes addons data-driven | HIGH | Uses `matchLabels` selector to scope to in-cluster secret; templates `{{metadata.annotations.compartment_ocid}}` etc. into Helm values |
| ArgoCD self-managed Application | If ArgoCD config is Terraform-managed it will drift; the self-managed app ensures upgrades and config changes are PRs | MEDIUM | ArgoCD Application targeting the ArgoCD Helm chart in the gitops repo; must handle the chicken-and-egg bootstrap carefully — ArgoCD must exist before it can manage itself |
| External Secrets Operator (ESO) addon | Required to pull ArgoCD sensitive config (GitHub OAuth, repo creds) from OCI Vault before ArgoCD Dex can start; without it all auth is broken | MEDIUM | Must deploy and become ready before ArgoCD self-managed config applies ExternalSecret resources |
| ClusterSecretStore → OCI Vault via Workload Identity | The credential-free secret pipeline; `principalType: Workload` + OCI Dynamic Group + IAM policy; eliminates static API keys | MEDIUM | `serviceAccountRef.namespace` is required when using ClusterSecretStore (vs namespaced SecretStore); compartment OCID needed for list operations |
| ExternalSecret manifests for ArgoCD config | Pulls GitHub OAuth client ID/secret into `argocd-dex-github-secret`; also repo credentials and notification tokens | LOW | Standard ESO pattern; refresh interval should be short during bootstrap (e.g., 1m), then relax to 1h |
| ingress-nginx addon with OCI LB annotations | Required for external access to ArgoCD; without ingress ArgoCD is only reachable inside the cluster | MEDIUM | OCI-specific: `service.beta.kubernetes.io/oci-load-balancer-shape: flexible`, min/max bandwidth annotations; ARM nodes work fine with nginx |
| ArgoCD GitHub SSO via Dex | The project's access model is GitHub org membership; without SSO every team member needs a local account | MEDIUM | Dex bundled with ArgoCD; `orgs` config restricts login to AssessForge org; org and team names are case-sensitive and must match GitHub exactly |
| ArgoCD RBAC (org members = admin, default deny) | Access control; without this anyone who logs in via GitHub gets read-only or no role | LOW | `policy.default: role:none`; `g, AssessForge:*, role:admin` (or org-level mapping); configure in `argocd-rbac-cm` via Helm values |
| Pinned Helm chart versions for all addons | Reproducibility and auditability; unpinned charts cause silent drift between environments and make rollback impossible | LOW | No `latest` or open ranges; each addon Application specifies exact `targetRevision` |
| `prevent_destroy = true` on critical Terraform resources | Protects against accidental cluster deletion during future infra changes | LOW | OKE cluster, VCN, state bucket; already partially in place |

### Differentiators (Competitive Advantage)

Features that elevate this from "ArgoCD with some addons" to operational excellence for the AssessForge platform.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| cert-manager addon with Let's Encrypt ClusterIssuer | Automated TLS for ArgoCD (and future workloads) via ACME; eliminates manual certificate rotation | MEDIUM | Requires ingress-nginx to be ready first (sync wave dependency); Cloudflare DNS-01 challenge is the safer choice for OCI since the LB IP may not be immediately reachable for HTTP-01; alternatively HTTP-01 works once LB is stable |
| metrics-server addon | Enables `kubectl top`, HPA, and VPA; without it resource autoscaling is blind | LOW | Lightweight; no cloud-specific config needed; ARM64 images available |
| Addon feature flags as bridge secret labels | Allows toggling addons on/off per cluster via label changes in Terraform (no gitops repo changes); cleanly supports future multi-cluster by reusing the same ApplicationSet templates | MEDIUM | Pattern: `enable_cert_manager: "true"` label on the bridge secret; ApplicationSet `matchExpressions` filters; addon deploys only when flag is present and `"true"` |
| OCI Workload Identity for all pod-level OCI API access | Zero credential rotation burden; ESO authenticates without any static key in the cluster; the OCI Dynamic Group policy is the sole trust anchor | MEDIUM | Requires OCI IAM Dynamic Group scoped to OKE cluster OCID + IAM policy granting Vault secret read; this must be Terraform-provisioned before bootstrap |
| Separation of `terraform/infra/` (cloud) and `gitops-setup/` (in-cluster) | Clean boundary — Terraform never runs `kubectl` or `helm` post-bootstrap; every in-cluster change is a PR; avoids the dual-state hell of Terraform managing Kubernetes resources | LOW | Pattern decision, not a code feature; enforced by destroying `terraform/k8s/` layer |
| ArgoCD repo credentials template (SSH or HTTPS) | Required if gitops-setup repo is private; stored as ExternalSecret in OCI Vault; avoids hardcoding deploy keys in Helm values | LOW | Use ArgoCD's `repositories` or `repository-credentials` configmap pattern; secret pulled via ESO |
| Sync wave ordering for addon bootstrap sequence | Ensures ESO is ready before ExternalSecrets are created, ingress-nginx exists before cert-manager issues certificates, ArgoCD self-manages after all dependencies settle | MEDIUM | Wave -2: ESO; Wave -1: ingress-nginx, cert-manager; Wave 0: ArgoCD self-managed; Wave 1: metrics-server and other stateless addons |

### Anti-Features (Commonly Requested, Often Problematic)

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Terraform managing in-cluster resources post-bootstrap | Familiar; operators already know Terraform; easy to add a `helm_release` for a new addon | Destroys the GitOps model — two sources of truth fight each other; `terraform apply` can overwrite changes made through ArgoCD; state drift becomes undetectable | After bootstrap, all in-cluster changes go through the gitops-setup repo via PRs; Terraform is cloud resources only |
| Static API keys / OCI user credentials in Kubernetes Secrets | Simpler to set up than workload identity; no IAM policy configuration required | Keys expire, rotate awkwardly, and leak; storing them in K8s Secrets (even base64) means they're readable by anyone with Secret access; violates the project's zero-static-credential constraint | OCI Workload Identity with Dynamic Group + IAM policy; ESO authenticates to Vault without any key |
| ArgoCD `admin` local account enabled | Useful for break-glass; easy to test with | Admin account bypasses SSO; if password leaks anyone gets cluster-admin; hard to audit who used it | Keep `admin.enabled=false`; use GitHub SSO for all access; document a break-glass procedure using `kubectl` directly via Bastion if ArgoCD is unavailable |
| ArgoCD `exec` enabled (terminal in UI) | Convenient for debugging pods directly from the ArgoCD UI | Opens a persistent shell into running containers; bypasses Kubernetes RBAC audit trail; significant attack surface | Use `kubectl exec` via Bastion tunnel with audit logging; ArgoCD exec disabled by default in this project |
| Using ArgoCD `parameters` override or `helm.set` in Application CRDs | Tempting for quick env-specific tweaks without a PR | Goes against GitOps — overrides live in ArgoCD's internal state, not in Git; next sync may or may not preserve them; makes the actual running config invisible to reviewers | Use Helm `valueFiles` in Git; bridge secret annotations for cluster-specific values; no in-UI parameter overrides |
| App-of-apps with deeply nested parent chains | Natural to organize: a root app managing a cluster-apps app managing addon apps | Each extra nesting layer adds sync latency and debugging complexity; a failure in the middle silently stops children from syncing | Maximum two levels: root bootstrap Application (Terraform-created) → addon ApplicationSet (gitops-managed); avoid app→app→app→app chains |
| Kustomize overlays for secret values | Allows injecting secret values via Kustomize `secretGenerator` | Secrets end up in Git (even if encrypted, the approach leaks structure); Kustomize secrets require additional tooling (SOPS, Sealed Secrets) that adds operational complexity | ESO + OCI Vault is the canonical approach for this project; secrets never touch Git |
| Argo CD notifications via hardcoded Slack/webhook tokens | Quick to set up | Tokens in Helm values or configmaps means they're in Git or in cluster plaintext | Store notification tokens in OCI Vault; pull via ExternalSecret into `argocd-notifications-secret` |
| Multi-cluster support in this milestone | Future-proofing; the bridge pattern supports it natively | Premature abstraction — designing ApplicationSets for multi-cluster when there's one cluster adds labeling complexity, testing burden, and cognitive overhead with no current benefit | Design ApplicationSets to be cluster-agnostic (use bridge secret annotations for cloud-specific values); multi-cluster support emerges naturally in a future milestone without rework |
| Monitoring/observability stack (Prometheus, Grafana) | Makes sense to add while doing addons | Prometheus + Grafana is a significant surface area (PVCs, retention, alerting, dashboards); out of scope risks the milestone never completing | Dedicate a future milestone to observability; metrics-server satisfies basic HPA needs in the interim |

---

## Feature Dependencies

```
[OCI Workload Identity (Dynamic Group + IAM Policy)]
    └──required-by──> [ESO ClusterSecretStore → OCI Vault]
                          └──required-by──> [ExternalSecret: argocd-dex-github-secret]
                                                └──required-by──> [ArgoCD Dex / GitHub SSO]
                                                └──required-by──> [ArgoCD repo credentials]
                                                └──required-by──> [ArgoCD notification tokens]

[Terraform: helm_release ArgoCD (minimal)]
    └──creates──> [Bootstrap Application → gitops-setup repo]
    └──creates──> [Bridge Secret with labels + annotations]
                      └──read-by──> [ApplicationSet cluster generator]
                                        └──generates──> [Application: ESO]
                                        └──generates──> [Application: ingress-nginx]
                                        └──generates──> [Application: cert-manager]
                                        └──generates──> [Application: metrics-server]
                                        └──generates──> [Application: ArgoCD self-managed]

[Application: ESO] (sync wave -2)
    └──enables──> [ExternalSecret: argocd-dex-github-secret]
    └──enables──> [ExternalSecret: argocd-repo-creds]

[Application: ingress-nginx] (sync wave -1)
    └──required-by──> [ArgoCD Ingress resource]
    └──required-by──> [cert-manager HTTP-01 solver] (if using HTTP-01)

[Application: cert-manager] (sync wave -1)
    └──required-by──> [ArgoCD TLS certificate (Certificate resource)]
    └──required-by──> [Future workload TLS]

[Application: ArgoCD self-managed] (sync wave 0)
    └──depends-on──> [ExternalSecret: argocd-dex-github-secret] (must be synced)
    └──depends-on──> [ingress-nginx] (must be ready for Ingress)
    └──replaces──> [Terraform-bootstrapped ArgoCD config]

[Application: metrics-server] (sync wave 1)
    └──no hard dependencies on other addons]
```

### Dependency Notes

- **ESO must precede ArgoCD self-managed**: ArgoCD's Dex config references `argocd-dex-github-secret`; if this secret doesn't exist when ArgoCD applies its self-managed Helm values, Dex crashes. ESO must be running and the ExternalSecret must have synced before the self-managed Application reconciles.

- **ingress-nginx precedes cert-manager (for HTTP-01)**: cert-manager's HTTP-01 ACME solver routes challenge traffic through the ingress controller. If ingress-nginx isn't running, certificate issuance fails silently (ACME challenge times out). Using DNS-01 (Cloudflare) removes this ordering dependency.

- **Bridge Secret is the single source of truth for cloud metadata**: The ApplicationSet cluster generator reads `metadata.annotations` and `metadata.labels` from the bridge secret to template Helm values. Any OCI-specific value (compartment OCID, vault OCID, subnet IDs, region) must be in the secret, not hardcoded in the gitops-setup repo. This keeps the gitops repo cloud-agnostic.

- **OCI Dynamic Group + IAM Policy must exist before ESO pod starts**: ESO uses workload identity on startup; if the IAM policy doesn't grant the ESO service account access to Vault, every ExternalSecret will fail with a 401. This is a Terraform responsibility — it must be applied before `helm_release` for ArgoCD.

- **ArgoCD self-managed creates a chicken-and-egg risk**: ArgoCD must exist to apply its own self-managed Application, but the self-managed Application changes the config of the running ArgoCD. The bootstrap sequence must handle the first reconcile carefully — Terraform installs a minimal ArgoCD, then the self-managed Application is applied, and ArgoCD reconciles itself to the gitops-desired state. If the self-managed Application is misconfigured it can take down the ArgoCD it's running in.

---

## MVP Definition

### Launch With (Phase 1 of this milestone)

Minimum viable bootstrap — the bridge is established, ArgoCD is self-managing, secrets flow from OCI Vault.

- [ ] Terraform: OCI Dynamic Group + IAM Policy for ESO workload identity
- [ ] Terraform: `helm_release` for ArgoCD (minimal, no SSO)
- [ ] Terraform: Bridge Secret with OCI metadata labels/annotations
- [ ] Terraform: Root bootstrap Application pointing to gitops-setup
- [ ] GitOps: ESO addon Application + ClusterSecretStore → OCI Vault
- [ ] GitOps: ExternalSecret for `argocd-dex-github-secret`
- [ ] GitOps: ArgoCD self-managed Application (Helm values: GitHub SSO, RBAC, hardened security contexts)
- [ ] GitOps: ApplicationSet with cluster generator driving all addon Applications

### Add After Bootstrap Validates (Phase 2)

Once the bridge is proven and ArgoCD is managing itself:

- [ ] ingress-nginx addon with OCI LB annotations — external access to ArgoCD
- [ ] cert-manager addon + ClusterIssuer — automated TLS for ArgoCD and future workloads
- [ ] ArgoCD Ingress resource (once ingress-nginx exists)
- [ ] metrics-server addon

### Future Consideration (Future Milestones)

Defer — out of scope for this bridge milestone:

- [ ] Kyverno policies via GitOps — dedicated future milestone
- [ ] NetworkPolicies for application namespaces — future milestone
- [ ] Prometheus + Grafana observability stack — future milestone
- [ ] Multi-cluster / multi-environment ApplicationSet expansion — future milestone
- [ ] CI/CD pipeline for gitops-setup repo (currently manual PR workflow) — future milestone

---

## Feature Prioritization Matrix

| Feature | Operational Value | Implementation Cost | Priority |
|---------|-------------------|---------------------|----------|
| Bridge Secret + ApplicationSet cluster generator | HIGH — pattern foundation | MEDIUM | P1 |
| ESO + OCI Vault workload identity | HIGH — no secrets in cluster | MEDIUM | P1 |
| ArgoCD self-managed Application | HIGH — eliminates config drift | MEDIUM | P1 |
| Root bootstrap Application | HIGH — Terraform→GitOps handoff | LOW | P1 |
| GitHub SSO via Dex + RBAC | HIGH — access control | MEDIUM | P1 |
| ingress-nginx with OCI LB | HIGH — external access | MEDIUM | P1 |
| cert-manager + Let's Encrypt | HIGH — automated TLS | MEDIUM | P2 |
| metrics-server | MEDIUM — HPA prerequisite | LOW | P2 |
| Sync wave ordering | MEDIUM — bootstrap reliability | MEDIUM | P2 |
| Addon feature flags via bridge labels | MEDIUM — future multi-cluster | LOW | P2 |
| Notification tokens via ESO | LOW — operational convenience | LOW | P3 |
| Kyverno policies via GitOps | MEDIUM — security posture | HIGH | P3 (future milestone) |

**Priority key:**
- P1: Must have for bridge pattern to function
- P2: Should have — operational excellence for single-cluster
- P3: Nice to have or future milestone scope

---

## Ecosystem Reference (What the GitOps Bridge Pattern Standardizes)

The [gitops-bridge-dev](https://github.com/gitops-bridge-dev/gitops-bridge) community project defines these conventions. This project follows the same conventions, adapted for OCI instead of AWS:

| Convention | AWS/EKS Standard | AssessForge/OKE Equivalent |
|------------|-----------------|---------------------------|
| Bridge secret location | `argocd` namespace, cluster secret type | Same — ArgoCD cluster secret in `argocd` namespace |
| Feature flag labels | `enable_aws_load_balancer_controller: "true"` | `enable_ingress_nginx: "true"`, `enable_cert_manager: "true"` etc. |
| Cloud metadata annotations | `aws_account_id`, `aws_region`, `aws_vpc_id` | `oci_compartment_ocid`, `oci_region`, `oci_vault_ocid`, `oci_subnet_id` |
| Addon repo path annotation | `addons_repo_basepath: "argocd/"` | Same convention |
| Workload identity annotation | `aws_load_balancer_controller_iam_role_arn` | Not applicable — OCI uses Dynamic Groups, no per-SA role ARN |
| ApplicationSet generator | Cluster generator with `matchLabels` | Same — ArgoCD ApplicationSet cluster generator |

---

## Sources

- [GitOps Bridge community project — gitops-bridge-dev/gitops-bridge](https://github.com/gitops-bridge-dev/gitops-bridge)
- [GitOps Bridge Terraform module — gitops-bridge-dev/gitops-bridge-argocd-bootstrap-terraform](https://github.com/gitops-bridge-dev/gitops-bridge-argocd-bootstrap-terraform)
- [AWS EKS Blueprints: GitOps Getting Started with ArgoCD](https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/gitops/gitops-getting-started-argocd/)
- [ArgoCD Cluster Bootstrapping — official docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ArgoCD ApplicationSet Cluster Generator — official docs](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Cluster/)
- [External Secrets Operator — Oracle Vault provider](https://external-secrets.io/latest/provider/oracle-vault/)
- [ESO with OCI Vault on OKE — Oracle Developers Medium](https://medium.com/oracledevs/using-the-external-secrets-operator-with-oci-kubernetes-and-oci-vault-6865f2e1fe35)
- [ArgoCD Anti-Patterns — Codefresh](https://codefresh.io/blog/argo-cd-anti-patterns-for-gitops/)
- [Deploy infra stack: self-managed ArgoCD with cert-manager, ESO, ingress-nginx — Medium](https://medium.com/@jojoooo/deploy-infra-stack-using-self-managed-argocd-with-cert-manager-externaldns-external-secrets-op-640fe8c1587b)
- [ArgoCD Sync Phases and Waves — official docs](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [cert-manager: Continuous Deployment and GitOps](https://cert-manager.io/docs/installation/continuous-deployment-and-gitops/)
- [GitOps Bridge Pattern on a Local Kind Cluster — DEV Community](https://dev.to/markbosire/gitops-bridge-pattern-on-a-local-kind-cluster-3h5j)

---
*Feature research for: GitOps Bridge Pattern on OCI/OKE*
*Researched: 2026-04-09*
