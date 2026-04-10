# Requirements: AssessForge GitOps Bridge

**Defined:** 2026-04-09
**Core Value:** After bootstrap, every cluster change flows exclusively through the GitOps repository via PRs. Terraform never touches in-cluster resources again.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Infrastructure & IAM

- [ ] **IAM-01**: Terraform creates OCI Dynamic Group scoped to OKE worker node instances for Instance Principal authentication
- [ ] **IAM-02**: Terraform creates IAM Policy granting Dynamic Group read access to OCI Vault secrets
- [ ] **IAM-03**: Critical Terraform resources (OKE cluster, VCN, state bucket) have `prevent_destroy = true`
- [ ] **IAM-04**: Every OCI resource used is verified as OCI Always Free tier eligible before implementation

### Terraform Bootstrap

- [ ] **BOOT-01**: Terraform installs ArgoCD via `helm_release` with minimal values (no SSO, no repo config, ClusterIP service)
- [ ] **BOOT-02**: Terraform creates GitOps Bridge Secret in argocd namespace with labels (addon feature flags: `enable_<addon>`) and annotations (compartment OCID, subnet IDs, vault OCID, region, environment)
- [ ] **BOOT-03**: Terraform creates root bootstrap Application resource pointing to gitops-setup repo
- [ ] **BOOT-04**: Terraform `helm_release` for ArgoCD uses `lifecycle { ignore_changes = all }` to prevent conflict with self-management
- [ ] **BOOT-05**: All Terraform provider versions and Helm chart versions are pinned — no `latest` or open ranges

### Migration

- [ ] **MIG-01**: Existing `terraform/k8s/` layer is destroyed cleanly (state removed, resources deleted from cluster)
- [ ] **MIG-02**: Old k8s modules (argocd, external-secrets, ingress-nginx, kyverno, network-policies) are removed from the repository
- [ ] **MIG-03**: OCI Flexible Load Balancer is released during destroy so it's available for Envoy Gateway

### GitOps Repository

- [ ] **REPO-01**: New git repository created at `~/projects/AssessForge/gitops-setup` with proper directory structure
- [ ] **REPO-02**: ApplicationSet with cluster generator reads Bridge Secret labels/annotations to dynamically create per-addon Applications
- [ ] **REPO-03**: Sync wave ordering ensures correct bootstrap sequence (ESO first, then gateway/cert-manager, then ArgoCD self-managed, then metrics-server)
- [ ] **REPO-04**: All addon Helm chart versions are pinned in Application manifests

### ArgoCD Self-Management

- [ ] **ARGO-01**: ArgoCD self-managed Application in gitops-setup repo (upgrades and config changes via PRs, `prune: false`)
- [ ] **ARGO-02**: GitHub SSO via Dex configured in Helm values (org: AssessForge, OAuth app credentials via ESO)
- [ ] **ARGO-03**: RBAC configured — AssessForge org members get admin role, default policy denies access
- [ ] **ARGO-04**: ArgoCD admin local account disabled, exec disabled
- [ ] **ARGO-05**: ArgoCD repo credentials stored as ExternalSecret (pulled from OCI Vault)

### External Secrets Operator

- [ ] **ESO-01**: ESO addon deployed via GitOps with pinned Helm chart version
- [ ] **ESO-02**: ClusterSecretStore configured pointing to OCI Vault using Instance Principal (Dynamic Group) authentication
- [ ] **ESO-03**: ExternalSecret for ArgoCD GitHub OAuth client ID/secret (`argocd-dex-github-secret`)
- [ ] **ESO-04**: ExternalSecret for ArgoCD repository credentials
- [ ] **ESO-05**: ExternalSecret for ArgoCD notification tokens (if applicable)
- [ ] **ESO-06**: All ExternalSecrets use `external-secrets.io/v1` API (not deprecated v1beta1)

### Envoy Gateway

- [ ] **GW-01**: Envoy Gateway addon deployed via GitOps with Kubernetes Gateway API
- [ ] **GW-02**: OCI Load Balancer annotations configured (flexible shape, free tier 10 Mbps bandwidth)
- [ ] **GW-03**: GatewayClass and Gateway resources created for the cluster
- [ ] **GW-04**: HTTPRoute for ArgoCD Server configured (replacing old Ingress resource)
- [ ] **GW-05**: OCI LB verified as free tier eligible (1 flexible LB included in Always Free)

