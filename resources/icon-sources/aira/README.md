# Aira Icon Sources

This folder contains the Canonical Aira Icon Catalog and its source inputs. The human-maintained authority is
`icon-catalog.json`; files under `AiraBrowser/entry/src/main/resources/**/media` are generated variants and should not
be edited by hand.

- `icon-catalog.json` is the sole authority for Aira Operational Icon identities, groups, legacy resource aliases,
  Lucide glyph mappings, the five Form SVG exceptions, and the small deterministic compatibility-output inventory.
- `image-assets.json` is the separate owner manifest for brand/third-party image sources, their compatibility export
  group, and the explicit packaged-SVG exception inventory. Entries here are not Operational Icons.
- `icons/` contains the five Form-only Operational SVG sources plus approved brand/third-party image assets. Ordinary
  Operational Icons no longer keep a parallel custom SVG source here.
- Files are named as `<primary_app_resource_family>__<source_label>.<ext>` so design exports and official assets can be matched back to app resources.
- `icon-map.csv`, `icon-map.json`, and `icon-groups.json` are derived compatibility artifacts. Do not edit them directly.
  They combine Operational Icon projections from the catalog with image-owned compatibility entries from the image
  manifest. The catalog group `bottom-toolbar-customizable` is the authority for the Settings > Bottom toolbar draggable
  action icons.
- `vendor/lucide/aira-operational-icons/` contains the vendored Lucide 124-SVG source set, a checksum-pinned append-only
  codepoint manifest, and the generated permanent Operational font.
- The generator packages the single Operational font under `rawfile/fonts/aira/` and derives
  `core/resources/GeneratedAiraIconCatalog.ets`. App code consumes semantic icon IDs from that generated catalog; it does
  not hand-maintain codepoints, font families, rawfile paths, or legacy Resource switches.
- `legacyResourceFamily` remains compatibility metadata for action catalogs and design exports. Old custom Operational
  SVGs are not retained after their Lucide glyph is adopted.
- Six frozen settings/Sync `Resource` consumers receive compatibility SVGs generated from the same Lucide source pack;
  these are not a second icon design source. The colored tile background remains owned by `SettingsRows.ets`.
- Official raster brand assets are copied without recoloring. Their source URLs and any lossless format conversion are
  recorded in `image-assets.json` and projected into `icon-map.csv` and `icon-map.json`.

Brand logos, third-party application icons, dynamic site icons, launcher artwork, and other identity-bearing or dynamic
images are intentionally outside the Operational Icon catalog. Desktop-card operational icons remain cataloged but keep
their legacy SVG representation until custom-font support in Form surfaces is verified.

## AI-safe workflow for licensed SVG changes

Every user-provided SVG change must follow this workflow. First decide whether it is a visual replacement or a genuinely
new Operational Icon:

- **Visual replacement:** keep the existing semantic Catalog ID, manifest `glyph`, `sourceFile`, and BMP private-use
  `codePoint`. Replace only the licensed SVG bytes; do not append a second glyph or change consumers.
- **New icon:** append one entry to `vendor/lucide/aira-operational-icons/source-manifest.json` with a new unique glyph
  name, the next unused BMP private-use `codePoint`, Lucide slug, and `svg/<filename>`, then add the semantic mapping to the
  human-maintained `icon-catalog.json`. Existing codepoints are immutable.

Brand logos, third-party app/provider icons, favicons, launcher artwork, and other identity-bearing or dynamic images do
not enter this font. Keep them image-owned. Do not hand-edit `icon-map.csv`, `icon-map.json`, `icon-groups.json`,
`GeneratedAiraIconCatalog.ets`, or packaged `media` outputs; they are generated artifacts.

### 1. Validate and collect the Lucide source

The importer accepts only SVGs with `viewBox="0 0 30 30"`, at least one non-empty `<path>` or `<polygon>` outline, and no
executable/external SVG content.
Keep the normalized source file bytes stable. Before changing an existing icon, locate its semantic ID and immutable
codepoint in `icon-catalog.json` and `vendor/lucide/aira-operational-icons/source-manifest.json`.

### 2. Resolve `新增修改` or other override folders deterministically

`import-aira-lucide-source-pack.js` requires exactly one source path for every unique Lucide slug in the manifest. It
allows one Lucide SVG to serve multiple Aira glyphs and writes each result to the canonical `svg/<glyph>.svg` path. When
an override folder contains a duplicate Lucide filename, build a temporary flat input directory so the intended file wins:

```bash
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cp /absolute/path/to/lucide-svg-directory/*.svg "$tmp/"
cp /absolute/path/to/lucide-svg-directory/新增修改/*.svg "$tmp/"
node scripts/import-aira-lucide-source-pack.js "$tmp"
```

The temporary directory is only importer input; it must not be committed. If there is no duplicate basename, the original
licensed directory can be passed directly.

### 3. Regenerate the font and synchronize checksums

Run FontForge after every replacement or addition:

```bash
fontforge -lang=py -script scripts/generate-aira-icons-font.py
```

`icon-catalog.json` pins the generated font, selection file, and source manifest. After FontForge/importer changes, update
the three matching hash fields (`fontSha256`, `selectionSha256`, `sourceManifestSha256`) with:

```bash
shasum -a 256 \
  resources/icon-sources/aira/vendor/lucide/aira-operational-icons/AiraOperationalIcons.ttf \
  resources/icon-sources/aira/vendor/lucide/aira-operational-icons/selection.json \
  resources/icon-sources/aira/vendor/lucide/aira-operational-icons/source-manifest.json
```

Only then regenerate the derived Catalog and packaged resources:

```bash
node scripts/generate-aira-icons-from-source.js
```

For a visual replacement, the selection checksum normally stays unchanged because the glyph/codepoint set is unchanged;
still verify it instead of assuming.

### 4. Verify before handing off

Run all of the following, in order:

```bash
node scripts/check-aira-icon-catalog.js
scripts/check-aira-icons-generated.sh
git diff --check
```

Review `git diff --name-only` and keep unrelated ADRs, Sync work, build-profile files, and other agents' planning folders
out of the icon change. For user-visible app changes, build and install with:

```bash
./scripts/install-aira-browser.sh
```

The installer must report `install bundle successfully`. Do not launch or visually operate the user's device unless the
user explicitly asks for that inspection.

To verify generated resources are current:

```bash
scripts/check-aira-icons-generated.sh
```

To export one product surface for design replacement:

```bash
node scripts/export-aira-icon-group.js bottom-toolbar-customizable
node scripts/export-aira-icon-group.js settings-colored-tile-foreground
```

The export goes to `~/Downloads/aira-icon-groups/<group-id>` by default and includes:

- `icons/`: editable source SVGs for that group.
- `icon-group-map.csv` and `icon-group-map.json`: action/resource/source mapping.
- `README.md`: short instructions for the exported group.

When changing the bottom toolbar icon set, update `icon-groups.json` and the app action catalog together. The build guard
checks that `bottom-toolbar-customizable` still matches `BrowserBottomPanelActionCatalog.customizableActionIds()`.
