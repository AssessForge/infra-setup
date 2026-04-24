---
phase: 03-argocd-self-management-addons
plan: 02
subsystem: envoy-gateway-routing
tags: [gateway-api, envoy-gateway, oci-lb, tls, routing]
dependency_graph:
  requires: []
  provides: [gateway-api-manifests, envoy-gateway-multisource]
  affects: [argocd-external-access, tls-termination]
tech_stack:
  added: [Gateway API v1, EnvoyProxy CRD]
  patterns: [multi-source-application, gateway-api-routing, http-to-https-redirect]
key_files:
  created:
    - gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/envoy-proxy.yaml
    - gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/gateway-class.yaml
    - gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/gateway.yaml
    - gitops-setup/bootstrap/control-plane/addons/envoy-gateway/manifests/httproute-argocd.yaml
  modified:
    - gitops-setup/bootstrap/control-plane/addons/envoy-gateway/application.yaml
decisions:
  - OCI LB bandwidth values as bare strings "10" without units (OCI API requirement)
  - Both HTTP and HTTPS listeners allow routes from All namespaces (required for cross-namespace HTTPRoute and cert-manager HTTP-01 challenges)
  - ArgoCD backend on port 8080 plain HTTP (TLS terminated at Gateway, ArgoCD runs --insecure)
metrics:
  duration: 97s
  completed: "2026-04-10T18:54:26Z"
  tasks_completed: 2
  tasks_total: 2
  files_created: 4
  files_modified: 1
---

# Phase 3 Plan 2: Envoy Gateway Routing Summary

Gateway API manifests for OCI Flexible LB routing with TLS termination to ArgoCD via Envoy Gateway multi-source Application.

## What Was Done

### Task 1: Create Gateway API manifest files in envoy-gateway/manifests/

Created 4 Gateway API manifests in the `manifests/` subdirectory:

1. **envoy-proxy.yaml** -- EnvoyProxy CR configuring OCI Flexible LB at 10 bandwidth (free tier). Annotations set `oci-load-balancer-shape: flexible` with min/max at `"10"`.

2. **gateway-class.yaml** -- GatewayClass `assessforge-gateway-class` referencing the EnvoyProxy via `parametersRef`, using `gateway.envoyproxy.io/gatewayclass-controller`.

3. **gateway.yaml** -- Gateway `assessforge-gateway` with two listeners:
   - HTTP (port 80) for redirect and ACME challenges, `allowedRoutes.from: All`
   - HTTPS (port 443) for TLS termination on `argocd.assessforge.com`, referencing `argocd-tls` Secret
   - `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation for automatic certificate provisioning

4. **httproute-argocd.yaml** -- Two HTTPRoutes:
   - `argocd-https`: routes HTTPS traffic to `argocd-server:8080` in argocd namespace
   - `argocd-http-redirect`: 301 redirect from HTTP to HTTPS

**Commit:** `89f1241` (gitops-setup)

### Task 2: Add third multi-source entry to Envoy Gateway Application

Updated `application.yaml` to add a third source pointing to `bootstrap/control-plane/addons/envoy-gateway/manifests`. The Application now has 3 sources:
1. Git repo with `ref: values` for Helm value files
2. OCI Helm chart `gateway-helm` at `1.4.0`
3. Git repo with `path` to raw manifests directory

**Commit:** `3502794` (gitops-setup)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Removed "Mbps" from envoy-proxy.yaml comment**
- **Found during:** Task 1
- **Issue:** Initial file comment contained "10Mbps" which violated acceptance criterion "does NOT contain Mbps anywhere"
- **Fix:** Changed comment to "10 bandwidth" instead of "10Mbps"
- **Files modified:** envoy-proxy.yaml
- **Commit:** included in `89f1241`

## Known Stubs

None -- all manifests contain production-ready configuration values.

## Verification Results

All acceptance criteria verified:
- EnvoyProxy: correct apiVersion, OCI LB annotations with bare "10" values, no "Mbps"
- GatewayClass: correct controllerName, parametersRef to assessforge-proxy
- Gateway: cert-manager annotation, hostname, TLS certificateRef, both listeners with `from: All`
- HTTPRoute: argocd-server backend on port 8080, 301 redirect, correct sectionName references
- Application: 3 sources including manifests path, existing sources unchanged

## Self-Check: PASSED

- All 4 manifest files exist in gitops-setup
- Both commits verified (89f1241, 3502794)
- SUMMARY.md created
