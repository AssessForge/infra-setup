output "dynamic_group_name" {
  description = "Nome do Dynamic Resource Group de Instance Principal (dentro do Identity Domain Default)"
  value       = oci_identity_domains_dynamic_resource_group.instance_principal.display_name
}
