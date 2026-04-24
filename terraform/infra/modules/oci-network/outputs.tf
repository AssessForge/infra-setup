output "vcn_id" {
  description = "OCID da VCN"
  value       = oci_core_vcn.main.id
}

output "public_subnet_id" {
  description = "OCID da subnet pública"
  value       = oci_core_subnet.public.id
}

output "private_subnet_id" {
  description = "OCID da subnet privada"
  value       = oci_core_subnet.private.id
}

output "lb_nsg_id" {
  description = "OCID do NSG do Load Balancer"
  value       = oci_core_network_security_group.lb.id
}

output "workers_nsg_id" {
  description = "OCID do NSG dos worker nodes"
  value       = oci_core_network_security_group.workers.id
}

output "bastion_nsg_id" {
  description = "OCID do NSG do Bastion"
  value       = oci_core_network_security_group.bastion.id
}

output "api_endpoint_nsg_id" {
  description = "OCID do NSG dedicado ao API endpoint do OKE"
  value       = oci_core_network_security_group.api_endpoint.id
}

output "cloud_shell_nsg_id" {
  description = "OCID do NSG dedicado ao OCI Cloud Shell Private Network (bootstrap via Cloud Shell)"
  value       = oci_core_network_security_group.cloud_shell.id
}
