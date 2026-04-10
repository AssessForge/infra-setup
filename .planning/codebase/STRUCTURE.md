# Codebase Structure

**Analysis Date:** 2026-04-09

## Directory Layout

```
infra-setup/
├── .claude/                          # Claude Code settings
│   ├── settings.json
│   └── settings.local.json
├── .gitignore                        # Root gitignore
├── docs/
│   └── superpowers/
│       ├── plans/
│       │   └── 2026-03-16-oci-oke-argocd-infra.md    # Implementation plan
│       └── specs/
│           └── 2026-03-16-oci-oke-argocd-infra-design.md  # Design spec
├── terraform/
│   ├── .gitignore                    # Ignores .terraform/, *.tfstate, *.tfvars, etc.
│   ├── README.md                     # Terraform usage instructions
│   ├── infra/                        # ROOT MODULE 1: OCI cloud resources
│   │   ├── main.tf                   # Module orchestration with dependency graph
│   │   ├── variables.tf              # Root-level input variables
│   │   ├── outputs.tf                # Cluster ID, vault OCID, bastion, kubeconfig cmd
│   │   ├── versions.tf               # Provider versions + S3 backend config
│   │   ├── terraform.tfvars.example  # Example variable values
│   │   ├── .terraform.lock.hcl       # Provider lock file
│   │   └── modules/
│   │       ├── oci-network/          # VCN, subnets, gateways, NSGs, flow logs
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       ├── oci-iam/              # Dynamic groups, IAM policies
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       ├── oci-oke/              # OKE cluster, node pool, bastion, kubeconfig
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       ├── oci-vault/            # KMS vault, master key, GitHub OAuth secrets
│   │       │   ├── main.tf
│   │       │   ├── variables.tf
│   │       │   └── outputs.tf
│   │       └── oci-cloud-guard/      # Cloud Guard, detector/responder recipes, alerts
│   │           ├── main.tf
│   │           ├── variables.tf
│   │           └── outputs.tf
│   └── k8s/                          # ROOT MODULE 2: Kubernetes services
│       ├── main.tf                   # Module orchestration + remote state data source
│       ├── variables.tf              # Root-level input variables
│       ├── outputs.tf                # ArgoCD namespace/hostname, LB IP
│       ├── versions.tf               # Provider versions + S3 backend config
│       ├── terraform.tfvars.example  # Example variable values
│       ├── .terraform.lock.hcl       # Provider lock file
│       └── modules/
│           ├── ingress-nginx/        # Nginx ingress controller + OCI LB
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   ├── outputs.tf
│           │   └── versions.tf
│           ├── external-secrets/     # ESO, ClusterSecretStore, ExternalSecret, argocd ns
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   ├── outputs.tf
│           │   └── versions.tf
│           ├── argocd/               # ArgoCD Helm, Ingress, AppProject
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   ├── outputs.tf
│           │   └── versions.tf
│           ├── kyverno/              # Kyverno Helm + 6 ClusterPolicies
│           │   ├── main.tf
│           │   ├── variables.tf
│           │   ├── outputs.tf
│           │   └── versions.tf
│           └── network-policies/     # NetworkPolicies for argocd namespace
│               ├── main.tf
│               ├── variables.tf
│               ├── outputs.tf
│               └── versions.tf
└── .planning/                        # Planning artifacts (not committed)
    └── codebase/                     # Codebase analysis docs
```

## Module Organization

### Two Root Modules

The project uses two independent Terraform root modules that must be applied in order:

1. **`terraform/infra/`** -- OCI provider only (`oracle/oci ~> 8.0`)
2. **`terraform/k8s/`** -- Helm (`~> 3.0`), Kubernetes (`~> 3.0`), kubectl (`alekc/kubectl ~> 2.0`), random (`~> 3.8`)

### Module Dependency Graph

**Infra layer (`terraform/infra/main.tf`):**

```
oci_network ──┐
              ├──> oci_oke ──> oci_vault
oci_iam ──────┘

oci_cloud_guard  (independent, runs in parallel with everything)
```

**K8s layer (`terraform/k8s/main.tf`):**

```
terraform_remote_state.infra
         │
         v
ingress_nginx ──> external_secrets ──> argocd ──┬──> kyverno
                                                └──> network_policies
```

### Module Interface Pattern

Every module follows the same three-file structure:
- `main.tf` -- resource definitions
- `variables.tf` -- input variables with descriptions and defaults
- `outputs.tf` -- output values exposed to the parent

K8s modules additionally include:
- `versions.tf` -- `required_providers` block (providers are configured in root, declared in modules)

### State Coupling

The k8s root module reads infra outputs via `data.terraform_remote_state.infra`:
- `vault_ocid` is consumed by the `external-secrets` module
- State is stored in OCI Object Storage at `assessforge-tfstate` bucket
- Infra state key: `infra/terraform.tfstate`
- K8s state key: `k8s/terraform.tfstate`

## Key Files

**Entry Points:**
- `terraform/infra/main.tf`: Infra root -- defines locals (freeform_tags), instantiates 5 modules with dependency ordering
- `terraform/k8s/main.tf`: K8s root -- reads remote state, instantiates 5 modules with sequential dependency chain

**Configuration:**
- `terraform/infra/versions.tf`: Terraform >= 1.5.0, OCI provider ~> 8.0, S3 backend for infra state
- `terraform/k8s/versions.tf`: Terraform >= 1.5.0, Helm/K8s/kubectl/random providers, S3 backend for k8s state
- `terraform/infra/terraform.tfvars.example`: Template for infra variables (tenancy, compartment, region, GitHub OAuth)
- `terraform/k8s/terraform.tfvars.example`: Template for k8s variables (region, Object Storage endpoint, ArgoCD hostname, GitHub org)

