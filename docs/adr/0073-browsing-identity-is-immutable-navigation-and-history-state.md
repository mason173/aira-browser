---
status: accepted
date: 2026-08-28
---

# Browsing Identity Is Immutable Navigation and History State

## Context

Aira supports all of the following at the same time:

- a physical-device default webpage family;
- an explicit global Browsing Identity;
- a saved exact-Origin identity;
- a current-tab temporary mobile/desktop choice;
- bundled and signed-cloud exact-Host compatibility policy;
- known presets, ArkWeb Original, and arbitrary custom UA strings;
- ArkWeb native Back/Forward, BFCache, WebState restore, and Controller replacement;
- foldable Shell changes and manual Touch/Desktop interface modes;
- HTTPS-First upgrade, confirmed HTTP fallback, and redirect handling.

Recent fixes proved that these cannot be modeled as one function returning a User-Agent string. The selected identity
changes server content, JavaScript-visible values, UA Client Hints, Controller state, BFCache eligibility, and the
identity required by a native history entry. Fold state and HTTPS authorization are different concerns even when the
same navigation exposes all of them.

This ADR is the normative Aira contract for Browsing Identity. The research in
[`user-agent-browsing-identity-architecture-research.md`](../research/user-agent-browsing-identity-architecture-research.md)
provides supporting platform and browser evidence. UA-specific statements in ADR 0040 are historical evidence; where
they conflict with this ADR, this ADR supersedes them. ADR 0040 remains authoritative for its Window-Open and BFCache
ownership contract, and ADR 0051 remains authoritative for the ordinary Web Page Navigation Transaction owner.

## Decision Summary

Aira has one Browsing Identity domain with two deep modules and one independent transport module:

```text
Policy inputs
  mandatory signed/bundled Host rule
  current-tab temporary choice
  saved exact-Origin choice
  explicit global choice
  Aira compatibility choice
  physical-device / active-Shell default
             |
             v
  Browsing Identity Policy
  immutable Decision + evidence
             |
             v
  Browsing Identity Runtime
  Navigation Transaction -> Controller Binding -> committed History Entry
             |
             v
          ArkWeb

Presentation inputs                         Transport inputs
  fold / Shell / width / pointer              URL / scheme / redirect / grant
             |                                           |
             v                                           v
  Shell and viewport plus                    HTTPS-First Navigation
  applicable default family                  never selects UA or Shell
```

`Browsing Identity Policy` owns selection. `Browsing Identity Runtime` owns when a decision is frozen, how it is
applied to a Controller, and which identity belongs to a native history entry. ArkWeb-specific calls are subordinate
implementation details behind the runtime interface. `HTTPS-First Navigation` is independent and shares only
navigation identity/provenance, never UA policy.

These are not five peer coordinators. Policy and runtime are the two narrative owners. Catalogs, repositories, Client
Hints application, Controller replacement, and ArkWeb callback adapters remain subordinate implementations.

## Normative Terms And State

| Term | Meaning | Lifetime | Owner |
|---|---|---|---|
| `BrowsingIdentityProfile` | Complete executable web identity: UA mode/string, UA-CH mode/metadata, mobile/desktop-request semantics, capability scope, and compatibility notice | Catalog revision | Browsing Identity Policy |
| `PolicySnapshot` | All policy candidates and their revisions for one tab, target, Profile, and privacy context | One resolution | Browsing Identity Policy |
| `BrowsingIdentityDecision` | Immutable winning profile plus source, evidence, snapshot key, reason, and execution fingerprint | One navigation transaction; copied into a committed entry | Browsing Identity Policy |
| `NavigationIdentityTransaction` | The frozen decision for one main-frame navigation and its uncommitted redirect chain | Prepare until commit, cancellation, failure, stop, or runtime disposal | Browsing Identity Runtime |
| `ControllerIdentityBinding` | The identity actually applied to one ArkWeb Controller generation, distinguished as untouched native or custom | Controller generation | Browsing Identity Runtime |
| `CommittedEntryIdentity` | The actually applied decision associated with an ArkWeb native history entry | Native entry/WebState lifetime | Browsing Identity Runtime |
| `HttpNavigationGrant` | Authorization to continue HTTP in a particular security/data context | Exact persistent exception or bounded tab transaction | HTTPS-First Navigation |

