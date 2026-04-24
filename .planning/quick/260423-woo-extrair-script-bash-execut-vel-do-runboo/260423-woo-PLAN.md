---
phase: quick-260423-woo
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - scripts/bastion-first-apply.sh
autonomous: true
requirements:
  - QUICK-260423-WOO
user_setup: []

must_haves:
  truths:
    - "Operator can run `bash scripts/bastion-first-apply.sh` and the script executes steps 1-10 of the runbook end-to-end without manual intervention (except the final terraform apply confirm)."
    - "Operator can run `bash scripts/bastion-first-apply.sh --teardown` to kill the SSH tunnel and delete the Bastion session using the persisted SESSION_OCID, falling back to `oci bastion session list` if the state file is missing."
    - "Operator can run `bash scripts/bastion-first-apply.sh --skip-apply` to execute steps 1-9 (session + tunnel + kubeconfig + kubectl validation) and stop before `terraform apply`."
    - "Every failure prints a Portuguese error message referencing `docs/runbooks/bastion-first-apply.md`."
    - "Running the script twice in a row is idempotent on kubeconfig rewrite (Passo 7) — sed is skipped if server already points to 127.0.0.1."
    - "The runbook `docs/runbooks/bastion-first-apply.md` is not modified — it remains the canonical documentation and source of truth."
  artifacts:
    - path: "scripts/bastion-first-apply.sh"
      provides: "End-to-end bash script that automates steps 1-10 of bastion-first-apply runbook, plus --teardown and --skip-apply subcommands."
      contains: "#!/bin/bash, set -euo pipefail, INFRA_DIR, check_ssh_key, create_bastion_session, wait_for_session_active, open_ssh_tunnel, rewrite_kubeconfig, validate_cluster, run_apply, teardown"
      min_lines: 180
  key_links:
    - from: "scripts/bastion-first-apply.sh"
      to: "docs/runbooks/bastion-first-apply.md"
      via: "Function bodies mirror the runbook steps 1-10 verbatim in bash commands; error messages reference runbook by path."
      pattern: "docs/runbooks/bastion-first-apply.md"
    - from: "scripts/bastion-first-apply.sh"
      to: "terraform/infra/"
      via: "INFRA_DIR pattern `$(cd \"$(dirname \"$0\")/../terraform/infra\" && pwd)`, same as scripts/retry-apply.sh"
      pattern: "cd \"\\$\\(dirname \"\\$0\"\\)/../terraform/infra\""
    - from: "scripts/bastion-first-apply.sh --teardown"
      to: "/tmp/bastion-session.ocid"
      via: "Teardown reads persisted SESSION_OCID from state file; falls back to `oci bastion session list` if absent."
      pattern: "/tmp/bastion-session.ocid"
---

<objective>
Extract the automatable bash steps from `docs/runbooks/bastion-first-apply.md` into a single executable
script `scripts/bastion-first-apply.sh` that operators can run with one command.

Purpose: reduce the "first apply" ceremony from 10 manual copy-paste blocks to a single command while
keeping the runbook as the canonical reference for troubleshooting and explanation.

Output: a new file `scripts/bastion-first-apply.sh` (plus `chmod +x`), following the style of
`scripts/retry-apply.sh` religiously — `#!/bin/bash`, Portuguese header/comments, `set -euo pipefail`,
`INFRA_DIR` pattern, timestamped `echo` for progress, no ANSI colors, no tee-to-file.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@./CLAUDE.md
@docs/runbooks/bastion-first-apply.md
@scripts/retry-apply.sh

<interfaces>
<!-- Conventions extracted from scripts/retry-apply.sh — executor MUST mirror these exactly. -->

Shebang + header format (from scripts/retry-apply.sh lines 1-3):
```bash
#!/bin/bash
# retry-apply.sh — retenta terraform apply ate ARM capacity ficar disponivel
# Uso: nohup bash scripts/retry-apply.sh > /tmp/tf-retry.log 2>&1 &
```

