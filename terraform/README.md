# AssessForge — Infrastructure Setup

Terraform production-ready para provisionar OKE (Oracle Kubernetes Engine) no Oracle Always Free Tier, com ArgoCD, GitHub SSO via Dex, Kyverno e External Secrets Operator.

## Pré-requisitos

- [ ] [Terraform ≥ 1.5](https://developer.hashicorp.com/terraform/install)
- [ ] [OCI CLI configurado](https://docs.oracle.com/en-us/iaas/Content/API/SDKDocs/cliinstall.htm) com `~/.oci/config` e perfil `DEFAULT`
- [ ] GitHub OAuth App criado em: GitHub > Settings > Developer Settings > OAuth Apps
  - Homepage URL: `https://argocd.assessforge.com`
  - Authorization callback URL: `https://argocd.assessforge.com/api/dex/callback`
- [ ] Domínio configurado no Cloudflare (ex: `assessforge.com`)
- [ ] SSH key pair (`~/.ssh/id_rsa`) para sessões Bastion

## Etapa 0 — Criar bucket de state

> Fazer apenas uma vez antes do primeiro `terraform init`.

```bash
# Descobrir namespace do Object Storage
NAMESPACE=$(oci os ns get --query 'data' --raw-output)
echo "Namespace: $NAMESPACE"

# Criar bucket
oci os bucket create \
  --compartment-id <compartment_ocid> \
  --name assessforge-tfstate \
  --versioning Enabled

# Substituir PLACEHOLDER nos arquivos versions.tf (backend está consolidado neles)
sed -i "s/PLACEHOLDER/$NAMESPACE/g" \
  infra/versions.tf \
  k8s/versions.tf
```

## Stage 1 — Infraestrutura OCI (infra/)

```bash
cd infra/

# Copiar e preencher variáveis
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com seus valores reais

# Inicializar com backend remoto
terraform init

# Revisar plano
terraform plan

# Aplicar
terraform apply
```

### Outputs do Stage 1

```bash
# OCID do cluster (necessário para o Stage 2)
terraform output cluster_id

# OCID do Bastion
terraform output bastion_ocid

# Comando para gerar kubeconfig
terraform output kubeconfig_command
```

## Etapa intermediária — Configurar acesso ao cluster

> Obrigatório antes do Stage 2.

```bash
# 1. Gerar kubeconfig inicial (apontará para IP privado)
$(terraform output -raw kubeconfig_command)

# 2. Descobrir IP privado do OKE API endpoint
OKE_IP=$(oci ce cluster get \
  --cluster-id $(terraform output -raw cluster_id) \
  --query 'data.endpoints."private-endpoint"' \
  --raw-output | cut -d: -f1)

# 3. Criar sessão Bastion
SESSION_OCID=$(oci bastion session create-port-forwarding \
  --bastion-id $(terraform output -raw bastion_ocid) \
  --display-name tunnel-oke \
  --target-private-ip $OKE_IP \
  --target-port 6443 \
  --session-ttl 10800 \
  --query 'data.id' --raw-output)

# Aguardar status ACTIVE
oci bastion session get --session-id $SESSION_OCID \
  --query 'data."lifecycle-state"' --raw-output

# 4. Abrir tunnel SSH em background
ssh -N -L 6443:$OKE_IP:6443 \
  -p 22 -i ~/.ssh/id_rsa \
  $SESSION_OCID@host.bastion.<region>.oci.oraclecloud.com &

# 5. Ajustar kubeconfig para usar localhost
sed -i "s|https://$OKE_IP:6443|https://127.0.0.1:6443|g" \
  ~/.kube/config-assessforge

# 6. Verificar acesso
KUBECONFIG=~/.kube/config-assessforge kubectl get nodes
```

## Stage 2 — Componentes Kubernetes (k8s/)

```bash
cd ../k8s/

# Copiar e preencher variáveis
cp terraform.tfvars.example terraform.tfvars
# Editar terraform.tfvars com seus valores reais
# Substituir NAMESPACE pelo valor de: oci os ns get

# Inicializar
terraform init

# Revisar plano
terraform plan

# Aplicar
terraform apply
```

## Etapa final — Configurar DNS no Cloudflare

```bash
# Obter IP do Load Balancer
KUBECONFIG=~/.kube/config-assessforge \
  kubectl get svc -n ingress-nginx ingress-nginx-controller \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

No Cloudflare:
1. DNS > Add record
2. Type: `A`
3. Name: `argocd` (ou o subdomínio configurado)
4. IPv4 address: `<ip_do_lb>`
5. Proxy status: **Proxied** (laranja)

O ArgoCD estará disponível em `https://argocd.assessforge.com` após a propagação DNS (geralmente < 1 minuto com Cloudflare).

## Login no ArgoCD

1. Acessar `https://argocd.assessforge.com`
2. Clicar em "Login via GitHub"
3. Autenticar com conta membro da organização GitHub configurada
4. Acesso admin concedido a todos os membros da organização GitHub configurada

## Destruição dos recursos

```bash
# ATENÇÃO: lifecycle { prevent_destroy = true } protege cluster OKE, Vault e Master Key
# Remover o lifecycle antes de destruir

# Stage 2 primeiro
cd k8s/ && terraform destroy

# Stage 1 depois
cd ../infra/ && terraform destroy
```
