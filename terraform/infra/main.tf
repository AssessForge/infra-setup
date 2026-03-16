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
