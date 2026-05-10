#!/usr/bin/env bash
set -euo pipefail

# Setup script for devops-lab-observability repo
# Creates folder structure and copies all files automatically
# Usage: ./setup-repo.sh /path/to/devops-lab-observability

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_RED='\033[0;31m'
COLOR_NC='\033[0m'

log_info() {
  echo -e "${COLOR_GREEN}[✓]${COLOR_NC} $*"
}

log_warn() {
  echo -e "${COLOR_YELLOW}[!]${COLOR_NC} $*"
}

log_error() {
  echo -e "${COLOR_RED}[✗]${COLOR_NC} $*"
}

show_usage() {
  cat <<EOF
Usage: $0 [REPO_PATH]

Creates the complete devops-lab-observability folder structure and files.

Examples:
  # Create in current directory
  ./setup-repo.sh .

  # Create in specific path
  ./setup-repo.sh ~/devops-lab-observability

  # Create and cd into it
  mkdir devops-lab-observability && cd devops-lab-observability
  ./setup-repo.sh .
EOF
}

if [ $# -lt 1 ]; then
  log_error "Missing REPO_PATH argument"
  show_usage
  exit 1
fi

REPO_PATH="$1"

# Create all directories
log_info "Creating directory structure..."
mkdir -p "$REPO_PATH/observability/loki"
mkdir -p "$REPO_PATH/security/falco"
mkdir -p "$REPO_PATH/overlays/dev"
mkdir -p "$REPO_PATH/overlays/staging"
mkdir -p "$REPO_PATH/overlays/prod"
mkdir -p "$REPO_PATH/flux-system"

log_info "Directory structure created"

# Create root kustomization.yaml
log_info "Creating root kustomization.yaml..."
cat > "$REPO_PATH/kustomization.yaml" << 'KUST_ROOT'
# Root kustomization.yaml
# Orchestrates all components (Loki + Falco)
# Usage: kustomize build . | kubectl apply -f -

apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: default

commonLabels:
  app.kubernetes.io/managed-by: kustomize
  app.kubernetes.io/part-of: devops-lab-observability
  version: v1.0.0

commonAnnotations:
  managed-by: "kustomize"

resources:
  - observability/loki/loki-stack.yaml
  - security/falco/falco.yaml

patches: []
KUST_ROOT

# Create dev overlay kustomization.yaml
log_info "Creating dev overlay kustomization.yaml..."
cat > "$REPO_PATH/overlays/dev/kustomization.yaml" << 'KUST_DEV'
# Dev Overlay - Small resources, short retention
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: dev
  tier: development
  team: platform

commonAnnotations:
  description: "Development observability stack"

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
        value: "2Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "256Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "100m"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "512Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "500m"

  - target:
      group: apps
      version: v1
      kind: DaemonSet
      name: falco
      namespace: falco
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "128Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "50m"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "256Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "200m"

replicas:
  - name: loki
    count: 1

configMapGenerator:
  - name: dev-observability-config
    behavior: create
    literals:
      - ENVIRONMENT=development
      - LOG_LEVEL=debug
      - RETENTION_DAYS=3
      - STORAGE_SIZE=2Gi
KUST_DEV

# Create staging overlay kustomization.yaml
log_info "Creating staging overlay kustomization.yaml..."
cat > "$REPO_PATH/overlays/staging/kustomization.yaml" << 'KUST_STAGING'
# Staging Overlay - Medium resources, medium retention
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: staging
  tier: pre-production
  team: platform

commonAnnotations:
  description: "Staging observability stack"

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
        value: "10Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "512Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "200m"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "1Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "1000m"

  - target:
      group: apps
      version: v1
      kind: DaemonSet
      name: falco
      namespace: falco
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "256Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "100m"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "512Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "500m"

replicas:
  - name: loki
    count: 1

configMapGenerator:
  - name: staging-observability-config
    behavior: create
    literals:
      - ENVIRONMENT=staging
      - LOG_LEVEL=info
      - RETENTION_DAYS=7
      - STORAGE_SIZE=10Gi
KUST_STAGING

# Create prod overlay kustomization.yaml
log_info "Creating prod overlay kustomization.yaml..."
cat > "$REPO_PATH/overlays/prod/kustomization.yaml" << 'KUST_PROD'
# Prod Overlay - Large resources, long retention, HA
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: prod
  tier: production
  team: platform
  compliance: pci-dss
  backup: enabled

commonAnnotations:
  description: "Production observability stack"
  sla: "24/7"

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
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "4Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "2000m"
      - op: add
        path: /spec/template/spec/affinity
        value:
          podAntiAffinity:
            preferredDuringSchedulingIgnoredDuringExecution:
              - weight: 100
                podAffinityTerm:
                  labelSelector:
                    matchExpressions:
                      - key: app
                        operator: In
                        values:
                          - loki
                  topologyKey: kubernetes.io/hostname

  - target:
      group: apps
      version: v1
      kind: DaemonSet
      name: falco
      namespace: falco
    patch: |-
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "512Mi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/cpu
        value: "250m"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/memory
        value: "1Gi"
      - op: replace
        path: /spec/template/spec/containers/0/resources/limits/cpu
        value: "1000m"

replicas:
  - name: loki
    count: 3

configMapGenerator:
  - name: prod-observability-config
    behavior: create
    literals:
      - ENVIRONMENT=production
      - LOG_LEVEL=warn
      - RETENTION_DAYS=30
      - STORAGE_SIZE=50Gi
      - HA_MODE=true
      - REPLICAS=3
KUST_PROD

# Create .gitkeep files so empty dirs are tracked
log_info "Creating .gitkeep files..."
touch "$REPO_PATH/observability/loki/.gitkeep"
touch "$REPO_PATH/security/falco/.gitkeep"
touch "$REPO_PATH/flux-system/.gitkeep"

# Create README.md
log_info "Creating README.md..."
cat > "$REPO_PATH/README.md" << 'README'
# devops-lab-observability

Observability stack for kind-devops-lab: Loki (logs) + Falco (security)

## Quick Start

```bash
# Deploy to kind cluster with ArgoCD
./deploy.sh --mode argocd

# Or with Flux
export GITHUB_USER=simonjday GITHUB_TOKEN=ghp_xxx
./deploy.sh --mode flux
```

## Structure

- `observability/loki/` — Loki log aggregation + Promtail DaemonSet
- `security/falco/` — Falco runtime security monitoring
- `overlays/dev/` — Development configuration (2Gi Loki, 3-day retention)
- `overlays/staging/` — Staging configuration (10Gi Loki, 7-day retention)
- `overlays/prod/` — Production configuration (50Gi Loki, 30-day retention, HA)
- `flux-system/` — Flux CD configuration

## Documentation

- `SETUP_INSTRUCTIONS.md` — Step-by-step setup
- `GITOPS_INTEGRATION_GUIDE.md` — Full technical guide
- `QUICK_REFERENCE.md` — Commands cheat sheet
- `KUSTOMIZATION_GUIDE.md` — Kustomize overlay explanation

## Deploy

### ArgoCD (Recommended)
```bash
./deploy.sh --mode argocd
```

### Flux
```bash
export GITHUB_USER=simonjday
export GITHUB_TOKEN=ghp_xxxxx
./deploy.sh --mode flux
```

## Verify

```bash
# Check ArgoCD apps
argocd app list | grep -E "loki|falco"

# Check pods
kubectl get pods -n observability
kubectl get pods -n falco

# Port-forward Loki
kubectl port-forward -n observability svc/loki 3100:3100 &

# Query Loki
curl http://localhost:3100/loki/api/v1/labels
```

## Customize

Edit overlays for your environment:
- `overlays/dev/kustomization.yaml` — Dev settings
- `overlays/staging/kustomization.yaml` — Staging settings
- `overlays/prod/kustomization.yaml` — Prod settings

Commit and push to trigger auto-sync!
README

# Create .gitignore
log_info "Creating .gitignore..."
cat > "$REPO_PATH/.gitignore" << 'GITIGNORE'
# Kustomize
/kustomization_build_output.yaml

# Secrets (if any)
secrets.yaml
.env
.env.local

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Misc
*.log
*.tmp
GITIGNORE

log_info "Repository structure created successfully!"
echo ""
echo "Next steps:"
echo "1. Copy these files into the repo:"
echo "   - loki-stack.yaml → observability/loki/"
echo "   - falco.yaml → security/falco/"
echo "   - deploy.sh → root"
echo "   - *.md files → root"
echo "   - flux-config.yaml → flux-system/"
echo ""
echo "2. Commit and push:"
echo "   git add ."
echo "   git commit -m 'Initial observability stack'"
echo "   git push origin main"
echo ""
echo "3. Deploy:"
echo "   ./deploy.sh --mode argocd"
echo ""
