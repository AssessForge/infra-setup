---
phase: quick-260423-va5
plan: 01
subsystem: infra/network
tags:
  - oci
  - oke
  - nsg
  - networking
  - bugfix
dependency-graph:
  requires:
    - oci_core_network_security_group.api_endpoint
    - oci_core_network_security_group.workers
    - data.oci_core_services.all
  provides:
    - api_endpoint <-> workers NSG wiring required for OKE node registration
  affects:
    - module.oci_oke.oci_containerengine_node_pool.main (unblocks node registration)
tech-stack:
  added: []
  patterns:
    - NSG-to-NSG source/destination rules (peer by NSG id, not CIDR)
    - SERVICE_CIDR_BLOCK destination_type for Service Gateway egress
    - ICMP type 3 code 4 rules in both directions to avoid PMTU blackhole
key-files:
  created: []
  modified:
    - terraform/infra/modules/oci-network/main.tf
decisions:
  - Use NSG-sourced/destined rules (not CIDR) between api_endpoint and workers to preserve least-privilege and resilience to CIDR changes
  - Restrict kubelet ingress on workers to TCP 10250 only (not all TCP) from api_endpoint
  - Keep egress to OCI Services over Service Gateway via SERVICE_CIDR_BLOCK, matching existing route_table.private convention
metrics:
  duration_minutes: 1
  tasks_completed: 1
  files_modified: 1
  completed_date: 2026-04-24
requirements:
  - FIX-OKE-NSG-01
---

# Quick Task 260423-va5: Fix OKE Worker Node Register Timeout Summary

**One-liner:** Added eight `oci_core_network_security_group_security_rule` resources wiring `api_endpoint <-> workers` NSGs (TCP 6443/10250/12250, ICMP 3/4, and TCP 443 egress via Service Gateway) so OKE worker nodes can complete kubelet registration.

## Context

The prior `terraform apply` failed on `module.oci_oke.oci_containerengine_node_pool.main` with `2 nodes(s) register timeout`. Root cause: the `api_endpoint` NSG only permitted `bastion -> 6443` ingress and had zero worker-peer or OCI-services rules. Per the OCI OKE network requirements, private-endpoint clusters need explicit rules between the `api_endpoint` NSG and the `workers` NSG, plus egress to the OCI Services CIDR via the Service Gateway.

The fix is purely additive to `terraform/infra/modules/oci-network/main.tf`. No variables, outputs, module interfaces, or lifecycle `prevent_destroy` blocks were touched. No k8s-layer changes.

## What Was Built

Eight new NSG security rules, inserted immediately after `api_endpoint_ingress_bastion` and before the flow-logs block, grouped under a Portuguese section header linking to the OCI OKE networking docs:

| # | Resource label | NSG | Dir | Proto | Peer (NSG/service) | Port / ICMP |
|---|----------------|-----|-----|-------|--------------------|-------------|
| 1 | `api_endpoint_ingress_workers_kubeapi` | api_endpoint | INGRESS | TCP | workers NSG | 6443 |
| 2 | `api_endpoint_ingress_workers_okeport` | api_endpoint | INGRESS | TCP | workers NSG | 12250 |
| 3 | `api_endpoint_ingress_workers_pmtu` | api_endpoint | INGRESS | ICMP | workers NSG | type 3 code 4 |
| 4 | `api_endpoint_egress_workers_kubelet` | api_endpoint | EGRESS | TCP | workers NSG | 10250 |
| 5 | `api_endpoint_egress_workers_pmtu` | api_endpoint | EGRESS | ICMP | workers NSG | type 3 code 4 |
| 6 | `api_endpoint_egress_oci_services` | api_endpoint | EGRESS | TCP | `data.oci_core_services.all.services[0].cidr_block` (SERVICE_CIDR_BLOCK) | 443 |
| 7 | `workers_ingress_from_api_endpoint_kubelet` | workers | INGRESS | TCP | api_endpoint NSG | 10250 |
| 8 | `workers_ingress_from_api_endpoint_pmtu` | workers | INGRESS | ICMP | api_endpoint NSG | type 3 code 4 |

