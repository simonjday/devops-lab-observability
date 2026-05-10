# Observability Stack Setup Instructions

## Your Repos

- **Main Cluster Config:** https://github.com/simonjday/devops-lab-repo (ArgoCD syncs this)
- **Observability Stack:** https://github.com/simonjday/devops-lab-observability (NEW - separate repo)

Both repos are watched by ArgoCD OR Flux (your choice).

---

## Step 1: Create Separate Observability Repo

```bash
# On GitHub.com:
# 1. Go to https://github.com/new
# 2. Repository name: devops-lab-observability
# 3. Public (ArgoCD needs to read it)
# 4. Initialize with README
# 5. Create repository

# Then clone it
git clone https://github.com/simonjday/devops-lab-observability.git
cd devops-lab-observability
```

---

## Step 2: Copy All Manifests

Create the directory structure and copy files from this deliverable:

```bash
# Create directories
mkdir -p observability/loki security/falco overlays/{dev,staging,prod} flux-system

# Copy manifests
cp /path/to/loki-stack.yaml observability/loki/
cp /path/to/falco.yaml security/falco/
cp /path/to/kustomization.yaml .
cp /path/to/flux-config.yaml flux-system/
cp /path/to/deploy.sh .
cp /path/to/*.md .

# Directory should look like:
tree -L 2
# devops-lab-observability/
# ├── observability/
# │   └── loki/
# │       └── loki-stack.yaml
# ├── security/
# │   └── falco/
# │       └── falco.yaml
# ├── overlays/
# │   ├── dev/
# │   ├── staging/
# │   └── prod/
# ├── flux-system/
# │   └── flux-config.yaml
# ├── kustomization.yaml
# ├── deploy.sh
# ├── GITOPS_INTEGRATION_GUIDE.md
# ├── QUICK_REFERENCE.md
# └── kustomize-overlays-reference.md
```

---

## Step 3: Commit and Push

```bash
git add .
git commit -m "Initial: Loki + Falco observability stack

- Loki: Log aggregation via Promtail
- Falco: Runtime security monitoring
- Supports both ArgoCD and Flux deployment
- Kustomize overlays for dev/staging/prod"
git push origin main
```

---

## Step 4: Deploy

### Option A: ArgoCD (Recommended - Uses Existing Controller)

```bash
# From devops-lab-observability repo:
chmod +x deploy.sh
./deploy.sh --mode argocd
```

This creates ArgoCD Applications that watch the observability repo.

**Verify:**
```bash
argocd app list
argocd app get loki
argocd app get falco

# Monitor sync
argocd app logs loki -f
```

### Option B: Flux + Kustomize (Learning - Full GitOps)

```bash
# Set GitHub credentials
export GITHUB_USER=simonjday
export GITHUB_TOKEN=ghp_xxxxx  # Personal Access Token

# Deploy
./deploy.sh --mode flux
```

This bootstraps Flux and watches the observability repo.

**Verify:**
```bash
flux logs --all-namespaces -f
flux get sources git
flux get kustomizations
```

---

## Step 5: Verify Stack Is Running

```bash
# Check ArgoCD Applications (if using ArgoCD path)
argocd app list | grep -E "loki|falco"

# Check pods
kubectl get pods -n observability
kubectl get pods -n falco

# Check metrics are being scraped
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090 &
# Visit http://localhost:9090/targets
# Look for: falco-metrics, loki (if ServiceMonitor added)
```

---

## Step 6: Add Loki to Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Open http://localhost:3000
# Username: admin
# Password: prom-operator

# Configuration → Data Sources → New Data Source
# Type: Loki
# URL: http://loki.observability.svc.cluster.local:3100
# Save & Test

# Then: Explore → select Loki → query logs
```

---

## Step 7: Test Everything

### Test Loki Log Flow

```bash
# Deploy test app
kubectl create deployment test-app --image=busybox \
  -- sh -c "while true; do echo 'test log message'; sleep 1; done"

