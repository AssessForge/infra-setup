# Phase 3: ArgoCD Self-Management & Addons - Context

**Gathered:** 2026-04-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Fill in the stub Helm values and add Gateway API / cert-manager resources so that: ArgoCD self-manages with GitHub SSO (Dex) and RBAC, Envoy Gateway serves external HTTPS traffic through an OCI Flexible Load Balancer, cert-manager issues a valid Let's Encrypt certificate for argocd.assessforge.com, and metrics-server provides resource usage data. All stub Application manifests and values files already exist from Phase 2 — this phase fills in configuration details and adds supplementary resource manifests.

</domain>

<decisions>
## Implementation Decisions

### ArgoCD SSO & RBAC
- **D-01:** Org-wide admin RBAC — all AssessForge GitHub org members get `role:admin`. Default policy denies access to non-members. No team-based granularity needed for a small team with a single cluster.
- **D-02:** All security hardening values go in `environments/default/addons/argocd/values.yaml` — admin.enabled=false, exec.enabled=false, security contexts (runAsNonRoot, readOnlyRootFilesystem, drop ALL caps, seccomp), resource limits. Single source of truth, no separate manifests.
- **D-03:** Dex GitHub connector references the OAuth credentials via environment variables (`$GITHUB_CLIENT_ID` / `$GITHUB_CLIENT_SECRET`) sourced from the `argocd-dex-github-secret` ExternalSecret. Mounted as env source on the Dex container via Helm values.

### Envoy Gateway & Routing
- **D-04:** OCI Load Balancer configured via Service annotations on the Envoy Gateway controller Service through Helm values — flexible shape, 10Mbps min/max bandwidth (free tier). Same pattern as the old ingress-nginx setup.
- **D-05:** Envoy Gateway Helm chart manages its own CRDs (default chart behavior). No separate CRD Application needed. CRDs upgrade with the chart.
- **D-06:** TLS terminates at Envoy Gateway. Plain HTTP from Gateway to ArgoCD Server on port 8080. Standard approach for internal cluster traffic — avoids ArgoCD self-signed cert complexity.

### TLS & cert-manager
- **D-07:** HTTP-01 challenge solver uses cert-manager's native Gateway API support (v1.20+). ClusterIssuer points to the Gateway, cert-manager creates temporary HTTPRoutes for ACME challenges automatically.
- **D-08:** Gateway TLS listener integration — the Gateway spec includes a TLS listener referencing a Secret. cert-manager annotates the Gateway to auto-issue the certificate. Tighter lifecycle coupling between cert and Gateway.
- **D-09:** Let's Encrypt production endpoint directly (acme-v02.api.letsencrypt.org). Single cluster, one domain — no rate limit risk. Avoids staging-to-prod config switch.

### Manifest Placement
- **D-10:** Gateway API resources (GatewayClass, Gateway, HTTPRoute) live inside `addons/envoy-gateway/` alongside the Application manifest. Single Application syncs the operator and its routing config together.
- **D-11:** cert-manager resources (ClusterIssuer, Certificate) live inside `addons/cert-manager/` alongside the Application manifest. Operator and issuance config stay together.
- **D-12:** Envoy Gateway Application uses multi-source — existing Helm chart source + a third source pointing to a local `manifests/` subdir within `addons/envoy-gateway/` for raw Gateway API YAML resources (GatewayClass, Gateway, HTTPRoute).

