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

variable "notification_emails" {
  description = "Lista de emails para alertas do Cloud Guard e do alarme de billing (opcional)"
  type        = list(string)
  default     = []
}

variable "enable_cloud_guard" {
  description = "Habilitar Cloud Guard (requer tenancy pago — nao disponivel no Free Tier)"
  type        = bool
  default     = false
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

variable "gitops_repo_pat" {
  description = "GitHub Personal Access Token para acesso ao repositorio gitops-setup"
  type        = string
  sensitive   = true
}

variable "enable_billing_alarm" {
  description = "Habilitar alarme de billing que alerta quando qualquer custo for maior que zero"
  type        = bool
  default     = false
}

variable "eso_user_email" {
  description = "Email do service-account user ESO (requerido pela OCI Identity ao criar o user)"
  type        = string
}
