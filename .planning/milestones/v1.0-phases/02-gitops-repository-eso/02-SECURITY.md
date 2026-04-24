---
phase: 02
slug: gitops-repository-eso
status: verified
threats_open: 0
threats_total: 10
threats_closed: 10
asvs_level: 2
created: 2026-04-24
---

# Phase 02 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| Git repo → ArgoCD | ArgoCD auto-syncs manifests from `gitops-setup` — malicious manifest = cluster compromise | Kubernetes manifests |
| ESO pod → OCI Vault API | Instance Principal / User Principal authenticates via metadata; secrets cross network boundary | Vault secret reads |
| OCI Vault → K8s Secret | Secrets materialized in argocd namespace; any pod in that namespace could read them | Dex OAuth creds, GitHub PAT |
| Operator workstation → OCI Vault | GitHub PAT value crosses from local terraform.tfvars into OCI Vault via Terraform apply | Sensitive PAT |

---

## Threat Register

| Threat ID | Category | Component | Disposition | Mitigation | Status | Evidence |
|-----------|----------|-----------|-------------|------------|--------|----------|
| T-02-01 | Tampering | gitops-setup repo | mitigate | `targetRevision: main` in all Application manifests; ApplicationSet uses Bridge-Secret-templated revision (defaults to main); GitHub branch protection is operator responsibility | closed | gitops-setup `bootstrap/control-plane/addons/*/application.yaml:15` all pin `targetRevision: 'main'`; `cluster-addons-appset.yaml:31` uses `{{.metadata.annotations.addons_repo_revision}}` |
| T-02-02 | EoP | ApplicationSet template | accept | Limited to default ArgoCD project; runs with ArgoCD's SA | closed | Accepted — see Accepted Risks |
| T-02-03 | Info Disclosure | values.yaml files | mitigate | No secrets in git — all credentials via OCI Vault + ESO; values contain only non-sensitive config | closed | All 6 values.yaml files scanned; only Helm config (`installCRDs`, `resources`, `securityContext`, Dex `$client_id`/`$client_secret` ENV var substitution refs, RBAC CSV). No plaintext tokens/passwords/keys. |
| T-02-04 | Info Disclosure | ClusterSecretStore | mitigate | `spec.conditions[].namespaceSelector` restricts secret creation to argocd namespace only | closed | gitops-setup `bootstrap/control-plane/addons/eso/cluster-secret-store.yaml:24-27` — `conditions[].namespaceSelector.matchLabels.kubernetes.io/metadata.name: argocd` |
| T-02-05 | Spoofing | ESO → Vault auth | mitigate | DG matching rule scoped to OKE workers (Phase 1 T-01-01); read-only `secret-family` policy; pivoted to dedicated `eso_secrets_reader` User Principal as IDCS matching-rule bug workaround | closed | Cross-ref Phase 1 T-01-01 (verified); `cluster-secret-store.yaml:5-7` uses `UserPrincipal` auth with dedicated user; see memory `project_oci_drg_matching_rule_bug.md` |
| T-02-06 | Info Disclosure | ExternalSecret repo-creds | mitigate | GitHub PAT in OCI Vault (not git); K8s Secret restricted to argocd namespace; PAT scope = operator responsibility (T-02-10) | closed | gitops-setup `bootstrap/control-plane/addons/eso/external-secret-repo-creds.yaml:29-30` — `remoteRef.key: gitops-repo-pat` (name only, no inline value); `metadata.namespace: argocd` |
| T-02-07 | Tampering | ExternalSecret manifests in git | mitigate | ExternalSecrets reference only `remoteRef.key` names — actual secret values never appear in git | closed | Grep across `bootstrap/control-plane/addons/` — zero matches for `ghp_`, `ghs_`, `github_pat_`, `AKIA`, `BEGIN PRIVATE/RSA`. All ExternalSecrets reference only Vault secret names |
| T-02-08 | Info Disclosure | gitops_repo_pat variable | mitigate | `sensitive = true` in root + module; `*.tfvars` in `terraform/.gitignore` | closed | `terraform/infra/variables.tf:63-67` and `terraform/infra/modules/oci-vault/variables.tf:18-22` both `sensitive = true`; `terraform/.gitignore:9` excludes `*.tfvars` |
| T-02-09 | Info Disclosure | Terraform state | mitigate | Remote state OCI Object Storage S3 backend; Vault + master key `prevent_destroy` + AES-256 encryption at rest | closed | Backend `terraform/infra/versions.tf:27-32` (bucket `assessforge-tfstate`); `terraform/infra/modules/oci-vault/main.tf:16-18` vault `prevent_destroy`, `:33-35` master key `prevent_destroy`, `:28-31` AES-256 |
| T-02-10 | EoP | GitHub PAT scope | accept | Operator responsibility — recommend fine-grained read-only PAT on gitops-setup repo | closed | Accepted — see Accepted Risks |

*Status: open · closed*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-02-01 | T-02-02 | ApplicationSet runs in argocd namespace with ArgoCD's ServiceAccount; it can only create Applications in allowed projects (default project has no cluster-level resource write). Elevation limited to Application-type resources in-scope of existing ArgoCD RBAC | Rodrigo Hernandez | 2026-04-10 |
| AR-02-02 | T-02-10 | Operator chooses PAT scope; no automated enforcement of fine-grained scoping. Recommendation documented (read-only on AssessForge/gitops-setup only). Periodic rotation is operator responsibility | Rodrigo Hernandez | 2026-04-10 |

*Accepted risks do not resurface in future audit runs.*

---

## Informational Findings

Non-blocking observations from the 2026-04-24 audit run:

- **Plan-vs-code deviation on T-02-04 mechanism:** Plan 02-02 body specified `spec.namespaceSelector` (top-level) and forbade `conditions:`. The delivered manifest uses `spec.conditions[].namespaceSelector` — both ESO v1-valid, both restrict to argocd. The threat register verify pattern ("has conditions with namespaceSelector") matches the delivered code, so T-02-04 is closed. Reconcile the plan prose if referenced elsewhere.
- **Missing `sensitive = true` on `gitops_repo_pat_ocid` output:** Plan 02-03 required the OCID output to be marked sensitive. Delivered `modules/oci-vault/outputs.tf:16-19` omits it. Low severity (OCIDs are identifiers, not secrets), not covered by a registered threat, noted for operator awareness.
- **T-02-05 auth pivot (documented):** ESO authentication was pivoted from Instance Principal to User Principal (`eso_secrets_reader` + dedicated API key, commit 13e1b65) as a transitory workaround for the IDCS `matching_rule` bug. Read-only security property is preserved but via a different mechanism than the Phase 2 plan specified. See `project_oci_drg_matching_rule_bug.md`. When OCI fixes the bug and the workaround is reverted, the mitigation mechanism returns to Instance Principal per original plan.

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
