#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROJECT_DIR="${REPO_ROOT}/AiraBrowser"
APP_CONFIG="${PROJECT_DIR}/AppScope/app.json5"
ENTRY_MODULE_CONFIG="${PROJECT_DIR}/entry/src/main/module.json5"
RELEASE_HISTORY="${REPO_ROOT}/release-history.json"
APP_SCOPE_STRING_RESOURCE="${PROJECT_DIR}/AppScope/resources/base/element/string.json"
ENTRY_STRING_RESOURCE="${PROJECT_DIR}/entry/src/main/resources/base/element/string.json"
MAIN_PAGES_RESOURCE="${PROJECT_DIR}/entry/src/main/resources/base/profile/main_pages.json"
SHORTCUTS_RESOURCE="${PROJECT_DIR}/entry/src/main/resources/base/profile/shortcuts_config.json"
APP_VERSION_INFO="${PROJECT_DIR}/entry/src/main/ets/common/constants/AppVersionInfo.ets"
DISTRIBUTION_OWNER="${PROJECT_DIR}/entry/src/main/ets/common/config/AiraDistributionCapabilityOwner.ets"
LOCAL_TEST_AUTH_CONFIG="${PROJECT_DIR}/entry/src/main/ets/common/config/AiraLocalTestAuth.ets"
AGCONNECT_RAWFILE="${PROJECT_DIR}/AppScope/resources/rawfile/agconnect-services.json"
AGCONNECT_LOCAL_DEFAULT="${PROJECT_DIR}/agconnect-services.local.json"
BUILD_PROFILE_TEMPLATE="${PROJECT_DIR}/build-profile.json5"
BUILD_PROFILE_LOCAL="${PROJECT_DIR}/build-profile.local.json5"
OHOS_CONFIG_DIR="${HOME}/.ohos/config"
DEVECO_APP="${AIRA_DEVECO_APP:-/Applications/DevEco-Studio.app}"
NODE_BIN="${DEVECO_APP}/Contents/tools/node/bin/node"
HVIGOR_BIN="${DEVECO_APP}/Contents/tools/hvigor/bin/hvigorw.js"
SDK_HOME="${DEVECO_APP}/Contents/sdk"
JAVA_HOME_DIR="${DEVECO_APP}/Contents/jbr/Contents/Home"
JAVA_BIN="${JAVA_HOME_DIR}/bin/java"
HDC_BIN="${SDK_HOME}/default/openharmony/toolchains/hdc"
SIGN_TOOL_JAR="${SDK_HOME}/default/openharmony/toolchains/lib/hap-sign-tool.jar"
ARCH_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-architecture-guardrails.sh"
ICON_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-icons-generated.sh"
HOME_CHROME_SCROLL_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-home-chrome-scroll-contract.cjs"
IMMERSIVE_LIGHT_SENSE_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-immersive-light-sense-contract.sh"
SYNC_FIRST_ACTIVATION_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-sync-first-activation-contract.sh"
SYNC_PROVIDER_SWITCH_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-sync-provider-switch-contract.sh"
HISTORY_SYNC_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-history-sync-contract.sh"
BOOKMARK_SNAPSHOT_GUARD_SCRIPT="${REPO_ROOT}/scripts/check-aira-bookmark-snapshot-contract.sh"
HUAWEI_APP_IDENTITY_RESOLVER="${REPO_ROOT}/scripts/huawei-app-identity.js"
HUAWEI_APP_IDENTITY_TEST="${REPO_ROOT}/scripts/huawei-app-identity.test.js"
PRODUCTION_BUNDLE_NAME="com.aira.browser"
PRODUCTION_APP_NAME="Aira"
COMMUNITY_BUNDLE_NAME="org.aira.browser"
COMMUNITY_APP_NAME="Aira"
MIN_SUPPORTED_API_VERSION=23
MAX_HARMONY_VERSION_CODE=2147483647
APP_OUTPUT_DIR="${PROJECT_DIR}/build/outputs/default"
ENTRY_OUTPUT_DIR="${PROJECT_DIR}/entry/build/default/outputs/default"
CRASH_SYMBOL_ARCHIVE_ROOT="${REPO_ROOT}/dist/crash-symbols"

BUILD_PROFILE_BACKUP=""
APP_CONFIG_BACKUP=""
ENTRY_MODULE_CONFIG_BACKUP=""
APP_SCOPE_STRING_BACKUP=""
ENTRY_STRING_BACKUP=""
SHORTCUTS_BACKUP=""
APP_VERSION_INFO_BACKUP=""
DISTRIBUTION_OWNER_BACKUP=""
LOCAL_TEST_AUTH_CONFIG_BACKUP=""
AGCONNECT_BACKUP=""
AGCONNECT_WAS_PRESENT=0
DISTRIBUTION_CONFIGURED=0
MAIN_PAGES_BACKUP=""
RELEASE_PRUNE_BACKUP_DIR=""
DISCOVERED_BUILD_PROFILE=""

# DevEco's native build invokes Cargo through the Rust toolchain. On machines
# where the global registry was initialized by root, keep dependency downloads
# in a persistent user-owned cache instead of forcing every build into a new
# temporary CARGO_HOME.
PERSISTENT_CARGO_HOME="${HOME}/.cache/aira-browser-cargo-home"

fail() {
  echo "$1" >&2
  exit 1
}

configure_cargo_home() {
  if [ -n "${CARGO_HOME:-}" ]; then
    mkdir -p "${CARGO_HOME}" || fail "Cannot create configured CARGO_HOME: ${CARGO_HOME}"
    return 0
  fi

  local default_cargo_home="${HOME}/.cargo"
  if [ -w "${default_cargo_home}" ] &&
     { [ ! -e "${default_cargo_home}/registry" ] || [ -w "${default_cargo_home}/registry" ]; }; then
    return 0
  fi

  mkdir -p "${PERSISTENT_CARGO_HOME}" ||
    fail "Cannot create persistent Cargo cache: ${PERSISTENT_CARGO_HOME}"
  export CARGO_HOME="${PERSISTENT_CARGO_HOME}"
  echo "Default Cargo registry is not writable; using persistent user cache: ${CARGO_HOME}"
}

cleanup() {
  if [ -n "${BUILD_PROFILE_BACKUP}" ] && [ -f "${BUILD_PROFILE_BACKUP}" ]; then
    cp "${BUILD_PROFILE_BACKUP}" "${BUILD_PROFILE_TEMPLATE}"
    rm -f "${BUILD_PROFILE_BACKUP}"
  fi
  if [ -n "${APP_CONFIG_BACKUP}" ] && [ -f "${APP_CONFIG_BACKUP}" ]; then
    cp "${APP_CONFIG_BACKUP}" "${APP_CONFIG}"
    rm -f "${APP_CONFIG_BACKUP}"
  fi
  if [ -n "${ENTRY_MODULE_CONFIG_BACKUP}" ] && [ -f "${ENTRY_MODULE_CONFIG_BACKUP}" ]; then
    cp "${ENTRY_MODULE_CONFIG_BACKUP}" "${ENTRY_MODULE_CONFIG}"
    rm -f "${ENTRY_MODULE_CONFIG_BACKUP}"
  fi
  if [ -n "${APP_SCOPE_STRING_BACKUP}" ] && [ -f "${APP_SCOPE_STRING_BACKUP}" ]; then
    cp "${APP_SCOPE_STRING_BACKUP}" "${APP_SCOPE_STRING_RESOURCE}"
    rm -f "${APP_SCOPE_STRING_BACKUP}"
  fi
  if [ -n "${ENTRY_STRING_BACKUP}" ] && [ -f "${ENTRY_STRING_BACKUP}" ]; then
    cp "${ENTRY_STRING_BACKUP}" "${ENTRY_STRING_RESOURCE}"
    rm -f "${ENTRY_STRING_BACKUP}"
  fi
  if [ -n "${SHORTCUTS_BACKUP}" ] && [ -f "${SHORTCUTS_BACKUP}" ]; then
    cp "${SHORTCUTS_BACKUP}" "${SHORTCUTS_RESOURCE}"
    rm -f "${SHORTCUTS_BACKUP}"
  fi
  if [ -n "${APP_VERSION_INFO_BACKUP}" ] && [ -f "${APP_VERSION_INFO_BACKUP}" ]; then
    cp "${APP_VERSION_INFO_BACKUP}" "${APP_VERSION_INFO}"
    rm -f "${APP_VERSION_INFO_BACKUP}"
  fi
  if [ -n "${DISTRIBUTION_OWNER_BACKUP}" ] && [ -f "${DISTRIBUTION_OWNER_BACKUP}" ]; then
    cp "${DISTRIBUTION_OWNER_BACKUP}" "${DISTRIBUTION_OWNER}"
    rm -f "${DISTRIBUTION_OWNER_BACKUP}"
  fi
  if [ -n "${LOCAL_TEST_AUTH_CONFIG_BACKUP}" ] && [ -f "${LOCAL_TEST_AUTH_CONFIG_BACKUP}" ]; then
    cp "${LOCAL_TEST_AUTH_CONFIG_BACKUP}" "${LOCAL_TEST_AUTH_CONFIG}"
    rm -f "${LOCAL_TEST_AUTH_CONFIG_BACKUP}"
  fi
  if [ -n "${AGCONNECT_BACKUP}" ] && [ -f "${AGCONNECT_BACKUP}" ]; then
    cp "${AGCONNECT_BACKUP}" "${AGCONNECT_RAWFILE}"
    rm -f "${AGCONNECT_BACKUP}"
  elif [ "${DISTRIBUTION_CONFIGURED}" = "1" ]; then
    rm -f "${AGCONNECT_RAWFILE}"
  fi
  if [ -n "${MAIN_PAGES_BACKUP}" ] && [ -f "${MAIN_PAGES_BACKUP}" ]; then
    cp "${MAIN_PAGES_BACKUP}" "${MAIN_PAGES_RESOURCE}"
    rm -f "${MAIN_PAGES_BACKUP}"
  fi
  if [ -n "${RELEASE_PRUNE_BACKUP_DIR}" ] && [ -d "${RELEASE_PRUNE_BACKUP_DIR}" ]; then
    while IFS= read -r -d '' backup_file; do
      local_path="${backup_file#${RELEASE_PRUNE_BACKUP_DIR}/}"
      cp "${backup_file}" "${PROJECT_DIR}/${local_path}"
    done < <(find "${RELEASE_PRUNE_BACKUP_DIR}" -type f -print0)
    rm -rf "${RELEASE_PRUNE_BACKUP_DIR}"
  fi
  if [ -n "${DISCOVERED_BUILD_PROFILE}" ] && [ -f "${DISCOVERED_BUILD_PROFILE}" ]; then
    rm -f "${DISCOVERED_BUILD_PROFILE}"
  fi
}
trap cleanup EXIT

BUILD_VARIANT="${AIRA_BUILD_VARIANT:-default}"
case "${BUILD_VARIANT}" in
  default|release)
    ;;
  *)
    fail "Unsupported AIRA_BUILD_VARIANT=${BUILD_VARIANT}. Use default or release."
    ;;
esac

