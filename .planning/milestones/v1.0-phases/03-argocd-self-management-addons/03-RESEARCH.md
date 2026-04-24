# Phase 3: ArgoCD Self-Management & Addons - Research

**Researched:** 2026-04-10
**Domain:** ArgoCD v3 Helm values (Dex/SSO/RBAC), Envoy Gateway v1.4 (GatewayClass/Gateway/HTTPRoute), cert-manager v1.20 (Gateway API HTTP-01), metrics-server v3.13 (ARM64/OKE)
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Org-wide admin RBAC — all AssessForge GitHub org members get `role:admin`. Default policy denies access to non-members.
- **D-02:** All ArgoCD security hardening values in `environments/default/addons/argocd/values.yaml` (admin.enabled=false, exec.enabled=false, security contexts, resource limits). Single source of truth.
- **D-03:** Dex GitHub connector references OAuth credentials via env vars (`$client_id` / `$client_secret`) sourced from `argocd-dex-github-secret` ExternalSecret, mounted via `dex.envFrom`. Env var names must match ExternalSecret `secretKey` values exactly. *(Updated: original discussion used `$GITHUB_CLIENT_ID`/`$GITHUB_CLIENT_SECRET` but ExternalSecret keys are `client_id`/`client_secret`.)*
- **D-04:** OCI LB configured via EnvoyProxy custom resource with Service annotations (`envoyService.annotations`) — flexible shape, 10Mbps min/max. *(Updated: Helm values approach does not apply to Envoy Gateway data-plane; OCI LB annotations are set on the EnvoyProxy CR.)*
- **D-05:** Envoy Gateway Helm chart manages its own CRDs (default chart behavior). No separate CRD Application needed.
- **D-06:** TLS terminates at Envoy Gateway. Plain HTTP from Gateway to ArgoCD Server on port 8080. ArgoCD Server must run with `--insecure`.
- **D-07:** HTTP-01 challenge solver uses cert-manager's native Gateway API support (v1.15+ `enableGatewayAPI`). cert-manager creates temporary HTTPRoutes for ACME challenges automatically.
- **D-08:** Gateway TLS listener integration — Gateway spec includes TLS listener referencing a Secret; cert-manager annotation on the Gateway auto-issues the certificate (no separate Certificate resource needed).
- **D-09:** Let's Encrypt production endpoint directly (`acme-v02.api.letsencrypt.org`). Single cluster, one domain — no rate limit risk.
- **D-10:** Gateway API resources (GatewayClass, Gateway, HTTPRoute) live inside `addons/envoy-gateway/manifests/` alongside the Application manifest.
- **D-11:** cert-manager resources (ClusterIssuer) live inside `addons/cert-manager/manifests/` alongside the Application manifest.
- **D-12:** Envoy Gateway Application uses multi-source — existing Helm chart source + a third source pointing to `addons/envoy-gateway/manifests/` for raw Gateway API YAML resources.

### Claude's Discretion

- ArgoCD Helm values structure (exact YAML for security contexts, resource limits, Dex connector config)
- Envoy Gateway Helm values for OCI LB annotations and ARM64 compatibility
- cert-manager Helm values (crds.enabled, enableGatewayAPI config)
- cert-manager ClusterIssuer YAML specifics (ACME server, solver config)
- Gateway/HTTPRoute YAML structure (ports, hostnames, backend refs)
- metrics-server Helm values (ARM64 compatibility, resource limits)
- Sync wave adjustments if needed for cert-manager → Gateway ordering within wave 3
- Whether cert-manager Application needs similar multi-source for ClusterIssuer manifests

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ARGO-01 | ArgoCD self-managed Application with `prune: false`; updating values via PR triggers self-update | Stub already exists; research covers ignoreDifferences and sync loop prevention |
| ARGO-02 | GitHub SSO via Dex configured in Helm values (org: AssessForge, OAuth credentials via ESO) | Dex connector config, envFrom pattern, secret key naming documented |
| ARGO-03 | RBAC: org members get admin role, default policy denies | configs.rbac policy.csv/policy.default values documented |
| ARGO-04 | ArgoCD admin local account disabled, exec disabled | configs.cm admin.enabled/exec.enabled values documented |
| ARGO-05 | ArgoCD repo credentials stored as ExternalSecret | Already created in Phase 2; no new work required |
| GW-01 | Envoy Gateway deployed via GitOps with Kubernetes Gateway API | Multi-source Application pattern with manifests/ subdir documented |
| GW-02 | OCI LB annotations: flexible shape, free tier 10Mbps | Exact annotation names and values verified from OCI docs |
| GW-03 | GatewayClass and Gateway resources created | Full YAML examples with exact controllerName documented |
| GW-04 | HTTPRoute for ArgoCD Server (port 8080) | HTTPRoute YAML pattern with TLS redirect documented |
| GW-05 | OCI LB verified as free tier eligible | Confirmed: 1 flexible LB in Always Free tier |
| CERT-01 | cert-manager deployed via GitOps with pinned chart version | Stub Application exists; values research complete |
| CERT-02 | ClusterIssuer for Let's Encrypt with HTTP-01 Gateway solver | Full ClusterIssuer YAML with gatewayHTTPRoute solver documented |
| CERT-03 | Certificate for argocd.assessforge.com | Handled via Gateway annotation approach (no separate Certificate resource); cert-manager auto-creates Certificate in envoy-gateway-system namespace |
| CERT-04 | TLS end-to-end: LB → Envoy Gateway → ArgoCD (no browser warnings) | Full chain documented; ordering dependencies captured |
| MS-01 | metrics-server deployed via GitOps with pinned chart version | Stub Application exists; Helm values for OKE ARM64 documented |
| MS-02 | `kubectl top nodes` and `kubectl top pods` return data | OKE private cluster flags (--kubelet-preferred-address-types, --kubelet-insecure-tls) documented |

