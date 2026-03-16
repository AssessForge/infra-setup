output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = "argocd"
}

output "argocd_ingress_host" {
  description = "Hostname configurado no Ingress do ArgoCD"
  value       = var.argocd_hostname
}
