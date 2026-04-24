# Runbook: Primeiro `terraform apply` via OCI Cloud Shell Private Network

## Contexto

Este runbook é o **caminho alternativo** ao
[bastion-first-apply.md](./bastion-first-apply.md) para concluir o bootstrap do
ArgoCD quando o túnel SSH via OCI Bastion Service sofre com `TLS handshake timeout`
no port-forwarding gerenciado — sintoma já reproduzido nesta tenancy onde o
ClientHello fragmentado do `kubectl`/Terraform é descartado pelo plano de dados
do Bastion.

Este runbook resolve o mesmo problema — fazer o `terraform apply` final do
bootstrap do ArgoCD alcançar o API endpoint privado do OKE — trocando o túnel
SSH pelo anexo nativo do Cloud Shell na VCN. O Cloud Shell Private Network
conecta o shell gerenciado do OCI Console diretamente na subnet privada via
uma VNIC atrelada a um NSG do cliente, sem intermediários TCP.

O mesmo padrão de duas fases do bastion-first-apply continua valendo aqui. O
primeiro `terraform apply` em `terraform/infra/` falha em
`module.oci_argocd_bootstrap.helm_release.argocd` com
`Kubernetes cluster unreachable: invalid configuration: no configuration has been provided`.
Esse erro não é bug: os providers Helm/Kubernetes/Kubectl usam
`local.kubeconfig_exists = fileexists(pathexpand("~/.kube/config-assessforge"))`
em [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf), e no
primeiro plan/apply o kubeconfig ainda não existe. Neste runbook o segundo
apply roda **dentro do Cloud Shell**, onde o kubeconfig aponta para o IP
privado diretamente — sem precisar reescrever para `127.0.0.1`.

> **Nota:** manter o `bastion-first-apply.md` continua sendo útil em tenancies
> onde o TLS não é afetado. Nada aqui deprecia aquele caminho.

## Pré-requisitos

- O primeiro `terraform apply` em `terraform/infra/` já foi executado ao menos
  uma vez, criando cluster OKE, node pool, vault, e agora também o NSG
  `assessforge-nsg-cloud-shell` mais a ingress rule correspondente no NSG
  `assessforge-nsg-api-endpoint` (ambos criados por este quick-plan).
- Acesso ao OCI Console com o mesmo usuário que roda o `terraform apply` (ou
  outro usuário com a mesma role no compartment).
- `~/.oci/config` configurado com perfil `DEFAULT` na estação do operador
  (necessário apenas para o `terraform output` inicial do Passo 1).
- `terraform` ≥ 1.5 no `PATH` da estação do operador.
- `kubectl` no `PATH` **dentro do Cloud Shell** (já vem pré-instalado).

## Passo 1 — Obter o OCID do NSG do Cloud Shell

```bash
# A partir de terraform/infra/ — o NSG dedicado ao Cloud Shell foi criado pela Fase 1.
cd terraform/infra
export CLOUD_SHELL_NSG_ID=$(terraform output -raw cloud_shell_nsg_id)
echo "NSG do Cloud Shell: $CLOUD_SHELL_NSG_ID"
```

O output esperado é uma string `ocid1.networksecuritygroup.oc1.sa-saopaulo-1.aaaa...`.
Copia esse valor para o clipboard — ele será colado no formulário do Cloud Shell
no Passo 3.

## Passo 2 — Abrir o OCI Cloud Shell

No OCI Console, abrir o Cloud Shell pelo ícone `>_` no canto superior direito
(ou via menu `Developer Services → Cloud Shell`). Aguardar o terminal inicializar
(~20-30s na primeira vez). O Cloud Shell já está autenticado como o usuário da
console — não precisa rodar `oci session authenticate` nem copiar `~/.oci/config`.

## Passo 3 — Anexar Private Network Connection

1. No topo do Cloud Shell, abrir o dropdown **Cloud Shell Network** (ou
   **Ephemeral Workspaces → Network**, dependendo da versão da UI).
2. Escolher **Create Private Network Connection** (ou **Switch to Private
   Network**).
3. Preencher o formulário:
   - **VCN**: `assessforge-vcn` (no compartment do projeto).
   - **Subnet**: `assessforge-subnet-private` (a subnet onde o API endpoint
     responde em `10.0.2.x:6443`).
   - **Network Security Group(s)**: colar o OCID do `$CLOUD_SHELL_NSG_ID` do
     Passo 1.
4. Clicar **Create**. A atualização leva ~30s; o Cloud Shell reinicia
   automaticamente no modo privado.

