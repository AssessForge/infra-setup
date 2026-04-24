variable "tenancy_ocid" {
  description = "OCID do tenancy"
  type        = string
}

variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}

variable "eso_user_email" {
  description = "Email do service-account user ESO (obrigatorio no OCI Identity)"
  type        = string
}
