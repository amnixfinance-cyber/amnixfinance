#!/bin/bash
set -euo pipefail

SERVICES_DIR="services"
SERVICES=$(ls "$SERVICES_DIR")

for SERVICE in $SERVICES; do
  K8S_DIR="$SERVICES_DIR/$SERVICE/k8s"
  TEMPLATES_DIR="$K8S_DIR/templates"
  
  echo "Processing: $SERVICE"
  mkdir -p "$TEMPLATES_DIR"

  # 1. NetworkPolicy
  if [ ! -f "$TEMPLATES_DIR/networkpolicy.yaml" ]; then
    cat > "$TEMPLATES_DIR/networkpolicy.yaml" << EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ .Release.Name }}-network-policy
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ .Release.Name }}
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: {{ .Release.Name }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: platform
        - podSelector: {}
  egress:
    - to:
        - namespaceSelector: {}
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
EOF
    echo "  ✅ NetworkPolicy added"
  fi

  # 2. KEDA ScaledObject
  if [ ! -f "$TEMPLATES_DIR/scaledobject.yaml" ]; then
    cat > "$TEMPLATES_DIR/scaledobject.yaml" << EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: {{ .Release.Name }}-scaledobject
  namespace: {{ .Release.Namespace }}
spec:
  scaleTargetRef:
    name: {{ .Release.Name }}
  minReplicaCount: 0
  maxReplicaCount: 10
  triggers:
    - type: cpu
      metadata:
        type: Utilization
        value: "70"
EOF
    echo "  ✅ KEDA ScaledObject added"
  fi

  # 3. ServiceAccount
  if [ ! -f "$TEMPLATES_DIR/serviceaccount.yaml" ]; then
    cat > "$TEMPLATES_DIR/serviceaccount.yaml" << EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ .Release.Name }}
  namespace: {{ .Release.Namespace }}
  labels:
    app.kubernetes.io/name: {{ .Release.Name }}
automountServiceAccountToken: false
EOF
    echo "  ✅ ServiceAccount added"
  fi

  # 4. PodDisruptionBudget
  if [ ! -f "$TEMPLATES_DIR/poddisruptionbudget.yaml" ]; then
    cat > "$TEMPLATES_DIR/poddisruptionbudget.yaml" << EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ .Release.Name }}-pdb
  namespace: {{ .Release.Namespace }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: {{ .Release.Name }}
EOF
    echo "  ✅ PodDisruptionBudget added"
  fi

  # 5. kustomization.yaml
  if [ ! -f "$K8S_DIR/kustomization.yaml" ]; then
    cat > "$K8S_DIR/kustomization.yaml" << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - templates/networkpolicy.yaml
  - templates/scaledobject.yaml
  - templates/serviceaccount.yaml
  - templates/poddisruptionbudget.yaml
EOF
    echo "  ✅ kustomization.yaml added"
  fi

  echo "  ✅ $SERVICE done"
done

echo ""
echo "✅ All services updated with platform standards"
