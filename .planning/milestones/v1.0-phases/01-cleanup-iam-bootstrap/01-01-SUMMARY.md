---
phase: 01-cleanup-iam-bootstrap
plan: 01
subsystem: terraform/infra
tags: [iam, vcn, providers, cleanup, migration]
dependency_graph:
  requires: []
  provides:
    - Instance Principal Dynamic Group (assessforge-instance-principal)
    - IAM policy for worker nodes to read OCI Vault secrets
    - VCN prevent_destroy protection
    - Helm/Kubernetes/kubectl providers in terraform/infra
    - gitops_repo_url and gitops_repo_revision variables
    - compartment_ocid, public_subnet_id, private_subnet_id outputs
  affects:
    - terraform/infra/modules/oci-iam/ (IAM resources renamed and fixed)
    - terraform/infra/modules/oci-network/ (VCN protected)
    - terraform/infra/versions.tf (new providers)
    - terraform/infra/variables.tf (new GitOps variables)
    - terraform/infra/outputs.tf (new subnet/compartment outputs)
tech_stack:
  added:
    - hashicorp/helm ~> 3.0 provider
    - hashicorp/kubernetes ~> 3.0 provider
    - alekc/kubectl ~> 2.0 provider
  patterns:
    - Instance Principal via Dynamic Group (resource.type = 'instance')
    - prevent_destroy lifecycle on critical OCI resources
    - create_before_destroy for IAM gap-free rename
key_files:
  modified:
    - terraform/infra/modules/oci-iam/main.tf
    - terraform/infra/modules/oci-iam/outputs.tf
    - terraform/infra/modules/oci-network/main.tf
    - terraform/infra/versions.tf
    - terraform/infra/variables.tf
    - terraform/infra/outputs.tf
  deleted:
    - terraform/k8s/ (entire directory, 25 files)
decisions:
  - "Instance Principal (resource.type = 'instance') chosen over Workload Identity — BASIC tier OKE does not support Workload Identity (requires Enhanced tier, which is paid)"
  - "create_before_destroy on Dynamic Group minimizes IAM gap during resource rename"
  - "terraform/k8s/ deleted via git rm — never applied to cluster, no terraform destroy needed"
  - "Helm provider v3.x uses kubernetes = {} object assignment syntax, not block syntax"
metrics:
  duration: "~3 minutes"
  completed_date: "2026-04-10T01:48:13Z"
  tasks_completed: 2
  files_modified: 6
  files_deleted: 25
---

# Phase 01 Plan 01: Cleanup IAM and Bootstrap Prep Summary

**One-liner:** Instance Principal Dynamic Group fix (resource.type = 'instance'), VCN protect, Helm/k8s/kubectl providers, plus full terraform/k8s/ removal.

## What Was Built

### Task 1: Fix IAM, add VCN protection, extend providers/variables/outputs

**IAM Dynamic Group fix (IAM-01, IAM-02):**
- Renamed `oci_identity_dynamic_group.workload_identity` to `oci_identity_dynamic_group.instance_principal`
- Dynamic Group name changed from `assessforge-workload-identity` to `assessforge-instance-principal`
- Matching rule changed from `resource.type = 'workload'` to `resource.type = 'instance'` scoped by `instance.compartment.id` — correct for BASIC tier OKE
- Added `create_before_destroy = true` lifecycle to minimize IAM gap during rename
- IAM policy renamed to `assessforge-instance-principal-vault-policy`
- Policy statements updated to reference renamed Dynamic Group

**VCN protection (IAM-03):**
- Added `lifecycle { prevent_destroy = true }` to `oci_core_vcn.main`
- VCN joins OKE cluster, node pool, Vault, and master key as protected resources

**Provider declarations (BOOT-05):**
- Added `hashicorp/helm ~> 3.0`, `hashicorp/kubernetes ~> 3.0`, `alekc/kubectl ~> 2.0` to `required_providers`
- Added `provider "helm"` with `kubernetes = { config_path = ... }` (object assignment — Helm v3 syntax)
- Added `provider "kubernetes"` and `provider "kubectl"` blocks pointing to `~/.kube/config-assessforge`

**Variables and outputs for Plan 02:**
- Added `gitops_repo_url` (default: `https://github.com/AssessForge/gitops-setup`)
- Added `gitops_repo_revision` (default: `main`)
- Added outputs: `compartment_ocid`, `public_subnet_id`, `private_subnet_id`

**Commit:** `24f4db3`

### Task 2: Delete terraform/k8s/ directory

- Removed entire `terraform/k8s/` directory (25 files) via `git rm -r`
- Includes: main.tf, versions.tf, variables.tf, outputs.tf, terraform.tfvars.example
- Modules deleted: argocd, external-secrets, ingress-nginx, kyverno, network-policies
- No `terraform destroy` needed — code was never applied to the cluster
- Git history preserves the code

**Commit:** `c17edf6`

## Deviations from Plan

### Worktree Branch Correction

**Found during:** Startup
**Issue:** Worktree HEAD was at `713cef9` (existing codebase) instead of the planning branch base `42f318e`. After `git reset --soft` to the correct base, git staged all `.planning/` files and `CLAUDE.md` as deletions (they existed in the base commit but not in the old worktree HEAD).
**Fix:** After Task 1 commit, restored `.planning/` and `CLAUDE.md` from base commit `42f318e` via `git checkout 42f318e -- .planning/ CLAUDE.md` and committed the restoration.
**Commit:** `ef1427c`
**Classification:** Rule 3 — Auto-fix blocking issue (branch state inconsistency)

## Known Stubs

None. All changes are complete infrastructure definitions with no placeholder values except the pre-existing `PLACEHOLDER` in the S3 backend endpoint (intentional — requires operator-specific value at apply time, documented in existing README).

## Threat Flags

No new network endpoints, auth paths, file access patterns, or schema changes introduced beyond what the plan's threat model covers. The Dynamic Group scope change (T-01-01) reduces the attack surface compared to the original `resource.type = 'workload'` rule.

## Self-Check

Files verified to exist:
- terraform/infra/modules/oci-iam/main.tf: FOUND
- terraform/infra/modules/oci-iam/outputs.tf: FOUND
- terraform/infra/modules/oci-network/main.tf: FOUND
- terraform/infra/versions.tf: FOUND
- terraform/infra/variables.tf: FOUND
- terraform/infra/outputs.tf: FOUND
- terraform/k8s/: DELETED (confirmed via test ! -d)

Commits verified:
- 24f4db3: Task 1 — IAM/VCN/providers/vars/outputs
- ef1427c: Restore planning files
- c17edf6: Task 2 — Delete terraform/k8s/

## Self-Check: PASSED
