#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SOURCE_ROOT="${REPO_ROOT}/AiraBrowser/entry/src/main/ets"

SHELL_PAGE="${SOURCE_ROOT}/app/pages/BrowserShellPage.ets"
FIXED_SLOTS="${SOURCE_ROOT}/app/components/browser/BrowserHostedWebSurfaceSlots.ets"
WEB_VIEWPORT_SURFACE_HOST="${SOURCE_ROOT}/app/components/browser/BrowserWebViewportSurfaceHost.ets"
WEB_HOST_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserWebHostCoordinator.ets"
RUNTIME_LIFECYCLE_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserRuntimeLifecycleCoordinator.ets"
WEB_EVENT_HOST_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserWebEventHostCoordinator.ets"
WEB_TABS="${SOURCE_ROOT}/core/browser/BrowserWebTabsController.ets"
WEB_PAGE_LIFECYCLE="${SOURCE_ROOT}/core/browser/BrowserWebPageLifecycleApplicationCoordinator.ets"
UA_ACTION_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserUserAgentActionCoordinator.ets"
UA_IDENTITY_POLICY_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserBrowsingIdentityPolicyCoordinator.ets"
UA_RUNTIME_POLICY_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserUserAgentRuntimePolicyCoordinator.ets"
UA_RUNTIME_TRANSITION_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserUserAgentRuntimeTransitionCoordinator.ets"
ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR="${SOURCE_ROOT}/services/web/BrowserActiveTabRuntimeRestoreCoordinator.ets"
WEB_COMPONENT_CONTROLLER="${SOURCE_ROOT}/core/web/BrowserWebComponentController.ets"
WEB_PAGE_CONTROLLER="${SOURCE_ROOT}/core/web/BrowserWebPageController.ets"
WINDOW_OPEN_APP="${SOURCE_ROOT}/core/browser/BrowserWindowOpenApplicationCoordinator.ets"
APP_URL_OPEN="${SOURCE_ROOT}/core/browser/BrowserAppUrlOpenCoordinator.ets"
MAIN_BACK="${SOURCE_ROOT}/core/browser/BrowserMainBackCoordinator.ets"
TAB_CLOSE="${SOURCE_ROOT}/core/browser/BrowserTabCloseCoordinator.ets"
TAB_MANAGER="${SOURCE_ROOT}/core/tabs/TabManager.ets"
WEB_LINK_CONTEXT_MENU="${SOURCE_ROOT}/core/web/WebLinkContextMenuCoordinator.ets"
ROOT_BOTTOM_ACTION="${SOURCE_ROOT}/core/browser/BrowserRootBottomPanelActionApplication.ets"
LARGE_SCREEN_PRESENTATION="${SOURCE_ROOT}/core/browser/BrowserLargeScreenPresentationViewModel.ets"
LARGE_SCREEN_INTENT="${SOURCE_ROOT}/core/browser/BrowserLargeScreenShellIntentApplication.ets"
BROWSER_MODELS="${SOURCE_ROOT}/common/models/BrowserModels.ets"
ATTACHMENT_COORDINATOR="${SOURCE_ROOT}/services/web/BrowserControllerAttachmentRuntimeCoordinator.ets"
HOSTED_RUNTIME_SURFACE_PORT="${SOURCE_ROOT}/services/web/BrowserHostedRuntimeSurfacePort.ets"
HOSTED_WEB_NODE="${SOURCE_ROOT}/core/web/HostedWebNode.ets"
BFCACHE_COORDINATOR="${SOURCE_ROOT}/core/web/WebBackForwardCacheCoordinator.ets"
DOCUMENT_START_SCRIPT_COORDINATOR="${SOURCE_ROOT}/core/web/BrowserHostedWebDocumentStartScriptCoordinator.ets"
WEB_BOOTSTRAPPER="${SOURCE_ROOT}/core/web/WebControllerBootstrapper.ets"
UA_RUNTIME_SERVICE="${SOURCE_ROOT}/services/web/BrowserUserAgentRuntimeService.ets"
UA_IDENTITY_DECISION_SERVICE="${SOURCE_ROOT}/services/web/BrowserBrowsingIdentityDecisionService.ets"
WEB_LOAD_RUNTIME="${SOURCE_ROOT}/services/web/BrowserWebLoadRuntimeCoordinator.ets"
HTTPS_FIRST_NAVIGATION_SERVICE="${SOURCE_ROOT}/services/web/BrowserHttpsFirstNavigationService.ets"
RUNTIME_LIFECYCLE_PORT="${SOURCE_ROOT}/services/web/BrowserRuntimeLifecyclePort.ets"
UA_POLICY_SERVICE="${SOURCE_ROOT}/services/web/BrowserUserAgentService.ets"
UA_HOST_POLICY_SERVICE="${SOURCE_ROOT}/services/web/BrowserUserAgentHostPolicyService.ets"
UA_HOST_POLICY_CATALOG="${SOURCE_ROOT}/services/web/BrowserUserAgentHostPolicyCatalog.ets"
UA_GOOGLE_SEARCH_HOSTS="${SOURCE_ROOT}/services/web/GeneratedGoogleSearchCompatibilityHosts.ets"
UA_HOST_POLICY_REMOTE_CATALOG="${SOURCE_ROOT}/services/web/BrowserUserAgentHostPolicyRemoteCatalog.ets"
UA_HOST_POLICY_CACHE_REPOSITORY="${SOURCE_ROOT}/data/browser/BrowserUserAgentHostPolicyManifestCacheRepository.ets"
UA_ACTION_COORDINATOR="${SOURCE_ROOT}/core/browser/BrowserUserAgentActionCoordinator.ets"
SITE_CUSTOMIZATION_COORDINATOR="${SOURCE_ROOT}/core/sitecustomization/SiteCustomizationManagementCoordinator.ets"
ENTRY_ABILITY="${SOURCE_ROOT}/app/abilities/EntryAbility.ets"
APP_RUNTIME="${SOURCE_ROOT}/app/bootstrap/BrowserAppRuntime.ets"
BACKGROUND_MANAGER="${SOURCE_ROOT}/core/browser/BrowserTabBackgroundManagerCoordinator.ets"
MEDIA_TAKEOVER_COORDINATOR="${SOURCE_ROOT}/core/browser/media/BrowserArkWebMediaTakeoverCoordinator.ets"
ADBLOCK_DOCUMENT_START="${SOURCE_ROOT}/core/adblock/AdBlockDocumentStartCoordinator.ets"
ADBLOCK_RUST_CORE="${REPO_ROOT}/AiraBrowser/entry/src/main/cpp/rust/aira_adblock_core/src/lib.rs"
RETIRED_ADBLOCK_SCRIPTLET_RUNTIME="${SOURCE_ROOT}/services/adblock/AdBlockScriptletRuntimeScriptService.ets"

failures=0

report_failure() {
  failures=$((failures + 1))
  printf 'Window-open contract guard failed: %s\n' "$1" >&2
}

require_file() {
  local file_path="$1"
  if [ ! -f "${file_path}" ]; then
    report_failure "required file is missing: ${file_path#${REPO_ROOT}/}"
  fi
}

forbid_file() {
  local file_path="$1"
  local message="$2"
  if [ -e "${file_path}" ]; then
    report_failure "${file_path#${REPO_ROOT}/} ${message}"
  fi
}

