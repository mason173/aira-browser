#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'Shortcut store hand-over contract violation: %s\n' "$1" >&2
  failures=$((failures + 1))
}

require_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if ! grep -Eq "${pattern}" "${REPO_ROOT}/${rel_path}"; then
    fail "${message}"
  fi
}

reject_pattern() {
  local rel_path="$1"
  local pattern="$2"
  local message="$3"
  if grep -Eqi "${pattern}" "${REPO_ROOT}/${rel_path}"; then
    fail "${message}"
  fi
}

STORE_HANDOFF_REL="AiraBrowser/entry/src/main/ets/services/shortcuts/ShortcutStoreHandoffCatalog.ets"
OPEN_POLICY_REL="AiraBrowser/entry/src/main/ets/services/shortcuts/HomeShortcutOpenPolicyService.ets"
OPEN_COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/shortcuts/HomeShortcutOpenCoordinator.ets"
BUNDLED_ICON_REL="AiraBrowser/entry/src/main/ets/core/resources/BundledShortcutIconResources.ets"
SHORTCUT_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeShortcutSurface.ets"
SHELL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets"
STORE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/system/SystemSettingsLaunchService.ets"
SHORTCUT_HANDOFF_TEST_REL="AiraBrowser/entry/src/test/HomeShortcutStoreHandoff.test.ets"
TRANSIENT_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
ROOT_BOTTOM_PANEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelSessionCoordinator.ets"
SHELL_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellBackCoordinator.ets"
MAIN_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMainBackCoordinator.ets"
TAB_HOME_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
ADR_REL="docs/adr/0086-a-store-page-shortcut-hands-the-app-over-to-the-store.md"

for rel_path in "${STORE_HANDOFF_REL}" "${OPEN_POLICY_REL}" "${OPEN_COORDINATOR_REL}" \
  "${BUNDLED_ICON_REL}" "${SHORTCUT_SURFACE_REL}" "${SHELL_PAGE_REL}" "${STORE_SERVICE_REL}" \
  "${SHORTCUT_HANDOFF_TEST_REL}" "${TRANSIENT_REL}" "${ROOT_BOTTOM_PANEL_REL}" \
  "${SHELL_BACK_REL}" "${MAIN_BACK_REL}" "${TAB_HOME_REL}" "${RUNTIME_REL}" \
  "${ADR_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# Which pages are store pages is one declared catalog, not a special case in the open path.
require_pattern "${STORE_HANDOFF_REL}" "export function resolveShortcutStoreHandoffId" \
  "which pages are store pages must be a declared catalog, not a special case in the open path."
require_pattern "${STORE_HANDOFF_REL}" "urlPrefix" \
  "the catalog must match the page prefix so share or channel parameters still hand over."
require_pattern "${STORE_HANDOFF_REL}" "com\\.noctide\\.sleep" \
  "the store hand-over rule must be scoped to the app whose store page it answers."
require_pattern "${OPEN_POLICY_REL}" "resolveShortcutStoreHandoffId\\(shortcut\\.url\\)" \
  "the open plan must ask the catalog whether this shortcut's page is a store page."
require_pattern "${OPEN_POLICY_REL}" "kind: 'store'" \
  "a store page must become its own open plan rather than a Web open."
require_pattern "${OPEN_POLICY_REL}" "normalizedIntent === 'current_tab'" \
  "only the tile's own open hands the app over; a tab intent still opens the page it names."
require_pattern "${OPEN_COORDINATOR_REL}" "openStoreDetailPage" \
  "the open coordinator must hand the store page to the store through one port."
require_pattern "${SHELL_PAGE_REL}" "openStoreDetailPage" \
  "the shell must implement the store hand-over the shortcuts open through."
require_pattern "${SHELL_PAGE_REL}" "handOverAppStoreDetailPage" \
  "the shortcut open must reach the store through the shell's one hand-over."
require_pattern "${STORE_SERVICE_REL}" "openAppGalleryDetailPageForApp" \
  "the store service must own the AppGallery detail deep link and its fallback."
require_pattern "${SHORTCUT_HANDOFF_TEST_REL}" "assertEqual\\('store'\\)" \
  "the store hand-over must be covered by the open-plan test."

# A shortcut draws its page's favicon, and a store page's favicon is the store's, so the
# store page ships its app's icon with the app instead.
require_pattern "${BUNDLED_ICON_REL}" "hasBundledShortcutIcon" \
  "a bundled shortcut icon must be an explicit rule, not a special case in the tile."
require_pattern "${BUNDLED_ICON_REL}" "resolveShortcutStoreHandoffId" \
  "the icon rule must look up the app the store hand-over catalog resolved, not repeat the URL."
require_pattern "${BUNDLED_ICON_REL}" "com\\.noctide\\.sleep" \
  "the bundled icon rule must be scoped to the app whose store page it answers."
require_pattern "${BUNDLED_ICON_REL}" "app_recommendation_shengxi" \
  "the bundled icon rule must carry the app's icon."
require_pattern "${SHORTCUT_SURFACE_REL}" "hasBundledShortcutIcon\\(shortcut\\.url\\)" \
  "the shortcut tile must draw the bundled icon for that store page."
require_pattern "${SHORTCUT_SURFACE_REL}" "resolveBundledShortcutIcon\\(shortcut\\.url\\)" \
  "the shortcut tile must draw the bundled icon for that store page."

# The announcement chain stays gone: settings is the only place the app catalog is opened. The
# catalog page itself is pinned by scripts/check-aira-app-recommendation-contract.sh.
reject_pattern "${TRANSIENT_REL}" "'app_recommendation'" \
  "no transient surface may reserve an id for an automatic announcement."
reject_pattern "${ROOT_BOTTOM_PANEL_REL}" "'app_recommendation'" \
  "no root bottom panel owner may reserve an announcement sheet."
reject_pattern "${SHELL_BACK_REL}" "dismiss_app_recommendation" \
  "system Back must not carry an announcement branch."
reject_pattern "${SHELL_PAGE_REL}" "AppRecommendation" \
  "the shell must not host the app catalog; that belongs to the settings page."
reject_pattern "${SHELL_PAGE_REL}" "app_recommendation" \
  "the shell must not host the app catalog; that belongs to the settings page."
reject_pattern "${MAIN_BACK_REL}" "AppRecommendation" \
  "the main back owner must not depend on the app catalog."
reject_pattern "${TAB_HOME_REL}" "AppRecommendation" \
  "arriving at the homepage must not open the app catalog."
reject_pattern "${RUNTIME_REL}" "AppRecommendation" \
  "the runtime must not initialize any app-catalog memory."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi
printf 'Shortcut store hand-over contract passed: one store hand-over for a hand-saved store page.\n'