Guard + INFRA_DIR pattern (lines 5-7):
```bash
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/../terraform/infra" && pwd)"
```

Progress echo pattern (line 14):
```bash
echo "$(date '+%Y-%m-%d %H:%M:%S') — Attempting terraform apply..."
```

<!-- Runbook bash blocks that become functions — extracted verbatim from docs/runbooks/bastion-first-apply.md -->

Passo 1 (lines 115-116) → function `discover_terraform_outputs`:
```bash
export CLUSTER_ID=$(terraform output -raw cluster_id)
export BASTION_OCID=$(terraform output -raw bastion_ocid)
```

Passo 2 (line 130) → function `generate_initial_kubeconfig`:
```bash
eval "$(terraform output -raw kubeconfig_command)"
```

Passo 3 (lines 147-150) → function `discover_oke_ip`:
```bash
export OKE_IP=$(oci ce cluster get \
  --cluster-id "$CLUSTER_ID" \
  --query 'data.endpoints."private-endpoint"' \
  --raw-output | cut -d: -f1)
```

Passo 4 (lines 166-173) → function `create_bastion_session`:
```bash
export SESSION_OCID=$(oci bastion session create-port-forwarding \
  --bastion-id "$BASTION_OCID" \
  --display-name "assessforge-first-apply-$(date +%s)" \
  --ssh-public-key-file "$SSH_PUBLIC_KEY" \
  --target-private-ip "$OKE_IP" \
  --target-port "$TUNNEL_PORT" \
  --session-ttl "$SESSION_TTL" \
  --query 'data.id' --raw-output)
```

Passo 5 (lines 187-197) → function `wait_for_session_active`:
```bash
for i in $(seq 1 40); do   # 40 x 3s = 120s
  STATE=$(oci bastion session get \
    --session-id "$SESSION_OCID" \
    --query 'data."lifecycle-state"' --raw-output)
  echo "$(date '+%Y-%m-%d %H:%M:%S') — [$i/40] Estado da sessao: $STATE"
  if [ "$STATE" = "ACTIVE" ]; then
    break
  fi
  sleep 3
done
```

Passo 6 (lines 216-221) → function `open_ssh_tunnel`:
```bash
ssh -f -N \
  -L "$TUNNEL_PORT:$OKE_IP:6443" \
  -i "$SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=60 \
  "$SESSION_OCID@host.bastion.$REGION.oci.oraclecloud.com"
```

Passo 7 (lines 236-237) → function `rewrite_kubeconfig` (idempotent guard):
```bash
# Idempotencia: so roda sed se o arquivo ainda aponta para o IP privado
if grep -q "https://$OKE_IP:6443" "$HOME/.kube/config-assessforge"; then
  sed -i "s|https://$OKE_IP:6443|https://127.0.0.1:$TUNNEL_PORT|g" \
    "$HOME/.kube/config-assessforge"
fi
```

Passo 8 (line 252) → function `validate_cluster`:
```bash
KUBECONFIG="$HOME/.kube/config-assessforge" kubectl get nodes
```

Passo 9 (lines 270-277) → function `run_apply`:
```bash
cd "$INFRA_DIR"
terraform apply    # SEM -auto-approve; operador confirma
```
(Nao executar `terraform init -upgrade` automaticamente — so se o apply falhar, o operador decide.)

