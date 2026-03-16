# OCI OKE + ArgoCD Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provisionar um cluster OKE no Oracle Always Free Tier com ArgoCD, GitHub SSO via Dex, Kyverno, External Secrets Operator e NetworkPolicies, totalmente declarativo em Terraform.

**Architecture:** Dois root modules separados (`infra/` e `k8s/`), cada um com seu próprio state no OCI Object Storage. A camada `infra/` cria todos os recursos OCI (VCN, OKE, IAM, Vault, Bastion, Cloud Guard). A camada `k8s/` instala os componentes Kubernetes via Helm e kubectl, lendo outputs do `infra/` via `terraform_remote_state`. O acesso ao cluster privado é feito via OCI Bastion Service (tunnel SSH manual antes do Stage 2).

**Tech Stack:** Terraform ≥1.5, OCI Provider ~6.0, Helm Provider ~2.13, Kubernetes Provider ~2.30, kubectl Provider ~1.14, Random Provider ~3.6

**Spec:** `docs/superpowers/specs/2026-03-16-oci-oke-argocd-infra-design.md`

---

## Chunk 1: Scaffolding, .gitignore, backend e providers

### Task 1: Estrutura de diretórios e .gitignore

**Files:**
- Create: `terraform/.gitignore`
- Create: `terraform/infra/` (diretório)
- Create: `terraform/k8s/` (diretório)
- Create todos os subdiretórios de módulos

- [ ] **Step 1: Criar estrutura de diretórios**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
mkdir -p terraform/infra/modules/{oci-network,oci-iam,oci-oke,oci-vault,oci-cloud-guard}
mkdir -p terraform/k8s/modules/{ingress-nginx,external-secrets,argocd,kyverno,network-policies}
```

- [ ] **Step 2: Criar .gitignore**

Criar `terraform/.gitignore`:

```gitignore
# Terraform state e cache
*.tfstate
*.tfstate.backup
*.tfplan
.terraform/
.terraform.lock.hcl

# Valores sensíveis — NUNCA commitar
*.tfvars

# Kubeconfig gerado
**/config-assessforge

# Arquivos de sistema
.DS_Store
```

- [ ] **Step 3: Verificar estrutura**

```bash
find terraform/ -type d | sort
```

Esperado: todos os diretórios criados acima.

- [ ] **Step 4: Commit**

```bash
git add terraform/.gitignore
git commit -m "chore: scaffold terraform directory structure"
```

---

### Task 2: infra/ — providers, backend e variables

**Files:**
- Create: `terraform/infra/versions.tf` (providers + backend em um único bloco terraform{})
- Create: `terraform/infra/variables.tf`
- Create: `terraform/infra/terraform.tfvars.example`

**Nota importante:** Terraform permite múltiplos blocos `terraform {}` em arquivos diferentes, mas para evitar ambiguidade consolidar `required_version`, `required_providers` e `backend` em um único arquivo `versions.tf`.

- [ ] **Step 1: Criar `terraform/infra/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket                      = "assessforge-tfstate"
    key                         = "infra/terraform.tfstate"
    region                      = "sa-saopaulo-1"
    endpoint                    = "https://PLACEHOLDER.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}

provider "oci" {
  region = var.region
  # Autentica via ~/.oci/config perfil DEFAULT
  # Não hardcodar user_ocid, fingerprint ou private_key_path aqui
}
```

**Nota:** O campo `endpoint` contém um placeholder. O operador substitui `PLACEHOLDER` pelo namespace do Object Storage (`oci os ns get`) antes do primeiro `terraform init`. Documentar isso no README.

- [ ] **Step 3: Criar `terraform/infra/variables.tf`**

```hcl
variable "tenancy_ocid" {
  description = "OCID do tenancy OCI"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment onde os recursos serão criados"
  type        = string
}

variable "region" {
  description = "Região OCI (ex: sa-saopaulo-1)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster OKE"
  type        = string
  default     = "assessforge-oke"
}

variable "bastion_allowed_cidr" {
  description = "CIDR do IP do operador para acesso SSH ao Bastion (ex: 1.2.3.4/32)"
  type        = string
}

variable "github_oauth_client_id" {
  description = "Client ID do GitHub OAuth App"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "Client Secret do GitHub OAuth App"
  type        = string
  sensitive   = true
}
```

- [ ] **Step 4: Criar `terraform/infra/terraform.tfvars.example`**

```hcl
# OCID do tenancy — OCI Console > Profile > Tenancy
tenancy_ocid = "ocid1.tenancy.oc1..EXAMPLE"

# OCID do compartment (pode ser o root compartment = tenancy_ocid)
compartment_ocid = "ocid1.compartment.oc1..EXAMPLE"

# Região OCI
region = "sa-saopaulo-1"

# Nome do cluster OKE
cluster_name = "assessforge-oke"

# Seu IP público em CIDR — descobrir via: curl -s ifconfig.me
bastion_allowed_cidr = "1.2.3.4/32"

# GitHub OAuth App — GitHub > Settings > Developer Settings > OAuth Apps
# NUNCA commitar estes valores
github_oauth_client_id     = "Ov23liXXXXXXXXXXXX"
github_oauth_client_secret = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
```

- [ ] **Step 5: Criar placeholder `terraform/infra/main.tf` e `terraform/infra/outputs.tf`**

```hcl
# terraform/infra/main.tf
# Módulos serão adicionados nas próximas tasks
```

```hcl
# terraform/infra/outputs.tf
# Outputs serão adicionados após os módulos
```

- [ ] **Step 6: Validar sintaxe**

```bash
cd terraform/infra
terraform init -backend=false
terraform validate
```

Esperado: `Success! The configuration is valid.`

- [ ] **Step 7: Formatar**

```bash
terraform fmt -recursive
```

- [ ] **Step 8: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/versions.tf terraform/infra/variables.tf \
        terraform/infra/terraform.tfvars.example \
        terraform/infra/main.tf terraform/infra/outputs.tf
git commit -m "feat(infra): add versions, backend, variables scaffold"
```

---

### Task 3: k8s/ — providers, backend e variables

**Files:**
- Create: `terraform/k8s/versions.tf` (providers + backend em único bloco)
- Create: `terraform/k8s/variables.tf`
- Create: `terraform/k8s/terraform.tfvars.example`

- [ ] **Step 1: Criar `terraform/k8s/versions.tf`**

```hcl
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  backend "s3" {
    bucket                      = "assessforge-tfstate"
    key                         = "k8s/terraform.tfstate"
    region                      = "sa-saopaulo-1"
    endpoint                    = "https://PLACEHOLDER.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}

provider "helm" {
  kubernetes {
    config_path = pathexpand("~/.kube/config-assessforge")
  }
}

provider "kubernetes" {
  config_path = pathexpand("~/.kube/config-assessforge")
}

provider "kubectl" {
  config_path      = pathexpand("~/.kube/config-assessforge")
  load_config_file = true
}
```