A `BrowsingIdentityDecision` is not only a UA string. Its execution fingerprint covers every value that changes the
observable identity, including at least:

```text
identityId
uaStringMode: system_untouched | known_preset | custom
uaString
clientHintsMode: system | known_metadata | low_entropy_only
clientHintsMetadata
presentationMode: mobile | desktop-request
scopeCapability
winningSource
policySnapshotKey
reason and decision evidence
executionFingerprint
```

Two decisions with equal visible UA text are not necessarily equal. In particular, an untouched ArkWeb Controller and a
Controller that received the same text through `setCustomUserAgent()` have different runtime identity.

## Policy Precedence

Policy resolves exactly one candidate in this order:

| Priority | Candidate | Match/scope | Persistence | Activation |
|---:|---|---|---|---|
| 1 | Mandatory Host compatibility | Valid signed-cloud snapshot, or bundled fallback, exact normalized Host | Catalog snapshot | Next explicit navigation/reload; never mutates an active transaction |
| 2 | Current-tab temporary choice | Exact tab ID; available in regular or private tab memory | Tab lifetime only | User action starts an explicit reload transaction |
| 3 | Saved exact-Origin choice | Scheme + normalized host + effective port + Profile; not read in private browsing | Persistent site setting | Next explicit navigation/reload |
| 4 | Explicit global choice | Browser-wide selected preset/custom/ArkWeb Original | Persistent settings | Next explicit navigation/reload; the settings UI may request that reload |
| 5 | Aira compatibility choice | Reserved non-mandatory application compatibility layer | Application/catalog revision | Next explicit navigation/reload |
| 6 | Physical-device default | Stable physical form factor | Process/device capability state | First navigation and later transactions without a higher candidate |

The first available candidate wins. Unavailable referenced identities are evidence, not implicit permission to invent a
replacement. The fallback must continue down the declared order and remain visible in the decision explanation.

Mandatory Host rules own the exact compatible profile for a managed Host, but may select the catalog's mobile or
desktop shape from the requested family established by current-tab, exact-Origin, global, or physical-default policy.
This lets the cloud rule remain mandatory without silently discarding an explicit mobile/desktop request. A cloud
snapshot revision that arrives while a page is loading cannot replace the transaction already in progress.

The `aira_compatibility` candidate is reserved in the model. While it has no configured rule, it stays explicitly empty;
callers must not duplicate it through hidden conditionals.

## Physical Device And Presentation

The stable physical form factor and, for foldable/manual Shell transitions, the active Shell family select only the
lowest-priority applicable default family:

| Physical/presentation state | Default webpage identity | Higher-priority choices |
|---|---|---|
| Phone + Phone Shell (folded or ordinary phone) | Bounded Android-compatible Aira mobile identity | Mandatory Host, tab, exact-Origin, global, and explicit identities remain authoritative |
| Phone + Large-Screen Shell (expanded foldable or manual Desktop mode) | Aira desktop compatibility identity | Mandatory Host, tab, exact-Origin, global, and explicit identities remain authoritative |
| Tablet / 2-in-1 / PC / desktop | Aira desktop compatibility identity | Window resize, split screen, orientation, and pointer/keyboard changes |

`arkweb_original` remains an explicit `system_untouched` identity. It is not the ordinary physical-phone default because
verified consumer sites can reject the native OpenHarmony token even with a correct mobile viewport. It remains the
escape hatch for native engine identity, login compatibility, or BFCache-sensitive browsing.

The Android-compatible phone default is a custom Controller identity and therefore accepts ArkWeb's observed BFCache
tradeoff. This is an Aira product decision, not a Huawei platform guarantee. A foldable phone's active Shell family is
an explicit input to its applicable default only: `phone` selects the mobile identity and `large_screen` selects the
desktop identity. Explicit Host/tab/Origin/global choices still win, and Shell changes never rewrite a committed
navigation transaction; they request a new UA runtime transaction for the active page.

## Navigation Identity Transaction

Every explicit main-frame navigation is prepared before ArkWeb receives the navigation command:

```text
IDLE
  |
  | explicit main-frame intent / reload / first load / child first load
  v
PLANNED(decision, transactionId, target)
  |
  | Controller binding prepared successfully
  v
APPLIED(actual Controller binding)
  | \
  |  \ cancellation / failure / stop / disposal
  |   -> TERMINAL
  |
  | main-frame commit
  v
COMMITTED(historyIndex, committedUrl, actual decision)
  -> IDLE
```

