#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# start.sh — Safe startup script for the RAG MLOps project
#
# Run this INSTEAD of `docker-compose up` every time.
# It ensures Minikube is running and Jenkins has a valid kubeconfig
# BEFORE the containers start — fixing the "connection refused" error.
# ─────────────────────────────────────────────────────────────────────────────

set -e

# ── Step 1: Start Minikube ────────────────────────────────────────────────────
echo "==> Checking Minikube status..."

if minikube status --format='{{.Host}}' 2>/dev/null | grep -q "Running"; then
    echo "    ✔ Minikube is already running."
else
    echo "    Starting Minikube (docker driver)..."
    minikube start --driver=docker --memory=3072 --cpus=2
    echo "    ✔ Minikube started."
fi

# ── Step 2: Patch kubeconfig to use Docker-reachable IP ──────────────────────
# Inside the Jenkins container, 192.168.49.2 is NOT reachable.
# We replace it with the Docker host gateway IP so Jenkins can reach Minikube.
echo ""
echo "==> Patching kubeconfig for Docker networking..."

MINIKUBE_IP=$(minikube ip)
# Docker host gateway — reachable from inside any container on the minikube network
HOST_IP=$(docker network inspect minikube \
    --format '{{range .IPAM.Config}}{{.Gateway}}{{end}}' 2>/dev/null \
    | head -1)

if [ -z "$HOST_IP" ]; then
    # Fallback: use host.docker.internal (works on Docker Desktop)
    HOST_IP="host.docker.internal"
fi

echo "    Minikube IP   : $MINIKUBE_IP"
echo "    Docker Host IP: $HOST_IP"

# Copy kubeconfig and replace Minikube's internal IP with Docker-reachable IP
KUBE_CONFIG_SOURCE="$HOME/.kube/config"
KUBE_CONFIG_PATCHED="/tmp/kube-config-patched"

sed "s|https://${MINIKUBE_IP}:|https://${HOST_IP}:|g" \
    "$KUBE_CONFIG_SOURCE" > "$KUBE_CONFIG_PATCHED"

echo "    ✔ Kubeconfig patched."

# ── Step 3: Put patched kubeconfig into Jenkins volume ───────────────────────
echo ""
echo "==> Injecting kubeconfig into Jenkins volume..."

# Ensure the volume exists by starting jenkins briefly or using docker volume
JENKINS_VOLUME="$(basename $(pwd))_jenkins_home"

# Write kubeconfig directly to the Jenkins home volume
docker run --rm \
    -v "${JENKINS_VOLUME}:/jenkins-home" \
    -v "$KUBE_CONFIG_PATCHED:/tmp/config:ro" \
    alpine sh -c "mkdir -p /jenkins-home/.kube && cp /tmp/config /jenkins-home/.kube/config && chmod 600 /jenkins-home/.kube/config"

echo "    ✔ Kubeconfig injected into Jenkins volume."

# ── Step 4: Verify Minikube Docker network exists ────────────────────────────
echo ""
echo "==> Verifying Docker network 'minikube'..."

if docker network inspect "minikube" > /dev/null 2>&1; then
    echo "    ✔ Network 'minikube' exists."
else
    echo "    ✘ Network 'minikube' still missing even after minikube start."
    echo "      Something went wrong with minikube. Try: minikube delete && minikube start --driver=docker"
    exit 1
fi

# ── Step 5: Start all services ───────────────────────────────────────────────
echo ""
echo "==> Starting all services with docker-compose..."
echo ""
docker-compose up "$@"