# Web Page Navigation Transaction Has One Lifecycle Owner

Accepted: 2026-07-19

## Context

Ordinary Web navigation behavior had accumulated across `BrowserShellPage.ets`, Event Commit host projections,
Presentation Event timers, Feature Effects, loading-progress state, and several fixed browser dependencies. The page had
to know callback ordering, stale-event guards, load-failure transitions, page-ready effects, navigation metadata, and
which downstream owner to call. That interface was nearly as wide as the implementation and made page slimming likely
to replace one oversized file with many shallow peer coordinators.

ArkWeb callback order is not treated as a total ordering guarantee. The browser must preserve its existing stale-event,
error-document, download-navigation, deferred-metadata, and per-tab routing guards even when code moves behind a deeper
module interface.

## Decision

`BrowserWebPageLifecycleApplicationCoordinator` is the single narrative owner of the Web Page Navigation Transaction.
It exposes typed semantic entry points for page begin, page end, progress, committed navigation, title, favicon,
load-finished, main-frame error, and History API URL changes. `BrowserWebEventCommitCoordinator`,
`BrowserWebPagePresentationEventCoordinator`, `BrowserWebPageFeatureEffectsCoordinator`, and
`BrowserLoadingProgressCoordinator` are subordinate implementations behind that interface rather than peer owners
wired together by BrowserShell.

Fixed dependencies belong in the Lifecycle owner constructor. BrowserShell may supply current shell facts and unavoidable
ArkUI/platform publications, but it does not construct ordered effect plans, interpret a tagged event bus, own progress
timers, decide stale-event acceptance, or route fixed services through callback aggregates. Snapshot Restore remains a
separate small seam for tab/session restoration.

`BrowserWebEventHostCoordinator` remains the ArkWeb ingress and exception-isolation adapter. Controller attachment,
Hosted Web construction, Window-Open/OAuth ownership, BFCache, user-agent bootstrap, runtime residency, background
discard, and the literal `onBeforeWebBuild -> BrowserWebTabsController` edge remain with their existing owners and are
not absorbed into this transaction.

## Considered Options

- A single tagged-union `dispatch(event)` interface was rejected because it would hide useful ArkWeb semantics and invite
  a page-side ordered effect interpreter.
- A second Lifecycle coordinator was rejected because it would split one user-visible flow across peer owners.
- Keeping page-built Event Commit, Presentation, Feature Effects, and Loading Progress hosts was rejected because their
  shallow interfaces leaked fixed implementation dependencies back into BrowserShell.

## Consequences

Future ordinary Web navigation changes enter through the Lifecycle owner first. BrowserShell changes in this area are
limited to callback forwarding, current-state reads, and state/UI publication, and each touch must reduce page-owned
logic. The Window-Open/BFCache static guard, architecture guard, signed HAP build, and user-operated navigation smoke
matrix remain required proportional verification. Window-Open/BFCache may evolve through normal in-scope work; Sync
retains its separate contract and verification rules.
