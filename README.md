# Aira

Aira is a privacy-focused browser ecosystem for HarmonyOS NEXT and desktop browsers.
It lets you keep browsing data local, or connect your own devices to a Personal Server that you control.

The browser, desktop extension, and self-hosted server are maintained in one repository so their protocols and
cross-device features can evolve together.

> Aira is currently in active development. The repository is usable for development and self-hosting, but release
> packages and production services are not provided here yet.

## What You Get

- A native HarmonyOS NEXT browser built with ArkTS, ArkUI, ArkWeb, and the Stage model.
- A Chromium/Firefox extension for bookmarks, history, Page Push, and Cross-device Tabs.
- A single-owner Personal Server that you can run on your own computer, NAS, VPS, or home server.
- Local-first data handling with WebDAV and Personal Server providers for people who do not want to use Aira's hosted
  services.
- One source tree for Community and Official builds. There are no long-lived edition forks.

## Repository Layout

| Component | Location | Description |
| --- | --- | --- |
| Aira Browser | [`AiraBrowser/`](AiraBrowser/README.md) | HarmonyOS NEXT browser client |
| Aira-sync | [`extensions/aira-sync/`](extensions/aira-sync/README.md) | Desktop browser extension |
| Personal Server | [`services/personal-server/`](services/personal-server/README.md) | Single-owner self-hosted backend |
| Shared documentation | [`docs/`](docs/) | Architecture, protocol, deployment, and release notes |

## Personal Server

Personal Server is the recommended way to connect your own phone and desktop browsers without an Aira account or
membership. It is intentionally single-owner and paired-device only:

- no registration or password account system;
- no organizations, roles, invitations, billing, or referral system;
- no Huawei Account, IAP, or Aira production credentials;
- revocable per-device credentials and a one-time pairing code.

### Quick Start With Docker

Requirements: Docker Engine with Compose, a persistent data volume, and HTTPS when the server is reachable outside a
trusted local network.

```bash
cd services/personal-server
cp .env.example .env
docker compose up -d --build
docker compose exec aira-server cat /data/setup-code
```

Open Aira or Aira-sync, choose **Personal Server**, enter the server URL, and use the one-time setup code. The setup
code is removed after the first device pairs. The default Compose file binds the service to `127.0.0.1:8787`; put a
TLS reverse proxy such as Caddy or Nginx in front of it before exposing it publicly.

Deployment, reverse proxy, backup, restore, upgrades, pairing, and revocation are documented in
[`docs/self-hosting.md`](docs/self-hosting.md) and [`services/personal-server/README.md`](services/personal-server/README.md).

## Build And Test

### Aira-sync

```bash
cd extensions/aira-sync
npm ci
npm run typecheck
npm test
npm run build:community
```

The Community extension is written to `build/community/` and can be loaded as an unpacked extension in Chrome, Edge,
or another Chromium-compatible browser. It uses the stable public extension ID:
`efehgppkhnkjamcpbipclfmmofdildji`.

### Personal Server

```bash
cd services/personal-server
npm ci
npm run check
```

The check command exercises discovery, pairing, sync protocols, Page Push, Cross-device Tabs, conflict handling,
credential rotation, and revocation in an isolated temporary server.

### HarmonyOS Browser

Open `AiraBrowser/` in DevEco Studio, or use the repository build script:

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

The unsigned command is suitable for CI and source verification. Installing on a device requires a local signing
profile for `org.aira.browser`. See [`AiraBrowser/README.md`](AiraBrowser/README.md) for DevEco, signing, API level,
release, and device-install instructions.

## Community And Official

Both distributions are built from the same source commit. Community is the public-safe default and does not contain
Aira's production identity, Huawei project configuration, or hosted-service routes.

| Capability | Community | Official |
| --- | --- | --- |
| Local browsing, tabs, offline pages, themes, userscripts, and ad blocking | Available | Available |
| User-provided WebDAV | Available | Available |
| Personal Server sync and Cross-device Tabs | Available | Available |
| Huawei Account and Huawei Cloud Space | Not included | Private production configuration |
| Aira Cloud and hosted-service pairing | Not included | Private production service |
| Huawei IAP and Aira Pro entitlement | Not included | Private production service |

Official builds require private Huawei/AGConnect inputs, production routes, and a matching signing profile. Those
materials are deliberately outside this repository. Read [`docs/open-source-distribution.md`](docs/open-source-distribution.md)
before preparing a release.

## Data And Privacy

Local data stays on the device unless you explicitly choose a provider. Personal Server and WebDAV credentials remain
in client storage and are sent only to the endpoint you select. Personal Server stores synchronized data for its single
owner; it is not end-to-end encrypted, so the server administrator can read that data.

The browser and extension do not require Aira registration. Huawei Account authentication, Huawei Cloud Space, Aira
Cloud, IAP, and production membership services are Official-only capabilities.

For vulnerability reports, use GitHub Security Advisories and follow [`SECURITY.md`](SECURITY.md). Never include
credentials, device tokens, browsing data, databases, backups, or signing files in an issue or pull request.

## Contributing

Cross-component protocol changes should be submitted together so the browser, extension, and server remain compatible.
Run the checks for every component you touch, and read [`CONTRIBUTING.md`](CONTRIBUTING.md) before opening a pull
request.

## License

Aira-authored source code is available under [GPL-3.0-only](LICENSE). Third-party components retain their own licenses;
see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and the notices in each component directory.

The license does not grant rights to the Aira name, logos, or other trademarks. See [`TRADEMARKS.md`](TRADEMARKS.md).
