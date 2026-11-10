#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPONENT_DIR="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/components"
TOKEN_FILE="${COMPONENT_DIR}/common/FloatingGlassMaterialTokens.ets"
ACCESS_FILE="${COMPONENT_DIR}/common/ArkUiMaterialAccess.ets"
SURFACE_FILE="${COMPONENT_DIR}/common/FloatingGlassMaterialSurface.ets"
BROWSER_SURFACE_FILE="${COMPONENT_DIR}/browser/BrowserFloatingGlassMaterialSurface.ets"
BOTTOM_SURFACE_FILE="${COMPONENT_DIR}/browser/BrowserBottomChromeImmersiveMaterialSurface.ets"
TABS_OVERLAY_FILE="${COMPONENT_DIR}/browser/BrowserTabsFloatingOverlay.ets"
VIDEO_OVERLAY_FILE="${COMPONENT_DIR}/browser/BrowserVideoAssistantPlayerOverlay.ets"
ADDRESS_PANEL_FILE="${COMPONENT_DIR}/browser/BrowserBottomAddressPanel.ets"
SETTINGS_HDS_FILE="${COMPONENT_DIR}/settings/SettingsHdsScaffold.ets"
MANAGEMENT_HDS_FILE="${COMPONENT_DIR}/common/ManagementHdsScaffold.ets"
SEGMENTED_TABS_FILE="${COMPONENT_DIR}/common/SegmentedTabs.ets"
CENTERED_DIALOG_FILE="${COMPONENT_DIR}/common/CenteredDialogSurface.ets"
CENTERED_DIALOG_WIDTH_VIEW_MODEL="${REPO_ROOT}/AiraBrowser/entry/src/main/ets/core/browser/CenteredDialogWidthViewModel.ets"
SYNC_PROGRESS_DIALOG_FILE="${COMPONENT_DIR}/sync/SyncOperationProgressDialog.ets"
SYNC_PROGRESS_HOST_FILES=(
  "${COMPONENT_DIR}/customhome/CustomHomepageSettingsScreen.ets"
  "${COMPONENT_DIR}/sync/SyncAdditionalBackupHost.ets"
  "${COMPONENT_DIR}/sync/SyncExperienceHost.ets"
  "${COMPONENT_DIR}/sync/SyncMasterControlSection.ets"
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages/BookmarkManagerPage.ets"
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages/SyncAdvancedSettingsPage.ets"
  "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages/SyncWebdavConfigPage.ets"
)

fail() {
  printf 'Immersive light-sense contract violation: %s\n' "$1" >&2
  exit 1
}

require_text() {
  local file="$1"
  local pattern="$2"
  local message="$3"
  rg -q --fixed-strings "$pattern" "$file" || fail "$message"
}

for file in "$TOKEN_FILE" "$ACCESS_FILE" "$SURFACE_FILE" "$BROWSER_SURFACE_FILE" "$BOTTOM_SURFACE_FILE" \
  "$TABS_OVERLAY_FILE" "$VIDEO_OVERLAY_FILE" "$ADDRESS_PANEL_FILE" "$SETTINGS_HDS_FILE" \
  "$MANAGEMENT_HDS_FILE" "$SEGMENTED_TABS_FILE" "$CENTERED_DIALOG_FILE" \
  "$SYNC_PROGRESS_DIALOG_FILE"; do
  [ -f "$file" ] || fail "required source file is missing: ${file}"
done

require_text "$TOKEN_FILE" 'export const IMMERSIVE_MATERIAL_MIN_API_VERSION: number = 26;' \
  'component-level material must keep the API 26 compatibility gate.'
require_text "$TOKEN_FILE" 'deviceInfo.sdkApiVersion < IMMERSIVE_MATERIAL_MIN_API_VERSION' \
  'material availability must check deviceInfo.sdkApiVersion before calling API 26 APIs.'
require_text "$ACCESS_FILE" "import { uiMaterial } from '@kit.ArkUI';" \
  'API 26 ArkUI material access must keep the uiMaterial kit import.'
