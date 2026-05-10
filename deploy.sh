#!/usr/bin/env bash
set -euo pipefail

# GitOps Stack Deployment Script
# Supports TWO deployment modes:
#   1. ArgoCD (recommended - uses existing ArgoCD)
#   2. Flux (learning - full GitOps bootstrapping)

REPO_URL="${REPO_URL:-https://github.com/simonjday/devops-lab-observability.git}"
BRANCH="${BRANCH:-main}"
GITHUB_USER="${GITHUB_USER:-simonjday}"
DEPLOYMENT_MODE="${DEPLOYMENT_MODE:-argocd}"  # or 'flux'

NAMESPACE_ARGOCD="argocd"
NAMESPACE_OBS="observability"
NAMESPACE_SEC="falco"

COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_NC='\033[0m'

log_info() {
  echo -e "${COLOR_GREEN}[INFO]${COLOR_NC} $*"
}

log_warn() {
  echo -e "${COLOR_YELLOW}[WARN]${COLOR_NC} $*"
}

log_error() {
  echo -e "${COLOR_RED}[ERROR]${COLOR_NC} $*"
}

show_usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

OPTIONS:
  --mode argocd       Deploy via existing ArgoCD (default, faster)
  --mode flux         Deploy via Flux bootstrap (full GitOps learning)
  --help              Show this message

ENVIRONMENT VARIABLES:
  REPO_URL            Git repository URL (default: https://github.com/yourusername/kind-devops-lab.git)
  BRANCH              Git branch (default: main)
  GITHUB_USER         GitHub username (required for Flux mode)
  GITHUB_TOKEN        GitHub PAT (required for Flux mode)

EXAMPLES:
  ./deploy.sh --mode argocd
  GITHUB_USER=alice GITHUB_TOKEN=ghp_xxx ./deploy.sh --mode flux
EOF
}

check_prerequisites() {
  log_info "Checking prerequisites..."
  
  local missing=0
  
  for cmd in kubectl kustomize; do
    if ! command -v $cmd &> /dev/null; then
      log_error "Missing: $cmd"
      missing=$((missing + 1))
    fi
  done
  
  if [ "$DEPLOYMENT_MODE" = "argocd" ]; then
    if ! command -v argocd &> /dev/null; then
      log_error "Missing: argocd"
      missing=$((missing + 1))
    fi
  elif [ "$DEPLOYMENT_MODE" = "flux" ]; then
    if ! command -v flux &> /dev/null; then
      log_error "Missing: flux"
      missing=$((missing + 1))
    fi
  fi
  
  if [ $missing -gt 0 ]; then
    log_error "Install missing tools and retry"
    exit 1
  fi
  
  log_info "Prerequisites OK"
}

verify_cluster() {
  log_info "Verifying kind cluster..."
  
  if ! kubectl cluster-info &> /dev/null; then
    log_error "Cluster not accessible. Start it first:"
    echo "  kind create cluster --name kind-devops-lab"
    exit 1
  fi
  
  log_info "Cluster context: $(kubectl config current-context)"
}

deploy_argocd_mode() {
  log_info "========== ARGOCD DEPLOYMENT MODE =========="
  
  # Verify ArgoCD
  if ! kubectl get namespace $NAMESPACE_ARGOCD &> /dev/null; then
    log_error "ArgoCD namespace not found. Install ArgoCD first:"
    echo "  kubectl create namespace argocd"
    echo "  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    exit 1
  fi
  
  log_info "ArgoCD is ready"
  
  # Create Loki Application
  log_info "Creating Loki ArgoCD Application..."
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: loki
  namespace: $NAMESPACE_ARGOCD
spec:
  project: default
  source:
    repoURL: $REPO_URL
    path: observability/loki
    targetRevision: $BRANCH
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE_OBS
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
  
  # Create Falco Application
  log_info "Creating Falco ArgoCD Application..."
  cat <<EOF | kubectl apply -f -
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: falco
  namespace: $NAMESPACE_ARGOCD
spec:
  project: default
  source:
    repoURL: $REPO_URL
    path: security/falco
    targetRevision: $BRANCH
  destination:
    server: https://kubernetes.default.svc
    namespace: $NAMESPACE_SEC
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
EOF
  
  log_info "Waiting for applications to sync..."
  sleep 30
  
  log_info "===== ARGOCD DEPLOYMENT COMPLETE ====="
  echo ""
  log_info "Next steps:"
  echo "1. Monitor sync: argocd app get loki && argocd app get falco"
  echo "2. Watch logs: argocd app logs loki -f"
  echo "3. Verify pods: kubectl get pods -n observability -n falco"
  echo "4. Port-forward Loki: kubectl port-forward -n observability svc/loki 3100:3100"
  echo ""
}

deploy_flux_mode() {
  log_info "========== FLUX DEPLOYMENT MODE =========="
  
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    log_error "GITHUB_TOKEN not set. Required for Flux bootstrap."
    echo "  export GITHUB_TOKEN=<your-github-token>"
    exit 1
  fi
  
  if kubectl get namespace flux-system &> /dev/null; then
    log_warn "Flux already installed. Skipping bootstrap."
  else
    log_info "Bootstrapping Flux..."
    flux bootstrap github \
      --owner=$GITHUB_USER \
      --repo=kind-devops-lab \
      --path=flux-system \
      --personal \
      --private=false
    
    log_info "Flux bootstrapped successfully"
  fi
  
  log_info "Waiting for Flux to reconcile (2-5 minutes)..."
  sleep 60
  
  # Check Flux status
  log_info "Flux status:"
  flux get sources git || log_warn "Git source not yet synced"
  flux get kustomizations || log_warn "Kustomizations not yet deployed"
  
  log_info "===== FLUX DEPLOYMENT INITIATED ====="
  echo ""
  log_info "Next steps:"
  echo "1. Watch reconciliation: flux logs --all-namespaces -f"
  echo "2. Check status: flux get kustomizations"
  echo "3. Verify pods: kubectl get pods -n observability -n falco"
  echo "4. Port-forward Loki: kubectl port-forward -n observability svc/loki 3100:3100"
  echo ""
}

main() {
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --mode)
        DEPLOYMENT_MODE="$2"
        shift 2
        ;;
      --help)
        show_usage
        exit 0
        ;;
      *)
        log_error "Unknown option: $1"
        show_usage
        exit 1
        ;;
    esac
  done
  
  log_info "Starting GitOps Stack Deployment"
  log_info "Mode: $DEPLOYMENT_MODE"
  log_info "Repository: $REPO_URL"
  log_info "Branch: $BRANCH"
  echo ""
  
  check_prerequisites
  verify_cluster
  
  case "$DEPLOYMENT_MODE" in
    argocd)
      deploy_argocd_mode
      ;;
    flux)
      deploy_flux_mode
      ;;
    *)
      log_error "Invalid mode: $DEPLOYMENT_MODE"
      show_usage
      exit 1
      ;;
  esac
}

main "$@"
