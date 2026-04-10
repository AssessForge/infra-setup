variable "tenancy_ocid" {
  description = "OCID do tenancy OCI"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment onde os recursos serão criados"
  type        = string
}

variable "region" {
  description = "Região OCI (ex: sa-saopaulo-1)"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster OKE"
  type        = string
  default     = "assessforge-oke"
}

variable "bastion_allowed_cidr" {
  description = "CIDR do IP do operador para acesso SSH ao Bastion (ex: 1.2.3.4/32)"
  type        = string
}

variable "notification_email" {
  description = "Email para alertas do Cloud Guard (opcional)"
  type        = string
  default     = ""
}

variable "github_oauth_client_id" {
  description = "Client ID do GitHub OAuth App"
  type        = string
  sensitive   = true
}

variable "github_oauth_client_secret" {
  description = "Client Secret do GitHub OAuth App"
  type        = string
  sensitive   = true
}

variable "gitops_repo_url" {
  description = "URL do repositorio GitOps (gitops-setup)"
  type        = string
  default     = "https://github.com/AssessForge/gitops-setup"
}

variable "gitops_repo_revision" {
  description = "Branch/revision do repositorio GitOps"
  type        = string
  default     = "main"
}
