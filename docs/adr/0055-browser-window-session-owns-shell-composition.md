# Browser Window Session Owns Shell Composition

Accepted: 2026-07-24

## Context

Aira needs independent Phone and Large-Screen browser chrome instead of stretching one ArkUI page tree across phones,
tablets, and 2-in-1 devices. The browser business graph, however, must remain shared: tabs, per-tab Web runtimes,
Window-Open/OAuth, navigation transactions, Search, background retention, Browser Home, private browsing, and WebApp
behavior cannot acquire separate owners merely because the chrome is different.

Today `BrowserShellPage.ets` still constructs and connects much of that graph. Creating a second page tree from the same
pattern would duplicate ownership, make lifetime depend on ArkUI mounting, and force changes to be coordinated across two
shallow shell modules. A generic Shell controller would only move that broad interface out of the page without increasing
locality or module depth.

Huawei Browser's observed large-screen organization provides an architectural bias rather than an implementation to
copy: window ownership, tab-list ownership, the tab-to-Web bridge, per-tab Web runtime ownership, and background resource
policy remain distinct, while phone and large-screen presentation adapt to those owners.

## Decision

Each Aira browser window owns exactly one **Browser Window Session**. It is the deep composition-and-lifetime module for
that window's browser graph and is implemented by
`core/browser/BrowserWindowSessionApplication.ets`.

The existing `BrowserWindowRuntime` owns the per-`windowId` Session registry. It lazily acquires one Session, keeps it
alive across route navigation, foreground/background changes, and Shell attachment changes, and releases it only when the
owning WindowStage is destroyed. A route or ArkUI component mounting is not Session ownership.

One Session covers Browser Home, ordinary and private browsing, and WebApp Single Surface. It composes existing narrative
owners but does not absorb their policies. `TabManager`, tab/runtime ownership, `BrowserWebTabsController`, Window Context,
Search Invocation, Web Page Navigation Transaction, Window-Open/OAuth, background retention/discard, Browser Home, and
WebApp behavior remain distinct subordinate modules with their current domain entry points.

### Presentation selection

The existing `BROWSER_SHELL_ROUTE` remains the one stable browser route. Its stable host can mount three presentation
adapters over the same Session:

- Phone Shell: independent phone browser-chrome tree.
- Large-Screen Shell: independent tablet and 2-in-1 browser-chrome tree.
- WebApp Single Surface: chrome-less presentation that bypasses both browser Shell chrome trees.

The Session has one stable **Browser Shell Family**, Phone or Large-Screen. It is resolved before the initial
`loadContent`, so the first ArkUI frame mounts the intended family. Window width, split-screen mode, floating-window mode,
and input changes update presentation inside the chosen family; they do not silently replace one Shell Family with the
other. An explicit future family-change command may perform a controlled handoff, but automatic width-threshold switching
is not part of this decision.

One deepened form-factor policy module projects WindowStage and device facts into a revisioned **Browser Window
Presentation Profile**. The Session holds the current profile. Shell adapters never query platform window or display
state independently and never become competing form-factor policy owners.

### Session interface

The window runtime acquires and releases the Session. The stable host connects its adapter catalog once and receives a
connection that reconciles monotonic, revisioned composition/lifetime facts:

```text
BrowserWindowRuntime
  acquireSession(seed)
  releaseSession(windowId)

Stable Browser Host
  connect(adapterCatalog) -> connection

Connection
  reconcile(revisionedFacts)
  disconnect()
```

`reconcile()` is limited to route visibility, foreground/background state, Browser Window Presentation Profile revision,
and the current WebApp presentation override. The Session accepts the staged installed-WebApp launch fact before first
content and selects the chrome-less WebApp adapter without changing the retained Phone or Large-Screen family. Stale
revisions and adapter generations are ignored.

The interface does not expose tab, Search, navigation, Window-Open, background, or other business commands. It exposes no
raw subordinate-owner getters, generic registry, generic `dispatch(event)`, or giant business-state snapshot. Fixed owner
dependencies belong behind the Session interface rather than in page-built host callback aggregates.

### State and stable surfaces

Semantic browser state belongs to the Session or its existing subordinate owner and survives presentation changes.
Geometry, animation, hover, overflow menus, and transient chrome state are **Browser Shell Presentation State** owned by
the active Shell adapter. An explicit Shell Family change ends that local state; it does not translate phone control state
into large-screen control state or vice versa.

Hosted Web fixed per-tab slots remain in the stable host. Phone and Large-Screen Shell adapters may supply geometry,
visibility, and chrome facts, but they cannot create, move, destroy, reparent, or rebind Web controllers or NodeContainer
slots. The literal `onBeforeWebBuild -> BrowserWebTabsController` ownership path remains unchanged unless the frozen
Window-Open/BFCache contract is separately authorized for revision.

Browser Home keeps one semantic/runtime owner with separate Phone and Large-Screen native presentations. The Active
Third-Party Home Document runtime and its slot remain single and stable in the host. Search keeps one window-scoped Search
Invocation Session; Phone and Large-Screen presentation adapters perform an atomic handoff only after the target adapter
reports mount readiness.

### Failure policy

Presentation failures never trigger a silent cross-family fallback after first content load:

- Initial Large-Screen resolution failure shows a stable same-family failure presentation rather than flashing Phone
  Shell and switching later.
