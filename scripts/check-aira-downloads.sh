#!/bin/sh
# One reliability gate shared by local builds and CI. No devices or public sites.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
download_node=${AIRA_NODE_BIN:-node}
# Always exercise orchestration first; the real HTTP fixture below remains mandatory.
"$download_node" "$root/scripts/check-aira-download-redirect-request.cjs" --control-only
for check in \
  check-aira-download-lifecycle.cjs \
  check-aira-download-failure-mapper.cjs \
  check-aira-download-repository.cjs \
  check-aira-download-finalization.cjs \
  check-aira-download-destination.cjs \
  check-aira-download-background-recovery.cjs \
  check-aira-download-pending-lifecycle.cjs \
  check-aira-download-source-boundary.cjs \
  check-aira-download-file-actions.cjs \
  check-aira-web-image-context.cjs \
  check-aira-download-history.cjs \
  check-aira-adblock-download-response.cjs \
  check-aira-hls-progress.cjs \
  check-aira-arkweb-download-recovery.cjs \
  check-aira-arkweb-download-hold.cjs \
  check-aira-arkweb-manual-start.cjs \
  check-aira-download-redirect-request.cjs \
  check-aira-download-request-context.cjs \
  check-aira-resource-download-context.cjs \
  check-aira-media-resource-selection.cjs \
  check-aira-media-discovery.cjs \
  check-aira-media-resource-names.cjs \
  check-aira-media-durations.cjs \
  check-aira-download-filenames.cjs \
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
