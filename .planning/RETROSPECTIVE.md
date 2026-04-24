# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v1.0 — AssessForge GitOps Bridge

**Shipped:** 2026-04-24
**Phases:** 3 | **Plans:** 8 | **Tasks:** 15 | **Quick tasks:** 7
**Git range:** `a3c76cb..9272a56` — 47 commits, 58 files changed, +7,208 / -92 lines

### What Was Built

- **Phase 1 · Cleanup & IAM Bootstrap** — Deleted never-applied `terraform/k8s/` layer; Instance Principal Dynamic Group + Vault-read IAM policy + VCN `prevent_destroy`; ArgoCD 9.5.0 via `helm_release` with GitOps Bridge Secret (labels + OCI metadata annotations) and root bootstrap Application; `lifecycle.ignore_changes = all` to enable self-management.
- **Phase 2 · GitOps Repository & ESO** — `gitops-setup` repo with matrix ApplicationSet (cluster × git); ESO 2.2.0 + ClusterSecretStore → OCI Vault; ExternalSecrets for GitHub OAuth + repo credentials; oci-vault module extended with `gitops_repo_pat`.
- **Phase 3 · ArgoCD Self-Management & Addons** — ArgoCD self-managed via `prune: false` Application, GitHub SSO (Dex), org-based default-deny RBAC, admin + exec disabled, hardened containers, sync-loop prevention via `ignoreDifferences`; Envoy Gateway (Gateway API v1) on free-tier 10 Mbps OCI Flexible LB; Let's Encrypt HTTP-01 via Gateway API solver for `argocd.assessforge.com`; metrics-server on ARM64 nodes.
- **Operational scaffolding** — Billing-cost alarm, multi-email notifications, bastion-tunnel runbook + `scripts/bastion-first-apply.sh`, OKE worker↔API-endpoint NSG fix, Cloud Shell private-network NSG + ingress rule, ArgoCD repo credential Secret for private gitops-setup.

### What Worked

- **GitOps Bridge handshake held first try** — Terraform-written Bridge Secret annotations consumed by the ApplicationSet matrix generator landed cleanly; zero broken flows across 10/10 integration checkpoints.
- **Pinning-everything discipline paid off** — all Helm charts and Terraform providers version-locked; reruns and disaster-recovery test applies produced identical plans (modulo the 4 cosmetic drifts catalogued in memory `project_terraform_plan_drifts.md`).
- **Security hardening up-front, not retrofit** — ArgoCD shipped with `admin.enabled=false`, `exec.enabled=false`, seccomp/runAsNonRoot/readOnly rootfs, and pod-security `restricted` on day one. Retroactive security audits closed 10/10 threats per phase with only documentation updates, not code changes.
- **Pre-ship milestone audit caught every gap** — the `/gsd-audit-milestone` run produced clean 36/36 requirements, 3/3 phases, 10/10 integration, 5/5 flows; tech debt (6 items) was identified and catalogued before close rather than discovered post-ship.
- **Stubbing Phase 3 addons during Phase 2** — Envoy Gateway / cert-manager / metrics-server Application manifests were scaffolded with placeholder `version` fields in Phase 2, which meant Phase 3 was pure values-file + manifest work instead of structural setup.

### What Was Inefficient

- **OCI IDCS `matching_rule` silent-drop bug** — burned the biggest time-sink of the milestone. ALL seven write paths (including Console, Terraform, every OCI CLI variant) silently drop `matching_rule` to `null`. Diagnosed via audit log + direct IDCS GET. Pivoted ESO to UserPrincipal + dedicated API key (commit `13e1b65`), which violates the `no static API keys` constraint as documented temporary debt (T6).
- **Bastion managed port-forward TLS stall** — TCP connects and session goes ACTIVE, but TLS ClientHello hangs on private OKE API. SNI ruled out. Three mitigation paths documented; ultimately worked around by applying from OCI Cloud Shell with private-network NSG ingress rule rather than fixing at the protocol layer.
- **Dex substitution chain debugging** — 5-hop pipeline (OCI Vault → ESO → K8s Secret → Dex envFrom → `$client_id`) with empty `client_id` was only diagnosable via curl-ing ArgoCD's `/api/dex/auth/github` to see the raw authorize URL. Spec contained the trap but debugging required live cluster probes.
- **Phase SUMMARY.md frontmatter schema drift** — custom schema didn't include `requirements_completed`, so the milestone audit's 3-source cross-reference degraded to 2 sources (VERIFICATION + traceability). Manual reconciliation required during archival.
- **`audit-open` false positives on completed quick tasks** — 7 quick tasks flagged `missing` because they lacked status files, even though all were complete per STATE.md with commit hashes. Required cross-checking STATE.md before trusting the audit (captured in memory `feedback_audit_open_false_positive.md`).
- **gsd-sdk `milestone.complete` handler is minimal** — the newer SDK handler just delegates to `phasesArchive` and errors without a version arg, requiring fallback to the richer `gsd-tools.cjs milestone complete` CLI.

