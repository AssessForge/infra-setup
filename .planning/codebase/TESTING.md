# Testing Patterns

**Analysis Date:** 2026-04-09

## Test Framework

**Runner:** None

No test framework is configured. There are no test files, no testing dependencies, no CI/CD pipeline, and no linting or validation tooling configured in the repository.

**Run Commands:**
```bash
# No test commands exist. The only validation is manual:
cd terraform/infra && terraform plan
cd terraform/k8s && terraform plan
```

## Current Testing Approach

### Manual `terraform plan` Review

The sole validation mechanism is manual `terraform plan` followed by human review before `terraform apply`. The `terraform/README.md` documents this workflow as a two-stage process:

1. **Stage 1 (infra/):** `terraform plan` then `terraform apply` for OCI infrastructure.
2. **Stage 2 (k8s/):** `terraform plan` then `terraform apply` for Kubernetes components.

### Built-in Terraform Validation

The following Terraform-native features provide some implicit validation:

- **Type constraints:** All variables declare explicit `type` (string, map(string)).
- **Required variables:** Variables without `default` must be provided, preventing partial applies.
- **`sensitive = true`:** Prevents accidental exposure of `github_oauth_client_id` and `github_oauth_client_secret` in plan output.
- **Provider version constraints:** `~>` pessimistic constraints in `versions.tf` files prevent breaking upgrades.
- **`lifecycle { prevent_destroy = true }`:** Protects critical resources (OKE cluster, node pool, Vault, master key) from accidental destruction.

### Runtime Policy Enforcement (Kyverno)

Kyverno (`terraform/k8s/modules/kyverno/main.tf`) provides runtime validation via 6 `ClusterPolicy` resources with `validationFailureAction: Enforce`:

| Policy | File | What it validates |
|--------|------|-------------------|
| `disallow-root-containers` | `terraform/k8s/modules/kyverno/main.tf` | `runAsNonRoot: true` on all containers |
| `disallow-privilege-escalation` | same | `allowPrivilegeEscalation: false` |
| `require-readonly-rootfs` | same | `readOnlyRootFilesystem: true` |
| `disallow-latest-tag` | same | No `:latest` tag or missing tag on images |
| `require-resource-limits` | same | CPU and memory limits defined |
| `require-seccomp-profile` | same | seccompProfile RuntimeDefault or Localhost |

These policies exclude system namespaces: `kube-system`, `kyverno`, `longhorn-system`, `external-secrets`, `argocd`, `ingress-nginx`.

### Security Monitoring (Cloud Guard)

OCI Cloud Guard (`terraform/infra/modules/oci-cloud-guard/main.tf`) provides continuous security posture monitoring with event-driven alerts via OCI Notifications (ONS). This is a runtime observability tool, not a pre-deploy test.

## Linting and Formatting

**No linting tools configured:**
- No `.tflint.hcl` or TFLint configuration.
- No `.pre-commit-config.yaml`.
- No `checkov` or `tfsec` configuration.
- No `terraform fmt` check in any CI pipeline.
- No `terraform validate` automation.

**No formatting enforcement:**
- The codebase appears consistently formatted (likely `terraform fmt` was run manually), but there is no automated check.

## CI/CD Pipeline

**None.** No `.github/workflows/`, no `Makefile`, no `Jenkinsfile`, no pipeline configuration of any kind.

## Test File Organization

Not applicable -- no test files exist.

## Coverage

**Requirements:** None enforced.

No code coverage tooling. No infrastructure test coverage tracking.

## Gaps and Recommended Additions

### High Priority

**1. `terraform validate` automation**
- Problem: Syntax and type errors are only caught at `terraform plan` time by a human.
- Files affected: All `.tf` files.
- Recommendation: Add a pre-commit hook or CI step running `terraform validate` in both `terraform/infra/` and `terraform/k8s/`.

**2. `terraform fmt -check` enforcement**
- Problem: Formatting consistency depends on developer discipline.
- Recommendation: Add `terraform fmt -check -recursive` to a pre-commit hook or CI step.

**3. Static security analysis (tfsec or checkov)**
- Problem: Security misconfigurations (e.g., overly permissive NSG rules, missing encryption) are only caught by manual review.
- Files affected: All module `main.tf` files, especially `terraform/infra/modules/oci-network/main.tf` (NSG rules).
- Recommendation: Add `tfsec` or `checkov` scan. Both support OCI resources.

### Medium Priority

**4. TFLint configuration**
- Problem: Provider-specific best practices (deprecated arguments, naming issues) are not checked.
- Recommendation: Add `.tflint.hcl` with the OCI provider ruleset.

**5. `terraform plan` in CI on pull requests**
- Problem: PRs are merged without automated plan validation.
- Recommendation: Add a GitHub Actions workflow that runs `terraform init` and `terraform plan` for both stages on every PR. Use a read-only OCI credential for plan-only access.

**6. Variable validation rules**
- Problem: Variables like `bastion_allowed_cidr` accept any string. Invalid CIDRs fail late at apply time.
- Files: `terraform/infra/variables.tf`, `terraform/infra/modules/oci-network/variables.tf`
- Recommendation: Add `validation` blocks:
  ```hcl
  variable "bastion_allowed_cidr" {
    type        = string
    description = "..."
    validation {
      condition     = can(cidrhost(var.bastion_allowed_cidr, 0))
      error_message = "Must be a valid CIDR block."
    }
  }
  ```

### Low Priority

**7. Integration tests (Terratest or terraform test)**
- Problem: No automated verification that applied infrastructure actually works (e.g., cluster is reachable, ArgoCD responds).
- Recommendation: Consider `terraform test` (native since Terraform 1.6) for plan-level assertions, or Terratest for full apply/destroy integration tests in a sandbox environment.

**8. Pre-commit hooks**
- Problem: No automated quality gates before commit.
- Recommendation: Add `.pre-commit-config.yaml` with:
  - `terraform fmt`
  - `terraform validate`
  - `tflint`
  - `checkov` or `tfsec`
  - `terraform-docs` (auto-generate module documentation)

**9. Drift detection**
- Problem: No mechanism to detect when deployed infrastructure drifts from Terraform state.
- Recommendation: Schedule periodic `terraform plan` runs (e.g., weekly cron in CI) that alert on non-empty plans.

---

*Testing analysis: 2026-04-09*