DISTRIBUTION="${AIRA_DISTRIBUTION:-official}"
case "${DISTRIBUTION}" in
  community)
    EXPECTED_BUNDLE_NAME="${COMMUNITY_BUNDLE_NAME}"
    EXPECTED_APP_NAME="${COMMUNITY_APP_NAME}"
    ;;
  official)
    EXPECTED_BUNDLE_NAME="${PRODUCTION_BUNDLE_NAME}"
    EXPECTED_APP_NAME="${PRODUCTION_APP_NAME}"
    ;;
  *)
    fail "Unsupported AIRA_DISTRIBUTION=${DISTRIBUTION}. Use community or official."
    ;;
esac

LOCAL_TEST_MODE="${AIRA_LOCAL_TEST_MODE:-0}"
case "${LOCAL_TEST_MODE}" in
  0|1)
    ;;
  *)
    fail "Unsupported AIRA_LOCAL_TEST_MODE=${LOCAL_TEST_MODE}. Use 0 or 1."
    ;;
esac
LOCAL_TEST_UID="${AIRA_LOCAL_TEST_UID:-}"
LOCAL_TEST_AUTH_TOKEN="${AIRA_LOCAL_TEST_AUTH_TOKEN:-}"
if [ "${LOCAL_TEST_MODE}" = "1" ]; then
  if [ "${DISTRIBUTION}" != "official" ]; then
    fail "AIRA_LOCAL_TEST_MODE=1 requires an Official build."
  fi
  if [ -z "${LOCAL_TEST_UID}" ] || [ -z "${LOCAL_TEST_AUTH_TOKEN}" ]; then
    fail "AIRA_LOCAL_TEST_MODE=1 requires AIRA_LOCAL_TEST_UID and AIRA_LOCAL_TEST_AUTH_TOKEN."
  fi
fi

DEFAULT_HOSTED_API_BASE_URL="https://api.aira.cool"
if [ "${DISTRIBUTION}" = "community" ]; then
  DEFAULT_HOSTED_API_BASE_URL="https://community.invalid"
fi
HOSTED_API_BASE_URL="${AIRA_HOSTED_API_BASE_URL:-${DEFAULT_HOSTED_API_BASE_URL}}"

# A community build normally uses its own bundle name. For local acceptance on
# a device that already has the store package installed, an explicitly requested
# temporary bundle override can reuse that package's signing identity while the
# source-level distribution remains Community.
PACKAGE_BUNDLE_NAME="${AIRA_PACKAGE_BUNDLE_NAME:-${EXPECTED_BUNDLE_NAME}}"
if [ "${PACKAGE_BUNDLE_NAME}" != "${EXPECTED_BUNDLE_NAME}" ]; then
  if [ "${DISTRIBUTION}" != "community" ] || [ "${PACKAGE_BUNDLE_NAME}" != "${PRODUCTION_BUNDLE_NAME}" ]; then
    fail "AIRA_PACKAGE_BUNDLE_NAME may only temporarily map Community to ${PRODUCTION_BUNDLE_NAME}."
  fi
  echo "Temporary package bundle override: ${EXPECTED_BUNDLE_NAME} -> ${PACKAGE_BUNDLE_NAME}"
fi

ARCHIVE_CRASH_SYMBOLS="${AIRA_ARCHIVE_CRASH_SYMBOLS:-}"
if [ -z "${ARCHIVE_CRASH_SYMBOLS}" ]; then
  if [ "${BUILD_VARIANT}" = "release" ]; then
    ARCHIVE_CRASH_SYMBOLS=1
  else
    ARCHIVE_CRASH_SYMBOLS=0
  fi
fi
case "${ARCHIVE_CRASH_SYMBOLS}" in
  0|1)
    ;;
  *)
    fail "Unsupported AIRA_ARCHIVE_CRASH_SYMBOLS=${ARCHIVE_CRASH_SYMBOLS}. Use 0 or 1."
    ;;
esac

BUILD_PACKAGE_FORMAT="${AIRA_BUILD_PACKAGE_FORMAT:-hap}"
case "${BUILD_PACKAGE_FORMAT}" in
  hap|app)
    ;;
  *)
    fail "Unsupported AIRA_BUILD_PACKAGE_FORMAT=${BUILD_PACKAGE_FORMAT}. Use hap or app."
    ;;
esac

ALLOW_UNSIGNED_BUILD="${AIRA_ALLOW_UNSIGNED_BUILD:-0}"
case "${ALLOW_UNSIGNED_BUILD}" in
  0)
    ;;
  1)
    if [ "${DISTRIBUTION}" != "community" ] ||
       [ "${BUILD_VARIANT}" != "default" ] ||
       [ "${BUILD_PACKAGE_FORMAT}" != "hap" ] ||
       [ "${SKIP_INSTALL:-0}" != "1" ]; then
      fail "AIRA_ALLOW_UNSIGNED_BUILD=1 is limited to default Community HAP builds with SKIP_INSTALL=1."
    fi
    ;;
  *)
    fail "Unsupported AIRA_ALLOW_UNSIGNED_BUILD=${ALLOW_UNSIGNED_BUILD}. Use 0 or 1."
    ;;
esac

RELEASE_SIGNING_CONFIG_NAME="${AIRA_RELEASE_SIGNING_CONFIG:-release}"
DEFAULT_SIGNING_CONFIG_NAME="${AIRA_DEFAULT_SIGNING_CONFIG:-debug}"
RELEASE_AUTO_INCREMENT_VERSION_CODE="${AIRA_RELEASE_AUTO_INCREMENT_VERSION_CODE:-1}"
DEFAULT_INSTALL_AUTO_VERSION="${AIRA_DEFAULT_INSTALL_AUTO_VERSION:-1}"

if [ ! -d "${PROJECT_DIR}" ]; then
  fail "AiraBrowser not found at ${PROJECT_DIR}"
fi

configure_cargo_home

if [ ! -x "${ARCH_GUARD_SCRIPT}" ]; then
  fail "Architecture guardrail script not executable: ${ARCH_GUARD_SCRIPT}"
fi

"${ARCH_GUARD_SCRIPT}"

if [ ! -x "${SYNC_FIRST_ACTIVATION_GUARD_SCRIPT}" ]; then
  fail "Sync first-activation contract guard not executable: ${SYNC_FIRST_ACTIVATION_GUARD_SCRIPT}"
fi

"${SYNC_FIRST_ACTIVATION_GUARD_SCRIPT}"

if [ ! -x "${SYNC_PROVIDER_SWITCH_GUARD_SCRIPT}" ]; then
  fail "Sync provider-switch contract guard not executable: ${SYNC_PROVIDER_SWITCH_GUARD_SCRIPT}"
fi

"${SYNC_PROVIDER_SWITCH_GUARD_SCRIPT}"

if [ ! -x "${HISTORY_SYNC_GUARD_SCRIPT}" ]; then
  fail "History Sync contract guard not executable: ${HISTORY_SYNC_GUARD_SCRIPT}"
fi

"${HISTORY_SYNC_GUARD_SCRIPT}"

if [ ! -x "${BOOKMARK_SNAPSHOT_GUARD_SCRIPT}" ]; then
  fail "Bookmark snapshot contract guard not executable: ${BOOKMARK_SNAPSHOT_GUARD_SCRIPT}"
fi

"${BOOKMARK_SNAPSHOT_GUARD_SCRIPT}"

if [ -x "${ICON_GUARD_SCRIPT}" ]; then
  NODE_BIN="${NODE_BIN}" "${ICON_GUARD_SCRIPT}"
else
  fail "Aira icon generation guard script not executable: ${ICON_GUARD_SCRIPT}"
fi

if [ ! -f "${APP_CONFIG}" ]; then
  fail "App config not found at ${APP_CONFIG}"
fi

if [ ! -f "${ENTRY_MODULE_CONFIG}" ]; then
  fail "Entry module config not found at ${ENTRY_MODULE_CONFIG}"
fi

if [ ! -f "${APP_SCOPE_STRING_RESOURCE}" ]; then
  fail "AppScope string resource not found at ${APP_SCOPE_STRING_RESOURCE}"
fi

if [ ! -f "${ENTRY_STRING_RESOURCE}" ]; then
  fail "Entry string resource not found at ${ENTRY_STRING_RESOURCE}"
fi

if [ ! -f "${MAIN_PAGES_RESOURCE}" ]; then
  fail "Main pages resource not found at ${MAIN_PAGES_RESOURCE}"
fi

if [ ! -f "${SHORTCUTS_RESOURCE}" ]; then
  fail "Shortcut resource not found at ${SHORTCUTS_RESOURCE}"
fi

if [ ! -f "${APP_VERSION_INFO}" ]; then
  fail "App version info not found at ${APP_VERSION_INFO}"
fi

if [ ! -f "${DISTRIBUTION_OWNER}" ]; then
  fail "Distribution capability owner not found at ${DISTRIBUTION_OWNER}"
fi
if [ ! -f "${LOCAL_TEST_AUTH_CONFIG}" ]; then
  fail "Local test auth config not found at ${LOCAL_TEST_AUTH_CONFIG}"
fi

if [ ! -f "${BUILD_PROFILE_TEMPLATE}" ]; then
  fail "Build profile not found at ${BUILD_PROFILE_TEMPLATE}"
fi

if [ ! -x "${NODE_BIN}" ]; then
  fail "DevEco Studio Node runtime not found at ${NODE_BIN}"
fi

if [ ! -f "${HOME_CHROME_SCROLL_GUARD_SCRIPT}" ]; then
  fail "Home Chrome Scroll contract guard not found: ${HOME_CHROME_SCROLL_GUARD_SCRIPT}"
fi

"${NODE_BIN}" "${HOME_CHROME_SCROLL_GUARD_SCRIPT}"

if [ ! -x "${IMMERSIVE_LIGHT_SENSE_GUARD_SCRIPT}" ]; then
  fail "Immersive light-sense contract guard not executable: ${IMMERSIVE_LIGHT_SENSE_GUARD_SCRIPT}"
fi

"${IMMERSIVE_LIGHT_SENSE_GUARD_SCRIPT}"

if [ ! -f "${HUAWEI_APP_IDENTITY_RESOLVER}" ] || [ ! -f "${HUAWEI_APP_IDENTITY_TEST}" ]; then
  fail "Huawei app identity build contract files are missing."
fi

"${NODE_BIN}" "${HUAWEI_APP_IDENTITY_TEST}"

if [ ! -x "${JAVA_BIN}" ]; then
  fail "DevEco Studio Java runtime not found at ${JAVA_BIN}"
fi

if [ ! -x "${HDC_BIN}" ]; then
  fail "OpenHarmony hdc not found at ${HDC_BIN}"
fi

if [ ! -f "${SIGN_TOOL_JAR}" ]; then
  fail "Signing tool not found at ${SIGN_TOOL_JAR}"
fi

export DEVECO_SDK_HOME="${SDK_HOME}"
export JAVA_HOME="${JAVA_HOME_DIR}"
export PATH="${JAVA_HOME}/bin:${PATH}"

ensure_app_config_backup() {
  if [ -n "${APP_CONFIG_BACKUP}" ] && [ -f "${APP_CONFIG_BACKUP}" ]; then
    return 0
  fi

  APP_CONFIG_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-app-config-backup-json5.XXXXXX")"
  cp "${APP_CONFIG}" "${APP_CONFIG_BACKUP}"
}

