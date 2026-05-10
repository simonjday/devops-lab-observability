# Kustomization.yaml Files: What Goes Where

## TL;DR

There are **multiple different kustomization.yaml files**, each with a specific purpose:

```
devops-lab-observability/
├── kustomization.yaml                    ← ROOT kustomization (orchestrator)
├── observability/loki/
│   └── kustomization.yaml                ← OPTIONAL: Loki-specific (usually empty)
├── security/falco/
│   └── kustomization.yaml                ← OPTIONAL: Falco-specific (usually empty)
└── overlays/
    ├── dev/kustomization.yaml            ← DEV: patches & dev-specific config
    ├── staging/kustomization.yaml        ← STAGING: patches & staging config
    └── prod/kustomization.yaml           ← PROD: patches & prod config
```

**Each file is different and has a specific purpose.**

---

## 1. Root Kustomization (`kustomization.yaml` - top level)

**Location:** `devops-lab-observability/kustomization.yaml`

**Purpose:** Orchestrates all components in the repo

**Contents:** References the actual manifests (loki-stack.yaml, falco.yaml)

**Use case:** When you run `kustomize build .` or when Flux/ArgoCD point to root

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

commonLabels:
  app.kubernetes.io/managed-by: kustomize
  app.kubernetes.io/part-of: kind-devops-lab

# Include base manifests (the raw YAML files)
resources:
  - observability/loki/loki-stack.yaml
  - security/falco/falco.yaml

# Optional: Common patches for all components
patches:
  - target:
      kind: Deployment
      labelSelector: ""
    patch: |-
      - op: add
        path: /metadata/labels/version
        value: v1.0
```

**When to use:**
- `kustomize build . | kubectl apply -f -`
- When pointing Flux/ArgoCD at root directory
- When you want all components deployed together

---

## 2. Component Kustomizations (Optional)

**Locations:**
- `observability/loki/kustomization.yaml`
- `security/falco/kustomization.yaml`

**Purpose:** Organize component-specific patches and config

**Contents:** Usually minimal or empty (unless you have component-specific patches)

**Example - Loki-specific:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Include the actual Loki manifest
resources:
  - loki-stack.yaml

# Optional: Loki-specific labels
commonLabels:
  component: loki
  part-of: observability

# Optional: Loki-specific patches
# (Usually empty - use root or overlays for patches)
```

**Example - Falco-specific:**
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - falco.yaml

commonLabels:
  component: falco
  part-of: security
```

**When to use:**
- If you have component-specific patches
- If you want to deploy Loki OR Falco independently
- If you're organizing for clarity

**When to skip:**
- If manifests are simple (usually safe to skip)
- If all patches go in root or overlays

---

## 3. Overlay Kustomizations (Different for Each!)

**Locations:**
- `overlays/dev/kustomization.yaml`
- `overlays/staging/kustomization.yaml`
- `overlays/prod/kustomization.yaml`

**Purpose:** Environment-specific patches and configuration

**Key difference:** Each overlay is DIFFERENT (dev != staging != prod)

### Dev Overlay

**Location:** `overlays/dev/kustomization.yaml`

**Purpose:** Smaller resources, dev-specific settings

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Reference the root kustomization as base
bases:
  - ../../

# Override namespace for dev
namespace: observability

# Dev-specific labels
commonLabels:
  environment: dev
  team: platform

# Dev-specific patches: SMALLER storage, fewer resources
patchesJson6902:
  - target:
      kind: StatefulSet
      name: loki
      namespace: observability
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "2Gi"  # Small in dev
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "256Mi"  # Less memory in dev

# Dev ConfigMap overrides
configMapGenerator:
  - name: loki-config
    behavior: merge
    literals:
      - RETENTION_DAYS=3  # Short retention in dev
```

### Staging Overlay

**Location:** `overlays/staging/kustomization.yaml`

**Purpose:** Mid-sized resources, staging settings (DIFFERENT from dev!)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: staging
  team: platform

# Staging patches: MEDIUM storage
patchesJson6902:
  - target:
      kind: StatefulSet
      name: loki
      namespace: observability
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "10Gi"  # Medium in staging
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "512Mi"  # More memory than dev

configMapGenerator:
  - name: loki-config
    behavior: merge
    literals:
      - RETENTION_DAYS=7  # Medium retention
```

### Prod Overlay

**Location:** `overlays/prod/kustomization.yaml`

**Purpose:** Large resources, production settings (DIFFERENT from dev AND staging!)

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: prod
  team: platform
  backup: enabled

# Prod patches: LARGE storage, HA config
patchesJson6902:
  - target:
      kind: StatefulSet
      name: loki
      namespace: observability
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "50Gi"  # Large in prod
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "2Gi"  # Plenty of memory in prod
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "500m"  # More CPU in prod

configMapGenerator:
  - name: loki-config
    behavior: merge
    literals:
      - RETENTION_DAYS=30  # Long retention in prod
      - HA_MODE=true
```

---

## Visual Comparison

```
┌─────────────────────────────────────────────────────────┐
│ Root: kustomization.yaml                                │
│ Purpose: Orchestrate all components                     │
│ resources:                                              │
│   - observability/loki/loki-stack.yaml                 │
│   - security/falco/falco.yaml                          │
└─────────────────────────────────────────────────────────┘
           ↓ (referenced by overlays as base)
┌──────────────────────┬──────────────────────┬──────────────────────┐
│ Dev Overlay          │ Staging Overlay      │ Prod Overlay         │
│ kustomization.yaml   │ kustomization.yaml   │ kustomization.yaml   │
├──────────────────────┼──────────────────────┼──────────────────────┤
│ bases:               │ bases:               │ bases:               │
│   - ../../          │   - ../../          │   - ../../          │
│                      │                      │                      │
│ Storage: 2Gi        │ Storage: 10Gi       │ Storage: 50Gi       │
│ Memory: 256Mi       │ Memory: 512Mi       │ Memory: 2Gi         │
│ Retention: 3 days   │ Retention: 7 days   │ Retention: 30 days  │
│ environment: dev    │ environment: staging│ environment: prod   │
└──────────────────────┴──────────────────────┴──────────────────────┘
```

