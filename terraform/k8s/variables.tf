variable "region" {
  description = "Região OCI"
  type        = string
}

variable "oci_object_storage_endpoint" {
  description = "Endpoint S3-compat do OCI Object Storage para leitura do remote state do infra/"
  type        = string
}

variable "argocd_hostname" {
  description = "Hostname público do ArgoCD (ex: argocd.assessforge.com)"
  type        = string
}

variable "github_org" {
  description = "Nome da organização no GitHub"
  type        = string
}

