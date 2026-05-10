# GitOps Stack Integration Guide: Loki + Falco (Separate Observability Repo)

## Architecture: Separate Repository

This observability stack lives in its **own GitHub repo** (`kind-devops-lab-observability`) — separate from your main cluster config repo. This keeps concerns clean:

- **Main repo** (`kind-devops-lab`): Platform/cluster foundation (ArgoCD, Bifrost, Kubecost, core infra)
- **Observability repo** (`kind-devops-lab-observability`): Loki + Falco + related observability (THIS stack)

Both ArgoCD and Flux point to this separate repo, making it reusable across clusters.

---

## Quick Start

```bash
# Step 1: Create separate GitHub repo
# Go to github.com → New repository → "kind-devops-lab-observability"

# Step 2: Clone and populate
git clone https://github.com/yourusername/kind-devops-lab-observability.git
cd kind-devops-lab-observability

# Copy all manifests from this deliverable:
mkdir -p observability/loki security/falco overlays/{dev,staging,prod} flux-system
cp loki-stack.yaml observability/loki/
cp falco.yaml security/falco/
cp kustomization.yaml .
cp flux-config.yaml flux-system/
cp deploy.sh .
# ... copy all other files

git add .
git commit -m "Initial: Loki + Falco observability stack"
git push origin main

# Step 3: Deploy to your kind cluster

# Path 1: ArgoCD (existing controller)
./deploy.sh --mode argocd

# Path 2: Flux + Kustomize (learning)
export GITHUB_USER=yourusername GITHUB_TOKEN=ghp_xxx
./deploy.sh --mode flux
```

---

# Path 1: ArgoCD Deployment

## Overview

Your cluster already has **ArgoCD** running. This path creates Applications that watch your **observability repo** and sync Loki + Falco.

**Pros:**
- Fast setup (1 command)
- Reuses existing ArgoCD
- Separate repo = clean separation of concerns
- Web UI for monitoring

**Cons:**
- Less "learning" about Kustomize
- Single point of control (ArgoCD)

## Architecture

```
GitHub: kind-devops-lab-observability repo
├── observability/loki/loki-stack.yaml
└── security/falco/falco.yaml
         ↓ (ArgoCD watches)
    ArgoCD in kind-devops-lab cluster
         ↓
    Creates Applications → kustomize build → kubectl apply
         ↓
    Namespaces: observability, falco
         ↓
    Feeds metrics to existing Prometheus (monitoring ns)
```

## Deployment

### 1. Verify ArgoCD in Your Main Cluster

```bash
kubectl get pods -n argocd | head -3
kubectl config current-context  # Should be kind-kind-devops-lab
```

### 2. Run Deploy Script

```bash
chmod +x deploy.sh
./deploy.sh --mode argocd
```

This creates two ArgoCD Applications pointing to `kind-devops-lab-observability` repo:
- `loki` — watches `observability/loki/`
- `falco` — watches `security/falco/`

### 3. Monitor Sync

```bash
# Check application status
argocd app list | grep -E "loki|falco"
argocd app get loki
argocd app get falco

# Watch logs
argocd app logs loki -f
argocd app logs falco -f

# Verify pods
kubectl get pods -n observability
kubectl get pods -n falco
```

## Key Commands

```bash
# Manual sync if repo changed
argocd app sync loki
argocd app sync falco

# Refresh (re-fetch from Git)
argocd app get loki --refresh

# Suspend auto-sync
argocd app set loki --sync-policy none

# Resume auto-sync
argocd app set loki --sync-policy automated
```

## Integration with Existing Stack

Your Prometheus (in `monitoring` ns) automatically scrapes:
- **Falco metrics** (via ServiceMonitor in falco.yaml)
- **Loki metrics** (optional — if you add ServiceMonitor)

### Add Loki to Grafana

```bash
# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Open http://localhost:3000 (admin/prom-operator)
# Configuration → Data Sources → Add Loki
# URL: http://loki.observability.svc.cluster.local:3100
```

