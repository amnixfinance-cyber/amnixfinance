#!/usr/bin/env bash
set -e

VALIDATE_FILE=".github/workflows/validate.yaml"
FAILED=0

# 1. إصلاح trailing spaces تلقائياً في كل yaml في platform/config/
find platform/config/ -name "*.yaml" -exec sed -i 's/[[:space:]]*$//' {} +

# 2. فحص كل Chart.yaml جديد أو معدّل في services/
for chart in $(git diff --cached --name-only | grep "services/.*/k8s/Chart.yaml"); do
  CHART_NAME=$(grep "^name:" "$chart" 2>/dev/null | awk '{print $2}')
  if [ -z "$CHART_NAME" ]; then
    continue
  fi

  if ! grep -q "helm repo add.*${CHART_NAME}\|helm-charts.*${CHART_NAME}" "$VALIDATE_FILE" 2>/dev/null; then
    echo "❌ MISSING: Chart '${CHART_NAME}' في ${chart}"
    echo "   → أضف helm repo add في ${VALIDATE_FILE}"
    FAILED=1
  fi

  if ! grep -q "helm search repo.*${CHART_NAME}" "$VALIDATE_FILE" 2>/dev/null; then
    echo "❌ MISSING: helm search repo لـ '${CHART_NAME}' في ${VALIDATE_FILE}"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 1 ]; then
  echo ""
  echo "🔴 commit مرفوض — حدّث validate.yaml أولاً"
  exit 1
fi

echo "✅ pre-commit checks passed"
exit 0
