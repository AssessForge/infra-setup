# Phase 1: Cleanup & IAM Bootstrap - Context

**Gathered:** 2026-04-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Remove the never-applied `terraform/k8s/` directory entirely, fix the IAM Dynamic Group for Instance Principal on BASIC tier (free), extend `terraform/infra/` with a new bootstrap module that installs ArgoCD via Helm, creates the GitOps Bridge Secret with OCI metadata annotations and addon feature flags, and deploys the root bootstrap Application pointing to the gitops-setup repo. After this phase, Terraform is done touching the cluster — everything else flows through GitOps.

</domain>

<decisions>
## Implementation Decisions

### IAM Strategy
- **D-01:** Claude's discretion on Dynamic Group matching rule for Instance Principal on BASIC tier. The existing `resource.type = 'workload'` rule is Enhanced-only and must be replaced. Best approach: match by `instance.compartment.id` scoped to the OKE node pool instances, giving all worker nodes Vault read access. This is the simplest pattern that works on free tier BASIC clusters.
- **D-02:** The existing IAM policy statements (`read secret-family`, `use vaults`, `use keys`) are correct — only the Dynamic Group matching rule changes.

### Bootstrap Layout
- **D-03:** Extend `terraform/infra/` — add Helm + Kubernetes providers to the existing infra root module. Create a new `modules/oci-argocd-bootstrap/` module alongside oci-oke, oci-vault, etc. Single `terraform apply` provisions everything.
- **D-04:** The bootstrap module depends on oci-oke (needs cluster endpoint + CA cert for Helm/k8s providers) and oci-vault (needs vault OCID for Bridge Secret annotations).

### Bridge Secret Design
- **D-05:** Claude's discretion on annotation key naming. Recommendation: use OCI-flavored names (`oci_compartment_ocid`, `oci_vault_ocid`, `oci_region`, `oci_public_subnet_id`, `oci_private_subnet_id`) — explicit about cloud provider, consistent with gitops-bridge community patterns adapted for OCI.
- **D-06:** Claude's discretion on which addon feature flags to include as labels. Recommendation: include all v1 addons as labels (`enable_eso: "true"`, `enable_envoy_gateway: "true"`, `enable_cert_manager: "true"`, `enable_metrics_server: "true"`, `enable_argocd: "true"`) plus metadata labels (`environment: "prod"`, `cluster_name: "assessforge-oke"`). Even always-on addons get flags for pattern consistency and future toggle capability.
- **D-07:** Bridge Secret must include `addons_repo_url` and `addons_repo_revision` annotations pointing to the gitops-setup repo.

### Code Cleanup
- **D-08:** Delete `terraform/k8s/` entirely — all modules, lock files, tfvars examples, provider lock files. No archive. Git history preserves everything if needed later.

### Claude's Discretion
- IAM: Dynamic Group matching rule details (D-01)
- Bridge Secret: Annotation key naming convention (D-05)
- Bridge Secret: Feature flag label selection (D-06)
- ArgoCD Helm chart version and minimal values configuration
- `prevent_destroy` placement on specific resources
- Additional infra outputs needed for Bridge Secret (subnet IDs, compartment OCID)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Existing Infrastructure
- `terraform/infra/main.tf` — Module orchestration, dependency graph, existing module calls
- `terraform/infra/modules/oci-iam/main.tf` — Current Dynamic Group + IAM policies (must be modified)
- `terraform/infra/outputs.tf` — Current outputs (must be extended for Bridge Secret)
- `terraform/infra/versions.tf` — Current providers + S3 backend config (must add Helm + k8s providers)
- `terraform/infra/variables.tf` — Current variables (may need new ones for bootstrap config)

### Design Specs
- `docs/superpowers/specs/2026-03-16-oci-oke-argocd-infra-design.md` — Original infrastructure design spec
- `docs/superpowers/plans/2026-03-16-oci-oke-argocd-infra.md` — Original implementation plan

### Research
- `.planning/research/ARCHITECTURE.md` — GitOps Bridge Pattern architecture, bridge secret schema, ApplicationSet pattern
- `.planning/research/PITFALLS.md` — OCI-specific pitfalls (Instance Principal, Workload Identity, sync waves)
- `.planning/research/STACK.md` — Recommended versions (ArgoCD 9.5.0/v3.3.6, ESO 2.2.0, etc.)

### Codebase Context
- `.planning/codebase/CONVENTIONS.md` — Naming conventions (assessforge- prefix), module structure patterns
- `.planning/codebase/STRUCTURE.md` — Directory layout, module organization

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `terraform/infra/modules/oci-iam/main.tf`: Dynamic Group + IAM policies already exist — modify matching rule, keep policy statements
- `terraform/infra/modules/oci-vault/main.tf`: GitHub OAuth secrets already stored in Vault — ESO will read these in Phase 2
- `terraform/infra/versions.tf`: S3 backend config already set up — add Helm + k8s providers here

### Established Patterns
- All modules follow `main.tf` + `variables.tf` + `outputs.tf` structure (no versions.tf for infra modules)
- Resource naming: `assessforge-<component>` prefix
- Terraform labels: short descriptive names, `main` for primary resource
- `freeform_tags` passed to all modules via local
- Dependencies declared via `depends_on` in root `main.tf`

### Integration Points
- New bootstrap module connects to: `module.oci_oke` (cluster endpoint, CA cert), `module.oci_vault` (vault OCID), `module.oci_network` (subnet IDs)
- Helm + Kubernetes providers need cluster auth — derive from OKE module outputs (exec-based kubeconfig or token)
- Bridge Secret annotations source from multiple module outputs — root `main.tf` wires them together

</code_context>

<specifics>
## Specific Ideas

- The existing `oci-iam` Dynamic Group is named `assessforge-workload-identity` — consider renaming to `assessforge-instance-principal` since it's no longer Workload Identity
- GitHub OAuth client ID/secret are passed as sensitive Terraform variables and stored in OCI Vault by the vault module — the Bridge Secret should NOT contain these, ESO will pull them in Phase 2
- The `helm_release` for ArgoCD must use `lifecycle { ignore_changes = all }` so Terraform doesn't fight with ArgoCD self-management in Phase 3

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-cleanup-iam-bootstrap*
*Context gathered: 2026-04-09*
