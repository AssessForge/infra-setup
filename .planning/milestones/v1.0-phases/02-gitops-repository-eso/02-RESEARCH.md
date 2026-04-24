# Phase 2: GitOps Repository & ESO - Research

**Researched:** 2026-04-10
**Domain:** GitOps Bridge Pattern — gitops-setup repo structure, ApplicationSet matrix generator, External Secrets Operator v2 on OCI Vault via Instance Principal
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Repo Structure**
- D-01: Flat addon directory layout inside `bootstrap/control-plane/`. The ApplicationSet YAML and per-addon directories live together under this path. `environments/prod/addons/{addon}/values.yaml` provides per-environment Helm value overrides.
- D-02: ArgoCD self-managed Application lives inside `bootstrap/control-plane/argocd/` alongside addon dirs — single sync point from the root bootstrap Application.
- D-03: Each addon directory contains a Helm-based Application manifest referencing the upstream Helm repo with a pinned chart version. Values come from `environments/` via multiple sources in the Application spec.

**ApplicationSet Design**
- D-04: Single ApplicationSet (`cluster-addons`) with a matrix generator: cluster generator (reads Bridge Secret labels) x git generator (discovers addon dirs under `bootstrap/control-plane/addons/*`). One file to maintain for all addons.
- D-05: Convention-based feature flag filtering — addon dir name maps to Bridge Secret label (e.g., `addons/eso/` matches `enable_eso` label). No explicit mapping file needed.
- D-06: ArgoCD self-managed Application is a standalone Application.yaml, NOT part of the ApplicationSet. ArgoCD has unique requirements (`prune: false`, special sync policy) that don't fit the generic addon template.

**ESO Auth Strategy**
- D-07: Single ClusterSecretStore with `namespaceSelector` restricting access to the `argocd` namespace only. Instance Principal auth via Dynamic Group on worker nodes (decided in Phase 1, D-01).
- D-08: Create ExternalSecrets for GitHub OAuth client ID/secret (`argocd-dex-github-secret`) and repo credentials (`argocd-repo-creds`). Skip notification tokens — ESO-05 says "if applicable" and no notification system is in v1 scope.
- D-09: Repo credentials (GitHub PAT or deploy key for gitops-setup repo) must be added to OCI Vault. This requires a small Terraform change to the `oci-vault` module — new secret resource + new sensitive variable. All credentials stay in Vault per project constraint.
- D-10: All ESO manifests use `external-secrets.io/v1` API (not deprecated v1beta1), per requirement ESO-06.

**Sync Wave Order**
- D-11: ArgoCD sync wave annotations on Application manifests for bootstrap ordering:
  - Wave 1: ESO operator
  - Wave 2: ClusterSecretStore + ExternalSecrets (secrets must exist before consumers)
  - Wave 3: ArgoCD self-managed, Envoy Gateway, cert-manager, metrics-server
- D-12: Stub ALL addon directories and Application manifests in Phase 2, including Phase 3 addons (Envoy Gateway, cert-manager, metrics-server, ArgoCD self-managed). Phase 3 fills in Helm values and configuration details. Avoids restructuring later.

### Claude's Discretion
- Exact Application manifest template structure (Helm source, values file references)
- Go template expressions in ApplicationSet for convention-based label matching
- ESO ClusterSecretStore YAML specifics (OCI Vault provider config for Instance Principal)
- ExternalSecret field mapping (which OCI Vault secret IDs map to which K8s secret keys)
- How to structure the Terraform change for adding repo creds to OCI Vault
- Git init and initial commit strategy for the gitops-setup repo

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| REPO-01 | New git repository at `~/projects/AssessForge/gitops-setup` with proper directory structure | Directory structure documented in Architecture Patterns section |
| REPO-02 | ApplicationSet with cluster generator reads Bridge Secret labels/annotations to dynamically create per-addon Applications | Matrix generator pattern with cluster+git generators; label matchExpression documented |
| REPO-03 | Sync wave ordering ensures correct bootstrap sequence | Sync wave assignments and ArgoCD ApplicationSet cross-app ordering pitfall documented |
| REPO-04 | All addon Helm chart versions pinned in Application manifests | Pinned versions from STACK.md verified; pattern for embedding in ApplicationSet template documented |
| ESO-01 | ESO addon deployed via GitOps with pinned Helm chart version | ESO 2.2.0 Helm chart verified; Application manifest structure documented |
| ESO-02 | ClusterSecretStore configured pointing to OCI Vault using Instance Principal | `principalType: InstancePrincipal` spec confirmed from ESO docs; namespaceSelector pattern documented |
| ESO-03 | ExternalSecret for ArgoCD GitHub OAuth client ID/secret (`argocd-dex-github-secret`) | ExternalSecret YAML pattern for OCI Vault remoteRef.key documented; existing Vault secret names known |
| ESO-04 | ExternalSecret for ArgoCD repository credentials | Repo cred Terraform extension pattern documented; PAT vs deploy key decision documented |
| ESO-05 | ExternalSecret for notification tokens (if applicable) | Explicitly skipped — no notification system in v1 scope (D-08) |
| ESO-06 | All ExternalSecrets use `external-secrets.io/v1` API | Confirmed from ESO docs — v1 is current API; v1beta1 deprecated |