- A failed explicit family handoff retains the previous complete presentation and its semantic Session state.
- A failed WebApp presentation remains chrome-less rather than exposing ordinary browser chrome around the WebApp.
- Stale profile revisions, reconciliation revisions, and adapter generations have no effect.

## Considered Options

- Two independent routes and application graphs were rejected because tabs, Search return routing, Web runtimes, and
  lifecycle ownership would drift between Phone and Large-Screen implementations.
- One responsive Shell page was rejected because macro layout, interaction, and chrome differences would keep expanding
  `BrowserShellPage.ets` and couple unrelated presentation state.
- A generic `BrowserShellController` or `BrowserShellOrchestrator` was rejected because its interface would be nearly as
  broad as the browser graph and would create a second policy owner rather than a deep composition module.
- Automatic Shell Family switching at width thresholds was rejected because ordinary resize could destroy transient UI,
  race ArkWeb mounting, and make window size an implicit application-graph replacement command.
- A fully flexible presentation/input lease fabric was rejected as premature interface surface. Repeating all adapters in
  every desired-state reconciliation was also rejected because adapter identity is stable after host connection.

## Consequences

Implementation proceeds as working tracer slices. Each slice removes the superseded ownership path and leaves the browser
buildable:

1. Add the Session foundation and `BrowserWindowRuntime` registry/lifetime integration.
2. Transfer tab/runtime composition ownership.
3. Transfer Window Context composition ownership.
4. In a separately authorized task, transfer the stable Hosted Web host while preserving ADR-0040.
5. Extract the existing Phone presentation until `BrowserShellPage.ets` contains only ArkUI/ArkWeb mounting, state
   binding, and one-line event forwarding in the touched area.
6. Add the Large-Screen adapter skeleton over the same Session and connect the stable host to the revisioned adapter catalog.

Ordinary ownership slices require focused architecture checks and a complete signed build. Presentation slices add
installation plus user-operated visual and interaction acceptance. The Hosted Web slice additionally requires explicit
current-task authorization, the frozen-contract guard, and the full user-operated Window-Open/BFCache device matrix;
compilation alone is insufficient.

The first presentation-policy tracer slice is now in place. `BrowserWindowSessionApplication` retains a revisioned
`Browser Window Presentation Profile`; `BrowserWindowDisplayViewportCoordinator` supplies exact WindowStage facts;
and `BrowserShellAdapterCatalog` reports which Shell Families are actually ready. The initial family is resolved before
`loadContent`, while later size/display revisions update the profile without silently switching a live Session between
Phone and Large-Screen. The catalog reports Phone, Large-Screen, and WebApp adapters as ready. An installed WebApp launch
overrides either browser Shell family with `BrowserWebAppPrimarySurface`, which mounts the stable Hosted Web surface
without tab, navigation, bookmark, Phone bottom, or other browser-owned Chrome. The underlying Phone/Large-Screen family
remains retained so an explicit end to the override can restore ordinary browser presentation without recomputing device
policy.

The stable host now connects the catalog through `BrowserWindowRuntime` into the Session-owned
`BrowserShellPresentationCoordinator`. The page receives only an opaque presentation binding and a read-only snapshot;
it does not select the family, inspect WindowStage facts, or own adapter lifetimes. Catalog revisions and profile
revisions are monotonic, stale profile updates are ignored, and Session release disconnects the presentation connection.

The first real presentation adapter is `BrowserPhonePrimarySurface`. It owns the Phone Shell's Home/Web primary-layer
ordering and receives shaped state and builder content from the stable host. Hosted Web parking remains mounted by the
stable host beside the adapter. The adapter does not own tab truth, Web runtime lifetime, discard policy, or Hosted Web
controller slots.

The Novel Reading Session ownership tracer is also in place. `BrowserWindowSessionApplication` constructs and retains
one `NovelReaderController` for the window, exposes it through an opaque binding, and the Shell connects a fixed
`BrowserWindowSessionNovelReaderPort`. The Shell mounts `NovelReaderOverlay` with one Session snapshot and forwards one
typed action stream; automatic page-ready facts and private/persistent data scope are passed to the Session without the
page deciding takeover policy. Reading preferences and character-offset checkpoints are Session state, while ArkUI text
measurement, Swiper/Scroller execution, InputKit volume handling, timers, and status-bar execution remain renderer/platform
adapter responsibilities. Real open requests require a tab and matching privacy/data scope, stale extraction is rejected
against both the request identity and original ArkWeb controller, and Shell listeners use ownership-aware disposable
connections. The Session also retains the loaded Chapter trail for vertical continuous reading, so a renderer remount can
reconstruct content and restore the Chapter-plus-character checkpoint without treating the latest fetched Chapter as the
user's reading position. This tracer adds no bookshelf, chapter cache, database, or Sync behavior.

The independent Large-Screen skeleton is `BrowserLargeScreenPrimarySurface`. It only fixes macro-region slots (top
chrome, tab strip, Web main area, optional side panel, and bottom status); it remains intentionally not ready in the
adapter catalog until those slots receive the approved product presentation and interaction design.

This ADR does not authorize edits to ADR-0040 Window-Open/BFCache protected paths, frozen Sync architecture, or new
repository-internal automated tests. It also does not prescribe the visual design of either Shell Family.
