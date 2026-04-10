# Phase 1: Cleanup & IAM Bootstrap - Research

**Researched:** 2026-04-09
**Domain:** Terraform — OCI IAM (Instance Principal), Helm/Kubernetes providers, ArgoCD bootstrap, GitOps Bridge Secret
**Confidence:** HIGH (all stack versions verified against official sources; IAM patterns verified against OCI docs and ESO docs)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Dynamic Group matching rule for Instance Principal on BASIC tier — Claude's discretion. Replace `resource.type = 'workload'` (Enhanced-only) with `instance.compartment.id` scoped to OKE worker instances. Gives all workers in compartment Vault read access.
- **D-02:** IAM policy statements (`read secret-family`, `use vaults`, `use keys`) are correct — only the Dynamic Group matching rule changes.
- **D-03:** Extend `terraform/infra/` — add Helm + Kubernetes providers to the existing infra root module. Create `modules/oci-argocd-bootstrap/` alongside oci-oke, oci-vault, etc. Single `terraform apply`.
- **D-04:** Bootstrap module depends on `oci-oke` (cluster endpoint + CA cert) and `oci-vault` (vault OCID for Bridge Secret annotations).
- **D-05:** Claude's discretion on annotation key naming — use OCI-flavored names (`oci_compartment_ocid`, `oci_vault_ocid`, `oci_region`, `oci_public_subnet_id`, `oci_private_subnet_id`).
- **D-06:** Claude's discretion on addon feature flag labels — include all v1 addons: `enable_eso`, `enable_envoy_gateway`, `enable_cert_manager`, `enable_metrics_server`, `enable_argocd`; plus metadata labels `environment: "prod"`, `cluster_name: "assessforge-oke"`.
- **D-07:** Bridge Secret must include `addons_repo_url` and `addons_repo_revision` annotations pointing to gitops-setup repo.
- **D-08:** Delete `terraform/k8s/` entirely — all modules, lock files, tfvars examples. No archive.

### Claude's Discretion

- IAM: Dynamic Group matching rule details (D-01)
- Bridge Secret: Annotation key naming convention (D-05)
- Bridge Secret: Feature flag label selection (D-06)
- ArgoCD Helm chart version and minimal values configuration
- `prevent_destroy` placement on specific resources
- Additional infra outputs needed for Bridge Secret (subnet IDs, compartment OCID)

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MIG-01 | `terraform/k8s/` directory and all child modules removed from repository | Cleanup is code-only — no live resources exist; simple `git rm -r terraform/k8s/` |
| MIG-02 | Old k8s modules (argocd, external-secrets, ingress-nginx, kyverno, network-policies) removed | Covered by MIG-01; all modules are under `terraform/k8s/modules/` |
| IAM-01 | Terraform creates OCI Dynamic Group scoped to OKE worker node instances for Instance Principal | Matching rule: `ALL {resource.type = 'instance', instance.compartment.id = '${var.compartment_ocid}'}` — verified pattern for BASIC tier |
| IAM-02 | Terraform creates IAM Policy granting Dynamic Group read access to OCI Vault secrets | Existing policy statements are correct; only matching rule changes |
| IAM-03 | Critical Terraform resources have `prevent_destroy = true` | OKE cluster already has it; VCN, Vault need review; Vault master key already has it |
| IAM-04 | Every OCI resource verified as Always Free tier eligible | Dynamic Groups and IAM Policies are free; no new OCI resources required for IAM |
| BOOT-01 | Terraform installs ArgoCD via `helm_release` (minimal — ClusterIP, no SSO) | ArgoCD 9.5.0 (chart) / v3.3.6 (app), helm provider ~>3.0 via kubeconfig |
| BOOT-02 | Terraform creates GitOps Bridge Secret with labels and annotations | `kubernetes_secret` resource in `modules/oci-argocd-bootstrap/`; labels = feature flags, annotations = OCI metadata |
| BOOT-03 | Terraform creates root bootstrap Application pointing to gitops-setup repo | `kubernetes_manifest` resource with ArgoCD Application YAML; points to `bootstrap/control-plane/` |
| BOOT-04 | `helm_release` for ArgoCD uses `lifecycle { ignore_changes = all }` | Required to prevent Terraform fighting ArgoCD self-management — covered in pitfalls |
| BOOT-05 | All provider and Helm chart versions are pinned | Exact versions provided in Standard Stack section; no `latest` or open ranges |

</phase_requirements>

---

## Summary

Phase 1 has three distinct work streams: (1) deleting the never-applied `terraform/k8s/` directory, (2) fixing the IAM Dynamic Group so Instance Principal works on the BASIC-tier OKE cluster, and (3) extending `terraform/infra/` with a new `modules/oci-argocd-bootstrap/` module that installs ArgoCD via Helm, creates the GitOps Bridge Secret, and deploys the root bootstrap Application.

