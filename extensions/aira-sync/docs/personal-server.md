# Use Aira-sync With Personal Server

## Deploy

Follow the [Aira Personal Server deployment guide](../../../services/personal-server/README.md). For internet access, place
the server behind a trusted HTTPS reverse proxy. Aira-sync accepts HTTP for a trusted local network, but HTTPS should be
used whenever traffic leaves that network.

The server is single-owner and multi-device. It does not provide accounts, organizations, roles, memberships, or a
hosted control plane.

## Pair This Browser

1. Start the server and read its pairing code from `setup-code`.
2. Open Aira-sync and select `使用自己的服务器`.
3. Enter the server base URL and the same pairing code used by the other devices.
4. After discovery and pairing succeed, Aira-sync selects Personal Server as the active Bookmark Provider.

The server pairing code can be reused. The returned device token belongs only to this extension installation and can be
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

## Troubleshooting

### The popup reports unreadable data

A reverse proxy can answer before the server does. When it returns a non-JSON body, such as an HTML 404, 413 or 502 page,
the extension reports "私有化部署返回了无法解析的数据" (unreadable data). The real HTTP status is carried on the error
object but is not shown in the popup, so check the browser Network panel or the proxy access log for it.

The most common cause is a proxy that does not pass `/.well-known/aira` through. Control panels such as 宝塔 (BT Panel)
and aaPanel generate a static `/.well-known` location for certificate validation; it is longer than the general proxy
route, so Nginx serves it from the site root and answers with a 404 before the request reaches the server. Keep an
exact-match route for the discovery document:

```nginx
location = /.well-known/aira {
  proxy_pass http://127.0.0.1:8787;
}
```

The deployment guide covers the full reverse proxy configuration, the request-body limit, and the `/health` and
`/.well-known/aira` checks:

- [Aira Personal Server](../../../services/personal-server/README.md)
- [Operations](../../../services/personal-server/docs/operations.md)
