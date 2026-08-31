# Window-Open / BFCache Contract Uses Static Regression Guardrails

Accepted: 2026-07-13

Freeze policy retired: 2026-08-27

## Context

The browser repeatedly regressed while aligning ordinary new-window links, Google OAuth popup ownership, child-to-opener
Back, and dynamic-list same-tab restoration with Huawei Browser 6.1.1. Fixes aimed at one symptom repeatedly broke another
because popup event timing, Hosted Web mounting, controller attachment, restore, user-agent policy, and BFCache were changed
independently.

Commit `172fef16` is the first combined baseline verified by user-operated device flows and read-only logs:

- ArkWeb accepted popup controllers with `NotifyPopupWindowResult result:1` and `PopupWindowCallbackImpl Continue`.
- Google OAuth completed and the native child exited back to its live opener.
- Ordinary child terminal Back returned through the opener-aware tab-close path.
- IT之家 refreshed-list Back used native history with `hasDiffUserAgent:0`, `canStore:1`, and `fromBFCache:1`.
- No `OnBeforePopup nweb is null`, reparent warning, Google GSI popup failure, or
  `policy_background_contract_violation` appeared in the verified matrix.

This contract took multiple failed experiments to isolate. Changes therefore need focused regression checks and
proportional device verification.

## Decision

The verified Window-Open / BFCache contract may evolve through normal in-scope implementation work.

`scripts/check-aira-window-open-contract.sh` is a mandatory build guard, invoked before the general architecture guard.
It checks required static ownership, call-order, and prohibited-path invariants. It does not protect paths by dirty-state
comparison, pin implementation hashes, require amendment IDs, or recognize authorization override variables.

The repository retired the previous deny-by-default edit freeze on 2026-08-27. The historical amendment sections below
remain as evidence for how the baseline evolved before that retirement; they are not current edit authorization gates.

The statically guarded invariants are:

1. `BrowserWindowOpenApplicationCoordinator` remains the app-level window-open/child-return owner.
2. `BrowserWebTabsController` directly owns pending popup event consumption for a tab and consumes it before Hosted Web
   construction.
3. The pre-build consumption result reaches normal controller attachment; no second attachment/window-open owner appears.
4. Normal live Web runtimes remain in fixed per-tab slots whose key is `tab.id` plus the owner-managed Hosted node
   generation, and switch visibility without reparenting while that generation is unchanged. An explicit
   Controller/Hosted-node replacement for the same tab changes the key and replaces that tab's `NodeContainer`; ordinary
   tab visibility changes do not. When a cold-restored tab's owner-managed controller becomes ready after the first slot
   evaluation, the existing surface revision must re-evaluate the mount predicate without changing the key while its
   generation is unchanged. Foreground visibility additionally requires the Hosted active tab id to equal the Shell's
   active tab id. A retained outgoing controller may stay mounted and hidden, but it must not appear during a
   Home-to-new-tab handoff; the target loading backdrop and progress presentation own that interval until the target
   Hosted surface becomes active.
5. Ordinary popup/OAuth children never use direct-child, hidden, prepared, or parking hosts. Parking remains limited to the
   desktop Web-entry exception.
6. Child exit and terminal Back close through the opener-aware tab path.
7. A fresh controller explicitly using the ArkWeb Original identity never receives an application-default string through
   `setCustomUserAgent()`. On a physical phone, ordinary Aira Default pages use the Android-compatible mobile identity
   through the existing Controller identity owner so legacy mobile detection works; that default accepts ArkWeb's known
   custom-UA/BFCache tradeoff. Explicit controller/site identities retain priority.
8. BFCache controller options are generation/controller/config aware and are cleared when the matching Hosted runtime is
   disposed.
9. `policy_background_contract_violation` remains a shipping blocker.
10. Timer/replay recovery, `window_open_handoff_recovery`, `BrowserWindowOpenNavigationWatchService`, ad-hoc popup
    controllers, and ordinary popup URL replay remain prohibited.
11. An active page-behavior lifecycle or heartbeat recovery sample that reports a playing video must first emit the
    existing identity-bearing playing video event. This lets the media-takeover owner recover after document-start
    injection, BFCache restore, or a missed original `playing` event without adding another Web-runtime probe or changing
    popup/BFCache ownership. Ordinary media/time-update notifications do not duplicate this recovery event.
12. Every newly attached Web controller disables ArkWeb's independent ad filter in the common bootstrap path. Production
    code does not publish `AdsBlockManager` rules or register `onAdsBlocked`; Rust remains the sole subscription-rule
    parser and selector for ordinary, background, restored, and Window-Open Web runtimes.

## Authorized amendment: 2026-07-25

The user explicitly authorized editing the protected Hosted Web path to fix the intermittent missing Video Assistant
entry. `HostedWebNode.ets` now reuses its existing tracked-video event builder before publishing an active lifecycle or
heartbeat recovery sample. The event is non-mutating and carries the already-owned runtime id, source, geometry,
visibility, timing, and playback state. Normal media/time-update notifications remain on their existing bounded path.

This amendment does not change pending-popup consumption, controller construction or attachment, fixed per-tab Hosted
Web slots, opener-aware child return, user-agent application, BFCache configuration, or background protection. The guard
now checks the new signal order in addition to all existing Window-Open / BFCache invariants. A successful static guard
and build do not replace the user-operated navigation matrix required before shipping a protected-path change.

The direct device installer carried amendment ID `2026-07-25-playing-video-identity-recovery` while this amendment was
the active protected working-tree revision. The later 2026-07-30 Hosted Web orientation revision supersedes that
installer authorization; this section remains the historical record of the identity-recovery change.

## Authorized fixed-slot refresh revision

On 2026-07-25 the user explicitly authorized a protected-file repair for cold-start-restored tabs. The initial active
tab could materialize normally, while selecting another restored metadata-only tab created its controller after the
fixed-slot Builder's first evaluation. `surfaceRevision` already reached `BrowserHostedWebFixedSlots`, but the mount
predicate did not consume it, so ArkUI had no dependency that caused the new `NodeContainer` to be projected.

The authorized revision is deliberately limited to passing `surfaceRevision` into `shouldMountFixedSlot()`. It does not
change the stable `tab.id` key, controller ownership, popup consumption, controller attachment, child return, UA, BFCache,
or background-discard contracts. The guard recognizes this exact two-line implementation revision so ordinary local
build/install commands can run without a permanent override variable; any additional protected implementation change is
still denied by default. The full user-operated Window-Open/BFCache matrix remains required before treating the revised
contract as release-accepted.

## Authorized live document-start update revision

On 2026-07-27 the user explicitly authorized a protected-path repair for phone tab-card switching. PID-scoped device
logs from package `1000422` proved that the selected target still had both an attached fixed-slot node and an attached
ArkWeb controller immediately before active-surface sync. `BrowserWebHostCoordinator.ensureController()` nevertheless
disposed that live node because its computed document-start script signature had changed. The replacement NWeb started
with an empty source, logged `web controller is nullptr` and `LoadUrl message:invalidUrl`, while page-cache policy still
classified the runtime as a live hit. The visible result was a persistent white page after switching A/B tabs.

The signature-rebuild branch originated in `9c87594b` to apply userscript setting changes, while `aa27b588` later made
active and preview Hosted nodes share one document-start provider. Runtime script/value readiness can still change the
computed signature after an already-loaded Web is attached, so using that signature as an activation-time disposal
trigger violates the fixed per-tab identity contract. `BrowserWebHostCoordinator` now preserves an ArkWeb-attached
controller and updates its Hosted config in place; signature changes may replace only a controller that has not yet
attached to ArkWeb. This keeps the current document and NWeb identity stable during tab activation while retaining the
existing config-refresh path for subsequent navigation. Popup/OAuth consumption, tab-id keys, BFCache policy, child
return, user-agent policy, parking exceptions, and background discard protection are unchanged.

The user accepted this repair on physical-phone package `1000425`: repeating the A/B tab-card switching flow no longer
produced a white Web surface. All `[DEBUG-phone-tabs-20260727]` instrumentation was removed after that acceptance; the
frozen guard records the final diagnostic-free `BrowserWebHostCoordinator` hash.