The transaction rules are:

1. Address-bar navigation, link-triggered new-document navigation, app-initiated loads, reload, a script-initiated
   new-document navigation after the prior document committed, and a child window's first document create a new decision.
2. Server redirects and other redirect hops belonging to the same uncommitted main-frame navigation reuse the frozen
   decision, even if the redirect target would currently resolve another policy candidate.
3. Same-document URL changes and History API changes reuse the committed document identity.
4. A later JavaScript navigation after the previous document committed is a new main-frame transaction.
5. `page_begin`, page progress, `page_end`, load-finished, and restore callbacks observe the plan and actual binding.
   They never select, repair, or mutate identity.
6. Commit records the Controller identity that was actually applied. A requested identity with
   `identity_transition_required` is intent, not committed fact.
7. A settings or cloud revision cannot change an active transaction. A user-facing settings action may explicitly
   request reload, which creates a new transaction after the setting is committed.

## Controller Identity State Machine

```text
UNBOUND
  | attach and prepare target identity
  +----------------------------+
  v                            v
NATIVE_UNTOUCHED          CUSTOM(fingerprint A)
  |                            |
  | explicit navigation        | same fingerprint -> unchanged
  | to custom                  | custom B before explicit nav
  +---------------> CUSTOM(fingerprint B)
                               |
          target cannot be prepared safely in place,
          including custom -> system_untouched
                               |
                               v
            TRANSITIONING(generation, target, WebState)
              -> new Controller -> prepare target at attach
              -> restore -> validate generation
              -> optional one-shot explicit reload

Any state -> DISPOSED
```

The Controller rules are:

- Native means a fresh Controller that has never received a custom UA setter. Reading ArkWeb's default text and writing
  it back is custom, not native.
- A custom identity is applied only at a pre-navigation or pre-restore preparation point, never as a page callback
  repair.
- Same-fingerprint application is idempotent and may refresh metadata without changing transaction identity.
- `custom -> system_untouched` never pretends to clear the Controller in place. Until Huawei confirms a lossless clear
  operation, it requires serialized WebState, a new Controller generation, restore, generation validation, and a
  controlled reload only when the user action requires one.
- No UA setter runs from `page_begin` or while `restoreWebState()` callbacks are executing.
- A stale callback from an old Controller generation cannot publish binding, history, or reload state.
- Controller replacement is owned by the per-tab runtime lifecycle. UI pages and Web callback adapters cannot dispose,
  replace, restore, or replay a Controller themselves.

## Native History And BFCache

Back/Forward is history restoration, not a new policy lookup:

```text
native history target index
          |
          v
CommittedEntryIdentity available?
     | yes                         | no
     v                             v
use entry decision          classified fallback decision
     |                             |
     +-------------+---------------+
                   v
prepare compatible Controller identity
                   |
                   v
issue ArkWeb native backOrForward/accessStep
```

The history contract is:

- A live native history entry restores the decision recorded when that entry committed, not the current global,
  exact-Origin, temporary-tab, cloud, or physical-device policy.
- The entry ledger is keyed by native history position plus committed URL validation and is pruned with ArkWeb's live
  BackForwardList.
- The ledger must survive an intentional Controller replacement together with its serialized WebState. Cold-start or
  background-discard restore must persist enough entry identity metadata to avoid silently reevaluating old entries.
- If an entry has no recorded identity, fallback policy is an explicit degraded path. It must be observable and must not
  be described as equivalent history restoration.
- If the target entry fingerprint differs from the current Controller binding, identity preparation happens before the
  native traversal. If ArkWeb cannot safely perform that preparation in place, the per-tab runtime performs a
  state-preserving Controller transition first.
- Ordinary Back/Forward never uses app-side URL replay or app-side scroll/form restoration as the primary path.
- ArkWeb owns BackForwardList, BFCache, document heap, form state, and scroll restoration. Aira owns only identity
  preparation, the entry identity ledger, and cold/controlled runtime recovery metadata.
- BFCache eligibility is verified per identity/application path. It is never inferred from matching UA text.

## HTTPS-First Transport Is Separate