- [ ] **Step 3: Criar `terraform/k8s/variables.tf`**

```hcl
variable "region" {
  description = "Região OCI"
  type        = string
}

variable "oci_object_storage_endpoint" {
  description = "Endpoint S3-compat do OCI Object Storage para leitura do remote state do infra/"
  type        = string
}

variable "argocd_hostname" {
  description = "Hostname público do ArgoCD (ex: argocd.assessforge.com)"
  type        = string
}

variable "github_org" {
  description = "Nome da organização no GitHub"
  type        = string
}

```

- [ ] **Step 4: Criar `terraform/k8s/terraform.tfvars.example`**

```hcl
# Região OCI (mesmo valor do infra/)
region = "sa-saopaulo-1"

# Endpoint Object Storage — substituir NAMESPACE pelo valor de: oci os ns get
oci_object_storage_endpoint = "https://NAMESPACE.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"

# Hostname público do ArgoCD
argocd_hostname = "argocd.assessforge.com"

# Organização no GitHub — todos os membros recebem acesso admin
github_org = "assessforge"
```

- [ ] **Step 5: Criar placeholders**

```hcl
# terraform/k8s/main.tf
# Módulos serão adicionados nas próximas tasks
```

```hcl
# terraform/k8s/outputs.tf
# Outputs serão adicionados após os módulos
```

- [ ] **Step 6: Validar**

```bash
cd terraform/k8s
terraform init -backend=false
terraform validate
```

Esperado: `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/versions.tf terraform/k8s/variables.tf \
        terraform/k8s/terraform.tfvars.example \
        terraform/k8s/main.tf terraform/k8s/outputs.tf
git commit -m "feat(k8s): add versions, backend, variables scaffold"
```

---

## Chunk 2: Módulo oci-network

### Task 4: oci-network — variáveis e outputs

**Files:**
- Create: `terraform/infra/modules/oci-network/variables.tf`
- Create: `terraform/infra/modules/oci-network/outputs.tf`

- [ ] **Step 1: Criar `terraform/infra/modules/oci-network/variables.tf`**

```hcl
variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR da VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR da subnet pública (LB e Bastion)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR da subnet privada (worker nodes)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "bastion_allowed_cidr" {
  description = "CIDR do IP do operador para acesso SSH ao Bastion"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Criar `terraform/infra/modules/oci-network/outputs.tf`**

```hcl
output "vcn_id" {
  description = "OCID da VCN"
  value       = oci_core_vcn.main.id
}

output "public_subnet_id" {
  description = "OCID da subnet pública"
  value       = oci_core_subnet.public.id
}

output "private_subnet_id" {
  description = "OCID da subnet privada"
  value       = oci_core_subnet.private.id
}

output "lb_nsg_id" {
  description = "OCID do NSG do Load Balancer"
  value       = oci_core_network_security_group.lb.id
}

output "workers_nsg_id" {
  description = "OCID do NSG dos worker nodes"
  value       = oci_core_network_security_group.workers.id
}
```

---

### Task 5: oci-network — main.tf (VCN, gateways, route tables)

**Files:**
- Create: `terraform/infra/modules/oci-network/main.tf`

- [ ] **Step 1: Criar VCN e gateways em `terraform/infra/modules/oci-network/main.tf`**

```hcl
# VCN principal
resource "oci_core_vcn" "main" {
  compartment_id = var.compartment_ocid
  cidr_blocks    = [var.vcn_cidr]
  display_name   = "assessforge-vcn"
  dns_label      = "assessforge"
  freeform_tags  = var.freeform_tags
}

# Internet Gateway (subnet pública)
resource "oci_core_internet_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-igw"
  enabled        = true
  freeform_tags  = var.freeform_tags
}

# NAT Gateway (subnet privada — saída para internet dos nodes)
resource "oci_core_nat_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-natgw"
  block_traffic  = false
  freeform_tags  = var.freeform_tags
}

# Service Gateway (acesso a serviços OCI sem sair pela internet)
resource "oci_core_service_gateway" "main" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-sgw"
  freeform_tags  = var.freeform_tags

  services {
    service_id = data.oci_core_services.all.services[0].id
  }
}

data "oci_core_services" "all" {
  filter {
    name   = "name"
    values = ["All .* Services In Oracle Services Network"]
    regex  = true
  }
}
```

- [ ] **Step 2: Adicionar route tables**

```hcl
# Route table — subnet pública
resource "oci_core_route_table" "public" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-rt-public"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.main.id
  }
}

# Route table — subnet privada
resource "oci_core_route_table" "private" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-rt-private"
  freeform_tags  = var.freeform_tags

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_nat_gateway.main.id
  }

  route_rules {
    destination       = data.oci_core_services.all.services[0].cidr_block
    destination_type  = "SERVICE_CIDR_BLOCK"
    network_entity_id = oci_core_service_gateway.main.id
  }
}
```

- [ ] **Step 3: Adicionar NSGs**

```hcl
# NSG — Load Balancer
resource "oci_core_network_security_group" "lb" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-lb"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "lb_ingress_http" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6" # TCP
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 80
      max = 80
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_ingress_https" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = "0.0.0.0/0"
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 443
      max = 443
    }
  }
}

resource "oci_core_network_security_group_security_rule" "lb_egress_all" {
  network_security_group_id = oci_core_network_security_group.lb.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# NSG — Worker nodes
resource "oci_core_network_security_group" "workers" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-workers"
  freeform_tags  = var.freeform_tags
}

# Ingress do LB para os workers (tráfego do ingress-nginx)
resource "oci_core_network_security_group_security_rule" "workers_ingress_from_lb" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = oci_core_network_security_group.lb.id
  source_type               = "NETWORK_SECURITY_GROUP"

  tcp_options {
    destination_port_range {
      min = 1
      max = 65535
    }
  }
}

# Inter-node comunicação entre nodes (subnet privada)
resource "oci_core_network_security_group_security_rule" "workers_ingress_inter_node" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = var.private_subnet_cidr
  source_type               = "CIDR_BLOCK"
}

# Pod-to-pod cross-node (overlay CIDR 10.244.0.0/16)
resource "oci_core_network_security_group_security_rule" "workers_ingress_pod_cidr" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "all"
  source                    = "10.244.0.0/16"
  source_type               = "CIDR_BLOCK"
}

# Bastion → OKE API endpoint (port 6443)
resource "oci_core_network_security_group_security_rule" "workers_ingress_bastion_api" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.public_subnet_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 6443
      max = 6443
    }
  }
}

