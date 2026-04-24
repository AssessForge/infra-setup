terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

# Dynamic Group legado (tenancy root) -- API `oci_identity_dynamic_group`.
# Em tenancies pos-2023 a OCI mantem essa API como facade sobre o Default
# Identity Domain, mas sem o bug que o recurso SCIM
# `oci_identity_domains_dynamic_resource_group` tem de dropar matching_rule
# silenciosamente no create (provider oracle/oci 8.10.0). A API legada grava
# matching_rule corretamente e eh a alternativa suportada com IaC reproduzivel.
resource "oci_identity_dynamic_group" "workers" {
  compartment_id = var.tenancy_ocid
  name           = "assessforge-workers"
  description    = "Workers OKE via Instance Principal"
  matching_rule  = "ALL {resource.type = 'instance', instance.compartment.id = '${var.compartment_ocid}'}"
  freeform_tags  = var.freeform_tags
}

# Policy -- worker nodes podem ler secrets do Vault via Instance Principal.
# Prefixo 'Default'/ e obrigatorio pra policies referenciarem DGs criados via
# API legada em tenancies pos-2023 (facade sobre Default Identity Domain).
resource "oci_identity_policy" "instance_principal_vault" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-instance-principal-vault-policy"
  description    = "Permite aos worker nodes OKE ler secrets do OCI Vault via Instance Principal"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow dynamic-group 'Default'/${oci_identity_dynamic_group.workers.name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group 'Default'/${oci_identity_dynamic_group.workers.name} to use vaults in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group 'Default'/${oci_identity_dynamic_group.workers.name} to use keys in compartment id ${var.compartment_ocid}",
  ]

  depends_on = [oci_identity_dynamic_group.workers]
}

# Policy -- OKE pode gerenciar recursos de rede para criar Load Balancers
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

# --- ESO User Principal (workaround para bug IDCS matching-rule) ---
#
# Contexto: nesta tenancy, writes de matching_rule no IDCS SCIM silenciosamente
# retornam null em TODOS os caminhos testados (Terraform/CLI/Console/raw PATCH
# via SCIM). Ver `project_oci_drg_matching_rule_bug.md` na memoria. Sem
# matching_rule, Instance Principal nao resolve pra nenhum DG → ESO recebe
# HTTP 404 "Authorization failed" ao chamar GetSecretBundleByName.
#
# Workaround: user dedicado com API key, escopo minimo (`read secret-family`
# apenas no compartment do projeto). Chave gerada localmente via tls_private_key,
# public key registrada no OCI via oci_identity_api_key, private key semeada
# como Secret K8s pelo modulo oci-argocd-bootstrap para que o ClusterSecretStore
# do ESO possa autenticar como UserPrincipal.
#
# Compromisso: viola a restricao do projeto "no static API keys". Transitorio
# ate o bug IDCS ser resolvido pelo suporte OCI -- entao este bloco pode ser
# removido e voltamos ao Instance Principal via DG legado.

resource "oci_identity_user" "eso_secrets_reader" {
  compartment_id = var.tenancy_ocid
  name           = "eso-secrets-reader"
  description    = "Service account para ESO autenticar no OCI Vault via API key (workaround bug IDCS)"
  email          = var.eso_user_email
  freeform_tags  = var.freeform_tags
}

resource "oci_identity_group" "eso_secrets_readers" {
  compartment_id = var.tenancy_ocid
  name           = "eso-secrets-readers"
  description    = "Grupo do service account ESO -- permissao de leitura no Vault"
  freeform_tags  = var.freeform_tags
}

resource "oci_identity_user_group_membership" "eso_secrets_reader" {
  user_id  = oci_identity_user.eso_secrets_reader.id
  group_id = oci_identity_group.eso_secrets_readers.id
}

# Par RSA 2048 gerado localmente; private key fica em state (sensitive).
# OCI aceita RSA 2048+ para API keys.
resource "tls_private_key" "eso_api_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "oci_identity_api_key" "eso_api_key" {
  user_id   = oci_identity_user.eso_secrets_reader.id
  key_value = tls_private_key.eso_api_key.public_key_pem
}

resource "oci_identity_policy" "eso_user_principal_vault" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-eso-user-principal-vault-policy"
  description    = "Permite ao user ESO ler secrets do Vault via API key (UserPrincipal)"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow group ${oci_identity_group.eso_secrets_readers.name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow group ${oci_identity_group.eso_secrets_readers.name} to use vaults in compartment id ${var.compartment_ocid}",
    "Allow group ${oci_identity_group.eso_secrets_readers.name} to use keys in compartment id ${var.compartment_ocid}",
  ]

  depends_on = [oci_identity_group.eso_secrets_readers]
}
