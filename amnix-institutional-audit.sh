#!/usr/bin/env bash
# ============================================================
# AMNIX FINANCE — INSTITUTIONAL AUDIT SCRIPT v1.0
# repo: amnixfinance-cyber/amnixfinance
# تشغيل: bash amnix-institutional-audit.sh <path-to-repo-root>
# ============================================================
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────
REPO="${1:-.}"
SERVICES_DIR="$REPO/services"
PLATFORM_DIR="$REPO/platform"
INFRA_DIR="$REPO/infrastructure"
SCORE=0
TOTAL=0
FAILURES=()
WARNINGS=()

# Known services
ALL_SERVICES=(auth ingestion processing realtime analytics search billing notifications feature-flags control-plane developer-portal tenant-operator hydration jobs ml-engine)
DONE_SERVICES=(auth ingestion processing realtime analytics search billing notifications)
TODO_SERVICES=(feature-flags control-plane developer-portal tenant-operator hydration jobs ml-engine)

# Reserved ports (platform tools)
declare -A RESERVED_PORTS=(
  [kratos]="4433 4434"
  [kratos-ui]="4435 4436 4437"
  [oathkeeper]="4455 4456"
  [keto]="4466 4467"
  [hydra]="4444 4445"
  [redpanda]="9092 9093 8082 8081"
  [quickwit]="7280"
  [apisix]="9080 9443"
  [backstage]="7007"
  [lago]="3000"
  [grafana-oncall]="8080"
  [minio]="9000 9001"
)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────
pass()    { echo -e "  ${GREEN}✅ PASS${NC} $1"; SCORE=$((SCORE+1)); TOTAL=$((TOTAL+1)); }
fail()    { echo -e "  ${RED}❌ FAIL${NC} $1"; FAILURES+=("$1"); TOTAL=$((TOTAL+1)); }
warn()    { echo -e "  ${YELLOW}⚠️  WARN${NC} $1"; WARNINGS+=("$1"); }
info()    { echo -e "  ${DIM}ℹ️  $1${NC}"; }
section() { echo -e "\n${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"; \
            echo -e "${BOLD}${BLUE}  $1${NC}"; \
            echo -e "${BOLD}${BLUE}══════════════════════════════════════════════════${NC}"; }
subsec()  { echo -e "\n${CYAN}  ── $1 ──${NC}"; }

# ─────────────────────────────────────────────────────────────
# SECTION 1: REPO STRUCTURE
# ─────────────────────────────────────────────────────────────
section "§1 REPO STRUCTURE — هيكل الـ repo"

subsec "Required top-level directories"
for d in infrastructure platform services; do
  if [ -d "$REPO/$d" ]; then
    pass "Directory exists: $d/"
  else
    fail "Directory MISSING: $d/"
  fi
done

subsec "Platform GitOps files"
for f in \
  "$PLATFORM_DIR/gitops/argocd-install.yaml" \
  "$PLATFORM_DIR/gitops/platform-appset.yaml" \
  "$PLATFORM_DIR/cicd/tekton-app.yaml"; do
  if [ -f "$f" ]; then
    pass "File exists: ${f#$REPO/}"
  else
    fail "File MISSING: ${f#$REPO/}"
  fi
done

subsec "Infrastructure blueprints"
for d in argocd karpenter multi-tenancy-with-teams wireguard-with-cilium; do
  if [ -d "$INFRA_DIR/$d" ]; then
    pass "Blueprint exists: infrastructure/$d/"
  else
    fail "Blueprint MISSING: infrastructure/$d/"
  fi
done

subsec "All 15 service directories"
for svc in "${ALL_SERVICES[@]}"; do
  if [ -d "$SERVICES_DIR/$svc" ]; then
    pass "Service dir exists: services/$svc/"
  else
    warn "Service dir MISSING (TODO): services/$svc/"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 2: EMBEDDED GIT REPOS
# ─────────────────────────────────────────────────────────────
section "§2 EMBEDDED GIT — no nested .git repos"

EMBEDDED=$(find "$SERVICES_DIR" -name ".git" -type d 2>/dev/null)
if [ -z "$EMBEDDED" ]; then
  pass "No embedded .git directories found in services/"
else
  while IFS= read -r eg; do
    fail "Embedded .git found: $eg — يجب حذفه فوراً"
  done <<< "$EMBEDDED"
fi

EMBEDDED_INFRA=$(find "$INFRA_DIR" -name ".git" -type d 2>/dev/null)
if [ -z "$EMBEDDED_INFRA" ]; then
  pass "No embedded .git in infrastructure/"
else
  while IFS= read -r eg; do
    fail "Embedded .git found: $eg"
  done <<< "$EMBEDDED_INFRA"
fi

# ─────────────────────────────────────────────────────────────
# SECTION 3: PORT CONFLICTS
# ─────────────────────────────────────────────────────────────
section "§3 PORT CONFLICTS — تعارضات المنافذ"

subsec "Scanning all services for port declarations"
ALL_USED_PORTS=()
declare -A PORT_SOURCE

for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  # Scan YAML/Go/Rust/Python files for ports
  while IFS= read -r line; do
    port=$(echo "$line" | grep -oE '[0-9]{4,5}' | head -1)
    [ -z "$port" ] && continue
    [ "$port" -lt 1024 ] && continue
    [ "$port" -gt 65535 ] && continue
    
    # Check against reserved
    for tool in "${!RESERVED_PORTS[@]}"; do
      for rport in ${RESERVED_PORTS[$tool]}; do
        if [ "$port" = "$rport" ]; then
          fail "PORT CONFLICT: services/$svc uses port $port — reserved by $tool"
        fi
      done
    done
    
    # Check cross-service conflicts
    if [ -n "${PORT_SOURCE[$port]+_}" ]; then
      if [ "${PORT_SOURCE[$port]}" != "$svc" ]; then
        fail "PORT COLLISION: $port used by both services/$svc AND services/${PORT_SOURCE[$port]}"
      fi
    else
      PORT_SOURCE[$port]="$svc"
      ALL_USED_PORTS+=("$port")
    fi
  done < <(grep -rE "(containerPort|port:|PORT|LISTEN|ListenAddr|addr|bind).*[0-9]{4,5}" \
             "$svc_dir" --include="*.yaml" --include="*.yml" \
             --include="*.go" --include="*.rs" --include="*.py" \
             --include="*.env" --include="*.toml" 2>/dev/null | \
             grep -oE '[0-9]{4,5}' | sort -u)