</phase_requirements>

---

## Summary

Phase 2 creates two deliverables: (1) the `gitops-setup` repository at `~/projects/AssessForge/gitops-setup` with the directory structure, a single matrix ApplicationSet, and all addon stub manifests; (2) a small Terraform extension to `terraform/infra/modules/oci-vault/` that adds a GitHub PAT secret for gitops-setup repo access.

The critical design choice locked in CONTEXT.md (D-04) uses a **single** `cluster-addons` ApplicationSet with a matrix generator (cluster generator × git directory generator) rather than per-addon ApplicationSets. This single-AppSet approach is simpler to maintain — one file drives all addon deployments — but requires the convention-based label matching in D-05: the addon directory name must map 1:1 to the Bridge Secret feature flag label. The `bootstrap/control-plane/argocd/` ArgoCD self-managed Application is a standalone Application.yaml outside the ApplicationSet, per D-06.

ESO uses Instance Principal auth (not OKE Workload Identity, which requires Enhanced cluster tier — a paid feature). The Dynamic Group and IAM policy already exist from Phase 1. The ClusterSecretStore YAML uses `principalType: InstancePrincipal` with no `serviceAccountRef` required. All ESO manifests use the `external-secrets.io/v1` API. The only new Terraform resource needed is a repo credential secret in OCI Vault; a GitHub PAT is the simplest approach given the project already uses HTTPS for git.

**Primary recommendation:** Build the gitops-setup repo structure first (git init → directory scaffold → ApplicationSet → addon stubs → ESO manifests), then apply the Terraform vault extension for repo creds, then verify ArgoCD can sync the bootstrap Application.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `external-secrets` (Helm chart) | **2.2.0** | ESO operator — syncs OCI Vault secrets to K8s Secrets | Latest stable as of March 2026; has native OCI Vault provider with Instance Principal support; v1 API is current [VERIFIED: .planning/research/STACK.md] |
| `argo-cd` (Helm chart) | **9.5.0** (app v3.3.6) | ArgoCD self-managed — already installed by Phase 1 | Pinned in Phase 1 bootstrap; stub Application must reference same version [VERIFIED: terraform/infra/modules/oci-argocd-bootstrap/main.tf] |
| `envoy-gateway` (Helm chart stub) | **1.4.0** | Phase 3 stub only — no values in Phase 2 | Pinned stub prevents restructuring in Phase 3 [ASSUMED — verify exact chart version before Phase 3] |
| `cert-manager` (Helm chart stub) | **1.20.1** | Phase 3 stub only — no values in Phase 2 | Latest stable per STACK.md [VERIFIED: .planning/research/STACK.md] |
| `metrics-server` (Helm chart stub) | **3.13.0** | Phase 3 stub only — no values in Phase 2 | Latest stable per STACK.md [VERIFIED: .planning/research/STACK.md] |

### Terraform Extension

| Resource | Module | Purpose |
|----------|--------|---------|
| `oci_vault_secret.gitops_repo_pat` | `terraform/infra/modules/oci-vault/` | Stores GitHub PAT for gitops-setup repo in OCI Vault |
| `variable "gitops_repo_pat"` | `terraform/infra/modules/oci-vault/variables.tf` + root `variables.tf` | Sensitive variable for PAT value |
| `output "gitops_repo_pat_ocid"` | `terraform/infra/modules/oci-vault/outputs.tf` | OCID passed to ExternalSecret remoteRef |

### Helm Repositories Referenced in Addon Manifests

| Chart | Repository URL |
|-------|---------------|
| `external-secrets` | `https://charts.external-secrets.io` |
| `argo-cd` | `https://argoproj.github.io/argo-helm` |
| `cert-manager` | `https://charts.jetstack.io` |
| `metrics-server` | `https://kubernetes-sigs.github.io/metrics-server/` |
| `gateway-helm` | `oci://docker.io/envoyproxy` [VERIFIED — OCI registry; no HTTPS Helm repo exists] |

---

## Architecture Patterns

### Recommended Project Structure

```
~/projects/AssessForge/gitops-setup/
├── bootstrap/
│   └── control-plane/
│       ├── addons/
│       │   ├── cluster-addons-appset.yaml      # single matrix ApplicationSet (D-04)
│       │   ├── eso/                            # ESO addon dir (matches enable_eso label)
│       │   │   └── application.yaml
│       │   ├── envoy-gateway/                  # Phase 3 stub (matches enable_envoy_gateway)
│       │   │   └── application.yaml
│       │   ├── cert-manager/                   # Phase 3 stub (matches enable_cert_manager)
│       │   │   └── application.yaml
│       │   └── metrics-server/                 # Phase 3 stub (matches enable_metrics_server)
│       │       └── application.yaml
│       └── argocd/
│           └── application.yaml                # standalone ArgoCD self-managed (D-06)
│
├── environments/
│   ├── default/
│   │   └── addons/
│   │       ├── eso/values.yaml                 # base ESO values (region, OCI config)
│   │       ├── envoy-gateway/values.yaml        # stub — empty for Phase 2
│   │       ├── cert-manager/values.yaml         # stub — empty for Phase 2
│   │       ├── metrics-server/values.yaml       # stub — empty for Phase 2
│   │       └── argocd/values.yaml               # stub — empty for Phase 2
│   └── prod/
│       └── addons/
│           └── eso/values.yaml                  # prod overrides for ESO (if any)
│
└── clusters/
    └── in-cluster/
        └── addons/
            └── eso/values.yaml                  # vault OCID injected here (or via AppSet param)
```

