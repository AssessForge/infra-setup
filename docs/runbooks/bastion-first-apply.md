# Runbook: Primeiro `terraform apply` com OCI Bastion tunnel

## Contexto

Depois que a Fase 1 (módulos `oci-network`, `oci-iam`, `oci-oke`, `oci-vault` e `oci-argocd-bootstrap`)
foi provisionada até o `oci-vault`, o próximo `terraform apply` tenta subir o Helm release do ArgoCD
via `module.oci_argocd_bootstrap.helm_release.argocd` e falha com o erro:

```
Error: Kubernetes cluster unreachable: invalid configuration: no configuration has been provided
```

Este erro **não é um bug**. É o comportamento esperado na primeira execução, provocado pela combinação
de três fatores de design documentados no projeto:

1. **O endpoint da API do OKE é privado por design.** Conforme a constraint `Networking` em
   [`CLAUDE.md`](../../CLAUDE.md) e a decisão arquitetural "API endpoint é privado — acesso via Bastion",
   o cluster é criado com `is_public_ip_enabled = false`. O kubeconfig gerado pelo `oci ce cluster
   create-kubeconfig` aponta para um IP da subnet privada (formato `10.0.2.x:6443`), inalcançável
   diretamente da estação do operador. A única via de acesso é o OCI Bastion Service.

2. **Os providers Helm/Kubernetes/Kubectl usam `fileexists()` para se auto-configurar em duas fases.**
   Como pode ser visto em [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf), cada
   provider lê `local.kubeconfig_exists = fileexists(pathexpand("~/.kube/config-assessforge"))`.
   No primeiríssimo plan/apply o kubeconfig ainda **não existe** em disco, então os três providers
   inicializam com `config_path = null` e não conseguem sequer tentar se conectar ao cluster — que
   está sendo criado neste mesmo apply.

3. **Por isso o apply precisa rodar duas vezes.** O fluxo correto é:
   (a) rodar `terraform apply` uma vez até o cluster + node pool + vault existirem (falha em
   `oci_argocd_bootstrap` é esperada); (b) gerar o kubeconfig em disco e subir o túnel Bastion; (c)
   rodar `terraform apply` de novo — agora `fileexists` retorna `true`, os providers reinicializam
   com `config_path` válido, o túnel expõe `127.0.0.1:6443`, e o Helm release do ArgoCD sobe.

Este runbook cobre a etapa (b) de ponta a ponta, incluindo o fallback para operadores que nunca
geraram uma chave SSH antes.

## Pré-requisitos

Antes de começar, confirme:

- Você está no diretório raiz do repositório `infra-setup`.
- A Fase 1 (`terraform apply` em `terraform/infra/`) já foi executada ao menos uma vez — o cluster OKE
  e o node pool **devem existir no OCI** mesmo que o apply tenha falhado em `oci_argocd_bootstrap`.
- `~/.oci/config` está configurado com o perfil `DEFAULT`.
- Você tem permissões OCI para criar sessões Bastion e ler o cluster.

### Chave SSH

O OCI Bastion Service autentica o túnel SSH pela **chave pública** registrada na sessão — a chave
privada correspondente assina o handshake no seu lado. Três cenários:

**Cenário A — Já tenho chave em `~/.ssh/id_rsa`** (padrão OpenSSH):

```bash
# Reutiliza a chave existente do shell/Git
export SSH_PRIVATE_KEY="$HOME/.ssh/id_rsa"
export SSH_PUBLIC_KEY="$HOME/.ssh/id_rsa.pub"
```

**Cenário B — Tenho chave em outro caminho** (ex.: chave dedicada a outra infra):

```bash
# Aponte as env vars para o par correto
export SSH_PRIVATE_KEY="$HOME/.ssh/assessforge_ed25519"
export SSH_PUBLIC_KEY="$HOME/.ssh/assessforge_ed25519.pub"
```

**Cenário C — Ainda não tenho chave SSH nenhuma** — gerar agora:

