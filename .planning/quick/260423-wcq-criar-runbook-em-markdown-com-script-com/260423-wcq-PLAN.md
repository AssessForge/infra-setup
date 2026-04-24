---
phase: quick-260423-wcq
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - docs/runbooks/bastion-first-apply.md
autonomous: true
requirements:
  - DOC-BASTION-RUNBOOK-01
user_setup: []

must_haves:
  truths:
    - "Operator with no prior SSH key can generate one following the runbook (ssh-keygen fallback block documented)"
    - "Operator with an existing SSH key at a non-default path can reuse it (SSH_PUBLIC_KEY env var pattern documented)"
    - "Runbook explains WHY first terraform apply fails at argocd bootstrap (private endpoint + fileexists kubeconfig check in versions.tf)"
    - "Runbook discovers cluster_id, bastion_ocid and OKE private API IP via terraform outputs and `oci ce cluster get`"
    - "Runbook creates an OCI Bastion port-forwarding session using the operator's SSH public key"
    - "Runbook polls the bastion session until lifecycle-state = ACTIVE before opening the tunnel"
    - "Runbook opens the SSH tunnel in background against `host.bastion.sa-saopaulo-1.oci.oraclecloud.com` using `ssh -f -N -L 6443:$OKE_IP:6443`"
    - "Runbook rewrites `~/.kube/config-assessforge` so the server points to `https://127.0.0.1:6443` instead of the private IP"
    - "Runbook validates connectivity with `KUBECONFIG=~/.kube/config-assessforge kubectl get nodes` before re-running apply"
    - "Runbook instructs the operator to re-run `terraform apply` in `terraform/infra/` and expects it to proceed through `module.oci_argocd_bootstrap.helm_release.argocd`"
    - "Runbook documents teardown: kill background SSH tunnel, delete bastion session, note that after ArgoCD is bootstrapped the tunnel is no longer required for GitOps flows"
    - "Runbook includes a troubleshooting section covering: session stuck in CREATING, tunnel refuses connection, kubectl times out, `cluster unreachable` error after tunnel is up (mentions re-running `terraform apply` and `terraform init -upgrade` for provider re-evaluation of `fileexists`)"
    - "Prose is in Portuguese consistent with terraform/README.md and CLAUDE.md conventions"
    - "All bash blocks are env-var-driven and copy-paste safe independently"
    - "Runbook cross-links `terraform/README.md` (Etapa intermediária) and CLAUDE.md (security constraints) for broader context"
  artifacts:
    - path: "docs/runbooks/bastion-first-apply.md"
      provides: "Standalone markdown runbook with inline bash script for OCI Bastion tunnel setup + first post-Phase-1 terraform apply, including SSH key bootstrap fallback"
      min_lines: 180
      contains: "host.bastion.sa-saopaulo-1.oci.oraclecloud.com"
  key_links:
    - from: "docs/runbooks/bastion-first-apply.md"
      to: "terraform/README.md"
      via: "Markdown link back to `terraform/README.md` 'Etapa intermediária' section"
      pattern: "terraform/README\\.md"
    - from: "docs/runbooks/bastion-first-apply.md"
      to: "CLAUDE.md"
      via: "Reference to the 'API endpoint is PRIVATE' security constraint"
      pattern: "CLAUDE\\.md|API endpoint.*privad"
    - from: "docs/runbooks/bastion-first-apply.md"
      to: "terraform/infra/versions.tf"
      via: "Explanation of the `fileexists(~/.kube/config-assessforge)` two-phase provider init pattern"
      pattern: "fileexists"
---

<objective>
Criar um runbook operacional standalone em Markdown — `docs/runbooks/bastion-first-apply.md` — que guie o operador do primeiro `terraform apply` em `terraform/infra/` pós-Fase-1 através do setup completo do túnel OCI Bastion, desde a criação/reaproveitamento da chave SSH até a execução bem-sucedida do `module.oci_argocd_bootstrap`.

