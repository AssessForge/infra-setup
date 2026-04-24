---
phase: 01-cleanup-iam-bootstrap
reviewed: 2026-04-09T00:00:00Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - terraform/infra/main.tf
  - terraform/infra/modules/oci-argocd-bootstrap/main.tf
  - terraform/infra/modules/oci-argocd-bootstrap/outputs.tf
  - terraform/infra/modules/oci-argocd-bootstrap/variables.tf
  - terraform/infra/modules/oci-iam/main.tf
  - terraform/infra/modules/oci-iam/outputs.tf
  - terraform/infra/modules/oci-network/main.tf
  - terraform/infra/outputs.tf
  - terraform/infra/variables.tf
  - terraform/infra/versions.tf
findings:
  critical: 2
  warning: 4
  info: 3
  total: 9
status: issues_found
---

# Phase 01: Code Review Report

**Reviewed:** 2026-04-09T00:00:00Z
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

This review covers the new `oci-argocd-bootstrap` module and associated refactoring of the infra root module, IAM, and network layers. The bootstrap module correctly implements the GitOps Bridge pattern — Helm install ArgoCD, write the `in-cluster` cluster secret, then create the root `bootstrap` Application. The overall structure is sound.

Two critical issues require attention before apply: the bootstrap module declares no `versions.tf`, which means the Helm, Kubernetes, and kubectl providers it uses have no required-provider constraints and will inherit from the root. This works at apply time but can cause subtle breakage when the module is used in isolation or refactored. More critically, the `oci_argocd_bootstrap` module is wired into `terraform/infra/` which is an OCI-only layer — placing Kubernetes providers in `versions.tf` at the infra root will attempt to connect to the cluster during `terraform init`/`plan`, before the cluster necessarily exists.

Four warnings cover logic gaps: the bootstrap `Application` uses `prune = false`, which is intentional but undocumented and risks orphaned resources; the ArgoCD chart version jumped significantly from the value in CLAUDE.md (7.6.12 → 9.5.0) without a comment explaining the upgrade; the `ignore_changes = all` lifecycle on `helm_release.argocd` is broad and will silently skip any future Helm value corrections applied by Terraform; and the `lb_egress_workers` NSG rule routes to the private subnet CIDR rather than the workers NSG ID, making it subnet-wide instead of NSG-scoped.

---

## Critical Issues

### CR-01: Bootstrap module has no `versions.tf` — providers are undeclared

**File:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:1`

**Issue:** The module uses three providers (`helm_release`, `kubernetes_secret`, `kubectl_manifest`) but declares no `versions.tf` with `required_providers`. Per CLAUDE.md conventions, k8s modules must each declare their own `required_providers`. Without this, Terraform cannot pin or validate provider versions for the module, and the module is not self-describing. This also violates the stated convention: "K8s modules (`terraform/k8s/modules/`) each declare their own `required_providers` in `versions.tf`."

Beyond convention, placing k8s provider calls inside `terraform/infra/` (an OCI-only root) means `versions.tf` at the infra root now must declare Helm/Kubernetes/kubectl providers — but those providers require a reachable kubeconfig at `plan` time. If the cluster does not yet exist, `terraform plan` on the infra layer will fail attempting to authenticate to Kubernetes.

**Fix:** Add a `versions.tf` to the module declaring its required providers, and move the bootstrap module to `terraform/k8s/` (the layer that already manages the cluster connection), or split it into a standalone third root with its own kubeconfig setup. If it must stay in the infra layer, the Kubernetes/Helm/kubectl provider blocks must be added to `terraform/infra/versions.tf` and the operator must ensure kubeconfig exists before running infra-layer plans.

```hcl
# terraform/infra/modules/oci-argocd-bootstrap/versions.tf
terraform {
  required_providers {
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
}
```

### CR-02: Infra root `versions.tf` declares Helm/Kubernetes/kubectl providers — breaks two-layer architecture

**File:** `terraform/infra/versions.tf:8-21`

**Issue:** `terraform/infra/versions.tf` declares `helm`, `kubernetes`, and `kubectl` as required providers (lines 8–21) alongside the OCI provider. This contradicts the documented architecture: "The infra layer uses the OCI provider only. The k8s layer uses Helm, Kubernetes, and kubectl providers. Separation avoids circular dependencies: infra creates the cluster, k8s configures it." Having Kubernetes provider blocks in the infra root means Terraform will try to read `~/.kube/config-assessforge` during every `terraform plan` on the infra layer — even on a fresh environment before any cluster exists. This breaks Day-0 apply and contradicts the layering invariant.

**Fix:** Remove `helm`, `kubernetes`, and `kubectl` from `terraform/infra/versions.tf` and relocate the `oci_argocd_bootstrap` module call to `terraform/k8s/main.tf` (after OKE exists). Add a corresponding state data source or pass the needed OCI values (vault OCID, subnet IDs) as variables via `terraform_remote_state` in the k8s layer, matching the established pattern.

```hcl
# terraform/infra/versions.tf — keep only OCI
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
    # helm / kubernetes / kubectl removed — belong in terraform/k8s/
  }
  ...
}
```

---

## Warnings

### WR-01: `prune = false` on root Application is undocumented and may orphan resources

**File:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:109`

