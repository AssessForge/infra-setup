---
phase: 03-argocd-self-management-addons
verified: 2026-04-10T20:30:00Z
status: human_needed
score: 5/5 must-haves verified (code-level)
overrides_applied: 0
human_verification:
  - test: "Login to ArgoCD at https://argocd.assessforge.com with a GitHub account in the AssessForge org"
    expected: "GitHub OAuth flow completes, user lands on ArgoCD dashboard with admin access; /api/v1/session/userinfo shows org membership"
    why_human: "Requires live cluster, DNS resolution, GitHub OAuth App configured, and OCI Vault secrets populated"
  - test: "Verify https://argocd.assessforge.com loads with a valid Let's Encrypt certificate (no browser warnings)"
    expected: "Browser shows padlock icon; certificate issuer is Let's Encrypt; certificate covers argocd.assessforge.com"
    why_human: "Requires live DNS pointing to OCI LB IP, cert-manager solving ACME HTTP-01 challenge, and Let's Encrypt issuing the certificate"
  - test: "Verify Envoy Gateway routing is active: kubectl get gatewayclass,gateway,httproute -A"
    expected: "GatewayClass assessforge-gateway-class shows Accepted; Gateway assessforge-gateway shows Programmed with LB IP; HTTPRoutes argocd-https and argocd-http-redirect show Accepted"
    why_human: "Requires running cluster with Envoy Gateway controller reconciling Gateway API resources"
  - test: "Verify metrics-server: kubectl top nodes && kubectl top pods -A"
    expected: "Both commands return CPU and memory usage data for nodes and pods"
    why_human: "Requires running cluster with metrics-server deployed and scraping kubelet metrics"
  - test: "Verify no local admin account: attempt ArgoCD login with admin/any-password"
    expected: "Login fails; no admin account available"
    why_human: "Requires live ArgoCD instance to test authentication"
---

# Phase 3: ArgoCD Self-Management & Addons Verification Report

