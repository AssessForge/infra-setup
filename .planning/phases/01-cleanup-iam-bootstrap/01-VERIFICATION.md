---
phase: 01-cleanup-iam-bootstrap
verified: 2026-04-10T03:00:00Z
status: human_needed
score: 5/5 must-haves verified (code); SC3 needs cluster-apply confirmation
human_verification:
  - test: "Run terraform apply from terraform/infra/ and confirm ArgoCD reaches Running state"
    expected: "All pods in argocd namespace become Ready; helm_release.argocd, kubernetes_secret.gitops_bridge, and kubectl_manifest.bootstrap_app all apply without error"
    why_human: "Cannot verify actual cluster connectivity or Helm chart installation programmatically — requires live OKE cluster and kubeconfig"
  - test: "Confirm terraform/k8s/ directory contains no tracked Terraform source files"
    expected: "Only .terraform/ (provider cache, gitignored) and .terraform.lock.hcl remain; git ls-files terraform/k8s/ returns empty"
    why_human: "Directory exists on disk due to .terraform/ cache; git-tracking status was verified automatically, but human should confirm no source files are present"
---

# Phase 1: Cleanup & IAM Bootstrap Verification Report

**Phase Goal:** The old `terraform/k8s/` code is deleted from the repository, Terraform provisions IAM (Dynamic Group + Instance Principal policy), and ArgoCD is bootstrapped with the GitOps Bridge Secret and root Application — Terraform is done touching the cluster after this
**Verified:** 2026-04-10T03:00:00Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| #   | Truth | Status | Evidence |
|-----|-------|--------|----------|
| SC1 | The `terraform/k8s/` directory and all its child modules no longer exist in the repository | VERIFIED | `git ls-files terraform/k8s/` returns empty; all 25 source files removed in commit c17edf6; only `.terraform/` cache (gitignored) remains on disk |
| SC2 | OCI Dynamic Group scoped to OKE worker node instances exists and IAM Policy grants it Vault secret read access | VERIFIED | `oci_identity_dynamic_group.instance_principal` with matching rule `resource.type = 'instance', instance.compartment.id`; `oci_identity_policy.instance_principal_vault` with read permissions on secret-family, vaults, keys |
| SC3 | `terraform apply` completes with ArgoCD running in the cluster (ClusterIP service, no SSO configured yet) | HUMAN NEEDED | Code is correct: `helm_release.argocd` version 9.5.0, ClusterIP service, no SSO; `ignore_changes = all` present; cannot verify actual cluster deployment without live OKE cluster |
| SC4 | GitOps Bridge Secret exists in the argocd namespace with all required labels (addon feature flags) and annotations (compartment OCID, subnet IDs, vault OCID, region, environment) | VERIFIED | `kubernetes_secret.gitops_bridge` with `argocd.argoproj.io/secret-type = "cluster"`, 5 feature flag labels (`enable_argocd`, `enable_eso`, `enable_envoy_gateway`, `enable_cert_manager`, `enable_metrics_server`), `environment = "prod"`, `cluster_name`; annotations: `addons_repo_url`, `addons_repo_revision`, `oci_region`, `oci_compartment_ocid`, `oci_vault_ocid`, `oci_public_subnet_id`, `oci_private_subnet_id` |
| SC5 | Root bootstrap ArgoCD Application resource exists and points at the gitops-setup repo; all provider and Helm chart versions are pinned | VERIFIED | `kubectl_manifest.bootstrap_app` with `source.path = "bootstrap/control-plane"`, `source.repoURL = var.gitops_repo_url`; providers pinned: helm ~> 3.0, kubernetes ~> 3.0, kubectl ~> 2.0, oci ~> 8.0; Helm chart pinned: 9.5.0 |

