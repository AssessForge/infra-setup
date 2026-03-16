output "cluster_id" {
  description = "OCID do cluster OKE"
  value       = oci_containerengine_cluster.main.id
}

output "cluster_kubernetes_version" {
  description = "Versão do Kubernetes instalada"
  value       = oci_containerengine_cluster.main.kubernetes_version
}

output "bastion_ocid" {
  description = "OCID do Bastion"
  value       = oci_bastion_bastion.main.id
}

output "bastion_name" {
  description = "Nome do Bastion (o hostname de sessão segue o padrão: <session_ocid>@host.bastion.<region>.oci.oraclecloud.com)"
  value       = oci_bastion_bastion.main.name
}
