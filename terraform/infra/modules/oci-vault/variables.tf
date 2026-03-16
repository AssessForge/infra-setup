variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
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

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
