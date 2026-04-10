# Stack Research

**Domain:** GitOps Bridge Pattern on OCI/OKE
**Researched:** 2026-04-09
**Confidence:** HIGH (all versions verified against official releases/docs)

---

## Context

This milestone adds the GitOps Bridge Pattern on top of existing OCI infrastructure
(VCN, OKE BASIC cluster on ARM, Vault, Cloud Guard). Terraform's scope narrows to OCI
resource provisioning + a one-time ArgoCD bootstrap. Everything in-cluster moves to a
new GitOps repo managed by ArgoCD.

Current `terraform/k8s/` layer is destroyed and not migrated — a clean break.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| ArgoCD (Helm chart `argo-cd`) | **9.5.0** (app v3.3.6) | GitOps controller, self-managed, ApplicationSet | Latest stable on argo-helm; v3.x line is current major — v2.x receives only patches. ApplicationSet controller is built-in since v2.3, no separate install. |
| External Secrets Operator (Helm `external-secrets`) | **2.2.0** | Pull secrets from OCI Vault into Kubernetes Secrets | Native OCI Vault provider with Workload Identity support — no static credentials needed. Latest stable as of March 2026. |
| cert-manager (Helm `cert-manager`) | **1.20.1** | TLS certificate issuance/renewal (ACME via Cloudflare DNS) | Latest stable (March 2026). Supports Kubernetes 1.32–1.35, covering all OKE versions currently available. v1.20 is the recommended version over v1.17 LTS for new deployments. |
| Traefik (Helm `traefik`) | **39.0.7** (app v3.6.12) | Ingress controller with OCI Load Balancer integration | ingress-nginx was archived March 24, 2026 — no further security patches. Traefik v3 is the only drop-in replacement with native ingress-nginx annotation compatibility, actively maintained, and documented for OKE. |
| metrics-server (Helm `metrics-server`) | **3.13.0** (app v0.8.0) | HPA/VPA resource metrics pipeline | Official kubernetes-sigs chart; 3.13.0 is latest Helm chart release. Required for HPA to function. Stateless — trivial to operate. |
| `terraform-helm-gitops-bridge` Terraform module | **0.0.2** | Creates ArgoCD cluster secret with bridge annotations | Official gitops-bridge-dev module. Writes infra metadata (compartment OCID, subnet IDs, vault OCID, region, env flags) as annotations on the ArgoCD in-cluster secret. ApplicationSet reads these annotations via cluster generator. |

### Terraform Providers (infra bootstrap layer additions)

| Provider | Version Constraint | Purpose | Why |
|----------|--------------------|---------|-----|
| `hashicorp/helm` | `~> 3.0` | Deploy ArgoCD via `helm_release` (bootstrap only) | Already used in old k8s layer — keep same constraint. Bootstrap installs minimal ArgoCD; GitOps takes over immediately after. |
| `hashicorp/kubernetes` | `~> 3.0` | Create namespace + bridge secret | Needed to write the GitOps bridge cluster secret manifest. |
| `oracle/oci` | `~> 8.0` | OCI Dynamic Group + IAM Policy for ArgoCD Workload Identity | Already present in infra layer; extend with new policy resources. |

### Helm Repositories

| Chart | Repository URL | Notes |
|-------|---------------|-------|
| `argo-cd` | `https://argoproj.github.io/argo-helm` | Official ArgoProj Helm repo |
| `external-secrets` | `https://charts.external-secrets.io` | Official ESO Helm repo |
| `cert-manager` | `https://charts.jetstack.io` OR `oci://quay.io/jetstack/charts/cert-manager` | OCI registry is now recommended source of truth for recent versions |
| `traefik` | `https://traefik.github.io/charts` | Official Traefik Helm repo |
| `metrics-server` | `https://kubernetes-sigs.github.io/metrics-server/` | Official kubernetes-sigs Helm repo |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `terraform` >= 1.5.0 | Bootstrap provisioning | Keep existing constraint; no upgrade needed |
| `helm` >= 3.x | Local chart introspection, testing values | Not used by CI but needed for local dry-runs |
| `kubectl` | Verify cluster post-bootstrap | Already in use for kubeconfig verification |
| `oci` CLI | Kubeconfig generation, namespace lookup | Already required by existing setup |
| `argocd` CLI | Validate ArgoCD state post-bootstrap | Optional but useful for troubleshooting sync status |