Teardown (lines 290-300) → function `teardown`:
```bash
pkill -f "ssh.*$TUNNEL_PORT:.*:6443" \
  && echo "Tunel encerrado" \
  || echo "Nenhum tunel ativo (nada para matar)"

oci bastion session delete --session-id "$SESSION_OCID" --force
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: Create scripts/bastion-first-apply.sh and chmod +x</name>
  <files>scripts/bastion-first-apply.sh</files>
  <behavior>
    Script must:
    - Default mode (`bash scripts/bastion-first-apply.sh`): execute steps 1-10 end-to-end, fail loud with Portuguese error + runbook reference on any step failure, prompt operator on final `terraform apply` (no `-auto-approve`).
    - `--teardown` flag: kill SSH tunnel (pkill by TUNNEL_PORT+OKE_IP pattern), delete Bastion session using SESSION_OCID from `/tmp/bastion-session.ocid`. If state file missing, call `oci bastion session list --bastion-id $BASTION_OCID --session-lifecycle-state ACTIVE` and delete matches. Remove state file at end.
    - `--skip-apply` flag: execute steps 1-9 (SSH key, outputs, kubeconfig, OKE IP, session, wait, tunnel, rewrite, kubectl validate) and exit 0 before `terraform apply`.
    - Env var overrides with defaults: `SSH_KEY` (default `$HOME/.ssh/id_rsa`), `REGION` (default `sa-saopaulo-1`), `SESSION_TTL` (default `10800`), `TUNNEL_PORT` (default `6443`). Derive `SSH_PRIVATE_KEY="$SSH_KEY"` and `SSH_PUBLIC_KEY="${SSH_KEY}.pub"` from the single `SSH_KEY` variable.
    - Idempotent kubeconfig rewrite (Passo 7): only run `sed` if file still contains `https://$OKE_IP:6443`.
    - Session polling (Passo 5): 40 iterations x 3s = 120s max, exit with Portuguese error "Sessao Bastion nao ficou ACTIVE em 120s. Consulte docs/runbooks/bastion-first-apply.md#sessao-bastion-presa-em-creating" on timeout.
    - Post-tunnel validation (Passo 8 fail): if `kubectl get nodes` fails, print "Falha ao conectar no cluster. Cheque o tunel com: ps -ef | grep 'ssh.*$TUNNEL_PORT' — Consulte docs/runbooks/bastion-first-apply.md#kubectl-get-nodes-da-timeout" and exit 1.
    - State persistence: write `$SESSION_OCID` to `/tmp/bastion-session.ocid` immediately after creation (Passo 4) so `--teardown` can read it later.
    - SSH key check (Passo 0 / Pre-requisites): if `$SSH_PRIVATE_KEY` exists but `$SSH_PUBLIC_KEY` missing, derive pub with `ssh-keygen -yf`. If neither exists and `SSH_KEY` is the default, generate ed25519 pair at `$HOME/.ssh/assessforge_ed25519` with empty passphrase and re-point `SSH_PRIVATE_KEY`/`SSH_PUBLIC_KEY`. If `SSH_KEY` was explicitly set but files missing, fail with clear error pointing to runbook Pre-requisites.
  </behavior>
  <action>
Create a new file at `scripts/bastion-first-apply.sh` following EXACTLY the style of `scripts/retry-apply.sh`:

1. Shebang line: `#!/bin/bash`

