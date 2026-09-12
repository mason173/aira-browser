---
status: accepted
date: 2026-09-13
---

# App-Launch Platform Tokens Use Exact-Host Compatibility Identities

Some sites decide which app-launch scheme to emit from the platform token in the User-Agent rather than from a feature
probe. When such a page reads an Android token it builds an Android-only scheme, and the HarmonyOS build of the target
app never registered that scheme. The platform then reports no matching ability, and the launch fails even though the app
is installed. Aira's ordinary physical-phone default is the Android-compatible `AIRA_COMPAT_MOBILE_USER_AGENT`, so this
class of page silently breaks for the ordinary phone configuration.

The reported case is the China Mobile activity-family pages (`wx.10086.cn`, `h.app.coc.10086.cn`,
`client.app.coc.10086.cn`, `h5.he.10086.cn`). Their PSIE launch SDK selects the target from the platform token:

- an Android token emits `com.greenpoint://android.mc10086.activity`, which is the Android package;
- a HarmonyOS/ArkWeb token emits the cross-platform `cn.10086.app://` entry or a universal-link transit page.

The HarmonyOS client registers the cross-platform entry, not the Android package scheme, so the Android-shaped launch can
never resolve.

## Decision

Aira corrects the platform token through the existing package-owned exact-Host compatibility catalog rather than by
special-casing one service or one scheme. `BrowserUserAgentHostPolicyCatalog` gains a third compiled Profile,
`aira_harmony_compat`, whose concrete identity is `AIRA_COMPAT_HARMONY_MOBILE_USER_AGENT`: it keeps the `OpenHarmony` and
`ArkWeb` tokens and contains no `Android` token. The page then reads a HarmonyOS platform and emits its own
cross-platform entry.

This stays inside the established contract:

- `BrowserUserAgentHostPolicyService` remains the single ArkWeb application/host UA execution owner and the single
  narrative owner of the mandatory runtime resolver.
- The new rule is an ordinary mandatory exact-Host entry in the same bundled catalog, with the same validation, evidence
  metadata, conflict rejection, and complete-Profile-group replay.
- It is scoped to the mobile family. A large-screen request does not receive a phone-shaped identity.
- It is hidden from ordinary site-customization UI exactly like the Google and YouTube rules.
- Mandatory Host precedence, exact-Origin/tab/global precedence, Controller construction, Window-Open/OAuth, URL replay,
  BFCache configuration, and privacy mode are unchanged. The new Profile registers no known Client Hints metadata, so
  these Hosts keep the platform's own low-entropy hints instead of receiving Android-shaped ones; no Client Hints code
  path is added or altered.

A second, bounded recovery exists for pages that cannot be fixed by the token alone. When a non-web launch reports
`no_matching_ability`, `ExternalNavigationLaunchService` retries once through the declared cross-platform rewrite for the
China Mobile Android scheme (`com.greenpoint://android.mc10086.activity` to `cn.10086.app://`), then once through
`context.openLink(url, { appLinkingOnly: false })` so the system's own scheme router gets a chance. Both steps run only
after the previous attempt reported that no installed ability claimed the URI; success short-circuits, and the final
failure is still reported as before. This recovery does not invent a bundle target, does not broaden scheme handling, and
does not run for HTTP App Linking.

## Evidence

The classification is derived from the shipped page code, not from device capture. The PSIE SDK at
`h.app.coc.10086.cn/ngpsie/psiesdk/js/index.js` and the production 1.3.2 build define:

```js
isAndroid = /Android/i.test(UA)
isHarmony = /harmony.*arkweb|arkweb.*harmony/i.test(UA)
scheme.protocol = isHarmony || isIOS ? 'cn.10086.app' : 'com.greenpoint://android.mc10086.activity'
```

Aira's `AIRA_COMPAT_MOBILE_USER_AGENT` matches `isAndroid` and fails `isHarmony`, which selects the Android-only branch.
`arkweb_original` and the `mobile_huawei_browser` preset both contain `Android` in their current text, so a user workaround
through those identities is not reliable; the catalog entry is the deterministic fix.

This revision is verified by catalog tests asserting the Android-free HarmonyOS shape, the mobile-only scope, and the
scheme rewrite, plus the static contract scripts. True-device acceptance remains a follow-up that requires explicit
authorization.
