terraform {
  required_providers {
    oci = {
      source = "oracle/oci"
    }
  }
}

# Lookup do Identity Domain Default da tenancy.
# Tenancies pos-2023 usam Identity Domains: Dynamic Groups "legados"
# (recurso oci_identity_dynamic_group, criados em tenancy root) nao sao
# reconhecidos por policies que usam o prefixo 'Default/<name>'.
# A forma correta e criar o grupo como Dynamic Resource Group DENTRO do
# Identity Domain via SCIM (recurso oci_identity_domains_dynamic_resource_group).
data "oci_identity_domains" "default" {
  compartment_id = var.tenancy_ocid

  display_name      = "Default"
  home_region_url   = null
  domain_type       = "DEFAULT"
  lifecycle_details = "ACTIVE"
}

locals {
  default_domain_url = data.oci_identity_domains.default.domains[0].url
}

# Dynamic Resource Group dentro do Identity Domain Default.
# resource.type = 'instance' com instance.compartment.id restringe ao
# compartment especifico, evitando que instancias de outros compartments
# assumam este grupo.
resource "oci_identity_domains_dynamic_resource_group" "instance_principal" {
  idcs_endpoint = local.default_domain_url

  display_name  = "assessforge-instance-principal"
  matching_rule = "ALL {resource.type = 'instance', instance.compartment.id = '${var.compartment_ocid}'}"
  schemas       = ["urn:ietf:params:scim:schemas:oracle:idcs:DynamicResourceGroup"]

  description = "DRG para worker nodes OKE via Instance Principal (Identity Domain-native)"
}

# Policy -- worker nodes podem ler secrets do Vault via Instance Principal.
# Prefixo 'Default/' e obrigatorio pra resolver o DRG dentro do Identity Domain.
resource "oci_identity_policy" "instance_principal_vault" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-instance-principal-vault-policy"
  description    = "Permite aos worker nodes OKE ler secrets do OCI Vault via Instance Principal"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow dynamic-group 'Default'/${oci_identity_domains_dynamic_resource_group.instance_principal.display_name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group 'Default'/${oci_identity_domains_dynamic_resource_group.instance_principal.display_name} to use vaults in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group 'Default'/${oci_identity_domains_dynamic_resource_group.instance_principal.display_name} to use keys in compartment id ${var.compartment_ocid}",
  ]

  depends_on = [oci_identity_domains_dynamic_resource_group.instance_principal]
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
