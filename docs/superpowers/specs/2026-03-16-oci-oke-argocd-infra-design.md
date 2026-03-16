# Design Spec: OCI OKE + ArgoCD Infrastructure (AssessForge)

**Date:** 2026-03-16
**Status:** Approved
**Project:** AssessForge — `infra-setup`

---

## 1. Overview

Projeto Terraform production-ready para provisionar um cluster Kubernetes (OKE) no Oracle Cloud Infrastructure dentro do **Always Free Tier**, com GitOps via ArgoCD, SSO via GitHub OAuth (Dex), políticas de segurança via Kyverno, segredos gerenciados via OCI Vault + External Secrets Operator, e acesso seguro via OCI Bastion Service.

### Princípios

- Zero credenciais hardcoded — tudo via variáveis sensitive ou Workload Identity
- Tudo declarativo — nenhum recurso criado manualmente
- Custo zero — 100% dentro do Oracle Always Free Tier
- Dois stages de apply — separação clara entre infra OCI e recursos Kubernetes

---

## 2. Estrutura de Diretórios

```
terraform/
├── infra/                          # Layer 1 — OCI resources
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── backend.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── oci-network/
│       ├── oci-oke/
│       ├── oci-iam/
│       ├── oci-vault/
│       └── oci-cloud-guard/
│
├── k8s/                            # Layer 2 — Kubernetes resources
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── providers.tf
│   ├── backend.tf
│   ├── terraform.tfvars.example
│   └── modules/
│       ├── ingress-nginx/
│       ├── external-secrets/
│       ├── argocd/
│       ├── kyverno/
│       └── network-policies/
│
└── README.md
```

---

## 3. Providers e Versões

```hcl
# infra/providers.tf
terraform {
  required_providers {
    oci = { source = "oracle/oci", version = "~> 6.0" }
  }
}

provider "oci" {
  # Autentica via ~/.oci/config perfil DEFAULT
  # Não hardcodar user_ocid, fingerprint ou private_key_path aqui.
  # Exportar: export TF_VAR_region=sa-saopaulo-1
  # O profile DEFAULT do OCI CLI é usado automaticamente.
  region = var.region
}
```

```hcl
# k8s/providers.tf
terraform {
  required_providers {
    helm       = { source = "hashicorp/helm",       version = "~> 2.13" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    kubectl    = { source = "gavinbunney/kubectl",  version = "~> 1.14" }
    random     = { source = "hashicorp/random",     version = "~> 3.6" }
  }
}

provider "helm" {
  kubernetes {
    config_path = "~/.kube/config-assessforge"
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config-assessforge"
}

provider "kubectl" {
  config_path = "~/.kube/config-assessforge"
}
```

**Nota:** O k8s/ layer assume que `~/.kube/config-assessforge` está configurado para apontar para `127.0.0.1:<porta_local>` (via tunnel Bastion). Ver Seção 11.

---

## 4. Backend (State Remoto)

**Bucket OCI Object Storage:** `assessforge-tfstate` (criado manualmente antes do primeiro apply — documentado no README).

| Layer  | State Key                   |
|--------|-----------------------------|
| infra/ | `infra/terraform.tfstate`   |
| k8s/   | `k8s/terraform.tfstate`     |

Autenticação via OCI CLI config padrão. Sem PAR (Pre-Authentication Request).

```hcl
# infra/backend.tf e k8s/backend.tf (estrutura idêntica, key diferente)
terraform {
  backend "s3" {
    bucket                      = "assessforge-tfstate"
    key                         = "infra/terraform.tfstate"  # ou k8s/
    region                      = "sa-saopaulo-1"
    endpoint                    = "https://<namespace>.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}
```

O namespace do Object Storage é obtido via `oci os ns get`. Documentado no README.

---

## 5. Handoff de Outputs entre Layers

Como `infra/` e `k8s/` têm states separados, o k8s/ usa `data "terraform_remote_state" "infra"` para ler outputs do infra/:

```hcl
# k8s/main.tf
data "terraform_remote_state" "infra" {
  backend = "s3"
  config = {
    bucket     = "assessforge-tfstate"
    key        = "infra/terraform.tfstate"
    region     = var.region
    endpoint   = var.oci_object_storage_endpoint
    # demais configs do backend
  }
}
# Uso: data.terraform_remote_state.infra.outputs.vault_ocid
```

Isso elimina cópia manual de outputs entre layers.

---

## 6. Ordem de Execução

