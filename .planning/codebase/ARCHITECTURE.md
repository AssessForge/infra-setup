# Architecture

**Analysis Date:** 2026-04-09

## System Overview

This project provisions the complete infrastructure for the AssessForge platform on Oracle Cloud Infrastructure (OCI). It creates a Kubernetes cluster (OKE) with a GitOps-based deployment pipeline (ArgoCD), secret management (OCI Vault + External Secrets Operator), ingress routing (nginx), and security hardening (Kyverno policies, NetworkPolicies, Cloud Guard).

The infrastructure is split into two independent Terraform root modules that run sequentially:

1. **`terraform/infra/`** -- provisions OCI cloud resources (VCN, IAM, OKE cluster, Vault, Cloud Guard)
2. **`terraform/k8s/`** -- provisions Kubernetes-level services on top of the OKE cluster (ingress-nginx, ESO, ArgoCD, Kyverno, NetworkPolicies)

The k8s layer reads the infra layer's state via `terraform_remote_state` data source, creating a one-way dependency.

## Layer Diagram

```
                         +----------------------------+
                         |     DNS (Cloudflare)       |
                         |  argocd.assessforge.com    |
                         +-------------+--------------+
                                       |
                         +-------------v--------------+
                         |    OCI Load Balancer        |
                         |    (Flexible 10Mbps)        |
                         |    Public Subnet 10.0.1.0/24|
                         +-------------+--------------+
                                       |
                    +------------------v------------------+
                    |         ingress-nginx               |
                    |         (ns: ingress-nginx)         |
                    +------------------+-----------------+
                                       |
           +---------------------------+---------------------------+
           |                           |                           |
   +-------v-------+          +-------v-------+           +-------v-------+
   |   ArgoCD       |          |   Dex (OIDC)  |           |   ESO          |
   |   (ns: argocd) |          |   (ns: argocd)|           |   (ns: ext-sec)|
   +-------+-------+          +-------+-------+           +-------+-------+
           |                           |                           |
           |                   +-------v-------+           +-------v-------+
           |                   |  GitHub OAuth  |           |  OCI Vault     |
           |                   |  (external)    |           |  (infra layer) |
           |                   +---------------+           +---------------+
           |
   +-------v-------+
   |  Git Repos     |
   |  (GitHub)      |
   +---------------+

   +---------------------------------------------------------+
   |  OKE Cluster (BASIC) -- Private API Endpoint            |
   |  2x VM.Standard.A1.Flex (2 OCPU, 12GB RAM each)        |
   |  Private Subnet 10.0.2.0/24                             |
   |  Pods CIDR: 10.244.0.0/16  Services CIDR: 10.96.0.0/16 |
   +---------------------------------------------------------+
   |  NSGs: api-endpoint, workers, lb, bastion               |
   |  Bastion Service (SSH tunnel to private subnet)         |
   +---------------------------------------------------------+
   |  Kyverno (policy enforcement)                           |
   |  NetworkPolicies (argocd namespace lockdown)            |
   +---------------------------------------------------------+
   |  Cloud Guard (OCI-native threat detection)              |
   |  VCN Flow Logs + OKE Audit Logs (90-day retention)      |
   +---------------------------------------------------------+
```

## Layers

**OCI Network Layer:**
- Purpose: VCN, subnets, gateways, route tables, NSGs, flow logging
- Location: `terraform/infra/modules/oci-network/`
- Contains: VCN (10.0.0.0/16), public subnet (10.0.1.0/24) for LBs/bastion, private subnet (10.0.2.0/24) for workers. Internet Gateway, NAT Gateway, Service Gateway. Four NSGs (lb, workers, bastion, api-endpoint).
- Depends on: Nothing (parallel module)
- Used by: `oci-oke` module (consumes VCN ID, subnet IDs, NSG IDs)

**OCI IAM Layer:**
- Purpose: Dynamic groups and IAM policies for workload identity and OKE service permissions
- Location: `terraform/infra/modules/oci-iam/`
- Contains: Dynamic group for ESO workload identity, policy for ESO to read Vault secrets, policy for OKE to manage LBs and network
- Depends on: Nothing (parallel module)
- Used by: `oci-oke` depends on it being applied first

**OCI OKE Layer:**
- Purpose: Kubernetes cluster, node pool, bastion, kubeconfig generation
- Location: `terraform/infra/modules/oci-oke/`
- Contains: OKE BASIC cluster with private API endpoint, node pool (2x A1.Flex ARM nodes), OCI Bastion Service, audit logging, kubeconfig provisioner
- Depends on: `oci-network` (VCN, subnets, NSGs), `oci-iam` (policies must exist)
- Used by: `oci-vault` depends on cluster existence; k8s layer uses the cluster

