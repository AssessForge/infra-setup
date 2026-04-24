---
phase: 01
slug: cleanup-iam-bootstrap
status: verified
threats_open: 0
threats_total: 10
threats_closed: 10
asvs_level: 2
created: 2026-04-24
---

# Phase 01 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Operator workstation → OCI IAM | Terraform apply modifies IAM policies; operator must have IAM permissions | IAM policy statements |
| OKE worker nodes → OCI Vault | Instance Principal auth via Dynamic Group; matching rule controls scope | Vault secret reads |
| Kubeconfig file → K8s API | `~/.kube/config-assessforge` grants cluster access; must never be committed | K8s API credentials |
| Terraform → K8s cluster | Helm/kubectl providers write to cluster via kubeconfig; ArgoCD namespace + resources created | ArgoCD manifests, Bridge Secret |
| Bridge Secret annotations | Contain OCIDs (not auth material); readable by any pod in argocd namespace | OCID strings |
| Bootstrap Application | Points to external git repo (gitops-setup); controls what ArgoCD syncs | Git repo URL |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status | Evidence |
|-----------|----------|-----------|-------------|------------|--------|----------|
| T-01-01 | EoP | Dynamic Group matching rule | mitigate | Scope by `instance.compartment.id` | closed | `terraform/infra/modules/oci-iam/main.tf:22` — matching_rule restricts to compartment, not tenancy-wide |
| T-01-02 | Spoofing | Kubeconfig file | mitigate | `pathexpand()` + CLAUDE.md convention | closed | `terraform/infra/versions.tf:42-43` uses `pathexpand("~/.kube/config-assessforge")`; `CLAUDE.md:164` lists `**/config-assessforge` under "Files That Must Never Be Committed" |
| T-01-03 | Info Disclosure | ArgoCD admin password | accept | Phase 3 disables admin; ClusterIP only | closed | Accepted — see Accepted Risks |
| T-01-04 | DoS | DG rename IAM gap | accept | `create_before_destroy` minimizes window | closed | Accepted — see Accepted Risks |
| T-01-05 | Tampering | Terraform state file | mitigate | Remote state OCI Object Storage + `prevent_destroy` on critical resources | closed | Backend `terraform/infra/versions.tf:27-32` (bucket `assessforge-tfstate`); `prevent_destroy = true` on `oci_core_vcn.main` (network/main.tf:18), `oci_containerengine_cluster.main` (oke/main.tf:64), `oci_containerengine_node_pool.main` (oke/main.tf:142), `oci_kms_vault.main` (vault/main.tf:17), `oci_kms_key.master` (vault/main.tf:34) |
| T-01-06 | Tampering | gitops_repo_url in Bridge Secret | mitigate | Terraform variable with default AssessForge org | closed | `terraform/infra/variables.tf:51-55` — default `https://github.com/AssessForge/gitops-setup` |
| T-01-07 | Info Disclosure | Bridge Secret OCID values | accept | OCIDs are not auth material; cluster-internal | closed | Accepted — see Accepted Risks |
| T-01-08 | EoP | Bootstrap Application selfHeal=true | mitigate | `prune = false` + path scoped to `bootstrap/control-plane` | closed | `terraform/infra/modules/oci-argocd-bootstrap/main.tf:184` path; line 207 `prune = false`, line 208 `selfHeal = true` |
| T-01-09 | Spoofing | ArgoCD admin during bootstrap | accept | ClusterIP only; no external access | closed | Accepted — see Accepted Risks |
| T-01-10 | DoS | helm_release ignore_changes | accept | Intentional tradeoff for GitOps self-management | closed | Accepted — see Accepted Risks |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-01-01 | T-01-03 | ArgoCD admin credential exposure during bootstrap window only — no external access (ClusterIP), admin disabled via GitOps self-management in Phase 3 | Rodrigo Hernandez | 2026-04-09 |
| AR-01-02 | T-01-04 | Transient auth gap during Dynamic Group rename — `create_before_destroy` minimizes window; no live ESO workloads dependent at rename time | Rodrigo Hernandez | 2026-04-09 |
| AR-01-03 | T-01-07 | Bridge Secret OCIDs are not auth material; readable only by pods in argocd namespace; no external exposure | Rodrigo Hernandez | 2026-04-09 |
| AR-01-04 | T-01-09 | ArgoCD admin account during bootstrap is reachable only via ClusterIP (no external access); disabled via GitOps in Phase 3 before external exposure via Envoy Gateway | Rodrigo Hernandez | 2026-04-09 |
| AR-01-05 | T-01-10 | `helm_release.argocd` uses `ignore_changes = [values]` (plan originally specified `all`) — intentional tradeoff so ArgoCD self-manages via GitOps post-bootstrap; Terraform does not overwrite GitOps-applied values | Rodrigo Hernandez | 2026-04-09 |

*Accepted risks do not resurface in future audit runs.*

---

## Informational Findings

Non-blocking observations from the audit run:

- **`.gitignore` defense-in-depth gap:** `.gitignore` does not contain an explicit entry for `**/config-assessforge` or `*.kubeconfig`. Mitigation for T-01-02 is satisfied via `pathexpand` (writes outside repo tree) + CLAUDE.md convention, but adding the pattern to `.gitignore` would provide belt-and-suspenders protection if a kubeconfig is ever accidentally copied into the repo.
- **Plan deviation (T-01-10 related):** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:40` uses `ignore_changes = [values]` instead of the planned `ignore_changes = all`. Scoped to the accepted DoS tradeoff; does not affect any mitigated threat.
- **Out-of-scope IAM addition (informational):** `terraform/infra/modules/oci-iam/main.tf:76-120` adds a user-principal workaround (`oci_identity_user.eso_secrets_reader` + static API key) as a transitory mitigation for the OCI IDCS DRG `matching_rule` bug (see `project_oci_drg_matching_rule_bug.md`). This post-dates the Phase 1 plan threat model. Consider adding a dedicated threat (e.g., T-XX: static API key exposure / rotation) to a later phase's threat model when the workaround is revisited.

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-04-24 | 10 | 10 | 0 | gsd-security-auditor |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-04-24
