# Desktop Bookmark Bar is boundary-aware Large-Screen chrome

Accepted: the Desktop Bookmark Bar is a device-local, Large-Screen browser-chrome surface that remains visible across ordinary Browser Home, Web, and native management scenes when enabled (default on), renders only the direct children of the current privacy boundary's Bookmark Toolbar collection, and stays separate from Home Shortcuts and the Bookmark Manager. It keeps a fixed compact row with a leading management entry and trailing overflow, while editing, deletion, ordering, and drag interactions remain in Bookmark Manager; this preserves a stable desktop browsing surface without crossing privacy scopes or turning persistent chrome into a second management workspace.

## Consequences

- The feature is absent from Phone Shell and existing chrome-less WebApp/fullscreen/native-takeover presentations.
- Visibility is device-local and does not participate in Personalization Sync.
- Large-Screen presentation code owns rendering and event forwarding; bookmark repositories and browser intent owners remain the sources of truth for data and navigation.
