# Lucide Operational Icon source snapshot

This directory is Aira's vendored Lucide Operational Icon source pack, currently containing 124 glyphs.

- Family: Lucide Operational Icons
- Source: Lucide Static 1.38.0, distributed under the ISC license
- Scope: Operational Icons only; brand logos, third-party app icons, search-engine icons, favicons, launcher artwork,
  and other identity-bearing images remain outside this font
- `svg/`: vendored Lucide source files normalized to the Aira 30x30 viewBox
- `source-manifest.json`: append-only Aira glyph key/codepoint, Lucide slug, source filename, and pinned checksum
- `AiraOperationalIcons.ttf` and `selection.json`: deterministic generated runtime outputs with stable Aira names

The complete AI-safe replacement/addition workflow—including nested `新增修改` override handling, checksum updates, and
verification commands—is maintained in [`resources/icon-sources/aira/README.md`](../../../README.md).

Existing codepoints must never be reassigned. For a new glyph, append a manifest entry with a new unused BMP private-use
codepoint and add the corresponding semantic Catalog mapping. For a visual replacement, keep the existing glyph and
codepoint and replace only its licensed SVG source. Use the complete workflow in the parent README to import the source
set and update all pinned hashes.

The basic importer command is:

```bash
node scripts/import-aira-lucide-source-pack.js /absolute/path/to/lucide-svg-directory
```

Regenerate the font with:

```bash
fontforge -lang=py -script scripts/generate-aira-icons-font.py
```

The Lucide ISC license is included in the review directory at `../review-2026-09/LICENSE` and is also listed in the
repository's `THIRD_PARTY_NOTICES.md`.
