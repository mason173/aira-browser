# Personal Server Protocol

## Discovery

`GET /.well-known/aira` returns the stable instance ID, supported protocol range, authentication mode, and Domain capability versions. Clients must reject an unsupported version before pairing.

## Authentication

The first server start creates a high-entropy, one-use bootstrap code at `<data-dir>/setup-code` with mode `0600`. `POST /v1/pairing/exchange` consumes that code and returns a random per-device bearer token. Later pairing codes are created by an authenticated device and expire after ten minutes by default.

The server stores only SHA-256 token hashes. Every protected request uses:

```http
Authorization: Bearer <device-token>
```

Huawei access tokens, Aira membership state, IAP receipts, passwords, and cookies are not accepted by this protocol.

## Device Management

| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/v1/pairing/exchange` | Consume a one-time code and pair one device |
| `POST` | `/v1/pairing/codes` | Mint a one-time code from a paired device |
| `GET` | `/v1/devices` | List paired and revoked devices without tokens |
| `POST` | `/v1/device/rotate` | Replace the caller's credential immediately |
| `POST` | `/v1/devices/:deviceId/revoke` | Revoke one active device |

Pairing requests declare `deviceKind` as `phone` or `desktop`. Older clients that omit it remain compatible and are
treated as phones. History requests require `clientId` to equal the device ID bound to the bearer credential.

## Sync Domains

| Domain | Version | Base path | Storage model |
| --- | ---: | --- | --- |
| Bookmarks | 3 | `/v1/sync/bookmarks` | Complete snapshot, history descriptor, commit CAS |
| History | 1 | `/v1/sync/history` | Bounded mutations, cursor exchange, stable-head bootstrap |
| Personalization | 2 | `/v1/sync/personalization` | Complete snapshot, revision CAS |
| Novel Bookshelf | 2 | `/v1/sync/novel-bookshelf` | Complete snapshot, revision CAS |

## Cross-device Services

| Service | Version | Base path | Retention model |
| --- | ---: | --- | --- |
| Page Push | 1 | `/v1/page-push` | Two-minute per-desktop task with lease and acknowledgement |
| Cross-device Tabs | 1 | `/v1/device-tabs` | Latest per-device snapshot, online for two minutes |

Page Push uses `enqueue`, `poll`, and `ack` operations. A paired phone enqueues one task for each paired desktop that has
polled Page Push within the last two minutes. General authenticated activity does not make a desktop a Page Push target.
A desktop leases its own task before opening it and acknowledges `opened` or `failed`; another device cannot
poll or acknowledge that task. Task rows are physically removed after fourteen days.

Cross-device Tabs uses `publish`, `list`, and `clear`. The authenticated device ID and kind are authoritative; payloads
cannot impersonate another device. A phone lists desktop snapshots and a desktop lists phone snapshots. Only HTTP(S)
URLs without embedded credentials are accepted, and each device may publish at most 100 tabs. Revoking a paired device
immediately excludes its snapshot from list results even when the snapshot TTL has not elapsed.

Application conflicts use HTTP `409` with stable JSON codes such as `sync_conflict`, `personalization_sync_write_conflict`, and `novel_bookshelf_sync_write_conflict`. Clients must preserve and parse error bodies on non-2xx responses.

## Compatibility Rules

- Additive response fields are allowed within a protocol version.
- Removing or changing field semantics requires a new Domain or discovery protocol version.
- New migrations are append-only and ordered by filename.
- The stable `instanceId` must survive upgrades and restores.
- A client must isolate baselines, runtime state, and History account scope by `instanceId` and normalized base URL.
- Page Push and Cross-device Tabs are ephemeral coordination services, not durable Sync Domains or browser-history stores.
