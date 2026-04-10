# Dynamic Group para Instance Principal dos worker nodes OKE
resource "oci_identity_dynamic_group" "instance_principal" {
  compartment_id = var.tenancy_ocid # Dynamic groups vivem no tenancy root
  name           = "assessforge-instance-principal"
  description    = "Dynamic group para worker nodes OKE via Instance Principal (BASIC tier)"
  freeform_tags  = var.freeform_tags

  # resource.type = 'instance' com instance.compartment.id restringe ao compartment especifico,
  # evitando que instancias de outros compartments assumam este grupo.
  matching_rule = "ALL {resource.type = 'instance', instance.compartment.id = '${var.compartment_ocid}'}"

  lifecycle {
    create_before_destroy = true
  }
}

# Policy — worker nodes podem ler secrets do Vault via Instance Principal
resource "oci_identity_policy" "instance_principal_vault" {
  compartment_id = var.compartment_ocid
  name           = "assessforge-instance-principal-vault-policy"
  description    = "Permite aos worker nodes OKE ler secrets do OCI Vault via Instance Principal"
  freeform_tags  = var.freeform_tags

  statements = [
    "Allow dynamic-group ${oci_identity_dynamic_group.instance_principal.name} to read secret-family in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.instance_principal.name} to use vaults in compartment id ${var.compartment_ocid}",
    "Allow dynamic-group ${oci_identity_dynamic_group.instance_principal.name} to use keys in compartment id ${var.compartment_ocid}",
  ]

  depends_on = [oci_identity_dynamic_group.instance_principal]
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
