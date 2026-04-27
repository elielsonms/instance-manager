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
# load_secrets <json-string>
#   Parses a JSON object and exports every key/value pair as an environment
#   variable. Requires jq (available on all GitHub-hosted runners).
#
#   Values may contain newlines (e.g. PEM-encoded SSH keys) — jq -r handles
#   the JSON escape sequences and command substitution preserves them.
# ---------------------------------------------------------------------------
load_secrets() {
  local json="${1:?JSON secrets string is required}"

  if ! command -v jq &>/dev/null; then
    log_error "jq is required to parse V1_SECRETS but was not found in PATH"
    exit 1
  fi

  local key
  while read -r key; do
    # Read each value individually so newlines inside values are preserved.
    local value
    value=$(printf '%s' "$json" | jq -r --arg k "$key" '.[$k]')
    export "$key=$value"
  done < <(printf '%s' "$json" | jq -r 'keys[]')

  log_info "Secrets loaded: $(printf '%s' "$json" | jq -r '[keys[]] | join(", ")')"
}

# ---------------------------------------------------------------------------
# validate_instance <instance-name> <script-name>
#   Checks that the instance directory, instance.yml, and the named script
#   exist under instances/. Exits with status 1 on failure.
# ---------------------------------------------------------------------------
validate_instance() {
  local instance="${1:?Instance name is required}"
  local script="${2:?Script name is required (e.g. deploy.sh)}"
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

  if [ ! -f "$repo_root/instances/$instance/scripts/$script" ]; then
    log_error "scripts/$script not found for instance '$instance'"
    exit 1
  fi

  log_info "Instance '$instance' validated (script: $script)"
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
