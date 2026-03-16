resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  version          = "0.9.20"

  # helm 3.x: set block → list of nested objects
  set = [
    {
      name  = "installCRDs"
      value = "true"
    },
  ]

  wait    = true
  timeout = 300
}

resource "kubectl_manifest" "cluster_secret_store" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ClusterSecretStore
    metadata:
      name: oci-vault-store
    spec:
      conditions:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: argocd
      provider:
        oracle:
          vault: "${var.vault_ocid}"
          region: "${var.region}"
          auth:
            workload:
              serviceAccountRef:
                name: external-secrets
                namespace: external-secrets
  YAML

  depends_on = [helm_release.external_secrets]
}

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "pod-security.kubernetes.io/enforce" = "restricted"
      "app.kubernetes.io/managed-by"       = "terraform"
    }
  }
}

resource "kubectl_manifest" "argocd_dex_external_secret" {
  yaml_body = <<-YAML
    apiVersion: external-secrets.io/v1beta1
    kind: ExternalSecret
    metadata:
      name: argocd-dex-github-secret
      namespace: argocd
    spec:
      refreshInterval: "1h"
      secretStoreRef:
        name: oci-vault-store
        kind: ClusterSecretStore
      target:
        name: argocd-dex-github-secret
        creationPolicy: Owner
      data:
        - secretKey: dex.github.clientID
          remoteRef:
            key: github-oauth-client-id
        - secretKey: dex.github.clientSecret
          remoteRef:
            key: github-oauth-client-secret
  YAML

  depends_on = [
    kubectl_manifest.cluster_secret_store,
    kubernetes_namespace_v1.argocd,
  ]
}
