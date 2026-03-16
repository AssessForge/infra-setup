terraform {
  required_version = ">= 1.5.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.8"
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

# helm 3.x: kubernetes {} block → kubernetes = {} nested object
provider "helm" {
  kubernetes = {
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
