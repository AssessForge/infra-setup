#!/bin/bash
# bastion-first-apply.sh — automatiza os passos 1-10 do runbook bastion-first-apply
# Uso: bash scripts/bastion-first-apply.sh [--teardown | --skip-apply]

set -euo pipefail

# region sa-saopaulo-1 hardcoded em CLAUDE.md -- usado no host do bastion
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_rsa}"
SSH_PRIVATE_KEY="$SSH_KEY"
SSH_PUBLIC_KEY="${SSH_KEY}.pub"
REGION="${REGION:-sa-saopaulo-1}"
SESSION_TTL="${SESSION_TTL:-10800}"
TUNNEL_PORT="${TUNNEL_PORT:-6443}"

INFRA_DIR="$(cd "$(dirname "$0")/../terraform/infra" && pwd)"
STATE_FILE="/tmp/bastion-session.ocid"
RUNBOOK="docs/runbooks/bastion-first-apply.md"
KUBECONFIG_PATH="$HOME/.kube/config-assessforge"
DEFAULT_SSH_KEY="$HOME/.ssh/id_rsa"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') — $*"; }
die() { echo "$(date '+%Y-%m-%d %H:%M:%S') — ERRO: $*" >&2; exit 1; }

# Passo 0 -- garante que o par de chaves SSH esta pronto antes de criar a sessao
check_ssh_key() {
  if [ ! -f "$SSH_PRIVATE_KEY" ]; then
    if [ "$SSH_KEY" = "$DEFAULT_SSH_KEY" ]; then
      # Usuario nao tem chave -- gerar par dedicado ed25519 sem passphrase (tunneling nao interativo)
      local GENERATED="$HOME/.ssh/assessforge_ed25519"
      log "Nenhuma chave em $SSH_PRIVATE_KEY -- gerando par ed25519 dedicado em $GENERATED"
      ssh-keygen -t ed25519 -f "$GENERATED" -N '' -C "assessforge-bastion-$(date +%Y%m%d)" >/dev/null
      SSH_PRIVATE_KEY="$GENERATED"
      SSH_PUBLIC_KEY="${GENERATED}.pub"
      log "Chaves geradas: $SSH_PRIVATE_KEY / $SSH_PUBLIC_KEY"
    else
      die "SSH_KEY aponta para $SSH_KEY mas o arquivo nao existe. Consulte $RUNBOOK#pre-requisitos"
    fi
  fi

  if [ ! -f "$SSH_PUBLIC_KEY" ]; then
    # Private existe mas publica sumiu -- derivar via ssh-keygen -yf
    log "Public key ausente em $SSH_PUBLIC_KEY -- derivando a partir da private key"
    ssh-keygen -yf "$SSH_PRIVATE_KEY" > "$SSH_PUBLIC_KEY"
  fi

  log "SSH OK: private=$SSH_PRIVATE_KEY public=$SSH_PUBLIC_KEY"
}

# Passo 1 -- le outputs do terraform infra e exporta como env vars
discover_terraform_outputs() {
  cd "$INFRA_DIR"
  # set -e garante que terraform output -raw falha o script se o output nao existir
  export CLUSTER_ID
  CLUSTER_ID=$(terraform output -raw cluster_id)
  export BASTION_OCID
  BASTION_OCID=$(terraform output -raw bastion_ocid)
  log "Cluster:  $CLUSTER_ID"
  log "Bastion:  $BASTION_OCID"
}

# Passo 2 -- gera kubeconfig apontando para IP privado (sera reescrito no Passo 7)
generate_initial_kubeconfig() {
  if [ ! -f "$KUBECONFIG_PATH" ]; then
    log "Kubeconfig ausente em $KUBECONFIG_PATH -- gerando via terraform output kubeconfig_command"
    eval "$(terraform output -raw kubeconfig_command)"
  else
    log "Kubeconfig ja existe em $KUBECONFIG_PATH (no-op)"
  fi
  test -f "$KUBECONFIG_PATH" || die "kubeconfig nao foi criado em $KUBECONFIG_PATH. Consulte $RUNBOOK#passo-2--gerar-kubeconfig-inicial"
}

# Passo 3 -- descobre IP privado da API do OKE (alvo do port-forwarding)
discover_oke_ip() {
  # endpoint vem no formato "10.0.2.x:6443" -- cortar com ':' para pegar so o IP
  export OKE_IP
  OKE_IP=$(oci ce cluster get \
    --cluster-id "$CLUSTER_ID" \
    --query 'data.endpoints."private-endpoint"' \
    --raw-output | cut -d: -f1)
  log "OKE API IP privado: $OKE_IP"
}

# Passo 4 -- cria sessao Bastion port-forwarding
create_bastion_session() {
  # --display-name com timestamp evita colisao com sessoes antigas
  # --session-ttl 10800 (3h) suficiente para re-apply + margem de depuracao
  export SESSION_OCID
  SESSION_OCID=$(oci bastion session create-port-forwarding \
    --bastion-id "$BASTION_OCID" \
    --display-name "assessforge-first-apply-$(date +%s)" \
    --ssh-public-key-file "$SSH_PUBLIC_KEY" \
    --target-private-ip "$OKE_IP" \
    --target-port "$TUNNEL_PORT" \
    --session-ttl "$SESSION_TTL" \
    --query 'data.id' --raw-output)

  # Persistir OCID para teardown conseguir encontrar mesmo em outra shell
  echo "$SESSION_OCID" > "$STATE_FILE"
  log "Sessao criada: $SESSION_OCID (persistida em $STATE_FILE)"
}

