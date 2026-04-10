output "dynamic_group_name" {
  description = "Nome do Dynamic Group de Instance Principal criado"
  value       = oci_identity_dynamic_group.instance_principal.name
}
