#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Base deploy script template — Schema v1
# ---------------------------------------------------------------------------
# Copy this file to instances/<your-instance>/scripts/deploy.sh and implement
# the deployment logic for your specific instance.
#
# This script is called by the "Release into Instance" workflow with the
# following environment variables already set:
#
#   INSTANCE        – Instance name (matches the folder under instances/)
#   RELEASE_VERSION – Version being deployed (e.g. 1.2.3)
#   APP_IMAGE       – Container image with tag (e.g. myapp:1.2.3)
#   SCHEMA_VERSION  – Schema version in use (e.g. v1)
#
# The workflow injects the secrets below from GitHub Secrets.  Never
# hard-code credentials in the codebase:
#
#   KUBECONFIG_DATA  – Base64-encoded kubeconfig for Kubernetes clusters
#   SERVER_HOST      – External server hostname
#   SERVER_USER      – External server SSH username
#   SERVER_SSH_KEY   – External server SSH private key
#   CLOUD_ACCESS_KEY – Cloud provider access key
#   CLOUD_SECRET_KEY – Cloud provider secret key
# ---------------------------------------------------------------------------

set -euo pipefail

: "${INSTANCE:?INSTANCE environment variable is required}"
: "${RELEASE_VERSION:?RELEASE_VERSION environment variable is required}"

echo "[INFO] Deploying release ${RELEASE_VERSION} to instance ${INSTANCE}"

# TODO: Implement instance-specific deployment logic here.

echo "[INFO] Deploy completed"
