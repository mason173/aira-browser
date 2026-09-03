# ADR-0071: Hosted Minimum-Version Policy for Bookmark Cutover

Status: Accepted

## Decision

The Aira Cloud bookmark cutover is enforced by a server-owned minimum-version policy. The App checks
`POST /client/v1/update-policy` only when Aira Cloud is an active provider or additional backup. The request contains
the bundle name, installed version, distribution, and `aira-cloud-bookmarks-v4` protocol identifier. The response is
valid only when `ok` is `true`:

```json
{
  "ok": true,
  "policyId": "bookmarks-v4-cutover-20260903",
  "required": true,
  "minimumVersionCode": 1000369,
  "minimumVersionName": "2.6.1",
  "updateUrl": "store://appgallery.huawei.com/app/detail?id=com.aira.browser",
  "updateMessage": "请升级 Aira 后继续使用云书签同步。"
}
```

Any missing, malformed, or unavailable policy response is fail-open for local browsing. A valid required response
does not disable local bookmarks, history, tabs, WebDAV, Huawei Space, or Personal Server. It only pauses the hosted
Aira Cloud capability and presents an upgrade entry. The user may open AppGallery or continue with local features for
the current process; the prompt is not shown again in that process after either choice.

The server migration is a separate one-time operator action. It must select one source per UID in the order
`v3 > v2 > legacy`, write one v4 snapshot, record an audit row, and never merge generations. The migration runs before
the server policy is enabled. No production migration or deployment is part of the client change.

## Consequences

- Old clients receive `client_update_required` from bookmark routes and cannot write a second copy of the data.
- New clients can be required to upgrade without making the browser unusable when the policy service is unreachable.
- The backend must publish the policy endpoint before enabling the minimum-version gate.
- AppGallery or a configured HTTPS update URL must be reachable on the target device.