Purpose: Após o quick-260423-va5 corrigir as regras de NSG entre workers e API endpoint, o `terraform apply` passou do provisionamento do node pool, Vault e secrets — mas falhou em `module.oci_argocd_bootstrap.helm_release.argocd` com `Kubernetes cluster unreachable: invalid configuration: no configuration has been provided`. A causa não é um bug, é operacional: (1) o endpoint da API do OKE é privado por design (`is_public_ip_enabled = false`, constraint do CLAUDE.md), (2) o kubeconfig gerado aponta para o IP privado inalcançável (`10.0.2.237:6443`), e (3) os providers Helm/Kubernetes/Kubectl em `terraform/infra/versions.tf` checam `fileexists(~/.kube/config-assessforge)` — no primeiro plan/apply o arquivo ainda não existe, então os providers inicializam com `config_path = null`. A seção "Etapa intermediária" atual do `terraform/README.md` está escrita para o design antigo de dois layers (infra/ + k8s/) e não cobre o caso do `oci-argocd-bootstrap` dentro do layer infra, não documenta o fallback de geração de chave SSH, e não explica o padrão "rodar apply duas vezes" imposto pelo `fileexists`. Um runbook dedicado resolve isso sem poluir o README principal.

Output: Um único arquivo Markdown novo em `docs/runbooks/bastion-first-apply.md` (diretório ainda não existe — será criado pela tarefa). Nenhuma outra modificação no repositório. Nenhum arquivo `.sh` separado — todo o script fica inline em blocos de código ```bash```.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@CLAUDE.md
@.planning/STATE.md
@terraform/README.md
@terraform/infra/versions.tf

<interfaces>
<!-- Outputs disponíveis em `terraform/infra/` relevantes para o runbook. -->
<!-- O executor NÃO precisa explorar o repositório para descobrir estes nomes. -->

Terraform outputs em `terraform/infra/` (já existentes, não criar novos):
- `cluster_id`           — OCID do cluster OKE (consumido por `oci ce cluster get`)
- `bastion_ocid`         — OCID do OCI Bastion Service
- `kubeconfig_command`   — Comando `oci ce cluster create-kubeconfig ...` pronto para `eval`

Provider init pattern em `terraform/infra/versions.tf`:
```hcl
locals {
  kubeconfig_path   = pathexpand("~/.kube/config-assessforge")
  kubeconfig_exists = fileexists(pathexpand("~/.kube/config-assessforge"))
}
# Fase 1 (cluster nao existe): config_path = null, providers inicializam sem conectar
# Fase 2 (apos kubeconfig gerado): config_path aponta para o arquivo e conectam normalmente
provider "helm"       { kubernetes = { config_path = local.kubeconfig_exists ? local.kubeconfig_path : null } }
provider "kubernetes" { config_path      = local.kubeconfig_exists ? local.kubeconfig_path : null }
provider "kubectl"    { config_path      = local.kubeconfig_exists ? local.kubeconfig_path : null
                        load_config_file = local.kubeconfig_exists }
```

Constraint da região (CLAUDE.md): `sa-saopaulo-1` — SSH bastion host é `host.bastion.sa-saopaulo-1.oci.oraclecloud.com`.

Constante do kubeconfig: `~/.kube/config-assessforge` (gerado por `null_resource.kubeconfig` no módulo `oci-oke`).

Template da seção atual (terraform/README.md linhas 82-120) serve como esqueleto — expandir com: geração de chave SSH, polling ACTIVE, `ssh -f` (fork to background + não alocar tty), re-apply, teardown, troubleshooting.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Criar docs/runbooks/bastion-first-apply.md com o runbook completo</name>
  <files>docs/runbooks/bastion-first-apply.md</files>
  <action>
Criar o diretório e o arquivo em uma única tarefa:

```bash
mkdir -p docs/runbooks
```

