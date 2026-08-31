# Personal Server

Aira Personal Server is maintained in the separate
[mason173/aira-server](https://github.com/mason173/aira-server) repository. It is designed for one person who controls
one server and pairs multiple devices.

It deliberately has no registration, password accounts, user directory, organizations, roles, membership, billing,
referral, Huawei identity, or Aira production control plane. Device pairing issues revocable per-device credentials;
Huawei tokens and IAP receipts are never sent to a Personal Server.

The v1 server supports:

- Bookmark Sync v3
- incremental History Sync v1
- Personalization Sync v2
- Novel Bookshelf Sync v2
- Docker/Compose deployment and health checks
- SQLite migrations, online backup, validated restore, credential rotation, and revocation

Follow the Personal Server repository's README for deployment, reverse proxy/TLS, pairing, upgrade, backup, and recovery.
In Aira Browser, open Sync, choose Personal Server, enter the HTTPS server URL, and complete the one-time pairing flow.

Disconnecting a Personal Server removes its device credential and instance configuration from the client. It does not
delete local browser data.
