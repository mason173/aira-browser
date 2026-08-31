---
status: accepted
supersedes: none
---

# Private Browsing Uses Effect Policy Instead of Blanket Gating

Accepted 2026-07-31. A Private Browsing Session is a traceless session, not a sandbox that forbids every persistent
effect. It prevents ambient browsing traces and automatic cross-privacy-boundary reads or writes from becoming
persistent. An Explicit User Persistence may still target a clearly identified destination, while login, purchase,
referral redemption, remote account mutation, and Sync remain separately classified effects rather than consequences of
one generic private-mode boolean.

## Decision

One closed Privacy Effect Catalog classifies every supported Privacy Effect Intent as an ambient trace, session-local
state, explicit user persistence, or remote account/Sync mutation. Feature owners provide the stable intent and current
target facts but cannot classify their own intent. An Unclassified Privacy Effect fails closed in a Private Browsing
Session with structured, non-sensitive diagnostics; ordinary browsing behavior remains unchanged.

A Privacy Effect Target Scope is one of:

- current private-session state;
- persistent private data;
- regular-profile data;
- device-wide preferences;
- a user-selected external location;
- remote account or Sync state.

The requesting session's privacy scope and the effect's target scope are independent facts. Existing action copy or a
system destination picker is sufficient confirmation when destination and permanence are already clear. A transition
into regular-profile or remote data that is not already clear requires explicit confirmation. The policy never silently
substitutes, downgrades, or redirects a denied effect; every alternative target is another intent with its own decision.

`BrowserPrivacyDataPolicyService` is replaced and deepened as the decision-only `BrowserPrivacyEffectPolicyService`
module. Its
existing valid data distinctions become subordinate catalog implementation. The module's interface produces only a
Privacy Effect Decision: allow, deny, or confirmation required. It owns no execution, routing, cleanup, Toast, dialog,
or target substitution. The feature's narrative owner re-evaluates current facts at its commit seam and executes the
effect; ArkUI availability is advisory, and repositories preserve storage invariants without maintaining a second
privacy policy.

Private Session Cleanup remains domain-owned. Browser Window Session provides lifecycle facts, while Download, Media,
permission, authentication-prompt, and other owners remove and verify their own session-local state. The policy catalog
classifies retention semantics but owns no cleanup timer, deletion operation, or callback host.

`BrowserPrivateBoundaryNavigationService` is removed after its non-frozen callers migrate and no protected dependency
remains. Route facts remain with existing navigation and profile owners, presentation text remains operation-local, and
cleanup remains with state-owning domains. No long-lived compatibility adapter or dual active policy source is allowed
for migrated non-Sync intents. Its existing frozen Sync gate is not moved, refactored, or deleted under this decision;
if that dependency prevents final module deletion, migration stops with the frozen Sync surface untouched and requires
separate explicit Sync-change authorization.

## Product Behavior

- Device-wide Settings destinations remain available from a Private Browsing Session. Theme, Toolbar, Search, user
  agent, Labs, content filtering, userscripts, and Download policy retain their own membership, platform,
  authentication, and dangerous-action constraints.
- App Service Mode is a compound Settings action rather than one blanket private gate. Full mode is a device-preference
  write and remains available from a Private Browsing Session. Basic mode also deactivates Sync through the frozen Sync
  Experience owner, so that choice retains the separately classified remote-account/Sync denial in private browsing;
  the App Service Mode owner checks both child effects before its first write.
- Membership entitlement reads and use of an otherwise allowed feature are not membership mutations. Login, account
  profile reconciliation, purchase, restore, referral redemption, and remote membership changes remain separately
  restricted intents. Account profile reconciliation may register/update the known account in a regular session, but
  it does not create or read referral artifacts and never runs as part of entitlement refresh.
- A Regular Profile Management Surface may explicitly display and manage regular History, Bookmark, Download, and
  Offline Page records while remaining persistently labelled as regular-profile data. Its authority never injects
  those records into private Home, suggestions, autofill, recently closed, or Web runtime.
- Navigation, mutation, share, and export from a management surface are separate intents. Opening a selected regular
  History or Bookmark record defaults to a new tab in the current Private Browsing Session; open-in-regular is a
  separate user-selected intent. Existing domain-specific destructive confirmations remain authoritative without an
  additional generic private-mode prompt.
- Explicit Bookmark HTML import targets the currently labelled regular or private Bookmark scope, and explicit export
  may write that scope to the user-selected system-picker destination. Private provenance alone does not disable either
  operation; the Bookmark owner still re-evaluates the scope mutation or external export at the commit seam.
- Explicit Offline Page save is allowed from a Private Browsing Session and writes to the clearly labelled regular
  Offline Page destination. The Offline Page owners re-evaluate save, management read, mutation, navigation, share, and
  export at their execution seams. Private-origin management may use an already stored or in-memory icon, but it does
  not start favicon network prewarming or persist incidental record-status repair.
- Manual element hiding from a private page may create a device-wide filtering rule after the filtering owner
  re-evaluates the device-preference write. Built-in page-resource discovery and ArkWeb media takeover remain available
  as current-session capabilities; private diagnostic logging stays suppressed, and third-party userscript-initiated
  media probing remains unavailable with the rest of private userscript execution.
- Recently Closed records, tab/session restore traces, ambient History and search recording, and automatic icon-cache
  refresh remain isolated from Private Browsing Sessions. These are not Regular Profile Management Surfaces under this
  decision.
- Password and account data retain their own authentication and disclosure rules.

The sealed Sync contract, Private Browser Home fail-closed contract, and Window-Open/BFCache contract are unchanged.
This decision does not authorize editing frozen Sync implementation or allowing remote Sync effects from a Private
Browsing Session.

## Migration And Verification

Migration proceeds in six tracer slices:

1. Establish the policy foundation and migrate Download, restoring private contextual Download Settings while
   preserving task isolation, temporary-file behavior, explicit system export, record persistence, and cleanup.
2. Separate membership entitlement reads/feature use from membership mutations.
3. Migrate device-wide Settings destinations and mutations.
4. Consolidate regular/private Bookmark scope inside the Bookmark narrative owner.
5. Separate ambient History recording from explicit regular-profile management.
6. Migrate remaining non-frozen callers and delete `BrowserPrivateBoundaryNavigationService` only if no protected Sync
   dependency remains; otherwise stop, report the exact dependency, and request explicit Sync-change authorization.

Every slice removes the corresponding legacy gate. Policy interface tests cover allow, deny, confirmation, unclassified
fail-closed behavior, and catalog completeness. Feature-owner tests cover the target domain's action and cleanup
invariants; ArkUI tests cover state mapping rather than policy authority. A full build is required, while proportional
true-device interaction and lifecycle acceptance remains separate evidence and uses no visual capture without explicit
authorization.

## Considered Options

- Keep `allowed = !isSessionEphemeral` as the shared rule. Rejected because it conflates ambient traces, session-local
  behavior, explicit persistence, device preferences, regular-profile management, and remote mutation.
- Let each feature classify its own effect. Rejected because caller-declared safety creates a policy bypass and loses
  locality.
- Make the privacy module execute actions or own presentation and cleanup. Rejected because its interface would again
  span unrelated domains and become shallow.
- Silently downgrade denied effects to session-local alternatives. Rejected because the resulting decision would no
  longer describe the effect the user requested.