require_text "$ACCESS_FILE" 'uiMaterial.getMaterialInfo().state' \
  'material availability must honor the application MaterialState.'
if rg -q --fixed-strings 'uiMaterial.ImmersiveStyle.' \
  "$TOKEN_FILE" "$COMPONENT_DIR/browser/BrowserFloatingGlassMaterialTokens.ets" \
  "$COMPONENT_DIR/browser/BrowserFloatingGlassMaterialSurface.ets" \
  "$BOTTOM_SURFACE_FILE" "$CENTERED_DIALOG_FILE"; then
  fail 'ImmersiveStyle enum access must remain encapsulated in ArkUiMaterialAccess.'
fi
if rg -q --fixed-strings 'isImmersiveMaterialSupported' "$TOKEN_FILE"; then
  fail 'the client SDK used by this repository does not expose isImmersiveMaterialSupported; keep the API-version and MaterialState gate.'
fi

require_text "$SURFACE_FILE" '@Prop materialEnabled: boolean = false;' \
  'ordinary FloatingGlassMaterialSurface instances must be opt-in.'
require_text "$SURFACE_FILE" "@Prop fallbackColor: ResourceColor = \$r('app.color.surface_glass_background');" \
  'ordinary FloatingGlassMaterialSurface instances must have a visible glass-like fallback.'
require_text "$BROWSER_SURFACE_FILE" '@Prop materialEnabled: boolean = false;' \
  'ordinary BrowserFloatingGlassMaterialSurface instances must be opt-in.'
require_text "$BROWSER_SURFACE_FILE" "@Prop fallbackColor: ResourceColor = \$r('app.color.surface_glass_background');" \
  'ordinary BrowserFloatingGlassMaterialSurface instances must have a visible glass-like fallback.'
require_text "$BOTTOM_SURFACE_FILE" '@Prop materialEnabled: boolean = false;' \
  'browser bottom chrome material must be opt-in.'
require_text "$BOTTOM_SURFACE_FILE" "@Prop fallbackColor: ResourceColor = \$r('app.color.browser_bottom_toolbar_glass_background');" \
  'browser bottom chrome must have a visible fallback when material is unavailable.'
require_text "$BOTTOM_SURFACE_FILE" 'this.shouldApplyMaterial() ? BlurStyle.NONE : BROWSER_FLOATING_GLASS_MATERIAL_BLUR_STYLE' \
  'browser bottom chrome must use a mutually exclusive blur fallback.'

if rg -q --fixed-strings '.backgroundColor(this.tintColor)' "$SURFACE_FILE" || \
   rg -q --fixed-strings '.backgroundColor(this.materialTint)' "$BOTTOM_SURFACE_FILE"; then
  fail 'material-unavailable fallbacks must not use the low-alpha material tint.'
fi

if rg -q --fixed-strings 'BrowserFloatingGlassMaterialSurface' "$TABS_OVERLAY_FILE" || \
   rg -q --fixed-strings 'systemMaterial(' "$TABS_OVERLAY_FILE"; then
  fail 'Tabs overview must not apply a full-screen immersive material background.'
fi

if rg -q --fixed-strings 'systemMaterial(' "$VIDEO_OVERLAY_FILE" || \
   rg -q --fixed-strings 'materialEnabled: true' "$VIDEO_OVERLAY_FILE"; then
  fail 'video assistant surfaces must not place immersive material above dynamic video content.'
fi

sheet_options_start="$(rg -n -m 1 'private buildToolbarSystemSheetOptions\(\)' "$ADDRESS_PANEL_FILE" | cut -d: -f1)"
sheet_options_end="$(rg -n -m 1 'private buildToolbarSystemSheet\(\)' "$ADDRESS_PANEL_FILE" | cut -d: -f1)"
[ -n "$sheet_options_start" ] && [ -n "$sheet_options_end" ] || \
  fail 'toolbar Sheet options source block could not be located.'
