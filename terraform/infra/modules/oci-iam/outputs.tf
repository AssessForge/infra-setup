output "dynamic_group_name" {
  description = "Nome do Dynamic Group criado"
  value       = oci_identity_dynamic_group.workload_identity.name
}