**Phase Goal:** ArgoCD manages its own config via the GitOps repo, GitHub SSO is active, Envoy Gateway serves external HTTPS traffic, cert-manager issues a valid Let's Encrypt certificate, and metrics-server provides resource metrics
**Verified:** 2026-04-10T20:30:00Z
**Status:** human_needed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths (Roadmap Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC1 | ArgoCD self-managed Application exists with prune: false; updating Helm values via PR causes self-update | VERIFIED | `application.yaml` has `prune: false`, `selfHeal: true`, chart argo-cd v9.5.0, multi-source with values ref, `ignoreDifferences` for argocd-secret, `RespectIgnoreDifferences=true` |
| SC2 | GitHub SSO login with AssessForge org succeeds; no local admin account available | VERIFIED (code) | `admin.enabled: "false"`, `exec.enabled: "false"`, Dex connector with `$client_id`/`$client_secret` matching ExternalSecret keys, `policy.default: "role:none"`, `g, AssessForge, role:admin` |
| SC3 | https://argocd.assessforge.com loads with valid Let's Encrypt TLS certificate | VERIFIED (code) | Gateway annotation `cert-manager.io/cluster-issuer: letsencrypt-prod`, HTTPS listener on 443 with `hostname: argocd.assessforge.com`, `certificateRefs` to `argocd-tls` Secret, ClusterIssuer with `acme-v02.api.letsencrypt.org` and `gatewayHTTPRoute` solver |
| SC4 | Envoy Gateway is active ingress: GatewayClass, Gateway, HTTPRoute all Accepted, traffic through OCI Flexible LB | VERIFIED (code) | GatewayClass references EnvoyProxy via `parametersRef`, Gateway has HTTP+HTTPS listeners, HTTPRoute routes to `argocd-server:8080`, EnvoyProxy has OCI LB annotations (flexible, 10/10), Application has 3 sources including manifests dir |
| SC5 | kubectl top nodes and kubectl top pods return resource usage data | VERIFIED (code) | metrics-server Application at v3.13.0 with pinned chart, values have `--kubelet-insecure-tls`, `--kubelet-preferred-address-types=InternalIP`, resource limits configured |

**Score:** 5/5 truths verified (code-level). All require live cluster for runtime confirmation.

### Plan-Level Must-Haves

| # | Truth | Plan | Status | Evidence |
|---|-------|------|--------|----------|
| P1 | ArgoCD self-managed Application has ignoreDifferences for argocd-secret | 01 | VERIFIED | `ignoreDifferences` block with `kind: Secret`, `name: argocd-secret`, `jsonPointers: [/data]` |
| P2 | ArgoCD values.yaml configures GitHub SSO via Dex with org-based RBAC | 01 | VERIFIED | Dex connector with GitHub type, envFrom with `argocd-dex-github-secret`, RBAC with org admin and default deny |
| P3 | ArgoCD admin and exec disabled | 01 | VERIFIED | `admin.enabled: "false"`, `exec.enabled: "false"` in configs.cm |
| P4 | ArgoCD Server runs with --insecure for TLS termination at Gateway | 01 | VERIFIED | `server.extraArgs: [--insecure]` |
| P5 | All ArgoCD containers have hardened security contexts | 01 | VERIFIED | 5x `runAsNonRoot: true`, 5x `readOnlyRootFilesystem: true`, all with `drop: ALL` caps and seccomp |
| P6 | Envoy Gateway Application deploys Helm chart and raw manifests via multi-source | 02 | VERIFIED | 3 sources in application.yaml: values ref, gateway-helm 1.4.0, manifests path |
| P7 | OCI Flexible LB configured at 10Mbps via EnvoyProxy annotations | 02 | VERIFIED | `oci-load-balancer-shape: flexible`, min/max `"10"`, no "Mbps" in file |
| P8 | GatewayClass references EnvoyProxy for OCI LB config | 02 | VERIFIED | `parametersRef` with `name: assessforge-proxy`, `kind: EnvoyProxy` |
| P9 | Gateway has HTTP (80) and HTTPS (443) listeners with TLS termination | 02 | VERIFIED | HTTP listener port 80, HTTPS listener port 443 with `mode: Terminate`, `certificateRefs` to `argocd-tls` |
| P10 | HTTPRoute routes argocd.assessforge.com to ArgoCD Server on port 8080 | 02 | VERIFIED | `argocd-https` HTTPRoute with `backendRefs: argocd-server:8080`, `sectionName: https` |
| P11 | HTTP requests redirect to HTTPS via 301 | 02 | VERIFIED | `argocd-http-redirect` HTTPRoute with `RequestRedirect`, `scheme: https`, `statusCode: 301` |
| P12 | cert-manager installs CRDs via Helm and has Gateway API support enabled | 03 | VERIFIED | `crds.enabled: true`, `crds.keep: true`, `enableGatewayAPI: true`, no deprecated `installCRDs` |
| P13 | ClusterIssuer uses Let's Encrypt production with HTTP-01 Gateway solver | 03 | VERIFIED | `acme-v02.api.letsencrypt.org`, `gatewayHTTPRoute` solver with `parentRefs: assessforge-gateway` |
| P14 | cert-manager Application syncs both Helm chart and ClusterIssuer manifest | 03 | VERIFIED | 3 sources: values ref, cert-manager chart v1.20.1, manifests path; `SkipDryRunOnMissingResource=true` |
| P15 | cert-manager auto-creates Certificate for argocd.assessforge.com via Gateway annotation | 03 | VERIFIED (design) | Gateway has `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation + HTTPS listener hostname + certificateRefs; annotation-driven approach per D-08 |
| P16 | metrics-server configured for OKE private cluster ARM64 nodes | 03 | VERIFIED | `--kubelet-insecure-tls`, `--kubelet-preferred-address-types=InternalIP`, resource limits set |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `gitops-setup/environments/default/addons/argocd/values.yaml` | Full ArgoCD Helm values with SSO, RBAC, hardening | VERIFIED | 124 lines, Dex SSO, RBAC, security contexts on 5 components, resource limits, --insecure |
| `gitops-setup/bootstrap/control-plane/argocd/application.yaml` | Self-managed Application with ignoreDifferences | VERIFIED | 41 lines, prune: false, selfHeal: true, ignoreDifferences, RespectIgnoreDifferences |
| `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/envoy-proxy.yaml` | EnvoyProxy with OCI LB annotations | VERIFIED | 16 lines, flexible shape, 10/10 bandwidth |
| `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/gateway-class.yaml` | GatewayClass linked to EnvoyProxy | VERIFIED | 13 lines, parametersRef to assessforge-proxy |
| `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/gateway.yaml` | Gateway with HTTP+HTTPS listeners | VERIFIED | 30 lines, cert-manager annotation, TLS termination, allowedRoutes from All |
| `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/httproute-argocd.yaml` | HTTPRoute for ArgoCD + redirect | VERIFIED | 39 lines, two HTTPRoutes (HTTPS route + HTTP redirect) |
| `gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml` | 3-source Application | VERIFIED | 3 sources: values ref, gateway-helm 1.4.0, manifests path |
| `gitops-setup/bootstrap/control-plane/addons/cert-manager/manifests/cluster-issuer.yaml` | Let's Encrypt ClusterIssuer with gatewayHTTPRoute | VERIFIED | 18 lines, acme-v02, gatewayHTTPRoute solver |
| `gitops-setup/bootstrap/control-plane/addons/cert-manager/application.yaml` | 3-source Application with SkipDryRunOnMissingResource | VERIFIED | 3 sources, SkipDryRunOnMissingResource=true, cert-manager v1.20.1 |
| `gitops-setup/environments/default/addons/cert-manager/values.yaml` | CRD install + Gateway API enabled | VERIFIED | 10 lines, crds.enabled, enableGatewayAPI |
| `gitops-setup/environments/default/addons/metrics-server/values.yaml` | OKE private cluster flags | VERIFIED | 15 lines, kubelet-insecure-tls, InternalIP, resource limits |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| argocd/values.yaml | argocd-dex-github-secret ExternalSecret | `dex.envFrom.secretRef` | WIRED | `secretRef.name: argocd-dex-github-secret` matches ExternalSecret target name; `$client_id`/`$client_secret` match ExternalSecret secretKey values |
| gateway-class.yaml | envoy-proxy.yaml | parametersRef | WIRED | `parametersRef.name: assessforge-proxy` matches EnvoyProxy metadata.name |
| gateway.yaml | gateway-class.yaml | gatewayClassName | WIRED | `gatewayClassName: assessforge-gateway-class` matches GatewayClass metadata.name |
| httproute-argocd.yaml | gateway.yaml | parentRefs | WIRED | `parentRefs.name: assessforge-gateway` matches Gateway metadata.name; `sectionName: https/http` matches listener names |
| cluster-issuer.yaml | gateway.yaml | gatewayHTTPRoute parentRefs | WIRED | `parentRefs.name: assessforge-gateway, namespace: envoy-gateway-system` matches Gateway location |
| gateway.yaml annotation | ClusterIssuer | cert-manager.io/cluster-issuer: letsencrypt-prod | WIRED | Gateway annotation value `letsencrypt-prod` matches ClusterIssuer metadata.name |
| cert-manager values | cert-manager Application | Helm valueFiles reference | WIRED | Application source 2 references `$values/environments/default/addons/cert-manager/values.yaml` |
| argocd application.yaml | argocd values.yaml | Helm valueFiles reference | WIRED | Application source 2 references `$values/environments/default/addons/argocd/values.yaml` |
| metrics-server application.yaml | metrics-server values.yaml | Helm valueFiles reference | WIRED | Application source 2 references `$values/environments/default/addons/metrics-server/values.yaml` |

### Data-Flow Trace (Level 4)

Not applicable -- this phase produces declarative Kubernetes/Helm configuration manifests, not runnable code with dynamic data rendering. Data flow is GitOps-based: Git commit -> ArgoCD sync -> cluster state.

### Behavioral Spot-Checks

Step 7b: SKIPPED (no runnable entry points). All artifacts are declarative YAML manifests managed by ArgoCD. Behavioral verification requires a live cluster with ArgoCD syncing.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| ARGO-01 | 01 | ArgoCD self-managed Application with prune: false | SATISFIED | application.yaml: prune: false, selfHeal: true, chart argo-cd v9.5.0 |
| ARGO-02 | 01 | GitHub SSO via Dex (org: AssessForge, OAuth via ESO) | SATISFIED | values.yaml: Dex GitHub connector, envFrom argocd-dex-github-secret |
| ARGO-03 | 01 | RBAC: org members admin, default deny | SATISFIED | values.yaml: policy.default role:none, g AssessForge role:admin |
| ARGO-04 | 01 | ArgoCD admin disabled, exec disabled | SATISFIED | values.yaml: admin.enabled "false", exec.enabled "false" |
| ARGO-05 | 01 | ArgoCD repo credentials stored as ExternalSecret | SATISFIED | external-secret-repo-creds.yaml exists from Phase 2 with argocd.argoproj.io/secret-type: repo-creds label |
| GW-01 | 02 | Envoy Gateway deployed via GitOps with Gateway API | SATISFIED | application.yaml with gateway-helm v1.4.0 + manifests multi-source |
| GW-02 | 02 | OCI LB annotations: flexible shape, free tier 10Mbps | SATISFIED | envoy-proxy.yaml: flexible shape, min/max "10" |
| GW-03 | 02 | GatewayClass and Gateway resources created | SATISFIED | gateway-class.yaml and gateway.yaml with correct linkage |
| GW-04 | 02 | HTTPRoute for ArgoCD Server (replacing old Ingress) | SATISFIED | httproute-argocd.yaml: argocd-server:8080, HTTPS + HTTP redirect |
| GW-05 | 02 | OCI LB verified as free tier eligible | SATISFIED | Flexible shape 10/10 bandwidth within Always Free 1 LB allowance |
| CERT-01 | 03 | cert-manager deployed via GitOps with pinned chart | SATISFIED | application.yaml with cert-manager v1.20.1 pinned |
| CERT-02 | 03 | ClusterIssuer for Let's Encrypt with HTTP-01 solver | SATISFIED | cluster-issuer.yaml: acme-v02, gatewayHTTPRoute solver |
| CERT-03 | 03 | Certificate for argocd.assessforge.com | SATISFIED | Annotation-driven: Gateway annotation + ClusterIssuer = auto-created Certificate for argocd-tls |
| CERT-04 | 03 | TLS termination end-to-end (LB -> Envoy -> ArgoCD) | SATISFIED (code) | Gateway TLS Terminate mode, ArgoCD --insecure, HTTPRoute to port 8080; runtime verification human-needed |
| MS-01 | 03 | metrics-server deployed via GitOps with pinned chart | SATISFIED | application.yaml with metrics-server v3.13.0 pinned |
| MS-02 | 03 | kubectl top nodes/pods return data | SATISFIED (code) | values.yaml with kubelet-insecure-tls and InternalIP flags for OKE |

**Orphaned requirements:** None. All 16 Phase 3 requirements (ARGO-01 through ARGO-05, GW-01 through GW-05, CERT-01 through CERT-04, MS-01 through MS-02) are claimed by plans and have implementation evidence.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `environments/default/addons/envoy-gateway/values.yaml` | 1-2 | Stub comment "Stub -- valores configurados na Phase 3" with `{}` | Info | Cosmetic only -- Application uses `ignoreMissingValueFiles: true`, and D-04 decision explicitly places OCI LB config on EnvoyProxy CR, not Helm values. File is unused but harmless. |

No TODO, FIXME, PLACEHOLDER, or empty implementation patterns found in any Phase 3 artifact.

### Human Verification Required

All 5 roadmap success criteria are verified at the code level but require a live cluster for runtime confirmation. This is expected for infrastructure-as-code phases where artifacts are declarative YAML.

### 1. GitHub SSO Login

**Test:** Navigate to https://argocd.assessforge.com, click "Log in via GitHub", authenticate with a GitHub account in the AssessForge org.
**Expected:** OAuth flow completes, user sees ArgoCD dashboard with admin access. Attempting login with a non-org GitHub account is denied.
**Why human:** Requires live cluster, DNS, GitHub OAuth App, and OCI Vault secrets all working together.

### 2. TLS Certificate Validity

**Test:** Open https://argocd.assessforge.com in a browser and inspect the certificate.
**Expected:** Valid Let's Encrypt certificate for argocd.assessforge.com, no browser warnings, padlock icon visible.
**Why human:** Requires DNS pointing to OCI LB IP, cert-manager completing ACME HTTP-01 challenge with Let's Encrypt.

### 3. Envoy Gateway Routing Active

**Test:** Run `kubectl get gatewayclass,gateway,httproute -A` and verify all resources show Accepted/Programmed status.
**Expected:** GatewayClass Accepted, Gateway Programmed with external LB IP, both HTTPRoutes Accepted.
**Why human:** Requires live cluster with Envoy Gateway controller reconciling resources.

### 4. Metrics-Server Data

**Test:** Run `kubectl top nodes && kubectl top pods -A`.
**Expected:** Both commands return CPU and memory usage metrics.
**Why human:** Requires live cluster with metrics-server scraping kubelet endpoints.

### 5. No Local Admin Account

**Test:** Attempt to login to ArgoCD with username `admin` and any password.
**Expected:** Login fails. No admin account exists.
**Why human:** Requires live ArgoCD instance.

### Gaps Summary

No code-level gaps found. All 16 requirements are satisfied in the codebase. All must-have truths from the roadmap and plans are verified with concrete evidence. All key links between artifacts are wired correctly. The only remaining verification is runtime confirmation on a live cluster, which is standard for infrastructure-as-code phases.

The single informational note is the leftover stub comment in `environments/default/addons/envoy-gateway/values.yaml`, which is harmless due to `ignoreMissingValueFiles: true` and the D-04 design decision to configure OCI LB via EnvoyProxy CR rather than Helm values.

---

_Verified: 2026-04-10T20:30:00Z_
_Verifier: Claude (gsd-verifier)_
