output "cluster_id" {
  description = "OCID do cluster OKE"
  value       = module.oci_oke.cluster_id
}

output "vault_ocid" {
  description = "OCID do OCI Vault"
  value       = module.oci_vault.vault_ocid
}

output "bastion_ocid" {
  description = "OCID do Bastion"
  value       = module.oci_oke.bastion_ocid
}

output "kubeconfig_command" {
  description = "Comando para gerar/atualizar o kubeconfig"
  value       = "oci ce cluster create-kubeconfig --cluster-id ${module.oci_oke.cluster_id} --file ~/.kube/config-assessforge --auth api_key --overwrite"
}

output "kubernetes_version" {
  description = "Versão do Kubernetes instalada"
  value       = module.oci_oke.cluster_kubernetes_version
}
