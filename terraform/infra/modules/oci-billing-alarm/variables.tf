variable "compartment_ocid" {
  description = "OCID do compartment target"
  type        = string
}

variable "tenancy_ocid" {
  description = "OCID do tenancy — metricas de billing vivem no nivel do tenancy"
  type        = string
}

variable "notification_email" {
  description = "Email para receber alertas de billing via OCI Notifications. Deixe vazio para nao criar subscription."
  type        = string
  default     = ""
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
