#!/usr/bin/env bash
set -euo pipefail

# Creates (or updates) all k8s Secrets for the bizno namespace, plus the
# grafana-dashboard-json ConfigMap (generated straight from the dashboard
# JSON file, so it's always in sync). Secret values are read from a local
# .env.secrets file that is NEVER committed to git.
#
# Usage (run from infra/secrets/):
#   cp env.secrets.example .env.secrets
#   # edit .env.secrets with real values
#   ./create-secrets.sh

ENV_FILE=".env.secrets"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found."
  echo "Copy env.secrets.example to .env.secrets and fill in real values first:"
  echo "  cp env.secrets.example .env.secrets"
  exit 1
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

for var in POSTGRES_DB POSTGRES_USER POSTGRES_PASSWORD GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD REDIS_PASSWORD; do
  if [ -z "${!var:-}" ]; then
    echo "ERROR: $var is not set in $ENV_FILE."
    exit 1
  fi
done

kubectl apply -f namespace.yml

echo ">> Creating/updating auth-postgres-secret..."
kubectl create secret generic auth-postgres-secret \
  --namespace bizno \
  --from-literal=POSTGRES_DB="$POSTGRES_DB" \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Creating/updating grafana-admin-secret..."
kubectl create secret generic grafana-admin-secret \
  --namespace bizno \
  --from-literal=GF_SECURITY_ADMIN_USER="$GRAFANA_ADMIN_USER" \
  --from-literal=GF_SECURITY_ADMIN_PASSWORD="$GRAFANA_ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -


echo ">> Creating/updating grafana-datasources..."
kubectl create configmap grafana-datasources \
  --namespace bizno \
  --from-file=../grafana/provisioning/datasources/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Creating/updating grafana-dashboard-provider..."
kubectl create configmap grafana-dashboard-provider \
  --namespace bizno \
  --from-file=../grafana/provisioning/dashboards/dashboards.yml \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Creating/updating grafana-dashboard-json ConfigMap..."
# Generated straight from the JSON file — always in sync, no manual
# regeneration needed when the dashboard changes.
kubectl create configmap grafana-dashboard-json \
  --namespace bizno \
  --from-file=../grafana/provisioning/dashboards/json/bizno-auth-overview.json \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Creating/updating loki-config..."
kubectl create configmap loki-config \
  --namespace bizno \
  --from-file=../loki/loki-config.yml \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Creating/updating lprometheus-config..."
kubectl create configmap lprometheus-config \
  --namespace bizno \
  --from-file=../prometheus/prometheus.yml \
  --dry-run=client -o yaml | kubectl apply -f -

echo ">> Creating/updating redis-secret..."
kubectl create secret generic redis-secret \
  --namespace bizno \
  --from-literal=REDIS_PASSWORD="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Namespace + Secrets + grafana-dashboard-json ConfigMap created/updated in 'bizno'."
echo "Verify with: kubectl get secrets,configmaps -n bizno"