# Phase 3: ArgoCD Self-Management & Addons - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-10
**Phase:** 03-argocd-self-management-addons
**Areas discussed:** ArgoCD SSO & RBAC, Envoy Gateway & routing, TLS & cert-manager, Manifest placement

---

## ArgoCD SSO & RBAC

### RBAC structure

| Option | Description | Selected |
|--------|-------------|----------|
| Org-wide admin (Recommended) | All AssessForge org members get role:admin. Simple, fits a small team. Default policy denies non-members. | ✓ |
| Team-based roles | Map specific GitHub teams to ArgoCD roles (e.g., platform-team=admin, dev-team=readonly). More granular but requires team setup. | |
| You decide | Claude picks the best fit based on project constraints. | |

**User's choice:** Org-wide admin (Recommended)
**Notes:** None

### Security hardening placement

| Option | Description | Selected |
|--------|-------------|----------|
| All in values.yaml (Recommended) | admin.enabled=false, exec.enabled=false, security contexts, resource limits — all as Helm values. Single source of truth. | ✓ |
| Split approach | Helm values for basic config, separate YAML manifests for security contexts and policies. | |
| You decide | Claude picks based on what the argo-cd chart supports natively. | |

**User's choice:** All in values.yaml (Recommended)
**Notes:** None

### Dex secret reference

| Option | Description | Selected |
|--------|-------------|----------|
| Env vars from secret (Recommended) | Use Dex config with $GITHUB_CLIENT_ID / $GITHUB_CLIENT_SECRET env vars, mount the ExternalSecret as env source on Dex container. | ✓ |
| Dex secret name reference | Point Dex connector config to K8s secret name directly using ArgoCD's built-in secret management. | |
| You decide | Claude picks the approach that works best with argo-cd Helm chart v9.5.0. | |

**User's choice:** Env vars from secret (Recommended)
**Notes:** None

---

## Envoy Gateway & Routing

### OCI Load Balancer configuration

| Option | Description | Selected |
|--------|-------------|----------|
| Service annotations (Recommended) | OCI LB annotations on the Envoy Gateway controller Service via Helm values: flexible shape, 10Mbps. | ✓ |
| Gateway resource annotations | Put OCI annotations on the Gateway resource itself via infrastructure field. | |
| You decide | Claude picks based on Envoy Gateway's OCI compatibility. | |

**User's choice:** Service annotations (Recommended)
**Notes:** None

### CRD handling

| Option | Description | Selected |
|--------|-------------|----------|
| Helm chart installs CRDs (Recommended) | Let the Envoy Gateway Helm chart manage its own CRDs (default behavior). CRDs upgrade with the chart. | ✓ |
| Separate CRD manifest | Install Gateway API CRDs as a separate Application at an earlier sync wave. | |
| You decide | Claude picks based on the gateway-helm chart's CRD handling behavior. | |

**User's choice:** Helm chart installs CRDs (Recommended)
**Notes:** None

### TLS termination mode

| Option | Description | Selected |
|--------|-------------|----------|
| Terminate at Gateway (Recommended) | TLS terminates at Envoy Gateway, plain HTTP to ArgoCD Server on port 8080. Standard for internal cluster traffic. | ✓ |
| End-to-end TLS | TLS passthrough or re-encrypt to ArgoCD Server on port 8443. More secure internally but adds complexity. | |
| You decide | Claude picks based on ArgoCD + Envoy Gateway best practices. | |

**User's choice:** Terminate at Gateway (Recommended)
**Notes:** None

---

## TLS & cert-manager

### HTTP-01 challenge solver

| Option | Description | Selected |
|--------|-------------|----------|
| Auto via Gateway API (Recommended) | cert-manager v1.20+ natively supports Gateway API HTTP-01 solver. ClusterIssuer points to Gateway, auto-creates temp HTTPRoutes. | ✓ |
| Ingress-class fallback | Use traditional ingress-based solver. Works but mixes Ingress and Gateway API paradigms. | |
| You decide | Claude picks based on cert-manager v1.20.1 + Envoy Gateway compatibility. | |

**User's choice:** Auto via Gateway API (Recommended)
**Notes:** None

### Certificate binding

| Option | Description | Selected |
|--------|-------------|----------|
| Gateway TLS listener (Recommended) | Gateway spec includes TLS listener referencing a Secret. cert-manager annotates Gateway to auto-issue certificate. | ✓ |
| Standalone Certificate | Separate Certificate resource writes to Secret, Gateway references that Secret. More explicit, decoupled. | |
| You decide | Claude picks based on Envoy Gateway + cert-manager best practices. | |

**User's choice:** Gateway TLS listener (Recommended)
**Notes:** None

### Let's Encrypt endpoint

| Option | Description | Selected |
|--------|-------------|----------|
| Production directly (Recommended) | Use prod endpoint. Single cluster, one domain — no rate limit risk. Avoids switching later. | ✓ |
| Staging first | Use staging endpoint first to validate, then switch. Safer but requires config change. | |
| You decide | Claude picks based on project context. | |

**User's choice:** Production directly (Recommended)
**Notes:** None

---

## Manifest Placement

### Gateway API resources location

| Option | Description | Selected |
|--------|-------------|----------|
| Inside envoy-gateway addon dir (Recommended) | GatewayClass, Gateway, HTTPRoute in addons/envoy-gateway/. Single Application syncs everything. | ✓ |
| Separate gateway-routes dir | New addons/gateway-routes/ directory. Separates operator from config but adds another Application. | |
| Inside argocd dir | ArgoCD HTTPRoute in bootstrap/control-plane/argocd/. Other routes in their own dirs. | |
| You decide | Claude picks the layout that best fits existing structure. | |

**User's choice:** Inside envoy-gateway addon dir (Recommended)
**Notes:** None

### cert-manager resources location

| Option | Description | Selected |
|--------|-------------|----------|
| Inside cert-manager addon dir (Recommended) | ClusterIssuer and Certificate in addons/cert-manager/. Operator and issuance config together. | ✓ |
| Separate cert-config dir | New addons/cert-config/ for ClusterIssuer and Certificates. Separates operator from config. | |
| You decide | Claude picks based on existing addon directory pattern. | |

**User's choice:** Inside cert-manager addon dir (Recommended)
**Notes:** None

### Helm + raw YAML handling

| Option | Description | Selected |
|--------|-------------|----------|
| Multi-source Application (Recommended) | Add a third source pointing to local manifests/ subdir within addons/envoy-gateway/ for raw YAML resources. | ✓ |
| Separate raw-YAML Application | Keep Helm Application as-is. Create second Application for raw manifests. | |
| You decide | Claude picks based on ArgoCD multi-source capabilities. | |

**User's choice:** Multi-source Application (Recommended)
**Notes:** None

---

## Claude's Discretion

- ArgoCD Helm values YAML structure (security contexts, resource limits, Dex connector)
- Envoy Gateway Helm values for OCI LB annotations and ARM64
- cert-manager Helm values (installCRDs, Gateway API feature gate)
- Gateway/HTTPRoute/ClusterIssuer YAML specifics
- metrics-server Helm values (ARM64, resource limits)
- Sync wave fine-tuning within wave 3

## Deferred Ideas

None — discussion stayed within phase scope