# Wait 30 seconds for logs to appear
sleep 30

# Port-forward Loki
kubectl port-forward -n observability svc/loki 3100:3100 &

# Query logs
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={pod="test-app-xxx"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq '.data.result | length'

# Should return > 0
# Cleanup: kubectl delete deployment test-app
```

### Test Falco Alerts

```bash
# Port-forward Falco metrics
kubectl port-forward -n falco svc/falco-metrics 5555:5555 &

# Trigger a shell spawn (test rule)
kubectl exec -it <any-pod> -n <namespace> -- /bin/bash
# (Then exit immediately)

# Check Falco caught it
kubectl logs -n falco -l app=falco -f | grep -i "spawned\|shell"

# Check metrics incremented
curl http://localhost:5555/metrics | grep falco_alerts_total
```

---

## Update Path: Customizing Per Environment

### Edit Dev Overlay

```bash
# Create dev-specific patches
vim overlays/dev/kustomization.yaml

# Example: reduce Loki storage in dev
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: dev

patchesJson6902:
  - target:
      kind: StatefulSet
      name: loki
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "2Gi"
```

### Commit and Push

```bash
git add overlays/dev/
git commit -m "Add dev overlay: 2Gi Loki storage"
git push origin main

# ArgoCD/Flux auto-syncs (with slight delay)
```

---

## Repo Structure Summary

```
devops-lab-observability/
├── observability/
│   └── loki/
│       ├── loki-stack.yaml           ← Loki + Promtail manifests
│       └── kustomization.yaml        (optional - for Loki-specific patches)
├── security/
│   └── falco/
│       ├── falco.yaml                ← Falco DaemonSet + rules
│       └── kustomization.yaml        (optional - for Falco-specific patches)
├── overlays/
│   ├── dev/
│   │   └── kustomization.yaml        ← Dev patches: smaller storage, dev labels
│   ├── staging/
│   │   └── kustomization.yaml        ← Staging patches
│   └── prod/
│       └── kustomization.yaml        ← Prod patches: larger storage, resources
├── flux-system/
│   └── flux-config.yaml              ← Flux GitRepository + Kustomizations
├── kustomization.yaml                ← Root orchestrator
├── deploy.sh                         ← Deployment script (ArgoCD or Flux mode)
├── GITOPS_INTEGRATION_GUIDE.md        ← Full guide (both paths)
├── QUICK_REFERENCE.md                ← Commands & troubleshooting
├── kustomize-overlays-reference.md   ← Overlay patterns
└── SETUP_INSTRUCTIONS.md             ← This file

Key separation:
- Main repo (devops-lab-repo): Platform foundation, ArgoCD config, Bifrost, Kubecost
- Observability repo (devops-lab-observability): Loki, Falco, logging/security only
```

---

## Both Controllers in Same Cluster?

**You can run both ArgoCD + Flux in the same cluster** (they don't conflict):
- ArgoCD watches `devops-lab-repo` (your main platform)
- Flux watches `devops-lab-observability` (this stack)

But typically you'd choose ONE:
- **ArgoCD only** (recommended): Use `--mode argocd` deployment
- **Flux only** (learning): Use `--mode flux` deployment

If you use ArgoCD path, Flux is not installed. If you use Flux path, ArgoCD remains but doesn't manage Loki/Falco.

---

## Next: Make It Yours

1. Fork/clone `devops-lab-observability` repo
2. Customize overlays for your environments
3. Add custom Falco rules (`security/falco/falco.yaml` ConfigMap)
4. Configure alerting (Falco → Slack/PagerDuty via AlertManager)
5. Optimize retention policies per environment
6. Consider S3/GCS backend for Loki in production

---

**Questions?** Check:
- `GITOPS_INTEGRATION_GUIDE.md` — Full technical guide
- `QUICK_REFERENCE.md` — Commands cheat sheet
- `kustomize-overlays-reference.md` — Overlay patterns

