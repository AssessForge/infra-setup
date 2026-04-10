<!-- GSD:project-start source:PROJECT.md -->
## Project

**AssessForge GitOps Bridge**

Adopt the GitOps Bridge Pattern for AssessForge's OCI/OKE infrastructure. Refactor the existing Terraform repository so it only provisions cloud resources and performs a one-time ArgoCD bootstrap, then create a new GitOps repository (`gitops-setup`) where ArgoCD manages itself, all cluster addons, and all workloads. After bootstrap, nothing inside the cluster is managed by Terraform — every change flows through Git PRs.

**Core Value:** After bootstrap, every cluster change — addons, ArgoCD config, workloads — flows exclusively through the GitOps repository via PRs. Terraform never touches in-cluster resources again.

### Constraints

- **Cloud**: OCI only — all IAM, networking, and secrets use OCI-native services
- **Cost**: 100% OCI Always Free tier — never introduce paid resources
- **Identity**: OCI Instance Principal via Dynamic Groups for pod-level OCI API access — no static API keys (Workload Identity requires Enhanced tier which is paid)
- **Secrets**: All sensitive values in OCI Vault, pulled by External Secrets Operator
- **Networking**: ArgoCD Server uses ClusterIP — Envoy Gateway manages external access via Gateway API (installed via GitOps, not Terraform)
- **Versioning**: All Helm chart versions and Terraform provider versions must be pinned — no `latest` or open ranges
- **State**: Terraform remote state on OCI Object Storage (S3-compatible backend)
- **Protection**: Critical resources (cluster, VCN, state bucket) must have `prevent_destroy = true`
- **Boundary**: After bootstrap, no Kubernetes resource is managed by Terraform — changes go through GitOps repo only
<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->
## Technology Stack