```
# Stage 1 — infra/ apply
(oci-network + oci-iam + oci-cloud-guard) em paralelo
  └── oci-oke          (depends_on: oci-network + oci-iam)
        └── oci-vault  (depends_on: oci-oke — precisa do compartment e cluster OCID)

# Stage 2 — k8s/ apply (via Bastion tunnel — ver Seção 11)
ingress-nginx
  └── external-secrets (depends_on: ingress-nginx)
        └── argocd     (depends_on: external-secrets)
              ├── kyverno          (depends_on: argocd)
              └── network-policies (depends_on: argocd)
```

**Nota sobre oci-iam:** O Dynamic Group e as policies IAM não dependem do OKE existir — podem ser criados em paralelo com `oci-network`. O OKE node pool usa as policies no momento em que os nodes fazem bootstrap, não durante a criação do cluster.

---

## 7. Módulos — Layer infra/

### 7.1 oci-network

- VCN CIDR: `10.0.0.0/16` com DNS label `assessforge`
- **Subnet pública** `10.0.1.0/24` — Load Balancer e Bastion
- **Subnet privada** `10.0.2.0/24` — Worker nodes
- Internet Gateway → route table pública
- NAT Gateway + Service Gateway → route table privada
- **NSG Load Balancer:** ingress TCP 80/443 de `0.0.0.0/0` (Cloudflare proxy)
- **NSG Workers:**
  - ingress do NSG LB (para tráfego do ingress controller)
  - inter-node (pod CIDR `10.244.0.0/16`)
  - ingress TCP 6443 da subnet pública `10.0.1.0/24` (para Bastion tunnel ao OKE API)
- **NSG Bastion:** ingress TCP 22 de `var.bastion_allowed_cidr` (IP do operador)
- VCN Flow Logs via `oci_logging_log_group` + `oci_logging_log`
- Tags: `freeform_tags = { project = "argocd-assessforge" }`

### 7.2 oci-iam

- Dynamic Group `assessforge-workload-identity`: matching rule por `compartment_ocid`
- **Policy ESO:** permite `read secret-family`, `use vaults`, `use keys` no compartment
- **Policy OKE:** permite gerenciar LBs e network resources na VCN
- Apenas Workload Identity + Instance Principals — sem API Keys estáticas
- Criado em paralelo com `oci-network` (sem depends_on entre eles)

### 7.3 oci-oke

- Tipo: `BASIC_CLUSTER` (não Enhanced — evita custo ~$72/mês)
- API endpoint: **privado** (`is_public_ip_enabled = false`)
- Kubernetes version: data source para versão estável mais recente disponível no OKE
- Kubernetes audit logs via OCI Logging
- **Node pool:**
  - Shape: `VM.Standard.A1.Flex`
  - 2 nodes fixos (sem autoscaling)
  - 2 OCPU + 12 GB RAM por node
  - Boot volume: **50 GB por node** (2 × 50 = 100 GB, deixa 100 GB de headroom no free tier)
  - Image: Oracle Linux mais recente compatível com A1
  - Subnet: privada
- Load Balancer: subnet pública
- `null_resource` + `local_exec`: gera kubeconfig em `~/.kube/config-assessforge` após cluster ready
- `oci_bastion_bastion`: subnet pública, sessões criadas manualmente pelo operador
- `depends_on`: [module.oci-network, module.oci-iam]
- `lifecycle { prevent_destroy = true }` no cluster OKE

**Nota sobre boot volumes:** O Oracle Always Free Tier inclui 200 GB de block storage total. Com 2 × 50 GB = 100 GB para boot volumes, ficam 100 GB disponíveis para outros usos. Reduzir de 100 GB para 50 GB por node é seguro para cargas leves (ArgoCD + Kyverno + ingress-nginx).

### 7.4 oci-vault

- Vault tipo `DEFAULT`, nome `argocd-vault`
- Master Encryption Key: AES-256
- Secrets (sensitive):
  - `github-oauth-client-id`
  - `github-oauth-client-secret`
- Os valores chegam via `var.github_oauth_client_id` e `var.github_oauth_client_secret` (sensitive=true)
- **Tradeoff documentado:** Os valores passam pelo Terraform state (encrypted em repouso no Object Storage). Alternativa: popular o Vault out-of-band via OCI CLI e remover as sensitive vars do infra/. Para este projeto, aceitar o tradeoff e garantir que o bucket de state tem Object Storage Server-Side Encryption habilitado.
- `depends_on`: [module.oci-oke]
- `lifecycle { prevent_destroy = true }` no Vault e na Master Key

### 7.5 oci-cloud-guard

