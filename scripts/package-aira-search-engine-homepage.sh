#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
homepage_dir="$repo_root/samples/aira-search-engine-homepage"
manifest_path="$homepage_dir/aira-homepage.json"
stable_package="$repo_root/samples/aira-search-engine-homepage.zip"

version="$(
  MANIFEST_PATH="$manifest_path" node <<'NODE'
const fs = require('fs');
const manifestPath = process.env.MANIFEST_PATH;
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const version = String(manifest.version || '').trim();
if (!/^[0-9]+(?:\.[0-9]+){1,2}(?:[-+][0-9A-Za-z.-]+)?$/.test(version)) {
  throw new Error('samples/aira-search-engine-homepage/aira-homepage.json must define a semver-like version.');
}
process.stdout.write(version);
NODE
)"

versioned_package="$repo_root/samples/aira-search-engine-homepage-v${version}.zip"

for preview in preview-light.png preview-dark.png; do
  if [ ! -s "$homepage_dir/$preview" ]; then
    echo "Missing generated preview: $homepage_dir/$preview" >&2
    exit 1
  fi
done

rm -f "$stable_package" "$versioned_package"

(
  cd "$homepage_dir"
  zip -X -r "$versioned_package" \
    aira-homepage.json \
    index.html \
    styles.css \
    app.js \
    preview-light.png \
    preview-dark.png
)

cp "$versioned_package" "$stable_package"

echo "Built $versioned_package"
echo "Updated $stable_package"