Each rule has a Portuguese `#` comment above it explaining WHY (not what) — e.g., rule #2 notes it is the rule whose absence causes the registration timeout.

Workers egress stays unchanged (`workers_egress_all` already allows all egress), so outbound 6443/12250 from workers is already permitted.

## Tasks Executed

| Task | Name | Status | Commit | Files |
|------|------|--------|--------|-------|
| 1 | Add missing `api_endpoint <-> workers` NSG rules in oci-network module | done | `391eca7` | `terraform/infra/modules/oci-network/main.tf` |

## Deviations from Plan

None — plan executed exactly as written. Rule count, labels, ordering, protocols, ports, ICMP codes, peer types, and Portuguese comments all match the plan spec.

`terraform -chdir=terraform/infra fmt -recursive` reformatted `terraform/infra/terraform.tfvars` (unrelated WIP); it was NOT staged. Only `terraform/infra/modules/oci-network/main.tf` is in the commit.

## Verification Performed Inline

- `terraform fmt -recursive` ran clean on the edited file (no diff on `modules/oci-network/main.tf`).
- Static review: all 8 resource labels follow `<target>_<direction>_<purpose>` snake_case; protocols (`"6"` / `"1"`) match existing patterns; ICMP rules omit `tcp_options` and use `icmp_options { type = 3, code = 4 }`; rule #6 uses `SERVICE_CIDR_BLOCK` consistent with `oci_core_route_table.private`; rule #7 caps kubelet ingress at TCP 10250 (least privilege).
- `terraform validate` and `terraform plan` were intentionally not executed per task constraints (require OCI credentials; operator will run apply).

## Operator Next Steps

1. Run `terraform apply` from `terraform/infra/`. Expected: 8 new NSG rules created; the failed node pool is replaced and workers register within ~15-20 min.
2. If OCI still holds a lingering failed node pool object, delete it manually: `oci ce node-pool delete --node-pool-id <ocid> --force` (check with `oci ce node-pool list` first).
3. Smoke test: `kubectl --kubeconfig ~/.kube/config-assessforge get nodes` should show 2 nodes `Ready`.

## Security Posture

- Every new peer rule uses `NETWORK_SECURITY_GROUP` source/destination (not `0.0.0.0/0`) — only NSG-attached resources can reach these ports.
- Kubelet ingress on workers is scoped to TCP 10250 only, preventing broader control-plane-to-worker exposure.
- Rule #6 egress uses `SERVICE_CIDR_BLOCK` so control plane egress to the OKE service stays on the private Oracle backbone via Service Gateway — no NAT, no public path.
- ICMP 3/4 pairs (rules #3, #5, #8) are explicitly scoped (no broad ICMP allow) and exist solely to prevent PMTU blackhole DoS.
- No new paid OCI resources introduced (NSG rules are free).

## Known Stubs

None.

## Threat Flags

None — all new surface is covered by the plan's `<threat_model>` (T-va5-01 through T-va5-05); no new endpoints, schema changes, or trust boundaries introduced beyond what was enumerated.

## Self-Check: PASSED

- FOUND: `terraform/infra/modules/oci-network/main.tf` (modified with 8 new rule resources)
- FOUND commit: `391eca7`
- FOUND: all 8 new resource labels (`api_endpoint_ingress_workers_kubeapi`, `api_endpoint_ingress_workers_okeport`, `api_endpoint_ingress_workers_pmtu`, `api_endpoint_egress_workers_kubelet`, `api_endpoint_egress_workers_pmtu`, `api_endpoint_egress_oci_services`, `workers_ingress_from_api_endpoint_kubelet`, `workers_ingress_from_api_endpoint_pmtu`)
- CONFIRMED: no edits to `variables.tf`, `outputs.tf`, or any other module
- CONFIRMED: no `prevent_destroy` block modifications
- CONFIRMED: commit includes only the target file (other WIP files left un-staged)
