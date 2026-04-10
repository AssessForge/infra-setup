# OCI Vault
resource "oci_kms_vault" "main" {
  compartment_id = var.compartment_ocid
  display_name   = "argocd-vault"
  vault_type     = "DEFAULT"
  freeform_tags  = var.freeform_tags

  lifecycle {
    prevent_destroy = true
  }
}

# Master Encryption Key AES-256
resource "oci_kms_key" "master" {
  compartment_id      = var.compartment_ocid
  display_name        = "argocd-master-key"
  management_endpoint = oci_kms_vault.main.management_endpoint
  freeform_tags       = var.freeform_tags

  key_shape {
    algorithm = "AES"
    length    = 32 # 256 bits
  }

  lifecycle {
    prevent_destroy = true
  }
}

# Secret — GitHub OAuth Client ID
resource "oci_vault_secret" "github_oauth_client_id" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "github-oauth-client-id"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.github_oauth_client_id)
    name         = "github-oauth-client-id"
    # stage é read-only no OCI provider >= 6.0 — não incluir
  }
}

# Secret — GitHub OAuth Client Secret
resource "oci_vault_secret" "github_oauth_client_secret" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "github-oauth-client-secret"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.github_oauth_client_secret)
    name         = "github-oauth-client-secret"
    # stage é read-only no OCI provider >= 6.0 — não incluir
  }
}

# Secret — GitHub PAT para acesso ao repositorio gitops-setup
resource "oci_vault_secret" "gitops_repo_pat" {
  compartment_id = var.compartment_ocid
  vault_id       = oci_kms_vault.main.id
  key_id         = oci_kms_key.master.id
  secret_name    = "gitops-repo-pat"
  freeform_tags  = var.freeform_tags

  secret_content {
    content_type = "BASE64"
    content      = base64encode(var.gitops_repo_pat)
    name         = "gitops-repo-pat"
    # stage é read-only no OCI provider >= 6.0 — não incluir
  }
}