**OCI Vault Layer:**
- Purpose: Secret storage for GitHub OAuth credentials
- Location: `terraform/infra/modules/oci-vault/`
- Contains: OCI KMS Vault, AES-256 master encryption key, two secrets (GitHub OAuth client ID and secret)
- Depends on: `oci-oke` (sequenced after cluster)
- Used by: k8s layer's `external-secrets` module reads vault OCID via remote state

**OCI Cloud Guard Layer:**
- Purpose: Threat detection and compliance monitoring
- Location: `terraform/infra/modules/oci-cloud-guard/`
- Contains: Cloud Guard configuration, detector/responder recipes cloned from Oracle managed, target scoped to compartment, ONS notification topic with optional email subscription, Events rule
- Depends on: Nothing (parallel module)
- Used by: Independent -- alerts go to ONS topic

**Ingress Layer (k8s):**
- Purpose: External traffic ingestion via OCI Load Balancer
- Location: `terraform/k8s/modules/ingress-nginx/`
- Contains: Helm release of ingress-nginx with OCI-specific LB annotations (flexible shape, 10Mbps)
- Depends on: OKE cluster being accessible
- Used by: ArgoCD ingress resource routes through it

**External Secrets Layer (k8s):**
- Purpose: Sync OCI Vault secrets into Kubernetes Secrets
- Location: `terraform/k8s/modules/external-secrets/`
- Contains: ESO Helm release, ClusterSecretStore (OCI Vault provider with workload identity auth), argocd namespace creation with pod-security label, ExternalSecret for GitHub OAuth credentials
- Depends on: `ingress-nginx`
- Used by: ArgoCD Dex consumes the synced `argocd-dex-github-secret`

**ArgoCD Layer (k8s):**
- Purpose: GitOps continuous delivery platform
- Location: `terraform/k8s/modules/argocd/`
- Contains: Helm release with hardened security contexts (runAsNonRoot, readOnly rootfs, drop ALL caps, seccomp), Dex connector for GitHub OAuth, RBAC (org members get admin, default deny), Ingress resource, AppProject with cluster resource blacklist
- Depends on: `external-secrets` (needs the GitHub OAuth secret)
- Used by: End-users deploy applications through ArgoCD

**Kyverno Layer (k8s):**
- Purpose: Policy enforcement for workload security
- Location: `terraform/k8s/modules/kyverno/`
- Contains: Kyverno Helm release, six ClusterPolicies in Enforce mode: disallow-root-containers, disallow-privilege-escalation, require-readonly-rootfs, disallow-latest-tag, require-resource-limits, require-seccomp-profile. System namespaces are excluded (kube-system, kyverno, argocd, external-secrets, ingress-nginx, longhorn-system).
- Depends on: `argocd`
- Used by: Validates all new Pods in application namespaces

**Network Policies Layer (k8s):**
- Purpose: Micro-segmentation of the argocd namespace
- Location: `terraform/k8s/modules/network-policies/`
- Contains: deny-all baseline, then allow rules: Redis accepts only from server/controller/repo-server on 6379; server accepts ingress from ingress-nginx namespace on 8080/8083; repo-server/app-controller/dex accept only intra-namespace; egress limited to DNS (53) + HTTPS (443) for non-redis pods; redis has no egress.
- Depends on: `argocd`
- Used by: Applied to argocd namespace

## Key Design Decisions

**Two-stage Terraform (infra/ then k8s/):**
- The infra layer uses the OCI provider only. The k8s layer uses Helm, Kubernetes, and kubectl providers.
- Separation avoids circular dependencies: infra creates the cluster, k8s configures it.
- State coupling is one-way via `terraform_remote_state` in k8s reading infra outputs.

**Private API endpoint with Bastion:**
- OKE API endpoint is on the private subnet (`is_public_ip_enabled = false`).
- Access requires OCI Bastion Service SSH tunnel. The API endpoint NSG only allows ingress from the bastion NSG on port 6443.
- Trade-off: harder to operate, but eliminates public K8s API exposure.

**ARM-based nodes (A1.Flex):**
- Uses OCI Always Free tier eligible `VM.Standard.A1.Flex` shape (2 OCPU, 12GB RAM per node, 2 nodes).
- Cost-optimized for a small workload; all container images must support ARM64.

**OCI Vault + External Secrets Operator (workload identity):**
- Secrets stored in OCI Vault, synced to K8s via ESO using OKE workload identity (OIDC-based, no static credentials).
- ClusterSecretStore is namespace-restricted to `argocd` only via `namespaceSelector`.

**Security-first defaults:**
- Kyverno enforces 6 policies on all application namespaces (system namespaces excluded).
- ArgoCD runs with `admin.enabled=false`, `exec.enabled=false`, anonymous disabled.
- All ArgoCD containers have hardened security contexts.
- NetworkPolicies implement deny-all baseline with least-privilege allow rules.
- Pod Security Standards: argocd namespace labeled `pod-security.kubernetes.io/enforce: restricted`.