```bash
# Gerar par de chaves ed25519 dedicado para o Bastion do AssessForge
# -t ed25519: algoritmo moderno e rápido (preferível a RSA para Bastion)
# -N '': sem passphrase — OK para chave dedicada a tunneling não interativo
# -C "...": comentário identificador nos authorized_keys do Bastion
ssh-keygen -t ed25519 -f "$HOME/.ssh/assessforge_ed25519" \
  -N '' -C "assessforge-bastion-$(date +%Y%m%d)"

export SSH_PRIVATE_KEY="$HOME/.ssh/assessforge_ed25519"
export SSH_PUBLIC_KEY="$HOME/.ssh/assessforge_ed25519.pub"
```

Independente do cenário, valide que as duas variáveis apontam para arquivos existentes:

```bash
# Confirmar que as duas variáveis apontam para arquivos existentes
test -f "$SSH_PRIVATE_KEY" && test -f "$SSH_PUBLIC_KEY" \
  && echo "OK: chaves SSH prontas" \
  || echo "ERRO: defina SSH_PRIVATE_KEY e SSH_PUBLIC_KEY"
```

### Ferramentas

Confira o checklist (instalação fora do escopo deste runbook):

- [ ] OCI CLI configurado com perfil `DEFAULT` (`~/.oci/config`)
- [ ] `kubectl` no `PATH`
- [ ] `terraform` ≥ 1.5 no `PATH`
- [ ] `ssh`, `sed`, `awk`, `grep`, `pgrep`, `pkill` disponíveis (pacotes padrão em Linux/macOS)
- [ ] Primeiro `terraform apply` em `terraform/infra/` já concluído até o ponto em que o cluster OKE
      e o node pool existem (mesmo que o apply tenha falhado depois em `oci_argocd_bootstrap`)

## Passo 1 — Descobrir outputs da infraestrutura

Todo o runbook roda a partir de `terraform/infra/` e usa os outputs já existentes — nenhum output
novo precisa ser criado.

```bash
# Entra no diretório do layer de infra
cd terraform/infra

# Lê os outputs uma vez e exporta como env vars para os próximos passos
# cluster_id      -> OCID do cluster OKE (usado para descobrir o IP privado da API)
# bastion_ocid    -> OCID do OCI Bastion Service (usado para criar a sessão port-forwarding)
export CLUSTER_ID=$(terraform output -raw cluster_id)
export BASTION_OCID=$(terraform output -raw bastion_ocid)

echo "Cluster:  $CLUSTER_ID"
echo "Bastion:  $BASTION_OCID"
```

## Passo 2 — Gerar kubeconfig inicial

Este passo cria `~/.kube/config-assessforge` apontando **ainda para o IP privado** do cluster — o
arquivo será reescrito para `127.0.0.1` no Passo 7, depois que o túnel estiver ativo.

```bash
# Executa o output kubeconfig_command, que é literalmente o comando
# `oci ce cluster create-kubeconfig --file ~/.kube/config-assessforge ...`
eval "$(terraform output -raw kubeconfig_command)"

# Sanity check: o arquivo precisa existir em disco antes de qualquer outra coisa
test -f "$HOME/.kube/config-assessforge" \
  && echo "OK: kubeconfig criado em ~/.kube/config-assessforge" \
  || echo "ERRO: kubeconfig não foi criado — revisar permissões OCI CLI"
```

## Passo 3 — Descobrir o IP privado do OKE API endpoint

Precisamos do IP privado como **alvo** da sessão de port-forwarding do Bastion. O `oci ce cluster
get` retorna o endpoint no formato `10.0.2.x:6443`; extraímos só o IP com `cut`.

```bash
# $CLUSTER_ID deve estar exportado do Passo 1
# jmespath query: data.endpoints."private-endpoint"
# O campo vem no formato "10.0.2.x:6443" — só queremos o IP
export OKE_IP=$(oci ce cluster get \
  --cluster-id "$CLUSTER_ID" \
  --query 'data.endpoints."private-endpoint"' \
  --raw-output | cut -d: -f1)

echo "OKE API IP privado: $OKE_IP"
```