## Authorized large-screen default-UA revision

On 2026-07-25 the user explicitly authorized revising the frozen default-UA behavior for the large-screen Shell. The
previous application policy always installed Aira's Android-shaped mobile-compatible UA, even after the Window Session
had selected the large-screen Shell. Consequently desktop sites such as Bilibili redirected ordinary
`https://www.bilibili.com/` navigation to their mobile host regardless of whether navigation originated from Home
favorites or search results.

The authorized revision keeps `BrowserUserAgentHostPolicyService` as the single application-default UA owner and feeds it
the locked Window Session Shell family before initial content/Web construction. Aira Default now resolves to the existing
mobile-compatible UA on the phone Shell and the existing desktop-compatible UA on the large-screen Shell. Explicit
mobile, desktop, custom, site, forced-compatibility, and compatibility-rule resolutions remain authoritative. The
controller-level `system_default` path still returns before `setCustomUserAgent()`, so this revision does not change
popup/OAuth ownership, controller attachment, fixed-slot identity, child return, or BFCache configuration.

## Authorized Rust-owned ad-block window-open scriptlet authority

On 2026-07-29 and 2026-07-30 the user explicitly authorized the narrow domain-scoped Window-Open exception required to
execute active `no-window-open-if` rules. The original implementation selected rules and generated a `window.open` proxy
in `AdBlockScriptletRuntimeScriptService`. After the accepted `adblock-rust 0.13.2` authority promotion, that ArkTS
runtime had no production consumer and was retired on 2026-08-14 rather than retained as a second scriptlet engine.

The same behavior now has one authority. The Rust engine builds subscriptions with `RuleTypes::All`, loads the pinned
Brave resource snapshot, and uses `Engine::url_cosmetic_resources()` to apply subscription domain and exception
semantics and expand the selected scriptlet resources. `AdBlockDocumentStartCoordinator` first applies Aira's
profile-scoped site exception, then passes only Rust's final `injected_script` text to the ArkWeb document-start execution
adapter. The Rust resource loader preserves the accepted AdGuard legacy `0/1, pattern` argument behavior by patching
only the pinned `prevent-window-open.js` resource before `Engine::use_resources()`.

This exception still runs before an ad popup reaches ArkWeb's native Window-Open event path. It does not consume or
synthesize ArkWeb popup events, create or attach a `WebviewController`, replay popup URLs, change fixed Hosted Web slots,
alter opener-aware child return, or modify BFCache and user-agent policy. Pages without a Rust-selected matching rule
retain the upstream resource's ordinary `window.open` path. The guard protects the exact Rust resource owner and ArkWeb
document-start handoff hashes and forbids restoring the retired ArkTS subscription scriptlet matcher/runtime. A static
guard or scriptlet smoke does not authorize broader changes to the native Window-Open owners.

## Authorized host-UA compatibility catalog revision

On 2026-07-29 the user explicitly authorized replacing the Google-specific host-UA method with a maintainable
compatibility catalog while keeping Google as the only initial rule. `BrowserUserAgentHostPolicyService` remains the sole
ArkWeb application/host UA execution owner. Its subordinate `BrowserUserAgentHostPolicyCatalog` separates stable concrete
UA profiles from evidence-linked explicit-host rules, validates rule metadata, rejects duplicate host assignments, and
resolves every profile as a complete host group before `setUserAgentForHosts` is called.

This architecture revision does not change Google identity: mobile `www.google.com` continues using
`AIRA_COMPAT_MOBILE_USER_AGENT`, while the desktop application family applies the same profile with an empty host list to
clear the mobile exception. No wildcard or inferred subdomain matching is introduced. Controller custom UA, explicit site
rules, Aira app UA, ArkWeb-original behavior, popup/OAuth ownership, fixed Hosted Web slots, child return, and BFCache
configuration are unchanged. Future catalog entries require Aira-specific reproduction and verification; upstream
browser rules are candidates, not shipping policy.

The same revision retires the unverified controller-level Bing, Microsoft, MSN, and CNN compatibility entries. The legacy
unsupported-title recovery entry point remains callable but cannot promote page text into a controller UA override. This
keeps Google as the only built-in shipping host exception and makes the typed catalog the only source for future built-in
host rules; explicit user site/custom UA choices remain separate and authoritative.

## Authorized physical-device User-Agent family revision

On 2026-08-10 the user explicitly authorized correcting the Aira Default identity for physical tablets. This revision
supersedes the previous Shell-family-to-UA mapping: touch versus desktop Shell selection is Aira presentation state and
must not decide the physical device's default web identity. `BrowserUserAgentService` owns the mapping from the Window
Session's already-detected form factor to the application family, while `BrowserUserAgentHostPolicyService` remains the
sole ArkWeb application/host UA execution owner.

The current semantic mapping is physical phone to `mobile`, physical tablet to a dedicated `tablet` family, and physical
`2in1` or PC to `desktop`. Tablet touch, auto-pointer, and desktop interface modes all retain the tablet family. The
tablet family's concrete Aira Default identity is the same desktop-compatible UA used by the desktop family, including
desktop Client Hints metadata, because a standard Android tablet UA without `Mobile` still routes important sites to
their phone experience.

This choice matches inspected Huawei Browser 6.1.1 HAP behavior rather than inventing an unverified `Tablet` token. Its
`UserInterfaceUtils.isMobileUi()` returns true only for phones, while `isPcUi()` returns true for PC or tablet;
`DataUpdateManager` therefore selects `pc_user_agent_cfg` for tablets, and `UserAgentLogic.getHarmonyOSUaContent()`
selects `COMPUTER_BROWSER_VERSION` on the tablet/PC branch. This reverse-engineered product evidence is not a Huawei
public API guarantee, but it provides a deterministic compatibility model for Aira. Explicit per-tab desktop/mobile
requests, presets, custom identities, exact-Origin site identities, ArkWeb-original selection, and the verified
mobile-only Google host exception keep their existing priority and scope.

This revision changes neither controller-level system-default handling nor the frozen Window-Open, popup/OAuth,
fixed Hosted Web, child-return, or BFCache contracts. A fresh controller on the system-default resolution path still
avoids `setCustomUserAgent()`; only the application-level Aira Default selected before navigation is device-specific.

## Authorized Hosted Web orientation geometry revision

On 2026-07-30 the user explicitly authorized a protected Hosted Web change for a physical-phone video-takeover rotation
failure. A first authorized attempt called `BuilderNode.updateConfiguration()` when system direction changed. True-device
acceptance disproved that hypothesis: the call ran for every direction change, yet ArkWeb still received `1320x1320` on
the portrait transition and `2848x2849` on the landscape transition before the correct dimensions arrived.

The confirmed layout cause is the Web host combining its parent's immediately updated width with the previous
orientation's numeric `webViewportPresentation.hostHeightPx` for one ArkUI pass. `BrowserWebViewportSurfaceHost` now owns
the outer Web geometry and presentation modifiers. During an active native video takeover it uses parent-relative
`100%` height, so width and height are both resolved from the same parent layout transaction; outside takeover it keeps
the existing keyboard-aware numeric host height.

`BrowserShellPage.ets` only forwards the active-takeover fact into that non-page owner, and the previous page-owned host
height, opacity, scale, blur, color, and hit-test bindings were extracted with it. The fixed per-tab slot, BuilderNode,
WebviewController identity and attachment, URL, popup/OAuth ownership, and BFCache configuration are unchanged. The guard
pins the new surface host and takeover coordinator shape. This static revision proves only the authorized structure;
Nivod portrait/landscape/Back acceptance and the full Window-Open/BFCache device matrix remain required before release
acceptance.

True-device build `1000580` then disproved parent-relative height as a complete repair: ArkWeb still crossed a square
intermediate viewport, reached the correct final Surface, and continued swapping before the picture became persistently
black. The media takeover coordinator therefore no longer calls `enter_live_presentation` twice after a manual direction
request. The injected presentation already owns resize, orientation, visual-viewport, and watchdog refreshes; repeated
entry after the final Surface exists can reapply the promoted video/backdrop composition at the wrong point in ArkWeb's
rotation transaction. This revision does not change controller identity, Hosted Web attachment, tab slots, URL state,
popup ownership, or BFCache behavior, and remains subject to Nivod true-device acceptance.

