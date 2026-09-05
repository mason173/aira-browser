const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repoRoot = path.resolve(__dirname, '..');
const typescriptPath = process.env.DEVECO_TYPESCRIPT_PATH ||
  '/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript/lib/typescript.js';
if (!fs.existsSync(typescriptPath)) {
  throw new Error(`DevEco TypeScript runtime not found: ${typescriptPath}`);
}
const ts = require(typescriptPath);

const panelPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserDetentBottomPanel.ets'
);
const addressPanelPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomAddressPanel.ets'
);
const homeContentPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/HomeContentSections.ets'
);
const shellPagePath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/pages/BrowserShellPage.ets'
);
const expandedScrimPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserRootBottomPanelExpandedScrim.ets'
);
const rootBottomPanelSessionPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserRootBottomPanelSessionCoordinator.ets'
);
const searchBackdropPresentationChannelPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserSearchBackdropPresentationChannel.ets'
);
const shellRouteCoordinatorPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserShellRouteCoordinator.ets'
);
const actionPresentationPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelActionPresentationCoordinator.ets'
);
const offlineViewerPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/offline/OfflinePageViewerScreen.ets'
);
const tabHomePath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserTabHomeCoordinator.ets'
);
const scrollCoordinatorPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomChromeScrollCoordinator.ets'
);
const homeCoordinatorPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeChromeScrollCoordinator.ets'
);
const oldHomeViewModelPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeScrollChromeViewModel.ets'
);
const homeSurfaceProfilePath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserHomeSurfaceProfileViewModel.ets'
);
const toolbarExpansionPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomToolbarExpansionViewModel.ets'
);
const bottomPanelMotionTokensPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomPanelMotionTokens.ets'
);
const chromePresentationPath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomChromePresentationViewModel.ets'
);

function transpileCommonJs(sourcePath) {
  const source = fs.readFileSync(sourcePath, 'utf8');
  return ts.transpileModule(source, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2020
    },
    fileName: sourcePath
  }).outputText;
}

