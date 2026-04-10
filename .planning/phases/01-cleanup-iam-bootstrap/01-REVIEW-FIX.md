---
phase: 01-cleanup-iam-bootstrap
fixed_at: 2026-04-10T17:51:12Z
review_path: .planning/phases/01-cleanup-iam-bootstrap/01-REVIEW.md
iteration: 1
findings_in_scope: 6
fixed: 3
skipped: 3
status: partial
---

# Phase 01: Code Review Fix Report

**Fixed at:** 2026-04-10T17:51:12Z
**Source review:** .planning/phases/01-cleanup-iam-bootstrap/01-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 6 (2 Critical, 4 Warning)
- Fixed: 3
- Skipped: 3

## Fixed Issues

### WR-01: `prune = false` on root Application is undocumented and may orphan resources

**Files modified:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf`
**Commit:** b3764f1
**Applied fix:** Added inline Portuguese comments explaining the intent behind `prune = false` on the root bootstrap Application and noting that child ApplicationSets should configure `prune = true` individually.

### WR-03: `lifecycle { ignore_changes = all }` on `helm_release.argocd` permanently suppresses Terraform management

**Files modified:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf`
**Commit:** ac802b1
**Applied fix:** Narrowed `ignore_changes = all` to `ignore_changes = [values]` so Terraform can still detect and apply chart version upgrades while avoiding conflicts with ArgoCD self-management of Helm values. Updated comment to explain the rationale and recovery path (taint for version upgrades).

### WR-04: LB egress NSG rule targets subnet CIDR, not workers NSG -- overly broad scope

**Files modified:** `terraform/infra/modules/oci-network/main.tf`
**Commit:** 584c27a
**Applied fix:** Changed `lb_egress_workers` rule from `destination = var.private_subnet_cidr` / `destination_type = "CIDR_BLOCK"` to `destination = oci_core_network_security_group.workers.id` / `destination_type = "NETWORK_SECURITY_GROUP"`. This creates symmetric NSG-to-NSG pairing with the existing `workers_ingress_from_lb` rule, restricting LB egress to only worker nodes rather than the entire private subnet.

## Skipped Issues

### CR-01: Bootstrap module has no `versions.tf` -- providers are undeclared

**File:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:1`
**Reason:** Already fixed. The file `terraform/infra/modules/oci-argocd-bootstrap/versions.tf` already exists with the correct `required_providers` declarations for helm (~> 3.0), kubernetes (~> 3.0), and kubectl (~> 2.0). This fix was applied before the review ran (the file appears as untracked in git status).
**Original issue:** The module uses three providers but declares no `versions.tf` with `required_providers`.

### CR-02: Infra root `versions.tf` declares Helm/Kubernetes/kubectl providers -- breaks two-layer architecture

**File:** `terraform/infra/versions.tf:8-21`
**Reason:** Architectural refactoring beyond scope of code fix. The bootstrap module intentionally lives in the infra layer (it runs immediately after cluster creation via `depends_on = [module.oci_oke]`). The code already handles the Day-0 chicken-and-egg problem with a `fileexists()` conditional that sets `config_path = null` when the kubeconfig does not yet exist, allowing `terraform plan` to succeed before the cluster is created. Moving the module to `terraform/k8s/` would require restructuring the dependency chain and state references across layers. The current approach is a deliberate design choice that works correctly.
**Original issue:** Having Kubernetes provider blocks in the infra root means Terraform will try to read kubeconfig during every plan, even before the cluster exists.

### WR-02: ArgoCD chart version (9.5.0) conflicts with documented pinned version (7.6.12)

**File:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:7`
**Reason:** Documentation-only change. The chart version 9.5.0 is intentional (the bootstrap module is new code using ArgoCD v3.3.6). CLAUDE.md documents the old k8s-layer chart version (7.6.12) which will be removed as part of the GitOps migration. Updating CLAUDE.md is outside the scope of source code fixes and will be handled when the migration documentation is refreshed.
**Original issue:** The bootstrap module pins version 9.5.0 while CLAUDE.md documents 7.6.12 as the pinned version.

---

_Fixed: 2026-04-10T17:51:12Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
