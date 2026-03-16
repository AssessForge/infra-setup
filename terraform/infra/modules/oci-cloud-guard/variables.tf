variable "tenancy_ocid" {
  description = "OCID do tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment target"
  type        = string
}

variable "region" {
  description = "Região OCI reporting do Cloud Guard"
  type        = string
}

variable "notification_email" {
  description = "Email para receber alertas do Cloud Guard via OCI Notifications. Deixe vazio para não criar subscription."
  type        = string
  default     = ""
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