- Habilitado no tenancy (`oci_cloud_guard_cloud_guard_configuration`)
- Detector Recipe clonado do Oracle Managed (sem detectores pagos)
- Responder Recipe com notificação via OCI Events
- Target: compartment do projeto
- Criado em paralelo com `oci-network` e `oci-iam` (sem depends_on entre eles)

---

## 8. Módulos — Layer k8s/

### 8.1 ingress-nginx

- Helm release: `ingress-nginx/ingress-nginx`, namespace `ingress-nginx`
- `service.type: LoadBalancer`
- Annotations OCI para LB flexível com bandwidth mínimo de 10 Mbps (free tier):
  ```yaml
  service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
  service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
  service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
  ```
- O IP público do LB é o mesmo exposto via Cloudflare → ArgoCD
- `depends_on`: nenhum (primeiro a ser criado)

### 8.2 external-secrets

- Helm release: `external-secrets/external-secrets`, namespace `external-secrets`
- `ClusterSecretStore`:
  ```yaml
  provider:
    oracle:
      vault: <data.terraform_remote_state.infra.outputs.vault_ocid>
      region: <var.region>
      auth:
        workload:
          serviceAccountRef:
            name: external-secrets
            namespace: external-secrets
  ```
- `ExternalSecret` no namespace `argocd`:
  - Target secret: **`argocd-dex-github-secret`** (secret novo, não o `argocd-secret` que o ArgoCD gerencia internamente)
  - `dex.github.clientID` ← `github-oauth-client-id`
  - `dex.github.clientSecret` ← `github-oauth-client-secret`
  - `creationPolicy: Owner` (ESO cria e possui — sem conflito pois é um secret dedicado)
  - `refreshInterval: 1h`
- `depends_on` no Helm release antes de criar CRDs (aguarda ESO estar ready)
- `depends_on`: [module.ingress-nginx]

**Por que `argocd-dex-github-secret` e não `argocd-secret`:** O ArgoCD cria e gerencia `argocd-secret` internamente (admin password hash, server signing key). Usar ESO com `Owner` ou `Merge` nesse secret causaria conflito. A solução correta é um secret dedicado `argocd-dex-github-secret`, referenciado no Dex config via `$argocd-dex-github-secret:dex.github.clientID` (sintaxe suportada pelo ArgoCD para referenciar qualquer secret no namespace `argocd`).

### 8.3 argocd

- Namespace `argocd` com label `pod-security.kubernetes.io/enforce=restricted`
- Helm release: `argoproj/argo-cd`, versão estável mais recente
- **Security contexts em todos os deployments** (server, repo-server, application-controller, dex, redis, applicationset-controller):
  ```yaml
  runAsNonRoot: true
  runAsUser: 999
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  ```
- Redis: senha via `random_password` (length=32, special=false)
- **Resource limits:**
  ```yaml
  controller:  { requests: { cpu: 250m, memory: 512Mi }, limits: { cpu: "1",   memory: 2Gi   } }
  server:      { requests: { cpu: 100m, memory: 128Mi }, limits: { cpu: 500m,  memory: 256Mi } }
  repoServer:  { requests: { cpu: 200m, memory: 256Mi }, limits: { cpu: "1",   memory: 1Gi   } }
  redis:       { requests: { cpu: 100m, memory: 128Mi }, limits: { cpu: 250m,  memory: 256Mi } }
  dex:         { requests: { cpu: 50m,  memory: 64Mi  }, limits: { cpu: 100m,  memory: 128Mi } }
  ```
- **`Ingress` resource** no namespace `argocd`:
  - `ingressClassName: nginx`
  - Host: `var.argocd_hostname`
  - Backend: `argocd-server:80`
  - Annotation `nginx.ingress.kubernetes.io/ssl-redirect: "false"` (TLS feito pelo Cloudflare)
- **`argocd-cm`** (kubernetes_config_map):
  - `url: https://<var.argocd_hostname>`
  - `admin.enabled: "false"`
  - `users.anonymous.enabled: "false"`
  - `exec.enabled: "false"`
  - Dex config com GitHub connector, restrito à org `<var.github_org>`:
    - `clientID: $argocd-dex-github-secret:dex.github.clientID`
    - `clientSecret: $argocd-dex-github-secret:dex.github.clientSecret`
- **`argocd-rbac-cm`** (kubernetes_config_map):
  - `policy.default: role:''`
  - RBAC por GitHub teams: `<org>:<team-admin>` → `role:admin`, `<org>:<team-readonly>` → `role:readonly`
- **`argocd-cmd-params-cm`** (kubernetes_config_map):
  - `server.login.attempts.max: "5"`, reset: `"300"`
  - Logs em JSON para todos os componentes
