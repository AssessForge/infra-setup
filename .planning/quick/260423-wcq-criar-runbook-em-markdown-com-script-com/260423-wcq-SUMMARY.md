---
phase: quick-260423-wcq
plan: 01
subsystem: docs
tags: [documentation, runbook, oci-bastion, operations]
requires: []
provides:
  - "DOC-BASTION-RUNBOOK-01"
affects:
  - "docs/runbooks/bastion-first-apply.md (new)"
tech_stack_added: []
tech_stack_patterns:
  - "Operational runbook — Markdown with inline bash script blocks, env-var-driven, copy-paste-safe per block"
key_files_created:
  - "docs/runbooks/bastion-first-apply.md"
key_files_modified: []
decisions:
  - "Single standalone Markdown file (no separate .sh) — all bash inline as fenced code blocks, matching terraform/README.md style"
  - "Portuguese prose to align with existing project documentation (terraform/README.md, inline module comments)"
  - "Cross-linked to terraform/README.md, CLAUDE.md and terraform/infra/versions.tf via relative Markdown links (../../ from docs/runbooks/)"
  - "Did NOT modify terraform/README.md — kept runbook addition non-invasive per plan scope"
metrics:
  tasks_completed: 1
  files_created: 1
  files_modified: 0
  lines_added: 420
  duration_minutes: "~5"
  completed: "2026-04-23"
---

# Quick 260423-wcq: Bastion-First-Apply Runbook Summary

**One-liner:** Standalone Markdown runbook at `docs/runbooks/bastion-first-apply.md` guiding the operator from the post-Phase-1 `terraform apply` failure (`Kubernetes cluster unreachable`) through SSH key bootstrap, OCI Bastion port-forwarding session creation, tunnel opening, kubeconfig rewrite, and successful re-apply through `module.oci_argocd_bootstrap.helm_release.argocd`.

## What Was Delivered

### Artifact

| Path                                     | Lines | Type |
| ---------------------------------------- | ----- | ---- |
| `docs/runbooks/bastion-first-apply.md`   | 420   | New  |

### H2 Sections Delivered (14 total)

1. `## Contexto` — explains the 3 design reasons for the `cluster unreachable` error and the two-phase apply pattern
2. `## Pré-requisitos` — intro + Chave SSH (3 scenarios) + Ferramentas checklist
3. `## Passo 1 — Descobrir outputs da infraestrutura`
4. `## Passo 2 — Gerar kubeconfig inicial`
5. `## Passo 3 — Descobrir o IP privado do OKE API endpoint`
6. `## Passo 4 — Criar sessão OCI Bastion port-forwarding`
7. `## Passo 5 — Aguardar sessão ficar ACTIVE` (with polling loop)
8. `## Passo 6 — Abrir túnel SSH em background`
9. `## Passo 7 — Reescrever kubeconfig para 127.0.0.1`
10. `## Passo 8 — Validar acesso ao cluster`
11. `## Passo 9 — Re-executar terraform apply`
12. `## Teardown — Encerrar túnel e sessão`
13. `## Troubleshooting` (4 subsections: CREATING stuck, SSH refuse, kubectl timeout, terraform still unreachable)
14. `## Referências`

### Plan Must-Haves Covered

- SSH key bootstrap fallback block (`ssh-keygen -t ed25519`) documented
- `SSH_PUBLIC_KEY` env var pattern for custom paths documented
- Explanation of WHY first `terraform apply` fails (private endpoint + `fileexists` two-phase init)
- Uses `terraform output -raw cluster_id` and `bastion_ocid`; OKE IP discovered via `oci ce cluster get`
- Bastion session created with `--ssh-public-key-file "$SSH_PUBLIC_KEY"`
- Polling loop until `lifecycle-state = ACTIVE`
- Tunnel opened with `ssh -f -N -L 6443:$OKE_IP:6443` against `host.bastion.sa-saopaulo-1.oci.oraclecloud.com`
- Kubeconfig rewritten from private IP to `https://127.0.0.1:6443`
- Validation with `KUBECONFIG=~/.kube/config-assessforge kubectl get nodes`
- Re-apply guidance including `terraform init -upgrade`
- Teardown: kill background SSH + delete bastion session + note about GitOps-only ops after
- Troubleshooting covers all 4 required cases
- Prose in Portuguese, bash comments in Portuguese
- All bash blocks env-var-driven, copy-paste-safe independently
- Cross-links to `terraform/README.md`, `CLAUDE.md`, `terraform/infra/versions.tf`

### Files Unchanged

- `terraform/README.md` — **NOT modified** per plan scope. `git diff terraform/README.md` returned empty.

## Deviations from Plan

None — plan executed exactly as written. All outline sections, required code blocks, and cross-links produced as specified.

## Verification

Automated verification from plan (all passed):

- `test -f docs/runbooks/bastion-first-apply.md` → PASS
- `wc -l` ≥ 180 → 420 lines (PASS)
- `grep -q "host.bastion.sa-saopaulo-1.oci.oraclecloud.com"` → PASS
- `grep -q "ssh-keygen"` → PASS
- `grep -q "fileexists"` → PASS
- `grep -q "terraform init -upgrade"` → PASS
- `grep -q "sa-saopaulo-1"` → PASS
- `grep -cE '^## '` ≥ 12 → 14 (PASS)

## Follow-up Suggestions (Optional, Not This Quick)

- Consider adding a one-line link from `terraform/README.md` "Etapa intermediária" section to this runbook: `> Para o procedimento completo com fallback de chave SSH e troubleshooting, ver [docs/runbooks/bastion-first-apply.md](../docs/runbooks/bastion-first-apply.md).` — intentionally out of scope for this quick to keep the change surface minimal.

## Commits

- `dcb995b docs(quick-260423-wcq): add bastion tunnel + first-apply runbook` — adds `docs/runbooks/bastion-first-apply.md` (420 lines)

## Self-Check: PASSED

- File `docs/runbooks/bastion-first-apply.md` exists (verified via `test -f`)
- Commit `dcb995b` present in `git log` (verified via `git rev-parse --short HEAD`)
- `terraform/README.md` unchanged (verified via `git diff --name-only terraform/README.md` returning empty)
