#!/usr/bin/env bash
# sync_groq_key.sh
# Reads GROQ_API_KEY from .env and syncs it to:
#   1. K8s secret (rag-secrets in rag-system namespace)
#   2. Restarts K8s backend deployment
#   3. Restarts docker-compose API container
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$PROJECT_DIR/.env"

echo "==> Reading GROQ_API_KEY from .env..."
NEW_KEY=$(grep '^GROQ_API_KEY=' "$ENV_FILE" | cut -d= -f2 | tr -d '\r')

if [ -z "$NEW_KEY" ] || [ "$NEW_KEY" = "gsk_your_key_here" ]; then
    echo "❌  ERROR: GROQ_API_KEY is empty or still the placeholder in .env"
    echo "    Please update .env with your real key from https://console.groq.com/keys"
    exit 1
fi

echo "    Key: ${NEW_KEY:0:15}... ✓"

echo ""
echo "==> Updating K8s secret 'rag-secrets' in namespace 'rag-system'..."
kubectl create secret generic rag-secrets \
    -n rag-system \
    --from-literal=GROQ_API_KEY="$NEW_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
echo "    ✔ K8s secret updated."

echo ""
echo "==> Restarting K8s backend deployment..."
kubectl rollout restart deployment/rag-backend -n rag-system
kubectl rollout status deployment/rag-backend -n rag-system --timeout=120s
echo "    ✔ K8s backend restarted."

echo ""
echo "==> Restarting docker-compose API container..."
cd "$PROJECT_DIR"
docker-compose restart api
echo "    ✔ docker-compose API restarted."

echo ""
echo "==> Verifying health (wait 10s for startup)..."
sleep 10
echo "--- docker-compose backend ---"
curl -s http://localhost:8000/api/v1/health | python3 -m json.tool

echo ""
echo "--- K8s backend (via nginx) ---"
MINIKUBE_IP=$(minikube ip)
curl -s "http://${MINIKUBE_IP}:30080/api/v1/health" | python3 -m json.tool

echo ""
echo "✅  Done! Refresh the UI at http://${MINIKUBE_IP}:30080"