True-device build `1000587` confirmed the accepted rotation contract after a clean ArkTS rebuild: the initial takeover
issued one `enter_live_presentation`, while both manual direction changes issued none. The later bounded exit-settle
experiment did not repair Back restoration and was removed at the user's request. Exit/Back restoration is not part of
this accepted revision; the guard pins only the parent-relative active-takeover host and the absence of the disproved
post-rotation delayed re-entry path.

The direct device installer now carries amendment ID `2026-07-30-hosted-web-orientation-geometry`. The guard accepts that
ID only while the changed protected-path set is exactly `BrowserWebViewportSurfaceHost.ets`, this ADR, and the guard
itself, and while both the Web surface host and media-takeover coordinator content hashes match the accepted revisions
recorded by the guard. This is a narrow installation authorization for the user-approved orientation repair, not a
general bypass: any further protected-file change still fails until separately authorized and truthfully recorded.

## Authorized Large-Screen parent-relative Web viewport geometry revision

On 2026-08-11 the user explicitly reported and authorized fixing a Large-Screen browser-shell defect where every Web
document extended below the visible window and its bottom remained unreachable at maximum scroll. The Large-Screen
adapter already reserves fixed tab, navigation, and optional bookmark chrome before mounting the Web surface in the
remaining weighted stage, but the shared Web renderer still applied the Phone shell's numeric full-root host and content
heights inside that smaller parent.

`BrowserWebViewportCoordinator` now projects whether the active Web surface must follow its parent height.
`BrowserWebViewportSurfaceHost` renders the complete projected geometry: both its outer host and inner ArkWeb content use
the same parent-relative height for the Large-Screen shell and native video takeover, while the Phone shell keeps its
existing keyboard-aware numeric host height, top inset, and content height. `BrowserShellPage.ets` only supplies current
shell/takeover facts, mounts the top chrome, Web content, loading progress, and find overlay builders, and no longer owns
the duplicated viewport Stack/Column geometry.

This amendment changes no fixed per-tab slot, NodeContainer, BuilderNode, WebviewController, controller attachment,
Window-Open/OAuth, URL, navigation, background residency, or BFCache behavior. The protected guard records only the
viewport renderer hash and this exact documented amendment. A signed build and user-operated Large-Screen bottom-of-page,
window-resize, tab-switch, fullscreen, and phone fixed-bottom-page checks remain the acceptance boundary.

## Authorized exact-Origin browsing-identity revision

On 2026-08-08 the user explicitly authorized changing only `BrowserUserAgentService.ets`,
`BrowserUserAgentRuntimeService.ets`, this ADR, and the Window-Open guard so a saved exact HTTP/HTTPS Origin may select a
Browsing Identity from the existing global catalog. Resolution is policy-only: current-tab temporary identity wins,
then the exact Origin, then an explicit global identity, and finally Aira Default compatibility behavior. Scheme and
effective port are part of the target; host fallback and inferred subdomain matching are not part of this site-setting
path. The identity chosen for a navigation remains unchanged through its redirect chain; a later explicit navigation or
reload resolves again.

A fresh Controller resolving to ArkWeb Original or another system-default result still returns before
`setCustomUserAgent()`. If Aira previously applied a Controller-level custom UA and that same Controller later resolves
to the system default, the runtime may write the correct default UA string back to that Controller. This restores the
observable UA string only: it does not claim to clear ArkWeb's custom-UA flag, restore BFCache eligibility, recreate the
Controller, replay a URL, or recover native system-default status. Natural Controller recreation is the only path back
to an untouched system-default runtime.

This amendment does not change popup/OAuth event ownership, Controller attachment, fixed Hosted Web slots, opener-aware
child return, URL replay prohibitions, or BFCache options. Those invariants and the full user-operated Window-Open matrix
remain frozen and required.

The user then explicitly authorized removing the obsolete host-scoped `BrowserUserAgentSiteRule` compatibility pipeline.
`BrowserUserAgentService` no longer accepts or resolves legacy site-rule inputs; exact-Origin Saved Site Settings remain
the only persistent per-site browsing-identity policy. The Controller execution path in
`BrowserUserAgentRuntimeService` is unchanged, as are temporary-identity precedence, forced host compatibility, global
identity resolution, popup/OAuth ownership, fixed slots, child return, and BFCache behavior. The guard pins the cleaned
policy hash and the unchanged runtime hash for this authorized cleanup.

## Authorized Web security runtime controls revision

On 2026-08-09 the user explicitly authorized the protected Hosted Web changes required to ship HTTPS-first navigation,
ArkWeb safe browsing, and global plus exact-Origin JavaScript policy. The existing main-frame navigation interception
owner composes HTTPS-first after special-navigation and content-filtering decisions, while the existing page-lifecycle
owner closes successful upgrade/fallback attempts and handles bounded connection/protocol failure fallback. Only
main-frame GET requests are upgraded; loopback origins are excluded. An attempted HTTPS upgrade may fall back once to
the original HTTP URL only for bounded connection/protocol-unavailable failures, never for certificate failures.
`BrowserWebHostCoordinator.ets` only resolves the Hosted Web security configuration before construction or refresh;
`HostedWebNode.ets` applies the resolved JavaScript attribute and ArkWeb safe-browsing setting to the existing per-tab
Web component and presents ArkWeb's `THREAT_WARNING` result through the native prompt surface.

The existing `BrowserWindowOpenApplicationCoordinator` remains the popup/OAuth narrative owner. Pending popup events
are still consumed before Hosted Web construction, the same controller remains bound to the same fixed per-tab slot,
child exit remains opener-aware, and no delayed URL replay, fallback Web host, controller replacement recovery, BFCache
option change, or background-retention exception is introduced. The guard pins both protected implementation hashes.
Static guards and the signed HAP build pass for this revision; the full user-operated Window-Open/BFCache device matrix
and clean device-log criteria remain required before declaring release acceptance.

## Authorized native-default UA / BFCache restoration revision

On 2026-08-12 the user explicitly authorized repairing Back restoration after a true-device reproduction showed that
the application-level Aira Default UA made ArkWeb reject BFCache. The original Android-shaped Aira Default policy was
introduced for compatibility-sensitive sites, but ArkWeb's runtime reported `hasDiffUserAgent:1`, `canStore:0`, and
`fromBFCache:0` for ordinary dynamic-list navigation while the same-controller tab and Web identity remained stable.
The resulting full document reload allowed dynamic content to shift the old scroll position.

`BrowserUserAgentHostPolicyService` no longer calls `setAppCustomUserAgent` for ordinary Aira Default settings, and the
startup path no longer invokes its application-level `setUserAgentForHosts` catalog. Fresh controllers therefore retain
ArkWeb's untouched native system-default identity. The typed host catalog remains as an inert, evidence-linked policy
record; any future reactivation requires separate true-device BFCache verification. Explicit presets, custom identities,
exact-Origin settings, and temporary per-tab identities continue through the existing controller-level resolution path
and keep their deliberate compatibility tradeoff.

The same ordinary system-default path leaves ArkWeb's process-global User-Agent Client Hints switch disabled and does not
apply controller metadata. The repaired USB-phone run then recorded `CanEnterBFCache canStore:1`, `hasDiffUserAgent:0`,
`fromBFCache:1`, and `OnRestoreFromBackForwardCache`; the prior standard-mode run had enabled Client Hints globally and
still recorded `hasDiffUserAgent:1`. Enhanced tracking protection continues to own the explicit disabled setting, while
custom/preset identities may opt into their compatibility metadata deliberately.

This is a UA-policy repair only. It does not add URL replay, JavaScript scroll restoration, screenshot/cover recovery,
controller recreation, or any change to native same-controller `backward()` or BFCache configuration. Because the public
SDK does not document a clear/reset API for an already-applied `setAppCustomUserAgent`, clean verification must start
from a fresh process after installation; the app deliberately does not write a copied default string as a substitute,
because that remains a custom-UA override.

## Authorized verified Host-UA compatibility restoration revision

