# Roadmap: AssessForge GitOps Bridge

## Overview

Remove the never-applied `terraform/k8s/` code from the repository, then rebuild
Terraform to provision only IAM and bootstrap ArgoCD once. Create the gitops-setup
repository where ArgoCD self-manages and controls all cluster addons (ESO, Envoy
Gateway, cert-manager, metrics-server). After Phase 3 completes, every cluster change
flows exclusively through the GitOps repo via PRs — Terraform never touches in-cluster
resources again.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Cleanup & IAM Bootstrap** - Remove old k8s Terraform code and provision IAM + ArgoCD bootstrap
- [ ] **Phase 2: GitOps Repository & ESO** - Create gitops-setup repo with ApplicationSet and External Secrets Operator
- [ ] **Phase 3: ArgoCD Self-Management & Addons** - Wire ArgoCD self-management, Envoy Gateway, cert-manager, and metrics-server end-to-end

## Phase Details

### Phase 1: Cleanup & IAM Bootstrap
**Goal**: The old `terraform/k8s/` code is deleted from the repository, Terraform provisions IAM (Dynamic Group + Instance Principal policy), and ArgoCD is bootstrapped with the GitOps Bridge Secret and root Application — Terraform is done touching the cluster after this
**Depends on**: Nothing (first phase)
**Requirements**: MIG-01, MIG-02, IAM-01, IAM-02, IAM-03, IAM-04, BOOT-01, BOOT-02, BOOT-03, BOOT-04, BOOT-05
**Success Criteria** (what must be TRUE):
  1. The `terraform/k8s/` directory and all its child modules no longer exist in the repository
  2. OCI Dynamic Group scoped to OKE worker node instances exists and IAM Policy grants it Vault secret read access
  3. `terraform apply` completes with ArgoCD running in the cluster (ClusterIP service, no SSO configured yet)
  4. GitOps Bridge Secret exists in the argocd namespace with all required labels (addon feature flags) and annotations (compartment OCID, subnet IDs, vault OCID, region, environment)
  5. Root bootstrap ArgoCD Application resource exists and points at the gitops-setup repo; all provider and Helm chart versions are pinned
**Plans:** 2 plans
Plans:
- [x] 01-01-PLAN.md — Cleanup k8s directory, fix IAM Dynamic Group, add providers/variables/outputs
- [x] 01-02-PLAN.md — Create oci-argocd-bootstrap module and wire into root main.tf

### Phase 2: GitOps Repository & ESO
**Goal**: The gitops-setup repository exists with the correct directory structure, ApplicationSet reads the Bridge Secret to create addon Applications, and External Secrets Operator is deployed and connected to OCI Vault via Instance Principal
**Depends on**: Phase 1
**Requirements**: REPO-01, REPO-02, REPO-03, REPO-04, ESO-01, ESO-02, ESO-03, ESO-04, ESO-05, ESO-06
**Success Criteria** (what must be TRUE):
  1. `~/projects/AssessForge/gitops-setup` exists as a git repository with the expected directory structure (bootstrap, addons, apps directories)
  2. ApplicationSet syncs from the gitops-setup repo and creates per-addon Applications based on Bridge Secret labels
  3. ESO is deployed and healthy; ClusterSecretStore reports `Ready` connecting to OCI Vault using Instance Principal (no static API keys anywhere)
  4. ExternalSecrets for ArgoCD OAuth, repo credentials, and notification tokens sync successfully and create Kubernetes Secrets from OCI Vault
  5. All ESO manifests use `external-secrets.io/v1` API; all addon Helm chart versions are pinned
**Plans:** 3 plans
Plans:
- [ ] 02-01-PLAN.md — Initialize gitops-setup repo with directory scaffold, ApplicationSet, and addon Application manifests
- [ ] 02-02-PLAN.md — Create ClusterSecretStore and ExternalSecret manifests for OCI Vault
- [ ] 02-03-PLAN.md — Extend oci-vault Terraform module with GitHub PAT secret for repo credentials

### Phase 3: ArgoCD Self-Management & Addons
**Goal**: ArgoCD manages its own config via the GitOps repo, GitHub SSO is active, Envoy Gateway serves external HTTPS traffic, cert-manager issues a valid Let's Encrypt certificate, and metrics-server provides resource metrics
**Depends on**: Phase 2
**Requirements**: ARGO-01, ARGO-02, ARGO-03, ARGO-04, ARGO-05, GW-01, GW-02, GW-03, GW-04, GW-05, CERT-01, CERT-02, CERT-03, CERT-04, MS-01, MS-02
**Success Criteria** (what must be TRUE):
  1. ArgoCD self-managed Application exists with `prune: false`; updating Helm values via PR and merging causes ArgoCD to update its own config without Terraform involvement
  2. Logging in to ArgoCD at argocd.assessforge.com with a GitHub account in the AssessForge org succeeds; no local admin account is available
  3. `https://argocd.assessforge.com` loads with a valid Let's Encrypt TLS certificate (no browser warnings)
  4. Envoy Gateway is the active ingress path: GatewayClass, Gateway, and HTTPRoute for ArgoCD are all `Accepted` and traffic flows through the OCI Flexible Load Balancer
  5. `kubectl top nodes` and `kubectl top pods` return resource usage data
**UI hint**: yes
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Cleanup & IAM Bootstrap | 0/2 | Not started | - |
| 2. GitOps Repository & ESO | 0/3 | Not started | - |
| 3. ArgoCD Self-Management & Addons | 0/TBD | Not started | - |
