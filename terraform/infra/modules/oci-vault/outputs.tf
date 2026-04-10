output "vault_ocid" {
  description = "OCID do OCI Vault"
  value       = oci_kms_vault.main.id
}

output "vault_management_endpoint" {
  description = "Management endpoint do Vault"
  value       = oci_kms_vault.main.management_endpoint
}

output "master_key_ocid" {
  description = "OCID da Master Key"
  value       = oci_kms_key.master.id
}

output "gitops_repo_pat_ocid" {
  description = "OCID do secret GitHub PAT no Vault"
  value       = oci_vault_secret.gitops_repo_pat.id
  sensitive   = true
}
