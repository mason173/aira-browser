# User Scripts and Ad-Block Subscriptions Are Local-Only

Accepted, superseding ADR 0037: user scripts and ad-block subscriptions do not participate in personalization sync. The app does not expose them as selectable sync items and does not serialize local content, merge remote content into local state, hydrate it, or apply it through Aira Cloud, Huawei Space, or WebDAV.

Normal app updates retain their device-local storage. Uninstalling the app may remove that local data, and reinstall does not automatically restore it. Existing remote sections are retired: current clients and Aira Cloud ignore and remove them from normalized active snapshots instead of preserving, applying, or copying them to another provider.

Bookmarks and the remaining personalization items continue using their existing synchronization behavior. This decision intentionally favors a smaller interface, less sync policy, and lower data-loss risk over cross-device restoration for extension content.