### Claude's Discretion
- ArgoCD Helm values structure (exact YAML for security contexts, resource limits, Dex connector config)
- Envoy Gateway Helm values for OCI LB annotations and ARM64 compatibility
- cert-manager Helm values (installCRDs, Gateway API feature gate)
- cert-manager ClusterIssuer YAML specifics (ACME server, solver config)
- Gateway/HTTPRoute YAML structure (ports, hostnames, backend refs)
- metrics-server Helm values (ARM64 compatibility, resource limits)
- Sync wave adjustments if needed for cert-manager → Gateway ordering within wave 3
- Whether cert-manager Application needs similar multi-source for ClusterIssuer/Certificate manifests

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 2 Outputs (Stub Manifests)
- `gitops-setup/bootstrap/control-plane/argocd/application.yaml` — ArgoCD self-managed Application (prune: false, chart argo-cd v9.5.0)
- `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml` — Envoy Gateway Application (chart gateway-helm v1.4.0, oci://docker.io/envoyproxy)
- `gitops-setup/bootstrap/control-plane/addons/cert-manager/application.yaml` — cert-manager Application (chart cert-manager v1.20.1)
- `gitops-setup/bootstrap/control-plane/addons/metrics-server/application.yaml` — metrics-server Application (chart metrics-server v3.13.0)
- `gitops-setup/environments/default/addons/argocd/values.yaml` — Stub (empty), to be filled with SSO/RBAC/hardening config
- `gitops-setup/environments/default/addons/envoy-gateway/values.yaml` — Stub (empty), to be filled with OCI LB annotations
- `gitops-setup/environments/default/addons/cert-manager/values.yaml` — Stub (empty), to be filled with CRD install + Gateway API feature gate
- `gitops-setup/environments/default/addons/metrics-server/values.yaml` — Stub (empty), to be filled with ARM64 + resource limits

### ESO Resources (Already Created)
- `gitops-setup/bootstrap/control-plane/addons/eso/external-secret-github-oauth.yaml` — Syncs GitHub OAuth client_id/client_secret from OCI Vault
- `gitops-setup/bootstrap/control-plane/addons/eso/external-secret-repo-creds.yaml` — Syncs GitHub PAT for repo access from OCI Vault

### Infrastructure Context
- `terraform/infra/modules/oci-argocd-bootstrap/main.tf` — Bridge Secret structure (labels, annotations), ArgoCD Helm bootstrap
- `terraform/infra/modules/oci-argocd-bootstrap/variables.tf` — Bootstrap module variables (gitops_repo_url, etc.)

### Research
- `.planning/research/STACK.md` — Recommended versions (ArgoCD 9.5.0/v3.3.6, ESO 2.2.0, cert-manager 1.20.1, metrics-server 3.13.0, Envoy Gateway 1.4.0)
- `.planning/research/PITFALLS.md` — OCI-specific pitfalls (Instance Principal, sync wave gotchas)
- `.planning/research/ARCHITECTURE.md` — GitOps Bridge Pattern architecture

### Prior Phase Context
- `.planning/phases/01-cleanup-iam-bootstrap/01-CONTEXT.md` — IAM strategy, Bridge Secret design, bootstrap layout
- `.planning/phases/02-gitops-repository-eso/02-CONTEXT.md` — Repo structure, ApplicationSet design, ESO auth, sync wave order

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- All 4 addon Application manifests already exist with pinned chart versions and multi-source (Helm + gitops-setup values ref)
- ArgoCD self-managed Application already configured with `prune: false` and `selfHeal: true`
- ExternalSecrets for GitHub OAuth and repo creds already deployed and syncing from OCI Vault
- ClusterSecretStore for OCI Vault via Instance Principal already configured
- ApplicationSet with matrix generator already discovering addon directories

### Established Patterns
- Addon dirs follow `addons/{name}/application.yaml` + `environments/default/addons/{name}/values.yaml` pattern
- Application manifests use multi-source: gitops-setup repo (ref: values) + upstream Helm chart
- Sync waves: wave 1 (ESO), wave 2 (secrets), wave 3 (all other addons)
- Portuguese comments in YAML files
- `ignoreMissingValueFiles: true` on all Helm sources

### Integration Points
- ArgoCD values.yaml must reference `argocd-dex-github-secret` (ExternalSecret output) for Dex env vars
- Envoy Gateway application.yaml needs a third source for raw Gateway API manifests (addons/envoy-gateway/manifests/)
- cert-manager application.yaml may need a third source for ClusterIssuer/Certificate manifests (addons/cert-manager/manifests/)
- Gateway HTTPRoute must target ArgoCD Server Service on port 8080 (TLS termination at Gateway)
- Gateway TLS listener must reference a Secret that cert-manager populates via annotation-based issuance

</code_context>

<specifics>
## Specific Ideas

- ArgoCD Server must run with `--insecure` flag (or Helm equivalent) since TLS terminates at Envoy Gateway, not at ArgoCD itself
- The `argocd-dex-github-secret` ExternalSecret outputs keys `client_id` and `client_secret` — Dex env var mounting must match these key names
- Envoy Gateway chart is from an OCI registry (`oci://docker.io/envoyproxy/gateway-helm`) — this is already correctly configured in the stub Application
- cert-manager needs `installCRDs: true` in Helm values and the Gateway API feature gate enabled for native HTTPRoute-based challenge solving
- All container images must support ARM64 (OKE nodes are VM.Standard.A1.Flex ARM)
- OCI Flexible LB free tier: 1 LB, 10Mbps bandwidth — annotations must specify this explicitly

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-argocd-self-management-addons*
*Context gathered: 2026-04-10*
