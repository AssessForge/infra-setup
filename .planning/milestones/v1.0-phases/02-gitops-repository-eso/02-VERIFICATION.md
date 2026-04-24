---
phase: 02-gitops-repository-eso
verified: 2026-04-10T22:00:00Z
status: passed
score: 10/10 must-haves verified
overrides_applied: 0
human_verification: []
---

# Phase 2: GitOps Repository & ESO Verification Report

**Phase Goal:** The gitops-setup repository exists with the correct directory structure, ApplicationSet reads the Bridge Secret to create addon Applications, and External Secrets Operator is deployed and connected to OCI Vault via Instance Principal
**Verified:** 2026-04-10T22:00:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | gitops-setup repository exists with proper directory structure | VERIFIED | `.git/HEAD` exists with `ref: refs/heads/main`; bootstrap/, environments/, clusters/ directories all present with expected subdirectories |
| 2 | ApplicationSet uses matrix generator (cluster + git) to discover addon directories | VERIFIED | `cluster-addons-appset.yaml` contains `kind: ApplicationSet`, `goTemplate: true`, cluster generator with `argocd.argoproj.io/secret-type: cluster` selector, git generator with `path: bootstrap/control-plane/addons/*` |
| 3 | ESO Application manifest references external-secrets chart version 2.2.0 | VERIFIED | `eso/application.yaml` line 16: `targetRevision: '2.2.0'`, chart: `external-secrets`, repoURL: `https://charts.external-secrets.io` |
| 4 | All addon Application manifests have sync wave annotations (ESO=1, secrets=2, rest=3) | VERIFIED | ESO application: wave "1"; ClusterSecretStore + ExternalSecrets: wave "2"; envoy-gateway, cert-manager, metrics-server, ArgoCD: wave "3" |
| 5 | ArgoCD self-managed Application is standalone with prune: false, NOT in the ApplicationSet | VERIFIED | `argocd/application.yaml` at `bootstrap/control-plane/argocd/` (sibling of `addons/`, not inside it); contains `prune: false` |
| 6 | ClusterSecretStore connects to OCI Vault using Instance Principal (no static API keys) | VERIFIED | `cluster-secret-store.yaml` contains `principalType: InstancePrincipal`, no `serviceAccountRef`, no static credentials; `namespaceSelector` correctly at `spec:` level (not under `conditions:`); API version `external-secrets.io/v1` |
| 7 | ExternalSecret for GitHub OAuth maps to existing OCI Vault secret names exactly | VERIFIED | `external-secret-github-oauth.yaml` remoteRef keys: `github-oauth-client-id` and `github-oauth-client-secret` -- exact match to `secret_name` in `terraform/infra/modules/oci-vault/main.tf` lines 35, 51 |
| 8 | ExternalSecret for repo credentials includes repo-creds label and plaintext template data | VERIFIED | `external-secret-repo-creds.yaml` has label `argocd.argoproj.io/secret-type: repo-creds`; template.data uses plaintext: `type: "git"`, `url: "https://github.com/AssessForge"`, `username: "x-token"`; remoteRef key `gitops-repo-pat` matches Terraform `secret_name` |
| 9 | OCI Vault has gitops-repo-pat secret resource with sensitive variable wired root-to-module | VERIFIED | `oci-vault/main.tf` has `oci_vault_secret.gitops_repo_pat` with `secret_name = "gitops-repo-pat"`; `oci-vault/variables.tf` has `gitops_repo_pat` with `sensitive = true`; root `main.tf` passes `gitops_repo_pat = var.gitops_repo_pat`; root `variables.tf` declares it with `sensitive = true` |
| 10 | All ESO manifests use external-secrets.io/v1 API; all addon Helm chart versions are pinned | VERIFIED | Zero occurrences of `v1beta1` in bootstrap/; all charts pinned: ESO 2.2.0, ArgoCD 9.5.0, envoy-gateway 1.4.0, cert-manager 1.20.1, metrics-server 3.13.0 |