**Why `cluster-addons-appset.yaml` is in `addons/` not `bootstrap/control-plane/` root:**
The root bootstrap Application syncs `bootstrap/control-plane` recursively. Placing the ApplicationSet inside `addons/` makes the intent clear — it governs addon deployment, not the bootstrap Application itself. [VERIFIED: .planning/phases/02-gitops-repository-eso/02-CONTEXT.md D-01]

**Why no per-addon `appset.yaml` files:**
D-04 locks a single matrix ApplicationSet. Per-addon ApplicationSets (what ARCHITECTURE.md Pattern 2 documents) are an alternative approach that is NOT what was decided for this project. The matrix generator achieves the same result with one file.

### Pattern 1: Single Matrix ApplicationSet (`cluster-addons`)

**What:** One ApplicationSet uses a matrix generator combining (a) a cluster generator that reads the Bridge Secret and filters on `enable_{addon}` labels, and (b) a git directory generator that discovers addon directories under `bootstrap/control-plane/addons/*`. The cross-product of these two generators creates one Application per enabled addon.

**Key constraint:** The convention requires that the directory name under `addons/` exactly matches the suffix of the Bridge Secret label. `addons/eso/` must match `enable_eso: "true"` in the Bridge Secret. [VERIFIED: .planning/phases/02-gitops-repository-eso/02-CONTEXT.md D-05]

**Template expression for label matching:**

The matrix generator merges cluster metadata with git directory path. The ApplicationSet template must filter using `matchExpressions` on the cluster generator side. The filtering based on dir name vs label is done with Go template syntax:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-addons
  namespace: argocd