---

# Path 2: Flux + Kustomize Deployment

## Overview

This path bootstraps **Flux** in your cluster and watches the **separate observability repo**.

**Pros:**
- Learn Kustomize overlays (dev/staging/prod)
- Understand multi-controller GitOps
- Full declarative setup (everything in Git)
- Reusable observability stack (can deploy to multiple clusters)

**Cons:**
- Slower setup (requires GitHub credentials, bootstrap)
- Two controllers in same cluster (ArgoCD + Flux)
- Learning curve (Flux concepts + Kustomize)

## Architecture

```
GitHub: kind-devops-lab-observability repo
├── observability/loki/loki-stack.yaml
├── security/falco/falco.yaml
├── overlays/{dev,staging,prod}
├── kustomization.yaml
└── flux-system/flux-config.yaml
         ↓ (Flux watches)
    Flux in kind-devops-lab cluster (flux-system ns)
         ↓
    GitRepository → Kustomization CRDs
         ↓
    kustomize build + kubectl apply
         ↓
    Continuous reconciliation loop
```

## Prerequisites

```bash
# Install Flux CLI
curl -s https://fluxcd.io/install.sh | sudo bash

# Verify
flux --version
```

## Deployment

### 1. Set GitHub Credentials

```bash
export GITHUB_USER=yourusername
export GITHUB_TOKEN=ghp_xxxxx  # Personal Access Token (repo + admin:repo_hook scope)
```

### 2. Run Deploy Script

```bash
./deploy.sh --mode flux
```

This:
1. Runs `flux bootstrap github` to set up Flux in `flux-system` namespace
2. Creates GitRepository pointing to `kind-devops-lab-observability` repo
3. Creates Kustomization resources for observability + security
4. Waits for initial reconciliation

### 3. Monitor Flux Reconciliation

```bash
# Watch Flux logs (verbose)
flux logs --all-namespaces -f

# Check GitRepository status
flux get sources git
flux get kustomizations

# View reconciliation history
kubectl get events -n flux-system --sort-by='.lastTimestamp' | tail -20
```

### 4. Verify Pods

```bash
# Flux system
kubectl get pods -n flux-system

# Observability
kubectl get pods -n observability
kubectl get pvc -n observability

# Security
kubectl get pods -n falco
```

## Kustomize Overlays (Environment-Specific)

Use overlays to customize per environment (dev/staging/prod).

### Directory Structure

```
kind-devops-lab-observability/
├── overlays/
│   ├── dev/
│   │   └── kustomization.yaml        # Dev patches: 2Gi storage
│   ├── staging/
│   │   └── kustomization.yaml        # Staging patches: 10Gi
│   └── prod/
│       └── kustomization.yaml        # Prod patches: 50Gi, more resources
├── observability/loki/loki-stack.yaml
├── security/falco/falco.yaml
├── kustomization.yaml                # Root
└── flux-system/flux-config.yaml       # Flux config
```

### Example Dev Overlay

```yaml
# overlays/dev/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: dev

# Patch: smaller storage for Loki in dev
patchesJson6902:
  - target:
      kind: StatefulSet
      name: loki
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "2Gi"  # vs 5Gi in prod
```

### Example Prod Overlay

```yaml
# overlays/prod/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

bases:
  - ../../

namespace: observability

commonLabels:
  environment: prod
  backup: enabled

# Patch: larger storage, more resources
patchesJson6902:
  - target:
      kind: StatefulSet
      name: loki
    patch: |-
      - op: replace
        path: /spec/volumeClaimTemplates/0/spec/resources/requests/storage
        value: "50Gi"  # Production size
      - op: replace
        path: /spec/template/spec/containers/0/resources/requests/memory
        value: "2Gi"
```

### Build and Test Overlay Locally

```bash
# Test overlay locally before applying
kustomize build overlays/dev | head -50

# Apply dev overlay (if using kubectl directly)
kubectl apply -k overlays/dev

# Apply prod overlay to production cluster
kubectl apply -k overlays/prod
```

