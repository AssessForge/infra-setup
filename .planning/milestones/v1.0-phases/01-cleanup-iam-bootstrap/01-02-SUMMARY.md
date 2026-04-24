---
phase: 01-cleanup-iam-bootstrap
plan: 02
subsystem: terraform/infra/modules/oci-argocd-bootstrap
tags: [argocd, gitops-bridge, bootstrap, helm, kubernetes-secret]
dependency_graph:
  requires:
    - Plan 01-01 (Helm/Kubernetes/kubectl providers, gitops_repo_url/gitops_repo_revision variables)
    - module.oci_oke (cluster must exist for Helm provider to connect)
    - module.oci_vault (vault_ocid needed for Bridge Secret annotation)
    - module.oci_network (subnet IDs needed for Bridge Secret annotations)
  provides:
    - helm_release.argocd (ArgoCD 9.5.0, ClusterIP, self-managed via ignore_changes=all)
    - kubernetes_secret.gitops_bridge (Bridge Secret with feature flags + OCI metadata)
    - kubectl_manifest.bootstrap_app (root Application pointing to gitops-setup repo)
    - module "oci_argocd_bootstrap" call wired into terraform/infra/main.tf
  affects:
    - terraform/infra/modules/oci-argocd-bootstrap/ (new module, 3 files)
    - terraform/infra/main.tf (bootstrap module call added)
tech_stack:
  added:
    - ArgoCD Helm chart 9.5.0 (argo-cd from argoproj.github.io/argo-helm)
    - GitOps Bridge Secret pattern (kubernetes_secret with argocd cluster generator labels)
    - kubectl_manifest for ArgoCD Application CRD (deferred schema validation)
  patterns:
    - lifecycle { ignore_changes = all } on helm_release to enable ArgoCD self-management
    - Bridge Secret with addon feature flag labels (enable_eso, enable_envoy_gateway, etc.)
    - OCI metadata annotations (oci_region, oci_compartment_ocid, oci_vault_ocid, subnet IDs)
    - kubectl_manifest over kubernetes_manifest for CRDs not yet registered at plan time
key_files:
  created:
    - terraform/infra/modules/oci-argocd-bootstrap/main.tf
    - terraform/infra/modules/oci-argocd-bootstrap/variables.tf
    - terraform/infra/modules/oci-argocd-bootstrap/outputs.tf
  modified:
    - terraform/infra/main.tf
decisions:
  - "kubectl_manifest (alekc/kubectl) used for bootstrap Application instead of kubernetes_manifest — ArgoCD Application CRD is not registered at plan time, kubernetes_manifest validates schema at plan time and would fail; kubectl_manifest defers validation to apply time"
  - "lifecycle { ignore_changes = all } on helm_release.argocd is mandatory — prevents Terraform from fighting ArgoCD self-management after initial bootstrap; all post-bootstrap changes go through GitOps repo"
  - "prune = false on bootstrap Application syncPolicy — prevents ArgoCD from auto-deleting resources; safer for bootstrap, full pruning enabled via GitOps repo after validation"
  - "ArgoCD chart 9.5.0 pinned (app v3.3.6) per BOOT-05 constraint — no latest or open ranges"
  - "ClusterIP service type for ArgoCD server — Envoy Gateway manages external access via Gateway API (Phase 3 plan), not LoadBalancer directly"
metrics:
  duration: "~5 minutes"
  completed_date: "2026-04-10T02:10:00Z"
  tasks_completed: 2
  files_modified: 1
  files_created: 3
---

# Phase 01 Plan 02: ArgoCD Bootstrap Module Summary

**One-liner:** ArgoCD 9.5.0 installed via Helm with GitOps Bridge Secret (feature flags + OCI metadata) and root bootstrap Application pointing to gitops-setup repo, with `lifecycle { ignore_changes = all }` enabling self-management.

## What Was Built

### Task 1: Create oci-argocd-bootstrap module

Created `terraform/infra/modules/oci-argocd-bootstrap/` with three files (no `versions.tf` — providers inherited from root per convention):

**`main.tf` — Three resources:**

1. **`helm_release.argocd`** (BOOT-01, BOOT-04, BOOT-05):
   - Chart `argo-cd` version `9.5.0` from `https://argoproj.github.io/argo-helm`
   - Namespace `argocd`, `create_namespace = true`, `wait = true`, `timeout = 600`
   - Helm values: `server.service.type = "ClusterIP"`, `--insecure` extraArgs, `server.exec.enabled = "false"`
   - `lifecycle { ignore_changes = all }` — mandatory for ArgoCD self-management post-bootstrap