ensure_distribution_file_backups() {
  if [ -z "${ENTRY_MODULE_CONFIG_BACKUP}" ]; then
    ENTRY_MODULE_CONFIG_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-entry-module-backup-json5.XXXXXX")"
    cp "${ENTRY_MODULE_CONFIG}" "${ENTRY_MODULE_CONFIG_BACKUP}"
  fi
  if [ -z "${APP_SCOPE_STRING_BACKUP}" ]; then
    APP_SCOPE_STRING_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-app-scope-string-backup-json.XXXXXX")"
    cp "${APP_SCOPE_STRING_RESOURCE}" "${APP_SCOPE_STRING_BACKUP}"
  fi
  if [ -z "${ENTRY_STRING_BACKUP}" ]; then
    ENTRY_STRING_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-entry-string-backup-json.XXXXXX")"
    cp "${ENTRY_STRING_RESOURCE}" "${ENTRY_STRING_BACKUP}"
  fi
  if [ -z "${SHORTCUTS_BACKUP}" ]; then
    SHORTCUTS_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-shortcuts-backup-json.XXXXXX")"
    cp "${SHORTCUTS_RESOURCE}" "${SHORTCUTS_BACKUP}"
  fi
  if [ -z "${APP_VERSION_INFO_BACKUP}" ]; then
    APP_VERSION_INFO_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-app-version-info-backup-ets.XXXXXX")"
    cp "${APP_VERSION_INFO}" "${APP_VERSION_INFO_BACKUP}"
  fi
  if [ -z "${DISTRIBUTION_OWNER_BACKUP}" ]; then
    DISTRIBUTION_OWNER_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-distribution-owner-backup-ets.XXXXXX")"
    cp "${DISTRIBUTION_OWNER}" "${DISTRIBUTION_OWNER_BACKUP}"
  fi
  if [ -z "${LOCAL_TEST_AUTH_CONFIG_BACKUP}" ]; then
    LOCAL_TEST_AUTH_CONFIG_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-local-test-auth-backup-ets.XXXXXX")"
    cp "${LOCAL_TEST_AUTH_CONFIG}" "${LOCAL_TEST_AUTH_CONFIG_BACKUP}"
  fi
}

ensure_agconnect_backup() {
  if [ -n "${AGCONNECT_BACKUP}" ] || [ "${AGCONNECT_WAS_PRESENT}" = "1" ]; then
    return 0
  fi
  if [ -f "${AGCONNECT_RAWFILE}" ]; then
    AGCONNECT_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-agconnect-backup-json.XXXXXX")"
    cp "${AGCONNECT_RAWFILE}" "${AGCONNECT_BACKUP}"
    AGCONNECT_WAS_PRESENT=1
  fi
}

apply_distribution_configuration() {
  ensure_app_config_backup
  ensure_distribution_file_backups
  ensure_agconnect_backup
  DISTRIBUTION_CONFIGURED=1

  if [ "${DISTRIBUTION}" = "official" ]; then
    AGCONNECT_SOURCE="${AIRA_AGCONNECT_CONFIG:-${AGCONNECT_LOCAL_DEFAULT}}"
    if [ ! -f "${AGCONNECT_SOURCE}" ]; then
      fail "Official builds require AIRA_AGCONNECT_CONFIG or ${AGCONNECT_LOCAL_DEFAULT}; production AGConnect configuration is intentionally not tracked."
    fi
  else
    AGCONNECT_SOURCE=""
  fi

  "${NODE_BIN}" - "${HOSTED_API_BASE_URL}" "${LOCAL_TEST_MODE}" "${REPO_ROOT}" <<'NODE'
const path = require('path');
const { parseEndpoint } = require(path.join(process.argv[4], 'scripts', 'distribution-endpoint-policy.js'));
const endpoint = process.argv[2];
const localTestMode = process.argv[3] === '1';
parseEndpoint(endpoint, { allowHttp: localTestMode, label: 'AIRA_HOSTED_API_BASE_URL' });
NODE

  "${NODE_BIN}" - \
    "${APP_CONFIG}" \
    "${ENTRY_MODULE_CONFIG}" \
    "${APP_SCOPE_STRING_RESOURCE}" \
    "${ENTRY_STRING_RESOURCE}" \
    "${SHORTCUTS_RESOURCE}" \
    "${APP_VERSION_INFO}" \
    "${DISTRIBUTION_OWNER}" \
    "${LOCAL_TEST_AUTH_CONFIG}" \
    "${HUAWEI_APP_IDENTITY_RESOLVER}" \
    "${AGCONNECT_SOURCE}" \
    "${DISTRIBUTION}" \
    "${PACKAGE_BUNDLE_NAME}" \
    "${EXPECTED_APP_NAME}" \
    "${AIRA_HUAWEI_APP_ID:-}" \
    "${AIRA_HUAWEI_CLIENT_ID:-}" \
    "${HOSTED_API_BASE_URL}" \
    "${LOCAL_TEST_MODE}" \
    "${LOCAL_TEST_UID}" \
    "${LOCAL_TEST_AUTH_TOKEN}" <<'NODE'
const fs = require('fs');

const [
  appConfigPath,
  moduleConfigPath,
  appScopeStringPath,
  entryStringPath,
  shortcutsPath,
  appVersionInfoPath,
  ownerPath,
  localTestAuthPath,
  huaweiAppIdentityResolverPath,
  agconnectPath,
  distribution,
  bundleName,
  appName,
  requestedAppId,
  requestedClientId,
  hostedApiBaseUrl,
  localTestMode,
  localTestUid,
  localTestAuthToken
] = process.argv.slice(2);
const { resolveHuaweiAppIdentity } = require(huaweiAppIdentityResolverPath);

function readJson5(path) {
  return new Function(`return (${fs.readFileSync(path, 'utf8')});`)();
}

function writeJson(path, value) {
  fs.writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

const appConfig = readJson5(appConfigPath);
appConfig.app.bundleName = bundleName;
appConfig.app.cloudStructuredDataSyncEnabled = distribution === 'official';
writeJson(appConfigPath, appConfig);

const appScopeStrings = JSON.parse(fs.readFileSync(appScopeStringPath, 'utf8'));
const appScopeName = (appScopeStrings.string || []).find((item) => item.name === 'app_name');
if (appScopeName) appScopeName.value = appName;
writeJson(appScopeStringPath, appScopeStrings);

const entryStrings = JSON.parse(fs.readFileSync(entryStringPath, 'utf8'));
const abilityLabel = (entryStrings.string || []).find((item) => item.name === 'EntryAbility_label');
if (abilityLabel) abilityLabel.value = appName;
writeJson(entryStringPath, entryStrings);

const shortcuts = JSON.parse(fs.readFileSync(shortcutsPath, 'utf8'));
for (const shortcut of shortcuts.shortcuts || []) {
  for (const want of shortcut.wants || []) {
    want.bundleName = bundleName;
  }
}
writeJson(shortcutsPath, shortcuts);

const appVersionSource = fs.readFileSync(appVersionInfoPath, 'utf8');
if (!/export const APP_BUNDLE_NAME: string = '[^']*';/.test(appVersionSource)) {
  throw new Error(`Could not find APP_BUNDLE_NAME in ${appVersionInfoPath}`);
}
const nextAppVersionSource = appVersionSource.replace(
  /export const APP_BUNDLE_NAME: string = '[^']*';/,
  `export const APP_BUNDLE_NAME: string = '${bundleName}';`
);
fs.writeFileSync(appVersionInfoPath, nextAppVersionSource);

const ownerSource = fs.readFileSync(ownerPath, 'utf8');
if (!/export const AIRA_DISTRIBUTION: AiraDistribution = '[^']*';/.test(ownerSource)) {
  throw new Error(`Could not find AIRA_DISTRIBUTION in ${ownerPath}`);
}
const nextOwnerSource = ownerSource.replace(
  /export const AIRA_DISTRIBUTION: AiraDistribution = '[^']*';/,
  `export const AIRA_DISTRIBUTION: AiraDistribution = '${distribution}';`
);
if (!/export const AIRA_HOSTED_API_BASE_URL: string = '[^']*';/.test(nextOwnerSource)) {
  throw new Error(`Could not find AIRA_HOSTED_API_BASE_URL in ${ownerPath}`);
}
const nextOwnerWithApiBaseUrl = nextOwnerSource.replace(
  /export const AIRA_HOSTED_API_BASE_URL: string = '[^']*';/,
  `export const AIRA_HOSTED_API_BASE_URL: string = ${JSON.stringify(hostedApiBaseUrl)};`
);
fs.writeFileSync(ownerPath, nextOwnerWithApiBaseUrl);

const localTestAuthSource = fs.readFileSync(localTestAuthPath, 'utf8');
for (const [name, value] of [
  ['AIRA_LOCAL_TEST_MODE', localTestMode === '1' ? 'true' : 'false'],
  ['AIRA_LOCAL_TEST_UID', JSON.stringify(localTestMode === '1' ? localTestUid : '')],
  ['AIRA_LOCAL_TEST_AUTH_TOKEN', JSON.stringify(localTestMode === '1' ? localTestAuthToken : '')]
]) {
  const pattern = new RegExp(`export const ${name}: (?:boolean|string) = (?:true|false|'[^']*'|"[^"]*");`);
  if (!pattern.test(localTestAuthSource)) {
    throw new Error(`Could not find ${name} in ${localTestAuthPath}`);
  }
}
const nextLocalTestAuthSource = localTestAuthSource
  .replace(/export const AIRA_LOCAL_TEST_MODE: boolean = (?:true|false);/, `export const AIRA_LOCAL_TEST_MODE: boolean = ${localTestMode === '1' ? 'true' : 'false'};`)
  .replace(/export const AIRA_LOCAL_TEST_UID: string = '[^']*';/, `export const AIRA_LOCAL_TEST_UID: string = ${JSON.stringify(localTestMode === '1' ? localTestUid : '')};`)
  .replace(/export const AIRA_LOCAL_TEST_AUTH_TOKEN: string = '[^']*';/, `export const AIRA_LOCAL_TEST_AUTH_TOKEN: string = ${JSON.stringify(localTestMode === '1' ? localTestAuthToken : '')};`);
fs.writeFileSync(localTestAuthPath, nextLocalTestAuthSource);

const moduleConfig = readJson5(moduleConfigPath);
const metadata = Array.isArray(moduleConfig.module.metadata) ? moduleConfig.module.metadata : [];
const isOfficial = distribution === 'official';
if (!isOfficial) {
  moduleConfig.module.metadata = metadata.filter((item) => item.name !== 'app_id' && item.name !== 'client_id');
} else {
  const agconnect = agconnectPath.length > 0
    ? JSON.parse(fs.readFileSync(agconnectPath, 'utf8'))
    : {};
  const { appId, clientId } = resolveHuaweiAppIdentity(
    agconnect,
    requestedAppId,
    requestedClientId
  );
  if (appId.length === 0 || clientId.length === 0) {
    throw new Error('Official builds require AIRA_HUAWEI_APP_ID and AIRA_HUAWEI_CLIENT_ID, or matching values in the private AGConnect file.');
  }
  const upsert = (name, value) => {
    const item = metadata.find((candidate) => candidate.name === name);
    if (item) item.value = value;
    else metadata.push({ name, value });
  };
  upsert('app_id', appId);
  upsert('client_id', clientId);
  moduleConfig.module.metadata = metadata;
}
writeJson(moduleConfigPath, moduleConfig);
NODE

  if [ "${DISTRIBUTION}" = "official" ]; then
    cp "${AGCONNECT_SOURCE}" "${AGCONNECT_RAWFILE}"
  else
    rm -f "${AGCONNECT_RAWFILE}"
  fi
  echo "Distribution: ${DISTRIBUTION} (${EXPECTED_APP_NAME}, ${PACKAGE_BUNDLE_NAME})"
}