# Egress workers → tudo
resource "oci_core_network_security_group_security_rule" "workers_egress_all" {
  network_security_group_id = oci_core_network_security_group.workers.id
  direction                 = "EGRESS"
  protocol                  = "all"
  destination               = "0.0.0.0/0"
  destination_type          = "CIDR_BLOCK"
}

# NSG — Bastion
resource "oci_core_network_security_group" "bastion" {
  compartment_id = var.compartment_ocid
  vcn_id         = oci_core_vcn.main.id
  display_name   = "assessforge-nsg-bastion"
  freeform_tags  = var.freeform_tags
}

resource "oci_core_network_security_group_security_rule" "bastion_ingress_ssh" {
  network_security_group_id = oci_core_network_security_group.bastion.id
  direction                 = "INGRESS"
  protocol                  = "6"
  source                    = var.bastion_allowed_cidr
  source_type               = "CIDR_BLOCK"

  tcp_options {
    destination_port_range {
      min = 22
      max = 22
    }
  }
}
```

- [ ] **Step 4: Adicionar subnets**

```hcl
# Subnet pública — LB e Bastion
resource "oci_core_subnet" "public" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.public_subnet_cidr
  display_name               = "assessforge-subnet-public"
  dns_label                  = "public"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public.id
  freeform_tags              = var.freeform_tags
}

# Subnet privada — worker nodes
resource "oci_core_subnet" "private" {
  compartment_id             = var.compartment_ocid
  vcn_id                     = oci_core_vcn.main.id
  cidr_block                 = var.private_subnet_cidr
  display_name               = "assessforge-subnet-private"
  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private.id
  freeform_tags              = var.freeform_tags
}
```

- [ ] **Step 5: Adicionar VCN Flow Logs**

```hcl
resource "oci_logging_log_group" "vcn_flow_logs" {
  compartment_id = var.compartment_ocid
  display_name   = "assessforge-vcn-flow-logs"
  freeform_tags  = var.freeform_tags
}

resource "oci_logging_log" "vcn_flow_log" {
  display_name = "assessforge-vcn-flow-log"
  log_group_id = oci_logging_log_group.vcn_flow_logs.id
  log_type     = "SERVICE"
  freeform_tags = var.freeform_tags

  configuration {
    source {
      category    = "all"
      resource    = oci_core_vcn.main.id
      service     = "flowlogs"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_ocid
  }

  is_enabled         = true
  retention_duration = 30
}
```

- [ ] **Step 6: Adicionar output do NSG do Bastion ao outputs.tf**

Abrir `terraform/infra/modules/oci-network/outputs.tf` e adicionar:

```hcl
output "bastion_nsg_id" {
  description = "OCID do NSG do Bastion"
  value       = oci_core_network_security_group.bastion.id
}
```

- [ ] **Step 7: Validar módulo isoladamente**

```bash
cd terraform/infra
terraform init -backend=false
terraform validate
terraform fmt -recursive
```

Esperado: `Success! The configuration is valid.`

- [ ] **Step 8: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/modules/oci-network/
git commit -m "feat(infra): add oci-network module (VCN, NSGs, gateways, flow logs)"
```

---

## Chunk 3: Módulos oci-iam e oci-cloud-guard

### Task 6: oci-iam

**Files:**
- Create: `terraform/infra/modules/oci-iam/variables.tf`
- Create: `terraform/infra/modules/oci-iam/main.tf`
- Create: `terraform/infra/modules/oci-iam/outputs.tf`

- [ ] **Step 1: Criar `terraform/infra/modules/oci-iam/variables.tf`**

```hcl
variable "tenancy_ocid" {
  description = "OCID do tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Criar `terraform/infra/modules/oci-iam/main.tf`**

```hcl
# Dynamic Group para Workload Identity do ESO
resource "oci_identity_dynamic_group" "workload_identity" {
  compartment_id = var.tenancy_ocid  # Dynamic groups vivem no tenancy root
  name           = "assessforge-workload-identity"
  description    = "Dynamic group para External Secrets Operator via Workload Identity"
  freeform_tags  = var.freeform_tags

  matching_rule = "ALL {instance.compartment.id = '${var.compartment_ocid}'}"
}

# Policy — ESO pode ler secrets do Vault
resource "oci_identity_policy" "eso_vault_access" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-eso-vault-policy"
  description    = "Permite ao ESO ler secrets do OCI Vault via Workload Identity"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow dynamic-group assessforge-workload-identity to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group assessforge-workload-identity to use vaults in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group assessforge-workload-identity to use keys in compartment id ${var.compartment_ocid}",
  ]

  depends_on = [oci_identity_dynamic_group.workload_identity]
}

# Policy — OKE pode gerenciar recursos de rede para criar Load Balancers
resource "oci_identity_policy" "oke_network_access" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-oke-network-policy"
  description    = "Permite ao OKE gerenciar LBs e recursos de rede na VCN"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow service oke to manage load-balancers in compartment id ${var.compartment_ocid}",
    "Allow service oke to use virtual-network-family in compartment id ${var.compartment_ocid}",
    "Allow service oke to manage cluster-family in compartment id ${var.compartment_ocid}",
  ]
}
```

- [ ] **Step 3: Criar `terraform/infra/modules/oci-iam/outputs.tf`**

```hcl
output "dynamic_group_name" {
  description = "Nome do Dynamic Group criado"
  value       = oci_identity_dynamic_group.workload_identity.name
}
```

- [ ] **Step 4: Validar**

```bash
cd terraform/infra && terraform validate
```

- [ ] **Step 5: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/modules/oci-iam/
git commit -m "feat(infra): add oci-iam module (dynamic group + policies)"
```

---

### Task 7: oci-cloud-guard

**Files:**
- Create: `terraform/infra/modules/oci-cloud-guard/variables.tf`
- Create: `terraform/infra/modules/oci-cloud-guard/main.tf`
- Create: `terraform/infra/modules/oci-cloud-guard/outputs.tf`

- [ ] **Step 1: Criar `terraform/infra/modules/oci-cloud-guard/variables.tf`**

```hcl
variable "tenancy_ocid" {
  description = "OCID do tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment target"
  type        = string
}

variable "region" {
  description = "Região OCI reporting do Cloud Guard"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Criar `terraform/infra/modules/oci-cloud-guard/main.tf`**

```hcl
# Habilitar Cloud Guard no tenancy
resource "oci_cloud_guard_cloud_guard_configuration" "main" {
  compartment_id   = var.tenancy_ocid
  reporting_region = var.region
  status           = "ENABLED"
}

# Data source: Oracle Managed Detector Recipe
data "oci_cloud_guard_detector_recipes" "oracle_managed" {
  compartment_id = var.tenancy_ocid

  filter {
    name   = "display_name"
    values = ["OCI Configuration Detector Recipe"]
    regex  = false
  }
}

