output "argocd_namespace" {
  description = "Namespace argocd criado pelo módulo external-secrets"
  value       = kubernetes_namespace_v1.argocd.metadata[0].name
}
