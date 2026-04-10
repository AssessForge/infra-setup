---
phase: 02-gitops-repository-eso
plan: 02
subsystem: infra
tags: [external-secrets, oci-vault, instance-principal, argocd, kubernetes]

requires:
  - phase: 02-gitops-repository-eso/01
    provides: "gitops-setup repo with ESO addon directory structure"
  - phase: 02-gitops-repository-eso/03
    provides: "gitops-repo-pat secret in OCI Vault"
provides:
  - "ClusterSecretStore connecting to OCI Vault via Instance Principal"
  - "ExternalSecret for GitHub OAuth credentials (argocd-dex-github-secret)"
  - "ExternalSecret for ArgoCD repo credentials with repo-creds label"
affects: [phase-03-argocd-migration]

tech-stack:
  added: []
  patterns: ["ESO v1 API manifests", "Instance Principal auth for OCI Vault", "sync-wave 2 for CRs after CRDs"]

key-files:
  created:
    - "~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/eso/cluster-secret-store.yaml"
    - "~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/eso/external-secret-github-oauth.yaml"
    - "~/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/eso/external-secret-repo-creds.yaml"
  modified: []

key-decisions:
  - "ClusterSecretStore namespaceSelector at spec level (not conditions) per ESO v1 API"
  - "Repo creds use url: https://github.com/AssessForge as credential template for all org repos"
  - "PLACEHOLDER_VAULT_OCID requires operator substitution after terraform apply"
  - "ESO-05 (notification tokens) explicitly skipped — no notification system in v1"

patterns-established:
  - "ESO manifests use external-secrets.io/v1 API exclusively"
  - "Sync-wave 2 for ESO CRs ensures CRDs from wave 1 are installed first"
  - "Plaintext values in target.template.data — ESO handles base64 encoding"

requirements-completed: [ESO-02, ESO-03, ESO-04, ESO-06]

duration: 5min
completed: 2026-04-10
---

# Plan 02-02: ESO Secret Manifests Summary

**ClusterSecretStore with Instance Principal auth and two ExternalSecrets mapping OCI Vault credentials to ArgoCD namespace**

## Performance

- **Duration:** 5 min (inline execution after agent permission issue)
- **Started:** 2026-04-10T14:35:00-03:00
- **Completed:** 2026-04-10T14:40:00-03:00
- **Tasks:** 1
- **Files created:** 3

## Accomplishments
- ClusterSecretStore configured for OCI Vault with Instance Principal auth and argocd namespace restriction via spec.namespaceSelector
- ExternalSecret for GitHub OAuth maps client_id and client_secret from existing Vault secrets
- ExternalSecret for repo credentials includes argocd.argoproj.io/secret-type: repo-creds label with plaintext template values

## Task Commits

1. **Task 1: Create ClusterSecretStore and ExternalSecret manifests** - `ae35d70` (feat: add ClusterSecretStore and ExternalSecrets for OCI Vault)

## Files Created/Modified
- `bootstrap/control-plane/addons/eso/cluster-secret-store.yaml` - ClusterSecretStore with Instance Principal, namespace-restricted to argocd
- `bootstrap/control-plane/addons/eso/external-secret-github-oauth.yaml` - ExternalSecret for ArgoCD Dex GitHub OAuth credentials
- `bootstrap/control-plane/addons/eso/external-secret-repo-creds.yaml` - ExternalSecret for ArgoCD repo credentials with PAT from Vault

## Decisions Made
- Used spec.namespaceSelector (top-level, not under conditions) per ESO v1 API — silent failure if placed under conditions
- Repo credentials URL set to https://github.com/AssessForge (org-level credential template matching all repos)
- PLACEHOLDER_VAULT_OCID left as operator substitution point — ClusterSecretStore is a standalone CR, not templated by ApplicationSet
- ESO-05 (notification tokens) explicitly skipped per D-08 — no notification system in v1 scope

## Deviations from Plan
None - plan executed exactly as written

## Issues Encountered
- Subagent could not write files to gitops-setup repo due to permission restrictions in worktree isolation — executed inline by orchestrator instead

## User Setup Required
None - Vault OCID placeholder documented inline for post-terraform-apply substitution.

## Next Phase Readiness
- All ESO manifests ready for deployment after ArgoCD bootstrap
- Vault OCID substitution required before ESO can connect to OCI Vault
- GitHub PAT must be added to terraform.tfvars before terraform apply

---
*Phase: 02-gitops-repository-eso*
*Completed: 2026-04-10*
