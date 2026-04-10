---
phase: 03-argocd-self-management-addons
plan: 01
subsystem: infra
tags: [argocd, dex, github-sso, rbac, helm, security-hardening, gitops]

# Dependency graph
requires:
  - phase: 02-gitops-repository-eso
    provides: "Stub ArgoCD Application manifest, ExternalSecret for GitHub OAuth, gitops repo structure"
provides:
  - "ArgoCD Helm values with GitHub SSO via Dex, org-based RBAC, security hardening"
  - "ArgoCD self-managed Application with ignoreDifferences for sync loop prevention"
affects: [03-02, 03-03]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dex envFrom pattern: ExternalSecret secretKey names become env var names for Dex connector"
    - "ignoreDifferences + RespectIgnoreDifferences for ArgoCD self-management sync loop prevention"

key-files:
  created: []
  modified:
    - "gitops-setup/environments/default/addons/argocd/values.yaml"
    - "gitops-setup/bootstrap/control-plane/argocd/application.yaml"

key-decisions:
  - "Used $client_id/$client_secret env var names matching ExternalSecret secretKey values exactly"
  - "Applied identical containerSecurityContext across all 5 ArgoCD components"

patterns-established:
  - "Security context pattern: runAsNonRoot, readOnlyRootFilesystem, drop ALL caps, seccomp RuntimeDefault on every component"
  - "RBAC pattern: org-wide admin with default deny (role:none)"

requirements-completed: [ARGO-01, ARGO-02, ARGO-03, ARGO-04, ARGO-05]

# Metrics
duration: 1min
completed: 2026-04-10
---

# Phase 3 Plan 1: ArgoCD Self-Management Summary

**ArgoCD Helm values with GitHub SSO via Dex, org-based RBAC (default deny), security-hardened containers, and ignoreDifferences to prevent self-management sync loops**

## Performance

- **Duration:** 1 min
- **Started:** 2026-04-10T18:52:42Z
- **Completed:** 2026-04-10T18:53:41Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Populated ArgoCD values.yaml with full Dex GitHub connector config using envFrom to inject OAuth credentials from ExternalSecret
- Configured RBAC with AssessForge org members as admin and default deny policy
- Applied security hardening to all 5 ArgoCD components (server, controller, repoServer, redis, dex) with resource limits
- Added ignoreDifferences for argocd-secret and RespectIgnoreDifferences syncOption to prevent self-management sync loops

## Task Commits

Each task was committed atomically:

1. **Task 1: Populate ArgoCD Helm values with SSO, RBAC, and security hardening** - `eb724f9` (feat)
2. **Task 2: Add ignoreDifferences to ArgoCD self-managed Application** - `d07db97` (feat)

## Files Created/Modified
- `gitops-setup/environments/default/addons/argocd/values.yaml` - Full ArgoCD Helm values with Dex SSO, RBAC, security contexts, resource limits, --insecure flag
- `gitops-setup/bootstrap/control-plane/argocd/application.yaml` - Added ignoreDifferences for argocd-secret and RespectIgnoreDifferences syncOption

## Decisions Made
None - followed plan as specified

## Deviations from Plan
None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- ArgoCD values ready for self-management via GitOps
- Envoy Gateway (plan 03-02) and cert-manager (plan 03-03) can proceed to configure external access and TLS

## Self-Check: PASSED

All files exist. All commits verified.

---
*Phase: 03-argocd-self-management-addons*
*Completed: 2026-04-10*
