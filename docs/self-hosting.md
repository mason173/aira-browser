# Personal Server

Aira Personal Server is maintained in this monorepo under
[`services/personal-server`](../services/personal-server/README.md). It is designed for one person who controls one server
and pairs multiple devices.

It deliberately has no registration, password accounts, user directory, organizations, roles, membership, billing,
referral, Huawei identity, or Aira production control plane. Device pairing issues revocable per-device credentials;
Huawei tokens and IAP receipts are never sent to a Personal Server.

The v1 server supports:

- Bookmark Sync v3
- incremental History Sync v1
- Personalization Sync v2
- Novel Bookshelf Sync v2
- Page Push v1 with short-lived per-desktop delivery and acknowledgement
- Cross-device Tabs v1 with short-lived phone/desktop presence snapshots
- Docker/Compose deployment and health checks
- SQLite migrations, online backup, validated restore, credential rotation, and revocation

Follow the [Personal Server README](../services/personal-server/README.md) for deployment, reverse proxy/TLS, pairing,
upgrade, backup, and recovery.
In Aira Browser, open Sync, choose Personal Server, enter the HTTPS server URL, and complete the one-time pairing flow.
Create another one-time pairing code for each Aira-sync installation and connect it to the same server. The paired phone
and desktops can then use the same server for sync, Page Push, and Cross-device Tabs without an Aira account.

Disconnecting a Personal Server removes its device credential and instance configuration from the client. It does not
delete local browser data.
