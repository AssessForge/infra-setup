variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "vcn_cidr" {
  description = "CIDR da VCN"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR da subnet pública (LB e Bastion)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR da subnet privada (worker nodes)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "bastion_allowed_cidr" {
  description = "CIDR do IP do operador para acesso SSH ao Bastion"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