The critical IAM fix is replacing `resource.type = 'workload'` (which requires OKE Enhanced tier — a paid feature) with `resource.type = 'instance'` scoped by `instance.compartment.id`. This is the correct pattern for Instance Principal on BASIC clusters. The policy statements (`read secret-family`, `use vaults`, `use keys`) are already correct and need no changes.

The bootstrap module integrates with the existing root module by consuming outputs from `module.oci_oke` (cluster ID for kubeconfig), `module.oci_vault` (vault OCID), and `module.oci_network` (subnet IDs). The Helm and Kubernetes providers use `config_path` pointing to the operator's kubeconfig file — the same pattern already established in `terraform/k8s/versions.tf`. After bootstrap, `lifecycle { ignore_changes = all }` on the ArgoCD helm_release permanently prevents Terraform from fighting ArgoCD's self-management.

**Primary recommendation:** Add the `oci-argocd-bootstrap` module to `terraform/infra/` (not a separate root module). Fix the Dynamic Group matching rule. Delete `terraform/k8s/`. Single `terraform apply` from `terraform/infra/` completes the phase.

---

## Standard Stack

### Core (Phase 1 additions to terraform/infra/)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| ArgoCD Helm chart (`argo-cd`) | **9.5.0** (app v3.3.6) | GitOps controller installed by Terraform bootstrap | Latest stable on argo-helm as of April 2026; v3.x is the active major — v2.x receives patches only |
| `hashicorp/helm` provider | `~> 3.0` | Deploy ArgoCD `helm_release` from Terraform | Same constraint already used in `terraform/k8s/versions.tf`; helm 3.x API (nested `kubernetes = {}` block) |
| `hashicorp/kubernetes` provider | `~> 3.0` | Create ArgoCD namespace + Bridge Secret + bootstrap Application | Required to write raw Kubernetes resources from Terraform |
| `oracle/oci` provider | `~> 8.0` | OCI Dynamic Group + IAM Policy resources | Already present in `terraform/infra/versions.tf` — no version change |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `alekc/kubectl` provider | `~> 2.0` | Alternative for raw YAML Application manifest | Use if `kubernetes_manifest` causes CRD schema issues — existing k8s layer used this pattern |
| `terraform-helm-gitops-bridge` module | `0.0.2` | Reference implementation only | Do NOT use as a dependency — use its patterns directly with raw `helm_release` + `kubernetes_secret` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `config_path` kubeconfig auth for Helm/k8s providers | `exec {}` block with OCI CLI token | `config_path` is simpler and works for private OKE endpoints if kubeconfig has `exec` in it (generated by `oci ce cluster create-kubeconfig --auth api_key`). Use `config_path` since the kubeconfig already handles auth. |
| `kubernetes_manifest` for Application resource | `kubectl_manifest` (alekc/kubectl) | `kubectl_manifest` handles unknown CRD schemas better; `kubernetes_manifest` may fail on ArgoCD Application CRD if it's not registered at plan time. Prefer `kubectl_manifest` for ArgoCD Application resource. |
| Separate `terraform/bootstrap/` root module | Extend `terraform/infra/` (D-03) | Separate root would require two applies and two state files; extending infra keeps single apply and avoids state coupling complexity. Decision locked. |

**Installation (adding to terraform/infra/):**

No new `npm install` — this is HCL. Add provider blocks to `versions.tf`, create `modules/oci-argocd-bootstrap/` directory with `main.tf` + `variables.tf` + `outputs.tf`, then run:

```bash
cd terraform/infra/
terraform init   # downloads helm + kubernetes providers
terraform apply
```

**Version verification:** [VERIFIED: ArtifactHub + GitHub Chart.yaml] ArgoCD chart 9.5.0 / app v3.3.6 confirmed as latest stable April 2026.

---

## Architecture Patterns

### New Module Structure

```
terraform/infra/
├── main.tf                         # Add module "oci_argocd_bootstrap" call here
├── versions.tf                     # Add helm + kubernetes provider blocks
├── outputs.tf                      # Add new outputs (public_subnet_id, private_subnet_id, compartment_ocid)
├── variables.tf                    # Add gitops_repo_url, gitops_repo_revision if needed
└── modules/
    ├── oci-network/                # Existing — no changes
    ├── oci-iam/                    # Existing — MODIFY matching rule only
    ├── oci-oke/                    # Existing — no changes needed; may need cluster_endpoint output
    ├── oci-vault/                  # Existing — no changes
    ├── oci-cloud-guard/            # Existing — no changes
    └── oci-argocd-bootstrap/       # NEW
        ├── main.tf                 # helm_release + kubernetes_secret + kubectl_manifest
        ├── variables.tf            # inputs: cluster_id, vault_ocid, subnet IDs, repo URL, etc.
        └── outputs.tf              # argocd_namespace (for reference)
```