### Patterns Established

- **GitOps Bridge pattern** — `kubernetes_secret` in `argocd` namespace with `argocd.argoproj.io/secret-type: cluster` label + addon feature-flag labels + OCI metadata annotations; matrix ApplicationSet reads it for dynamic addon materialization. This is now the repo's idiom for any future Terraform→ArgoCD handoff.
- **Self-management sync-loop prevention** — `lifecycle.ignore_changes = all` on the Terraform `helm_release` + `prune: false` on the self-managed Application + `ignoreDifferences` with `RespectIgnoreDifferences` on the ArgoCD Application. All three layers needed; removing any one causes drift or destruction.
- **ESO v1 API** — `external-secrets.io/v1` (not deprecated v1beta1), `namespaceSelector` at `spec` level (not in `conditions`), `ClusterSecretStore` scoped via `namespaceSelector` matchLabels to `argocd` only.
- **Gateway API HTTP-01 solver** — cert-manager's `gatewayHTTPRoute` solver (not `ingress`), cert auto-creation via `cert-manager.io/cluster-issuer` annotation on the Gateway, OCI LB bandwidth values as bare strings ("10") without units.
- **Bridge Secret = contract, not config** — annotations are *metadata* (compartment, vault, subnets); labels are *feature flags* (enable_<addon>); everything the AppSet needs must come from one Secret so operators can trace a single source.

### Key Lessons

1. **"Never static keys" is an OCI-policy aspiration, not a tooling guarantee.** The IDCS `matching_rule` bug made Instance Principal unusable in practice; accept that some OCI-specific workarounds will need a documented revert path rather than letting the ideal block shipping.
2. **Verify auth substitution chains end-to-end before claiming "wired".** The 5-hop Dex pipeline looked correct at every manifest boundary but produced empty `client_id`s at runtime. Add curl probes to integration tests for anything that crosses ESO → envFrom → app config.
3. **Pin every Helm chart at the Application manifest level, not values level.** `targetRevision` belongs in the Application source, not buried in a values file where review doesn't catch churn.
4. **Archived ingress-nginx stays archived.** When an upstream project is explicitly no-security-patches archived, swap it out *this* milestone, not a follow-up. The Envoy Gateway swap was cheap; deferring would have left the cluster on an unsupported ingress.
5. **`lifecycle.ignore_changes` on `helm_release` must be `all`, not `[values]`.** The narrowed form (`ignore_changes = [values]`) leaves chart-version diffs visible, which Terraform then tries to re-apply in conflict with ArgoCD self-management. Use `all` when ArgoCD owns the release.
6. **Audit trails beat audit commands.** `oci iam dynamic-group list` returns incomplete data on Identity Domains; the authoritative diagnostic is the audit log filtered via `jq` or a direct IDCS REST GET. Memory: `feedback_oci_diagnostic_techniques.md`.
7. **Post-2023 OCI tenancies need `'Default'/` prefix in policy statements referencing dynamic groups** or runtime resolution returns 404 — invisible at plan time, breaks only on actual auth attempts.

### Cost Observations

- **Model mix:** primarily Opus (planning, discuss, complex debugging) with Sonnet for executors and mappers; Haiku not used
- **Sessions:** 3 phases each spanning multiple sessions (context gathering → planning → execution → verify → UAT → security); ~15-20 sessions total across the milestone
- **Notable:** Biggest unplanned spend was the IDCS `matching_rule` investigation (diagnostic spelunking across audit log, OCI CLI quirks, and four write-path tests). Biggest savings came from stubbing Phase 3 addons during Phase 2 planning, which turned Phase 3 into values-file work rather than scaffolding.

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Sessions | Phases | Key Change |
|-----------|----------|--------|------------|
| v1.0 | ~18 | 3 | Initial milestone — established GitOps Bridge pattern, security-first ArgoCD baseline, and free-tier compliance discipline |

### Cumulative Quality

| Milestone | Requirements Shipped | Deferred by Design | Tech Debt Items | Security Threats Closed |
|-----------|----------------------|--------------------|-----------------|-------------------------|
| v1.0 | 35/36 | 1 (ESO-05) | 6 (all non-blocking) | 30/30 across 3 phases |

### Top Lessons (Verified Across Milestones)

*Requires 2+ milestones to establish cross-validation. Revisit after v1.1.*

1. (pending v1.1)