require_literal() {
  local file_path="$1"
  local literal="$2"
  local message="$3"
  if ! grep -Fq -- "${literal}" "${file_path}"; then
    report_failure "${file_path#${REPO_ROOT}/} ${message}"
  fi
}

require_literal_count() {
  local file_path="$1"
  local literal="$2"
  local expected_count="$3"
  local message="$4"
  local actual_count
  actual_count="$(grep -Fc -- "${literal}" "${file_path}" || true)"
  if [ "${actual_count}" -ne "${expected_count}" ]; then
    report_failure "${file_path#${REPO_ROOT}/} ${message} (expected ${expected_count}, found ${actual_count})"
  fi
}

forbid_regex() {
  local file_path="$1"
  local pattern="$2"
  local message="$3"
  if grep -Eq -- "${pattern}" "${file_path}"; then
    report_failure "${file_path#${REPO_ROOT}/} ${message}"
  fi
}

require_order() {
  local file_path="$1"
  local first_literal="$2"
  local second_literal="$3"
  local message="$4"
  local first_line
  local second_line
  first_line="$(awk -v text="${first_literal}" 'index($0, text) { print NR; exit }' "${file_path}")"
  second_line="$(awk -v text="${second_literal}" 'index($0, text) { print NR; exit }' "${file_path}")"
  if [ -z "${first_line}" ] || [ -z "${second_line}" ] || [ "${first_line}" -ge "${second_line}" ]; then
    report_failure "${file_path#${REPO_ROOT}/} ${message}"
  fi
}

require_order_after() {
  local file_path="$1"
  local anchor_literal="$2"
  local first_literal="$3"
  local second_literal="$4"
  local message="$5"
  if ! awk -v anchor="${anchor_literal}" -v first="${first_literal}" -v second="${second_literal}" '
    !anchored && index($0, anchor) { anchored = 1; next }
    anchored && !first_seen && index($0, first) { first_seen = 1; next }
    anchored && first_seen && index($0, second) { found = 1; exit }
    END { exit(found ? 0 : 1) }
  ' "${file_path}"; then
    report_failure "${file_path#${REPO_ROOT}/} ${message}"
  fi
}

require_no_literal_between_after() {
  local file_path="$1"
  local anchor_literal="$2"
  local first_literal="$3"
  local second_literal="$4"
  local forbidden_literal="$5"
  local message="$6"
  if ! awk -v anchor="${anchor_literal}" -v first="${first_literal}" -v second="${second_literal}" \
    -v forbidden="${forbidden_literal}" '
    !anchored && index($0, anchor) { anchored = 1; next }
    anchored && !between && index($0, first) { between = 1; next }
    between && index($0, second) { completed = 1; exit }
    between && index($0, forbidden) { forbidden_found = 1; exit }
    END { exit(completed && !forbidden_found ? 0 : 1) }
  ' "${file_path}"; then
    report_failure "${file_path#${REPO_ROOT}/} ${message}"
  fi
}

for file_path in \
  "${SHELL_PAGE}" \
  "${FIXED_SLOTS}" \
  "${WEB_VIEWPORT_SURFACE_HOST}" \
  "${WEB_HOST_COORDINATOR}" \
  "${RUNTIME_LIFECYCLE_COORDINATOR}" \
  "${WEB_TABS}" \
  "${WINDOW_OPEN_APP}" \
  "${APP_URL_OPEN}" \
  "${MAIN_BACK}" \
  "${TAB_CLOSE}" \
  "${TAB_MANAGER}" \
  "${WEB_LINK_CONTEXT_MENU}" \
  "${ROOT_BOTTOM_ACTION}" \
  "${LARGE_SCREEN_PRESENTATION}" \
  "${LARGE_SCREEN_INTENT}" \
  "${BROWSER_MODELS}" \
  "${ATTACHMENT_COORDINATOR}" \
  "${HOSTED_RUNTIME_SURFACE_PORT}" \
  "${HOSTED_WEB_NODE}" \
  "${BFCACHE_COORDINATOR}" \
  "${DOCUMENT_START_SCRIPT_COORDINATOR}" \
  "${WEB_BOOTSTRAPPER}" \
  "${UA_IDENTITY_DECISION_SERVICE}" \
  "${UA_IDENTITY_POLICY_COORDINATOR}" \
  "${UA_RUNTIME_POLICY_COORDINATOR}" \
  "${UA_RUNTIME_SERVICE}" \
  "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  "${HTTPS_FIRST_NAVIGATION_SERVICE}" \
  "${UA_POLICY_SERVICE}" \
  "${UA_HOST_POLICY_SERVICE}" \
  "${UA_HOST_POLICY_CATALOG}" \
  "${ENTRY_ABILITY}" \
  "${APP_RUNTIME}" \
  "${BACKGROUND_MANAGER}" \
  "${MEDIA_TAKEOVER_COORDINATOR}" \
  "${ADBLOCK_DOCUMENT_START}" \
  "${ADBLOCK_RUST_CORE}"; do
  require_file "${file_path}"
done

require_order "${HOSTED_WEB_NODE}" \
  'config.callbacks.onBeforeWebBuild?.(config.tabId);' \
  'const hostedController = new HostedWebNodeController(config.tabId, undefined);' \
  'must consume a pending popup event before constructing/binding the Hosted Web node.'
require_literal "${WEB_TABS}" \
  'private readonly windowOpenApplicationCoordinator: BrowserWindowOpenApplicationCoordinator;' \
  'must own the fixed window-open dependency directly instead of receiving page-built callbacks.'
require_literal "${WEB_TABS}" \
  'private preBuildWindowNewEventConsumptionByTabId:' \
  'must retain the pre-build event-consumption result until controller attachment.'
require_literal "${WEB_TABS}" \
  'onBeforeWebBuild(tabId: string): void {' \
  'must expose the pre-build handoff entry point.'
require_literal "${WEB_TABS}" \
  'this.windowOpenApplicationCoordinator.hasStoredEventForPageController(tabId)' \
  'must check the real window-open event owner before pre-build consumption.'
require_literal "${WEB_TABS}" \
  "'before_hosted_web_build'" \
  'must preserve the Huawei-order pre-build event-consumption reason.'
require_literal "${WEB_TABS}" \
  'return preBuildConsumption?.eventFound === true ? preBuildConsumption : attachedConsumption;' \
  'must carry the pre-build result into the normal controller-attachment path.'
forbid_regex "${ATTACHMENT_COORDINATOR}" \
  'BrowserWindowOpenApplicationCoordinator|before_hosted_web_build|pendingPreBuildWindowOpenConsumptionByTabId' \
  'must not become a second window-open narrative owner.'
require_literal "${RUNTIME_LIFECYCLE_COORDINATOR}" \
  'host.activateAttachedController(tabId, resolution.targetUrl, resolution.runtime);' \
  'must carry the already-resolved restore target into attached Controller identity binding.'
require_literal "${ATTACHMENT_COORDINATOR}" \
  'this.host.applyUserAgent(controller, targetUrl);' \
  'must apply attached Controller identity from the lifecycle-owned restore target.'
forbid_regex "${ATTACHMENT_COORDINATOR}" \
  'resolveUserAgentPageUrl' \
  'must not re-resolve a restore URL after the lifecycle owner has selected the target.'
