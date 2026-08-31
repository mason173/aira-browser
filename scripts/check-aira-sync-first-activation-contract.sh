#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERL_BIN="${PERL_BIN:-/usr/bin/perl}"
failures=0

fail() {
  printf 'Sync first-activation contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  if [ ! -f "${REPO_ROOT}/$1" ]; then
    fail "missing $1"
  fi
}

matches_pattern() {
  local rel_path="$1"
  local pattern="$2"
  "${PERL_BIN}" -e '
    use strict;
    use warnings;

    my ($pattern, $path) = @ARGV;
    open my $file, "<", $path or exit 2;
    local $/;
    my $content = <$file>;
    close $file;
    exit($content =~ /$pattern/ ? 0 : 1);
  ' "${pattern}" "${REPO_ROOT}/${rel_path}"
}

require_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if ! matches_pattern "${rel_path}" "${pattern}"; then
    fail "${message}"
  fi
}

reject_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if matches_pattern "${rel_path}" "${pattern}"; then
    fail "${message}"
  fi
}

SCREEN_REL="AiraBrowser/entry/src/main/ets/app/components/sync/SyncExperienceScreen.ets"
HOST_REL="AiraBrowser/entry/src/main/ets/app/components/sync/SyncExperienceHost.ets"
COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceCoordinator.ets"
PROVIDER_OPERATIONS_REL="AiraBrowser/entry/src/main/ets/core/sync/SyncExperienceProviderOperations.ets"
NAVIGATION_REL="AiraBrowser/entry/src/main/ets/app/router/SettingsNavigationCoordinator.ets"
ADR_REL="docs/adr/0048-sync-experience-is-the-single-state-transition-owner.md"

for rel_path in "${SCREEN_REL}" "${HOST_REL}" "${COORDINATOR_REL}" \
  "${PROVIDER_OPERATIONS_REL}" "${NAVIGATION_REL}" "${ADR_REL}"; do
  require_file "${rel_path}"
done

if [ ! -x "${PERL_BIN}" ]; then
  fail "Perl is required at ${PERL_BIN}"
fi

if [ "${failures}" -eq 0 ]; then
  require_pattern "${SCREEN_REL}" \
    'onConfigureWebdav: \([[:space:]]*firstActivationItems\?: SyncFirstActivationItemsState[[:space:]]*\) => void' \
    "the Sync screen must expose selected first-activation items on the WebDAV configuration callback"
  require_pattern "${SCREEN_REL}" \
    'private requestWebdavConfiguration\([[:space:]]*firstActivationItems\?: SyncFirstActivationItemsState[[:space:]]*\)' \
    "the Sync screen WebDAV request must accept the current first-activation selection"
  require_pattern "${SCREEN_REL}" \
    'this\.onConfigureWebdav\(pendingWebdavFirstActivationItems\);' \
    "the Sync screen must forward the captured selection after its sheet dismissal"
  require_pattern "${SCREEN_REL}" \
    'this\.activeSheetKind === '\''setup'\'' \? this\.firstActivationItemsState : undefined' \
    "large-screen first activation must forward the selected items into WebDAV configuration"
  require_pattern "${SCREEN_REL}" \
    'this\.requestWebdavConfiguration\(this\.firstActivationItemsState\);' \
    "phone first activation must forward the selected items into WebDAV configuration"

  require_pattern "${HOST_REL}" \
    'onConfigureWebdav: \([[:space:]]*firstActivationItems\?: SyncFirstActivationItemsState[[:space:]]*\)' \
    "the Sync host must receive optional first-activation items"
  require_pattern "${HOST_REL}" \
    'requestFirstActivationWebdavConfiguration\(firstActivationItems\)' \
    "the Sync host must route first-activation WebDAV configuration through the Sync Experience owner"

  require_pattern "${COORDINATOR_REL}" \
    'async requestFirstActivationWebdavConfiguration\([[:space:]]*firstActivationItems: SyncFirstActivationItemsState[[:space:]]*\)' \
    "Sync Experience must expose one owner entry point for first-activation WebDAV configuration"
  require_pattern "${COORDINATOR_REL}" \
    'requestFirstActivationWebdavConfiguration[\s\S]*await this\.persistFirstActivationItems\(firstActivationItems\);[\s\S]*enableDefaultContent: true' \
    "Sync Experience must persist selected content before requesting an activating WebDAV configuration"
  require_pattern "${COORDINATOR_REL}" \
    'async load\(\): Promise<SyncExperienceViewState> \{[[:space:]]*await this\.awaitPendingGoalChange\(\);' \
    "re-entering Sync must wait for an in-flight first-provider activation before reconstructing setup state"
  require_pattern "${COORDINATOR_REL}" \
    'requestGoalChange\([\s\S]*const operation = this\.executeGoalChange\([\s\S]*return this\.trackGoalChange\(operation\);' \
    "Sync Experience must publish the complete goal-change operation for re-entry state reads"

  require_pattern "${PROVIDER_OPERATIONS_REL}" \
    'handleWebdavActivationResultWithinTransition[\s\S]*activateBookmarkDomainWithProviderWithinTransition\('\''webdav'\''\)' \
    "ordinary WebDAV configuration must retain its bookmark-only activation behavior"
  require_pattern "${ADR_REL}" \
    'first-activation.*WebDAV configuration.*device-local content selection' \
    "ADR-0048 must record the first-activation WebDAV configuration handoff contract"

  reject_pattern "${NAVIGATION_REL}" \
    'firstActivationItems|firstActivationSelection|syncSelectedItems' \
    "selected Sync content must not be serialized into route parameters"
fi

if [ "${failures}" -gt 0 ]; then
  exit 1
fi

echo "Sync first-activation contract passed."