**Issue:** The root `bootstrap` Application sets `automated.prune = false`. In a GitOps bridge pattern this is intentionally safe during initial bootstrap (avoids accidentally pruning the entire cluster if the repo is temporarily unreachable), but there is no comment explaining the intent. Operators unfamiliar with the pattern may silently leave orphaned resources in the cluster if they remove addons from the GitOps repo without understanding that pruning is disabled at the root level.

**Fix:** Add an inline comment and, once the cluster is stable, consider enabling prune on the root app or documenting in the README that child ApplicationSets should set their own prune policy.

```hcl
syncPolicy = {
  automated = {
    # prune = false no root app — evita destruicao acidental durante bootstrap.
    # Child ApplicationSets devem configurar prune = true individualmente.
    prune    = false
    selfHeal = true
  }
  ...
}
```

### WR-02: ArgoCD chart version (9.5.0) conflicts with documented pinned version (7.6.12)

**File:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:7`

**Issue:** The bootstrap module pins `version = "9.5.0"` (ArgoCD app v3.3.6 per the inline comment), while CLAUDE.md documents the pinned version as `7.6.12`. This discrepancy indicates either the documentation is stale or the version was bumped without updating project docs. Either way, the pinned version table in CLAUDE.md is now incorrect, which is a maintenance hazard. Additionally, v9.x of the argo-helm chart introduced significant values schema changes; if any downstream k8s module (now removed) was relying on old value paths, silent breakage is possible.

**Fix:** Update CLAUDE.md to reflect `9.5.0` (and ArgoCD app version v3.3.6) as the current pinned version, or align the chart pin back to 7.6.12 if the upgrade was unintentional.

### WR-03: `lifecycle { ignore_changes = all }` on `helm_release.argocd` permanently suppresses Terraform management

**File:** `terraform/infra/modules/oci-argocd-bootstrap/main.tf:30-32`

**Issue:** `ignore_changes = all` means Terraform will never detect or apply any drift to the ArgoCD Helm release after the first apply. The comment says this is to prevent Terraform from conflicting with ArgoCD self-management. This is correct for the GitOps bridge pattern, but `ignore_changes = all` also silently suppresses legitimate bootstrap corrections (e.g., a wrong initial `extraArgs` value). If the initial install has a bug, the operator must `terraform taint` or `terraform destroy` the release to recover — not obvious.

**Fix:** Document this behavior explicitly in a comment and in the README teardown/recovery section. Consider restricting to only the values that ArgoCD will mutate (e.g., `ignore_changes = [values]`) rather than blocking all change detection, which would still allow chart version upgrades to be Terraform-managed:

```hcl
lifecycle {
  # ArgoCD gerencia seus proprios valores apos bootstrap — ignorar mudancas de values
  # para evitar conflito com self-management. Para upgrade de versao, fazer taint manual.
  ignore_changes = [values]
}
```

### WR-04: LB egress NSG rule targets subnet CIDR, not workers NSG — overly broad scope

**File:** `terraform/infra/modules/oci-network/main.tf:124-137`

**Issue:** `lb_egress_workers` sets `destination = var.private_subnet_cidr` (`10.0.2.0/24`). This permits LB egress to any host in the private subnet, not only OKE worker nodes. If other resources are placed in the private subnet (e.g., a future database or internal service), the LB can reach them on the NodePort range. The corresponding ingress rule on the workers NSG (`workers_ingress_from_lb`) correctly uses `source_type = "NETWORK_SECURITY_GROUP"`, creating an asymmetric pairing.

**Fix:** Change the LB egress destination to reference the workers NSG ID to maintain NSG-to-NSG scoping consistently:

```hcl
resource "oci_core_network_security_group_security_rule" "lb_egress_workers" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "6"
  destination               = oci_core_network_security_group.workers.id
  destination_type          = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 30000
      max = 32767
    }
  }
}
```

Note: the network module's `variables.tf` exports `private_subnet_cidr` which would no longer be needed for this rule (though it is still used by `workers_ingress_inter_node`).

---

## Info

### IN-01: `oci_argocd_bootstrap` module has no output for the bootstrap Application name/status

**File:** `terraform/infra/modules/oci-argocd-bootstrap/outputs.tf:1-4`

**Issue:** The only output is `argocd_namespace`. The bootstrap Application and the GitOps bridge secret are not exposed as outputs, making it harder to reference them in `terraform/infra/outputs.tf` or to signal bootstrap completion to operators. This is minor since the GitOps repo takes over immediately, but an output like `bootstrap_app_name` or `gitops_bridge_secret_name` aids observability.

**Fix:** Add outputs for the key bootstrap resources:

```hcl
output "bootstrap_app_name" {
  description = "Nome da Application raiz do GitOps Bridge"
  value       = "bootstrap"
}