# Detector Recipe clonado do Oracle Managed
resource "oci_cloud_guard_detector_recipe" "assessforge" {
  compartment_id            = var.compartment_ocid
  display_name              = "assessforge-detector-recipe"
  source_detector_recipe_id = data.oci_cloud_guard_detector_recipes.oracle_managed.detector_recipe_collection[0].items[0].id
  freeform_tags             = var.freeform_tags

  depends_on = [oci_cloud_guard_cloud_guard_configuration.main]
}

# Data source: Oracle Managed Responder Recipe
data "oci_cloud_guard_responder_recipes" "oracle_managed" {
  compartment_id = var.tenancy_ocid

  filter {
    name   = "display_name"
    values = ["OCI Notification Responder Recipe"]
    regex  = false
  }
}

# Responder Recipe clonado
resource "oci_cloud_guard_responder_recipe" "assessforge" {
  compartment_id             = var.compartment_ocid
  display_name               = "assessforge-responder-recipe"
  source_responder_recipe_id = data.oci_cloud_guard_responder_recipes.oracle_managed.responder_recipe_collection[0].items[0].id
  freeform_tags              = var.freeform_tags

  depends_on = [oci_cloud_guard_cloud_guard_configuration.main]
}

# Target apontando para o compartment do projeto
resource "oci_cloud_guard_target" "assessforge" {
  compartment_id       = var.compartment_ocid
  display_name         = "assessforge-cloud-guard-target"
  target_resource_id   = var.compartment_ocid
  target_resource_type = "COMPARTMENT"
  freeform_tags        = var.freeform_tags

  target_detector_recipes {
    detector_recipe_id = oci_cloud_guard_detector_recipe.assessforge.id
  }

  target_responder_recipes {
    responder_recipe_id = oci_cloud_guard_responder_recipe.assessforge.id
  }

  depends_on = [
    oci_cloud_guard_detector_recipe.assessforge,
    oci_cloud_guard_responder_recipe.assessforge,
  ]
}
```

- [ ] **Step 3: Criar `terraform/infra/modules/oci-cloud-guard/outputs.tf`**

```hcl
output "target_id" {
  description = "OCID do Cloud Guard target"
  value       = oci_cloud_guard_target.assessforge.id
}
```

- [ ] **Step 4: Validar e commit**

```bash
cd terraform/infra && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/modules/oci-cloud-guard/
git commit -m "feat(infra): add oci-cloud-guard module"
```

---

## Chunk 4: Módulos oci-oke e oci-vault

### Task 8: oci-oke

**Files:**
- Create: `terraform/infra/modules/oci-oke/variables.tf`
- Create: `terraform/infra/modules/oci-oke/main.tf`
- Create: `terraform/infra/modules/oci-oke/outputs.tf`

- [ ] **Step 1: Criar `terraform/infra/modules/oci-oke/variables.tf`**

```hcl
variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster OKE"
  type        = string
}

variable "vcn_id" {
  description = "OCID da VCN"
  type        = string
}

variable "public_subnet_id" {
  description = "OCID da subnet pública (LB)"
  type        = string
}

variable "private_subnet_id" {
  description = "OCID da subnet privada (workers)"
  type        = string
}

variable "workers_nsg_id" {
  description = "OCID do NSG dos worker nodes"
  type        = string
}

variable "lb_nsg_id" {
  description = "OCID do NSG do Load Balancer"
  type        = string
}

variable "bastion_nsg_id" {
  description = "OCID do NSG do Bastion"
  type        = string
}

