#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Deploy script for my-k8s-instance  —  Schema v1
# ---------------------------------------------------------------------------
# Deploys a container workload to a Kubernetes cluster using the kubeconfig
# stored in the KUBECONFIG_DATA GitHub Secret.
#
# Required environment variables (set by the "Release into Instance" workflow):
#   INSTANCE        – Instance name
#   RELEASE_VERSION – Version being deployed (e.g. 1.2.3)
#   APP_IMAGE       – Full container image reference (e.g. myapp:1.2.3)
#
# Required GitHub Secrets (injected as env vars by the workflow):
#   KUBECONFIG_DATA – Base64-encoded kubeconfig for the target cluster
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTANCE_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source shared utilities
# shellcheck source=../../../scripts/utils.sh
source "$REPO_ROOT/scripts/utils.sh"

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${INSTANCE:?INSTANCE environment variable is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION environment variable is required}"
: "${APP_IMAGE:?APP_IMAGE environment variable is required}"
: "${KUBECONFIG_DATA:?KUBECONFIG_DATA secret is required — set it in GitHub Secrets}"

log_info "Deploying release ${RELEASE_VERSION} (image: ${APP_IMAGE}) to instance ${INSTANCE}"

# ---------------------------------------------------------------------------
# Set up kubeconfig from the secret (base64-encoded)
# ---------------------------------------------------------------------------
KUBECONFIG_FILE="$(mktemp)"
echo "$KUBECONFIG_DATA" | base64 --decode > "$KUBECONFIG_FILE"
export KUBECONFIG="$KUBECONFIG_FILE"

# Ensure the temporary kubeconfig is removed even if the script fails
trap 'rm -f "$KUBECONFIG_FILE"' EXIT

# ---------------------------------------------------------------------------
# Export variables used by envsubst in the manifest templates
# ---------------------------------------------------------------------------
export INSTANCE
export RELEASE_VERSION
export APP_IMAGE

# ---------------------------------------------------------------------------
# Apply Kubernetes manifests (namespace → deployment → service)
# ---------------------------------------------------------------------------
log_info "Applying namespace manifest…"
envsubst < "$INSTANCE_DIR/manifests/namespace.yml" | kubectl apply -f -

log_info "Applying deployment manifest…"
envsubst < "$INSTANCE_DIR/manifests/deployment.yml" | kubectl apply -f -

log_info "Applying service manifest…"
envsubst < "$INSTANCE_DIR/manifests/service.yml" | kubectl apply -f -

# ---------------------------------------------------------------------------
# Wait for the rollout to complete
# ---------------------------------------------------------------------------
log_info "Waiting for rollout to complete…"
kubectl rollout status deployment/"${INSTANCE}" \
  --namespace "${INSTANCE}" \
  --timeout 5m

log_info "Release ${RELEASE_VERSION} deployed to instance ${INSTANCE} successfully"