On 2026-08-13 the user reported that Google again rejected Aira as unsupported after the native-default UA / BFCache
repair and explicitly authorized restoring site-specific UA compatibility with a maintainable architecture. The
installed official ArkWeb SDK exposes only the application-scoped static
`WebviewController.setUserAgentForHosts(userAgent, hosts)` API for Host-UA policy; it exposes no Controller-instance
Host-UA method. Its documented priority remains Controller custom UA, Host-UA, app custom UA, then ArkWeb default UA.

`BrowserUserAgentHostPolicyService` therefore resumes applying every complete profile group resolved by the existing
evidence-gated `BrowserUserAgentHostPolicyCatalog` when UA settings initialize, change, or reconcile to a physical device
family. It still never calls `setAppCustomUserAgent`: ordinary nonmatching pages fall through to ArkWeb's untouched native
default identity. The only built-in rule remains the previously verified mobile `www.google.com` exception. Explicit
custom/preset, exact-Origin, and temporary-tab identities keep their higher Controller-level priority and existing
tradeoff. Reapplying one concrete Host-UA always sends that profile's complete host list because ArkWeb replaces the
previous list for the same UA. The policy owner derives one deterministic key from those complete groups and skips
unchanged reapplication during repeated Window Presentation reconciliation; a device-family or catalog change produces a
different key and replays the complete groups.

The unused `WebControllerBootstrapper` adapter that modeled an unverified instance method accepting
`Record<host, UA>` has been removed. Future rules enter only through the typed catalog after an Aira-specific reproduction
proves a stable profile fixes an exact Host. Wildcards, inferred subdomains, title sniffing, arbitrary per-rule UA strings,
and navigation-time Controller overrides are not built-in compatibility mechanisms. Each addition must record evidence
metadata and pass the relevant site flow plus the ordinary IT之家 Back/BFCache and Window-Open/OAuth device matrix.

This revision does not restore app-wide custom UA, enable Client Hints for system-default pages, change Controller
attachment, recreate or swap Controllers, replay URLs, restore scroll from application state, or alter native Back and
BFCache options. Huawei does not document whether Host-UA entries themselves remain BFCache-eligible on matching history
entries, so Google-specific BFCache behavior is a true-device acceptance fact rather than a claimed platform guarantee.

## Authorized mandatory Google identity revision

On 2026-08-17 the user explicitly authorized making the verified Google compatibility identity mandatory on every device
family. The Host-UA catalog now contains two evidence-linked profiles for the exact `www.google.com` host: the verified
Android-shaped Aira compatibility UA for `mobile`, and the verified Windows Chrome UA for `tablet` and `desktop` large-
screen families.

Because ArkWeb gives Controller-level `setCustomUserAgent()` priority over Host-UA, the catalog alone cannot enforce this
product rule. `BrowserUserAgentHostPolicyService` exposes the matching mandatory identity to the existing
`BrowserUserAgentActionCoordinator`, and `BrowserUserAgentService` resolves that identity before temporary-tab, exact-
Origin, global, or desktop-site choices. Site customization and temporary desktop/mobile controls remain ordinary user
controls: choices can be selected, displayed, and persisted without revealing the mandatory compatibility rule. Those
choices remain valid configuration but cannot change the effective Google runtime UA while the exact-host rule matches.

The rule is exact-host only; it does not infer regional Google domains or subdomains. Enhanced anti-tracking continues to
disable Client Hints and third-party cookies according to the existing privacy policy. No app-wide custom UA, Controller
recreation, URL replay, page-title promotion, or screenshot/device capture is introduced. A true-device acceptance pass
still needs to confirm Google search, OAuth, redirects, BFCache, and the large-screen layout with the Windows Chrome UA.

## Authorized YouTube and signed cloud Host-UA revision (historical, superseded)

On 2026-08-17 the user explicitly authorized extending the same opaque mandatory compatibility behavior to YouTube and
making future exact-host additions remotely controllable through `api.aira.cool`. The built-in offline snapshot now maps
`youtube.com`, `www.youtube.com`, `m.youtube.com`, `music.youtube.com`, and `youtu.be` to the Android compatibility
Profile on mobile and the Windows Chrome compatibility Profile on tablet/desktop. Google and YouTube built-ins cannot be
deleted, weakened, or replaced by the remote snapshot.

`BrowserUserAgentHostPolicyService` remains the single narrative and ArkWeb execution owner. Its Host-UA application and
the final mandatory runtime resolver now share one `BrowserUserAgentHostPolicyCatalog` snapshot. Global settings,
exact-Origin settings, and temporary mobile/desktop choices continue to save and render normally; no setting or message
reveals the compatibility override, while the mandatory match still resolves before every user-controlled identity.

The subordinate remote catalog fetches one complete RS256-signed envelope from
`GET /ua-host-policy/v1/manifest`, loads an app-private last-known-good cache before initial UA application, and refreshes
on deferred startup or foreground entry without sending the current page URL or Host. The signed schema accepts only
exact Hosts, the compiled `aira_android_compat` / `aira_desktop_compat` Profile IDs, their compatible application
families, bounded evidence metadata, and a bounded validity window. It rejects wildcards, arbitrary UA strings,
executable code, revision rollback, same-revision content reuse, built-in conflicts, and family/Host conflicts.

ArkWeb documents that reapplying `setUserAgentForHosts(userAgent, hosts)` replaces that concrete UA's previous complete
Host list. Remote activation, removal, and expiry therefore resolve and replay every Profile group, including an empty
group, so a removed remote Host does not remain assigned. Signature, schema, network, version, or expiry failure keeps
the built-ins and the last still-valid signed snapshot; it never broadens matching or falls back to an unsigned rule.
The remote Catalog schedules the exact `expiresAt` boundary while the process remains alive, segments waits beyond the
platform timer limit, and rechecks immediately on foreground. Crossing expiry therefore clears the remote snapshot and
replays both complete Profile groups even when the App stayed continuously foregrounded and no refresh became due.
This amendment changes no Controller construction/attachment, Window-Open/OAuth, URL replay, BFCache, privacy mode,
Client Hints, cookie, or UI behavior.

## Authorized unified cloud Host-UA and Admin maintenance revision (historical, superseded)

On 2026-08-17 the user explicitly replaced the preceding built-in-plus-remote merge contract with one complete signed
cloud snapshot for Google, YouTube, and every future managed Host. Google and YouTube are ordinary entries in schema-v2
`ua-host-policy/manifest.json` and the protected Admin console maintains the same full rule collection. The server accepts
only the two compiled compatibility Profile IDs, derives their valid application families, generates publication metadata,
increments revision under optimistic concurrency, atomically replaces the authoring snapshot, and confirms signing before
reporting success. Both the signer and App require the exact complete family set for each Profile: Android maps only to
`mobile`, while desktop compatibility maps to both `tablet` and `desktop`. It cannot accept arbitrary UA strings,
wildcards, executable content, request headers, or cookies.

`BrowserUserAgentHostPolicyCatalog` now selects exactly one complete snapshot: a still-valid signed cloud snapshot, or the
same-schema bundled fallback when no valid signed snapshot exists. It never merges the two. The fallback preserves first
launch and offline Google/YouTube compatibility, but has no separate runtime priority and cannot override a valid cloud
snapshot. Schema v2 and a v2 cache filename prevent a cached empty schema-v1 additive snapshot from becoming an
authoritative replacement during upgrade. Existing Apps reject schema v2 and retain their previous built-in behavior;
updated Apps accept the full cloud snapshot after signature, expiry, minimum-version, exact-schema, and rollback checks.

All active rules remain mandatory at runtime and resolve before user global, exact-Origin, or temporary UA choices while
remaining absent from ordinary App UI. A managed Host still has exactly two compiled cloud Profiles: mobile and
desktop. The Policy Snapshot owner derives a requested shape from the current-tab choice, exact-Origin choice, explicit
global choice, or (for Follow Global/default) the physical application family, then selects the matching cloud Profile
as the mandatory winner. Windows Chrome, macOS Safari, and other user-facing desktop choices therefore remain opaque
shape intent; their concrete UA strings are never sent to a managed Host. Snapshot activation, expiry, and fallback
replay both complete ArkWeb Profile groups so removed Hosts do not remain registered. This revision changes no signed
schema, Controller construction, Window-Open/OAuth, URL replay, BFCache, privacy, Client Hints, cookie, or
browsing-history behavior.