---

## Installation

```bash
# No npm/pip — this is a Terraform + Helm stack.
# All charts are deployed via ArgoCD Applications in the gitops-setup repo.

# Bootstrap only (Terraform deploys ArgoCD, then hands off):
cd terraform/infra/
terraform apply  # creates OCI resources + Dynamic Group + IAM Policy

# Then bootstrap ArgoCD and bridge secret:
cd terraform/bootstrap/   # new module
terraform apply            # helm_release ArgoCD + kubernetes_secret bridge secret

# After bootstrap, ALL subsequent changes go through gitops-setup repo (PRs only).
```

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Traefik v39.0.7 | ingress-nginx 4.15.1 | **Do not use** — archived March 2026, no security patches. Only acceptable if you are migrating away from it before any production traffic. |
| Traefik v39.0.7 | OCI Native Ingress Controller v1.4.2 | Use if you want OCI Load Balancer native features (WAF policy, certificate service, reserved IPs without service annotations). Adds Oracle-specific operational overhead and an OCI-native CRD model — not a drop-in for existing Ingress manifests. For this project scope (ArgoCD at `argocd.assessforge.com` with Cloudflare DNS), Traefik is simpler. |
| Traefik v39.0.7 | Traefik Hub | Traefik Hub adds API management/observability on top. Overkill for single-service ingress — defer to future milestone if multi-service API gateway is needed. |
| ArgoCD 9.5.0 (v3.3.6) | ArgoCD 7.x (v2.14.x) | Use v2.14.x only if you have an existing v2 cluster with breaking-change incompatibilities to resolve. For a fresh GitOps setup (this project destroys the k8s layer), start on v3 — it receives active features and bug fixes. |
| ESO 2.2.0 | Secrets Store CSI Driver + OCI provider | Use CSI driver if you need volume-mounted secrets or strict process-level isolation. ESO with ClusterSecretStore is simpler for the pattern here (ArgoCD reads ExternalSecrets, gets Kubernetes Secrets). |
| cert-manager 1.20.1 | cert-manager 1.17.0 (previous LTS) | 1.17 is still supported until 1.19's +2 cycle ends. 1.20 supports the same Kubernetes versions as 1.17 for OKE and has a year of forward support. No reason to choose 1.17 for a new deployment. |
| `terraform-helm-gitops-bridge` 0.0.2 | Manual `kubernetes_secret` resource | Manual is fine if the bridge module is too opinionated. The module wraps helm_release (ArgoCD) + cluster secret creation. You can replicate this with raw provider resources for more control — this project's bootstrap is simple enough that either works. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `kubernetes/ingress-nginx` (any version) | Repository archived March 24, 2026. No further security patches will be issued. Using it in new infrastructure is technical debt from day one. | Traefik v39.0.7 (drop-in replacement) or OCI Native Ingress Controller |
| Static OCI API keys in Kubernetes Secrets | Any compromise of the secret exposes long-lived credentials. OCI Workload Identity grants the same permissions with no credential material stored anywhere. | OCI Workload Identity via OKE's OIDC token injection — configure `principalType: Workload` in ESO ClusterSecretStore |
| ArgoCD `latest` or open version ranges | Causes unpredictable upgrades during `helm upgrade` or ArgoCD App sync. Breaking changes in v3.x (e.g., applicationset schema changes in 3.4) can break in production unannounced. | Pin all Helm chart versions in gitops-setup; upgrade via PR |
| `terraform-helm-gitops-bridge` v0.0.2 from archived repo | The original `gitops-bridge-argocd-bootstrap-terraform` repo is archived. `terraform-helm-gitops-bridge` (v0.0.2, Dec 2023) is current but sees minimal activity — treat it as reference, not a dependency. | Use its pattern directly: `helm_release` for ArgoCD + `kubernetes_secret` for bridge secret with annotations |
| ArgoCD `installCRDs: true` with auto-upgrade | CRD upgrades during Helm upgrade can cause data loss on ApplicationSet resources if schema changes are breaking. | Manage CRDs separately or use `--skip-crds` during ArgoCD self-managed upgrades (ArgoCD manages its own CRDs via GitOps Application) |
| GitOps Bridge Pattern secret in non-argocd namespace | ApplicationSet cluster generator reads annotations from the in-cluster secret in the `argocd` namespace specifically. Other namespaces will not be discovered. | Always create the bridge secret in namespace `argocd` |