**S3-compatible backend (OCI Object Storage):**
- Both root modules store state in `assessforge-tfstate` bucket on OCI Object Storage using S3-compat API.
- Keys: `infra/terraform.tfstate` and `k8s/terraform.tfstate`.

**GitHub OAuth via Dex:**
- ArgoCD authenticates users via GitHub OAuth App through Dex.
- All members of the configured GitHub org get `role:admin`. Default policy is deny.

## Data Flow

**Infrastructure Provisioning Flow:**

1. Operator runs `terraform apply` in `terraform/infra/` with `terraform.tfvars` providing OCI credentials, compartment, region, GitHub OAuth secrets.
2. Network, IAM, and Cloud Guard modules run in parallel (no inter-dependencies).
3. OKE module runs after network + IAM, creating cluster and node pool.
4. Vault module runs after OKE, storing GitHub OAuth secrets encrypted with AES-256 master key.
5. `null_resource.kubeconfig` generates `~/.kube/config-assessforge` for kubectl access.

**K8s Services Provisioning Flow:**

1. Operator runs `terraform apply` in `terraform/k8s/`. It reads infra state via `terraform_remote_state`.
2. ingress-nginx deploys first, creating the OCI Load Balancer.
3. external-secrets deploys, creating the ClusterSecretStore connected to OCI Vault and the ExternalSecret that syncs GitHub OAuth creds into `argocd-dex-github-secret`.
4. ArgoCD deploys with Dex configured to reference the synced secret.
5. Kyverno and network-policies deploy last (both depend on ArgoCD).

**Secret Flow (GitHub OAuth):**

1. Operator provides `github_oauth_client_id` and `github_oauth_client_secret` as sensitive tfvars to infra layer.
2. `oci-vault` module stores them as OCI Vault secrets (base64-encoded, AES-256 encrypted).
3. ESO's ClusterSecretStore authenticates to OCI Vault via workload identity (dynamic group policy).
4. ExternalSecret in argocd namespace pulls secrets every 1h, creates K8s Secret `argocd-dex-github-secret`.
5. ArgoCD Dex reads the secret at runtime for GitHub OAuth flow.

**User Access Flow:**

1. User navigates to `https://argocd.assessforge.com`.
2. DNS resolves to OCI LB IP (configured manually in Cloudflare).
3. ingress-nginx routes to ArgoCD server (HTTP backend, `--insecure` flag -- TLS terminates at ingress/LB level).
4. ArgoCD redirects to GitHub OAuth via Dex.
5. GitHub authenticates user; Dex checks org membership.
6. ArgoCD RBAC grants admin role if user is in the configured GitHub org.

## Entry Points

**Infra Root Module:**
- Location: `terraform/infra/main.tf`
- Triggers: Manual `terraform apply` by operator
- Responsibilities: Orchestrates all OCI resource modules, manages dependency ordering

**K8s Root Module:**
- Location: `terraform/k8s/main.tf`
- Triggers: Manual `terraform apply` by operator (after infra is applied)
- Responsibilities: Orchestrates all Kubernetes service modules, reads infra state

## Error Handling

**Strategy:** Terraform-native -- plan/apply cycle with state locking via S3 backend.

**Patterns:**
- `lifecycle { prevent_destroy = true }` on critical resources: OKE cluster (`terraform/infra/modules/oci-oke/main.tf`), node pool, OCI Vault, master encryption key (`terraform/infra/modules/oci-vault/main.tf`)
- Helm releases use `wait = true` with explicit timeouts (300-600s) to ensure readiness before downstream modules proceed
- `depends_on` used extensively to enforce sequential deployment where implicit dependencies are insufficient

## Cross-Cutting Concerns

**Logging:**
- VCN flow logs: 90-day retention (`terraform/infra/modules/oci-network/main.tf`)
- OKE API server audit logs: 90-day retention (`terraform/infra/modules/oci-oke/main.tf`)
- ArgoCD components: JSON format logging at info level (`terraform/k8s/modules/argocd/main.tf`)
- Cloud Guard: event-driven alerts via ONS topic (`terraform/infra/modules/oci-cloud-guard/main.tf`)

**Tagging:**
- All OCI resources tagged with `freeform_tags = { project = "argocd-assessforge" }` (defined in `terraform/infra/main.tf`)
- All K8s resources labeled with `app.kubernetes.io/managed-by: terraform`

**Authentication:**
- OCI provider authenticates via `~/.oci/config` DEFAULT profile (no hardcoded credentials)
- K8s providers authenticate via `~/.kube/config-assessforge` (generated by infra layer)
- ESO authenticates to Vault via OKE workload identity (OIDC)
- Users authenticate to ArgoCD via GitHub OAuth

---

*Architecture analysis: 2026-04-09*
