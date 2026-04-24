# Phase 2: GitOps Repository & ESO - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Create the `gitops-setup` repository at `~/projects/AssessForge/gitops-setup` with the directory structure, a single ApplicationSet (matrix generator) that reads the Bridge Secret to dynamically create per-addon Applications, and deploy External Secrets Operator connected to OCI Vault via Instance Principal. Stub all Phase 3 addon directories with sync wave annotations so Phase 3 only fills in configuration details. Add repo credentials to OCI Vault via Terraform.

</domain>

<decisions>
## Implementation Decisions

### Repo Structure
- **D-01:** Flat addon directory layout inside `bootstrap/control-plane/`. The ApplicationSet YAML and per-addon directories live together under this path. `environments/prod/addons/{addon}/values.yaml` provides per-environment Helm value overrides.
- **D-02:** ArgoCD self-managed Application lives inside `bootstrap/control-plane/argocd/` alongside addon dirs — single sync point from the root bootstrap Application.
- **D-03:** Each addon directory contains a Helm-based Application manifest referencing the upstream Helm repo with a pinned chart version. Values come from `environments/` via multiple sources in the Application spec.

### ApplicationSet Design
- **D-04:** Single ApplicationSet (`cluster-addons`) with a matrix generator: cluster generator (reads Bridge Secret labels) x git generator (discovers addon dirs under `bootstrap/control-plane/addons/*`). One file to maintain for all addons.
- **D-05:** Convention-based feature flag filtering — addon dir name maps to Bridge Secret label (e.g., `addons/eso/` matches `enable_eso` label). No explicit mapping file needed.
- **D-06:** ArgoCD self-managed Application is a **standalone** Application.yaml, NOT part of the ApplicationSet. ArgoCD has unique requirements (`prune: false`, special sync policy) that don't fit the generic addon template.

### ESO Auth Strategy
- **D-07:** Single ClusterSecretStore with `namespaceSelector` restricting access to the `argocd` namespace only. Instance Principal auth via Dynamic Group on worker nodes (decided in Phase 1, D-01).
- **D-08:** Create ExternalSecrets for GitHub OAuth client ID/secret (`argocd-dex-github-secret`) and repo credentials (`argocd-repo-creds`). Skip notification tokens — ESO-05 says "if applicable" and no notification system is in v1 scope.
- **D-09:** Repo credentials (GitHub PAT or deploy key for gitops-setup repo) must be added to OCI Vault. This requires a small Terraform change to the `oci-vault` module — new secret resource + new sensitive variable. All credentials stay in Vault per project constraint.
- **D-10:** All ESO manifests use `external-secrets.io/v1` API (not deprecated v1beta1), per requirement ESO-06.

### Sync Wave Order
- **D-11:** ArgoCD sync wave annotations on Application manifests for bootstrap ordering:
  - Wave 1: ESO operator
  - Wave 2: ClusterSecretStore + ExternalSecrets (secrets must exist before consumers)
  - Wave 3: ArgoCD self-managed, Envoy Gateway, cert-manager, metrics-server
- **D-12:** Stub ALL addon directories and Application manifests in Phase 2, including Phase 3 addons (Envoy Gateway, cert-manager, metrics-server, ArgoCD self-managed). Phase 3 fills in Helm values and configuration details. Avoids restructuring later.

### Claude's Discretion
- Exact Application manifest template structure (Helm source, values file references)
- Go template expressions in ApplicationSet for convention-based label matching
- ESO ClusterSecretStore YAML specifics (OCI Vault provider config for Instance Principal)
- ExternalSecret field mapping (which OCI Vault secret IDs map to which K8s secret keys)
- How to structure the Terraform change for adding repo creds to OCI Vault
- Git init and initial commit strategy for the gitops-setup repo

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 1 Outputs (Bootstrap Infrastructure)
- `terraform/infra/modules/oci-argocd-bootstrap/main.tf` — Bridge Secret structure (labels, annotations), root bootstrap Application (points to `bootstrap/control-plane/`), ArgoCD Helm release
- `terraform/infra/modules/oci-argocd-bootstrap/variables.tf` — Variables consumed by bootstrap (gitops_repo_url, gitops_repo_revision, etc.)
- `terraform/infra/modules/oci-vault/main.tf` — Existing OCI Vault secrets (GitHub OAuth) — must be extended with repo credentials

### Existing Infrastructure
- `terraform/infra/main.tf` — Module orchestration, how oci-vault and oci-argocd-bootstrap are wired
- `terraform/infra/variables.tf` — Current variables (will need new sensitive var for repo credentials)
- `terraform/infra/versions.tf` — Providers and backend config

### Research
- `.planning/research/ARCHITECTURE.md` — GitOps Bridge Pattern architecture, directory structure, ApplicationSet patterns
- `.planning/research/STACK.md` — Recommended versions (ESO 2.2.0, ArgoCD 9.5.0/v3.3.6, cert-manager 1.20.1, metrics-server 3.13.0)
- `.planning/research/PITFALLS.md` — OCI-specific pitfalls (Instance Principal config, sync wave gotchas)

### Design Specs
- `docs/superpowers/specs/2026-03-16-oci-oke-argocd-infra-design.md` — Original infrastructure design spec

### Prior Phase Context
- `.planning/phases/01-cleanup-iam-bootstrap/01-CONTEXT.md` — Phase 1 decisions (IAM strategy, Bridge Secret design, bootstrap layout)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `terraform/infra/modules/oci-vault/main.tf`: OCI Vault + master key + GitHub OAuth secrets already exist — extend with repo credential secret
- `terraform/infra/modules/oci-argocd-bootstrap/main.tf`: Bridge Secret with all required labels/annotations is already deployed — ApplicationSet reads this directly
- `terraform/infra/modules/oci-iam/main.tf`: Dynamic Group for Instance Principal already configured for worker nodes

### Established Patterns
- Terraform module structure: `main.tf` + `variables.tf` + `outputs.tf` (no versions.tf for infra modules)
- Resource naming: `assessforge-<component>` prefix
- All sensitive values as Terraform variables with `sensitive = true`, stored in OCI Vault
- `freeform_tags` passed to all modules
- Portuguese comments in HCL files

### Integration Points
- Root bootstrap Application syncs from `gitops-setup/bootstrap/control-plane/` — all manifests placed here are automatically reconciled by ArgoCD
- Bridge Secret annotations (`addons_repo_url`, `addons_repo_revision`, `oci_vault_ocid`, etc.) are consumed by ApplicationSet template expressions
- OCI Vault OCID from Bridge Secret annotation feeds into ClusterSecretStore config
- Instance Principal auth requires no additional K8s resources — ESO uses the node's instance metadata endpoint

</code_context>

<specifics>
## Specific Ideas

- The `gitops-setup` repo is a NEW repository at `~/projects/AssessForge/gitops-setup` — not inside the infra-setup repo
- Phase 3 addon stubs should have the correct sync wave annotations and Helm chart references but minimal/empty values — they become functional when Phase 3 fills in config
- ESO v2 API (`external-secrets.io/v1`) is mandatory — the v1beta1 API is deprecated
- The repo credential in OCI Vault could be a GitHub PAT (simplest) or deploy key — Claude's discretion on which fits better

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 02-gitops-repository-eso*
*Context gathered: 2026-04-10*
