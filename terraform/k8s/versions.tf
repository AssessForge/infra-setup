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
