variable "compartment_ocid" {
  description = "OCID do compartment"
  type        = string
}

variable "cluster_name" {
  description = "Nome do cluster OKE"
  type        = string
}

variable "vcn_id" {
  description = "OCID da VCN"
  type        = string
}

variable "public_subnet_id" {
  description = "OCID da subnet pública (LB)"
  type        = string
}

variable "private_subnet_id" {
  description = "OCID da subnet privada (workers)"
  type        = string
}

variable "workers_nsg_id" {
  description = "OCID do NSG dos worker nodes"
  type        = string
}

variable "lb_nsg_id" {
  description = "OCID do NSG do Load Balancer"
  type        = string
}

variable "bastion_nsg_id" {
  description = "OCID do NSG do Bastion"
  type        = string
}

variable "bastion_allowed_cidr" {
  description = "CIDR do IP do operador para o Bastion client_cidr_block_allow_list"
  type        = string
}

variable "freeform_tags" {
  description = "Tags aplicadas a todos os recursos"
  type        = map(string)
  default     = {}
}
