---
status: accepted
supersedes: none
---

# Bottom Toolbar Uses a Device-Local Interaction Profile

Accepted 2026-07-31. The Root Bottom-Panel toolbar has four physical action slots shared by Browser Home and ordinary
Web browsing. Aira stores one device-local profile of ten independent assignments: tap and long press on every slot,
plus upward swipe on the two outer slots. Assignments use the same action semantics and live availability rules regardless
of interaction kind.

| Physical slot | Tap | Long press | Upward swipe |
|---|---|---|---|
| Far left | Required; default Back | Optional; default no action | Optional; default Home |
| Address-left | Optional; default Menu | Optional; default no action | Not supported; upward drag expands the toolbar |
| Address-right | Optional; default Reload | Optional; default no action | Not supported; upward drag expands the toolbar |
| Far right | Required; default Tabs | Optional; default no action | Optional; default Home |

The action catalog contains Back, Menu, Reload, Tabs, and New Tab followed by every customizable expanded-toolbar quick
action. New Tab reuses the tab manager's foreground creation flow and the current regular/private session boundary, but
remains assignment-only and does not become an expanded-toolbar quick entry.
Duplicate assignments are intentional: choosing an action changes only the selected slot and interaction, never swaps or
deduplicates another assignment, and never removes that action from the expanded-toolbar roster. All catalog entries stay
selectable in settings; runtime context decides whether an invocation is currently available.

An address-adjacent tap set to no action collapses that button completely and lets the address field reclaim its width.
Its independent long-press assignment remains stored but inactive until a tap action restores the button; ordinary chrome
must not expose an invisible hit target. The customization preview represents a collapsed inner slot with the licensed
user-provided `Empty.svg` marker so the user can reopen its editor. This marker appears only in the configuration preview,
not in ordinary browser chrome, and implementation must import it through the canonical Aira icon-font source manifest and
generators rather than ship a one-off runtime SVG.

Ordinary chrome represents tap only: the visible icon and disabled appearance come from the tap assignment, while long
press and upward swipe add no badge or persistent marker and cannot dim the button. An unavailable configured gesture
shows the action's existing brief rejection message and never falls back to another command. A no-action long press or
upward swipe remains completely silent.

One touch executes at most one assignment. Meaningful upward movement cancels tap and long press. A stationary long press
uses the existing approximately 450ms convention, gives one light haptic when a configured assignment is recognized,
executes immediately at recognition, and consumes release. Outer upward swipe keeps the existing release-to-commit
contract: crossing the threshold gives one light haptic and shows a natural action-specific instruction such as
`松手打开书签`, `松手刷新`, or `松手展开工具栏`; release while armed executes, and pulling back before release cancels.
Gesture timing and distance are not user-configurable.

Selecting a physical position in the configuration-only toolbar preview opens that slot's interaction overview. Outer
slots show tap, long press, and upward swipe; address-adjacent slots show tap and long press. Choosing an interaction opens
one grouped picker: optional no action first where allowed, then the five browser-core actions, then quick actions in the
user's expanded-toolbar order. The picker has no search. Selection saves immediately, refreshes the preview, and returns
to the slot overview. Slot reset immediately restores that slot's defaults; whole-profile reset restores all ten after
confirmation. Neither reset changes the expanded-toolbar roster.

Existing tap customization survives upgrade, and only the six new gesture assignments receive defaults. The complete
profile remains outside Personalization Sync, matching the existing slot fields and preserving the frozen Sync contract.
Offline viewing, reader mode, document viewing, tabs overview, and other special surfaces keep their dedicated controls
and interaction semantics.

`BrowserRootBottomPanelSessionCoordinator` remains the single runtime narrative owner for toolbar gesture arbitration,
prompt state, threshold feedback requests, availability-aware action dispatch, and release commitment. Existing toolbar
customization and bottom-chrome view models project persistence and presentation beneath that owner. ArkUI components
remain gesture ingress and rendering surfaces. `BrowserShellPage.ets` must not acquire assignment policy, prompt copy,
gesture arbitration, action construction, or new page-owned timers; any unavoidable page wiring must accompany the
required feature-adjacent extraction and reduce page-owned logic.

Implementation acceptance must cover short tap, stationary long press, slow and fast upward drag, pull-back cancellation,
tap-disabled with gesture-enabled combinations, no-action silence, unavailable-action feedback, both Home and ordinary
Web scenes, collapsed inner-slot geometry, persistence across restart, and preservation of existing tap choices. Build
evidence alone does not establish composed ArkUI gesture behavior; true-device acceptance is required, without visual
capture unless separately authorized.
