# Canonical Aira Icon Catalog Is the Single Authority

Accepted: 2026-07-20

## Context

Aira's UI icon mappings were previously split between design-source SVGs, a handwritten generator table, compatibility
maps, surface groups, runtime resource resolvers, and multiple theme/scene copies. The old pipeline expanded 98 canonical
SVG sources into hundreds of packaged resources. Keeping that source set alongside a font would create permanent dual
authority and make later icon changes difficult to audit.

Not every app image is an Operational Icon. Brand logos, third-party app/search-engine/provider identities, dynamic site
icons, launcher artwork, and multi-color layout previews must preserve image fidelity and remain with their image owners.
HarmonyOS Form surfaces also continue to use five explicit SVG Operational Icons until custom-font support is officially
confirmed or proven on device.

## Decision

`resources/icon-sources/aira/icon-catalog.json` is the single human-authored authority for Aira Operational Icon semantic
identities, legacy resource aliases, groups, representation state, and exact glyph mappings. `icon-map.json`,
`icon-map.csv`, `icon-groups.json`, packaged compatibility SVGs, the generated ArkTS catalog, and the packaged TTF are
derived artifacts rather than peer authorities.

Aira permanently uses the vendored Lucide 1.38.0 source pack for ordinary Operational Icons. The checksum-pinned
`vendor/lucide/aira-operational-icons/source-manifest.json` owns each glyph name, Lucide slug, source SVG, and stable BMP
private-use codepoint. Existing codepoints are immutable. A future glyph is appended with a new unused codepoint, added
to the semantic Catalog, and regenerated into the same font; glyphs may not be silently renamed, reassigned, guessed, or
substituted.

The current catalog has 159 font-backed semantic icons sharing 124 glyphs and five Form-quarantined SVG icons. Old custom
Operational SVG sources and the former Phosphor Regular/Medium/Bold/Fill font family are not retained as fallbacks.
`legacyResourceFamily` remains compatibility metadata for action catalogs and exports, not a second source of artwork.

While `Resource` callers remain, the catalog owns a compact set of exact legacy-output profiles. Five frozen
settings/Sync colored-tile identities receive base/dark SVGs generated from their Lucide source glyphs, one activity
identity receives a white SVG, and the five Form icons retain base/dark SVG output. The generator fails on extra,
unclassified, overlapping, or stale packaged SVG paths.

`resources/icon-sources/aira/image-assets.json` is a separate image-owner manifest. It preserves Aira branding,
third-party raster sources, and explicitly classified identity/decorative SVG exceptions without adding them to the
Operational Icon font.

Third-party homepage documents reuse the same packaged Operational Icon TTF through the owned `AiraHome` Bridge.
Document start installs only the lightweight helper/API; the first System Shortcut render requests the cached Base64
font payload once through the existing native JavaScript proxy and registers it under the stable Web alias. The complete
font payload must not be embedded in the document-start script because ArkWeb device verification showed that the large
bootstrap did not become the active page Bridge, while the later zero-payload bootstrap did. System Shortcuts are
exposed as semantic icon IDs plus font glyph presentation and are rendered through
`AiraHome.renderShortcutIcon()`. Bridge installation does not eagerly fetch the font; `AiraHome.prepareIconFont()` is an
explicit opt-in prewarm for homepages that need it before their first icon render. Homepage authors do not load another
font or depend on the current vendor. Web
Shortcuts, brand assets, and site icons remain image-rendered. No third-party-homepage SVG compatibility set is generated.

## Considered Options

- Keeping the old custom SVG set beside Lucide was rejected because it preserves dual authority and unused assets.
- Keeping Phosphor as a runtime fallback was rejected after the user permanently accepted Lucide.
- Converting brands, third-party applications, providers, or favicons into font glyphs was rejected because identity and
  dynamic imagery remain image-owned.
- Editing frozen Sync surfaces merely to remove six `Resource` reads was rejected; generating those compatibility SVGs
  from the Lucide source pack preserves the frozen contract without preserving old artwork.
- Automatic filename-to-glyph matching was rejected because it hides semantic review and codepoint mistakes.

## Consequences

Future Operational Icon additions require a licensed SVG, a new append-only source-manifest codepoint, and an explicit
semantic Catalog mapping. The font, Catalog artifacts, compatibility SVGs, architecture guards, and app build must be
regenerated and verified together. Form SVGs and image-owned assets remain explicit exceptions. Phosphor, obsolete custom
Operational SVGs, and unreferenced compatibility variants must not be restored without a new architecture decision.
