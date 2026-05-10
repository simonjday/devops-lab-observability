# Kustomize Overlays Reference
# Shows how to structure environment-specific patches

## Directory Structure

```
kind-devops-lab/
├── kustomization.yaml                 # Root
├── observability/
│   └── loki/
│       ├── loki-stack.yaml           # Base manifests
│       └── kustomization.yaml        # (optional) Loki-specific kustomization
├── security/
│   └── falco/
│       ├── falco.yaml                # Base manifests
│       └── kustomization.yaml        # (optional) Falco-specific kustomization
├── overlays/
│   ├── dev/
│   │   ├── kustomization.yaml
│   │   ├── loki-patch.yaml
│   │   └── falco-patch.yaml
│   ├── staging/
│   │   ├── kustomization.yaml
│   │   ├── loki-patch.yaml
│   │   └── falco-patch.yaml
│   └── prod/
│       ├── kustomization.yaml
│       ├── loki-patch.yaml
│       └── falco-patch.yaml
└── flux-system/
    ├── flux-config.yaml              # Flux Kustomizations pointing to overlays
    └── (flux bootstrap files)
```

---

## Example Overlay: overlays/dev/kustomization.yaml

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# Reference the root
bases:
  - ../../

# Development-specific namespace
namespace: observability

# Development labels
commonLabels:
  environment: dev
  team: platform

# Patch Loki for dev (smaller storage)
patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: StatefulSet
      name: loki
      namespace: observability
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/storage
        value: "2Gi"
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "2Gi"

# Patch Falco for dev (reduce replicas, no alert forwarding)
patchesStrategicMerge:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: falco-config
      namespace: falco
    data:
      falco.yaml: |
        # Dev: minimal alerting
        rules_file:
          - /etc/falco/rules.yaml
          - /etc/falco/rules.d
          - /etc/falco/custom_rules.yaml
```

---

## Example Overlay: overlays/prod/kustomization.yaml

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

# Patch Loki for production (larger storage)
patchesJson6902:
  - target:
      group: apps
      version: v1
      kind: StatefulSet
      name: loki
      namespace: observability
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "50Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "2Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "500m"

# Patch Falco for production (enable all alerts, forwarding)
patchesStrategicMerge:
  - apiVersion: v1
    kind: ConfigMap
    metadata:
      name: falco-config
      namespace: falco
    data:
      falco.yaml: |
        # Prod: full alerting, integration with AlertManager
        engine: modern_ebpf
        rules_file:
          - /etc/falco/rules.yaml
          - /etc/falco/rules.d
          - /etc/falco/custom_rules.yaml
```

---

## Usage

### Build and validate overlay

```bash
# Dev
kustomize build overlays/dev | kubectl apply -f - --dry-run=client -o yaml | head -50

# Staging
kustomize build overlays/staging

# Prod
kustomize build overlays/prod
```

### Apply via kubectl

```bash
# Apply dev environment
kubectl apply -k overlays/dev

# Apply prod environment
kubectl apply -k overlays/prod
```

### Apply via Flux (point Kustomization to overlay)

Update `flux-config.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: observability-prod
  namespace: flux-system
spec:
  interval: 10m
  sourceRef:
    kind: GitRepository
    name: kind-devops-lab
  path: ./overlays/prod  # Point to overlay, not base
  prune: true
  wait: true
```

Then: `flux reconcile source git kind-devops-lab`

---

## Key Kustomize Features Demonstrated

1. **bases** — Reference parent kustomization
2. **namespace** — Override namespace per environment
3. **commonLabels** — Add labels to all resources
4. **patchesJson6902** — Strategic JSON patches (e.g., storage size)
5. **patchesStrategicMerge** — Full resource patches
6. **replicas** — Scale deployments per environment
7. **configMapGenerator** — Generate ConfigMaps from literals or files
8. **secretGenerator** — Generate Secrets (for creds, API keys)

---

## Best Practices

- **One overlay per environment** — dev, staging, prod
- **Use bases for common config** — root kustomization.yaml
- **Small patches** — keep overlays minimal and focused
- **Test locally first** — `kustomize build overlays/dev` before applying
- **Version your overlays** — treat them like code (Git)
- **Document patch rationale** — why does prod have 50Gi storage?