**Score:** 5/5 truths verified (code level); SC3 pending human cluster-apply confirmation

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `terraform/infra/modules/oci-iam/main.tf` | Fixed Dynamic Group + renamed resources | VERIFIED | `oci_identity_dynamic_group.instance_principal` with `resource.type = 'instance'`; `create_before_destroy = true`; policy renamed to `assessforge-instance-principal-vault-policy` |
| `terraform/infra/modules/oci-iam/outputs.tf` | References instance_principal | VERIFIED | `output "dynamic_group_name"` references `oci_identity_dynamic_group.instance_principal.name` |
| `terraform/infra/modules/oci-network/main.tf` | VCN has prevent_destroy | VERIFIED | `lifecycle { prevent_destroy = true }` on `oci_core_vcn.main` (lines 9-11) |
| `terraform/infra/versions.tf` | Helm + Kubernetes + kubectl provider declarations | VERIFIED | All three providers in `required_providers`; `provider "helm"` uses object syntax `kubernetes = { config_path = ... }` (Helm v3); `provider "kubernetes"` and `provider "kubectl"` both reference `~/.kube/config-assessforge` |
| `terraform/infra/variables.tf` | GitOps repo variables | VERIFIED | `variable "gitops_repo_url"` (default: `https://github.com/AssessForge/gitops-setup`); `variable "gitops_repo_revision"` (default: `"main"`) |
| `terraform/infra/outputs.tf` | Subnet and compartment outputs | VERIFIED | `output "compartment_ocid"`, `output "public_subnet_id"` (from `module.oci_network`), `output "private_subnet_id"` (from `module.oci_network`) |
| `terraform/infra/modules/oci-argocd-bootstrap/main.tf` | ArgoCD helm_release + Bridge Secret + bootstrap Application | VERIFIED | Three resources present and complete; no stubs |
| `terraform/infra/modules/oci-argocd-bootstrap/variables.tf` | Module input variables | VERIFIED | All 9 required variables declared: compartment_ocid, region, vault_ocid, public_subnet_id, private_subnet_id, gitops_repo_url, gitops_repo_revision, cluster_name, freeform_tags |
| `terraform/infra/modules/oci-argocd-bootstrap/outputs.tf` | Module outputs | VERIFIED | `output "argocd_namespace"` from `helm_release.argocd.namespace` |
| `terraform/infra/main.tf` | Bootstrap module call wired to existing modules | VERIFIED | `module "oci_argocd_bootstrap"` block after `module "oci_vault"` with all variable mappings and `depends_on = [module.oci_oke, module.oci_vault]` |
| `terraform/k8s/` | Directory removed | VERIFIED | Zero git-tracked files; directory on disk contains only `.terraform/` cache (gitignored); commit c17edf6 removed all 25 source files |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `terraform/infra/modules/oci-iam/main.tf` | `oci_identity_dynamic_group.instance_principal` | resource rename from workload_identity | WIRED | Resource label is `instance_principal`; `workload_identity` string does not appear anywhere in `terraform/infra/` |
| `terraform/infra/outputs.tf` | `module.oci_network` | output references | WIRED | `module.oci_network.public_subnet_id` and `module.oci_network.private_subnet_id` in outputs.tf |
| `terraform/infra/main.tf` | `terraform/infra/modules/oci-argocd-bootstrap/main.tf` | module call with variable mapping | WIRED | `module "oci_argocd_bootstrap" { source = "./modules/oci-argocd-bootstrap" ... }` with all 9 variables mapped |
| `terraform/infra/modules/oci-argocd-bootstrap/main.tf` | `helm_release.argocd` | Helm provider installing ArgoCD chart | WIRED | `resource "helm_release" "argocd"` with chart 9.5.0, namespace argocd |
| `terraform/infra/modules/oci-argocd-bootstrap/main.tf` | `kubernetes_secret.gitops_bridge` | Bridge Secret depends on ArgoCD namespace | WIRED | `namespace = helm_release.argocd.namespace` and `depends_on = [helm_release.argocd]` |
| `terraform/infra/modules/oci-argocd-bootstrap/main.tf` | `kubectl_manifest.bootstrap_app` | Bootstrap Application depends on ArgoCD + Bridge Secret | WIRED | `depends_on = [helm_release.argocd, kubernetes_secret.gitops_bridge]` |

### Data-Flow Trace (Level 4)

Not applicable — this phase produces Terraform HCL declarations, not components that render dynamic data. All variable references flow from root module through to resources at apply time.

### Behavioral Spot-Checks

