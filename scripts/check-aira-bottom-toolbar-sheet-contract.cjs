const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const panelPath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets');
const addressPanelPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets');
const quickActionCardPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/HomeSearchQuickActionCard.ets');
const toolbarCustomizationCoordinatorPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserToolbarCustomizationCoordinator.ets');
const personalizationSyncSnapshotPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/services/sync/PersonalizationSyncSnapshotService.ets');
const neutralThemePath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/theme/BrowserBottomPanelNeutralTheme.ets');
const surfaceHostPath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserShellPrimarySurfaceHost.ets');
const shellPagePath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets');
const storageAdapterPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/data/preferences/ArkPreferencesStorageAdapter.ets');
const toolbarModelsPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/common/models/BrowserModels.ets');

const panel = fs.readFileSync(panelPath, 'utf8');
const addressPanel = fs.readFileSync(addressPanelPath, 'utf8');
const normalizedAddressPanel = addressPanel.replace(/\s+/g, ' ');
const quickActionCard = fs.readFileSync(quickActionCardPath, 'utf8');
const toolbarCustomizationCoordinator = fs.readFileSync(toolbarCustomizationCoordinatorPath, 'utf8');
const personalizationSyncSnapshot = fs.readFileSync(personalizationSyncSnapshotPath, 'utf8');
const neutralTheme = fs.readFileSync(neutralThemePath, 'utf8');
const normalizedNeutralTheme = neutralTheme.replace(/\s+/g, ' ');
const surfaceHost = fs.readFileSync(surfaceHostPath, 'utf8');
const shellPage = fs.readFileSync(shellPagePath, 'utf8');
const storageAdapter = fs.readFileSync(storageAdapterPath, 'utf8');
const toolbarModels = fs.readFileSync(toolbarModelsPath, 'utf8');
const toolbarSheetBindingStart = addressPanel.indexOf(
  '.bindSheet($$this.toolbarSystemSheetVisible, this.buildToolbarSystemSheet(),'
);
const toolbarSheetBindingEnd = addressPanel.indexOf('\n  }', toolbarSheetBindingStart);
const toolbarSheetBinding = toolbarSheetBindingStart >= 0 && toolbarSheetBindingEnd > toolbarSheetBindingStart ?
  addressPanel.slice(toolbarSheetBindingStart, toolbarSheetBindingEnd) : '';
const toolbarSheetContentStart = addressPanel.indexOf('private buildToolbarSystemSheet()');
const toolbarSheetContentEnd = addressPanel.indexOf('private buildAddressHeader()', toolbarSheetContentStart);
const toolbarSheetContent = toolbarSheetContentStart >= 0 && toolbarSheetContentEnd > toolbarSheetContentStart ?
  addressPanel.slice(toolbarSheetContentStart, toolbarSheetContentEnd) : '';
const toolbarSheetGridStart = addressPanel.indexOf('private buildToolbarSystemSheetActionGrid(');
const toolbarSheetGridEnd = addressPanel.indexOf('\n  @Builder', toolbarSheetGridStart + 1);
const toolbarSheetGrid = toolbarSheetGridStart >= 0 && toolbarSheetGridEnd > toolbarSheetGridStart ?
  addressPanel.slice(toolbarSheetGridStart, toolbarSheetGridEnd) : '';