---

## OCI-Specific Configuration Details

### GitOps Bridge Secret Structure

The bridge secret must be created in namespace `argocd` with label `argocd.argoproj.io/secret-type: cluster` and a `server: https://kubernetes.default.svc` entry. Annotations carry the infra metadata:

```yaml
annotations:
  argocd.argoproj.io/cluster-name: assessforge-oke
  environment: production
  region: sa-saopaulo-1
  compartment_id: <compartment-ocid>
  vcn_id: <vcn-ocid>
  private_subnet_id: <subnet-ocid>
  vault_id: <vault-ocid>
  # Feature flags for ApplicationSet conditional addon rendering:
  addons_ingress_nginx: "false"     # retired
  addons_traefik: "true"
  addons_cert_manager: "true"
  addons_external_secrets: "true"
  addons_metrics_server: "true"
```

### ESO ClusterSecretStore for OCI Vault (Workload Identity)

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: oci-vault
spec:
  provider:
    oracle:
      vault: <vault-ocid>      # from bridge secret annotation
      region: sa-saopaulo-1
      principalType: Workload
      serviceAccountRef:
        name: external-secrets
        namespace: external-secrets
```

The ESO pod's service account must have an OCI IAM policy allowing `secret-family` read in the vault's compartment. Use Dynamic Group matching OKE workload identity tokens.

### Traefik OCI Load Balancer Service Annotations

When Traefik creates a `Service` of type `LoadBalancer`, OKE provisions an OCI Load Balancer. Control it with:

```yaml
service:
  annotations:
    oci.oraclecloud.com/load-balancer-type: "lb"           # or "nlb" for Network LB
    oci.oraclecloud.com/security-rule-management-mode: "NSG"
    # Optional — pin to reserved IP:
    oci.oraclecloud.com/reserved-ips: "[{\"ip\":\"<reserved-ip>\"}]"
    # Optional — place LB in specific compartment:
    oci.oraclecloud.com/compartment-id: "<compartment-ocid>"
