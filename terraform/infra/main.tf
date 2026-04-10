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
  count  = var.enable_cloud_guard ? 1 : 0

  tenancy_ocid       = var.tenancy_ocid
  compartment_ocid   = var.compartment_ocid
  region             = var.region
  notification_email = var.notification_email
  freeform_tags      = local.freeform_tags
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
  api_endpoint_nsg_id  = module.oci_network.api_endpoint_nsg_id
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
  gitops_repo_pat            = var.gitops_repo_pat
  freeform_tags              = local.freeform_tags

  depends_on = [module.oci_oke]
}

# --- Bootstrap ArgoCD (depende de OKE + Vault) ---

module "oci_argocd_bootstrap" {
  source = "./modules/oci-argocd-bootstrap"

  compartment_ocid     = var.compartment_ocid
  region               = var.region
  vault_ocid           = module.oci_vault.vault_ocid
  public_subnet_id     = module.oci_network.public_subnet_id
  private_subnet_id    = module.oci_network.private_subnet_id
  gitops_repo_url      = var.gitops_repo_url
  gitops_repo_revision = var.gitops_repo_revision
  cluster_name         = var.cluster_name
  freeform_tags        = local.freeform_tags

  depends_on = [
    module.oci_oke,
    module.oci_vault,
  ]
}