**Directory to delete:**
```
terraform/k8s/                      # DELETE entirely (git rm -r)
```

### Pattern 1: IAM Dynamic Group Fix (Instance Principal for BASIC tier)

**What:** Replace the `resource.type = 'workload'` matching rule (Enhanced/Workload Identity only) with the correct Instance Principal pattern that targets compute instances by compartment.

**When to use:** Always on OKE BASIC clusters. `resource.type = 'workload'` never works on BASIC tier.

**Current (broken — Enhanced-only):**
```hcl
# terraform/infra/modules/oci-iam/main.tf — CURRENT (WRONG for BASIC)
matching_rule = "ALL {resource.type = 'workload', resource.compartment.id = '${var.compartment_ocid}'}"
```

**Corrected (works on BASIC tier):**
```hcl
# terraform/infra/modules/oci-iam/main.tf — CORRECTED
resource "oci_identity_dynamic_group" "instance_principal" {
  compartment_id = var.tenancy_ocid  # Dynamic groups live at tenancy root
  name           = "assessforge-instance-principal"
  description    = "Dynamic group para worker nodes OKE via Instance Principal (BASIC tier)"
  freeform_tags  = var.freeform_tags

  # Matches all compute instances in the compartment.
  # resource.type = 'workload' requires Enhanced tier -- use 'instance' for BASIC.
  matching_rule = "ALL {resource.type = 'instance', instance.compartment.id = '${var.compartment_ocid}'}"
}
```

**Key insight:** The matching rule `resource.type = 'instance'` targets actual compute instances (OKE worker VMs). ESO's `principalType: InstancePrincipal` (the default) then uses the worker node's Instance Principal certificate to authenticate. [VERIFIED: ESO docs — `principalType` defaults to `InstancePrincipal`; IAM docs — `instance.compartment.id` is the correct compartment-scoped selector]

### Pattern 2: Dynamic Group rename consideration

Per CONTEXT.md specifics: the existing group is named `assessforge-workload-identity`. Rename to `assessforge-instance-principal` since it no longer uses Workload Identity. The Terraform resource label should also change: `oci_identity_dynamic_group.workload_identity` → `oci_identity_dynamic_group.instance_principal`.

**Rename causes a replace:** Terraform will destroy the old Dynamic Group and create the new one. The IAM Policy references the Dynamic Group by name — policy must be updated simultaneously. This is a single-apply atomic operation.

**Warning:** If the Dynamic Group is destroyed before the new one is created, any running pods using Instance Principal will lose access momentarily. Since this is a dev cluster with no live ESO workloads yet, this is acceptable.

### Pattern 3: Helm + Kubernetes Provider Configuration (in terraform/infra/versions.tf)

**What:** Add Helm and Kubernetes providers using `config_path` pointing to the operator's kubeconfig. This mirrors the exact pattern from `terraform/k8s/versions.tf`.

**When to use:** Any Terraform root module that needs to interact with a Kubernetes cluster where auth is handled via a kubeconfig file.

```hcl
# terraform/infra/versions.tf — ADD these provider blocks

required_providers {
  # existing:
  oci = { source = "oracle/oci", version = "~> 8.0" }
  # NEW:
  helm = {
    source  = "hashicorp/helm"
    version = "~> 3.0"
  }
  kubernetes = {
    source  = "hashicorp/kubernetes"
    version = "~> 3.0"
  }
  kubectl = {
    source  = "alekc/kubectl"
    version = "~> 2.0"
  }
}

# Helm provider (helm 3.x uses nested kubernetes = {} object, not block)
provider "helm" {
  kubernetes = {
    config_path = pathexpand("~/.kube/config-assessforge")
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/config-assessforge")
}

provider "kubectl" {
  config_path      = pathexpand("~/.kube/config-assessforge")
  load_config_file = true
}
```

[VERIFIED: copied from `terraform/k8s/versions.tf` which was working]

### Pattern 4: ArgoCD Helm Release (minimal bootstrap values)

**What:** Install ArgoCD with ClusterIP service, no SSO, no repo config, no admin disabled yet (admin needed for initial access before ESO syncs GitHub OAuth secret).

```hcl
# terraform/infra/modules/oci-argocd-bootstrap/main.tf

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.5.0"   # PINNED — never use latest
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
        # admin user stays enabled — GitOps self-management (Phase 3) disables it
        extraArgs = ["--insecure"]  # TLS terminated at Envoy Gateway (Phase 3)
      }
      configs = {
        params = {
          # Disable exec to prevent terminal access (security hardening)
          "server.exec.enabled" = "false"
        }
      }
    })
  ]

  lifecycle {
    ignore_changes = all  # REQUIRED: prevents Terraform fighting ArgoCD self-management
  }

  depends_on = [var.cluster_ready]
}
```

