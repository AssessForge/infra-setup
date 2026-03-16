output "argocd_namespace" {
  description = "Namespace do ArgoCD"
  value       = module.argocd.argocd_namespace
}

output "argocd_hostname" {
  description = "Hostname configurado no Ingress do ArgoCD"
  value       = module.argocd.argocd_ingress_host
}

output "ingress_lb_ip" {
  description = "IP público do Load Balancer do ingress-nginx (use para configurar DNS no Cloudflare)"
  value       = module.ingress_nginx.lb_ip
}

output "ingress_lb_ip_command" {
  description = "Comando alternativo para obter o IP do LB caso o output acima mostre 'pending'"
  value       = "kubectl get svc -n ingress-nginx ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