# Passo 5 -- polling ate sessao virar ACTIVE
wait_for_session_active() {
  # sessao em CREATING retorna Connection refused -- por isso o polling antes do ssh
  # 40 x 3s = 120s cap (granularidade fina para detectar ACTIVE rapido)
  local STATE
  for i in $(seq 1 40); do
    STATE=$(oci bastion session get \
      --session-id "$SESSION_OCID" \
      --query 'data."lifecycle-state"' --raw-output)
    log "[$i/40] Estado da sessao: $STATE"
    if [ "$STATE" = "ACTIVE" ]; then
      log "OK: sessao ACTIVE"
      return 0
    fi
    sleep 3
  done
  die "Sessao Bastion nao ficou ACTIVE em 120s. Consulte $RUNBOOK#sessao-bastion-presa-em-creating"
}

# Passo 6 -- abre tunel SSH em background
open_ssh_tunnel() {
  # -f fork p/ background, -N sem comando remoto
  # -L forward: localhost:$TUNNEL_PORT -> $OKE_IP:6443 atraves do bastion
  # StrictHostKeyChecking=accept-new -- aceita fingerprint do bastion sem prompt
  # ServerAliveInterval=60 -- evita que firewalls derrubem o tunel por ociosidade
  ssh -f -N \
    -L "$TUNNEL_PORT:$OKE_IP:6443" \
    -i "$SSH_PRIVATE_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o ServerAliveInterval=60 \
    "$SESSION_OCID@host.bastion.$REGION.oci.oraclecloud.com"

  pgrep -af "ssh.*$TUNNEL_PORT:$OKE_IP:6443" >/dev/null \
    || die "Tunel SSH nao subiu. Consulte $RUNBOOK#tunel-ssh-recusa-conexao"
  log "Tunel SSH ativo em 127.0.0.1:$TUNNEL_PORT -> $OKE_IP:6443"
}

# Passo 7 -- reescreve kubeconfig para 127.0.0.1 (idempotente)
rewrite_kubeconfig() {
  # Idempotencia: so roda sed se o arquivo ainda aponta para o IP privado
  if grep -q "https://$OKE_IP:6443" "$KUBECONFIG_PATH"; then
    sed -i "s|https://$OKE_IP:6443|https://127.0.0.1:$TUNNEL_PORT|g" "$KUBECONFIG_PATH"
    log "kubeconfig reescrito para 127.0.0.1:$TUNNEL_PORT"
  else
    log "kubeconfig ja aponta para localhost (no-op)"
  fi
}

# Passo 8 -- valida conexao ao cluster via tunel
validate_cluster() {
  set +e
  KUBECONFIG="$KUBECONFIG_PATH" kubectl get nodes
  local EC=$?
  set -e
  if [ $EC -ne 0 ]; then
    die "Falha ao conectar no cluster via tunel. Cheque 'ps -ef | grep ssh.*$TUNNEL_PORT'. Consulte $RUNBOOK#kubectl-get-nodes-da-timeout"
  fi
  log "Cluster acessivel via tunel"
}

# Passo 9 -- re-executa terraform apply (interativo; operador confirma plan)
run_apply() {
  cd "$INFRA_DIR"
  # Nao executar terraform init -upgrade automaticamente -- so se o apply falhar, o operador decide.
  log "Executando terraform apply (operador confirma interativamente)"
  terraform apply
}

# Teardown -- mata tunel e deleta sessao Bastion para liberar slot
teardown() {
  local SESSION_TO_DELETE=""

  if [ -f "$STATE_FILE" ]; then
    SESSION_TO_DELETE=$(cat "$STATE_FILE")
    log "Sessao encontrada em $STATE_FILE: $SESSION_TO_DELETE"
  else
    # Fallback: listar sessoes ACTIVE via OCI CLI
    log "State file $STATE_FILE ausente -- consultando sessoes ACTIVE via oci bastion session list"
    cd "$INFRA_DIR"
    local BID
    BID=$(terraform output -raw bastion_ocid 2>/dev/null || true)
    if [ -z "$BID" ]; then
      die "BASTION_OCID nao encontrado via terraform output. Consulte $RUNBOOK#teardown"
    fi
    SESSION_TO_DELETE=$(oci bastion session list \
      --bastion-id "$BID" \
      --session-lifecycle-state ACTIVE \
      --query 'data[].id' --raw-output || true)
  fi

  # Mata tunel pelo padrao da linha -L (tolerante a no-match)
  pkill -f "ssh.*$TUNNEL_PORT:.*:6443" \
    && log "Tunel encerrado" \
    || log "Nenhum tunel ativo (nada para matar)"

  if [ -n "$SESSION_TO_DELETE" ]; then
    # Pode ser multi-linha (lista) ou unico OCID
    for s in $SESSION_TO_DELETE; do
      log "Deletando sessao Bastion: $s"
      oci bastion session delete --session-id "$s" --force || log "Falha ao deletar $s (pode ja estar deletada)"
    done
  else
    log "Nenhuma sessao Bastion ACTIVE para deletar"
  fi

  rm -f "$STATE_FILE"
  log "Teardown concluido"
}

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