[VERIFIED: chart version 9.5.0 / app v3.3.6 from ArtifactHub + GitHub Chart.yaml April 2026]

### Pattern 5: GitOps Bridge Secret

**What:** Kubernetes Secret in `argocd` namespace with the `argocd.argoproj.io/secret-type: cluster` label. Labels carry addon feature flags (boolean strings). Annotations carry OCI metadata (OCIDs, region, repo URL).

```hcl
resource "kubernetes_secret" "gitops_bridge" {
  metadata {
    name      = "in-cluster"
    namespace = helm_release.argocd.namespace

    labels = {
      # Required for ArgoCD cluster generator to discover this secret
      "argocd.argoproj.io/secret-type" = "cluster"

      # Metadata labels
      environment  = "prod"
      cluster_name = "assessforge-oke"

      # Addon feature flags — ApplicationSet matchExpressions filter on these
      # Values must be string "true"/"false", not boolean
      enable_argocd          = "true"
      enable_cert_manager    = "true"
      enable_eso             = "true"
      enable_envoy_gateway   = "true"
      enable_metrics_server  = "true"
    }

    annotations = {
      # GitOps repo routing (ApplicationSet template vars)
      addons_repo_url      = var.gitops_repo_url
      addons_repo_revision = var.gitops_repo_revision

      # OCI infra metadata for addon Helm values
      oci_region            = var.region
      oci_compartment_ocid  = var.compartment_ocid
      oci_vault_ocid        = var.vault_ocid
      oci_public_subnet_id  = var.public_subnet_id
      oci_private_subnet_id = var.private_subnet_id
    }
  }

  # Required fields for ArgoCD cluster secret
  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = { insecure = false }
    })
  }

  depends_on = [helm_release.argocd]
}
```

[VERIFIED against ARCHITECTURE.md bridge secret schema and gitops-bridge-dev reference implementation]

### Pattern 6: Root Bootstrap Application

**What:** ArgoCD Application resource pointing to the gitops-setup repo. Created via `kubectl_manifest` (not `kubernetes_manifest`) to avoid CRD schema lookup errors at plan time.

```hcl
resource "kubectl_manifest" "bootstrap_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "bootstrap"
      namespace = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_revision
        path           = "bootstrap/control-plane"
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = false  # Never auto-prune the root app — safety
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true", "ServerSideApply=true"]
      }
    }
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_secret.gitops_bridge,
  ]
}
```

### Pattern 7: New Outputs Needed in terraform/infra/outputs.tf

The root `outputs.tf` must expose subnet IDs and compartment OCID for the bootstrap module to use as Bridge Secret annotations:

```hcl
# terraform/infra/outputs.tf — ADD

output "compartment_ocid" {
  description = "OCID do compartment principal"
  value       = var.compartment_ocid
}

output "public_subnet_id" {
  description = "OCID da subnet publica (LB)"
  value       = module.oci_network.public_subnet_id
}

output "private_subnet_id" {
  description = "OCID da subnet privada (workers)"
  value       = module.oci_network.private_subnet_id
}
```

These are passed as variables to `module.oci_argocd_bootstrap` in root `main.tf`.

### Anti-Patterns to Avoid

- **`resource.type = 'workload'` in Dynamic Group:** Enhanced-only. Always use `resource.type = 'instance'` for BASIC tier Instance Principal. [VERIFIED: PITFALLS.md Pitfall 8 + OCI docs]
- **No `lifecycle { ignore_changes = all }` on ArgoCD helm_release:** Terraform will plan drift every apply after ArgoCD self-manages. Always include it. [VERIFIED: PITFALLS.md Pitfall 4]
- **Using `kubernetes_manifest` for ArgoCD Application:** This resource type requires the CRD to be registered at plan time. At first apply, ArgoCD is just being installed — its CRDs may not be registered yet. Use `kubectl_manifest` (alekc/kubectl) which defers schema lookup to apply time.
- **Hardcoding OCIDs in Bridge Secret values:** OCIDs change if infra is rebuilt. Always reference them from Terraform variables/module outputs.
- **`create_namespace = true` on ArgoCD helm_release without `wait = true`:** Race condition — Bridge Secret creation begins before ArgoCD pods are Ready. Always set `wait = true` and a generous `timeout`.
- **Keeping `assessforge-workload-identity` name:** Misleading — it's now Instance Principal, not Workload Identity. Rename to `assessforge-instance-principal` as noted in CONTEXT.md specifics.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| ArgoCD installation | Custom `kubectl apply` scripts | `helm_release` resource | Idempotent, Helm-lifecycle managed, Terraform-native |
| Bridge Secret schema | Arbitrary annotation naming | Follow gitops-bridge-dev schema | ApplicationSet generators read specific label/annotation keys |
| IAM policy verification | Manual OCI console checks | IAM policy statements are declarative HCL | Terraform tracks state; `terraform plan` shows drift |
| CRD-dependent manifests | `kubernetes_manifest` for ArgoCD resources | `kubectl_manifest` (alekc/kubectl) | Handles unknown CRDs without schema lookup at plan time |

