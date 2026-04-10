---
phase: 02-gitops-repository-eso
plan: 01
subsystem: infra
tags: [argocd, gitops, eso, external-secrets, applicationset, helm, kubernetes]

# Dependency graph
requires:
  - phase: 01-cleanup-iam-bootstrap
    provides: oci-argocd-bootstrap module with Bridge Secret labels and root bootstrap Application
provides:
  - gitops-setup repository at ~/projects/AssessForge/gitops-setup with full directory scaffold
  - Matrix ApplicationSet (cluster x git generators) for addon discovery via Bridge Secret
  - ESO addon Application manifest referencing external-secrets 2.2.0
  - ArgoCD self-managed standalone Application with prune:false
  - Phase 3 stub manifests (envoy-gateway 1.4.0, cert-manager 1.20.1, metrics-server 3.13.0)
  - clusters/in-cluster/addons/eso/values.yaml with PLACEHOLDER_VAULT_OCID injection point
affects: [02-02, 02-03, phase-03]

# Tech tracking
tech-stack:
  added:
    - external-secrets Helm chart 2.2.0 (referenced in Application manifest)
    - argo-cd Helm chart 9.5.0 (self-managed Application)
    - envoy-gateway (gateway-helm) 1.4.0 from oci://docker.io/envoyproxy
    - cert-manager 1.20.1 from https://charts.jetstack.io
    - metrics-server 3.13.0 from https://kubernetes-sigs.github.io/metrics-server/
  patterns:
    - "GitOps Bridge Pattern: matrix ApplicationSet with cluster + git generators reads Bridge Secret annotations"
    - "Multi-source Application: values ref source + chart source with ignoreMissingValueFiles"
    - "Sync wave ordering: ESO=1, all others=3 for correct bootstrap sequence"
    - "ArgoCD self-managed: standalone Application outside ApplicationSet with prune:false"
    - "Convention-based addon discovery: directory name maps to Bridge Secret enable_* label"

key-files:
  created:
    - ~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cluster-addons-appset.yaml
    - ~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/eso/application.yaml
    - ~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml
    - ~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cert-manager/application.yaml
    - ~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/metrics-server/application.yaml
    - ~/projects/AssessForge/gitops-setup/bootstrap/control-plane/argocd/application.yaml
    - ~/projects/AssessForge/gitops-setup/clusters/in-cluster/addons/eso/values.yaml
    - ~/projects/AssessForge/gitops-setup/environments/default/addons/eso/values.yaml
    - ~/projects/AssessForge/gitops-setup/environments/default/addons/argocd/values.yaml
    - ~/projects/AssessForge/gitops-setup/environments/default/addons/{envoy-gateway,cert-manager,metrics-server}/values.yaml
  modified: []

key-decisions:
  - "Single matrix ApplicationSet (D-04) with cluster + git generators rather than per-addon ApplicationSets"
  - "ArgoCD self-managed Application is standalone with prune:false — NOT part of ApplicationSet (D-06)"
  - "Directory presence is the feature flag gate — all committed addon dirs generate Applications"
  - "Envoy Gateway uses OCI registry (oci://docker.io/envoyproxy), not HTTPS Helm repo"
  - "Sync wave 1 for ESO ensures operator exists before ClusterSecretStore/ExternalSecrets in Plan 02"

patterns-established:
  - "Multi-source Application: first source sets ref: values for valueFiles, second source references chart"
  - "Bootstrap/control-plane structure: addons/ for ApplicationSet + addon dirs, argocd/ sibling for self-managed"
  - "clusters/in-cluster/ layer: cluster-specific value overrides (Vault OCID injection point)"

requirements-completed: [REPO-01, REPO-02, REPO-03, REPO-04, ESO-01]

# Metrics
duration: 15min
completed: 2026-04-10
---

# Phase 02 Plan 01: GitOps Repository Scaffold Summary

**gitops-setup repository initialized with matrix ApplicationSet, ESO 2.2.0 addon manifest, ArgoCD self-managed Application (prune:false), and Phase 3 stubs for envoy-gateway/cert-manager/metrics-server**

## Performance

- **Duration:** ~15 min
- **Started:** 2026-04-10T00:00:00Z
- **Completed:** 2026-04-10
- **Tasks:** 2
- **Files modified:** 13 (all new in gitops-setup repo)

## Accomplishments

- Initialized `~/projects/AssessForge/gitops-setup` git repository with correct directory structure matching Bridge Secret label names
- Created single matrix ApplicationSet that reads Bridge Secret annotations (addons_repo_url, addons_repo_revision) and discovers addon directories via git generator
- Configured ESO Application with chart version 2.2.0, sync wave 1, multi-source values pattern
- Created ArgoCD standalone Application with prune:false (prevents ArgoCD from deleting itself during self-management)
- Created Phase 3 stubs for envoy-gateway (OCI registry), cert-manager, metrics-server with pinned versions
- Established clusters/in-cluster layer with PLACEHOLDER_VAULT_OCID injection point for operator substitution

