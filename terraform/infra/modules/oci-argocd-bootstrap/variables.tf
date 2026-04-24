variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "region" {
  description = "Regiao OCI (ex: sa-saopaulo-1)"
  type        = string
}

variable "vault_ocid" {
  description = "OCID do OCI Vault para annotations do Bridge Secret"
  type        = string
}

variable "public_subnet_id" {
  description = "OCID da subnet publica (para annotations do Bridge Secret)"
  type        = string
}

variable "private_subnet_id" {
  description = "OCID da subnet privada (para annotations do Bridge Secret)"
  type        = string
}

variable "gitops_repo_url" {
  description = "URL do repositorio GitOps (gitops-setup)"
  type        = string
}

variable "gitops_repo_revision" {
  description = "Branch/revision do repositorio GitOps"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster OKE"
  type        = string
  default     = "assessforge-oke"
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}

variable "gitops_repo_pat" {
  description = "GitHub Personal Access Token para autenticar o ArgoCD no repositorio privado gitops-setup"
  type        = string
  sensitive   = true
}

variable "tenancy_ocid" {
  description = "OCID do tenancy (usado no Secret de credenciais ESO -- UserPrincipal auth)"
  type        = string
}

variable "eso_user_ocid" {
  description = "OCID do user ESO (workaround bug IDCS matching-rule; ver project_oci_drg_matching_rule_bug.md)"
  type        = string
}

variable "eso_api_key_fingerprint" {
  description = "Fingerprint da API key do user ESO"
  type        = string
}

variable "eso_api_key_private_key_pem" {
  description = "Private key PEM da API key do user ESO"
  type        = string
  sensitive   = true
}
