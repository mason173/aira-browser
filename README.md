# Aira

Aira is a GPL-3.0 monorepo for building a privacy-focused browser stack on HarmonyOS NEXT and desktop browsers.
It contains the browser client, the desktop extension, and the single-owner backend used for self-hosted sync.

This README is for contributors, integrators, and developers who want to run or extend Aira. It describes the public
source boundary and the shortest path to a working local development environment.

## Repository Contract

- The browser and extension are built as **Community** or **Official** distributions from the same source commit.
- Community builds do not require Aira production credentials or hosted-service access.
- Personal Server is a single-owner, paired-device service. It has no registration, password accounts, organizations,
  roles, membership, billing, referrals, or Huawei authentication.
- Local data providers, WebDAV, and Personal Server are available without Aira membership.
- Production Aira services, Admin tooling, Huawei project configuration, signing material, and deployment secrets are
  outside this repository.

## Components

| Component | Location | Developer responsibility |
| --- | --- | --- |
| HarmonyOS client | [`AiraBrowser/`](AiraBrowser/README.md) | ArkTS/ArkUI browser shell, local storage, and provider integration |
| Desktop extension | [`extensions/aira-sync/`](extensions/aira-sync/README.md) | Chromium/Firefox UI, background runtime, and cross-device client |
| Personal Server | [`services/personal-server/`](services/personal-server/README.md) | Node.js/Docker sync, pairing, Page Push, and tab-presence APIs |
| Shared resources | [`resources/`](resources/) and [`docs/`](docs/) | Icons, notices, architecture decisions, and protocol documentation |

## Architecture At A Glance

The clients keep their local browser state and select one remote provider for each supported sync domain. The public
providers are WebDAV and Personal Server; Official builds can additionally use Aira Cloud and Huawei Cloud Space.

Personal Server exposes discovery, one-time pairing, Bookmark, History, Personalization, Novel Bookshelf, Page Push,
and Cross-device Tabs endpoints. It uses per-device bearer credentials, stores only credential hashes, and does not
implement a user account system.

Start with these contracts before changing wire behavior:

- [Open-source distribution boundary](docs/open-source-distribution.md)
- [Personal Server self-hosting](docs/self-hosting.md)
- [Personal Server protocol](services/personal-server/docs/protocol.md)
- [Personal Server operations](services/personal-server/docs/operations.md)
- [Aira-sync development notes](extensions/aira-sync/README.md)
- [HarmonyOS client development notes](AiraBrowser/README.md)

## Development Prerequisites

| Area | Requirement |
| --- | --- |
| Repository scripts | Node.js `18.20.8` from `.node-version` / `.nvmrc` |
| Aira-sync | Node.js 18.x and npm |
| Personal Server | Node.js 20 or newer, or Docker with Compose |
| HarmonyOS client | DevEco Studio, HarmonyOS NEXT SDK/API 23 or newer, and `ohpm` |

Clone the repository and run commands from its root unless a section says otherwise:

```bash
git clone https://github.com/mason173/aira-browser.git
cd aira
```

## Run Personal Server Locally

The Node.js check is the fastest way to exercise the server without creating persistent data:

```bash
cd services/personal-server
npm ci
npm run check
```

To run a persistent local instance with Docker:

```bash
cd services/personal-server
cp .env.example .env
docker compose up -d --build
docker compose exec aira-server cat /data/setup-code
```

Use the printed one-time code to pair a development client. The default Compose file binds `127.0.0.1:8787`; use a
TLS reverse proxy before making an instance reachable outside a trusted local network. Backup, restore, upgrades,
reverse proxy settings, and credential revocation are documented in the server README and operations guide.

## Build Aira-sync

```bash
cd extensions/aira-sync
npm ci
npm run typecheck
npm test
npm run build:community
```

The Community output is written to `build/community/` and can be loaded as an unpacked extension in a Chromium-based
browser. The public Community manifest has the stable extension ID `efehgppkhnkjamcpbipclfmmofdildji`.

Official builds use private route configuration supplied through `AIRA_SYNC_OFFICIAL_API_ROUTES`; the repository does
not contain production routes. See the extension README for the complete route schema and package commands.

## Build The HarmonyOS Client

Open `AiraBrowser/` in DevEco Studio, or use the root build script:

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community AIRA_ALLOW_UNSIGNED_BUILD=1 SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

This produces an unsigned Community HAP suitable for CI and source verification. Device installation requires a local
signing profile for `org.aira.browser`. An Official build additionally requires private AGConnect input, production
routes, and a signing profile for `com.aira.browser`:

```bash
AIRA_DISTRIBUTION=official SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

Do not commit `agconnect-services.json`, build profiles containing encrypted passwords, `.p12`/`.p7b` files, or any
other signing material. Official signing and device-install wrappers are private packaging scripts, not this repository.
See [`AiraBrowser/README.md`](AiraBrowser/README.md) for Community builds.

## Community And Official

The two distributions share source code and tests. Only build-time identity and private capability inputs differ:

| Capability | Community | Official |
| --- | --- | --- |
| Local browser features and local storage | Enabled | Enabled |
| User-selected WebDAV | Enabled | Enabled |
| Personal Server sync and Cross-device Tabs | Enabled | Enabled |
| Huawei Account / Huawei Cloud Space | Not configured | Private Huawei project and approval |
| Aira Cloud hosted services | Not configured | Private service routes and entitlement |
| Huawei IAP / Aira Pro | Not configured | Private production service |

Read [`docs/open-source-distribution.md`](docs/open-source-distribution.md) before adding a provider or changing a
distribution boundary. Do not create a long-lived Community fork or copy Official-only pages into a second source tree.

## Contribution Workflow

Keep cross-component protocol changes in one pull request and run checks for every component you touch. Put policy,
transport, persistence, and orchestration in their existing `core`, `services`, `data`, or `features` owners rather
than adding behavior to native UI shells.

Before opening a pull request:

```bash
# from the repository root
git diff --check

# for Aira-sync changes
(cd extensions/aira-sync && npm run typecheck && npm test)

# for Personal Server changes
(cd services/personal-server && npm run check)
```

Read [`CONTRIBUTING.md`](CONTRIBUTING.md) for review expectations and [`SECURITY.md`](SECURITY.md) for private
vulnerability reporting. Never include device data, credentials, tokens, databases, backups, browser profiles, or
production configuration in an issue or pull request.

## License

Aira-authored source code is available under [GPL-3.0-only](LICENSE). Third-party components retain their own licenses;
see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and the notices in each component directory.

The license does not grant rights to the Aira name, logos, or other trademarks. See [`TRADEMARKS.md`](TRADEMARKS.md).

## Star History

[![Star History Chart](https://api.star-history.com/svg?repos=mason173/aira-browser&type=Date)](https://star-history.com/#mason173/aira-browser&Date)
