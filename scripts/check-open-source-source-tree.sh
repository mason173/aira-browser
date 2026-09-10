#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'Open-source source-tree violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_file() {
  local rel_path="$1"
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
    return 1
  fi
}

file_contains() {
  local rel_path="$1"
  local needle="$2"
  grep -F -q -- "${needle}" "${REPO_ROOT}/${rel_path}"
}

require_contains() {
  local rel_path="$1"
  local needle="$2"
  local message="$3"
  require_file "${rel_path}" || return
  if ! file_contains "${rel_path}" "${needle}"; then
    fail "${message}"
  fi
}

forbid_contains() {
  local rel_path="$1"
  local needle="$2"
  local message="$3"
  require_file "${rel_path}" || return
  if file_contains "${rel_path}" "${needle}"; then
    fail "${message}"
  fi
}

OWNER_REL="AiraBrowser/entry/src/main/ets/common/config/AiraDistributionCapabilityOwner.ets"
APP_CONFIG_REL="AiraBrowser/AppScope/app.json5"
APP_VERSION_REL="AiraBrowser/entry/src/main/ets/common/constants/AppVersionInfo.ets"
SHORTCUTS_REL="AiraBrowser/entry/src/main/resources/base/profile/shortcuts_config.json"
MODULE_REL="AiraBrowser/entry/src/main/module.json5"
BUILD_REL="scripts/build-aira-browser.sh"

require_contains "${OWNER_REL}" "export const AIRA_DISTRIBUTION: AiraDistribution = 'community';" \
  "${OWNER_REL} must commit Community as AIRA_DISTRIBUTION."
require_contains "${OWNER_REL}" "export const AIRA_HOSTED_API_BASE_URL: string = 'https://community.invalid';" \
  "${OWNER_REL} must commit the non-routable Community API placeholder."
forbid_contains "${OWNER_REL}" "export const AIRA_DISTRIBUTION: AiraDistribution = 'official';" \
  "${OWNER_REL} must not commit Official AIRA_DISTRIBUTION."
forbid_contains "${OWNER_REL}" "https://api.aira.cool" \
  "${OWNER_REL} must not commit the production API host."

require_contains "${APP_CONFIG_REL}" '"bundleName": "org.aira.browser"' \
  "${APP_CONFIG_REL} must commit Community bundleName org.aira.browser."
require_contains "${APP_CONFIG_REL}" '"cloudStructuredDataSyncEnabled": false' \
  "${APP_CONFIG_REL} must keep Huawei cloud structured-data sync disabled in Git."
forbid_contains "${APP_CONFIG_REL}" '"bundleName": "com.aira.browser"' \
  "${APP_CONFIG_REL} must not commit Official bundleName."

require_contains "${APP_VERSION_REL}" "export const APP_BUNDLE_NAME: string = 'org.aira.browser';" \
  "${APP_VERSION_REL} must commit Community APP_BUNDLE_NAME."
forbid_contains "${APP_VERSION_REL}" "export const APP_BUNDLE_NAME: string = 'com.aira.browser';" \
  "${APP_VERSION_REL} must not commit Official APP_BUNDLE_NAME."

require_contains "${SHORTCUTS_REL}" '"bundleName": "org.aira.browser"' \
  "${SHORTCUTS_REL} must commit Community shortcut bundleName."
forbid_contains "${SHORTCUTS_REL}" '"bundleName": "com.aira.browser"' \
  "${SHORTCUTS_REL} must not commit Official shortcut bundleName."

require_contains "${MODULE_REL}" '"metadata": []' \
  "${MODULE_REL} must commit empty module metadata."
forbid_contains "${MODULE_REL}" '"name": "app_id"' \
  "${MODULE_REL} must not commit Huawei app_id metadata."
forbid_contains "${MODULE_REL}" '"name": "client_id"' \
  "${MODULE_REL} must not commit Huawei client_id metadata."

require_contains "${BUILD_REL}" 'DISTRIBUTION="${AIRA_DISTRIBUTION:-community}"' \
  "${BUILD_REL} must default AIRA_DISTRIBUTION to community."
forbid_contains "${BUILD_REL}" 'DISTRIBUTION="${AIRA_DISTRIBUTION:-official}"' \
  "${BUILD_REL} must not default AIRA_DISTRIBUTION to official."


if [ "${failures}" -gt 0 ]; then
  cat >&2 <<'HINT'

The committed source tree must stay Community. Official identity, production API hosts, AGConnect, and Huawei app
metadata are private packaging inputs. See AGENTS.md and docs/open-source-distribution.md.
HINT
  exit 1
fi

echo "Open-source source-tree check passed."
