# External Integrations

**Analysis Date:** 2026-04-09

## Cloud Services (OCI)

**Networking (`terraform/infra/modules/oci-network/main.tf`):**
- OCI VCN (`assessforge-vcn`) - Primary virtual cloud network, CIDR configurable via `var.vcn_cidr`
- Internet Gateway - Public subnet egress
- NAT Gateway - Private subnet egress (worker nodes reach internet without public IPs)
- Service Gateway - Private access to OCI services without traversing internet
- Public subnet - Hosts Load Balancers and Bastion
- Private subnet - Hosts OKE worker nodes (no public IPs)
- Network Security Groups (NSGs): `lb`, `workers`, `bastion`, `api_endpoint` - Micro-segmented network access control

**Compute / Kubernetes (`terraform/infra/modules/oci-oke/main.tf`):**
- OKE (Oracle Kubernetes Engine) - BASIC_CLUSTER type, private API endpoint
  - Pod CIDR: `10.244.0.0/16`
  - Services CIDR: `10.96.0.0/16`
  - Node shape: VM.Standard.A1.Flex (ARM64)
  - Node pool: 2 nodes, 2 OCPUs, 12GB RAM, 50GB boot volume each
  - Kubernetes dashboard and Tiller disabled
  - `lifecycle.prevent_destroy = true` on cluster and node pool

**Bastion (`terraform/infra/modules/oci-oke/main.tf`):**
- OCI Bastion Service (`assessforge-bastion`) - STANDARD type
  - Targets private subnet (worker nodes)
  - Restricted to operator CIDR via `client_cidr_block_allow_list`
  - Used for SSH tunneling to access private API endpoint on port 6443

**Identity & Access Management (`terraform/infra/modules/oci-iam/main.tf`):**
- Dynamic Group `assessforge-workload-identity` - Matches `resource.type = 'workload'` in the compartment for OKE Workload Identity (OIDC-based pod authentication)
- IAM Policy `assessforge-eso-vault-policy` - Grants dynamic group: `read secret-family`, `use vaults`, `use keys`
- IAM Policy `assessforge-oke-network-policy` - Grants OKE service: `manage load-balancers`, `use virtual-network-family`, `manage cluster-family`

**Secrets Management (`terraform/infra/modules/oci-vault/main.tf`):**
- OCI Vault (`argocd-vault`) - DEFAULT type, `lifecycle.prevent_destroy = true`
- Master Encryption Key - AES-256, used to encrypt all vault secrets
- Stored secrets:
  - `github-oauth-client-id` - GitHub OAuth App client ID
  - `github-oauth-client-secret` - GitHub OAuth App client secret

**Security Monitoring (`terraform/infra/modules/oci-cloud-guard/main.tf`):**
- OCI Cloud Guard - Enabled at tenancy level
  - Detector Recipe (cloned from Oracle Managed "OCI Configuration Detector Recipe")
  - Responder Recipe (cloned from Oracle Managed "OCI Notification Responder Recipe")
  - Target scoped to project compartment

**Alerting (`terraform/infra/modules/oci-cloud-guard/main.tf`):**
- OCI Notifications (ONS) - Topic `assessforge-cloud-guard-alerts`
  - Email subscription (conditional on `var.notification_email != ""`)
- OCI Events Rule - Forwards `problemdetected` and `problemthresholdreached` events to ONS topic

**Logging (`terraform/infra/modules/oci-network/main.tf`, `terraform/infra/modules/oci-oke/main.tf`):**
- VCN Flow Logs - 90-day retention, log group `assessforge-vcn-flow-logs`
- OKE Audit Logs - `kube-apiserver-audit` category, 90-day retention, log group `assessforge-oke-audit-logs`

**Object Storage:**
- Bucket `assessforge-tfstate` - Terraform remote state backend (S3-compatible API)
  - Endpoint: OCI Object Storage S3-compatible endpoint in `sa-saopaulo-1`

## Third-Party Services

**GitHub (`terraform/k8s/modules/argocd/main.tf`):**
- GitHub OAuth App - SSO authentication for ArgoCD via Dex connector
  - Scopes: `read:org`
  - Organization-based access control: all members of `var.github_org` get `role:admin`
  - Credentials stored in OCI Vault, synced to K8s via External Secrets Operator
  - Config location: ArgoCD `configs.cm.dex.config` in Helm values

**GitHub (ArgoCD GitOps):**
- ArgoCD AppProject `assessforge` defined in `terraform/k8s/modules/argocd/main.tf`
  - `sourceRepos: ['*']` - Can pull from any Git repository
  - Destinations: any namespace on `https://kubernetes.default.svc`
  - Blacklisted cluster resources: ClusterRole, ClusterRoleBinding, Node, PriorityClass
  - Blacklisted namespace resources: ResourceQuota

## Kubernetes Services (K8s Layer)

**Ingress Controller (`terraform/k8s/modules/ingress-nginx/main.tf`):**
- ingress-nginx (chart v4.10.1) - Namespace: `ingress-nginx`
  - Service type: LoadBalancer (provisions OCI Flexible Load Balancer)
  - LB shape: flexible, 10 Mbps min/max
  - Resources: 100m-500m CPU, 128Mi-512Mi memory
  - Output: `ingress_lb_ip` exposed for DNS configuration