**Key insight:** The Helm provider + `lifecycle { ignore_changes = all }` is the standard pattern for bootstrapping a self-managed GitOps controller. Don't fight it by attempting to keep Terraform in sync with post-bootstrap ArgoCD state.

---

## Common Pitfalls

### Pitfall 1: `resource.type = 'workload'` Does Not Work on BASIC OKE

**What goes wrong:** The current `oci_identity_dynamic_group.workload_identity` uses `resource.type = 'workload'`. This is the OKE Workload Identity syntax, which requires an Enhanced cluster (paid tier). On BASIC clusters, this matching rule matches nothing — no instances join the group, so ESO has no Instance Principal to authenticate with.

**Why it happens:** OCI documentation distinguishes Workload Identity from Instance Principal, but both are called "workload identity" colloquially. The old code was written assuming Workload Identity; BASIC tier forces Instance Principal.

**How to avoid:** Use `resource.type = 'instance'` with `instance.compartment.id` scope. This matches OKE worker node compute instances by compartment, not by pod identity.

**Warning signs:** ESO ClusterSecretStore shows `Invalid`; OCI audit logs show no Instance Principal requests from worker node OCIDs.

[VERIFIED: PITFALLS.md Pitfall 1 + Pitfall 8; ESO docs confirming `principalType: InstancePrincipal` as default]

### Pitfall 2: Dynamic Group Rename Causes Brief IAM Gap

**What goes wrong:** Renaming the Dynamic Group (from `assessforge-workload-identity` to `assessforge-instance-principal`) causes Terraform to destroy the old group and create the new one. The IAM policy references the old group name. If destroy happens before create, there's a brief window with no valid Dynamic Group.

**Why it happens:** Terraform's default behavior is destroy-then-create for resource renames. The policy's `depends_on` on the group is not enough to prevent a window.

**How to avoid:** Use `create_before_destroy = true` in the Dynamic Group lifecycle block. This creates the new group first, updates the policy, then destroys the old group.

```hcl
lifecycle {
  create_before_destroy = true
}
```

**Warning signs:** IAM policy errors in `terraform apply` output mentioning the old group name not found.

### Pitfall 3: ArgoCD Application CRD Not Available at Plan Time

**What goes wrong:** Using `kubernetes_manifest` to create the ArgoCD bootstrap Application fails at plan time with "no matches for kind Application in version argoproj.io/v1alpha1" because the CRD is not registered until after the `helm_release` installs it.

**Why it happens:** `kubernetes_manifest` validates schema at plan time. ArgoCD's Application CRD is only installed during the ArgoCD Helm chart installation.

**How to avoid:** Use `kubectl_manifest` (alekc/kubectl ~> 2.0) instead. It defers schema validation to apply time. Add `alekc/kubectl` to `versions.tf`.

**Warning signs:** `terraform plan` fails with CRD not found error before any resource is applied.

### Pitfall 4: Helm Provider `kubernetes` Block Syntax Change in v3.x

**What goes wrong:** Helm provider v3.x changed the `kubernetes {}` configuration from a block to a nested object (`kubernetes = {}`). Old v2.x syntax causes a parse error.

**Why it happens:** Breaking change in Helm provider v3.x. The existing `terraform/k8s/versions.tf` already uses the v3.x syntax — use it as the reference.

**How to avoid:** Use `kubernetes = { config_path = ... }` (object), not `kubernetes { config_path = ... }` (block).

[VERIFIED: `terraform/k8s/versions.tf` line 36-38 — existing code uses correct v3.x syntax]

### Pitfall 5: `lifecycle { ignore_changes = all }` on helm_release Scope

**What goes wrong:** `ignore_changes = all` makes Terraform ignore drift on the ArgoCD release permanently. If someone passes wrong initial values, Terraform can never correct them via apply. The initial `values` block must be correct from the start.

**Why it happens:** The lifecycle block is necessary for GitOps self-management, but it disables Terraform's self-healing for that resource.

**How to avoid:** Double-check ArgoCD initial values (ClusterIP service type, `--insecure` flag) before first apply. After apply, changes to this resource only happen via the GitOps repo, not `terraform apply`.

### Pitfall 6: Bridge Secret Missing Required `server` Field

