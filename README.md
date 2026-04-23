# Amnixfinance Platform

Enterprise-grade financial intelligence platform built on battle-tested open source infrastructure.

## Architecture

| Layer | Tool | Version | Purpose |
|-------|------|---------|---------|
| Networking | Cilium | 1.19.3 | eBPF-based CNI |
| Service Mesh | Linkerd | 1.16.11 | mTLS + observability |
| API Gateway | APISIX | 2.14.0 | Traffic management |
| Messaging | Redpanda | 26.1.2 | Kafka-compatible streaming |
| Vector DB | Qdrant | 1.17.1 | AI/ML embeddings |
| Search | Quickwit | 0.8.4 | Cloud-native search |
| Storage | MinIO | 5.4.0 | S3-compatible object storage |
| Security | Falco | 8.0.2 | Runtime threat detection |
| Jobs | Temporal | 1.1.1 | Distributed workflows |
| Auth | Ory Kratos | 0.61.1 | Identity management |
| Observability | Loki Stack | 2.10.3 | Logs + metrics + traces |
| Scaling | KEDA | 2.19.0 | Event-driven autoscaling |
| Backup | Velero | 12.0.0 | Disaster recovery |
| Admin | Backstage | 2.6.3 | Developer portal |
| DR Storage | Longhorn | 1.11.1 | Persistent block storage |
| Multi-tenancy | vCluster | 0.33.1 | Virtual Kubernetes clusters |
| RBAC | Gatekeeper | 3.22.0 | OPA policy enforcement |
| CI/CD | Tekton | 1.11.1 | Cloud-native pipelines |
| GitOps | ArgoCD | 9.5.4 | Declarative deployments |

## Structure
## Deployment

### Step 1 — Install ArgoCD
```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

### Step 2 — Apply ApplicationSet
```bash
kubectl apply -f platform/gitops/argocd-install.yaml
kubectl apply -f platform/gitops/platform-appset.yaml
kubectl apply -f platform/cicd/tekton-app.yaml
```

### Step 3 — ArgoCD syncs everything automatically

## Languages
- Infrastructure: Go (majority of tools)
- Data Plane: Rust (Linkerd proxy, Quickwit, Qdrant)
- Messaging: C++ (Redpanda)
- Security: C++ (Falco)
