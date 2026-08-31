# Video Assistant Session Resolution Has One Evidence-Derived Authority

Accepted: 2026-07-30

## Context

Video Assistant observations currently converge through two state paths. ArkWeb MediaInfo and top-level page behavior can
mutate sessions owned by `BrowserArkWebMediaTakeoverCoordinator`, while frame observations also enter the Media Evidence
Graph and are correlated through `BrowserMediaSessionRegistry`. The paths repeat playback-target identity matching and
can disagree about the current session. Adding cloud compatibility profiles before resolving that split would give the
profiles no single safe seam and could let observation hints accidentally influence takeover authority.

## Decision

`BrowserMediaRuntimeObservationApplicationCoordinator` remains the narrative owner for the observation-to-resolution
flow. A subordinate deep Session Resolution module is the only authority that interprets current Media Evidence into
Video Assistant Sessions and, when unambiguous, selects one Active Video Assistant Session. Media discovery supplies
evidence; takeover consumes resolution and separately owns Web-Live reachability execution, Takeover Routes, Entry
Eligibility, and presentation. `BrowserShellPage.ets` remains wiring-only.

Every result is an immutable Session Resolution Snapshot scoped to one Media Evidence Generation, Media Route Epoch, and
evidence revision. Consumers cannot mutate sessions. Playback, reachability, end, and invalidation changes re-enter as
evidence and produce a new snapshot. Session identity is stable only within one generation and never crosses a top-level
document navigation.

Direct evidence cannot be created, deleted, overwritten, or downgraded by a compatibility profile. A future signed Video
Compatibility Profile may contribute attributed structured or heuristic evidence, suppress future noisy heuristic
observations, or select bounded compiled observation strategies, but it cannot choose the Active Session, prove
reachability, create a Takeover Route, or make the Video Assistant entry eligible.

Active Session Continuity preserves a current session while it retains fresh direct playback evidence. Weaker competing
evidence cannot displace it. Equally authoritative direct competitors leave no Active Session until stronger direct
evidence resolves the ambiguity; recency, DOM area, and a global numeric confidence score are not tie-breakers.

Direct observations compete only after Aira-owned target aliases are canonicalized. When the recursive page observer and
exactly one current executable child-frame observer report the same stable Aira DOM video runtime ID, they describe one
Media Playback Target rather than two Sessions. Session Resolution keeps the frame-proxy target as the canonical command
binding and merges the direct observations for playback, timing, and presentation state. Different runtime IDs, multiple
matching frame targets, or ambiguous identities remain separate and fail closed under the ordinary competition rule.

Resolution failures fail closed for the affected tab: the Video Assistant entry is unavailable, while the original Web
playback and Media Evidence remain intact. Diagnostics are categorical and exclude full page/media URLs, credentials,
headers, and cookies. Retry is bounded and triggered by new evidence, navigation, or an explicit recomputation event.

## Migration

The new resolver first runs as a read-only shadow over the same evidence while the current production authority remains
unchanged. Sanitized old/new differences are classified. After the agreed fixture and true-device gates pass, authority
switches atomically to the new resolver; the old `sessionsByTab` identity matching, selection logic, and mutable session
authority are then deleted. There is no permanent dual write, per-event fallback, or silent return to the old resolver.

Cloud Video Compatibility Profiles are a separate later phase. One App release must first ship and stabilize the single
Session Resolution authority. A following release may add the signed profile interpreter and delivery adapter; after
that, only compatibility changes expressible through capabilities already compiled into the installed App can update
without an App release.

## Consequences

- Session identity, ambiguity, freshness, continuity, and generation rules gain one testable implementation.
- A detected session still does not imply reachability, an executable route, or a visible blue entry button.
- Resolver errors may temporarily reduce takeover availability but cannot select the wrong video or disrupt Web playback.
- Cutover requires automated direct/frame/multi-video/SPA/navigation/late-callback fixtures, fully classified shadow
  differences, true-device entry and takeover verification, reachability/recovery/tab-isolation checks, no
  `policy_background_contract_violation`, and code-search evidence that the former authority is gone. Compilation alone
  is insufficient.
- New protocols, encryption, bridge transports, executable scripts, credentials, or acquisition mechanisms remain App
  release work even after cloud profiles exist.
