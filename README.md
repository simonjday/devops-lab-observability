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