done

if [ ${#PORT_SOURCE[@]} -gt 0 ]; then
  info "Detected service ports: ${!PORT_SOURCE[*]}"
  pass "Port scan completed — ${#PORT_SOURCE[@]} unique ports found"
fi

# ─────────────────────────────────────────────────────────────
# SECTION 4: LANGUAGE & VERSION CONSISTENCY
# ─────────────────────────────────────────────────────────────
section "§4 LANGUAGE & VERSION CONSISTENCY"

subsec "Go version consistency across services"
GO_VERSIONS=()
for svc in "${DONE_SERVICES[@]}"; do
  gomod="$SERVICES_DIR/$svc/go.mod"
  [ -f "$gomod" ] || continue
  ver=$(grep -E "^go [0-9]" "$gomod" | awk '{print $2}' | head -1)
  GO_VERSIONS+=("$svc:$ver")
  info "$svc → go $ver"
done

UNIQUE_GO=$(printf '%s\n' "${GO_VERSIONS[@]}" | awk -F: '{print $2}' | sort -u)
if [ "$(echo "$UNIQUE_GO" | wc -l)" -le 1 ]; then
  pass "Go version consistent across all services: $UNIQUE_GO"
else
  warn "Multiple Go versions detected — review for compatibility:"
  echo "$UNIQUE_GO" | while IFS= read -r v; do warn "  version: $v"; done
fi

subsec "Dockerfile convention: Go→Dockerfile.arm64, Python→Dockerfile"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  if [ -f "$svc_dir/go.mod" ]; then
    # Go service — must have Dockerfile.arm64
    if [ -f "$svc_dir/Dockerfile.arm64" ]; then
      pass "$svc: Dockerfile.arm64 exists (Go service ✓)"
    else
      fail "$svc: MISSING Dockerfile.arm64 (Go service requires it)"
    fi
    if [ -f "$svc_dir/Dockerfile" ] && [ ! -f "$svc_dir/Dockerfile.arm64" ]; then
      warn "$svc: Has Dockerfile but not Dockerfile.arm64 — wrong convention"
    fi
  fi
  
  if [ -f "$svc_dir/pyproject.toml" ] || [ -f "$svc_dir/requirements.txt" ] || \
     [ -f "$svc_dir/setup.py" ] || [ -f "$svc_dir/poetry.lock" ]; then
    # Python service — must have Dockerfile NOT Dockerfile.arm64
    if [ -f "$svc_dir/Dockerfile" ]; then
      pass "$svc: Dockerfile exists (Python service ✓)"
    else
      fail "$svc: MISSING Dockerfile (Python service requires Dockerfile not Dockerfile.arm64)"
    fi
    if [ -f "$svc_dir/Dockerfile.arm64" ]; then
      fail "$svc: Has Dockerfile.arm64 — Python services MUST NOT use this"
    fi
  fi
  
  if [ -f "$svc_dir/Cargo.toml" ]; then
    # Rust service
    if [ -f "$svc_dir/Dockerfile.arm64" ]; then
      pass "$svc: Dockerfile.arm64 exists (Rust service ✓)"
    else
      fail "$svc: MISSING Dockerfile.arm64 (Rust service requires it)"
    fi
  fi
done

subsec "cmd/server/main.go convention for Go services"
for svc in "${DONE_SERVICES[@]}"; do
  gomod="$SERVICES_DIR/$svc/go.mod"
  [ -f "$gomod" ] || continue
  mainpath="$SERVICES_DIR/$svc/cmd/server/main.go"
  if [ -f "$mainpath" ]; then
    pass "$svc: cmd/server/main.go exists ✓"
  else
    # Check for wrong location
    if [ -f "$SERVICES_DIR/$svc/main.go" ]; then
      fail "$svc: main.go at root — must be at cmd/server/main.go"
    else
      fail "$svc: MISSING cmd/server/main.go"
    fi
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 5: KUBERNETES MANIFEST QUALITY
# ─────────────────────────────────────────────────────────────
section "§5 KUBERNETES MANIFESTS — جودة الـ manifests"

subsec "Required k8s files per service"
K8S_REQUIRED=(deployment.yaml service.yaml kustomization.yaml)
# Some may be rollout.yaml instead of deployment.yaml for Argo Rollouts

for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  k8s_dir=""
  for candidate in "$svc_dir/k8s" "$svc_dir/deploy" "$svc_dir/kubernetes" "$svc_dir/manifests"; do
    [ -d "$candidate" ] && k8s_dir="$candidate" && break
  done
  
  if [ -z "$k8s_dir" ]; then
    fail "$svc: No k8s directory found (k8s/, deploy/, kubernetes/, manifests/)"
    continue
  fi
  
  info "$svc: k8s dir = ${k8s_dir#$REPO/}"
  
  # Check rollout vs deployment
  if find "$k8s_dir" -name "rollout.yaml" | grep -q .; then
    pass "$svc: rollout.yaml exists (Argo Rollouts ✓)"
  elif find "$k8s_dir" -name "deployment*.yaml" -o -name "*deploy*.yaml" | grep -q .; then
    warn "$svc: Uses deployment.yaml — should use kind: Rollout for Argo Rollouts"
  else
    fail "$svc: No deployment.yaml OR rollout.yaml found"
  fi
  
  # service.yaml
  if find "$k8s_dir" -name "*service*.yaml" | grep -q .; then
    pass "$svc: service.yaml exists ✓"
  else
    fail "$svc: MISSING service.yaml"
  fi
  
  # kustomization.yaml
  if find "$k8s_dir" -name "kustomization.yaml" -o -name "kustomization.yml" 2>/dev/null | grep -q .; then
    pass "$svc: kustomization.yaml exists ✓"
  else
    fail "$svc: MISSING kustomization.yaml"
  fi
done

subsec "kind: Rollout (not Deployment) enforcement"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  # Check if any yaml uses kind: Deployment (should be Rollout)
  BAD_DEPLOYMENTS=$(grep -rl "^kind: Deployment" "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null || true)
  if [ -n "$BAD_DEPLOYMENTS" ]; then
    fail "$svc: Found kind: Deployment — must be kind: Rollout (Argo Rollouts)"
    echo "$BAD_DEPLOYMENTS" | while IFS= read -r f; do warn "  → $f"; done
  else
    pass "$svc: No bare kind: Deployment found ✓"
  fi
done

subsec "Resource limits & requests"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  YAML_FILES=$(find "$svc_dir" -name "*.yaml" -o -name "*.yml" 2>/dev/null)
  [ -z "$YAML_FILES" ] && continue
  
  HAS_LIMITS=$(echo "$YAML_FILES" | xargs grep -l "limits:" 2>/dev/null | head -1 || true)
  HAS_REQUESTS=$(echo "$YAML_FILES" | xargs grep -l "requests:" 2>/dev/null | head -1 || true)
  
  if [ -n "$HAS_LIMITS" ] && [ -n "$HAS_REQUESTS" ]; then
    pass "$svc: Resource limits and requests defined ✓"
  elif [ -z "$HAS_LIMITS" ] && [ -z "$HAS_REQUESTS" ]; then
    fail "$svc: MISSING both resource limits AND requests"
  elif [ -z "$HAS_LIMITS" ]; then
    fail "$svc: MISSING resource limits"
  else
    fail "$svc: MISSING resource requests"
  fi
done

subsec "Liveness & Readiness probes"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  YAML_FILES=$(find "$svc_dir" -name "*.yaml" -o -name "*.yml" 2>/dev/null)
  [ -z "$YAML_FILES" ] && continue
  
  HAS_LIVENESS=$(echo "$YAML_FILES" | xargs grep -l "livenessProbe:" 2>/dev/null | head -1 || true)
  HAS_READINESS=$(echo "$YAML_FILES" | xargs grep -l "readinessProbe:" 2>/dev/null | head -1 || true)
  
  [ -n "$HAS_LIVENESS" ]  && pass "$svc: livenessProbe defined ✓"  || fail "$svc: MISSING livenessProbe"
  [ -n "$HAS_READINESS" ] && pass "$svc: readinessProbe defined ✓" || fail "$svc: MISSING readinessProbe"
done

subsec "NetworkPolicy per service"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_NETPOL=$(grep -rl "kind: NetworkPolicy" "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_NETPOL" ]; then
    pass "$svc: NetworkPolicy defined ✓"
  else
    fail "$svc: MISSING NetworkPolicy — تسرب شبكي محتمل"
  fi
done

subsec "PodDisruptionBudget per service"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_PDB=$(grep -rl "kind: PodDisruptionBudget" "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_PDB" ]; then
    pass "$svc: PodDisruptionBudget defined ✓"
    # Check for KEDA conflict: maxUnavailable:1 + minReplicaCount:0
    PDB_MAX=$(grep -r "maxUnavailable:" "$svc_dir" 2>/dev/null | grep -v "^--$" | head -1 || true)
    KEDA_MIN=$(grep -r "minReplicaCount:" "$svc_dir" 2>/dev/null | grep -v "^--$" | head -1 || true)
    if echo "$PDB_MAX" | grep -q ": 1" && echo "$KEDA_MIN" | grep -q ": 0"; then
      fail "$svc: PDB maxUnavailable:1 + KEDA minReplicaCount:0 = DEADLOCK (known bug)"
    fi
  else
    warn "$svc: No PodDisruptionBudget — HA risk during rolling updates"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 6: KEDA SCALING
# ─────────────────────────────────────────────────────────────
section "§6 KEDA SCALING — إعدادات التوسع"

for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_SCALEDOBJECT=$(grep -rl "kind: ScaledObject" "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_SCALEDOBJECT" ]; then
    pass "$svc: ScaledObject (KEDA) defined ✓"
    
    # Check for ignoreDifferences on /spec/replicas in ArgoCD app
    APP_FILE=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
               xargs grep -l "$svc" 2>/dev/null | \
               xargs grep -l "ignoreDifferences" 2>/dev/null | head -1 || true)
    if [ -n "$APP_FILE" ]; then
      IGNORE_REPLICAS=$(grep -A5 "ignoreDifferences" "$APP_FILE" 2>/dev/null | grep "replicas" || true)
      if [ -n "$IGNORE_REPLICAS" ]; then
        pass "$svc: ArgoCD ignoreDifferences on /spec/replicas ✓"
      else
        warn "$svc: KEDA ScaledObject present but ArgoCD ignoreDifferences for replicas not found"
      fi
    fi
  else
    warn "$svc: No ScaledObject — KEDA scaling not configured"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 7: SERVICE MESH — LINKERD
# ─────────────────────────────────────────────────────────────
section "§7 SERVICE MESH — Linkerd annotations"

for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_LINKERD=$(grep -r "linkerd.io/inject" "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_LINKERD" ]; then
    INJECT_VAL=$(echo "$HAS_LINKERD" | grep -oE '"enabled"|"disabled"' | head -1 || true)
    if echo "$HAS_LINKERD" | grep -q '"enabled"'; then
      pass "$svc: linkerd.io/inject: enabled ✓"
    else
      warn "$svc: linkerd.io/inject present but value = $INJECT_VAL"
    fi
  else
    fail "$svc: MISSING linkerd.io/inject annotation — service mesh bypass"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 8: SECURITY — أمان متعدد الطبقات
# ─────────────────────────────────────────────────────────────
section "§8 SECURITY — فحص الأمان"

subsec "8.1 Hardcoded secrets / credentials"
SECRET_PATTERNS='password\s*=\s*"[^${\"]|secret\s*=\s*"[^${\"]|api_key\s*=\s*"[^${\"]|token\s*=\s*"[^${\"]|AWS_SECRET\s*=\s*[^${\"]|private_key.*-----BEGIN'

for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  FOUND=$(grep -rEi "$SECRET_PATTERNS" "$svc_dir" \
          --include="*.go" --include="*.rs" --include="*.py" \
          --include="*.yaml" --include="*.yml" --include="*.env" \
          --include="*.toml" --include="*.json" \
          --exclude-dir=".git" --exclude-dir="vendor" 2>/dev/null | \
          grep -v "_test\." | grep -v "example\|sample\|TODO\|FIXME\|placeholder" | head -5 || true)
  
  if [ -z "$FOUND" ]; then
    pass "$svc: No hardcoded secrets found ✓"
  else
    fail "$svc: HARDCODED SECRETS DETECTED — فضيحة أمنية:"
    echo "$FOUND" | while IFS= read -r line; do
      warn "  → $line"
    done
  fi
done

subsec "8.2 \${VAR} pattern for secrets in YAML"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  # Check env vars in YAML — should use ${VAR} or secretKeyRef, not literal values
  INLINE_VALS=$(grep -rE 'value:\s+"[A-Za-z0-9+/]{20,}"' "$svc_dir" \
                --include="*.yaml" --include="*.yml" 2>/dev/null | \
                grep -iv "image:\|tag:\|version:" | head -5 || true)
  
  if [ -z "$INLINE_VALS" ]; then
    pass "$svc: No suspicious inline secret values in YAML ✓"
  else
    warn "$svc: Possible inline secret values (review manually):"
    echo "$INLINE_VALS" | while IFS= read -r line; do warn "  → $line"; done
  fi
done

subsec "8.3 ExternalSecrets / SecretKeyRef usage"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_ESO=$(grep -rl "ExternalSecret\|secretKeyRef\|SecretKeyRef" "$svc_dir" \
             --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_ESO" ]; then
    pass "$svc: Uses ExternalSecret / secretKeyRef ✓"
  else
    warn "$svc: No ExternalSecret or secretKeyRef found — secrets injection unclear"
  fi
done

subsec "8.4 runAsNonRoot / securityContext"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_NONROOT=$(grep -rl "runAsNonRoot\|runAsUser" "$svc_dir" \
                --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_NONROOT" ]; then
    pass "$svc: securityContext/runAsNonRoot configured ✓"
  else
    fail "$svc: MISSING runAsNonRoot — containers may run as root"
  fi
done

subsec "8.5 readOnlyRootFilesystem"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_RO=$(grep -rl "readOnlyRootFilesystem" "$svc_dir" \
            --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_RO" ]; then
    pass "$svc: readOnlyRootFilesystem configured ✓"
  else
    warn "$svc: readOnlyRootFilesystem not set — filesystem writable"
  fi
done

subsec "8.6 allowPrivilegeEscalation: false"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_APE=$(grep -rl "allowPrivilegeEscalation" "$svc_dir" \
             --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_APE" ]; then
    VAL=$(grep -r "allowPrivilegeEscalation" "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null | grep -o "false\|true" | head -1 || true)
    [ "$VAL" = "false" ] && pass "$svc: allowPrivilegeEscalation: false ✓" || fail "$svc: allowPrivilegeEscalation is NOT false"
  else
    fail "$svc: MISSING allowPrivilegeEscalation: false"
  fi
done

subsec "8.7 ServiceAccount per service (no default)"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_SA=$(grep -rl "kind: ServiceAccount" "$svc_dir" \
            --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_SA" ]; then
    pass "$svc: ServiceAccount defined ✓"
    # Check for duplicate ServiceAccounts
    SA_COUNT=$(grep -rl "kind: ServiceAccount" "$svc_dir" \
               --include="*.yaml" --include="*.yml" 2>/dev/null | wc -l || echo 0)
    [ "$SA_COUNT" -gt 1 ] && warn "$svc: Multiple ServiceAccount files ($SA_COUNT) — check for duplicates"
  else
    fail "$svc: MISSING ServiceAccount — uses default SA (security risk)"
  fi
done

subsec "8.8 RBAC — Role/ClusterRole bindings"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_RBAC=$(grep -rl "kind: Role\|kind: ClusterRole" "$svc_dir" \
              --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_RBAC" ]; then
    pass "$svc: RBAC Role/ClusterRole defined ✓"
    # Check for wildcard permissions
    WILDCARDS=$(grep -r '"[*]"' "$svc_dir" --include="*.yaml" --include="*.yml" 2>/dev/null | \
                grep -v "^--$" | head -3 || true)
    if [ -n "$WILDCARDS" ]; then
      warn "$svc: WILDCARD (*) permissions found in RBAC — review:"
      echo "$WILDCARDS" | while IFS= read -r line; do warn "  → $line"; done
    fi
  else
    warn "$svc: No explicit RBAC roles — may rely on cluster defaults"
  fi
done

subsec "8.9 Tenant isolation — tenantID header injection check"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  # Known vulnerability: tenantID from HTTP header without JWT verification
  HEADER_TENANT=$(grep -rn 'Header.*[Tt]enant\|[Tt]enant.*Header\|r\.Header\.Get.*tenant' \
                   "$svc_dir" --include="*.go" 2>/dev/null | \
                  grep -v "_test\." | head -3 || true)
  if [ -n "$HEADER_TENANT" ]; then
    warn "$svc: tenantID read from HTTP header — verify JWT validation is enforced:"
    echo "$HEADER_TENANT" | while IFS= read -r line; do warn "  → $line"; done
  else
    pass "$svc: No unprotected tenant header reads detected ✓"
  fi
done

subsec "8.10 Authentication on all endpoints"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  # Check for auth middleware
  HAS_AUTH=$(grep -rn "middleware\|Middleware\|AuthMiddleware\|JWTMiddleware\|RequireAuth" \
              "$svc_dir" --include="*.go" 2>/dev/null | \
              grep -v "_test\." | head -1 || true)
  if [ -n "$HAS_AUTH" ]; then
    pass "$svc: Auth middleware found ✓"
  else
    warn "$svc: No explicit auth middleware found — verify all routes are protected"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 9: CI/CD PIPELINE COVERAGE
# ─────────────────────────────────────────────────────────────
section "§9 CI/CD PIPELINE — تغطية الـ pipelines"

WORKFLOWS_DIR="$REPO/.github/workflows"
TEKTON_DIR="$PLATFORM_DIR/cicd"

subsec "9.1 GitHub Actions workflow files"
for wf in image-sign.yml release.yml; do
  wf_path="$WORKFLOWS_DIR/$wf"
  if [ -f "$wf_path" ]; then
    pass "Workflow exists: .github/workflows/$wf"
    
    # Check every done service is referenced
    for svc in "${DONE_SERVICES[@]}"; do
      if grep -q "$svc" "$wf_path" 2>/dev/null; then
        pass "$wf: references $svc ✓"
      else
        fail "$wf: MISSING reference to service '$svc'"
      fi
    done
  else
    warn "Workflow MISSING: .github/workflows/$wf (may use Tekton instead)"
  fi
done

subsec "9.2 Cosign image signing"
if [ -d "$WORKFLOWS_DIR" ]; then
  HAS_COSIGN=$(grep -rl "cosign" "$WORKFLOWS_DIR" --include="*.yml" --include="*.yaml" 2>/dev/null | head -1 || true)
  [ -n "$HAS_COSIGN" ] && pass "Cosign signing configured in CI ✓" || warn "Cosign signing not found in workflows"
  
  HAS_SBOM=$(grep -rl "sbom\|SBOM\|syft" "$WORKFLOWS_DIR" --include="*.yml" --include="*.yaml" 2>/dev/null | head -1 || true)
  [ -n "$HAS_SBOM" ] && pass "SBOM generation configured ✓" || warn "SBOM generation not found"
  
  HAS_GRYPE=$(grep -rl "grype\|trivy\|snyk" "$WORKFLOWS_DIR" --include="*.yml" --include="*.yaml" 2>/dev/null | head -1 || true)
  [ -n "$HAS_GRYPE" ] && pass "Vulnerability scanning (Grype/Trivy) configured ✓" || warn "No CVE scanner found in CI"
fi

subsec "9.3 Kyverno policy for cosign signature enforcement"
HAS_KYVERNO_COSIGN=$(grep -rl "ClusterPolicy\|verify.*image\|cosign" "$REPO" \
                      --include="*.yaml" --include="*.yml" 2>/dev/null | \
                     xargs grep -l "ClusterPolicy" 2>/dev/null | head -1 || true)
[ -n "$HAS_KYVERNO_COSIGN" ] && pass "Kyverno ClusterPolicy for image signing found ✓" || warn "Kyverno image signature enforcement not found"

subsec "9.4 ArgoCD AppSet — all services registered"
APPSET_FILE="$PLATFORM_DIR/gitops/platform-appset.yaml"
SERVICES_APPSET_FILE="$PLATFORM_DIR/gitops/services-appset.yaml"
SERVICES_APPSET_FILE="$PLATFORM_DIR/gitops/services-appset.yaml"
if [ -f "$APPSET_FILE" ]; then
  for svc in "${DONE_SERVICES[@]}"; do
    if grep -q "$svc" "$APPSET_FILE" || grep -q "$svc" "$SERVICES_APPSET_FILE" 2>/dev/null 2>/dev/null; then
      pass "AppSet: $svc registered ✓"
    else
      fail "AppSet: $svc NOT registered in platform-appset.yaml"
    fi
  done
else
  fail "platform-appset.yaml not found — cannot verify service registration"
fi

# ─────────────────────────────────────────────────────────────
# SECTION 10: DATABASE & MIGRATIONS
# ─────────────────────────────────────────────────────────────
section "§10 DATABASE & MIGRATIONS"

subsec "10.1 Migration files structure"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  MIG_DIR=""
  for candidate in "$svc_dir/migrations" "$svc_dir/db/migrations" "$svc_dir/internal/db/migrations"; do
    [ -d "$candidate" ] && MIG_DIR="$candidate" && break
  done
  
  if [ -z "$MIG_DIR" ]; then
    # Not all services need migrations
    info "$svc: No migrations directory (may not need DB)"
    continue
  fi
  
  MIG_COUNT=$(find "$MIG_DIR" -name "*.sql" 2>/dev/null | wc -l)
  pass "$svc: Migrations directory found ($MIG_COUNT SQL files)"
  
  # Check scope header
  for sql in "$MIG_DIR"/*.sql; do
    [ -f "$sql" ] || continue
    if grep -q "Scope:" "$sql" 2>/dev/null; then
      pass "$svc: $(basename $sql) has Scope header ✓"
    else
      warn "$svc: $(basename $sql) missing '-- Scope:' header"
    fi
  done
  
  # Check for sequential numbering gaps
  NUMS=$(find "$MIG_DIR" -name "*.sql" 2>/dev/null | \
         grep -oE '[0-9]+' | sort -n)
  PREV=0
  while IFS= read -r n; do
    EXPECTED=$((PREV + 1))
    [ "$n" -ne "$EXPECTED" ] && warn "$svc: Migration gap — expected $EXPECTED, got $n"
    PREV=$n
  done <<< "$NUMS"
done

subsec "10.2 NOT VALID constraint pattern for production safety"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  LARGE_TABLES_CONSTRAINTS=$(grep -rn "ADD CONSTRAINT" "$svc_dir" --include="*.sql" 2>/dev/null | \
                              grep -v "NOT VALID" | grep -v "PRIMARY KEY\|UNIQUE" | head -5 || true)
  if [ -z "$LARGE_TABLES_CONSTRAINTS" ]; then
    pass "$svc: FK constraints use NOT VALID pattern ✓"
  else
    warn "$svc: Some ADD CONSTRAINT without NOT VALID — table lock risk on large tables:"
    echo "$LARGE_TABLES_CONSTRAINTS" | while IFS= read -r line; do warn "  → $line"; done
  fi
done

subsec "10.3 RLS policies"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_RLS=$(grep -rl "ROW LEVEL SECURITY\|ENABLE ROW\|CREATE POLICY" "$svc_dir" \
             --include="*.sql" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_RLS" ]; then
    pass "$svc: Row Level Security policies found ✓"
    
    # Check every table with RLS also has a policy
    TABLES_RLS=$(grep -rh "ENABLE ROW LEVEL SECURITY" "$svc_dir" --include="*.sql" 2>/dev/null | \
                 grep -oE "ON [a-z_.]+" | sort || true)
    POLICIES=$(grep -rh "CREATE POLICY" "$svc_dir" --include="*.sql" 2>/dev/null | \
               grep -oE "ON [a-z_.]+" | sort || true)
    
    while IFS= read -r tbl; do
      tblname=$(echo "$tbl" | awk '{print $2}')
      if ! echo "$POLICIES" | grep -q "$tblname"; then
        warn "$svc: Table $tblname has RLS enabled but no policy found — will block ALL access"
      fi
    done <<< "$TABLES_RLS"
  else
    warn "$svc: No RLS found — multi-tenant isolation at DB level unverified"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 11: PROTO / API CONTRACTS
# ─────────────────────────────────────────────────────────────
section "§11 PROTO / API CONTRACTS"

GEN_DIR="$REPO/gen"
PROTO_DIR="$REPO/proto"

subsec "11.1 Proto files location"
if [ -d "$PROTO_DIR" ]; then
  PROTO_COUNT=$(find "$PROTO_DIR" -name "*.proto" 2>/dev/null | wc -l)
  pass "Proto directory exists: proto/ ($PROTO_COUNT .proto files)"
else
  warn "No proto/ directory found — gRPC contracts location unclear"
fi

subsec "11.2 Generated code at /gen/ root (not per-service)"
if [ -d "$GEN_DIR" ]; then
  pass "Gen directory exists at repo root: gen/ ✓"
  # Check no service has its own gen/
  for svc in "${DONE_SERVICES[@]}"; do
    svc_dir="$SERVICES_DIR/$svc"
    [ -d "$svc_dir" ] || continue
    if [ -d "$svc_dir/gen" ]; then
      fail "$svc: Has per-service gen/ directory — proto gen must be at /gen/ root only"
    else
      pass "$svc: No per-service gen/ ✓"
    fi
  done
else
  warn "No gen/ directory at repo root — proto generation status unclear"
fi

subsec "11.3 API versioning"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  # Check for /v1/ in route definitions
  HAS_VERSION=$(grep -rn '"/v[0-9]' "$svc_dir" --include="*.go" --include="*.rs" 2>/dev/null | \
                grep -v "_test\." | head -1 || true)
  if [ -n "$HAS_VERSION" ]; then
    pass "$svc: API versioning in routes (/v1/, etc.) ✓"
  else
    warn "$svc: No API versioning detected in routes"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 12: INTEGRATION MAP VERIFICATION
# ─────────────────────────────────────────────────────────────
section "§12 INTEGRATION MAP — التكامل بين الـ services والـ platform"

declare -A SERVICE_INTEGRATIONS=(
  [auth]="kratos hydra keto oathkeeper"
  [billing]="lago"
  [notifications]="oncall grafana"
  [search]="quickwit"
  [ingestion]="redpanda minio"
  [processing]="redpanda clickhouse"
  [realtime]="redpanda redis"
  [analytics]="clickhouse quickwit"
)

for svc in "${!SERVICE_INTEGRATIONS[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  for integration in ${SERVICE_INTEGRATIONS[$svc]}; do
    FOUND=$(grep -rin "$integration" "$svc_dir" \
             --include="*.go" --include="*.rs" --include="*.py" \
             --include="*.yaml" --include="*.yml" --include="*.toml" \
             --include="*.env" 2>/dev/null | \
             grep -v "_test\." | head -1 || true)
    if [ -n "$FOUND" ]; then
      pass "$svc ↔ $integration: integration referenced ✓"
    else
      warn "$svc ↔ $integration: no reference found — integration may be incomplete"
    fi
  done
done

# ─────────────────────────────────────────────────────────────
# SECTION 13: DEPENDENCY SUPPLY CHAIN
# ─────────────────────────────────────────────────────────────
section "§13 DEPENDENCY SUPPLY CHAIN — سلسلة التبعيات"

subsec "13.1 Go module integrity"
for svc in "${DONE_SERVICES[@]}"; do
  gomod="$SERVICES_DIR/$svc/go.mod"
  gosum="$SERVICES_DIR/$svc/go.sum"
  
  [ -f "$gomod" ] || continue
  
  if [ -f "$gosum" ]; then
    pass "$svc: go.sum present (dependency checksums) ✓"
  else
    fail "$svc: MISSING go.sum — dependency integrity not guaranteed"
  fi
  
  # Check for 'replace' directives (can introduce untrusted code)
  REPLACES=$(grep "^replace" "$gomod" 2>/dev/null || true)
  if [ -n "$REPLACES" ]; then
    warn "$svc: go.mod has 'replace' directives — verify they are intentional:"
    echo "$REPLACES" | while IFS= read -r line; do warn "  → $line"; done
  else
    pass "$svc: No 'replace' directives in go.mod ✓"
  fi
done

subsec "13.2 Pinned versions (no 'latest' tags)"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  LATEST_TAG=$(grep -rn ":latest" "$svc_dir" \
               --include="*.yaml" --include="*.yml" \
               --include="Dockerfile*" 2>/dev/null | \
               grep -v "#" | head -5 || true)
  if [ -z "$LATEST_TAG" ]; then
    pass "$svc: No ':latest' image tags ✓"
  else
    fail "$svc: ':latest' tag found — pin to specific digest/version:"
    echo "$LATEST_TAG" | while IFS= read -r line; do warn "  → $line"; done
  fi
done

subsec "13.3 Vendor directory"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  if [ -d "$svc_dir/vendor" ]; then
    info "$svc: vendor/ present — ensure it's committed and up to date"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 14: OBSERVABILITY
# ─────────────────────────────────────────────────────────────
section "§14 OBSERVABILITY — المراقبة والرصد"

subsec "14.1 Prometheus metrics annotations"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_PROM=$(grep -rl "prometheus.io/scrape\|prometheus.io/port" "$svc_dir" \
              --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_PROM" ]; then
    pass "$svc: Prometheus scrape annotations present ✓"
  else
    warn "$svc: No Prometheus annotations — metrics scraping not configured"
  fi
done

subsec "14.2 Structured logging"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  HAS_SLOG=$(grep -rl "zap\|zerolog\|slog\|logrus" "$svc_dir" --include="*.go" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_SLOG" ]; then
    pass "$svc: Structured logger (zap/zerolog/slog) found ✓"
  else
    warn "$svc: No structured logger detected — may use fmt.Println"
  fi
done

subsec "14.3 Distributed tracing"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  HAS_TRACE=$(grep -rl "opentelemetry\|otel\|jaeger\|zipkin" "$svc_dir" \
               --include="*.go" --include="go.mod" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_TRACE" ]; then
    pass "$svc: Distributed tracing (OpenTelemetry) found ✓"
  else
    warn "$svc: No distributed tracing — production debugging will be hard"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 15: MULTI-TENANCY ISOLATION
# ─────────────────────────────────────────────────────────────
section "§15 MULTI-TENANCY ISOLATION"

for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  # Check tenant_id in queries
  HAS_TENANT=$(grep -rn "tenant_id\|tenantID\|TenantID" "$svc_dir" --include="*.go" 2>/dev/null | \
               grep -v "_test\." | head -1 || true)
  if [ -n "$HAS_TENANT" ]; then
    pass "$svc: tenant_id referenced in business logic ✓"
  else
    warn "$svc: tenant_id not found in service code — multi-tenancy isolation unclear"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 16: ERROR HANDLING
# ─────────────────────────────────────────────────────────────
section "§16 ERROR HANDLING"

subsec "16.1 No silent error swallowing"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  SILENT_ERRORS=$(grep -rn "_ = err\|_, err :=.*\n.*if err" "$svc_dir" --include="*.go" 2>/dev/null | \
                  grep -v "_test\." | head -3 || true)
  UNHANDLED=$(grep -rn ":= .*err" "$svc_dir" --include="*.go" 2>/dev/null | \
              grep -v "if err\|return err\|log\|_ =" | grep -v "_test\." | head -3 || true)
  
  if [ -z "$SILENT_ERRORS" ]; then
    pass "$svc: No obvious silent error swallowing ✓"
  else
    warn "$svc: Possible silent error handling:"
    echo "$SILENT_ERRORS" | while IFS= read -r line; do warn "  → $line"; done
  fi
done

subsec "16.2 Background jobs return errors (not nil)"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  [ ! -f "$svc_dir/go.mod" ] && continue
  
  # Critical vulnerability: background handlers returning nil
  NIL_HANDLERS=$(grep -rn "func.*Handler.*{" "$svc_dir" --include="*.go" 2>/dev/null | \
                 grep -v "_test\." | head -5 || true)
  # Simplified check — look for return nil at end of handler functions
  RETURN_NIL=$(grep -rn "^	return nil$" "$svc_dir" --include="*.go" 2>/dev/null | \
               grep -v "_test\." | wc -l || echo 0)
  
  info "$svc: $RETURN_NIL 'return nil' statements in Go code (verify handlers return proper errors)"
done

# ─────────────────────────────────────────────────────────────
# SECTION 17: CERT-MANAGER & TLS
# ─────────────────────────────────────────────────────────────
section "§17 TLS & CERT-MANAGER"

subsec "17.1 Certificate definitions"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  HAS_CERT=$(grep -rl "kind: Certificate\|cert-manager.io" "$svc_dir" \
              --include="*.yaml" --include="*.yml" 2>/dev/null | head -1 || true)
  if [ -n "$HAS_CERT" ]; then
    pass "$svc: Certificate (cert-manager) defined ✓"
  else
    info "$svc: No cert-manager Certificate (may use cluster-wide certs)"
  fi
done

subsec "17.2 TLS in service endpoints"
for svc in "${DONE_SERVICES[@]}"; do
  svc_dir="$SERVICES_DIR/$svc"
  [ -d "$svc_dir" ] || continue
  
  PLAIN_HTTP=$(grep -rn '"http://\|http://' "$svc_dir" --include="*.go" --include="*.yaml" 2>/dev/null | \
               grep -v "localhost\|127.0.0.1\|health\|_test\.\|//\|#" | head -3 || true)
  if [ -n "$PLAIN_HTTP" ]; then
    warn "$svc: Plain HTTP (non-localhost) found — verify mTLS handles this via service mesh:"
    echo "$PLAIN_HTTP" | while IFS= read -r line; do warn "  → $line"; done
  else
    pass "$svc: No plain HTTP to external services ✓"
  fi
done

# ─────────────────────────────────────────────────────────────
# SECTION 18: DISASTER RECOVERY & BACKUP
# ─────────────────────────────────────────────────────────────
section "§18 DISASTER RECOVERY — Velero + Backup"

subsec "18.1 Velero backup schedules"
VELERO_SCHEDULE=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
                  xargs grep -l "kind: Schedule\|kind: Backup" 2>/dev/null | head -1 || true)
if [ -n "$VELERO_SCHEDULE" ]; then
  pass "Velero Schedule/Backup definition found ✓"
else
  warn "No Velero Schedule found — disaster recovery plan unclear"
fi

subsec "18.2 StatefulSet data persistence"
STATEFUL=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
           xargs grep -l "kind: StatefulSet" 2>/dev/null | head -1 || true)
if [ -n "$STATEFUL" ]; then
  pass "StatefulSet definitions found ✓"
  PVC=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
        xargs grep -l "PersistentVolumeClaim\|volumeClaimTemplates" 2>/dev/null | head -1 || true)
  [ -n "$PVC" ] && pass "PersistentVolumeClaims defined ✓" || warn "StatefulSet without PVC definitions"
fi

# ─────────────────────────────────────────────────────────────
# SECTION 19: COMPLIANCE & GOVERNANCE
# ─────────────────────────────────────────────────────────────
section "§19 COMPLIANCE & GOVERNANCE"

subsec "19.1 OPA/Gatekeeper policies"
GATEKEEPER_POLICIES=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
                      xargs grep -l "ConstraintTemplate\|kind: K8s" 2>/dev/null | wc -l || echo 0)
if [ "$GATEKEEPER_POLICIES" -gt 0 ]; then
  pass "Gatekeeper ConstraintTemplate policies found ($GATEKEEPER_POLICIES files) ✓"
else
  warn "No Gatekeeper ConstraintTemplate found — policy enforcement unclear"
fi

subsec "19.2 Falco security rules"
FALCO_RULES=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
              xargs grep -l "falco_rules\|falco.yaml\|macro:\|rule:" 2>/dev/null | head -1 || true)
if [ -n "$FALCO_RULES" ]; then
  pass "Falco rules found ✓"
else
  warn "No custom Falco rules — runtime security detection using defaults only"
fi

subsec "19.3 Audit logging"
AUDIT_LOG=$(find "$REPO" -name "*.yaml" -o -name "*.yml" 2>/dev/null | \
            xargs grep -l "audit\|AuditPolicy\|audit-log" 2>/dev/null | head -1 || true)
if [ -n "$AUDIT_LOG" ]; then
  pass "Audit policy/logging configured ✓"
else
  warn "No explicit audit policy found — compliance audit trail unclear"
fi

# ─────────────────────────────────────────────────────────────
# FINAL SCORECARD
# ─────────────────────────────────────────────────────────────
FAIL_COUNT=${#FAILURES[@]}
WARN_COUNT=${#WARNINGS[@]}
PASS_COUNT=$SCORE

echo ""
echo -e "${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${BLUE}║       AMNIX FINANCE — INSTITUTIONAL AUDIT REPORT     ║${NC}"
echo -e "${BOLD}${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${GREEN}✅ PASS  ${NC}: $PASS_COUNT"
echo -e "  ${RED}❌ FAIL  ${NC}: $FAIL_COUNT"
echo -e "  ${YELLOW}⚠️  WARN  ${NC}: $WARN_COUNT"
echo -e "  ${DIM}📊 TOTAL ${NC}: $TOTAL checks"
echo ""

PERCENT=0
[ $TOTAL -gt 0 ] && PERCENT=$(( (PASS_COUNT * 100) / TOTAL ))

if [ $FAIL_COUNT -eq 0 ]; then
  echo -e "  ${BOLD}${GREEN}OVERALL RESULT: ✅ INSTITUTIONAL PASS ($PERCENT%)${NC}"
elif [ $FAIL_COUNT -le 5 ]; then
  echo -e "  ${BOLD}${YELLOW}OVERALL RESULT: ⚠️  CONDITIONAL PASS ($PERCENT%) — fix FAILs before deploy${NC}"
else
  echo -e "  ${BOLD}${RED}OVERALL RESULT: ❌ INSTITUTIONAL FAIL ($PERCENT%) — requires remediation${NC}"
fi

if [ $FAIL_COUNT -gt 0 ]; then
  echo ""
  echo -e "${BOLD}${RED}━━━ CRITICAL FAILURES (must fix before next service) ━━━${NC}"
  for i in "${!FAILURES[@]}"; do
    echo -e "  ${RED}[$((i+1))]${NC} ${FAILURES[$i]}"
  done
fi

if [ $WARN_COUNT -gt 0 ]; then
  echo ""
  echo -e "${BOLD}${YELLOW}━━━ WARNINGS (address before production) ━━━━━━━━━━━━━${NC}"
  for i in "${!WARNINGS[@]}"; do
    echo -e "  ${YELLOW}[$((i+1))]${NC} ${WARNINGS[$i]}"
  done
fi

echo ""
echo -e "${DIM}Audit completed at $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""