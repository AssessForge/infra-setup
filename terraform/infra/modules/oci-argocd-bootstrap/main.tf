terraform {
  required_providers {
    kubectl = {
      source = "alekc/kubectl"
    }
  }
}

# --- ArgoCD via Helm (bootstrap minimo) ---

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "9.5.0" # PINNED — app v3.3.6
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      server = {
        service = { type = "ClusterIP" }
        # TLS terminado no Envoy Gateway (Phase 3)
        extraArgs = ["--insecure"]
      }
      configs = {
        params = {
          # Desabilita exec por seguranca
          "server.exec.enabled" = "false"
        }
      }
    })
  ]

  # ArgoCD gerencia seus proprios valores apos bootstrap — ignorar mudancas de values
  # para evitar conflito com self-management. Para upgrade de versao, fazer taint manual.
  lifecycle {
    ignore_changes = [values]
  }
}

# --- GitOps Bridge Secret ---

resource "kubernetes_secret_v1" "gitops_bridge" {
  metadata {
    name      = "in-cluster"
    namespace = helm_release.argocd.namespace

    labels = {
      # Requerido pelo ArgoCD cluster generator
      "argocd.argoproj.io/secret-type" = "cluster"

      # Metadata
      environment  = "prod"
      cluster_name = var.cluster_name

      # Feature flags para addon ApplicationSet (D-06)
      enable_argocd         = "true"
      enable_eso            = "true"
      enable_envoy_gateway  = "true"
      enable_cert_manager   = "true"
      enable_metrics_server = "true"
    }

    annotations = {
      # Routing do repositorio GitOps (D-07)
      addons_repo_url      = var.gitops_repo_url
      addons_repo_revision = var.gitops_repo_revision

      # Metadata OCI para Helm values dos addons (D-05)
      oci_region            = var.region
      oci_compartment_ocid  = var.compartment_ocid
      oci_vault_ocid        = var.vault_ocid
      oci_public_subnet_id  = var.public_subnet_id
      oci_private_subnet_id = var.private_subnet_id
    }
  }

  # Campos obrigatorios para ArgoCD cluster secret
  data = {
    name   = "in-cluster"
    server = "https://kubernetes.default.svc"
    config = jsonencode({
      tlsClientConfig = { insecure = false }
    })
  }

  depends_on = [helm_release.argocd]
}

# --- ArgoCD Repo Credential (bootstrap seed) ---

# Secret de credencial de repositorio consumido pelo ArgoCD via label
# `argocd.argoproj.io/secret-type=repository`. Existe para quebrar o
# chicken-and-egg do bootstrap GitOps: o ExternalSecret que rotaciona esta
# PAT mora DENTRO do repo `gitops-setup`, mas o ArgoCD nao consegue sincronizar
# esse repo privado ate ter a credencial. Apos o primeiro sync, ESO assume a
# rotacao via OCI Vault e este secret vira apenas a semente inicial.
# username = "oauth2" e o padrao canonico do GitHub para PAT via HTTPS.
resource "kubernetes_secret_v1" "gitops_repo_creds" {
  metadata {
    name      = "gitops-setup-repo"
    namespace = helm_release.argocd.namespace

    labels = {
      # Requerido pelo ArgoCD para descobrir secrets de repositorio
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  type = "Opaque"

  # O provider hashicorp/kubernetes auto-encoda base64 ao enviar para a API.
  data = {
    type     = "git"
    url      = var.gitops_repo_url
    username = "oauth2"
    password = var.gitops_repo_pat
  }

  # ArgoCD pode adicionar annotations de runtime neste secret — ignorar
  # para evitar drift perpetuo em terraform plan.
  lifecycle {
    ignore_changes = [metadata[0].annotations]
  }

  depends_on = [helm_release.argocd]
}

# --- ESO OCI API-Key Credentials (workaround bug IDCS matching-rule) ---
#
# Seeds o Secret que o ClusterSecretStore `oci-vault` consome para autenticar
# no OCI Vault via UserPrincipal. Enquanto o bug IDCS (ver memoria do projeto
# `project_oci_drg_matching_rule_bug.md`) impedir Instance Principal, esse
# Secret eh a unica via de autenticacao do ESO na OCI.
#
# Namespace: argocd (nao external-secrets) porque:
# - bootstrap do Terraform nao gerencia o namespace external-secrets (criado
#   pelo Helm chart do ESO via ArgoCD)
# - ClusterSecretStore.secretRef aceita namespace explicito, entao isso eh ok
#
# Campos que o ClusterSecretStore espera ao referenciar: privateKey + fingerprint.
# tenancy + user ficam inline no ClusterSecretStore YAML (nao no Secret).
resource "kubernetes_secret_v1" "eso_oci_credentials" {
  metadata {
    name      = "eso-oci-credentials"
    namespace = helm_release.argocd.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "eso-auth"
    }
  }

  type = "Opaque"

  # hashicorp/kubernetes 3.x expoe somente `data` (auto-base64 no envio).
  # Passamos PEM e fingerprint como strings normais -- o provider codifica.
  data = {
    privateKey  = var.eso_api_key_private_key_pem
    fingerprint = var.eso_api_key_fingerprint
  }

  depends_on = [helm_release.argocd]
}

# --- Root Bootstrap Application ---

resource "kubectl_manifest" "bootstrap_app" {
  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name       = "bootstrap"
      namespace  = "argocd"
      finalizers = ["resources-finalizer.argocd.argoproj.io"]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_revision
        path           = "bootstrap/control-plane"
        # Bootstrap sincroniza APENAS:
        # 1. O ApplicationSet cluster-addons -- faz o fan-out dos addons
        #    gerando Apps addon-<name> que sincronizam addons/<name>/ inteiro
        # 2. A Application argocd/ -- self-manage, nao entra no AppSet
        #    porque esta fora do path addons/*
        # NAO incluir addons/<name>/application.yaml diretamente: eles sao
        # sincronizados pelo proprio AppSet (via nested app-of-apps), e incluir
        # aqui causaria duplicacao (App "<name>" criado pelo bootstrap +
        # "<name>" criado por addon-<name>, mesmo recurso, dois donos).
        directory = {
          recurse = true
          include = "{argocd/application.yaml,addons/cluster-addons-appset.yaml}"
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          # prune = false no root app — evita destruicao acidental durante bootstrap.
          # Child ApplicationSets devem configurar prune = true individualmente.
          prune    = false
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true", "ServerSideApply=true"]
      }
    }
  })

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.gitops_bridge,
  ]
}
