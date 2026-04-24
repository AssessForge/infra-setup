---
phase: quick-260424-2vo
plan: 01
subsystem: infra/argocd-bootstrap
tags:
  - terraform
  - argocd
  - gitops
  - bootstrap
  - kubernetes-secret
dependency_graph:
  requires:
    - terraform/infra/variables.tf (var.gitops_repo_pat already declared at root)
    - terraform/infra/modules/oci-argocd-bootstrap/main.tf (helm_release.argocd for namespace)
  provides:
    - kubernetes_secret_v1.gitops_repo_creds (ArgoCD repo credential)
    - module-level var.gitops_repo_pat in oci-argocd-bootstrap
  affects:
    - ArgoCD root bootstrap Application sync capability
tech-stack:
  added: []
  patterns:
    - ArgoCD repository secret convention (label argocd.argoproj.io/secret-type=repository)
    - Bootstrap-seed pattern (Terraform seeds, ESO rotates post first-sync)
key-files:
  created:
    - .planning/quick/260424-2vo-adicionar-kubernetes-secret-v1-de-creden/260424-2vo-SUMMARY.md
  modified:
    - terraform/infra/modules/oci-argocd-bootstrap/variables.tf
    - terraform/infra/modules/oci-argocd-bootstrap/main.tf
    - terraform/infra/main.tf
    - docs/runbooks/cloud-shell-first-apply.md
decisions:
  - Use kubernetes_secret_v1 (native provider) instead of kubectl_manifest to keep typed handling and sensitive-field treatment
  - string_data over base64-encoded data (provider handles encoding; Terraform state still protects the field)
  - lifecycle.ignore_changes on metadata[0].annotations to prevent drift from ArgoCD runtime annotations
  - Bootstrap-seed approach (Terraform creates the Secret; ESO takes over rotation once gitops-setup AppSet installs it)
metrics:
  completed: 2026-04-23
  tasks: 1
  files_modified: 4
---

# Quick 260424-2vo: Add ArgoCD Repo Credential Secret for Private gitops-setup

**One-liner:** Seed Kubernetes Secret `gitops-setup-repo` in the argocd namespace so the `bootstrap` ArgoCD Application can authenticate against the private `gitops-setup` GitHub repo via PAT, closing the GitOps chicken-and-egg bootstrap gap.

## Files Modified

1. **`terraform/infra/modules/oci-argocd-bootstrap/variables.tf`** — Added sensitive module variable `gitops_repo_pat` (no default, type=string).
2. **`terraform/infra/modules/oci-argocd-bootstrap/main.tf`** — Added `resource "kubernetes_secret_v1" "gitops_repo_creds"` with the ArgoCD repository-secret label convention, `string_data` fields (type/url/username/password), `depends_on = [helm_release.argocd]`, and `lifecycle.ignore_changes = [metadata[0].annotations]`.
3. **`terraform/infra/main.tf`** — Wired root-level `var.gitops_repo_pat` passthrough into the `oci_argocd_bootstrap` module block.
4. **`docs/runbooks/cloud-shell-first-apply.md`** — Appended "Validacao pos-apply: credencial do repositorio GitOps" subsection to Passo 7 with verification `kubectl get secret` command and optional force-sync `kubectl patch application` command.

## Block Inserted into `oci-argocd-bootstrap/main.tf`

```hcl
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

  string_data = {
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
```

## Operator Post-Apply Checklist

1. Run `terraform apply` at `terraform/infra/` (Cloud Shell path per runbook).
2. Wait ~3 minutes for ArgoCD auto-retry on the `bootstrap` Application, OR force immediate resync:
   ```bash
   kubectl patch application bootstrap -n argocd --type=merge \
     -p '{"operation":{"sync":{}}}'
   ```
3. Verify the secret landed with the correct label:
   ```bash
   kubectl get secret gitops-setup-repo -n argocd \
     -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/secret-type}'
   # Expected: repository
   ```

## Runbook Section Pointer

- `docs/runbooks/cloud-shell-first-apply.md` → section **"Validacao pos-apply: credencial do repositorio GitOps"** at the end of Passo 7 (immediately before Passo 8 — Teardown).

## Follow-up Note: ESO Takeover

Once the `gitops-setup` AppSet installs External Secrets Operator and its ExternalSecret for this PAT, the live PAT rotation flows via OCI Vault. The Terraform-managed `kubernetes_secret_v1.gitops_repo_creds` remains in state as an **idempotent seed** — no removal needed, and a future apply simply re-asserts the same value. If rotation through ESO later conflicts with Terraform's view of the secret, extend `lifecycle.ignore_changes` to include `string_data` so ESO can write without drift alerts.

## Deviations from Plan

None — plan executed exactly as written. All four file edits applied, `terraform fmt -recursive` produced no diff, and verification greps all returned expected matches.

## Deferred / Out-of-Scope Observations

- `terraform validate` and `terraform plan` were explicitly skipped (no credentials locally; operator-gated).
- Pre-existing uncommitted changes to `.gitignore`, `scripts/bastion-first-apply.sh`, and several infra modules (explicit OCI provider blocks — see project memory "Dirty WIP Provider Blocks") were deliberately NOT staged. Only the four plan-scoped files were added.

## Self-Check: PASSED

- `terraform/infra/modules/oci-argocd-bootstrap/variables.tf` — contains `variable "gitops_repo_pat"` at line 48.
- `terraform/infra/modules/oci-argocd-bootstrap/main.tf` — contains `resource "kubernetes_secret_v1" "gitops_repo_creds"` at line 102, with label `argocd.argoproj.io/secret-type = "repository"`.
- `terraform/infra/main.tf` — contains `gitops_repo_pat = var.gitops_repo_pat` at line 93 inside the `oci_argocd_bootstrap` module block.
- `docs/runbooks/cloud-shell-first-apply.md` — contains `gitops-setup-repo` reference inside Passo 7 validation subsection.
- `terraform fmt -recursive` produced zero output (no formatting drift).