2. Header (3 lines total, Portuguese, no accents if matching retry-apply.sh's accent-free style — the reference file uses `ate` not `ate'`, so keep accents OFF to match):
```
#!/bin/bash
# bastion-first-apply.sh — automatiza os passos 1-10 do runbook bastion-first-apply
# Uso: bash scripts/bastion-first-apply.sh [--teardown | --skip-apply]
```

3. `set -euo pipefail` on its own line after the header.

4. Env var defaults block (right after `set -euo pipefail`):
```bash
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_PRIVATE_KEY="$SSH_KEY"
SSH_PUBLIC_KEY="${SSH_KEY}.pub"
REGION="${REGION:-sa-saopaulo-1}"
SESSION_TTL="${SESSION_TTL:-10800}"
TUNNEL_PORT="${TUNNEL_PORT:-6443}"

INFRA_DIR="$(cd "$(dirname "$0")/../terraform/infra" && pwd)"
STATE_FILE="/tmp/bastion-session.ocid"
RUNBOOK="docs/runbooks/bastion-first-apply.md"
```

5. Helper function for timestamped progress (matches retry-apply.sh pattern):
```bash
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') — $*"; }
die() { echo "$(date '+%Y-%m-%d %H:%M:%S') — ERRO: $*" >&2; exit 1; }
```

6. Implement functions IN THIS ORDER (order matters for readability, matches runbook flow):

   - `check_ssh_key`: If `$SSH_PRIVATE_KEY` doesnt exist AND `$SSH_KEY` equals the default `$HOME/.ssh/id_rsa` path, generate `$HOME/.ssh/assessforge_ed25519` via `ssh-keygen -t ed25519 -f ... -N '' -C "assessforge-bastion-$(date +%Y%m%d)"` and re-point both vars. If `$SSH_PRIVATE_KEY` exists but `$SSH_PUBLIC_KEY` missing, derive via `ssh-keygen -yf "$SSH_PRIVATE_KEY" > "$SSH_PUBLIC_KEY"`. If `$SSH_KEY` was non-default and files missing, `die "SSH_KEY aponta para $SSH_KEY mas o arquivo nao existe. Consulte $RUNBOOK#pre-requisitos"`.

   - `discover_terraform_outputs`: `cd "$INFRA_DIR"`, `export CLUSTER_ID=$(terraform output -raw cluster_id)`, `export BASTION_OCID=$(terraform output -raw bastion_ocid)`. `log` both values. Fail-loud via `set -e` se o output nao existir.

   - `generate_initial_kubeconfig`: if `[ ! -f "$HOME/.kube/config-assessforge" ]`, run `eval "$(terraform output -raw kubeconfig_command)"`. Validate file exists afterwards or `die`.

   - `discover_oke_ip`: `export OKE_IP=$(oci ce cluster get --cluster-id "$CLUSTER_ID" --query 'data.endpoints."private-endpoint"' --raw-output | cut -d: -f1)`. `log "OKE API IP privado: $OKE_IP"`.

   - `create_bastion_session`: exact OCI CLI call from Passo 4 (use `$TUNNEL_PORT` in place of hardcoded 6443 on `--target-port`; use `$SESSION_TTL`). After success, `echo "$SESSION_OCID" > "$STATE_FILE"` for teardown fallback. `log "Sessao criada: $SESSION_OCID (persistida em $STATE_FILE)"`.

   - `wait_for_session_active`: `for i in $(seq 1 40); do ... sleep 3; done`. On success `log "OK: sessao ACTIVE"` and return. On exhaustion, `die "Sessao Bastion nao ficou ACTIVE em 120s. Consulte $RUNBOOK#sessao-bastion-presa-em-creating"`.

   - `open_ssh_tunnel`: `ssh -f -N -L "$TUNNEL_PORT:$OKE_IP:6443" -i "$SSH_PRIVATE_KEY" -o StrictHostKeyChecking=accept-new -o ServerAliveInterval=60 "$SESSION_OCID@host.bastion.$REGION.oci.oraclecloud.com"`. After: `pgrep -af "ssh.*$TUNNEL_PORT:$OKE_IP:6443" >/dev/null || die "Tunel SSH nao subiu. Consulte $RUNBOOK#tunel-ssh-recusa-conexao"`.

   - `rewrite_kubeconfig`: guarded `if grep -q "https://$OKE_IP:6443" "$HOME/.kube/config-assessforge"; then sed -i "s|https://$OKE_IP:6443|https://127.0.0.1:$TUNNEL_PORT|g" "$HOME/.kube/config-assessforge"; log "kubeconfig reescrito para 127.0.0.1:$TUNNEL_PORT"; else log "kubeconfig ja aponta para localhost (no-op)"; fi`.

   - `validate_cluster`: `KUBECONFIG="$HOME/.kube/config-assessforge" kubectl get nodes` inside `set +e` / check exit code. On failure: `die "Falha ao conectar no cluster via tunel. Cheque 'ps -ef | grep ssh.*$TUNNEL_PORT'. Consulte $RUNBOOK#kubectl-get-nodes-da-timeout"`.

   - `run_apply`: `cd "$INFRA_DIR"` + `terraform apply` (NO `-auto-approve` — critical per design_requirements; operator confirms interactively). Do NOT run `terraform init -upgrade` automatically.

   - `teardown`: read `$STATE_FILE` into `SESSION_OCID` if present; otherwise discover `BASTION_OCID` from `terraform output` and run `oci bastion session list --bastion-id "$BASTION_OCID" --session-lifecycle-state ACTIVE --query 'data[].id' --raw-output` to find active sessions. For each found: kill tunnel via `pkill -f "ssh.*$TUNNEL_PORT:.*:6443" || true` (tolerate no-match) and `oci bastion session delete --session-id "$s" --force`. Remove `$STATE_FILE` at end.

7. Main dispatcher at bottom of file:
```bash
case "${1:-}" in
  --teardown)
    teardown
    ;;
  --skip-apply)
    check_ssh_key
    discover_terraform_outputs
    generate_initial_kubeconfig
    discover_oke_ip
    create_bastion_session
    wait_for_session_active
    open_ssh_tunnel
    rewrite_kubeconfig
    validate_cluster
    log "Skip-apply: ambiente pronto. Rode 'cd $INFRA_DIR && terraform apply' manualmente."
    ;;
  "")
    check_ssh_key
    discover_terraform_outputs
    generate_initial_kubeconfig
    discover_oke_ip
    create_bastion_session
    wait_for_session_active
    open_ssh_tunnel
    rewrite_kubeconfig
    validate_cluster
    run_apply
    ;;
  *)
    die "Flag desconhecida: $1. Uso: bash scripts/bastion-first-apply.sh [--teardown | --skip-apply]"
    ;;
