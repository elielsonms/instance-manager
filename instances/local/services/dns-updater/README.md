# dns-updater

A lightweight service that runs on the `local` home server and keeps the
`local.instance.elielsonms.com` DNS A-record in DigitalOcean pointed at the
server's current public IP address. Because the home internet connection uses
a dynamic IP, this service polls for changes and updates the record
automatically.

---

## How it works

1. On startup (and on a configurable interval), it fetches the server's
   current public IP from a reliable external endpoint (e.g. `https://api.ipify.org`).
2. It compares the result with the IP stored in the target DigitalOcean DNS record.
3. If the IP has changed (or the record is new), it calls the DigitalOcean
   Domains API to update the A-record.

---

## Required `V1_SECRETS` keys

Add these keys to the `V1_SECRETS` JSON GitHub Secret before deploying:

| Key | Description |
|---|---|
| `SERVER_HOST` | Home server hostname or current IP (for SSH access from the runner) |
| `SERVER_USER` | SSH username on the home server |
| `SERVER_SSH_KEY` | SSH private key (PEM format) |
| `DO_TOKEN` | DigitalOcean personal access token with **Domain** read+write scope |
| `DO_DOMAIN` | Root domain managed in DigitalOcean, e.g. `elielsonms.com` |
| `DO_RECORD_NAME` | Subdomain part of the target record, e.g. `local.instance` |

Example `V1_SECRETS` value:

```json
{
  "SERVER_HOST":     "203.0.113.42",
  "SERVER_USER":     "deploy",
  "SERVER_SSH_KEY":  "-----BEGIN OPENSSH PRIVATE KEY-----\n...\n-----END OPENSSH PRIVATE KEY-----",
  "DO_TOKEN":        "dop_v1_xxxxxxxxxxxxxxxxxxxx",
  "DO_DOMAIN":       "elielsonms.com",
  "DO_RECORD_NAME":  "local.instance"
}
```

`DO_TOKEN`, `DO_DOMAIN`, and `DO_RECORD_NAME` are injected into the container
automatically by the deploy script (all V1_SECRETS keys except the SSH
connection credentials are passed through as container environment variables).

---

## Deploying

Trigger the **Release into Instance** workflow with:

| Input | Value |
|---|---|
| `instance` | `local` |
| `release_version` | Image tag, e.g. `1.0.0` |
| `image` | `ghcr.io/elielsonms/dns-updater:1.0.0` |

The deploy script will:
1. Pull the image on the home server
2. Stop and remove any previously running `dns-updater` container
3. Start a new container named `dns-updater` with `--restart unless-stopped`
   and all relevant secrets injected via env file

---

## Undeploying

Trigger the **Undeploy Release from Instance** workflow with:

| Input | Value |
|---|---|
| `instance` | `local` |
| `release_version` | e.g. `1.0.0` |
| `image` | `ghcr.io/elielsonms/dns-updater:1.0.0` |

The undeploy script stops and removes the `dns-updater` container.

---

## Notes

- The service name is always derived from the image name (`dns-updater` in
  this case), so you can redeploy a new version by simply triggering the
  release workflow with the new image tag — the old container is replaced
  automatically.
- The container runs with `--restart unless-stopped`, so it survives server
  reboots.
- Docker must be installed on the home server before the first deploy.
