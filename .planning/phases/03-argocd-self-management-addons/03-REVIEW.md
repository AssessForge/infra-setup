---
phase: 03-argocd-self-management-addons
reviewed: 2026-04-10T12:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cert-manager/application.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/cert-manager/manifests/cluster-issuer.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/envoy-proxy.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/gateway-class.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/gateway.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/httproute-argocd.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/bootstrap/control-plane/argocd/application.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/environments/default/addons/argocd/values.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/environments/default/addons/cert-manager/values.yaml
  - /home/rodrigo/projects/AssessForge/gitops-setup/environments/default/addons/metrics-server/values.yaml
findings:
  critical: 1
  warning: 3
  info: 2
  total: 6
status: issues_found
---

# Phase 03: Code Review Report

**Reviewed:** 2026-04-10T12:00:00Z
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Reviewed the Phase 03 GitOps manifests for ArgoCD self-management, Envoy Gateway routing, cert-manager with Let's Encrypt HTTP-01, and metrics-server. The overall structure is solid -- sync waves are well-ordered (ESO wave 1, ExternalSecrets wave 2, addons wave 3), security hardening is thorough (all containers have restricted security contexts), and the multi-source Application pattern correctly separates Helm values from manifests.

One critical issue: missing Gateway API ReferenceGrant for cross-namespace HTTPRoute references. Three warnings around RBAC group matching, cert-manager CRD ordering, and kubelet-insecure-tls usage.

## Critical Issues

### CR-01: Missing ReferenceGrant for cross-namespace Gateway API references

**File:** `bootstrap/control-plane/addons/envoy-gateway/manifests/httproute-argocd.yaml:8-11`
**Issue:** The HTTPRoute in namespace `argocd` references a Gateway in namespace `envoy-gateway-system` via `parentRefs`. Gateway API requires a `ReferenceGrant` in the `envoy-gateway-system` namespace to permit cross-namespace parentRef bindings. Without it, conformant Gateway API implementations will reject the route attachment, and the HTTPRoute will show `Accepted: False` with reason `RefNotPermitted`.

The same applies to cert-manager's HTTP-01 solver, which creates temporary HTTPRoutes referencing the Gateway in `envoy-gateway-system`.

**Fix:** Add a ReferenceGrant manifest in the envoy-gateway manifests directory:

```yaml
# ReferenceGrant -- permite HTTPRoutes de outros namespaces referenciarem o Gateway
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-httproutes-to-gateway
  namespace: envoy-gateway-system
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: argocd
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: cert-manager
  to:
  - group: gateway.networking.k8s.io
    kind: Gateway
```

Place this at `bootstrap/control-plane/addons/envoy-gateway/manifests/reference-grant.yaml`. The `cert-manager` namespace entry allows the HTTP-01 solver to create temporary routes.

## Warnings

### WR-01: ArgoCD RBAC group claim may not match Dex GitHub connector output

**File:** `environments/default/addons/argocd/values.yaml:44`
**Issue:** The RBAC mapping `g, AssessForge, role:admin` assumes Dex returns the bare org name `AssessForge` as the group claim. However, depending on the Dex GitHub connector version and whether teams are configured, the group format may differ. If teams are later added to the `orgs` config, the group format changes to `AssessForge:team-name`, breaking this mapping silently (users would get `role:none` -- locked out).

**Fix:** This works correctly for the current config (org-only, no teams). Add a comment documenting the coupling:

```yaml
  rbac:
    policy.default: "role:none"
    # Grupo retornado pelo Dex e o nome da org (sem teams configurados).
    # Se adicionar teams na config do Dex, o formato muda para "OrgName:TeamName".
    policy.csv: |
      g, AssessForge, role:admin
```

### WR-02: cert-manager ClusterIssuer synced alongside CRD installation may race

**File:** `bootstrap/control-plane/addons/cert-manager/application.yaml:27`
**Issue:** The cert-manager Application uses multi-source to deploy both the Helm chart (which installs CRDs) and the manifests directory (which contains the ClusterIssuer) in the same sync operation. The `SkipDryRunOnMissingResource=true` syncOption on line 38 mitigates the dry-run failure, but the ClusterIssuer resource could still be applied before cert-manager's webhook is ready, causing a transient validation failure.

**Fix:** The `SkipDryRunOnMissingResource=true` and `ServerSideApply=true` options should handle this in most cases, and ArgoCD will retry on failure. This is an acceptable risk given the retry behavior. However, if this causes persistent sync failures during initial bootstrap, consider splitting the ClusterIssuer into a separate Application at sync-wave "4" or adding a sync-wave annotation to the ClusterIssuer manifest itself:

```yaml
metadata:
  name: letsencrypt-prod
  annotations:
    argocd.argoproj.io/sync-wave: "1"
```

(Within the Application's own sync phases, wave "1" would apply after wave "0" Helm resources.)

### WR-03: metrics-server uses --kubelet-insecure-tls

**File:** `environments/default/addons/metrics-server/values.yaml:7`
**Issue:** The `--kubelet-insecure-tls` flag disables TLS certificate verification when metrics-server connects to kubelets. This is a common workaround for OKE private clusters where kubelet certificates are not signed by the cluster CA, but it does weaken the security posture by allowing potential MITM between metrics-server and kubelets.

**Fix:** This is an accepted trade-off for OKE private clusters and is documented in Oracle's own OKE guidance. Add a comment explaining why:

```yaml
# --kubelet-insecure-tls necessario porque OKE nao assina certificados kubelet
# com a CA do cluster. Risco mitigado: comunicacao e intra-cluster na subnet privada.
- --kubelet-insecure-tls
```

## Info

### IN-01: ArgoCD Application has prune disabled

**File:** `bootstrap/control-plane/argocd/application.yaml:36`
**Issue:** The ArgoCD self-management Application sets `prune: false`, unlike other Applications which use `prune: true`. This means resources removed from the values file will become orphaned in the cluster rather than being deleted.

**Fix:** This is likely intentional for safety (preventing ArgoCD from pruning its own critical resources during upgrades). No change needed, but consider adding a comment:

```yaml
    automated:
      # prune desabilitado para seguranca -- evita que ArgoCD delete seus proprios recursos
      prune: false
```

### IN-02: All addon Applications use sync-wave "3" with no relative ordering

**File:** `bootstrap/control-plane/addons/cert-manager/application.yaml:10`, `bootstrap/control-plane/addons/envoy-gateway/application.yaml:10`, `bootstrap/control-plane/addons/metrics-server/application.yaml:10`
**Issue:** cert-manager, envoy-gateway, and metrics-server all share sync-wave "3". This means ArgoCD syncs them in parallel. While this is fine for metrics-server (independent), the Gateway resources in envoy-gateway depend on having the GatewayClass CRD (installed by envoy-gateway's own Helm chart), and the ClusterIssuer depends on cert-manager CRDs. Each Application handles this internally via multi-source, but the cert-manager ClusterIssuer also references the Gateway (for HTTP-01 solver), creating a cross-Application dependency: cert-manager's ClusterIssuer needs the Gateway from envoy-gateway to exist.

**Fix:** This is acceptable because cert-manager will simply retry ACME registration when the Gateway becomes available. The ClusterIssuer will be created but remain in a non-ready state until the Gateway exists. No ordering change needed -- document the expected transient state during bootstrap if desired.

---

_Reviewed: 2026-04-10T12:00:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
