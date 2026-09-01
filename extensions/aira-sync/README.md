# Aira-sync

Aira-sync is the open-source desktop browser extension for Aira Browser. It connects Chrome-compatible desktop browsers
to the same single-owner Aira Personal Server used by the HarmonyOS app.

With a Personal Server, paired devices can share:

- bookmarks through the complete-snapshot v3 protocol;
- browsing history through the bounded incremental/bootstrap v1 protocol;
- phone-to-desktop Page Push;
- short-lived Cross-device Tabs presence.

Aira-sync has no account registration, password login, membership, billing, referral system, or multi-user server model.
One owner pairs multiple revocable devices with one Personal Server.

## Distributions

Community and Official are built from the same source tree and commit.

| Capability | Community | Official |
| --- | --- | --- |
| Personal Server | Available, no membership gate | Available, no membership gate |
| WebDAV bookmark sync | Available | Available |
| Aira Cloud and desktop pairing | Unavailable | Available, hosted-service entitlement applies |
| History, Page Push, Cross-device Tabs on Personal Server | Available | Available |

The Community build contains no default Aira production API endpoint. Official service routes are private build inputs.

## Development

```bash
cd extensions/aira-sync
npm ci
npm run typecheck
npm test
npm run build:community
```

The Community output is written to `build/community/`. Load that directory as an unpacked extension in Chrome or Edge
developer mode. Every Community build uses the public manifest key checked by the build and therefore keeps the stable
Chromium extension ID `efehgppkhnkjamcpbipclfmmofdildji`. The repository contains no extension signing private key.
Official builds omit `manifest.key`; a future Chrome or Edge store listing owns its store-assigned ID.

An Official build requires every hosted-service route to be supplied as one JSON object:

```bash
AIRA_SYNC_OFFICIAL_API_ROUTES='{
  "bookmarkSync":"https://example.invalid/sync/v3/bookmarks",
  "historySync":"https://example.invalid/sync/v1/history",
  "desktopPairingCreate":"https://example.invalid/desktop-login/create",
  "desktopPairingStatus":"https://example.invalid/desktop-login/status",
  "desktopMembershipState":"https://example.invalid/desktop-login/membership-state",
  "desktopSessionRevoke":"https://example.invalid/desktop-session/revoke",
  "pagePushPoll":"https://example.invalid/phone-page-push/poll",
  "pagePushAck":"https://example.invalid/phone-page-push/ack",
  "deviceTabsPublish":"https://example.invalid/device-tabs/v1/publish",
  "deviceTabsList":"https://example.invalid/device-tabs/v1/list",
  "deviceTabsClear":"https://example.invalid/device-tabs/v1/clear"
}' npm run build:official
```

Official output is written to `build/official/`. The build fails if any route is absent, non-HTTPS, or contains embedded
credentials. Do not commit a production environment file.

## Personal Server

Deploy [Aira Personal Server](../../services/personal-server/README.md), then open Aira-sync and choose
`使用自己的服务器`. Enter the public HTTPS base URL and a one-time pairing code. The first code comes from the server's
`setup-code` file; later codes can be created by an already paired device.

The extension stores one device credential and isolates preferences, History data, Bookmark baselines, Page Push, and
Cross-device Tabs by Personal Server instance identity. Disconnecting removes the connection and active Provider choice,
but preserves local browser data and inactive Provider baselines. See [docs/personal-server.md](docs/personal-server.md).

## Data And Sync

- One bookmark Provider is active on each extension installation. Inactive Providers are not read or written in the
  background.
- Personal Server and Aira Cloud can carry Bookmark, History, Page Push, and Cross-device Tabs. WebDAV carries Bookmark
  only.
- Aira-sync captures only locally originated regular HTTP(S) history visits. Remote visits are shown in Aira-sync's History
  projection and are never written into the browser's native history database.
- The extension overrides the browser History page so the merged projection opens from the normal History command.
- First sync and ordinary differences merge automatically. A real two-sided Bookmark conflict asks which side to keep.
- Personal Server tokens and WebDAV credentials stay in extension storage and are sent only to the selected endpoint.
- Do not commit credentials, tokens, production environment files, generated builds, browser profiles, databases, or
  remote snapshots.

## License And Marks

Authored source code is licensed under GPL-3.0-only. See [LICENSE](LICENSE). Third-party components retain their own
licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). The license does not grant rights to Aira names or logos;
see [TRADEMARKS.md](TRADEMARKS.md).