## Languages
- HCL (HashiCorp Configuration Language) - All infrastructure definitions across `terraform/infra/` and `terraform/k8s/`
- YAML (embedded) - Kubernetes manifests embedded in HCL via `kubectl_manifest` resources and Helm `values` blocks
- Bash (minimal) - `local-exec` provisioner in `terraform/infra/modules/oci-oke/main.tf` for kubeconfig generation
## Runtime
- Terraform >= 1.5.0 (required version constraint in both `terraform/infra/versions.tf` and `terraform/k8s/versions.tf`)
- OCI CLI - Required for kubeconfig generation and Object Storage namespace lookup
- Terraform providers (auto-managed via `terraform init`)
- Lockfiles: Present at `terraform/infra/.terraform.lock.hcl` and `terraform/k8s/.terraform.lock.hcl`
## Frameworks
- Terraform >= 1.5.0 - Infrastructure as Code provisioning for OCI and Kubernetes resources
- Helm (via Terraform provider) - Deploys Kubernetes applications (ArgoCD, ingress-nginx, external-secrets, Kyverno)
- OCI CLI - Cluster authentication and kubeconfig management
## Terraform Providers
- `oracle/oci` ~> 8.0 - OCI resource provisioning (VCN, OKE, Vault, IAM, Cloud Guard)
- `hashicorp/helm` ~> 3.0 - Helm chart deployments for all k8s services
- `hashicorp/kubernetes` ~> 3.0 - Native Kubernetes resources (namespaces, ingress)
- `alekc/kubectl` ~> 2.0 - Raw YAML manifest application (ClusterPolicies, NetworkPolicies, ExternalSecrets, AppProjects)
- `hashicorp/random` ~> 3.8 - Random value generation
## Helm Charts (Pinned Versions)
| Chart | Version | Repository | Module |
|-------|---------|-----------|--------|
| `argo-cd` | 7.6.12 | `https://argoproj.github.io/argo-helm` | `terraform/k8s/modules/argocd/main.tf` |
| `external-secrets` | 0.9.20 | `https://charts.external-secrets.io` | `terraform/k8s/modules/external-secrets/main.tf` |
| `ingress-nginx` | 4.10.1 | `https://kubernetes.github.io/ingress-nginx` | `terraform/k8s/modules/ingress-nginx/main.tf` |
| `kyverno` | 3.2.6 | `https://kyverno.github.io/kyverno` | `terraform/k8s/modules/kyverno/main.tf` |
## State Management
- Bucket: `assessforge-tfstate`
- Infra state key: `infra/terraform.tfstate` (configured in `terraform/infra/versions.tf`)
- K8s state key: `k8s/terraform.tfstate` (configured in `terraform/k8s/versions.tf`)
- Region: `sa-saopaulo-1`
- Endpoint: OCI Object Storage S3-compatible endpoint (PLACEHOLDER in committed config)
- Options: `skip_region_validation`, `skip_credentials_validation`, `skip_metadata_api_check`, `force_path_style` all set to `true`
## Configuration
- `tenancy_ocid` - OCI tenancy OCID
- `compartment_ocid` - Target compartment OCID
- `region` - OCI region (default: `sa-saopaulo-1`)
- `cluster_name` - OKE cluster name (default: `assessforge-oke`)
- `bastion_allowed_cidr` - Operator IP for SSH/API access
- `notification_email` - Cloud Guard alert email (optional)
- `github_oauth_client_id` - GitHub OAuth App client ID (sensitive)
- `github_oauth_client_secret` - GitHub OAuth App client secret (sensitive)
- `region` - OCI region (must match infra layer)
- `oci_object_storage_endpoint` - S3-compat endpoint for remote state access
- `argocd_hostname` - Public hostname for ArgoCD (e.g., `argocd.assessforge.com`)
- `github_org` - GitHub organization for RBAC
- OCI provider authenticates via `~/.oci/config` (DEFAULT profile) - no credentials in Terraform files
- Kubernetes/Helm/Kubectl providers use `~/.kube/config-assessforge` (generated by OKE module)
## Platform Requirements
- Terraform >= 1.5.0
- OCI CLI (for `oci ce cluster create-kubeconfig` and `oci os ns get`)
- `kubectl` (for cluster verification)
- `~/.oci/config` configured with API key authentication
- Access to OCI tenancy with appropriate IAM permissions
- OCI region: `sa-saopaulo-1` (Sao Paulo)
- OKE cluster type: BASIC_CLUSTER
- Node shape: VM.Standard.A1.Flex (ARM64, 2 OCPUs, 12GB RAM per node)
- Node pool: 2 nodes with 50GB boot volumes
- Kubernetes version: Auto-selects latest available via `oci_containerengine_cluster_option` data source (configurable via `var.kubernetes_version`)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