Transport policy is evaluated independently from Browsing Identity:

| HTTPS-First owns | Browsing Identity owns |
|---|---|
| Scheme upgrade and retry | UA and UA-CH profile |
| User-confirmed HTTP fallback | Mobile/desktop-request semantics |
| Exact-host/port persistent exceptions | Policy source and revision |
| Redirect provenance and tab-local grants | Controller binding and execution fingerprint |
| Transport failure classification | History-entry identity |

The order for a new app-issued load is:

```text
normalize URL
  -> transport chooses the authorized scheme/target
  -> identity policy resolves that target
  -> runtime freezes and applies identity
  -> ArkWeb navigation is issued
```

During the uncommitted navigation, HTTPS-First may evaluate a redirect hop while Browsing Identity continues to reuse
its frozen decision. The modules may share a navigation transaction/provenance ID, but neither reads the other's policy
state.

Persistent HTTP exceptions remain exact host and effective port. A tab-local user-confirmed HTTP grant may follow an
actual server redirect only when the redirect stays within the same standards-derived registrable site, effective port,
Profile, privacy mode, and data scope, and remains in the same uncommitted navigation transaction. It cannot authorize
an arbitrary sibling-host navigation or a later navigation. The current fixed `www` / `wap` / `m` / `mobile` alias
implementation is a conservative temporary approximation, not this model's normative site relation.

## Scenario Matrix

| Event | Re-resolve current policy? | Change Controller now? | Reload? | History identity |
|---|---:|---:|---:|---|
| First page on a new Controller | Yes | Before load | No extra reload | Commit actual binding |
| Address-bar/app explicit navigation | Yes | Before load if safe | No extra reload | Commit new entry |
| Link-triggered new-document navigation | Yes | Before load if safe | No extra reload | Commit new entry |
| Server/redirect hop inside the same uncommitted transaction | No | No | No | Commit frozen transaction |
| Same-document/History API URL change | No | No | No | Keep current entry identity |
| User selects temporary desktop/mobile for current tab | Yes, after state update | Before explicit reload or through controlled transition | Yes, user-authorized | New committed identity |
| User saves exact-Origin choice | Yes, after save | Before explicit reload or through controlled transition | Yes when applying now | New committed identity |
| User changes global choice | Future transactions; active page only through explicit reconcile | Never mid-transaction | Optional explicit active-page reload | Old entries unchanged |
| Signed cloud Host catalog activates | Future transactions only | Never mid-transaction | No forced reload | Old entries unchanged |
| Fold/unfold or Shell/interface-mode change | Active page only when the applicable default changes | Existing runtime transition for the active Web tab | Yes only when the selected identity changes | Existing entries unchanged |
| Back/Forward | No; use entry ledger | Prepare entry identity before traversal | Never URL replay | Restore recorded entry |
| Controlled Controller replacement | No policy drift during transition | New generation only | At most one marked reload | Preserve ledger with WebState |
| User confirms HTTP fallback | No UA change | No | Transport retry only | Identity transaction remains frozen |

## Non-Negotiable Invariants

1. There is exactly one selected identity decision for an explicit navigation transaction.
2. The decision is immutable from prepare through terminal state.
3. The applied Controller binding, not requested intent, is the only value committed to history.
4. Redirects cannot cause identity drift inside an uncommitted transaction.
5. `page_begin` and restore callbacks are observation-only for identity.
6. Untouched native and custom-with-equal-text are distinct states.
7. Current policy never rewrites an existing history entry.
8. Back/Forward uses ArkWeb native history as the normal path.
9. Fold, Shell, viewport, pointer, and orientation state never select identity.
10. HTTPS authorization never selects or persists UA state.
11. A scope change affects only its declared scope; a tab choice cannot mutate another tab or a process-static switch.
12. Every decision is explainable from its snapshot key, winning source, evidence, and execution fingerprint.

## Module Mapping

The current implementation maps to the model as follows. Names may later improve, but ownership must not drift:

