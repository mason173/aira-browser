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

History requests require `clientId` to equal the device ID bound to the bearer credential.

## Sync Domains

| Domain | Version | Base path | Storage model |
| --- | ---: | --- | --- |
| Bookmarks | 3 | `/v1/sync/bookmarks` | Complete snapshot, history descriptor, commit CAS |
| History | 1 | `/v1/sync/history` | Bounded mutations, cursor exchange, stable-head bootstrap |
| Personalization | 2 | `/v1/sync/personalization` | Complete snapshot, revision CAS |
| Novel Bookshelf | 2 | `/v1/sync/novel-bookshelf` | Complete snapshot, revision CAS |

Application conflicts use HTTP `409` with stable JSON codes such as `sync_conflict`, `personalization_sync_write_conflict`, and `novel_bookshelf_sync_write_conflict`. Clients must preserve and parse error bodies on non-2xx responses.

## Compatibility Rules

- Additive response fields are allowed within a protocol version.
- Removing or changing field semantics requires a new Domain or discovery protocol version.
- New migrations are append-only and ordered by filename.
- The stable `instanceId` must survive upgrades and restores.
- A client must isolate baselines, runtime state, and History account scope by `instanceId` and normalized base URL.
