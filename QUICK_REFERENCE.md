# GitOps Stack: Quick Reference (ArgoCD Edition)

## Pre-Flight Checklist

- [ ] Kind cluster running: `kind get clusters` should show `kind-devops-lab`
- [ ] kubectl context set: `kubectl config current-context` → `kind-kind-devops-lab`
- [ ] ArgoCD running: `kubectl get pods -n argocd | head -3`
- [ ] Tools installed: `kubectl`, `kustomize`, `argocd`

## Deployment

```bash
# 1. Verify ArgoCD is running
kubectl get namespace argocd
kubectl get deployment argocd-server -n argocd

# 2. Run deployment script
chmod +x deploy.sh
./deploy.sh

# Or manually create ArgoCD Applications:
argocd app create loki \
  --repo https://github.com/yourusername/kind-devops-lab \
  --path observability/loki \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace observability \
  --auto-prune --self-heal

argocd app create falco \
  --repo https://github.com/yourusername/kind-devops-lab \
  --path security/falco \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace falco \
  --auto-prune --self-heal
```

## Monitoring Deployment

```bash
# Watch ArgoCD applications sync
argocd app get loki --refresh
argocd app get falco --refresh

# Check component status
argocd app list | grep -E "loki|falco"

# View sync logs
argocd app logs loki -f
argocd app logs falco -f

# Verify pods running
kubectl get pods -n observability
kubectl get pods -n falco
```

## Key Commands

### ArgoCD

```bash
# List all applications
argocd app list

# Get application status
argocd app get loki
argocd app get falco

# Refresh app (re-fetch from Git)
argocd app get loki --refresh

# Manual sync
argocd app sync loki
argocd app sync falco

# Wait for sync to complete
argocd app wait loki
argocd app wait falco

# Suspend auto-sync
argocd app set loki --sync-policy none

# Resume auto-sync
argocd app set loki --sync-policy automated

# Delete application
argocd app delete loki
```

### Loki

```bash
# Port-forward Loki API
kubectl port-forward -n observability svc/loki 3100:3100 &

# Query labels
curl http://localhost:3100/loki/api/v1/labels | jq .

# Query logs (LogQL)
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={namespace="default"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq .

# Check pod logs
kubectl logs -n observability -l app=loki -f
kubectl logs -n observability -l app=promtail --tail=50
```

### Falco

```bash
# Port-forward Falco metrics
kubectl port-forward -n falco svc/falco-metrics 5555:5555 &

# View Falco logs
kubectl logs -n falco -l app=falco -f

# Trigger test rule (spawn shell in pod)
kubectl exec -it <any-pod> -n <namespace> -- /bin/bash

# Check Falco metrics
curl http://localhost:5555/metrics | grep falco_alerts_total

# Check ServiceMonitor
kubectl get servicemonitor -n falco
```

### Kubernetes

```bash
# List all namespaces
kubectl get namespaces

# Check all pods
kubectl get pods --all-namespaces

# Check specific namespace
kubectl get pods -n observability
kubectl get pods -n falco
kubectl get pods -n monitoring

# Describe pod (debugging)
kubectl describe pod <pod-name> -n <namespace>

# View pod logs
kubectl logs <pod-name> -n <namespace>

# Tail logs
kubectl logs <pod-name> -n <namespace> -f
```

### Prometheus + Grafana (Pre-existing)

```bash
# Port-forward Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090 &

# Check scrape targets: http://localhost:9090/targets

# Port-forward Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

# Access: http://localhost:3000 (admin/prom-operator)
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| ArgoCD app stuck in "Pending" | Check Git repo; verify branch; `argocd app get <app> --refresh` |
| Loki pod CrashLoopBackOff | `kubectl logs -n observability loki-0`; check PVC binding |
| Promtail not scraping | `kubectl logs -n observability -l app=promtail`; verify mount |
| Falco DaemonSet not scheduling | `kubectl describe node`; check tolerations in manifest |
| Prometheus not scraping Falco | `kubectl get servicemonitor -n falco`; check labels |
| Cannot connect to Loki | Port-forward: `kubectl port-forward -n observability svc/loki 3100:3100` |

## Port Forwards (Quick Setup)

```bash
#!/bin/bash
# port-forwards.sh

# Loki
kubectl port-forward -n observability svc/loki 3100:3100 &

# Falco metrics
kubectl port-forward -n falco svc/falco-metrics 5555:5555 &

# Prometheus
kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-stack-prometheus 9090:9090 &

# Grafana
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 &

echo "Port forwards active:"
echo "  Loki: http://localhost:3100"
echo "  Falco metrics: http://localhost:5555"
echo "  Prometheus: http://localhost:9090"
echo "  Grafana: http://localhost:3000 (admin/prom-operator)"
```

Run with: `chmod +x port-forwards.sh && ./port-forwards.sh`

## Testing

### Loki: Test Log Flow

```bash
# 1. Deploy test app
kubectl create deployment test-app --image=busybox -- sh -c "while true; do echo 'test log'; sleep 1; done"

# 2. Wait for pod
kubectl rollout status deployment test-app

# 3. Port-forward Loki
kubectl port-forward -n observability svc/loki 3100:3100 &

# 4. Query in 30 seconds
sleep 30
curl -G -s http://localhost:3100/loki/api/v1/query_range \
  --data-urlencode 'query={pod="test-app-xxx"}' \
  --data-urlencode 'start=0' \
  --data-urlencode 'end=9999999999' | jq '.data.result[0].values' | head -5

# 5. Cleanup
kubectl delete deployment test-app
```

### Falco: Test Alert Rule

```bash
# 1. Trigger a shell spawn (watch for alert)
kubectl exec -it <any-pod> -n <namespace> -- /bin/bash

# 2. Check Falco logs for alert
kubectl logs -n falco -l app=falco -f | grep -i "shell\|spawned"

# 3. Monitor metrics
kubectl port-forward -n falco svc/falco-metrics 5555:5555 &
curl http://localhost:5555/metrics | grep falco_alerts_total
```

## Cleanup

```bash
# Remove ArgoCD applications (keep resources)
argocd app delete loki --cascade=false
argocd app delete falco --cascade=false

# Remove with resources
argocd app delete loki
argocd app delete falco

# Remove namespaces
kubectl delete namespace observability falco

# Destroy kind cluster
kind delete cluster --name kind-devops-lab
```
