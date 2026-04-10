---
status: partial
phase: 03-argocd-self-management-addons
source: [03-VERIFICATION.md]
started: 2026-04-10T19:15:00Z
updated: 2026-04-10T19:15:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. GitHub SSO Login
expected: Navigate to https://argocd.assessforge.com, OAuth flow completes with admin access for AssessForge org member; non-org accounts denied
result: [pending]

### 2. TLS Certificate Validity
expected: Inspect certificate at https://argocd.assessforge.com — valid Let's Encrypt cert, no browser warnings
result: [pending]

### 3. Envoy Gateway Routing Active
expected: `kubectl get gatewayclass,gateway,httproute -A` shows all resources Accepted/Programmed with LB IP assigned
result: [pending]

### 4. Metrics-Server Data
expected: `kubectl top nodes && kubectl top pods -A` returns CPU and memory usage data
result: [pending]

### 5. No Local Admin Account
expected: Attempt admin login at ArgoCD — login fails (admin.enabled: "false")
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