### cert-manager

- [ ] **CERT-01**: cert-manager addon deployed via GitOps with pinned Helm chart version
- [ ] **CERT-02**: ClusterIssuer configured for Let's Encrypt with HTTP-01 challenge solver
- [ ] **CERT-03**: Certificate resource for ArgoCD domain (argocd.assessforge.com)
- [ ] **CERT-04**: TLS termination working end-to-end (LB → Envoy Gateway → ArgoCD with valid cert)

### metrics-server

- [ ] **MS-01**: metrics-server addon deployed via GitOps with pinned Helm chart version
- [ ] **MS-02**: `kubectl top nodes` and `kubectl top pods` return data after deployment

## v2 Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Policy & Network

- **POL-01**: Kyverno policies managed via GitOps (currently Terraform-managed, will be destroyed)
- **POL-02**: Network policies managed via GitOps (currently Terraform-managed, will be destroyed)

### Observability

- **OBS-01**: Prometheus deployed via GitOps for cluster monitoring
- **OBS-02**: Grafana deployed via GitOps for dashboards

### Automation

- **AUTO-01**: CI/CD pipeline for gitops-setup repo (linting, diff preview on PRs)
- **AUTO-02**: ArgoCD notifications (Slack/Discord) for sync status

### Multi-Environment

- **ENV-01**: Multi-cluster ApplicationSet support (dev/staging/prod)
- **ENV-02**: Per-environment values file override chain

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| OCI Workload Identity | Requires Enhanced tier (paid) — use Instance Principal instead |
| OKE Enhanced tier upgrade | Paid feature — project is 100% free tier |
| Application workload deployments | This milestone is infrastructure/addons only |
| Monitoring stack (Prometheus, Grafana) | Significant scope — dedicated future milestone |
| Multi-cluster support | Single prod cluster; premature abstraction |
| CI/CD for GitOps repo | Manual PRs sufficient for now |
| ArgoCD admin local account | Security risk — SSO only |
| ArgoCD exec (terminal in UI) | Security risk — use kubectl via Bastion |
| ingress-nginx | Archived March 2026, no security patches — replaced by Envoy Gateway |
| Any paid OCI resource | Hard constraint — 100% Always Free tier |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| IAM-01 | TBD | Pending |
| IAM-02 | TBD | Pending |
| IAM-03 | TBD | Pending |
| IAM-04 | TBD | Pending |
| BOOT-01 | TBD | Pending |
| BOOT-02 | TBD | Pending |
| BOOT-03 | TBD | Pending |
| BOOT-04 | TBD | Pending |
| BOOT-05 | TBD | Pending |
| MIG-01 | TBD | Pending |
| MIG-02 | TBD | Pending |
| MIG-03 | TBD | Pending |
| REPO-01 | TBD | Pending |
| REPO-02 | TBD | Pending |
| REPO-03 | TBD | Pending |
| REPO-04 | TBD | Pending |
| ARGO-01 | TBD | Pending |
| ARGO-02 | TBD | Pending |
| ARGO-03 | TBD | Pending |
| ARGO-04 | TBD | Pending |
| ARGO-05 | TBD | Pending |
| ESO-01 | TBD | Pending |
| ESO-02 | TBD | Pending |
| ESO-03 | TBD | Pending |
| ESO-04 | TBD | Pending |
| ESO-05 | TBD | Pending |
| ESO-06 | TBD | Pending |
| GW-01 | TBD | Pending |
| GW-02 | TBD | Pending |
| GW-03 | TBD | Pending |
| GW-04 | TBD | Pending |
| GW-05 | TBD | Pending |
| CERT-01 | TBD | Pending |
| CERT-02 | TBD | Pending |
| CERT-03 | TBD | Pending |
| CERT-04 | TBD | Pending |
| MS-01 | TBD | Pending |
| MS-02 | TBD | Pending |

**Coverage:**
- v1 requirements: 37 total
- Mapped to phases: 0
- Unmapped: 37 ⚠️

---
*Requirements defined: 2026-04-09*
*Last updated: 2026-04-09 after initial definition*