read_bundle_name() {
  "${NODE_BIN}" -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(data.app.bundleName || "");
  ' "$1"
}

read_version_name() {
  "${NODE_BIN}" -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(data.app.versionName || ""));
  ' "$1"
}

read_version_code() {
  "${NODE_BIN}" -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    process.stdout.write(String(data.app.versionCode ?? ""));
  ' "$1"
}

increment_version_code() {
  "${NODE_BIN}" - "$1" <<'NODE'
const sourceVersionCode = Number((process.argv[2] || '').trim());
if (!Number.isInteger(sourceVersionCode) || sourceVersionCode < 1) {
  throw new Error(`Cannot increment invalid versionCode: ${process.argv[2] || ''}`);
}
if (sourceVersionCode >= 2147483647) {
  throw new Error(`Cannot increment versionCode beyond HarmonyOS maximum: ${sourceVersionCode}`);
}
process.stdout.write(String(sourceVersionCode + 1));
NODE
}

derive_release_version_name() {
  "${NODE_BIN}" - "$1" <<'NODE'
const sourceVersionName = (process.argv[2] || '').trim();
if (sourceVersionName.length === 0) {
  throw new Error('Cannot derive release versionName from an empty source versionName.');
}

const releaseVersionName = sourceVersionName.replace(
  /-(dev|preview|alpha(?:\.[0-9A-Za-z.-]+)?|beta(?:\.[0-9A-Za-z.-]+)?|rc(?:\.[0-9A-Za-z.-]+)?)$/i,
  ''
).trim();

process.stdout.write(releaseVersionName.length > 0 ? releaseVersionName : sourceVersionName);
NODE
}

read_latest_release_version_name() {
  "${NODE_BIN}" - "$1" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
if (!path || !fs.existsSync(path)) {
  process.stdout.write('');
  process.exit(0);
}
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
const latest = data.latestAppGalleryRelease || {};
process.stdout.write(String(latest.versionName || '').trim());
NODE
}

read_latest_release_version_code() {
  "${NODE_BIN}" - "$1" <<'NODE'
const fs = require('fs');
const path = process.argv[2];
if (!path || !fs.existsSync(path)) {
  process.stdout.write('');
  process.exit(0);
}
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
const latest = data.latestAppGalleryRelease || {};
process.stdout.write(String(latest.versionCode ?? '').trim());
NODE
}

list_connected_targets() {
  "${HDC_BIN}" list targets | tr -d '\r' | sed '/^[[:space:]]*$/d; /^\[Empty\]$/d'
}

read_installed_version_code() {
  local target="$1"
  local bundle_name="$2"
  local dump_output

  dump_output="$("${HDC_BIN}" -t "${target}" shell bm dump -n "${bundle_name}" 2>/dev/null || true)"
  if [ -z "${dump_output}" ]; then
    return 0
  fi

  printf '%s' "${dump_output}" | "${NODE_BIN}" -e '
    let input = "";
    process.stdin.on("data", (chunk) => input += chunk);
    process.stdin.on("end", () => {
      const matches = [...input.matchAll(/"versionCode"\s*:\s*([0-9]+)/g)]
        .map((match) => Number(match[1]))
        .filter((value) => Number.isInteger(value) && value > 0);
      if (matches.length <= 0) {
        process.stdout.write("");
        return;
      }
      process.stdout.write(String(Math.max(...matches)));
    });
  '
}

install_hap_to_target() {
  local target="$1"
  local hap_path="$2"
  local install_output
  local install_status

  if install_output="$("${HDC_BIN}" -t "${target}" install -r "${hap_path}" 2>&1)"; then
    if [ -n "${install_output}" ]; then
      printf '%s\n' "${install_output}"
    fi
    if printf '%s' "${install_output}" | grep -Eiq 'downgrade|version downgrade'; then
      echo "Device rejected this debug install as a version downgrade; retrying with downgrade allowed."
      "${HDC_BIN}" -t "${target}" install -r -d "${hap_path}"
      return $?
    fi
    if printf '%s' "${install_output}" | grep -Eiq 'msg:error:|error: failed to install bundle'; then
      return 1
    fi
    return 0
  fi

  install_status=$?
  if [ -n "${install_output}" ]; then
    printf '%s\n' "${install_output}"
  fi

  if printf '%s' "${install_output}" | grep -Eiq 'downgrade|version downgrade'; then
    echo "Device rejected this debug install as a version downgrade; retrying with downgrade allowed."
    "${HDC_BIN}" -t "${target}" install -r -d "${hap_path}"
    return $?
  fi

  return "${install_status}"
}

derive_next_release_version_name() {
  "${NODE_BIN}" - "$1" "$2" <<'NODE'
const sourceVersionName = (process.argv[2] || '').trim();
const latestReleaseVersionName = (process.argv[3] || '').trim();

function stripPreviewSuffix(versionName) {
  return versionName.replace(
    /-(dev|preview|alpha(?:\.[0-9A-Za-z.-]+)?|beta(?:\.[0-9A-Za-z.-]+)?|rc(?:\.[0-9A-Za-z.-]+)?)$/i,
    ''
  ).trim();
}

function parseSemver(versionName) {
  const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(versionName);
  if (match === null) {
    return null;
  }
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3])
  };
}

function compareSemver(left, right) {
  if (left.major !== right.major) {
    return left.major - right.major;
  }
  if (left.minor !== right.minor) {
    return left.minor - right.minor;
  }
  return left.patch - right.patch;
}

function bumpPatch(version) {
  return `${version.major}.${version.minor}.${version.patch + 1}`;
}

const sourceReleaseVersionName = stripPreviewSuffix(sourceVersionName);
if (sourceReleaseVersionName.length === 0) {
  throw new Error('Cannot derive release versionName from an empty source versionName.');
}
if (latestReleaseVersionName.length === 0) {
  process.stdout.write(sourceReleaseVersionName);
  process.exit(0);
}

const latestRelease = parseSemver(latestReleaseVersionName);
const sourceRelease = parseSemver(sourceReleaseVersionName);
if (latestRelease === null || sourceRelease === null) {
  if (sourceReleaseVersionName !== latestReleaseVersionName) {
    process.stdout.write(sourceReleaseVersionName);
    process.exit(0);
  }
  throw new Error(
    `Cannot auto-increment non-semver release versionName: ${latestReleaseVersionName}. ` +
    'Set AIRA_RELEASE_VERSION_NAME explicitly.'
  );
}

if (compareSemver(sourceRelease, latestRelease) > 0) {
  process.stdout.write(sourceReleaseVersionName);
  process.exit(0);
}

process.stdout.write(bumpPatch(latestRelease));
NODE
}

apply_version_override() {
  local version_name="$1"
  local version_code="$2"

  ensure_app_config_backup
  "${NODE_BIN}" - "$APP_CONFIG" "$version_name" "$version_code" <<'NODE'
const fs = require('fs');

const appConfigPath = process.argv[2];
const versionName = (process.argv[3] || '').trim();
const versionCodeText = (process.argv[4] || '').trim();
const versionCode = Number(versionCodeText);

if (versionName.length === 0) {
  throw new Error('versionName must not be empty.');
}
if (!Number.isInteger(versionCode) || versionCode < 1) {
  throw new Error(`versionCode must be a positive integer. Received: ${versionCodeText}`);
}

const data = JSON.parse(fs.readFileSync(appConfigPath, 'utf8'));
data.app.versionName = versionName;
data.app.versionCode = versionCode;
fs.writeFileSync(appConfigPath, `${JSON.stringify(data, null, 2)}\n`);
NODE
  echo "Using temporary app version: ${version_name} (${version_code})"
}

sanitize_package_filename_part() {
  printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-' | sed -E 's/^-+//; s/-+$//; s/-+/-/g'
}

archive_crash_symbols() {
  if [ "${ARCHIVE_CRASH_SYMBOLS}" != "1" ]; then
    return 0
  fi

  local source_map="${ENTRY_OUTPUT_DIR}/mapping/sourceMaps.map"
  local native_build_root="${PROJECT_DIR}/entry/build/default/intermediates/cmake"
  if [ ! -f "${source_map}" ]; then
    fail "Crash symbol archive requires the exact-build ArkTS SourceMap: ${source_map}"
  fi
  if [ ! -d "${native_build_root}" ]; then
    fail "Crash symbol archive requires the Native build intermediates: ${native_build_root}"
  fi

  local safe_version_name
  local safe_version_code
  local safe_distribution
  local archive_timestamp
  local archive_dir
  safe_version_name="$(sanitize_package_filename_part "${TARGET_VERSION_NAME}")"
  safe_version_code="$(sanitize_package_filename_part "${TARGET_VERSION_CODE}")"
  safe_distribution="$(sanitize_package_filename_part "${DISTRIBUTION}")"
  archive_timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  archive_dir="${CRASH_SYMBOL_ARCHIVE_ROOT}/Aira-${safe_distribution}-v${safe_version_name}-${safe_version_code}-${BUILD_VARIANT}-${archive_timestamp}"
  mkdir -p "${archive_dir}/arkts" "${archive_dir}/native"
  cp "${source_map}" "${archive_dir}/arkts/sourceMaps.map"

  local native_count=0
  local native_path
  while IFS= read -r -d '' native_path; do
    if ! file "${native_path}" | grep -q 'not stripped'; then
      continue
    fi
    local abi
    abi="$(basename "$(dirname "${native_path}")")"
    mkdir -p "${archive_dir}/native/${abi}"
    cp "${native_path}" "${archive_dir}/native/${abi}/$(basename "${native_path}")"
    native_count=$((native_count + 1))
  done < <(find "${native_build_root}" -type f -name 'libaira_*.so' -print0)

  if [ "${native_count}" -le 0 ]; then
    fail "Crash symbol archive found no unstripped Aira-owned Native libraries under ${native_build_root}."
  fi

  local source_commit
  local source_dirty
  source_commit="$(git -C "${REPO_ROOT}" rev-parse HEAD 2>/dev/null || true)"
  source_dirty=0
  if [ -n "$(git -C "${REPO_ROOT}" status --porcelain --untracked-files=no 2>/dev/null || true)" ]; then
    source_dirty=1
  fi
  "${NODE_BIN}" - "${archive_dir}" "${TARGET_VERSION_NAME}" "${TARGET_VERSION_CODE}" \
    "${BUILD_VARIANT}" "${DISTRIBUTION}" "${APP_BUNDLE_NAME}" "${source_commit}" "${source_dirty}" <<'NODE'
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const archiveDir = process.argv[2];
const versionName = process.argv[3];
const versionCode = Number(process.argv[4]);
const buildVariant = process.argv[5];
const distribution = process.argv[6];
const bundleName = process.argv[7];
const sourceCommit = process.argv[8];
const sourceDirty = process.argv[9] === '1';

function walk(directory) {
  const output = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) output.push(...walk(absolute));
    else if (entry.isFile()) output.push(absolute);
  }
  return output;
}

