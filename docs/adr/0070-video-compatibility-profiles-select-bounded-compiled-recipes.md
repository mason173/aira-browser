# Video Compatibility Profiles Select Bounded Compiled Recipes

Accepted: 2026-08-08
Amended: 2026-08-09 — YouTube Acquisition Recipe authority cutover and known-scope XlPlayer migration
Status: Remote delivery superseded for current clients on 2026-09-01

## Package-owned catalog revision

Video Compatibility Profiles remain the bounded declarative selector for compiled Recipes, but the current App resolves
only the normalized packaged catalog. Manifest fetch, foreground watch, signature/envelope/version/expiry validation,
request policy, lifecycle policy, remote overlay, and app-private cache code are deleted. Profile changes require source
review and an App release. The private server endpoint remains temporarily for older clients and is not a dependency of
the current client.

The original decision below is retained as delivery-history context; its remote lifecycle is no longer current.

## Context

ADR-0059 reserves a future signed Video Compatibility Profile seam but explicitly names only attributed evidence,
heuristic suppression, and compiled observation strategies. Current site differences also include YouTube-specific media
acquisition and a Weibo-specific presentation choice. Leaving those differences outside the Profile seam would preserve
site-named branches across discovery and takeover, while allowing remote executable behavior would create a second,
unsafe takeover engine.

## Decision

A Video Compatibility Profile is purely declarative and may select only exact Video Compatibility Recipe identities
already compiled into the installed App. Recipes have three closed categories:

- an Observation Recipe contributes attributed structured or heuristic Media Evidence;
- an Acquisition Recipe produces and normalizes Media Resources but cannot select an Active Video Assistant Session;
- a Presentation Recipe configures only the execution of a Video Assistant Takeover Route that the existing resolution,
  reachability, route, and eligibility chain has independently established.

A Profile may also carry a strictly bounded set of reviewed CSS selectors for allowed media structures and attributes.
Selector evaluation stays local to its declared frame and origin scope, produces only attributed structured or heuristic
Media Evidence, and remains subject to App-owned structural quality gates. Profiles cannot carry XPath, regular
expressions, arbitrary attribute extraction, or selector fields that directly declare session, reachability, route, or
eligibility outcomes.

The first packaged Presentation Recipe is the normalized `preserve_surface` mode for `m.weibo.cn`. It runs in
read-only shadow mode only after the existing route authority has produced an executable `web_live` launch plan. Shadow
diagnostics compare only the sanitized Profile attribution and categorical current/recipe modes; they contain no URL,
resource, credential, or Private Browsing identity. The legacy hostname branch remains the production presentation
authority until the separate cutover decision.

The first packaged Acquisition Recipe is Bilibili play-info for the exact top-level host www.bilibili.com. It reads
only the established bounded play-info globals, normalizes selected DASH video/audio tracks or progressive segments into
site-neutral Media Resources, and labels each resource with fixed profile_acquisition provenance plus an App-side
observation timestamp. In this release it is shadow-only: output is held only for the current callback and summarized
without URLs, resource addresses, credentials, or Private Browsing identity. It does not write Media Evidence, candidates,
or a Session; the existing generic vendor_adapters deep probe and its scanBilibiliPlayInfo() path remain the production
resource authority until a later cutover decision. The generic deep probe marks only its current Bilibili output as an
ephemeral acquisition baseline; the opaque compiled capability compares that baseline with the Recipe and returns only
counts plus track/resource-identity equality facts for diagnostics. Shared discovery owners never receive or branch on
the Recipe identity. Every callback rechecks its captured generation, route epoch, Profile attribution, and current
top-level page URL before its sanitized summary can be emitted.

After the explicit true-device acceptance gate, the packaged YouTube Acquisition Recipe is the sole site-specific
YouTube Media Resource acquisition authority for Profile-matched routes. Its compiled capability owns bounded YouTube
URL/request matching, request access context, immediate/delayed/SPA scheduling, throttling, expected-media freshness,
extraction, and late-result rejection. `BrowserMediaDiscoveryCoordinator` projects each current report into ordinary
site-neutral Media Signals and progressive or paired-adaptive acquisition facts. The legacy peer YouTube coordinator,
candidate publisher, signal adapter, and `youtube_progressive` / `youtube_adaptive` generic candidate kinds are deleted;
there is no hidden named fallback. A signed disabled or unresolved YouTube Profile therefore restores only the complete
generic discovery engine. Session Resolution, Web-Live Control Reachability, Takeover Route, Entry Eligibility, failure
recovery, and resource actions retain their existing owners and do not receive Recipe identity. A Media Route Epoch
advance clears the route-scoped Resource Store and invalidates prior validation work, replacing the deleted
YouTube-identity cleanup with one site-neutral SPA freshness rule.