forbid_regex "${SHELL_PAGE}" \
  'resolveUserAgentPageUrl' \
  'must keep restore-target identity policy out of BrowserShellPage.'
require_literal "${SHELL_PAGE}" \
  'this.browserWebTabsController.onBeforeWebBuild(tabId);' \
  'must keep the ArkWeb pre-build callback as one-line owner forwarding.'

require_literal "${FIXED_SLOTS}" \
  '.visibility(this.isActiveSlotVisible(tab.id) ? Visibility.Visible : Visibility.Hidden)' \
  'must keep normal live tabs in stable fixed slots and switch only visibility.'
require_literal "${SHELL_PAGE}" \
  'activeSurfaceVisible: this.activeHostedWebNodeTabId === this.activeTabId &&' \
  'must hide a retained previous Hosted tab before the Shell reveals a newly active foreground tab.'
require_literal "${FIXED_SLOTS}" \
  'if (this.shouldMountFixedSlot(tab, this.surfaceRevision)) {' \
  'must re-evaluate a cold-restored fixed slot when its owner-managed controller becomes ready.'
require_literal "${FIXED_SLOTS}" \
  '}, (tab: BrowserTabState) => `${tab.id}:${this.resolveControllerGeneration(tab.id)}`)' \
  'must keep the fixed Hosted Web slot identity stable by tab id when its Hosted node generation is unchanged.'
require_literal "${FIXED_SLOTS}" \
  '}, (tab: BrowserTabState) => `${tab.id}:${this.resolveControllerGeneration(tab.id)}`)' \
  'must replace only the affected fixed slot when its Hosted node generation changes.'
require_literal "${WEB_HOST_COORDINATOR}" \
  'getHostedNodeGeneration(tabId: string): number {' \
  'must expose the existing per-tab Hosted node generation without creating a second owner.'
require_literal "${HOSTED_RUNTIME_SURFACE_PORT}" \
  'return this.webHostCoordinator.getHostedNodeGeneration(tabId);' \
  'must forward Hosted node generation from its lifecycle owner to the ArkUI surface adapter.'
require_literal "${SHELL_PAGE}" \
  'this.browserHostedRuntimeSurfacePort.getHostedNodeGeneration(tabId)' \
  'must keep BrowserShellPage limited to generation wiring for the fixed Hosted surface.'
require_literal "${FIXED_SLOTS}" \
  "slot.kind === 'desktop-web-entry-parked'" \
  'must restrict parking slots to the desktop Web-entry exception.'
forbid_regex "${FIXED_SLOTS}" \
  'window[_-]?open|popup|oauth' \
  'must never host ordinary popup/OAuth children in a parking surface.'
require_literal "${WEB_HOST_COORDINATOR}" \
  'if (documentStartScriptsChanged && !existingController.isWebControllerAttached()) {' \
  'must preserve an ArkWeb-attached fixed-slot controller when document-start config changes.'
require_order "${WEB_HOST_COORDINATOR}" \
  'if (documentStartScriptsChanged && !existingController.isWebControllerAttached()) {' \
  'existingController.update(config);' \
  'must update live Hosted config without disposing the attached NWeb.'

require_literal "${UA_RUNTIME_SERVICE}" \
  "const requestsNativeIdentity = resolution.profile.uaStringMode === 'system_untouched';" \
  'must model untouched system identity explicitly instead of comparing a copied UA string.'
require_order "${UA_RUNTIME_SERVICE}" \
  "if (requestsNativeIdentity) {" \
  'this.platformAdapter.applyCustomUserAgent(controller, targetUserAgent);' \
  'must return a fresh Controller from the system-default path before any custom-UA setter.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'controller.setCustomUserAgent(userAgent);' \
  'production ArkWeb adapter must remain the final custom-UA setter.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'const binding = this.controllerBindings.get(controller);' \
  'must distinguish fresh Controllers from Controllers previously customized by Aira.'
