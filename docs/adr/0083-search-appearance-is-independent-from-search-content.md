# Search Appearance Is Independent From Search Content

Accepted, 2026-10-16.

## Context

Phone navigation has three search appearances: floating, split, and dock. Split and dock share a
Search Invocation runtime adapter, but their editors belong at different edges. Previously that
distinction was spread across Shell routing, toolbar branches, and homepage geometry flags.
The dock editor also depended on a nonempty history or suggestion list occupying the space above
it. Empty or asynchronously changing content could move the editor to the top without actually
changing the selected appearance.

ADR-0050 already establishes one window-scoped Search Invocation Session and separates stable
surface identity from mutable suggestion content. This decision makes that rule explicit for
all three phone appearances and retains the existing large-screen and floating-panel owners.

## Decision

- `resolveBrowserSearchPresentationTarget` is the single mapping from the effective toolbar and
  shell facts to runtime host, search appearance, and centered-home geometry. Its interface has
  no query, result count, history content, or keyboard state. An unavailable host keeps its selected
  appearance; it does not fall back to another toolbar's search UI.
- Floating search retains `BrowserBottomAddressPanel` and its existing Root Bottom-Panel owner.
  Split and dock retain a shared session adapter but render separate fixed layout modules:
  `BrowserSplitSearchSurface` and `BrowserDockSearchSurface`. Each layout has one list direction
  and cannot choose a different appearance.
- Dock always mounts a weighted content viewport and a separate editor region. History,
  suggestions, loading, and empty content only replace descendants of the content viewport.
  The editor and engine menu are native builder slots capturing their existing UI owner; content
  updates do not recreate a search session or change editor placement.
- The native chrome keeps focus, IME execution, selection execution, and the centered-home editor's
  geometry-transition node. Split content reserves that top editor; dock content owns its bottom
  editor slot. Native pages forward accepted state and intents rather than normalize drafts again.
- `BrowserSplitToolbarSearchInvocationAdapter` normalizes fresh prefill and selection once. A
  reinforced or re-presented search preserves an edited draft, including an intentionally empty
  draft. Search Invocation Session remains the canonical draft and authority owner.
- `BrowserToolbarSearchPresentationCoordinator` owns native open-command versions and close
  generations. Acceptance invalidates an earlier close. Repeated close is idempotent; suspension
  supersedes a pending animated close. Old native animation completions cannot reset newer search.
- An explicit appearance change refreshes presentation even when the runtime host remains `split`
  (split to dock or dock to split). Content updates do not refresh presentation. Existing window
  session authority and draft survive the explicit change.

## Verification

`node scripts/check-aira-search-style-isolation.cjs` exercises the production Shell mapping and
mount binding, session/router/adapter handoff, actual Shell close/animation wiring, and the dock
builder's recorded layout. It covers fresh and repeated opens, edited and cleared drafts,
split/dock switching within the same host, late close completions, and empty/nonempty content with
and without a keyboard. Fixed layouts also cannot depend on toolbar-style fields.

This check complements native compilation. Native focus, IME, and geometry animation smoothness
still require device acceptance; source-level layout replay does not claim to render ArkUI pixels.

## Consequences

The three existing visual designs stay intact. Search content and submission capabilities remain
shared, while layout changes have locality in their own appearance. No persistence or Sync schema,
homepage selection semantics, account capability, or distribution configuration changes.
