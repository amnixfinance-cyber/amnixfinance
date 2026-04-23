# Amnixfinance Platform

Enterprise-grade financial intelligence platform built on battle-tested open source infrastructure.

## Architecture

| # | Layer | Tool | Version | syncWave |
|---|-------|------|---------|----------|
| 1 | Networking | Cilium | 1.19.3 | 0 |
| 2 | TLS/Certificates | cert-manager | v1.20.2 | 0 |
| 3 | Service Mesh CRDs | Linkerd CRDs | 1.8.0 | 1 |
| 4 | Service Mesh | Linkerd | 1.16.11 | 2 |
| 5 | RBAC/Policy | Gatekeeper (OPA) | 3.22.0 | 2 |
| 6 | DR Storage | Longhorn | 1.11.1 | 2 |
| 7 | Database | PostgreSQL | 18.6.1 | 2 |
| 8 | Cache | Redis | 25.4.0 | 2 |
| 9 | Secrets | Vault | 0.32.0 | 2 |
| 10 | API Gateway | APISIX | 2.14.0 | 3 |
| 11 | Messaging | Redpanda | 26.1.2 | 3 |
| 12 | Vector DB | Qdrant | 1.17.1 | 3 |
| 13 | Search | Quickwit | 0.8.4 | 3 |
| 14 | Storage | MinIO | 5.4.0 | 3 |
| 15 | Security | Falco | 8.0.2 | 3 |
| 16 | Jobs | Temporal | 1.1.1 | 3 |
| 17 | Auth | Ory Kratos | 0.61.1 | 3 |
| 18 | Observability | Loki Stack | 2.10.3 | 3 |
| 19 | Scaling | KEDA | 2.19.0 | 3 |
| 20 | Backup | Velero | 12.0.0 | 3 |
| 21 | Multi-tenancy | vCluster | 0.33.1 | 3 |
| 22 | Billing | Lago | 1.27.1 | 4 |
| 23 | Notifications | Grafana OnCall | 1.16.5 | 4 |
| 24 | Admin Portal | Backstage | 2.6.3 | 4 |

**GitOps:** ArgoCD 9.5.4 | **CI/CD:** Tekton v1.11.1

## Structure
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

### Step 3 — ArgoCD syncs automatically (wave 0 → 1 → 2 → 3 → 4)

## Languages
- Go: Cilium, KEDA, Temporal, Ory, MinIO, Velero, Gatekeeper, vCluster, Linkerd control plane
- Rust: Linkerd proxy, Quickwit, Qdrant
- C++: Redpanda, Falco