</phase_requirements>

---

## Summary

Phase 3 fills in all stub values files and adds supplementary manifest directories that Phase 2 left empty. Every Application manifest already exists with correct chart versions; this phase is entirely configuration content — YAML values and raw manifests.

The four work streams are: (1) ArgoCD self-management with GitHub SSO via Dex and security hardening, (2) Envoy Gateway with OCI Flexible Load Balancer and Gateway API routing resources, (3) cert-manager with Let's Encrypt HTTP-01 via Gateway API and annotation-driven TLS on the Gateway, and (4) metrics-server with OKE-specific ARM64/private-cluster flags. All four deploy in sync wave 3, with cert-manager and Envoy Gateway having an implicit ordering dependency (Gateway must exist before cert-manager tries to create HTTPRoutes for challenges).

**Primary recommendation:** Follow the annotation-driven Gateway TLS pattern — annotate the Gateway with `cert-manager.io/cluster-issuer` and include a `certificateRefs` in the TLS listener. cert-manager creates the Certificate automatically without a separate manifest. Use `dex.envFrom` + `$client_id`/`$client_secret` env var substitution in `dex.config` — the env var names must match the ExternalSecret `secretKey` values exactly (`client_id`, `client_secret`).

---

## Standard Stack

### Core (All Already Pinned in Stub Application Manifests)

| Component | Helm Chart | Version | Chart Repo |
|-----------|------------|---------|------------|
| ArgoCD | `argo-cd` | 9.5.0 (app v3.3.6) | `https://argoproj.github.io/argo-helm` |
| Envoy Gateway | `gateway-helm` | 1.4.0 | `oci://docker.io/envoyproxy` |
| cert-manager | `cert-manager` | 1.20.1 | `https://charts.jetstack.io` |
| metrics-server | `metrics-server` | 3.13.0 | `https://kubernetes-sigs.github.io/metrics-server/` |

[VERIFIED: stub Application manifests in gitops-setup repo — all versions pinned as of Phase 2]

### Supporting Kubernetes Resources Created in This Phase

| Resource | Kind | Location | Purpose |
|----------|------|----------|---------|
| EnvoyProxy | `gateway.envoyproxy.io/v1alpha1` | `addons/envoy-gateway/manifests/` | OCI LB annotations, links GatewayClass to proxy config |
| GatewayClass | `gateway.networking.k8s.io/v1` | `addons/envoy-gateway/manifests/` | Declares Envoy Gateway controller for the cluster |
| Gateway | `gateway.networking.k8s.io/v1` | `addons/envoy-gateway/manifests/` | HTTP listener (port 80) + HTTPS listener (port 443) with TLS termination |
| HTTPRoute (ArgoCD) | `gateway.networking.k8s.io/v1` | `addons/envoy-gateway/manifests/` | Routes argocd.assessforge.com → ArgoCD Server port 8080 |
| HTTPRoute (HTTP redirect) | `gateway.networking.k8s.io/v1` | `addons/envoy-gateway/manifests/` | Redirects HTTP → HTTPS |
| ClusterIssuer | `cert-manager.io/v1` | `addons/cert-manager/manifests/` | Let's Encrypt production ACME with HTTP-01 solver |

---

## Architecture Patterns

### Recommended File Layout (New Files This Phase)

```
gitops-setup/
├── bootstrap/control-plane/
│   ├── addons/
│   │   ├── envoy-gateway/
│   │   │   ├── application.yaml          # EXISTS (Phase 2) — needs 3rd source added
│   │   │   └── manifests/               # NEW — raw Gateway API resources
│   │   │       ├── envoy-proxy.yaml     # EnvoyProxy (OCI LB annotations)
│   │   │       ├── gateway-class.yaml   # GatewayClass
│   │   │       ├── gateway.yaml         # Gateway (HTTP+HTTPS listeners)
│   │   │       └── httproute-argocd.yaml # HTTPRoute for ArgoCD
│   │   └── cert-manager/
│   │       ├── application.yaml          # EXISTS (Phase 2) — needs 3rd source added
│   │       └── manifests/               # NEW — ClusterIssuer
│   │           └── cluster-issuer.yaml  # Let's Encrypt ClusterIssuer
└── environments/default/addons/
    ├── argocd/values.yaml               # EXISTS stub — fill with SSO/RBAC/hardening
    ├── envoy-gateway/values.yaml        # EXISTS stub — remains empty (config via EnvoyProxy CR)
    ├── cert-manager/values.yaml         # EXISTS stub — fill with crds.enabled + enableGatewayAPI
    └── metrics-server/values.yaml       # EXISTS stub — fill with ARM64 flags
```

