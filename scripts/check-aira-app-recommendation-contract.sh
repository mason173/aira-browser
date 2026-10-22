#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PERL_BIN="${PERL_BIN:-/usr/bin/perl}"
failures=0

fail() {
  printf 'App recommendation contract violation: %s\n' "$1" >&2
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

CONTENT_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationContent.ets"
SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationSheet.ets"
OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationOverlay.ets"
PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/SettingsAppRecommendationPage.ets"
ROUTES_REL="AiraBrowser/entry/src/main/ets/app/router/AppRoutes.ets"
NAV_REL="AiraBrowser/entry/src/main/ets/app/router/SettingsNavigationCoordinator.ets"
MAIN_PAGES_REL="AiraBrowser/entry/src/main/resources/base/profile/main_pages.json"
CENTER_VM_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsCenterViewModel.ets"
CATALOG_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsDestinationCatalog.ets"
COPY_REL="AiraBrowser/entry/src/main/ets/core/settings/SettingsCatalogCopy.ets"
STORE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/system/SystemSettingsLaunchService.ets"
ADR_REL="docs/adr/0089-the-app-recommendation-lands-in-settings.md"
TRANSIENT_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
SHELL_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellBackCoordinator.ets"
TAB_HOME_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"

for rel_path in "${CONTENT_REL}" "${SHEET_REL}" "${OVERLAY_REL}" "${PAGE_REL}" "${ROUTES_REL}" \
  "${NAV_REL}" "${MAIN_PAGES_REL}" "${CENTER_VM_REL}" "${CATALOG_REL}" "${COPY_REL}" \
  "${STORE_SERVICE_REL}" "${ADR_REL}" "${TRANSIENT_REL}" "${SHELL_BACK_REL}" \
  "${TAB_HOME_REL}" "${RUNTIME_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

if [ ! -x "${PERL_BIN}" ]; then
  fail "Perl is required at ${PERL_BIN}"
fi

if [ "${failures}" -ne 0 ]; then
  exit 1
fi

# One catalog owns what is on offer, and it is source content: adding an app is a catalog
# change plus its artwork, never a code change on the page or the sheet.
require_pattern "${CONTENT_REL}" "export function appRecommendationCatalog" \
  "the catalog must be the single place an offered app is declared."
require_pattern "${CONTENT_REL}" "export function appRecommendationEntryFor" \
  "the catalog must resolve one app for the detail sheet."
require_pattern "${CONTENT_REL}" "storeId: 'com\.noctide\.sleep'" \
  "the catalog must carry the store page the store action hands over."
require_pattern "${SHEET_REL}" "appRecommendationEntryFor" \
  "the sheet must render the app the page opened, not compiled-in copy."
# The card owns no content of its own: its strings live in the catalog and the resource
# files, so a new app never edits the sheet.
forbid_pattern "${SHEET_REL}" "app_recommendation_review_author|app_recommendation_faq_content_title|app_recommendation_tagline" \
  "the sheet must not own app copy; that belongs to the catalog."
forbid_pattern "${CONTENT_REL}" "shownAt|dismissedAt|hasCompleted" \
  "the catalog must not carry presentation state; the page is opened on demand."

# The entry sits in Settings, directly above 关于Aira, and it opens its own page.
require_pattern "${CENTER_VM_REL}" "this\.buildRow\('app_recommendation', '应用推荐'\),\s*\n\s*this\.buildRow\('about', '关于Aira'\)" \
  "应用推荐 must sit directly above 关于Aira in the settings center."
require_pattern "${CENTER_VM_REL}" "case 'app_recommendation':" \
  "the settings center row must carry an icon."
require_pattern "${CATALOG_REL}" "target\('app_recommendation', 'app_recommendation', 'app_recommendation', '应用推荐',[\s\S]{0,200}'routed'\)" \
  "应用推荐 must be a searchable settings destination that always opens its own page."
require_pattern "${CATALOG_REL}" "target\('app_recommendation'[\s\S]{0,300}target\('about', 'about', 'about', '关于Aira'" \
  "应用推荐 must sit directly above 关于Aira in the settings directory."
require_pattern "${COPY_REL}" "case '应用推荐':" \
  "the settings directory string must be localized through the copy table."
require_pattern "${ROUTES_REL}" "SETTINGS_APP_RECOMMENDATION_ROUTE: string = 'app/pages/SettingsAppRecommendationPage'" \
  "the page must have a route of its own."
require_pattern "${MAIN_PAGES_REL}" "app/pages/SettingsAppRecommendationPage" \
  "the page's route must be registered in main_pages.json."
require_pattern "${NAV_REL}" "SETTINGS_APP_RECOMMENDATION_ROUTE," \
  "the route must be imported by the settings navigation owner."
require_pattern "${NAV_REL}" "target\.targetId === 'app_recommendation'[\s\S]{0,160}SETTINGS_APP_RECOMMENDATION_ROUTE" \
  "selecting the entry must push the page's route."

# The page lists the catalog and opens one app's sheet on demand. Nothing announces,
# remembers, or gates it; the user asked for this page.
require_pattern "${PAGE_REL}" "appRecommendationCatalog\(\)" \
  "the page must draw the catalog as its list."
require_pattern "${PAGE_REL}" "SettingsNavigationRow\(" \
  "each app must be a settings row so the page keeps the standard list chrome."
require_pattern "${PAGE_REL}" "AppRecommendationOverlay\(" \
  "the page must host the one detail sheet."
# The card resolves its app from the id, not once at mount: a host that mounts the sheet up
# front, or opens a second app through the same sheet, must still draw the app it opened.
require_pattern "${SHEET_REL}" "@Prop @Watch\('syncEntry'\) recommendationId" \
  "the card must resolve its app again whenever the opened id changes."
require_pattern "${PAGE_REL}" "if \(this\.sheetMounted\)[\s\S]{0,200}AppRecommendationOverlay\(" \
  "the sheet must be mounted only once an app has been opened."
require_pattern "${OVERLAY_REL}" "export type AppRecommendationAction = 'dismiss' \| 'open_market';" \
  "the sheet's actions must be owned by the surface that hosts it."
require_pattern "${PAGE_REL}" "openAppGalleryDetailPageForApp" \
  "the store action must go through the store service."
require_pattern "${STORE_SERVICE_REL}" "openAppGalleryDetailPageForApp" \
  "the store service must own the AppGallery detail deep link and its fallback."

# No arrival may open it, and no surface may be reserved for it: the page is the only
# entry point, and only a tap on a card opens the sheet.
for removed_rel in \
  "AiraBrowser/entry/src/main/ets/core/onboarding/AppRecommendationCoordinator.ets" \
  "AiraBrowser/entry/src/main/ets/data/onboarding/AppRecommendationRepository.ets"; do
  if [ -e "${REPO_ROOT}/${removed_rel}" ]; then
    fail "the app catalog must not regain an automatic presenter: ${removed_rel}"
  fi
done
forbid_pattern "${TRANSIENT_REL}" "'app_recommendation'" \
  "no transient surface may reserve an id for an announcement."
forbid_pattern "${SHELL_BACK_REL}" "dismiss_app_recommendation" \
  "system Back must not carry an announcement branch."
forbid_pattern "${TAB_HOME_REL}" "AppRecommendation" \
  "arriving at the homepage must not open the app catalog."
forbid_pattern "${RUNTIME_REL}" "AppRecommendation" \
  "the runtime must not initialize an app-catalog memory."
require_pattern "${ADR_REL}" "supersedes: ADR-0084" \
  "the move into settings must record the decision it replaces."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi
printf 'App recommendation contract passed: settings-only catalog, on-demand sheet, no announcement.\n'