> **Nota:** enquanto a Private Network estiver ativa, o Cloud Shell perde
> acesso à internet pública — `curl github.com` e `helm repo update` falham.
> Isso importa para o Passo 7 (ver o item de Troubleshooting sobre download
> de chart). Para este runbook, o `terraform apply` se comunica com dois
> destinos: (a) OCI Object Storage para o backend de estado, acessível via
> Service Gateway; (b) OKE API, acessível direto pela VCN. Ambos funcionam
> no modo privado.

## Passo 4 — Gerar kubeconfig dentro do Cloud Shell

```bash
# Dentro do Cloud Shell, depois que a Private Network ficou ACTIVE.
# $CLUSTER_ID pode ser obtido com `oci ce cluster list --compartment-id <...>` ou
# copiado do output `terraform output -raw cluster_id` rodado na estação do operador.
export CLUSTER_ID="<colar aqui o output terraform output -raw cluster_id>"

# O Cloud Shell tem OCI CLI pré-configurado com as credenciais da console — sem precisar de ~/.oci/config.
# --file ~/.kube/config sobrescreve o kubeconfig default do Cloud Shell; não afeta a estação do operador.
# --kube-endpoint PRIVATE_ENDPOINT é CRÍTICO — sem ele o CLI escolhe o endpoint público (desabilitado nesta cluster)
# e o kubeconfig aponta para um IP inutilizável.
oci ce cluster create-kubeconfig \
  --cluster-id "$CLUSTER_ID" \
  --file ~/.kube/config \
  --region sa-saopaulo-1 \
  --token-version 2.0.0 \
  --kube-endpoint PRIVATE_ENDPOINT \
  --overwrite
```

## Passo 5 — Validar acesso ao cluster

```bash
# Dentro do Cloud Shell, ainda com a Private Network ativa.
kubectl get nodes
# Esperado: 2 nodes em Ready. Se aparecer NotReady, tudo bem também — o
# helm_release.argocd tem wait=true e aguarda o cluster ficar saudável.
```

Se der `Unable to connect ... i/o timeout`, voltar ao Passo 3 e confirmar que a
Private Network está **ACTIVE** (o dropdown do Cloud Shell mostra
"Connected to: assessforge-vcn/assessforge-subnet-private"). Se estiver em outra
subnet ou sem o NSG correto, refazer o Passo 3.

## Passo 6 — Clonar repositório e preparar variáveis

```bash
# No Cloud Shell, clone o repo (via HTTPS ou SSH com deploy key — operador decide).
git clone https://github.com/<org>/infra-setup.git
cd infra-setup/terraform/infra

# Copie seu terraform.tfvars local para dentro do Cloud Shell usando o botão Upload
# no menu superior do Cloud Shell (Settings → Upload file). O arquivo vai para ~/.
# Mova para o diretório correto:
cp ~/terraform.tfvars ./terraform.tfvars

# Se o backend remoto exigir credenciais S3-compat (Object Storage), exporte-as agora.
# As chaves vêm do Customer Secret Key criado em OCI Console → Identity → Users → <user> → Customer Secret Keys.
export AWS_ACCESS_KEY_ID="<access key gerado no OCI Console>"
export AWS_SECRET_ACCESS_KEY="<secret key correspondente>"
```

## Passo 7 — Executar `terraform apply` completo

```bash
# Reinicializa providers dentro do Cloud Shell (filesystem diferente do da estação do operador).
# -upgrade força reavaliação do fileexists() agora que ~/.kube/config existe em disco.
terraform init -upgrade

# Apply completa o bootstrap: helm_release.argocd + argocd-bridge secret + bootstrap application.
# Nessa execução o fileexists() encontra ~/.kube/config e os providers Helm/Kubernetes/Kubectl se conectam
# direto no IP privado via VNIC do Cloud Shell — sem túnel, sem reescrita de host.
terraform apply
```

Esperado: apply termina sem `cluster unreachable`. Quando finalizar, o ArgoCD
está rodando no cluster e, a partir deste ponto, toda mudança dentro do cluster
flui pelo repositório `gitops-setup` — o Terraform não toca mais em recursos
Kubernetes (boundary documentada em [`CLAUDE.md`](../../CLAUDE.md)).

### Validacao pos-apply: credencial do repositorio GitOps

Apos `terraform apply` concluir, o ArgoCD tentara sincronizar o `bootstrap`
Application automaticamente (retry ~3 min). Se aparecer `ComparisonError`
com `authentication required: Repository not found`, verifique se o secret
de credencial foi criado pelo modulo `oci_argocd_bootstrap`:

```bash
kubectl get secret gitops-setup-repo -n argocd \
  -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}'
# Esperado: repository
```

Para forcar um resync imediato (opcional):

```bash
kubectl patch application bootstrap -n argocd --type=merge \
  -p '{"operation":{"sync":{}}}'
```

Apos o primeiro sync bem-sucedido, o ESO (instalado via AppSet a partir do
`gitops-setup`) passa a gerenciar essa PAT via OCI Vault — o secret criado
pelo Terraform permanece como seed idempotente.

## Passo 8 — Teardown da conexão Cloud Shell

- Reabrir o dropdown **Cloud Shell Network** e escolher **Switch to Public
  Network** (ou **Disconnect Private Network**).
- Alternativa mais simples: apenas fechar a aba do Cloud Shell — a conexão
  privada é descartada junto com o workspace efêmero.
- O NSG `assessforge-nsg-cloud-shell` permanece no estado Terraform e pode ser
  reutilizado no próximo bootstrap — não é necessário destruí-lo.

## Troubleshooting

### Cloud Shell não consegue alcançar 10.0.2.x:6443

**Sintoma:** `kubectl get nodes` (Passo 5) dá `i/o timeout` ou
`no route to host`.

**Causa provável:** a Private Network Connection não foi criada com o NSG
correto (ou foi criada em outra subnet).

**Correção:** no dropdown do Cloud Shell, verificar os NSGs anexados à sessão
atual — a lista precisa conter exatamente o OCID copiado no Passo 1. Se não
estiver, recriar a conexão seguindo o Passo 3. Confirmar também que a subnet
escolhida é `assessforge-subnet-private` (o API endpoint responde ali).

### `terraform apply` falha com `Kubernetes cluster unreachable`

**Sintoma:**
`Error: Kubernetes cluster unreachable: invalid configuration: no configuration has been provided`
mesmo com `kubectl get nodes` funcionando no Cloud Shell.

**Causa provável:** mesma causa do
[bastion-first-apply.md](./bastion-first-apply.md) — o `fileexists()` foi
avaliado num plan anterior, quando o kubeconfig ainda não existia, e os
providers Helm/Kubernetes/Kubectl mantiveram `config_path = null` em cache.

**Correção:** forçar reavaliação:

```bash
cd ~/infra-setup/terraform/infra
terraform init -upgrade
terraform apply
```

### Apply precisa de acesso à internet para baixar Helm chart

**Sintoma:** `terraform apply` falha com
`failed to download "argo-cd" (https://argoproj.github.io/argo-helm)`
ou timeout semelhante ao resolver repositórios Helm públicos.

**Causa:** com Cloud Shell em Private Network, a rota default vai para a VCN;
destinos públicos na internet (fora da Service Gateway) ficam inacessíveis.

**Correção (escolher uma, caso bata nesse sintoma):**

- **(a)** Desanexar temporariamente a Private Network depois que o kubeconfig
  já estiver OK em disco (Passos 2-5), rodar `terraform init -upgrade` no
  modo público para popular `.terraform/` com o chart baixado, e então
  reanexar a Private Network antes do `terraform apply` final. O chart
  permanece em cache local.
- **(b)** Hospedar o chart do ArgoCD num OCI registry (OCIR) acessível via
  Service Gateway e apontar o `helm_release` para o `oci://...` correspondente.

Registrar esta decisão como follow-up operacional do projeto — não prescrever
uma solução rígida aqui.

## Referências

- [`bastion-first-apply.md`](./bastion-first-apply.md) — caminho original por
  túnel SSH; ainda válido em tenancies onde o TLS handshake do OCI Bastion não
  sofre com fragmentação. Este runbook existe como alternativa justamente
  porque o Bastion bateu em TLS handshake timeout na tenancy do AssessForge.
- [`CLAUDE.md`](../../CLAUDE.md) — constraints de segurança do projeto (API
  endpoint privado, 100% OCI Always Free tier).
- [`terraform/infra/versions.tf`](../../terraform/infra/versions.tf) — padrão
  `fileexists(kubeconfig)` de inicialização em duas fases dos providers
  Helm/Kubernetes/Kubectl.
- [OCI Cloud Shell — Private Network access](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/cloudshellintro.htm#privatenetwork)
- [OCI Container Engine — `create-kubeconfig`](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengdownloadkubeconfigfile.htm)
