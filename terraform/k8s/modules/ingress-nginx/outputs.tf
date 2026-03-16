data "kubernetes_service_v1" "ingress_lb" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = "ingress-nginx"
  }

  depends_on = [helm_release.ingress_nginx]
}

output "release_status" {
  description = "Status do Helm release do ingress-nginx"
  value       = helm_release.ingress_nginx.status
}

output "lb_ip" {
  description = "IP público do Load Balancer do ingress-nginx"
  value       = try(data.kubernetes_service_v1.ingress_lb.status[0].load_balancer[0].ingress[0].ip, "pending")
}
