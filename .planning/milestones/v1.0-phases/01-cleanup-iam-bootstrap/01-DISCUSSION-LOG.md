# Phase 1: Cleanup & IAM Bootstrap - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-09
**Phase:** 01-cleanup-iam-bootstrap
**Areas discussed:** IAM strategy, Bootstrap layout, Bridge Secret design, Code cleanup scope

---

## IAM Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Instance matching rule | Match by instance.compartment.id — all worker nodes get Vault access. Simple, works on BASIC tier. | |
| Cluster OCID matching | Match by tag or more specific rule scoped to OKE node pool instances only | |
| You decide | Claude picks the best approach for free tier BASIC cluster | ✓ |

**User's choice:** You decide — Claude's discretion
**Notes:** Existing Dynamic Group uses resource.type='workload' which requires Enhanced tier (paid). Must change to Instance Principal matching for BASIC tier free cluster.

---

## Bootstrap Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Extend terraform/infra/ | Add Helm + k8s providers to existing infra root module. New oci-argocd-bootstrap module alongside existing modules. Single apply. | ✓ |
| New terraform/bootstrap/ | Separate root module reading infra state via remote_state. Keeps infra pure OCI. Two applies. | |
| You decide | Claude picks the approach that fits existing patterns best | |

**User's choice:** Extend terraform/infra/ — single root module with new bootstrap module
**Notes:** This means adding helm + kubernetes providers to terraform/infra/versions.tf

---

## Bridge Secret Design

### Annotation naming

| Option | Description | Selected |
|--------|-------------|----------|
| OCI-flavored names | oci_compartment_ocid, oci_vault_ocid, oci_region — explicit about cloud provider | |
| Generic names | compartment_id, vault_id, region — cloud-agnostic | |
| You decide | Claude picks based on gitops-bridge community patterns | ✓ |

**User's choice:** You decide — Claude's discretion

### Feature flag labels

| Option | Description | Selected |
|--------|-------------|----------|
| All v1 addons | enable_eso, enable_envoy_gateway, enable_cert_manager, enable_metrics_server, enable_argocd | |
| Only toggleable ones | Skip always-on addons, only flag optional ones | |
| You decide | Claude decides which labels based on the pattern | ✓ |

**User's choice:** You decide — Claude's discretion

---

## Code Cleanup Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Delete entirely | Remove the whole terraform/k8s/ directory — all modules, lock files, tfvars examples | ✓ |
| Keep as reference | Move to docs/archive/ for reference | |
| You decide | Claude decides the cleanest approach | |

**User's choice:** Delete entirely — no archive, git history is sufficient
**Notes:** terraform/k8s/ was never applied, no live resources exist

---

## Claude's Discretion

- IAM Dynamic Group matching rule for Instance Principal on BASIC tier
- Bridge Secret annotation key naming convention
- Bridge Secret feature flag label selection
- ArgoCD Helm chart version and minimal values
- prevent_destroy placement
- Additional infra outputs for Bridge Secret

## Deferred Ideas

None — discussion stayed within phase scope
