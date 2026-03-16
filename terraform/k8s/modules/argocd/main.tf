resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  version          = "7.6.12"
  create_namespace = false

  wait    = true
  timeout = 600

  values = [
    yamlencode({
      global = {
        securityContext = {
          runAsNonRoot   = true
          runAsUser      = 999
          fsGroup        = 999
          seccompProfile = { type = "RuntimeDefault" }
        }
      }

      controller = {
        resources = {
          requests = { cpu = "250m", memory = "512Mi" }
          limits   = { cpu = "1", memory = "2Gi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      server = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "500m", memory = "256Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
        extraArgs = ["--insecure"]
      }

      repoServer = {
        resources = {
          requests = { cpu = "200m", memory = "256Mi" }
          limits   = { cpu = "1", memory = "1Gi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      dex = {
        resources = {
          requests = { cpu = "50m", memory = "64Mi" }
          limits   = { cpu = "100m", memory = "128Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      redis = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "250m", memory = "256Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      applicationSet = {
        resources = {
          requests = { cpu = "100m", memory = "128Mi" }
          limits   = { cpu = "250m", memory = "256Mi" }
        }
        containerSecurityContext = {
          runAsNonRoot             = true
          runAsUser                = 999
          readOnlyRootFilesystem   = true
          allowPrivilegeEscalation = false
          capabilities             = { drop = ["ALL"] }
        }
      }

      configs = {
        cm = {
          "url"                     = "https://${var.argocd_hostname}"
          "admin.enabled"           = "false"
          "users.anonymous.enabled" = "false"
          "exec.enabled"            = "false"
          "dex.config"              = <<-EOT
            connectors:
              - type: github
                id: github
                name: GitHub
                config:
                  clientID: $argocd-dex-github-secret:dex.github.clientID
                  clientSecret: $argocd-dex-github-secret:dex.github.clientSecret
                  orgs:
                    - name: ${var.github_org}
                  scopes:
                    - read:org
          EOT
        }

        rbac = {
          "policy.default" = "role:''"
          "scopes"         = "[groups, email]"
          "policy.csv"     = <<-EOT
            g, ${var.github_org}, role:admin
          EOT
        }

        params = {
          "server.login.attempts.max"   = "5"
          "server.login.attempts.reset" = "300"
          "server.log.level"            = "info"
          "server.log.format"           = "json"
          "controller.log.level"        = "info"
          "controller.log.format"       = "json"
          "reposerver.log.level"        = "info"
          "reposerver.log.format"       = "json"
        }
      }
    })
  ]
}

resource "kubernetes_ingress_v1" "argocd" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
    annotations = {
      "nginx.ingress.kubernetes.io/ssl-redirect"     = "false"
      "nginx.ingress.kubernetes.io/backend-protocol" = "HTTP"
    }
  }

  spec {
    ingress_class_name = "nginx"

    rule {
      host = var.argocd_hostname

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = "argocd-server"
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [helm_release.argocd]
}

# AppProject com restrições de RBAC para workloads de aplicação
resource "kubectl_manifest" "argocd_appproject" {
  yaml_body = <<-YAML
    apiVersion: argoproj.io/v1alpha1
    kind: AppProject
    metadata:
      name: assessforge
      namespace: argocd
      labels:
        app.kubernetes.io/managed-by: terraform
    spec:
      description: "Project para workloads de aplicação — bloqueia criação de RBAC cluster-wide"
      sourceRepos:
        - '*'
      destinations:
        - namespace: '*'
          server: 'https://kubernetes.default.svc'
      clusterResourceBlacklist:
        - group: 'rbac.authorization.k8s.io'
          kind: ClusterRole
        - group: 'rbac.authorization.k8s.io'
          kind: ClusterRoleBinding
        - group: ''
          kind: Node
        - group: 'scheduling.k8s.io'
          kind: PriorityClass
      namespaceResourceBlacklist:
        - group: ''
          kind: ResourceQuota
  YAML

  depends_on = [helm_release.argocd]
}
