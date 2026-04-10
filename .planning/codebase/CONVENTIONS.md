# Coding Conventions

**Analysis Date:** 2026-04-09

## Terraform Module Structure

**Standard module layout** (every module follows this pattern):
```
modules/<module-name>/
  main.tf        # All resources and data sources
  variables.tf   # Input variables
  outputs.tf     # Output values
  versions.tf    # Required providers (k8s modules only)
```

- Infra modules (`terraform/infra/modules/`) do NOT have `versions.tf` files -- providers are inherited from the root.
- K8s modules (`terraform/k8s/modules/`) each declare their own `required_providers` in `versions.tf`.
- No module has a dedicated `locals.tf` -- locals are defined inline in `main.tf` when needed.

**Root module layout:**
```
terraform/{infra,k8s}/
  main.tf                    # Module calls with dependency ordering
  variables.tf               # Root-level input variables
  outputs.tf                 # Aggregated outputs from modules
  versions.tf                # Terraform version, providers, backend config
  terraform.tfvars.example   # Documented example values (committed)
```

## Naming Conventions

### Resource Names (display_name / name)

Use the pattern `assessforge-<component>` consistently:
- `assessforge-vcn`, `assessforge-igw`, `assessforge-natgw`, `assessforge-sgw`
- `assessforge-subnet-public`, `assessforge-subnet-private`
- `assessforge-nsg-lb`, `assessforge-nsg-workers`, `assessforge-nsg-bastion`, `assessforge-nsg-api-endpoint`
- `assessforge-oke-audit-logs`, `assessforge-vcn-flow-logs`
- `assessforge-bastion`, `assessforge-workload-identity`
- `assessforge-cloud-guard-target`, `assessforge-cloud-guard-alerts`

When naming new OCI resources, always prefix with `assessforge-`.

### Terraform Resource Labels

Use short, descriptive names. Prefer `main` for the primary resource of its type within a module:
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

All variable descriptions are in **Portuguese (pt-BR)**:
```hcl
variable "compartment_ocid" {
  description = "OCID do compartment onde os recursos serao criados"
  type        = string
}
```

When adding new variables, write descriptions in Portuguese to match existing style.

### Default Values

- Required variables have no `default` -- they must be supplied via `terraform.tfvars`.
- Optional variables use sensible defaults:
  - Empty string `""` for optional features (e.g., `notification_email`, `kubernetes_version`).
  - CIDR defaults for network layout: `"10.0.0.0/16"`, `"10.0.1.0/24"`, `"10.0.2.0/24"`.
  - Empty map `{}` for `freeform_tags`.
- Conditional resource creation uses `count` with variable check:
  ```hcl
  count = var.notification_email != "" ? 1 : 0
  ```

### Sensitive Variables

Mark secrets with `sensitive = true` in the variable declaration:
```hcl
variable "github_oauth_client_id" {
  description = "Client ID do GitHub OAuth App"
  type        = string
  sensitive   = true
}
```

Sensitive values are:
- `github_oauth_client_id` in `terraform/infra/variables.tf`
- `github_oauth_client_secret` in `terraform/infra/variables.tf`

## Variable Flow Pattern

Variables flow from root `terraform.tfvars` through root `variables.tf` into module calls in root `main.tf`. Modules receive only what they need -- no passthrough of the entire variable set.

**Common shared variable (`freeform_tags`):**
- Defined as a `local` in root `terraform/infra/main.tf`: `local.freeform_tags = { project = "argocd-assessforge" }`
- Passed explicitly to every infra module via `freeform_tags = local.freeform_tags`
- Every OCI resource in every infra module includes `freeform_tags = var.freeform_tags`

**Cross-stage data sharing:**
- `terraform/k8s/` reads outputs from `terraform/infra/` via `terraform_remote_state` data source, not variables.
- Example: `data.terraform_remote_state.infra.outputs.vault_ocid`

## Helm Chart Configuration Patterns

### K8s modules use two Helm value patterns:

**1. `values` block with `yamlencode()` for complex config** (used in `terraform/k8s/modules/argocd/main.tf`):
```hcl
values = [
  yamlencode({
    global = { ... }
    controller = { resources = { ... } }
  })
]
```

**2. `set` block as list of objects for flat config** (used in `terraform/k8s/modules/ingress-nginx/main.tf`, `terraform/k8s/modules/kyverno/main.tf`, `terraform/k8s/modules/external-secrets/main.tf`):
```hcl
set = [
  { name = "controller.service.type", value = "LoadBalancer" },
  { name = "controller.resources.requests.cpu", value = "100m" },
]
```

Use `yamlencode()` when the Helm values are deeply nested. Use `set` for simple key-value overrides.

### Helm release conventions:
- Always set `wait = true` and explicit `timeout` (300 or 600 seconds).
- Use `create_namespace = true` for new namespaces, except ArgoCD (namespace created by external-secrets module).
- Pin chart versions explicitly (no floating ranges).

## Kubernetes Manifest Patterns

Use `kubectl_manifest` resource with heredoc YAML for CRDs and custom resources:
```hcl
resource "kubectl_manifest" "policy_name" {
  yaml_body = <<-YAML
    apiVersion: ...
    kind: ...
    metadata:
      labels:
        app.kubernetes.io/managed-by: terraform
  YAML
  depends_on = [helm_release.parent]
}
```

Always include the label `app.kubernetes.io/managed-by: terraform` on resources managed by Terraform.

## Security Hardening Conventions

### Container Security Context (applied to every ArgoCD component in `terraform/k8s/modules/argocd/main.tf`):
```hcl
containerSecurityContext = {
  runAsNonRoot             = true
  runAsUser                = 999
  readOnlyRootFilesystem   = true
  allowPrivilegeEscalation = false
  capabilities             = { drop = ["ALL"] }
}
```

### Resource Limits
Every Helm-deployed component specifies both `requests` and `limits` for CPU and memory.

### Lifecycle Protection
Critical resources use `lifecycle { prevent_destroy = true }`:
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

Both root modules use S3-compatible OCI Object Storage backend:
```hcl
backend "s3" {
  bucket                      = "assessforge-tfstate"
  key                         = "infra/terraform.tfstate"  # or "k8s/terraform.tfstate"
  region                      = "sa-saopaulo-1"
  skip_region_validation      = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  force_path_style            = true
}
```

## Documentation Patterns

- `terraform/README.md`: Comprehensive operational runbook covering prerequisites, setup, stages, and teardown.
- `terraform.tfvars.example`: Committed with placeholder values and inline comments explaining each variable.
- `docs/superpowers/specs/`: Design specification documents.
- `docs/superpowers/plans/`: Implementation plan documents.
- No per-module README files exist.

## Files That Must Never Be Committed

Per `terraform/.gitignore`:
- `*.tfvars` (contains real secrets)
- `*.tfstate`, `*.tfstate.backup`
- `.terraform/`
- `**/config-assessforge` (kubeconfig)

---

*Convention analysis: 2026-04-09*