**Score:** 10/10 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gitops-setup/bootstrap/control-plane/addons/cluster-addons-appset.yaml` | Matrix ApplicationSet for addon discovery | VERIFIED | 44 lines, contains matrix generator with cluster + git generators |
| `gitops-setup/bootstrap/control-plane/addons/eso/application.yaml` | ESO addon Application manifest | VERIFIED | 32 lines, multi-source with values ref + chart, sync-wave 1 |
| `gitops-setup/bootstrap/control-plane/addons/eso/cluster-secret-store.yaml` | ClusterSecretStore pointing to OCI Vault | VERIFIED | 18 lines, Instance Principal, namespaceSelector at spec level |
| `gitops-setup/bootstrap/control-plane/addons/eso/external-secret-github-oauth.yaml` | ExternalSecret for argocd-dex-github-secret | VERIFIED | 24 lines, maps client_id and client_secret from Vault |
| `gitops-setup/bootstrap/control-plane/addons/eso/external-secret-repo-creds.yaml` | ExternalSecret for argocd-repo-creds | VERIFIED | 30 lines, repo-creds label, plaintext template, gitops-repo-pat key |
| `gitops-setup/bootstrap/control-plane/argocd/application.yaml` | ArgoCD self-managed standalone Application | VERIFIED | 31 lines, prune: false, chart 9.5.0, sync-wave 3 |
| `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml` | Phase 3 stub for Envoy Gateway | VERIFIED | 32 lines, gateway-helm 1.4.0 from OCI registry |
| `gitops-setup/bootstrap/control-plane/addons/cert-manager/application.yaml` | Phase 3 stub for cert-manager | VERIFIED | 32 lines, cert-manager 1.20.1 |
| `gitops-setup/bootstrap/control-plane/addons/metrics-server/application.yaml` | Phase 3 stub for metrics-server | VERIFIED | 31 lines, metrics-server 3.13.0 |
| `gitops-setup/clusters/in-cluster/addons/eso/values.yaml` | Cluster-specific ESO values with Vault OCID placeholder | VERIFIED | Contains `vault_ocid: "PLACEHOLDER_VAULT_OCID"` with instructions |
| `gitops-setup/environments/default/addons/eso/values.yaml` | ESO base values | VERIFIED | Contains `installCRDs: true` |
| `terraform/infra/modules/oci-vault/main.tf` | oci_vault_secret.gitops_repo_pat resource | VERIFIED | Lines 63-76, secret_name = "gitops-repo-pat", follows existing pattern |
| `terraform/infra/modules/oci-vault/variables.tf` | gitops_repo_pat variable definition | VERIFIED | Lines 18-22, sensitive = true |
| `terraform/infra/modules/oci-vault/outputs.tf` | gitops_repo_pat_ocid output | VERIFIED | Lines 16-20, sensitive = true |
| `terraform/infra/variables.tf` | Root-level gitops_repo_pat variable | VERIFIED | Lines 63-67, sensitive = true, no default |
| `terraform/infra/main.tf` | Module passes gitops_repo_pat | VERIFIED | Line 65: `gitops_repo_pat = var.gitops_repo_pat` in module "oci_vault" block |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `cluster-addons-appset.yaml` | Bridge Secret | `argocd.argoproj.io/secret-type: cluster` label selector | WIRED | Line 16: matchLabels contains the label |
| `cluster-addons-appset.yaml` | addon directories | git generator `bootstrap/control-plane/addons/*` | WIRED | Line 22: path pattern matches actual directory structure |
| `cluster-secret-store.yaml` | OCI Vault | `principalType: InstancePrincipal` | WIRED | Line 18: Instance Principal auth, Dynamic Group from Phase 1 |
| `cluster-secret-store.yaml` | argocd namespace | `spec.namespaceSelector` (top-level) | WIRED | Lines 11-13: namespaceSelector directly under spec, not under conditions |
| `external-secret-github-oauth.yaml` | OCI Vault secrets | remoteRef.key matches Terraform secret_name | WIRED | `github-oauth-client-id` and `github-oauth-client-secret` match exactly |
| `external-secret-repo-creds.yaml` | OCI Vault secret | remoteRef.key = `gitops-repo-pat` | WIRED | Matches `secret_name = "gitops-repo-pat"` in oci-vault/main.tf line 67 |
| `terraform/infra/main.tf` | oci-vault module | `gitops_repo_pat = var.gitops_repo_pat` | WIRED | Line 65 passes the variable to module |

### Data-Flow Trace (Level 4)

Not applicable -- this phase produces static YAML manifests and Terraform HCL. No runtime data rendering to trace. Data flow will be verified at runtime when the cluster is live.

### Behavioral Spot-Checks

Step 7b: SKIPPED (no runnable entry points -- code-only phase with static manifests and Terraform modules that require OCI credentials and a live cluster)

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| REPO-01 | 02-01 | New git repository with proper directory structure | SATISFIED | gitops-setup has .git/HEAD, bootstrap/control-plane/, environments/default/, clusters/in-cluster/ |
| REPO-02 | 02-01 | ApplicationSet with cluster generator reads Bridge Secret | SATISFIED | Matrix ApplicationSet with cluster + git generators, reads annotations for repo URL/revision |
| REPO-03 | 02-01 | Sync wave ordering ensures correct bootstrap sequence | SATISFIED | ESO=wave 1, secrets CRs=wave 2, all other addons + ArgoCD=wave 3 |
| REPO-04 | 02-01 | All addon Helm chart versions pinned | SATISFIED | ESO 2.2.0, ArgoCD 9.5.0, envoy-gateway 1.4.0, cert-manager 1.20.1, metrics-server 3.13.0 |
| ESO-01 | 02-01 | ESO addon deployed via GitOps with pinned chart version | SATISFIED | eso/application.yaml with chart external-secrets version 2.2.0 |
| ESO-02 | 02-02 | ClusterSecretStore with Instance Principal to OCI Vault | SATISFIED | cluster-secret-store.yaml with principalType: InstancePrincipal, namespace-restricted to argocd |
| ESO-03 | 02-02 | ExternalSecret for ArgoCD GitHub OAuth | SATISFIED | external-secret-github-oauth.yaml maps client_id + client_secret from correct Vault secrets |
| ESO-04 | 02-02, 02-03 | ExternalSecret for ArgoCD repository credentials | SATISFIED | external-secret-repo-creds.yaml with repo-creds label; gitops-repo-pat secret added to OCI Vault module |
| ESO-05 | N/A | ExternalSecret for notification tokens | SKIPPED (design decision) | D-08: no notification system in v1 scope; explicitly documented in plan |
| ESO-06 | 02-02 | All ExternalSecrets use external-secrets.io/v1 API | SATISFIED | Zero occurrences of v1beta1 across all ESO manifests |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `cluster-secret-store.yaml` | 16 | PLACEHOLDER_VAULT_OCID | Info | Intentional -- operator must substitute after terraform apply. Documented with instructions in comments. |
| `clusters/in-cluster/addons/eso/values.yaml` | 8 | PLACEHOLDER_VAULT_OCID | Info | Same as above -- injection point for cluster-specific Vault OCID |

No blockers or warnings found. The PLACEHOLDER values are intentional operator substitution points, not stubs.

### Human Verification Required

No human verification items identified. This is a code-only phase producing static manifests. Runtime behavior (SC 2-4: ApplicationSet syncing, ESO health, ExternalSecret sync) can only be verified after Phase 1 terraform apply creates the cluster. Those runtime validations are inherent to the deploy step, not this code phase.

### Gaps Summary

No gaps found. All 10 must-haves verified against actual codebase artifacts. Every requirement ID (REPO-01 through REPO-04, ESO-01 through ESO-06) is accounted for, with ESO-05 explicitly skipped per design decision D-08.

Key structural validations confirmed:
- ClusterSecretStore namespaceSelector is at the correct spec-level position (not under conditions)
- All ExternalSecret remoteRef.key values exactly match OCI Vault secret_name values in Terraform
- Repo credentials ExternalSecret uses plaintext template data (not base64)
- ArgoCD self-managed Application is outside the ApplicationSet with prune: false
- Variable wiring from root to oci-vault module is complete for gitops_repo_pat

---

_Verified: 2026-04-10T22:00:00Z_
_Verifier: Claude (gsd-verifier)_
