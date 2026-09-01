# Use Aira-sync With Personal Server

## Deploy

Follow the [Aira Personal Server deployment guide](https://github.com/mason173/aira-server). For internet access, place
the server behind a trusted HTTPS reverse proxy. Aira-sync accepts HTTP for a trusted local network, but HTTPS should be
used whenever traffic leaves that network.

The server is single-owner and multi-device. It does not provide accounts, organizations, roles, memberships, or a
hosted control plane.

## Pair This Browser

1. Start the server and obtain its one-time setup code, or create a new pairing code from an already paired device.
2. Open Aira-sync and select `使用自己的服务器`.
3. Enter the server base URL and pairing code.
4. After discovery and pairing succeed, Aira-sync selects Personal Server as the active Bookmark Provider.

The pairing code is consumed once. The returned device token belongs only to this extension installation and can be
rotated or revoked independently.

## Supported Services

The discovery document at `/.well-known/aira` must advertise Bookmark v3, History v1, Page Push v1, and Cross-device Tabs
v1. Aira-sync rejects an incompatible server before storing credentials.

Personal Server is free of Aira membership checks. The popup's advanced settings control Page Push and Cross-device Tabs
for this server instance. WebDAV remains a separate Bookmark-only option and never carries history or device presence.

## Data Boundaries

- Bookmark baselines are scoped by `instanceId`; a different server cannot reuse them.
- History projection, cursor, outbox, and deletion frontier are scoped by `personal-server:<instanceId>`.
- Page Push and Cross-device preferences use the same instance scope.
- Huawei tokens, Aira membership state, and Official desktop credentials are never sent to Personal Server.
- The protocol does not provide end-to-end encryption. The Personal Server administrator can read synchronized data.

Disconnecting Personal Server removes its URL and device credential. If it is active, the local Provider selection is
also cleared. Local browser bookmarks/history and inactive Provider baselines are not deleted.
