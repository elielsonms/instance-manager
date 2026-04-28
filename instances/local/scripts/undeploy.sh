#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Undeploy script for the local instance  —  Schema v1
# ---------------------------------------------------------------------------
# Stops and removes a Docker-based service from the home server over SSH.
#
# Required environment variables (set by the v1-undeploy workflow):
#   INSTANCE        – Instance name (always "local" for this instance)
#   RELEASE_VERSION – Version being undeployed (e.g. 1.2.3)
#   APP_IMAGE       – Image reference used to derive the service name
#                     (e.g. ghcr.io/org/dns-updater:1.2.3 → dns-updater)
#
# Required keys inside V1_SECRETS (exported before this script is called):
#   SERVER_HOST     – Home server hostname or IP address
#   SERVER_USER     – SSH username on the home server
#   SERVER_SSH_KEY  – SSH private key (PEM format)
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=../../../scripts/utils.sh
source "$REPO_ROOT/scripts/utils.sh"

# ---------------------------------------------------------------------------
# Validate required environment variables
# ---------------------------------------------------------------------------
: "${INSTANCE:?INSTANCE environment variable is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION environment variable is required}"
: "${APP_IMAGE:?APP_IMAGE environment variable is required}"
: "${SERVER_HOST:?SERVER_HOST secret is required — add it to V1_SECRETS}"
: "${SERVER_USER:?SERVER_USER secret is required — add it to V1_SECRETS}"
: "${SERVER_SSH_KEY:?SERVER_SSH_KEY secret is required — add it to V1_SECRETS}"

# ---------------------------------------------------------------------------
# Derive the service name from the image reference
# ---------------------------------------------------------------------------
SERVICE_NAME="${APP_IMAGE##*/}"
SERVICE_NAME="${SERVICE_NAME%%:*}"

log_info "Undeploying service '${SERVICE_NAME}' version ${RELEASE_VERSION} from ${INSTANCE} instance"

# ---------------------------------------------------------------------------
# Set up the SSH key in a temp file
# ---------------------------------------------------------------------------
SSH_KEY_FILE="$(mktemp)"
trap 'rm -f "$SSH_KEY_FILE"' EXIT

printf '%s' "$SERVER_SSH_KEY" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

SSH_OPTS="-i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o BatchMode=yes"

# ---------------------------------------------------------------------------
# Stop and remove the container on the remote server
# ---------------------------------------------------------------------------
# shellcheck disable=SC2087
ssh $SSH_OPTS "${SERVER_USER}@${SERVER_HOST}" bash <<REMOTE
set -euo pipefail

echo "[INFO]  Stopping container '${SERVICE_NAME}' (if running)…"
docker stop "${SERVICE_NAME}" 2>/dev/null || true

echo "[INFO]  Removing container '${SERVICE_NAME}' (if present)…"
docker rm   "${SERVICE_NAME}" 2>/dev/null || true

echo "[INFO]  Service '${SERVICE_NAME}' removed"
REMOTE

log_info "Service '${SERVICE_NAME}' version ${RELEASE_VERSION} undeployed from ${INSTANCE} instance successfully"