## Authorized managed Host shape-selection revision

On 2026-08-21 the user clarified that the cloud Host-UA rule remains the highest-priority and user-invisible policy,
but its two fixed cloud identities are the only effective UA shapes. The client now resolves the requested cloud shape
before applying mandatory Host precedence: an explicit current-tab or exact-Origin identity maps by presentation mode,
an explicit browser-wide choice maps by its selected mode, and Follow Global/default falls back to the physical device
family. The mandatory candidate then supplies the corresponding cloud UA and wins the final decision. This lets a phone
request the cloud desktop Profile and a large-screen device request the cloud mobile Profile without exposing or
persisting a separate cloud identity, changing the signed manifest schema, or allowing arbitrary UA text for managed
Hosts.

## Authorized immediate Host-UA publication revision (historical, superseded)

On 2026-08-17 the user explicitly required a manually published Host-UA revision to reach online clients promptly. The
UA manifest service now exposes a global revision watch and wakes its bounded long-poll waiters only after an Admin
publication has atomically persisted and successfully signed the new complete snapshot. Foreground Apps keep that watch
active without sending a current page URL or Host; a higher revision forces a manifest fetch that bypasses the ordinary
30-minute refresh gate while retaining the same signature, schema, expiry, minimum-version, and rollback checks.

`BrowserUserAgentHostPolicyRemoteCatalog` remains the single remote-distribution lifecycle owner. It cancels both manifest
and watch requests on background, restarts the watch after foreground/cache readiness, and retries through the existing
periodic refresh fallback when watch transport fails. A file-published higher revision is discovered at the next bounded
watch completion even when it has no Admin wake signal. Failed or rejected updates never replace the last still-valid
snapshot.

Activation updates the complete Host-UA map and mandatory resolver for subsequent navigation, but it does not reload an
already displayed page or replay an in-flight request. This preserves form, POST, redirect, media, Window-Open/OAuth, and
BFCache behavior; a user reload or later navigation receives the newly activated policy.

## Authorized package-owned Host-UA revision

On 2026-09-01 the open-source release preparation superseded the remote Host-UA distribution revisions above. The
complete Google and YouTube compatibility catalog now ships in the App package and is validated synchronously by
`BrowserUserAgentHostPolicyCatalog`; package signing is the integrity boundary. The temporary `httpbingo.org` test rule
was removed before the bundled catalog became authoritative.

`BrowserUserAgentHostPolicyRemoteCatalog`, its manifest cache, the `api.aira.cool` manifest/watch endpoints, signature
envelope, expiry timer, deferred refresh, and foreground/background watch wiring are deleted. Startup still initializes
the user's UA settings and applies the complete packaged profile groups through
`BrowserUserAgentHostPolicyService`. Mandatory exact-host precedence, requested mobile/desktop shape selection, ArkWeb
application, Controller ownership, Window-Open/OAuth, URL replay, BFCache, privacy, Client Hints, cookie, and browsing
history behavior are unchanged. Catalog changes now require a source change, review, signed App build, and release.

## Authorized Page Behavior bridge repair revision

On 2026-08-13 the user reported that the native Video Assistant entry no longer appeared on any site, including
Bilibili, and explicitly authorized repairing the diagnosed Hosted Web bridge regression. Non-visual device logs proved
that media discovery still found seven video candidates and ArkWeb observed a native video source, while Page Behavior
published no playing event or Web-live reachability evidence. The regression began when the 2026-08-11 userscript repair
folded Page Behavior into a unified declarative proxy and made the document-start alias give up after twenty zero-delay
retries.

`HostedWebNodeController` now owns one stable `__airaPageBehaviorNativeBridge` wrapper, rebinds only its signal callback
when Hosted config updates, registers it after the controller is attached and before the external attachment callback
starts the first real page load, and removes it only when the controller changes or the Hosted node is disposed. The
document-start playback observer continues to call the same bridge name, but the unified userscript alias script no
longer owns or retries that name. This restores the previous deterministic Page Behavior lifecycle without reverting the
userscript storage journal, stable shared userscript proxy, or other unified bridge methods.

This amendment does not change pending-popup consumption, controller construction or attachment order, fixed per-tab
Hosted Web slots, opener-aware child return, URL replay prohibitions, user-agent policy, background retention, or BFCache
configuration. The guard pins the repaired Hosted node hash and requires Page Behavior registration before the external
attachment callback while forbidding a document-start assignment to its bridge name. Static verification and a signed
HAP build do not replace the retained true-device video repro or the full user-operated Window-Open/BFCache matrix before
release acceptance.

## Authorized Rust-only ArkWeb ad-block retirement

On 2026-08-14 the user explicitly authorized fixing every omission found by the post-delivery ad-block authority audit.
The audit found that older releases had persisted custom `AdsBlockManager` rules and that the shared controller bootstrap
could still call `enableAdsBlock(true)`. Active-controller finalization later disabled the ArkWeb filter, but background
attachments returned before that step and could therefore keep ArkWeb's independent matcher enabled beside Rust.

`WebControllerBootstrapper` is now the single ArkWeb switch owner and calls `enableAdsBlock(false)` before applying any
other attached-controller configuration. The page-derived enable flag, later ad-block-coordinator toggle, Hosted Web
`onAdsBlocked` callback, callback propagation, native evidence set, and `网页引擎拦截` statistics category are retired.
The common bootstrap runs for active, background, restored, and Window-Open controllers, so persisted ArkWeb rules cannot
become a second production authority. `BrowserWebLoadRuntimeCoordinator` now constructs the remaining UA/download
bootstrap configuration; `BrowserShellPage.ets` only forwards current page facts and is smaller in the touched area.

This amendment does not alter pending-popup consumption, controller construction or attachment order, fixed per-tab
Hosted Web identity, opener-aware child return, system-default UA behavior, BFCache configuration, or background-discard
policy. The guard pins the three protected implementation hashes and rejects any other production `enableAdsBlock`,
`AdsBlockManager`, or `onAdsBlocked` path. Static checks and a signed HAP build still do not replace the user-operated
Window-Open/BFCache matrix required before release acceptance.

## Authorized Browsing Identity lifecycle repair revision

On 2026-08-16 the user explicitly authorized repairing the complete UA architecture after non-default identities were
correlated with broken element inspection, lost/reloaded page state, and Back returning directly to Home. Existing
true-device evidence already showed that a Controller custom UA disables ArkWeb BFCache. DevEco Knowledge additionally
confirmed that `setCustomUserAgent()` is Controller-lifetime state, should be applied after attachment and before
`loadUrl()`, and may refresh a document if changed while loading. Huawei does not document a clear-to-native operation
or a public per-navigation-entry desktop/mobile identity API.

`BrowserUserAgentRuntimeService` is now the sole Controller Browsing Identity execution owner. It records an explicit
native/custom binding for each Controller and freezes a complete profile before app loads, allowed main-frame Web
requests, and native Back/Forward. The immutable plan includes the UA string mode, known Client Hints metadata mode,
mobile/desktop presentation intent, ArkWeb scope capability, and compatibility notice; redirect interception reuses the
first plan until the main-frame entry commits, while a new user-gesture navigation supersedes an in-flight plan. Failed
UA application never leaves an active plan, and load-command failure, Back/Forward-command failure, main-frame failure,
and Hosted runtime release all cancel abandoned plans. At commit, the owner associates the Controller's actually applied
profile—not an unsupported requested transition—with the current native BackForwardList index so a later Back/Forward
can recover a truthful entry plan instead of re-resolving mutable settings.

A fresh system-default Controller still returns before `setCustomUserAgent()` and remains eligible for native BFCache.
Once a Controller has taken the custom path, a later system-default plan returns `identity_transition_required`: it does
not write a copied default string, does not claim to clear ArkWeb's custom-UA flag, and does not recreate the Controller.
The navigation may continue under the current Controller identity so native history remains available; a naturally new
Controller is the only supported return to the untouched native identity until Huawei documents a lossless clear or
state-preserving runtime transition. This rule explicitly supersedes the earlier exact-Origin amendment's allowance to
write the observable default string back to an already-customized Controller. The shared `WebControllerBootstrapper`
continues to own common attached-controller configuration, including disabling ArkWeb's parallel ad filter, but no
longer reads, infers, or writes browsing identity.

