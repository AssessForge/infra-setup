---
phase: 02-gitops-repository-eso
fixed_at: 2026-04-10T12:15:00Z
review_path: .planning/phases/02-gitops-repository-eso/02-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 2: Code Review Fix Report

**Fixed at:** 2026-04-10T12:15:00Z
**Source review:** .planning/phases/02-gitops-repository-eso/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: Infra module `oci-argocd-bootstrap` has its own `versions.tf` -- violates project convention

**Files modified:** `terraform/infra/modules/oci-argocd-bootstrap/versions.tf`
**Commit:** 8793f3d
**Applied fix:** Deleted `versions.tf` from the infra module entirely. Per CLAUDE.md convention, infra modules inherit providers from the root `terraform/infra/versions.tf`. No other infra module has a `versions.tf`.

### WR-01: ESO CRDs may not exist when ClusterSecretStore and ExternalSecrets are applied during bootstrap

**Files modified:** `bootstrap/control-plane/addons/eso/cluster-secret-store.yaml` (gitops-setup repo)
**Commit:** 86b3447 (in gitops-setup repo)
**Applied fix:** Added comment block explaining that during initial bootstrap, this resource may fail temporarily until ESO (sync-wave 1) finishes registering its CRDs, and that selfHeal ensures automatic convergence.

### WR-02: Addon Applications hardcode repo URL and revision instead of using Bridge Secret annotations

**Files modified:** `bootstrap/control-plane/addons/eso/application.yaml`, `bootstrap/control-plane/argocd/application.yaml`, `bootstrap/control-plane/addons/envoy-gateway/application.yaml`, `bootstrap/control-plane/addons/cert-manager/application.yaml`, `bootstrap/control-plane/addons/metrics-server/application.yaml` (gitops-setup repo)
**Commit:** fbcfa79 (in gitops-setup repo)
**Applied fix:** Added comment to all 5 application.yaml files documenting that repoURL and targetRevision are hardcoded because standalone Application manifests cannot reference Bridge Secret annotations, and that changing the repo or branch requires updating all application.yaml files manually.

### WR-03: `gitops_repo_pat_ocid` output unnecessarily marked as sensitive

**Files modified:** `terraform/infra/modules/oci-vault/outputs.tf`
**Commit:** e8157ac
**Applied fix:** Removed `sensitive = true` from the `gitops_repo_pat_ocid` output. OCIDs are resource identifiers, not credentials -- knowing a Vault secret's OCID does not grant access to the secret's contents.

---

_Fixed: 2026-04-10T12:15:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
