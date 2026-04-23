# Amnixfinance Platform

Enterprise-grade financial intelligence platform built on battle-tested open source infrastructure.

## Architecture

| # | Layer | Tool | Version | syncWave |
|---|-------|------|---------|----------|
| 1 | Networking | Cilium | 1.19.3 | 0 |
| 2 | Service Mesh (CRDs) | Linkerd CRDs | 1.8.0 | 1 |
| 3 | Service Mesh | Linkerd | 1.16.11 | 2 |
| 4 | RBAC/Policy | Gatekeeper (OPA) | 3.22.0 | 2 |
| 5 | DR Storage | Longhorn | 1.11.1 | 2 |
| 6 | API Gateway | APISIX | 2.14.0 | 3 |
| 7 | Messaging | Redpanda | 26.1.2 | 3 |
| 8 | Vector DB | Qdrant | 1.17.1 | 3 |
| 9 | Search | Quickwit | 0.8.4 | 3 |
| 10 | Storage | MinIO | 5.4.0 | 3 |
| 11 | Security | Falco | 8.0.2 | 3 |
| 12 | Jobs | Temporal | 1.1.1 | 3 |
| 13 | Auth | Ory Kratos | 0.61.1 | 3 |
| 14 | Observability | Loki Stack | 2.10.3 | 3 |
| 15 | Scaling | KEDA | 2.19.0 | 3 |
| 16 | Backup | Velero | 12.0.0 | 3 |
| 17 | Multi-tenancy | vCluster | 0.33.1 | 3 |
| 18 | Billing | Lago | 1.27.1 | 4 |
| 19 | Notifications | Grafana OnCall | 1.16.5 | 4 |
| 20 | Admin Portal | Backstage | 2.6.3 | 4 |

**GitOps Engine:** ArgoCD 9.5.4  
**CI/CD:** Tekton v1.11.1

## Repository Structure
platform/
├── cicd/
│   └── tekton-app.yaml
└── gitops/
├── argocd-install.yaml
└── platform-appset.yaml
infrastructure/

## Deployment

### Step 1 — Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 2 — Apply platform
```bash
kubectl apply -f platform/gitops/argocd-install.yaml
kubectl apply -f platform/gitops/platform-appset.yaml
kubectl apply -f platform/cicd/tekton-app.yaml
```

### Step 3 — ArgoCD syncs everything automatically in order (wave 0 → 1 → 2 → 3 → 4)

## Languages
- Infrastructure: Go (Cilium, KEDA, Temporal, Ory, MinIO, Velero, Gatekeeper, vCluster, Linkerd control plane)
- Data Plane: Rust (Linkerd proxy, Quickwit, Qdrant)
- Messaging: C++ (Redpanda)
- Security: C++ (Falco)