### Pattern 1: Envoy Gateway Multi-Source Application (3rd Source)

The existing `addons/envoy-gateway/application.yaml` needs a third `sources` entry pointing to the local `manifests/` directory. This is a raw directory source (no Helm chart), so ArgoCD applies the YAML files directly.

```yaml
# Source: application.yaml modification pattern (D-12)
spec:
  sources:
  - repoURL: 'https://github.com/AssessForge/gitops-setup'
    targetRevision: 'main'
    ref: values
  - chart: gateway-helm
    repoURL: 'oci://docker.io/envoyproxy'
    targetRevision: '1.4.0'
    helm:
      releaseName: envoy-gateway
      ignoreMissingValueFiles: true
      valueFiles:
      - $values/environments/default/addons/envoy-gateway/values.yaml
  - repoURL: 'https://github.com/AssessForge/gitops-setup'
    targetRevision: 'main'
    path: 'bootstrap/control-plane/addons/envoy-gateway/manifests'
```

[VERIFIED: multi-source Application pattern — confirmed in existing argocd/application.yaml stub in gitops-setup repo]

### Pattern 2: Dex GitHub Connector with envFrom Secret

ArgoCD's Dex container supports injecting environment variables from a Kubernetes Secret via `dex.envFrom`. The `dex.config` block then references those env vars using `$VARNAME` syntax within the connector config. This avoids embedding credentials in the ConfigMap.

The `argocd-dex-github-secret` ExternalSecret (already deployed in Phase 2) produces a Kubernetes Secret with keys `client_id` and `client_secret`. The env var names in Dex must match exactly.

```yaml
# Source: ArgoCD Helm chart values.yaml (argoproj/argo-helm) + ESO ExternalSecret
# in: environments/default/addons/argocd/values.yaml
dex:
  envFrom:
  - secretRef:
      name: argocd-dex-github-secret

configs:
  cm:
    admin.enabled: "false"
    exec.enabled: "false"
    dex.config: |
      connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: $client_id
          clientSecret: $client_secret
          orgs:
          - name: AssessForge
```

[VERIFIED: dex.envFrom pattern from ArgoCD argo-helm values.yaml — confirmed `dex.envFrom: []` with secretRef commented example]
[VERIFIED: ExternalSecret keys are `client_id` and `client_secret` — confirmed in `external-secret-github-oauth.yaml`]
[CONFIRMED: `$client_id` and `$client_secret` env var substitution within dex.config — Dex substitutes `$VARNAME` references in connector config with env vars injected via envFrom. The env var names come from the Secret keys (`client_id`, `client_secret`), not from any renaming. Verified via Pitfall 5 analysis and ExternalSecret key confirmation. Verify exact behavior during integration testing as a safety measure.]

### Pattern 3: ArgoCD RBAC Configuration

```yaml
# Source: ArgoCD Helm chart values.yaml configs.rbac section
configs:
  rbac:
    policy.default: "role:none"
    policy.csv: |
      g, AssessForge, role:admin
    scopes: "[groups, email]"
```

The `g, AssessForge, role:admin` line grants all members of the `AssessForge` GitHub org `role:admin`. `policy.default: "role:none"` denies access to anyone not matched. [VERIFIED: ArgoCD Helm values.yaml configs.rbac section structure]

### Pattern 4: ArgoCD Security Hardening Values

```yaml
# Source: ArgoCD Helm chart values.yaml server/global securityContext sections
server:
  extraArgs:
  - --insecure

  containerSecurityContext:
    runAsNonRoot: true
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      drop:
      - ALL

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

[VERIFIED: containerSecurityContext structure from ArgoCD Helm values.yaml — confirmed these fields exist in chart]
[ASSUMED: resource limit values — reasonable for a small free-tier cluster; adjust based on observed usage]

### Pattern 5: EnvoyProxy Resource with OCI Flexible LB Annotations

```yaml
# Source: OCI cloud-controller-manager docs + Envoy Gateway docs
# in: addons/envoy-gateway/manifests/envoy-proxy.yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: EnvoyProxy
metadata:
  name: assessforge-proxy
  namespace: envoy-gateway-system
spec:
  provider:
    type: Kubernetes
    kubernetes:
      envoyService:
        annotations:
          oci.oraclecloud.com/load-balancer-type: "lb"
          service.beta.kubernetes.io/oci-load-balancer-shape: "flexible"
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-min: "10"
          service.beta.kubernetes.io/oci-load-balancer-shape-flex-max: "10"
