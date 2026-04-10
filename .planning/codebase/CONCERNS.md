# Codebase Concerns

**Analysis Date:** 2026-04-09

## Tech Debt

**PLACEHOLDER values in S3 backend endpoints:**
- Issue: Both `terraform/infra/versions.tf` (line 15) and `terraform/k8s/versions.tf` (line 27) contain `endpoint = "https://PLACEHOLDER.compat.objectstorage.sa-saopaulo-1.oraclecloud.com"`. These must be manually replaced with the OCI Object Storage namespace before `terraform init`. This is a manual setup step that could be forgotten or done inconsistently.
- Files: `terraform/infra/versions.tf`, `terraform/k8s/versions.tf`
- Impact: `terraform init` fails if PLACEHOLDERs are not replaced. No automated check validates this was done.
- Fix approach: Use a partial backend configuration file (`backend.hcl`) or a Makefile/script that auto-detects the namespace via `oci os ns get` and generates the backend config. At minimum, add a `terraform init` wrapper script that validates the endpoint is not PLACEHOLDER.

**TODO: Multiple notification emails for Cloud Guard:**
- Issue: The `terraform/infra/terraform.tfvars.example` (line 16) contains `# TODO multiplos emails?` indicating a known limitation — only a single email can receive Cloud Guard alerts.
- Files: `terraform/infra/modules/oci-cloud-guard/main.tf`, `terraform/infra/modules/oci-cloud-guard/variables.tf`
- Impact: Only one person receives security alerts. If that person is unavailable, alerts go unnoticed.
- Fix approach: Change `notification_email` to `notification_emails` as a `list(string)` variable and create one `oci_ons_subscription` per email using `count` or `for_each`.

**Hardcoded pod CIDR in network NSG rule:**
- Issue: The pod overlay CIDR `10.244.0.0/16` is hardcoded in the network NSG rule at `terraform/infra/modules/oci-network/main.tf` (line 174) but defined separately in the OKE module at `terraform/infra/modules/oci-oke/main.tf` (line 49). These values must stay in sync manually.
- Files: `terraform/infra/modules/oci-network/main.tf`, `terraform/infra/modules/oci-oke/main.tf`
- Impact: If someone changes the pod CIDR in the OKE module but forgets the NSG rule, cross-node pod communication breaks silently.
- Fix approach: Extract `pods_cidr` as a root-level variable passed to both modules, or output it from one module and input it to the other.

**Hardcoded resource display names with "assessforge" prefix:**
- Issue: All OCI resource `display_name` values are hardcoded with `assessforge-` prefix (e.g., `assessforge-vcn`, `assessforge-igw`, `assessforge-natgw`). This is spread across all infra modules.
- Files: `terraform/infra/modules/oci-network/main.tf`, `terraform/infra/modules/oci-oke/main.tf`, `terraform/infra/modules/oci-vault/main.tf`, `terraform/infra/modules/oci-cloud-guard/main.tf`
- Impact: Cannot reuse modules for a different project without modifying every display name. Low immediate risk since this is a single-project setup.
- Fix approach: Introduce a `project_name` variable at root level and use `"${var.project_name}-vcn"` pattern for all display names. Low priority unless module reuse is planned.

**Hardcoded Helm chart versions across k8s modules:**
- Issue: Helm chart versions are pinned inline in each module's `main.tf` without being parameterized as variables: ArgoCD `7.6.12`, external-secrets `0.9.20`, ingress-nginx `4.10.1`, Kyverno `3.2.6`.
- Files: `terraform/k8s/modules/argocd/main.tf` (line 7), `terraform/k8s/modules/external-secrets/main.tf` (line 7), `terraform/k8s/modules/ingress-nginx/main.tf` (line 7), `terraform/k8s/modules/kyverno/main.tf` (line 18)
- Impact: Upgrading chart versions requires editing module source code instead of changing a variable. No single place to see all chart versions.
- Fix approach: Add a `chart_version` variable to each k8s module and pass values from the root `terraform/k8s/variables.tf`. Alternatively, keep pinned versions in modules (they are stable contracts) but document the upgrade process.