Step 7b: SKIPPED — Terraform files are not runnable without a live OCI/OKE cluster. Provider authentication via `~/.oci/config` and kubeconfig cannot be tested in this environment.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| MIG-01 | 01-01-PLAN.md | `terraform/k8s/` directory and all modules removed (code-only, never applied) | SATISFIED | All 25 source files removed in commit c17edf6; git-tracked files: 0 |
| MIG-02 | 01-01-PLAN.md | Old k8s modules (argocd, external-secrets, ingress-nginx, kyverno, network-policies) removed | SATISFIED | All child modules under `terraform/k8s/modules/` removed in same commit |
| IAM-01 | 01-01-PLAN.md | OCI Dynamic Group scoped to OKE worker node instances for Instance Principal auth | SATISFIED | `oci_identity_dynamic_group.instance_principal` with `resource.type = 'instance', instance.compartment.id` scope |
| IAM-02 | 01-01-PLAN.md | IAM Policy granting Dynamic Group read access to OCI Vault secrets | SATISFIED | `oci_identity_policy.instance_principal_vault` with 3 statements: secret-family, vaults, keys read access |
| IAM-03 | 01-01-PLAN.md | Critical resources have `prevent_destroy = true` | SATISFIED | VCN added in this phase; OKE cluster, node pool, Vault, master key already had it |
| IAM-04 | 01-01-PLAN.md | Every OCI resource is Always Free tier eligible | SATISFIED | Dynamic Groups and IAM Policies are free OCI services; no paid resources introduced |
| BOOT-01 | 01-02-PLAN.md | ArgoCD installed via helm_release with minimal values (no SSO, no repo config, ClusterIP) | SATISFIED (code) | `helm_release.argocd`: chart 9.5.0, ClusterIP, no SSO, no repo config; cluster apply pending |
| BOOT-02 | 01-02-PLAN.md | GitOps Bridge Secret in argocd namespace with addon feature flag labels and OCI annotations | SATISFIED | `kubernetes_secret.gitops_bridge` with all required labels and 7 annotations verified |
| BOOT-03 | 01-02-PLAN.md | Root bootstrap Application pointing to gitops-setup repo | SATISFIED | `kubectl_manifest.bootstrap_app` with `source.path = "bootstrap/control-plane"`, `repoURL = var.gitops_repo_url` |
| BOOT-04 | 01-02-PLAN.md | helm_release uses `lifecycle { ignore_changes = all }` | SATISFIED | Present in `helm_release.argocd` at line 31 |
| BOOT-05 | 01-01-PLAN.md + 01-02-PLAN.md | All provider and Helm chart versions pinned | SATISFIED | Providers: oci ~> 8.0, helm ~> 3.0, kubernetes ~> 3.0, kubectl ~> 2.0; ArgoCD chart: 9.5.0; zero `latest` or open ranges found |

### Anti-Patterns Found

| File | Pattern | Severity | Impact |
|------|---------|----------|--------|
| `terraform/infra/versions.tf` | `endpoint = "https://PLACEHOLDER.compat..."` in S3 backend | Info | Pre-existing intentional placeholder requiring operator-specific value at apply time; documented in README; not a code anti-pattern |

No TODO/FIXME/HACK/stub patterns found in any modified file. No empty return values. No hardcoded credentials.

### Human Verification Required

#### 1. Cluster Apply Verification

**Test:** From a workstation with `~/.oci/config` and `~/.kube/config-assessforge` configured, run `terraform apply` from `terraform/infra/` after supplying required variables.
**Expected:** All pods in the `argocd` namespace reach `Running/Ready` state; `helm_release.argocd` applies without error; `kubernetes_secret.gitops_bridge` with name `in-cluster` appears in the argocd namespace; `kubectl_manifest.bootstrap_app` creates an `Application` resource named `bootstrap` in the argocd namespace with status `Unknown` (pointing to gitops-setup repo that does not yet exist).
**Why human:** Cannot verify actual Kubernetes cluster connectivity or Helm chart installation without a live OKE cluster and valid kubeconfig.

#### 2. terraform/k8s/ Source File Confirmation

**Test:** Run `git ls-files terraform/k8s/` in the repository root.
**Expected:** Empty output — no tracked files in terraform/k8s/.
**Why human:** The directory exists on disk due to `.terraform/` provider cache folder (gitignored); automated check showed zero tracked files but a human should confirm before considering this phase fully closed.

### Gaps Summary

No blocking gaps found. All required code artifacts exist, are substantive (not stubs), and are correctly wired. The phase goal is achievable with the current codebase.

The only open item is cluster-level verification (SC3) which requires a live OKE cluster — this is an operational verification, not a code gap.

---

_Verified: 2026-04-10T03:00:00Z_
_Verifier: Claude (gsd-verifier)_
