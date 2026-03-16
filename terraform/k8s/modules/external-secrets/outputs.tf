output "argocd_namespace" {
  description = "Namespace argocd criado pelo módulo external-secrets"
  value       = kubernetes_namespace.argocd.metadata[0].name
}