- `depends_on`: [module.external-secrets]

### 8.4 kyverno

- Helm release: `kyverno/kyverno`, namespace `kyverno`, `replicaCount: 1`
- **5 ClusterPolicies** (`validationFailureAction: Enforce`):
  1. `disallow-root-containers`
  2. `disallow-privilege-escalation`
  3. `require-readonly-rootfs`
  4. `disallow-latest-tag`
  5. `require-resource-limits`
- **Exceções** (namespace exclusions) em todas as policies: `kube-system`, `kyverno`, `longhorn-system`, `external-secrets`, `argocd`, `ingress-nginx`
- `depends_on`: [module.argocd]

### 8.5 network-policies

- Recursos via `kubectl_manifest`
- **deny-all-default:** baseline deny-all no namespace `argocd`
- **argocd-redis-lockdown:** ingress porta 6379 apenas dos pods com label:
  - `app.kubernetes.io/component: server`
  - `app.kubernetes.io/component: application-controller`
  - `app.kubernetes.io/component: repo-server`
- **argocd-server-ingress:** ingress portas 8080/8083 apenas do namespace `ingress-nginx` (usando `namespaceSelector: matchLabels: kubernetes.io/metadata.name: ingress-nginx`) no pod com `component: server` — tráfego externo chega exclusivamente via ingress-nginx, não diretamente de outros pods
- **argocd-internal-only:** ingress apenas de dentro do namespace `argocd` para os demais pods (repo-server, application-controller, dex, applicationset-controller) — usando `podSelector` explícito por componente, não exclusão
- `depends_on`: [module.argocd]

---

## 9. Variáveis

### infra/variables.tf

| Variável | Descrição | Sensitive |
|----------|-----------|-----------|
| `tenancy_ocid` | OCID do tenancy OCI | não |
| `compartment_ocid` | OCID do compartment | não |
| `region` | Região OCI (ex: `sa-saopaulo-1`) | não |
| `cluster_name` | Nome do cluster OKE | não |
| `bastion_allowed_cidr` | CIDR do IP do operador para SSH ao Bastion (ex: `1.2.3.4/32`) | não |
| `github_oauth_client_id` | Client ID do GitHub OAuth App | **sim** |
| `github_oauth_client_secret` | Client Secret do GitHub OAuth App | **sim** |

### k8s/variables.tf

| Variável | Descrição | Sensitive |
|----------|-----------|-----------|
| `region` | Região OCI | não |
| `oci_object_storage_endpoint` | Endpoint do Object Storage (para remote state) | não |
| `argocd_hostname` | Hostname do ArgoCD (ex: `argocd.assessforge.com`) | não |
| `github_org` | Nome da org no GitHub | não |
| `github_team_admin` | Slug do team admin | não |
| `github_team_readonly` | Slug do team readonly | não |

---

## 10. Outputs

### infra/outputs.tf

| Output | Valor |
|--------|-------|
| `cluster_id` | OCID do cluster OKE |
| `vault_ocid` | OCID do Vault |
| `bastion_ocid` | OCID do Bastion |
| `kubeconfig_command` | Comando OCI CLI para gerar kubeconfig |

**Nota:** O IP do Load Balancer não é um output do `infra/` — o LB é criado pelo ingress-nginx no Stage 2. Ver `k8s/outputs.tf`.

### k8s/outputs.tf

| Output | Valor |
|--------|-------|
| `argocd_namespace` | Namespace do ArgoCD |
| `ingress_lb_ip` | IP público do LB do ingress-nginx |

---

## 11. Acesso ao Cluster via Bastion (Pré-requisito obrigatório do Stage 2)

Antes de executar `terraform apply` no k8s/, o operador DEVE:

**1. Descobrir o IP privado do OKE API endpoint:**
```bash
oci ce cluster get --cluster-id <cluster_id> \
  --query 'data.endpoints."private-endpoint"' --raw-output
# Retorna algo como: 10.0.2.5:6443
```

**2. Criar sessão Bastion de port-forwarding:**
```bash
oci bastion session create-port-forwarding \
  --bastion-id <bastion_ocid> \
  --display-name tunnel-oke \
  --target-private-ip <ip_privado_oke> \
  --target-port 6443 \
  --session-ttl 10800
# Aguardar status ACTIVE (~30s)
```

**3. Estabelecer tunnel SSH em background:**
```bash
ssh -N -L 6443:<ip_privado_oke>:6443 \
  -p 22 \
  -i ~/.ssh/id_rsa \
  <session_ocid>@host.bastion.<region>.oci.oraclecloud.com &
```