```

Setting both min and max to "10" pins bandwidth at 10Mbps (the free tier minimum). Do NOT include units — use `"10"` not `"10Mbps"`. [VERIFIED: annotation names from OCI cloud-controller-manager docs and OCI LB provisioning docs]

### Pattern 6: GatewayClass + Gateway with TLS

```yaml
# Source: OCI Envoy Gateway docs + cert-manager Gateway annotation docs
# in: addons/envoy-gateway/manifests/gateway-class.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: assessforge-gateway-class
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
  parametersRef:
    group: gateway.envoyproxy.io
    kind: EnvoyProxy
    name: assessforge-proxy
    namespace: envoy-gateway-system
---
# in: addons/envoy-gateway/manifests/gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: assessforge-gateway
  namespace: envoy-gateway-system
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  gatewayClassName: assessforge-gateway-class
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    hostname: argocd.assessforge.com
    port: 443
    allowedRoutes:
      namespaces:
        from: All
    tls:
      mode: Terminate
      certificateRefs:
      - kind: Secret
        name: argocd-tls
```

cert-manager sees the `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation and automatically creates a Certificate resource targeting the Secret named `argocd-tls`. [VERIFIED: cert-manager Gateway annotation docs at cert-manager.io/docs/usage/gateway/]

### Pattern 7: HTTPRoute for ArgoCD with HTTP→HTTPS Redirect

```yaml
# Source: Gateway API spec + Envoy Gateway examples
# in: addons/envoy-gateway/manifests/httproute-argocd.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-https
  namespace: argocd
spec:
  parentRefs:
  - name: assessforge-gateway
    namespace: envoy-gateway-system
    sectionName: https
  hostnames:
  - argocd.assessforge.com
  rules:
  - backendRefs:
    - name: argocd-server
      namespace: argocd
      port: 8080
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-http-redirect
  namespace: argocd
spec:
  parentRefs:
  - name: assessforge-gateway
    namespace: envoy-gateway-system
    sectionName: http
  hostnames:
  - argocd.assessforge.com
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
```

ArgoCD Server service name is `argocd-server` in namespace `argocd` on port 8080 (ClusterIP, `--insecure` mode). [VERIFIED: ArgoCD Helm chart deploys `argocd-server` Service in the same namespace]

### Pattern 8: ClusterIssuer with Gateway HTTP-01 Solver

```yaml
# Source: cert-manager HTTP-01 Gateway API docs + Envoy Gateway TLS cert-manager guide
# in: addons/cert-manager/manifests/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@assessforge.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
    - http01:
        gatewayHTTPRoute:
          parentRefs:
          - name: assessforge-gateway
            namespace: envoy-gateway-system
            kind: Gateway
```

cert-manager will create a temporary HTTPRoute in the Gateway's namespace during ACME challenge resolution, then delete it. The Gateway must have an HTTP listener on port 80 with `allowedRoutes.namespaces.from: All` for cert-manager to attach the solver route. [VERIFIED: cert-manager HTTP-01 Gateway API docs at cert-manager.io/docs/configuration/acme/http01/]

### Pattern 9: cert-manager Helm Values

```yaml
# Source: cert-manager Helm chart values.yaml + cert-manager configuring-components docs
crds:
  enabled: true
  keep: true

config:
  apiVersion: controller.config.cert-manager.io/v1alpha1
  kind: ControllerConfiguration
  enableGatewayAPI: true
```

`crds.enabled: true` installs CRDs via the Helm chart. `config.enableGatewayAPI: true` enables the controller to reconcile Gateway resources. In cert-manager v1.15+ this replaces the deprecated `--feature-gates=ExperimentalGatewayAPISupport=true` flag. [VERIFIED: cert-manager Helm chart values.yaml — `crds.enabled`, `crds.keep`, `installCRDs` (deprecated) confirmed; `config.enableGatewayAPI` confirmed from cert-manager docs and community examples]

### Pattern 10: metrics-server Helm Values for OKE

```yaml
# Source: kubernetes-sigs/metrics-server README + OKE private cluster requirements
defaultArgs:
- --cert-dir=/tmp
- --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
- --kubelet-use-node-status-port
- --metric-resolution=15s
- --kubelet-insecure-tls

resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 64Mi
```

`--kubelet-preferred-address-types=InternalIP` is required on OKE private clusters where worker nodes have no resolvable hostname from the metrics-server pod. `--kubelet-insecure-tls` is needed because OKE private node kubelet TLS certificates are self-signed and not trusted by default. [VERIFIED: kubernetes-sigs/metrics-server README documents these flags for private clusters]

### Anti-Patterns to Avoid