The packaged `xlplayer_lines` Acquisition Recipe applies only to the evidence-backed exact host `v.xl01.eu.cc`.
Its compiled module owns the `/lines` signature, same-origin request, bounded response cache, extraction precedence
`url3 -> tos -> m3u8 -> m3u8_2`, URL normalization, and Resource projection. Automatic page-end and SPA observation
starts the request asynchronously and performs one bounded follow-up after 900 milliseconds; explicit takeover launch
uses the existing synchronous page-runtime fallback and awaits its attributed report before the launch probe returns.
For an active
matching Profile, the compiled capability declares that it replaces the App-known generic deep-probe strategy
`vendor_adapters`, and the generic probe omits only that strategy. This declaration is compiled into the App: remote
Profile data cannot name or suppress a generic strategy. XlPlayer sites without a Profile continue to reuse the same
compiled runtime through `vendor_adapters` as a transitional generic fallback. A missing Recipe, unresolved Profile, or
signed disabled entry declares no replacement and therefore restores the complete generic probe automatically.
The cloud Catalog revision containing `xlplayer_lines` is gated to App version code 1000262 or newer so older clients
fail over to their packaged Catalog without attempting to interpret an unknown compiled Recipe identity.

No Recipe and no Profile may create, delete, overwrite, or downgrade direct evidence; select an Active Video Assistant
Session; prove Web-Live Control Reachability; create a Video Assistant Takeover Route; or determine Video Assistant Entry
Eligibility. Profiles cannot carry JavaScript, executable logic, arbitrary requests or parameters, request headers,
cookies, credentials, new protocols, or new acquisition or presentation algorithms. Those remain reviewed App-release
work.

At most one Profile applies to a current top-level Media Route Epoch. Child frames may satisfy bounded evidence
conditions but never resolve competing Profiles. The resulting Video Compatibility Profile Resolution is immutable for
its Media Evidence Generation and Media Route Epoch; catalog changes apply only after a new resolution. Direct and
structured evidence plus every unsuppressed generic strategy remain active. A selected Recipe's failure does not revive
a named heuristic that the resolved Profile explicitly suppresses.

Profile Scope uses only top-level HTTP(S) identity with exact host or anchored subdomain matching, an optional normalized
path prefix, and optional required query-key presence. It cannot match query values or contain regular expressions,
arbitrary globs, or executable URL logic. Exact host and then longest path prefix determine specificity. Equal-specificity
conflicts invalidate the Catalog rather than making entry order a hidden precedence rule; runtime ambiguity resolves no
Profile and preserves generic behavior.

The Video Compatibility Profile Catalog is separate from the global `MediaDetectionPolicyCatalog`. A complete valid
signed Profile entry atomically overrides its packaged fallback and is never field-merged with it. An invalid or expired
cloud source falls back to the packaged entry. A signed disabled entry removes only the Profile enhancement and restores
the full generic engine; it cannot block Video Assistant recognition or takeover eligibility.

The packaged selector capability uses a closed media-element grammar (`video`/`audio` with bounded class or id
suffixes), a fixed top-document/top-origin scope, and a four-value output attribute vocabulary. The local ArkWeb probe
returns only bounded match counts after App-owned visibility/structure checks; it never serializes DOM nodes, URLs,
attribute values, page text, or executable Profile content. Accepted selector results enter the Media Evidence Graph as
profile-attributed structured or heuristic evidence and remain outside Session Resolution authority. Heuristic
suppression is an allowlisted capability for weak generic DOM/deep textual signals only; direct evidence and structured
media-element evidence are not suppressible. Selector evidence is discarded when the Media Route Epoch advances, so a
SPA route cannot inherit a prior route's Profile attribution.

Cloud delivery publishes one complete App-bounded signed Catalog snapshot that the App matches locally. Profile
resolution never performs a per-site lookup or sends the current host, path, frame identity, Media Resource, or private
browsing fact to the Catalog server. Packaged and currently valid cached Profiles remain available in Private Browsing
Sessions without a page-triggered Profile request.

The operational envelope is published at `GET /video-compatibility-profiles/v1/manifest` from the checked-in authoring
snapshot `server/video-compatibility-profiles/manifest.json`. The App pins the dedicated envelope type and key ID
`aira-video-compatibility-profiles-rsa-20260808`; the server may reuse the provisioned Novel RSA key material by
default, but it must still verify that the configured private key matches the App-embedded public key. The App stores
only one complete signed envelope in its recoverable app-private cache and writes it before activating the normalized
remote set. A signed disabled entry is therefore a complete replacement for its matching packaged key, not a partial
field overlay. The bounded foreground watch at `GET /video-compatibility-profiles/v1/watch` transports only revision
and wake metadata; its wake-up uses the existing authenticated admin operation surface.

## Consequences

- YouTube acquisition now has one Profile-selected compiled Recipe authority without moving Session Resolution or
  takeover authority; Profile-negative routes continue through generic discovery only.
- The proven XlPlayer host has one Profile-selected Recipe authority without duplicate `/lines` work, while unknown
  XlPlayer hosts retain the shared generic adapter until evidence-backed scopes are added.
- Every remotely selectable behavior must already exist, be bounded, and be testable through an App-owned Recipe
  interface before a Profile may reference it.
- New executable algorithms, protocols, access mechanisms, and route types still require an App release and architectural
  review.
- Packaged Profile behavior can stabilize before signed delivery is allowed to select the same Recipe identities.
- Catalog delivery cannot become a browsing-history side channel.
- Small reviewed DOM compatibility changes can ship declaratively without treating selector matches as direct evidence.
- Profile matching remains deterministic, reviewable, and fail-closed under ambiguity.
