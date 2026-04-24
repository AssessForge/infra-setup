---
phase: 03-argocd-self-management-addons
fixed_at: 2026-04-10T12:30:00Z
review_path: .planning/phases/03-argocd-self-management-addons/03-REVIEW.md
iteration: 1
findings_in_scope: 4
fixed: 4
skipped: 0
status: all_fixed
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-04-10T12:30:00Z
**Source review:** .planning/phases/03-argocd-self-management-addons/03-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 4
- Fixed: 4
- Skipped: 0

## Fixed Issues

### CR-01: Missing ReferenceGrant for cross-namespace Gateway API references

**Files modified:** `bootstrap/control-plane/addons/envoy-gateway/manifests/reference-grant.yaml`
**Commit:** e0d9c50
**Applied fix:** Created new ReferenceGrant manifest permitting HTTPRoutes from `argocd` and `cert-manager` namespaces to reference the Gateway in `envoy-gateway-system`. This is required by Gateway API spec for cross-namespace parentRef bindings.

### WR-01: ArgoCD RBAC group claim may not match Dex GitHub connector output

**Files modified:** `environments/default/addons/argocd/values.yaml`
**Commit:** 80a0ba7
**Applied fix:** Added Portuguese comments documenting that the RBAC group format depends on the Dex GitHub connector configuration -- bare org name when no teams are configured, `OrgName:TeamName` format when teams are added.

### WR-02: cert-manager ClusterIssuer synced alongside CRD installation may race

**Files modified:** `bootstrap/control-plane/addons/cert-manager/manifests/cluster-issuer.yaml`
**Commit:** 7181797
**Applied fix:** Added `argocd.argoproj.io/sync-wave: "1"` annotation to the ClusterIssuer metadata, ensuring it is applied after wave "0" Helm resources (CRDs and webhook) within the same Application sync.

### WR-03: metrics-server uses --kubelet-insecure-tls

**Files modified:** `environments/default/addons/metrics-server/values.yaml`
**Commit:** 0120f12
**Applied fix:** Added Portuguese comments explaining why `--kubelet-insecure-tls` is necessary for OKE private clusters (kubelet certificates not signed by cluster CA) and that the risk is mitigated by intra-cluster communication on the private subnet.

## Skipped Issues

None -- all findings were fixed.

---

_Fixed: 2026-04-10T12:30:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
