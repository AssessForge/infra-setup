---
phase: quick-260424-0rf
plan: 01
subsystem: infra
tags: [terraform, oci, networking, nsg, runbook, bootstrap]
dependency_graph:
  requires:
    - terraform/infra/modules/oci-network (existing VCN + api_endpoint NSG)
    - docs/runbooks/bastion-first-apply.md (cross-referenced as the alternative path)
  provides:
    - oci_core_network_security_group.cloud_shell (assessforge-nsg-cloud-shell)
    - oci_core_network_security_group_security_rule.api_endpoint_ingress_cloud_shell
    - terraform output cloud_shell_nsg_id
    - docs/runbooks/cloud-shell-first-apply.md
  affects:
    - terraform/infra plan drift: two new additive resources expected on next apply
tech_stack:
  added: []
  patterns:
    - Customer-supplied NSG pattern for OCI Cloud Shell Private Network attachment
    - Ingress-only stateful NSG rule (mirrors bastion NSG pattern — no egress on cloud_shell NSG)
key_files:
  created:
    - docs/runbooks/cloud-shell-first-apply.md
  modified:
    - terraform/infra/modules/oci-network/main.tf
    - terraform/infra/modules/oci-network/outputs.tf
    - terraform/infra/outputs.tf
decisions:
  - "Dedicated NSG (assessforge-nsg-cloud-shell) instead of reusing bastion/workers NSGs — isolates blast radius of Cloud Shell attachment from production data paths"
  - "Ingress-only rule on api_endpoint NSG (TCP 6443); no egress rule on cloud_shell NSG — NSGs are stateful and Cloud Shell initiates the connection, so return traffic flows without explicit egress (mirrors the bastion NSG pattern)"
  - "Root-level output cloud_shell_nsg_id so operator runs `terraform output cloud_shell_nsg_id` — zero friction paste into the OCI Console form"
  - "bastion-first-apply.md left untouched — still valid for tenancies where OCI Bastion's managed port-forwarding does not fragment the TLS ClientHello"
metrics:
  duration: "~5m"
  completed: "2026-04-24T03:42:38Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 1
  files_modified: 3
  lines_added_runbook: 236
  lines_added_terraform: 37
---

# Quick 260424-0rf: Cloud Shell NSG + First-Apply Runbook Summary

Purpose: add an additive Cloud Shell Private Network path for the bootstrap final-apply, unblocking the stalled Bastion tunnel whose TLS handshake timed out in the managed OCI Bastion port-forwarding path.

## What Changed

### Terraform — Infrastructure (Task 1, commit `83d51ae`)

Two new additive resources in `terraform/infra/modules/oci-network/main.tf`, placed at the end of the NSG section (right after `workers_ingress_from_api_endpoint_pmtu`, before `oci_logging_log_group.vcn_flow_logs`):

1. `oci_core_network_security_group.cloud_shell`
   - Display name: `assessforge-nsg-cloud-shell`
   - Attached to the main VCN, in the same compartment.
   - Tagged with `freeform_tags = var.freeform_tags`.
   - Carries no rules of its own (stateful, ingress-only pattern — same as bastion NSG).

2. `oci_core_network_security_group_security_rule.api_endpoint_ingress_cloud_shell`
   - Attached to the existing `api_endpoint` NSG.
   - INGRESS, TCP, from `oci_core_network_security_group.cloud_shell.id`, destination port 6443.

Outputs — two locations, same logical name for consistency:

- `terraform/infra/modules/oci-network/outputs.tf` — new `output "cloud_shell_nsg_id"` (module-level).
- `terraform/infra/outputs.tf` — passthrough `output "cloud_shell_nsg_id" { value = module.oci_network.cloud_shell_nsg_id }` so the operator runs `terraform output cloud_shell_nsg_id` at the root.

### Runbook (Task 2, commit `5eb3eee`)

New file `docs/runbooks/cloud-shell-first-apply.md` (236 lines) mirroring the style of `bastion-first-apply.md`:

