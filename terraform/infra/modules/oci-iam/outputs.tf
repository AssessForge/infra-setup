output "dynamic_group_name" {
  description = "Nome do Dynamic Group legado (tenancy root) usado no Instance Principal"
  value       = oci_identity_dynamic_group.workers.name
}

output "eso_user_ocid" {
  description = "OCID do user ESO (autenticacao UserPrincipal via API key)"
  value       = oci_identity_user.eso_secrets_reader.id
}

output "eso_api_key_fingerprint" {
  description = "Fingerprint da API key do user ESO (formato colon-separated MD5)"
  value       = oci_identity_api_key.eso_api_key.fingerprint
}

output "eso_api_key_private_key_pem" {
  description = "Private key PEM da API key do user ESO (sensivel, flui pra K8s Secret)"
  value       = tls_private_key.eso_api_key.private_key_pem
  sensitive   = true
}
