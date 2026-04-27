#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Schema v1 — base undeploy dispatcher
# ---------------------------------------------------------------------------
# Called directly by the v1-undeploy workflow. Responsibilities:
#   1. Export all secrets from the V1_SECRETS JSON env var
#   2. Validate that the target instance and its undeploy.sh exist
#   3. Set SCHEMA_VERSION so instance scripts can inspect it
#   4. Delegate execution to instances/<INSTANCE>/scripts/undeploy.sh
#
# Required environment variables (injected by the workflow):
#   INSTANCE        – Target instance name (matches folder under instances/)
#   RELEASE_VERSION – Semantic version to undeploy (e.g. 1.2.3)
#   V1_SECRETS      – JSON object with all secret values, e.g.:
#                     {
#                       "KUBECONFIG_DATA": "base64...",
#                       "SERVER_HOST":     "hostname",
#                       "SERVER_USER":     "user",
#                       "SERVER_SSH_KEY":  "-----BEGIN...",
#                       "CLOUD_ACCESS_KEY": "key",
#                       "CLOUD_SECRET_KEY": "secret"
#                     }
#
# Instance scripts may reference any key exported from V1_SECRETS.
# ---------------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# shellcheck source=../../../scripts/utils.sh
source "$REPO_ROOT/scripts/utils.sh"

# ---------------------------------------------------------------------------
# Validate required workflow inputs
# ---------------------------------------------------------------------------
: "${INSTANCE:?INSTANCE environment variable is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION environment variable is required}"
: "${V1_SECRETS:?V1_SECRETS environment variable is required}"

# ---------------------------------------------------------------------------
# Export all secrets from the V1_SECRETS JSON blob
# ---------------------------------------------------------------------------
load_secrets "$V1_SECRETS"

# ---------------------------------------------------------------------------
# Validate that the instance and its undeploy script exist
# ---------------------------------------------------------------------------
validate_instance "$INSTANCE" "undeploy.sh"

# ---------------------------------------------------------------------------
# Expose schema version to instance scripts
# ---------------------------------------------------------------------------
export SCHEMA_VERSION="v1"

# ---------------------------------------------------------------------------
# Delegate to the instance-specific undeploy script
# ---------------------------------------------------------------------------
INSTANCE_SCRIPT="$REPO_ROOT/instances/$INSTANCE/scripts/undeploy.sh"
chmod +x "$INSTANCE_SCRIPT"

log_info "Delegating to $INSTANCE_SCRIPT"
exec bash "$INSTANCE_SCRIPT"