- `## Contexto` — states upfront this is the alternative to the Bastion tunnel; explains the TLS handshake timeout cause; preserves the two-phase apply `fileexists(kubeconfig)` pattern explanation so the file stands alone.
- `## Pré-requisitos` — Fase 1 applied, OCI Console access, `terraform` + `kubectl` ready.
- `## Passo 1` — `terraform output -raw cloud_shell_nsg_id`.
- `## Passo 2` — open OCI Cloud Shell.
- `## Passo 3` — attach Private Network Connection via the Cloud Shell dropdown (VCN, subnet, NSG).
- `## Passo 4` — `oci ce cluster create-kubeconfig --kube-endpoint PRIVATE_ENDPOINT` (the critical flag — without it the CLI defaults to the disabled public endpoint).
- `## Passo 5` — `kubectl get nodes` validation.
- `## Passo 6` — clone repo, upload tfvars, export Customer Secret Key for state backend.
- `## Passo 7` — `terraform init -upgrade && terraform apply` inside Cloud Shell.
- `## Passo 8` — teardown (switch back to public network or close the tab).
- `## Troubleshooting` — three failure modes: NSG-not-attached / `fileexists` cache / internet-bound Helm chart download during Private Network.
- `## Referências` — cross-link to `bastion-first-apply.md`, `CLAUDE.md`, `terraform/infra/versions.tf`, and two OCI docs pages.

## Operational Substitution

`bastion-first-apply.md` is **not** physically deleted or modified. Operationally, the new runbook replaces the bastion path *for this tenancy*, where OCI Bastion port-forwarding fragments the kube-apiserver TLS ClientHello and the handshake stalls. In tenancies where that behavior is absent, the bastion runbook remains a fully supported alternative — the two coexist by design.

## Verification

- `terraform -chdir=terraform/infra fmt -recursive` → no drift (silent success).
- `terraform validate` / `terraform plan` → NOT executed (no OCI credentials in this session). The plan's verification section warns the operator to confirm on next apply that only two new resources are added and zero are changed or destroyed.
- `grep 'oci_core_network_security_group.cloud_shell' terraform/infra/modules/oci-network/main.tf` → matches on definition (line 398) and source reference (line 411).
- `grep 'output "cloud_shell_nsg_id"'` → matches in module `outputs.tf` (line 36) and root `outputs.tf` (line 41).
- `grep 'module.oci_network.cloud_shell_nsg_id'` → matches root `outputs.tf` (line 43).
- `docs/runbooks/bastion-first-apply.md` untouched (`git diff --stat` empty).
- Runbook: 236 lines; all required grep checks (Cloud Shell Private Network, cloud_shell_nsg_id, bastion-first-apply.md, PRIVATE_ENDPOINT, CLAUDE.md) pass.

## Deviations from Plan

None. Plan executed exactly as written. No Rule 1/2/3 auto-fixes were needed.

One observation worth logging for future sessions: the repository has several pre-existing dirty/WIP uncommitted edits (`scripts/bastion-first-apply.sh`, `.gitignore`, and five `terraform/infra/modules/*/main.tf` files carrying explicit OCI `required_providers` blocks). Per the operator's documented preference, those remain untouched and were explicitly excluded from the two atomic commits created here — only the four files named in the plan were staged.

## Commits

- `83d51ae` — `feat(quick-260424-0rf): add cloud_shell NSG + api_endpoint ingress rule for Cloud Shell access`
- `5eb3eee` — `docs(quick-260424-0rf): add Cloud Shell Private Network first-apply runbook`

## Memory Hook

The next operator bootstrap (or any redo of the first-apply bridge step) uses the Cloud Shell Private Network runbook (`docs/runbooks/cloud-shell-first-apply.md`) unless Oracle fixes the Bastion-managed port-forwarding TLS fragmentation upstream. If that happens later, the bastion runbook can resume as the preferred path — nothing in this change blocks it.

## Self-Check: PASSED

- `docs/runbooks/cloud-shell-first-apply.md` FOUND (236 lines).
- `terraform/infra/modules/oci-network/main.tf` FOUND — contains `oci_core_network_security_group.cloud_shell` definition and `api_endpoint_ingress_cloud_shell` rule.
- `terraform/infra/modules/oci-network/outputs.tf` FOUND — contains `output "cloud_shell_nsg_id"`.
- `terraform/infra/outputs.tf` FOUND — contains root-level `cloud_shell_nsg_id` passthrough.
- Commit `83d51ae` FOUND in `git log`.
- Commit `5eb3eee` FOUND in `git log`.