**External Secrets Operator (`terraform/k8s/modules/external-secrets/main.tf`):**
- external-secrets (chart v0.9.20) - Namespace: `external-secrets`
  - CRDs installed via chart
  - ClusterSecretStore `oci-vault-store` - Connects to OCI Vault
    - Auth: OKE Workload Identity (OIDC) via service account `external-secrets` in namespace `external-secrets`
    - Scoped to namespace `argocd` only (via `namespaceSelector`)
  - ExternalSecret `argocd-dex-github-secret` in namespace `argocd`
    - Syncs `github-oauth-client-id` and `github-oauth-client-secret` from OCI Vault
    - Refresh interval: 1 hour

**ArgoCD (`terraform/k8s/modules/argocd/main.tf`):**
- argo-cd (chart v7.6.12) - Namespace: `argocd`
  - Admin UI disabled (`admin.enabled = false`)
  - Anonymous access disabled
  - Exec disabled
  - Server runs in insecure mode (TLS terminated at ingress)
  - Ingress: nginx ingress class, host-based routing on `var.argocd_hostname`
  - Logging: JSON format, info level across all components
  - Login rate limiting: 5 attempts max, 300s reset
  - All components run as non-root (UID 999), read-only root filesystem, seccomp RuntimeDefault, capabilities dropped

**Kyverno (`terraform/k8s/modules/kyverno/main.tf`):**
- kyverno (chart v3.2.6) - Namespace: `kyverno`, 1 replica
  - 6 ClusterPolicies enforced (all `validationFailureAction: Enforce`):
    1. `disallow-root-containers` - Requires `runAsNonRoot: true`
    2. `disallow-privilege-escalation` - Requires `allowPrivilegeEscalation: false`
    3. `require-readonly-rootfs` - Requires `readOnlyRootFilesystem: true`
    4. `disallow-latest-tag` - Blocks `:latest` or untagged images
    5. `require-resource-limits` - Requires CPU and memory limits
    6. `require-seccomp-profile` - Requires RuntimeDefault or Localhost seccomp
  - Excluded namespaces: `kube-system`, `kyverno`, `longhorn-system`, `external-secrets`, `argocd`, `ingress-nginx`

**Network Policies (`terraform/k8s/modules/network-policies/main.tf`):**
- 7 NetworkPolicy resources in `argocd` namespace:
  1. `deny-all-default` - Default deny all ingress/egress baseline
  2. `argocd-redis-lockdown` - Redis port 6379 only from server, controller, repo-server
  3. `argocd-server-ingress` - Server accepts traffic only from `ingress-nginx` namespace (ports 8080, 8083)
  4. `argocd-internal-repo-server` - Repo-server accepts only intra-namespace traffic
  5. `argocd-internal-app-controller` - App-controller accepts only intra-namespace traffic
  6. `argocd-internal-dex` - Dex accepts only intra-namespace traffic
  7. `argocd-egress-dns-https` - Non-Redis components: egress DNS (53) + HTTPS (443) only
  - Redis has no egress (intentionally blocked by deny-all baseline)

## Internal Service Communication

**Cross-layer data flow (infra -> k8s):**
```
terraform/infra/ outputs:
  ├── vault_ocid ──────────> terraform/k8s/ (via terraform_remote_state)
  │                            └── module.external_secrets (ClusterSecretStore vault reference)
  ├── cluster_id ──────────> kubeconfig generation (~/.kube/config-assessforge)
  │                            └── All k8s providers (helm, kubernetes, kubectl)
  └── bastion_ocid ────────> Manual SSH tunnel for private API access
```

**K8s module dependency chain (`terraform/k8s/main.tf`):**
```
ingress_nginx
  └── external_secrets (depends_on)
        └── argocd (depends_on)
              ├── kyverno (depends_on)
              └── network_policies (depends_on)
```

**Secret flow (OCI Vault -> Kubernetes):**
```
OCI Vault (github-oauth-client-id, github-oauth-client-secret)
  │
  ├── OKE Workload Identity (OIDC) authenticates ESO service account
  │
  └── External Secrets Operator (ClusterSecretStore: oci-vault-store)
        └── ExternalSecret (argocd-dex-github-secret, refresh: 1h)
              └── Kubernetes Secret in argocd namespace
                    └── ArgoCD Dex connector reads credentials
```

**Ingress traffic flow:**
```
Internet → OCI Flexible Load Balancer (public subnet, NSG: lb)
  → ingress-nginx controller (NodePort 30000-32767, NSG: workers)
    → ArgoCD server (port 8080, NetworkPolicy: argocd-server-ingress)
```

## Environment Configuration

**Required env vars / config files:**
- `~/.oci/config` - OCI API key authentication (DEFAULT profile)
- `terraform/infra/terraform.tfvars` - Infra layer variables (from `.example` template)
- `terraform/k8s/terraform.tfvars` - K8s layer variables (from `.example` template)
- `~/.kube/config-assessforge` - Auto-generated by infra layer, consumed by k8s layer

**Sensitive values (stored in `terraform.tfvars`, gitignored):**
- `github_oauth_client_id`
- `github_oauth_client_secret`
- OCI tenancy/compartment OCIDs
- Object Storage namespace (in endpoint URL)

**DNS (external, manual):**
- `argocd_hostname` (e.g., `argocd.assessforge.com`) must be pointed to `ingress_lb_ip` output
- Output `ingress_lb_ip_command` in `terraform/k8s/outputs.tf` provides kubectl fallback command

---

*Integration audit: 2026-04-09*
