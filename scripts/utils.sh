#!/usr/bin/env bash
# Common utility functions shared across all instance scripts.
# Source this file – do not execute it directly.

set -euo pipefail

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log_info() {
  echo "[INFO]  $*"
}

log_error() {
  echo "[ERROR] $*" >&2
}

# ---------------------------------------------------------------------------
# validate_instance <instance-name>
#   Checks that the instance directory and required files exist under instances/.
#   Exits with status 1 on failure.
# ---------------------------------------------------------------------------
validate_instance() {
  local instance="${1:?Instance name is required}"
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

  if [ ! -d "$repo_root/instances/$instance" ]; then
    log_error "Instance '$instance' not found in instances/"
    exit 1
  fi

  if [ ! -f "$repo_root/instances/$instance/instance.yml" ]; then
    log_error "instance.yml not found for instance '$instance'"
    exit 1
  fi

  if [ ! -f "$repo_root/instances/$instance/scripts/deploy.sh" ]; then
    log_error "scripts/deploy.sh not found for instance '$instance'"
    exit 1
  fi

  if [ ! -f "$repo_root/instances/$instance/scripts/undeploy.sh" ]; then
    log_error "scripts/undeploy.sh not found for instance '$instance'"
    exit 1
  fi

  log_info "Instance '$instance' validated successfully"
}

# ---------------------------------------------------------------------------
# get_schema_version <instance-name>
#   Reads schema_version from instances/<name>/instance.yml and prints it.
# ---------------------------------------------------------------------------
get_schema_version() {
  local instance="${1:?Instance name is required}"
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  grep 'schema_version:' "$repo_root/instances/$instance/instance.yml" \
    | awk '{print $2}' | tr -d '"' | tr -d "'"
}
