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
┌─────────────────────────────────────────────────────┐
│             instance-manager (this repo)            │
│                                                     │
│  .github/workflows/release.yml                      │
│  .github/workflows/undeploy.yml                     │
│           │                                         │
│           │  reads schema_version from              │
│           │  instances/<name>/instance.yml          │
│           │                                         │
│           ▼                                         │
│  instances/<name>/scripts/deploy.sh  (or undeploy)  │
│           │                                         │
│           │  uses GitHub Secrets for credentials    │
│           ▼                                         │
│       Remote Target (K8s cluster / server / cloud)  │
└─────────────────────────────────────────────────────┘
```

**Key principles:**

1. **No secrets in code** — all sensitive values are stored in GitHub Secrets
   and injected as environment variables at runtime.
2. **Schema-driven contracts** — each schema version defines the scripts an
   instance must implement and which environment variables they receive.
3. **Instance encapsulation** — all instance-specific logic lives inside
   `instances/<name>/`; the workflows are generic and schema-agnostic.
4. **Legacy support** — an instance may keep older schema implementations
   alongside the current one for backward compatibility.

---

## Repository Structure

```
instance-manager/
├── .github/
│   └── workflows/
│       ├── release.yml          # "Release into Instance" pipeline
│       └── undeploy.yml         # "Undeploy Release from Instance" pipeline
│
├── schemas/
│   └── v1/
│       ├── schema.yml           # Schema v1 definition (contract)
│       └── scripts/
│           ├── deploy.sh        # Base deploy template for v1
│           └── undeploy.sh      # Base undeploy template for v1
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
| `available_secrets` | Secrets the workflow injects (never committed to code) |

### Schema v1

Located at `schemas/v1/schema.yml`.  Requires two scripts per instance:

| Script | Trigger | Key env vars |
|---|---|---|
| `scripts/deploy.sh` | Release into Instance workflow | `INSTANCE`, `RELEASE_VERSION`, `APP_IMAGE` |
| `scripts/undeploy.sh` | Undeploy Release from Instance workflow | `INSTANCE`, `RELEASE_VERSION` |

Copy `schemas/v1/scripts/deploy.sh` and `schemas/v1/scripts/undeploy.sh` into
your new instance's `scripts/` folder as starting templates.

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

### `release.yml` — Release into Instance

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

**Steps:**
1. Resolve inputs from the event type
2. Validate that the instance folder and `deploy.sh` exist
3. Read `schema_version` from `instance.yml`
4. Execute `instances/<name>/scripts/deploy.sh` with secrets injected as env vars

---

### `undeploy.yml` — Undeploy Release from Instance

Removes a versioned release from a target instance.

**Triggers:**
- `workflow_dispatch` — manual trigger from the GitHub UI
- `repository_dispatch` with `event_type: undeploy-from-instance`

**Inputs / payload:**

| Name | Required | Description |
|---|---|---|
| `instance` | ✅ | Instance folder name under `instances/` |
| `release_version` | ✅ | Semantic version to remove (e.g. `1.2.3`) |

---

## Secrets Configuration

All credentials are stored as **GitHub Secrets** (repository or environment
level) and are **never** committed to the codebase.

Go to **Settings → Secrets and variables → Actions** and add the secrets
your instances need:

| Secret name | Used by | Description |
|---|---|---|
| `KUBECONFIG_DATA` | Kubernetes instances | Base64-encoded kubeconfig (`cat ~/.kube/config | base64`) |
| `SERVER_HOST` | Server instances | Remote server hostname or IP |
| `SERVER_USER` | Server instances | SSH username |
| `SERVER_SSH_KEY` | Server instances | SSH private key |
| `CLOUD_ACCESS_KEY` | Cloud instances | Cloud provider access key |
| `CLOUD_SECRET_KEY` | Cloud instances | Cloud provider secret key |

The workflows pass **all** available secrets as environment variables to the
instance scripts; each script uses only the ones it needs.

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

3. **Copy the schema templates and implement the scripts:**

   ```bash
   cp schemas/v1/scripts/deploy.sh   instances/my-new-instance/scripts/deploy.sh
   cp schemas/v1/scripts/undeploy.sh instances/my-new-instance/scripts/undeploy.sh
   ```

   Edit both files to implement instance-specific logic (SSH to a server,
   apply Kubernetes manifests, call a cloud API, etc.).

4. **Add any instance-specific resources** (e.g. `manifests/` for Kubernetes)
   inside the instance folder.

5. **Configure GitHub Secrets** for any credentials the scripts need.

6. **Test** by triggering the workflow manually from the Actions tab or via
   `workflow_dispatch`.