### Point Flux to Overlay

Update `flux-system/flux-config.yaml`:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: observability
  namespace: flux-system
spec:
  sourceRef:
    kind: GitRepository
    name: kind-devops-lab-observability
  path: ./overlays/prod  # Point to overlay, not root
  prune: true
  wait: true
```

Then Flux auto-syncs the prod overlay. Commit and push:

```bash
git add flux-system/flux-config.yaml
git commit -m "Flux: point observability to prod overlay"
git push origin main
```

## Key Flux Commands

```bash
# Manual reconciliation
flux reconcile source git kind-devops-lab-observability
flux reconcile kustomization observability
flux reconcile kustomization security

# Suspend (emergency stop)
flux suspend kustomization observability

# Resume
flux resume kustomization observability

# View detailed status
kubectl describe kustomization -n flux-system observability
kubectl get events -n flux-system -w

# Force garbage collection
kubectl get all -n observability  # After Flux prune
```

---

# Loki: Log Aggregation

## What Loki Does

- **Collects logs** from all pods via Promtail DaemonSet
- **Indexes by labels** (pod, namespace, container)
- **Stores logs** in local PVC or object storage (local for kind)
- **Integrates with Grafana** — query logs in Explore tab

## Key Components

**Loki StatefulSet:**
- Port 3100 (API)
- PVC storage: 5Gi (default), customizable per overlay
- Config: boltdb-shipper, local filesystem storage

**Promtail DaemonSet:**
- Scrapes `/var/log/pods/*` from all nodes
- Auto-discovers pods via Kubernetes SD
- Sends to Loki via HTTP push

## Query Examples (LogQL in Grafana)

```logql
# All logs from namespace
{namespace="default"}

# Logs from specific pod
{pod="bifrost-0", namespace="ai-gateway"}

# Error logs
{job="kubernetes-pods"} |= "error"

# Parse JSON and filter
{job="api"} | json | status >= 500

# Rate of errors
rate({job="kubernetes-pods"} |= "error" [5m]) by (namespace)
```

## Access Loki

```bash
# Port-forward
kubectl port-forward -n observability svc/loki 3100:3100 &

# Query labels
curl http://localhost:3100/loki/api/v1/labels | jq .

# Query logs
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="default"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq .
```

## Customize Retention

Edit `observability/loki/loki-stack.yaml`:

```yaml
env:
  - name: LOKI_RETENTION_ENABLED
    value: "true"
  - name: LOKI_RETENTION_DAYS
    value: "7"  # Dev
    # value: "30"  # Prod (via overlay)
```

---

# Falco: Runtime Security

## What Falco Does

- **Monitors system calls** at kernel level (eBPF engine)
- **Detects anomalies** — privilege escalation, reverse shells, etc.
- **Exports metrics** to Prometheus (already integrated)
- **Generates alerts** (CRITICAL, WARNING, INFO)

## Key Components

**Falco DaemonSet:**
- Runs on all nodes (tolerates control-plane)
- Engine: modern_ebpf (no kernel compilation on kind)
- Outputs: JSON to stdout, metrics on port 5555

**Custom Rules (ConfigMap):**

```yaml
- rule: Reverse Shell Activity
  condition: outbound and container and fd.sport > 40000
  output: Potential reverse shell (address=%fd.cip:%fd.cport)
  priority: CRITICAL
```

**ServiceMonitor + PrometheusRule:**
- Prometheus scrapes metrics
- AlertManager fires alerts on thresholds

## Falco Metrics (in Prometheus)

```promql
# Alerts by priority
falco_alerts_total{priority="CRITICAL"}
falco_alerts_total{priority="WARNING"}

# Rate
rate(falco_alerts_total[5m]) by (rule_name)
```

## Test Falco

```bash
# Trigger shell rule
kubectl exec -it <any-pod> -n <namespace> -- /bin/bash

# Check Falco logs
kubectl logs -n falco -l app=falco -f | grep -i "shell"

# Check metrics
kubectl port-forward -n falco svc/falco-metrics 5555:5555 &
curl http://localhost:5555/metrics | grep falco_alerts_total
```

## Customize Rules

Edit `security/falco/falco.yaml` ConfigMap:

```bash
vim security/falco/falco.yaml
git add security/falco/falco.yaml
git commit -m "Add custom rule: detect DNS exfiltration"
git push origin main

# ArgoCD or Flux auto-syncs (with delay)
```

---

# Verification & Testing

## Verify Components

```bash
# ArgoCD mode
argocd app list | grep -E "loki|falco"
argocd app get loki
argocd app get falco

# Flux mode
flux get sources git
flux get kustomizations

# Pods
kubectl get pods -n observability
kubectl get pods -n falco
```

## Test Log Flow

```bash
# Deploy test app
kubectl create deployment test-app --image=busybox \
  -- sh -c "while true; do echo 'test log'; sleep 1; done"

# Wait 30 seconds for logs to appear
sleep 30

# Query Loki
kubectl port-forward -n observability svc/loki 3100:3100 &
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={pod="test-app-xxx"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq '.data.result[0].values | length'

# Cleanup
kubectl delete deployment test-app
```

## Test Falco Alert

```bash
# Trigger shell spawn alert
kubectl exec -it <any-pod> -n <namespace> -- /bin/bash

# Verify alert in logs
kubectl logs -n falco -l app=falco -f | grep -i "spawned_process\|shell"

# Check metric incremented
curl http://localhost:5555/metrics | grep falco_alerts_total
```

---

# Troubleshooting

| Issue | ArgoCD Solution | Flux Solution |
|-------|-----------------|---------------|
| App stuck in Pending | `argocd app get <app> --refresh` | `flux get kustomizations -w` |
| Loki pod CrashLoopBackOff | `kubectl logs -n observability loki-0` | `kubectl describe pvc -n observability` |
| Promtail not scraping | Check mount: `kubectl exec <pod> -- ls /var/log/pods/` | Same |
| Falco DaemonSet not ready | Check tolerations in manifest | Edit overlay, commit, push |
| Prometheus not scraping Falco | Verify ServiceMonitor labels | `kubectl get servicemonitor -n falco` |

---

# Cleanup

**ArgoCD mode:**
```bash
argocd app delete loki
argocd app delete falco
kubectl delete namespace observability falco
```

**Flux mode:**
```bash
flux suspend kustomization observability security
kubectl delete kustomization -n flux-system observability security
flux uninstall --silent
kubectl delete namespace flux-system observability falco
```

---

# Next Steps

1. **Create repo** — `kind-devops-lab-observability` on GitHub
2. **Copy manifests** — clone repo, add all files
3. **Choose path** — ArgoCD (fast) or Flux+Kustomize (learning)
4. **Run deploy.sh** with chosen mode
5. **Monitor** — watch logs and pods
6. **Customize** — edit overlays per environment
7. **Integrate** — add Loki datasource to Grafana
8. **Alert** — route Falco alerts to Slack/PagerDuty

---

# File Structure (Observability Repo)

```
kind-devops-lab-observability/
├── observability/
│   └── loki/
│       ├── loki-stack.yaml
│       └── kustomization.yaml (optional)
├── security/
│   └── falco/
│       ├── falco.yaml
│       └── kustomization.yaml (optional)
├── overlays/
│   ├── dev/kustomization.yaml
│   ├── staging/kustomization.yaml
│   └── prod/kustomization.yaml
├── flux-system/
│   └── flux-config.yaml
├── kustomization.yaml (root)
├── deploy.sh
├── GITOPS_INTEGRATION_GUIDE.md (this file)
├── QUICK_REFERENCE.md
└── kustomize-overlays-reference.md
```

---

**Remember:** This repo is separate from your main `kind-devops-lab` repo. It's self-contained and reusable across clusters!

