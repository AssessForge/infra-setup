# Phase 2: GitOps Repository & ESO - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-10
**Phase:** 02-gitops-repository-eso
**Areas discussed:** Repo structure, ApplicationSet design, ESO auth strategy, Sync wave order

---

## Repo Structure

### Q1: Directory Layout

| Option | Description | Selected |
|--------|-------------|----------|
| Flat addon dir | bootstrap/control-plane/ contains ApplicationSet(s) + per-addon dirs. environments/ holds values overrides. Matches gitops-bridge reference repos. | ✓ |
| Separate bootstrap + apps | bootstrap/ only has the ApplicationSet. addons/ at repo root holds per-addon manifests. Cleaner separation but deeper paths. | |
| You decide | Claude picks the structure that best fits the gitops-bridge pattern. | |

**User's choice:** Flat addon dir (Recommended)
**Notes:** None

### Q2: ArgoCD Self-Management Location

| Option | Description | Selected |
|--------|-------------|----------|
| Same dir | bootstrap/control-plane/argocd/ alongside addons. Single sync point. | ✓ |
| Separate dir | Dedicated bootstrap/argocd/ path. Requires restructuring bootstrap source path. | |
| You decide | Claude picks based on bootstrap Application path. | |

**User's choice:** Same dir (Recommended)
**Notes:** None

### Q3: Per-Addon Directory Contents

| Option | Description | Selected |
|--------|-------------|----------|
| Helm Application manifest | Application.yaml referencing upstream Helm repo + pinned chart version. Standard gitops-bridge pattern. | ✓ |
| Raw manifests + kustomize | Rendered YAML manifests with kustomize overlays. More control but harder to upgrade. | |
| You decide | Claude picks the approach. | |

**User's choice:** Helm Application manifest (Recommended)
**Notes:** None

---

## ApplicationSet Design

### Q1: Generator Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Single AppSet + matrix | One ApplicationSet with cluster generator x git generator matrix. One file to maintain. | ✓ |
| One AppSet per addon | Separate ApplicationSet YAML per addon. More files but independently toggleable. | |
| You decide | Claude picks based on single-cluster setup. | |

**User's choice:** Single AppSet + matrix (Recommended)
**Notes:** None

### Q2: Feature Flag Filtering

| Option | Description | Selected |
|--------|-------------|----------|
| Convention-based | Addon dir name maps to label (addons/eso/ -> enable_eso). No extra config per addon. | ✓ |
| Explicit mapping file | Config file maps addon dir to feature flag label. More explicit but adds maintenance. | |
| You decide | Claude picks for simplicity. | |

**User's choice:** Convention-based (Recommended)
**Notes:** None

### Q3: ArgoCD Self-Management via AppSet

| Option | Description | Selected |
|--------|-------------|----------|
| Standalone Application | Separate Application.yaml for ArgoCD with unique prune: false sync policy. | ✓ |
| Through the AppSet | ArgoCD as another addon dir in the matrix. Simpler but harder to customize. | |
| You decide | Claude picks based on requirements. | |

**User's choice:** Standalone Application (Recommended)
**Notes:** None

---

## ESO Auth Strategy

### Q1: ClusterSecretStore Scope

| Option | Description | Selected |
|--------|-------------|----------|
| ClusterSecretStore, ns-restricted | Single store with namespaceSelector restricting to argocd namespace. | ✓ |
| ClusterSecretStore, cluster-wide | Single store accessible from any namespace. Less secure. | |
| Per-namespace SecretStore | One SecretStore per namespace. Most restrictive but more manifests. | |
| You decide | Claude picks based on security posture. | |

**User's choice:** ClusterSecretStore, ns-restricted (Recommended)
**Notes:** None

### Q2: Which ExternalSecrets to Create

| Option | Description | Selected |
|--------|-------------|----------|
| OAuth + repo creds | ExternalSecrets for GitHub OAuth and repo credentials. Skip notification tokens. | ✓ |
| All three | OAuth, repo creds, AND notification tokens. | |
| You decide | Claude picks based on Phase 3 needs. | |

**User's choice:** OAuth + repo creds (Recommended)
**Notes:** None

### Q3: Repo Credentials Source

| Option | Description | Selected |
|--------|-------------|----------|
| Need to add repo creds to Vault | New OCI Vault secret + Terraform variable for repo credentials. Small TF change. | ✓ |
| Use ArgoCD SSH key instead | Skip vault-stored repo creds. Manual deploy key. | |
| You decide | Claude picks keeping creds in Vault. | |

**User's choice:** Need to add repo creds to Vault
**Notes:** None

---

## Sync Wave Order

### Q1: Ordering Mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| ArgoCD sync waves | sync-wave annotations on Applications. ESO wave 1, secrets wave 2, rest wave 3. | ✓ |
| Health checks only | No explicit ordering. Rely on ArgoCD health checks and retries. | |
| You decide | Claude picks ordering mechanism. | |

**User's choice:** ArgoCD sync waves (Recommended)
**Notes:** None

### Q2: Wave Scope in Phase 2

| Option | Description | Selected |
|--------|-------------|----------|
| Stub all waves now | Create all addon dirs/manifests with sync waves. Phase 3 fills in details. | ✓ |
| Only ESO in Phase 2 | Phase 2 creates only ESO files. Phase 3 does remaining scaffolding. | |
| You decide | Claude picks to minimize rework. | |

**User's choice:** Stub all waves now (Recommended)
**Notes:** None

---

## Claude's Discretion

- Application manifest template structure
- Go template expressions in ApplicationSet
- ESO ClusterSecretStore YAML specifics for OCI Vault + Instance Principal
- ExternalSecret field mapping
- Terraform change structure for repo creds in OCI Vault
- Git init strategy for gitops-setup repo

## Deferred Ideas

None — discussion stayed within phase scope