output "gitops_bridge_secret_name" {
  description = "Nome do cluster secret do ArgoCD GitOps Bridge"
  value       = kubernetes_secret.gitops_bridge.metadata[0].name
}
```

### IN-02: `oci_argocd_bootstrap` module not exposed in root `outputs.tf`

**File:** `terraform/infra/outputs.tf:1-39`

**Issue:** `terraform/infra/outputs.tf` exposes cluster, vault, bastion, and subnet IDs, but none of the bootstrap module's outputs (e.g., `argocd_namespace`). This is a minor gap — operators running `terraform output` after apply will not see ArgoCD-related values.

**Fix:** Add the namespace and any other relevant bootstrap outputs to `terraform/infra/outputs.tf`:

```hcl
output "argocd_namespace" {
  description = "Namespace onde ArgoCD foi instalado"
  value       = module.oci_argocd_bootstrap.argocd_namespace
}
```

### IN-03: Pod CIDR `10.244.0.0/16` is hardcoded without a variable or comment explaining the source

**File:** `terraform/infra/modules/oci-network/main.tf:177`

**Issue:** The overlay/pod CIDR (`10.244.0.0/16`) used in `workers_ingress_pod_cidr` is a magic number. It matches the default Flannel CIDR, but OKE can be configured with a different pod CIDR. If the cluster's pod CIDR is ever changed, this NSG rule will silently stop working and cross-node pod traffic will be blocked.

**Fix:** Extract to a variable with a comment:

```hcl
variable "pod_cidr" {
  description = "CIDR da rede de pods (overlay) — deve coincidir com a configuracao do OKE"
  type        = string
  default     = "10.244.0.0/16"
}
```

And reference as `source = var.pod_cidr` in the NSG rule.

---

_Reviewed: 2026-04-09T00:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
