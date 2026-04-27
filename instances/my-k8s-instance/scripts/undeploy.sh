#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Undeploy script for my-k8s-instance  —  Schema v1
# ---------------------------------------------------------------------------
# Removes a workload from the Kubernetes cluster using the kubeconfig stored
# in the KUBECONFIG_DATA GitHub Secret.
#
# Required environment variables (set by the "Undeploy Release from Instance"
# workflow):
#   INSTANCE        – Instance name
#   RELEASE_VERSION – Version being undeployed (e.g. 1.2.3)
#
# Required GitHub Secrets (injected as env vars by the workflow):
#   KUBECONFIG_DATA – Base64-encoded kubeconfig for the target cluster
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source shared utilities
# shellcheck source=../../../scripts/utils.sh
source "$REPO_ROOT/scripts/utils.sh"

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${INSTANCE:?INSTANCE environment variable is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION environment variable is required}"
: "${KUBECONFIG_DATA:?KUBECONFIG_DATA secret is required — set it in GitHub Secrets}"

log_info "Undeploying release ${RELEASE_VERSION} from instance ${INSTANCE}"

# ---------------------------------------------------------------------------
# Set up kubeconfig from the secret (base64-encoded)
# ---------------------------------------------------------------------------
KUBECONFIG_FILE="$(mktemp)"
echo "$KUBECONFIG_DATA" | base64 --decode > "$KUBECONFIG_FILE"
export KUBECONFIG="$KUBECONFIG_FILE"

# Ensure the temporary kubeconfig is removed even if the script fails
trap 'rm -f "$KUBECONFIG_FILE"' EXIT

# ---------------------------------------------------------------------------
# Remove the deployment (ignore if already absent)
# ---------------------------------------------------------------------------
log_info "Deleting deployment ${INSTANCE} in namespace ${INSTANCE}…"
kubectl delete deployment "${INSTANCE}" \
  --namespace "${INSTANCE}" \
  --ignore-not-found=true

log_info "Release ${RELEASE_VERSION} undeployed from instance ${INSTANCE} successfully"