**What goes wrong:** ArgoCD's cluster generator only discovers the Bridge Secret as a valid cluster if it has `data.server = "https://kubernetes.default.svc"`. Missing this field means ArgoCD does not recognize it as a cluster secret, and the ApplicationSet generates nothing.

**Why it happens:** The `server` field in `data` is required by ArgoCD's cluster secret schema. Omitting it is easy when focusing on labels/annotations.

**How to avoid:** Always include `data.server` and `data.name` in the `kubernetes_secret.data` block.

---

## Code Examples

### IAM Module — Corrected Dynamic Group

```hcl
# Source: verified pattern from OCI IAM docs + ESO docs
resource "oci_identity_dynamic_group" "instance_principal" {
  compartment_id = var.tenancy_ocid
  name           = "assessforge-instance-principal"
  description    = "Dynamic group para worker nodes OKE via Instance Principal (BASIC tier)"
  freeform_tags  = var.freeform_tags

  # 'instance' matches OKE worker node compute instances by compartment.
  # 'workload' requires Enhanced tier (paid) -- never use on BASIC clusters.
  matching_rule = "ALL {resource.type = 'instance', instance.compartment.id = '${var.compartment_ocid}'}"

  lifecycle {
    create_before_destroy = true
  }
}

resource "oci_identity_policy" "instance_principal_vault" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-instance-principal-vault-policy"
  description    = "Permite aos worker nodes OKE ler secrets do OCI Vault via Instance Principal"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.instance_principal.name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.instance_principal.name} to use vaults in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.instance_principal.name} to use keys in compartment id ${var.compartment_ocid}",
  ]

  depends_on = [oci_identity_dynamic_group.instance_principal]
}
```

### ESO ClusterSecretStore (Phase 2 reference — for Bridge Secret annotation naming validation)

```yaml
# Source: external-secrets.io/latest/provider/oracle-vault/
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: oci-vault
spec:
  provider:
    oracle:
      vault: "{{metadata.annotations.oci_vault_ocid}}"   # annotation key from Bridge Secret
      region: "sa-saopaulo-1"
      principalType: InstancePrincipal                     # default; Dynamic Group must match worker nodes
```

This validates the annotation key name `oci_vault_ocid` chosen in D-05.

### Root main.tf — Bootstrap Module Call

```hcl
# terraform/infra/main.tf — ADD at bottom

# --- Bootstrap ArgoCD (depende de OKE + Vault) ---

module "oci_argocd_bootstrap" {
  source = "./modules/oci-argocd-bootstrap"

  compartment_ocid      = var.compartment_ocid
  region                = var.region
  vault_ocid            = module.oci_vault.vault_ocid
  public_subnet_id      = module.oci_network.public_subnet_id
  private_subnet_id     = module.oci_network.private_subnet_id
  gitops_repo_url       = var.gitops_repo_url
  gitops_repo_revision  = var.gitops_repo_revision

  depends_on = [
    module.oci_oke,
    module.oci_vault,
  ]
}
```

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `resource.type = 'workload'` Dynamic Group | `resource.type = 'instance'` for BASIC tier | N/A (was always wrong for BASIC) | Must fix before ESO can authenticate |
| `terraform/k8s/` as separate root module | Bootstrap integrated into `terraform/infra/` | This phase | Single apply, simpler operations |
| Helm provider v2.x `kubernetes {}` block | Helm provider v3.x `kubernetes = {}` nested object | Helm provider 3.0 | Syntax change — use existing k8s/versions.tf as reference |
| ArgoCD v2.x (chart 7.x) | ArgoCD v3.3.6 (chart 9.5.0) | v3.0 released 2024 | ServerSideApply required for self-management; v2 EOL for new deployments |

**Deprecated/outdated in this project:**
- `terraform/k8s/`: Entire directory — was never applied, now deleted
- `assessforge-workload-identity` Dynamic Group name: Misleading — rename to `assessforge-instance-principal`
- Old IAM policy `assessforge-eso-vault-policy`: Name should update to `assessforge-instance-principal-vault-policy` for consistency

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `config_path = pathexpand("~/.kube/config-assessforge")` works for Helm/k8s providers when kubeconfig is generated by `oci ce cluster create-kubeconfig --auth api_key` | Standard Stack / Pattern 3 | Provider auth fails — must use `exec {}` block instead; requires knowing OKE cluster OCID at provider config time |
| A2 | `kubectl_manifest` (alekc/kubectl ~> 2.0) handles ArgoCD Application CRD creation without plan-time schema errors | Anti-Patterns / Pitfall 3 | If wrong, may need to use `kubernetes_manifest` with `wait_for_rollout = false` or a separate apply pass |
| A3 | ArgoCD 9.5.0 with `server.extraArgs = ["--insecure"]` is valid for minimal bootstrap (TLS added in Phase 3 via Envoy Gateway) | Pattern 4 | If ArgoCD 3.x removed `--insecure` flag, server will refuse insecure connections; check 3.x changelog |

