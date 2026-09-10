# Aira Operational Icon source snapshot

This directory holds Aira's vendored Operational Icon source pack, currently containing 124 glyphs.

- Family: Aira Operational Icons
- Current source: Tabler Icons outline 3.46.0 (`@tabler/icons`), MIT
- Directory name `lucide/` is historical. Semantic glyph keys, Lucide slugs in the manifest, and BMP private-use
  codepoints stay stable so ArkTS consumers do not change.
- Scope: Operational Icons only; brand logos, third-party app icons, search-engine icons, favicons, launcher artwork,
  and other identity-bearing images remain outside this font
- `svg/`: vendored Tabler outline sources normalized to the Aira 30x30 viewBox
- `source-manifest.json`: append-only Aira glyph key/codepoint, historical Lucide slug, source filename, and pinned checksum
- `AiraOperationalIcons.ttf` and `selection.json`: deterministic generated runtime outputs with stable Aira names
- `LICENSE`: Tabler MIT license text

The complete AI-safe replacement/addition workflow is maintained in
[`resources/icon-sources/aira/README.md`](../../../README.md).

Existing codepoints must never be reassigned. For a new glyph, append a manifest entry with a new unused BMP private-use
codepoint and add the corresponding semantic Catalog mapping. For a visual replacement, keep the existing glyph and
codepoint and replace only its licensed SVG source. Use the complete workflow in the parent README to import the source
set and update all pinned hashes.

Regenerate the font with:

```bash
fontforge -lang=py -script scripts/generate-aira-icons-font.py
```

Tabler's MIT license is at `LICENSE` in this directory and is also listed in the repository's `THIRD_PARTY_NOTICES.md`.