variable "bastion_allowed_cidr" {
  description = "CIDR do IP do operador para o Bastion client_cidr_block_allow_list"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Criar `terraform/infra/modules/oci-oke/main.tf` — cluster**

```hcl
# Versão mais recente estável do Kubernetes no OKE
data "oci_containerengine_cluster_option" "k8s_versions" {
  cluster_option_id = "all"
}

locals {
  # Pega a última versão disponível (ex: v1.31.1)
  k8s_version = reverse(
    sort(
      [for v in data.oci_containerengine_cluster_option.k8s_versions.kubernetes_versions : v]
    )
  )[0]
}

# Log group para audit logs do OKE
resource "oci_logging_log_group" "oke_audit" {
  compartment_id = var.compartment_ocid
  display_name   = "assessforge-oke-audit-logs"
  freeform_tags  = var.freeform_tags
}

resource "oci_logging_log" "oke_audit" {
  display_name  = "assessforge-oke-audit"
  log_group_id  = oci_logging_log_group.oke_audit.id
  log_type      = "SERVICE"
  freeform_tags = var.freeform_tags

  configuration {
    source {
      category    = "kube-apiserver-audit"
      resource    = oci_containerengine_cluster.main.id
      service     = "oke"
      source_type = "OCISERVICE"
    }
    compartment_id = var.compartment_ocid
  }

  is_enabled         = true
  retention_duration = 30

  depends_on = [oci_containerengine_cluster.main]
}

# Cluster OKE BASIC
resource "oci_containerengine_cluster" "main" {
  compartment_id     = var.compartment_ocid
  kubernetes_version = local.k8s_version
  name               = var.cluster_name
  vcn_id             = var.vcn_id
  type               = "BASIC_CLUSTER"
  freeform_tags      = var.freeform_tags

  endpoint_config {
    is_public_ip_enabled = false
    nsg_ids              = [var.workers_nsg_id]
    subnet_id            = var.private_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.public_subnet_id]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }

    kubernetes_network_config {
      pods_cidr     = "10.244.0.0/16"
      services_cidr = "10.96.0.0/16"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}
```

- [ ] **Step 3: Adicionar node pool ao main.tf**

```hcl
# Image Oracle Linux mais recente para A1
data "oci_core_images" "oracle_linux_a1" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Oracle Linux"
  shape                    = "VM.Standard.A1.Flex"
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
  state                    = "AVAILABLE"
}

# Node pool — 2 nodes A1
resource "oci_containerengine_node_pool" "main" {
  cluster_id         = oci_containerengine_cluster.main.id
  compartment_id     = var.compartment_ocid
  kubernetes_version = local.k8s_version
  name               = "${var.cluster_name}-np"
  freeform_tags      = var.freeform_tags

  node_shape = "VM.Standard.A1.Flex"

  node_shape_config {
    memory_in_gbs = 12
    ocpus         = 2
  }

  node_source_details {
    image_id                = data.oci_core_images.oracle_linux_a1.images[0].id
    source_type             = "IMAGE"
    boot_volume_size_in_gbs = 50
  }

  node_config_details {
    size = 2

    placement_configs {
      availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
      subnet_id           = var.private_subnet_id
    }

    nsg_ids = [var.workers_nsg_id]
  }
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}
```

- [ ] **Step 4: Adicionar Bastion e geração de kubeconfig ao main.tf**

```hcl
# OCI Bastion Service — reside na subnet PÚBLICA para ser acessível da internet
resource "oci_bastion_bastion" "main" {
  bastion_type                 = "STANDARD"
  compartment_id               = var.compartment_ocid
  target_subnet_id             = var.public_subnet_id   # subnet pública — obrigatório
  name                         = "assessforge-bastion"
  client_cidr_block_allow_list = [var.bastion_allowed_cidr]  # IP do operador, não hardcoded
  freeform_tags                = var.freeform_tags
}

# Geração do kubeconfig após o cluster estar pronto
resource "null_resource" "kubeconfig" {
  triggers = {
    cluster_id = oci_containerengine_cluster.main.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      oci ce cluster create-kubeconfig \
        --cluster-id ${oci_containerengine_cluster.main.id} \
        --file ~/.kube/config-assessforge \
        --auth api_key \
        --overwrite
    EOT
  }

  depends_on = [oci_containerengine_node_pool.main]
}
```

- [ ] **Step 5: Criar `terraform/infra/modules/oci-oke/outputs.tf`**

```hcl
output "cluster_id" {
  description = "OCID do cluster OKE"
  value       = oci_containerengine_cluster.main.id
}

output "cluster_kubernetes_version" {
  description = "Versão do Kubernetes instalada"
  value       = oci_containerengine_cluster.main.kubernetes_version
}

output "bastion_ocid" {
  description = "OCID do Bastion"
  value       = oci_bastion_bastion.main.id
}

output "bastion_name" {
  description = "Nome do Bastion (o hostname de sessão segue o padrão: <session_ocid>@host.bastion.<region>.oci.oraclecloud.com)"
  value       = oci_bastion_bastion.main.name
}
```

- [ ] **Step 6: Validar e commit**

```bash
cd terraform/infra && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/modules/oci-oke/
git commit -m "feat(infra): add oci-oke module (BASIC cluster, A1 node pool, bastion)"
```

---

### Task 9: oci-vault

**Files:**
- Create: `terraform/infra/modules/oci-vault/variables.tf`
- Create: `terraform/infra/modules/oci-vault/main.tf`
- Create: `terraform/infra/modules/oci-vault/outputs.tf`

- [ ] **Step 1: Criar `terraform/infra/modules/oci-vault/variables.tf`**

```hcl
variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "github_oauth_client_id" {
  description = "Client ID do GitHub OAuth App"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "Client Secret do GitHub OAuth App"
  type        = string
  sensitive   = true
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Criar `terraform/infra/modules/oci-vault/main.tf`**

```hcl
# OCI Vault
resource "oci_kms_vault" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "argocd-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = var.freeform_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Master Encryption Key AES-256
resource "oci_kms_key" "master" {
  compartment_id      = var.compartment_ocid
  display_name        = "argocd-master-key"
  management_endpoint = oci_kms_vault.main.management_endpoint
  freeform_tags       = var.freeform_tags

  key_shape {
    algorithm = "AES"
    length    = 32  # 256 bits
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Secret — GitHub OAuth Client ID
resource "oci_vault_secret" "github_oauth_client_id" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "github-oauth-client-id"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.github_oauth_client_id)
    name         = "github-oauth-client-id"
    # stage é read-only no OCI provider >= 6.0 — não incluir
  }
}

# Secret — GitHub OAuth Client Secret
resource "oci_vault_secret" "github_oauth_client_secret" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "github-oauth-client-secret"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.github_oauth_client_secret)
    name         = "github-oauth-client-secret"
    # stage é read-only no OCI provider >= 6.0 — não incluir
  }
}
```

- [ ] **Step 3: Criar `terraform/infra/modules/oci-vault/outputs.tf`**

```hcl
output "vault_ocid" {
  description = "OCID do OCI Vault"
  value       = oci_kms_vault.main.id
}

output "vault_management_endpoint" {
  description = "Management endpoint do Vault"
  value       = oci_kms_vault.main.management_endpoint
}

output "master_key_ocid" {
  description = "OCID da Master Key"
  value       = oci_kms_key.master.id
}
```

- [ ] **Step 4: Validar e commit**

```bash
cd terraform/infra && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/modules/oci-vault/
git commit -m "feat(infra): add oci-vault module (vault, master key, github secrets)"
```

---

## Chunk 5: infra/ wiring (main.tf + outputs.tf)

### Task 10: infra/ main.tf — conectar todos os módulos

**Files:**
- Modify: `terraform/infra/main.tf`
- Modify: `terraform/infra/outputs.tf`

- [ ] **Step 1: Reescrever `terraform/infra/main.tf`**

```hcl
locals {
  freeform_tags = {
    project = "argocd-assessforge"
  }
}

# --- Módulos paralelos (sem dependências entre si) ---

module "oci_network" {
  source = "./modules/oci-network"

  compartment_ocid     = var.compartment_ocid
  bastion_allowed_cidr = var.bastion_allowed_cidr
  freeform_tags        = local.freeform_tags
}

module "oci_iam" {
  source = "./modules/oci-iam"

  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  freeform_tags    = local.freeform_tags
}

module "oci_cloud_guard" {
  source = "./modules/oci-cloud-guard"

  tenancy_ocid     = var.tenancy_ocid
  compartment_ocid = var.compartment_ocid
  region           = var.region
  freeform_tags    = local.freeform_tags
}

# --- OKE (depende de network + iam) ---

module "oci_oke" {
  source = "./modules/oci-oke"

  compartment_ocid     = var.compartment_ocid
  cluster_name         = var.cluster_name
  vcn_id               = module.oci_network.vcn_id
  public_subnet_id     = module.oci_network.public_subnet_id
  private_subnet_id    = module.oci_network.private_subnet_id
  workers_nsg_id       = module.oci_network.workers_nsg_id
  lb_nsg_id            = module.oci_network.lb_nsg_id
  bastion_nsg_id       = module.oci_network.bastion_nsg_id
  bastion_allowed_cidr = var.bastion_allowed_cidr
  freeform_tags        = local.freeform_tags

  depends_on = [
    module.oci_network,
    module.oci_iam,
  ]
}

# --- Vault (depende do OKE) ---

module "oci_vault" {
  source = "./modules/oci-vault"

  compartment_ocid           = var.compartment_ocid
  github_oauth_client_id     = var.github_oauth_client_id
  github_oauth_client_secret = var.github_oauth_client_secret
  freeform_tags              = local.freeform_tags

  depends_on = [module.oci_oke]
}
```

- [ ] **Step 2: Reescrever `terraform/infra/outputs.tf`**

```hcl
output "cluster_id" {
  description = "OCID do cluster OKE"
  value       = module.oci_oke.cluster_id
}

