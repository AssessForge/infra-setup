locals {
  excluded_namespaces = [
    "kube-system",
    "kyverno",
    "longhorn-system",
    "external-secrets",
    "argocd",
    "ingress-nginx",
  ]
}

resource "helm_release" "kyverno" {
  name             = "kyverno"
  repository       = "https://kyverno.github.io/kyverno"
  chart            = "kyverno"
  namespace        = "kyverno"
  create_namespace = true
  version          = "3.2.6"

  # helm 3.x: set block → list of nested objects
  set = [
    {
      name  = "replicaCount"
      value = "1"
    },
  ]

  wait    = true
  timeout = 300
}

resource "kubectl_manifest" "policy_disallow_root_containers" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-root-containers
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-runAsNonRoot
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Containers devem rodar como non-root (runAsNonRoot: true)"
            pattern:
              spec:
                containers:
                  - securityContext:
                      runAsNonRoot: true
                initContainers:
                  - securityContext:
                      runAsNonRoot: true
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_disallow_privilege_escalation" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-privilege-escalation
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-privilege-escalation
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "allowPrivilegeEscalation deve ser false"
            pattern:
              spec:
                containers:
                  - securityContext:
                      allowPrivilegeEscalation: false
                initContainers:
                  - securityContext:
                      allowPrivilegeEscalation: false
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_require_readonly_rootfs" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-readonly-rootfs
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-readOnlyRootFilesystem
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "readOnlyRootFilesystem deve ser true"
            pattern:
              spec:
                containers:
                  - securityContext:
                      readOnlyRootFilesystem: true
                initContainers:
                  - securityContext:
                      readOnlyRootFilesystem: true
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_disallow_latest_tag" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: disallow-latest-tag
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-image-tag
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Imagens não devem usar a tag ':latest'"
            foreach:
              - list: "request.object.spec.containers"
                deny:
                  conditions:
                    any:
                      - key: "{{element.image}}"
                        operator: Equals
                        value: "*:latest"
                      - key: "{{element.image}}"
                        operator: NotContains
                        value: ":"
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_require_resource_limits" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-resource-limits
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-resource-limits
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Todos os containers devem ter resources.limits.cpu e resources.limits.memory definidos"
            pattern:
              spec:
                containers:
                  - resources:
                      limits:
                        cpu: "?*"
                        memory: "?*"
                initContainers:
                  - resources:
                      limits:
                        cpu: "?*"
                        memory: "?*"
  YAML

  depends_on = [helm_release.kyverno]
}

resource "kubectl_manifest" "policy_require_seccomp" {
  yaml_body = <<-YAML
    apiVersion: kyverno.io/v1
    kind: ClusterPolicy
    metadata:
      name: require-seccomp-profile
      annotations:
        app.kubernetes.io/managed-by: terraform
    spec:
      validationFailureAction: Enforce
      background: true
      rules:
        - name: check-seccomp
          match:
            any:
              - resources:
                  kinds: ["Pod"]
          exclude:
            any:
              - resources:
                  namespaces: ${jsonencode(local.excluded_namespaces)}
          validate:
            message: "Pods devem definir seccompProfile RuntimeDefault ou Localhost"
            pattern:
              spec:
                securityContext:
                  seccompProfile:
                    type: "RuntimeDefault | Localhost"
  YAML

  depends_on = [helm_release.kyverno]
}