## Passo 4 — Criar sessão OCI Bastion port-forwarding

A sessão dura pelo `session-ttl` (máximo 3h = 10800s na configuração do projeto). O Bastion só aceita
conexões SSH que apresentem exatamente a **public key registrada na sessão** — por isso o
`--ssh-public-key-file` é obrigatório.

```bash
# $BASTION_OCID, $OKE_IP e $SSH_PUBLIC_KEY devem estar exportados
# --display-name: inclui timestamp para não colidir com sessões antigas
# --target-private-ip + --target-port: encaminha para a API do OKE na subnet privada
# --session-ttl 10800: 3h, suficiente para o re-apply + margem de depuração
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

## Passo 5 — Aguardar sessão ficar ACTIVE

Logo após o `create-port-forwarding`, a sessão fica em `CREATING` por alguns segundos antes de virar
`ACTIVE`. Abrir o túnel SSH contra uma sessão ainda em `CREATING` retorna `Connection refused` — por
isso fazemos polling antes.

```bash
# Polling: espera até 120s (24 x 5s) pela sessão ficar ACTIVE
# Em condições normais o ACTIVE aparece em ~15-30s
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

Se sair do loop sem imprimir `OK: sessão pronta`, vá para a seção de [Troubleshooting](#sessão-bastion-presa-em-creating).

## Passo 6 — Abrir túnel SSH em background

A região `sa-saopaulo-1` (constraint documentada em [`CLAUDE.md`](../../CLAUDE.md)) usa o host
`host.bastion.sa-saopaulo-1.oci.oraclecloud.com`. O usuário SSH é o **próprio OCID da sessão**. As
flags `-f -N` colocam o processo em background sem executar comando remoto — ideal para um
port-forward de longa duração.

```bash
# -f  : fork para background imediatamente após autenticar
# -N  : não executar comando remoto (apenas port-forward)
# -L 6443:$OKE_IP:6443 : forward localhost:6443 -> OKE_IP:6443 através do bastion
# -i  : private key correspondente à --ssh-public-key-file do Passo 4
# StrictHostKeyChecking=accept-new : aceita fingerprint do bastion na primeira vez (sem prompt)
# ServerAliveInterval=60 : evita que firewalls derrubem o túnel por ociosidade
ssh -f -N \
  -L "6443:$OKE_IP:6443" \
  -i "$SSH_PRIVATE_KEY" \
  -o StrictHostKeyChecking=accept-new \
  -o ServerAliveInterval=60 \
  "$SESSION_OCID@host.bastion.sa-saopaulo-1.oci.oraclecloud.com"

# Confirma que o processo de túnel está rodando
pgrep -af "ssh.*6443:$OKE_IP:6443" \
  || echo "ERRO: túnel não subiu — checar logs com 'ssh -v' (remover -f temporariamente)"
```

## Passo 7 — Reescrever kubeconfig para 127.0.0.1

O kubeconfig gerado pelo `oci ce cluster create-kubeconfig` tem `server: https://$OKE_IP:6443`.
Como o túnel expõe o API server **localmente** em `127.0.0.1:6443`, precisamos substituir o host.

```bash
# Substitui o host privado pelo localhost onde o túnel está escutando
# Usa '|' como separador do sed porque a URL contém '/'
sed -i "s|https://$OKE_IP:6443|https://127.0.0.1:6443|g" \
  "$HOME/.kube/config-assessforge"

# Confere a linha server: do kubeconfig
grep -E "server:" "$HOME/.kube/config-assessforge"
# esperado: server: https://127.0.0.1:6443
```

> **Nota:** o `sed -i` é idempotente — rodá-lo de novo num arquivo já reescrito é no-op.
> **Porém**, se você regerar o kubeconfig (repetir o Passo 2, ex.: após expirar a sessão), o arquivo
> volta a apontar para o IP privado e você precisa rodar este passo de novo.

## Passo 8 — Validar acesso ao cluster

```bash
# Se kubectl retornar a lista de nodes, o túnel está saudável e o auth OIDC do OCI funcionou
KUBECONFIG="$HOME/.kube/config-assessforge" kubectl get nodes

# Esperado: 2 nodes em Ready (ou NotReady se ainda inicializando — também é OK para prosseguir,
# o helm_release.argocd tem wait=true e vai aguardar o cluster ficar healthy)
```

Se der timeout ou `Unable to connect`, vá para a seção de
[Troubleshooting](#kubectl-get-nodes-dá-timeout).

## Passo 9 — Re-executar `terraform apply`

Com o kubeconfig funcional em disco, a expressão `fileexists(pathexpand("~/.kube/config-assessforge"))`
em [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf) retorna `true`, os providers
Helm/Kubernetes/Kubectl reavaliam `config_path` apontando para o arquivo, conectam no `127.0.0.1:6443`
via túnel, e `module.oci_argocd_bootstrap` consegue subir o Helm release.

```bash
# Garante que o diretório é o mesmo do Passo 1
cd terraform/infra

# Re-inicializar: força o Terraform a reavaliar o valor de fileexists() no plan seguinte
# Sem isso, o provider cache do run anterior pode manter config_path = null
terraform init -upgrade

# Apply — dessa vez deve proceder através de module.oci_argocd_bootstrap.helm_release.argocd
terraform apply
```

Quando o apply terminar sem erros, o ArgoCD já está no cluster. A partir deste ponto, toda mudança
dentro do cluster é feita via PR no repositório `gitops-setup` — o Terraform não toca mais em
recursos Kubernetes (boundary documentada em [`CLAUDE.md`](../../CLAUDE.md)).

## Teardown — Encerrar túnel e sessão

Depois que o ArgoCD está operacional, **o túnel não precisa ficar ativo**. Reabrir o túnel só é
necessário para operações manuais de break-glass (ex.: `kubectl debug`). Libere o slot da sessão
Bastion (a conta Always Free tem limite de sessões simultâneas).

```bash
# 1. Mata o processo SSH em background pelo padrão da linha -L
pkill -f "ssh.*6443:$OKE_IP:6443" \
  && echo "Túnel encerrado" \
  || echo "Nenhum túnel ativo (nada para matar)"

# 2. Deleta a sessão Bastion (libera o slot)
# --force evita o prompt interativo de confirmação
oci bastion session delete --session-id "$SESSION_OCID" --force

echo "Teardown concluído. Para operar o cluster no dia-a-dia, use o GitOps repo (gitops-setup)."
```

## Troubleshooting

### Sessão Bastion presa em CREATING

**Sintoma:** após 2 minutos no loop do Passo 5, o estado continua `CREATING` e nunca vira `ACTIVE`.

**Causa provável:** cota de sessões simultâneas do Bastion atingida (o Always Free limita
sessões concorrentes), ou erro transiente do serviço OCI.

**Correção:** liste as sessões existentes, delete as órfãs e tente criar de novo:

```bash
# Lista sessões ainda consumindo slot (ACTIVE ou presas em CREATING)
oci bastion session list --bastion-id "$BASTION_OCID" \
  --query 'data[?"lifecycle-state"==`ACTIVE` || "lifecycle-state"==`CREATING`].{id:id,state:"lifecycle-state",name:"display-name"}'

# Delete a sessão órfã específica (substituir pelo OCID retornado acima)
oci bastion session delete --session-id <OCID-da-sessao-antiga> --force
```

Depois refaça do Passo 4.

### Túnel SSH recusa conexão

**Sintoma:** `ssh: connect to host ... port 22: Connection refused` ou
`Permission denied (publickey)` ao executar o comando do Passo 6.

**Causas prováveis:**
- (a) sessão Bastion ainda não está `ACTIVE` (voltar ao Passo 5);
- (b) a chave pública enviada no `--ssh-public-key-file` do Passo 4 **não corresponde** à chave
  privada indicada com `-i` no Passo 6.

**Correção:** valide que `$SSH_PRIVATE_KEY` e `$SSH_PUBLIC_KEY` são o **mesmo par de chaves**. Os
fingerprints devem ser idênticos:

```bash
# Deriva a public key a partir da private key e imprime o fingerprint
ssh-keygen -yf "$SSH_PRIVATE_KEY" | awk '{print $2}'

# Imprime o fingerprint da public key que está no disco
awk '{print $2}' "$SSH_PUBLIC_KEY"

# As duas linhas devem imprimir exatamente a mesma string.
# Se forem diferentes, volte aos Pré-requisitos e alinhe as duas variáveis no mesmo par.
```

### `kubectl get nodes` dá timeout

**Sintoma:** `Unable to connect to the server: net/http: TLS handshake timeout` ou
`dial tcp 127.0.0.1:6443: connect: connection refused`.

**Causa provável:** o túnel subiu em algum momento, mas o processo SSH foi encerrado (suspensão
do laptop, mudança de rede, timeout por ociosidade).

**Correção:** confira o processo e, se não houver nenhum, reabra do Passo 5:

```bash
# Se nada for listado, o túnel caiu
pgrep -af "ssh.*6443" \
  || echo "Nenhum túnel ativo — reabrir a partir do Passo 5 (incluir novo create-port-forwarding se a sessão expirou)"
```

Se o processo estiver ativo mas o `kubectl` ainda falha, teste a porta local:

```bash
# Deve responder (mesmo que com TLS handshake) se o forward está saudável
nc -zv 127.0.0.1 6443
```

### `terraform apply` ainda diz "cluster unreachable" depois do túnel subir

**Sintoma:** mesmo com `kubectl get nodes` funcionando no shell, o
`terraform apply` retorna `Kubernetes cluster unreachable: invalid configuration: no configuration
has been provided`.

**Causa provável:** o Terraform avaliou `fileexists()` em um plan anterior (quando o kubeconfig
ainda não existia) e manteve o resultado em cache para os providers Helm/Kubernetes/Kubectl.

**Correção primária:** forçar reavaliação dos providers com o estado atual do filesystem:

```bash
cd terraform/infra

# Re-inicializa e re-avalia locais (incluindo o fileexists)
terraform init -upgrade

# Se ainda falhar, rodar um plan explícito para ver o que os providers estão vendo
terraform plan
# Observar na saída: os providers helm/kubernetes/kubectl devem listar config_path não-nulo
# apontando para ~/.kube/config-assessforge. Se ainda aparecer como null, o arquivo sumiu
# do disco — refazer Passo 2.

terraform apply
```

**Causa secundária — `$KUBECONFIG` exportado no shell:** o projeto hardcoda o caminho
`~/.kube/config-assessforge` em [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf)
via `local.kubeconfig_path = pathexpand("~/.kube/config-assessforge")`. Se você tiver outro
`$KUBECONFIG` exportado no shell atual, ele **não afeta** o Terraform — mas pode confundir o
`kubectl` usado para validar. Limpe a variável para evitar ambiguidade:

```bash
# Os providers do Terraform leem diretamente ~/.kube/config-assessforge (caminho hardcoded em versions.tf),
# então desexportar KUBECONFIG só ajuda nos comandos kubectl de validação.
unset KUBECONFIG
```

## Referências

- [`terraform/README.md`](../../terraform/README.md) — runbook operacional completo; a seção
  "Etapa intermediária" tem a versão resumida deste procedimento (sem fallback de chave SSH e
  sem o padrão `fileexists`/two-phase apply).
- [`CLAUDE.md`](../../CLAUDE.md) — constraints de segurança do projeto: API endpoint privado,
  Instance Principal, 100% OCI Always Free tier.
- [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf) — padrão
  `fileexists(kubeconfig)` de inicialização em duas fases dos providers Helm/Kubernetes/Kubectl.
- [OCI Bastion — Managing port-forwarding sessions](https://docs.oracle.com/en-us/iaas/Content/Bastion/Tasks/managingsessions.htm)
- [OCI Container Engine — Setting up cluster access](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm)
