#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
homepage_dir="$repo_root/samples/aira-minimal-homepage"
stable_package="$repo_root/samples/aira-minimal-homepage.zip"
release_version="${1:-}"
package_target="$stable_package"

if [ -n "$release_version" ]; then
  if ! printf '%s' "$release_version" | grep -Eq '^[0-9]+([.][0-9]+){1,2}([-+][0-9A-Za-z.-]+)?$'; then
    echo "Usage: $0 [semver-like-release-version]" >&2
    exit 1
  fi
  package_target="$repo_root/samples/aira-minimal-homepage-v${release_version}.zip"
fi

rm -f "$stable_package"
if [ "$package_target" != "$stable_package" ]; then
  rm -f "$package_target"
fi

(
  cd "$homepage_dir"
  zip -X -r "$package_target" \
    aira-homepage.json \
    index.html \
    preview-light.jpg \
    preview-dark.jpg \
    assets
)

if [ "$package_target" != "$stable_package" ]; then
  cp "$package_target" "$stable_package"
  echo "Built $package_target"
fi
echo "Updated $stable_package"
