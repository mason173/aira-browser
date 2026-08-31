# Novel Rules Use Signed Declarative Cloud Snapshots

Accepted: 2026-07-29
Status: Superseded for current clients on 2026-09-01

## Package-owned revision

The open-source release preparation moved the complete Novel Rules catalog into the App package. `NovelRuleCatalog`
now performs synchronous packaged rule/blocklist resolution only; manifest fetch, watch, envelope verification, expiry,
ETag, and app-private cache code are deleted. Rule changes require source review and an App release. The private server
endpoint remains temporarily for already-installed older clients and is not a dependency of the current client.

The package snapshot includes the five enabled entries from the last active manifest (`site.bqgnovels`, `site.80dzs`,
`site.mayitxt`, `site.trxsw`, and `site.80ge`) plus its reviewed false-positive exclusions. Mixed video properties remain
path-scoped, so the Bilibili, iQIYI, and twxgct/xgcartoon exclusions do not suppress their entire domain families. The
same bounded same-origin path and content-quality gates continue to apply after changing the delivery mechanism.

The original decision below is retained as delivery-history context; its remote lifecycle is no longer current.

## Context

Novel sites regularly rename containers or adjust chapter/catalog markup. Keeping every selector only in the App made a
small compatibility repair wait for a full App release, while accepting remote executable extraction code would give a
configuration endpoint the same authority as application code running inside arbitrary pages.

The current extraction flow already has a coherent owner: `NovelExtractionService` decides detection, page extraction,
special acquisition, quality fallback, and result parsing. Cloud update support must preserve that narrative flow rather
than create a second extraction engine.

## Decision

`NovelExtractionService` remains the narrative owner. Its subordinate `NovelRuleCatalog` exposes synchronous in-memory
rule resolution and a non-blocking deferred refresh. The catalog hides signature verification, schema validation,
precedence, App-version gating, expiry, ETag handling, and app-private cache replacement.

The server publishes a full compact RS256 envelope at `GET /novel-rules/v1/manifest`. The signature covers the exact
base64url header and payload bytes. The App pins the dedicated public key, key ID, issuer, schema version, maximum 45-day
validity window, rule/field sizes, and current minimum App version. The private key stays outside the repository and the
server refuses to publish when it does not match the tracked/App-embedded public key.

Remote entries may contain only:

- stable rule ID, enabled/disabled state, bounded hosts, and bounded path prefixes;
- `novel`/`comic` kind;
- bounded CSS selectors used by the existing extraction helpers;
- `reverseCatalog` and `catalogIncomplete` booleans.

As refined by ADR-0067, the same selectors may also locate Book/Chapter recognition evidence. They cannot directly mark
a page eligible: compiled structural gates still require bounded same-origin Catalog links or accepted Chapter content,
title, and navigation evidence before Novel Mode is offered.

Remote entries cannot contain executable JavaScript, User-Agent policy, cookies, request headers, credentials,
cross-origin acquisition instructions, or a `chapterSource`. Authoring notes and local special-acquisition recipes are
never projected into page JavaScript.

Resolution order is fixed:

1. packaged hard blocklist;
2. valid signed remote disable entry;
3. valid signed remote rule;
4. packaged site rule;
5. generic extraction.

A disabled entry is a site-suppression decision, not an extraction fallback. `NovelExtractionService` resolves it before
running DOM detection, so the same result prevents candidate acquisition, floating Novel entry, and automatic takeover.
Suppression remains limited to reviewed host suffixes and optional path prefixes; the cloud cannot infer a content
category, execute code, or supply a regular expression.

The initial editorial/news/forum/video suppression batch follows a conservative scope rule: dedicated non-novel domains
may be blocked as a whole, large portals use exact news/video subdomains, and mixed properties use explicit video path
prefixes. In particular, the Bilibili and iQIYI rules do not block their entire domain families, while the VGN rule
covers both the public origin and its canonical redirect host. The authoring Manifest remains the exact current list.

An expired, malformed, incompatible, oversized, rollback, unavailable, or bad-signature manifest is ignored. The highest
accepted signed revision and its exact signed content identity survive expiry and process restart, so a lower revision or
different content reusing the same revision is rejected. A failed or low-quality remote content selector falls through
the existing same-request DOM/general quality paths. Cached remote data is used only while its signed validity window is
active; browsing never waits for cache or network I/O. Cache writes use an fsynced `next` file plus recoverable
`previous` state because the platform does not document overwrite-rename crash atomicity.

Remote selector-derived chapter links, catalog links, pagination, interactive catalog frames, and observable ArkWeb
redirects must remain HTTP(S), same-origin, and inside the signed rule's path prefixes. Remote selectors are never passed
to the native direct-HTML fallback because the platform response does not expose the effective URL after a redirect;
that fallback retains only its existing generic/bundled behavior. A remote rule cannot expand acquisition beyond its
signed host/path scope.

## Operations

The authoring snapshot is `server/novel-rules/manifest.json`. Every content change raises `revision` and sets a fresh
`issuedAt`/`expiresAt` window. The server watches file identity on requests and signs a changed snapshot without a
restart. ETag/304 avoids retransmitting an unchanged signed envelope. Key rotation requires both a server public/private
key change and an App release containing the new public key and identity. The App performs its first refresh from the
existing deferred warmup, then reuses the catalog's six-hour due check on later foreground transitions; concurrent calls
remain coalesced by the catalog.

## Consequences

- Site selector and bounded recognition-evidence fixes can ship independently of App releases after server publication.
- Reviewed false-positive sites can also be suppressed for already-compatible clients through a signed disabled entry.
  Category-oriented suppression stays remote so a higher-revision Manifest can withdraw an over-broad rule immediately;
  the packaged hard blocklist remains reserved for sites with no usable online reading surface.
- Loss of the endpoint, signing key, network, or cache cannot remove packaged behavior.
- The cloud surface is intentionally less expressive than the local `NovelSiteRule`; special transports remain compiled,
  reviewed App behavior. A remote override inherits a compiled special transport only when its stable ID and complete
  host/path scope exactly match the bundled rule; overlapping aliases are rejected.
- Adding new remotely writable capabilities requires an explicit schema and ADR revision, not an untyped metadata field.
