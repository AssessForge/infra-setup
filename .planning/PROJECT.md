# AssessForge GitOps Bridge

## What This Is

The GitOps Bridge Pattern is live on AssessForge's OCI/OKE infrastructure. Terraform provisions cloud resources (VCN, OKE, Vault, Cloud Guard, IAM) and performs a one-time ArgoCD bootstrap; the `~/projects/AssessForge/gitops-setup` repository then drives every in-cluster change — ArgoCD self-management, addons (ESO, Envoy Gateway, cert-manager, metrics-server), and future workloads — exclusively through Git PRs.

## Core Value

After bootstrap, every cluster change — addons, ArgoCD config, workloads — flows exclusively through the GitOps repository via PRs. Terraform never touches in-cluster resources again.

## Current State

- **Shipped version:** v1.0 — AssessForge GitOps Bridge (2026-04-24)
- **Cluster:** `assessforge-oke` in `sa-saopaulo-1`, BASIC tier, 2× VM.Standard.A1.Flex ARM nodes, private API endpoint
- **External access:** `https://argocd.assessforge.com` via Envoy Gateway → OCI Flexible LB (10 Mbps free tier) with Let's Encrypt TLS
- **GitOps repo:** `~/projects/AssessForge/gitops-setup` — matrix ApplicationSet driven by Bridge Secret labels/annotations
- **Secret flow:** OCI Vault → ESO (currently UserPrincipal; Instance Principal revert path retained) → K8s Secrets
- **Identity:** GitHub SSO via Dex (org: `AssessForge`), default-deny RBAC, admin + exec disabled

## Next Milestone Goals

Candidate directions for v1.1 (to be scoped via `/gsd-new-milestone`):

- **Policy & network controls** — Kyverno policies + NetworkPolicies via GitOps (deferred from v1 per POL-01/POL-02)
- **Observability stack** — Prometheus + Grafana + argocd-notifications (unlocks deferred ESO-05 notification tokens)
- **Tech-debt cleanup** — address the 6 items catalogued in `milestones/v1.0-MILESTONE-AUDIT.md` (Bridge-Secret annotation/label consumers, repo-creds unification, ClusterIssuer sync-wave race, HTTP-01 renewal verification, revert ESO to Instance Principal when the OCI IDCS `matching_rule` bug is fixed)
- **Multi-environment support** — ApplicationSet generators for dev/staging/prod once a non-prod cluster exists

## Requirements

### Validated

<details>
<summary>v1.0 (shipped 2026-04-24) — 35 requirements validated + 1 deferred by design</summary>

**Pre-existing infrastructure**

- ✓ OCI VCN with public/private subnets, NSGs — existing (`terraform/infra/modules/oci-network`)
- ✓ OCI IAM compartment and policies — existing (`terraform/infra/modules/oci-iam`)
- ✓ OKE cluster (BASIC, ARM, private API endpoint) — existing (`terraform/infra/modules/oci-oke`)
- ✓ OCI Vault for secrets — existing (`terraform/infra/modules/oci-vault`)
- ✓ OCI Cloud Guard — existing (`terraform/infra/modules/oci-cloud-guard`)
- ✓ Terraform remote state on OCI Object Storage (S3-compatible) — existing

**Phase 1 · Cleanup & IAM Bootstrap**

- ✓ MIG-01/MIG-02: `terraform/k8s/` layer and all old modules removed — v1.0
- ✓ IAM-01/IAM-02: Dynamic Group + Vault-read IAM policy for ESO — v1.0
- ✓ IAM-03/IAM-04: `prevent_destroy` on OKE/VCN/state bucket; 100% Always Free — v1.0
- ✓ BOOT-01/BOOT-02/BOOT-03: ArgoCD 9.5.0 via `helm_release`, Bridge Secret, root bootstrap Application — v1.0
- ✓ BOOT-04/BOOT-05: `lifecycle.ignore_changes = all` on helm_release; all versions pinned — v1.0

**Phase 2 · GitOps Repository & ESO**

- ✓ REPO-01/REPO-02/REPO-03/REPO-04: `gitops-setup` repo, matrix ApplicationSet, sync-wave ordering, pinned chart versions — v1.0
- ✓ ESO-01/ESO-02/ESO-03/ESO-04/ESO-06: ESO 2.2.0, ClusterSecretStore → OCI Vault, ExternalSecrets for GitHub OAuth + repo creds, `external-secrets.io/v1` API — v1.0

**Phase 3 · ArgoCD Self-Management & Addons**

- ✓ ARGO-01/ARGO-02/ARGO-03/ARGO-04/ARGO-05: self-managed Application (`prune: false`), GitHub SSO via Dex, org→admin default-deny RBAC, admin + exec disabled, repo creds via ExternalSecret — v1.0
- ✓ GW-01/GW-02/GW-03/GW-04/GW-05: Envoy Gateway, GatewayClass + Gateway + HTTPRoute, OCI Flexible LB 10 Mbps free tier — v1.0
- ✓ CERT-01/CERT-02/CERT-03/CERT-04: cert-manager, Let's Encrypt ClusterIssuer with Gateway API HTTP-01 solver, valid cert for `argocd.assessforge.com`, end-to-end TLS — v1.0
- ✓ MS-01/MS-02: metrics-server deployed; `kubectl top` returns data — v1.0

</details>

### Active

(None — v1.0 shipped; next milestone to be scoped via `/gsd-new-milestone`.)

### Deferred

- **ESO-05** — ExternalSecret for argocd-notification tokens. Deferred by design (D-08): argocd-notifications controller is out of v1 scope; revisit with observability milestone.

### Out of Scope

