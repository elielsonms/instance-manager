#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Deploy script for the local instance  —  Schema v1
# ---------------------------------------------------------------------------
# Deploys a Docker-based service to the home server over SSH.
#
# Required environment variables (set by the v1-release workflow):
#   INSTANCE        – Instance name (always "local" for this instance)
#   RELEASE_VERSION – Version being deployed (e.g. 1.2.3)
#   APP_IMAGE       – Full container image reference (e.g. ghcr.io/org/svc:1.2.3)
#
# Required keys inside V1_SECRETS (exported before this script is called):
#   SERVER_HOST     – Home server hostname or IP address
#   SERVER_USER     – SSH username on the home server
#   SERVER_SSH_KEY  – SSH private key (PEM format)
#
# Optional keys inside V1_SECRETS (passed as env vars to the container):
#   Any additional key (e.g. DO_TOKEN, DO_DOMAIN) that is NOT a deployment
#   credential (SERVER_HOST / SERVER_USER / SERVER_SSH_KEY) is written to a
#   temporary env file and injected into the container via --env-file.
#   Values must be single-line strings.
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
# ghcr.io/org/dns-updater:1.2.3  →  dns-updater
# nginx:latest                   →  nginx
# ---------------------------------------------------------------------------
SERVICE_NAME="${APP_IMAGE##*/}"
SERVICE_NAME="${SERVICE_NAME%%:*}"

log_info "Deploying service '${SERVICE_NAME}' (${APP_IMAGE}) version ${RELEASE_VERSION} to ${INSTANCE} instance"

# ---------------------------------------------------------------------------
# Set up the SSH key in a temp file
# ---------------------------------------------------------------------------
SSH_KEY_FILE="$(mktemp)"
ENV_FILE="$(mktemp)"
trap 'rm -f "$SSH_KEY_FILE" "$ENV_FILE"' EXIT

printf '%s' "$SERVER_SSH_KEY" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

SSH_OPTS="-i $SSH_KEY_FILE -o StrictHostKeyChecking=no -o BatchMode=yes"

# ---------------------------------------------------------------------------
# Build a service env file from all V1_SECRETS keys that are NOT deployment
# credentials. These become environment variables inside the container.
# ---------------------------------------------------------------------------
printf '%s' "$V1_SECRETS" | jq -r '
  to_entries
  | map(select(.key | IN("SERVER_HOST", "SERVER_USER", "SERVER_SSH_KEY") | not))
  | .[]
  | "\(.key)=\(.value)"
' > "$ENV_FILE"

# ---------------------------------------------------------------------------
# Copy env file to a temporary location on the remote server
# ---------------------------------------------------------------------------
REMOTE_ENV_FILE="/tmp/.env-${SERVICE_NAME}-$$"
scp $SSH_OPTS "$ENV_FILE" "${SERVER_USER}@${SERVER_HOST}:${REMOTE_ENV_FILE}"

# ---------------------------------------------------------------------------
# Pull image, replace the running container, clean up env file on server
# ---------------------------------------------------------------------------
# shellcheck disable=SC2087
ssh $SSH_OPTS "${SERVER_USER}@${SERVER_HOST}" bash <<REMOTE
set -euo pipefail

echo "[INFO]  Pulling image ${APP_IMAGE}…"
docker pull "${APP_IMAGE}"

echo "[INFO]  Stopping existing container '${SERVICE_NAME}' (if any)…"
docker stop "${SERVICE_NAME}" 2>/dev/null || true
docker rm   "${SERVICE_NAME}" 2>/dev/null || true

echo "[INFO]  Starting container '${SERVICE_NAME}'…"
docker run -d \
  --name "${SERVICE_NAME}" \
  --restart unless-stopped \
  --env-file "${REMOTE_ENV_FILE}" \
  "${APP_IMAGE}"

rm -f "${REMOTE_ENV_FILE}"

echo "[INFO]  Service '${SERVICE_NAME}' is up"
REMOTE

log_info "Service '${SERVICE_NAME}' version ${RELEASE_VERSION} deployed to ${INSTANCE} instance successfully"