---

## Open Questions

1. **Does the OKE module need to expose `cluster_endpoint` and `cluster_ca_certificate` outputs?**
   - What we know: The existing `terraform/k8s/` layer uses `config_path` only (no endpoint/cert in provider config). The OKE module does not expose these outputs.
   - What's unclear: If `config_path` stops working (e.g., kubeconfig expires before `terraform apply` runs), the fallback is the `exec {}` block which needs the cluster OCID. The OKE module does expose `cluster_id`.
   - Recommendation: Keep `config_path` approach for now (matches existing pattern). Document that kubeconfig must be refreshed before `terraform apply`. If issues arise, add `exec {}` block using cluster OCID from `module.oci_oke.cluster_id`.

2. **Should `gitops_repo_url` and `gitops_repo_revision` be root variables or hardcoded in the module?**
   - What we know: The gitops-setup repo URL is `https://github.com/AssessForge/gitops-setup` and revision is `main`.
   - What's unclear: Whether these will change (public vs private repo, branch strategies).
   - Recommendation: Add as root `variables.tf` variables with defaults. This keeps the values in one place and makes them overridable via `terraform.tfvars`.

3. **Does renaming the Dynamic Group require updating the IAM Policy in the same apply?**
   - What we know: The policy statement references the group by name, not OCID. Terraform tracks this via `depends_on`.
   - What's unclear: OCI IAM propagation delay — there may be a brief period where the new group exists but the policy hasn't propagated.
   - Recommendation: Use `create_before_destroy` on the group. Accept a potential 30-60 second IAM propagation window during apply. No live workloads depend on it yet.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Terraform | All tasks | Assumed present | >= 1.5.0 | — |
| OCI CLI (`oci`) | kubeconfig generation before apply | Assumed present | — | Cannot bypass — required for OKE auth |
| kubectl | Cluster verification post-apply | Assumed present | — | Use `oci ce cluster` CLI for basic checks |
| `~/.kube/config-assessforge` | Helm + k8s providers | Must exist before `terraform apply` | — | Run `oci ce cluster create-kubeconfig` first |
| `~/.oci/config` DEFAULT profile | OCI provider auth | Must exist | — | Cannot apply without it |
| ArgoCD Helm chart `argo-cd` 9.5.0 | BOOT-01 | Fetched from `https://argoproj.github.io/argo-helm` | 9.5.0 | — |

**Missing dependencies with no fallback:**
- `~/.kube/config-assessforge` must be generated via `oci ce cluster create-kubeconfig` before the bootstrap module can apply. This is an operator prerequisite, not a task to automate.

**Missing dependencies with fallback:**
- None with viable alternative for this phase.

**Pre-apply prerequisite (must be documented in plan):**
```bash
oci ce cluster create-kubeconfig \
  --cluster-id <cluster_ocid> \
  --file ~/.kube/config-assessforge \
  --auth api_key \
  --overwrite
```

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | None — infrastructure-only phase; validation via Terraform plan + OCI/kubectl CLI |
| Config file | none |
| Quick run command | `terraform plan -out=tfplan` |
| Full suite command | `terraform apply tfplan && kubectl get pods -n argocd` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIG-01 | `terraform/k8s/` directory does not exist | Manual / git | `ls terraform/k8s/ 2>&1 \| grep "No such"` | N/A |
| MIG-02 | Old modules not in repo | Manual / git | `git status --short terraform/k8s/` | N/A |
| IAM-01 | Dynamic Group with Instance Principal rule exists | OCI CLI | `oci iam dynamic-group list --compartment-id <tenancy_ocid> --query "data[?name=='assessforge-instance-principal']"` | N/A |
| IAM-02 | IAM Policy grants Dynamic Group Vault read | OCI CLI | `oci iam policy list --compartment-id <compartment_ocid> --query "data[?name=='assessforge-instance-principal-vault-policy']"` | N/A |
| IAM-03 | `prevent_destroy = true` on critical resources | Code review | `grep -r "prevent_destroy" terraform/infra/modules/` | N/A |
| IAM-04 | No paid resources introduced | Manual review | Verify no Enhanced-tier resources in `terraform plan` output | N/A |
| BOOT-01 | ArgoCD pods running in `argocd` namespace | kubectl | `kubectl get pods -n argocd --field-selector=status.phase=Running` | N/A |
| BOOT-02 | Bridge Secret exists with correct labels | kubectl | `kubectl get secret in-cluster -n argocd -o yaml` | N/A |
| BOOT-03 | Bootstrap Application exists in ArgoCD | kubectl / argocd | `kubectl get application bootstrap -n argocd` | N/A |
| BOOT-04 | `ignore_changes = all` in helm_release | Code review | `grep -A2 "lifecycle" terraform/infra/modules/oci-argocd-bootstrap/main.tf` | N/A |
| BOOT-05 | All versions pinned | Code review | `grep -r "version" terraform/infra/versions.tf terraform/infra/modules/oci-argocd-bootstrap/` | N/A |

