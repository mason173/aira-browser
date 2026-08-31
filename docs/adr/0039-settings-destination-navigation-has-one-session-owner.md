# Settings Destination Navigation Has One Session Owner

Accepted: Settings destination structure and navigation state are owned by one Settings Destination Navigation owner. Compact and two-pane Settings shells render the same logical Settings Navigation Session through a reactive `snapshot()`, `observe()`, and `dispatch(intent)` interface, so changing window size replaces only the shell and never creates, removes, or resets navigation entries.

The owner contains only structural navigation facts: the closed destination catalog and its group, title, icon, search, availability, presentation-capability, destination/detail/task relationships, route resolution, Back order, and commit rules. Passwords, downloads, WebApps, membership, and other settings domains continue to own their data, mutations, and feature-specific behavior. Primary tablet sidebar destinations always replace the two-pane detail root; ordinary deeper navigation advances within the active Settings Detail Stack; only explicitly declared immersive, multi-step, system, or external tasks may open full-screen. Missing declarations fail closed instead of selecting a placeholder or silently switching presentation mode.

Internally, the owner uses a closed catalog, a pure session reducer, staged navigation commands, and atomic commit. A command changes the published session only after the platform navigation succeeds; failure preserves the originating primary destination and detail stack. Switching primary destinations resets the one active detail stack to the new root. Back closes an active full-screen detail task first, then pops the detail stack, then returns a compact root detail to the directory; at a two-pane root, where the directory is already visible, Back exits Settings.

The only platform port is a Settings router interface with a production HarmonyOS adapter and an in-memory contract-test adapter. The router executes platform presentation but does not decide destination policy. The public interface does not expose a Destination Package extension seam until a second genuinely independent catalog provider creates that need.

## Considered Options

- Keep the current per-screen switches and presentation allowlists. Rejected because destination knowledge drifts across compact routing, two-pane selection, detail rendering, fallback handling, and Back behavior; the observed WebApps and Aira Pro regressions are consequences of that duplication.
- Expose only synchronous `read` and `navigate` calls. Rejected as the shell-facing interface because ArkUI callers would still coordinate refresh and publication, although its small reducer-and-command shape is retained internally.
- Publish a compiled Destination Package extension API now. Rejected because it would make authoring and compatibility interfaces larger before the app has multiple independent destination providers. Catalog completeness checks may still be used privately.
- Let compact and two-pane shells own separate navigation stacks. Rejected because rotation and window resizing would become navigation events and could change the user's destination or depth.

## Consequences

Migration proceeds destination by destination, beginning with `web_apps`. Each tracer slice moves that destination's catalog, presentation, stack, Back, and route behavior behind the owner and deletes the corresponding legacy switch or allowlist path in the same slice; old and new policy sources must not remain active together. Owner-interface contract tests cover compact and two-pane shells, detail depth, explicitly full-screen tasks, failed-command atomicity, shell resizing, Back order, primary-destination reset, and undeclared-capability failure.