**4. Gerar e ajustar kubeconfig:**
```bash
oci ce cluster create-kubeconfig \
  --cluster-id <cluster_id> \
  --file ~/.kube/config-assessforge \
  --auth api_key

# Substituir o endpoint privado por 127.0.0.1
sed -i 's|https://10\.0\.2\.[0-9]*:6443|https://127.0.0.1:6443|g' \
  ~/.kube/config-assessforge
```

**5. Verificar acesso:**
```bash
KUBECONFIG=~/.kube/config-assessforge kubectl get nodes
```

**6. Agora executar o Stage 2:**
```bash
cd terraform/k8s && terraform apply
```

---

## 12. TLS / DNS

- TLS gerenciado pelo **Cloudflare** (proxy reverso)
- OCI Load Balancer (criado pelo ingress-nginx) recebe tráfego HTTP de Cloudflare
- Após o k8s/ apply, obter o IP do LB:
  ```bash
  KUBECONFIG=~/.kube/config-assessforge \
    kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  ```
- Cadastrar no Cloudflare: record `A` apontando `argocd.assessforge.com` → `<ip_lb>` com proxy habilitado (laranja)
- Sem cert-manager, sem OCI Certificates Service

---

## 13. terraform.tfvars.example

### infra/terraform.tfvars.example
```hcl
# OCID do tenancy — encontrado em OCI Console > Profile > Tenancy
tenancy_ocid = "ocid1.tenancy.oc1..example"

# OCID do compartment onde os recursos serão criados
# Pode ser o root compartment (mesmo valor do tenancy_ocid) ou um sub-compartment
compartment_ocid = "ocid1.compartment.oc1..example"

# Região OCI — ex: sa-saopaulo-1, us-ashburn-1, eu-frankfurt-1
region = "sa-saopaulo-1"

# Nome do cluster OKE
cluster_name = "assessforge-oke"

# Seu IP público em notação CIDR (ex: curl ifconfig.me para descobrir)
bastion_allowed_cidr = "0.0.0.0/0"  # Restringir para seu IP real em produção

# GitHub OAuth App — criado em: GitHub > Settings > Developer Settings > OAuth Apps
# NUNCA commitar estes valores
github_oauth_client_id     = "Ov23liXXXXXXXXXXXX"
github_oauth_client_secret = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

### k8s/terraform.tfvars.example
```hcl
# Região OCI (mesmo valor do infra/)
region = "sa-saopaulo-1"

# Endpoint do OCI Object Storage para leitura do remote state
# Formato: https://<namespace>.compat.objectstorage.<region>.oraclecloud.com
# namespace obtido via: oci os ns get
oci_object_storage_endpoint = "https://axxxxxxxxxxx.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"

# Hostname público do ArgoCD (deve ter record DNS apontando para o IP do LB)
argocd_hostname = "argocd.assessforge.com"

# Nome da organização no GitHub (ex: minha-empresa)
github_org = "assessforge"

# Slug do team GitHub com acesso admin ao ArgoCD
github_team_admin = "devops"

# Slug do team GitHub com acesso read-only ao ArgoCD
github_team_readonly = "developers"
```

---

## 14. Convenções

- `freeform_tags = { project = "argocd-assessforge" }` em todos os recursos OCI
- `app.kubernetes.io/managed-by = "terraform"` em labels de recursos Kubernetes
- Nenhum valor hardcoded — tudo via variáveis ou data sources
- `lifecycle { prevent_destroy = true }` no cluster OKE, Vault e Master Key
- `.gitignore` inclui: `*.tfvars`, `*.tfstate`, `*.tfstate.backup`, `.terraform/`, `.terraform.lock.hcl`, `~/.kube/config-assessforge`

---

## 15. Free Tier — Recursos Provisionados

| Recurso | Configuração | Free Tier? |
|---------|-------------|------------|
| OKE Cluster | BASIC_CLUSTER | ✅ |
| Worker Nodes | 2× VM.Standard.A1.Flex (2 OCPU, 12 GB) | ✅ (4 OCPU / 24 GB total) |
| Boot Volumes | 2× 50 GB = 100 GB | ✅ (200 GB disponível) |
| Load Balancer | 1× Flexible, 10 Mbps min/max | ✅ |
| OCI Vault | DEFAULT type | ✅ |
| OCI Bastion | 1 instância | ✅ |
| Object Storage | Bucket state (~KB) | ✅ |
| VCN Flow Logs | Log group + log | ✅ |
| Cloud Guard | Oracle Managed recipes | ✅ |
