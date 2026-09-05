const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const panelPath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets');
const addressPanelPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets');
const quickActionCardPath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/HomeSearchQuickActionCard.ets');
const neutralThemePath = path.join(repoRoot,
  'AiraBrowser/entry/src/main/ets/core/theme/BrowserBottomPanelNeutralTheme.ets');
const surfaceHostPath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserShellPrimarySurfaceHost.ets');
const shellPagePath = path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets');

const panel = fs.readFileSync(panelPath, 'utf8');
const addressPanel = fs.readFileSync(addressPanelPath, 'utf8');
const normalizedAddressPanel = addressPanel.replace(/\s+/g, ' ');
const quickActionCard = fs.readFileSync(quickActionCardPath, 'utf8');
const neutralTheme = fs.readFileSync(neutralThemePath, 'utf8');
const normalizedNeutralTheme = neutralTheme.replace(/\s+/g, ' ');
const surfaceHost = fs.readFileSync(surfaceHostPath, 'utf8');
const shellPage = fs.readFileSync(shellPagePath, 'utf8');
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
assertContract(addressPanel.includes('dragBar: true') && addressPanel.includes('showClose: false'),
  'Toolbar system Sheet must use the plain system drag bar without a custom close header.');
assertContract(!toolbarSheetBinding.includes('title:') && !toolbarSheetBinding.includes('detents:') &&
  !toolbarSheetBinding.includes('systemMaterial:') && !toolbarSheetBinding.includes('onWillDismiss:'),
  'Toolbar system Sheet must not add a title, custom material, or dismissal state machine.');
assertContract(!addressPanel.includes('onDetentsDidChange:') &&
  !addressPanel.includes('toolbarSystemSheetExpanded') &&
  toolbarSheetContent.includes('this.resolveToolbarRenderSnapshot().actions') &&
  addressPanel.includes('scrollSizeMode: ScrollSizeMode.CONTINUOUS'),
  'Toolbar system Sheet must keep one stable full action list and resize it continuously between native detents.');
assertContract(toolbarSheetGrid.includes('Column({ space: layoutState.rowGap })') &&
  toolbarSheetGrid.includes('this.resolveQuickActionRowsForActions(actions, layoutState.columnCount)') &&
  !toolbarSheetGrid.includes('List(') &&
  !toolbarSheetGrid.includes('Scroll(') &&
  !toolbarSheetGrid.includes('.scrollable(') &&
  !toolbarSheetGrid.includes('.layoutWeight(1)'),
  'Toolbar system Sheet action grid must be fixed rows without an inner scroll container.');
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
assertContract(!toolbarSheetContent.includes('PanGesture') && !toolbarSheetContent.includes('.onMove('),
  'Toolbar Sheet content must contain no custom drag or reorder gestures.');
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
  "floatingHeaderPanEnabled: this.resolveFloatingLayoutMode() === 'input' || this.shouldUseThreeBlockBottomChrome()"
), 'Input and outer return-home gestures must remain enabled; center tool expansion is not a Sheet gesture.');
assertContract(!surfaceHost.includes('expandedScrimHomeSurfaceVisible'),
  'Phone surface host must not force-mount Home for an expanded toolbar scrim.');
assertContract(!surfaceHost.includes('webLayerOpacity: this.expandedScrimHomeSurfaceVisible'),
  'Expanded toolbar must not hide the active Web layer.');
assertContract(!shellPage.includes('expandedScrimHomeSurfaceVisible:'),
  'Browser Shell must not pass the removed Home-forcing scrim prop.');

console.log('Bottom toolbar system Sheet contract passed.');