output "vault_ocid" {
  description = "OCID do OCI Vault"
  value       = module.oci_vault.vault_ocid
}

output "bastion_ocid" {
  description = "OCID do Bastion"
  value       = module.oci_oke.bastion_ocid
}

output "kubeconfig_command" {
  description = "Comando para gerar/atualizar o kubeconfig"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${module.oci_oke.cluster_id} --file ~/.kube/config-assessforge --auth api_key --overwrite"
}

output "kubernetes_version" {
  description = "Versão do Kubernetes instalada"
  value       = module.oci_oke.cluster_kubernetes_version
}
```

- [ ] **Step 3: Validar o root module completo**

```bash
cd terraform/infra
terraform init -backend=false
terraform validate
```

Esperado: `Success! The configuration is valid.`

- [ ] **Step 4: Formatar tudo**

```bash
terraform fmt -recursive
```

- [ ] **Step 5: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/infra/main.tf terraform/infra/outputs.tf
git commit -m "feat(infra): wire all modules in infra/main.tf and outputs"
```

---

## Chunk 6: k8s/ — ingress-nginx e external-secrets

### Task 11: ingress-nginx

**Files:**
- Create: `terraform/k8s/modules/ingress-nginx/variables.tf`
- Create: `terraform/k8s/modules/ingress-nginx/main.tf`
- Create: `terraform/k8s/modules/ingress-nginx/outputs.tf`

- [ ] **Step 1: Criar `terraform/k8s/modules/ingress-nginx/variables.tf`**

```hcl
# Sem variáveis externas — módulo auto-contido
# O namespace ingress-nginx e o LB são criados pelo Helm chart
```

- [ ] **Step 2: Criar `terraform/k8s/modules/ingress-nginx/main.tf`**

```hcl
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.10.1"  # pinnar versão estável

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape"
    value = "flexible"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape-flex-min"
    value = "10"
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape-flex-max"
    value = "10"
  }

  # Aguardar até o LB receber IP (timeout 5 min)
  wait    = true
  timeout = 300
}
```

- [ ] **Step 3: Criar `terraform/k8s/modules/ingress-nginx/outputs.tf`**

```hcl
# Lê o IP do LB após o Helm release estar pronto
data "kubernetes_service" "ingress_lb" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.ingress_nginx]
}

output "release_status" {
  description = "Status do Helm release do ingress-nginx"
  value       = helm_release.ingress_nginx.status
}

output "lb_ip" {
  description = "IP público do Load Balancer do ingress-nginx"
  value       = try(data.kubernetes_service.ingress_lb.status[0].load_balancer[0].ingress[0].ip, "pending")
}
```

- [ ] **Step 4: Validar**

```bash
cd terraform/k8s && terraform init -backend=false && terraform validate
```

- [ ] **Step 5: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/modules/ingress-nginx/
git commit -m "feat(k8s): add ingress-nginx module with OCI LB flex annotations"
```

---

### Task 12: external-secrets

**Files:**
- Create: `terraform/k8s/modules/external-secrets/variables.tf`
- Create: `terraform/k8s/modules/external-secrets/main.tf`
- Create: `terraform/k8s/modules/external-secrets/outputs.tf`

- [ ] **Step 1: Criar `terraform/k8s/modules/external-secrets/variables.tf`**

```hcl
variable "vault_ocid" {
  description = "OCID do OCI Vault"
  type        = string
}

variable "region" {
  description = "Região OCI"
  type        = string
}
```

- [ ] **Step 2: Criar `terraform/k8s/modules/external-secrets/main.tf` — Helm release**

```hcl
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.9.20"  # pinnar versão estável

  set {
    name  = "installCRDs"
    value = "true"
  }

  wait    = true
  timeout = 300
}
```

- [ ] **Step 3: Adicionar ClusterSecretStore ao main.tf**

```hcl
resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: oci-vault-store
    spec:
      provider:
        oracle:
          vault: "${var.vault_ocid}"
          region: "${var.region}"
          auth:
            workload:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}
```

- [ ] **Step 4: Adicionar ExternalSecret ao main.tf**

```hcl
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "app.kubernetes.io/managed-by"       = "terraform"
    }
  }
}

resource "kubectl_manifest" "argocd_dex_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: argocd-dex-github-secret
      namespace: argocd
    spec:
      refreshInterval: "1h"
      secretStoreRef:
        name: oci-vault-store
        kind: ClusterSecretStore
      target:
        name: argocd-dex-github-secret
        creationPolicy: Owner
      data:
        - secretKey: dex.github.clientID
          remoteRef:
            key: github-oauth-client-id
        - secretKey: dex.github.clientSecret
          remoteRef:
            key: github-oauth-client-secret
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace.argocd,
  ]
}
```

- [ ] **Step 5: Criar `terraform/k8s/modules/external-secrets/outputs.tf`**

```hcl
output "argocd_namespace" {
  description = "Namespace argocd criado pelo módulo external-secrets"
  value       = kubernetes_namespace.argocd.metadata[0].name
}
```

- [ ] **Step 6: Validar e commit**

```bash
cd terraform/k8s && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/modules/external-secrets/
git commit -m "feat(k8s): add external-secrets module (ESO, ClusterSecretStore, ExternalSecret)"
```

---

## Chunk 7: Módulo argocd

### Task 13: argocd — Helm release + ConfigMaps + Ingress

**Files:**
- Create: `terraform/k8s/modules/argocd/variables.tf`
- Create: `terraform/k8s/modules/argocd/main.tf`
- Create: `terraform/k8s/modules/argocd/outputs.tf`

- [ ] **Step 1: Criar `terraform/k8s/modules/argocd/variables.tf`**

```hcl
variable "argocd_hostname" {
  description = "Hostname público do ArgoCD"
  type        = string
}

variable "github_org" {
  description = "Nome da organização no GitHub"
  type        = string
}

