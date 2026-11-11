# Search Invocation Uses One Window-Scoped Session Owner

Accepted, 2026-07-18: every browser window has one Search Invocation Session owner. Desktop cards, app-icon shortcuts, keyboard shortcuts, browser chrome, and `Active Third-Party Home Document` `openSearch()` calls use pre-bound `open()` Triggers; callers cannot choose the Search Scene, manipulate Settings routes, set Root Bottom-Panel detents, request focus/IME directly, or decide suggestion visibility. The owner holds Search Invocation Authority, Search Scene, in-memory Search Draft, pending/protected-flow state, latest-request cancellation, Search Presentation Commit ordering, Home fallback, foreground reinforcement, and privacy-safe diagnostics. Direct third-party `search(query, options)` remains a Search Submission and does not open Search.

Settings Navigation Session, Root Bottom-Panel Session, Search suggestion content, Search Submission, browser scene/tab ownership, and Active Third-Party Home Document authority remain separate existing owners behind subordinate seams. Settings Navigation Commit must complete before Search presentation; Root Bottom-Panel remains the sole owner of detent/backdrop/restore; native ArkUI focus and HarmonyOS IME execution report mount/focus readiness but do not choose policy; suggestions receive current Session eligibility and hydrate asynchronously after Search Presentation Commit. HarmonyOS Want/Form handling is an inbound adapter to the same Trigger interface, not a second Search architecture.

Search surface identity and Search suggestion content revision are separate contracts. Search authority and the Root
Bottom-Panel presentation determine the stable surface/motion identity; query changes, history hydration, repository
invalidation, bookmark refresh, remote merges, and deletion only replace mutable suggestion content under stable row
keys. Content refresh must not remount the Search surface, restart row-entry timers or watchers, replay whole-list motion,
or force a scroll position. `BrowserDetentBottomPanel` remains the only owner of whole-surface translation and opacity.
An active Search keeps its reserved suggestion viewport even when content is empty; a tap on uncovered blank space emits
the same semantic Back command as system Back through `BrowserMainBackCoordinator`, while rows and scrolling retain their
own hit targets. The Search List Surface is the one module that owns the shared visual relationships among suggestion
rows, the scroll clipping safety region, external-app search targets, the horizontal rail, and blank interaction space.
Its interface exposes Search presentation and intent rather than row, gap, alignment, or strip implementation details.
All visible content within a regular suggestion row shares one projected content frame and therefore one centerline:
the 54vp touch row bottom-aligns a 36vp visible frame containing title, history/trailing icon, and delete action. This
resting-content frame is independent from the positive scroll clipping safety region above external-app targets, so
resting suggestions can sit lower without letting scrolled content clip against the target icons. External targets keep
the shared leading rail even when only a small number of targets is visible. `BrowserDetentBottomPanel` remains
the generic host and the only owner of whole-surface clipping placement, translation, and opacity; it does not learn
Search-specific row or external-target geometry.

The Settings Search-exit adapter is owned by the window runtime, not by `SettingsCenterPage`. Entering the Settings
Navigation Session activates that adapter once; independent secondary and tertiary router pages do not unregister it.
An authorized Search request returns directly to the existing BrowserShell route and remains in the routing phase until
the BrowserShell Search surface registers again. That surface registration is the exit commit acknowledgement because
`router.back()` itself returns no completion result. Page-disappear callbacks, fixed delays, and repeated blind Back
commands are not commit signals. A superseded or interrupted exit is retryable and must not leave a shared unresolved
Promise that blocks later Settings Back actions.

## Search input interpretation

Updated 2026-11-11: `resolveAddressInput` in `common/utils/UrlUtils.ets` is the shared interpretation interface for
Search Submission and synchronous navigation/restore. It returns one `AddressInputResolution`: empty, search text,
or a navigation URL with its optional HTTP fallback. URL extraction carries that same result forward; consumers do
not independently repeat classification, IDNA conversion, or scheme selection. A failed conversion cannot silently
switch a navigation result to a different engine later in the same submission. `normalizeUrl` is URL-only and returns
an empty string for search text; it never constructs a search-engine URL.

The input module owns pasted-link extraction, domain evidence, international-host conversion, and local HTTP versus
public HTTPS defaults. `SearchEngineRoutingService` still owns configured/exact engine selection, availability probes,
eligibility and automatic fallback. `SearchEngineTemplateService` owns query encoding and template expansion.
Paste-and-go submits the raw clipboard text through the same interpreter; editor paste previews may use the shared
extraction helper without choosing an engine or executing navigation.

This seam does not absorb the other search-box features. Search Invocation Session still owns opening, draft and
focus authority; suggestion composition owns history/bookmark/tab/remote rows; Search Submission owns cancellation,
privacy, history recording and navigation effects; Quick Search owns result-document continuation and engine switching.
Explicit selected-text search remains a search even for URL-shaped selections. External-app search retains its native
handoff, private-mode confirmation and web fallback. The floating/split/dock appearances retain ADR-0083's owners.

`scripts/check-aira-international-domain-navigation.cjs` exercises the interpreter through actual routing and synchronous
navigation, including conversion failure, custom engines, exact selection, automatic fallback and external-app actions.
The suggestion, selection-search, quick-search-continuation and search-style-isolation checks protect the separate features.

## Considered Options

- Expose a generic `dispatch/snapshot/observe` Search event interface. Rejected because ordinary callers would learn lifecycle phases, authority references, draft state, and extension policy, making the external seam wider than the common `open Search` use case.
- Expose `request(source)` plus a public typed mailbox. Rejected as the ordinary caller interface because sources and authority-scoped interaction events should be pre-bound; the mailbox remains internal to the Search surface and runtime adapters.
- Keep Home, Web, Settings, startup, keyboard, and third-party entry flows separate. Rejected because route, panel, focus, IME, draft, and suggestion ordering would continue to drift across callers and reproduce warm-start races.

## Consequences

Implementation proceeds as tracer slices: first establish window-owned Settings exit acknowledgement and the window-scoped Session owner; then replace caller-side Root Bottom-Panel boolean-plan interpretation with semantic Search preparation, move suggestion eligibility under Session authority, and migrate every `open Search` source to a pre-bound Trigger. Suggestion rendering keeps content refresh motionless and routes blank-space dismissal through semantic Back rather than duplicating detent, focus, or IME policy. `BrowserShellPage.ets` retains only ArkUI/ArkWeb mounting, state binding, adapter registration, and one-line forwarding, and must lose more Search orchestration than it gains. This decision does not change frozen Sync or ADR-0040 Window-Open/BFCache ownership.
