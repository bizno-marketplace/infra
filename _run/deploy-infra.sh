#!/usr/bin/env bash
set -euo pipefail

# Applies every infra component's k8s manifest, in the right order.
# Run from infra/_run/:
#
#   ./deploy-infra.sh
#
# Expected layout (each component folder has a deployment.yml):
#
#   infra/
#   ├── _run/
#   │   └── deploy-infra.sh   <- you are here
#   ├── messaging/deployment.yml
#   ├── loki/deployment.yml
#   ├── zipkin/deployment.yml
#   ├── prometheus/deployment.yml
#   └── grafana/deployment.yml
#
# Order matters loosely: Loki/Zipkin/Prometheus have no dependencies among
# themselves; Grafana goes last since its datasources point at the others
# (it would still start fine either way, but this avoids a brief window of
# unreachable datasources).
#
# NOTE: secrets + the grafana-dashboard-json ConfigMap are NOT applied
# here — run secrets/create-secrets.sh first (one-time, or whenever a
# secret/dashboard changes). Grafana will fail to mount its volumes if
# that hasn't been run yet.

COMPONENTS=(
  "messaging"
  "loki"
  "zipkin"
  "prometheus"
  "grafana"
)

BASE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

for component in "${COMPONENTS[@]}"; do
  MANIFEST="${BASE_DIR}/${component}/deployment.yml"

  if [ ! -f "$MANIFEST" ]; then
    echo "WARNING: ${MANIFEST} not found — skipping ${component}."
    continue
  fi

  echo ">> Applying ${component}..."
  kubectl apply -f "$MANIFEST"
done

echo ""
echo ">> Waiting for all infra pods to become Ready..."
kubectl wait --for=condition=Ready pods --all -n bizno --timeout=180s || true

echo ""
echo "Done. Current state:"
kubectl get pods -n bizno