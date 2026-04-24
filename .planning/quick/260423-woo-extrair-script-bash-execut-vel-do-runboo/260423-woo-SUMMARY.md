---
phase: quick-260423-woo
plan: 01
subsystem: scripts/operator-tooling
tags:
  - bastion
  - first-apply
  - runbook-automation
  - bash
  - oci
requirements:
  - QUICK-260423-WOO
dependency_graph:
  requires:
    - docs/runbooks/bastion-first-apply.md
    - scripts/retry-apply.sh
  provides:
    - scripts/bastion-first-apply.sh
  affects: []
tech_stack:
  added: []
  patterns:
    - "Bash scripts seguem o estilo de scripts/retry-apply.sh: #!/bin/bash, set -euo pipefail, INFRA_DIR via cd+dirname+pwd, timestamped echo com em-dash, comentarios em portugues sem acentos."
key_files:
  created:
    - scripts/bastion-first-apply.sh
  modified: []
decisions:
  - "Polling da sessao Bastion: 40 x 3s (120s cap com granularidade fina) em vez do 24 x 5s do runbook -- mesma janela total, detecta ACTIVE mais rapido."
  - "Persistir SESSION_OCID em /tmp/bastion-session.ocid imediatamente apos criar a sessao (Passo 4) para permitir --teardown mesmo de outra shell / dia seguinte."
  - "--teardown com fallback: le /tmp/bastion-session.ocid; se ausente, consulta oci bastion session list --session-lifecycle-state ACTIVE para evitar deixar sessao orfa."
  - "Sem -auto-approve no terraform apply final -- operador confirma interativamente (risco muito alto para automacao completa no first apply)."
  - "Sem terraform init -upgrade automatico -- operador decide se roda apos falha (o runbook ja documenta quando isso e necessario)."
  - "Idempotencia do Passo 7: sed guardado por grep -- reexecucao no-op se o kubeconfig ja aponta para 127.0.0.1."
  - "check_ssh_key com fallback: gera ~/.ssh/assessforge_ed25519 apenas se SSH_KEY e o default e nao existe; fail-loud se SSH_KEY foi explicitamente setado mas o arquivo sumiu."
metrics:
  duration_minutes: 4
  completed: 2026-04-23
---

# Quick 260423-woo: Extrair script bash executavel do runbook bastion-first-apply Summary

One-liner: Added executable shortcut `scripts/bastion-first-apply.sh` that automates the 10-step bastion-first-apply runbook into a single command with `--teardown` and `--skip-apply` subcommands, mirroring `scripts/retry-apply.sh` style conventions.

## What Was Built

Created `scripts/bastion-first-apply.sh` (242 lines, executable), encapsulating every automatable bash block from `docs/runbooks/bastion-first-apply.md` into small named functions dispatched by a top-level `case "${1:-}"` switch.

### Functions exposed (in runbook order)

| Function                        | Runbook step | Purpose                                                                                                          |
| ------------------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------- |
| `check_ssh_key`                 | Pre-req      | Ensures an SSH key pair is present; generates `assessforge_ed25519` if SSH_KEY is the default and missing.       |
| `discover_terraform_outputs`    | Passo 1      | Reads `cluster_id` and `bastion_ocid` from `terraform output -raw`.                                              |
| `generate_initial_kubeconfig`   | Passo 2      | Runs `eval "$(terraform output -raw kubeconfig_command)"` only if `~/.kube/config-assessforge` is missing.       |
| `discover_oke_ip`               | Passo 3      | Queries OCI for the cluster's private-endpoint IP.                                                               |
| `create_bastion_session`        | Passo 4      | Creates the port-forwarding session and persists `SESSION_OCID` to `/tmp/bastion-session.ocid`.                  |
| `wait_for_session_active`       | Passo 5      | Polls 40 x 3s = 120s for ACTIVE lifecycle; dies with runbook link on timeout.                                    |
| `open_ssh_tunnel`               | Passo 6      | Opens `ssh -f -N -L $TUNNEL_PORT:$OKE_IP:6443`; validates the process is running post-fork.                      |
| `rewrite_kubeconfig`            | Passo 7      | Idempotent `sed` rewrite guarded by `grep -q` so reruns are no-ops.                                              |
| `validate_cluster`              | Passo 8      | `kubectl get nodes` against the tunneled kubeconfig; dies with runbook link on failure.                          |
| `run_apply`                     | Passo 9      | `cd "$INFRA_DIR" && terraform apply` (interactive confirm; no `-auto-approve`, no `terraform init -upgrade`).    |
| `teardown`                      | Teardown     | Kills SSH tunnel by `-L` pattern; deletes Bastion session via state file or OCI CLI fallback; removes state file.|

### Subcommand dispatcher

```bash
bash scripts/bastion-first-apply.sh              # end-to-end (steps 1-9 + terraform apply)
bash scripts/bastion-first-apply.sh --skip-apply # steps 1-8 only (stops before terraform apply)
bash scripts/bastion-first-apply.sh --teardown   # kill tunnel + delete session + remove state file
```

Any unrecognized flag exits 1 with Portuguese error `"Flag desconhecida: <flag>. Uso: ..."`.

## Style conformance with `scripts/retry-apply.sh`