## Terraform Module Structure
- Infra modules (`terraform/infra/modules/`) do NOT have `versions.tf` files -- providers are inherited from the root.
- K8s modules (`terraform/k8s/modules/`) each declare their own `required_providers` in `versions.tf`.
- No module has a dedicated `locals.tf` -- locals are defined inline in `main.tf` when needed.
## Naming Conventions
### Resource Names (display_name / name)
- `assessforge-vcn`, `assessforge-igw`, `assessforge-natgw`, `assessforge-sgw`
- `assessforge-subnet-public`, `assessforge-subnet-private`
- `assessforge-nsg-lb`, `assessforge-nsg-workers`, `assessforge-nsg-bastion`, `assessforge-nsg-api-endpoint`
- `assessforge-oke-audit-logs`, `assessforge-vcn-flow-logs`
- `assessforge-bastion`, `assessforge-workload-identity`
- `assessforge-cloud-guard-target`, `assessforge-cloud-guard-alerts`
### Terraform Resource Labels
- `oci_core_vcn.main`, `oci_core_nat_gateway.main`, `oci_containerengine_cluster.main`
- For multiple resources of the same type, use descriptive suffixes: `oci_core_subnet.public`, `oci_core_subnet.private`
- NSG rules use `<target>_<direction>_<purpose>` pattern: `workers_ingress_from_lb`, `api_endpoint_ingress_bastion`
### Variable Names
- Use `snake_case` for all variables.
- OCI OCIDs use `_ocid` suffix: `compartment_ocid`, `tenancy_ocid`, `vault_ocid`.
- Subnet/NSG IDs use `_id` suffix: `vcn_id`, `public_subnet_id`, `workers_nsg_id`.
- CIDRs use `_cidr` suffix: `vcn_cidr`, `bastion_allowed_cidr`, `public_subnet_cidr`.
### Output Names
- Use `snake_case`.
- Include the resource type in the name: `cluster_id`, `vault_ocid`, `bastion_ocid`, `lb_ip`.
- Actionable outputs include `_command` suffix: `kubeconfig_command`, `ingress_lb_ip_command`.
## Variable Design Patterns
### Description Language
### Default Values
- Required variables have no `default` -- they must be supplied via `terraform.tfvars`.
- Optional variables use sensible defaults:
- Conditional resource creation uses `count` with variable check:
### Sensitive Variables
- `github_oauth_client_id` in `terraform/infra/variables.tf`
- `github_oauth_client_secret` in `terraform/infra/variables.tf`
## Variable Flow Pattern
- Defined as a `local` in root `terraform/infra/main.tf`: `local.freeform_tags = { project = "argocd-assessforge" }`
- Passed explicitly to every infra module via `freeform_tags = local.freeform_tags`
- Every OCI resource in every infra module includes `freeform_tags = var.freeform_tags`
- `terraform/k8s/` reads outputs from `terraform/infra/` via `terraform_remote_state` data source, not variables.
- Example: `data.terraform_remote_state.infra.outputs.vault_ocid`
## Helm Chart Configuration Patterns
### K8s modules use two Helm value patterns:
### Helm release conventions:
- Always set `wait = true` and explicit `timeout` (300 or 600 seconds).
- Use `create_namespace = true` for new namespaces, except ArgoCD (namespace created by external-secrets module).
- Pin chart versions explicitly (no floating ranges).
## Kubernetes Manifest Patterns
## Security Hardening Conventions
### Container Security Context (applied to every ArgoCD component in `terraform/k8s/modules/argocd/main.tf`):
### Resource Limits
### Lifecycle Protection
- `terraform/infra/modules/oci-oke/main.tf`: cluster and node pool
- `terraform/infra/modules/oci-vault/main.tf`: vault and master key
## Comment Style
- Use `#` comments in Portuguese for section headers and explanations.
- Section separators use `# --- Section Name ---` pattern in root `main.tf` files.
- Inline comments explain "why" not "what": `# resource.type = 'workload' restringe ao Workload Identity de pods OKE via OIDC`
- Empty files get a single comment explaining why they are empty: `# Sem variaveis externas -- modulo auto-contido`
## Dependency Management
### Explicit `depends_on` for ordering:
- In `terraform/infra/main.tf`: OKE depends on network + IAM; Vault depends on OKE.
- In `terraform/k8s/main.tf`: Sequential chain -- ingress-nginx -> external-secrets -> argocd -> kyverno/network-policies.
- Within modules: `kubectl_manifest` resources depend on their parent `helm_release`.
### Backend Configuration
## Documentation Patterns
- `terraform/README.md`: Comprehensive operational runbook covering prerequisites, setup, stages, and teardown.
- `terraform.tfvars.example`: Committed with placeholder values and inline comments explaining each variable.
- `docs/superpowers/specs/`: Design specification documents.
- `docs/superpowers/plans/`: Implementation plan documents.
- No per-module README files exist.
## Files That Must Never Be Committed
- `*.tfvars` (contains real secrets)
- `*.tfstate`, `*.tfstate.backup`
- `.terraform/`
- `**/config-assessforge` (kubeconfig)
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