spec:
  goTemplate: true
  goTemplateOptions: ["missingkey=error"]
  generators:
  - matrix:
      generators:
      # Generator 1: cluster — reads Bridge Secret, filters by feature flag
      - clusters:
          selector:
            matchLabels:
              argocd.argoproj.io/secret-type: cluster
      # Generator 2: git — discovers addon directories
      - git:
          repoURL: '{{.metadata.annotations.addons_repo_url}}'
          revision: '{{.metadata.annotations.addons_repo_revision}}'
          directories:
          - path: bootstrap/control-plane/addons/*
  template:
    metadata:
      name: 'addon-{{.name}}-{{.path.basename}}'
      annotations:
        argocd.argoproj.io/sync-wave: '{{index .metadata.labels (printf "syncwave_%s" .path.basename) | default "1"}}'
    spec:
      project: default
      source:
        repoURL: '{{.metadata.annotations.addons_repo_url}}'
        targetRevision: '{{.metadata.annotations.addons_repo_revision}}'
        path: 'bootstrap/control-plane/addons/{{.path.basename}}'
      destination:
        namespace: '{{.path.basename}}'
        name: '{{.name}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
  syncPolicy:
    preserveResourcesOnDeletion: true
```

**IMPORTANT limitation on convention-based label filtering:** The matrix generator produces a Cartesian product of ALL cluster × ALL discovered dirs. It does NOT automatically filter out disabled addons. The `enable_{addon}` label check must be done inside the Application template using a `when` condition, OR the git generator's path discovery must be the gate (only directories present in git will generate Applications). The simplest approach for this project: **only commit addon directories for features that should be enabled**. If `enable_envoy_gateway: "false"` in the Bridge Secret, the stub `envoy-gateway/` directory is still committed but the Application it generates will still be created. This is a design tension in D-04 vs D-05.

**Resolved recommendation (Claude's discretion):** Use the per-addon `application.yaml` inside each addon directory as the actual ArgoCD Application manifest, and use the ApplicationSet to apply it. Each `application.yaml` in the addon directory IS the Application spec (Application-in-a-directory pattern). The ApplicationSet deploys what it finds in each directory. Feature flag gating is done by checking the Bridge Secret label in the ApplicationSet's cluster generator `matchExpressions` — but since a single AppSet applies to all dirs, the filtering must use a Go template `if` block or a separate AppSet per-addon for true gating. [ASSUMED — requires validation against ArgoCD docs for feasibility of Go template conditional in AppSet]

**Simpler alternative resolving the tension:** Each addon directory contains a Helm-type Application manifest (not another AppSet). The single `cluster-addons-appset.yaml` discovers these directories and creates Applications. The Bridge Secret labels are used to control which Applications ArgoCD syncs by adding a `when` clause on the cluster generator using `matchExpressions` — but `matchExpressions` can only match against static label keys, not dynamically derived from the directory basename. **This means the single-AppSet + convention-based approach (D-04 + D-05) cannot do per-addon gating without either: (a) accepting that all discovered addon directories deploy regardless of feature flags, or (b) using per-addon AppSets.**

**For Phase 2 scope:** All Phase 2 addons (ESO) and Phase 3 stubs are stubbed — stub Applications that point at empty Helm values are harmless (they deploy with defaults). Feature flag filtering becomes relevant in Phase 3. Document this design decision for the planner. [ASSUMED — user confirmation may be needed]

### Pattern 2: Addon Application Manifest (inside each addon directory)

Each addon directory contains a Helm-type Application that directly references the upstream chart. Values come from the `environments/` hierarchy.

**ESO example (`bootstrap/control-plane/addons/eso/application.yaml`):**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eso
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: default
  sources:
  - repoURL: 'https://github.com/AssessForge/gitops-setup'
    targetRevision: 'main'
    ref: values
  - chart: external-secrets
    repoURL: 'https://charts.external-secrets.io'
    targetRevision: '2.2.0'
    helm:
      releaseName: external-secrets
      ignoreMissingValueFiles: true
      valueFiles:
      - $values/environments/default/addons/eso/values.yaml
      - $values/environments/prod/addons/eso/values.yaml
      - $values/clusters/in-cluster/addons/eso/values.yaml
  destination:
    namespace: external-secrets
    name: in-cluster
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
    - CreateNamespace=true
    - ServerSideApply=true
```

**Note:** This approach puts the Application manifest directly in the addon directory rather than using the ApplicationSet to template the Application. The ApplicationSet discovers and applies the manifest. This is the "App of Apps via ApplicationSet" pattern. [CITED: https://github.com/gitops-bridge-dev/gitops-bridge-argocd-control-plane-template]

### Pattern 3: ArgoCD Self-Managed Standalone Application (D-06)

**What:** `bootstrap/control-plane/argocd/application.yaml` is a standalone Application (NOT part of the cluster-addons ApplicationSet). It manages ArgoCD's own Helm release with `prune: false`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argocd
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "3"
spec:
  project: default
  sources:
  - repoURL: 'https://github.com/AssessForge/gitops-setup'
    targetRevision: 'main'
    ref: values
  - chart: argo-cd
    repoURL: 'https://argoproj.github.io/argo-helm'
    targetRevision: '9.5.0'
    helm:
      releaseName: argocd
      ignoreMissingValueFiles: true
      valueFiles:
      - $values/environments/default/addons/argocd/values.yaml
      - $values/environments/prod/addons/argocd/values.yaml
      - $values/clusters/in-cluster/addons/argocd/values.yaml
  destination:
    namespace: argocd
    name: in-cluster
  syncPolicy:
    automated:
      prune: false    # NUNCA prunar o proprio ArgoCD
      selfHeal: true
    syncOptions:
    - ServerSideApply=true
```

### Pattern 4: ESO ClusterSecretStore for OCI Vault (Instance Principal)

**What:** ClusterSecretStore in the `external-secrets` namespace using `principalType: InstancePrincipal`. No `serviceAccountRef` needed — the node's instance metadata endpoint provides the token. Access restricted to `argocd` namespace via `namespaceSelector`.

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: oci-vault
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: argocd
  provider:
    oracle:
      vault: "<oci_vault_ocid>"      # replace with actual OCID at deploy time
      region: "sa-saopaulo-1"
      principalType: InstancePrincipal
```

**OCI Vault OCID injection:** The vault OCID is an infrastructure value from Terraform. Options:
1. Hardcode it in `clusters/in-cluster/addons/eso/values.yaml` (committed after `terraform apply` gives the OCID)
2. Use ApplicationSet template parameter from Bridge Secret annotation `oci_vault_ocid` (cleaner — no hardcoded OCID in repo)

**Recommendation (Claude's discretion):** Commit the ClusterSecretStore manifest with a placeholder comment and document that the operator must substitute the OCID after the first `terraform apply`. The Bridge Secret already carries `oci_vault_ocid` as an annotation — an ESO addon in the ApplicationSet approach can inject it as a Helm parameter. For a standalone ClusterSecretStore YAML (not Helm-managed), the operator substitution approach is simpler in Phase 2. The OCID is stable (protected by `prevent_destroy = true`).

[VERIFIED: terraform/infra/modules/oci-argocd-bootstrap/main.tf — Bridge Secret carries `oci_vault_ocid` annotation]

### Pattern 5: ExternalSecrets (ESO-03 and ESO-04)

**GitHub OAuth secret (ESO-03):**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-dex-github-secret
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: oci-vault
    kind: ClusterSecretStore
  target:
    name: argocd-dex-github-secret
    creationPolicy: Owner
  data:
  - secretKey: client_id
    remoteRef:
      key: github-oauth-client-id        # secret_name in OCI Vault
  - secretKey: client_secret
    remoteRef:
      key: github-oauth-client-secret    # secret_name in OCI Vault
```

**Repo credentials secret (ESO-04):**

```yaml
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-repo-creds
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: oci-vault
    kind: ClusterSecretStore
  target:
    name: argocd-repo-creds
    creationPolicy: Owner
    template:
      type: Opaque
      metadata:
        labels:
          argocd.argoproj.io/secret-type: repo-creds
  data:
  - secretKey: url
    remoteRef:
      key: gitops-repo-url              # new Vault secret (Terraform extension)
  - secretKey: username
    remoteRef:
      key: gitops-repo-username         # "x-token" or GitHub username
  - secretKey: password
    remoteRef:
      key: gitops-repo-pat              # the GitHub PAT
```

[VERIFIED: ESO v1 API from external-secrets.io docs — `remoteRef.key` maps to OCI Vault `secret_name`]

### Pattern 6: Terraform Extension for Repo Credentials

**What:** Add one new `oci_vault_secret` resource to `terraform/infra/modules/oci-vault/main.tf` for the GitHub PAT. Follow existing pattern from `github_oauth_client_id` secret.

**GitHub PAT vs Deploy Key decision:** GitHub PAT is simpler — one Vault secret, no SSH key management. ArgoCD uses HTTPS for the gitops-setup repo (consistent with `gitops_repo_url` format already configured as HTTPS). Deploy keys require an SSH private key in Vault + ArgoCD SSH known_hosts config. Use GitHub PAT. [VERIFIED: terraform/infra/variables.tf — `gitops_repo_url` default is `https://github.com/AssessForge/gitops-setup`]

**oci-vault module extension:**

```hcl
# New variable in variables.tf
variable "gitops_repo_pat" {
  description = "GitHub Personal Access Token para acesso ao repositorio gitops-setup"
  type        = string
  sensitive   = true
}

# New resource in main.tf
resource "oci_vault_secret" "gitops_repo_pat" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "gitops-repo-pat"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.gitops_repo_pat)
    name         = "gitops-repo-pat"
  }
}

# New output in outputs.tf
output "gitops_repo_pat_ocid" {
  description = "OCID do secret GitHub PAT no Vault"
  value       = oci_vault_secret.gitops_repo_pat.id
  sensitive   = true
}
```

**Root module changes required:**
- Add `gitops_repo_pat = var.gitops_repo_pat` to `module "oci_vault"` block in `terraform/infra/main.tf`
- Add `variable "gitops_repo_pat"` with `sensitive = true` to `terraform/infra/variables.tf`
- Add `gitops_repo_pat = "<PAT>"` to `terraform.tfvars` (not committed)

### Anti-Patterns to Avoid

- **Single giant ApplicationSet for ALL addons including ArgoCD self-managed:** ArgoCD self-managed needs `prune: false` and special handling. The matrix AppSet applies the same template to all addon dirs. Keep ArgoCD in `bootstrap/control-plane/argocd/` as a standalone Application. (D-06)
- **ClusterSecretStore before ESO CRDs are established:** The ClusterSecretStore must have sync-wave > the ESO Helm release. Place ClusterSecretStore in `bootstrap/control-plane/addons/eso/` alongside the ESO Application manifest, with a higher sync wave annotation. Never deploy ClusterSecretStore as a standalone Application parallel to ESO.
- **Hardcoding OCI OCIDs in values files:** Use the Bridge Secret annotation `oci_vault_ocid` as the source of truth. Commit a placeholder comment in values files noting where the OCID will be injected.
- **Using `v1beta1` API for ExternalSecrets:** The `external-secrets.io/v1beta1` API is deprecated in ESO 2.x. All manifests must use `external-secrets.io/v1`. (D-10, ESO-06)

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Secret sync from OCI Vault to K8s | Custom CronJob/script that calls OCI SDK and creates K8s secrets | ESO 2.2.0 `ExternalSecret` + `ClusterSecretStore` | ESO handles rotation, refresh intervals, error reporting, RBAC on secret access, and race conditions in a production-tested way |
| ArgoCD repo credential injection | Mount a K8s Secret manually with ArgoCD repo config YAML | ArgoCD-native repo-creds secret type (label `argocd.argoproj.io/secret-type: repo-creds`) + ESO ExternalSecret | ArgoCD natively watches for secrets with this label in the `argocd` namespace; no custom controller needed |
| Addon feature flag parsing | Shell script that reads Bridge Secret labels and generates Application YAMLs | ArgoCD ApplicationSet cluster generator with `matchExpressions` | ApplicationSet reconciles continuously; shell scripts are run once and diverge |
| Directory structure convention enforcement | README rules | Directory names that literally match Bridge Secret label suffixes | Convention enforced by the ApplicationSet template expression itself — wrong dir name = broken Application name |

---

## Common Pitfalls

### Pitfall 1: ESO CRD Race — ClusterSecretStore applied before CRDs are ready

**What goes wrong:** If the ClusterSecretStore manifest and the ESO Helm Application are in different ArgoCD Applications (or even different sync waves within the same Application applied simultaneously), the CRD for `ClusterSecretStore` may not be established when ArgoCD tries to apply the CR. Sync fails with `no matches for kind "ClusterSecretStore"`.

**Why it happens:** ArgoCD doesn't gate cross-Application CRD establishment by default. ApplicationSet creates all Applications simultaneously unless Progressive Syncs are enabled.

**How to avoid:** Keep the ClusterSecretStore manifest INSIDE the ESO addon directory (same Application). Assign sync-wave: "2" on the ClusterSecretStore, "1" on ESO Application. ESO Helm installs CRDs in wave 1; ClusterSecretStore is applied in wave 2 after CRDs are established. [VERIFIED: .planning/research/PITFALLS.md Pitfall 3]

**Warning signs:** `no matches for kind "ClusterSecretStore" in version "external-secrets.io/v1"`

### Pitfall 2: Instance Principal auth on BASIC OKE cluster — works correctly

**What goes wrong:** This is actually NOT a pitfall for Instance Principal — it is a pitfall only for OKE Workload Identity (which requires Enhanced cluster). The existing cluster is BASIC, which is correct for Instance Principal (node-level authentication via Dynamic Group).

**What to verify:** The Dynamic Group matching rule in `oci-iam/main.tf` uses `resource.type = 'instance'` (instance principal pattern), NOT `resource.type = 'workload'`. This is correct. The IAM policy grants `read secret-family` to the dynamic group. No changes needed to IAM for ESO with Instance Principal. [VERIFIED: terraform/infra/modules/oci-iam/main.tf]

**Warning signs if this is wrong:** ClusterSecretStore shows `Invalid`; ESO pod logs show 401 or permission denied from OCI Vault API.

### Pitfall 3: Convention mismatch between addon dir name and Bridge Secret label

**What goes wrong:** The Bridge Secret in Phase 1 uses `enable_eso: "true"` (not `enable_external_secrets`). The addon directory is named `eso/`. If someone names the directory `external-secrets/` following the Helm chart name, the convention breaks — the ApplicationSet expects `enable_external-secrets` which doesn't exist in the Bridge Secret.

**How to avoid:** The addon directory names must match what was committed in the Bridge Secret. Bridge Secret labels from Phase 1:
- `enable_eso = "true"`
- `enable_envoy_gateway = "true"`
- `enable_cert_manager = "true"`
- `enable_metrics_server = "true"`
- `enable_argocd = "true"`

So addon directories must be: `eso/`, `envoy-gateway/`, `cert-manager/`, `metrics-server/`. [VERIFIED: terraform/infra/modules/oci-argocd-bootstrap/main.tf]

### Pitfall 4: Root Bootstrap Application syncs `argocd/` dir and creates duplicate ArgoCD resources

**What goes wrong:** The root bootstrap Application syncs `bootstrap/control-plane` recursively. If the ArgoCD self-managed Application in `argocd/application.yaml` references a Helm chart that overlaps with the already-running ArgoCD (from Phase 1 Terraform), the first sync may try to modify running ArgoCD resources before the self-managed lifecycle is established.

**How to avoid:** Set `lifecycle { ignore_changes = all }` on the Terraform `helm_release.argocd` resource (already done in Phase 1 per `oci-argocd-bootstrap/main.tf`). The ArgoCD self-managed Application will adopt the existing Helm release via `ServerSideApply=true` without conflict. First sync of the self-managed Application is effectively a no-op if the values match what Terraform installed. [VERIFIED: terraform/infra/modules/oci-argocd-bootstrap/main.tf]

### Pitfall 5: ExternalSecret `remoteRef.key` must match OCI Vault `secret_name` exactly

**What goes wrong:** OCI Vault secret names are case-sensitive. The `remoteRef.key` in ExternalSecret must exactly match the `secret_name` used in the `oci_vault_secret` Terraform resource. The existing vault has `secret_name = "github-oauth-client-id"` and `secret_name = "github-oauth-client-secret"`. The ExternalSecret must use these exact strings.

**How to avoid:** Check `terraform/infra/modules/oci-vault/main.tf` for exact secret names before writing ExternalSecret manifests. Current names:
- `github-oauth-client-id`
- `github-oauth-client-secret`
- `gitops-repo-pat` (to be added by Terraform extension in this phase)

[VERIFIED: terraform/infra/modules/oci-vault/main.tf]

### Pitfall 6: `argocd-repo-creds` secret requires specific format for ArgoCD to recognize it

**What goes wrong:** ArgoCD discovers repo credential templates by watching for K8s Secrets in the `argocd` namespace with label `argocd.argoproj.io/secret-type: repo-creds`. If the ExternalSecret's `target.template.metadata.labels` does not include this label, ArgoCD won't use the secret as repo credentials and will fail to clone the gitops-setup repo.

**How to avoid:** The ExternalSecret for repo credentials must use `target.template` to inject the ArgoCD label:
```yaml
target:
  template:
    type: Opaque
    metadata:
      labels:
        argocd.argoproj.io/secret-type: repo-creds
```
[VERIFIED: ESO v1 API docs — target.template allows label injection on the generated K8s Secret]

---

## Code Examples

### ESO ClusterSecretStore (OCI Vault, Instance Principal, namespace-restricted)

```yaml
# Source: https://external-secrets.io/latest/provider/oracle-vault/
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: oci-vault
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  namespaceSelector:
    matchLabels:
      kubernetes.io/metadata.name: argocd
  provider:
    oracle:
      vault: "ocid1.vault.oc1.sa-saopaulo-1.<vault_unique_id>"
      region: "sa-saopaulo-1"
      principalType: InstancePrincipal
```

### ESO ExternalSecret (GitHub OAuth, maps to ArgoCD Dex expected keys)

```yaml
# Source: https://external-secrets.io/latest/provider/oracle-vault/
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: argocd-dex-github-secret
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "2"
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: oci-vault
    kind: ClusterSecretStore
  target:
    name: argocd-dex-github-secret
    creationPolicy: Owner
  data:
  - secretKey: client_id
    remoteRef:
      key: github-oauth-client-id
  - secretKey: client_secret
    remoteRef:
      key: github-oauth-client-secret
```

### Terraform OCI Vault secret for GitHub PAT (follow existing pattern)

```hcl
# Source: terraform/infra/modules/oci-vault/main.tf (existing pattern)
resource "oci_vault_secret" "gitops_repo_pat" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "gitops-repo-pat"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.gitops_repo_pat)
    name         = "gitops-repo-pat"
  }
}
```

### Git repository initialization

```bash
# Create gitops-setup repo
mkdir -p ~/projects/AssessForge/gitops-setup
cd ~/projects/AssessForge/gitops-setup
git init
git branch -m main

# Create required directory structure
mkdir -p bootstrap/control-plane/addons/{eso,envoy-gateway,cert-manager,metrics-server}
mkdir -p bootstrap/control-plane/argocd
mkdir -p environments/{default,prod}/addons/{eso,envoy-gateway,cert-manager,metrics-server,argocd}
mkdir -p clusters/in-cluster/addons/{eso,envoy-gateway,cert-manager,metrics-server,argocd}

# Create .gitkeep files for empty stub directories
find . -type d -empty -exec touch {}/.gitkeep \;
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `external-secrets.io/v1beta1` API | `external-secrets.io/v1` API | ESO 2.x (2024) | All ExternalSecret and ClusterSecretStore manifests must use v1 API group |
| Per-addon ApplicationSets (gitops-bridge reference impl) | Single matrix ApplicationSet per project decision | D-04 (2026-04-10) | One file to maintain; convention-based dir naming required |
| OKE Workload Identity for ESO | Instance Principal via Dynamic Group | Project constraint (paid feature) | `principalType: InstancePrincipal`; no `serviceAccountRef` needed |
| `ingress-nginx` | Envoy Gateway (Phase 3) | ingress-nginx archived March 2026 | Stub Envoy Gateway dir in Phase 2; configure in Phase 3 |
| ArgoCD Helm chart 7.x | 9.5.0 (app v3.3.6) | Phase 1 decision | Self-managed Application must reference same pinned version |

**Deprecated/outdated:**
- `external-secrets.io/v1beta1`: Deprecated, will be removed in a future ESO release. Use `v1`.
- `ingress-nginx`: Repository archived March 24, 2026. Stubs for ingress-nginx must NOT be created — use `envoy-gateway` instead.

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Envoy Gateway Helm chart version is `1.4.0` from `oci://docker.io/envoyproxy` (chart name: `gateway-helm`) | Standard Stack | Phase 3 stub Application will have wrong chart version; low risk in Phase 2 since stub has no values |
| A2 | The single matrix ApplicationSet (D-04) with convention-based filtering (D-05) will produce Applications for ALL discovered addon directories regardless of Bridge Secret feature flags — feature gating requires either dir presence control or per-addon AppSets | Architecture Patterns Pattern 1 | If false, a simpler filtering approach exists; if true, Phase 3 may need to revisit gating |
| A3 | `clusters/in-cluster/addons/eso/values.yaml` is the correct place to inject vault OCID for ESO (rather than ApplicationSet Helm parameter override) for Phase 2 simplicity | Architecture Patterns Pattern 4 | If wrong approach, vault OCID won't reach ESO Helm values; ClusterSecretStore will have wrong OCID |
| A4 | ArgoCD recognizes `argocd-repo-creds` by watching for `argocd.argoproj.io/secret-type: repo-creds` label on K8s Secrets in the `argocd` namespace | Common Pitfalls Pitfall 6 | Repo cloning will fail silently; ArgoCD won't use the secret as credentials |

---

## Open Questions (RESOLVED)

1. **Single AppSet feature gating behavior**
   - What we know: D-04 commits to a single matrix ApplicationSet; D-05 commits to convention-based dir-to-label mapping
   - What's unclear: Does the matrix ApplicationSet create Applications for ALL discovered directories (including disabled addons), or can `matchExpressions` on the cluster generator filter by a label that matches the dir basename?
   - Recommendation: Plan should document that ALL stubbed addon dirs will generate Applications; stub Applications with empty Helm values are harmless in Phase 2. Address proper gating in Phase 3 if needed.
   - **RESOLVED:** Plans adopt this recommendation. All dirs generate Applications; gating deferred to Phase 3.

2. **ArgoCD repo-creds secret exact format**
   - What we know: ArgoCD uses secrets labeled `argocd.argoproj.io/secret-type: repo-creds` for credential templates
   - What's unclear: Whether `url`, `username`, `password` are the exact required keys or if `type: git` is also needed
   - Recommendation: Plan should include a verification step — after ESO syncs the secret, run `argocd repo list` to confirm ArgoCD picks it up.
   - **RESOLVED:** Plan 02-02 uses target.template with type/url/username/password keys and `argocd.argoproj.io/secret-type: repo-creds` label. Runtime verification deferred to Phase 3 deployment.

3. **gitops-setup repo visibility (public vs private)**
   - What we know: ArgoCD repo-creds with PAT are needed for private repos
   - What's unclear: Will the repo be public (no creds needed for read) or private (PAT required)?
   - Recommendation: Create as private; use PAT credentials. Lower risk than public for a GitOps control-plane repo. The ESO-04 ExternalSecret for repo creds is required either way per REQUIREMENTS.md.
   - **RESOLVED:** Private repo + PAT. Plan 02-03 adds PAT to OCI Vault; Plan 02-02 creates ExternalSecret for repo-creds.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| `git` | gitops-setup repo creation | ✓ | 2.43.0 | — |
| `kubectl` | verify cluster state, ESO ClusterSecretStore status | ✓ | v1.34.1 | — |
| `helm` | local chart introspection (optional) | ✓ | v4.1.3 | — |
| OCI Vault (live) | Terraform extension for PAT secret | Unknown — depends on Phase 1 completion | — | No fallback — Phase 1 must complete first |
| OKE cluster (live) | ESO deployment and verification | Unknown — depends on Phase 1 completion | — | No fallback — Phase 1 must complete first |
| GitHub repository `AssessForge/gitops-setup` | ArgoCD bootstrap Application | Must be created | — | Create at start of phase |

**Missing dependencies with no fallback:**
- OCI Vault live instance (created by Phase 1) — required before Terraform extension can run
- OKE cluster live instance (created by Phase 1) — required before ESO can be deployed and verified
- `AssessForge/gitops-setup` GitHub repository — must be created at the start of Phase 2 (git push to new remote)

**Missing dependencies with fallback:**
- None identified for Phase 2 deliverables

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes | Instance Principal via OCI Dynamic Group — no static credentials |
| V3 Session Management | no | GitOps repo; no user sessions |
| V4 Access Control | yes | `namespaceSelector` on ClusterSecretStore restricts ESO access to `argocd` namespace only |
| V5 Input Validation | yes | ESO ExternalSecret uses explicit `data[].remoteRef.key` — no wildcard secret extraction |
| V6 Cryptography | no — OCI-managed | OCI Vault handles encryption; AES-256 master key from Phase 1 |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| ESO over-permissive ClusterSecretStore | Information Disclosure | `namespaceSelector: matchLabels: kubernetes.io/metadata.name: argocd` restricts which namespaces can create ExternalSecrets |
| GitHub PAT with excessive scopes | Elevation of Privilege | PAT must be scoped to `repo` read-only for gitops-setup repo; document minimum required scopes |
| ArgoCD repo-creds secret readable by all apps | Information Disclosure | Secret in `argocd` namespace; namespace RBAC restricts access to ArgoCD service accounts only |
| Vault OCID hardcoded in git history | Information Disclosure | OCIDs are not credentials; hardcoding is acceptable. Do not commit actual PAT values. |

**Security constraint from CLAUDE.md:** No static API keys anywhere — all sensitive values in OCI Vault, pulled by ESO. The GitHub PAT (a credential) must be stored in OCI Vault and synced by ESO. It must not appear in any committed YAML file.

---

## Sources

### Primary (HIGH confidence)
- `terraform/infra/modules/oci-argocd-bootstrap/main.tf` — Bridge Secret labels (`enable_eso`, `enable_envoy_gateway`, etc.), ArgoCD Helm release version 9.5.0, root bootstrap Application spec
- `terraform/infra/modules/oci-vault/main.tf` — Existing Vault secret names (`github-oauth-client-id`, `github-oauth-client-secret`), Vault resource pattern
- `terraform/infra/modules/oci-iam/main.tf` — Dynamic Group matching rule (`resource.type = 'instance'`) — confirms Instance Principal, not Workload Identity
- `https://external-secrets.io/latest/provider/oracle-vault/` — ESO v1 API, `principalType: InstancePrincipal`, `remoteRef.key` maps to OCI `secret_name`, `namespaceSelector` placement
- `.planning/research/STACK.md` — Pinned Helm chart versions (ESO 2.2.0, ArgoCD 9.5.0, cert-manager 1.20.1, metrics-server 3.13.0)
- `.planning/research/PITFALLS.md` — CRD race condition (Pitfall 3), Instance Principal vs Workload Identity (Pitfall 1, Pitfall 8), sync wave cross-Application ordering (Pitfall 7)

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` — Directory structure, Bridge Secret annotation reference, per-addon AppSet YAML pattern (adapted for single-AppSet design)
- `https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/applicationset/Generators-Matrix.md` — Matrix generator combining clusters and git generators, Go template syntax for metadata label access

### Tertiary (LOW confidence)
- Envoy Gateway Helm chart version (A1) — assumed 1.4.0; not verified in this session

---

## Metadata

**Confidence breakdown:**
- Standard stack (ESO, ArgoCD versions): HIGH — verified against existing Terraform code and STACK.md
- ApplicationSet matrix generator pattern: MEDIUM — official ArgoCD docs confirm matrix generator; single-AppSet convention approach has assumptions about feature gating behavior (A2)
- ESO ClusterSecretStore (Instance Principal): HIGH — verified against ESO official docs
- ExternalSecret YAML patterns: HIGH — verified API version and remoteRef structure from ESO docs + existing Vault secret names from Terraform code
- Terraform vault extension: HIGH — follows identical pattern to existing secrets in module

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (stable technologies — ESO and ArgoCD move slowly on major API changes)