| Current module | Role in this ADR | Constraint |
|---|---|---|
| `BrowserBrowsingIdentityPolicyCoordinator` | Builds the complete Policy Snapshot | Does not mutate Controller or navigate |
| `BrowserBrowsingIdentityDecisionService` | Pure precedence decision and evidence | Decision is immutable and complete |
| `BrowserUserAgentService` | Profile catalog, normalization, and legacy-named identity construction | Does not own navigation timing |
| `BrowserUserAgentHostPolicyService` / Catalog | Signed/bundled exact-Host policy adapter | Activation affects later transactions |
| `BrowserUserAgentRuntimeService` | Navigation transaction, Controller binding, and committed-entry ledger owner | Its small runtime interface is the main seam |
| `BrowserUserAgentRuntimePolicyCoordinator` | Converts explicit user policy changes into reconcile/reload work | Cannot mutate an active transaction |
| `BrowserUserAgentRuntimeTransitionCoordinator` | Subordinate serialized Controller replacement implementation | Generation-bound; never called as page-begin repair |
| `BrowserUserAgentClientHintsService` | ArkWeb UA-CH metadata adapter | Per-Controller metadata cannot own the process-static switch |
| `BrowserWebLoadRuntimeCoordinator` | ArkWeb/navigation adapter into the runtime interface | Does not re-resolve or repair identity in callbacks |
| `BrowserHttpsFirstNavigationService` | Independent transport policy | No UA, Shell, fold, viewport, or history-entry rules |
| `BrowserShellPage` and ArkUI surfaces | Event forwarding and presentation | No policy, Controller transition, or navigation replay ownership |

The external Browsing Identity Runtime seam remains navigation-oriented: prepare explicit navigation, prepare native
history traversal, commit/cancel navigation, and release a runtime. Catalog lookup, candidate evidence, ArkWeb setters,
Client Hints registration, Controller generations, and ledger maintenance remain internal to that interface.

## Current Conformance And Required Convergence

Already present in the current implementation:

- a complete Policy Snapshot with declared precedence and evidence;
- an execution fingerprint covering UA and UA-CH presentation facts;
- immutable active navigation plans and redirect reuse;
- observation-only page-begin handling;
- explicit untouched-native versus custom Controller binding;
- commit of actual Controller identity to an in-memory native-history ledger;
- serialized custom-to-native Controller replacement with generation guards;
- physical-device ownership of the default family;
- separate HTTPS-First ownership.

Required follow-up convergence, without changing this ADR:

- persist/restore sufficient committed-entry identity metadata with WebState for cold/discard recovery;
- audit every Back/Forward path so an identity mismatch is prepared before native traversal and never repaired afterward;
- generalize or explicitly constrain state-preserving transitions for history entries whose custom fingerprints differ;
- either implement the reserved Aira compatibility layer as a first-class candidate or keep it empty without duplicate
  hidden fallbacks;
- replace the temporary HTTP presentation-alias heuristic with navigation-bound authorization and a standards-derived
  registrable-site implementation;
- keep static guards that prevent Shell/fold state, page callbacks, and HTTPS policy from acquiring identity ownership.

## Platform Facts And Open Questions

Huawei API 24 exposes application, Host, and Controller UA mechanisms, UA Client Hints controls, native history,
`serializeWebState()` / `restoreWebState()`, and BFCache controls. Aira has also verified on a target device that writing
the observable default UA through the custom setter differs from leaving the Controller untouched.

Huawei public documentation has not established a lossless in-place operation that clears a Controller custom UA back
to the never-overridden state, nor a complete guarantee for which history/BFCache state survives Controller replacement.
This ADR therefore keeps the conservative replacement and verification contract. It must not be weakened by assuming
Android WebView behavior applies to ArkWeb.

## Consequences

Site compatibility bugs are classified by the first broken invariant instead of patched by adding conditions to one UA
resolver. Policy errors, transaction drift, Controller transition failures, history-ledger loss, and transport mistakes
have separate owners and verification paths.

The ordinary Android-compatible phone default improves legacy mobile-site selection but knowingly gives up the native
untouched BFCache path for those entries. `arkweb_original` preserves the alternative. Product UI can expose mobile,
desktop, global, site, and temporary choices, but each choice only changes policy and begins a new explicit transaction;
it never repairs a page after navigation has started.

Verification is performed across policy scope, navigation kind, identity/UA-CH observation, Controller generation,
native history, BFCache, Profile/privacy isolation, fold/Shell changes, and HTTPS redirect/fallback behavior. Tests and
diagnostics should cross the Policy or Runtime interface rather than reaching through to internal maps and setters.