Escrever o arquivo `docs/runbooks/bastion-first-apply.md` seguindo EXATAMENTE a estrutura de H2/H3 abaixo. Toda a prosa deve ser em português (consistente com `terraform/README.md`). Todos os blocos de script devem usar fenced code blocks com a tag ```bash``` e ser **copy-paste-safe independentemente** — cada bloco define/reutiliza variáveis de ambiente no topo, sem depender de estado implícito entre blocos. Incluir comentários `#` em português dentro dos blocos bash explicando o "porquê" de cada comando não-trivial.

### Outline obrigatório (H1/H2/H3) — o executor DEVE criar exatamente estas seções, nesta ordem:

```
# Runbook: Primeiro `terraform apply` com OCI Bastion tunnel

## Contexto

## Pré-requisitos

### Chave SSH
### Ferramentas

## Passo 1 — Descobrir outputs da infraestrutura

## Passo 2 — Gerar kubeconfig inicial

## Passo 3 — Descobrir o IP privado do OKE API endpoint

## Passo 4 — Criar sessão OCI Bastion port-forwarding

## Passo 5 — Aguardar sessão ficar ACTIVE

## Passo 6 — Abrir túnel SSH em background

## Passo 7 — Reescrever kubeconfig para 127.0.0.1

## Passo 8 — Validar acesso ao cluster

## Passo 9 — Re-executar `terraform apply`

## Teardown — Encerrar túnel e sessão

## Troubleshooting

### Sessão Bastion presa em CREATING
### Túnel SSH recusa conexão
### `kubectl get nodes` dá timeout
### `terraform apply` ainda diz "cluster unreachable" depois do túnel subir

## Referências
```

### Conteúdo obrigatório por seção:

**`## Contexto`** — 2–3 parágrafos explicando:
- Por que este runbook existe: depois que a Fase 1 (módulos `oci-network`, `oci-iam`, `oci-oke`, `oci-vault`, `oci-argocd-bootstrap`) foi concluída até o `oci-vault`, o próximo `terraform apply` tenta subir o Helm release do ArgoCD via `module.oci_argocd_bootstrap` mas falha com `Kubernetes cluster unreachable: invalid configuration: no configuration has been provided`.
- Por que NÃO é um bug: o endpoint da API do OKE é **privado por design** (constraint documentada em [`CLAUDE.md`](../../CLAUDE.md) — seção Constraints, item "Networking/Identity"), apenas acessível via OCI Bastion Service.
- Por que precisa rodar apply **duas vezes**: os providers Helm/Kubernetes/Kubectl em [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf) usam `fileexists(~/.kube/config-assessforge)` — no primeiríssimo plan o arquivo não existe, então os providers inicializam com `config_path = null` e não conseguem se conectar ao cluster que está sendo criado no mesmo apply. O fluxo correto é: (a) rodar apply 1x até o cluster + node pool + vault existirem, (b) gerar kubeconfig + subir túnel Bastion, (c) rodar apply de novo — agora `fileexists` retorna true e o ArgoCD sobe.

**`## Pré-requisitos`** — lista introdutória + duas subseções:

**`### Chave SSH`** — cobrir os três cenários do usuário:
1. **Já tenho chave em `~/.ssh/id_rsa`** — seguir em frente, definir `SSH_PRIVATE_KEY=~/.ssh/id_rsa` e `SSH_PUBLIC_KEY=~/.ssh/id_rsa.pub`.
2. **Tenho chave em outro caminho** — exportar as env vars apontando para o caminho correto:
   ```bash
   # Exemplo: chave gerada previamente para outra infra
   export SSH_PRIVATE_KEY="$HOME/.ssh/assessforge_ed25519"
   export SSH_PUBLIC_KEY="$HOME/.ssh/assessforge_ed25519.pub"
   ```
3. **Ainda não tenho chave SSH nenhuma** — gerar agora:
   ```bash
   # Gerar par de chaves ed25519 dedicado para o Bastion do AssessForge
   # -N '' cria sem passphrase (OK para chave dedicada a tunneling, não a auth humana)
   # -C identifica a chave nos authorized_keys do Bastion
   ssh-keygen -t ed25519 -f "$HOME/.ssh/assessforge_ed25519" \
     -N '' -C "assessforge-bastion-$(date +%Y%m%d)"
   export SSH_PRIVATE_KEY="$HOME/.ssh/assessforge_ed25519"
   export SSH_PUBLIC_KEY="$HOME/.ssh/assessforge_ed25519.pub"
   ```