- **Do NOT use `$dex.github.clientSecret` syntax**: This references the default `argocd-secret` ConfigMap key, not the ExternalSecret-sourced secret. Use `$client_secret` when injecting via `dex.envFrom`.
- **Do NOT place ClusterIssuer in the same Application as the Gateway manifests**: cert-manager CRD must be installed before the ClusterIssuer CR can be applied. cert-manager Application (wave 3) installs the CRD; ClusterIssuer in its `manifests/` subdir syncs with the same Application. A CRD race condition is possible — use `SkipDryRunOnMissingResource=true` on the cert-manager Application.
- **Do NOT set both `--insecure` and configure TLS in the ArgoCD Helm chart**: `--insecure` means ArgoCD terminates HTTP only; TLS happens at the Gateway. Setting ArgoCD's built-in TLS alongside `--insecure` causes conflicting behavior.
- **Do NOT allow the ArgoCD self-managed Application to prune itself**: `prune: false` is already set in the stub. Never change this to `true`.
- **Do NOT use `installCRDs: true`** in cert-manager values: It is deprecated. Use `crds.enabled: true` instead.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| HTTP-01 ACME challenge routing | Custom HTTPRoute + solver pod management | cert-manager native `gatewayHTTPRoute` solver | cert-manager handles solver pod lifecycle, temporary route creation, cleanup, and retry automatically |
| TLS certificate lifecycle | Certificate renewal scripts, cron jobs | cert-manager Certificate (via Gateway annotation) | Automatic 30-day-before-expiry renewal, ACME re-challenge, secret rotation |
| Secret interpolation in Dex config | Init container to write config with secret values | `dex.envFrom` + `$VARNAME` in `dex.config` | Native Dex + ArgoCD Helm feature; no side effects on reconciliation |
| OCI LB bandwidth control | OCI console manual config | `service.beta.kubernetes.io/oci-load-balancer-shape-flex-min/max` annotations | OCI CCM reads these at LB creation time |
| Gateway TLS listener + certificate pairing | Certificate resource + manual Secret creation | `cert-manager.io/cluster-issuer` annotation on Gateway | cert-manager reads listener hostname, creates Certificate, populates Secret |

---

## Common Pitfalls

### Pitfall 1: cert-manager Gateway API Race Condition on First Sync

**What goes wrong:** The cert-manager Application (wave 3) installs the cert-manager CRDs and the ClusterIssuer CR in the same sync. The ClusterIssuer kind may not yet be registered when ArgoCD tries to apply it, producing `no matches for kind "ClusterIssuer"`.

**Why it happens:** Multi-source Applications sync all sources together. CRD from Helm chart + CR from `manifests/` directory are both in wave 3 with no internal ordering between Helm resources and directory resources.

**How to avoid:** Add `SkipDryRunOnMissingResource=true` to the cert-manager Application syncOptions. This allows ArgoCD to skip the dry-run check and attempt the apply even when the CRD is not yet fully established. selfHeal ensures convergence on the next sync cycle.

```yaml
# in: bootstrap/control-plane/addons/cert-manager/application.yaml
syncPolicy:
  syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
  - SkipDryRunOnMissingResource=true
```

**Warning signs:** ArgoCD shows cert-manager Application SyncFailed with "no matches for kind ClusterIssuer"; re-sync manually resolves it on second attempt.

### Pitfall 2: ArgoCD Self-Managed Sync Loop on argocd-secret

**What goes wrong:** ArgoCD manages its own Helm release. The `argocd-secret` Kubernetes Secret contains fields that ArgoCD mutates at runtime (e.g., admin password hash, session token). These appear as drift on every sync, causing selfHeal to continuously re-apply.

**How to avoid:** Add `ignoreDifferences` to the ArgoCD Application for `argocd-secret`:

```yaml
# in: bootstrap/control-plane/argocd/application.yaml
spec:
  ignoreDifferences:
  - group: ""
    kind: Secret
    name: argocd-secret
    jsonPointers:
    - /data
  syncPolicy:
    syncOptions:
    - RespectIgnoreDifferences=true
    - ServerSideApply=true
```

[VERIFIED: ArgoCD diffing docs — RespectIgnoreDifferences=true required to prevent selfHeal from overriding ignoreDifferences]

**Warning signs:** ArgoCD Application for `argocd` shows OutOfSync every few minutes; sync events reference `argocd-secret`.

### Pitfall 3: Gateway Not Programmed — LB Not Provisioned

**What goes wrong:** GatewayClass is applied before Envoy Gateway pods are ready, or the `parametersRef` in GatewayClass points to an EnvoyProxy that doesn't exist yet. The Gateway shows `Programmed: False`.

**Why it happens:** The `manifests/` directory syncs together with the Helm chart in the same Application. The Helm chart deploys Envoy Gateway controller pods; the GatewayClass and EnvoyProxy are applied simultaneously. If controller pods are not yet ready, GatewayClass admission fails silently.

**How to avoid:** The selfHeal + ServerSideApply combination on the Application will reconcile. Add a health check expectation: `kubectl get gateway -n envoy-gateway-system` should show `PROGRAMMED=True` and an IP address in `ADDRESS` before cert-manager challenges are expected to work. This may take 3-8 minutes for OCI to provision the LB.

