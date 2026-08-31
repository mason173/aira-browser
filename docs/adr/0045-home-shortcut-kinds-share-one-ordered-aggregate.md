# Home Shortcut kinds share one ordered aggregate

Web Shortcuts and System Shortcuts share the existing Home Shortcut record, repository, order, deletion, and synchronization flow, distinguished by the existing nullable `kind` field and a stable target identity. This keeps one user-visible ordered collection and avoids a second table, repository, merge policy, or parallel ordering system; missing kind is treated as Web Shortcut and Home Add Entry remains derived presentation outside the aggregate.

The same ordered collection is exposed to third-party homepages through `AiraHome.getShortcuts()` and
`AiraHome.reorderShortcuts(ids)`. The reorder request must contain the complete current shortcut ID sequence,
including System Shortcuts. System Shortcut titles and targets remain Aira-owned and immutable; their list positions
are user-controlled just like Web Shortcuts.

The third-party presentation contract preserves the same aggregate while keeping representation ownership separate:
System Shortcuts use Aira's shared Operational Icon font through `AiraHome.renderShortcutIcon()`, while Web Shortcuts
continue to expose image or fallback presentation. Homepage packages must not persist or interpret private font
codepoints as shortcut identity; `id`, `kind`, and `iconId` carry those stable meanings.

Amended 2026-08-08: destination identity is an aggregate invariant, not a selection-sheet convenience. One active
System Shortcut target and one normalized Web destination may appear at most once in the user-visible Home collection.
Scenario IDs remain storage/order metadata and do not partition that single destination-identity namespace.
Local toggle/add mutations are serialized and duplicate in-flight requests for the same destination share one result.
The Shortcut Repository's active aggregate projection deterministically keeps the lowest-position record, then the
earliest-created record, then the lowest stable ID for every consumer. Personalization Sync applies the same winner rule after record-ID merge; every additional active record for
that destination becomes a normal versioned tombstone with a revision newer than all members of the duplicate group, so
all Providers and devices converge without a startup migration, database sweep, physical deletion, or presentation-only
exception. Existing tombstones retain their ordinary ID-based merge semantics, and Provider-switch live-preservation
rules remain unchanged.
