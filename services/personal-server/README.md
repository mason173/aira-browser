# Aira Personal Server

Aira Personal Server is the single-owner sync backend for Aira Browser. It is designed for one person and that person's paired devices. It has no account registration, passwords, users, organizations, roles, membership, billing, referral system, Huawei login, or Aira-operated control plane.

The server currently synchronizes:

- bookmarks through the complete-snapshot v4 protocol (`aira-cloud-bookmarks-v4`) with compare-and-swap writes;
- history through the bounded incremental/bootstrap v1 protocol;
- personalization through the complete-snapshot v2 protocol;
- Novel Bookshelf metadata and reading anchors through the complete-snapshot v2 protocol.

The same paired-device connection also provides:

- phone-to-desktop Page Push with per-device delivery, short leases, and acknowledgement;
- Cross-device Tabs using short-lived latest snapshots from paired phones and desktops.

Only paired-device bearer credentials can access data. Device tokens are generated randomly and stored by the server only as SHA-256 hashes.

## Requirements

- Docker Engine with Docker Compose, or Node.js 20 or newer;
- a persistent data volume;
- HTTPS from a reverse proxy when the server is reachable outside a trusted local network.

Run the following deployment and development commands from the component directory:

```bash
cd services/personal-server
```

## Docker Quick Start

```bash
cp .env.example .env
docker compose up -d --build
docker compose exec aira-server cat /data/setup-code
```

The last command prints the one-time setup code. Enter the public server URL and this code in Aira under `Settings > Sync > Personal Server`. The setup-code file is deleted after the first device pairs.

The default Compose configuration binds port `8787` to `127.0.0.1`, so it is not directly exposed to the network. Put Caddy, Nginx, or another TLS reverse proxy in front of it.

Set the public URL in `.env`:

```dotenv
AIRA_PUBLIC_URL=https://sync.example.com
```

A minimal Caddy site is:

```caddyfile
sync.example.com {
  reverse_proxy 127.0.0.1:8787
}
```

Keep the proxy request-body limit at 12 MiB or higher and preserve the `Authorization` header. Do not terminate public TLS with a self-signed certificate unless every client device explicitly trusts that certificate.

## Native Node.js

```bash
npm ci --omit=dev
AIRA_DATA_DIR=/srv/aira-server/data \
AIRA_HOST=127.0.0.1 \
AIRA_PORT=8787 \
AIRA_PUBLIC_URL=https://sync.example.com \
npm start
```

The service writes its SQLite database and initial setup code under `AIRA_DATA_DIR`. That directory should be readable only by the service account.

## Pairing More Devices

An already paired device can mint a ten-minute, one-use pairing code through `POST /v1/pairing/codes`. The authenticated device-management endpoints can also list devices, rotate the current credential, and revoke a device. See [docs/protocol.md](docs/protocol.md).

Never place a device token in a shell history, issue, log, or configuration committed to Git. Prefer the Aira client UI when it exposes the relevant device-management operation.

## Operations

Backup, restore, upgrades, health checks, and rollback steps are documented in [docs/operations.md](docs/operations.md). The essential checks are:

```bash
curl --fail --silent https://sync.example.com/health
npm run check
```

`npm run check` starts an isolated temporary server and verifies discovery, phone and desktop pairing, all four sync
domains, Page Push, Cross-device Tabs, compare-and-swap conflicts, credential rotation, device listing, and revocation.

## Scope And Compatibility

The discovery document at `/.well-known/aira` is the client compatibility contract. Protocol changes must remain explicit and versioned. Aira production membership, IAP, admin, analytics, diagnostics, and Huawei-account services are intentionally outside this public monorepo.

This release is a deliberate breaking generation for the unpublished Personal Server. It has no public-user
compatibility or legacy-data migration obligation. Bookmarks require the v4 protocol; pre-v4 bookmark clients are rejected
before any state is read or written. The server stores one complete snapshot and never merges legacy sources.

## Security

Read [SECURITY.md](SECURITY.md) before exposing the server. Report vulnerabilities through GitHub Security Advisories rather than a public issue.

## License And Marks

Source code is licensed under GPL-3.0-only. See [LICENSE](LICENSE). The license does not grant rights to Aira names, logos, or other marks; see [TRADEMARKS.md](TRADEMARKS.md).
