#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
failures=0

fail() {
  printf 'App recommendation contract violation: %s\n' "$1" >&2
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

REPOSITORY_REL="AiraBrowser/entry/src/main/ets/data/onboarding/AppRecommendationRepository.ets"
COORDINATOR_REL="AiraBrowser/entry/src/main/ets/core/onboarding/AppRecommendationCoordinator.ets"
CONTENT_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationContent.ets"
SHEET_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationSheet.ets"
OVERLAY_REL="AiraBrowser/entry/src/main/ets/app/components/onboarding/AppRecommendationOverlay.ets"
ICON_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_shengxi.png"
LAUREL_LEFT_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_laurel_left.svg"
LAUREL_RIGHT_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_laurel_right.svg"
AVATAR_CLEAR_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_review_avatar_clear.png"
AVATAR_SPENDING_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_review_avatar_spending.png"
AVATAR_SIMPLE_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_review_avatar_simple.png"
AVATAR_CYCLES_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_review_avatar_cycles.png"
AVATAR_TIDY_REL="AiraBrowser/entry/src/main/resources/base/media/app_recommendation_review_avatar_tidy.png"
TRANSIENT_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTransientSurfaceCoordinator.ets"
BOTTOM_PANEL_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelSessionCoordinator.ets"
SHELL_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserShellBackCoordinator.ets"
MAIN_BACK_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserMainBackCoordinator.ets"
TAB_HOME_REL="AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets"
SHELL_PAGE_REL="AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets"
RUNTIME_REL="AiraBrowser/entry/src/main/ets/app/bootstrap/BrowserAppRuntime.ets"
STORE_SERVICE_REL="AiraBrowser/entry/src/main/ets/services/system/SystemSettingsLaunchService.ets"
SEED_SITES_REL="AiraBrowser/entry/src/main/ets/data/repositories/BrowserDefaultSeedSites.ets"
BUNDLED_ICON_REL="AiraBrowser/entry/src/main/ets/core/resources/BundledShortcutIconResources.ets"
SHORTCUT_SURFACE_REL="AiraBrowser/entry/src/main/ets/app/components/browser/HomeShortcutSurface.ets"
TEST_REL="AiraBrowser/entry/src/test/AppRecommendationCoordinator.test.ets"
ADR_REL="docs/adr/0084-an-app-recommendation-is-announced-once-per-campaign.md"
SEED_SLOT_ADR_REL="docs/adr/0085-the-recommended-app-takes-over-a-default-shortcut-slot.md"
VARIANT_FLAGS_REL="AiraBrowser/entry/src/main/ets/common/config/BuildVariantFlags.ets"
ICON_MANIFEST_REL="resources/icon-sources/aira/image-assets.json"
BUILD_SCRIPT_REL="scripts/build-aira-browser.sh"
BASE_STRINGS_REL="AiraBrowser/entry/src/main/resources/base/element/string.json"
EN_STRINGS_REL="AiraBrowser/entry/src/main/resources/en_US/element/string.json"
ZH_CN_STRINGS_REL="AiraBrowser/entry/src/main/resources/zh_CN/element/string.json"
ZH_HANT_STRINGS_REL="AiraBrowser/entry/src/main/resources/zh_Hant/element/string.json"

for rel_path in "${REPOSITORY_REL}" "${COORDINATOR_REL}" "${CONTENT_REL}" "${SHEET_REL}" "${OVERLAY_REL}" \
  "${ICON_REL}" "${LAUREL_LEFT_REL}" "${LAUREL_RIGHT_REL}" \
  "${AVATAR_CLEAR_REL}" "${AVATAR_SPENDING_REL}" "${AVATAR_SIMPLE_REL}" \
  "${AVATAR_CYCLES_REL}" "${AVATAR_TIDY_REL}" \
  "${TRANSIENT_REL}" "${BOTTOM_PANEL_REL}" "${SHELL_BACK_REL}" "${MAIN_BACK_REL}" \
  "${TAB_HOME_REL}" "${SHELL_PAGE_REL}" "${RUNTIME_REL}" "${STORE_SERVICE_REL}" "${TEST_REL}" "${ADR_REL}" \
  "${SEED_SITES_REL}" "${BUNDLED_ICON_REL}" "${SHORTCUT_SURFACE_REL}" "${SEED_SLOT_ADR_REL}" \
  "${ICON_MANIFEST_REL}" "${BASE_STRINGS_REL}" "${EN_STRINGS_REL}" \
  "${ZH_CN_STRINGS_REL}" "${ZH_HANT_STRINGS_REL}"; do
  if [ ! -f "${REPO_ROOT}/${rel_path}" ]; then
    fail "missing ${rel_path}"
  fi
done

# The memory is per campaign and presentation-only. It must never model the app it
# points at, its install state, or anything the user could be gated on.
require_pattern "${REPOSITORY_REL}" "interface AppRecommendationRecord" \
  "the local record must be keyed by recommendation campaign."
require_pattern "${REPOSITORY_REL}" "id: string;" \
  "each record must carry its campaign identity."
require_pattern "${REPOSITORY_REL}" "shownAt" \
  "the local record must store that the campaign was shown."
require_pattern "${REPOSITORY_REL}" "dismissedAt" \
  "the local record must store that the user closed it."
require_pattern "${REPOSITORY_REL}" "hasCompleted\\(id: string\\)" \
  "the memory must answer per campaign instead of per install."
# The once rule is the whole point: no replay, always-show, or debug branch may appear in
# the memory, so a campaign cannot be brought back by anything but a new campaign id.
reject_pattern "${REPOSITORY_REL}" "REPLAY|ALWAYS_SHOW|FORCE_SHOW|DEBUG" \
  "the recommendation memory must not carry a replay or always-show branch."
reject_pattern "${REPOSITORY_REL}" "bundleName|storeUrl|versionCode|installedAt|launchCount|packageName" \
  "the recommendation memory must not model install or launch state."

# One owner decides which pending campaign may present, and when.
require_pattern "${COORDINATOR_REL}" "class AppRecommendationCoordinator" \
  "the recommendation must keep one eligibility and presentation owner."
require_pattern "${COORDINATOR_REL}" "'app_recommendation'" \
  "the coordinator must present through the fixed transient surface."
require_pattern "${COORDINATOR_REL}" "recommendationId" \
  "the snapshot must name the campaign it is showing."
require_pattern "${COORDINATOR_REL}" "resolveFacts\\(\\)\\.recommendationIds" \
  "the catalog order must come in as a shell fact, not as compiled-in copy."
require_pattern "${COORDINATOR_REL}" "hasCompleted\\(recommendationId\\)" \
  "the coordinator must skip only the campaigns this device already spent."
require_pattern "${COORDINATOR_REL}" "facts\\.homeVisible" \
  "the recommendation belongs to the homepage and must not present over a Web page."
require_pattern "${COORDINATOR_REL}" "facts\\.shellFamily !== 'phone'" \
  "the recommendation is a phone announcement and must not present on the large-screen shell."
require_pattern "${COORDINATOR_REL}" "facts\\.privacyMode === 'private'" \
  "a Private Browsing Session must not be interrupted by the recommendation."
require_pattern "${COORDINATOR_REL}" "handleHomeSurfaceVisible\\(\\)" \
  "a homepage arrival is what opens the next opportunity."
require_pattern "${COORDINATOR_REL}" "handleSurfaceRevealed\\(\\)" \
  "the campaign must be spent only once the card actually reveals."
require_pattern "${COORDINATOR_REL}" "markShown\\(recommendationId" \
  "the reveal must spend the campaign the card is actually showing."
require_pattern "${COORDINATOR_REL}" "markDismissed\\(recommendationId" \
  "the close must spend the campaign the card is actually showing."
require_pattern "${COORDINATOR_REL}" "'open_market'" \
  "the card's store action must be an explicit owner action."
require_pattern "${COORDINATOR_REL}" "openStore\\(recommendationId\\)" \
  "opening the store page must go through the shell seam, keyed by campaign."
require_pattern "${COORDINATOR_REL}" "isReleaseNoticeBlocked\\(facts\\.promptBlockingFacts\\)" \
  "the recommendation must yield the lane to prompts that already hold it."
require_pattern "${COORDINATOR_REL}" "presentationGeneration === this\\.presentationGeneration && this\\.snapshot\\.visible" \
  "the reveal guard must require the published visible snapshot, not reject it."
require_pattern "${COORDINATOR_REL}" "scheduleEvaluation\\(\\)" \
  "the recommendation must re-decide presentation instead of deciding once."
# One arrival offers one card, so two pending campaigns can never land back to back.
require_pattern "${COORDINATOR_REL}" "private armed: boolean = false;" \
  "the coordinator must remember that one arrival offers at most one campaign."
require_pattern "${COORDINATOR_REL}" "if \\(!this\\.armed\\)" \
  "an evaluation without an arrival must not present anything."

# A new app is a catalog change plus a new campaign id, and nothing else.
require_pattern "${CONTENT_REL}" "export function appRecommendationCatalog" \
  "the catalog must be the single place a recommendation is declared."
require_pattern "${CONTENT_REL}" "export function appRecommendationIds" \
  "the catalog must expose its campaign ids in order."
require_pattern "${CONTENT_REL}" "export function appRecommendationEntryFor" \
  "the catalog must resolve one campaign for the card."
require_pattern "${CONTENT_REL}" "id: 'shengxi'" \
  "the catalog must carry the campaign identity the memory keys on."
require_pattern "${CONTENT_REL}" "storeId: 'com.noctide.sleep'" \
  "the catalog must carry the store page the action hands over."
require_pattern "${SHEET_REL}" "appRecommendationEntryFor" \
  "the card must render the campaign the owner decided to show."
require_pattern "${SHEET_REL}" "AppRecommendationEntry" \
  "the card must render catalog content rather than compiled-in copy."
# The card owns no content of its own: its strings live in the catalog and the
# resource files, so a new recommendation never edits the card.
reject_pattern "${SHEET_REL}" "app_recommendation_review_author|app_recommendation_faq_content_title|app_recommendation_tagline" \
  "the card must not own recommendation copy; that belongs to the catalog."

# The homepage is the only entry point, and it re-evaluates on every arrival.
require_pattern "${TAB_HOME_REL}" "resolveAppRecommendationCoordinator\\(\\)\\.handleHomeSurfaceVisible\\(\\)" \
  "arriving at the homepage must arm the pending recommendation."
require_pattern "${SHELL_PAGE_REL}" "recommendationIds: appRecommendationIds\\(\\)" \
  "the shell must project the catalog order into the recommendation facts."
require_pattern "${SHELL_PAGE_REL}" "homeVisible: this\\.showHomePage" \
  "the shell must project the homepage state into the recommendation facts."
require_pattern "${SHELL_PAGE_REL}" "recommendationId: this\\.appRecommendationSnapshot\\.recommendationId" \
  "the shell must hand the decided campaign to the card."
require_pattern "${SHELL_PAGE_REL}" "appRecommendationCoordinator\\.handleHomeSurfaceVisible\\(\\)" \
  "a returning shell must report a new homepage arrival for a cold start."
require_pattern "${SHELL_PAGE_REL}" "appRecommendationCoordinator\\.handleSurfaceRevealed\\(\\)" \
  "the shell must report the reveal back to the one-time owner."
require_pattern "${SHELL_PAGE_REL}" "appRecommendationCoordinator\\.handleShellReset\\(\\)" \
  "a route reset must take an in-flight card down."
require_pattern "${SHELL_PAGE_REL}" "openAppGalleryDetailPageForApp" \
  "the shell must open the recommended app's store page through the store service."
require_pattern "${STORE_SERVICE_REL}" "openAppGalleryDetailPageForApp" \
  "the store service must own the AppGallery detail deep link and its fallback."
require_pattern "${RUNTIME_REL}" "sharedAppRecommendationRepository\\.initialize\\(\\)" \
  "the recommendation memory must be initialized with the other runtime stores."

# The surface takes part in the shared transient-surface lifecycle.
require_pattern "${TRANSIENT_REL}" "'app_recommendation'" \
  "the transient surface owner must know the recommendation id."
require_pattern "${BOTTOM_PANEL_REL}" "'app_recommendation'" \
  "the root bottom panel owner must know the recommendation id."
require_pattern "${SHELL_BACK_REL}" "dismiss_app_recommendation" \
  "system Back must close the card."
require_pattern "${MAIN_BACK_REL}" "dismiss_app_recommendation" \
  "system Back must be handled by the main back coordinator."

# The card draws the declared campaign.
require_pattern "${CONTENT_REL}" "app_recommendation_shengxi" \
  "the catalog must carry the recommended app icon."
require_pattern "${CONTENT_REL}" "app_recommendation_laurel_left|app_recommendation_badge_sleep" \
  "the catalog must carry the two-laurel product phrase copy."
require_pattern "${CONTENT_REL}" "app_recommendation_review_avatar_clear" \
  "the catalog must carry the sample review band."
require_pattern "${CONTENT_REL}" "app_recommendation_faq_content_title" \
  "the catalog must carry the centred questions."
require_pattern "${SHEET_REL}" "app_recommendation_laurel_left" \
  "the card must draw the two-laurel product phrase."
require_pattern "${SHEET_REL}" "app_recommendation_laurel_right" \
  "the card must keep the two-laurel product phrase."
require_pattern "${SHEET_REL}" "createAnimator" \
  "the review band must scroll at a constant speed."
require_pattern "${SHEET_REL}" "app_recommendation_open_market" \
  "the card must offer the store action under the body."
require_pattern "${SHEET_REL}" "footerVisible" \
  "the store action must be the immersive sheet footer, not a floating custom control."
require_pattern "${OVERLAY_REL}" "recommendationId" \
  "the overlay must pass the decided campaign to the card."
require_pattern "${OVERLAY_REL}" "'open_market'" \
  "the overlay must report the store action to the owner."
require_pattern "${OVERLAY_REL}" "dismissOnOutsideTap: false" \
  "a stray tap on the scrim must not spend a one-time campaign."
# The shell owns no copy: every visible string is a localized resource.
reject_pattern "${SHELL_PAGE_REL}" "应用推荐|不再提醒|常见问题|声栖" \
  "the shell must not own the recommendation copy."
reject_pattern "${COORDINATOR_REL}" "应用推荐|声栖|常见问题" \
  "the coordinator must not own the recommendation copy."

# Every locale carries the same recommendation strings.
for strings_rel in "${BASE_STRINGS_REL}" "${EN_STRINGS_REL}" "${ZH_CN_STRINGS_REL}" "${ZH_HANT_STRINGS_REL}"; do
  require_pattern "${strings_rel}" "app_recommendation_title" \
    "${strings_rel} must carry the recommendation title."
  require_pattern "${strings_rel}" "app_recommendation_app_name" \
    "${strings_rel} must carry the recommended app name."
  require_pattern "${strings_rel}" "app_recommendation_reviews_title" \
    "${strings_rel} must carry the sample review heading."
  require_pattern "${strings_rel}" "app_recommendation_faq_title" \
    "${strings_rel} must carry the questions heading."
  require_pattern "${strings_rel}" "app_recommendation_close" \
    "${strings_rel} must carry the close label."
  require_pattern "${strings_rel}" "app_recommendation_open_market" \
    "${strings_rel} must carry the store action label."
done

# The same app is also offered as a default homepage shortcut, and that slot keeps the
# id of the shortcut it replaced: an install that already seeded that id keeps its own
# shortcut, so only a fresh install shows the recommendation. Renaming the id would
# re-seed the slot as a brand-new shortcut on every device.
require_pattern "${SEED_SITES_REL}" "idSuffix: 'zhihu'" \
  "the recommended app must take over the existing shortcut slot instead of adding one."
require_pattern "${SEED_SITES_REL}" "title: '声栖'" \
  "the shortcut slot must be titled with the recommended app."
require_pattern "${SEED_SITES_REL}" "https://appgallery.huawei.com/app/detail\\?id=com\\.noctide\\.sleep" \
  "the shortcut slot must open the recommended app's store page."
# A shortcut draws its page's favicon, and a store page's favicon is the store's, so the
# recommended app's tile ships its icon with the app instead.
require_pattern "${BUNDLED_ICON_REL}" "hasBundledShortcutIcon" \
  "a bundled shortcut icon must be an explicit rule, not a special case in the tile."
require_pattern "${BUNDLED_ICON_REL}" "com\\.noctide\\.sleep" \
  "the bundled icon rule must be scoped to the recommended app's store page."
require_pattern "${BUNDLED_ICON_REL}" "app_recommendation_shengxi" \
  "the bundled icon rule must carry the recommended app's icon."
require_pattern "${SHORTCUT_SURFACE_REL}" "hasBundledShortcutIcon\\(shortcut\\.url\\)" \
  "the shortcut tile must draw the bundled icon for that store page."
require_pattern "${SHORTCUT_SURFACE_REL}" "resolveBundledShortcutIcon\\(shortcut\\.url\\)" \
  "the shortcut tile must draw the bundled icon for that store page."
require_pattern "${SEED_SLOT_ADR_REL}" "shortcut-seed-zhihu" \
  "the shortcut slot decision must record the id it keeps."

# The laurel artwork is decorative, so it must be classified rather than treated
# as a colorable Operational Icon.
require_pattern "${ICON_MANIFEST_REL}" "app-recommendation-laurel-artwork" \
  "the packaged laurel SVG resources must be classified in the icon manifest."

if [ "${failures}" -gt 0 ]; then
  exit 1
fi
printf 'App recommendation contract passed: one campaign per telling, phone homepage only, four locales.\n'