Terminar a subseção com a validação:
```bash
# Confirmar que as duas variáveis apontam para arquivos existentes
test -f "$SSH_PRIVATE_KEY" && test -f "$SSH_PUBLIC_KEY" && echo "OK: chaves SSH prontas" || echo "ERRO: defina SSH_PRIVATE_KEY e SSH_PUBLIC_KEY"
```

**`### Ferramentas`** — checklist simples (não executável):
- OCI CLI configurado com perfil `DEFAULT` (`~/.oci/config`)
- `kubectl` no PATH
- `terraform` ≥ 1.5 no PATH
- Primeiro `terraform apply` em `terraform/infra/` já concluído até o ponto onde o cluster OKE e o node pool existem (mesmo que o apply tenha falhado depois em `oci_argocd_bootstrap`).

**`## Passo 1 — Descobrir outputs da infraestrutura`**: explicar que o runbook roda a partir de `terraform/infra/` e usa os outputs já existentes. Bloco:
```bash
cd terraform/infra

# Ler os outputs uma vez e exportar como env vars para os próximos passos
export CLUSTER_ID=$(terraform output -raw cluster_id)
export BASTION_OCID=$(terraform output -raw bastion_ocid)

echo "Cluster:  $CLUSTER_ID"
echo "Bastion:  $BASTION_OCID"
```

**`## Passo 2 — Gerar kubeconfig inicial`**: explicar que este passo cria `~/.kube/config-assessforge` apontando ainda para o IP privado (será corrigido no Passo 7). Bloco:
```bash
# Usa o output kubeconfig_command (comando `oci ce cluster create-kubeconfig ...`)
# O arquivo gerado é ~/.kube/config-assessforge
eval "$(terraform output -raw kubeconfig_command)"

# Sanity check: arquivo existe
test -f "$HOME/.kube/config-assessforge" && echo "OK" || echo "ERRO: kubeconfig não foi criado"
```

**`## Passo 3 — Descobrir o IP privado do OKE API endpoint`**: bloco:
```bash
# $CLUSTER_ID deve estar exportado do Passo 1
# O endpoint privado vem no formato "10.0.2.x:6443" — só queremos o IP
export OKE_IP=$(oci ce cluster get \
  --cluster-id "$CLUSTER_ID" \
  --query 'data.endpoints."private-endpoint"' \
  --raw-output | cut -d: -f1)

echo "OKE API IP privado: $OKE_IP"
```

**`## Passo 4 — Criar sessão OCI Bastion port-forwarding`**: explicar que a sessão dura por padrão o `session-ttl` (3h aqui), e que o Bastion aceita apenas a public key registrada nela. Bloco:
```bash
# $BASTION_OCID, $OKE_IP, $SSH_PUBLIC_KEY devem estar exportados
# --ssh-public-key-file: O Bastion OCI só permite conexão de quem apresenta esta chave
# --session-ttl 10800 = 3h (máximo), tempo suficiente para os dois apply + margem
export SESSION_OCID=$(oci bastion session create-port-forwarding \
  --bastion-id "$BASTION_OCID" \
  --display-name "assessforge-first-apply-$(date +%s)" \
  --ssh-public-key-file "$SSH_PUBLIC_KEY" \
  --target-private-ip "$OKE_IP" \
  --target-port 6443 \
  --session-ttl 10800 \
  --query 'data.id' --raw-output)

echo "Sessão criada: $SESSION_OCID"
```

