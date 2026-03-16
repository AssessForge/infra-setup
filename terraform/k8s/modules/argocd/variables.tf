variable "argocd_hostname" {
  description = "Hostname público do ArgoCD"
  type        = string
}

variable "github_org" {
  description = "Nome da organização no GitHub"
  type        = string
}

variable "github_team_admin" {
  description = "Slug do GitHub team com acesso admin"
  type        = string
}

variable "github_team_readonly" {
  description = "Slug do GitHub team com acesso read-only"
  type        = string
}
