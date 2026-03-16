# Dynamic Group para Workload Identity do ESO
resource "oci_identity_dynamic_group" "workload_identity" {
  compartment_id = var.tenancy_ocid # Dynamic groups vivem no tenancy root
  name           = "assessforge-workload-identity"
  description    = "Dynamic group para External Secrets Operator via Workload Identity"
  freeform_tags  = var.freeform_tags

  # resource.type = 'workload' restringe ao Workload Identity de pods OKE via OIDC,
  # evitando que qualquer compute instance do compartment assuma este grupo.
  matching_rule = "ALL {resource.type = 'workload', resource.compartment.id = '${var.compartment_ocid}'}"
}

# Policy — ESO pode ler secrets do Vault
resource "oci_identity_policy" "eso_vault_access" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-eso-vault-policy"
  description    = "Permite ao ESO ler secrets do OCI Vault via Workload Identity"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.workload_identity.name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.workload_identity.name} to use vaults in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.workload_identity.name} to use keys in compartment id ${var.compartment_ocid}",
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
