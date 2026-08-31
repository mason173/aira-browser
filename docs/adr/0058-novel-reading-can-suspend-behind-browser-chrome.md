---
status: accepted
---

# Novel Reading Can Suspend Behind Browser Chrome

A Novel Reading Session may be hidden behind Browser Home and ordinary browsing without being ended. The Novel session
owner retains the Book, loaded Chapter trail, Reading Anchor, preferences, source-scoped identity, source tab, and
presentation-ready state; Close, Return to source, explicit source-tab close, or successful user-authorized replacement
still ends that live session. The Home action is an optional fifth rightmost action in Novel and Comic body-reading
chrome only. It pauses automatic reading, dismisses transient reader surfaces, persists the current checkpoint, and uses
the existing Home route that preserves the source tab rather than the ordinary route that closes the current Web tab.

The expanded Root Bottom-Panel toolbar presents Continue Reading as its first section above the normal quick-action grid.
It shares that toolbar's container, material, motion, and lifecycle, but uses a fixed full-width action row with the
Reading icon, `继续阅读`, the ellipsized Novel title, and a trailing entry affordance. It is not an independent overlay,
not a customizable quick action, and has no adjacent destructive control. It is available on Browser Home and ordinary
Web browsing in the matching privacy boundary, absent on non-browsing surfaces and while the reader is visible, and is
the only Home-level continuation path; Back never resumes reading implicitly.

## Session and replacement contract

- One Novel session may be live per Browser Window Session and privacy boundary. Regular and private sessions never
  reveal, compare, resume, or replace one another. Private reading is ephemeral and produces no durable continuation.
- A session is bound to its source tab. Continue Reading activates that tab before revealing the reader. Home itself
  creates no tab, but Home-originated Search, shortcut, and bookmark navigation opens a new ordinary Web tab while the
  suspended source tab is protected from implicit reuse.
- Explicit source-tab close checkpoints and ends its live session. Background Web Runtime discard does not end it and
  continues through the existing runtime restore and protected-background pipeline.
- Automatic Novel takeover is suppressed while a session is suspended. A recognized Novel page may instead show the
  existing-style floating Novel Page Entry. Same source-scoped canonical book/catalog identity resumes the suspended
  session; cross-source title matches are different Novels.
- On a different Novel, tapping the floating entry is itself replacement authorization and does not open a second
  confirmation dialog. Replacement is staged: the old checkpoint and suspended session remain authoritative until the
  new Novel is identified and acquired successfully. Failure or uncertain identity leaves the old session intact.
- Automatic reading stops on suspension and remains paused after continuation. Catalog, settings, and dialogs are
  dismissed; continuation returns to clean body content at the retained Reading Anchor.
- Every new Web-to-Novel takeover prepares the source tab's shared preview through the existing tab-preview owner before
  the reader becomes visible. This includes automatic takeover and explicit manual takeover. A different-Novel candidate
  remains hidden and does not capture merely because it was recognized; after the user taps its Novel Page Entry, the
  source preview is prepared before the candidate replaces the retained session. Capture is best-effort and failure does
  not block reading, but takeover never starts the preview only after the Web surface has already been covered. The
  source tab must still be the visible Web surface both before and after the awaited capture; changing tabs or leaving
  Web, navigating that tab to another URL, crossing a privacy/data boundary, replacing its Web controller, or replacing
  the shell binding while capture is in flight cancels that stale takeover rather than revealing it over a different
  scene.

## Process recovery

Each regular Browser Window Session persists its own Novel Reading Recovery Marker containing the source-scoped identity, source destination,
display title, and Reading Checkpoint needed to attempt cold reconstruction. After process termination the same Continue
Reading row may rebuild the session with an honest loading state; this is checkpoint recovery, not a claim that the live
presentation survived. An irrecoverable marker is removed from Continue Reading presentation while any still-valid
reading checkpoint remains available through ordinary Novel resume paths. Private browsing never writes this marker.

## Ownership

`NovelReaderSessionCoordinator` is the single window-level narrative owner for privacy-boundary isolation, staged
replacement, continuation presentation, and recovery-marker state. Its subordinate `NovelReaderController` owns one
privacy boundary's live suspension, continuation eligibility, source-scoped identity, and checkpoints; persistence
remains subordinate rather than becoming a peer flow owner. `BrowserTabHomeCoordinator` and the existing tab/runtime
owners execute source-tab activation, preserving Home navigation, protected Home-originated navigation, tab close, and
runtime lifecycle effects. The existing tab-preview action/coordinator pipeline owns source-card capture and persistence;
the Novel session owner owns only the pre-takeover ordering barrier. The root bottom-panel presentation owner supplies the Continue Reading view state and
`BrowserBottomAddressPanel` only renders and forwards its action. `ReadingExperienceChrome` accepts an optional fifth
action, while Novel UI wiring forwards the typed action and Article reading remains unchanged. Any unavoidable
`BrowserShellPage.ets` change is one-line binding/event forwarding and must include a cohesive extraction from the touched
area under the page-debt rule.

The Root Bottom-Panel Session treats both Article Reader and Novel Reader visibility as exclusion facts for its panel
host and expanded Scrim. Neither browser-chrome surface may remain mounted above a visible reading surface during
continuation.

This design deliberately keeps a suspended live session distinct from the older URL-backed Novel re-entry affordance:
Continue Reading reveals retained state, whereas re-entry after a true close reacquires from a Web source. It also keeps
the feature outside Bookmark/Personalization Sync and does not change any frozen Sync contract.
