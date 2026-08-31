# Aira Browser for HarmonyOS

Aira Browser is a HarmonyOS NEXT browser built with ArkTS, ArkUI, ArkWeb, and the Stage model.

The client is maintained as one source tree with two build distributions:

- **Community** provides local browsing and data, WebDAV, and Personal Server without Aira production credentials.
- **Official** adds Aira Cloud, Huawei Account, Huawei Cloud Space, and Huawei IAP through private build inputs.

`AIRA_DISTRIBUTION=community|official` selects the distribution independently from the debug/release build variant. Local
features do not require membership; Aira Pro pays for Official Aira-hosted services.

## Build

The source tree defaults to the Community identity `org.aira.browser.community`. Install the dependencies from
`AiraBrowser/`, provide a matching local HarmonyOS signing profile, then build from the repository root:

```bash
cd AiraBrowser
ohpm install
cd ..
AIRA_DISTRIBUTION=community SKIP_INSTALL=1 ./scripts/build-aira-browser.sh
```

See [AiraBrowser/README.md](AiraBrowser/README.md) for SDK, signing, release, and device-install details. See
[docs/open-source-distribution.md](docs/open-source-distribution.md) for the capability matrix and private-input boundary.

## Personal Server

[Aira Personal Server](https://github.com/mason173/aira-server) is a separate GPL-3.0-only project for one owner and multiple
paired devices. It supports Bookmark, History, Personalization, and Novel Bookshelf sync with revocable device
credentials, Docker/Compose deployment, and validated backup/restore. See [docs/self-hosting.md](docs/self-hosting.md).

The Aira production backend, Admin console, billing, analytics, policy operations, and deployment configuration are not
part of this repository or Personal Server.

## Project Policy

Aira-authored source is offered under [GPL-3.0-only](LICENSE). Review [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) before
redistribution: the current Icons8 asset set is commercially licensed and remains a publication gate until its public
source/binary distribution rights are confirmed or the assets are replaced.

Contributions and security reports follow [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and
[TRADEMARKS.md](TRADEMARKS.md).