## Task Commits

Commits are in the gitops-setup repo at `~/projects/AssessForge/gitops-setup`:

1. **Task 1: Initialize gitops-setup repository with directory scaffold** - `eed6c43` (feat)
2. **Task 2: Create ApplicationSet, addon Application manifests, and ArgoCD standalone Application** - `7ebb60a` (feat)

## Files Created/Modified

- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cluster-addons-appset.yaml` - Matrix ApplicationSet with cluster + git generators
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/eso/application.yaml` - ESO 2.2.0, sync-wave 1
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml` - Phase 3 stub, gateway-helm 1.4.0 (OCI registry), sync-wave 3
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cert-manager/application.yaml` - Phase 3 stub, 1.20.1, sync-wave 3
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/metrics-server/application.yaml` - Phase 3 stub, 3.13.0, sync-wave 3
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/argocd/application.yaml` - Standalone self-managed, 9.5.0, prune:false, sync-wave 3
- `~/projects/AssessForge/gitops-setup/clusters/in-cluster/addons/eso/values.yaml` - Vault OCID placeholder for post-terraform injection
- `~/projects/AssessForge/gitops-setup/environments/default/addons/eso/values.yaml` - installCRDs: true base config
- `~/projects/AssessForge/gitops-setup/environments/default/addons/{argocd,envoy-gateway,cert-manager,metrics-server}/values.yaml` - Phase 3 stubs

## Decisions Made

- Used single matrix ApplicationSet (D-04) rather than per-addon ApplicationSets for single-file maintenance
- ArgoCD self-managed placed at `bootstrap/control-plane/argocd/` (sibling of `addons/`), not inside the ApplicationSet to support unique prune:false requirement
- Envoy Gateway uses OCI registry source (`oci://docker.io/envoyproxy`) — no HTTPS Helm repo exists
- Feature flag gating (D-05) is implicit via directory presence; no separate filtering needed for Phase 2 since all labels are `"true"`

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Worktree branch was based on older commit (101ca75) instead of target (220104e). Applied `git reset --soft` to correct base before execution.

## Known Stubs

Phase 3 addon stubs with empty values — intentional per D-12:

| File | Stub Content | Resolved In |
|------|-------------|-------------|
| `environments/default/addons/envoy-gateway/values.yaml` | `{}` | Phase 3 |
| `environments/default/addons/cert-manager/values.yaml` | `{}` | Phase 3 |
| `environments/default/addons/metrics-server/values.yaml` | `{}` | Phase 3 |
| `environments/default/addons/argocd/values.yaml` | `{}` | Phase 3 |
| `clusters/in-cluster/addons/eso/values.yaml` | `PLACEHOLDER_VAULT_OCID` | Post-terraform apply by operator |

These stubs do NOT prevent the plan's goal (repository scaffold) from being achieved. They are intentional placeholders for Phase 3 configuration.

## Threat Flags

No new threat surface introduced — all files are static YAML manifests with no network endpoints, auth paths, or schema changes. The T-02-01/T-02-02/T-02-03 threats documented in the plan's threat model are addressed by: `targetRevision: main` (operator ensures branch protection), ApplicationSet limited to default ArgoCD project, no secrets in values files (PLACEHOLDER only, not actual values).

## Next Phase Readiness

- Plan 02 (ClusterSecretStore + ExternalSecrets) can proceed immediately — gitops repo scaffold is ready
- Plan 03 (Terraform infra changes for vault PAT secret) can proceed in parallel — no dependencies on Plan 02
- Operator action needed before ArgoCD can sync: replace PLACEHOLDER_VAULT_OCID in `clusters/in-cluster/addons/eso/values.yaml` after running `terraform output vault_ocid`

---

## Self-Check: PASSED

- `~/projects/AssessForge/gitops-setup/.git` exists: FOUND
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cluster-addons-appset.yaml` exists: FOUND
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/eso/application.yaml` exists: FOUND
- `~/projects/AssessForge/gitops-setup/bootstrap/control-plane/argocd/application.yaml` exists: FOUND
- `~/projects/AssessForge/gitops-setup/clusters/in-cluster/addons/eso/values.yaml` exists: FOUND
- gitops-setup commit eed6c43 (Task 1): FOUND
- gitops-setup commit 7ebb60a (Task 2): FOUND

---
*Phase: 02-gitops-repository-eso*
*Completed: 2026-04-10*
