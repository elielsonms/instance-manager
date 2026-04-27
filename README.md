# instance-manager

A personal cloud management project that stores **Instances** as folders,
defines reusable **Instance Template Schemas**, and provides **GitHub Actions
pipelines** that external projects can trigger to deploy or undeploy a release
into any registered instance.

---

## Table of Contents

- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Schemas](#schemas)
- [Instances](#instances)
- [GitHub Actions Workflows](#github-actions-workflows)
- [Secrets Configuration](#secrets-configuration)
- [How External Projects Trigger Workflows](#how-external-projects-trigger-workflows)
- [Creating a New Instance](#creating-a-new-instance)

---

## Architecture

```
External Project
      │
      │  repository_dispatch  (or workflow_dispatch)
      ▼
┌──────────────────────────────────────────────────────────────┐
│                instance-manager (this repo)                  │
│                                                              │
│  .github/workflows/v1-release.yml   ← schema v1 trigger     │
│  .github/workflows/v1-undeploy.yml  ← schema v1 trigger     │
│           │                                                  │
│           │  calls base dispatcher                           │
│           ▼                                                  │
│  schemas/v1/scripts/deploy.sh  (or undeploy.sh)              │
│    • parses V1_SECRETS JSON → exports env vars               │
│    • validates instance folder                               │
│    • delegates to instance script                            │
│           │                                                  │
│           ▼                                                  │
│  instances/<name>/scripts/deploy.sh  (or undeploy)           │
│           │                                                  │
│           │  uses exported credentials                       │
│           ▼                                                  │
│       Remote Target (K8s cluster / server / cloud)           │
└──────────────────────────────────────────────────────────────┘
```

**Key principles:**

1. **No secrets in code** — all sensitive values are stored in GitHub Secrets
   and injected as environment variables at runtime.
2. **Schema-driven contracts** — each schema version defines the scripts an
   instance must implement and which environment variables they receive.
3. **Instance encapsulation** — all instance-specific logic lives inside
   `instances/<name>/`; the workflows are versioned and schema-specific.
4. **Legacy support** — an instance may keep older schema implementations
   alongside the current one for backward compatibility.

---

## Repository Structure

```
instance-manager/
├── .github/
│   └── workflows/
│       ├── v1-release.yml       # Schema v1 release workflow (workflow_dispatch / repository_dispatch)
│       └── v1-undeploy.yml      # Schema v1 undeploy workflow (workflow_dispatch / repository_dispatch)
│
├── schemas/
│   └── v1/
│       ├── schema.yml           # Schema v1 definition (contract)
│       └── scripts/
│           ├── deploy.sh        # Base v1 deploy dispatcher (called by workflow)
│           └── undeploy.sh      # Base v1 undeploy dispatcher (called by workflow)
│
├── instances/
│   └── my-k8s-instance/         # Example Kubernetes instance
│       ├── instance.yml         # Instance config (schema_version, type, …)
│       ├── scripts/
│       │   ├── deploy.sh        # v1 deploy implementation for this instance
│       │   └── undeploy.sh      # v1 undeploy implementation for this instance
│       └── manifests/           # Kubernetes-specific manifests (envsubst templates)
│           ├── namespace.yml
│           ├── deployment.yml
│           └── service.yml
│
└── scripts/
    └── utils.sh                 # Shared utility functions (logging, validation)
```

---

## Schemas

Schemas live under `schemas/<version>/` and define the **contract** between
the workflows and the instances.

| Field | Description |
|---|---|
| `required_scripts` | Scripts every instance must implement (`deploy.sh`, `undeploy.sh`) |
| `required_env_vars` | Environment variables each script must expect |
| `available_secrets` | Secrets passed inside `V1_SECRETS` JSON (never committed to code) |

### Schema v1

Located at `schemas/v1/schema.yml`.  Requires two scripts per instance:

| Script | Trigger | Key env vars |
|---|---|---|
| `scripts/deploy.sh` | Release into Instance workflow | `INSTANCE`, `RELEASE_VERSION`, `APP_IMAGE` |
| `scripts/undeploy.sh` | Undeploy Release from Instance workflow | `INSTANCE`, `RELEASE_VERSION` |

Instance scripts receive any secret exported from `V1_SECRETS` as an
environment variable. The base dispatcher scripts in `schemas/v1/scripts/`
handle the JSON parsing — instance scripts just use the variables directly.

---

## Instances

Each instance is a self-contained folder under `instances/`.

### `instance.yml`

```yaml
name: my-instance
schema_version: v1          # which schema this instance implements
type: kubernetes            # kubernetes | server | cloud
description: "…"
```

### Instance folder layout

```
instances/<name>/
├── instance.yml
├── scripts/
│   ├── deploy.sh           # implements the deploy contract for schema_version
│   └── undeploy.sh         # implements the undeploy contract for schema_version
└── <type-specific dirs>/   # e.g. manifests/ for Kubernetes
```

> **Legacy implementations** — if an instance needs to support an older schema
> version, place the legacy scripts in a sub-folder such as
> `instances/<name>/legacy/v0/scripts/`.

---

## GitHub Actions Workflows

Workflows follow the same versioning as schemas:

```
.github/workflows/
├── v1-release.yml   # Schema v1 release (workflow_dispatch / repository_dispatch)
└── v1-undeploy.yml  # Schema v1 undeploy (workflow_dispatch / repository_dispatch)
```

Each workflow file is named `<schema>-<action>.yml`, so its schema version is
immediately visible. When schema v2 arrives, add `v2-*.yml` files without
touching existing ones.

> **Note:** GitHub Actions only fires event-based triggers (`workflow_dispatch`,
> `repository_dispatch`, etc.) from files directly in `.github/workflows/`.
> Subdirectories are only supported for `workflow_call` (reusable workflows).
> The `v1-` prefix approach keeps all trigger files at the root while making
> the schema ownership explicit in the file name.

### `v1-release.yml` — Release into Instance (v1)

Deploys a versioned release to a target instance.

**Triggers:**
- `workflow_dispatch` — manual trigger from the GitHub UI
- `repository_dispatch` with `event_type: release-into-instance`

**Inputs / payload:**

| Name | Required | Description |
|---|---|---|
| `instance` | ✅ | Instance folder name under `instances/` |
| `release_version` | ✅ | Semantic version (e.g. `1.2.3`) |
| `image` | ⬜ | Container image with tag (e.g. `myapp:1.2.3`) |

**Execution path:**
1. Resolve inputs from the event type
2. Checkout repository
3. Call `schemas/v1/scripts/deploy.sh` (base dispatcher)
   - Parses `V1_SECRETS` JSON → exports all keys as env vars
   - Validates instance folder and `deploy.sh`
   - Delegates to `instances/<name>/scripts/deploy.sh`

---

### `v1-undeploy.yml` — Undeploy Release from Instance (v1)

Removes a versioned release from a target instance.

**Triggers:**
- `workflow_dispatch` — manual trigger from the GitHub UI
- `repository_dispatch` with `event_type: undeploy-from-instance`

**Inputs / payload:**

| Name | Required | Description |
|---|---|---|
| `instance` | ✅ | Instance folder name under `instances/` |
| `release_version` | ✅ | Semantic version to remove (e.g. `1.2.3`) |

**Execution path:**
1. Resolve inputs from the event type
2. Checkout repository
3. Call `schemas/v1/scripts/undeploy.sh` (base dispatcher)
   - Parses `V1_SECRETS` JSON → exports all keys as env vars
   - Validates instance folder and `undeploy.sh`
   - Delegates to `instances/<name>/scripts/undeploy.sh`

---

## Secrets Configuration

All credentials are stored as **GitHub Secrets** and are **never** committed
to the codebase. Go to **Settings → Secrets and variables → Actions**.

### `V1_SECRETS` (required for all v1 workflows)

Create **one** secret named `V1_SECRETS` whose value is a JSON object
containing every credential key your v1 instance scripts need:

```json
{
  "KUBECONFIG_DATA":  "base64-encoded-kubeconfig",
  "SERVER_HOST":      "hostname-or-ip",
  "SERVER_USER":      "ssh-username",
  "SERVER_SSH_KEY":   "-----BEGIN RSA PRIVATE KEY-----\n...\n-----END RSA PRIVATE KEY-----",
  "CLOUD_ACCESS_KEY": "cloud-access-key",
  "CLOUD_SECRET_KEY": "cloud-secret-key"
}
```

You only need to include the keys your instance scripts actually use. The
base dispatcher exports all keys as environment variables before calling the
instance script, so scripts reference them by name in the usual way
(`$KUBECONFIG_DATA`, `$SERVER_HOST`, etc.).

**Common values and how to obtain them:**

| Key | Description |
|---|---|
| `KUBECONFIG_DATA` | Base64-encoded kubeconfig: `cat ~/.kube/config \| base64` |
| `SERVER_HOST` | Remote server hostname or IP |
| `SERVER_USER` | SSH username |
| `SERVER_SSH_KEY` | SSH private key (PEM format — newlines encoded as `\n` in JSON) |
| `CLOUD_ACCESS_KEY` | Cloud provider access key |
| `CLOUD_SECRET_KEY` | Cloud provider secret key |

---

## How External Projects Trigger Workflows

External projects use the
[GitHub repository dispatch API](https://docs.github.com/en/rest/repos/repos#create-a-repository-dispatch-event).

### Release

```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer <GITHUB_TOKEN>" \
  https://api.github.com/repos/elielsonms/instance-manager/dispatches \
  -d '{
    "event_type": "release-into-instance",
    "client_payload": {
      "instance":        "my-k8s-instance",
      "release_version": "1.2.3",
      "image":           "myapp:1.2.3"
    }
  }'
```

### Undeploy

```bash
curl -X POST \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer <GITHUB_TOKEN>" \
  https://api.github.com/repos/elielsonms/instance-manager/dispatches \
  -d '{
    "event_type": "undeploy-from-instance",
    "client_payload": {
      "instance":        "my-k8s-instance",
      "release_version": "1.2.3"
    }
  }'
```

> The `GITHUB_TOKEN` used here must have `repo` scope on this repository.
> Store it as a secret in the calling project — never commit it.

---

## Creating a New Instance

1. **Create the instance folder:**

   ```bash
   mkdir -p instances/my-new-instance/scripts
   ```

2. **Add `instance.yml`:**

   ```yaml
   name: my-new-instance
   schema_version: v1
   type: server        # or: kubernetes, cloud
   description: "My new instance"
   ```

3. **Implement the instance scripts:**

   Create `instances/my-new-instance/scripts/deploy.sh` and `undeploy.sh`.
   The scripts receive all secrets exported from `V1_SECRETS` as environment
   variables. Use the existing `instances/my-k8s-instance/scripts/` as a
   reference — or start from scratch for a different deployment type.

   The minimum contract is:

   `deploy.sh` — must handle env vars `INSTANCE`, `RELEASE_VERSION`, `APP_IMAGE`
   plus any secrets it needs.

   `undeploy.sh` — must handle `INSTANCE`, `RELEASE_VERSION` plus any secrets.

4. **Add any instance-specific resources** (e.g. `manifests/` for Kubernetes)
   inside the instance folder.

5. **Configure the `V1_SECRETS` GitHub Secret** with a JSON object containing
   every credential key your scripts need (see [Secrets Configuration](#secrets-configuration)).

6. **Test** by triggering the workflow manually from the Actions tab or via
   `workflow_dispatch`.