**`## Passo 5 — Aguardar sessão ficar ACTIVE`**: explicar que logo após `create-port-forwarding` o estado é `CREATING` e só após alguns segundos vira `ACTIVE` — tentar abrir o túnel antes disso dá `Connection refused`. Bloco com polling:
```bash
# Polling: espera até 120s pela sessão ficar ACTIVE (normalmente ~15-30s)
for i in $(seq 1 24); do
  STATE=$(oci bastion session get \
    --session-id "$SESSION_OCID" \
    --query 'data."lifecycle-state"' --raw-output)
  echo "[$i/24] Estado da sessão: $STATE"
  if [ "$STATE" = "ACTIVE" ]; then
    echo "OK: sessão pronta"
    break
  fi
  sleep 5
done
```

**`## Passo 6 — Abrir túnel SSH em background`**: explicar que a região `sa-saopaulo-1` usa o host `host.bastion.sa-saopaulo-1.oci.oraclecloud.com`, que `-f -N` envia o SSH para background sem executar comando remoto, e que o usuário SSH é o próprio OCID da sessão. Bloco:
```bash
# -f  = fork to background após autenticar
# -N  = não executar comando remoto (apenas port-forward)
# -L 6443:$OKE_IP:6443 = forward localhost:6443 -> OKE_IP:6443 via bastion
# -o StrictHostKeyChecking=accept-new = aceita fingerprint do bastion na primeira vez
ssh -f -N \
  -L "6443:$OKE_IP:6443" \
  -i "$SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=60 \
  "$SESSION_OCID@host.bastion.sa-saopaulo-1.oci.oraclecloud.com"

# Confirmar que o processo está rodando
pgrep -af "ssh.*6443:$OKE_IP:6443" || echo "ERRO: túnel não subiu"
```

**`## Passo 7 — Reescrever kubeconfig para 127.0.0.1`**: explicar que o kubeconfig gerado pelo `oci ce cluster create-kubeconfig` aponta para `https://$OKE_IP:6443`, mas como o túnel expõe localmente em `127.0.0.1:6443`, precisamos reescrever. Bloco:
```bash
# Substituir o host privado pelo localhost onde o túnel está escutando
sed -i "s|https://$OKE_IP:6443|https://127.0.0.1:6443|g" \
  "$HOME/.kube/config-assessforge"

# Conferir
grep -E "server:" "$HOME/.kube/config-assessforge"
# esperado: server: https://127.0.0.1:6443
```
*Nota importante*: adicionar callout explicando que ao rodar `sed` múltiplas vezes a substituição vira no-op (idempotente), mas se o operador regenerar o kubeconfig (Passo 2) precisa repetir este passo.

**`## Passo 8 — Validar acesso ao cluster`**: bloco:
```bash
# Se kubectl get nodes retornar a lista de nodes, o túnel está saudável
KUBECONFIG="$HOME/.kube/config-assessforge" kubectl get nodes

# Esperado: 2 nodes em estado Ready (ou NotReady se ainda inicializando, o que é OK)
```

**`## Passo 9 — Re-executar terraform apply`**: explicar que agora, com o kubeconfig funcional em disco, o `fileexists` em `versions.tf` retorna `true`, os providers Helm/Kubernetes/Kubectl conectam, e o `module.oci_argocd_bootstrap` consegue subir. Bloco:
```bash
cd terraform/infra

# Re-inicializar se os providers foram avaliados antes (cache de fileexists)
terraform init -upgrade

# Apply — dessa vez deve proceder através de helm_release.argocd
terraform apply
```

**`## Teardown — Encerrar túnel e sessão`**: explicar que após o ArgoCD estar operacional, toda mudança no cluster é via GitOps (PR no `gitops-setup`) — o túnel **não precisa ficar ativo**. Reabrir o túnel só é necessário para operações manuais de break-glass via `kubectl`. Bloco:
```bash
# 1. Matar o processo SSH em background
pkill -f "ssh.*6443:$OKE_IP:6443" && echo "Túnel encerrado" || echo "Nenhum túnel ativo"

# 2. Deletar a sessão Bastion (libera o slot — Always Free tem limites)
oci bastion session delete --session-id "$SESSION_OCID" --force

echo "Teardown concluído. Para operar o cluster no dia-a-dia, use o GitOps repo (gitops-setup)."
```

