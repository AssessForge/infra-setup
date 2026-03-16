# Policy 1: deny-all baseline no namespace argocd
resource "kubectl_manifest" "deny_all_default" {
  yaml_body = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: deny-all-default
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector: {}
      policyTypes:
        - Ingress
        - Egress
  YAML
}

# Policy 2: redis lockdown — ingress 6379 apenas dos componentes argocd necessários
resource "kubectl_manifest" "argocd_redis_lockdown" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-redis-lockdown
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: redis
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector:
                matchLabels:
                  app.kubernetes.io/component: server
            - podSelector:
                matchLabels:
                  app.kubernetes.io/component: application-controller
            - podSelector:
                matchLabels:
                  app.kubernetes.io/component: repo-server
          ports:
            - protocol: TCP
              port: 6379
  YAML
}

# Policy 3: argocd-server-ingress — apenas do namespace ingress-nginx
resource "kubectl_manifest" "argocd_server_ingress" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-server-ingress
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: server
      policyTypes:
        - Ingress
      ingress:
        - from:
            - namespaceSelector:
                matchLabels:
                  kubernetes.io/metadata.name: ingress-nginx
          ports:
            - protocol: TCP
              port: 8080
            - protocol: TCP
              port: 8083
  YAML
}

# Policy 4: repo-server — ingress somente de dentro do namespace argocd
resource "kubectl_manifest" "argocd_internal_only_repo_server" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-internal-repo-server
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: repo-server
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector: {}
  YAML
}

resource "kubectl_manifest" "argocd_internal_only_app_controller" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-internal-app-controller
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: application-controller
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector: {}
  YAML
}

resource "kubectl_manifest" "argocd_internal_only_dex" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-internal-dex
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchLabels:
          app.kubernetes.io/component: dex
      policyTypes:
        - Ingress
      ingress:
        - from:
            - podSelector: {}
  YAML
}

# Egress para componentes ArgoCD (exceto Redis) — DNS + HTTPS apenas
resource "kubectl_manifest" "argocd_egress_dns_https" {
  depends_on = [kubectl_manifest.deny_all_default]
  yaml_body  = <<-YAML
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: argocd-egress-dns-https
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      podSelector:
        matchExpressions:
          - key: app.kubernetes.io/component
            operator: NotIn
            values: [redis]
      policyTypes:
        - Egress
      egress:
        - ports:
            - protocol: UDP
              port: 53
            - protocol: TCP
              port: 53
        - ports:
            - protocol: TCP
              port: 443
  YAML
}

# Redis não precisa de egress (cache in-cluster — bloqueado pelo deny-all-default)
# Sem resource adicional: a ausência de regra de egress para redis é intencional.