An unsupported transition is not reported as a successful current-tab switch. Direct UA actions keep the live document
and native history intact, skip the pointless reload, and explain that the saved selection takes effect after Web runtime
recreation. Other navigation paths may continue under the Controller's actual identity, but emit one deferred-transition
notice per identity pair. Fresh Controller attachment may apply the selected identity; ordinary reattachment and load
state synchronization cannot mutate an already-bound Controller or overwrite the frozen plan. Controller bindings are
weak, and Hosted runtime disposal releases per-tab binding/active-plan state while retaining only the pure-data committed
entry ledger needed by a possible state restore.

`page_begin` is now observation-only. It never compares UA text to trigger a Controller replacement, so it cannot
discard the native BackForwardList and turn terminal Back into a tab close/Home transition. The shallow
`BrowserUserAgentControllerLifecycleCoordinator` and its `user_agent_changed` replacement/reload path are retired.
Background preview attachment now forwards the real tab id to the same identity owner instead of resolving against the
active tab.

The process-static Client Hints switch remains owned exclusively by the application privacy policy. Per-tab, exact-site,
and Controller identity resolution can prepare matching metadata, but cannot enable or disable the static switch.
At the time of this revision, Site/tab `Aira Default` meant the same untouched ArkWeb system identity as global
`Aira Default` on a fresh Controller. The later Android-compatible phone-default revision below supersedes that part of
the contract while retaining ArkWeb Original as the explicit native identity. Compatibility/custom identities retain
their documented BFCache and engine-fingerprint tradeoffs.
The temporary application-ownership diagnostic was removed after true-device acceptance confirmed the UA, native
Back/Forward, and element-inspection fixes.

Element inspection now mounts a modal ArkUI input shield exactly over the measured Hosted Web layer. The native layer
consumes touch and mouse activation before sending bounded local coordinates to the session owner; page script only
performs `elementFromPoint()` DOM description and highlight rendering, with no click/pointer/touch listeners or layout
knowledge about the native details sheet. This prevents a desktop page's earlier page-world listener from activating a
link underneath the inspector. Cross-origin iframe internals remain intentionally unavailable; the selectable result at
that boundary is the iframe element because ArkWeb exposes no public in-app DevTools node-picker.

This revision does not change pending-popup consumption, fixed Hosted Web slots, controller attachment identity,
opener-aware child return, native `backward()`, BFCache options, or URL replay prohibitions. Static guards and a signed
build prove only the implementation contract; user-operated true-device global/site/tab UA, Back, and element-selection
flows completed the acceptance boundary on 2026-08-16.

## Authorized immediate native-identity transition revision

On 2026-08-20 the user explicitly rejected the delayed custom-to-native action behavior and required Follow Default or
Mobile selection to take effect immediately without restoring the earlier Back/Forward regression. ArkWeb still exposes
no confirmed operation that clears a Controller-level `setCustomUserAgent()` override. Writing the default UA text back
would remain a custom identity and would again make BFCache report `hasDiffUserAgent:1`.

`BrowserUserAgentRuntimeTransitionCoordinator` now owns this explicit action transition. For a regular active Web tab it
serializes the live ArkWeb access stack, persists the payload through `WebStateSnapshotStore`, revalidates both the active
tab and an operation generation, commits the snapshot path with `runtimeState: restoring`, then releases the customized
Hosted runtime and installs a fresh Controller. Ordinary controller attachment applies the newly selected untouched
native identity before the existing snapshot restore flow restores the access stack. Because restoring the serialized
access stack does not re-request the restored current entry, the transition owner carries a one-shot, generation-bound
tab marker and calls the attached Controller's `refresh()` only after that UA-transition snapshot succeeds. This refresh
does not replay the URL or add a history entry; ordinary cold-start, tab-switch, and non-UA snapshot restores never use
the marker. Custom-to-custom actions keep the existing reload path. A superseding UA action or active-tab change
invalidates the pending transition before release.

The old customized Controller remains live when serialization or snapshot persistence fails. Session-ephemeral/private
tabs do not write this access stack to disk and retain the explicit delayed fallback. After old-runtime release, ordinary
runtime recovery owns any exceptional replacement failure; the action never writes a copied default string to the old
Controller. This revision does not add URL replay, JavaScript scroll restoration, a second Back/Forward owner, or a new
Controller-attachment path.

The protected guard fixes the privacy check and the `serialize -> persist -> restoring patch -> release -> replace ->
ordinary attach/restore -> one-shot current-entry refresh` order. Static guards and signed HAP builds passed on
2026-08-20. This is not true-device
acceptance: Desktop -> Follow Default, Desktop -> Mobile, multi-entry Back/Forward, dynamic-list position, SPA state,
private fallback, rapid repeated selection, popup/OAuth, and background/memory-pressure flows remain user-operated device
checks before release acceptance.

## Authorized UA-replacement fixed-slot generation repair

On 2026-08-20 the retained true-device diagnostic loop disproved both a missing native-UA transition and a missing
reload. During Desktop -> Follow Default, the old ArkWeb instance had WebId `1`; the replacement Controller had WebId
`2`, and both its Controller UA and page `navigator.userAgent` reported the mobile family before and after the one-shot
refresh. Snapshot restoration succeeded, the automatic refresh was issued, and a later user-operated reload was also
issued, while the user-visible surface remained the old desktop rendering.

The remaining mismatch was the fixed Hosted surface identity. `surfaceRevision` re-evaluated the existing fixed slot, but
the tab-id-only key allowed ArkUI to retain its previous `NodeContainer` after `BrowserWebHostCoordinator` had installed a
different `HostedWebNodeController` for the same tab. The coordinator exposes its already-owned per-tab Hosted node
generation through `BrowserHostedRuntimeSurfacePort`. The fixed-slot renderer now keys its `ForEach` directly by
`tab.id` plus that generation. A Controller/Hosted-node replacement therefore replaces the affected fixed-slot node and
rebinds the new native container; ordinary active/background visibility changes, tab switching, and configuration updates
keep the generation and mounted ArkWeb identity stable.

This repair does not create another runtime owner, reparent a live unchanged Web, replay a URL, change snapshot contents,
or change popup/OAuth, child-return, background-residency, and BFCache policy. The protected guard requires the direct
`tab.id:generation` key and owner-to-port-to-shell generation wiring together. Static build and guard verification do not
replace the pending true-device Desktop -> Follow Default, Desktop -> Mobile, ordinary Tab switching, and multi-entry
Back/Forward acceptance.

## Authorized Browsing Identity policy consolidation revision

On 2026-08-21 the user explicitly authorized consolidating global, exact-Origin, current-tab, and mandatory Host-UA
policy without changing the accepted Controller replacement or Hosted surface lifecycle. The previous
unsupported-title compatibility path was inert by construction: `shouldForceCompatibilityReload()` always returned
false, but its forced-Host state and recovery callbacks still formed a second apparent policy path. That path is now
deleted rather than represented in the consolidated model.

`BrowserBrowsingIdentityPolicyCoordinator` is the single owner that reads and privacy-filters current policy sources,
normalizes stored identity references, and builds one revision-identified Policy Snapshot. Private browsing snapshots do
not read regular Saved Site Setting entries. `BrowserBrowsingIdentityDecisionService` is pure and selects one immutable
Decision in this fixed order: mandatory Host, current-tab override, exact Origin, explicit global choice, Aira
compatibility, then the applicable default. Invalid identity references are recorded as unavailable evidence and skipped
without copying stale UA text or mutating persistence.

Every package-owned Host rule remains mandatory. Google, YouTube, and future reviewed managed Hosts therefore cannot be
replaced by Desktop, Mobile, Follow
Global, exact-Origin, or global raw UA choices. Those choices only select the mobile or desktop shape of the hidden
packaged Profile that remains the winning mandatory identity; the concrete user-facing preset string is never used for the
managed Host. A superseded user choice still saves and remains visible, but when the effective UA, Client Hints metadata,
and presentation fingerprint is unchanged it does not reload or rebuild the current runtime. The Action owner presents
user commands only; Web Load consumes the Policy owner directly and cannot assemble policy through Action.