Confirmed patterns mirrored:

- Shebang `#!/bin/bash` (not `/usr/bin/env bash`)
- Header comment in Portuguese without accents (`automatiza`, not `automatiza'`)
- `set -euo pipefail` on its own line right after the 3-line header
- `INFRA_DIR="$(cd "$(dirname "$0")/../terraform/infra" && pwd)"` exact pattern
- Timestamped progress via `$(date '+%Y-%m-%d %H:%M:%S')` with em-dash separator
- No ANSI colors, no `tee` to file, no logging frameworks
- Small focused functions, each with a leading `# Passo N -- ...` comment

## Env var overrides

| Var            | Default                          | Purpose                                     |
| -------------- | -------------------------------- | ------------------------------------------- |
| `SSH_KEY`      | `$HOME/.ssh/id_rsa`              | Private key path (public derived as `.pub`) |
| `REGION`       | `sa-saopaulo-1`                  | Bastion host region suffix                  |
| `SESSION_TTL`  | `10800`                          | Session TTL in seconds (3h max, per OCI)    |
| `TUNNEL_PORT`  | `6443`                           | Local forward port                          |

All other paths (`$STATE_FILE`, `$KUBECONFIG_PATH`, `$RUNBOOK`) are derived constants.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Force-staged script past `.gitignore`**
- **Found during:** Task 1 commit step
- **Issue:** `.gitignore` line 7 contains `scripts/`, which causes both the new `scripts/bastion-first-apply.sh` and the existing `scripts/retry-apply.sh` to be ignored by git. Without bypassing the ignore, the plan's must_haves (the script must exist in the repo and be committable) could not be satisfied.
- **Fix:** Used `git add -f scripts/bastion-first-apply.sh` — the `-f` bypasses the ignore rule for this one file only (still does NOT equal `git add -A`; only the intended file was staged). Verified via `git status --short` that no other files were accidentally added.
- **Files modified:** none additional (just staging mechanics)
- **Commit:** 2f3b370
- **Note:** The `scripts/` ignore rule is pre-existing and out of scope for this quick task. It affects `scripts/retry-apply.sh` the same way. Documented here as a deferred concern rather than auto-fixed, because modifying `.gitignore` could impact other files / WIP outside this task's surface area.

### Deliberate choices relative to the runbook

**1. Polling cadence changed from 24x5s to 40x3s**
- **Why:** Plan behavior block specifies 40x3s = 120s (same total cap as runbook 24x5s = 120s). Finer-grained polling detects `ACTIVE` sooner in the common case (~15-30s per runbook notes). Runbook unchanged.

**2. Hardcoded region `sa-saopaulo-1` in runbook parametrized to `$REGION`**
- **Why:** Runbook hardcodes the host `host.bastion.sa-saopaulo-1.oci.oraclecloud.com`; the script makes it a variable with the same default so future region changes are a single env-var override. Matches project convention of keeping `sa-saopaulo-1` as the constraint-documented default in `CLAUDE.md`.

## Operator Usage Examples

### End-to-end first apply

```bash
bash scripts/bastion-first-apply.sh
# => creates SSH key (if missing), reads TF outputs, generates kubeconfig,
#    creates Bastion session, waits ACTIVE, opens SSH tunnel, rewrites
#    kubeconfig to 127.0.0.1, validates kubectl, then runs `terraform apply`
#    (interactive confirm).
```

### Pre-apply validation only (setup without apply)

```bash
bash scripts/bastion-first-apply.sh --skip-apply
# => steps 1-8 complete; script exits with "Rode 'cd <infra> && terraform apply' manualmente."
# Useful for validating the tunnel + kubeconfig before committing to the apply.
```

### Custom SSH key + longer session

```bash
SSH_KEY="$HOME/.ssh/my-oci-key" SESSION_TTL=7200 \
  bash scripts/bastion-first-apply.sh --skip-apply
```

### Cleanup (liberate Bastion session slot)

```bash
bash scripts/bastion-first-apply.sh --teardown
# => reads /tmp/bastion-session.ocid, kills SSH tunnel by -L pattern,
#    deletes the Bastion session with --force, removes the state file.
# Fallback: if /tmp/bastion-session.ocid is missing, queries
#   `oci bastion session list --session-lifecycle-state ACTIVE`
#   and deletes every active session under the bastion returned by
#   `terraform output -raw bastion_ocid`.
```

## Verification Evidence

- `bash -n scripts/bastion-first-apply.sh` → exit 0 (no output)
- `test -x scripts/bastion-first-apply.sh` → exit 0
- Automated verify block from the plan (19 `grep`/`test` checks) → `ALL VERIFY CHECKS PASSED`
- `git diff docs/runbooks/bastion-first-apply.md` → empty (runbook untouched)
- `git show --stat HEAD` → 1 file changed, 242 insertions(+)
- `git diff --diff-filter=D HEAD~1 HEAD` → empty (no accidental deletions)

## Self-Check: PASSED

- Created file: `scripts/bastion-first-apply.sh` — FOUND
- Commit: `2f3b370` — FOUND in `git log --oneline`
- Runbook diff: empty — CONFIRMED
- Executable bit: set — CONFIRMED