sheet_options_block="$(sed -n "${sheet_options_start},${sheet_options_end}p" "$ADDRESS_PANEL_FILE")"
if printf '%s\n' "$sheet_options_block" | rg -q --fixed-strings 'systemMaterial:'; then
  fail 'toolbar native Sheet must keep the system default surface instead of an immersive material.'
fi
sheet_start="$(rg -n -m 1 'private buildToolbarSystemSheet\(\)' "$ADDRESS_PANEL_FILE" | cut -d: -f1)"
sheet_end="$(rg -n -m 1 'private resolveToolbarSystemSheetPreviewHeight' "$ADDRESS_PANEL_FILE" | cut -d: -f1)"
[ -n "$sheet_start" ] && [ -n "$sheet_end" ] || fail 'toolbar Sheet source block could not be located.'
sheet_block="$(sed -n "${sheet_start},${sheet_end}p" "$ADDRESS_PANEL_FILE")"
if printf '%s\n' "$sheet_block" | rg -q --fixed-strings 'systemMaterial('; then
  fail 'toolbar Sheet child content must not set a nested systemMaterial.'
fi

if rg -q --fixed-strings 'MaterialLevel.SMOOTH' "$SETTINGS_HDS_FILE" "$MANAGEMENT_HDS_FILE"; then
  fail 'HDS title bars must use the device-adaptive material level.'
fi
require_text "$SETTINGS_HDS_FILE" 'materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE' \
  'Settings HDS title bar must use ADAPTIVE material level.'
require_text "$MANAGEMENT_HDS_FILE" 'materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE' \
  'Management HDS title bar must use ADAPTIVE material level.'
require_text "$MANAGEMENT_HDS_FILE" 'materialEnabled: true' \
  'Management HDS title actions must explicitly opt into the API-gated material.'
require_text "$CENTERED_DIALOG_FILE" 'instance.backgroundColor(resolveCenteredDialogSurfaceColor())' \
  'centered dialog content must paint the shared opaque surface.'
require_text "$CENTERED_DIALOG_FILE" 'params.backgroundBlurStyle = BlurStyle.NONE;' \
  'centered alerts must disable the default dialog blur so the surface stays opaque.'
if rg -q --fixed-strings 'createCenteredDialogMaterial' "$CENTERED_DIALOG_FILE" || \
   rg -q --fixed-strings 'systemMaterial' "$CENTERED_DIALOG_FILE"; then
  fail 'centered dialogs must use one opaque surface instead of immersive material.'
fi
# AlertDialog.width is window-relative with no constraintSize, so a bare percentage
# stretches the alert to the whole PC/large-screen window. The width must stay
# clamped to the shared centered-dialog maximum.
require_text "$CENTERED_DIALOG_FILE" 'centeredDialogWidthViewModel.resolve(readDisplayWidthVp())' \
  'centered alerts must resolve their width from the shared clamp instead of a flat percentage.'
require_text "$CENTERED_DIALOG_WIDTH_VIEW_MODEL" 'CENTERED_DIALOG_MAX_WIDTH_VP' \
  'centered alert width owner must keep the shared maximum width clamp.'
if rg -q --fixed-strings "params.width = '90%';" "$CENTERED_DIALOG_FILE"; then
  fail 'centered alerts must not apply a flat window-relative percentage width on large screens.'
fi
# Sync progress uses the same opaque centered surface as every other dialog.
if rg -q 'createCenteredDialogMaterial|applyCommonSystemMaterial|ImmersiveMaterial|systemMaterial' \
  "$SYNC_PROGRESS_DIALOG_FILE"; then
  fail 'sync progress must use the shared opaque dialog surface instead of immersive material.'
fi
require_text "$SYNC_PROGRESS_DIALOG_FILE" 'CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER' \
  'sync progress must take the shared centered dialog surface.'
if rg -q --fixed-strings 'new CustomDialogController(withDialogSystemMaterial' \
  "$COMPONENT_DIR" "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages" -g '*.ets'; then
  fail 'CustomDialogController must receive the options object literal directly so @CustomDialog builders keep new.'
