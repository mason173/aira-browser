---
status: accepted
date: 2026-08-29
---

# Cross-Device Open Tabs Use Ephemeral Presence Snapshots

Cross-Device Open Tabs is an independent, short-lived Presence Domain shared by the HarmonyOS App and AiraTab. It is
not Bookmark Sync, History Sync, Phone Page Push, a recently-closed list, or a remote-control channel. Its only state is
the latest complete publishable tab projection for each authenticated installation. Aira Cloud keys that projection by
`uid + deviceId`; multiple computers and phones therefore coexist without replacing one another.

The HarmonyOS App authenticates with its verified Huawei-account token and a stable App installation ID. AiraTab
authenticates with its existing independent Desktop Device Session, whose server-owned device ID must match the request.
The capability uses the same Pro entitlement boundary as Aira Cloud Phone Page Push. Removing the account, disabling
the capability, or revoking a Desktop Device Session clears that installation's snapshot immediately. A failed clear is
bounded by expiry rather than retained as durable user data.

`POST /device-tabs/v1/publish` replaces one device snapshot atomically. `POST /device-tabs/v1/list` returns only online
devices of the opposite kind, grouped as complete device records. `POST /device-tabs/v1/clear` removes the caller's
snapshot. Each device record carries `deviceId`, `deviceKind`, an automatically derived `deviceName`, `platform`, `model`,
`browserName`, `browserVersion`, server `updatedAt`/`expiresAt`, and an ordered `tabs` array. A tab contains only title,
canonical HTTP(S) URL, active state, client last-active time, and local window/tab order. The server rejects private or
non-web protocol leakage indirectly by accepting only bounded HTTP(S) URLs without embedded credentials; both clients
must still filter at the source before upload.

The online window is two minutes from server receipt. App foreground/current-tab signals and AiraTab startup/tab-event/
alarm signals publish complete snapshots and heartbeats. A computer that is off, a closed browser, a killed/backgrounded
App, or a network-disconnected client disappears after that window. The server may retain the expired row for cleanup
and physically removes it after roughly ten minutes, but list operations never return expired rows. “Online” means the
client can still authenticate and publish; it does not mean recent mouse, keyboard, or touch activity.

Snapshots contain at most 100 ordinary tabs and are request-size bounded. They never contain screenshots, DOM, cookies,
form values, response bodies, browsing-history events, private/incognito tabs, internal/error/viewer pages, extension
pages, or files. Phase 1 may open a selected remote HTTP(S) URL on the viewing device. It cannot focus, close, mutate, or
otherwise control the source tab. AiraTab's browser host permissions are used only to project already-open ordinary
HTTP(S) tabs; the warning-bearing `tabs` permission is added only if real Chrome/Edge verification proves the existing
host permissions insufficient.

Device groups sort by server freshness. Tabs sort active first, then by last-active time and stable local order. Clients
show the device label, model/platform/browser metadata, tab count, and freshness. Device labels are read-only and always
derived by the publishing client: the App uses HarmonyOS device information, while AiraTab uses normalized browser and
OS metadata because exact desktop hardware model/name is not reliably available to a browser extension.
