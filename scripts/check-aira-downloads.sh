#!/bin/sh
# One reliability gate shared by local builds and CI. No devices or public sites.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
download_node=${AIRA_NODE_BIN:-node}
for check in \
  check-aira-download-lifecycle.cjs \
  check-aira-hls-progress.cjs \
  check-aira-arkweb-download-recovery.cjs \
  check-aira-download-redirect-request.cjs \
  check-aira-download-request-context.cjs \
  check-aira-resource-download-context.cjs \
  check-aira-media-resource-selection.cjs \
  check-aira-media-discovery.cjs \
  check-aira-media-resource-names.cjs \
  check-aira-media-durations.cjs \
  check-aira-download-directory-lifecycle.cjs \
  check-aira-download-export-ghost-guard.cjs \
  check-aira-download-selection.cjs \
  check-aira-download-rewind-does-not-move-page.cjs
do
  "$download_node" "$root/scripts/$check"
done
"$root/scripts/check-download-native.sh"
"$root/scripts/check-download-proxy.sh"
echo 'Download reliability suite passed.'