fi
for file in "${SYNC_PROGRESS_HOST_FILES[@]}"; do
  require_text "$file" 'customStyle: false' \
    "sync progress host must use the system CustomDialog style: ${file#"$REPO_ROOT"/}"
  require_text "$file" 'backgroundColor: resolveCenteredDialogSurfaceColor(),' \
    "sync progress host must use the shared opaque dialog surface: ${file#"$REPO_ROOT"/}"
  require_text "$file" 'backgroundBlurStyle: BlurStyle.NONE,' \
    "sync progress host must disable dialog blur: ${file#"$REPO_ROOT"/}"
done
if rg -q --fixed-strings 'systemMaterial: createCenteredDialogMaterial()' \
  "$COMPONENT_DIR" "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages" -g '*.ets'; then
  fail 'centered dialogs must not opt into immersive systemMaterial.'
fi
while IFS= read -r file; do
  require_text "$file" 'backgroundBlurStyle: BlurStyle.NONE,' \
    "CustomDialogController must use the opaque dialog surface: ${file#"$REPO_ROOT"/}"
  require_text "$file" 'cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,' \
    "CustomDialogController must use the shared dialog corner radius: ${file#"$REPO_ROOT"/}"
done < <(rg -l --fixed-strings 'new CustomDialogController(' \
  "$COMPONENT_DIR" "${REPO_ROOT}/AiraBrowser/entry/src/main/ets/app/pages" -g '*.ets')
require_text "$SEGMENTED_TABS_FILE" 'HdsTabs' \
  'shared segmented tabs must use the HDS Tabs component.'
require_text "$SEGMENTED_TABS_FILE" 'HdsTabsController' \
  'shared segmented tabs must use the HDS Tabs controller for controlled selection.'
require_text "$SEGMENTED_TABS_FILE" '.barMode(BarMode.Fixed)' \
  'shared segmented tabs must use the fixed HDS bar layout.'
require_text "$SEGMENTED_TABS_FILE" '.barFloatingStyle(this.resolveBarFloatingStyle())' \
  'shared segmented tabs must use the HDS floating bar style.'
require_text "$SEGMENTED_TABS_FILE" 'systemMaterialEffect' \
  'shared segmented tabs must configure the HDS system material effect.'
require_text "$SEGMENTED_TABS_FILE" 'hdsMaterial.MaterialType.ADAPTIVE' \
  'shared segmented tabs must use the device-adaptive HDS material type.'
require_text "$SEGMENTED_TABS_FILE" 'hdsMaterial.MaterialLevel.ADAPTIVE' \
  'shared segmented tabs must use the device-adaptive HDS material level.'
require_text "$SEGMENTED_TABS_FILE" 'hdsMaterial.getSystemMaterialTypes()' \
  'shared segmented tabs must query HDS material compatibility before enabling the effect.'
if rg -q --fixed-strings 'FloatingGlassMaterialSurface' "$SEGMENTED_TABS_FILE" || \
   rg -q --fixed-strings 'uiMaterial' "$SEGMENTED_TABS_FILE"; then
  fail 'shared segmented tabs must not fall back to the old immersive-material surface API.'
fi

while IFS= read -r file; do
  case "$file" in
    "$SURFACE_FILE"|"$BROWSER_SURFACE_FILE"|"$BOTTOM_SURFACE_FILE"|"$TOKEN_FILE") continue ;;
  esac
  if rg -q --fixed-strings 'systemMaterial(createFloatingGlassMaterial(' "$file"; then
    fail "${file#"$REPO_ROOT"/} must use the availability-gated material helper."
  fi
done < <(rg -l --fixed-strings 'systemMaterial(' "$COMPONENT_DIR" -g '*.ets')

if rg -Uq 'systemMaterial\([\s\S]{0,240}backgroundBlurStyle' "$COMPONENT_DIR" -g '*.ets'; then
  fail 'immersive material must not be combined with backgroundBlurStyle in the same component chain.'
fi

echo 'Immersive light-sense contract passed.'