function evaluateCommonJs(sourcePath, requireModule) {
  const module = { exports: {} };
  vm.runInNewContext(transpileCommonJs(sourcePath), {
    module,
    exports: module.exports,
    require: requireModule,
    Date,
    Math,
    Number,
    String,
    Object,
    Array,
    Map,
    Set
  }, { filename: sourcePath });
  return module.exports;
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function buildCustomHomepageState(kind, hideToolbarOnScroll, showSystemSearchBar = true) {
  return {
    kind,
    shouldRenderCustomHtml: kind === 'custom_web',
    webUrl: kind === 'custom_web' ? 'https://home.example/' : '',
    isRemoteUrlHomepage: kind === 'custom_web',
    shouldForceDarkWebContent: false,
    showSystemEntryButton: false,
    showSystemSearchBar,
    hideToolbarOnScroll,
    unavailableTitle: '',
    unavailableMessage: ''
  };
}

const scrollModule = evaluateCommonJs(scrollCoordinatorPath, () => ({}));
const homeModule = evaluateCommonJs(homeCoordinatorPath, (request) => {
  if (request === './BrowserBottomChromeScrollCoordinator') {
    return scrollModule;
  }
  return {};
});
const profileModule = evaluateCommonJs(homeSurfaceProfilePath, () => ({}));

function buildProfile(customHomepageState) {
  const profileViewModel = new profileModule.BrowserHomeSurfaceProfileViewModel();
  return profileViewModel.buildProfile({
    showHomePage: true,
    webPageVisible: false,
    thirdPartyHomepageAllowed: true,
    customHomepageState,
    customHomepageWebVisible: customHomepageState.kind === 'custom_web'
  });
}

function checkPolicyOwnershipMatrix() {
  const coordinator = new homeModule.BrowserHomeChromeScrollCoordinator();
  const systemState = buildCustomHomepageState('system', false);
  const systemProfile = buildProfile(systemState);
  assert(systemProfile.scene === 'system_home', 'system profile must resolve to system_home');
  assert(coordinator.resolvePolicyMode(systemProfile, systemState, 'compact') === 'compact',
    'native system Home must ignore the third-party homepage scroll switch for compact');
  assert(coordinator.resolvePolicyMode(systemProfile, systemState, 'hidden') === 'hidden',
    'native system Home must ignore the third-party homepage scroll switch for hidden');
  assert(coordinator.resolvePolicyMode(systemProfile, systemState, 'fixed') === 'fixed',
    'native system Home must honor the global fixed behavior');

  const thirdPartyDisabled = buildCustomHomepageState('custom_web', false);
  const thirdPartyDisabledProfile = buildProfile(thirdPartyDisabled);
  assert(thirdPartyDisabledProfile.scene === 'third_party_home',
    'custom profile must resolve to third_party_home');
  assert(coordinator.resolvePolicyMode(thirdPartyDisabledProfile, thirdPartyDisabled, 'hidden') === 'fixed',
    'third-party Home must remain fixed when its own scroll switch is disabled');

  const thirdPartyEnabled = buildCustomHomepageState('custom_web', true);
  const thirdPartyEnabledProfile = buildProfile(thirdPartyEnabled);
  assert(coordinator.resolvePolicyMode(thirdPartyEnabledProfile, thirdPartyEnabled, 'compact') === 'compact',
    'third-party Home must honor compact when its own scroll switch is enabled');
  assert(coordinator.resolvePolicyMode(thirdPartyEnabledProfile, thirdPartyEnabled, 'hidden') === 'hidden',
    'third-party Home must honor hidden when its own scroll switch is enabled');

  const searchHiddenState = buildCustomHomepageState('system', false, false);
  const searchHiddenProfile = buildProfile(searchHiddenState);
  assert(coordinator.resolvePolicyMode(searchHiddenProfile, searchHiddenState, 'hidden') === 'inactive',
    'Home chrome scroll must be inactive when the system search surface is absent');
}

function buildInteraction() {
  return {
    showTabsSheet: false,
    addressFocused: false,
    currentDetent: 'low',
    documentViewerActive: false,
    webVideoControllerActive: false,
    webAppImmersiveMode: false,
    fullScreenModeEnabled: false
  };
}

function resolveSystemPresentation(behavior, samples) {
  const coordinator = new homeModule.BrowserHomeChromeScrollCoordinator();
  const customHomepageState = buildCustomHomepageState('system', false);
  const profile = buildProfile(customHomepageState);
  let currentPresentation = 'resting';
  for (const sample of samples) {
    const decision = coordinator.handleScrollEvent({
      profile,
      customHomepageState,
      interaction: buildInteraction(),
      currentPresentation,
      scrollBehavior: behavior
    }, {
      type: 'move',
      source: 'system',
      scrollOffsetY: sample.offset,
      nativeAtEnd: sample.isAtEnd
    }, sample.now);
    if (decision !== undefined) {
      currentPresentation = decision.presentation;
    }
  }
  coordinator.handleScrollEvent({
    profile,
    customHomepageState,
    interaction: buildInteraction(),
    currentPresentation,
    scrollBehavior: behavior
  }, { type: 'stop', source: 'system' });
  return currentPresentation;
}

function checkNativeScrollBehavior() {
  const upwardSamples = [
    { offset: 0, isAtEnd: false, now: 0 },
    { offset: 16, isAtEnd: false, now: 1000 },
    { offset: 40, isAtEnd: false, now: 1001 }
  ];
  const revealSamples = upwardSamples.concat([
    { offset: 20, isAtEnd: false, now: 1300 },
    { offset: 8, isAtEnd: false, now: 1301 }
  ]);
  assert(resolveSystemPresentation('compact', upwardSamples) === 'compact',
    'native system Home upward movement must compact the bottom chrome');
  assert(resolveSystemPresentation('hidden', upwardSamples) === 'hidden',
    'native system Home upward movement must hide the bottom chrome');
  assert(resolveSystemPresentation('fixed', upwardSamples) === 'resting',
    'native system Home fixed behavior must remain resting');
  assert(resolveSystemPresentation('hidden', revealSamples) === 'resting',
    'native system Home downward movement must restore the bottom chrome');
}

function checkRawAdapterAndOwnerSeam() {
  const homeContentSource = fs.readFileSync(homeContentPath, 'utf8');
  const surfaceProfileSource = fs.readFileSync(homeSurfaceProfilePath, 'utf8');
  const shellPageSource = fs.readFileSync(shellPagePath, 'utf8');
  const tabHomeSource = fs.readFileSync(tabHomePath, 'utf8');
  assert(homeContentSource.includes('.onDidScroll(') &&
    homeContentSource.includes('this.homeContentScroller.currentOffset().yOffset') &&
    homeContentSource.includes('scrollAtEnd: this.homeContentScroller.isAtEnd()'),
  'native Home content must forward raw offset/end samples');
  assert(homeContentSource.includes("type: 'scroll_stop'"),
    'native Home content must forward native scroll-stop events');
  assert(!homeContentSource.includes('BrowserHomeChromeScrollCoordinator') &&
    !homeContentSource.includes('resolveNativeHomeScrollOffset'),
  'native Home content must not own chrome-scroll policy or bounce state');
  assert(!surfaceProfileSource.includes('homeScrollHideAllowed') &&
    !surfaceProfileSource.includes('hideToolbarOnScroll') &&
    !surfaceProfileSource.includes('buildSystemChromePolicy'),
  'Home Surface Profile must remain presentation-only');
  assert(!shellPageSource.includes('homeScrollHideAllowed') &&
    !shellPageSource.includes('homeSearchEligible'),
  'BrowserShellPage must not compose Home chrome-scroll policy booleans');
  assert(tabHomeSource.includes('private readonly homeChromeScrollCoordinator: BrowserHomeChromeScrollCoordinator'),
    'Tab Home must own one Home Chrome Scroll coordinator');
  assert(!fs.existsSync(oldHomeViewModelPath),
    'the shallow BrowserHomeScrollChromeViewModel must stay deleted');
}

function checkCollapsedOverlayPanOwnership() {
  const source = fs.readFileSync(panelPath, 'utf8');
  const start = source.indexOf('private buildFloatingOverlay()');
  const end = source.indexOf('private buildFloatingOverlayTopSurface()', start);
  assert(start >= 0 && end > start, 'cannot isolate buildFloatingOverlay');
  const body = source.slice(start, end);
  assert(
    body.includes('direction: this.floatingOverlayPanEnabled ? PanDirection.Vertical : PanDirection.None'),
    'collapsed/low toolbar must not mount a vertical whole-screen recognizer over native Home'
  );
}

function checkHiddenFloatingHeaderHitTesting() {
  const source = fs.readFileSync(panelPath, 'utf8');
  const start = source.indexOf('private buildFloatingOverlayHeaderSurface()');
  const end = source.indexOf('private buildFloatingOverlayHeaderMaterialBackground()', start);
  assert(start >= 0 && end > start, 'cannot isolate floating header hit testing');
  const body = source.slice(start, end).replace(/\s+/g, ' ');
  assert(
    body.includes(
      '.hitTestBehavior(this.shouldEnableFloatingHeaderInteraction() ? HitTestMode.BLOCK_HIERARCHY : ' +
        'HitTestMode.BLOCK_DESCENDANTS)'
    ),
    'hidden floating Search must disable its complete interactive descendant subtree'
  );
}

function buildChromePresentationFacts(currentDetent) {
  return {
    scene: 'web',
    addressFocused: false,
    addressEditable: true,
    currentDetent,
    scrollPresentation: 'resting',
    returnHomeDrag: false,
    returnHomeProgress: 0,
    panelWidth: 360,
    expandedChromeWidth: 340,
    panelExpansionEnabled: true,
    addressInput: '',
    addressDisplayText: 'example.com',
    placeholder: '搜索或输入网址',
    toolbarSlotActions: [],
    leadingHeaderActions: [{ id: 'back', title: '后退', enabled: true }],
    trailingHeaderActions: [
      { id: 'reload', title: '刷新', enabled: true },
      { id: 'tabs', title: '标签页', enabled: true }
    ]
  };
}

function checkFixedSearchAnchorAndStableGeometry() {
  const panelSource = fs.readFileSync(panelPath, 'utf8');
  const addressPanelSource = fs.readFileSync(addressPanelPath, 'utf8');
  const shellPageSource = fs.readFileSync(shellPagePath, 'utf8');
  const rootBottomPanelSessionSource = fs.readFileSync(rootBottomPanelSessionPath, 'utf8');
  const expansionSource = fs.readFileSync(toolbarExpansionPath, 'utf8');
  const motionTokensSource = fs.readFileSync(bottomPanelMotionTokensPath, 'utf8');
  const transitionStart = expansionSource.indexOf('export interface BrowserBottomToolbarSurfaceTransitionState');
  const transitionEnd = expansionSource.indexOf(
    'export interface BrowserBottomToolbarQuickActionLayoutInput',
    transitionStart
  );
  assert(transitionStart >= 0 && transitionEnd > transitionStart,
    'cannot isolate toolbar surface transition contract');
  const transitionContract = expansionSource.slice(transitionStart, transitionEnd);
  assert(!transitionContract.includes('searchExitProgress') &&
    !addressPanelSource.includes('floatingHeaderExpandedExitProgress:') &&
    !panelSource.includes('floatingHeaderExpandedExitProgress') &&
    !panelSource.includes('resolveFloatingHeaderExpandedExitTranslateY'),
  'fixed floating Search must not add a progress-driven exit translation');
  assert(panelSource.includes('private shouldAnchorFloatingHeaderToBottom(): boolean') &&
    panelSource.includes('private resolveFixedFloatingHeaderGlobalTop(): number') &&
    panelSource.includes('private resolveFloatingPanelMotionGlobalTop(): number') &&
    panelSource.includes('private buildFloatingOverlayPanelMotionProbe()'),
  'tool expansion must split the fixed bottom Search anchor from the panel motion anchor');
  const fixedHeaderAnchorStart = panelSource.indexOf('private shouldAnchorFloatingHeaderToBottom(): boolean');
  const fixedHeaderAnchorEnd = panelSource.indexOf(
    'private resolveFixedFloatingHeaderGlobalTop(): number',
    fixedHeaderAnchorStart
  );
  assert(fixedHeaderAnchorStart >= 0 && fixedHeaderAnchorEnd > fixedHeaderAnchorStart &&
    panelSource.slice(fixedHeaderAnchorStart, fixedHeaderAnchorEnd)
      .includes('this.getPanelHeight() >= this.getOverlayLowPanelHeight()'),
  'downward low-to-peek Search dismissal must leave the fixed expansion anchor and track panel height');
  assert(panelSource.includes('@Prop floatingHeaderTracksPanelMotion: boolean = false;') &&
    panelSource.includes('!this.floatingHeaderTracksPanelMotion;') &&
    addressPanelSource.includes('@State private floatingHeaderTracksPanelMotion: boolean = false;') &&
    addressPanelSource.includes('floatingHeaderTracksPanelMotion: this.floatingHeaderTracksPanelMotion') &&
    addressPanelSource.includes("this.activeChromeGestureSource === 'leading-outer'") &&
    addressPanelSource.includes("this.activeChromeGestureSource === 'trailing-outer'") &&
    addressPanelSource.includes('this.floatingHeaderTracksPanelMotion = false;'),
  'edge return-home gesture must keep the floating Header on the finger-tracked panel anchor until settle');
  const expandedSurfaceStart = panelSource.indexOf('private resolveFloatingExpandedSurfaceGlobalTop(): number');
  const expandedSurfaceEnd = panelSource.indexOf(
    'private resolveFloatingExpandedSurfaceCoverProgress(): number',
    expandedSurfaceStart
  );
  assert(expandedSurfaceStart >= 0 && expandedSurfaceEnd > expandedSurfaceStart &&
    panelSource.slice(expandedSurfaceStart, expandedSurfaceEnd)
      .includes('return this.resolveFloatingPanelMotionGlobalTop() +'),
  'expanded tool surface must remain finger-tracked independently of the fixed bottom Search');
  assert(motionTokensSource.includes('BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_DURATION_MS: number = 110') &&
    motionTokensSource.includes('BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_BARRIER_MS') &&
    addressPanelSource.includes('private beginFloatingActionContentExit(completion?: () => void): void') &&
    addressPanelSource.includes('!this.floatingActionContentExitActive') &&
    addressPanelSource.includes('this.beginFloatingActionContentExit((): void => {') &&
    panelSource.includes('private shouldHoldFloatingCollapseMotionForContentExit(offsetY: number): boolean') &&
    panelSource.includes('private deferFloatingCollapseUntilContentExit(): void') &&
    panelSource.includes('private resumeDeferredFloatingCollapseAfterContentExit(): void'),
  'toolbar collapse must finish the fixed button exit before panel and backdrop blur collapse');
  assert(panelSource.includes('BROWSER_DETENT_FLOATING_CONTENT_ENTER_TRANSLATE_Y: number = 36') &&
    panelSource.includes('BROWSER_DETENT_FLOATING_CONTENT_ENTER_INITIAL_SCALE: number = 0.94') &&
    panelSource.includes('BROWSER_DETENT_FLOATING_CONTENT_EXIT_TRANSLATE_Y: number = 8') &&
    panelSource.includes('BROWSER_DETENT_FLOATING_CONTENT_ENTER_CURVE: ICurve = curves.springMotion(0.42, 0.62)') &&
    panelSource.includes('.animation({ curve: BROWSER_DETENT_FLOATING_CONTENT_ENTER_CURVE })') &&
    panelSource.includes('x: BROWSER_DETENT_FLOATING_CONTENT_ENTER_INITIAL_SCALE') &&
    panelSource.includes("centerY: '100%'") &&
    panelSource.includes('.combine(TransitionEffect.opacity(0).animation({'),
  'toolbar quick actions must enter as one translated/scaled spring group with monotonic opacity');
  assert(addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_TRANSLATE_Y: number = 10') &&
    addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_STAGGER_MS: number = 45') &&
    addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_MAX_DELAY_MS: number = 90') &&
    addressPanelSource.includes('this.resolveQuickActionEntryRowIndex(index, layoutState.columnCount)') &&
    addressPanelSource.includes('delay: this.resolveQuickActionRowEntryDelayMs(rowIndex)') &&
    addressPanelSource.includes('TransitionEffect.IDENTITY') &&
    addressPanelSource.includes(
      'private resolveQuickActionRowEntryTransition(rowIndex: number): TransitionEffect'
    ) &&
    addressPanelSource.includes(
      'private resolveQuickActionEntryRowIndex(index: number, columnCount: number): number'
    ) &&
    addressPanelSource.includes('private resolveQuickActionRowEntryDelayMs(rowIndex: number): number') &&
    !addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ENTRY_INITIAL_SCALE') &&
    !addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ENTRY_SCALE_CURVE'),
  'toolbar quick actions must stagger entry translation by row without per-button scale or staggered exit');
  const quickActionGridStart = addressPanelSource.indexOf('private buildQuickActionGrid(');
  const quickActionGridEnd = addressPanelSource.indexOf(
    'private buildFloatingSuggestionContent()',
    quickActionGridStart
  );
  const quickActionCardStart = addressPanelSource.indexOf('private buildQuickActionCard(');
  const quickActionCardEnd = addressPanelSource.indexOf(
    'private resolveQuickActionRowEntryTransition(',
    quickActionCardStart
  );
  const quickActionGridSource = addressPanelSource.slice(quickActionGridStart, quickActionGridEnd);
  const quickActionCardSource = addressPanelSource.slice(quickActionCardStart, quickActionCardEnd);
  assert(quickActionGridStart >= 0 && quickActionGridEnd > quickActionGridStart &&
    quickActionCardStart >= 0 && quickActionCardEnd > quickActionCardStart &&
    !quickActionCardSource.includes('.transition(this.resolveQuickActionRowEntryTransition(') &&
    (quickActionGridSource.match(/\.transition\(this\.resolveQuickActionRowEntryTransition\(/g) || []).length === 2,
  'volatile Web action render keys must not own quick-action row entry motion');
  assert(
    addressPanelSource.includes('@State private floatingActionContentEntryActive: boolean = false;') &&
    addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_BARRIER_MS: number =') &&
    addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_DURATION_MS +') &&
    addressPanelSource.includes('WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_MAX_DELAY_MS;') &&
    addressPanelSource.includes('private beginFloatingActionContentEntry(): void') &&
    addressPanelSource.includes('this.floatingActionContentEntryActive = false;') &&
    addressPanelSource.includes('}, WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_BARRIER_MS);') &&
    addressPanelSource.includes('if (!this.floatingActionContentEntryActive || rowIndex < 0)') &&
    addressPanelSource.includes('this.beginFloatingActionContentEntry();') &&
    addressPanelSource.includes('this.clearFloatingActionContentEntry();'),
  'settled adaptive-foreground refreshes must not replay quick-action row entry motion');
  const editingStateDispatchStart = addressPanelSource.indexOf(
    'private shouldDispatchHeaderActionWithoutEditingStateChange(actionId: string): boolean'
  );
  const editingStateDispatchEnd = addressPanelSource.indexOf(
    'private dispatchReliableHeaderAction(',
    editingStateDispatchStart
  );
  const actionTapStart = rootBottomPanelSessionSource.indexOf('handleActionTap(');
  const actionTapEnd = rootBottomPanelSessionSource.indexOf(
    'private executeActionDispatch(',
    actionTapStart
  );
  const actionTapSource = rootBottomPanelSessionSource.slice(actionTapStart, actionTapEnd);
  const headerActionStart = shellPageSource.indexOf('onHeaderAction: (actionId: string)');
  const headerActionEnd = shellPageSource.indexOf('onOpenSuggestion:', headerActionStart);
  const executeActionStart = rootBottomPanelSessionSource.indexOf('private executeActionDispatch(');
  const executeActionEnd = rootBottomPanelSessionSource.indexOf('handlePanelSettled(', executeActionStart);
  const executeActionSource = rootBottomPanelSessionSource.slice(executeActionStart, executeActionEnd);
  const chromePlanExecutionStart = shellPageSource.indexOf(
    'private applyRootBottomPanelSessionChromePlan(plan: BrowserRootBottomPanelChromePlan): void'
  );
  const chromePlanExecutionEnd = shellPageSource.indexOf(
    'private applyRootBottomPanelSessionDetentPlan(',
    chromePlanExecutionStart
  );
  const chromePlanExecutionSource = shellPageSource.slice(chromePlanExecutionStart, chromePlanExecutionEnd);
  assert(editingStateDispatchStart >= 0 && editingStateDispatchEnd > editingStateDispatchStart &&
    addressPanelSource.slice(editingStateDispatchStart, editingStateDispatchEnd)
      .includes("actionId === 'copyLink'") &&
    headerActionStart >= 0 && headerActionEnd > headerActionStart &&
    !shellPageSource.slice(headerActionStart, headerActionEnd)
      .includes('BrowserSearchInvocationRuntime.endCurrent') &&
    actionTapStart >= 0 && actionTapEnd > actionTapStart &&
    actionTapSource.indexOf("this.settleSearchBackdropToDetent('low')") >= 0 &&
    actionTapSource.indexOf("this.settleSearchBackdropToDetent('low')") <
    actionTapSource.indexOf('this.sink.applyChromePlan(plan.chromePlan)') &&
    executeActionStart >= 0 && executeActionEnd > executeActionStart &&
    executeActionSource.indexOf('completionPlan.shouldEndSearchInvocationForAction = true') >= 0 &&
    executeActionSource.indexOf('this.sink.applyChromePlan(completionPlan)') <
      executeActionSource.indexOf('this.resolveActionApplication().apply') &&
    chromePlanExecutionStart >= 0 && chromePlanExecutionEnd > chromePlanExecutionStart &&
    chromePlanExecutionSource.includes('if (plan.shouldEndSearchInvocationForAction)') &&
    chromePlanExecutionSource.includes(
      "BrowserSearchInvocationRuntime.endCurrent(this.getWindowScopeId(), 'other_surface_selected')"
    ),
  'address-input Copy must delegate focus exit until the root owner starts backdrop collapse');

  class SearchEnginePresentation {
    constructor(selectedSearchEngine, searchEngines, placeholder) {
      this.selectedSearchEngine = selectedSearchEngine;
      this.searchEngines = searchEngines;
      this.placeholder = placeholder;
    }
  }
  const chromeModule = evaluateCommonJs(chromePresentationPath, (request) => {
    if (request === './BrowserBottomAddressPanelMetrics') {
      return { BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING: 10 };
    }
    if (request === './BrowserBottomPanelMotionTokens') {
      return {
        BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS: 220,
        BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS: 180,
        resolveBrowserBottomPanelMiddleSnapCurve: () => ({}),
        resolveBrowserBottomPanelMotionCurve: () => ({})
      };
    }
    if (request === './BrowserSearchEnginePresentationViewModel') {
      return { BrowserSearchEngineChromePresentation: SearchEnginePresentation };
    }
    return {};
  });
  const viewModel = new chromeModule.BrowserBottomChromePresentationViewModel();
  const resting = viewModel.buildPresentation(buildChromePresentationFacts('low'));
  const tools = viewModel.buildPresentation(buildChromePresentationFacts('middle'));
  for (const key of [
    'leadingOuterWidth',
    'leadingGap',
    'centerWidth',
    'trailingGap',
    'trailingOuterWidth',
    'outerOpacity'
  ]) {
    assert(resting.frame[key] === tools.frame[key],
      `floating Search geometry changed during tool expansion: ${key}`);
  }
  assert(tools.leadingOuterTarget.enabled === resting.leadingOuterTarget.enabled &&
    tools.trailingOuterTarget.enabled === resting.trailingOuterTarget.enabled,
  'floating Search side-button semantics changed during tool expansion');
}

function checkExpansionHintContract() {
  const panelSource = fs.readFileSync(addressPanelPath, 'utf8');
  const expansionModule = evaluateCommonJs(toolbarExpansionPath, () => ({}));
  const viewModel = new expansionModule.BrowserBottomToolbarExpansionViewModel();
  assert(viewModel.shouldShowExpansionHint(true),
    'three-row preview must expose the second-swipe expansion hint when full expansion is available');
  assert(!viewModel.shouldShowExpansionHint(false),
    'toolbar expansion hint must disappear when no second stage is available');
  assert(viewModel.resolveExpansionHintRotationAngle('preview', true) === 0 &&
    viewModel.resolveExpansionHintRotationAngle('full', true) === 180,
  'toolbar expansion hint must point up in preview and down when fully expanded');
  assert(panelSource.includes("'browser.toolbar.expandHint'") &&
    panelSource.includes('layoutState.expansionHintSlotHeight') &&
    panelSource.includes('.justifyContent(FlexAlign.Center)') &&
    panelSource.includes('.rotate({ angle: this.resolveToolbarExpansionHintRotationAngle() })') &&
    panelSource.includes('WEB_BOTTOM_TOOLBAR_EXPANSION_HINT_ROTATION_DURATION_MS') &&
    panelSource.includes('expansionHintSlotHeight: BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_SIZE') &&
    panelSource.includes('expansionHintBottomGap: BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_BOTTOM_GAP'),
  'toolbar must render one centered font-backed hint with stable geometry and animated direction');
}

function checkToolbarResponsiveGridContract() {
  const panelSource = fs.readFileSync(addressPanelPath, 'utf8');
  const metricsSource = fs.readFileSync(
    path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/core/browser/BrowserBottomAddressPanelMetrics.ets'),
    'utf8'
  );
  const expansionModule = evaluateCommonJs(toolbarExpansionPath, () => ({}));
  const viewModel = new expansionModule.BrowserBottomToolbarExpansionViewModel();
  const api23Layout = viewModel.resolveQuickActionLayout({
    actionCount: 29,
    availableWidth: 320,
    availableHeight: 488,
    preferredColumns: 4,
    maxColumns: 8,
    buttonSize: 64,
    labelBlockHeight: 18,
    columnGap: 12,
    rowGap: 18,
    groupHorizontalPadding: 12,
    groupVerticalPadding: 12,
    surfaceVerticalPadding: 12,
    expansionHintSlotHeight: 22,
    expansionHintBottomGap: 4
  });
  const phoneLayout = viewModel.resolveQuickActionLayout({
    actionCount: 29,
    availableWidth: 390,
    availableHeight: 540,
    preferredColumns: 4,
    maxColumns: 8,
    buttonSize: 64,
    labelBlockHeight: 18,
    columnGap: 12,
    rowGap: 18,
    groupHorizontalPadding: 12,
    groupVerticalPadding: 12,
    surfaceVerticalPadding: 12,
    expansionHintSlotHeight: 22,
    expansionHintBottomGap: 4
  });
  assert(api23Layout.columnCount < 8 && api23Layout.buttonSize >= 48,
    'API 23 toolbar layout must not fall back to an eight-column micro-grid');
  assert(api23Layout.contentHeight <= 488.01 && phoneLayout.contentHeight <= 540.01,
    'toolbar layout must stay inside the drag-bar-adjusted available height');
  assert(metricsSource.includes(
    'BROWSER_BOTTOM_TOOLBAR_SYSTEM_SHEET_DRAG_BAR_HEIGHT: number = 16'
  ) && panelSource.includes('Math.min(hostHeight, maxPanelHeight)'),
  'toolbar layout must use the window host height rather than the current middle detent');
}

function checkUnifiedToolbarPageContract() {
  const panelSource = fs.readFileSync(addressPanelPath, 'utf8');
  const detentSource = fs.readFileSync(panelPath, 'utf8');
  const expansionModule = evaluateCommonJs(toolbarExpansionPath, () => ({}));
  const viewModel = new expansionModule.BrowserBottomToolbarExpansionViewModel();
  const layout = viewModel.resolveQuickActionLayout({
    actionCount: 29,
    availableWidth: 360,
    availableHeight: 680,
    preferredColumns: 4,
    maxColumns: 8,
    buttonSize: 56,
    labelBlockHeight: 28,
    columnGap: 12,
    rowGap: 12,
    groupHorizontalPadding: 12,
    groupVerticalPadding: 12,
    surfaceVerticalPadding: 12,
    expansionHintSlotHeight: 22,
    expansionHintBottomGap: 4
  });
  assert(layout.actionCount === 29 &&
    layout.previewSurfaceHeight > 0 &&
    layout.fullSurfaceHeight > layout.previewSurfaceHeight &&
    layout.expansionHintSlotHeight === 22,
  'toolbar layout must expose one full grid plus a three-row clip height');
  const contentStart = panelSource.indexOf('private buildFloatingQuickActionPageContent()');
  const contentEnd = panelSource.indexOf('private buildQuickActionGrid(', contentStart);
  const content = panelSource.slice(contentStart, contentEnd);
  assert(!panelSource.includes('buildFloatingQuickActionStageLayer') &&
    contentStart >= 0 && contentEnd > contentStart &&
    (content.match(/this\.buildQuickActionGrid\(/g) || []).length === 1 &&
    content.includes('this.resolveToolbarRenderSnapshot()') &&
    content.includes('this.resolveToolbarRenderSnapshot().actions') &&
    content.includes('this.resolveToolbarRenderSnapshot().layoutRenderKey') &&
    !content.includes('.slice(') &&
    !panelSource.includes('resolveStagePresentation') &&
    !panelSource.includes('previewOpacity') &&
    !panelSource.includes('fullOpacity'),
  'toolbar must render one complete clipped page without preview/full crossfade layers');
  assert(content.includes('layoutState.expansionHintSlotHeight') &&
    content.includes('this.shouldShowToolbarExpansionHint()'),
  'toolbar expansion hint must reserve one stable slot in the unified page');
  const expandedSurfaceStart = detentSource.indexOf('private buildFloatingOverlayExpandedSurface()');
  const expandedSurfaceEnd = detentSource.indexOf('private buildFloatingTopContentRenderKey()', expandedSurfaceStart);
  const expandedSurfaceSource = detentSource.slice(expandedSurfaceStart, expandedSurfaceEnd);
  assert(expandedSurfaceStart >= 0 && expandedSurfaceEnd > expandedSurfaceStart &&
    expandedSurfaceSource.includes('.height(this.resolveFloatingExpandedSurfaceHeight())') &&
    expandedSurfaceSource.includes('.clip(true)') &&
    !expandedSurfaceSource.includes('.onAreaChange(') &&
    !detentSource.includes('onFloatingExpandedVisualHeightChange') &&
    !panelSource.includes('toolbarStagePresentationHeight'),
  'expanded toolbar outer height and clip must be the only preview/full presentation mechanism');
  assert(panelSource.includes('floatingExpandedContentPrepared: this.shouldPrepareFloatingActionSurface()') &&
    panelSource.includes("this.activeChromeGestureSource === 'center-capsule'") &&
    panelSource.includes('return this.floatingActionSurfacePrepared || this.shouldMountFloatingActionSurface();') &&
    detentSource.includes('if (this.shouldPrepareFloatingExpandedContent())') &&
    detentSource.includes('this.shouldShowFloatingExpandedContent() ? HitTestMode.Transparent : HitTestMode.None'),
  'the one complete toolbar tree must prepare only for its gesture session and stay non-interactive while hidden');
  assert(panelSource.includes('nextDetent !== previousDetent || this.panelDragHeight <= 0'),
    'same-detent preview/full release must not overwrite the current visual height with the target height');
}

function checkToolbarGestureFrameContract() {
  const detentSource = fs.readFileSync(panelPath, 'utf8');
  const addressPanelSource = fs.readFileSync(addressPanelPath, 'utf8');
  const shellPageSource = fs.readFileSync(shellPagePath, 'utf8');
  const expandedScrimSource = fs.readFileSync(expandedScrimPath, 'utf8');
  const rootBottomPanelSessionSource = fs.readFileSync(rootBottomPanelSessionPath, 'utf8');
  const actionPresentationSource = fs.readFileSync(actionPresentationPath, 'utf8');
  const offlineViewerSource = fs.readFileSync(offlineViewerPath, 'utf8');
  assert(detentSource.includes('export interface BrowserDetentBottomPanelGestureFrame') &&
    (detentSource.match(/this\.onPanelGestureFrame\(/g) || []).length === 2 &&
    !detentSource.includes('onPanelGestureStartDetail') &&
    !detentSource.includes('onPanelGestureUpdateDetail'),
  'Detent drag start/update must publish one typed frame through one callback seam');
  assert(addressPanelSource.includes('export interface BrowserBottomAddressPanelGestureFrame') &&
    addressPanelSource.includes('activeChromeGestureMiddlePanelHeight') &&
    !addressPanelSource.includes('onPanelDragStartDetail') &&
    !addressPanelSource.includes('onPanelDragUpdateDetail'),
  'Bottom Address Panel must resolve one higher-level gesture frame and stable middle target');
  assert(/import\s*\{[^}]*\bFrameCallback\b[^}]*\}\s*from '@kit\.ArkUI';/s.test(detentSource) &&
    detentSource.includes('postFrameCallback(new BrowserDetentBottomPanelFrameCallback') &&
    detentSource.includes('private pendingPanelDragOffsetY: number | undefined') &&
    detentSource.includes('this.flushPendingPanelDragFrame(offsetY);') &&
    detentSource.includes('this.flushPendingPanelDragFrame();') &&
    detentSource.includes('this.invalidatePendingPanelDragFrame();') &&
    !detentSource.includes('DisplaySync'),
  'raw Pan updates must use one-shot latest-frame VSYNC commits with synchronous release/lifecycle invalidation');
  assert(addressPanelSource.includes('private toolbarOrderRevision: number') &&
    addressPanelSource.includes('private toolbarMotionLayoutRevision: number') &&
    addressPanelSource.includes('private toolbarPresentationRevision: number') &&
    addressPanelSource.includes('snapshot.liveActionRevision === liveActionRevision') &&
    addressPanelSource.includes('snapshot.layoutRevision === this.toolbarLayoutRevision') &&
    !addressPanelSource.includes('buildToolbarRenderSnapshotInputKey') &&
    !addressPanelSource.includes('toolbarRenderSnapshotInputKey') &&
    actionPresentationSource.includes('revision: this.snapshotRevision') &&
    offlineViewerSource.includes('toolbarActionRevision: this.offlineToolbarActionRevision') &&
    offlineViewerSource.includes('toolbarLayoutRevision: this.offlineToolbarLayoutRevision'),
  'toolbar render snapshots must invalidate through explicit action/order/layout/presentation revisions');
  assert(!shellPageSource.includes('@State searchBackdropProgress') &&
    !shellPageSource.includes('browserSearchBackdropPresentationViewModel'),
  'BrowserShellPage must not own live Search Backdrop progress or its presentation ViewModel');
  assert(expandedScrimSource.includes(".width(this.shouldBlockHitTest() ? '100%' : 0)") &&
    expandedScrimSource.includes(".height(this.shouldBlockHitTest() ? '100%' : 0)") &&
    expandedScrimSource.includes('HitTestMode.BLOCK_HIERARCHY : HitTestMode.None') &&
    rootBottomPanelSessionSource.includes('input.bottomPanelHostVisible'),
  'inactive Search Backdrop hosts must collapse out of layout and hit testing behind the host visibility gate');
}

function checkRoutedToolbarBackdropContract() {
  const routeSource = fs.readFileSync(shellRouteCoordinatorPath, 'utf8');
  const shellPageSource = fs.readFileSync(shellPagePath, 'utf8');
  const expandedScrimSource = fs.readFileSync(expandedScrimPath, 'utf8');
  const rootBottomPanelSessionSource = fs.readFileSync(rootBottomPanelSessionPath, 'utf8');
  const presentationChannelSource = fs.readFileSync(searchBackdropPresentationChannelPath, 'utf8');
  const pushRouteStart = routeSource.indexOf('private pushRoute(');
  const pushRouteSource = routeSource.slice(pushRouteStart);
  const routeResetIndex = pushRouteSource.indexOf('this.host.resetTransientOverlayStateForRouteTransition();');
  const routerPushIndex = pushRouteSource.indexOf('router.pushUrl({');
  assert(pushRouteStart >= 0 && routeResetIndex >= 0 && routerPushIndex > routeResetIndex,
    'routed toolbar actions must synchronously clear transient presentation before router.pushUrl');
  assert(rootBottomPanelSessionSource.includes('resetForRouteTransitionPresentation(') &&
    rootBottomPanelSessionSource.includes('this.searchBackdropPresentationChannel.publishRouteTransitionSuppression();') &&
    rootBottomPanelSessionSource.includes('this.resetTransientSheetPresentation(preservedOwners);') &&
    shellPageSource.includes('.resetForRouteTransitionPresentation(preservedCustomBottomSurfaceIds);'),
  'route transition cleanup must synchronously invalidate the Root Bottom-Panel backdrop channel in its owner');
  assert(routeSource.includes("import { FrameCallback, UIContext } from '@kit.ArkUI';") &&
    routeSource.includes('class BrowserShellRouteIdleCallback extends FrameCallback') &&
    routeSource.includes('onIdle(_timeLeftInNano: number): void') &&
    routeSource.includes('private routeTransitionRunId: number = 0;') &&
    routeSource.includes('this.dependencies.resolveUIContext().postFrameCallback(') &&
    routeSource.includes('if (runId !== this.routeTransitionRunId)') &&
    routerPushIndex > pushRouteSource.indexOf('new BrowserShellRouteIdleCallback'),
  'router must start from a latest-request-only post-render idle callback, not in the reset UI turn');
  assert(presentationChannelSource.includes('surfaceSuppressed: boolean;') &&
    presentationChannelSource.includes('publishRouteTransitionSuppression(): void') &&
    expandedScrimSource.includes('@State private surfaceSuppressed: boolean = false;') &&
    expandedScrimSource.includes('this.surfaceSuppressed = presentation.surfaceSuppressed;') &&
    expandedScrimSource.includes('if (this.surfaceSuppressed || !this.surfaceEligible)') &&
    expandedScrimSource.includes('return !this.surfaceSuppressed && this.surfaceEligible'),
  'route reset must physically unmount and collapse the glass backdrop before the post-render route barrier');
}

const checks = [
  checkPolicyOwnershipMatrix,
  checkNativeScrollBehavior,
  checkRawAdapterAndOwnerSeam,
  checkCollapsedOverlayPanOwnership,
  checkHiddenFloatingHeaderHitTesting,
  checkFixedSearchAnchorAndStableGeometry,
  checkExpansionHintContract,
  checkToolbarResponsiveGridContract,
  checkUnifiedToolbarPageContract,
  checkToolbarGestureFrameContract,
  checkRoutedToolbarBackdropContract
];
const failures = [];
for (const check of checks) {
  try {
    check();
  } catch (error) {
    failures.push(error instanceof Error ? error.message : String(error));
  }
}

if (failures.length > 0) {
  for (const failure of failures) {
    console.error(`Home Chrome Scroll contract failed: ${failure}`);
  }
  process.exit(1);
}

console.log('Home Chrome Scroll contract passed.');