const artifacts = walk(archiveDir).map((absolute) => {
  const bytes = fs.readFileSync(absolute);
  const relativePath = path.relative(archiveDir, absolute);
  let buildId = '';
  if (absolute.endsWith('.so')) {
    const description = execFileSync('/usr/bin/file', ['-b', absolute], { encoding: 'utf8' });
    const match = /BuildID\[sha1\]=([0-9a-f]+)/i.exec(description);
    buildId = match ? match[1] : '';
  }
  return {
    path: relativePath,
    bytes: bytes.byteLength,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    buildId
  };
});

const manifest = {
  schemaVersion: 1,
  createdAt: new Date().toISOString(),
  app: { bundleName, versionName, versionCode },
  distribution,
  buildVariant,
  sourceCommit,
  sourceDirty,
  artifacts
};
fs.writeFileSync(path.join(archiveDir, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`);
NODE

  echo "Crash symbols archived: ${archive_dir}"
}

remove_release_app_outputs() {
  if [ "${BUILD_VARIANT}" != "release" ] || [ "${BUILD_PACKAGE_FORMAT}" != "app" ]; then
    return 0
  fi
  if [ ! -d "${APP_OUTPUT_DIR}" ]; then
    return 0
  fi

  local removed=0
  local app_path
  while IFS= read -r -d '' app_path; do
    rm -f "${app_path}"
    removed=1
  done < <(find "${APP_OUTPUT_DIR}" -maxdepth 1 -type f -name '*.app' -print0)

  if [ "${removed}" = "1" ]; then
    echo "Removed previous APP outputs from ${APP_OUTPUT_DIR}."
  fi
}

remove_other_app_outputs() {
  local keep_path="$1"
  local output_dir
  output_dir="$(dirname "${keep_path}")"
  if [ ! -d "${output_dir}" ]; then
    return 0
  fi

  local app_path
  while IFS= read -r -d '' app_path; do
    if [ "${app_path}" = "${keep_path}" ]; then
      continue
    fi
    rm -f "${app_path}"
  done < <(find "${output_dir}" -maxdepth 1 -type f -name '*.app' -print0)
}

remove_release_app_loose_haps() {
  if [ "${BUILD_VARIANT}" != "release" ] || [ "${BUILD_PACKAGE_FORMAT}" != "app" ]; then
    return 0
  fi
  if [ ! -d "${ENTRY_OUTPUT_DIR}" ]; then
    return 0
  fi

  local removed=0
  local hap_path
  while IFS= read -r -d '' hap_path; do
    rm -f "${hap_path}"
    removed=1
  done < <(find "${ENTRY_OUTPUT_DIR}" -maxdepth 2 -type f -name '*.hap' -print0)

  if [ "${removed}" = "1" ]; then
    echo "Removed loose HAP intermediates from ${ENTRY_OUTPUT_DIR}."
  fi
}

read_app_name() {
  "${NODE_BIN}" -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const item = (data.string || []).find((entry) => entry.name === "app_name");
    process.stdout.write((item && item.value) || "");
  ' "${APP_SCOPE_STRING_RESOURCE}"
}

read_entry_ability_label() {
  "${NODE_BIN}" -e '
    const fs = require("fs");
    const data = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const item = (data.string || []).find((entry) => entry.name === "EntryAbility_label");
    process.stdout.write((item && item.value) || "");
  ' "${ENTRY_STRING_RESOURCE}"
}

apply_release_page_pruning() {
  MAIN_PAGES_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-main-pages-backup-json.XXXXXX")"
  cp "${MAIN_PAGES_RESOURCE}" "${MAIN_PAGES_BACKUP}"

  "${NODE_BIN}" - "${MAIN_PAGES_RESOURCE}" <<'NODE'
const fs = require('fs');

const mainPagesPath = process.argv[2];
const data = JSON.parse(fs.readFileSync(mainPagesPath, 'utf8'));
const releaseOnlyExcludedPages = new Set([]);
data.src = (data.src || []).filter((page) => !releaseOnlyExcludedPages.has(page));
fs.writeFileSync(mainPagesPath, `${JSON.stringify(data, null, 2)}\n`);
NODE
  echo "Using release page list."
}

backup_release_file() {
  local file_path="$1"
  local relative_path="${file_path#${PROJECT_DIR}/}"
  local backup_path

  if [ ! -f "${file_path}" ]; then
    return 0
  fi

  if [ -z "${RELEASE_PRUNE_BACKUP_DIR}" ]; then
    RELEASE_PRUNE_BACKUP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/aira-release-prune-backup.XXXXXX")"
  fi

  backup_path="${RELEASE_PRUNE_BACKUP_DIR}/${relative_path}"
  if [ -f "${backup_path}" ]; then
    return 0
  fi
  mkdir -p "$(dirname "${backup_path}")"
  cp "${file_path}" "${backup_path}"
}

apply_release_source_pruning() {
  local browser_test_lab_page="${PROJECT_DIR}/entry/src/main/ets/app/debug/BrowserTestLabPage.ets"
  local animation_curve_page="${PROJECT_DIR}/entry/src/main/ets/app/debug/BrowserAnimationCurvePreviewPage.ets"
  local new_window_test_page="${PROJECT_DIR}/entry/src/main/ets/app/debug/BrowserNewWindowTestPage.ets"
  local build_variant_flags="${PROJECT_DIR}/entry/src/main/ets/common/config/BuildVariantFlags.ets"

  backup_release_file "${browser_test_lab_page}"
  backup_release_file "${animation_curve_page}"
  backup_release_file "${new_window_test_page}"
  backup_release_file "${build_variant_flags}"

  "${NODE_BIN}" - \
    "${browser_test_lab_page}" \
    "${animation_curve_page}" \
    "${new_window_test_page}" \
    "${build_variant_flags}" <<'NODE'
const fs = require('fs');

const [
  browserTestLabPage,
  animationCurvePage,
  newWindowTestPage,
  buildVariantFlags
] = process.argv.slice(2);

if (fs.existsSync(browserTestLabPage)) fs.writeFileSync(browserTestLabPage, `import { BrowserDiagnosticEvent } from '../../common/models/BrowserModels';

export interface BrowserTestLabDebugState {
  activeTabId: string;
  currentTabId: string;
  windowId: string;
  pendingLaunchWindowIds: string[];
  pendingLaunchSummaryLines: string[];
  pendingNewWindowLaunchWindowIds: string[];
  activeWindowLocatorLine: string;
  windowRuntimeManagementSummaryLine: string;
  lastPendingLaunchConsumeSummaryLine: string;
  lastWindowUnregisterSummaryLine: string;
  windowRuntimeTabSummaryLine: string;
  totalTabs: number;
  runtimeLabel: string;
  runtimeHelperMessage: string;
  runtimeEvidenceLine: string;
  runtimeState: string;
  lastRestoreReason: string;
  lastDiscardReason: string;
  lastCrashReason: string;
  hasLiveController: boolean;
  pageCacheRestoreType: string;
  pageCacheReason: string;
  pageCacheMetricLines: string[];
  tabPreviewMetricLines: string[];
  scrollOffsetY: number;
  lastGoodUrl: string;
  lastGoodTitle: string;
  restoreTraceId: string;
  restoreTraceSource: string;
  restoreTraceTargetUrl: string;
  restoreTraceBreadcrumbs: string[];
  snapshotPath: string;
  mountedTabIds: string[];
  hotTabIds: string[];
  warmTabIds: string[];
  coldTabIds: string[];
  forcedDiscardTabIds: string[];
  webStateRestoreCandidateTabIds: string[];
  retentionReason: string;
  retentionScore: number;
  restorePriority: number;
  nonReclaimableReason: string;
  retentionPressureSummary: string;
  retentionPressureWarmTabIds: string[];
  retentionPressureMountedTabIds: string[];
  policyDecisionSchemaLines: string[];
  policyDecisionLines: string[];
  diagnosticLines: string[];
  windowSharedSnapshotDiagnosticLines: string[];
  diagnosticSummaryLines: string[];
  diagnosticFaultLines: string[];
  diagnosticExportPreview: string;
  diagnosticRetentionLine: string;
  diagnosticEvents: BrowserDiagnosticEvent[];
  diagnosticPersistedEvents: BrowserDiagnosticEvent[];
  diagnosticPersistedTotal: number;
  diagnosticPersistedLimit: number;
  diagnosticPersistedOffset: number;
  diagnosticPersistedPage: number;
  diagnosticPersistedPageCount: number;
  diagnosticPersistedRetentionLine: string;
  diagnosticPersistedStatusLine: string;
  diagnosticPersistedExportPreview: string;
  recentEvents: string[];
}

const BROWSER_TEST_LAB_URL = 'aira://release-disabled';
const RCP_RANGE_DOWNLOAD_PROBE_URL = 'aira://release-disabled';
const RCP_STREAMING_SEGMENTED_DOWNLOAD_PROBE_URL = 'aira://release-disabled';
const SEGMENTED_RANGE_DOWNLOAD_PROBE_URL = 'aira://release-disabled';

export function isBrowserTestLabUrl(_url: string): boolean {
  return false;
}

export function getBrowserTestLabUrl(): string {
  return BROWSER_TEST_LAB_URL;
}

export function getBrowserTestLabTitle(): string {
  return 'Aira';
}

export function isRcpRangeDownloadProbeUrl(_url: string): boolean {
  return false;
}

export function isRcpStreamingSegmentedDownloadProbeUrl(_url: string): boolean {
  return false;
}

export function isSegmentedRangeDownloadProbeUrl(_url: string): boolean {
  return false;
}

export function buildBrowserTestLabHtml(_debugState?: BrowserTestLabDebugState): string {
  return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8" /></head><body>Aira</body></html>';
}
`);

if (fs.existsSync(animationCurvePage)) fs.writeFileSync(animationCurvePage, `const ANIMATION_CURVE_PREVIEW_URL = 'aira://release-disabled';

export function isAnimationCurvePreviewUrl(_url: string): boolean {
  return false;
}

export function getAnimationCurvePreviewUrl(): string {
  return ANIMATION_CURVE_PREVIEW_URL;
}

export function getAnimationCurvePreviewTitle(): string {
  return 'Aira';
}

export function buildAnimationCurvePreviewHtml(): string {
  return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8" /></head><body>Aira</body></html>';
}
`);

if (fs.existsSync(newWindowTestPage)) fs.writeFileSync(newWindowTestPage, `const BROWSER_NEW_WINDOW_TEST_URL = 'aira://release-disabled';

export function isBrowserNewWindowTestUrl(_url: string): boolean {
  return false;
}

export function getBrowserNewWindowTestUrl(): string {
  return BROWSER_NEW_WINDOW_TEST_URL;
}

export function getBrowserNewWindowTestTitle(): string {
  return 'Aira';
}

export function resolveBrowserNewWindowTestTitle(_url: string, fallbackTitle: string): string {
  return fallbackTitle;
}

export function buildBrowserNewWindowTestHtml(): string {
  return '<!doctype html><html lang="zh-CN"><head><meta charset="utf-8" /></head><body>Aira</body></html>';
}
`);

const flagsSource = fs.readFileSync(buildVariantFlags, 'utf8');
const developmentDiagnosticsFlag = 'export const AIRA_ENABLE_DEVELOPMENT_DIAGNOSTICS: boolean = true;';
const releaseDiagnosticsFlag = 'export const AIRA_ENABLE_DEVELOPMENT_DIAGNOSTICS: boolean = false;';
const debugLegacyFlag = 'export const AIRA_DEBUG_TREAT_AIRACLOUD_AS_V4_LEGACY: boolean = true;';
const releaseLegacyFlag = 'export const AIRA_DEBUG_TREAT_AIRACLOUD_AS_V4_LEGACY: boolean = false;';
let nextFlagsSource = flagsSource;
if (nextFlagsSource.includes(developmentDiagnosticsFlag)) {
  nextFlagsSource = nextFlagsSource.replace(
    developmentDiagnosticsFlag,
    releaseDiagnosticsFlag
  );
} else if (!nextFlagsSource.includes(releaseDiagnosticsFlag)) {
  throw new Error(`Could not find development diagnostics flag in ${buildVariantFlags}`);
}
if (nextFlagsSource.includes(debugLegacyFlag)) {
  nextFlagsSource = nextFlagsSource.replace(debugLegacyFlag, releaseLegacyFlag);
} else if (!nextFlagsSource.includes(releaseLegacyFlag)) {
  throw new Error(`Could not find Aira Cloud V4 legacy debug flag in ${buildVariantFlags}`);
}
fs.writeFileSync(buildVariantFlags, nextFlagsSource);
NODE
  echo "Using release source pruning: removed debug lab HTML and development diagnostics buttons."
}


apply_debug_aira_cloud_v4_legacy_flag() {
  local build_variant_flags="${PROJECT_DIR}/entry/src/main/ets/common/config/BuildVariantFlags.ets"
  backup_release_file "${build_variant_flags}"
  "${NODE_BIN}" - "${build_variant_flags}" <<'NODE'
const fs = require('fs');
const buildVariantFlags = process.argv[2];
const source = fs.readFileSync(buildVariantFlags, 'utf8');
const debugLegacyFlag = 'export const AIRA_DEBUG_TREAT_AIRACLOUD_AS_V4_LEGACY: boolean = true;';
const releaseLegacyFlag = 'export const AIRA_DEBUG_TREAT_AIRACLOUD_AS_V4_LEGACY: boolean = false;';
if (source.includes(debugLegacyFlag)) {
  process.exit(0);
}
if (!source.includes(releaseLegacyFlag)) {
  throw new Error(`Could not find Aira Cloud V4 legacy debug flag in ${buildVariantFlags}`);
}
fs.writeFileSync(buildVariantFlags, source.replace(releaseLegacyFlag, debugLegacyFlag));
NODE
  echo "Using debug Aira Cloud V4 cutover candidate override."
}

read_signing_paths() {
  "${NODE_BIN}" - "$1" "${2:-}" <<'NODE'
const fs = require('fs');

const [profilePath, requestedConfigName] = process.argv.slice(2);
const source = fs.readFileSync(profilePath, 'utf8');
const data = new Function(`return (${source});`)();
const configs = data.app?.signingConfigs || [];
const products = data.app?.products || [];
const defaultProduct = products.find((product) => product.name === 'default') || products[0];
const configName = requestedConfigName || defaultProduct?.signingConfig || configs[0]?.name || '';
const config = configs.find((item) => item.name === configName);
if (!config) {
  process.exit(1);
}
const material = config.material || {};
    process.stdout.write([
      material.certpath || "",
      material.storeFile || "",
      material.profile || "",
      material.keyAlias || "",
      material.storePassword || "",
      material.keyPassword || "",
    ].join("\n"));
NODE
}

read_profile_api_versions() {
  "${NODE_BIN}" - "$1" <<'NODE'
const fs = require('fs');

const profilePath = process.argv[2];
const source = fs.readFileSync(profilePath, 'utf8');
const data = new Function(`return (${source});`)();
const products = data.app?.products || [];
const product = products.find((item) => item.name === 'default') || products[0];

function parseApiVersion(value) {
  if (typeof value === 'number' && Number.isSafeInteger(value)) {
    return value;
  }
  const text = String(value ?? '').trim();
  const parenthesized = text.match(/\((\d+)\)\s*$/);
  if (parenthesized !== null) {
    return Number(parenthesized[1]);
  }
  const semantic = text.match(/^(\d+)(?:\.\d+){0,2}$/);
  if (semantic !== null) {
    return Number(semantic[1]);
  }
  return NaN;
}

if (!product) {
  process.exit(1);
}

const compatible = parseApiVersion(product.compatibleSdkVersion);
const target = parseApiVersion(product.targetSdkVersion);
if (!Number.isSafeInteger(compatible) || !Number.isSafeInteger(target)) {
  process.exit(1);
}
process.stdout.write(`${compatible}\n${target}`);
NODE
}

validate_minimum_api_version() {
  local profile_path="$1"
  local api_versions
  local compatible_api_version
  local target_api_version

  api_versions="$(read_profile_api_versions "${profile_path}")" || return 1
  compatible_api_version="$(printf '%s\n' "${api_versions}" | sed -n '1p')"
  target_api_version="$(printf '%s\n' "${api_versions}" | sed -n '2p')"
  [ "${compatible_api_version}" -ge "${MIN_SUPPORTED_API_VERSION}" ] || return 1
  [ "${target_api_version}" -ge "${MIN_SUPPORTED_API_VERSION}" ] || return 1
}

apply_product_signing_config() {
  local profile_path="$1"
  local signing_config_name="$2"

  "${NODE_BIN}" - "${profile_path}" "${signing_config_name}" <<'NODE'
const fs = require('fs');

const [profilePath, signingConfigName] = process.argv.slice(2);
const source = fs.readFileSync(profilePath, 'utf8');
const data = new Function(`return (${source});`)();
const configs = data.app?.signingConfigs || [];
if (!configs.some((config) => config.name === signingConfigName)) {
  throw new Error(`Signing config not found: ${signingConfigName}`);
}

let updated = false;
for (const product of data.app?.products || []) {
  if (product.name === 'default') {
    product.signingConfig = signingConfigName;
    updated = true;
  }
}
if (!updated) {
  throw new Error('Default product not found in build profile.');
}

fs.writeFileSync(profilePath, `${JSON.stringify(data, null, 2)}\n`);
NODE
}

verify_profile() {
  "${JAVA_BIN}" -jar "${SIGN_TOOL_JAR}" verify-profile -inFile "$1" 2>&1
}

profile_verified() {
  printf '%s\n' "$1" | grep -q '"verifiedPassed": true'
}

extract_profile_bundle_name() {
  printf '%s\n' "$1" | sed -n 's|.*"bundle-name": "\(.*\)",$|\1|p' | head -n 1
}

extract_profile_type() {
  printf '%s\n' "$1" | sed -n 's|.*"type": "\(.*\)",$|\1|p' | head -n 1
}

extract_profile_issuer() {
  printf '%s\n' "$1" | sed -n 's|.*"issuer": "\(.*\)".*|\1|p' | head -n 1
}

material_from_profile() {
  local profile_path="$1"
  local profile_base="${profile_path%.p7b}"
  printf '%s\n%s\n%s\n' \
    "${profile_base}.cer" \
    "${profile_base}.p12" \
    "${profile_base}.p7b"
}

material_exists() {
  [ -f "$1" ] && [ -f "$2" ] && [ -f "$3" ]
}

write_discovered_build_profile() {
  local profile_path="$1"
  local signing_config_name="$2"
  local material_paths
  local sign_cert_path
  local sign_store_path
  local sign_profile_path

  material_paths="$(material_from_profile "${profile_path}")"
  sign_cert_path="$(printf '%s\n' "${material_paths}" | sed -n '1p')"
  sign_store_path="$(printf '%s\n' "${material_paths}" | sed -n '2p')"
  sign_profile_path="$(printf '%s\n' "${material_paths}" | sed -n '3p')"

  if ! material_exists "${sign_cert_path}" "${sign_store_path}" "${sign_profile_path}"; then
    return 1
  fi

  DISCOVERED_BUILD_PROFILE="$(mktemp "${TMPDIR:-/tmp}/aira-discovered-build-profile-json5.XXXXXX")"
  "${NODE_BIN}" - \
    "${BUILD_PROFILE_TEMPLATE}" \
    "${DISCOVERED_BUILD_PROFILE}" \
    "${signing_config_name}" \
    "${sign_cert_path}" \
    "${sign_store_path}" \
    "${sign_profile_path}" <<'NODE'
const fs = require('fs');

const [templatePath, outputPath, signingConfigName, certpath, storeFile, profile] = process.argv.slice(2);
const source = fs.readFileSync(templatePath, 'utf8');
const data = new Function(`return (${source});`)();
if (!data.app || !Array.isArray(data.app.signingConfigs)) {
  throw new Error('Build profile app.signingConfigs must be an array.');
}
const config = data.app.signingConfigs.find((item) => item.name === signingConfigName) || {
  name: signingConfigName,
  material: {}
};
const material = config.material || {};
material.certpath = certpath;
material.storeFile = storeFile;
material.profile = profile;
config.material = material;
if (!data.app.signingConfigs.includes(config)) {
  data.app.signingConfigs.push(config);
}
const product = (data.app.products || []).find((item) => item.name === 'default') || data.app.products?.[0];
if (!product) {
  throw new Error('Default product not found in build profile.');
}
product.signingConfig = signingConfigName;
fs.writeFileSync(outputPath, `${JSON.stringify(data, null, 2)}\n`);
NODE
}

discover_matching_build_profile() {
  local profile_path
  local profile_verify_output
  local profile_bundle_name
  local profile_issuer

  [ -d "${OHOS_CONFIG_DIR}" ] || return 1

  for profile_path in "${OHOS_CONFIG_DIR}"/*.p7b; do
    [ -f "${profile_path}" ] || continue
    profile_verify_output="$(verify_profile "${profile_path}")"
    if ! profile_verified "${profile_verify_output}"; then
      continue
    fi
    profile_bundle_name="$(extract_profile_bundle_name "${profile_verify_output}")"
    [ "${profile_bundle_name}" = "${APP_BUNDLE_NAME}" ] || continue

    profile_issuer="$(extract_profile_issuer "${profile_verify_output}")"
    if [ "${profile_issuer}" != "app_gallery" ] && [ "${AIRA_ALLOW_OPENHARMONY_SIGNING:-0}" != "1" ]; then
      continue
    fi

    if write_discovered_build_profile "${profile_path}" "${EXPECTED_SIGNING_CONFIG_NAME}"; then
      return 0
    fi
  done

  return 1
}

prepare_build_profile() {
  local source_profile="$1"
  local signing_config_name="$2"
  local should_patch_signing=0
  if [ -n "${signing_config_name}" ]; then
    should_patch_signing=1
  fi

  if [ "${source_profile}" != "${BUILD_PROFILE_TEMPLATE}" ] || [ "${should_patch_signing}" = "1" ]; then
    BUILD_PROFILE_BACKUP="$(mktemp "${TMPDIR:-/tmp}/aira-build-profile-backup-json5.XXXXXX")"
    cp "${BUILD_PROFILE_TEMPLATE}" "${BUILD_PROFILE_BACKUP}"
  fi

  if [ "${source_profile}" != "${BUILD_PROFILE_TEMPLATE}" ]; then
    cp "${source_profile}" "${BUILD_PROFILE_TEMPLATE}"
  fi

  if [ "${should_patch_signing}" = "1" ]; then
    apply_product_signing_config "${BUILD_PROFILE_TEMPLATE}" "${signing_config_name}"
  fi
}

apply_distribution_configuration

SOURCE_APP_BUNDLE_NAME="$(read_bundle_name "${APP_CONFIG}")"
SOURCE_APP_NAME="$(read_app_name)"
SOURCE_ENTRY_ABILITY_LABEL="$(read_entry_ability_label)"
SOURCE_APP_VERSION_NAME="$(read_version_name "${APP_CONFIG}")"
SOURCE_APP_VERSION_CODE="$(read_version_code "${APP_CONFIG}")"
LATEST_RELEASE_VERSION_NAME=""
LATEST_RELEASE_VERSION_CODE=""
DEFAULT_INSTALL_TARGET_LIST=""
SHOULD_AUTO_VERSION_DEFAULT_INSTALL=0
if [ "${BUILD_VARIANT}" = "default" ] &&
   [ "${BUILD_PACKAGE_FORMAT}" = "hap" ] &&
   [ "${SKIP_INSTALL:-0}" != "1" ] &&
   [ "${DEFAULT_INSTALL_AUTO_VERSION}" = "1" ] &&
   [ -z "${AIRA_VERSION_NAME:-}" ] &&
   [ -z "${AIRA_VERSION_CODE:-}" ]; then
  DEFAULT_INSTALL_TARGET_LIST="$(list_connected_targets || true)"
  if [ -n "${DEFAULT_INSTALL_TARGET_LIST}" ]; then
    SHOULD_AUTO_VERSION_DEFAULT_INSTALL=1
  fi
fi
if [ "${BUILD_VARIANT}" = "release" ] || [ "${SHOULD_AUTO_VERSION_DEFAULT_INSTALL}" = "1" ]; then
  LATEST_RELEASE_VERSION_NAME="$(read_latest_release_version_name "${RELEASE_HISTORY}")"
  LATEST_RELEASE_VERSION_CODE="$(read_latest_release_version_code "${RELEASE_HISTORY}")"
fi
TARGET_VERSION_NAME="${SOURCE_APP_VERSION_NAME}"
TARGET_VERSION_CODE="${SOURCE_APP_VERSION_CODE}"
if [ "${BUILD_VARIANT}" = "default" ]; then
  if [ "${SHOULD_AUTO_VERSION_DEFAULT_INSTALL}" = "1" ] && [ -n "${LATEST_RELEASE_VERSION_NAME}" ]; then
    TARGET_VERSION_NAME="$(derive_next_release_version_name "${SOURCE_APP_VERSION_NAME}" "${LATEST_RELEASE_VERSION_NAME}")"
  fi
else
  if [ -n "${LATEST_RELEASE_VERSION_NAME}" ]; then
    TARGET_VERSION_NAME="$(derive_next_release_version_name "${SOURCE_APP_VERSION_NAME}" "${LATEST_RELEASE_VERSION_NAME}")"
  else
    TARGET_VERSION_NAME="$(derive_release_version_name "${SOURCE_APP_VERSION_NAME}")"
  fi
fi

if [ "${BUILD_VARIANT}" = "default" ] && [ "${SHOULD_AUTO_VERSION_DEFAULT_INSTALL}" = "1" ]; then
  if [ -n "${LATEST_RELEASE_VERSION_CODE}" ]; then
    if ! printf '%s' "${LATEST_RELEASE_VERSION_CODE}" | grep -Eq '^[0-9]+$'; then
      fail "Latest AppGallery release versionCode must be a positive integer in ${RELEASE_HISTORY}. Received: ${LATEST_RELEASE_VERSION_CODE}"
    fi
    NEXT_RELEASE_VERSION_CODE="$(increment_version_code "${LATEST_RELEASE_VERSION_CODE}")"
    if [ "${NEXT_RELEASE_VERSION_CODE}" -gt "${TARGET_VERSION_CODE}" ]; then
      TARGET_VERSION_CODE="${NEXT_RELEASE_VERSION_CODE}"
    fi
  fi

  DEFAULT_INSTALL_TARGETS=()
  if [ -n "${HDC_TARGET:-}" ]; then
    DEFAULT_INSTALL_TARGETS+=("${HDC_TARGET}")
  else
    while IFS= read -r target; do
      DEFAULT_INSTALL_TARGETS+=("${target}")
    done <<< "${DEFAULT_INSTALL_TARGET_LIST}"
  fi

  for target in "${DEFAULT_INSTALL_TARGETS[@]}"; do
    INSTALLED_VERSION_CODE="$(read_installed_version_code "${target}" "${SOURCE_APP_BUNDLE_NAME}")"
    if [ -z "${INSTALLED_VERSION_CODE}" ]; then
      continue
    fi
    if [ "${INSTALLED_VERSION_CODE}" -ge "${MAX_HARMONY_VERSION_CODE}" ]; then
      echo "Installed app on ${target} is already at HarmonyOS maximum versionCode ${MAX_HARMONY_VERSION_CODE}; reusing it for same-version debug install."
      INSTALLED_NEXT_VERSION_CODE="${MAX_HARMONY_VERSION_CODE}"
    else
      INSTALLED_NEXT_VERSION_CODE="$(increment_version_code "${INSTALLED_VERSION_CODE}")"
    fi
    if [ "${INSTALLED_NEXT_VERSION_CODE}" -gt "${TARGET_VERSION_CODE}" ]; then
      TARGET_VERSION_CODE="${INSTALLED_NEXT_VERSION_CODE}"
    fi
  done
fi

if [ "${BUILD_VARIANT}" = "release" ] && [ "${RELEASE_AUTO_INCREMENT_VERSION_CODE}" = "1" ]; then
  if [ -n "${LATEST_RELEASE_VERSION_CODE}" ]; then
    TARGET_VERSION_CODE="$(increment_version_code "${LATEST_RELEASE_VERSION_CODE}")"
  else
    TARGET_VERSION_CODE="$(increment_version_code "${SOURCE_APP_VERSION_CODE}")"
  fi
fi

if [ "${BUILD_VARIANT}" = "release" ] && [ -n "${AIRA_RELEASE_VERSION_NAME:-}" ]; then
  TARGET_VERSION_NAME="${AIRA_RELEASE_VERSION_NAME}"
fi

if [ "${BUILD_VARIANT}" = "release" ] && [ -n "${AIRA_RELEASE_VERSION_CODE:-}" ]; then
  TARGET_VERSION_CODE="${AIRA_RELEASE_VERSION_CODE}"
fi

if [ -n "${AIRA_VERSION_NAME:-}" ]; then
  TARGET_VERSION_NAME="${AIRA_VERSION_NAME}"
fi

if [ -n "${AIRA_VERSION_CODE:-}" ]; then
  TARGET_VERSION_CODE="${AIRA_VERSION_CODE}"
fi

echo "Build variant: ${BUILD_VARIANT}"
echo "Build package format: ${BUILD_PACKAGE_FORMAT}"
if [ "${BUILD_VARIANT}" = "release" ] && [ -n "${LATEST_RELEASE_VERSION_NAME}" ] && [ -n "${LATEST_RELEASE_VERSION_CODE}" ]; then
  echo "Latest AppGallery release: ${LATEST_RELEASE_VERSION_NAME} (${LATEST_RELEASE_VERSION_CODE})"
  echo "Release history: ${RELEASE_HISTORY}"
fi
if [ "${BUILD_VARIANT}" = "default" ] && [ "${SHOULD_AUTO_VERSION_DEFAULT_INSTALL}" = "1" ]; then
  echo "Default install auto-version: enabled"
  if [ -n "${LATEST_RELEASE_VERSION_NAME}" ] && [ -n "${LATEST_RELEASE_VERSION_CODE}" ]; then
    echo "Latest AppGallery release: ${LATEST_RELEASE_VERSION_NAME} (${LATEST_RELEASE_VERSION_CODE})"
  fi
fi
echo "Target app version: ${TARGET_VERSION_NAME} (${TARGET_VERSION_CODE})"

if [ -z "${TARGET_VERSION_NAME}" ]; then
  fail "Failed to resolve target versionName."
fi

if ! printf '%s' "${TARGET_VERSION_CODE}" | grep -Eq '^[0-9]+$'; then
  fail "Target versionCode must be a positive integer. Received: ${TARGET_VERSION_CODE}"
fi

if [ "${TARGET_VERSION_CODE}" -lt 1 ]; then
  fail "Target versionCode must be greater than 0. Received: ${TARGET_VERSION_CODE}"
fi

if [ "${TARGET_VERSION_CODE}" -gt "${MAX_HARMONY_VERSION_CODE}" ]; then
  fail "Target versionCode ${TARGET_VERSION_CODE} exceeds HarmonyOS maximum ${MAX_HARMONY_VERSION_CODE}."
fi

if [ "${BUILD_VARIANT}" = "release" ] && [ -n "${LATEST_RELEASE_VERSION_CODE}" ]; then
  if ! printf '%s' "${LATEST_RELEASE_VERSION_CODE}" | grep -Eq '^[0-9]+$'; then
    fail "Latest AppGallery release versionCode must be a positive integer in ${RELEASE_HISTORY}. Received: ${LATEST_RELEASE_VERSION_CODE}"
  fi
  if [ "${TARGET_VERSION_CODE}" -le "${LATEST_RELEASE_VERSION_CODE}" ]; then
    fail "Release target versionCode ${TARGET_VERSION_CODE} must be greater than latest AppGallery release ${LATEST_RELEASE_VERSION_CODE}. Update ${RELEASE_HISTORY} only after a package is actually approved/on shelf, or set AIRA_RELEASE_VERSION_CODE to a larger value."
  fi
fi

if [ "${SOURCE_APP_BUNDLE_NAME}" != "${PACKAGE_BUNDLE_NAME}" ]; then
  fail "App bundleName must remain ${PACKAGE_BUNDLE_NAME} for ${DISTRIBUTION}. Found ${SOURCE_APP_BUNDLE_NAME} in ${APP_CONFIG}."
fi

if [ "${SOURCE_APP_NAME}" != "${EXPECTED_APP_NAME}" ] || [ "${SOURCE_ENTRY_ABILITY_LABEL}" != "${EXPECTED_APP_NAME}" ]; then
  fail "App name must remain ${EXPECTED_APP_NAME} for ${DISTRIBUTION}. Found AppScope=${SOURCE_APP_NAME}, EntryAbility=${SOURCE_ENTRY_ABILITY_LABEL}."
fi

if [ "${SOURCE_APP_VERSION_NAME}" != "${TARGET_VERSION_NAME}" ] || [ "${SOURCE_APP_VERSION_CODE}" != "${TARGET_VERSION_CODE}" ]; then
  apply_version_override "${TARGET_VERSION_NAME}" "${TARGET_VERSION_CODE}"
fi

APP_BUNDLE_NAME="$(read_bundle_name "${APP_CONFIG}")"
if [ -z "${APP_BUNDLE_NAME}" ]; then
  fail "Failed to resolve bundleName from ${APP_CONFIG}"
fi

if [ "${BUILD_VARIANT}" = "release" ]; then
  apply_release_page_pruning
  apply_release_source_pruning
else
  apply_debug_aira_cloud_v4_legacy_flag
fi

validate_effective_build_profile() {
  local profile_path="$1"
  local signing_config_name="${2:-}"
  local signing_paths
  local sign_cert_path
  local sign_store_path
  local sign_profile_path

  if ! validate_minimum_api_version "${profile_path}"; then
    return 1
  fi

  signing_paths="$(read_signing_paths "${profile_path}" "${signing_config_name}")"
  sign_cert_path="$(printf '%s\n' "${signing_paths}" | sed -n '1p')"
  sign_store_path="$(printf '%s\n' "${signing_paths}" | sed -n '2p')"
  sign_profile_path="$(printf '%s\n' "${signing_paths}" | sed -n '3p')"

  [ -n "${sign_cert_path}" ] || return 1
  [ -n "${sign_store_path}" ] || return 1
  [ -n "${sign_profile_path}" ] || return 1

  if ! material_exists "${sign_cert_path}" "${sign_store_path}" "${sign_profile_path}"; then
    return 1
  fi

  local profile_verify_output
  local profile_bundle_name
  local profile_type
  local profile_issuer
  profile_verify_output="$(verify_profile "${sign_profile_path}")"
  if ! profile_verified "${profile_verify_output}"; then
    return 1
  fi

  profile_bundle_name="$(extract_profile_bundle_name "${profile_verify_output}")"
  [ "${profile_bundle_name}" = "${APP_BUNDLE_NAME}" ] || return 1

  profile_type="$(extract_profile_type "${profile_verify_output}")"
  if [ "${BUILD_VARIANT}" = "release" ] && [ "${profile_type}" = "debug" ]; then
    return 1
  fi

  profile_issuer="$(extract_profile_issuer "${profile_verify_output}")"
  if [ "${profile_issuer}" != "app_gallery" ] && [ "${AIRA_ALLOW_OPENHARMONY_SIGNING:-0}" != "1" ]; then
    return 1
  fi
}

EXPECTED_SIGNING_CONFIG_NAME=""
if [ "${BUILD_VARIANT}" = "release" ]; then
  EXPECTED_SIGNING_CONFIG_NAME="${RELEASE_SIGNING_CONFIG_NAME}"
else
  EXPECTED_SIGNING_CONFIG_NAME="${DEFAULT_SIGNING_CONFIG_NAME}"
fi

SOURCE_BUILD_PROFILE="${BUILD_PROFILE_TEMPLATE}"
SOURCE_PROFILE_MODE="template"
if [ "${ALLOW_UNSIGNED_BUILD}" = "1" ]; then
  SOURCE_PROFILE_MODE="unsigned-template"
else
  if [ -n "${AIRA_BUILD_PROFILE:-}" ]; then
    SOURCE_BUILD_PROFILE="${AIRA_BUILD_PROFILE}"
    SOURCE_PROFILE_MODE="env"
  elif [ -f "${BUILD_PROFILE_LOCAL}" ]; then
    if validate_effective_build_profile "${BUILD_PROFILE_LOCAL}" "${EXPECTED_SIGNING_CONFIG_NAME}"; then
      SOURCE_BUILD_PROFILE="${BUILD_PROFILE_LOCAL}"
      SOURCE_PROFILE_MODE="local"
    else
      echo "Skipping local signing profile because it does not match ${APP_BUNDLE_NAME} or minimum API ${MIN_SUPPORTED_API_VERSION}: ${BUILD_PROFILE_LOCAL}"
    fi
  fi

  if [ "${SOURCE_PROFILE_MODE}" != "env" ] && ! validate_effective_build_profile "${SOURCE_BUILD_PROFILE}" "${EXPECTED_SIGNING_CONFIG_NAME}"; then
    if discover_matching_build_profile; then
      SOURCE_BUILD_PROFILE="${DISCOVERED_BUILD_PROFILE}"
      SOURCE_PROFILE_MODE="discovered"
    fi
  fi
fi

if [ ! -f "${SOURCE_BUILD_PROFILE}" ]; then
  fail "Build profile source not found at ${SOURCE_BUILD_PROFILE}"
fi

if ! validate_minimum_api_version "${SOURCE_BUILD_PROFILE}"; then
  fail "Build profile ${SOURCE_BUILD_PROFILE} must set compatibleSdkVersion and targetSdkVersion to HarmonyOS API ${MIN_SUPPORTED_API_VERSION} or newer."
fi

if [ "${ALLOW_UNSIGNED_BUILD}" = "1" ]; then
  echo "Using unsigned Community build profile: ${SOURCE_BUILD_PROFILE}"
  prepare_build_profile "${SOURCE_BUILD_PROFILE}" ""
else
  echo "Using signing profile: ${SOURCE_BUILD_PROFILE} (${SOURCE_PROFILE_MODE})"

  if ! validate_effective_build_profile "${SOURCE_BUILD_PROFILE}" "${EXPECTED_SIGNING_CONFIG_NAME}"; then
    if [ "${BUILD_VARIANT}" = "release" ]; then
      fail "Release signing profile verification failed for ${SOURCE_BUILD_PROFILE}. Make sure the release signing config uses a valid AppGallery release Profile for ${APP_BUNDLE_NAME}, not a debug/auto-signing Profile, or pass AIRA_BUILD_PROFILE=/abs/path/to/build-profile.json5."
    fi
    fail "Signing profile verification failed for ${SOURCE_BUILD_PROFILE}. Make sure DevEco Signing Configs are valid and the profile bundle-name matches ${APP_BUNDLE_NAME}, or pass AIRA_BUILD_PROFILE=/abs/path/to/build-profile.json5."
  fi

  echo "Using signing config: ${EXPECTED_SIGNING_CONFIG_NAME}"

  prepare_build_profile "${SOURCE_BUILD_PROFILE}" "${EXPECTED_SIGNING_CONFIG_NAME}"
fi
remove_release_app_outputs
remove_release_app_loose_haps
rm -f \
  "${PROJECT_DIR}/entry/build/default/outputs/default/entry-default-signed.hap" \
  "${PROJECT_DIR}/entry/build/default/outputs/default/entry-default-unsigned.hap"

cd "${PROJECT_DIR}"
"${NODE_BIN}" "${HVIGOR_BIN}" --stop-daemon >/dev/null 2>&1 || true
if [ "${BUILD_PACKAGE_FORMAT}" = "app" ]; then
  HVIGOR_TASK="assembleApp"
  HVIGOR_MODE="project"
else
  HVIGOR_TASK="assembleHap"
  HVIGOR_MODE="module"
fi
HVIGOR_ARGS=(
  --mode "${HVIGOR_MODE}"
  -p product=default
)
if [ "${BUILD_VARIANT}" = "release" ]; then
  HVIGOR_ARGS+=(-p buildMode=release)
fi
HVIGOR_ARGS+=(
  "${HVIGOR_TASK}"
  --analyze=normal
  --parallel
  --incremental
)
if ! "${NODE_BIN}" "${HVIGOR_BIN}" "${HVIGOR_ARGS[@]}"; then
  echo
  echo "Build failed for bundleName: ${APP_BUNDLE_NAME}"
  echo "If the error above says 'keystore password was incorrect', open this project in DevEco Studio and refresh Signing Configs for this exact bundle name."
  echo "DevEco/Hvigor encrypted signing passwords are machine-local, so a copied build-profile JSON can point to the right files but still have stale encrypted passwords."
  exit 1
fi

archive_crash_symbols

SIGNED_HAP="${PROJECT_DIR}/entry/build/default/outputs/default/entry-default-signed.hap"
UNSIGNED_HAP="${PROJECT_DIR}/entry/build/default/outputs/default/entry-default-unsigned.hap"
SIGNED_APP="$(find "${APP_OUTPUT_DIR}" -maxdepth 1 -type f -name '*-signed.app' 2>/dev/null | sort | tail -n 1 || true)"
UNSIGNED_APP="$(find "${APP_OUTPUT_DIR}" -maxdepth 1 -type f -name '*.app' ! -name '*-signed.app' 2>/dev/null | sort | tail -n 1 || true)"
OUTPUT_HAP=""
OUTPUT_APP=""

echo
echo "Build output:"
if [ "${BUILD_PACKAGE_FORMAT}" = "app" ]; then
  if [ -n "${SIGNED_APP}" ] && [ -f "${SIGNED_APP}" ]; then
    OUTPUT_APP="${SIGNED_APP}"
    APP_SIGNATURE_LABEL="signed"
  elif [ -n "${UNSIGNED_APP}" ] && [ -f "${UNSIGNED_APP}" ]; then
    OUTPUT_APP="${UNSIGNED_APP}"
    APP_SIGNATURE_LABEL="unsigned"
  else
    fail "No APP output found."
  fi

  STANDARD_VERSION_NAME="$(sanitize_package_filename_part "${TARGET_VERSION_NAME}")"
  STANDARD_VERSION_CODE="$(sanitize_package_filename_part "${TARGET_VERSION_CODE}")"
  STANDARD_APP_NAME="Aira-${DISTRIBUTION}-v${STANDARD_VERSION_NAME}-${STANDARD_VERSION_CODE}-${BUILD_VARIANT}-${APP_SIGNATURE_LABEL}.app"
  STANDARD_APP_PATH="$(dirname "${OUTPUT_APP}")/${STANDARD_APP_NAME}"
  if [ "${OUTPUT_APP}" != "${STANDARD_APP_PATH}" ]; then
    mv -f "${OUTPUT_APP}" "${STANDARD_APP_PATH}"
  fi
  remove_other_app_outputs "${STANDARD_APP_PATH}"
  remove_release_app_loose_haps

  echo "${STANDARD_APP_PATH}"
  echo
  echo "Skip install because .app packages are for distribution and cannot be installed directly."
  exit 0
elif [ -f "${SIGNED_HAP}" ]; then
  OUTPUT_HAP="${SIGNED_HAP}"
elif [ -f "${UNSIGNED_HAP}" ]; then
  OUTPUT_HAP="${UNSIGNED_HAP}"
else
  fail "No HAP output found."
fi

echo "${OUTPUT_HAP}"

if [ "${SKIP_INSTALL:-0}" = "1" ]; then
  echo
  echo "Skip install because SKIP_INSTALL=1."
  exit 0
fi

TARGET_LIST="$(list_connected_targets)"
if [ -z "${TARGET_LIST}" ]; then
  echo
  echo "No connected devices detected. Build finished without installation."
  exit 0
fi

TARGET_COUNT="$(printf '%s\n' "${TARGET_LIST}" | wc -l | tr -d ' ')"
INSTALL_TARGET="${HDC_TARGET:-}"
INSTALL_TARGETS=()

if [ -n "${INSTALL_TARGET}" ]; then
  INSTALL_TARGETS+=("${INSTALL_TARGET}")
else
  while IFS= read -r target; do
    INSTALL_TARGETS+=("${target}")
  done <<< "${TARGET_LIST}"
fi

echo
if [ "${TARGET_COUNT}" = "1" ]; then
  echo "Installing to connected device."
else
  echo "Multiple devices detected. Installing to all connected devices:"
  printf '%s\n' "${INSTALL_TARGETS[@]}"
  echo "Set HDC_TARGET=<device-id> to install only one device."
fi

for target in "${INSTALL_TARGETS[@]}"; do
  echo
  echo "Installing to device: ${target}"
  install_hap_to_target "${target}" "${OUTPUT_HAP}"

  echo "Stopping running app process on ${target} so the next launch uses the updated package."
  "${HDC_BIN}" -t "${target}" shell aa force-stop "${APP_BUNDLE_NAME}" >/dev/null 2>&1 || true
done