- **Multi-cluster / multi-environment support** — single prod cluster; premature abstraction until a second cluster exists
- **Application workload deployments** — this project is infrastructure + addons only; workloads belong to AssessForge product repos
- **ingress-nginx** — archived March 2026, no security patches; replaced by Envoy Gateway
- **OCI Workload Identity / OKE Enhanced tier** — paid feature; hard free-tier constraint
- **ArgoCD admin local account + exec-in-UI** — security risk; SSO-only, kubectl via Bastion
- **CI/CD pipeline for the GitOps repo** — manual PRs sufficient for now
- **`terraform destroy` for old k8s layer** — was never applied; code-only removal

## Context

- **Existing infra** (Terraform-managed, retained): VCN + public/private subnets + NSGs, OKE cluster (2× ARM nodes, private API endpoint), OCI Vault + master key, Cloud Guard, remote state on Object Storage (S3-compat), billing-cost alarm with multi-email notifications
- **In-cluster layer** (GitOps-managed as of v1.0): ArgoCD (self-managed), ESO, Envoy Gateway, cert-manager, metrics-server — all driven from `~/projects/AssessForge/gitops-setup` via ApplicationSet
- **GitOps Bridge Pattern**: Terraform writes cluster metadata (compartment, subnets, Vault OCID, region, environment) as annotations on a Kubernetes Secret in the `argocd` namespace; ArgoCD's ApplicationSet uses a cluster + git matrix generator to materialize per-addon Applications from that metadata
- **GitHub**: org `AssessForge`, OAuth app registered with callback `https://argocd.assessforge.com/api/dex/callback` (hardcoded — must match exactly)
- **Region**: `sa-saopaulo-1` (São Paulo)
- **DNS**: `argocd.assessforge.com` via Cloudflare; TLS issued by Let's Encrypt HTTP-01 through Gateway API solver
- **Known operational constraints**: OCI IDCS `matching_rule` bug forced a temporary UserPrincipal workaround for ESO auth (commit `13e1b65`); Bastion managed port-forward + private OKE API TLS handshake can stall — runbook at `scripts/bastion-first-apply.sh`
- **User applies from**: both laptop workspace and OCI Cloud Shell (`~/infra-setup/`), sharing the remote state backend

## Constraints

- **Cloud**: OCI only — all IAM, networking, and secrets use OCI-native services
- **Cost**: 100% OCI Always Free tier — never introduce paid resources
- **Identity**: OCI Instance Principal via Dynamic Groups for pod-level OCI API access — no static API keys (Workload Identity requires Enhanced tier which is paid); current UserPrincipal pivot is a documented temporary workaround for an OCI bug
- **Secrets**: All sensitive values in OCI Vault, pulled by External Secrets Operator
- **Networking**: ArgoCD Server uses ClusterIP — Envoy Gateway manages external access via Gateway API (installed via GitOps, not Terraform)
- **Versioning**: All Helm chart versions and Terraform provider versions must be pinned — no `latest` or open ranges
- **State**: Terraform remote state on OCI Object Storage (S3-compatible backend)
- **Protection**: Critical resources (cluster, VCN, state bucket) must have `prevent_destroy = true`
- **Boundary**: After bootstrap, no Kubernetes resource is managed by Terraform — changes go through GitOps repo only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Destroy existing `terraform/k8s/` layer | Clean break — ArgoCD adopts resources fresh rather than complex state migration | ✓ Good (v1.0 Phase 1 — code-only removal; layer was never applied) |
| Single prod environment | Only one cluster needed now; multi-env is future scope | ✓ Good (held through v1.0) |
| GitOps Bridge Secret for metadata passing | Standard pattern for Terraform→ArgoCD handoff; annotations drive ApplicationSet | ⚠️ Revisit (v1.0 Phase 1 — 5 annotations + addon feature-flag labels are written but unconsumed: T1, T2 in v1.0 audit) |
| Instance Principal over static keys | Zero credential rotation burden via Dynamic Groups; Workload Identity requires paid Enhanced tier | ⚠️ Revisit (v1.0 Phase 2 — pivoted to UserPrincipal per OCI IDCS `matching_rule` bug; revert path retained in commit `13e1b65`) |
| Envoy Gateway over ingress-nginx | ingress-nginx archived March 2026; Envoy Gateway is modern Gateway API standard | ✓ Good (v1.0 Phase 3) |
| HTTP-01 cert challenge via Gateway API solver | Simpler setup; no Cloudflare API token needed; Gateway API-native | ✓ Good (v1.0 Phase 3 — initial issuance verified; renewal path flagged for monitoring as T5) |
| 100% OCI Free Tier | Hard cost constraint; OKE stays BASIC, no Enhanced tier features | ✓ Good (validated across v1.0) |
| ArgoCD self-managed from day one | Prevents config drift; upgrades and config changes are PRs | ✓ Good (v1.0 Phase 3 — `ignoreDifferences` + `prune: false` + `lifecycle.ignore_changes` prevent sync loops) |
| D-08: Skip argocd-notifications + ESO-05 in v1 | Notifications controller is observability-tier scope; skip ExternalSecret until controller lands | ✓ Good (v1.0 — deferred by design) |
| Sync waves: ESO=1, secrets=2, rest=3 | Ensures CRDs/operator ready before CRs | ⚠️ Revisit (v1.0 Phase 3 — ClusterIssuer at wave 1 races cert-manager CRDs at wave 3; converges but noisy — T4) |
| Dedicated `argocd-repo-creds` via ESO alongside TF seed `gitops-setup-repo` | Two secrets coexist: Terraform seed for bootstrap, ESO-managed for steady state | ⚠️ Revisit (v1.0 — T3: unify usernames or document TF seed as bootstrap-only) |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-24 after v1.0 milestone*
