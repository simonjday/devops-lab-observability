# devops-lab-observability

Production-ready observability stack for `kind-devops-lab` cluster: **Loki** (log aggregation) + **Falco** (runtime security).

This repo is separate from the main [`devops-lab-repo`](https://github.com/simonjday/devops-lab-repo) to keep concerns clean and allow reuse across clusters.

---

## 🎯 What This Does

| Component | Purpose | Details |
|-----------|---------|---------|
| **Loki** | Log aggregation | Collects pod logs via Promtail DaemonSet, stores in PVC, queryable via LogQL |
| **Promtail** | Log collector | DaemonSet on all nodes, scrapes `/var/log/pods/`, sends to Loki |
| **Falco** | Runtime security | Monitors system calls, detects anomalies (privilege escalation, reverse shells, etc.) |
| **ServiceMonitor** | Metrics export | Falco exports metrics to Prometheus (already in your cluster) |

**Integration:** Feeds into your existing Prometheus + Grafana stack (`monitoring` namespace).

---

## 🚀 Quick Start

### Prerequisite
- `kind-devops-lab` cluster running
- ArgoCD installed (or Flux if you prefer)
- `kubectl`, `kustomize`, `argocd` (or `flux`) in PATH

### Deploy (Choose One)

**Option 1: ArgoCD (Recommended)**
```bash
chmod +x deploy.sh
./deploy.sh --mode argocd
```

**Option 2: Flux**
```bash
export GITHUB_USER=simonjday
export GITHUB_TOKEN=ghp_xxxxx  # GitHub Personal Access Token
./deploy.sh --mode flux
```

### Verify
```bash
# Check status
argocd app list | grep -E "loki|falco"
kubectl get pods -n observability
kubectl get pods -n falco

# Port-forward and query
kubectl port-forward -n observability svc/loki 3100:3100 &
curl http://localhost:3100/loki/api/v1/labels
```

---

## 📁 Structure

```
devops-lab-observability/
├── observability/
│   └── loki/
│       ├── loki-stack.yaml           # Loki StatefulSet + Promtail DaemonSet
│       └── kustomization.yaml        # Loki-specific kustomization
├── security/
│   └── falco/
│       ├── falco.yaml                # Falco DaemonSet + rules + alerts
│       └── kustomization.yaml        # Falco-specific kustomization
├── overlays/
│   ├── dev/kustomization.yaml        # Dev: 2Gi Loki, 256Mi RAM, 3-day retention
│   ├── staging/kustomization.yaml    # Staging: 10Gi Loki, 512Mi RAM, 7-day retention
│   └── prod/kustomization.yaml       # Prod: 50Gi Loki, 2Gi RAM, 30-day retention, HA
├── flux-system/
│   └── flux-config.yaml              # Flux GitRepository + Kustomization CRDs
├── kustomization.yaml                # Root orchestrator
├── deploy.sh                         # Deployment script (ArgoCD or Flux mode)
├── GITOPS_INTEGRATION_GUIDE.md        # Full technical guide (both paths)
├── QUICK_REFERENCE.md                # Commands cheat sheet
├── SETUP_INSTRUCTIONS.md             # Step-by-step setup
├── REPO_STRUCTURE.md                 # What goes where
├── KUSTOMIZATION_GUIDE.md            # Kustomize overlay explanation
├── kustomize-overlays-reference.md   # Overlay patterns & examples
├── AUTOMATED_SETUP_GUIDE.md          # Using setup-repo.sh
├── README.md                         # This file
└── .gitignore
```

---

## 📚 Documentation

Start with these in order:

1. **[SETUP_INSTRUCTIONS.md](SETUP_INSTRUCTIONS.md)** — Step-by-step for your repos
2. **[AUTOMATED_SETUP_GUIDE.md](AUTOMATED_SETUP_GUIDE.md)** — How to use `setup-repo.sh`
3. **[REPO_STRUCTURE.md](REPO_STRUCTURE.md)** — What files go where
4. **[GITOPS_INTEGRATION_GUIDE.md](GITOPS_INTEGRATION_GUIDE.md)** — Full technical deep dive
5. **[KUSTOMIZATION_GUIDE.md](KUSTOMIZATION_GUIDE.md)** — Understanding each kustomization.yaml
6. **[QUICK_REFERENCE.md](QUICK_REFERENCE.md)** — Commands cheat sheet

---

## 🛠️ Deployment Modes

### ArgoCD (Recommended)

Uses your existing ArgoCD installation to watch this repo.

```bash
./deploy.sh --mode argocd
```

**Pros:**
- Fast (1 command)
- Reuses existing ArgoCD
- Web UI for monitoring
- No additional controller needed

**Monitor:**
```bash
argocd app list
argocd app get loki
argocd app logs loki -f
```

### Flux (Learning)

Bootstraps Flux CD as a second GitOps controller.

```bash
export GITHUB_USER=simonjday
export GITHUB_TOKEN=ghp_xxxxx
./deploy.sh --mode flux
```

**Pros:**
- Learn Kustomize overlays
- Full GitOps bootstrapping
- Declarative everything

**Monitor:**
```bash
flux logs --all-namespaces -f
flux get sources git
flux get kustomizations
```

---

## 🔧 Customization

### Change Dev Storage

```bash
vim overlays/dev/kustomization.yaml
# Change: value: "2Gi" → value: "5Gi"
git add overlays/dev/kustomization.yaml
git commit -m "Dev: increase storage"
git push
# Auto-syncs!
```

### Change Prod Retention

```bash
vim overlays/prod/kustomization.yaml
# Change: retention_period: 720h → retention_period: 1440h (60 days)
git add overlays/prod/kustomization.yaml
git commit -m "Prod: 60-day retention"
git push
# Auto-syncs!
```

### Add Falco Rule

```bash
vim security/falco/falco.yaml
# Add rule to custom_rules.yaml ConfigMap section
git add security/falco/falco.yaml
git commit -m "Add DNS exfiltration detection rule"
git push
# Auto-syncs!
```

---

## 📊 Environment Comparison

| Aspect | Dev | Staging | Prod |
|--------|-----|---------|------|
| **Storage** | 2Gi | 10Gi | 50Gi |
| **Memory (Loki)** | 256Mi | 512Mi | 2Gi |
| **CPU (Loki)** | 100m | 200m | 500m |
| **Retention** | 3 days | 7 days | 30 days |
| **Log Level** | debug | info | warn |
| **Falco Memory** | 128Mi | 256Mi | 512Mi |
| **Falco CPU** | 50m | 100m | 250m |
| **HA Mode** | No | No | Yes (3x) |
| **Caching** | No | No | Yes |
| **Compliance** | — | — | PCI-DSS |

---

## 🔍 Loki Usage

### Port-Forward

```bash
kubectl port-forward -n observability svc/loki 3100:3100 &
```

### Query Labels

```bash
curl http://localhost:3100/loki/api/v1/labels | jq .
```

### Query Logs (LogQL)

```bash
# All logs from namespace
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="default"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq .

# Logs from specific pod
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={pod="bifrost-0", namespace="ai-gateway"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq .

# Error logs
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={job="kubernetes-pods"} |= "error"' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq .
```

### Add to Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Open http://localhost:3000 (admin/prom-operator)
# Configuration → Data Sources → Add Loki
# URL: http://loki.observability.svc.cluster.local:3100
# Save & Test

# Then: Explore → select Loki → query logs
```

---

## 🛡️ Falco Usage

### Port-Forward Metrics

```bash
kubectl port-forward -n falco svc/falco-metrics 5555:5555 &
```

### Check Metrics

```bash
curl http://localhost:5555/metrics | grep falco_alerts_total
```

### Test Alert Rule

```bash
# Trigger shell spawn (test rule)
kubectl exec -it <any-pod> -n <any-namespace> -- /bin/bash

# Check Falco caught it
kubectl logs -n falco -l app=falco -f | grep -i "shell\|spawned"
```

### View Prometheus Alerts

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090 &

# Check targets: http://localhost:9090/targets
# Query: falco_alerts_total
```

---

## 🚨 Alerts

### Falco PrometheusRule

Automatically fires alerts when:
- **CRITICAL alert detected** — Pager goes off immediately
- **5+ WARNINGs in 5 minutes** — Notification sent

Edit in `security/falco/falco.yaml`:

```yaml
- alert: FalcoCriticalAlert
  expr: increase(falco_alerts_total{priority="CRITICAL"}[5m]) > 0
  for: 1m
  annotations:
    summary: "Critical security event detected"
```

---

## 🧪 Testing

### Test Loki Log Flow

```bash
# Deploy test app
kubectl create deployment test-app --image=busybox \
  -- sh -c "while true; do echo 'test log'; sleep 1; done"

# Wait 30 seconds
sleep 30

# Query in Loki
kubectl port-forward -n observability svc/loki 3100:3100 &
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={pod="test-app-xxx"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq '.data.result | length'

# Should return > 0
# Cleanup: kubectl delete deployment test-app
```

### Test Falco Alert

```bash
# Trigger shell spawn
kubectl exec -it <any-pod> -n <any-namespace> -- /bin/bash
# (exit immediately)

# Check logs
kubectl logs -n falco -l app=falco -f | grep -i "shell"

# Check metrics incremented
curl http://localhost:5555/metrics | grep falco_alerts_total
```

---

## 🔄 Flux vs ArgoCD

Both are supported. Choose based on your needs:

| Aspect | ArgoCD | Flux |
|--------|--------|------|
| **Setup** | Fast (1 command) | Slower (bootstrap) |
| **Learning** | Minimal | Full GitOps learning |
| **UI** | Web UI | CLI only |
| **Overlays** | Via path selection | Via Kustomization path |
| **Best For** | Production | Learning + ops |

---

## 📋 Checklist

- [ ] Clone repo: `git clone https://github.com/simonjday/devops-lab-observability.git`
- [ ] Run setup: `./setup-repo.sh .` (if folders don't exist)
- [ ] Copy manifests: `loki-stack.yaml`, `falco.yaml`, `deploy.sh`, etc.
- [ ] Test builds: `kustomize build overlays/prod`
- [ ] Commit: `git add . && git commit -m "Initial observability stack" && git push`
- [ ] Deploy: `./deploy.sh --mode argocd` (or flux)
- [ ] Verify: `kubectl get pods -n observability -n falco`
- [ ] Port-forward: `kubectl port-forward -n observability svc/loki 3100:3100`
- [ ] Query Loki: `curl http://localhost:3100/loki/api/v1/labels`
- [ ] Add to Grafana: Configuration → Data Sources → Loki

---

## 🐛 Troubleshooting

### App Stuck in "Pending"
```bash
argocd app get loki --refresh
argocd app get falco --refresh
```

### Loki Pod CrashLoopBackOff
```bash
kubectl logs -n observability loki-0
kubectl describe pvc -n observability
```

### Promtail Not Scraping
```bash
kubectl logs -n observability -l app=promtail --tail=50
kubectl exec -n observability <promtail-pod> -- ls /var/log/pods/
```

### Falco DaemonSet Not Scheduling
```bash
kubectl describe node
kubectl describe daemonset -n falco falco
```

### Prometheus Not Scraping Falco
```bash
kubectl get servicemonitor -n falco
# Check port and labels match Prometheus config
```

---

## 📖 Learn More

See documentation in this repo for comprehensive guides:
- `GITOPS_INTEGRATION_GUIDE.md` — Full technical reference
- `KUSTOMIZATION_GUIDE.md` — Kustomize deep dive
- `QUICK_REFERENCE.md` — Commands cheat sheet

---

## 🤝 Related Repos

- **[devops-lab-repo](https://github.com/simonjday/devops-lab-repo)** — Main platform (Bifrost, Kubecost, Kyverno, etc.)
- **[kind-devops-lab](https://github.com/simonjday/kind-devops-lab)** — Cluster setup (kind config)

---

## 📝 License

Same as main platform repo.

---

## 🎯 Next Steps

1. **Set it up:** `./setup-repo.sh .` or manual copy of files
2. **Deploy:** `./deploy.sh --mode argocd`
3. **Verify:** `kubectl get pods -n observability -n falco`
4. **Customize:** Edit overlays for your environment
5. **Integrate:** Add Loki datasource to Grafana
6. **Alert:** Route Falco alerts to Slack/PagerDuty

---

**Questions?** Check the documentation files or see troubleshooting section above.