function assertContract(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

assertContract(addressPanel.includes('@State private toolbarSystemSheetVisible: boolean = false;'),
  'Toolbar system Sheet visibility must be independent from the search panel detent.');
assertContract(addressPanel.includes(
  '.bindSheet($$this.toolbarSystemSheetVisible, this.buildToolbarSystemSheet(),'
), 'Toolbar actions must be hosted by a plain native bindSheet.');
assertContract(addressPanel.includes('this.buildToolbarSystemSheetOptions()'),
  'Toolbar system Sheet must provide native Sheet options.');
assertContract(addressPanel.includes('height: fullHeight') &&
  addressPanel.includes('detents: [previewHeight, fullHeight]') &&
  addressPanel.includes('detentSelection: this.toolbarSystemSheetDetentSelection'),
  'Toolbar system Sheet must expose native preview and full detents.');
assertContract(addressPanel.includes('BROWSER_BOTTOM_TOOLBAR_SYSTEM_SHEET_DRAG_BAR_HEIGHT') &&
  addressPanel.includes('this.resolveReadingContinuationHeight() +\n        BROWSER_BOTTOM_TOOLBAR_SYSTEM_SHEET_DRAG_BAR_HEIGHT') &&
  addressPanel.includes('Math.min(hostHeight, maxPanelHeight) -\n        BROWSER_BOTTOM_TOOLBAR_SYSTEM_SHEET_DRAG_BAR_HEIGHT'),
  'Toolbar Sheet sizing must reserve the native 16vp drag bar in both detents and layout height.');
assertContract(addressPanel.includes('dragBar: true') && addressPanel.includes('showClose: false'),
  'Toolbar system Sheet must use the plain system drag bar without a custom close header.');
assertContract(normalizedAddressPanel.includes(
  "if (this.responsiveState.aspectBreakpoint === 'wide') { options.width = " +
    'this.resolveFloatingQuickActionLayoutWidth(); }'
), 'Landscape toolbar Sheets must use the same responsive width as their action grid.');
assertContract(!toolbarSheetBinding.includes('title:') && !toolbarSheetBinding.includes('detents:') &&
  !toolbarSheetBinding.includes('systemMaterial:') && !toolbarSheetBinding.includes('onWillDismiss:'),
  'Toolbar system Sheet must not add a title, custom material, or dismissal state machine.');
assertContract(!addressPanel.includes('onDetentsDidChange:') &&
  !addressPanel.includes('toolbarSystemSheetExpanded') &&
  toolbarSheetContent.includes('this.resolveToolbarRenderSnapshot().actions') &&
  addressPanel.includes('scrollSizeMode: ScrollSizeMode.CONTINUOUS'),
  'Toolbar system Sheet must keep one stable full action list and resize it continuously between native detents.');
assertContract(toolbarSheetGrid.includes('List({ space: layoutState.rowGap })') &&
  toolbarSheetGrid.includes('.onMove((from: number, to: number) =>') &&
  toolbarSheetGrid.includes('onLongPress: (index: number) =>') &&
  toolbarSheetGrid.includes('true,\n                this.resolveToolbarSystemSheetActionCellWidth(layoutState)') &&
  !toolbarSheetGrid.includes('Scroll(') &&
  !toolbarSheetGrid.includes('.scrollable(') &&
  toolbarSheetGrid.includes('.cachedCount(actions.length)') &&
  toolbarSheetGrid.includes('.syncLoad(true)'),
  'Toolbar system Sheet action grid must use the official List drag-sort seam with all cards preloaded.');
assertContract(addressPanel.includes(".width(actionCellWidth > 0 ? actionCellWidth : '100%')") &&
  addressPanel.includes('.layoutWeight(actionCellWidth > 0 ? 0 : 1)'),
  'Toolbar system Sheet cards must use fixed equal-width cells so a final partial row stays left aligned.');
assertContract(toolbarSheetGrid.includes(".width('100%')") &&
  toolbarSheetGrid.includes('.lanes(layoutState.columnCount, layoutState.columnGap)') &&
  toolbarSheetGrid.includes('this.resolveToolbarSystemSheetActionCellWidth(layoutState)'),
  'Toolbar system Sheet must use full-width equal lanes so the complete fixed-width grid stays centered and partial rows start at column one.');
assertContract(addressPanel.includes('private shouldSuppressBackdropForToolbarSystemSheetGesture(') &&
  addressPanel.includes('this.suppressBackdropForActiveToolbarSheetGesture =\n' +
    '              this.shouldSuppressBackdropForToolbarSystemSheetGesture(this.activeChromeGestureSource);') &&
  addressPanel.includes('!this.suppressBackdropForActiveToolbarSheetGesture'),
  'Native toolbar Sheet gestures must not drive the legacy root scrim while the system Sheet supplies its own fade.');
assertContract(/private shouldRenderLegacyFloatingActionSurface\(\): boolean\s*\{\s*return false;\s*\}/s.test(addressPanel),
  'Legacy floating toolbar presentation must stay disabled; native Sheet owns both stages.');
assertContract(/private shouldMountFloatingActionSurface\(\): boolean\s*\{\s*return this\.shouldRenderLegacyFloatingActionSurface\(\) &&/s.test(addressPanel) &&
  /private shouldMountFloatingActionContent\(\): boolean\s*\{\s*return this\.shouldRenderLegacyFloatingActionSurface\(\) &&/s.test(addressPanel),
  'Legacy floating toolbar content must not be mounted indirectly by the search surface state.');
const toolbarGestureHelperStart = addressPanel.indexOf('private shouldOpenToolbarSystemSheetFromGesture(');
const toolbarGestureHelperEnd = addressPanel.indexOf('\n  }', toolbarGestureHelperStart);
const toolbarGestureHelper = toolbarGestureHelperStart >= 0 && toolbarGestureHelperEnd > toolbarGestureHelperStart ?
  addressPanel.slice(toolbarGestureHelperStart, toolbarGestureHelperEnd) : '';
assertContract(addressPanel.includes('private shouldOpenToolbarSystemSheetFromGesture(') &&
  addressPanel.includes('this.openToolbarSystemSheet();') &&
  addressPanel.includes("return 'low';") &&
  toolbarGestureHelper.includes("source === 'center-capsule'") &&
  toolbarGestureHelper.includes('this.hasQuickActionSlotsAvailable()') &&
  !toolbarGestureHelper.includes('this.isWebContentMode()'),
  'Home and Web center upward gestures must open the native Sheet and leave the legacy panel at low.');
assertContract(!addressPanel.includes('private resolveToolbarGestureRelease('),
  'The old toolbar stage gesture-release state machine must not remain in the address panel.');
assertContract(addressPanel.includes("intent.actionId === 'bottomChromeMenu'"),
  'Toolbar menu clicks must be intercepted before the legacy panel coordinator.');
assertContract(addressPanel.indexOf("intent.actionId === 'bottomChromeMenu'") <
  addressPanel.indexOf('const item = this.findLiveHeaderAction(intent.actionId);'),
  'Toolbar menu interception must happen before legacy header-action dispatch.');
assertContract(addressPanel.includes('this.toolbarSystemSheetVisible = true;'),
  'Toolbar menu clicks must directly open the independent system Sheet.');
assertContract(addressPanel.includes('BrowserBottomSheetSurface({') &&
  addressPanel.includes('private buildToolbarSystemSheet()'),
  'Toolbar Sheet content must reuse the existing bottom-sheet surface.');
assertContract(toolbarSheetContent.includes('surfaceColor: this.storedPageBackgroundColor') &&
  !toolbarSheetContent.includes('resolveFloatingGlassMaterialBackgroundColor('),
  'Toolbar system Sheet must use the opaque themed surface instead of a transparent glass background.');
assertContract(addressPanel.includes('backgroundColor: this.storedPageBackgroundColor') &&
  addressPanel.includes('blurStyle: BlurStyle.NONE') &&
  !addressPanel.includes('systemMaterial: createFloatingGlassMaterialIfAvailable('),
  'Toolbar system Sheet must keep one opaque themed backplate and must not add a second glass blur.');
assertContract(addressPanel.includes('const WEB_BOTTOM_TOOLBAR_SHEET_ACTION_CORNER_RADIUS: number = 16;') &&
  addressPanel.includes('cardCornerRadius: toolbarSystemSheetAction ?') &&
  addressPanel.includes('WEB_BOTTOM_TOOLBAR_SHEET_ACTION_CORNER_RADIUS : 0'),
  'Toolbar system Sheet action icons must use rounded rectangles without changing other quick-action surfaces.');
assertContract(quickActionCard.includes('@Prop cardCornerRadius: number = 0;') &&
  quickActionCard.includes('this.cardCornerRadius > 0'),
  'Shared quick-action cards must keep circles by default and support an explicit rounded-rectangle radius.');
assertContract(addressPanel.includes('resolveBrowserBottomToolbarSheetActionColor(this.resolveNeutralThemeMode())') &&
  neutralTheme.includes("const BROWSER_BOTTOM_TOOLBAR_SHEET_ACTION_LIGHT: string = '#FFFFFFFF';") &&
  normalizedNeutralTheme.includes('return isBrowserBottomNeutralDarkMode(mode) ? ' +
    'BROWSER_BOTTOM_EXPANDED_TOOLBAR_ACTION_DARK : BROWSER_BOTTOM_TOOLBAR_SHEET_ACTION_LIGHT;'),
  'Toolbar system Sheet actions must use an opaque light background and preserve the dark theme branch.');
assertContract(!toolbarSheetContent.includes('PanGesture') &&
  toolbarSheetGrid.includes('.onMove(') &&
  addressPanel.includes('private shouldEnableToolbarSystemSheetReorder(') &&
  addressPanel.includes('this.toolbarSystemSheetVisible'),
  'Toolbar Sheet content must use the official List drag-sort callback without a competing custom PanGesture.');
assertContract(addressPanel.includes('this.toolbarCustomizationCoordinator.persistPrimaryMove(') &&
  toolbarCustomizationCoordinator.includes('preferencesRepository.updateToolbarLayoutSettings') &&
  personalizationSyncSnapshot.includes('toolbarLayout: {') &&
  personalizationSyncSnapshot.includes('preferences.toolbarLayout.primaryActionIds.slice()'),
  'Toolbar reorder must persist through PreferencesRepository and remain part of the personalization sync payload.');
assertContract(!panel.includes('.bindSheet($$this.nativeSheetVisible'),
  'The persistent search/address panel must not own a native Sheet.');
assertContract(!panel.includes('nativeSheetDetentSelection') &&
  !panel.includes('detents: [lowHeight, previewHeight, fullHeight]'),
  'The removed three-detent toolbar Sheet state machine must not remain in the search panel.');
assertContract(!panel.includes('uiMaterial'),
  'The search panel must not own a second system-material Sheet implementation.');
assertContract(panel.includes('this.buildFloatingOverlay()'),
  'The search/address panel must retain its original floating overlay path.');
assertContract(normalizedAddressPanel.includes(
  "floatingHeaderPanEnabled: !this.tabSwipeActive && (this.resolveFloatingLayoutMode() === 'input' || " +
    'this.shouldUseThreeBlockBottomChrome())'
), 'Input and outer return-home gestures must remain enabled outside a horizontal tab swipe; ' +
  'center tool expansion is not a Sheet gesture.');
assertContract(!surfaceHost.includes('expandedScrimHomeSurfaceVisible'),
  'Phone surface host must not force-mount Home for an expanded toolbar scrim.');
assertContract(!surfaceHost.includes('webLayerOpacity: this.expandedScrimHomeSurfaceVisible'),
  'Expanded toolbar must not hide the active Web layer.');
assertContract(!shellPage.includes('expandedScrimHomeSurfaceVisible:'),
  'Browser Shell must not pass the removed Home-forcing scrim prop.');

// Every field of the toolbar settings must survive a cold start.
//
// `writeToolbarLayoutSettings` stores the whole object with `JSON.stringify`, but the read side goes
// through a hand-written `parseToolbarLayoutSettings`. A field added to the model and the writer but
// not to that parse is written, then silently dropped on the next launch and replaced by its default.
// The middle bar's swipe-up choice was exactly that: it looked saved for the session and reverted to
// 打开工具面板 after a cold start.
const toolbarSettingsStart = toolbarModels.indexOf('export interface BrowserToolbarLayoutSettings');
const toolbarSettingsBody = toolbarModels.slice(toolbarSettingsStart);
const toolbarModelFields = (toolbarSettingsBody.slice(0, toolbarSettingsBody.indexOf('\n}'))
  .match(/^\s{2}(\w+)\??:/gm) || []).map(field => field.trim().replace(/\??:$/, ''));
assertContract(toolbarModelFields.length > 0,
  'The toolbar layout settings model must declare its fields.');
const parseBody = storageAdapter.slice(
  storageAdapter.indexOf('private parseToolbarLayoutSettings('),
  storageAdapter.indexOf('private parseSitePermissionDefaultSettings('));
assertContract(parseBody.length > 0, 'The toolbar layout parse must exist in the storage adapter.');
const unparsedFields = toolbarModelFields.filter(field => !parseBody.includes(`${field}:`));
assertContract(unparsedFields.length === 0,
  `Every toolbar layout setting must be restored by parseToolbarLayoutSettings; missing: ${unparsedFields.join(', ')}`);
assertContract(storageAdapter.includes('centerCapsuleSwipeUpActionId: String(parsed.centerCapsuleSwipeUpActionId ??'),
  'The middle bar swipe-up choice must be parsed back, not left to default.');

const preferencesRepository = fs.readFileSync(path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/data/preferences/PreferencesRepository.ets'), 'utf8');
const toolbarViewModel = fs.readFileSync(path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserToolbarCustomizationViewModel.ets'), 'utf8');
const splitPolicy = fs.readFileSync(path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserSplitToolbarCustomizationPolicy.ets'), 'utf8');
const toolbarSettingsScreen = fs.readFileSync(path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/settings/BrowserToolbarCustomizationScreen.ets'), 'utf8');
const splitChrome = fs.readFileSync(path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserSplitToolbarChrome.ets'), 'utf8');
const normalizeBody = preferencesRepository.slice(
  preferencesRepository.indexOf('private normalizeToolbarLayoutSettings('),
  preferencesRepository.indexOf('private normalizeToolbarSlotActionId('));
const mergeBody = preferencesRepository.slice(
  preferencesRepository.indexOf('async updateToolbarLayoutSettings('),
  preferencesRepository.indexOf('async updateSitePermissionDefaultSettings('));
const floatingNormalizeStart = toolbarViewModel.indexOf(
  'normalizeSettings(settings: BrowserToolbarLayoutSettings)');
const floatingNormalizeBody = toolbarViewModel.slice(
  floatingNormalizeStart,
  toolbarViewModel.indexOf('getCatalogActionIds(): BrowserBottomAddressPanelActionId[]', floatingNormalizeStart));
const cloneBody = splitPolicy.slice(
  splitPolicy.indexOf('export function cloneBrowserToolbarLayoutSettings('),
  splitPolicy.indexOf('export function resolveSplitToolbarTapActionId('));
const droppedFields = toolbarModelFields.filter(field => {
  return !normalizeBody.includes(`${field}:`) ||
    !mergeBody.includes(field) ||
    !cloneBody.includes(`${field}:`);
});
assertContract(droppedFields.length === 0,
  `Toolbar layout fields must survive normalize, merge and clone; missing: ${droppedFields.join(', ')}`);
assertContract(floatingNormalizeBody.includes('cloneBrowserToolbarLayoutSettings') &&
  floatingNormalizeBody.includes('normalizeSplitToolbarSettings'),
  'Floating toolbar normalize must keep split bottom-bar slots.');
assertContract(toolbarSettingsScreen.includes("this.toolbarChromeStyle === 'split'") &&
  toolbarSettingsScreen.includes('buildSplitToolbarPreview') &&
  toolbarSettingsScreen.includes('buildSplitSceneChip') &&
  toolbarSettingsScreen.includes('openSplitSlotSheet'),
  'Split toolbar settings must preview the split bottom bar and open a slot sheet from it.');
assertContract(splitChrome.includes('onButtonTap') &&
  splitChrome.includes('BrowserSplitToolbarButtonRow') &&
  shellPage.includes('handleSplitToolbarButton') &&
  shellPage.includes('resolveSplitToolbarButtons'),
  'The live split bottom bar must render the saved buttons and dispatch their actions.');
assertContract(!personalizationSyncSnapshot.includes('splitHomeLeadingTapActionId'),
  'Split bottom-bar slots stay on the device, like the floating slot gestures.');

const ts = require(process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js');
const vm = require('node:vm');
const assert = require('node:assert/strict');

function loadEts(relative, requireDependency) {
  const filename = path.join(repoRoot, relative);
  const compiled = ts.transpileModule(fs.readFileSync(filename, 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 },
    fileName: filename,
    reportDiagnostics: true
  });
  const errors = (compiled.diagnostics || []).filter(item => item.category === ts.DiagnosticCategory.Error);
  assert.equal(errors.length, 0, `Transpile errors in ${relative}`);
  const module = { exports: {} };
  vm.runInNewContext(compiled.outputText, {
    module,
    exports: module.exports,
    require: requireDependency
  }, { filename });
  return module.exports;
}

const policyExports = loadEts(
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserSplitToolbarCustomizationPolicy.ets',
  (name) => {
    throw new Error(`Split toolbar policy must not import ${name}`);
  });
let cases = 0;
const suite = loadEts(
  'AiraBrowser/entry/src/test/BrowserSplitToolbarCustomizationPolicy.test.ets',
  (name) => {
    if (name === '@ohos/hypium') {
      return {
        describe: (_name, body) => body(),
        it: (name, _flags, body) => {
          try {
            body();
            cases += 1;
          } catch (error) {
            throw new Error(name, { cause: error });
          }
        },
        expect: (value) => ({
          assertEqual: (expected) => assert.equal(value, expected),
          assertTrue: () => assert.equal(value, true),
          assertFalse: () => assert.equal(value, false)
        })
      };
    }
    if (name.endsWith('BrowserSplitToolbarCustomizationPolicy')) {
      return policyExports;
    }
    throw new Error(`Unexpected test import ${name}`);
  });
suite.default();
assert.equal(cases, 3, 'Split toolbar policy tests must all run.');

console.log('Bottom toolbar system Sheet contract passed.');
