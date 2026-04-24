# Milestones

## v1.0 AssessForge GitOps Bridge (Shipped: 2026-04-24)

**Phases completed:** 3 phases, 8 plans, 15 tasks
**Git range:** `a3c76cb..9272a56` (47 commits, 58 files changed, +7,208 / -92 lines of HCL + YAML)
**Requirements:** 35/36 satisfied + 1 deferred by design (ESO-05 — argocd-notifications out of v1 scope per D-08)
**Tech debt catalogued:** 6 non-blocking items (see `milestones/v1.0-MILESTONE-AUDIT.md`)

**Key accomplishments:**

- **Phase 1 · Cleanup & IAM Bootstrap** — Deleted the never-applied `terraform/k8s/` layer; provisioned Instance Principal Dynamic Group + Vault-read IAM policy + `prevent_destroy` on VCN; bootstrapped ArgoCD 9.5.0 via `helm_release` with the GitOps Bridge Secret (addon feature-flag labels + OCI metadata annotations) and root bootstrap Application, using `lifecycle.ignore_changes = all` to enable self-management.
- **Phase 2 · GitOps Repository & ESO** — Created `gitops-setup` repo with matrix ApplicationSet (cluster × git generators) reading Bridge Secret annotations; deployed External Secrets Operator 2.2.0 with ClusterSecretStore → OCI Vault; stood up ExternalSecrets for GitHub OAuth + ArgoCD repo credentials; added `gitops_repo_pat` to the oci-vault module.
- **Phase 3 · ArgoCD Self-Management & Addons** — ArgoCD now self-manages via `prune: false` Application with GitHub SSO (Dex), org-based RBAC (default deny), admin + exec disabled, hardened containers, and sync-loop prevention via `ignoreDifferences`. Envoy Gateway (Gateway API v1) replaced ingress-nginx on a free-tier 10-Mbps OCI Flexible LB. cert-manager issued a valid Let's Encrypt certificate for `argocd.assessforge.com` via Gateway API HTTP-01 solver. metrics-server live on ARM64 nodes.
- **End-to-end GitOps Bridge boundary established** — After bootstrap, Terraform never touches an in-cluster resource: every addon, ArgoCD config change, and future workload flows exclusively through the `gitops-setup` repo via PRs. 10/10 cross-phase integration handshakes WIRED; 5/5 E2E UAT flows PASSED.
- **OCI-specific workarounds & ops safety nets** — Pivoted ESO to UserPrincipal + dedicated API key (commit `13e1b65`) to sidestep the IDCS `matching_rule` bug while preserving the Instance Principal revert path; added billing cost alarm, multi-email notifications, bastion-tunnel runbook + `scripts/bastion-first-apply.sh`, OKE worker↔API-endpoint NSG fix, Cloud Shell private-network NSG + ingress rule, and an ArgoCD repo credential Secret for the private gitops-setup.

---
