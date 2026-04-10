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

### Active

- [ ] Terraform creates OCI Dynamic Group + IAM Policy for ArgoCD Workload Identity
- [ ] Terraform installs ArgoCD via helm_release (minimal — no SSO, no repo config)
- [ ] Terraform creates GitOps Bridge Secret with infra annotations (compartment OCID, subnet IDs, vault OCID, region, environment, addon feature flags)
- [ ] Terraform creates root bootstrap Application pointing to gitops-setup repo
- [ ] Critical resources have `prevent_destroy = true` (cluster, VCN, state bucket)
- [ ] GitOps repo: ArgoCD self-managed Application (upgrades/config via PRs)
- [ ] GitOps repo: ArgoCD config via Helm values — GitHub SSO (Dex, org: AssessForge), RBAC, repo credentials — all secrets via ESO
- [ ] GitOps repo: ApplicationSet reading Bridge Secret annotations for dynamic addon creation
- [ ] GitOps repo: ingress-nginx with OCI Load Balancer annotations
- [ ] GitOps repo: cert-manager addon
- [ ] GitOps repo: external-secrets-operator with ClusterSecretStore pointing to OCI Vault via Workload Identity
- [ ] GitOps repo: metrics-server addon
- [ ] GitOps repo: ExternalSecret manifests for ArgoCD sensitive config (GitHub OAuth, repo creds, notification tokens)
- [ ] Existing `terraform/k8s/` layer destroyed and removed — ArgoCD takes over
- [ ] No static API keys or credentials in any Kubernetes Secret — all via OCI Workload Identity or OCI Vault + ESO

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
- **Identity**: OCI Workload Identity for all pod-level OCI API access — no static API keys
- **Secrets**: All sensitive values in OCI Vault, pulled by External Secrets Operator
- **Networking**: ArgoCD Server uses ClusterIP — ingress-nginx manages external access (installed via GitOps, not Terraform)
- **Versioning**: All Helm chart versions and Terraform provider versions must be pinned — no `latest` or open ranges
- **State**: Terraform remote state on OCI Object Storage (S3-compatible backend)
- **Protection**: Critical resources (cluster, VCN, state bucket) must have `prevent_destroy = true`
- **Boundary**: After bootstrap, no Kubernetes resource is managed by Terraform — changes go through GitOps repo only

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Destroy existing `terraform/k8s/` layer | Clean break — ArgoCD adopts resources fresh rather than complex state migration | — Pending |
| Single prod environment | Only one cluster needed now; multi-env is future scope | — Pending |
| GitOps Bridge Secret for metadata passing | Standard pattern for Terraform→ArgoCD handoff; annotations drive ApplicationSet | — Pending |
| OCI Workload Identity over static keys | Zero credential rotation burden, no secrets in cluster | — Pending |
| ArgoCD self-managed from day one | Prevents config drift; upgrades and config changes are PRs | — Pending |

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
*Last updated: 2026-04-09 after initialization*