## System Overview
## Layer Diagram
```
```
## Layers
- Purpose: VCN, subnets, gateways, route tables, NSGs, flow logging
- Location: `terraform/infra/modules/oci-network/`
- Contains: VCN (10.0.0.0/16), public subnet (10.0.1.0/24) for LBs/bastion, private subnet (10.0.2.0/24) for workers. Internet Gateway, NAT Gateway, Service Gateway. Four NSGs (lb, workers, bastion, api-endpoint).
- Depends on: Nothing (parallel module)
- Used by: `oci-oke` module (consumes VCN ID, subnet IDs, NSG IDs)
- Purpose: Dynamic groups and IAM policies for workload identity and OKE service permissions
- Location: `terraform/infra/modules/oci-iam/`
- Contains: Dynamic group for ESO workload identity, policy for ESO to read Vault secrets, policy for OKE to manage LBs and network
- Depends on: Nothing (parallel module)
- Used by: `oci-oke` depends on it being applied first
- Purpose: Kubernetes cluster, node pool, bastion, kubeconfig generation
- Location: `terraform/infra/modules/oci-oke/`
- Contains: OKE BASIC cluster with private API endpoint, node pool (2x A1.Flex ARM nodes), OCI Bastion Service, audit logging, kubeconfig provisioner
- Depends on: `oci-network` (VCN, subnets, NSGs), `oci-iam` (policies must exist)
- Used by: `oci-vault` depends on cluster existence; k8s layer uses the cluster
- Purpose: Secret storage for GitHub OAuth credentials
- Location: `terraform/infra/modules/oci-vault/`
- Contains: OCI KMS Vault, AES-256 master encryption key, two secrets (GitHub OAuth client ID and secret)
- Depends on: `oci-oke` (sequenced after cluster)
- Used by: k8s layer's `external-secrets` module reads vault OCID via remote state
- Purpose: Threat detection and compliance monitoring
- Location: `terraform/infra/modules/oci-cloud-guard/`
- Contains: Cloud Guard configuration, detector/responder recipes cloned from Oracle managed, target scoped to compartment, ONS notification topic with optional email subscription, Events rule
- Depends on: Nothing (parallel module)
- Used by: Independent -- alerts go to ONS topic
- Purpose: External traffic ingestion via OCI Load Balancer
- Location: `terraform/k8s/modules/ingress-nginx/`
- Contains: Helm release of ingress-nginx with OCI-specific LB annotations (flexible shape, 10Mbps)
- Depends on: OKE cluster being accessible
- Used by: ArgoCD ingress resource routes through it
- Purpose: Sync OCI Vault secrets into Kubernetes Secrets
- Location: `terraform/k8s/modules/external-secrets/`
- Contains: ESO Helm release, ClusterSecretStore (OCI Vault provider with workload identity auth), argocd namespace creation with pod-security label, ExternalSecret for GitHub OAuth credentials
- Depends on: `ingress-nginx`
- Used by: ArgoCD Dex consumes the synced `argocd-dex-github-secret`
- Purpose: GitOps continuous delivery platform
- Location: `terraform/k8s/modules/argocd/`
- Contains: Helm release with hardened security contexts (runAsNonRoot, readOnly rootfs, drop ALL caps, seccomp), Dex connector for GitHub OAuth, RBAC (org members get admin, default deny), Ingress resource, AppProject with cluster resource blacklist
- Depends on: `external-secrets` (needs the GitHub OAuth secret)
- Used by: End-users deploy applications through ArgoCD
- Purpose: Policy enforcement for workload security
- Location: `terraform/k8s/modules/kyverno/`
- Contains: Kyverno Helm release, six ClusterPolicies in Enforce mode: disallow-root-containers, disallow-privilege-escalation, require-readonly-rootfs, disallow-latest-tag, require-resource-limits, require-seccomp-profile. System namespaces are excluded (kube-system, kyverno, argocd, external-secrets, ingress-nginx, longhorn-system).
- Depends on: `argocd`
- Used by: Validates all new Pods in application namespaces
- Purpose: Micro-segmentation of the argocd namespace
- Location: `terraform/k8s/modules/network-policies/`
- Contains: deny-all baseline, then allow rules: Redis accepts only from server/controller/repo-server on 6379; server accepts ingress from ingress-nginx namespace on 8080/8083; repo-server/app-controller/dex accept only intra-namespace; egress limited to DNS (53) + HTTPS (443) for non-redis pods; redis has no egress.
- Depends on: `argocd`
- Used by: Applied to argocd namespace
## Key Design Decisions
- The infra layer uses the OCI provider only. The k8s layer uses Helm, Kubernetes, and kubectl providers.
- Separation avoids circular dependencies: infra creates the cluster, k8s configures it.
- State coupling is one-way via `terraform_remote_state` in k8s reading infra outputs.
- OKE API endpoint is on the private subnet (`is_public_ip_enabled = false`).
- Access requires OCI Bastion Service SSH tunnel. The API endpoint NSG only allows ingress from the bastion NSG on port 6443.
- Trade-off: harder to operate, but eliminates public K8s API exposure.
- Uses OCI Always Free tier eligible `VM.Standard.A1.Flex` shape (2 OCPU, 12GB RAM per node, 2 nodes).
- Cost-optimized for a small workload; all container images must support ARM64.
- Secrets stored in OCI Vault, synced to K8s via ESO using OKE workload identity (OIDC-based, no static credentials).
- ClusterSecretStore is namespace-restricted to `argocd` only via `namespaceSelector`.
- Kyverno enforces 6 policies on all application namespaces (system namespaces excluded).
- ArgoCD runs with `admin.enabled=false`, `exec.enabled=false`, anonymous disabled.
- All ArgoCD containers have hardened security contexts.
- NetworkPolicies implement deny-all baseline with least-privilege allow rules.
- Pod Security Standards: argocd namespace labeled `pod-security.kubernetes.io/enforce: restricted`.
- Both root modules store state in `assessforge-tfstate` bucket on OCI Object Storage using S3-compat API.
- Keys: `infra/terraform.tfstate` and `k8s/terraform.tfstate`.
- ArgoCD authenticates users via GitHub OAuth App through Dex.
- All members of the configured GitHub org get `role:admin`. Default policy is deny.
## Data Flow
## Entry Points
- Location: `terraform/infra/main.tf`
- Triggers: Manual `terraform apply` by operator
- Responsibilities: Orchestrates all OCI resource modules, manages dependency ordering
- Location: `terraform/k8s/main.tf`
- Triggers: Manual `terraform apply` by operator (after infra is applied)
- Responsibilities: Orchestrates all Kubernetes service modules, reads infra state
## Error Handling
- `lifecycle { prevent_destroy = true }` on critical resources: OKE cluster (`terraform/infra/modules/oci-oke/main.tf`), node pool, OCI Vault, master encryption key (`terraform/infra/modules/oci-vault/main.tf`)
- Helm releases use `wait = true` with explicit timeouts (300-600s) to ensure readiness before downstream modules proceed
- `depends_on` used extensively to enforce sequential deployment where implicit dependencies are insufficient
## Cross-Cutting Concerns
- VCN flow logs: 90-day retention (`terraform/infra/modules/oci-network/main.tf`)
- OKE API server audit logs: 90-day retention (`terraform/infra/modules/oci-oke/main.tf`)
- ArgoCD components: JSON format logging at info level (`terraform/k8s/modules/argocd/main.tf`)
- Cloud Guard: event-driven alerts via ONS topic (`terraform/infra/modules/oci-cloud-guard/main.tf`)
- All OCI resources tagged with `freeform_tags = { project = "argocd-assessforge" }` (defined in `terraform/infra/main.tf`)
- All K8s resources labeled with `app.kubernetes.io/managed-by: terraform`
- OCI provider authenticates via `~/.oci/config` DEFAULT profile (no hardcoded credentials)
- K8s providers authenticate via `~/.kube/config-assessforge` (generated by infra layer)
- ESO authenticates to Vault via OKE workload identity (OIDC)
- Users authenticate to ArgoCD via GitHub OAuth
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, or `.github/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
