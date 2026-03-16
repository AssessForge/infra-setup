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
