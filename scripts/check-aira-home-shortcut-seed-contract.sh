#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERL_BIN="${PERL_BIN:-/usr/bin/perl}"
failures=0

fail() {
  printf 'Home shortcut seed contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
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

forbid_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if matches_pattern "${rel_path}" "${pattern}"; then
    fail "${message}"
  fi
}

REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/repositories/BrowserRepositories.ets"
DATABASE_REL="AiraBrowser/entry/src/main/ets/data/database/BrowserDatabase.ets"
SEED_SITES_REL="AiraBrowser/entry/src/main/ets/data/repositories/BrowserDefaultSeedSites.ets"

for rel_path in "${REPOSITORY_REL}" "${DATABASE_REL}" "${SEED_SITES_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

if [ ! -x "${PERL_BIN}" ]; then
  fail "Perl is required at ${PERL_BIN}"
fi

if [ "${failures}" -eq 0 ]; then
  require_pattern "${SEED_SITES_REL}" \
    'const CORE_BROWSER_SEED_SITES: BrowserDefaultSeedSite\[\] = \[\];' \
    "a fresh install must seed no default homepage shortcut (ADR-0088)"
  require_pattern "${REPOSITORY_REL}" \
    'function createSeedShortcutId\(idSuffix: string\): string \{[\s\S]*return `shortcut-seed-\$\{idSuffix\}`;' \
    "default homepage shortcuts must keep one seed id builder"
  require_pattern "${REPOSITORY_REL}" \
    'function buildSeedShortcutIds\(\): string\[\] \{[\s\S]*createSeedShortcutId\(site\.idSuffix\)' \
    "seed id retention must use the same ids that cold start can recreate"
  require_pattern "${REPOSITORY_REL}" \
    'function shouldRetainShortcutAfterDeletedSyncPurge\(shortcut: ShortcutRecord\): boolean \{[\s\S]*buildSeedShortcutIds\(\)\.indexOf\(shortcut\.id\) >= 0' \
    "a deleted default homepage shortcut must survive shortcut tombstone purge"
  require_pattern "${REPOSITORY_REL}" \
    'this\.shortcuts = this\.shortcuts\.filter\(\(shortcut: ShortcutRecord\): boolean => \{[\s\S]*return shouldRetainShortcutAfterDeletedSyncPurge\(shortcut\);' \
    "in-memory shortcut purge must retain deleted default homepage shortcuts"
  require_pattern "${REPOSITORY_REL}" \
    'purgeDeletedShortcutSyncRecords\(buildSeedShortcutIds\(\)\)' \
    "relational shortcut purge must retain deleted default homepage shortcut ids"
  require_pattern "${REPOSITORY_REL}" \
    'function buildMissingSeedShortcuts\(existingShortcuts: ShortcutRecord\[\]\): ShortcutRecord\[\] \{[\s\S]*const existingIds = new Set<string>\(existingShortcuts\.map\(\(shortcut: ShortcutRecord\) => shortcut\.id\)\);' \
    "cold start must treat an existing seed id, including a tombstone, as already installed"
  require_pattern "${DATABASE_REL}" \
    'async purgeDeletedShortcutSyncRecords\(retainedShortcutIds: string\[\] = \[\]\): Promise<number> \{[\s\S]*shortcutPredicates\.isNotNull\('"'"'deleted_at'"'"'\);[\s\S]*if \(retainedShortcutIds\.length > 0\) \{[\s\S]*shortcutPredicates\.notIn\('"'"'id'"'"', retainedShortcutIds\);' \
    "physical shortcut tombstone cleanup must exclude retained seed ids"
  forbid_pattern "${REPOSITORY_REL}" \
    'function buildMissingSeedShortcuts\(existingShortcuts: ShortcutRecord\[\]\): ShortcutRecord\[\] \{[\s\S]{0,500}deletedAt === undefined' \
    "missing-seed detection must not ignore tombstoned seed ids"
fi

if [ "${failures}" -ne 0 ]; then
  printf 'Home shortcut seed contract failed with %s violation(s).\n' "${failures}" >&2
  exit 1
fi

printf 'Home shortcut seed contract passed.\n'