The current-tab override remains session-local across Origin changes until Follow Global or tab close. Navigation
Runtime owns redirect affinity, the frozen Decision for an in-flight transaction, and the Decision associated with each
native history entry. Redirects and same-document navigation do not re-decide mid-transaction; Back/Forward restores the
entry-bound Decision. A new navigation or user reload evaluates a new Policy Snapshot. A package catalog change takes
effect after installing the new App version and remains non-disruptive for an already displayed page until a later
navigation or reload.

This revision changes no settings schema, Host matching rules, Client Hints execution behavior,
snapshot format, Controller construction or attachment, native-default transition sequence, Hosted generation key,
Window-Open/OAuth flow, URL replay prohibition, or BFCache configuration. `BrowserShellPage.ets` only wires the Policy
owner to Action and Web Load. The temporary UA diagnostics were removed after user acceptance on 2026-08-27.

## Authorized restore-time UA reentrancy repair revision

On 2026-08-23 the user explicitly authorized changing this frozen contract after two independent Aira `2.4.0 (1000338)`
production crashes showed the same native sequence across different devices, OpenHarmony/API versions, and ArkWeb Build
IDs. During `restoreWebState()`, ArkWeb entered `NavigationControllerImpl::LoadIfNecessary`, synchronously called Aira's
`onLoadIntercept`, and Aira called `setCustomUserAgent()`. ArkWeb's resulting `SetUserAgentOverride -> Reload` reentered
the pending navigation; one fault thread explicitly named `NavigationControllerImpl::ScopedPendingEntryReentrancyGuard`
before `SIGTRAP`.

`BrowserRuntimeLifecycleCoordinator` already resolves the active restore target from a non-empty `pendingUrl` or the
tab's persisted URL. Controller attachment now carries that immutable `targetUrl` directly into
`BrowserControllerAttachmentRuntimeCoordinator`, which applies the selected Browsing Identity before snapshot restore.
The attachment adapter and `BrowserShellPage.ets` no longer re-resolve the URL through nullish coalescing, which treated
the required-but-empty `pendingUrl` string as a valid result. `BrowserRuntimeLifecyclePort` uses the same non-empty rule
when synchronizing an active Controller.

`BrowserWebComponentController` now marks only the synchronous `restoreWebState()` call window. Main-frame callbacks
emitted from inside that window do not re-prepare Browsing Identity and therefore cannot call `setCustomUserAgent()`
while ArkWeb owns a pending restored entry. The fresh Controller was already bound from the lifecycle-owned target before
restore. Ordinary Web-initiated navigation keeps its previous identity preparation behavior, while app-owned pre-load
commands and fresh Controller attachment retain mutation authority before navigation or restore begins. Existing
Controller binding truth, system-default no-setter behavior, native history-entry plans, and the custom-to-native
replacement path remain unchanged.

This repair adds no Controller, URL replay, popup/OAuth owner, fixed Hosted slot, child-return path, BFCache option, or
background-retention exception. The temporary UA diagnostics were removed after user acceptance on 2026-08-27. The
contract guard pins the resolved-target handoff, the empty-string fallback, and the restore-time callback boundary. Static
guards and a signed HAP build do not replace user-operated restore, ordinary `_blank`, Google OAuth/child exit, native
Back/BFCache, WebApp/external-app, private-boundary, and background/memory-pressure acceptance before release.

## HTTPS-First server-downgrade loop repair

On 2026-08-27 device logs confirmed that an HTTPS endpoint redirecting to its matching HTTP URL could create an unbounded
navigation loop. The interception owner upgraded that HTTP URL again, ArkWeb cancelled the current main-frame navigation,
and the server repeated the downgrade about 10-12 times per second. The repeated main-frame cancellation and `LoadUrl`
work starved foreground input and continuously restarted the loading indicator.

`BrowserHttpsFirstNavigationService` now recognizes only the matching HTTP return of the current active upgrade attempt,
after the existing fallback executor has been attached and within the same Profile/privacy/data boundary. It converts
that proven server downgrade into the existing tab-local HTTP session grant, clears the attempt, and lets ArkWeb continue
the current HTTP navigation. The grant is not a persistent site exception: leaving the granted host/port or starting an
HTTPS navigation clears it through the existing session rules. Unrelated HTTP navigation, explicit HTTPS failure, TLS
certificate handling, user-confirmed persistent exceptions, popup ownership, Controller attachment, and BFCache remain
unchanged. User-operated device verification recorded one `registered` attempt followed by one
`server_downgrade_fallback`, with no repeated-upgrade signal; the temporary sampled diagnostic was then removed.

## Bing search BroadcastChannel BFCache compatibility repair

On 2026-08-27 a same-process physical-phone Back trace showed that Bing search initially passed ArkWeb's BFCache
eligibility check and emitted `OnEnterBFCache`, but ArkWeb evicted the entry 72 ms later with `No: blocklisted features:
requested broadcast channel permission`. The same `webId` and Hosted generation then returned with `fromBFCache:0`, and
the dynamically rebuilt result document changed height while ArkWeb restored its native history position. Aira source
does not use BroadcastChannel. The installed SDK exposes only `nativeEmbed` and `mediaTakeOver` as
`BackForwardCacheSupportedFeatures`, so there is no official application flag that relaxes this page feature.

`WebBackForwardCacheCoordinator` now owns a document-start compatibility rule limited to Bing's `/search` path on
`cn.bing.com` and `www.bing.com`. It preserves native BroadcastChannel behavior while the result page is active, tracks
channels created by that page, and closes them at the real `pagehide` boundary so ArkWeb can retain the history entry.
The rule does not affect other hosts, emulate native Back, replay a URL or scroll position, create a Controller, or
change BFCache size/TTL. Other page-owned exclusion reasons, including `Cache-Control: No-Store`, remain native ArkWeb
behavior and require separate evidence rather than a global Web API override.

The signed `2.4.3 (1000390)` physical-phone verification closed one Bing channel, returned with `fromBFCache:1`, and
emitted `OnRestoreFromBackForwardCache`; the user confirmed that the position looked correct. The low-noise
`[DEBUG-bfcache-broadcast-0827]` signal remains temporarily available for additional affected-site diagnosis and is not
an installation or protected-path blocker.

## Corrected physical-device default webpage identity revision

On 2026-08-27 a Shell-aligned default-UA revision incorrectly coupled Aira presentation state to website identity. An
expanded foldable or a phone using the Large-Screen Shell remained a physical `phone`, but the Shell mapping silently
changed ordinary pages to the Windows-Chrome desktop identity. Responsive sites then served their PC layout even though
the user had not requested a desktop page.

The corrected contract restores `detectedFormFactor` as the input to `BrowserUserAgentHostPolicyService`: physical phone
maps to `mobile`, physical tablet maps to `tablet`, and physical `2in1`/PC maps to `desktop`. Shell family, fold state,
pointer state, manual Touch/Desktop interface mode, and window width remain presentation inputs only. They must not
silently change the applicable default Browsing Identity.

The physical-phone applicable default uses the bounded Android-compatible Aira mobile identity even when that phone
renders a Large-Screen Shell. Physical tablet/desktop defaults retain the distinct internal `aira_default_desktop`
identity with the bounded Aira Windows-Chrome compatibility UA and known Client Hints metadata. Mandatory package-owned
Host policy, current-tab identity, exact-Origin identity, and explicit global choices retain their existing precedence
above the applicable default.

`BrowserUserAgentRuntimePolicyCoordinator` remains the runtime reaction owner for explicit global, current-tab, and
exact-Origin identity changes. Shell-only transitions on the same physical device no longer create an automatic UA
transition. A user can still request desktop or mobile pages through the existing website-version controls without
changing Shell composition.

## Restored Android-compatible physical-phone default revision

The first 2026-08-27 correction restored physical-device ownership but true-device user acceptance still failed on
`english.news.cn` and `dawenks.com`. A device-side HTTP/JavaScript probe proved that Aira sent ArkWeb's native
`Phone; OpenHarmony ... Mobile` UA at a correct 392 CSS-pixel viewport. Xinhua's shipped `XHOME.browser.isMobile`
implementation nevertheless checks only `/iPad|iPhone|Android|Windows Phone|Nokia/`, so it deterministically classified
that native OpenHarmony UA as desktop and skipped its `mobile/index.htm` redirect. The same probe passes with Aira's
existing Android-compatible mobile UA.