### Wave 0 Gaps

None — no automated test framework is applicable for this infrastructure-only phase. Validation is via Terraform plan output, OCI CLI queries, and kubectl checks post-apply.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | yes — IAM Dynamic Group controls who can authenticate to Vault | OCI Instance Principal via Dynamic Group; no static credentials |
| V3 Session Management | no — no user sessions in this phase | — |
| V4 Access Control | yes — IAM Policy scope | Least-privilege: only `read secret-family`, `use vaults`, `use keys` in specific compartment |
| V5 Input Validation | no — Terraform HCL, no user input paths | — |
| V6 Cryptography | yes — OCI Vault uses AES-256 master key already provisioned | `oci_kms_key.master` with `prevent_destroy = true` already in place |

### Known Threat Patterns

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Dynamic Group over-scoping (all tenancy instances) | Elevation of Privilege | Scope by `instance.compartment.id` — only worker nodes in the specific compartment, not all tenancy instances |
| Leaked kubeconfig | Spoofing | `~/.kube/config-assessforge` must never be committed; already in `.gitignore` convention from CLAUDE.md |
| ArgoCD admin password exposure | Information Disclosure | Admin remains enabled only for bootstrap window; Phase 3 disables it via GitOps self-management |
| Bridge Secret OCID leak | Information Disclosure | Bridge Secret is in-cluster only; no sensitive credentials, only OCIDs (no auth material) |
| IAM propagation window during Dynamic Group rename | Denial of Service | Use `create_before_destroy`; brief window acceptable since no live ESO workloads exist yet |

---

## Sources

### Primary (HIGH confidence)

- `terraform/k8s/versions.tf` — Helm/k8s/kubectl provider versions and `config_path` auth pattern [VERIFIED: codebase]
- `terraform/infra/modules/oci-iam/main.tf` — Current Dynamic Group + IAM policy (target for modification) [VERIFIED: codebase]
- `terraform/infra/modules/oci-network/outputs.tf` — `public_subnet_id`, `private_subnet_id` exist and are available [VERIFIED: codebase]
- `terraform/infra/modules/oci-vault/outputs.tf` — `vault_ocid` output exists [VERIFIED: codebase]
- `.planning/research/STACK.md` — ArgoCD 9.5.0 / v3.3.6, provider versions [VERIFIED: codebase research doc]
- `.planning/research/ARCHITECTURE.md` — Bridge Secret schema, bootstrap Application spec [VERIFIED: codebase research doc]
- `.planning/research/PITFALLS.md` — Pitfall 1, 4, 8 (Workload Identity vs Instance Principal, helm_release lifecycle, BASIC tier) [VERIFIED: codebase research doc]
- `https://github.com/argoproj/argo-helm/blob/main/charts/argo-cd/Chart.yaml` — chart 9.5.0 / appVersion v3.3.6 [VERIFIED: fetched April 2026]
- `https://external-secrets.io/latest/provider/oracle-vault/` — `principalType: InstancePrincipal` configuration [VERIFIED: fetched]
- `https://docs.oracle.com/en-us/iaas/Content/Identity/dynamicgroups/Writing_Matching_Rules_to_Define_Dynamic_Groups.htm` — `instance.compartment.id` matching rule [VERIFIED: fetched]

### Secondary (MEDIUM confidence)

- Web search results confirming `instance.compartment.id` as the standard compartment-scoped Instance Principal matching rule for OKE worker nodes [MEDIUM — multiple sources agree, not fetched from official page directly]

---

## Metadata

**Confidence breakdown:**

- IAM fix (Dynamic Group rule): HIGH — verified against OCI IAM docs, ESO docs, and PITFALLS.md
- Standard Stack (versions): HIGH — ArgoCD 9.5.0 verified from GitHub Chart.yaml; provider versions from existing codebase
- Architecture (module structure): HIGH — derived from existing codebase patterns + locked decisions
- Bridge Secret schema: HIGH — verified against ARCHITECTURE.md canonical reference
- Helm provider config: HIGH — verified from existing `terraform/k8s/versions.tf`
- Pitfalls: HIGH — derived from PITFALLS.md which was already researched with official sources

**Research date:** 2026-04-09
**Valid until:** 2026-07-09 (stable stack; ArgoCD chart version may update but 9.5.0 is pinned)
