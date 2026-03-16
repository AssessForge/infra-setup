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
