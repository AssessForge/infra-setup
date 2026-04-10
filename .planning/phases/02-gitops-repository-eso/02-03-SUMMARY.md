---
phase: 02-gitops-repository-eso
plan: 03
subsystem: infra
tags: [terraform, oci-vault, secrets, github-pat, hcl]

# Dependency graph
requires:
  - phase: 01-cleanup-iam-bootstrap
    provides: oci-vault module with KMS vault, master key, and existing GitHub OAuth secrets
provides:
  - oci_vault_secret.gitops_repo_pat resource in oci-vault module (secret_name=gitops-repo-pat)
  - gitops_repo_pat sensitive variable wired from root to oci-vault module
  - gitops_repo_pat_ocid output for downstream consumers
affects:
  - 02-02 (ExternalSecret in gitops-setup repo uses remoteRef.key=gitops-repo-pat to pull this secret)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "OCI Vault secret resource follows existing pattern: base64encode(var.X), secret_name matches ExternalSecret remoteRef.key exactly"
    - "Sensitive variable flows: root variables.tf -> root main.tf module block -> module variables.tf -> module main.tf resource"

key-files:
  created: []
  modified:
    - terraform/infra/modules/oci-vault/main.tf
    - terraform/infra/modules/oci-vault/variables.tf
    - terraform/infra/modules/oci-vault/outputs.tf
    - terraform/infra/main.tf
    - terraform/infra/variables.tf

key-decisions:
  - "secret_name=gitops-repo-pat must match ExternalSecret remoteRef.key exactly — case-sensitive OCI Vault lookup"
  - "No default value on gitops_repo_pat variable — operator must supply via terraform.tfvars before next apply"
  - "gitops_repo_pat_ocid output marked sensitive=true to prevent accidental exposure in plan output"

patterns-established:
  - "New Vault secrets: add resource to oci-vault/main.tf, variable to oci-vault/variables.tf, output to oci-vault/outputs.tf, wire in root main.tf and variables.tf"

requirements-completed: [ESO-04]

# Metrics
duration: 12min
completed: 2026-04-10
---

# Phase 02 Plan 03: GitHub PAT Secret in OCI Vault Summary

**New oci_vault_secret.gitops_repo_pat added to oci-vault module — sensitive variable wired root-to-module, secret_name matches ExternalSecret remoteRef.key exactly**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-10T18:00:00Z
- **Completed:** 2026-04-10T18:12:00Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Added `oci_vault_secret.gitops_repo_pat` resource following existing `github_oauth_client_secret` pattern exactly (BASE64 content, freeform_tags, Portuguese comment)
- Added `gitops_repo_pat` sensitive variable at both module and root levels with no default (required from terraform.tfvars)
- Added `gitops_repo_pat_ocid` output with `sensitive = true`
- Wired `gitops_repo_pat = var.gitops_repo_pat` in root `module "oci_vault"` block
- All HCL formatted (`terraform fmt -check` passes)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add GitHub PAT secret to oci-vault module** - `f649154` (feat)
2. **Task 2: Wire gitops_repo_pat variable from root to oci-vault module** - `6c995ae` (feat)
3. **Carry forward: Phase 1 terraform module fixes** - `c8feb03` (chore)

## Files Created/Modified

- `terraform/infra/modules/oci-vault/main.tf` - Added `oci_vault_secret.gitops_repo_pat` resource (secret_name=gitops-repo-pat)
- `terraform/infra/modules/oci-vault/variables.tf` - Added `gitops_repo_pat` variable with `sensitive = true`
- `terraform/infra/modules/oci-vault/outputs.tf` - Added `gitops_repo_pat_ocid` output with `sensitive = true`
- `terraform/infra/main.tf` - Added `gitops_repo_pat = var.gitops_repo_pat` to module "oci_vault" block
- `terraform/infra/variables.tf` - Added root `gitops_repo_pat` variable with `sensitive = true`, no default

## Decisions Made

- `secret_name = "gitops-repo-pat"` matches `remoteRef.key: gitops-repo-pat` in Plan 02's ExternalSecret manifest exactly — case-sensitive per OCI Vault lookup requirement
- No `default` on `gitops_repo_pat` — required variable, operator must add to `terraform.tfvars` before next `terraform apply`
- Output marked `sensitive = true` to suppress OCID from appearing in plan output

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Committed carry-forward of Phase 1 terraform module fixes**
- **Found during:** Pre-execution worktree branch check
- **Issue:** Worktree branch was based on documentation-only commit `220104e` which diverged from `origin/main` (code commits). Stashed changes from Phase 1 work (`oci-argocd-bootstrap`, `oci-cloud-guard`, `oci-network`, `oci-oke` modules, `versions.tf`) needed to be committed in this worktree to avoid losing prior work.
- **Fix:** After resetting to correct base `220104e` via `git reset --soft`, stashed changes were committed as `chore(02-03): carry forward Phase 1 terraform module fixes`
- **Files modified:** terraform/infra/modules/oci-argocd-bootstrap/main.tf, terraform/infra/modules/oci-argocd-bootstrap/versions.tf, terraform/infra/modules/oci-cloud-guard/main.tf, terraform/infra/modules/oci-network/main.tf, terraform/infra/modules/oci-oke/main.tf
- **Verification:** git status clean after commit; all Phase 1 fixes preserved
- **Committed in:** `c8feb03`

---

**Total deviations:** 1 auto-fixed (Rule 3 - blocking issue with worktree base)
**Impact on plan:** Carry-forward was necessary to preserve Phase 1 work. No scope creep on Plan 03 objectives.

## Issues Encountered

- Worktree branch `worktree-agent-a4deb785` was at commit `101ca75` (origin/main) rather than the target base `220104e` (planning branch). Required `git reset --soft` to correct base, then stash pop to recover the uncommitted changes. The stash contained valid Phase 1 code changes that were committed as a carry-forward chore commit.

## Known Stubs

None — no placeholder values, hardcoded empty returns, or TODO stubs introduced in this plan.

## Threat Surface

No new network endpoints, auth paths, or file access patterns introduced. The `gitops_repo_pat` variable is marked `sensitive = true` at both root and module levels per T-02-08 mitigation. Terraform state stores the base64-encoded PAT in OCI Object Storage bucket `assessforge-tfstate` (IAM-controlled) per T-02-09 mitigation.

## User Setup Required

**Operator must add `gitops_repo_pat` to `terraform/infra/terraform.tfvars` before next `terraform apply`:**

```hcl
gitops_repo_pat = "github_pat_xxxxxxxxxxxxxxxxxxxx"
```

Recommended: create a fine-grained GitHub PAT with read-only access to the `gitops-setup` repository only (T-02-10).

## Next Phase Readiness

- OCI Vault will store `gitops-repo-pat` secret after next `terraform apply`
- Plan 02 ExternalSecret (`external-secret-repo-creds.yaml`) references `remoteRef.key: gitops-repo-pat` — name matches exactly
- No blockers for Phase 02 plans 01 and 02 (gitops-setup repo creation and ArgoCD config manifests)

---
*Phase: 02-gitops-repository-eso*
*Completed: 2026-04-10*