```

- [ ] **Step 2: Criar `terraform/k8s/modules/argocd/main.tf` — senha Redis e Helm release**

```hcl
resource "random_password" "redis" {
  length  = 32
  special = false
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "7.6.12"  # pinnar versão estável
  create_namespace = false      # namespace criado pelo módulo external-secrets com labels corretas

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      global = {
        securityContext = {
          runAsNonRoot = true
          runAsUser    = 999
          fsGroup      = 999
        }
      }

      controller = {
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { cpu = "1",    memory = "2Gi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      server = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
        # Desabilitar HTTPS interno — TLS feito pelo Cloudflare
        extraArgs = ["--insecure"]
      }

      repoServer = {
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits   = { cpu = "1",    memory = "1Gi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      dex = {
        resources = {
          requests = { cpu = "50m",  memory = "64Mi" }
          limits   = { cpu = "100m", memory = "128Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      redis = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "250m", memory = "256Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      applicationSet = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "250m", memory = "256Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      configs = {
        secret = {
          # Redis password gerenciado aqui; argocd-secret gerenciado pelo ArgoCD
          redisPassword = random_password.redis.result
        }

        # argocd-cm — Helm gerencia este ConfigMap, usar configs.cm para evitar conflito
        cm = {
          "url"                     = "https://${var.argocd_hostname}"
          "admin.enabled"           = "false"
          "users.anonymous.enabled" = "false"
          "exec.enabled"            = "false"
          "dex.config"              = <<-EOT
            connectors:
              - type: github
                id: github
                name: GitHub
                config:
                  clientID: $argocd-dex-github-secret:dex.github.clientID
                  clientSecret: $argocd-dex-github-secret:dex.github.clientSecret
                  orgs:
                    - name: ${var.github_org}
                  scopes:
                    - read:org
          EOT
        }

        # argocd-rbac-cm
        rbac = {
          "policy.default" = "role:admin"
          "scopes"         = "[groups, email]"
        }

        # argocd-cmd-params-cm
        params = {
          "server.login.attempts.max"   = "5"
          "server.login.attempts.reset" = "300"
          "server.log.level"            = "info"
          "server.log.format"           = "json"
          "controller.log.level"        = "info"
          "controller.log.format"       = "json"
          "reposerver.log.level"        = "info"
          "reposerver.log.format"       = "json"
        }
      }
    })
  ]
}
```

**Nota:** Os ConfigMaps `argocd-cm`, `argocd-rbac-cm` e `argocd-cmd-params-cm` são gerenciados pelo Helm chart via `configs.cm`, `configs.rbac` e `configs.params` no bloco `values` acima. NÃO criar `kubernetes_config_map` separados para estes — causaria conflito com o Helm chart que já os possui.

- [ ] **Step 3: Adicionar Ingress resource**

```hcl
resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect"    = "false"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.argocd_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}
```

- [ ] **Step 4: Criar `terraform/k8s/modules/argocd/outputs.tf`**

```hcl
output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = "argocd"
}

output "argocd_ingress_host" {
  description = "Hostname configurado no Ingress do ArgoCD"
  value       = var.argocd_hostname
}
```

- [ ] **Step 5: Validar e commit**

```bash
cd terraform/k8s && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/modules/argocd/
git commit -m "feat(k8s): add argocd module (helm values with cm/rbac/params, ingress)"
```

---

## Chunk 8: Módulos kyverno e network-policies

### Task 14: kyverno

**Files:**
- Create: `terraform/k8s/modules/kyverno/variables.tf`
- Create: `terraform/k8s/modules/kyverno/main.tf`
- Create: `terraform/k8s/modules/kyverno/outputs.tf`

- [ ] **Step 1: Criar `terraform/k8s/modules/kyverno/variables.tf`**

```hcl
# Sem variáveis externas — configuração interna ao módulo
```

- [ ] **Step 2: Criar `terraform/k8s/modules/kyverno/main.tf` — Helm release**

```hcl
locals {
  excluded_namespaces = [
    "kube-system",
    "kyverno",
    "longhorn-system",
    "external-secrets",
    "argocd",
    "ingress-nginx",
  ]
}

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  version          = "3.2.6"  # pinnar versão estável

  set {
    name  = "replicaCount"
    value = "1"
  }

  wait    = true
  timeout = 300
}
```

- [ ] **Step 3: Adicionar ClusterPolicy disallow-root-containers**

```hcl
resource "kubectl_manifest" "policy_disallow_root_containers" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-root-containers
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-runAsNonRoot
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Containers devem rodar como non-root (runAsNonRoot: true)"
            pattern:
              spec:
                containers:
                  - securityContext:
                      runAsNonRoot: true
  YAML

  depends_on = [helm_release.kyverno]
}
```

- [ ] **Step 4: Adicionar demais ClusterPolicies**

```hcl
resource "kubectl_manifest" "policy_disallow_privilege_escalation" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-privilege-escalation
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-privilege-escalation
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "allowPrivilegeEscalation deve ser false"
            pattern:
              spec:
                containers:
                  - securityContext:
                      allowPrivilegeEscalation: false
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_require_readonly_rootfs" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-readonly-rootfs
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-readOnlyRootFilesystem
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "readOnlyRootFilesystem deve ser true"
            pattern:
              spec:
                containers:
                  - securityContext:
                      readOnlyRootFilesystem: true
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_disallow_latest_tag" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-latest-tag
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-image-tag
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Imagens não devem usar a tag ':latest'"
            foreach:
              - list: "request.object.spec.containers"
                deny:
                  conditions:
                    any:
                      - key: "{{element.image}}"
                        operator: Equals
                        value: "*:latest"
                      - key: "{{element.image}}"
                        operator: NotContains
                        value: ":"
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_require_resource_limits" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-resource-limits
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-resource-limits
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Todos os containers devem ter resources.limits.cpu e resources.limits.memory definidos"
            pattern:
              spec:
                containers:
                  - resources:
                      limits:
                        cpu: "?*"
                        memory: "?*"
  YAML

  depends_on = [helm_release.kyverno]
}
```

- [ ] **Step 5: Criar `terraform/k8s/modules/kyverno/outputs.tf`**

```hcl
output "release_status" {
  description = "Status do Helm release do Kyverno"
  value       = helm_release.kyverno.status
}
```

- [ ] **Step 6: Validar e commit**

```bash
cd terraform/k8s && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/modules/kyverno/
git commit -m "feat(k8s): add kyverno module (5 ClusterPolicies enforce)"
```

---

### Task 15: network-policies

**Files:**
- Create: `terraform/k8s/modules/network-policies/variables.tf`
- Create: `terraform/k8s/modules/network-policies/main.tf`
- Create: `terraform/k8s/modules/network-policies/outputs.tf`

- [ ] **Step 1: Criar `terraform/k8s/modules/network-policies/variables.tf`**

```hcl
# Sem variáveis externas — políticas são específicas do namespace argocd
```

- [ ] **Step 2: Criar `terraform/k8s/modules/network-policies/main.tf`**

```hcl
# Policy 1: deny-all baseline no namespace argocd
resource "kubectl_manifest" "deny_all_default" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-all-default
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
        - Egress
  YAML
}

# Policy 2: redis lockdown — ingress 6379 apenas dos componentes argocd necessários
resource "kubectl_manifest" "argocd_redis_lockdown" {
  # depends_on garante que o deny-all baseline existe antes de aplicar exceções
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-redis-lockdown
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: redis
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector:
                matchLabels:
                  app.kubernetes.io/component: server
            - podSelector:
                matchLabels:
                  app.kubernetes.io/component: application-controller
            - podSelector:
                matchLabels:
                  app.kubernetes.io/component: repo-server
          ports:
            - protocol: TCP
              port: 6379
  YAML
}