```

---

## Version Compatibility

| Component | Kubernetes Compatibility | Notes |
|-----------|--------------------------|-------|
| cert-manager 1.20.1 | K8s 1.32–1.35 | OKE currently offers 1.32, 1.33, 1.34 (1.35 in preview) — all covered |
| ArgoCD 9.5.0 (v3.3.6) | K8s 1.28+ | No issues with OKE 1.32+ |
| ESO 2.2.0 | K8s 1.25+ | OCI Vault Workload Identity requires OKE with OIDC token projection enabled (default on OKE BASIC) |
| Traefik 39.0.7 (v3.6.12) | K8s 1.22+ | OKE BASIC on ARM fully supported |
| metrics-server 3.13.0 (v0.8.0) | K8s 1.19+ | OKE BASIC: requires `--kubelet-insecure-tls` or cert verification — use `args: [--kubelet-preferred-address-types=InternalIP]` on private node pools |

---

## Stack Patterns by Variant

**For the ArgoCD bootstrap Terraform module (new `terraform/bootstrap/`):**
- Use `helm_release` resource directly (not `terraform-helm-gitops-bridge` module — it's minimally maintained)
- Set `values` to minimal ArgoCD config: ClusterIP server, no SSO, no repo credentials
- Create bridge secret via `kubernetes_secret` with correct labels and annotations
- Create root bootstrap `Application` resource pointing to gitops-setup repo

**For ArgoCD self-management in gitops-setup repo:**
- Create an `Application` named `argocd` that targets `argo-cd` Helm chart version 9.5.0
- Set `syncPolicy.syncOptions: [ServerSideApply=true]` — required for CRD management in v3
- Use `ignoreDifferences` for `argocd-cm` and `argocd-secret` to prevent sync loops on generated fields

**For ApplicationSet reading bridge annotations:**
- Use `cluster` generator (not `git` generator) — reads from the in-cluster ArgoCD cluster secret directly
- Reference annotations via `{{metadata.annotations.vault_id}}` syntax in Helm values

**If OKE ARM nodes reject metrics-server:**
- Add `args: ["--kubelet-preferred-address-types=InternalIP", "--kubelet-insecure-tls"]` to metrics-server Helm values — private OKE clusters route kubelet traffic over internal IPs and may not present certs that metrics-server can verify without this flag

---

## Sources

- [argo-helm releases (GitHub)](https://github.com/argoproj/argo-helm/releases) — ArgoCD Helm chart 9.5.0, app v3.3.6 confirmed April 2026 (HIGH confidence)
- [argo-cd app releases (GitHub)](https://github.com/argoproj/argo-cd/releases) — v3.3.6 latest stable March 2026 (HIGH confidence)
- [external-secrets releases (GitHub)](https://github.com/external-secrets/external-secrets/releases) — v2.2.0 / chart 2.2.0 March 2026 (HIGH confidence)
- [external-secrets OCI Vault docs](https://external-secrets.io/latest/provider/oracle-vault/) — Workload Identity configuration (HIGH confidence)
- [cert-manager supported releases](https://cert-manager.io/docs/releases/) — 1.20.1 latest stable, K8s 1.32–1.35 (HIGH confidence)
- [ingress-nginx retirement blog (Kubernetes.io)](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/) — retirement announced November 2025 (HIGH confidence)
- [ingress-nginx repository (GitHub)](https://github.com/kubernetes/ingress-nginx) — archived March 24, 2026, last release controller-v1.15.1 (HIGH confidence)
- [traefik-helm-chart releases (GitHub)](https://github.com/traefik/traefik-helm-chart/releases) — v39.0.7 / Traefik v3.6.12, March 2026 (HIGH confidence)
- [metrics-server releases (GitHub)](https://github.com/kubernetes-sigs/metrics-server/releases) — chart 3.13.0 / app v0.8.0 (HIGH confidence)
- [OCI load balancer annotation docs](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingloadbalancers-subtopic.htm) — `oci.oraclecloud.com/` annotation prefix (HIGH confidence)
- [OCI Native Ingress Controller (GitHub)](https://github.com/oracle/oci-native-ingress-controller) — v1.4.2 April 2025, alternative to Traefik for OCI-native routing (MEDIUM confidence)
- [terraform-helm-gitops-bridge (GitHub)](https://github.com/gitops-bridge-dev/terraform-helm-gitops-bridge) — v0.0.2, reference implementation (MEDIUM confidence — minimally maintained)
- [OKE Kubernetes version support](https://docs.oracle.com/en-us/iaas/Content/ContEng/Concepts/contengaboutk8sversions.htm) — 1.32, 1.33, 1.34 available; 1.35 in preview (MEDIUM confidence — exact SA-Sao Paulo regional availability not confirmed)

---

*Stack research for: GitOps Bridge Pattern on OCI/OKE*
*Researched: 2026-04-09*