esac
```

8. Inline comments in Portuguese explaining the "porque" not the "o que" — mirror the runbook's explanatory comments (e.g., `# region sa-saopaulo-1 hardcoded em CLAUDE.md -- usado no host do bastion`, `# -L forward: localhost:$TUNNEL_PORT -> $OKE_IP:6443 atraves do bastion`, `# sessao em CREATING retorna Connection refused -- por isso o polling antes do ssh`).

9. After writing the file, make it executable: `chmod +x scripts/bastion-first-apply.sh`.

STYLE RULES (non-negotiable — match scripts/retry-apply.sh):
- `#!/bin/bash` (not `#!/usr/bin/env bash`)
- Header comments in Portuguese (without accents, matching retry-apply.sh's `ate` style)
- `set -euo pipefail` placement: on its own line right after the header block
- `INFRA_DIR="$(cd "$(dirname "$0")/../terraform/infra" && pwd)"` exact pattern
- Timestamped `echo` via `$(date '+%Y-%m-%d %H:%M:%S')` — match format EXACTLY (em-dash separator, not `--`)
- No ANSI colors, no `tee` to log file, no fancy logging frameworks
- Small focused functions (one concern each)
- Use `>&2` for error output inside `die`

WHAT NOT TO DO:
- Do NOT modify `docs/runbooks/bastion-first-apply.md`.
- Do NOT pass `-auto-approve` on the final `terraform apply` (risk too high per design_requirements).
- Do NOT run `terraform init -upgrade` automatically — only on failure, let operator decide.
- Do NOT use `set -x` or debug tracing by default.
- Do NOT write logs to a file (retry-apply.sh uses tee only for capacity detection; this script doesnt need it).
  </action>
  <verify>
    <automated>bash -n /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && test -x /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && head -3 /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh | grep -q '^#!/bin/bash' && grep -q 'set -euo pipefail' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'INFRA_DIR="\$(cd "\$(dirname "\$0")/../terraform/infra" && pwd)"' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'check_ssh_key' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'create_bastion_session' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'wait_for_session_active' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'open_ssh_tunnel' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'rewrite_kubeconfig' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'validate_cluster' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'run_apply' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'teardown' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q -- '--teardown' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q -- '--skip-apply' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && ! grep -q 'auto-approve' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q '/tmp/bastion-session.ocid' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh && grep -q 'docs/runbooks/bastion-first-apply.md' /home/rodrigo/projects/AssessForge/infra-setup/scripts/bastion-first-apply.sh</automated>
  </verify>
  <done>
    - File `scripts/bastion-first-apply.sh` exists with executable bit set.
    - `bash -n` passes (syntactically valid bash).
    - Contains all 9 required functions: `check_ssh_key`, `discover_terraform_outputs`, `generate_initial_kubeconfig`, `discover_oke_ip`, `create_bastion_session`, `wait_for_session_active`, `open_ssh_tunnel`, `rewrite_kubeconfig`, `validate_cluster`, `run_apply`, `teardown`.
    - Supports `--teardown` and `--skip-apply` flags via case dispatcher.
    - Does NOT contain `auto-approve` (per design_requirements).
    - Does NOT contain `init -upgrade` invoked unconditionally (only reference in comments is allowed; no automatic call).
    - Persists SESSION_OCID to `/tmp/bastion-session.ocid`.
    - Error messages reference `docs/runbooks/bastion-first-apply.md`.
    - Uses `INFRA_DIR` pattern identical to `scripts/retry-apply.sh`.
    - Uses `$(date '+%Y-%m-%d %H:%M:%S')` timestamp pattern in progress output.
    - Runbook `docs/runbooks/bastion-first-apply.md` is UNCHANGED (`git status` shows no modification to it).
  </done>
</task>

</tasks>

<verification>
Manual smoke verification after execution (not run by executor — documented for operator):

1. Lint: `bash -n scripts/bastion-first-apply.sh` → no output, exit 0.
2. Shellcheck (if available): `shellcheck scripts/bastion-first-apply.sh` → zero warnings preferred, informational OK.
3. Help/bad flag: `bash scripts/bastion-first-apply.sh --nope` → exits 1 with Portuguese "Flag desconhecida" error.
4. Dry style-match: `diff <(head -8 scripts/retry-apply.sh | sed 's/retry-apply/bastion-first-apply/g; s/retenta terraform.*/automatiza os passos 1-10/') <(head -8 scripts/bastion-first-apply.sh)` — structure should be visually identical (shebang, header, blank, `set -euo pipefail`, blank, `INFRA_DIR=`).
5. Runbook unchanged: `git diff docs/runbooks/bastion-first-apply.md` → empty.
6. Real run (operator, against live OCI): `bash scripts/bastion-first-apply.sh --skip-apply` succeeds and `kubectl --kubeconfig ~/.kube/config-assessforge get nodes` returns 2 nodes.
7. Teardown: `bash scripts/bastion-first-apply.sh --teardown` kills tunnel and deletes session; `oci bastion session list --bastion-id <B> --session-lifecycle-state ACTIVE` returns empty.
</verification>

<success_criteria>
- `scripts/bastion-first-apply.sh` exists, is executable, and passes `bash -n` lint.
- Script style is indistinguishable from `scripts/retry-apply.sh` at a glance (shebang, header format, Portuguese comments, `set -euo pipefail`, `INFRA_DIR` pattern, timestamped echo).
- All 10 runbook steps are encapsulated in small named functions and invoked by a single `case` dispatcher.
- Default invocation runs end-to-end; `--teardown` cleans up; `--skip-apply` stops before `terraform apply`.
- Idempotent kubeconfig rewrite (Passo 7 guard).
- `--teardown` works both with persisted state file AND via `oci bastion session list` fallback.
- Error messages always reference `docs/runbooks/bastion-first-apply.md` so the operator lands on the troubleshooting section.
- `docs/runbooks/bastion-first-apply.md` is NOT modified.
</success_criteria>

<output>
After completion, create `.planning/quick/260423-woo-extrair-script-bash-execut-vel-do-runboo/260423-woo-01-SUMMARY.md` summarizing:
- What was created (file path, line count, functions exposed)
- Style conformance with `scripts/retry-apply.sh` (confirmed patterns)
- Any deviations from the runbook (e.g., 40x3s polling instead of 24x5s to match 120s cap at finer granularity — call out if applied)
- Operator-facing usage examples for all three modes (default, --skip-apply, --teardown)
</output>