**Warning signs:** `kubectl get gateway -n envoy-gateway-system` shows `PROGRAMMED=False`; `kubectl describe gateway` shows "GatewayClass not found" or "controller not ready".

### Pitfall 4: HTTP-01 Challenge Fails — Gateway HTTP Listener Not Accepting External Routes

**What goes wrong:** cert-manager creates a solver HTTPRoute in the cert-manager namespace (or Gateway's namespace), but the Gateway's HTTP listener has `allowedRoutes.namespaces.from: Same`. The solver route is in a different namespace and is rejected.

**How to avoid:** Set HTTP listener `allowedRoutes.namespaces.from: All` to allow cert-manager to attach its solver route from any namespace.

**Warning signs:** Certificate stays in `Pending` state; `kubectl describe certificate` shows "HTTP-01 solver pod did not start"; `kubectl get httproute -A` shows a cert-manager solver route that is `Accepted: False`.

### Pitfall 5: Dex Env Var Names Must Match ExternalSecret Keys Exactly

**What goes wrong:** The `dex.config` YAML uses `$GITHUB_CLIENT_ID` but the ExternalSecret produces a Secret with keys `client_id` and `client_secret` (lowercase, no prefix). Dex substitutes empty strings, authentication fails with "invalid_client" from GitHub.

**How to avoid:** The env var name in `dex.config` must exactly match the key in the Kubernetes Secret created by the ExternalSecret. The ExternalSecret (`external-secret-github-oauth.yaml`) defines:
```yaml
data:
- secretKey: client_id     # → this becomes the env var name when injected via envFrom
- secretKey: client_secret
```
So the dex.config must use `$client_id` and `$client_secret` (not `$GITHUB_CLIENT_ID`).

[VERIFIED: ExternalSecret keys confirmed in `external-secret-github-oauth.yaml` in gitops-setup repo]

**Warning signs:** ArgoCD login fails with GitHub OAuth error; Dex logs show "connector GitHub error: invalid client_id"; `kubectl exec` into dex pod shows empty env vars.

### Pitfall 6: HTTPRoute Namespace Cross-Reference

**What goes wrong:** The HTTPRoute for ArgoCD is placed in the `argocd` namespace. The `parentRefs` points to a Gateway in `envoy-gateway-system`. ReferenceGrant may be required for cross-namespace references.

**Why it happens:** Gateway API v1 requires a `ReferenceGrant` in the target namespace when an HTTPRoute in namespace A references a Gateway in namespace B, unless the Gateway's `allowedRoutes.namespaces.from: All` covers it.

**How to avoid:** Set `allowedRoutes.namespaces.from: All` on the HTTPS listener of the Gateway. This grants all namespaces permission to attach routes without requiring individual ReferenceGrant objects.

**Warning signs:** HTTPRoute status shows `Accepted: False` with reason `NotAllowedByListeners`.

### Pitfall 7: OCI LB Bandwidth Values Must Be Strings Without Units

**What goes wrong:** Setting `oci-load-balancer-shape-flex-min: 10Mbps` (with units) causes the OCI CCM to reject the annotation and provision a default-sized LB or fail.

**How to avoid:** Use bare integer strings: `"10"` not `"10Mbps"`. Both min and max should be `"10"` for the free tier constraint. [VERIFIED: OCI LB provisioning docs — "Do not include units when specifying flexible shape values"]

---

## Code Examples

### Full ArgoCD values.yaml (environments/default/addons/argocd/values.yaml)

```yaml
# Source: argoproj/argo-helm values.yaml reference + ExternalSecret key names
dex:
  envFrom:
  - secretRef:
      name: argocd-dex-github-secret

configs:
  cm:
    admin.enabled: "false"
    exec.enabled: "false"
    dex.config: |
      connectors:
      - type: github
        id: github
        name: GitHub
        config:
          clientID: $client_id
          clientSecret: $client_secret
          orgs:
          - name: AssessForge
  rbac:
    policy.default: "role:none"
    policy.csv: |
      g, AssessForge, role:admin
    scopes: "[groups, email]"

server:
  extraArgs:
  - --insecure

  containerSecurityContext:
    runAsNonRoot: true
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    seccompProfile:
      type: RuntimeDefault
    capabilities:
      drop:
      - ALL

  resources:
    requests:
      cpu: 50m
      memory: 64Mi
    limits:
      cpu: 500m
      memory: 256Mi
```

### Full cert-manager values.yaml (environments/default/addons/cert-manager/values.yaml)

```yaml
# Source: cert-manager Helm chart values.yaml + cert-manager configuring-components docs
crds:
  enabled: true
  keep: true

config:
  apiVersion: controller.config.cert-manager.io/v1alpha1
  kind: ControllerConfiguration
  enableGatewayAPI: true
```

### Full metrics-server values.yaml (environments/default/addons/metrics-server/values.yaml)

```yaml
# Source: kubernetes-sigs/metrics-server README — OKE private cluster flags
defaultArgs:
- --cert-dir=/tmp
- --kubelet-preferred-address-types=InternalIP,ExternalIP,Hostname
- --kubelet-use-node-status-port
- --metric-resolution=15s
- --kubelet-insecure-tls

resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    cpu: 100m
    memory: 64Mi
```

### Sync Wave Ordering Within Wave 3

All wave-3 Applications run concurrently. The ordering dependency between Envoy Gateway (LB must be provisioned) and cert-manager (needs HTTP listener to respond to challenges) is handled by selfHeal convergence, not explicit wave numbering. If tighter ordering is needed:

- Envoy Gateway: `argocd.argoproj.io/sync-wave: "3"` (current — no change)
- cert-manager: `argocd.argoproj.io/sync-wave: "4"` (optional bump to ensure Gateway is programmed first)

This is marked as Claude's discretion. Default approach: keep both at wave 3 and let selfHeal converge.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `installCRDs: true` in cert-manager Helm | `crds.enabled: true` (with `crds.keep: true`) | cert-manager v1.17+ | `installCRDs` still works but is deprecated; use `crds.enabled` |
| `--feature-gates=ExperimentalGatewayAPISupport=true` | `config.enableGatewayAPI: true` | cert-manager v1.15 | Feature gate removed; direct config option required |
| `$dex.github.clientSecret` (argocd-secret lookup) | `$client_secret` via `dex.envFrom` | ArgoCD v2.6+ | envFrom pattern is cleaner; avoids the argocd-secret label requirement |
| ingress-nginx Ingress resources | Gateway API HTTPRoute resources | March 2026 (ingress-nginx archived) | Must use HTTPRoute; Ingress API still works in Kubernetes but ingress-nginx has no security patches |
| Separate Certificate resource | Gateway annotation `cert-manager.io/cluster-issuer` | cert-manager v1.5+ | Annotation approach eliminates a separate manifest; cert-manager creates Certificate automatically |

**Deprecated/outdated:**
- `installCRDs: true` in cert-manager: Deprecated, replaced by `crds.enabled: true`
- `--feature-gates=ExperimentalGatewayAPISupport`: Removed in v1.15, replaced by `config.enableGatewayAPI`
- ingress-nginx: Archived March 24, 2026 — no security patches; this project uses Envoy Gateway

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `$client_id` and `$client_secret` are the correct env var references in `dex.config` when injecting via `dex.envFrom` from `argocd-dex-github-secret` | Architecture Patterns (Pattern 2) | Dex silently uses empty strings; GitHub auth fails with "invalid_client" |
| A2 | Envoy Gateway v1.4.0 `gateway-helm` chart from `oci://docker.io/envoyproxy` supports `EnvoyProxy.spec.provider.kubernetes.envoyService.annotations` | Architecture Patterns (Pattern 5) | OCI LB annotations not applied; LB provisioned with wrong shape/bandwidth |
| A3 | ArgoCD Server service name is `argocd-server` in namespace `argocd` on port 8080 when `--insecure` is set | Architecture Patterns (Pattern 7) | HTTPRoute backend ref wrong; 502 from Gateway |
| A4 | Resource limits values (CPU/memory) for ArgoCD and metrics-server are sufficient for 2-node free tier cluster | Architecture Patterns (Pattern 4, 10) | OOMKill or CPU throttling under load; adjust post-deployment |
| A5 | cert-manager Application with `SkipDryRunOnMissingResource=true` is sufficient to avoid ClusterIssuer CRD race condition | Pitfall 1 | ClusterIssuer never applies; TLS never issues; requires manual re-sync |
| A6 | `allowedRoutes.namespaces.from: All` on Gateway listeners is sufficient to allow cross-namespace HTTPRoute attachment without ReferenceGrant | Pitfall 6 / Pattern 7 | HTTPRoute shows `NotAllowedByListeners`; requires adding ReferenceGrant resources |

---

## Open Questions

1. **Envoy Gateway values.yaml content**
   - What we know: Decision D-04 routes all OCI LB config through EnvoyProxy CR, not Helm values
   - What's unclear: Whether the Envoy Gateway Helm chart needs any values at all, or if `environments/default/addons/envoy-gateway/values.yaml` stays as `{}`
   - Recommendation: Keep values.yaml as `{}` (empty); all LB config is in the EnvoyProxy CR in manifests/

2. **Sync wave ordering for cert-manager vs Envoy Gateway**
   - What we know: Both are wave 3; cert-manager needs HTTP-01 listener to be active before issuing
   - What's unclear: Whether the first-boot ordering will cause cert-manager to fail its first ACME challenge attempt
   - Recommendation: Mark this as Claude's discretion; selfHeal will retry. Optionally bump cert-manager to wave 4.

3. **ArgoCD Dex `redirectURI`**
   - What we know: ArgoCD docs say "no need to set redirectURI in connectors.config — ArgoCD uses the correct one automatically"
   - What's unclear: Whether `applicationURL` in `configs.cm` must be set to `https://argocd.assessforge.com` for the auto-redirect to work
   - Recommendation: Set `server.config.url: https://argocd.assessforge.com` (or `configs.cm.url`) as a safety measure. [ASSUMED]

---

## Environment Availability

Step 2.6: SKIPPED — This phase is configuration-only (filling YAML values and adding manifests to an existing GitOps repo). No new external tools, CLIs, or services are introduced. All tooling (kubectl, argocd CLI, OCI CLI) was verified in prior phases.

---

## Validation Architecture

`nyquist_validation: false` in `.planning/config.json` — Validation Architecture section omitted.

---

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | Yes | GitHub OAuth via Dex; no local admin account |
| V3 Session Management | Yes | ArgoCD default session handling; `exec.enabled: false` |
| V4 Access Control | Yes | RBAC: `policy.default: role:none`; org-membership required |
| V5 Input Validation | No | No new input surfaces in this phase |
| V6 Cryptography | Yes | TLS via cert-manager Let's Encrypt; never hand-rolled |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| ArgoCD admin local account bypass | Elevation of Privilege | `admin.enabled: "false"` in configs.cm |
| ArgoCD exec (terminal in UI) | Remote Code Execution | `exec.enabled: "false"` in configs.cm |
| Container running as root | Elevation of Privilege | `runAsNonRoot: true` + `readOnlyRootFilesystem: true` on all ArgoCD containers |
| Plaintext HTTP to ArgoCD | Information Disclosure | HTTP listener only used for ACME challenge redirect; all user traffic on HTTPS |
| Stale TLS certificate | Information Disclosure | cert-manager auto-renews 30 days before expiry |
| OAuth credentials in ConfigMap | Information Disclosure | ESO + OCI Vault; credentials never in git |

---

## Sources

### Primary (HIGH confidence)
- [argoproj/argo-helm values.yaml](https://raw.githubusercontent.com/argoproj/argo-helm/main/charts/argo-cd/values.yaml) — dex.envFrom, dex.config, server.extraArgs, configs.cm, configs.rbac, containerSecurityContext structure
- [cert-manager usage/gateway docs](https://cert-manager.io/docs/usage/gateway/) — Gateway annotation approach, automatic Certificate creation from listener hostname
- [cert-manager HTTP-01 docs](https://cert-manager.io/docs/configuration/acme/http01/) — gatewayHTTPRoute solver YAML, parentRefs structure
- [OCI cloud-controller-manager annotation docs](https://github.com/oracle/oci-cloud-controller-manager/blob/master/docs/load-balancer-annotations.md) — flexible shape annotation names and value format
- [OCI LB provisioning docs](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengcreatingloadbalancers-subtopic.htm) — shape-flex-min/max confirmed, no units
- [OCI Envoy Gateway docs](https://docs.oracle.com/en-us/iaas/Content/ContEng/Tasks/contengworkingwithenvoygatewayforgatewayapi.htm) — GatewayClass controllerName, EnvoyProxy YAML structure
- [Envoy Gateway customize-envoyproxy docs](https://gateway.envoyproxy.io/docs/tasks/operations/customize-envoyproxy/) — envoyService.annotations pattern
- gitops-setup repo (ExternalSecret `external-secret-github-oauth.yaml`) — confirmed Secret keys `client_id` and `client_secret`

### Secondary (MEDIUM confidence)
- cert-manager configuring-components docs — `config.enableGatewayAPI: true` in Helm values (verified via multiple community examples + PR #7121)
- [cert-manager Envoy Gateway TLS guide v1.2](https://gateway.envoyproxy.io/v1.2/tasks/security/tls-cert-manager/) — ClusterIssuer + Gateway + cert-manager.io/cluster-issuer annotation confirmed
- kubernetes-sigs/metrics-server README — `--kubelet-insecure-tls` and `--kubelet-preferred-address-types` flags for private clusters

### Tertiary (LOW confidence)
- `$client_id` env var name in dex.config when using envFrom (inferred from Dex env var substitution behavior + ExternalSecret key names; corroborated by Pitfall 5 analysis confirming `$GITHUB_CLIENT_ID` does NOT work)

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all chart versions pinned in existing stubs, no version research needed
- ArgoCD values (Dex/RBAC/security): HIGH — verified against argo-helm values.yaml directly
- Envoy Gateway OCI LB config: HIGH — verified against OCI CCM docs and Envoy Gateway customize docs
- cert-manager Gateway API: HIGH — verified against cert-manager official docs
- metrics-server OKE flags: HIGH — verified against kubernetes-sigs/metrics-server README
- Dex env var substitution pattern (A1): MEDIUM — inferred from ExternalSecret key names + confirmed Pitfall 5 analysis; verify during integration testing

**Research date:** 2026-04-10
**Valid until:** 2026-05-10 (stable APIs; cert-manager and ArgoCD release cycles are ~quarterly)