**Core Logic (infra modules):**
- `terraform/infra/modules/oci-network/main.tf`: 283 lines -- VCN, IGW, NAT GW, Service GW, route tables, 4 NSGs with rules, 2 subnets, VCN flow logs
- `terraform/infra/modules/oci-oke/main.tf`: 160 lines -- OKE cluster config, A1.Flex node pool, Bastion Service, kubeconfig generation
- `terraform/infra/modules/oci-vault/main.tf`: 61 lines -- KMS Vault, AES-256 key, 2 secrets
- `terraform/infra/modules/oci-iam/main.tf`: 42 lines -- workload identity dynamic group, ESO and OKE IAM policies
- `terraform/infra/modules/oci-cloud-guard/main.tf`: 115 lines -- Cloud Guard enablement, recipes, target, ONS alerts

**Core Logic (k8s modules):**
- `terraform/k8s/modules/argocd/main.tf`: 225 lines -- Helm release with full security config, Dex GitHub OAuth, RBAC, Ingress, AppProject
- `terraform/k8s/modules/kyverno/main.tf`: 251 lines -- Helm release + 6 enforced ClusterPolicies
- `terraform/k8s/modules/network-policies/main.tf`: 183 lines -- deny-all baseline + 6 allow rules for argocd namespace
- `terraform/k8s/modules/external-secrets/main.tf`: 85 lines -- ESO Helm, ClusterSecretStore, argocd namespace, ExternalSecret
- `terraform/k8s/modules/ingress-nginx/main.tf`: 48 lines -- Helm release with OCI LB annotations

**Documentation:**
- `docs/superpowers/specs/2026-03-16-oci-oke-argocd-infra-design.md`: Original design specification
- `docs/superpowers/plans/2026-03-16-oci-oke-argocd-infra.md`: Implementation plan
- `terraform/README.md`: Usage instructions

## Naming Conventions

**Files:**
- All Terraform files use standard names: `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- No custom file splitting within modules (all resources in `main.tf`)
- Example tfvars: `terraform.tfvars.example`

**Directories:**
- Infra modules: `oci-{service}` (e.g., `oci-network`, `oci-oke`, `oci-vault`, `oci-iam`, `oci-cloud-guard`)
- K8s modules: `{tool-name}` (e.g., `argocd`, `ingress-nginx`, `external-secrets`, `kyverno`, `network-policies`)
- Kebab-case for all directory names

**Resources:**
- OCI resources use `assessforge-` prefix in display names (e.g., `assessforge-vcn`, `assessforge-oke-audit-logs`)
- Terraform resource names use `main` for primary resources (e.g., `oci_core_vcn.main`, `oci_containerengine_cluster.main`)
- Descriptive suffixes for secondary resources (e.g., `oci_core_route_table.public`, `oci_core_route_table.private`)

**Variables:**
- Snake_case for all variable names
- OCIDs suffixed with `_ocid` (e.g., `compartment_ocid`, `tenancy_ocid`, `vault_ocid`)
- Subnet/NSG IDs suffixed with `_id` (e.g., `vcn_id`, `public_subnet_id`, `workers_nsg_id`)
- CIDRs suffixed with `_cidr` (e.g., `vcn_cidr`, `bastion_allowed_cidr`)

**Tags:**
- All OCI resources receive `freeform_tags = { project = "argocd-assessforge" }`
- All K8s resources labeled `app.kubernetes.io/managed-by: terraform`

**Helm Releases:**
- Release name matches chart name (e.g., `argocd`, `ingress-nginx`, `kyverno`, `external-secrets`)
- Each gets its own namespace matching the release name

## Where to Add New Code

**New OCI infrastructure resource:**
1. Create `terraform/infra/modules/oci-{resource-name}/` with `main.tf`, `variables.tf`, `outputs.tf`
2. Add module block in `terraform/infra/main.tf` with appropriate `depends_on`
3. Add any new root variables to `terraform/infra/variables.tf`
4. Expose outputs in `terraform/infra/outputs.tf` if needed by k8s layer

**New Kubernetes service/tool:**
1. Create `terraform/k8s/modules/{tool-name}/` with `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
2. Add module block in `terraform/k8s/main.tf` with appropriate `depends_on` in the chain
3. If the module needs infra outputs, pass them from `data.terraform_remote_state.infra.outputs.{name}`
4. Add any new root variables to `terraform/k8s/variables.tf`
5. Add `required_providers` in the module's `versions.tf` for any providers it uses

**New Kyverno policy:**
- Add a new `kubectl_manifest` resource in `terraform/k8s/modules/kyverno/main.tf`
- Follow existing pattern: `depends_on = [helm_release.kyverno]`, use `local.excluded_namespaces` for system namespace exclusions

**New NetworkPolicy for argocd namespace:**
- Add a new `kubectl_manifest` resource in `terraform/k8s/modules/network-policies/main.tf`
- Follow existing pattern: `depends_on = [kubectl_manifest.deny_all_default]`

**New variable for existing module:**
- Add to module's `variables.tf`, pass from root `main.tf`, add to root `variables.tf`, update `terraform.tfvars.example`

## Special Directories

**`.terraform/` (in both `terraform/infra/` and `terraform/k8s/`):**
- Purpose: Terraform provider cache and plugin binaries
- Generated: Yes (by `terraform init`)
- Committed: No (gitignored)

**`.planning/`:**
- Purpose: Codebase analysis and planning documents
- Generated: By tooling
- Committed: No

**`docs/superpowers/`:**
- Purpose: Design specs and implementation plans
- Generated: No (hand-written)
- Committed: Yes

---

*Structure analysis: 2026-04-09*
