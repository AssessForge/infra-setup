# AssessForge GitOps Bridge

## What This Is

Adopt the GitOps Bridge Pattern for AssessForge's OCI/OKE infrastructure. Refactor the existing Terraform repository so it only provisions cloud resources and performs a one-time ArgoCD bootstrap, then create a new GitOps repository (`gitops-setup`) where ArgoCD manages itself, all cluster addons, and all workloads. After bootstrap, nothing inside the cluster is managed by Terraform — every change flows through Git PRs.

## Core Value

After bootstrap, every cluster change — addons, ArgoCD config, workloads — flows exclusively through the GitOps repository via PRs. Terraform never touches in-cluster resources again.

## Requirements

### Validated

- ✓ OCI VCN with public/private subnets, NSGs — existing (`terraform/infra/modules/oci-network`)
- ✓ OCI IAM compartment and policies — existing (`terraform/infra/modules/oci-iam`)
- ✓ OKE cluster (BASIC, ARM, private API endpoint) — existing (`terraform/infra/modules/oci-oke`)
- ✓ OCI Vault for secrets — existing (`terraform/infra/modules/oci-vault`)
- ✓ OCI Cloud Guard — existing (`terraform/infra/modules/oci-cloud-guard`)
- ✓ Terraform remote state on OCI Object Storage (S3-compatible) — existing
- ✓ IAM Dynamic Group + Instance Principal policy for ESO → OCI Vault — Validated in Phase 1
- ✓ ArgoCD installed via helm_release (minimal, ClusterIP, no SSO) — Validated in Phase 1
- ✓ GitOps Bridge Secret with infra annotations and addon feature flags — Validated in Phase 1
- ✓ Root bootstrap Application pointing to gitops-setup repo — Validated in Phase 1
- ✓ VCN `prevent_destroy = true` — Validated in Phase 1
- ✓ `terraform/k8s/` layer removed (never applied) — Validated in Phase 1

### Active

- ✓ GitOps repo created at ~/projects/AssessForge/gitops-setup — Validated in Phase 2
- ✓ GitOps repo: ArgoCD self-managed Application (upgrades/config via PRs, prune: false) — Validated in Phase 2
- ✓ GitOps repo: ArgoCD config via Helm values — GitHub SSO (Dex, org: AssessForge), RBAC, repo credentials — all secrets via ESO — Validated in Phase 3
- ✓ GitOps repo: ApplicationSet reading Bridge Secret annotations for dynamic addon creation — Validated in Phase 2
- ✓ GitOps repo: Envoy Gateway with Kubernetes Gateway API + OCI Load Balancer annotations — Validated in Phase 3
- ✓ GitOps repo: cert-manager addon with HTTP-01 Let's Encrypt ClusterIssuer — Validated in Phase 3
- ✓ GitOps repo: external-secrets-operator with ClusterSecretStore pointing to OCI Vault via Instance Principal — Validated in Phase 2
- ✓ GitOps repo: metrics-server addon — Validated in Phase 3
- ✓ GitOps repo: ExternalSecret manifests for ArgoCD sensitive config (GitHub OAuth, repo creds) — Validated in Phase 2 (ESO-05 notification tokens skipped per D-08)
- ✓ No static API keys or credentials in any Kubernetes Secret — all via Instance Principal (Dynamic Groups) or OCI Vault + ESO — Validated in Phase 2

### Out of Scope

- Multi-cluster / multi-environment support — single prod cluster for now
- Application workload deployments — this project is infrastructure and addons only
- Kyverno policies via GitOps — defer to future milestone
- Network policies via GitOps — defer to future milestone
- CI/CD pipeline for the GitOps repo — manual PRs for now
- Monitoring/observability stack (Prometheus, Grafana) — future milestone

## Context

- **Existing infra**: OCI VCN, OKE cluster (2x ARM nodes, private API), Vault, Cloud Guard — all provisioned via `terraform/infra/`
- **Existing k8s layer**: ArgoCD, external-secrets, ingress-nginx, kyverno, network-policies — all managed via `terraform/k8s/` (will be destroyed)
- **GitOps Bridge Pattern**: Terraform outputs infra metadata as Kubernetes Secret annotations in the argocd namespace. ArgoCD reads these annotations via ApplicationSet generators to dynamically configure addons with cluster-specific values
- **GitHub org**: AssessForge — OAuth app already registered for ArgoCD SSO
- **Region**: sa-saopaulo-1
- **Cluster**: BASIC tier, VM.Standard.A1.Flex (ARM), private API endpoint
- **DNS**: argocd.assessforge.com via Cloudflare
- **New repo**: `~/projects/AssessForge/gitops-setup` — to be created

## Constraints

- **Cloud**: OCI only — all IAM, networking, and secrets use OCI-native services
- **Cost**: 100% OCI Always Free tier — never introduce paid resources
- **Identity**: OCI Instance Principal via Dynamic Groups for pod-level OCI API access — no static API keys (Workload Identity requires Enhanced tier which is paid)
- **Secrets**: All sensitive values in OCI Vault, pulled by External Secrets Operator
- **Networking**: ArgoCD Server uses ClusterIP — Envoy Gateway manages external access via Gateway API (installed via GitOps, not Terraform)
- **Versioning**: All Helm chart versions and Terraform provider versions must be pinned — no `latest` or open ranges
- **State**: Terraform remote state on OCI Object Storage (S3-compatible backend)
- **Protection**: Critical resources (cluster, VCN, state bucket) must have `prevent_destroy = true`
- **Boundary**: After bootstrap, no Kubernetes resource is managed by Terraform — changes go through GitOps repo only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Destroy existing `terraform/k8s/` layer | Clean break — ArgoCD adopts resources fresh rather than complex state migration | ✓ Phase 1 |
| Single prod environment | Only one cluster needed now; multi-env is future scope | — Pending |
| GitOps Bridge Secret for metadata passing | Standard pattern for Terraform→ArgoCD handoff; annotations drive ApplicationSet | ✓ Phase 1 |
| Instance Principal over static keys | Zero credential rotation burden via Dynamic Groups; Workload Identity requires paid Enhanced tier | ✓ Phase 1 |
| Envoy Gateway over ingress-nginx | ingress-nginx archived March 2026; Envoy Gateway is modern Gateway API standard | ✓ Phase 3 |
| HTTP-01 cert challenge | Simpler setup; no Cloudflare API token needed | ✓ Phase 3 |
| 100% OCI Free Tier | Hard cost constraint; OKE stays BASIC, no Enhanced tier features | ✓ All phases |
| ArgoCD self-managed from day one | Prevents config drift; upgrades and config changes are PRs | ✓ Phase 3 |

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
*Last updated: 2026-04-10 after Phase 3 completion*
