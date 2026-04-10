output "argocd_namespace" {
  description = "Namespace onde ArgoCD foi instalado"
  value       = helm_release.argocd.namespace
}
