# Architecture Research

**Domain:** GitOps Bridge Pattern — OCI/OKE single-cluster
**Researched:** 2026-04-09
**Confidence:** HIGH (reference implementation verified against gitops-bridge-dev org canonical repos)

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  LAYER 1: OCI Infrastructure (terraform/infra/)                  │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │  VCN/NSG │  │  IAM/DG  │  │   OKE    │  │  OCI Vault   │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────────┘   │
└──────────────────────────┬──────────────────────────────────────┘
                           │  terraform output metadata
┌──────────────────────────▼──────────────────────────────────────┐
│  LAYER 2: Bootstrap (terraform/infra/ — one-time, idempotent)    │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  ArgoCD (helm_release, minimal — no SSO, no repo config)   │  │
│  └───────────────────────────┬────────────────────────────────┘  │
│  ┌────────────────────────────▼────────────────────────────────┐  │
│  │  Bridge Secret (K8s Secret, ns: argocd)                     │  │
│  │  labels:  argocd.argoproj.io/secret-type: cluster           │  │
│  │           environment: prod                                  │  │
│  │           enable_argocd: "true"                             │  │
│  │           enable_cert_manager: "true"                       │  │
│  │           enable_external_secrets: "true"                   │  │
│  │           enable_ingress_nginx: "true"                      │  │
│  │           enable_metrics_server: "true"                     │  │
│  │  annotations: addons_repo_url, addons_repo_revision,        │  │
│  │               addons_repo_basepath, cluster_name,           │  │
│  │               oci_compartment_id, oci_vault_ocid,           │  │
│  │               oci_subnet_id, oci_region,                    │  │
│  │               argocd_workload_identity_namespace            │  │
│  └────────────────────────────┬───────────────────────────────┘  │
│  ┌────────────────────────────▼────────────────────────────────┐  │
│  │  Root Bootstrap Application (App of Apps)                   │  │
│  │  → points to gitops-setup/bootstrap/control-plane/          │  │
│  └────────────────────────────────────────────────────────────┘  │
└──────────────────────────┬──────────────────────────────────────┘
                           │  ArgoCD reconciles
┌──────────────────────────▼──────────────────────────────────────┐
│  LAYER 3: GitOps Control Plane (gitops-setup repo)               │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  bootstrap/control-plane/                                   │  │
│  │  ├── argocd/argocd-appset.yaml  (ArgoCD self-managed)      │  │
│  │  └── addons/oss/                (one ApplicationSet each)  │  │
│  │      ├── ingress-nginx-appset.yaml                         │  │
│  │      ├── cert-manager-appset.yaml                          │  │
│  │      ├── external-secrets-appset.yaml                      │  │
│  │      └── metrics-server-appset.yaml                        │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  environments/                  (values hierarchy)         │  │
│  │  ├── default/addons/{addon}/values.yaml                    │  │
│  │  └── prod/addons/{addon}/values.yaml                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  clusters/                      (cluster overrides)        │  │
│  │  └── in-cluster/addons/{addon}/values.yaml                 │  │
│  └────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Communicates With |
|-----------|----------------|-------------------|
| `terraform/infra/` | OCI cloud resources, OKE cluster, Vault, IAM Dynamic Group for ArgoCD workload identity | OCI APIs only |
| Bridge Secret (`argocd/in-cluster`) | Carries infra metadata from Terraform into ArgoCD's secret store; drives ApplicationSet cluster generator | ArgoCD ApplicationSet controller reads it |
| Root Bootstrap Application | App of Apps created by Terraform; points ArgoCD at `gitops-setup/bootstrap/control-plane/` | ArgoCD → gitops-setup repo |
| ArgoCD self-managed ApplicationSet | Manages ArgoCD's own Helm release and config (SSO, RBAC, repo creds via ESO) | Reads values files from gitops-setup repo; ESO syncs secrets |
| Per-addon ApplicationSets | One ApplicationSet per addon; reads Bridge Secret labels to decide whether to deploy; reads annotations for values file paths | Bridge Secret → Helm chart repos → cluster |
| `environments/` values files | Provides addon configuration scoped by environment (default → prod override); merged by ApplicationSet `ignoreMissingValueFiles: true` | Referenced by ApplicationSet `valueFiles` array |
| `clusters/` values files | Cluster-specific overrides layered on top of environment values | Referenced by ApplicationSet `valueFiles` array, last wins |
| External Secrets Operator | Syncs OCI Vault secrets into cluster K8s Secrets; provides ArgoCD SSO creds, repo creds, notification tokens | OCI Vault (workload identity) → K8s Secrets |