# Policy 3: argocd-server-ingress — apenas do namespace ingress-nginx
resource "kubectl_manifest" "argocd_server_ingress" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-server-ingress
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: server
      policyTypes:
        - Ingress
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: ingress-nginx
          ports:
            - protocol: TCP
              port: 8080
            - protocol: TCP
              port: 8083
  YAML
}

# Policy 4: argocd-internal-only — componentes internos só aceitam tráfego de dentro do namespace
resource "kubectl_manifest" "argocd_internal_only_repo_server" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-internal-repo-server
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: repo-server
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector: {}
  YAML
}

resource "kubectl_manifest" "argocd_internal_only_app_controller" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-internal-app-controller
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: application-controller
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector: {}
  YAML
}

resource "kubectl_manifest" "argocd_internal_only_dex" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-internal-dex
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: dex
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector: {}
  YAML
}

# Egress liberado para todos os pods argocd (DNS + GitHub + OCI APIs)
# Necessário: ArgoCD precisa alcançar GitHub (sync), OCI Vault (ESO), DNS, e outros serviços externos
resource "kubectl_manifest" "argocd_egress_all" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-egress-allow-all
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector: {}
      policyTypes:
        - Egress
      egress:
        - {}
  YAML
}
```

- [ ] **Step 3: Criar `terraform/k8s/modules/network-policies/outputs.tf`**

```hcl
# Sem outputs externos — módulo aplica políticas e não expõe valores
```

- [ ] **Step 4: Validar e commit**

```bash
cd terraform/k8s && terraform validate && terraform fmt -recursive
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/modules/network-policies/
git commit -m "feat(k8s): add network-policies module (deny-all, redis lockdown, ingress policies)"
```

---

## Chunk 9: k8s/ wiring + README

### Task 16: k8s/ main.tf e outputs.tf

**Files:**
- Modify: `terraform/k8s/main.tf`
- Modify: `terraform/k8s/outputs.tf`

- [ ] **Step 1: Reescrever `terraform/k8s/main.tf`**

```hcl
# Leitura dos outputs do infra/ via remote state
data "terraform_remote_state" "infra" {
  backend = "s3"

  config = {
    bucket                      = "assessforge-tfstate"
    key                         = "infra/terraform.tfstate"
    region                      = var.region
    endpoint                    = var.oci_object_storage_endpoint
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    force_path_style            = true
  }
}

# --- Módulo ingress-nginx (primeiro — cria o LB) ---

module "ingress_nginx" {
  source = "./modules/ingress-nginx"
}

# --- External Secrets Operator (depende do ingress) ---

module "external_secrets" {
  source = "./modules/external-secrets"

  vault_ocid = data.terraform_remote_state.infra.outputs.vault_ocid
  region     = var.region

  depends_on = [module.ingress_nginx]
}

# --- ArgoCD (depende do ESO) ---

module "argocd" {
  source = "./modules/argocd"

  argocd_hostname = var.argocd_hostname
  github_org      = var.github_org

  depends_on = [module.external_secrets]
}

# --- Kyverno (depende do ArgoCD) ---

module "kyverno" {
  source = "./modules/kyverno"

  depends_on = [module.argocd]
}

# --- NetworkPolicies (depende do ArgoCD) ---

module "network_policies" {
  source = "./modules/network-policies"

  depends_on = [module.argocd]
}
```

- [ ] **Step 2: Reescrever `terraform/k8s/outputs.tf`**

```hcl
output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = module.argocd.argocd_namespace
}

output "argocd_hostname" {
  description = "Hostname configurado no Ingress do ArgoCD"
  value       = module.argocd.argocd_ingress_host
}

output "ingress_lb_ip" {
  description = "IP público do Load Balancer do ingress-nginx (use para configurar DNS no Cloudflare)"
  value       = module.ingress_nginx.lb_ip
}

output "ingress_lb_ip_command" {
  description = "Comando alternativo para obter o IP do LB caso o output acima mostre 'pending'"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
```

- [ ] **Step 3: Validar root module k8s/ completo**

```bash
cd terraform/k8s
terraform init -backend=false
terraform validate
```

Esperado: `Success! The configuration is valid.`

- [ ] **Step 4: Formatar tudo**

```bash
terraform fmt -recursive
```

- [ ] **Step 5: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/k8s/main.tf terraform/k8s/outputs.tf
git commit -m "feat(k8s): wire all modules in k8s/main.tf and outputs"
```

---

### Task 17: README.md

**Files:**
- Create: `terraform/README.md`

- [ ] **Step 1: Criar `terraform/README.md`**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git add terraform/README.md
git commit -m "docs: add terraform README with step-by-step setup guide"
```

---

### Task 18: Validação final end-to-end

- [ ] **Step 1: Validar ambos os root modules**

```bash
cd terraform/infra && terraform init -backend=false && terraform validate
cd ../k8s && terraform init -backend=false && terraform validate
```

Esperado: ambos retornam `Success! The configuration is valid.`

- [ ] **Step 2: Verificar fmt em todo o projeto**

```bash
cd terraform && terraform fmt -recursive -check
```

Esperado: nenhum output (zero diff).

- [ ] **Step 3: Verificar que nenhum .tfvars foi commitado**

```bash
git -C /home/rodrigo/projects/AssessForge/infra-setup \
  log --all --full-history -- "**/*.tfvars"
```

Esperado: nenhum resultado (nenhum .tfvars no histórico git).

- [ ] **Step 4: Listar todos os arquivos criados**

```bash
find /home/rodrigo/projects/AssessForge/infra-setup/terraform -name "*.tf" | sort
```

Esperado: ao menos 38 arquivos `.tf`. Listar e confirmar que todos os módulos têm `main.tf`, `variables.tf` e `outputs.tf`.

- [ ] **Step 5: Commit final de consolidação**

```bash
cd /home/rodrigo/projects/AssessForge/infra-setup
git status  # deve estar clean
git log --oneline
```

---

## Checklist de Verificação Pré-Deploy

Antes de executar `terraform apply` em ambiente real:

- [ ] `~/.oci/config` tem perfil `DEFAULT` configurado e testado (`oci iam region list`)
- [ ] Variáveis `github_oauth_client_id` e `github_oauth_client_secret` preenchidas no `terraform.tfvars` (não commitado)
- [ ] Endpoint do backend substituído nos dois `backend.tf` (PLACEHOLDER → namespace real)
- [ ] Bucket `assessforge-tfstate` criado no OCI Object Storage
- [ ] `bastion_allowed_cidr` restrito ao seu IP real (não `0.0.0.0/0`)
- [ ] DNS `argocd.assessforge.com` pronto para receber o record A após o deploy