2. **`kubernetes_secret.gitops_bridge`** (BOOT-02, D-05, D-06, D-07):
   - Name: `in-cluster`, namespace: `argocd`
   - Labels: `argocd.argoproj.io/secret-type = "cluster"`, `environment = "prod"`, `cluster_name`, five addon feature flags (`enable_argocd`, `enable_eso`, `enable_envoy_gateway`, `enable_cert_manager`, `enable_metrics_server`)
   - Annotations: `addons_repo_url`, `addons_repo_revision`, `oci_region`, `oci_compartment_ocid`, `oci_vault_ocid`, `oci_public_subnet_id`, `oci_private_subnet_id`
   - Data: `name = "in-cluster"`, `server = "https://kubernetes.default.svc"`, `config` with JSON `tlsClientConfig`

3. **`kubectl_manifest.bootstrap_app`** (BOOT-03):
   - ArgoCD `Application` kind, name `bootstrap`, namespace `argocd`
   - `spec.source.path = "bootstrap/control-plane"`, repoURL and targetRevision from variables
   - `syncPolicy.automated.prune = false`, `selfHeal = true`
   - `syncOptions = ["CreateNamespace=true", "ServerSideApply=true"]`
   - `depends_on = [helm_release.argocd, kubernetes_secret.gitops_bridge]`

**`variables.tf`:** compartment_ocid, region, vault_ocid, public_subnet_id, private_subnet_id, gitops_repo_url, gitops_repo_revision, cluster_name (default: assessforge-oke), freeform_tags

**`outputs.tf`:** `argocd_namespace` — value from `helm_release.argocd.namespace`

**Commit:** `35d5f17`

### Task 2: Wire bootstrap module into root main.tf

Added `module "oci_argocd_bootstrap"` block to `terraform/infra/main.tf` after `module "oci_vault"`:

- All variable mappings wired: `compartment_ocid = var.compartment_ocid`, `region = var.region`, `vault_ocid = module.oci_vault.vault_ocid`, both subnet IDs from `module.oci_network`, gitops vars from root variables, `freeform_tags = local.freeform_tags`
- `depends_on = [module.oci_oke, module.oci_vault]` — cluster must exist for Helm/k8s providers; Vault must exist for vault_ocid annotation
- Portuguese comment header: `# --- Bootstrap ArgoCD (depende de OKE + Vault) ---`

**Commit:** `00b8e69`

## Deviations from Plan

### Worktree State Restoration

**Found during:** Startup
**Issue:** After `git reset --soft 6cf03e4`, the working tree still reflected the OLD pre-Plan-01-01 branch code (old `versions.tf` without Helm/k8s/kubectl providers, old `variables.tf` without gitops vars, `terraform/k8s/` still present). The `git reset --soft` only moves HEAD; working tree and index retain prior state.
**Fix:** Used `git checkout 6cf03e4 -- terraform/infra/versions.tf terraform/infra/variables.tf terraform/infra/outputs.tf terraform/infra/modules/oci-iam/main.tf terraform/infra/modules/oci-iam/outputs.tf terraform/infra/modules/oci-network/main.tf terraform/infra/main.tf` to restore Plan 01-01 state, then `git rm -r --cached terraform/k8s/` + `rm -rf` to delete it, then restored `.planning/` and `CLAUDE.md` from base commit.
**Classification:** Rule 3 — Auto-fix blocking issue (working tree inconsistency prevented plan execution)

## Known Stubs

None. All resources are fully wired with real variable references. The `PLACEHOLDER` in the S3 backend endpoint is intentional and pre-existing — requires operator-specific value at apply time, documented in README.

## Threat Flags

Reviewed against plan `<threat_model>`:

- T-01-06 (Tampering — gitops_repo_url): `gitops_repo_url` is a Terraform variable with default pointing to `AssessForge/gitops-setup`; changes require explicit `terraform apply` with variable override. Mitigated as planned.
- T-01-08 (EoP — bootstrap Application selfHeal=true): `prune = false` prevents auto-deletion. Application scoped to `bootstrap/control-plane` path only. Mitigated as planned.
- T-01-09 (Spoofing — ArgoCD admin during bootstrap): Accepted per plan. ClusterIP means no external access. Admin disabled via GitOps in Phase 3.
- T-01-10 (DoS — ignore_changes preventing fixes): Accepted per plan. Intentional tradeoff.

No new trust boundaries introduced beyond what the plan's threat model covers.

## Self-Check

Files verified to exist:
- terraform/infra/modules/oci-argocd-bootstrap/main.tf: FOUND
- terraform/infra/modules/oci-argocd-bootstrap/variables.tf: FOUND
- terraform/infra/modules/oci-argocd-bootstrap/outputs.tf: FOUND
- terraform/infra/modules/oci-argocd-bootstrap/versions.tf: NOT FOUND (correct — per convention, infra modules inherit providers from root)
- terraform/infra/main.tf (module call added): FOUND

Commits verified:
- 35d5f17: Task 1 — oci-argocd-bootstrap module (3 files)
- 00b8e69: Task 2 — wire into root main.tf

## Self-Check: PASSED
