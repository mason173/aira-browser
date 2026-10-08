const fs = require('fs');
const path = require('path');
const vm = require('vm');

const repoRoot = path.resolve(__dirname, '..');
const ts = require('./lib/deveco-typescript.cjs');

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
const classicHomeFramePath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/ClassicHomeFrame.ets'
);
const centeredHomeFramePath = path.join(
  repoRoot,
  'AiraBrowser/entry/src/main/ets/app/components/browser/CenteredHomeFrame.ets'
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
    // ArkTS resources resolve in the ArkUI runtime; the harness only needs the
    // resource identity plus its format arguments.
    $r: (value, ...args) => args.length > 0 ? `${value} ${args.join(' ')}` : value,
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

function assertFrameForwardsRawScroll(framePath, label) {
  const source = fs.readFileSync(framePath, 'utf8');
  assert(source.includes('.onDidScroll(') &&
    source.includes('this.scroller.currentOffset().yOffset') &&
    source.includes('scrollAtEnd: this.scroller.isAtEnd()'),
  `${label} must forward raw offset/end samples`);
  assert(source.includes("type: 'scroll_stop'"),
    `${label} must forward native scroll-stop events`);
  assert(!source.includes('BrowserHomeChromeScrollCoordinator') &&
    !source.includes('resolveNativeHomeScrollOffset'),
  `${label} must not own chrome-scroll policy or bounce state`);
}

function checkRawAdapterAndOwnerSeam() {
  const homeContentSource = fs.readFileSync(homeContentPath, 'utf8');
  const surfaceProfileSource = fs.readFileSync(homeSurfaceProfilePath, 'utf8');
  const shellPageSource = fs.readFileSync(shellPagePath, 'utf8');
  const tabHomeSource = fs.readFileSync(tabHomePath, 'utf8');
  assertFrameForwardsRawScroll(classicHomeFramePath, 'classic Home');
  assertFrameForwardsRawScroll(centeredHomeFramePath, 'centered Home');
  assert(!homeContentSource.includes('private scroller: Scroller') &&
    !homeContentSource.includes('BrowserHomeChromeScrollCoordinator') &&
    !homeContentSource.includes('resolveNativeHomeScrollOffset'),
  'native Home content host must not own a scroller or chrome-scroll policy');
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
    body.includes('.hitTestBehavior(this.shouldEnableFloatingHeaderInteraction() ?'),
    'floating header hit testing must stay keyed off the presentation-owner interaction verdict'
  );
  assert(
    body.includes('HitTestMode.BLOCK_DESCENDANTS'),
    'hidden floating Search must disable its complete interactive descendant subtree'
  );
  // Expanded chrome keeps BLOCK_HIERARCHY so the bar's taps cannot reach the page. Collapsed chrome
  // must not: that mode blocks ancestors and lower-priority siblings across the host's whole box, not
  // just its responseRegion, which left the blank space beside the collapsed capsule unable to reach
  // either the page or any control. The capsule carries the blocking for its own box instead.
  assert(
    body.includes('HitTestMode.BLOCK_HIERARCHY') &&
      body.includes('this.isCompactFloatingHeaderInteraction()') &&
      body.includes('HitTestMode.Transparent'),
    'floating header must block the page while expanded and release it while collapsed'
  );
  const rendererSource = fs.readFileSync(
    path.join(repoRoot, 'AiraBrowser/entry/src/main/ets/app/components/browser/BrowserBottomChromeRenderer.ets'),
    'utf8'
  );
  const compactStart = rendererSource.indexOf('private buildCompactTapSurface()');
  const compactEnd = rendererSource.indexOf('private buildLeadingOuterMaterial()', compactStart);
  assert(compactStart >= 0 && compactEnd > compactStart, 'cannot isolate the compact tap surface');
  assert(
    rendererSource.slice(compactStart, compactEnd).includes('HitTestMode.BLOCK_HIERARCHY : HitTestMode.None'),
    'the collapsed capsule must block the page inside its own box while the header host releases it'
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

  const chromeModule = evaluateChromePresentationModule();
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

function evaluateChromePresentationModule() {
  class SearchEnginePresentation {
    constructor(selectedSearchEngine, searchEngines, placeholder) {
      this.selectedSearchEngine = selectedSearchEngine;
      this.searchEngines = searchEngines;
      this.placeholder = placeholder;
    }
  }
  return evaluateCommonJs(chromePresentationPath, (request) => {
    if (request === './BrowserBottomAddressPanelMetrics') {
      return {
        BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING: 10,
        BROWSER_BOTTOM_ADDRESS_PANEL_PHONE_HEADER_HORIZONTAL_PADDING: 0,
        BROWSER_BOTTOM_CHROME_PHONE_OUTER_SIZE: 48,
        BROWSER_BOTTOM_CHROME_PHONE_OUTER_GAP: 4
      };
    }
    if (request === './BrowserBottomPanelMotionTokens') {
      return {
        BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS: 220,
        BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS: 180,
        resolveBrowserBottomPanelMiddleSnapCurve: () => ({}),
        resolveBrowserBottomPanelMotionCurve: () => ({})
      };
    }
    if (request === './BrowserBottomPanelText') {
      return {
        resourceStrPresent: (value) => value !== undefined &&
          (typeof value !== 'string' || value.trim().length > 0),
        resourceStrKey: (value) => value === undefined
          ? ''
          : (typeof value === 'string' ? value : `r:${value.id}`),
        bottomPanelCustomizeSlot: () => 'app.string.bottom_panel_customize_slot'
      };
    }
    if (request === './BrowserSearchEnginePresentationViewModel') {
      return { BrowserSearchEngineChromePresentation: SearchEnginePresentation };
    }
    return {};
  });
}

function checkCollapseIsAnOpacityCrossFade() {
  const chromeModule = evaluateChromePresentationModule();
  const viewModel = new chromeModule.BrowserBottomChromePresentationViewModel();
  const resting = viewModel.buildPresentation(buildChromePresentationFacts('low'));
  const compact = viewModel.buildPresentation(
    Object.assign(buildChromePresentationFacts('low'), { scrollPresentation: 'compact' })
  );

  // The whole point of the fix: Scroll-Compact must NOT move the expanded rail, because animating
  // its width/height/padding/radius re-laid-out the rail and re-sampled three glass materials plus
  // three large shadows on every frame of an in-gesture collapse.
  assert(compact.frame.isEquivalent(resting.frame),
    'Scroll-Compact must leave the expanded rail at resting geometry so the collapse animates opacity only');
  assert(compact.scrollCompactProgress === 1 && resting.scrollCompactProgress === 0,
    'Scroll-Compact must drive the capsule cross-fade through presentation-owned progress');
  assert(compact.floatingSurfaceTranslateY === resting.floatingSurfaceTranslateY + 16,
    'Scroll-Compact must still translate the floating surface with the collapsed capsule');

  // The collapsed capsule is its own fixed-geometry layer, so its geometry may not vary with mode.
  for (const sameModeFacts of [buildChromePresentationFacts('low'), buildChromePresentationFacts('middle')]) {
    const other = viewModel.buildPresentation(sameModeFacts);
    assert(other.compactFrame.isEquivalent(compact.compactFrame),
      'the collapsed capsule geometry must stay fixed across modes so it can be laid out once');
  }
  assert(compact.compactFrame.centerWidth === 96 &&
    compact.compactFrame.centerHeight === 32 &&
    compact.compactFrame.centerRadius === 16 &&
    compact.compactFrame.centerTranslateY === 4,
  'the collapsed capsule must keep its refined 96x32 capsule lifted 12vp clear of the 48vp rail');
  assert(compact.compactFrame.leadingOuterWidth === 0 &&
    compact.compactFrame.trailingOuterWidth === 0 &&
    compact.compactFrame.outerOpacity === 0,
  'the collapsed capsule must not carry the expanded outer clusters');

  // Restore tap must live on the collapsed layer, and the faded-out expanded rail must not also
  // expose a center restore target or both layers would answer the same touch.
  assert(compact.compactBodyTarget.intent.actionId === 'bottomChromeRestore' &&
    compact.compactBodyTarget.enabled === true,
  'the collapsed capsule must own the restore-toolbar tap');
  assert(resting.compactBodyTarget.intent.kind === 'none' &&
    compact.centerBodyTarget.intent.kind === 'none',
  'only the presented layer may expose the center tap target');

  // Gesture arbitration has to follow the visible capsule, not the faded-out expanded clusters.
  const panelCenterX = compact.panelWidth / 2;
  assert(compact.resolveGestureSource(panelCenterX) === 'center-capsule',
    'a touch on the collapsed capsule must resolve to the capsule rather than an expanded outer cluster');
  assert(resting.resolveGestureSource(panelCenterX) === 'center-capsule' &&
    resting.resolveGestureSource(0) === 'leading-outer',
  'the expanded rail must keep resolving its outer clusters from resting geometry');
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
    panelSource.includes('reserveExpansionHint ? BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_SIZE : 0') &&
    panelSource.includes('reserveExpansionHint ? BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_BOTTOM_GAP : 0') &&
    panelSource.includes('expansionHintSlotHeight: expansionHintSlotHeight') &&
    panelSource.includes('expansionHintBottomGap: expansionHintBottomGap'),
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

function checkExpandedSearchPageBackgroundContract() {
  const expandedScrimSource = fs.readFileSync(expandedScrimPath, 'utf8');
  const addressPanelSource = fs.readFileSync(addressPanelPath, 'utf8');
  const shellPageSource = fs.readFileSync(shellPagePath, 'utf8');
  const rootBottomPanelSessionSource = fs.readFileSync(rootBottomPanelSessionPath, 'utf8');
  const presentationSource = fs.readFileSync(path.join(
    repoRoot,
    'AiraBrowser/entry/src/main/ets/core/browser/BrowserSearchBackdropPresentationViewModel.ets'
  ), 'utf8');
  assert(presentationSource.includes('resolveExpandedPageBackgroundVisible(') &&
    presentationSource.includes("input.surfaceEligible && input.detent === 'middle'"),
  'the expanded search page background is owned by the backdrop presentation policy and only the committed middle surface');
  assert(rootBottomPanelSessionSource.includes('this.searchBackdropPresentationViewModel.resolveExpandedPageBackgroundVisible({') &&
    rootBottomPanelSessionSource.includes('pageBackgroundVisible: pageBackgroundVisible') &&
    shellPageSource.includes('pageBackgroundVisible: this.buildRootBottomPanelExpandedScrimState().pageBackgroundVisible'),
  'the shell must paint the expanded page background from the session policy, not from a local colour choice');
  assert(expandedScrimSource.includes('BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY') &&
    expandedScrimSource.includes('private shouldPaintExpandedPageBackground(): boolean') &&
    expandedScrimSource.includes('return !this.surfaceSuppressed && this.surfaceEligible && this.pageBackgroundVisible;') &&
    expandedScrimSource.includes('.backgroundColor(this.storedPageBackgroundColor)') &&
    expandedScrimSource.includes('TransitionEffect.opacity(0)') &&
    !expandedScrimSource.includes('TransitionEffect.IDENTITY') &&
    !expandedScrimSource.includes('browser_overlay_scrim') &&
    !expandedScrimSource.includes('start_window_background'),
  'the committed search interface must fade in a full-screen theme page background without the system appear slide, not a drag veil or a dim scrim');
  assert(addressPanelSource.includes('floatingTopSurfaceChromeVisible: false'),
  'suggestion rows must sit on the full-screen page background instead of owning a separate history plate');
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
    routeSource.includes('class BrowserShellRouteFrameCallback extends FrameCallback') &&
    routeSource.includes('onFrame(_frameTimeInNano: number): void {\n    this.task();') &&
    routeSource.includes('private routeTransitionRunId: number = 0;') &&
    routeSource.includes('this.dependencies.resolveUIContext().postFrameCallback(') &&
    routeSource.includes('if (runId !== this.routeTransitionRunId)') &&
    !routeSource.includes('onIdle(_timeLeftInNano: number): void {\n    this.task();') &&
    routerPushIndex > pushRouteSource.indexOf('new BrowserShellRouteFrameCallback'),
  'router must start from a latest-request-only post-render frame callback that runs on the next frame, ' +
  'not in the reset UI turn and not once the frame goes idle (an idle callback is starved by a running ' +
  'bottom-panel collapse animation and defers the route until the animation ends)');
  assert(presentationChannelSource.includes('surfaceSuppressed: boolean;') &&
    presentationChannelSource.includes('publishRouteTransitionSuppression(): void') &&
    expandedScrimSource.includes('@State private surfaceSuppressed: boolean = false;') &&
    expandedScrimSource.includes('this.surfaceSuppressed = presentation.surfaceSuppressed;') &&
    expandedScrimSource.includes('if (this.surfaceSuppressed || !this.surfaceEligible)') &&
    expandedScrimSource.includes('return !this.surfaceSuppressed && this.surfaceEligible'),
  'route reset must physically unmount and collapse the glass backdrop before the post-render route barrier');
}

function checkRenderPolicyReadsOnlySurfaceFacts() {
  const tabHomeModule = evaluateCommonJs(tabHomePath, () => ({}));
  const cases = [
    { kind: 'system', home: true, private: false, override: undefined, search: true,
      hide: false, behavior: 'compact', scene: 'system_home', mode: 'compact', visible: true },
    { kind: 'custom_web', home: true, private: false, override: undefined, search: true,
      hide: false, behavior: 'hidden', scene: 'third_party_home', mode: 'fixed', visible: true },
    { kind: 'custom_web', home: true, private: false, override: undefined, search: true,
      hide: true, behavior: 'hidden', scene: 'third_party_home', mode: 'hidden', visible: true },
    { kind: 'custom_web', home: true, private: true, override: undefined, search: true,
      hide: false, behavior: 'compact', scene: 'system_home', mode: 'compact', visible: true },
    { kind: 'system', home: false, private: false, override: undefined, search: true,
      hide: false, behavior: 'compact', scene: 'web_page', mode: 'inactive', visible: false },
    { kind: 'system', home: false, private: false, override: true, search: true,
      hide: false, behavior: 'compact', scene: 'system_home', mode: 'compact', visible: true },
    { kind: 'system', home: true, private: false, override: false, search: true,
      hide: false, behavior: 'compact', scene: 'hidden', mode: 'inactive', visible: false },
    { kind: 'system', home: true, private: false, override: undefined, search: false,
      hide: false, behavior: 'compact', scene: 'system_home', mode: 'inactive', visible: false }
  ];
  for (const value of cases) {
    let broadReads = 0;
    let surfaceReads = 0;
    const custom = buildCustomHomepageState(value.kind, value.hide, value.search);
    const input = { showHomePage: value.home, webPageVisible: !value.home,
      thirdPartyHomepageAllowed: !value.private, customHomepageState: custom,
      customHomepageWebVisible: value.kind === 'custom_web' };
    const coordinator = Object.create(tabHomeModule.BrowserTabHomeCoordinator.prototype);
    coordinator.shell = {
      readState() {
        broadReads++;
        return { showHomePage: value.home, currentBoundaryPrivate: value.private,
          customHomepageRuntimeState: { presentation: custom, surfaceVisible: input.customHomepageWebVisible } };
      },
      readSurfaceProfileInput() { surfaceReads++; return input; }
    };
    coordinator.dependencies = { preferencesRepository: {
      getPreferences: () => ({ appearance: { bottomToolbarScrollBehavior: value.behavior } })
    } };
    coordinator.homeSurfaceProfileViewModel = new profileModule.BrowserHomeSurfaceProfileViewModel();
    coordinator.homeChromeScrollCoordinator = new homeModule.BrowserHomeChromeScrollCoordinator();
    const before = JSON.stringify(input);
    const profile = coordinator.buildHomeSurfaceProfile(value.override);
    const policy = coordinator.buildHomeSystemChromePolicyState(value.override);
    assert(profile.scene === value.scene && policy.scene === value.scene,
      'narrow render facts must preserve home/web/private/override scene selection');
    assert(policy.homeScrollMode === value.mode && policy.bottomPanelHomeSearchVisible === value.visible,
      'narrow render facts must preserve custom-home and toolbar scroll policy');
    assert(before === JSON.stringify(input), 'render overrides must not mutate shell-owned facts');
    assert(broadReads === 0,
      `Home render policy observed the whole page ${broadReads} times, including unrelated reactive fields`);
    assert(surfaceReads === 2, 'each public presentation builder should read its surface facts once');
  }
}

const checks = [
  checkRenderPolicyReadsOnlySurfaceFacts,
  checkPolicyOwnershipMatrix,
  checkNativeScrollBehavior,
  checkRawAdapterAndOwnerSeam,
  checkCollapsedOverlayPanOwnership,
  checkHiddenFloatingHeaderHitTesting,
  checkFixedSearchAnchorAndStableGeometry,
  checkCollapseIsAnOpacityCrossFade,
  checkExpansionHintContract,
  checkToolbarResponsiveGridContract,
  checkUnifiedToolbarPageContract,
  checkToolbarGestureFrameContract,
  checkRoutedToolbarBackdropContract,
  checkExpandedSearchPageBackgroundContract
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