---

## Usage Patterns

### Pattern 1: Direct (No Overlays)

Use root kustomization directly:

```bash
# Build and apply root
kustomize build devops-lab-observability/ | kubectl apply -f -

# Or point Flux/ArgoCD at root path
# path: ./
```

Result: Default config (5Gi Loki storage, etc.)

---

### Pattern 2: Use Overlay for Dev

```bash
# Build and apply dev overlay
kustomize build devops-lab-observability/overlays/dev | kubectl apply -f -

# Or point Flux/ArgoCD at dev overlay
# path: ./overlays/dev
```

Result: Dev config (2Gi Loki, 3-day retention, dev labels)

---

### Pattern 3: Use Overlay for Prod

```bash
# Build and apply prod overlay
kustomize build devops-lab-observability/overlays/prod | kubectl apply -f -

# Or point Flux/ArgoCD at prod overlay
# path: ./overlays/prod
```

Result: Prod config (50Gi Loki, 30-day retention, backup enabled)

---

## What You Actually Need (Minimal Setup)

If you want to keep it simple, you **only need:**

1. **Root kustomization.yaml** (top level) — REQUIRED
   - Points to loki-stack.yaml and falco.yaml

2. **Loki/Falco kustomization.yaml** (in each folder) — OPTIONAL
   - Can be omitted if no component-specific patches

3. **Overlay kustomization.yaml** files — OPTIONAL (but recommended!)
   - Only if you want dev/staging/prod differences

---

## Recommended Minimal Structure

```
devops-lab-observability/
├── kustomization.yaml                    ← ROOT (required, points to manifests)
├── observability/
│   └── loki/
│       └── loki-stack.yaml               ← Raw manifests (required)
├── security/
│   └── falco/
│       └── falco.yaml                    ← Raw manifests (required)
└── overlays/
    ├── dev/kustomization.yaml            ← DEV (optional but recommended)
    ├── staging/kustomization.yaml        ← STAGING (optional)
    └── prod/kustomization.yaml           ← PROD (optional)

# NO component-level kustomization.yaml files needed
# (unless you have component-specific patches)
```

---

## Example: What Gets Generated

### Using Root

```bash
$ kustomize build devops-lab-observability/
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    app.kubernetes.io/managed-by: kustomize
  name: observability
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: observability
spec:
  volumeClaimTemplates:
  - spec:
      resources:
        requests:
          storage: 5Gi  ← Default from loki-stack.yaml
# ... rest of manifests
```

### Using Dev Overlay

```bash
$ kustomize build devops-lab-observability/overlays/dev/
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    app.kubernetes.io/managed-by: kustomize
    environment: dev  ← Added by overlay
  name: observability
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: observability
  labels:
    environment: dev  ← Added by overlay
spec:
  volumeClaimTemplates:
  - spec:
      resources:
        requests:
          storage: 2Gi  ← Patched by overlay (was 5Gi)
# ... rest of manifests
```

### Using Prod Overlay

```bash
$ kustomize build devops-lab-observability/overlays/prod/
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    app.kubernetes.io/managed-by: kustomize
    environment: prod  ← Added by overlay
    backup: enabled    ← Added by overlay
  name: observability
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: loki
  namespace: observability
  labels:
    environment: prod  ← Added by overlay
spec:
  volumeClaimTemplates:
  - spec:
      resources:
        requests:
          storage: 50Gi  ← Patched by overlay (was 5Gi)
# ... rest of manifests
```

---

## Flux Usage

### Point Flux at Root (Default)

```yaml
# flux-system/flux-config.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: observability
spec:
  sourceRef:
    kind: GitRepository
    name: devops-lab-observability
  path: ./  # Points to root (uses root kustomization.yaml)
```

### Point Flux at Dev Overlay

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: observability
spec:
  sourceRef:
    kind: GitRepository
    name: devops-lab-observability
  path: ./overlays/dev  # Points to dev overlay
```

### Point Flux at Prod Overlay

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: observability
spec:
  sourceRef:
    kind: GitRepository
    name: devops-lab-observability
  path: ./overlays/prod  # Points to prod overlay
```

---

## Summary

| File | Location | Different? | Purpose | Required? |
|------|----------|-----------|---------|-----------|
| Root kustomization | `./kustomization.yaml` | One version | Orchestrate all components | ✅ Yes |
| Loki kustomization | `./observability/loki/kustomization.yaml` | One version | Loki-specific (if needed) | ❌ Optional |
| Falco kustomization | `./security/falco/kustomization.yaml` | One version | Falco-specific (if needed) | ❌ Optional |
| Dev overlay | `./overlays/dev/kustomization.yaml` | **DIFFERENT** | Dev-specific patches | ❌ Optional |
| Staging overlay | `./overlays/staging/kustomization.yaml` | **DIFFERENT** | Staging-specific patches | ❌ Optional |
| Prod overlay | `./overlays/prod/kustomization.yaml` | **DIFFERENT** | Prod-specific patches | ❌ Optional |

**KEY POINT:** Overlays are DIFFERENT from each other (dev != staging != prod). They're not the same file copied 3 times!

