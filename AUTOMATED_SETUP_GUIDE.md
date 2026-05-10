# Automated Repo Setup Guide

## What You Get

The `setup-repo.sh` script automatically creates:

✅ All folder structure
✅ All kustomization.yaml files (root + dev/staging/prod)
✅ .gitkeep files (so git tracks empty directories)
✅ README.md
✅ .gitignore

You just need to copy the manifest files!

---

## Step-by-Step

### 1️⃣ Create Repo on GitHub

```bash
# On GitHub.com:
# - Go to https://github.com/new
# - Name: devops-lab-observability
# - Description: "Observability stack: Loki + Falco"
# - Public
# - Initialize with README
# - Create repository
```

### 2️⃣ Clone the Repo

```bash
git clone https://github.com/simonjday/devops-lab-observability.git
cd devops-lab-observability
```

### 3️⃣ Run Setup Script

Copy `setup-repo.sh` from deliverable and run it:

```bash
# Copy the script into the repo
cp /path/to/setup-repo.sh .

# Make it executable
chmod +x setup-repo.sh

# Run it (dot = current directory)
./setup-repo.sh .
```

**Output:**
```
[✓] Creating directory structure...
[✓] Directory structure created
[✓] Creating root kustomization.yaml...
[✓] Creating dev overlay kustomization.yaml...
[✓] Creating staging overlay kustomization.yaml...
[✓] Creating prod overlay kustomization.yaml...
[✓] Creating .gitkeep files...
[✓] Creating README.md...
[✓] Creating .gitignore...
[✓] Repository structure created successfully!

Next steps:
1. Copy these files into the repo:
   - loki-stack.yaml → observability/loki/
   - falco.yaml → security/falco/
   - deploy.sh → root
   - *.md files → root
   - flux-config.yaml → flux-system/
...
```

### 4️⃣ Verify Structure Created

```bash
tree -L 2
# devops-lab-observability/
# ├── observability/
# │   └── loki/
# │       └── .gitkeep
# ├── security/
# │   └── falco/
# │       └── .gitkeep
# ├── overlays/
# │   ├── dev/
# │   │   └── kustomization.yaml
# │   ├── staging/
# │   │   └── kustomization.yaml
# │   └── prod/
# │       └── kustomization.yaml
# ├── flux-system/
# │   └── .gitkeep
# ├── kustomization.yaml
# ├── .gitignore
# └── README.md
```

### 5️⃣ Copy Manifest Files

Now copy the actual manifest files from deliverable:

```bash
# Copy Loki manifest
cp /path/to/loki-stack.yaml observability/loki/

# Copy Falco manifest
cp /path/to/falco.yaml security/falco/

# Copy deployment script
cp /path/to/deploy.sh .

# Copy all documentation
cp /path/to/GITOPS_INTEGRATION_GUIDE.md .
cp /path/to/QUICK_REFERENCE.md .
cp /path/to/SETUP_INSTRUCTIONS.md .
cp /path/to/REPO_STRUCTURE.md .
cp /path/to/KUSTOMIZATION_GUIDE.md .
cp /path/to/kustomize-overlays-reference.md .

# Copy Flux config
cp /path/to/flux-config.yaml flux-system/
```

### 6️⃣ Verify Everything

```bash
# Check all files present
tree
# devops-lab-observability/
# ├── observability/
# │   └── loki/
# │       ├── loki-stack.yaml         ✅
# │       └── .gitkeep
# ├── security/
# │   └── falco/
# │       ├── falco.yaml              ✅
# │       └── .gitkeep
# ├── overlays/
# │   ├── dev/
# │   │   └── kustomization.yaml      ✅
# │   ├── staging/
# │   │   └── kustomization.yaml      ✅
# │   └── prod/
# │       └── kustomization.yaml      ✅
# ├── flux-system/
# │   ├── flux-config.yaml            ✅
# │   └── .gitkeep
# ├── kustomization.yaml              ✅
# ├── deploy.sh                       ✅
# ├── GITOPS_INTEGRATION_GUIDE.md      ✅
# ├── QUICK_REFERENCE.md              ✅
# ├── SETUP_INSTRUCTIONS.md           ✅
# ├── REPO_STRUCTURE.md               ✅
# ├── KUSTOMIZATION_GUIDE.md          ✅
# ├── kustomize-overlays-reference.md ✅
# ├── .gitignore
# └── README.md

ls -la observability/loki/      # Should have loki-stack.yaml
ls -la security/falco/          # Should have falco.yaml
ls -la flux-system/             # Should have flux-config.yaml
```

### 7️⃣ Test Kustomizations

Before committing, test that builds work:

```bash
# Test root build
kustomize build . | head -20

# Test dev overlay
kustomize build overlays/dev | head -20

# Test prod overlay  
kustomize build overlays/prod | head -20

# All should succeed with no errors
```

### 8️⃣ Commit and Push

```bash
git add .
git commit -m "Initial observability stack: Loki + Falco

- Loki: Log aggregation via Promtail DaemonSet
- Falco: Runtime security monitoring
- Kustomize overlays for dev/staging/prod
- Supports ArgoCD and Flux deployment"

git push origin main
```

### 9️⃣ Deploy to Your Cluster

```bash
# Make deploy.sh executable
chmod +x deploy.sh

# Choose your path:

# Option A: ArgoCD (recommended)
./deploy.sh --mode argocd

# Option B: Flux (learning)
export GITHUB_USER=simonjday
export GITHUB_TOKEN=ghp_xxxxx
./deploy.sh --mode flux
```

### 🔟 Verify Deployment

```bash
# Check ArgoCD apps
argocd app list | grep -E "loki|falco"

# Check pods
kubectl get pods -n observability
kubectl get pods -n falco

# Port-forward Loki
kubectl port-forward -n observability svc/loki 3100:3100 &

# Query logs
curl http://localhost:3100/loki/api/v1/labels
```

---

## What setup-repo.sh Creates

### Folder Structure
```
devops-lab-observability/
├── observability/loki/
├── security/falco/
├── overlays/
│   ├── dev/
│   ├── staging/
│   └── prod/
└── flux-system/
```

### Root kustomization.yaml
- Orchestrates all components
- Includes loki-stack.yaml and falco.yaml
- Applies base labels and annotations

### Dev Overlay (overlays/dev/kustomization.yaml)
- 2Gi Loki storage
- 256Mi memory
- 3-day retention
- Debug logging
- development labels

### Staging Overlay (overlays/staging/kustomization.yaml)
- 10Gi Loki storage
- 512Mi memory
- 7-day retention
- Info logging
- pre-production labels

### Prod Overlay (overlays/prod/kustomization.yaml)
- 50Gi Loki storage
- 2Gi memory
- 30-day retention
- Warn logging
- 3 replicas (HA)
- Affinity rules
- Caching enabled
- PCI-DSS compliance labels

### Other Files
- `.gitignore` — Ignores temporary files
- `README.md` — Quick start guide
- `.gitkeep` — Allows tracking of empty directories

---

## What You Still Need to Copy

The script creates structure and kustomizations, but you need to copy these files manually:

1. **loki-stack.yaml** → `observability/loki/`
2. **falco.yaml** → `security/falco/`
3. **deploy.sh** → root
4. **flux-config.yaml** → `flux-system/`
5. **Documentation**:
   - GITOPS_INTEGRATION_GUIDE.md
   - QUICK_REFERENCE.md
   - SETUP_INSTRUCTIONS.md
   - REPO_STRUCTURE.md
   - KUSTOMIZATION_GUIDE.md
   - kustomize-overlays-reference.md

These are the "deliverable" files that you're downloading.

---

## Customization After Setup

### Change Dev Storage

```bash
vim overlays/dev/kustomization.yaml

# Find:
#   value: "2Gi"
# Change to:
#   value: "5Gi"

git add overlays/dev/kustomization.yaml
git commit -m "Dev: increase storage to 5Gi"
git push
```

### Change Prod Retention

```bash
vim overlays/prod/kustomization.yaml

# Change retention_period value
git add overlays/prod/kustomization.yaml
git commit -m "Prod: increase retention to 60 days"
git push
```

### Add New Falco Rules

```bash
vim security/falco/falco.yaml

# Edit the custom rules ConfigMap
git add security/falco/falco.yaml
git commit -m "Add rule: detect DNS exfiltration"
git push
```

---

## Troubleshooting

### Error: "No such file or directory"

Make sure you're in the repo directory:
```bash
cd devops-lab-observability
./setup-repo.sh .
```

### Error: "Permission denied"

Make script executable:
```bash
chmod +x setup-repo.sh
./setup-repo.sh .
```

### Kustomize build fails

Check that manifests are in place:
```bash
ls -la observability/loki/loki-stack.yaml
ls -la security/falco/falco.yaml
```

If missing, copy them first.

---

## Summary

| Step | Manual? | Tool |
|------|---------|------|
| Create folder structure | ❌ No | setup-repo.sh |
| Create kustomization files | ❌ No | setup-repo.sh |
| Copy manifests | ✅ Yes | Manual copy |
| Copy deploy script | ✅ Yes | Manual copy |
| Copy documentation | ✅ Yes | Manual copy |
| Commit and push | ✅ Yes | git |
| Deploy | ✅ Yes | ./deploy.sh |

**Only 4 steps are manual** — everything else is automated! 🎉

