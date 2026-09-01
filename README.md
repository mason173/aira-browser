# Aira

Aira is an open-source browser ecosystem centered on a HarmonyOS NEXT browser, a desktop browser extension, and a
single-owner self-hosted server. The three public components live in this monorepo so protocol and cross-device changes
can be reviewed and released together.

## Components

| Component | Path | Purpose |
| --- | --- | --- |
| Aira Browser | [`AiraBrowser/`](AiraBrowser/README.md) | HarmonyOS NEXT browser built with ArkTS, ArkUI, ArkWeb, and the Stage model |
| Aira-sync | [`extensions/aira-sync/`](extensions/aira-sync/README.md) | Chromium/Firefox extension for Bookmark, History, Page Push, and Cross-device Tabs |
| Personal Server | [`services/personal-server/`](services/personal-server/README.md) | Single-owner paired-device backend for self-hosted sync and cross-device services |

HarmonyOS Aira and Aira-sync can pair with the same Personal Server without Aira Account or Pro. Personal Server has no
registration, password accounts, organizations, roles, membership, billing, referral system, or Huawei login.

## Quick Start

Build the public-safe HarmonyOS Community distribution:

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

Build and test Aira-sync:

```bash
cd extensions/aira-sync
npm ci
npm run typecheck
npm test
npm run build:community
```

Check or run Personal Server:

```bash
cd services/personal-server
npm ci
npm run check
docker compose up -d --build
```

See [docs/open-source-distribution.md](docs/open-source-distribution.md) for the Community/Official capability boundary
and [docs/self-hosting.md](docs/self-hosting.md) for the deployment model.

## Public And Private Boundary

The HarmonyOS client and Aira-sync each build Community and Official distributions from one source tree. Community
contains no Aira production identity or hosted-service routes. Official builds inject private Huawei and Aira Cloud
configuration at build time. Local capabilities, WebDAV, and Personal Server do not require membership; Aira Pro pays
only for Aira-operated hosted services.

The Aira production backend, Admin console, billing, analytics, private deployment configuration, signing material, and
Huawei production credentials are intentionally outside this repository.

## Versioning

Each component keeps an independent version and release artifact. Use component-qualified tags such as
`browser-v2.5.3`, `aira-sync-v0.2.13`, and `personal-server-v0.2.0`.

## Project Policy

Aira-authored source is offered under [GPL-3.0-only](LICENSE). Component directories retain their own license and
third-party notice files where useful for standalone source distributions. Review
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before redistribution: the current Icons8 asset set is commercially
licensed and remains a publication gate until its public source/binary distribution rights are confirmed or replaced.

Contributions and security reports follow [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[TRADEMARKS.md](TRADEMARKS.md).
