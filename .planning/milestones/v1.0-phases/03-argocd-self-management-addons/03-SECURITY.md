# Phase 03 Security Audit: ArgoCD Self-Management & Addons

**Audit Date:** 2026-04-10
**Auditor:** GSD Security Auditor (automated)
**Phase:** 03 -- ArgoCD Self-Management & Addons
**Threats Closed:** 14/14
**Status:** SECURED

## Threat Verification

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-03-01 | Spoofing | mitigate | `policy.default: "role:none"` + `orgs: - name: AssessForge` in `environments/default/addons/argocd/values.yaml:39-42` |
| T-03-02 | Elevation of Privilege | mitigate | `admin.enabled: "false"` in `environments/default/addons/argocd/values.yaml:27` |
| T-03-03 | Elevation of Privilege | mitigate | `exec.enabled: "false"` in `environments/default/addons/argocd/values.yaml:28` |
| T-03-04 | Elevation of Privilege | mitigate | `runAsNonRoot: true`, `readOnlyRootFilesystem: true`, `drop: [ALL]` on all 5 components (server, controller, repoServer, redis, dex) in `environments/default/addons/argocd/values.yaml:8-15,52-59,70-77,90-97,108-115` |
| T-03-05 | Information Disclosure | mitigate | `$client_id`/`$client_secret` env var substitution in `values.yaml:36-37`; credentials sourced from OCI Vault via ESO `external-secret-github-oauth.yaml`; no plaintext secrets in git |
| T-03-06 | Tampering | mitigate | `ignoreDifferences` for `argocd-secret /data` + `RespectIgnoreDifferences=true` in `bootstrap/control-plane/argocd/application.yaml:29-40` |
| T-03-07 | Tampering | accept | HTTP listener (port 80) open to all namespaces -- required for cert-manager HTTP-01 ACME challenges; listener only serves 301 redirects to HTTPS |
| T-03-08 | Information Disclosure | mitigate | HTTP-to-HTTPS 301 redirect via `statusCode: 301` + `scheme: https` in `bootstrap/control-plane/addons/envoy-gateway/manifests/httproute-argocd.yaml:35-37` |
| T-03-09 | Denial of Service | accept | OCI Flexible LB pinned at 10Mbps (free tier limit) in `envoy-proxy.yaml:14-15`; natural bandwidth throttle sufficient for admin UI |
| T-03-10 | Spoofing | mitigate | HTTPS listener locked to `hostname: argocd.assessforge.com` with TLS `mode: Terminate` + `certificateRefs` in `bootstrap/control-plane/addons/envoy-gateway/manifests/gateway.yaml:20-29` |
| T-03-11 | Spoofing | mitigate | ClusterIssuer `letsencrypt-prod` uses ACME `acme-v02.api.letsencrypt.org` with `gatewayHTTPRoute` solver referencing `assessforge-gateway` in `bootstrap/control-plane/addons/cert-manager/manifests/cluster-issuer.yaml:7-18` |
| T-03-12 | Information Disclosure | mitigate | `privateKeySecretRef: name: letsencrypt-prod-key` in `cluster-issuer.yaml:11`; cert-manager manages key lifecycle as K8s Secret; never stored in git |
| T-03-13 | Tampering | accept | `--kubelet-insecure-tls` in `environments/default/addons/metrics-server/values.yaml:5`; required for OKE private cluster; kubelets on private subnet (10.0.2.0/24) behind NSG |
| T-03-14 | Denial of Service | mitigate | `SkipDryRunOnMissingResource=true` in cert-manager `application.yaml:38` + `selfHeal: true` at line 34 ensures CRD race convergence |

## Accepted Risks Log

| Threat ID | Risk | Justification | Residual Risk |
|-----------|------|---------------|---------------|
| T-03-07 | HTTP listener allows routes from all namespaces | Required for cert-manager HTTP-01 ACME challenges to attach solver HTTPRoutes to the Gateway | Low -- HTTP listener only serves 301 redirects; no application traffic served over HTTP |
| T-03-09 | OCI LB bandwidth capped at 10Mbps | Free tier constraint; ArgoCD admin UI has low bandwidth requirements | Low -- natural throttle prevents abuse; insufficient for DDoS amplification |
| T-03-13 | metrics-server uses kubelet-insecure-tls | OKE private cluster kubelets use self-signed TLS certificates | Low -- kubelet traffic is cluster-internal on private subnet behind NSG; no external exposure |

## Unregistered Flags

None -- no `## Threat Flags` sections found in any SUMMARY.md file.