**`## Troubleshooting`** — quatro subseções, cada uma com sintoma + causa + comando corretivo:

**`### Sessão Bastion presa em CREATING`**: após 2 minutos ainda não virou ACTIVE. Causa: cota de sessões simultâneas no Bastion atingida, ou problema transiente OCI. Correção:
```bash
# Listar sessões ativas do bastion
oci bastion session list --bastion-id "$BASTION_OCID" \
  --query 'data[?"lifecycle-state"==`ACTIVE` || "lifecycle-state"==`CREATING`].{id:id,state:"lifecycle-state",name:"display-name"}'

# Deletar sessões órfãs antes de tentar de novo
oci bastion session delete --session-id <OCID-da-sessao-antiga> --force
```

**`### Túnel SSH recusa conexão`** — sintoma: `ssh: connect to host ... port 22: Connection refused` ou `Permission denied (publickey)`. Causa mais comum: (a) sessão não está ACTIVE ainda, (b) a public key passada no `--ssh-public-key-file` não bate com a private key em `-i`. Correção: validar que ambas env vars apontam para o **mesmo par**:
```bash
# O fingerprint da private key deve casar com o da public key
ssh-keygen -yf "$SSH_PRIVATE_KEY" | awk '{print $2}'
awk '{print $2}' "$SSH_PUBLIC_KEY"
# as duas linhas devem imprimir a mesma string
```

**`### kubectl get nodes dá timeout`** — sintoma: `Unable to connect to the server: net/http: TLS handshake timeout`. Causa: túnel subiu mas o processo morreu (ex.: laptop suspendeu). Correção: conferir o processo, matar resíduo e reabrir do Passo 5:
```bash
pgrep -af "ssh.*6443" || echo "Nenhum túnel ativo — reabrir a partir do Passo 5"
```

**`### terraform apply ainda diz "cluster unreachable" depois do túnel subir`** — sintoma: `Kubernetes cluster unreachable: invalid configuration: no configuration has been provided`. Causa: Terraform avaliou `fileexists()` no plan anterior (quando kubeconfig não existia) e cacheou `config_path = null`. Correção:
```bash
# Força re-avaliação dos providers com o estado atual do filesystem
cd terraform/infra
terraform init -upgrade

# Se ainda assim falhar, tocar um trivial no state para re-planejar do zero:
terraform plan   # observar na saída se os providers helm/kubernetes/kubectl listam config_path não-nulo
terraform apply
```
Mencionar também: confirmar `KUBECONFIG` default — o runbook usa `~/.kube/config-assessforge` (padrão do projeto), não `~/.kube/config`. Se o operador tiver outro `$KUBECONFIG` exportado no shell, o `terraform` pode estar olhando para o arquivo errado. Workaround:
```bash
unset KUBECONFIG   # os providers vão ler ~/.kube/config-assessforge via o caminho hardcoded em versions.tf
```

**`## Referências`** — bullets com links Markdown relativos:
- [`terraform/README.md`](../../terraform/README.md) — runbook operacional completo (Etapa intermediária tem a versão curta deste procedimento)
- [`CLAUDE.md`](../../CLAUDE.md) — constraints de segurança do projeto (API endpoint privado, Instance Principal, free tier)
- [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf) — padrão `fileexists(kubeconfig)` de inicialização em duas fases dos providers
- [OCI Bastion — Port forwarding sessions](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/managingsessions.htm)
- [OCI CE — Setting up cluster access](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm)

