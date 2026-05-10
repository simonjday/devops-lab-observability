# devops-lab-observability

Production-ready observability stack for `kind-devops-lab` cluster: **Loki** (log aggregation) + **Falco** (runtime security).

This repo is separate from the main [`devops-lab-repo`](https://github.com/simonjday/devops-lab-repo) to keep concerns clean and allow reuse across clusters.

---

## 🎯 What This Does

```
┌─────────────────────────────────────────────────────────────┐
│                    kind-devops-lab Cluster                  │
│                                                             │
│  ┌────────────────┐         ┌──────────────────┐           │
│  │   All Pods     │         │   All Nodes      │           │
│  │   (all ns)     │         │                  │           │
│  └────────┬───────┘         └────────┬─────────┘           │
│           │                          │                     │
│           │                          │                     │
│  ┌────────▼────────────────────────▼──────────┐            │
│  │        Promtail DaemonSet                  │            │
│  │  (Scrapes /var/log/pods/*)                │            │
│  └────────┬─────────────────────────────────┬─┘            │
│           │                                 │              │
│           │ Logs (HTTP push)                │              │
│           │                                 │              │
│  ┌────────▼──────────────────────────────────▼──┐          │
│  │         Loki StatefulSet                     │          │
│  │   • Stores in PVC (5Gi default)             │          │
│  │   • Queryable via LogQL                     │          │
│  │   • Integration with Grafana                │          │
│  └─────────┬──────────────────────────┬────────┘          │
│            │                          │                    │
│  ┌─────────▼──────────┐   ┌──────────▼─────────┐          │
│  │   Falco DaemonSet  │   │  Prometheus Scrape │          │
│  │  • Monitors sycalls│   │  • Loki metrics    │          │
│  │  • Detects anomalies   │  • Falco metrics   │          │
│  │  • System call rules   │                    │          │
│  └────────┬───────────┘   └──────────┬─────────┘          │
│           │                          │                    │
│           │ Metrics (port 5555)      │                    │
│           └──────────┬───────────────┘                    │
│                      │                                    │
│           ┌──────────▼───────────┐                       │
│           │  Prometheus          │                       │
│           │  (monitoring ns)     │                       │
│           └──────────┬───────────┘                       │
│                      │                                    │
│           ┌──────────▼───────────┐                       │
│           │  Grafana             │                       │
│           │  (monitoring ns)     │                       │
│           │  • Logs (Loki)       │                       │
│           │  • Metrics (Prom)    │                       │
│           │  • Alerts            │                       │
│           └──────────────────────┘                       │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

---

## 🚀 Quick Start

### Prerequisite
- `kind-devops-lab` cluster running
- ArgoCD installed (or Flux if you prefer)
- `kubectl`, `kustomize`, `argocd` (or `flux`) in PATH

### Deploy (Choose One)

```
┌──────────────────────────────────────────────┐
│  Deployment Flow                             │
├──────────────────────────────────────────────┤
│                                              │
│  Option A: ArgoCD (Recommended)              │
│  ┌────────────────────────────────────────┐  │
│  │ $ ./deploy.sh --mode argocd            │  │
│  │                                        │  │
│  │ 1. Creates Loki Application            │  │
│  │ 2. Creates Falco Application           │  │
│  │ 3. ArgoCD watches Git repo             │  │
│  │ 4. Auto-syncs on push                  │  │
│  └────────────────────────────────────────┘  │
│                                              │
│  Option B: Flux (Learning)                   │
│  ┌────────────────────────────────────────┐  │
│  │ $ export GITHUB_USER=simonjday         │  │
│  │ $ export GITHUB_TOKEN=ghp_xxx          │  │
│  │ $ ./deploy.sh --mode flux              │  │
│  │                                        │  │
│  │ 1. Bootstraps Flux in flux-system ns   │  │
│  │ 2. Creates GitRepository CR            │  │
│  │ 3. Creates Kustomization CRs           │  │
│  │ 4. Continuous reconciliation           │  │
│  └────────────────────────────────────────┘  │
│                                              │
└──────────────────────────────────────────────┘
```

**Verify:**
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
│
├── observability/loki/               # Log aggregation
│   ├── loki-stack.yaml               #   ✓ Loki StatefulSet
│   └── kustomization.yaml            #   ✓ Promtail DaemonSet
│
├── security/falco/                   # Runtime security
│   ├── falco.yaml                    #   ✓ Falco DaemonSet
│   └── kustomization.yaml            #   ✓ Custom rules
│
├── overlays/                         # Environment configs
│   ├── dev/                          #   • 2Gi, 256Mi, 3 days
│   │   └── kustomization.yaml
│   ├── staging/                      #   • 10Gi, 512Mi, 7 days
│   │   └── kustomization.yaml
│   └── prod/                         #   • 50Gi, 2Gi, 30 days (HA)
│       └── kustomization.yaml
│
├── flux-system/                      # Flux CD config (optional)
│   └── flux-config.yaml              #   GitRepository + Kustomizations
│
├── kustomization.yaml                # Root orchestrator
├── deploy.sh                         # Deployment script
├── README.md                         # This file
└── docs/                             # Documentation
    ├── GITOPS_INTEGRATION_GUIDE.md
    ├── QUICK_REFERENCE.md
    ├── SETUP_INSTRUCTIONS.md
    └── ...
```

---

## 🔄 Data Flow

```
Pod Logs              System Calls
    │                      │
    ▼                      ▼
┌─────────────┐      ┌──────────────┐
│  Promtail   │      │    Falco     │
│  DaemonSet  │      │  DaemonSet   │
└──────┬──────┘      └───────┬──────┘
       │                     │
       │ HTTP Push           │ Metrics (5555)
       │                     │
       └──────────┬──────────┘
                  │
          ┌───────▼────────┐
          │      Loki      │
          │  StatefulSet   │
          └───────┬────────┘
                  │
        ┌─────────┴──────────┐
        │                    │
   Metrics            LogQL Queries
        │                    │
        └──────────┬─────────┘
                   │
          ┌────────▼─────────┐
          │  Prometheus      │
          │  Grafana         │
          │  AlertManager    │
          └──────────────────┘
```

---

## 📊 Environment Comparison

```
┌─────────────┬──────────┬──────────────┬──────────┐
│   Aspect    │   Dev    │   Staging    │   Prod   │
├─────────────┼──────────┼──────────────┼──────────┤
│ Storage     │   2Gi    │    10Gi      │  50Gi    │
│ Memory      │  256Mi   │    512Mi     │   2Gi    │
│ CPU         │  100m    │    200m      │  500m    │
│ Retention   │ 3 days   │   7 days     │ 30 days  │
│ Log Level   │  debug   │    info      │  warn    │
│ Replicas    │    1     │      1       │    3     │
│ HA Mode     │   No     │     No       │   Yes    │
└─────────────┴──────────┴──────────────┴──────────┘
```

---

## 🔍 Loki Usage

### Port-Forward & Query

```bash
# Start port-forward
kubectl port-forward -n observability svc/loki 3100:3100 &

# Query labels
curl http://localhost:3100/loki/api/v1/labels

# Query logs (all from default namespace)
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="default"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq .
```

### Add to Grafana

```
Grafana → Configuration → Data Sources → Add Loki
URL: http://loki.observability.svc.cluster.local:3100
                            ↓
                    Explore → select Loki
                            ↓
                      Query Logs (LogQL)
```

---

## 🛡️ Falco Usage

```
System Calls ──(eBPF)──→ Falco ──(Rules)──→ ✓ Allowed / ✗ Alert
                       (DaemonSet)
                            │
                    ┌───────┴────────┐
                    │                │
              Logs (stdout)    Metrics (5555)
                    │                │
              kubectl logs    Prometheus
                             ↓
                        Alertmanager
```

---

## 🧪 Testing

### Test Loki

```bash
# 1. Deploy test app
kubectl create deployment test-app --image=busybox \
  -- sh -c "while true; do echo 'test'; sleep 1; done"

# 2. Wait for logs
sleep 30

# 3. Query in Loki
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={pod="test-app-xxx"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq '.data.result | length'

# 4. Cleanup
kubectl delete deployment test-app
```

### Test Falco

```bash
# 1. Trigger shell (test rule)
kubectl exec -it <pod> -n <ns> -- /bin/bash

# 2. Check logs
kubectl logs -n falco -l app=falco -f | grep -i "shell"

# 3. Check metrics
curl http://localhost:5555/metrics | grep falco_alerts_total
```

---

## 🔄 Flux vs ArgoCD

```
                  Git Push
                     │
         ┌───────────┴───────────┐
         │                       │
    ┌────▼─────┐           ┌────▼─────┐
    │  ArgoCD   │           │   Flux   │
    │           │           │          │
    │ • Web UI  │           │ • CLI    │
    │ • Fast    │           │ • GitOps │
    │ • Pull    │           │ • Push   │
    │ • Easy    │           │ • Complex│
    └────┬─────┘           └────┬─────┘
         │                       │
         └───────────┬───────────┘
                     │
          kubectl apply / sync
                     │
    ┌────────────────┴─────────────────┐
    │                                   │
┌───▼───────┐                  ┌───────▼──┐
│    Loki   │                  │  Falco   │
│ + Promtail│                  │  (DaemonSet)
│(StatefulSet)                 │          │
└───────────┘                  └──────────┘
```

---

## 🚨 Alert Flow

```
Falco DaemonSet          Prometheus         AlertManager
    │                         │                    │
    ├─ System Call Alert      │                    │
    │  (CRITICAL)             │                    │
    │                         │                    │
    └─→ Metrics (5555)        │                    │
             │                │                    │
             └─→ Scrape ──────→ Query              │
                                │                  │
                                ├─ Rule Match      │
                                │  (CRITICAL > 0)  │
                                │                  │
                                └─→ Fire Alert ───→ Slack / PagerDuty / Email
                                                    │
                                                    ✓ On-Call Notified
```

---

## 📚 Documentation Map

```
START HERE
    │
    ├─→ SETUP_INSTRUCTIONS.md
    │   (Step-by-step for your repos)
    │
    ├─→ REPO_STRUCTURE.md
    │   (What files go where)
    │
    ├─→ AUTOMATED_SETUP_GUIDE.md
    │   (Using setup-repo.sh)
    │
    ├─→ GITOPS_INTEGRATION_GUIDE.md
    │   (Full technical reference)
    │
    ├─→ KUSTOMIZATION_GUIDE.md
    │   (Kustomize deep dive)
    │
    └─→ QUICK_REFERENCE.md
        (Commands cheat sheet)
```

---

## 🎯 Next Steps

1. **Set it up:** `./setup-repo.sh .` or manual copy of files
2. **Deploy:** `./deploy.sh --mode argocd`
3. **Verify:** `kubectl get pods -n observability -n falco`
4. **Customize:** Edit overlays for your environment
5. **Integrate:** Add Loki datasource to Grafana
6. **Alert:** Route Falco alerts to Slack/PagerDuty

---

## 📖 Learn More

See documentation in this repo for comprehensive guides:
- `GITOPS_INTEGRATION_GUIDE.md` — Full technical reference
- `KUSTOMIZATION_GUIDE.md` — Kustomize deep dive
- `QUICK_REFERENCE.md` — Commands cheat sheet

---

## 🤝 Related Repos

- **[devops-lab-repo](https://github.com/simonjday/devops-lab-repo)** — Main platform (Bifrost, Kubecost, Kyverno, etc.)

---

**Questions?** Check the documentation files or see repo About section.