require_literal "${UA_RUNTIME_SERVICE}" \
  "return 'identity_transition_required';" \
  'must surface unsupported in-place identity transitions without writing the default string.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'prepareWebMainFrameNavigation(' \
  'must freeze browsing identity before an allowed Web-initiated main-frame navigation.'
require_literal "${WEB_COMPONENT_CONTROLLER}" \
  'private restoringWebState: boolean = false;' \
  'must track the synchronous ArkWeb snapshot-restore callback boundary.'
require_order "${WEB_COMPONENT_CONTROLLER}" \
  'this.restoringWebState = true;' \
  'controller.restoreWebState(payload);' \
  'must enter the restore guard before ArkWeb can synchronously emit navigation callbacks.'
require_order "${WEB_COMPONENT_CONTROLLER}" \
  'controller.restoreWebState(payload);' \
  'this.restoringWebState = false;' \
  'must clear the restore guard after ArkWeb returns or throws.'
require_literal "${WEB_COMPONENT_CONTROLLER}" \
  'if (!this.restoringWebState &&' \
  'must not re-prepare or mutate Controller identity from a restore-time navigation callback.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'prepareHistoryNavigation(' \
  'must recover a navigation-entry identity plan before native Back/Forward.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'commitNavigation(' \
  'must associate the committed identity plan with the native history entry.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'const resolution = binding?.resolution ?? activePlan?.resolution;' \
  'must commit the Controller identity that actually applied, never transition intent.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'this.activeNavigationPlanByTabId[tabId] = undefined;' \
  'must expose an owner-owned cancellation terminal for abandoned navigation plans.'
forbid_regex "${UA_RUNTIME_SERVICE}" \
  'controllerByTabId' \
  'must not retain disposed WebviewControllers through a strong per-tab map.'
forbid_regex "${WEB_BOOTSTRAPPER}" \
  'setCustomUserAgent|getUserAgent|getCustomUserAgent' \
  'must leave browsing-identity execution to BrowserUserAgentRuntimeService.'
ua_setter_files="$(grep -RIlF --include='*.ets' 'setCustomUserAgent(' "${SOURCE_ROOT}" | sort || true)"
if [ "${ua_setter_files}" != "${UA_RUNTIME_SERVICE}" ]; then
  report_failure "BrowserUserAgentRuntimeService must be the sole ArkTS setCustomUserAgent owner; found: ${ua_setter_files:-<none>}"
fi
require_order "${WEB_COMPONENT_CONTROLLER}" \
  'host.prepareMainFrameWebNavigation(this.tabId, targetUrl, request.isRequestGesture)' \
  'host.observeMainFrameWebRequest(this.tabId, targetUrl);' \
  'must prepare a frozen identity before allowing a Web main-frame request.'
require_literal "${WEB_LOAD_RUNTIME}" \
  'resolveUserAgentRuntimeService().prepareWebMainFrameNavigation(' \
  'must forward Web main-frame preparation to the sole identity owner.'
require_literal "${HTTPS_FIRST_NAVIGATION_SERVICE}" \
  'this.isKnownHttpPresentationHostAlias(target.host, grant.anchorHost)' \
  'must let a confirmed tab-local HTTP grant follow a known mobile presentation-host alias redirect.'
require_literal "${HTTPS_FIRST_NAVIGATION_SERVICE}" \
  "const HTTP_PRESENTATION_HOST_ALIASES: string[] = ['m', 'mobile', 'wap', 'www'];" \
  'must keep sibling-host fallback limited to the explicit presentation-host alias set.'
require_literal "${HTTPS_FIRST_NAVIGATION_SERVICE}" \
  'return normalizedHost.substring(separatorIndex + 1);' \
  'must compare presentation aliases by their unchanged base host.'
require_order "${WEB_PAGE_CONTROLLER}" \
  'host.prepareHistoryNavigation(' \
  'direction === '\''back'\'' ? this.componentController.backward(host) : this.componentController.forward(host);' \
  'must prepare the target history-entry identity before native Back/Forward.'
require_literal "${WEB_LOAD_RUNTIME}" \
  'resolveUserAgentRuntimeService().prepareHistoryNavigation(' \
  'must forward native history preparation to the sole identity owner.'
require_literal "${WEB_PAGE_CONTROLLER}" \
  'host.cancelPreparedNavigation(this.tabId);' \
  'must cancel a prepared history identity when the native command is not issued.'
ua_navigation_cancel_terminal_count="$(grep -Fc -- 'host.cancelPreparedNavigation(this.tabId);' "${WEB_PAGE_CONTROLLER}" || true)"
if [ "${ua_navigation_cancel_terminal_count}" -lt 4 ]; then
  report_failure "BrowserWebPageController must cancel prepared identity plans on history failure and explicit load stop."
fi
require_literal "${WEB_PAGE_LIFECYCLE}" \
  'webLoadRuntimeCoordinator.commitUserAgentNavigation(' \
  'must commit raw main-frame history identity even when product event handling is filtered.'
require_literal "${WEB_PAGE_LIFECYCLE}" \
  'webLoadRuntimeCoordinator.cancelUserAgentNavigation(tabId);' \
  'must cancel the active identity plan when the main-frame navigation fails.'
require_literal "${UA_RUNTIME_POLICY_COORDINATOR}" \
  'userAgentRuntimeService.requiresControllerTransition(' \
  'must detect a custom-to-native transition before choosing the reload path.'
require_literal "${UA_RUNTIME_POLICY_COORDINATOR}" \
  'runtimeTransitionCoordinator.transitionToNative(' \
  'must route custom-to-native policy changes through the history-preserving runtime transition owner.'
require_order "${UA_RUNTIME_POLICY_COORDINATOR}" \
  'runtimeTransitionCoordinator.transitionToNative(' \
  '        reloadReason' \
  'must carry the policy-owned reload reason into the native Controller transition.'
require_order "${UA_ACTION_COORDINATOR}" \
  "result.status === 'transition_deferred'" \
  '为保留返回与前进历史' \
  'must use the delayed notice only after the immediate runtime transition declines or is unavailable.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'isBrowserDataBoundarySessionEphemeralTabLike({' \
  'snapshotStore.saveSnapshot(tabId, serializedWebState)' \
  'must reject session-ephemeral disk snapshots before starting native-UA state migration.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'webTabsController.serializeWebState(tabId)' \
  'snapshotStore.saveSnapshot(tabId, serializedWebState)' \
  'must serialize the live Web access stack before persisting its transition snapshot.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  "runtimeState: 'restoring'" \
  "hostedRuntimeSurfacePort.release(tabId, 'user_agent_changed')" \
  'must commit a restorable tab state before releasing the customized Controller.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  "hostedRuntimeSurfacePort.release(tabId, 'user_agent_changed')" \
  'runtimeLifecyclePort.replaceControllerForRuntimeRefresh(tabId)' \
  'must dispose the customized Hosted runtime before installing a fresh Controller.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'runtimeLifecyclePort.replaceControllerForRuntimeRefresh(tabId)' \
  'host.applyActiveRuntimeController(restoringTab, runtime)' \
  'must attach the replacement through the ordinary Controller-attach restore path.'
require_literal "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'if (!this.isCurrent(transitionGeneration, tabId)) {' \
  'must cancel a stale snapshot completion before releasing the live Controller.'
require_literal "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'pendingSnapshotReloadMarkerByTabId[tabId] = {' \
  'must mark only a completed UA runtime replacement for its one-shot post-restore reload.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'const hasMatchingReloadMarker = this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] !== undefined;' \
  'if (hasMatchingReloadMarker) {' \
  'must preserve a committed post-snapshot reload marker from redundant matching profile reconciliation.'
require_literal "${UA_RUNTIME_POLICY_COORDINATOR}" \
  'runtimeTransitionCoordinator.cancelUncommittedTransition(facts.activeTabId);' \
  'must cancel only an uncommitted transition when a repeated profile reconciliation already matches the Controller identity.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'applyActiveRuntimeController(restoringTab, runtime)' \
  'this.pendingSnapshotReloadMarkerByTabId[tabId] = {' \
  'must mark the replacement only after the fresh Controller has been installed.'
forbid_regex "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'controller\.refresh\(' \
  'must not bypass the UA-aware browser navigation pipeline after snapshot restore.'
require_literal "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] = undefined;' \
  'must consume or clear the one-shot reload marker before handing off navigation.'
require_order "${UA_RUNTIME_TRANSITION_COORDINATOR}" \
  'this.pendingSnapshotReloadMarkerByTabId[normalizedTabId] = undefined;' \
  'return marker.reloadReason;' \
  'must consume the marker before returning its reload postcondition.'
require_literal "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  'consumeUserAgentTransitionSnapshotReloadReason(activeTab.id);' \
  'must consume the UA-transition reload postcondition only after snapshot restore.'
require_order "${ACTIVE_TAB_RUNTIME_RESTORE_COORDINATOR}" \
  'this.applySnapshotRestoreSuccess(' \
  'this.reloadActive(userAgentReloadReason);' \
  'must issue the first post-restore request through the UA-aware browser reload owner.'
require_literal "${RUNTIME_LIFECYCLE_PORT}" \
  'this.dependencies.hostedRuntimeReleaseSink?.releaseControllerBindings(result.releasedTabIds);' \
  'must release per-controller identity bindings through the typed owner sink when Hosted Web runtimes are disposed.'
require_literal "${RUNTIME_LIFECYCLE_PORT}" \
  "const pendingUrl = tab?.pendingUrl ?? '';" \
  'must normalize the required pending URL before choosing a Controller identity target.'
require_literal "${RUNTIME_LIFECYCLE_PORT}" \
  'const userAgentPageUrl = pendingUrl.trim().length > 0' \
  'must fall back when pendingUrl is empty instead of treating empty text as a resolved target.'
require_literal "${WEB_BOOTSTRAPPER}" \
  'controller.enableAdsBlock(false);' \
  'must disable ArkWeb ad filtering for every attached controller before Rust-owned page filtering begins.'
forbid_regex "${WEB_BOOTSTRAPPER}" \
  'enableAdsBlock\([^)]*true|AdsBlockManager|onAdsBlocked|adsBlockEnabled' \
  'must not restore a configurable or enabled ArkWeb ad-filter authority in controller bootstrap.'
unexpected_arkweb_adblock_owners="$(
  rg -l 'enableAdsBlock|AdsBlockManager|onAdsBlocked' "${SOURCE_ROOT}" 2>/dev/null |
    grep -Fvx -- "${WEB_BOOTSTRAPPER}" || true
)"
if [ -n "${unexpected_arkweb_adblock_owners}" ]; then
  report_failure "ArkWeb ad-filter authority escaped the common disabled bootstrap owner:\n${unexpected_arkweb_adblock_owners}"
fi
require_literal "${UA_POLICY_SERVICE}" \
  "export type BrowserUserAgentApplicationFamily = 'mobile' | 'tablet' | 'desktop';" \
  'must retain explicit UA-family vocabulary for policy and signed Host-rule compatibility.'
require_literal "${UA_POLICY_SERVICE}" \
  "const normalizedFormFactor = detectedFormFactor.trim().toLowerCase();" \
  'must retain physical-device UA family mapping for non-foldable device defaults.'
require_literal "${UA_POLICY_SERVICE}" \
  'resolveApplicationFamilyForShell(' \
  'must derive the foldable/manual presentation UA family from the active Shell profile.'
require_literal "${UA_POLICY_SERVICE}" \
  "if (applicationFamily !== 'mobile') {" \
  'must give physical tablet/desktop devices a concrete desktop default identity.'
require_literal "${UA_POLICY_SERVICE}" \
  'AIRA_DESKTOP_DEFAULT_BROWSER_IDENTITY_ID' \
  'must keep the automatic desktop default distinguishable from explicit user presets.'
require_literal "${UA_POLICY_SERVICE}" \
  'userAgent: systemDefaultUserAgent.trim(),' \
  'must keep the explicit ArkWeb-original native identity path available.'
require_literal "${UA_POLICY_SERVICE}" \
  'userAgent: AIRA_COMPAT_MOBILE_USER_AGENT,' \
  'must keep Aira Default distinct from ArkWeb Original by resolving it to the Android-compatible mobile identity.'
require_literal "${UA_HOST_POLICY_SERVICE}" \
  "private applicationFamily: BrowserUserAgentApplicationFamily = 'mobile';" \
  'must keep the application default-UA family in the application policy owner.'
require_literal "${UA_HOST_POLICY_SERVICE}" \
  'reconcileApplicationUserAgentForDevice(' \
  'must retain the physical-device application UA adapter for non-foldable defaults.'
require_literal "${UA_HOST_POLICY_SERVICE}" \
  'reconcileApplicationUserAgentForPresentation(' \
  'must reconcile the application UA family from the active Shell profile.'
require_literal "${UA_HOST_POLICY_SERVICE}" \
  'groups = this.compatibilityCatalog.resolve(this.applicationFamily);' \
  'must resolve complete host-UA profile groups through the compatibility catalog owner.'
require_order "${UA_HOST_POLICY_SERVICE}" \
  'const hostPolicyResult = this.applyHostCompatibilityPolicy();' \
  'const applicableDefaultUserAgent = this.userAgentService.resolveApplicationDefaultUserAgent(' \
  'must apply the complete Host-UA catalog before resolving the physical-device applicable default.'
require_order "${UA_HOST_POLICY_SERVICE}" \
  'if (policyKey === this.lastAppliedHostPolicyKey) {' \
  'webview.WebviewController.setUserAgentForHosts(group.userAgent, group.hosts);' \
  'must skip unchanged complete Host-UA policies before mutating ArkWeb.'
require_literal "${UA_HOST_POLICY_SERVICE}" \
  'identityId: `host_profile:${match.profileId}`' \
  'must normalize each mandatory Host profile to one stable Browsing Identity reference.'
forbid_regex "${UA_HOST_POLICY_SERVICE}" \
  'setAppCustomUserAgent' \
  'must not restore an app-wide custom UA while applying exact-host compatibility policy.'
require_order "${UA_IDENTITY_DECISION_SERVICE}" \
  'snapshot.mandatoryHost,' \
  'snapshot.currentTab,' \
  'must keep mandatory signed/bundled Host identity above the current-tab override.'
require_order "${UA_IDENTITY_DECISION_SERVICE}" \
  'snapshot.currentTab,' \
  'snapshot.exactOrigin,' \
  'must keep the current-tab override above the exact-Origin choice.'
require_order "${UA_IDENTITY_DECISION_SERVICE}" \
  'snapshot.exactOrigin,' \
  'snapshot.global,' \
  'must keep the exact-Origin choice above the explicit global choice.'
require_order "${UA_IDENTITY_DECISION_SERVICE}" \
  'snapshot.global,' \
  'snapshot.airaCompatibility,' \
  'must keep the explicit global choice above Aira compatibility.'
require_order "${UA_IDENTITY_DECISION_SERVICE}" \
  'snapshot.airaCompatibility,' \
  'snapshot.applicableDefault,' \
  'must keep Aira compatibility above the applicable default identity.'
forbid_regex "${UA_IDENTITY_DECISION_SERVICE}" \
  '@kit|Repository|saveSettings|loadUrl|\.refresh\(' \
  'must keep the Browsing Identity Decision pure and free of persistence, platform, and runtime execution.'
require_literal "${UA_IDENTITY_POLICY_COORDINATOR}" \
  'const siteEntry = request.privateBrowsing || target === undefined ? undefined :' \
  'must exclude regular Saved Site Settings before a private Policy Snapshot is assembled.'
require_literal "${UA_IDENTITY_POLICY_COORDINATOR}" \
  'const managedHostApplicationFamily = this.resolveManagedHostApplicationFamily(' \
  'must derive the managed Host profile shape before mandatory Host precedence is evaluated.'
require_literal "${UA_IDENTITY_POLICY_COORDINATOR}" \
  'const mandatoryCompatibility = this.hostPolicyAdapter.resolveMandatoryCompatibility(' \
  'must assemble mandatory Host identity through the injectable Host-policy boundary.'
require_literal "${UA_IDENTITY_POLICY_COORDINATOR}" \
  'return BrowserUserAgentHostPolicyService.resolveMandatoryCompatibilityForHost(' \
  'default Host-policy adapter must remain backed by the signed/bundled Catalog owner.'
require_literal_count "${UA_IDENTITY_POLICY_COORDINATOR}" \
  'this.decisionService.decide(this.buildSnapshot(request))' \
  1 \
  'must route every assembled Policy Snapshot exactly once through the pure Decision owner.'
forbid_regex "${UA_IDENTITY_POLICY_COORDINATOR}" \
  'fold|hinge|[Ss]hellFamily|largeScreen|viewport|orientation|pointerType|keyboardAttached|interfaceMode|windowWidth|windowHeight' \
  'must not let fold, Shell, viewport, orientation, pointer, or keyboard presentation facts select Browsing Identity.'
forbid_regex "${UA_ACTION_COORDINATOR}" \
  'resolveForRuntimeWithSystemDefault|resolveForRuntime\(' \
  'must keep runtime Browsing Identity policy assembly out of the UI Action owner.'
require_literal "${WEB_LOAD_RUNTIME}" \
  'resolveBrowsingIdentityPolicyCoordinator: () => BrowserBrowsingIdentityPolicyCoordinator;' \
  'must consume Browsing Identity through the Policy Snapshot owner interface.'
forbid_regex "${WEB_LOAD_RUNTIME}" \
  'resolveUserAgentActionCoordinator|BrowserWebLoadUserAgentApplication' \
  'must not route Web Load policy assembly through the UI Action owner.'
require_literal "${WEB_LOAD_RUNTIME}" \
  'this.dependencies.resolveBrowsingIdentityPolicyCoordinator().releaseTab(tabId);' \
  'must release the session-local current-tab override when the tab runtime is closed.'
require_order_after "${WEB_LOAD_RUNTIME}" \
  'applyUserAgentToControllerForTab(' \
  'runtimeService.isControllerIdentitySynchronized(tabId, controller)' \
  'const resolution = this.resolveUserAgentForContext(context, false);' \
  'must reuse a committed Controller binding before reading mutable policy during non-navigation runtime sync.'
require_literal "${UA_RUNTIME_SERVICE}" \
  'this.activeNavigationPlanByTabId[tabId] !== undefined' \
  'must distinguish an active navigation transaction from a stable committed Controller binding.'
require_order "${UA_RUNTIME_POLICY_COORDINATOR}" \
  'userAgentRuntimeService.hasEffectiveIdentityChange(' \
  'runtimeTransitionCoordinator.transitionToNative(' \
  'must skip reload or Controller replacement when a mandatory Host keeps the effective identity unchanged.'
require_literal "${UA_ACTION_COORDINATOR}" \
  '当前网站继续使用 Aira 兼容标识。' \
  'must explain a saved but superseded user choice without exposing a mutable mandatory-Host control.'
require_literal "${UA_HOST_POLICY_CATALOG}" \
  'GOOGLE_SEARCH_COMPATIBILITY_HOST_CHUNKS' \
  'must build the bundled Google compatibility policy from the generated exact-Host snapshot.'
require_literal "${UA_GOOGLE_SEARCH_HOSTS}" \
  "'google.com.hk'" \
  'must keep the reported Google Hong Kong apex Host in the generated exact-Host snapshot.'
require_literal "${UA_GOOGLE_SEARCH_HOSTS}" \
  "'www.google.com.hk'" \
  'must keep the reported Google Hong Kong www Host in the generated exact-Host snapshot.'
require_literal "${UA_HOST_POLICY_CATALOG}" \
  "hosts: ['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com', 'youtu.be']" \
  'must keep the authorized exact-host YouTube compatibility exceptions in the typed catalog.'
forbid_regex "${UA_HOST_POLICY_CATALOG}" \
  'httpbingo\.org' \
  'must not restore the retired temporary Host-UA test rule.'
forbid_regex "${UA_ACTION_COORDINATOR}" \
  "message: 'Google " \
  'must keep mandatory Google UA policy hidden from ordinary temporary identity controls.'
forbid_regex "${UA_ACTION_COORDINATOR}" \
  "message: 'YouTube " \
  'must keep mandatory YouTube UA policy hidden from ordinary temporary identity controls.'
forbid_regex "${SITE_CUSTOMIZATION_COORDINATOR}" \
  'BrowserUserAgentHostPolicyService|mandatoryCompatibility|Google|YouTube' \
  'must keep mandatory compatibility policy out of ordinary site-customization presentation and persistence.'
require_literal "${UA_HOST_POLICY_CATALOG}" \
  'Host UA assignment conflict:' \
  'must reject duplicate or conflicting host assignments instead of applying last-write-wins policy.'
forbid_regex "${UA_POLICY_SERVICE}" \
  'shouldForceCompatibilityReload|forcedCompatibilityHosts|forced_compatibility' \
  'must keep retired page-title compatibility promotion and its forced-host state deleted.'
retired_forced_compatibility_sources="$(
  rg -l 'shouldForceCompatibilityReload|forcedCompatibilityHosts|forced_compatibility|reloadForUnsupportedBrowserCompatibility' \
    "${SOURCE_ROOT}" 2>/dev/null || true
)"
if [ -n "${retired_forced_compatibility_sources}" ]; then
  report_failure "Retired title-based forced compatibility state escaped deletion:\n${retired_forced_compatibility_sources}"
fi
forbid_regex "${UA_POLICY_SERVICE}" \
  'bing\.com|microsoft\.com|msn\.com|cnn\.com|compatibility_rule' \
  'must keep unverified legacy compatibility hosts and controller-level built-in UA rules retired.'
forbid_regex "${WEB_BOOTSTRAPPER}" \
  'hostUserAgents|setUserAgentForHosts' \
  'must not model the static ArkWeb Host-UA policy as an unsupported Controller-instance adapter.'
require_literal "${ENTRY_ABILITY}" \
  'sharedBrowserUserAgentHostPolicyService.reconcileApplicationUserAgentForPresentation(' \
  'must feed the active Shell family into the application default-UA owner.'
require_literal "${ENTRY_ABILITY}" \
  'profile.shellFamily' \
  'must align the applicable default webpage identity with the active Shell family.'
require_literal "${ENTRY_ABILITY}" \
  "this.reconcileBrowserWindowPresentationProfile(boundWindow, 'window-fact-change', false);" \
  'must keep application identity reconciliation conditional on a real profile transition during ordinary fact changes.'
require_literal "${ENTRY_ABILITY}" \
  "this.reconcileBrowserWindowPresentationProfile(mainWindow, 'window-stage-create', true);" \
  'must initialize the application Browsing Identity family from physical device facts before first content.'
require_literal "${SHELL_PAGE}" \
  'browserUserAgentRuntimePolicyCoordinator.bindPresentationRefresh();' \
  'must bind the existing Browsing Identity runtime owner to active Shell profile refreshes.'
require_order "${ENTRY_ABILITY}" \
  'sharedBrowserUserAgentHostPolicyService.reconcileApplicationUserAgentForPresentation(' \
  'BrowserShellPresentationRefreshSignal.publish();' \
  'must publish the Shell refresh only after the active Shell UA family is observable to Web runtime policy.'
require_literal "${UA_HOST_POLICY_SERVICE}" \
  'sharedBrowserUserAgentHostPolicyCatalog.resolveMandatoryCompatibility(' \
  'must resolve mandatory runtime identity from the same Catalog snapshot applied to ArkWeb.'
forbid_file "${UA_HOST_POLICY_REMOTE_CATALOG}" \
  'must stay deleted because Host-UA policy is package-owned.'
forbid_file "${UA_HOST_POLICY_CACHE_REPOSITORY}" \
  'must stay deleted because package-owned Host-UA policy has no runtime manifest cache.'
require_literal "${UA_HOST_POLICY_CATALOG}" \
  'return this.copyRules(BUNDLED_HOST_COMPATIBILITY_RULES);' \
  'must resolve Host-UA compatibility from the complete package-owned catalog.'
forbid_regex "${UA_HOST_POLICY_CATALOG}" \
  'remoteRules|validateRemoteRules|replaceRemoteRules|clearRemoteRules' \
  'must not restore a remote overlay inside the package-owned Host-UA catalog.'
forbid_regex "${UA_HOST_POLICY_SERVICE}" \
  'RemoteCatalog|initializeRemotePolicy|refreshRemotePolicy|notifyForeground|notifyBackground' \
  'must not own a remote Host-UA policy lifecycle.'
forbid_regex "${APP_RUNTIME}" \
  'browser_user_agent_host_policy_cache|refreshRemotePolicyIfDue|runDeferredPolicyFanout' \
  'must not restore Host-UA cache or deferred remote policy refresh wiring.'
forbid_regex "${ENTRY_ABILITY}" \
  'runForegroundPolicyFanout|refreshRemotePolicyIfDue|sharedBrowserUserAgentHostPolicyService\.notify' \
  'must not restore foreground/background remote policy lifecycle wiring.'

require_literal "${BFCACHE_COORDINATOR}" \
  'private configuredRuntimeByTabId: Record<string, WebBackForwardCacheConfiguredRuntime | undefined> = {};' \
  'must deduplicate BFCache options by runtime identity, not only tab id.'
require_literal "${BFCACHE_COORDINATOR}" \
  'private runtimeGenerationByTabId: Record<string, number | undefined> = {};' \
  'must keep generation-aware BFCache diagnostics.'
require_literal "${BFCACHE_COORDINATOR}" \
  'const sameController = controller !== undefined && configuredRuntime?.controller === controller;' \
  'must include controller identity in the BFCache configuration key.'
require_literal "${BFCACHE_COORDINATOR}" \
  'generation=${runtimeGeneration}' \
  'must retain generation in BFCache apply/skipped diagnostics.'
require_literal "${DOCUMENT_START_SCRIPT_COORDINATOR}" \
  'this.backForwardCacheCoordinator.buildCompatibilityDocumentStartScriptItem(),' \
  'must install the BFCache compatibility script through the Hosted Web document-start owner.'
require_literal "${BFCACHE_COORDINATOR}" \
  "if ((host !== 'cn.bing.com' && host !== 'www.bing.com') || path !== '/search') {" \
  'must keep BroadcastChannel compatibility limited to the exact Bing search hosts and path.'
require_literal "${BFCACHE_COORDINATOR}" \
  "window.addEventListener('pagehide', function () {" \
  'must close tracked Bing BroadcastChannels at the real pagehide lifecycle boundary.'
require_literal "${BFCACHE_COORDINATOR}" \
  'channels[index].close();' \
  'must close each tracked Bing BroadcastChannel before BFCache eligibility is finalized.'
require_literal "${HOSTED_WEB_NODE}" \
  'HOSTED_WEB_BFCACHE_COORDINATOR.removeTabId(this.tabId, this.webController);' \
  'must clear BFCache configuration state when the matching Hosted runtime is disposed.'
require_literal "${HOSTED_WEB_NODE}" \
  'function shouldRecoverPlayingVideoIdentity(reason) {' \
  'must keep playing-video identity recovery scoped to lifecycle and heartbeat samples.'
require_order "${HOSTED_WEB_NODE}" \
  'var snapshot = buildSnapshot(reason);' \
  "sendPlayingVideoGeometry('playing');" \
  'must recover an identity-bearing playing-video event before publishing an active recovery sample.'
require_order "${HOSTED_WEB_NODE}" \
  "sendPlayingVideoGeometry('playing');" \
  'sendSnapshot(snapshot, force === true);' \
  'must publish playing-video identity before the aggregate active-video sample.'
require_literal "${HOSTED_WEB_NODE}" \
  "const PAGE_BEHAVIOR_NATIVE_BRIDGE_NAME: string = '__airaPageBehaviorNativeBridge';" \
  'must retain one explicit native Page Behavior bridge identity.'
require_order "${HOSTED_WEB_NODE}" \
  'hostedController.registerPageBehaviorBridge(config.controller);' \
  'config.callbacks.onControllerAttached(tabId);' \
  'must register Page Behavior before the external attachment owner starts the first real page load.'
forbid_regex "${HOSTED_WEB_NODE}" \
  'window\.__airaPageBehaviorNativeBridge[[:space:]]*=' \
  'must not restore the bounded document-start alias race for Page Behavior.'
require_literal "${WEB_VIEWPORT_SURFACE_HOST}" \
  ".height(this.presentation.fillParentHeight ? '100%' : Math.max(1, this.presentation.hostHeightPx))" \
  'must inherit both parent axes in Large-Screen and video-takeover layout instead of mixing current parent width with full-root/stale numeric height.'
require_literal "${SHELL_PAGE}" \
  'this.webViewportVisualTopInset = targetTopInsetPx;' \
  'must settle the visual top inset synchronously in the history-navigation layout pass.'
forbid_regex "${SHELL_PAGE}" \
  'animateTo\(\{ duration: 180, curve: Curve\.EaseOut \}, \(\) => \{' \
  'must not animate the BrowserShell visual top inset while ArkWeb restores native history.'
forbid_regex "${WEB_VIEWPORT_SURFACE_HOST}" \
  '\.animation\(\{ duration: 180, curve: Curve\.EaseOut \}\)' \
  'must not animate Web surface height/top while ArkWeb restores native history.'
require_literal "${SHELL_PAGE}" \
  'largeScreenShellActive: this.isLargeScreenShellFamilyActive()' \
  'must keep the page limited to forwarding the current Large-Screen shell fact into the Web viewport geometry owner.'
require_literal "${SHELL_PAGE}" \
  'nativeVideoTakeoverActive: this.isAssistantVideoTakeoverActive()' \
  'must keep the page limited to forwarding the current video-takeover fact into the Web viewport geometry owner.'
forbid_regex "${MEDIA_TAKEOVER_COORDINATOR}" \
  'WEB_LIVE_ORIENTATION_REFRESH_(FIRST|SECOND)_DELAY_MS|canRefreshWebLiveOrientation' \
  'must not restore the disproved post-rotation presentation re-entry path.'

require_literal "${WINDOW_OPEN_APP}" \
  "host.recordRuntimeEvent('window_open_child_exit'" \
  'must keep native child-exit handling in the window-open owner.'
require_literal "${WINDOW_OPEN_APP}" \
  "'window_open_child_terminal_back'" \
  'must keep terminal Back handling in the window-open owner.'
require_literal "${WINDOW_OPEN_APP}" \
  'host.closeActiveTabBackToLastTabOrHome' \
  'must return child exit/terminal Back through the opener-aware tab-close path.'
require_literal "${WEB_LINK_CONTEXT_MENU}" \
  'openerTabId: state.tabId' \
  'must forward the source tab when a Web link is opened from the context menu.'
require_literal "${APP_URL_OPEN}" \
  "plan.source === 'web_context_menu'" \
  'must distinguish context-menu source lineage from unrelated native tab creation.'
require_literal "${APP_URL_OPEN}" \
  'openerTabId: openerTabId' \
  'must persist the context-menu source tab as terminal Back lineage.'
require_literal "${APP_URL_OPEN}" \
  "openSource: 'web_context_menu'" \
  'must preserve an explicit manual-link tab source without reusing window_open.'
require_literal "${APP_URL_OPEN}" \
  'openedByNewWindow: false' \
  'must not classify a manual context-menu tab as an ArkWeb popup/OAuth child.'
require_literal "${BROWSER_MODELS}" \
  "'web_context_menu' |" \
  'must retain the persisted manual-link tab source vocabulary.'
require_literal "${TAB_MANAGER}" \
  "value === 'user_new_tab' || value === 'web_context_menu' || value === 'window_open'" \
  'must preserve context-menu source lineage during tab persistence and restore.'
require_literal "${MAIN_BACK}" \
  'const result = this.dependencies.webHistoryCommandRuntimeCoordinator.handleSystemBack();' \
  'must consume active-tab Web history before considering terminal tab Back.'
require_order "${MAIN_BACK}" \
  'const result = this.dependencies.webHistoryCommandRuntimeCoordinator.handleSystemBack();' \
  'return this.handleTerminalWebBack(host, systemRequest, unavailableReason);' \
  'must enter terminal tab Back only after active-tab Web history is unavailable.'
require_literal "${TAB_MANAGER}" \
  'const openerTabId = this.normalizeTabId(activeTab.openerTabId);' \
  'must resolve terminal Back from the active tab source lineage.'
require_literal "${TAB_MANAGER}" \
  'export function isBrowserTabTerminalBackAvailable(tab: BrowserTabState | undefined): boolean {' \
  'must keep terminal Back availability in the tab-domain owner.'
require_literal "${TAB_MANAGER}" \
  'return tab !== undefined && !tab.isHome;' \
  'must keep Back available for every Web tab so transient state and Home fallback remain reachable.'
require_literal "${TAB_CLOSE}" \
  'await this.closeActiveTabAndReturnToParent(host, plan);' \
  'must close a source-linked terminal tab and activate its exact source tab.'
require_order_after "${TAB_CLOSE}" \
  'private async closeActiveTabAndReturnToParent(' \
  'this.dependencies.resolveWebPageLifecycleCoordinator().prepareTabForTerminalClose(activeTab.id);' \
  'this.applyCloseTabTransition(transition, host);' \
  'must prepare the child for terminal close before publishing the visual parent-return transition.'
require_order_after "${TAB_CLOSE}" \
  'private async closeActiveTabAndReturnToParent(' \
  'this.applyCloseTabTransition(transition, host);' \
  'this.dependencies.tabSwitchCoordinator.synchronizeActiveTab();' \
  'must synchronize the exact source tab immediately after the close transition.'
require_order_after "${TAB_CLOSE}" \
  'private async closeActiveTabAndReturnToParent(' \
  'this.dependencies.tabSwitchCoordinator.synchronizeActiveTab();' \
  "this.scheduleDeferredCloseTabCleanup(cleanupPlan, 'source_linked_parent_return', () => {" \
  'must defer child runtime and preview cleanup until after the parent is visible.'
require_no_literal_between_after "${TAB_CLOSE}" \
  'private async closeActiveTabAndReturnToParent(' \
  'this.applyCloseTabTransition(transition, host);' \
  "this.scheduleDeferredCloseTabCleanup(cleanupPlan, 'source_linked_parent_return', () => {" \
  'await ' \
  'must not suspend between publishing the parent-return transition and scheduling child cleanup.'
require_order_after "${TAB_CLOSE}" \
  'private applyCloseTabTransition(' \
  'host.applyActiveTabState(transition.activeTabId, transition.tabSequence);' \
  'host.applyTabList(transition.tabs);' \
  'must activate the surviving tab before the animated tab-list mutation can remove the closing tab.'
require_literal "${ROOT_BOTTOM_ACTION}" \
  'const terminalBackAvailable = isBrowserTabTerminalBackAvailable(this.findActiveTab(facts));' \
  'must enable phone chrome Back for transient handling and tab terminal return.'
require_literal "${LARGE_SCREEN_PRESENTATION}" \
  'canGoBack: navigationIndex > 0 || terminalBackAvailable,' \
  'must enable Large-Screen Back for current-tab history, transient handling, or terminal return.'
require_literal "${LARGE_SCREEN_INTENT}" \
  'this.dependencies.requestBrowserBack();' \
  'must route Large-Screen Back through a typed unified browser Back capability.'
require_order "${LARGE_SCREEN_INTENT}" \
  '!this.searchInvocationAdapter.snapshot().editing' \
  "navigateNativeTabHistory(facts.activeTabId, 'back')" \
  'must inspect Large-Screen omnibox editing before native workspace history.'
require_order "${LARGE_SCREEN_INTENT}" \
  "navigateNativeTabHistory(facts.activeTabId, 'back')" \
  'this.dependencies.requestBrowserBack();' \
  'must preserve native workspace history before terminal browser Back when no omnibox edit is active.'
forbid_regex "${LARGE_SCREEN_INTENT}" \
  'private requestBrowserBack\(' \
  'must not wrap the typed Large-Screen Back dependency in a pass-through helper.'
require_literal "${SHELL_PAGE}" \
  'this.browserMainBackCoordinator.onBackPress(this.browserMainBackHost);' \
  'must send Large-Screen Back directly to the unified coordinator before transient cleanup.'
require_literal "${SHELL_PAGE}" \
  'largeScreenOmniboxEditing: this.isLargeScreenShellFamilyActive() &&' \
  'must expose active Large-Screen omnibox editing as a shell Back state.'
require_literal "${MAIN_BACK}" \
  "case 'dismiss_search_invocation':" \
  'must consume Large-Screen omnibox editing as one complete Back action.'
require_order "${MAIN_BACK}" \
  "case 'dismiss_search_invocation':" \
  'const result = this.dependencies.webHistoryCommandRuntimeCoordinator.handleSystemBack();' \
  'must dismiss Large-Screen omnibox editing before attempting active-tab Web history.'
forbid_regex "${LARGE_SCREEN_INTENT}" \
  'handleToolbarNavigateBack\(\)' \
  'must not stop Large-Screen Back at Web history without terminal tab continuation.'
require_literal "${BACKGROUND_MANAGER}" \
  "'policy_background_contract_violation'" \
  'must retain the browser-core background protection violation guard.'
require_literal "${ADBLOCK_RUST_CORE}" \
  'patch_legacy_window_open_scriptlet(&mut resources)?;' \
  'must retain the accepted AdGuard legacy window-open argument compatibility in the Rust resource owner.'
require_literal "${ADBLOCK_RUST_CORE}" \
  '.find(|resource| resource.name == "prevent-window-open.js")' \
  'must patch only the pinned Brave window-open resource before Rust installs it.'
require_literal "${ADBLOCK_RUST_CORE}" \
  'let resources: UrlSpecificResources = engine.engine.url_cosmetic_resources(url);' \
  'must keep domain and exception selection inside the Rust authority.'
require_literal "${ADBLOCK_DOCUMENT_START}" \
  'const resources = allowlisted ? undefined : this.runtimeGeneration.resolveNativeCosmeticResources(targetUrl);' \
  'must suppress Rust scriptlets for product-level site exceptions before document-start execution.'
require_literal "${ADBLOCK_DOCUMENT_START}" \
  'const scriptletScript = resources?.injectedScript.trim() ??' \
  'must consume only the final script text selected and expanded by Rust.'
require_literal "${ADBLOCK_DOCUMENT_START}" \
  'this.cosmeticRuntimeScriptService.buildInjectedScriptExecutionScript(' \
  'must keep ArkTS limited to the ArkWeb execution adapter for Rust-selected scriptlets.'
if [ -e "${RETIRED_ADBLOCK_SCRIPTLET_RUNTIME}" ]; then
  report_failure 'retired ArkTS subscription scriptlet matcher/runtime must not be restored.'
fi

if grep -R -E -n --include='*.ets' \
  'window_open_handoff_recovery|BrowserWindowOpenNavigationWatchService' \
  "${SOURCE_ROOT}" >/dev/null; then
  report_failure 'forbidden window-open timer/replay recovery code was restored under AiraBrowser/entry/src/main/ets.'
fi

if [ "${failures}" -gt 0 ]; then
  cat >&2 <<'EOF'

The Huawei-aligned window-open/BFCache static contract has regressed.
See AGENTS.md and docs/adr/0040-window-open-bfcache-contract-is-frozen.md.
Update the implementation and, when the intended behavior changes, update this guard and ADR truthfully.
EOF
  exit 1
fi

echo 'Window-open/BFCache static contract passed.'