**null_resource for kubeconfig generation:**
- Issue: The OKE module uses `null_resource` with `local-exec` provisioner to generate kubeconfig at `terraform/infra/modules/oci-oke/main.tf` (lines 143-159). This runs on the operator's machine and writes to `~/.kube/config-assessforge`. It only triggers on cluster ID change, not on credential rotation.
- Files: `terraform/infra/modules/oci-oke/main.tf`
- Impact: If credentials rotate or the kubeconfig expires, there is no automatic refresh. The `null_resource` does not re-run unless tainted manually. Also couples Terraform apply to the operator's local filesystem.
- Fix approach: Consider removing the `null_resource` and relying solely on the `kubeconfig_command` output at `terraform/infra/outputs.tf` (line 17) for operators to run manually. This makes the process explicit and repeatable.

## Security Concerns

**ArgoCD running in --insecure mode (no TLS termination at server):**
- Issue: ArgoCD server is started with `extraArgs = ["--insecure"]` at `terraform/k8s/modules/argocd/main.tf` (line 49), and the ingress has `ssl-redirect = "false"` at line 161. Traffic between the ingress controller and ArgoCD server is unencrypted HTTP.
- Files: `terraform/k8s/modules/argocd/main.tf`
- Impact: Without TLS at the ingress level (cert-manager + Let's Encrypt or similar), the entire ArgoCD UI and API is served over plain HTTP from the load balancer to the client. This exposes GitHub OAuth tokens and session cookies. Within the cluster, ingress-to-argocd traffic is also plain HTTP but within the same network.
- Fix approach: Deploy cert-manager and configure a TLS `ClusterIssuer` with Let's Encrypt. Add TLS section to the ArgoCD ingress resource. The `--insecure` flag can remain (TLS terminates at ingress), but `ssl-redirect` should be `"true"`.

**Broad IAM dynamic group matching rule:**
- Issue: The workload identity dynamic group at `terraform/infra/modules/oci-iam/main.tf` (line 10) matches `ALL {resource.type = 'workload', resource.compartment.id = '...'}`. This grants any workload (pod with service account) in the compartment access to vault secrets, not just the ESO pods.
- Files: `terraform/infra/modules/oci-iam/main.tf`
- Impact: If a compromised application pod in the same compartment has a service account, it could potentially read vault secrets. The risk is mitigated by the `ClusterSecretStore` condition limiting access to the argocd namespace, but the OCI-level IAM is broader than necessary.
- Fix approach: Tighten the matching rule to include the cluster OCID and specific service account: `ALL {resource.type = 'workload', resource.compartment.id = '...', resource.cluster.id = '...'}`. OKE Workload Identity supports more specific claims.

**ArgoCD AppProject sourceRepos allows all repositories:**
- Issue: The `assessforge` AppProject at `terraform/k8s/modules/argocd/main.tf` (line 206) sets `sourceRepos: ['*']` allowing ArgoCD to pull manifests from any Git repository.
- Files: `terraform/k8s/modules/argocd/main.tf`
- Impact: A user with ArgoCD admin access could deploy workloads from untrusted repositories. Combined with the broad RBAC (`all org members = admin`), any org member could point an Application at a malicious repo.
- Fix approach: Restrict `sourceRepos` to the organization's GitHub repositories: `https://github.com/assessforge/*` or specific repos.

**All GitHub org members receive ArgoCD admin role:**
- Issue: The RBAC policy at `terraform/k8s/modules/argocd/main.tf` (line 133) grants `role:admin` to the entire GitHub organization. There is no role differentiation.
- Files: `terraform/k8s/modules/argocd/main.tf`
- Impact: Every organization member can create/delete applications, modify ArgoCD settings, and access all namespaces. No least-privilege separation between developers and operators.
- Fix approach: Map GitHub teams to specific ArgoCD roles. E.g., `g, assessforge:platform-team, role:admin` and `g, assessforge:developers, role:readonly`. Requires the GitHub OAuth scope to include team membership.

**Network policies only cover the argocd namespace:**
- Issue: The network-policies module at `terraform/k8s/modules/network-policies/main.tf` only creates policies for the `argocd` namespace. No default-deny policies exist for `external-secrets`, `ingress-nginx`, `kyverno`, or application namespaces.
- Files: `terraform/k8s/modules/network-policies/main.tf`
- Impact: Pods in other namespaces have unrestricted network access by default. A compromised pod in an application namespace could communicate freely within the cluster.
- Fix approach: Add default-deny NetworkPolicies for `external-secrets`, `ingress-nginx`, and `kyverno` namespaces. For application namespaces, create a Kyverno policy that auto-generates a default-deny NetworkPolicy when a new namespace is created.

**ArgoCD egress allows TCP 443 to any destination:**
- Issue: The egress NetworkPolicy at `terraform/k8s/modules/network-policies/main.tf` (line 151) allows all ArgoCD pods (except Redis) to reach any IP on port 443.
- Files: `terraform/k8s/modules/network-policies/main.tf`
- Impact: A compromised ArgoCD pod could exfiltrate data to any HTTPS endpoint. Acceptable for repo-server (needs GitHub access) and dex (needs GitHub OAuth), but the policy is broader than needed.
- Fix approach: Low priority. Restricting HTTPS egress by IP is impractical for GitHub/OCI APIs with dynamic IPs. Accept this as a known trade-off and document it.

## Operational Concerns

**No TLS/cert-manager — production traffic is unencrypted:**
- Issue: There is no cert-manager module or TLS configuration anywhere in the codebase. The ingress-nginx controller serves traffic on port 80/443 but without certificates.
- Files: `terraform/k8s/modules/ingress-nginx/main.tf`, `terraform/k8s/modules/argocd/main.tf`
- Impact: ArgoCD UI and any future applications are accessible only over HTTP. GitHub OAuth callback will fail or be insecure without HTTPS. This is the single biggest gap for production readiness.
- Fix approach: Add a `cert-manager` module to `terraform/k8s/modules/` that installs cert-manager via Helm and creates a `ClusterIssuer` for Let's Encrypt. Update the ArgoCD ingress to include a `tls` block with `cert-manager.io/cluster-issuer` annotation.

**No monitoring or observability stack:**
- Issue: There are no Prometheus, Grafana, Loki, or any monitoring/alerting modules. The only monitoring is OCI Cloud Guard (security posture) and OCI audit logs.
- Files: N/A (not present in codebase)
- Impact: No visibility into cluster resource usage, pod health, application metrics, or ingress traffic patterns. Issues must be diagnosed manually via `kubectl`.
- Fix approach: Add a monitoring module deploying kube-prometheus-stack (Prometheus + Grafana) via Helm. Consider Loki for log aggregation.

**No disaster recovery or backup strategy:**
- Issue: ArgoCD state (applications, projects, repositories) lives in Kubernetes (etcd) with no backup. The OCI Vault has `prevent_destroy` but no cross-region replication. Terraform state is in a single OCI Object Storage bucket with no versioning configuration visible.
- Files: `terraform/infra/modules/oci-vault/main.tf`, `terraform/infra/versions.tf`, `terraform/k8s/versions.tf`
- Impact: Loss of the etcd data or state bucket means full manual reconstruction. The `prevent_destroy` lifecycle rules protect against accidental Terraform deletion but not data loss.
- Fix approach: Enable versioning on the `assessforge-tfstate` Object Storage bucket (done outside Terraform or via a separate bootstrap module). For ArgoCD, its declarative GitOps model means applications can be re-synced from Git, but custom settings and repository credentials would be lost.

**Single availability domain for node pool:**
- Issue: The OKE node pool at `terraform/infra/modules/oci-oke/main.tf` (line 119) only has one `placement_configs` block using the first availability domain.
- Files: `terraform/infra/modules/oci-oke/main.tf`
- Impact: All worker nodes run in a single AD. An AD-level outage takes down all workloads. This may be acceptable for the free tier (sa-saopaulo-1 may have only one AD), but is a scaling concern.
- Fix approach: Add additional `placement_configs` for other ADs if available. Use `for_each` over `data.oci_identity_availability_domains.ads.availability_domains` to automatically distribute across all ADs.

**Node pool has only 2 nodes with modest resources:**
- Issue: The node pool at `terraform/infra/modules/oci-oke/main.tf` (lines 96-130) runs 2 nodes of `VM.Standard.A1.Flex` with 2 OCPUs and 12GB RAM each. This is consistent with OCI Always Free tier limits.
- Files: `terraform/infra/modules/oci-oke/main.tf`
- Impact: Total cluster capacity is 4 OCPUs and 24GB RAM. After system pods (kube-system, kyverno, ingress-nginx, external-secrets, argocd), available capacity for application workloads is limited. ArgoCD alone requests ~800m CPU and ~1.2Gi memory.
- Fix approach: Monitor actual resource usage. If capacity is tight, consider reducing ArgoCD resource requests or scaling the node pool. The `size` parameter can be increased but may exceed free tier limits.

**Bastion CIDR is a single operator IP:**
- Issue: The `bastion_allowed_cidr` variable accepts only one CIDR block, passed to both the Bastion NSG at `terraform/infra/modules/oci-network/main.tf` (line 199) and the Bastion service at `terraform/infra/modules/oci-oke/main.tf` (line 138).
- Files: `terraform/infra/variables.tf`, `terraform/infra/modules/oci-network/main.tf`, `terraform/infra/modules/oci-oke/main.tf`
- Impact: Only one operator can access the cluster at a time. If the operator's IP changes (dynamic ISP), access is lost until `terraform apply` updates the CIDR.
- Fix approach: Change `bastion_allowed_cidr` to `bastion_allowed_cidrs` as a `list(string)`. Update the NSG rule to use `for_each` and the Bastion `client_cidr_block_allow_list` already accepts a list.

## Code Quality Concerns

**Inconsistent .gitignore coverage:**
- Issue: The root `.gitignore` at `/home/rodrigo/projects/AssessForge/infra-setup/.gitignore` only ignores `.claude`, `.terraform/`, and `*.tfstate`. The more comprehensive gitignore at `terraform/.gitignore` covers `*.tfvars`, `*.tfplan`, kubeconfig, and other sensitive files. But `.terraform.lock.hcl` is ignored in `terraform/.gitignore` while the lock files are actually committed (they exist at `terraform/infra/.terraform.lock.hcl` and `terraform/k8s/.terraform.lock.hcl`).
- Files: `.gitignore`, `terraform/.gitignore`
- Impact: The lock files being committed is actually correct practice (they should be committed for reproducible builds). The `.gitignore` rule ignoring `.terraform.lock.hcl` is wrong and could cause future lock file changes to not be committed.
- Fix approach: Remove the `.terraform.lock.hcl` line from `terraform/.gitignore` since lock files should be committed. Verify the committed lock files are not stale.

**Kyverno excluded_namespaces includes "longhorn-system" which does not exist:**
- Issue: The `excluded_namespaces` local at `terraform/k8s/modules/kyverno/main.tf` (line 6) includes `longhorn-system`, but there is no Longhorn module or any reference to Longhorn elsewhere in the codebase.
- Files: `terraform/k8s/modules/kyverno/main.tf`
- Impact: No functional impact (excluding a non-existent namespace is harmless), but it signals either leftover planning or a missing module. Causes confusion about what is actually deployed.
- Fix approach: Remove `longhorn-system` from the exclusion list, or add it back when Longhorn is actually deployed.

**ArgoCD namespace created in external-secrets module, not argocd module:**
- Issue: The `argocd` namespace is created by the `external-secrets` module at `terraform/k8s/modules/external-secrets/main.tf` (line 46) because the ExternalSecret resource needs the namespace to exist. The ArgoCD module then uses `create_namespace = false` at `terraform/k8s/modules/argocd/main.tf` (line 7).
- Files: `terraform/k8s/modules/external-secrets/main.tf`, `terraform/k8s/modules/argocd/main.tf`
- Impact: Cross-module coupling — the external-secrets module owns the argocd namespace lifecycle. If someone removes or refactors external-secrets, the argocd namespace disappears. The `argocd_namespace` output is also duplicated (once from external-secrets, once hardcoded in argocd outputs).
- Fix approach: Create the namespace in a dedicated resource at the root `terraform/k8s/main.tf` level and pass it to both modules. Or accept the coupling since ESO must create the namespace before ArgoCD for the ExternalSecret to work.

**No validation blocks on critical variables:**
- Issue: Variables like `bastion_allowed_cidr` (should be a valid CIDR), `region` (should be a valid OCI region), and `github_org` (should not be empty) have no `validation` blocks.
- Files: `terraform/infra/variables.tf`, `terraform/k8s/variables.tf`
- Impact: Invalid values cause cryptic API errors at apply time instead of clear messages at plan time.
- Fix approach: Add `validation` blocks. Example: `validation { condition = can(cidrhost(var.bastion_allowed_cidr, 0)); error_message = "Must be valid CIDR" }`.

## Test Coverage Gaps

**No automated tests exist:**
- Issue: There are no test files anywhere in the codebase — no `terratest`, no `terraform test`, no CI pipeline configuration.
- Files: N/A (not present)
- Impact: Changes to modules cannot be validated without manual `terraform plan` against a real environment. Refactoring is risky.
- Fix approach: Add Terraform native tests (`*.tftest.hcl`) for plan-level validation of each module. For integration testing, consider `terratest` with a dedicated test compartment.

**No CI/CD pipeline:**
- Issue: There are no GitHub Actions workflows, no `.github/` directory, no CI configuration files.
- Files: N/A (not present)
- Impact: No automated `terraform fmt` check, no `terraform validate`, no plan preview on pull requests. Code quality depends entirely on manual discipline.
- Fix approach: Add a GitHub Actions workflow that runs `terraform fmt -check`, `terraform validate`, and optionally `terraform plan` (with appropriate OCI credentials) on pull requests.

## Dependencies at Risk

**External Secrets Operator using v1beta1 API:**
- Issue: The `ClusterSecretStore` and `ExternalSecret` manifests at `terraform/k8s/modules/external-secrets/main.tf` use `apiVersion: external-secrets.io/v1beta1`. The chart version `0.9.20` supports this, but newer ESO versions are migrating to `v1`.
- Files: `terraform/k8s/modules/external-secrets/main.tf`
- Impact: Upgrading the ESO Helm chart past the deprecation boundary will break these manifests.
- Fix approach: When upgrading ESO, update manifests to `external-secrets.io/v1`. Test in a staging environment first.

**Provider version constraints are broad (~> major.0):**
- Issue: The k8s layer pins providers loosely: `helm ~> 3.0`, `kubernetes ~> 3.0`, `kubectl ~> 2.0`. The infra layer uses `oci ~> 8.0`.
- Files: `terraform/k8s/versions.tf`, `terraform/infra/versions.tf`
- Impact: A `terraform init -upgrade` could pull in a new minor/patch version with breaking changes. The lock files provide protection, but if regenerated, versions could jump significantly.
- Fix approach: This is acceptable Terraform practice for active development. The lock files provide the actual pinning. Ensure lock files remain committed.

---

*Concerns audit: 2026-04-09*
