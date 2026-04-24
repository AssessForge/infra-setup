terraform {
  required_version = ">= 1.5.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 8.0"
    }
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
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  backend "oci" {
    bucket    = "assessforge-tfstate"
    key       = "infra/terraform.tfstate"
    region    = "sa-saopaulo-1"
    namespace = "grzav3wfvr8v"
  }
}

provider "oci" {
  region = var.region
  # Autentica via ~/.oci/config perfil DEFAULT
  # Não hardcodar user_ocid, fingerprint ou private_key_path aqui
}

locals {
  kubeconfig_path   = pathexpand("~/.kube/config-assessforge")
  kubeconfig_exists = fileexists(pathexpand("~/.kube/config-assessforge"))
}

# Fase 1 (cluster nao existe): config_path = null, providers inicializam sem conectar
# Fase 2 (apos kubeconfig gerado): config_path aponta para o arquivo e conectam normalmente
provider "helm" {
  kubernetes = {
    config_path = local.kubeconfig_exists ? local.kubeconfig_path : null
  }
}

provider "kubernetes" {
  config_path = local.kubeconfig_exists ? local.kubeconfig_path : null
}

provider "kubectl" {
  config_path      = local.kubeconfig_exists ? local.kubeconfig_path : null
  load_config_file = local.kubeconfig_exists
}