The physical-phone applicable default and the `aira_default` site/tab identity therefore resolve to
`AIRA_COMPAT_MOBILE_USER_AGENT` with matching Android/mobile Client Hints metadata. `arkweb_original` remains a distinct
explicit identity that leaves a fresh Controller untouched for sites where native engine identity, login verification,
or BFCache behavior matters. Desktop identities, physical tablet/PC defaults, exact-Origin/current-tab/global precedence,
and mandatory managed Host rules are unchanged.

This correction does not restore `setAppCustomUserAgent` and does not add a wildcard Host-UA policy. The existing
per-Controller Browsing Identity runtime applies the compatible default before navigation. ArkWeb may report
`hasDiffUserAgent:1` and reject native BFCache for those compatible-default entries; that is the accepted tradeoff for
making ordinary physical-phone browsing select mobile sites reliably. Explicit ArkWeb Original remains the user-visible
escape hatch when native BFCache eligibility is more important for a particular flow.

## Active Shell default revision

The foldable product contract supersedes the same-device Shell-only exception above: when a physical phone enters the
Large-Screen Shell through an expanded fold or the explicit Desktop interface simulation, its applicable default
Browsing Identity is the desktop compatibility identity; returning to the Phone Shell selects the Android-compatible
mobile identity. `EntryAbility` applies this Shell-derived family before publishing the Shell refresh, and the existing
Browsing Identity runtime then reloads or replaces only the active Web Controller as required. Explicit Host, tab,
exact-Origin, global, and user-selected identities remain higher priority. No site viewport, CSS breakpoint, DOM, or
layout behavior is changed by this revision.

## HTTPS-First confirmed HTTP presentation-host redirect repair

On 2026-08-28 the physical-phone repro for `http://www.dawenks.com/` showed that the user-confirmed HTTP load was issued
correctly, then the site redirected the main frame to `http://wap.dawenks.com/`. The existing tab-local HTTP session grant
was anchored to `www.dawenks.com:80`; it rejected the sibling `wap` host, registered a new intercepted-HTTP attempt, and
upgraded the redirect to `https://wap.dawenks.com/`. That HTTPS endpoint completed as the user-visible 404 page.

`BrowserHttpsFirstNavigationService` now lets an existing tab-local grant continue between the exact base host and the
fixed presentation aliases `www`, `wap`, `m`, and `mobile`, or between those aliases, when their remaining host is
identical. The existing scheme, effective-port, expiration, Profile, privacy-mode, and data-scope checks still apply.
Arbitrary sibling hosts do not match. The durable 15-day site exception remains keyed to the exact host and port the user
approved; following a presentation alias does not create another persistent exception.

The static contract pins the fixed alias set and base-host comparison. Build and static verification do not replace the
nonvisual true-device acceptance check: the same HTTP URL must reach `http://wap.dawenks.com/` without a new
`intercepted_http` attempt or an ArkWeb `https://wap.dawenks.com/` load.

## Authorized Shell refresh runtime-owner binding revision

On 2026-08-28 the foldable presentation repair moved Shell-profile refresh handling behind the existing
`BrowserUserAgentRuntimePolicyCoordinator`. `BrowserShellPresentationRefreshSignal` still publishes the revision through
the shared storage link so `BrowserShellPage` can reconcile its native/Web surface, but the page no longer assembles or
executes Browsing Identity policy in its storage watcher. The runtime coordinator binds and releases one listener with the
Shell page lifecycle and performs the single reconcile for each active Web tab. Native/Home tabs are explicitly skipped,
so a fold or window-profile change cannot turn a controller-less native route into a failed Web reload.

This keeps the existing EntryAbility ordering: the application-level Shell identity is observable before the refresh is
published. It changes only the event handoff owner and duplicate-trigger behavior; Controller construction/attachment,
fixed Hosted Web slots, popup/OAuth, URL state, and BFCache policy remain unchanged.

## Authorized source-linked manual-tab Back revision

On 2026-08-30 the user explicitly defined one terminal Back contract for website-created child tabs and links manually
opened from the Web context menu. Back first consumes the active tab's ArkWeb history. Only when that history is
unavailable does a source-linked tab close and activate its exact source tab; if the source no longer exists, the
existing Home fallback applies. A plain `+` tab remains source-less and does not select an arbitrary adjacent or
recently active tab.

Web context-menu foreground and background tabs now persist `openerTabId` with the distinct `web_context_menu` source.
They explicitly remain `openedByNewWindow: false`: source-linked terminal return is shared tab behavior, while native
ArkWeb popup/OAuth child ownership and opener-runtime retention remain exclusive to the existing `window_open` path.
This separation lets a manually opened child survive ordinary background discard/restore policy without being mistaken
for a live `window.opener` relationship.

Phone and Large-Screen Back affordances remain available on every non-Home tab: this lets the unified Back owner consume
transient state first, then ArkWeb history, then terminal tab return. A source-linked tab closes to its exact source;
a source-less tab uses the existing Home fallback. Large-Screen Back enters `BrowserMainBackCoordinator` directly so the
coordinator observes and consumes Large-Screen omnibox editing before any search-invocation cleanup can expose Web
history to that same click. Active omnibox editing also precedes Large-Screen native-workspace route history; otherwise
that native history keeps its existing priority. Phone chrome and system Back converge on the same coordinator before
Web history and the existing `BrowserTabCloseCoordinator` terminal path. The page only forwards the typed Back request
and binds the live Large-Screen editing fact; action-rejection presentation moved into the existing Root Bottom Panel
session owner, reducing page-owned logic. No URL replay, Controller, Web host, popup handoff, BFCache option, or
background-retention exception is introduced.

The source-linked terminal return is a visual-first close transaction. `BrowserTabCloseCoordinator` prepares the child
for terminal close, activates the surviving source tab while that tab is still present, removes the child in the same
synchronous state turn, and immediately synchronizes the active Hosted Web surface. Runtime release, snapshot/preview
removal, private-session cleanup, and clear-on-close work run only in the existing deferred cleanup tail. No asynchronous
cleanup may split source activation from child removal; otherwise `activeTabId` can temporarily name a removed tab and
expose the Web viewport backdrop as a blank frame. The shared close-transition helper applies active-tab state before its
animated tab-list mutation so active and background tab closes keep the same valid publication order.

The protected static guard pins context-menu lineage creation and persistence, page-history-first ordering, exact-source
terminal close, visual-first state publication and deferred cleanup, phone/Large-Screen availability, and unified
Large-Screen dispatch. Static guards and a signed build do not replace user-operated acceptance for context-menu
foreground/background tabs, same-tab second-level navigation, ordinary `_blank`, child with/without history, Google
OAuth completion/child exit, private boundary, and source-tab removal fallback.

## Change process

Window-Open/BFCache owners and adapters may be changed during ordinary in-scope feature, repair, diagnosis, or
architecture work. No protected-path approval, hash allowlist, amendment ID, or override environment variable is
required.

Contract changes still require all of the following:

1. Name the user-visible behavior and affected invariant before editing.
2. Keep one owner for pending popup consumption, attachment, child return, and BFCache lifecycle responsibilities.
3. Update the static guard and this ADR when the intended behavior changes; never weaken an assertion merely to hide an
   unintended regression.
4. Run the static guard, architecture guard, and signed build.
5. Run a proportional user-operated matrix selected from ordinary `_blank`, child with/without history, Google OAuth
   completion and child exit, IT之家 refreshed-list Back, WebApp/external-app behavior, private boundary, and
   background/memory pressure.
6. For the exercised paths, device logs must show no null NWeb, popup fallback/replay, opener reload, reparent warning,
   GSI failure, or background contract violation.

The detailed implementation and evidence remain in
`docs/aira-window-open-huawei-alignment-development-plan.md`,
`docs/aira-back-forward-huawei-alignment-plan.md`, and
`docs/research/huawei-window-open-deep-owner-alignment.md`.
