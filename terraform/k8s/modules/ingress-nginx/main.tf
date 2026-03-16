resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.10.1"

  # helm 3.x: set blocks → list of nested objects
  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape"
      value = "flexible"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape-flex-min"
      value = "10"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/oci-load-balancer-shape-flex-max"
      value = "10"
    },
    {
      name  = "controller.resources.requests.cpu"
      value = "100m"
    },
    {
      name  = "controller.resources.requests.memory"
      value = "128Mi"
    },
    {
      name  = "controller.resources.limits.cpu"
      value = "500m"
    },
    {
      name  = "controller.resources.limits.memory"
      value = "512Mi"
    },
  ]

  wait    = true
  timeout = 300
}