## Recommended GitOps Repository Structure

```
gitops-setup/
├── bootstrap/
│   └── control-plane/
│       ├── exclude/
│       │   └── bootstrap.yaml          # root App of Apps (Terraform creates this in-cluster)
│       ├── argocd/
│       │   └── argocd-appset.yaml      # ArgoCD self-managed ApplicationSet
│       └── addons/
│           └── oss/
│               ├── ingress-nginx-appset.yaml
│               ├── cert-manager-appset.yaml
│               ├── external-secrets-appset.yaml
│               └── metrics-server-appset.yaml
│
├── environments/
│   ├── default/
│   │   └── addons/
│   │       ├── argocd/values.yaml          # base ArgoCD Helm values
│   │       ├── ingress-nginx/values.yaml   # OCI LB annotations etc.
│   │       ├── cert-manager/values.yaml
│   │       ├── external-secrets/values.yaml
│   │       └── metrics-server/values.yaml
│   └── prod/
│       └── addons/
│           ├── argocd/values.yaml          # prod overrides (SSO config, RBAC)
│           ├── ingress-nginx/values.yaml   # prod LB shape override
│           └── cert-manager/values.yaml    # prod issuer config
│
└── clusters/
    └── in-cluster/
        └── addons/
            ├── argocd/values.yaml          # cluster-specific ArgoCD config
            ├── external-secrets/values.yaml # OCI vault OCID injected here
            └── ingress-nginx/values.yaml    # OCI subnet annotation
```

### Structure Rationale