### Regras finais obrigatórias:
- **Prosa em português** (títulos, explicações, notas) — código e OCIDs em inglês/literal. Seguir tom técnico-operacional de `terraform/README.md`.
- **Comentários `#` dentro dos blocos bash em português** sempre que explicarem intenção.
- **NÃO** modificar `terraform/README.md` — fora de escopo.
- **NÃO** criar `.sh` separado — todo script inline em blocos ```bash```.
- **NÃO** usar `latest`/versões abertas em nada.
- O arquivo final deve ter **no mínimo 180 linhas** e conter a string literal `host.bastion.sa-saopaulo-1.oci.oraclecloud.com` (verificável no `must_haves.artifacts.contains`).
  </action>
  <verify>
    <automated>test -f docs/runbooks/bastion-first-apply.md && wc -l docs/runbooks/bastion-first-apply.md | awk '$1 >= 180 {exit 0} {exit 1}' && grep -q "host.bastion.sa-saopaulo-1.oci.oraclecloud.com" docs/runbooks/bastion-first-apply.md && grep -q "ssh-keygen" docs/runbooks/bastion-first-apply.md && grep -q "fileexists" docs/runbooks/bastion-first-apply.md && grep -q "terraform init -upgrade" docs/runbooks/bastion-first-apply.md && grep -q "sa-saopaulo-1" docs/runbooks/bastion-first-apply.md && grep -cE '^## ' docs/runbooks/bastion-first-apply.md | awk '$1 >= 12 {exit 0} {exit 1}' && echo OK</automated>
  </verify>
  <done>
Arquivo `docs/runbooks/bastion-first-apply.md` existe com no mínimo 180 linhas. Contém todas as 12+ seções H2 do outline, em ordem. Inclui a sub-seção `### Chave SSH` cobrindo os três cenários (chave existente default, chave em caminho customizado, sem chave — com `ssh-keygen`). Referencia `host.bastion.sa-saopaulo-1.oci.oraclecloud.com` literalmente. Explica o porquê do `fileexists`-based two-phase provider init e do `terraform init -upgrade`. Seção de troubleshooting cobre os 4 casos listados. Cross-links para `terraform/README.md` e `CLAUDE.md` presentes como Markdown links relativos. Prosa em português. Nenhum outro arquivo modificado.
  </done>
</task>

</tasks>

<verification>
- [ ] `docs/runbooks/bastion-first-apply.md` existe (diretório `docs/runbooks/` foi criado)
- [ ] Arquivo tem ≥ 180 linhas e ≥ 12 seções H2
- [ ] Contém literalmente `host.bastion.sa-saopaulo-1.oci.oraclecloud.com`
- [ ] Contém bloco `ssh-keygen -t ed25519` para o caso sem chave
- [ ] Explica o padrão `fileexists` de `terraform/infra/versions.tf`
- [ ] Inclui comando `terraform init -upgrade` na seção de troubleshooting
- [ ] `git status` mostra apenas 1 arquivo novo (`docs/runbooks/bastion-first-apply.md`) e 0 arquivos modificados
- [ ] `terraform/README.md` permanece inalterado (`git diff terraform/README.md` vazio)
</verification>

<success_criteria>
- Um operador novato que acabou de sofrer o erro `Kubernetes cluster unreachable` consegue, seguindo apenas este runbook (sem ler o `terraform/README.md`), chegar a um `terraform apply` bem-sucedido através do `module.oci_argocd_bootstrap`.
- Um operador que nunca gerou chave SSH antes consegue gerar uma e completar o túnel sem sair do runbook.
- Após o ArgoCD estar em pé, o operador consegue encerrar o túnel e deletar a sessão Bastion seguindo o bloco de Teardown, ficando com o ambiente limpo.
- Nenhum segredo é exposto em nenhum bloco do runbook (sem `*.tfvars`, sem OCIDs literais — só env vars e outputs do terraform).
</success_criteria>

<output>
Após execução, criar `.planning/quick/260423-wcq-criar-runbook-em-markdown-com-script-com/260423-wcq-SUMMARY.md` descrevendo:
- Caminho do arquivo criado e total de linhas
- Lista de seções H2 entregues
- Confirmação de que `terraform/README.md` não foi modificado
- Nota de follow-up sugerindo (opcional, não neste quick) adicionar um link do `terraform/README.md` seção "Etapa intermediária" para este runbook
</output>