- **`bootstrap/control-plane/`:** Mirrors the gitops-bridge-dev reference template. ArgoCD reconciles this directory recursively via the root App of Apps. The `exclude/` pattern prevents the bootstrap Application itself from being re-applied by ArgoCD (it's the root; if ArgoCD managed it, deletion would cascade).
- **`environments/default/`:** Values that apply to every cluster regardless of environment — avoids duplication. All addon-specific ApplicationSets use `ignoreMissingValueFiles: true` so absent files don't block deployment.
- **`environments/prod/`:** Environment-specific overrides. With a single cluster this mostly holds ArgoCD SSO config and production-tuned resource limits.
- **`clusters/in-cluster/`:** Cluster-specific leaf overrides (last in the `valueFiles` array, so they win). This is where OCI-specific OCIDs and subnet IDs that came from the Bridge Secret are injected back as Helm values for addons like ESO and ingress-nginx.

## Architectural Patterns

### Pattern 1: Bridge Secret as Metadata Bus

**What:** Terraform writes a Kubernetes Secret in the `argocd` namespace with `argocd.argoproj.io/secret-type: cluster`. The secret carries two categories of data: `labels` (boolean enable/disable flags per addon) and `annotations` (string metadata — OCIDs, repo URLs, revision, paths).

**When to use:** Whenever an addon needs cloud-provider metadata (IAM role ARN, vault OCID, subnet ID) that only exists after `terraform apply`. This is the canonical handoff mechanism in the GitOps Bridge Pattern.

**Full secret structure for this project:**

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: in-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    environment: prod
    # Feature flags — ApplicationSet matchExpressions filter on these
    enable_argocd: "true"
    enable_cert_manager: "true"
    enable_external_secrets: "true"
    enable_ingress_nginx: "true"
    enable_metrics_server: "true"
  annotations:
    # GitOps repo routing (ApplicationSet uses these as template vars)
    addons_repo_url: "https://github.com/AssessForge/gitops-setup"
    addons_repo_revision: "main"
    addons_repo_basepath: ""          # empty = root of repo
    # OCI infra metadata for addon Helm values
    oci_region: "sa-saopaulo-1"
    oci_compartment_id: "<ocid1.compartment...>"
    oci_vault_ocid: "<ocid1.vault...>"
    oci_subnet_id: "<ocid1.subnet...>"   # private worker subnet
    oci_lb_subnet_id: "<ocid1.subnet...>" # public LB subnet
    cluster_name: "in-cluster"
    argocd_workload_identity_namespace: "argocd"
stringData:
  name: "in-cluster"
  server: "https://kubernetes.default.svc"
  config: |
    {"tlsClientConfig":{"insecure":false}}
```

**Trade-offs:** Labels are queryable by ApplicationSet cluster generator (`matchExpressions`). Annotations are accessible as template variables (`{{metadata.annotations.X}}`). Putting OCIDs in annotations rather than labels is intentional — labels have character restrictions, annotations do not.

### Pattern 2: Per-Addon ApplicationSet with Merge Generator

**What:** Each addon gets its own ApplicationSet (not one giant ApplicationSet). The merge generator combines a base cluster selector (the feature-flag label) with environment-specific version overrides.

**When to use:** Every addon in this project. ApplicationSets are the canonical way to drive per-cluster addon deployment in GitOps Bridge.

**Canonical structure (cert-manager example):**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: addons-cert-manager
  namespace: argocd
spec:
  syncPolicy:
    preserveResourcesOnDeletion: true
  generators:
  - merge:
      mergeKeys: [server]
      generators:
      - clusters:
          values:
            addonChart: cert-manager
            addonChartVersion: "1.14.4"       # pinned
            addonChartRepository: https://charts.jetstack.io
          selector:
            matchExpressions:
            - key: enable_cert_manager
              operator: In
              values: ['true']
      - clusters:
          selector:
            matchLabels:
              environment: prod
          values:
            addonChartVersion: "1.14.4"       # can pin per-env
  template:
    metadata:
      name: addon-{{name}}-{{values.addonChart}}
    spec:
      project: default
      sources:
      - repoURL: '{{metadata.annotations.addons_repo_url}}'
        targetRevision: '{{metadata.annotations.addons_repo_revision}}'
        ref: values
      - chart: '{{values.addonChart}}'
        repoURL: '{{values.addonChartRepository}}'
        targetRevision: '{{values.addonChartVersion}}'
        helm:
          releaseName: '{{values.addonChart}}'
          ignoreMissingValueFiles: true
          valueFiles:
          - $values/environments/default/addons/{{values.addonChart}}/values.yaml
          - $values/environments/{{metadata.labels.environment}}/addons/{{values.addonChart}}/values.yaml
          - $values/clusters/{{name}}/addons/{{values.addonChart}}/values.yaml
      destination:
        namespace: '{{values.addonChart}}'
        name: '{{name}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
        - ServerSideApply=true
```

**Trade-offs:** Per-addon ApplicationSets allow independent versioning and enable/disable without touching other addons. The downside is more YAML files (one per addon). For 4-5 addons at this scale, the file count is manageable and the per-addon control is worth it.

### Pattern 3: ArgoCD Self-Management

**What:** ArgoCD manages its own Helm release via a dedicated ApplicationSet in `bootstrap/control-plane/argocd/`. After the root App of Apps reconciles this directory, ArgoCD picks up the self-managed ApplicationSet and starts reconciling its own Helm values. Changes to ArgoCD config (SSO, RBAC, resource limits) flow through PRs to the gitops-setup repo, not `terraform apply`.

**When to use:** From day one. Prevents config drift — without this, ArgoCD's own configuration lives outside Git.

**Self-managed ApplicationSet structure:**

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: addons-argocd
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchExpressions:
        - key: enable_argocd
          operator: In
          values: ['true']
      values:
        addonChart: argo-cd
        addonChartVersion: "6.7.3"    # pinned
        addonChartRepository: https://argoproj.github.io/argo-helm
  template:
    metadata:
      name: addon-{{name}}-argocd
    spec:
      project: default
      sources:
      - repoURL: '{{metadata.annotations.addons_repo_url}}'
        targetRevision: '{{metadata.annotations.addons_repo_revision}}'
        ref: values
      - chart: '{{values.addonChart}}'
        repoURL: '{{values.addonChartRepository}}'
        targetRevision: '{{values.addonChartVersion}}'
        helm:
          releaseName: argocd
          ignoreMissingValueFiles: true
          valueFiles:
          - $values/environments/default/addons/argocd/values.yaml
          - $values/environments/{{metadata.labels.environment}}/addons/argocd/values.yaml
          - $values/clusters/{{name}}/addons/argocd/values.yaml
      destination:
        namespace: argocd
        name: '{{name}}'
      syncPolicy:
        automated:
          prune: false    # NEVER prune argocd itself — safety
          selfHeal: true
        syncOptions:
        - ServerSideApply=true
```

**Prune: false for ArgoCD self:** This is deliberate. Auto-pruning ArgoCD's own resources risks the controller deleting itself mid-sync. All other addons use `prune: true`.

## Data Flow

### Bootstrap Sequence (Terraform → Fully GitOps-Managed)

```
Step 1: terraform apply (terraform/infra/)
        ↓
        OCI resources created: VCN, IAM, OKE, Vault
        Dynamic Group + IAM Policy for ArgoCD Workload Identity
        ↓
Step 2: helm_release "argocd" (minimal, in terraform/infra/)
        ↓
        ArgoCD running — no SSO, no repo config, admin user only
        ↓
Step 3: kubernetes_secret "in-cluster" created (Bridge Secret)
        ↓
        Contains: OCI metadata as annotations
                  Feature flags as labels
                  In-cluster server config
        ↓
Step 4: kubectl_manifest "bootstrap" applied by Terraform
        ↓
        ArgoCD Application: points to gitops-setup/bootstrap/control-plane/
        Excludes: exclude/* (prevents recursive self-application)
        ↓
Step 5: ArgoCD reconciles bootstrap/control-plane/ (recursive)
        ↓
        Discovers: argocd/argocd-appset.yaml → ArgoCD self-managed Application
                   addons/oss/*.yaml → one Application per enabled addon
        ↓
Step 6: ArgoCD self-managed Application syncs
        ↓
        ArgoCD Helm release updated with full config:
          - Dex connector (GitHub OAuth)
          - RBAC (org members → admin)
          - ExternalSecret references for OAuth creds
          - Ingress config
        ↓
Step 7: external-secrets-operator addon syncs
        ↓
        ESO ClusterSecretStore: authenticates to OCI Vault via Workload Identity
        ExternalSecrets: pull GitHub OAuth creds, repo creds → K8s Secrets
        ↓
Step 8: ingress-nginx addon syncs
        ↓
        OCI Load Balancer provisioned (flexible, public subnet)
        ArgoCD Ingress route active
        ↓
Step 9: cert-manager + metrics-server addons sync
        ↓
        Cluster fully operational via GitOps
        Terraform never touches in-cluster resources again
```

### Metadata Flow (Infra Values to Addon Config)

```
Terraform output
    │
    ↓ (terraform/infra/main.tf → kubernetes_secret)
Bridge Secret annotations
    │
    ↓ (ApplicationSet template: {{metadata.annotations.X}})
ApplicationSet generates Application
    │
    ├── addons_repo_url → source repoURL for values files
    ├── addons_repo_revision → targetRevision
    └── addons_repo_basepath → prefix for valueFiles paths
                │
                ↓ (multi-source: $values ref + chart)
values.yaml files (environments/ and clusters/)
    │
    ├── environments/default/addons/external-secrets/values.yaml
    │     → OCI provider config (region, compartment)
    ├── environments/prod/addons/external-secrets/values.yaml
    │     → prod-specific tolerations/replicas
    └── clusters/in-cluster/addons/external-secrets/values.yaml
          → oci_vault_ocid (from Bridge Secret annotation,
            referenced in values.yaml via static value committed
            at bootstrap time — OR via Helm parameter override
            injected by ApplicationSet template)
```

### Secret Flow (OCI Vault → ArgoCD Runtime)

```
OCI Vault (GitHub OAuth, repo creds, notification tokens)
    │
    ↓ (ESO ClusterSecretStore, OKE Workload Identity)
K8s Secrets (argocd namespace)
    │  argocd-dex-github-secret
    │  argocd-repo-creds
    │  argocd-notifications-secret
    │
    ↓ (ArgoCD reads at runtime)
Dex OIDC connector → GitHub OAuth flow
Repo credentials → gitops-setup repo access
Notifications → alerting channels
```

## Suggested Build Order

The dependency graph drives this order:

1. **OCI IAM Dynamic Group + Policy for ArgoCD Workload Identity** — must exist before ArgoCD is installed, because ESO needs it at pod start. Without this, ESO can't authenticate to Vault.

2. **ArgoCD Helm release (minimal)** — installed by Terraform. Must be minimal (no SSO config) because the SSO secrets don't exist yet — ESO hasn't run yet. ArgoCD with admin user only at this stage.

3. **Bridge Secret** — depends on ArgoCD namespace existing. Contains all infra metadata. Terraform creates this immediately after the ArgoCD Helm release.

4. **Root Bootstrap Application** — applied by Terraform (`kubectl_manifest` or `kubernetes_manifest`). This triggers the full GitOps reconciliation chain. All subsequent steps are driven by ArgoCD, not Terraform.

5. **ESO addon** (ArgoCD-managed) — first addon to sync after bootstrap, because all other addons that need secrets depend on it. ApplicationSet for ESO must deploy before ArgoCD self-manages its full config.

6. **ArgoCD self-managed update** (ArgoCD-managed) — once ESO has synced the GitHub OAuth secret into `argocd-dex-github-secret`, ArgoCD Helm reconciles with SSO config. This is a Helm upgrade, not a fresh install.

7. **ingress-nginx** (ArgoCD-managed) — depends only on OKE being ready. Provisions OCI Load Balancer. No secret dependencies.

8. **cert-manager** (ArgoCD-managed) — can deploy in parallel with ingress-nginx. No dependencies on ESO secrets for basic deployment.

9. **metrics-server** (ArgoCD-managed) — independent, can deploy any time after bootstrap.

**Dependency constraint to flag:** ArgoCD SSO will not work until ESO has synced the GitHub OAuth secret. There is a brief window after bootstrap where ArgoCD is accessible but SSO is non-functional (admin login only). This is by design — the window closes when ESO syncs, which happens within seconds of ESO's pod becoming Ready.

## Anti-Patterns

### Anti-Pattern 1: Letting Terraform Manage In-Cluster Resources After Bootstrap

**What people do:** Keep `terraform/k8s/` module and continue using Terraform to manage ArgoCD config, ingress, secrets.

**Why it's wrong:** Two sources of truth. Terraform state and ArgoCD drift against each other. Helm provider in Terraform can conflict with ArgoCD's Helm management. Any `terraform apply` after bootstrap risks overwriting ArgoCD-managed config.

**Do this instead:** Destroy `terraform/k8s/` entirely after bootstrap. ArgoCD adopts the addons via the GitOps repo. All changes go through PRs.

### Anti-Pattern 2: One Giant ApplicationSet for All Addons

**What people do:** Create a single ApplicationSet that iterates over addon names with a directory generator or list generator.

**Why it's wrong:** Cannot pin different chart versions per addon. Cannot have addon-specific enable/disable logic. Changing one addon's config requires touching a shared manifest, increasing blast radius.

**Do this instead:** One ApplicationSet per addon. The reference implementation (gitops-bridge-dev/gitops-bridge-argocd-control-plane-template) uses exactly this pattern: `addons-kyverno-appset.yaml`, `addons-cert-manager-appset.yaml`, etc.

### Anti-Pattern 3: Hardcoding OCI Metadata in Values Files

**What people do:** Commit OCI OCIDs (compartment, vault, subnet) directly into `environments/prod/addons/*/values.yaml`.

**Why it's wrong:** OCIDs change if infra is rebuilt. Values files become out of sync with actual infra state. The Bridge Secret exists precisely to avoid this.

**Do this instead:** Use the Bridge Secret's annotations as the authoritative source. The ApplicationSet template can inject Bridge Secret annotations as Helm `parameters` that override values files:
```yaml
helm:
  parameters:
  - name: "provider.oci.vaultOCID"
    value: "{{metadata.annotations.oci_vault_ocid}}"
```
This way, the value always reflects current Terraform output.

### Anti-Pattern 4: `prune: true` on ArgoCD Self-Managed Application

**What people do:** Set `automated.prune: true` on the ArgoCD self-managed Application (same as other addons).

**Why it's wrong:** If ArgoCD determines its own Deployment or Service is "not in source," it will delete them — killing the controller mid-reconciliation. Recovery requires manual intervention.

**Do this instead:** ArgoCD self-managed Application uses `prune: false` exclusively. All other addons use `prune: true`.

## Integration Points

### External Services

| Service | Integration Pattern | OCI-Specific Notes |
|---------|---------------------|--------------------|
| OCI Vault | ESO ClusterSecretStore with OKE Workload Identity | No static credentials; pod identity via Dynamic Group + IAM Policy |
| GitHub OAuth | Dex connector, secret synced by ESO from Vault | OAuth App registered in AssessForge org |
| GitHub (gitops repo) | ArgoCD repo credentials (HTTPS + PAT or GitHub App) | PAT stored in Vault, synced by ESO into `argocd-repo-creds` |
| Cloudflare DNS | Manual A record update after ingress-nginx provisions OCI LB | LB IP is Terraform output; cannot be automated without Cloudflare provider |
| OCI Load Balancer | ingress-nginx ServiceType: LoadBalancer with OCI annotations | Flexible shape, 10Mbps — annotations in `environments/default/addons/ingress-nginx/values.yaml` |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Terraform → ArgoCD | Bridge Secret (K8s Secret) | One-way. Terraform writes, ArgoCD reads. No reverse flow. |
| ArgoCD ApplicationSet → Helm charts | Multi-source Application (ref + chart) | `$values` ref provides values files; chart source is upstream Helm repo |
| ESO → OCI Vault | HTTPS API, OIDC token from OKE | ClusterSecretStore scoped to argocd namespace only |
| ESO → K8s Secrets | Direct write to argocd namespace | `ExternalSecret` resources define the sync mapping |
| ArgoCD → K8s Secrets | Volume mount or env-from | Dex and repo-server read secrets at runtime |

## Scaling Considerations

This is a single-cluster, single-environment deployment. Scaling considerations are intentionally minimal.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| Single cluster (current) | in-cluster secret + direct ApplicationSet. No cluster management complexity. |
| Multi-cluster (future) | Add additional cluster secrets to argocd namespace. ApplicationSets automatically generate Applications for each cluster matching the label selector. No ApplicationSet changes required. |
| Multi-environment (future) | Add `environments/staging/` values directories. Add new cluster secrets with `environment: staging` label. Existing ApplicationSets pick them up via merge generator. |

## Sources

- gitops-bridge-dev canonical reference: [gitops-bridge-argocd-control-plane-template](https://github.com/gitops-bridge-dev/gitops-bridge-argocd-control-plane-template) — HIGH confidence (official reference implementation)
- ApplicationSet kyverno example (full YAML verified): [addons-kyverno-appset.yaml](https://github.com/gitops-bridge-dev/gitops-bridge-argocd-control-plane-template/blob/main/bootstrap/control-plane/addons/oss/addons-kyverno-appset.yaml) — HIGH confidence
- Terraform module inputs: [terraform-helm-gitops-bridge](https://github.com/gitops-bridge-dev/terraform-helm-gitops-bridge) — HIGH confidence
- EKS Blueprints getting started (bootstrap sequence reference): [ArgoCD Getting Started](https://aws-ia.github.io/terraform-aws-eks-blueprints/patterns/gitops/gitops-getting-started-argocd/) — MEDIUM confidence (AWS-specific, OCI annotations differ)
- Values file hierarchy pattern: [thatmlopsguy gitops-bridge post](https://thatmlopsguy.github.io/posts/gitops-bridge/) — MEDIUM confidence (verified against reference impl)
- ArgoCD self-management bootstrap: [Demystifying GitOps Bootstrapping ArgoCD](https://medium.com/@aaltundemir/demystifying-gitops-bootstrapping-argo-cd-4a861284f273) — MEDIUM confidence

---
*Architecture research for: GitOps Bridge Pattern on OCI/OKE*
*Researched: 2026-04-09*
