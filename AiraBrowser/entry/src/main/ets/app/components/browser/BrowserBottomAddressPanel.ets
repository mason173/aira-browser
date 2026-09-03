import {
  BrowserBottomAddressPanelAction,
  BrowserBottomAddressPanelActionId,
  BrowserBottomAddressPanelBuildInput,
  BrowserBottomAddressPanelHeaderAction,
  BrowserBottomAddressPanelViewModel,
  BrowserBottomPanelMotionState,
  DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE,
  filterBrowserBottomAddressPanelActionsHiddenByVisiblePrimary,
  resolveBrowserBottomAddressPanelActionAiraIconId
} from '../../../core/browser/BrowserBottomAddressPanelViewModel';
import {
  ExternalAppSearchPreferences,
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchSuggestion
} from '../../../common/models/BrowserModels';
import {
  BrowserBottomToolbarLabelContrastCoordinator,
  BrowserBottomToolbarLabelContrastRequest,
  BrowserBottomToolbarLabelTone,
  BrowserBottomToolbarLabelToneApplier
} from '../../../core/browser/BrowserBottomToolbarLabelContrastCoordinator';
import {
  BrowserForegroundPresentation,
  BrowserForegroundPresentationViewModel,
  createDefaultBrowserForegroundPresentation
} from '../../../core/browser/BrowserForegroundPresentationViewModel';
import { HomeSearchPanelDetent } from '../../../core/browser/HomeSearchPanelDetentViewModel';
import {
  BrowserSearchChromeSurfaceState,
  BrowserSearchChromeSurfaceViewModel
} from '../../../core/browser/BrowserSearchChromeSurfaceViewModel';
import {
  BrowserBottomAddressContextAction,
  BrowserBottomChromeGestureSource,
  BrowserBottomChromeContentPresentation,
  BrowserBottomChromeHeaderPresentation,
  BrowserBottomChromePresentation,
  BrowserBottomChromeTapIntent,
  DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION
} from '../../../core/browser/BrowserBottomChromePresentationViewModel';
import {
  BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT,
  BROWSER_BOTTOM_CHROME_TEXT_SIZE,
  BROWSER_BOTTOM_ADDRESS_INPUT_SELECTION_HANDLE_INSET,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING,
  BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP,
  BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE,
  BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
  BROWSER_BOTTOM_QUICK_ACTION_LABEL_LINE_HEIGHT,
  BROWSER_BOTTOM_QUICK_ACTION_VERTICAL_GAP,
  BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_BOTTOM_GAP,
  BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_SIZE
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import {
  BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_REVEAL_DISTANCE,
  BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_BARRIER_MS
} from '../../../core/browser/BrowserBottomPanelMotionTokens';
import {
  BrowserDetentBottomPanel,
  BrowserDetentBottomPanelGestureFrame,
  BrowserDetentBottomPanelGestureInterceptTarget,
  BrowserDetentBottomPanelGestureReleaseDisposition
} from './BrowserDetentBottomPanel';
import {
  BrowserBottomToolbarExpansionStage,
  BrowserBottomToolbarExpansionViewModel,
  BrowserBottomToolbarQuickActionLayoutState,
  BrowserBottomToolbarSurfaceTransitionState
} from '../../../core/browser/BrowserBottomToolbarExpansionViewModel';
import { BrowserBottomChromeRenderer } from './BrowserBottomChromeRenderer';
import {
  resolveBrowserBottomChromeEdgeHighlightColor,
  resolveBrowserBottomChromeMaterialTintForMode
} from './BrowserFloatingGlassMaterialTokens';
import { BrowserBottomSheetSurface } from './BrowserModalBottomSheet';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor
} from '../common/FloatingGlassMaterialTokens';
import { BROWSER_GLOBAL_SYMBOL_WEIGHT } from './BrowserIconStyle';
import { HomeSearchQuickActionCard } from './HomeSearchQuickActionCard';
import { AiraIcon } from '../common/AiraIcon';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BrowserSearchListSurface,
  BrowserSearchListSurfaceIntent
} from './BrowserSearchListSurface';
import { inputMethod } from '@kit.IMEKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_APP_PROXY_ACTIVE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_BOTTOM_NEUTRAL_ICON_DISABLED_OPACITY,
  BROWSER_BOTTOM_NEUTRAL_ICON_ENABLED_OPACITY,
  resolveBrowserBottomAdaptiveQuickActionBackgroundColor,
  resolveBrowserBottomAdaptiveQuickActionIconColor,
  resolveBrowserBottomExpandedToolbarActionColor,
  resolveBrowserBottomExpandedToolbarActionIconColor,
  resolveBrowserBottomFloatingHeaderGrayProgress,
  resolveBrowserBottomFloatingMaterialShadowColor,
  resolveBrowserBottomNeutralContainerColor,
  resolveBrowserBottomNeutralPressedColor,
  resolveBrowserBottomNeutralPrimaryColor,
  resolveBrowserBottomNeutralSecondaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { AppChromeIconTone, AppIconResources } from '../../../core/resources/AppIconResources';
import {
  BrowserBottomAddressPanelActionVisualState,
  BrowserBottomAddressPanelActionVisualViewModel
} from '../../../core/browser/BrowserBottomAddressPanelActionVisualViewModel';
import {
  BrowserBottomPanelResponsiveState,
  DEFAULT_BROWSER_BOTTOM_PANEL_RESPONSIVE_STATE
} from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import { extractFirstUrlFromText } from '../../../common/utils/UrlUtils';
import {
  EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY
} from '../../../common/constants/SearchPreferenceKeys';
import {
  ExternalAppSearchService,
  ExternalAppSearchTarget
} from '../../../services/search/ExternalAppSearchService';
import {
  BrowserBottomPanelLivePresentation,
  BrowserBottomPanelReadingContinuationPresentation,
  BrowserBottomPanelPresentationChannel,
  BrowserBottomPanelPresentationListener,
  HIDDEN_BROWSER_BOTTOM_PANEL_READING_CONTINUATION
} from '../../../core/browser/BrowserBottomPanelPresentationChannel';
import { BrowserBottomPanelActionSnapshot } from '../../../core/browser/BrowserBottomPanelActionPresentationCoordinator';
import {
  BrowserToolbarCustomizationBoundary,
  BrowserToolbarCustomizationCoordinator
} from
  '../../../core/browser/BrowserToolbarCustomizationCoordinator';
import {
  DownloadToolbarIndicatorState,
  DownloadToolbarIndicatorViewModel,
  createHiddenDownloadToolbarIndicatorState
} from '../../../core/download/DownloadToolbarIndicatorViewModel';
import { DownloadV2TaskEntity } from '../../../domain/downloadv2/DownloadV2TaskEntity';
import {
  sharedDownloadRuntimeService,
  sharedExternalAppSearchPreferencesRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
const WEB_BOTTOM_ADDRESS_BAR_HEIGHT: number = 52;
const USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN: number = 0x0000;
const USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG: string = 'BrowsingIdentity';
const USER_AGENT_ACTION_DIAGNOSTIC_PREFIX: string = '[DEBUG-UA-ACTION-20260828]';
const WEB_BOTTOM_ADDRESS_INPUT_CONTENT_HEIGHT: number = 52;
const WEB_BOTTOM_ADDRESS_INPUT_LINE_HEIGHT: number = BROWSER_BOTTOM_CHROME_TEXT_LINE_HEIGHT;
const WEB_BOTTOM_ADDRESS_BUTTON_SIZE: number = 48;
const WEB_BOTTOM_ADDRESS_ICON_SIZE: number = 24;
const WEB_BOTTOM_ADDRESS_IMAGE_ICON_SIZE: number = 24;
const WEB_BOTTOM_ADDRESS_BUTTON_GAP: number = 2;
const WEB_BOTTOM_ADDRESS_HORIZONTAL_PADDING: number = 2;
const WEB_BOTTOM_CENTER_ACTION_PRESS_RADIUS: number = WEB_BOTTOM_ADDRESS_BAR_HEIGHT / 2;
const WEB_BOTTOM_QUICK_ACTION_GROUP_VERTICAL_PADDING: number = 12;
const WEB_BOTTOM_QUICK_ACTION_MAX_COLUMNS: number = 8;
const WEB_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_ID: AiraRenderableIconId = 'browser.toolbar.expandHint';
const WEB_BOTTOM_LIST_IMAGE_ICON_SIZE: number = 26;
const WEB_BOTTOM_LIST_TEXT_SIZE: number = 15;
const WEB_BOTTOM_LIST_TRAILING_TEXT_SIZE: number = 14;
const WEB_BOTTOM_SECONDARY_CARD_ROW_MIN_HEIGHT: number = 54;
const WEB_BOTTOM_SUGGESTION_TOP_SAFE_GAP: number = 24;
const WEB_BOTTOM_DISABLED_OPACITY: number = 0.42;
const WEB_BOTTOM_INPUT_FOCUS_ID: string = 'aira-web-bottom-address-input';
const WEB_BOTTOM_INPUT_FOCUS_RETRY_DELAY_MS: number = 32;
const WEB_BOTTOM_INPUT_FOCUS_MAX_ATTEMPTS: number = 6;
const WEB_BOTTOM_INPUT_SELECT_ALL_DELAY_MS: number = 0;
const WEB_BOTTOM_ADDRESS_BULK_INPUT_MIN_DELTA: number = 6;
const WEB_BOTTOM_HEADER_ACTION_DEDUP_MS: number = 240;
const WEB_BOTTOM_DRAG_EXPANDED_CONTENT_REVEAL_THRESHOLD: number = 2;
const WEB_BOTTOM_ADDRESS_TEXT_FADE_MS: number = 180;
const WEB_BOTTOM_RELIABLE_HEADER_ACTION_THROTTLE_MS: number = 360;
const WEB_BOTTOM_HEADER_BUTTON_ENTER_DURATION_MS: number = 260;
const WEB_BOTTOM_HEADER_BUTTON_ENTER_DELAY_MS: number = 24;
const WEB_BOTTOM_EXPANDED_CONTENT_IDLE_HEIGHT: number = 1;
const WEB_BOTTOM_SECONDARY_ACTION_PRESSED_SCALE: number = 0.98;
const WEB_BOTTOM_SECONDARY_ACTION_PRESS_DURATION_MS: number = 90;
const WEB_BOTTOM_SECONDARY_ACTION_RELEASE_DURATION_MS: number = 260;
const WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_TRANSLATE_Y: number = 10;
const WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_DURATION_MS: number = 180;
const WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_STAGGER_MS: number = 45;
const WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_MAX_DELAY_MS: number = 90;
const WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_BARRIER_MS: number =
  WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_DURATION_MS + WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_MAX_DELAY_MS;
const WEB_BOTTOM_QUICK_ACTION_DRAG_CLICK_GUARD_MS: number = 260;
const WEB_BOTTOM_TOOLBAR_EXPANSION_HINT_ROTATION_DURATION_MS: number = 220;
const WEB_BOTTOM_READING_CONTINUATION_HEIGHT: number = 64;
const WEB_BOTTOM_READING_CONTINUATION_ICON_SIZE: number = 22;
const WEB_BOTTOM_READING_CONTINUATION_TRAILING_ICON_SIZE: number = 16;
const WEB_BOTTOM_READING_CONTINUATION_HORIZONTAL_PADDING: number = 16;
function buildDefaultBrowserBottomAddressPanelActionInput(): BrowserBottomAddressPanelBuildInput {
  return {
    chromeIconTone: 'light',
    privateModeActive: false,
    actionEnablement: {},
    pageFindEnabled: true,
    readerModeEnabled: false,
    webpageTranslationEnabled: true,
    offlinePageSaveEnabled: true,
    offlinePageSaveDisabledMessage: '当前页面无法保存',
    bookmarksEnabled: true,
    bookmarksActionLabel: '添加书签',
    bookmarksActionIcon: $r('sys.symbol.bookmark'),
    bookmarksActionDisabledMessage: '当前页面无法收藏',
    bookmarksActionSelected: false,
    bookmarksActionVersion: 0,
    appProxyActive: false,
    userAgentActionLabel: '网站版本',
    userAgentActionTrailingText: '跟随默认',
    userAgentActionIcon: $r('sys.symbol.rectangle_on_rectangle_fill'),
    userAgentActionVersion: 0,
    textZoomActionLabel: '网页文字大小',
    textZoomActionTrailingText: '100%',
    textZoomActionIcon: $r('sys.symbol.doc_text_fill'),
    textZoomActionVersion: 0,
    userAgentPresetActionLabel: '网页标识',
    userAgentPresetActionTrailingText: 'Aira默认',
    userAgentPresetActionIcon: $r('sys.symbol.compass_circle_fill'),
    userAgentPresetActionVersion: 0,
    screenOrientationActionLabel: '屏幕方向：跟随系统',
    screenOrientationActionTrailingText: '跟随系统',
    screenOrientationActionIcon: $r('sys.symbol.gyroscope'),
    screenOrientationActionVersion: 0,
    themeModeActionLabel: '跟随系统外观',
    themeModeActionTrailingText: '跟随系统',
    themeModeActionIcon: $r('sys.symbol.sun_max_fill'),
    themeModeActionVersion: 0,
    fullScreenModeActionLabel: '全屏模式',
    fullScreenModeActionTrailingText: '沉浸浏览',
    fullScreenModeActionIcon: $r('sys.symbol.fullscreen'),
    fullScreenModeActionVersion: 0
  };
}

interface BrowserBottomAddressPanelActionGridRow {
  rowIndex: number;
  actions: BrowserBottomAddressPanelAction[];
}

export interface BrowserBottomAddressPanelGestureFrame {
  phase: 'start' | 'update';
  panelHeight: number;
  offsetY: number;
  source: BrowserBottomChromeGestureSource;
  middlePanelHeight: number;
}

interface BrowserBottomToolbarRenderSnapshot {
  liveActionRevision: number;
  fallbackActionRevision: number;
  orderRevision: number;
  layoutRevision: number;
  motionLayoutRevision: number;
  presentationRevision: number;
  continuationRevision: number;
  actions: BrowserBottomAddressPanelAction[];
  layoutState: BrowserBottomToolbarQuickActionLayoutState;
  fullExpansionAvailable: boolean;
  layoutRenderKey: string;
}

@Component
export struct BrowserBottomAddressPanel {
  @StorageLink(EXTERNAL_APP_SEARCH_PREFERENCES_REVISION_KEY) @Watch('refreshExternalAppSearchPreferences')
  private externalAppSearchPreferencesRevision: number = 0;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_APP_PROXY_ACTIVE_BACKGROUND_KEY)
  private storedAppProxyActiveBackgroundColor: string = '#9C55D7';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY)
  private storedSelectedIconForegroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @State private panelDetent: HomeSearchPanelDetent = 'low';
  @State private panelTargetDetent: HomeSearchPanelDetent = 'low';
  @State private addressInputAdapterActive: boolean = false;
  @State private editingMotionFocusReady: boolean = false;
  @State private addressFocused: boolean = false;
  @State private editingAddressText: string = '';
  @State private externalAppSearchPreferences: ExternalAppSearchPreferences =
    sharedExternalAppSearchPreferencesRepository.getSettings();
  @State private pressedActionId: string = '';
  @State private headerButtonsEnterProgress: number = 1;
  @State private reliableHeaderActionEnabled: boolean = true;
  @State private toolbarExpansionStage: BrowserBottomToolbarExpansionStage = 'preview';
  @State private panelDragHeight: number = 0;
  @State private quickActionLabelTone: BrowserBottomToolbarLabelTone = 'dark';
  @State private quickActionReorderActive: boolean = false;
  @State private liveQuickActionOrderIds: BrowserBottomAddressPanelActionId[] = [];
  @State private floatingActionSurfacePrepared: boolean = false;
  @State private toolbarSystemSheetVisible: boolean = false;
  @State private toolbarSystemSheetDetentSelection: Length = 0;
  @State private floatingActionContentSettled: boolean = false;
  @State private floatingActionContentGestureRevealed: boolean = false;
  @State private floatingActionContentEntryActive: boolean = false;
  @State private floatingActionContentExitActive: boolean = false;
  @State private downloadIndicatorState: DownloadToolbarIndicatorState =
    createHiddenDownloadToolbarIndicatorState();
  private viewModel: BrowserBottomAddressPanelViewModel = new BrowserBottomAddressPanelViewModel();
  private actionVisualViewModel: BrowserBottomAddressPanelActionVisualViewModel =
    new BrowserBottomAddressPanelActionVisualViewModel();
  private searchChromeSurfaceViewModel: BrowserSearchChromeSurfaceViewModel =
    new BrowserSearchChromeSurfaceViewModel();
  private browserForegroundPresentationViewModel: BrowserForegroundPresentationViewModel =
    new BrowserForegroundPresentationViewModel();
  private externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService();
  private addressInputController: TextInputController = new TextInputController();
  private quickActionLabelContrastCoordinator: BrowserBottomToolbarLabelContrastCoordinator =
    new BrowserBottomToolbarLabelContrastCoordinator();
  private toolbarExpansionViewModel: BrowserBottomToolbarExpansionViewModel =
    new BrowserBottomToolbarExpansionViewModel();
  private toolbarCustomizationCoordinator: BrowserToolbarCustomizationCoordinator =
    new BrowserToolbarCustomizationCoordinator(sharedPreferencesRepository);
  private downloadToolbarIndicatorViewModel: DownloadToolbarIndicatorViewModel =
    new DownloadToolbarIndicatorViewModel();
  private panelContentScroller: Scroller = new Scroller();
  private pendingAddressFocusRequest: boolean = false;
  private addressFocusAttemptCount: number = 0;
  private addressInputMounted: boolean = false;
  private addressInputActuallyFocused: boolean = false;
  private preserveExpandedBackdropForActiveToolbarGesture: boolean = false;
  private addressFocusTimeout: number = -1;
  private addressSelectAllTimeout: number = -1;
  private restorableWebAddressText: string = '';
  private addressBlurTimeout: number = -1;
  private lastHeaderActionId: string = '';
  private lastHeaderActionAt: number = 0;
  private headerButtonsEnterTimeout: number = -1;
  private panelDetentNotificationTimer: number = -1;
  private pendingPanelDetentNotification: HomeSearchPanelDetent | undefined = undefined;
  private homeDismissAfterLowSettlePending: boolean = false;
  private activeChromeGestureSource: BrowserBottomChromeGestureSource = 'none';
  private activeChromeGestureMiddlePanelHeight: number = 0;
  private pendingToolbarSystemSheetAction: BrowserBottomAddressPanelAction | undefined = undefined;
  private handledImmediateLowDetentRequestVersion: number = 0;
  private dragConsumedQuickActionId: BrowserBottomAddressPanelActionId | undefined = undefined;
  private quickActionDragClickGuardTimeout: number = -1;
  private floatingActionContentEntryTimer: number = -1;
  private floatingActionGestureRevealTimer: number = -1;
  private floatingActionContentExitTimer: number = -1;
  private pendingFloatingActionContentExitCompletion?: () => void = undefined;
  private lastChromeHeaderPresentation: BrowserBottomChromeHeaderPresentation = 'address';
  private lastChromeContentPresentation: BrowserBottomChromeContentPresentation = 'web';
  private presentationListener: BrowserBottomPanelPresentationListener =
    (presentation: BrowserBottomPanelLivePresentation): void => {
      this.livePresentationConnected = true;
      this.applyLivePresentation(presentation);
    };
  private disconnectPresentationChannel: () => boolean = (): boolean => false;
  private downloadIndicatorListenerKey: string = '';
  private livePresentationConnected: boolean = false;
  private liveActionSnapshot?: BrowserBottomPanelActionSnapshot = undefined;
  private toolbarRenderSnapshot?: BrowserBottomToolbarRenderSnapshot = undefined;
  private toolbarOrderRevision: number = 0;
  private toolbarMotionLayoutRevision: number = 0;
  private toolbarPresentationRevision: number = 0;
  @State private liveActionSnapshotRevision: number = 0;
  @State private liveReadingContinuationRevision: number = 0;
  @State private liveReadingContinuation: BrowserBottomPanelReadingContinuationPresentation =
    HIDDEN_BROWSER_BOTTOM_PANEL_READING_CONTINUATION;
  @State private liveFloatingHeaderVisible: boolean = true;
  @State private livePanelMotionState: BrowserBottomPanelMotionState = DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE;
  @State private liveAddressInput: string = '';
  @State private liveAddressDisplayText: string = '';
  @State private liveAddressPlaceholder: string = '';
  @State private floatingHeaderTracksPanelMotion: boolean = false;
  @State private liveBottomChromePresentation: BrowserBottomChromePresentation =
    DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION;
  @Prop
  @Watch('syncPanelMotionStateFromProp')
  panelMotionState: BrowserBottomPanelMotionState = DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE;
  private requestedAddressFocused: boolean = false;
  presentationChannel: BrowserBottomPanelPresentationChannel = new BrowserBottomPanelPresentationChannel();
  @Prop privateMode: boolean = false;
  @Prop appProxyActive: boolean = false;
  @Prop liveBackdropBlurSuppressed: boolean = false;
  @Prop actionInput: BrowserBottomAddressPanelBuildInput = buildDefaultBrowserBottomAddressPanelActionInput();
  @Prop addressEditable: boolean = true;
  @Prop @Watch('invalidateToolbarPresentationSnapshot') viewerInfoActionEnabled: boolean = false;
  @Prop
  @Watch('syncBottomChromePresentationFromProp')
  bottomChromePresentation: BrowserBottomChromePresentation = DEFAULT_BROWSER_BOTTOM_CHROME_PRESENTATION;
  @Prop centerActionEnabled: boolean = false;
  @Prop centerActionIcon: Resource = $r('sys.symbol.plus');
  @Prop centerActionText: string = '';
  @Prop centerActionAccessibilityText: string = '中间操作';
  @Prop homeSuggestions: SearchSuggestion[] = [];
  @Prop homeSuggestionsVisible: boolean = false;
  @Prop currentTabSuggestionRefId: string = '';
  @Prop primaryActionOverrides?: BrowserBottomAddressPanelAction[] = undefined;
  @Prop secondaryActionOverrides?: BrowserBottomAddressPanelAction[] = undefined;
  @Prop quickActionOverrides?: BrowserBottomAddressPanelAction[] = undefined;
  @Prop quickActionLabelSnapshotId: string = '';
  @Prop quickActionLabelTabId: string = '';
  @Prop quickActionLabelBackdropRevision: string = '';
  @Prop quickActionLabelWebPageVisible: boolean = false;
  @Prop quickActionLabelControllerAttached: boolean = false;
  @Prop homeForegroundPresentation: BrowserForegroundPresentation =
    createDefaultBrowserForegroundPresentation();
  @Prop @Watch('invalidateToolbarPresentationSnapshot') quickActionsOnly: boolean = false;
  @Prop responsiveState: BrowserBottomPanelResponsiveState = DEFAULT_BROWSER_BOTTOM_PANEL_RESPONSIVE_STATE;
  @Prop toolbarActionRevision: number = 0;
  @Prop toolbarLayoutRevision: number = 0;
  @Prop activeDownloadIndicatorEnabled: boolean = true;
  onPanelDetentChange: (detent: HomeSearchPanelDetent) => void = (_detent: HomeSearchPanelDetent) => {};
  onPanelGestureFrame: (frame: BrowserBottomAddressPanelGestureFrame) => void =
    (_frame: BrowserBottomAddressPanelGestureFrame) => {};
  onPanelVisualHeightChange: (panelHeight: number, expandedHeight: number) => void =
    (_panelHeight: number, _expandedHeight: number) => {};
  onPresentationHostReady: (hostHeight: number) => void = (_hostHeight: number) => {};
  onPanelDragEnd: (panelHeight: number, targetDetent: HomeSearchPanelDetent) => void =
    (_panelHeight: number, _targetDetent: HomeSearchPanelDetent) => {};
  onPanelDragEndIntercept:
    (panelHeight: number, targetDetent: HomeSearchPanelDetent, offsetY: number,
      source: BrowserBottomChromeGestureSource) =>
    BrowserDetentBottomPanelGestureInterceptTarget =
    (_panelHeight: number, _targetDetent: HomeSearchPanelDetent, _offsetY: number,
      _source: BrowserBottomChromeGestureSource) => undefined;
  onPanelSettled: (detent: HomeSearchPanelDetent) => void = (_detent: HomeSearchPanelDetent) => {};
  onPresentationHostDisconnected: () => void = () => {};
  onAddressFocusPrepare: () => void = () => {};
  onAddressFocusStateChange: (focused: boolean) => void = (_focused: boolean) => {};
  onAddressChange: (value: string) => void = (_value: string) => {};
  onAddressSubmit: (rawInput: string) => void = (_rawInput: string) => {};
  onAddressContextAction: (action: BrowserBottomAddressContextAction) => void =
    (_action: BrowserBottomAddressContextAction) => {};
  onExternalAppSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};
  onHeaderAction: (actionId: string) => void = (_actionId: string) => {};
  onToolbarLongPress: (slotId: string) => void = (_slotId: string) => {};
  onOpenSuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onDeleteHistorySuggestion: (suggestion: SearchSuggestion) => void = (_suggestion: SearchSuggestion) => {};
  onSearchBlankAreaBack: () => void = () => {};
  onSelectSearchEngine: (engineId: SearchEngineId) => void = (_engineId: SearchEngineId) => {};
  onHomeRevealSuggestions: () => void = () => {};
  onHomeDismiss: () => void = () => {};
  onAction: (actionId: BrowserBottomAddressPanelActionId) => void = (_actionId: BrowserBottomAddressPanelActionId) => {};
  onContinueReading: () => void = (): void => {};
  onKeyboardResizeSessionBegin: () => void = () => {};
  onKeyboardResizeSessionEnd: () => void = () => {};

  aboutToAppear(): void {
    this.requestedAddressFocused = false;
    this.addressInputActuallyFocused = false;
    let retainedAddressFocused = false;
    const retainedPresentation = this.presentationChannel.current();
    if (retainedPresentation !== undefined) {
      this.livePresentationConnected = true;
      retainedAddressFocused = retainedPresentation.addressFocused;
      this.applyLivePanelMotionState(retainedPresentation.panelMotionState);
      this.applyBottomChromePresentation(retainedPresentation.bottomChromePresentation);
      this.applyLiveActionSnapshot(retainedPresentation.actionSnapshot);
      this.applyReadingContinuation(retainedPresentation.readingContinuation);
      this.liveFloatingHeaderVisible = retainedPresentation.floatingHeaderVisible;
    } else {
      this.livePresentationConnected = false;
      this.applyLivePanelMotionState(this.panelMotionState);
      this.applyBottomChromePresentation(this.bottomChromePresentation);
    }
    this.lastChromeHeaderPresentation = this.liveBottomChromePresentation.headerPresentation;
    this.lastChromeContentPresentation = this.liveBottomChromePresentation.contentPresentation;
    this.syncAddressInputAdapterFromPresentation();
    this.syncPanelMotionState();
    this.requestedAddressFocused = retainedAddressFocused;
    this.syncRequestedAddressFocused();
    this.disconnectPresentationChannel = this.presentationChannel.connect(this.presentationListener);
    this.bindActiveDownloadIndicator();
  }

  aboutToDisappear(): void {
    this.onPresentationHostDisconnected();
    const ownsLivePresentation = this.disconnectPresentationChannel();
    this.disconnectPresentationChannel = (): boolean => false;
    this.unbindActiveDownloadIndicator();
    this.livePresentationConnected = false;
    this.clearAddressFocusTimeout();
    this.clearAddressSelectAllTimeout();
    this.clearAddressBlurRequest();
    this.clearHeaderButtonsEnterRequest();
    this.clearPanelDetentNotification();
    this.clearFloatingActionContentEntry();
    this.clearFloatingActionGestureReveal();
    this.clearFloatingActionContentExitBarrier();
    this.resetQuickActionReorderState();
    this.preserveExpandedBackdropForActiveToolbarGesture = false;
    this.floatingActionSurfacePrepared = false;
    this.toolbarSystemSheetVisible = false;
    this.toolbarSystemSheetDetentSelection = 0;
    this.pendingToolbarSystemSheetAction = undefined;
    this.floatingActionContentSettled = false;
    this.floatingActionContentGestureRevealed = false;
    this.floatingHeaderTracksPanelMotion = false;
    this.quickActionLabelContrastCoordinator.dispose();
    this.homeDismissAfterLowSettlePending = false;
    this.releaseAddressFocusSessionIfOwned(ownsLivePresentation);
  }

  build() {
    Stack() {
      BrowserDetentBottomPanel({
        mode: 'overlay',
        motionState: this.buildDetentMotionState(),
        deferLowDetentChangeUntilSettled: this.shouldDeferLowDetentChangeUntilSettled(),
        floatingBlocksEnabled: true,
        floatingLayoutMode: this.resolveFloatingLayoutMode(),
        floatingExpandedContentPrepared: this.shouldPrepareFloatingActionSurface(),
        floatingExpandedContentVisible: this.shouldMountFloatingActionSurface(),
        floatingExpandedContentBodyVisible: this.shouldMountFloatingActionContent(),
        floatingExpandedContentGeometryLocked: this.floatingActionContentGestureRevealed,
        floatingContentFirstCollapseEnabled: this.shouldSequenceFloatingActionContentExit(),
        floatingContentFirstCollapseActive: this.floatingActionContentExitActive,
        floatingExpandedContentHeight: this.resolveFloatingActionSurfaceHeight(),
        floatingOverlayPanEnabled: this.resolveFloatingLayoutMode() === 'input' &&
          this.isExpandedPanelDetent(this.panelDetent) &&
          !this.quickActionReorderActive,
        floatingHeaderPanEnabled: this.resolveFloatingLayoutMode() === 'input' ||
          this.shouldUseThreeBlockBottomChrome(),
        floatingExpandedSurfaceCoversHeader: this.shouldRenderFloatingActionSurface(),
        floatingExpandedSurfaceCoverProgress: this.resolveToolbarSurfaceTransitionState().surfaceCoverProgress,
        floatingExpandedSurfaceChromeVisible: false,
        floatingExpandedHeaderHorizontalInset: this.shouldUseThreeBlockBottomChrome() ? 0 :
          this.resolveFloatingExpandedHeaderHorizontalInset(),
        floatingTopContentVisible: this.shouldReserveFloatingSuggestionPanelHeight(),
        floatingTopContentHeight: this.resolveFloatingSuggestionPanelHeight(),
        floatingContentRenderKey: this.buildAdaptiveForegroundRenderKey(),
        floatingTopSurfaceChromeVisible: false,
        floatingHeaderChromeVisible: !this.shouldUseThreeBlockBottomChrome(),
        floatingHeaderPresentationOpacity: this.resolveFloatingHeaderPresentationOpacity(),
        floatingHeaderInteractionEnabled: this.resolveFloatingHeaderPresentationOpacity() > 0.05,
        floatingHeaderHorizontalPadding: this.responsiveState.floatingHeaderHorizontalPadding,
        floatingHeaderPresentationTranslateY: this.liveBottomChromePresentation.floatingSurfaceTranslateY,
        floatingHeaderInteractionWidth: this.resolveFloatingHeaderInteractionWidth(),
        floatingHeaderInteractionHeight: this.resolveFloatingHeaderInteractionHeight(),
        floatingHeaderInteractionOffsetY: this.resolveFloatingHeaderInteractionOffsetY(),
        floatingHeaderTracksPanelMotion: this.floatingHeaderTracksPanelMotion,
        liveBackdropBlurSuppressed: this.liveBackdropBlurSuppressed,
        panelWidth: this.responsiveState.panelWidth,
        panelOffsetX: this.responsiveState.panelOffsetX,
        lightweightCollapsedMotion: this.shouldUseLightweightCollapsedSearchMotion(),
        onDetentChange: (detent: HomeSearchPanelDetent) => {
          this.applyPanelDetent(detent, false, this.shouldDeferRequestedPanelDetentNotification(detent));
        },
        onPanelGestureFrame: (frame: BrowserDetentBottomPanelGestureFrame) => {
          if (frame.phase === 'start') {
            this.clearFloatingActionGestureReveal();
            this.floatingActionContentGestureRevealed = false;
            this.preserveExpandedBackdropForActiveToolbarGesture =
              this.toolbarExpansionViewModel.shouldPreserveExpandedBackdropDuringGesture(this.toolbarExpansionStage);
            this.activeChromeGestureSource = this.isExpandedPanelDetent(this.panelDetent) ? 'none' :
              this.resolveBottomChromeGestureSource(frame.startX, frame.panelWidth);
            this.floatingHeaderTracksPanelMotion =
              this.activeChromeGestureSource === 'leading-outer' ||
                this.activeChromeGestureSource === 'trailing-outer';
            this.activeChromeGestureMiddlePanelHeight = this.resolveMiddlePanelHeight();
            this.floatingActionSurfacePrepared = this.activeChromeGestureSource === 'center-capsule' &&
              this.shouldRenderFloatingActionSurface();
          }
          if (frame.phase === 'update' &&
            this.isExpandedPanelDetent(this.panelDetent) &&
            this.toolbarExpansionStage === 'preview' &&
            frame.offsetY > 0 &&
            this.floatingActionContentSettled) {
            this.beginFloatingActionContentExit();
          }
          this.panelDragHeight = frame.panelHeight;
          if (!this.preserveExpandedBackdropForActiveToolbarGesture &&
            !this.floatingActionContentExitActive) {
            this.onPanelGestureFrame({
              phase: frame.phase,
              panelHeight: frame.panelHeight,
              offsetY: frame.offsetY,
              source: this.activeChromeGestureSource,
              middlePanelHeight: this.activeChromeGestureMiddlePanelHeight
            });
          }
          if (frame.phase === 'update') {
            this.scheduleFloatingActionContentRevealAtBackdropThreshold(frame.offsetY);
          }
        },
        onPanelVisualHeightChange: (panelHeight: number) => {
          if (!this.preserveExpandedBackdropForActiveToolbarGesture &&
            !this.floatingActionContentExitActive) {
            this.onPanelVisualHeightChange(panelHeight, this.resolveMiddlePanelHeight());
          }
        },
        onHostGeometryReady: (_hostWidth: number, hostHeight: number) => {
          this.onPresentationHostReady(hostHeight);
        },
        onPanelGestureEnd: (panelHeight: number, targetDetent: HomeSearchPanelDetent) => {
          this.clearFloatingActionGestureReveal();
          this.panelDragHeight = panelHeight;
          this.onPanelDragEnd(panelHeight, targetDetent);
          if (targetDetent !== 'middle') {
            this.floatingActionContentGestureRevealed = false;
          }
          this.preserveExpandedBackdropForActiveToolbarGesture = false;
          this.floatingActionSurfacePrepared = false;
          this.activeChromeGestureMiddlePanelHeight = 0;
        },
        onPanelGestureEndIntercept: (
          panelHeight: number,
          targetDetent: HomeSearchPanelDetent,
          offsetY: number,
          startX: number,
          panelWidth: number
        ) => {
          void startX;
          void panelWidth;
          if (this.preserveExpandedBackdropForActiveToolbarGesture) {
            this.activeChromeGestureSource = 'none';
            return undefined;
          }
          const source = this.activeChromeGestureSource;
          this.activeChromeGestureSource = 'none';
          if (this.shouldOpenToolbarSystemSheetFromGesture(targetDetent, offsetY, source)) {
            this.openToolbarSystemSheet();
            return 'low';
          }
          return this.onPanelDragEndIntercept(panelHeight, targetDetent, offsetY, source);
        },
        onPanelGestureRelease: (
          _panelHeight: number,
          targetDetent: HomeSearchPanelDetent,
          offsetY: number,
          velocityY: number
        ): BrowserDetentBottomPanelGestureReleaseDisposition => {
          void targetDetent;
          void offsetY;
          void velocityY;
          return 'default';
        },
        onExpandToMiddle: () => {
          if (!this.livePanelMotionState.panelExpansionEnabled) {
            this.applyPanelDetent('low');
            return;
          }
          if (this.isHomeHeaderMode()) {
            this.onHomeRevealSuggestions();
          }
        },
        onCollapse: () => {
          if (this.isHomeHeaderMode()) {
            if (this.shouldDeferHomeDismissUntilLowSettle()) {
              this.homeDismissAfterLowSettlePending = true;
              return;
            }
            this.applyAddressFocusState(false, true);
            this.onHomeDismiss();
            return;
          }
          this.applyAddressFocusState(false, true);
        },
        onPanelSettled: (detent: HomeSearchPanelDetent) => {
          this.handleDetentPanelSettled(detent);
          this.floatingHeaderTracksPanelMotion = false;
        },
        floatingTopContent: () => {
          this.buildFloatingSuggestionContent()
        },
        header: () => {
          this.buildAddressHeader()
        },
        expandedContent: () => {
          this.buildExpandedContent()
        }
      })
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.Transparent)

    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
    .bindSheet($$this.toolbarSystemSheetVisible, this.buildToolbarSystemSheet(),
      this.buildToolbarSystemSheetOptions())
  }

  private buildToolbarSystemSheetOptions(): SheetOptions {
    const layoutState = this.resolveToolbarRenderSnapshot().layoutState;
    const previewHeight = this.resolveToolbarSystemSheetPreviewHeight(layoutState);
    const fullHeight = this.resolveToolbarSystemSheetFullHeight(layoutState);
    return {
      preferType: SheetType.BOTTOM,
      height: fullHeight,
      detents: [previewHeight, fullHeight],
      detentSelection: this.toolbarSystemSheetDetentSelection > 0 ?
        this.toolbarSystemSheetDetentSelection : previewHeight,
      scrollSizeMode: ScrollSizeMode.FOLLOW_DETENT,
      dragBar: true,
      showClose: false,
      systemMaterial: createFloatingGlassMaterialIfAvailable(
        this.resolveBottomChromeMaterialTint()
      ),
      onDisappear: (): void => {
        this.handleToolbarSystemSheetDisappear();
      }
    };
  }

  @Builder
  private buildToolbarSystemSheet() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: resolveFloatingGlassMaterialBackgroundColor(this.storedPageBackgroundColor)
    }) {
      ForEach([this.resolveToolbarRenderSnapshot().layoutState],
        (layoutState: BrowserBottomToolbarQuickActionLayoutState) => {
          Column({ space: 0 }) {
            if (this.shouldShowReadingContinuation()) {
              this.buildReadingContinuationRow()
            }
            this.buildToolbarSystemSheetActionGrid(
              this.resolveToolbarRenderSnapshot().actions,
              layoutState
            )
          }
          .width('100%')
          .height('100%')
          .padding({
            top: layoutState.surfaceVerticalPadding,
            bottom: layoutState.surfaceVerticalPadding
          })
        }, (_layoutState: BrowserBottomToolbarQuickActionLayoutState) =>
          this.resolveToolbarRenderSnapshot().layoutRenderKey)
    }
  }

  private resolveToolbarSystemSheetPreviewHeight(
    layoutState: BrowserBottomToolbarQuickActionLayoutState
  ): number {
    const previewRows = Math.min(3, layoutState.rowCount);
    const gridHeight = previewRows > 0 ?
      previewRows * layoutState.cardHeight +
        Math.max(0, previewRows - 1) * layoutState.rowGap +
        layoutState.groupVerticalPadding * 2 : 0;
    return Math.max(1,
      gridHeight +
        layoutState.surfaceVerticalPadding * 2 +
        this.resolveReadingContinuationHeight());
  }

  private resolveToolbarSystemSheetFullHeight(
    layoutState: BrowserBottomToolbarQuickActionLayoutState
  ): number {
    return Math.max(
      this.resolveToolbarSystemSheetPreviewHeight(layoutState) + 1,
      layoutState.fullSurfaceHeight + this.resolveReadingContinuationHeight()
    );
  }

  @Builder
  private buildToolbarSystemSheetActionGrid(
    actions: BrowserBottomAddressPanelAction[],
    layoutState: BrowserBottomToolbarQuickActionLayoutState
  ) {
    // Keep the Sheet content fixed. Native detents reveal the preview rows or
    // the complete grid; the action surface itself must never become a scroll
    // container.
    Column({ space: layoutState.rowGap }) {
      ForEach(
        this.resolveQuickActionRowsForActions(actions, layoutState.columnCount),
        (row: BrowserBottomAddressPanelActionGridRow) => {
          Row({ space: layoutState.columnGap }) {
            ForEach(row.actions, (item: BrowserBottomAddressPanelAction) => {
              ForEach([this.buildActionRenderKey(item)], (_renderKey: string) => {
                this.buildQuickActionCard(
                  item,
                  layoutState.buttonSize,
                  layoutState.cardHeight,
                  true
                );
              }, (renderKey: string) => renderKey)
            }, (item: BrowserBottomAddressPanelAction) => item.id)

            ForEach(this.resolvePrimaryActionPlaceholderIndexes(
              row.actions.length,
              layoutState.columnCount
            ), (placeholderIndex: number) => {
              Blank()
                .width(this.resolveToolbarSystemSheetActionCellWidth(layoutState))
            }, (placeholderIndex: number) => `${row.rowIndex}-${placeholderIndex}`)
          }
          .width('100%')
          .height(layoutState.cardHeight)
        }, (row: BrowserBottomAddressPanelActionGridRow) =>
          `${row.rowIndex}-${row.actions.length}`)
    }
    .width('100%')
    .padding({
      left: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      right: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      top: layoutState.groupVerticalPadding,
      bottom: layoutState.groupVerticalPadding
    })
  }

  private resolveToolbarSystemSheetActionCellWidth(
    layoutState: BrowserBottomToolbarQuickActionLayoutState
  ): number {
    const columnCount = Math.max(1, Math.floor(layoutState.columnCount));
    const availableWidth = this.resolveFloatingQuickActionLayoutWidth();
    const horizontalPadding = BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING * 2;
    const totalGapWidth = Math.max(0, columnCount - 1) * Math.max(0, layoutState.columnGap);
    return Math.max(1, (availableWidth - horizontalPadding - totalGapWidth) / columnCount);
  }

  @Builder
  private buildAddressHeader() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseThreeBlockBottomChrome()) {
        this.buildThreeBlockToolbarHeader()
      } else {
        this.buildLegacyViewerToolbarHeader()
      }
    }
    .width('100%')
    .height(WEB_BOTTOM_ADDRESS_BAR_HEIGHT)
  }

  @Builder
  private buildThreeBlockToolbarHeader() {
    BrowserBottomChromeRenderer({
      presentation: this.liveBottomChromePresentation,
      materialTint: this.resolveBottomChromeMaterialTint(),
      materialShadowColor: resolveBrowserBottomFloatingMaterialShadowColor(this.resolveNeutralThemeMode()),
      edgeHighlightColor: resolveBrowserBottomChromeEdgeHighlightColor(this.resolveNeutralThemeMode()),
      primaryIconColor: this.resolveIconColor(true),
      disabledIconColor: this.resolveIconColor(false),
      primaryTextColor: this.resolvePrimaryTextColor(),
      secondaryTextColor: this.resolveSecondaryTextColor(),
      adaptiveForeground: true,
      pressedBackgroundColor: this.resolvePressedBackgroundColor(),
      downloadProgressColor: this.storedAccentColor,
      downloadIndicatorState: this.downloadIndicatorState,
      chromeIconTone: this.resolveChromeIconTone(),
      reliableActionsEnabled: this.reliableHeaderActionEnabled,
      addressContextMenuEnabled: true,
      editingLayer: () => {
        this.buildBottomChromeEditingLayer()
      },
      onIntent: (intent: BrowserBottomChromeTapIntent) => {
        this.handleBottomChromeIntent(intent);
      },
      onLongPressIntent: (intent: BrowserBottomChromeTapIntent) => {
        this.onToolbarLongPress(intent.slotId);
      },
      onAddressContextAction: (action: BrowserBottomAddressContextAction) => {
        this.onAddressContextAction(action);
      },
      onSelectSearchEngine: (engineId: SearchEngineId) => {
        this.onSelectSearchEngine(engineId);
      },
      onEditingFocusReady: () => {
        this.handleBottomChromeEditingFocusReady();
      }
    })
      .width('100%')
      .height(WEB_BOTTOM_ADDRESS_BAR_HEIGHT)
  }

  @Builder
  private buildLegacyViewerToolbarHeader() {
    Row({ space: 0 }) {
      Stack({ alignContent: Alignment.Center }) {
        this.buildHeaderCenterContent()
      }
      .layoutWeight(1)
      .constraintSize({ minWidth: 1 })
      .height(WEB_BOTTOM_ADDRESS_BAR_HEIGHT)
      .clip(true)
      if (this.viewerInfoActionEnabled) {
        this.buildViewerActionRail()
      }
    }
    .width('100%')
    .height(WEB_BOTTOM_ADDRESS_BAR_HEIGHT)
    .padding({ left: WEB_BOTTOM_ADDRESS_HORIZONTAL_PADDING, right: WEB_BOTTOM_ADDRESS_HORIZONTAL_PADDING })
  }

  @Builder
  private buildViewerActionRail() {
    Row({ space: 0 }) {
      this.buildViewerActionSlots()
    }
    .width(WEB_BOTTOM_ADDRESS_BUTTON_SIZE * 2 + WEB_BOTTOM_ADDRESS_BUTTON_GAP)
    .height(WEB_BOTTOM_ADDRESS_BAR_HEIGHT)
  }

  @Builder
  private buildHeaderCenterContent() {
    if (this.centerActionEnabled) {
      this.buildCenterActionField()
    } else {
      this.buildAddressField()
    }
  }

  @Builder
  private buildHeaderFixedButtonGap() {
    Blank()
      .width(WEB_BOTTOM_ADDRESS_BUTTON_GAP)
      .height(1)
      .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildCenterActionField() {
    Button() {
      Row({ space: this.centerActionText.trim().length > 0 ? 6 : 0 }) {
        SymbolGlyph(this.centerActionIcon)
          .fontSize(WEB_BOTTOM_ADDRESS_ICON_SIZE)
          .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
          .fontColor([this.resolveIconColor(true)])

        if (this.centerActionText.trim().length > 0) {
          Text(this.centerActionText)
            .fontSize(15)
            .fontWeight(FontWeight.Regular)
            .fontColor(this.resolvePrimaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .width('100%')
      .height(WEB_BOTTOM_ADDRESS_INPUT_CONTENT_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolvePressedBackground('center-action'))
      .borderRadius(WEB_BOTTOM_CENTER_ACTION_PRESS_RADIUS)
    }
    .width('100%')
    .height(WEB_BOTTOM_ADDRESS_INPUT_CONTENT_HEIGHT)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .accessibilityText(this.centerActionAccessibilityText)
    .onTouch((event: TouchEvent) => {
      this.updatePressedAction('center-action', event.type, true);
    })
    .onClick(() => {
      this.runHeaderAction('center-action', true, () => {
        this.onAction('newTab');
      })
    })
  }

  @Builder
  private buildAddressField() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildBottomChromeEditingLayer()

      if (this.shouldShowWebProtectionConfirmation()) {
        this.buildWebProtectionConfirmation()
      } else {
        Text(this.getAddressText())
          .width('100%')
          .height(WEB_BOTTOM_ADDRESS_INPUT_CONTENT_HEIGHT)
          .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
          .lineHeight(WEB_BOTTOM_ADDRESS_INPUT_LINE_HEIGHT)
          .halfLeading(true)
          .textVerticalAlign(TextVerticalAlign.CENTER)
          .fontColor(this.resolveAddressTextColor())
          .fontWeight(FontWeight.Regular)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .opacity(this.resolveAddressTextOpacity())
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(WEB_BOTTOM_ADDRESS_INPUT_CONTENT_HEIGHT)
  }

  @Builder
  private buildWebProtectionConfirmation() {
    Row({ space: 6 }) {
      Stack({ alignContent: Alignment.Center }) {
        AiraIcon({
          airaIconId: 'settings.privacySecurity',
          iconSize: 23,
          iconColor: this.resolvePrimaryTextColor()
        })
      }
      .width(24)
      .height(24)

      Text(this.liveBottomChromePresentation.centerContent.webProtectionFeedback.displayText)
        .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
          .lineHeight(WEB_BOTTOM_ADDRESS_INPUT_LINE_HEIGHT)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(WEB_BOTTOM_ADDRESS_INPUT_CONTENT_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .opacity(this.resolveAddressTextOpacity())
    .accessibilityText(this.liveBottomChromePresentation.centerContent.webProtectionFeedback.accessibilityLabel)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildBottomChromeEditingLayer() {
    TextInput({
      text: this.editingAddressText,
      placeholder: this.resolveAddressInputPlaceholder(),
      controller: this.addressInputController
    })
      .id(WEB_BOTTOM_INPUT_FOCUS_ID)
      .width('100%')
      .height('100%')
      .fontSize(BROWSER_BOTTOM_CHROME_TEXT_SIZE)
      .halfLeading(true)
      .padding({
        left: BROWSER_BOTTOM_ADDRESS_INPUT_SELECTION_HANDLE_INSET,
        right: BROWSER_BOTTOM_ADDRESS_INPUT_SELECTION_HANDLE_INSET,
        top: 0,
        bottom: 0
      })
      .fontColor(this.resolvePrimaryTextColor())
      .placeholderColor(this.resolveSecondaryTextColor())
      .fontWeight(FontWeight.Regular)
      .caretColor(this.storedAccentColor)
      .textAlign(TextAlign.Start)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .borderRadius(0)
      .type(InputType.URL)
      .enterKeyType(EnterKeyType.Go)
      .focusable(this.addressInputAdapterActive)
      .focusOnTouch(this.addressInputAdapterActive)
      .enableKeyboardOnFocus(this.addressInputAdapterActive)
      .stopBackPress(false)
      .hitTestBehavior(this.addressInputAdapterActive ? HitTestMode.Default : HitTestMode.None)
      .onAppear(() => {
        this.addressInputMounted = true;
        this.requestAddressFocusIfPending();
      })
      .onDisAppear(() => {
        this.addressInputMounted = false;
        this.addressInputActuallyFocused = false;
        this.clearAddressFocusTimeout();
        this.addressFocusAttemptCount = 0;
      })
      .onAreaChange((_oldValue: Area, _newValue: Area) => {
        this.requestAddressFocusIfPending();
      })
      .onFocus(() => {
        this.addressInputActuallyFocused = true;
        this.acknowledgeAddressFocus();
        this.scheduleWebAddressSelectAll();
      })
      .onBlur(() => {
        this.addressInputActuallyFocused = false;
      })
      .onChange((value: string) => {
        this.handleAddressInputChange(value);
      })
      .onPaste((content: string, event: PasteEvent) => {
        this.handleAddressInputPaste(content, event);
      })
      .onSubmit((_enterKey: EnterKeyType) => {
        const submittedText = this.editingAddressText;
        this.onAddressSubmit(submittedText);
      })
  }

  @Builder
  private buildViewerActionSlots() {
    this.buildHeaderImageIconButton(undefined, '主页', true, 'viewerHome', () => {
      this.onAction('home');
    }, 0, 0, 'browser.shortcut.home')
    this.buildHeaderFixedButtonGap()
    this.buildHeaderImageIconButton(undefined, '文件信息', true, 'viewerInfo', () => {
      this.onAction('viewerInfo');
    }, 0, 0, 'browser.toolbar.siteInfo')
  }

  @Builder
  private buildHeaderImageIconButton(
    imageIcon: Resource | undefined,
    accessibilityText: string,
    enabled: boolean,
    actionId: string,
    action: () => void,
    renderVersion: number = 0,
    rotationAngle: number = 0,
    airaIconId: AiraRenderableIconId | undefined = undefined
  ) {
    Button() {
      Stack({ alignContent: Alignment.Center }) {
        if (airaIconId !== undefined) {
          AiraIcon({
            airaIconId: airaIconId,
            iconSize: WEB_BOTTOM_ADDRESS_IMAGE_ICON_SIZE,
            iconColor: this.resolveIconColor(enabled)
          })
            .rotate({ angle: rotationAngle })
            .opacity(this.resolveActionIconOpacity(enabled))
        } else if (imageIcon !== undefined) {
          ForEach([this.buildHeaderImageIconRenderKey(actionId, renderVersion, rotationAngle)], (_renderKey: string) => {
            Image(imageIcon)
              .width(WEB_BOTTOM_ADDRESS_IMAGE_ICON_SIZE)
              .height(WEB_BOTTOM_ADDRESS_IMAGE_ICON_SIZE)
              .objectFit(ImageFit.Contain)
              .rotate({ angle: rotationAngle })
              .opacity(this.resolveActionIconOpacity(enabled))
          }, (renderKey: string) => renderKey)
        }
      }
      .width(WEB_BOTTOM_ADDRESS_BUTTON_SIZE)
      .height(WEB_BOTTOM_ADDRESS_BUTTON_SIZE)
      .backgroundColor(this.resolvePressedBackground(actionId))
      .borderRadius(WEB_BOTTOM_ADDRESS_BUTTON_SIZE / 2)
    }
    .width(WEB_BOTTOM_ADDRESS_BUTTON_SIZE)
    .height(WEB_BOTTOM_ADDRESS_BUTTON_SIZE)
    .type(ButtonType.Circle)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .focusable(false)
    .focusOnTouch(false)
    .enabled(true)
    .accessibilityText(accessibilityText)
    .hitTestBehavior(this.shouldHeaderActionReceiveTouch(enabled) ? HitTestMode.Default : HitTestMode.None)
    .scale({
      x: this.resolveHeaderButtonEnterScale(),
      y: this.resolveHeaderButtonEnterScale()
    })
    .opacity(this.resolveHeaderIconButtonOpacity(enabled))
    .animation({ duration: WEB_BOTTOM_ADDRESS_TEXT_FADE_MS, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      this.updatePressedAction(actionId, event.type, enabled);
    })
    .onClick(() => {
      this.runHeaderAction(actionId, enabled, action);
    })
  }

  @Builder
  private buildExpandedContent() {
    if (this.shouldUseFloatingActionPanel()) {
      this.buildFloatingActionPanelContent()
    } else {
      this.buildAttachedExpandedContent()
    }
  }

  @Builder
  private buildFloatingActionPanelContent() {
    Row() {
      Column({ space: 0 }) {
        if (this.shouldRenderFloatingActionSurface()) {
          if (this.shouldRenderUnifiedQuickActionsContent()) {
            this.buildFloatingQuickActionPageContent()
          } else if (this.shouldRenderPrimaryActionsContent()) {
            this.buildPrimaryActionsContent()
          }
        } else {
          Blank()
            .width('100%')
            .height(WEB_BOTTOM_EXPANDED_CONTENT_IDLE_HEIGHT)
        }
      }
      .width(this.resolveContentWidth())
      .constraintSize({ maxWidth: this.resolveContentMaxWidthConstraint() })
      .height(this.resolveFloatingQuickActionLayoutState().fullSurfaceHeight +
        this.resolveReadingContinuationHeight())
    }
    .width('100%')
    .height(this.resolveFloatingQuickActionLayoutState().fullSurfaceHeight +
      this.resolveReadingContinuationHeight())
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildAttachedExpandedContent() {
    Row() {
      Column({ space: 0 }) {
        if (this.shouldRenderQuickActionArea()) {
          Blank()
            .width('100%')
            .height(this.responsiveState.quickActionTopGap)
        }

        if (this.shouldMountExpandedScrollContent()) {
          Scroll(this.panelContentScroller) {
            Column({ space: 0 }) {
              if (this.shouldRenderUnifiedQuickActionsContent()) {
                if (this.shouldShowReadingContinuation()) {
                  this.buildReadingContinuationRow()
                }
                this.buildQuickActionGrid(
                  this.resolveUnifiedQuickActions(),
                  this.resolveFloatingQuickActionLayoutState()
                )
              } else if (this.shouldRenderPrimaryActionsContent()) {
                this.buildPrimaryActionsContent()
              }

              if (this.shouldRenderSecondaryActionsContent()) {
                Column() {
                  this.buildSecondaryActionsContent()
                }
                .width('100%')
                .margin({ top: this.responsiveState.secondaryActionListTopGap })
              }
            }
            .width('100%')
            .constraintSize({ minHeight: '100%' })
            .padding({ left: this.responsiveState.contentHorizontalPadding, right: this.responsiveState.contentHorizontalPadding })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollable(this.shouldDisableExpandedContentVerticalScroll() ? ScrollDirection.None : ScrollDirection.Vertical)
          .scrollBar(this.shouldDisableExpandedContentVerticalScroll() ? BarState.Off : BarState.Auto)
          .edgeEffect(this.shouldDisableExpandedContentVerticalScroll() ? EdgeEffect.None : EdgeEffect.Spring,
            { alwaysEnabled: true })
        } else {
          Blank()
            .width('100%')
            .height(WEB_BOTTOM_EXPANDED_CONTENT_IDLE_HEIGHT)
            .layoutWeight(1)
        }
      }
      .width(this.resolveContentWidth())
      .constraintSize({ maxWidth: this.resolveContentMaxWidthConstraint() })
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildPrimaryActionsContent() {
    Column({ space: this.responsiveState.quickActionRowGap }) {
      ForEach(this.resolvePrimaryActionRows(), (row: BrowserBottomAddressPanelActionGridRow) => {
        Row({ space: this.responsiveState.quickActionColumnGap }) {
          ForEach(row.actions, (item: BrowserBottomAddressPanelAction) => {
            this.buildQuickActionCard(
              item,
              this.resolveQuickActionButtonSize(),
              this.responsiveState.quickActionCardHeight
            );
          }, (item: BrowserBottomAddressPanelAction) => this.buildActionRenderKey(item))

          ForEach(this.resolvePrimaryActionPlaceholderIndexes(
            row.actions.length,
            this.resolveQuickActionColumnCount()
          ),
            (placeholderIndex: number) => {
              Blank()
                .layoutWeight(1)
                .constraintSize({ minWidth: 0 })
            }, (placeholderIndex: number) => `${row.rowIndex}-${placeholderIndex}`)
        }
        .width('100%')
        .height(this.responsiveState.quickActionCardHeight)
      }, (row: BrowserBottomAddressPanelActionGridRow) => `${row.rowIndex}-${row.actions.length}`)
    }
    .width('100%')
    .height(this.resolvePrimaryActionGridHeight())
    .padding({
      left: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      right: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      top: WEB_BOTTOM_QUICK_ACTION_GROUP_VERTICAL_PADDING,
      bottom: WEB_BOTTOM_QUICK_ACTION_GROUP_VERTICAL_PADDING
    })
  }

  @Builder
  private buildFloatingQuickActionPageContent() {
    ForEach([this.resolveToolbarRenderSnapshot().layoutState],
      (layoutState: BrowserBottomToolbarQuickActionLayoutState) => {
        Column({ space: 0 }) {
          Row() {
            if (this.shouldShowToolbarExpansionHint()) {
              AiraIcon({
                airaIconId: WEB_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_ID,
                iconSize: BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_SIZE,
                iconColor: this.resolveQuickActionLabelColor(true)
              })
                .rotate({ angle: this.resolveToolbarExpansionHintRotationAngle() })
                .animation({
                  duration: WEB_BOTTOM_TOOLBAR_EXPANSION_HINT_ROTATION_DURATION_MS,
                  curve: Curve.EaseInOut
                })
            }
          }
          .width('100%')
          .height(layoutState.expansionHintSlotHeight)
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.Transparent)

          Blank()
            .width('100%')
            .height(layoutState.expansionHintBottomGap)

          if (this.shouldShowReadingContinuation()) {
            this.buildReadingContinuationRow()
          }

          this.buildQuickActionGrid(this.resolveToolbarRenderSnapshot().actions, layoutState);
        }
        .width('100%')
        .height(layoutState.fullSurfaceHeight + this.resolveReadingContinuationHeight())
        .padding({
          top: layoutState.surfaceVerticalPadding,
          bottom: layoutState.surfaceVerticalPadding
        })
        .hitTestBehavior(HitTestMode.Transparent)
      }, (_layoutState: BrowserBottomToolbarQuickActionLayoutState) =>
        this.resolveToolbarRenderSnapshot().layoutRenderKey)
  }

  @Builder
  private buildReadingContinuationRow() {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        AiraIcon({
          airaIconId: 'browser.toolbar.reader',
          iconSize: WEB_BOTTOM_READING_CONTINUATION_ICON_SIZE,
          iconColor: this.resolveQuickActionLabelColor(true)
        })

        Column({ space: 2 }) {
          Text('继续阅读')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.resolveQuickActionLabelColor(true))
            .maxLines(1)

          Text(this.liveReadingContinuation.title)
            .fontSize(13)
            .fontColor(this.resolveQuickActionLabelColor(false))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        if (this.liveReadingContinuation.loading) {
          LoadingProgress()
            .width(WEB_BOTTOM_READING_CONTINUATION_TRAILING_ICON_SIZE)
            .height(WEB_BOTTOM_READING_CONTINUATION_TRAILING_ICON_SIZE)
            .color(this.resolveQuickActionLabelColor(false))
        } else {
          AiraIcon({
            airaIconId: 'browser.toolbar.back',
            iconSize: WEB_BOTTOM_READING_CONTINUATION_TRAILING_ICON_SIZE,
            iconColor: this.resolveQuickActionLabelColor(false)
          })
            .rotate({ angle: 180 })
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(WEB_BOTTOM_READING_CONTINUATION_HEIGHT)
    .padding({
      left: WEB_BOTTOM_READING_CONTINUATION_HORIZONTAL_PADDING,
      right: WEB_BOTTOM_READING_CONTINUATION_HORIZONTAL_PADDING
    })
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(16)
    .stateEffect(true)
    .enabled(!this.liveReadingContinuation.loading)
    .accessibilityText(`继续阅读${this.liveReadingContinuation.title}`)
    .onClick((): void => {
      this.onContinueReading();
    })
  }

  @Builder
  private buildQuickActionGrid(
    actions: BrowserBottomAddressPanelAction[],
    layoutState: BrowserBottomToolbarQuickActionLayoutState
  ) {
    List({ space: layoutState.rowGap }) {
      if (this.shouldEnableQuickActionReorder()) {
        ForEach(actions, (item: BrowserBottomAddressPanelAction, index: number) => {
          ListItem() {
            Row() {
              ForEach([this.buildActionRenderKey(item)], (_renderKey: string) => {
                this.buildQuickActionCard(
                  item,
                  layoutState.buttonSize,
                  layoutState.cardHeight
                );
              }, (renderKey: string) => renderKey)
            }
            .width('100%')
            .height('100%')
            .transition(this.resolveQuickActionRowEntryTransition(
              this.resolveQuickActionEntryRowIndex(index, layoutState.columnCount)
            ))
          }
          .width('100%')
          .height(layoutState.cardHeight)
        }, (item: BrowserBottomAddressPanelAction) => item.id)
          .onMove((from: number, to: number) => {
            this.handleQuickActionNativeMove(from, to);
          }, {
            onLongPress: (index: number) => {
              this.beginQuickActionNativeDrag(index, true);
            },
            onDragStart: (index: number) => {
              this.beginQuickActionNativeDrag(index, false);
            },
            onDrop: (_index: number) => {
              this.endQuickActionNativeDrag();
            }
          })
      } else {
        ForEach(actions, (item: BrowserBottomAddressPanelAction, index: number) => {
          ListItem() {
            Row() {
              ForEach([this.buildActionRenderKey(item)], (_renderKey: string) => {
                this.buildQuickActionCard(
                  item,
                  layoutState.buttonSize,
                  layoutState.cardHeight
                );
              }, (renderKey: string) => renderKey)
            }
            .width('100%')
            .height('100%')
            .transition(this.resolveQuickActionRowEntryTransition(
              this.resolveQuickActionEntryRowIndex(index, layoutState.columnCount)
            ))
          }
          .width('100%')
          .height(layoutState.cardHeight)
        }, (item: BrowserBottomAddressPanelAction) => item.id)
      }
    }
    .width('100%')
    .height(layoutState.gridHeight)
    .lanes(layoutState.columnCount, layoutState.columnGap)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
    .clip(false)
    .padding({
      left: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      right: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      top: layoutState.groupVerticalPadding,
      bottom: layoutState.groupVerticalPadding
    })
  }

  @Builder
  private buildFloatingSuggestionContent() {
    BrowserSearchListSurface({
      presentation: {
        suggestions: this.homeSuggestionsVisible ? this.homeSuggestions : [],
        externalTargets: this.shouldShowExternalAppSearchTargets() ? this.resolveExternalAppSearchTargets() : [],
        query: this.editingAddressText,
        blankAreaBackEnabled: this.isAddressInputPresentationActive(),
        currentTabSuggestionRefId: this.currentTabSuggestionRefId,
        hostLayout: {
          surfaceWidth: this.responsiveState.panelWidth,
          contentHorizontalPadding: this.responsiveState.contentHorizontalPadding,
          widthBreakpoint: this.responsiveState.widthBreakpoint,
          heightBreakpoint: this.responsiveState.heightBreakpoint,
          aspectBreakpoint: this.responsiveState.aspectBreakpoint
        },
        pressedBackgroundColor: this.resolvePressedBackgroundColor(),
        foreground: this.resolveSearchForegroundPresentation()
      },
      onIntent: (intent: BrowserSearchListSurfaceIntent) => {
        this.handleSearchListSurfaceIntent(intent);
      }
    })
  }

  private handleSearchListSurfaceIntent(intent: BrowserSearchListSurfaceIntent): void {
    if (intent.kind === 'open_suggestion') {
      this.dispatchHomeSuggestion(intent.suggestion);
      return;
    }
    if (intent.kind === 'delete_history_suggestion') {
      this.onDeleteHistorySuggestion(intent.suggestion);
      return;
    }
    if (intent.kind === 'blank_back') {
      this.onSearchBlankAreaBack();
      return;
    }
    if (intent.kind !== 'external_search') {
      return;
    }
    this.onExternalAppSearch(intent.targetId, intent.query);
  }

  private shouldShowExternalAppSearchTargets(): boolean {
    return this.externalAppSearchService.shouldShowTargets({
      inputEditing: this.addressInputAdapterActive,
      inputFocused: this.addressFocused,
      preferences: this.externalAppSearchPreferences
    });
  }

  private resolveExternalAppSearchTargets(): ExternalAppSearchTarget[] {
    return this.externalAppSearchService.listVisibleTargets({
      inputEditing: this.addressInputAdapterActive,
      inputFocused: this.addressFocused,
      preferences: this.externalAppSearchPreferences
    });
  }

  private refreshExternalAppSearchPreferences(): void {
    void this.externalAppSearchPreferencesRevision;
    this.externalAppSearchPreferences = sharedExternalAppSearchPreferencesRepository.getSettings();
  }

  @Builder
  private buildQuickActionCard(
    item: BrowserBottomAddressPanelAction,
    buttonSize: number,
    cardHeight: number,
    toolbarSystemSheetAction: boolean = false
  ) {
    Row() {
      HomeSearchQuickActionCard({
        imageIcon: item.imageIcon,
        airaIconId: this.resolveActionAiraIconId(item),
        label: item.title,
        cardEnabled: item.enabled,
        cardImageFillColor: toolbarSystemSheetAction ?
          this.resolveToolbarSystemSheetActionIconColor(item) : this.resolveQuickActionCardImageFillColor(item),
        cardLabelColor: toolbarSystemSheetAction ?
          this.resolveItemTextColor(item.enabled) : this.resolveQuickActionLabelColor(item.enabled),
        cardBackgroundColor: toolbarSystemSheetAction ?
          this.resolveToolbarSystemSheetActionBackgroundColor(item) : this.resolveQuickActionCardBackgroundColor(item),
        cardDisabledOpacity: 1,
        cardBorderWidth: 0,
        buttonSize,
        imageRenderVersion: this.resolveActionRenderVersion(item),
        action: () => {
          if (toolbarSystemSheetAction) {
            this.requestToolbarSystemSheetAction(item);
            return;
          }
          this.dispatchPanelAction(item);
        }
      })
    }
    .layoutWeight(1)
    .height(cardHeight)
  }

  private resolveQuickActionRowEntryTransition(rowIndex: number): TransitionEffect {
    if (!this.floatingActionContentEntryActive || rowIndex < 0) {
      return TransitionEffect.IDENTITY;
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.translate({ y: WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_TRANSLATE_Y }).animation({
        duration: WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_DURATION_MS,
        curve: Curve.EaseOut,
        delay: this.resolveQuickActionRowEntryDelayMs(rowIndex)
      }),
      TransitionEffect.IDENTITY
    );
  }

  private resolveQuickActionEntryRowIndex(index: number, columnCount: number): number {
    const safeColumnCount = Math.max(1, Math.floor(columnCount));
    return Math.floor(Math.max(0, index) / safeColumnCount);
  }

  private resolveQuickActionRowEntryDelayMs(rowIndex: number): number {
    const safeRowIndex = Math.max(0, Math.floor(rowIndex));
    return Math.min(
      WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_MAX_DELAY_MS,
      safeRowIndex * WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_STAGGER_MS
    );
  }

  private beginFloatingActionContentEntry(): void {
    this.clearFloatingActionContentEntry();
    this.floatingActionContentEntryActive = true;
    this.floatingActionContentEntryTimer = setTimeout(() => {
      this.floatingActionContentEntryTimer = -1;
      this.floatingActionContentEntryActive = false;
    }, WEB_BOTTOM_QUICK_ACTION_ROW_ENTRY_BARRIER_MS);
  }

  private clearFloatingActionContentEntry(): void {
    if (this.floatingActionContentEntryTimer >= 0) {
      clearTimeout(this.floatingActionContentEntryTimer);
      this.floatingActionContentEntryTimer = -1;
    }
    this.floatingActionContentEntryActive = false;
  }

  @Builder
  private buildSecondaryActionsContent() {
    Column({ space: this.responsiveState.secondaryActionRowGap }) {
      ForEach(this.resolveExpandedSecondaryActions(), (item: BrowserBottomAddressPanelAction) => {
        this.buildSecondaryActionRow(item)
      }, (item: BrowserBottomAddressPanelAction) => this.buildActionRenderKey(item))
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildSecondaryActionRow(item: BrowserBottomAddressPanelAction) {
    Button() {
      Row({ space: 10 }) {
        ForEach([this.buildActionRenderKey(item)], (_renderKey: string) => {
          this.buildSecondaryActionImageIcon(item)
        }, (renderKey: string) => renderKey)

        Text(item.title)
          .fontSize(WEB_BOTTOM_LIST_TEXT_SIZE)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.resolveSecondaryActionTextColor(item))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if ((item.trailingText ?? '').length > 0) {
          Text(item.trailingText ?? '')
            .fontSize(WEB_BOTTOM_LIST_TRAILING_TEXT_SIZE)
            .fontColor(this.resolveSecondaryActionTrailingTextColor(item))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 88 })
        }
      }
      .width('100%')
      .height(this.resolveSecondaryActionRowHeight())
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.resolveSecondaryActionRowHeight())
    .type(ButtonType.Normal)
    .backgroundColor(this.resolveSecondaryActionBackgroundColor(item, this.buildPanelActionPressKey(item)))
    .borderRadius(16)
    .stateEffect(false)
    .scale({
      x: this.resolveSecondaryActionScale(this.buildPanelActionPressKey(item)),
      y: this.resolveSecondaryActionScale(this.buildPanelActionPressKey(item))
    })
    .animation({
      duration: this.pressedActionId === this.buildPanelActionPressKey(item) ? WEB_BOTTOM_SECONDARY_ACTION_PRESS_DURATION_MS :
      WEB_BOTTOM_SECONDARY_ACTION_RELEASE_DURATION_MS,
      curve: this.pressedActionId === this.buildPanelActionPressKey(item) ? Curve.EaseOut :
      'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressedAction(this.buildPanelActionPressKey(item), event.type, item.enabled);
    })
    .onClick(() => {
      this.dispatchPanelAction(item);
    })
  }

  @Builder
  private buildSecondaryActionImageIcon(item: BrowserBottomAddressPanelAction) {
    if (this.resolveActionAiraIconId(item) !== undefined) {
      AiraIcon({
        airaIconId: this.resolveActionAiraIconId(item),
        iconSize: WEB_BOTTOM_LIST_IMAGE_ICON_SIZE,
        iconColor: this.resolveSecondaryActionOperationalIconColor(item)
      })
        .opacity(this.resolveActionIconOpacity(item.enabled))
    } else if (this.resolveSecondaryActionImageFillColor(item) !== undefined) {
      Image(this.resolveActionImageIcon(item))
        .width(WEB_BOTTOM_LIST_IMAGE_ICON_SIZE)
        .height(WEB_BOTTOM_LIST_IMAGE_ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .opacity(this.resolveActionIconOpacity(item.enabled))
        .fillColor(this.resolveSecondaryActionImageFillColor(item) as ResourceColor)
    } else {
      Image(this.resolveActionImageIcon(item))
        .width(WEB_BOTTOM_LIST_IMAGE_ICON_SIZE)
        .height(WEB_BOTTOM_LIST_IMAGE_ICON_SIZE)
        .objectFit(ImageFit.Contain)
        .opacity(this.resolveActionIconOpacity(item.enabled))
    }
  }

  private resolveSecondaryActionRowHeight(): number {
    return Math.max(this.responsiveState.secondaryActionRowHeight, WEB_BOTTOM_SECONDARY_CARD_ROW_MIN_HEIGHT);
  }

  private resolvePrimaryActions(): BrowserBottomAddressPanelAction[] {
    const liveSnapshot = this.resolveLiveActionSnapshot();
    const primaryActionOverrides = liveSnapshot !== undefined
      ? liveSnapshot.primaryActionOverrides
      : this.primaryActionOverrides;
    if (primaryActionOverrides !== undefined) {
      if (this.quickActionsOnly) {
        return this.resolveCurrentPanelActionStates(primaryActionOverrides);
      }
      return this.resolveCurrentPanelActionStates(
        primaryActionOverrides.slice(0, this.resolveQuickActionLimit())
      );
    }
    return this.resolveCurrentPanelActionStates(
      this.viewModel.buildPrimaryActions(this.buildActionInput(), this.resolveQuickActionLimit())
    );
  }

  private resolveSecondaryActions(): BrowserBottomAddressPanelAction[] {
    const liveSnapshot = this.resolveLiveActionSnapshot();
    const secondaryActionOverrides = liveSnapshot !== undefined
      ? liveSnapshot.secondaryActionOverrides
      : this.secondaryActionOverrides;
    if (secondaryActionOverrides !== undefined) {
      return this.resolveCurrentPanelActionStates(
        filterBrowserBottomAddressPanelActionsHiddenByVisiblePrimary(
          secondaryActionOverrides,
          this.resolvePrimaryActions()
        )
      );
    }
    return this.resolveCurrentPanelActionStates(
      this.viewModel.buildSecondaryActions(this.buildActionInput(), this.resolvePrimaryActions())
    );
  }

  private resolveCurrentPanelActionStates(
    actions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    return actions.map((action: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelAction => {
      return this.resolveCurrentPanelActionState(action);
    });
  }

  private resolveCurrentPanelActionState(action: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelAction {
    if (action.id === 'appProxySettings') {
      const appProxyActive = this.buildActionInput().appProxyActive === true;
      return {
        id: action.id,
        title: action.title,
        trailingText: action.trailingText,
        icon: action.icon,
        imageIcon: action.imageIcon,
        airaIconId: action.airaIconId,
        enabled: action.enabled,
        disabledMessage: action.disabledMessage,
        selected: appProxyActive,
        renderVersion: appProxyActive ? (action.renderVersion ?? 0) + 1 : action.renderVersion
      };
    }
    if (action.id !== 'newPrivateTab') {
      return action;
    }
    const privateModeActive = this.buildActionInput().privateModeActive;
    return {
      id: action.id,
      title: privateModeActive ? '退出隐私模式' : '隐私模式',
      trailingText: privateModeActive ? '退出' : '私密',
      icon: action.icon,
      airaIconId: 'browser.toolbar.privacyMode',
      enabled: action.enabled,
      disabledMessage: action.disabledMessage,
      selected: privateModeActive,
      renderVersion: privateModeActive ? 1 : 0
    };
  }

  private resolveUnifiedQuickActions(): BrowserBottomAddressPanelAction[] {
    return this.resolveToolbarRenderSnapshot().actions;
  }

  private resolveBaseUnifiedQuickActions(): BrowserBottomAddressPanelAction[] {
    if (!this.shouldRenderUnifiedQuickActionsContent()) {
      return this.resolvePrimaryActions();
    }
    const liveSnapshot = this.resolveLiveActionSnapshot();
    const quickActionOverrides = liveSnapshot !== undefined
      ? liveSnapshot.quickActionOverrides
      : this.quickActionOverrides;
    if (quickActionOverrides !== undefined) {
      return this.resolveCurrentPanelActionStates(quickActionOverrides);
    }
    const actions: BrowserBottomAddressPanelAction[] = [];
    this.resolvePrimaryActions().concat(this.resolveSecondaryActions()).forEach((action: BrowserBottomAddressPanelAction) => {
      if (actions.some((item: BrowserBottomAddressPanelAction) => item.id === action.id)) {
        return;
      }
      actions.push(action);
    });
    return actions;
  }

  private applyLiveQuickActionOrder(
    actions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    if (this.liveQuickActionOrderIds.length <= 0) {
      return actions;
    }
    const orderedActions: BrowserBottomAddressPanelAction[] = [];
    this.liveQuickActionOrderIds.forEach((actionId: BrowserBottomAddressPanelActionId) => {
      const action = actions.find((item: BrowserBottomAddressPanelAction) => item.id === actionId);
      if (action !== undefined) {
        orderedActions.push(action);
      }
    });
    actions.forEach((action: BrowserBottomAddressPanelAction) => {
      if (!orderedActions.some((item: BrowserBottomAddressPanelAction) => item.id === action.id)) {
        orderedActions.push(action);
      }
    });
    return orderedActions;
  }

  private resolveExpandedSecondaryActions(): BrowserBottomAddressPanelAction[] {
    if (this.quickActionsOnly) {
      return [];
    }
    if (this.shouldRenderUnifiedQuickActionsContent()) {
      return this.resolveUnifiedQuickActions().slice(this.resolveToolbarPreviewActionLimit());
    }
    return this.resolveSecondaryActions();
  }

  private resolveQuickActionRowsForActions(
    actions: BrowserBottomAddressPanelAction[],
    columnCount: number = this.resolveQuickActionColumnCount()
  ): BrowserBottomAddressPanelActionGridRow[] {
    const columns = Math.max(1, Math.floor(columnCount));
    const rows: BrowserBottomAddressPanelActionGridRow[] = [];
    for (let index = 0; index < actions.length; index += columns) {
      rows.push({
        rowIndex: rows.length,
        actions: actions.slice(index, index + columns)
      });
    }
    return rows;
  }

  private buildQuickActionLayoutRenderKey(
    layoutState: BrowserBottomToolbarQuickActionLayoutState
  ): string {
    return `${this.liveBottomChromePresentation.contentPresentation}:layout:` +
      `columns=${layoutState.columnCount}:` +
      `panel=${this.roundLayoutValue(this.responsiveState.panelWidth)}:` +
      `content=${this.roundLayoutValue(this.responsiveState.contentMaxWidth)}:` +
      `pad=${this.roundLayoutValue(this.responsiveState.contentHorizontalPadding)}:` +
      `colGap=${this.roundLayoutValue(layoutState.columnGap)}:` +
      `rowGap=${this.roundLayoutValue(layoutState.rowGap)}:` +
      `card=${this.roundLayoutValue(layoutState.cardHeight)}:` +
      `button=${this.roundLayoutValue(layoutState.buttonSize)}:` +
      `groupPad=${this.roundLayoutValue(layoutState.groupVerticalPadding)}:` +
      `surfacePad=${this.roundLayoutValue(layoutState.surfaceVerticalPadding)}:` +
      `hint=${this.roundLayoutValue(layoutState.expansionHintSlotHeight)}:` +
      `hintGap=${this.roundLayoutValue(layoutState.expansionHintBottomGap)}`;
  }

  private roundLayoutValue(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }

  private resolvePrimaryActionRows(): BrowserBottomAddressPanelActionGridRow[] {
    return this.resolveQuickActionRowsForActions(this.resolvePrimaryActions());
  }

  private resolvePrimaryActionGridHeight(): number {
    return this.resolvePrimaryActionGridHeightForActionCount(this.resolvePrimaryActions().length);
  }

  private resolvePrimaryActionGridHeightForActionCount(actionCount: number): number {
    const rowCount = Math.ceil(Math.max(0, actionCount) / this.resolveQuickActionColumnCount());
    if (rowCount <= 0) {
      return 0;
    }
    return rowCount * this.responsiveState.quickActionCardHeight +
      (rowCount - 1) * this.responsiveState.quickActionRowGap +
      WEB_BOTTOM_QUICK_ACTION_GROUP_VERTICAL_PADDING * 2;
  }

  private resolveQuickActionButtonSize(): number {
    return BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE;
  }

  private resolveFloatingQuickActionLayoutState(): BrowserBottomToolbarQuickActionLayoutState {
    return this.resolveToolbarRenderSnapshot().layoutState;
  }

  private buildFloatingQuickActionLayoutState(actionCount: number): BrowserBottomToolbarQuickActionLayoutState {
    return this.toolbarExpansionViewModel.resolveQuickActionLayout({
      actionCount: actionCount,
      availableWidth: this.resolveFloatingQuickActionLayoutWidth(),
      availableHeight: Math.max(1,
        this.resolveFloatingQuickActionLayoutHeight() - this.resolveReadingContinuationHeight()),
      preferredColumns: this.resolveQuickActionColumnCount(),
      maxColumns: WEB_BOTTOM_QUICK_ACTION_MAX_COLUMNS,
      buttonSize: BROWSER_BOTTOM_QUICK_ACTION_BUTTON_SIZE,
      labelBlockHeight: BROWSER_BOTTOM_QUICK_ACTION_VERTICAL_GAP + BROWSER_BOTTOM_QUICK_ACTION_LABEL_LINE_HEIGHT,
      columnGap: this.responsiveState.quickActionColumnGap,
      rowGap: this.responsiveState.quickActionRowGap,
      groupHorizontalPadding: BROWSER_BOTTOM_QUICK_ACTION_GROUP_HORIZONTAL_PADDING,
      groupVerticalPadding: WEB_BOTTOM_QUICK_ACTION_GROUP_VERTICAL_PADDING,
      surfaceVerticalPadding: this.responsiveState.quickActionTopGap,
      expansionHintSlotHeight: BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_ICON_SIZE,
      expansionHintBottomGap: BROWSER_BOTTOM_TOOLBAR_EXPANSION_HINT_BOTTOM_GAP
    });
  }

  private resolveToolbarRenderSnapshot(): BrowserBottomToolbarRenderSnapshot {
    const liveActionRevision = this.liveActionSnapshotRevision;
    const snapshot = this.toolbarRenderSnapshot;
    if (snapshot !== undefined &&
      snapshot.liveActionRevision === liveActionRevision &&
      snapshot.fallbackActionRevision === this.toolbarActionRevision &&
      snapshot.orderRevision === this.toolbarOrderRevision &&
      snapshot.layoutRevision === this.toolbarLayoutRevision &&
      snapshot.motionLayoutRevision === this.toolbarMotionLayoutRevision &&
      snapshot.presentationRevision === this.toolbarPresentationRevision &&
      snapshot.continuationRevision === this.liveReadingContinuationRevision) {
      return snapshot;
    }
    const actions = this.applyLiveQuickActionOrder(this.resolveBaseUnifiedQuickActions());
    const layoutState = this.buildFloatingQuickActionLayoutState(actions.length);
    const fullExpansionAvailable = this.shouldRenderFloatingActionSurface() &&
      layoutState.actionCount >
        this.toolbarExpansionViewModel.resolvePreviewActionLimit(layoutState.columnCount) &&
      layoutState.fullSurfaceHeight > layoutState.previewSurfaceHeight + 0.01;
    const nextSnapshot: BrowserBottomToolbarRenderSnapshot = {
      liveActionRevision: liveActionRevision,
      fallbackActionRevision: this.toolbarActionRevision,
      orderRevision: this.toolbarOrderRevision,
      layoutRevision: this.toolbarLayoutRevision,
      motionLayoutRevision: this.toolbarMotionLayoutRevision,
      presentationRevision: this.toolbarPresentationRevision,
      continuationRevision: this.liveReadingContinuationRevision,
      actions: actions,
      layoutState: layoutState,
      fullExpansionAvailable: fullExpansionAvailable,
      layoutRenderKey: this.buildQuickActionLayoutRenderKey(layoutState)
    };
    this.toolbarRenderSnapshot = nextSnapshot;
    return nextSnapshot;
  }

  private resolveFloatingQuickActionLayoutWidth(): number {
    const panelWidth = Math.max(0, this.responsiveState.panelWidth);
    const contentMaxWidth = Math.max(0, this.responsiveState.contentMaxWidth);
    if (contentMaxWidth <= 0) {
      return Math.max(1, panelWidth);
    }
    if (panelWidth <= 0) {
      return Math.max(1, contentMaxWidth);
    }
    return Math.max(1, Math.min(panelWidth, contentMaxWidth));
  }

  private resolveFloatingQuickActionLayoutHeight(): number {
    const panelHeight = Math.max(0, this.livePanelMotionState.panelHeight);
    if (panelHeight > 0) {
      return panelHeight;
    }
    return Math.max(1, this.responsiveState.panelMaxHeight);
  }

  private resolveToolbarPreviewActionLimit(): number {
    return this.toolbarExpansionViewModel.resolvePreviewActionLimit(this.resolveQuickActionColumnCount());
  }

  private resolveQuickActionLimit(): number {
    return Math.max(0, Math.floor(this.responsiveState.quickActionLimit));
  }

  private resolveQuickActionColumnCount(): number {
    const quickActionLimit = this.resolveQuickActionLimit();
    if (quickActionLimit <= 0) {
      return 1;
    }
    return Math.max(1, Math.min(
      quickActionLimit,
      WEB_BOTTOM_QUICK_ACTION_MAX_COLUMNS,
      this.resolvePlannedQuickActionColumnCount()
    ));
  }

  private resolvePlannedQuickActionColumnCount(): number {
    return Math.max(1, Math.min(WEB_BOTTOM_QUICK_ACTION_MAX_COLUMNS, Math.floor(this.responsiveState.quickActionColumns)));
  }

  private resolvePrimaryActionPlaceholderIndexes(actionCount: number, columnCount: number): number[] {
    const placeholderCount = Math.max(0, Math.max(1, Math.floor(columnCount)) - actionCount);
    const indexes: number[] = [];
    for (let index = 0; index < placeholderCount; index += 1) {
      indexes.push(index);
    }
    return indexes;
  }

  private resolveContentWidth(): Length {
    return this.responsiveState.contentMaxWidth > 0 ? '100%' : '100%';
  }

  private resolveContentMaxWidthConstraint(): Length {
    return this.responsiveState.contentMaxWidth > 0 ? this.responsiveState.contentMaxWidth : '100%';
  }

  private buildActionInput(): BrowserBottomAddressPanelBuildInput {
    const liveSnapshot = this.resolveLiveActionSnapshot();
    return liveSnapshot !== undefined ? liveSnapshot.actionInput : this.actionInput;
  }

  private buildActionRenderKey(item: BrowserBottomAddressPanelAction): string {
    return `${this.liveBottomChromePresentation.contentPresentation}:${item.id}:` +
      `${this.resolveActionRenderVersion(item)}:image:` +
      `${item.enabled ? 'enabled' : 'disabled'}:${item.selected === true ? 'selected' : 'idle'}:` +
      `${item.title}:${item.trailingText ?? ''}:${item.disabledMessage}`;
  }

  private buildPanelActionPressKey(item: BrowserBottomAddressPanelAction): string {
    return `panel-action-${item.id}`;
  }

  private resolveActionImageIcon(item: BrowserBottomAddressPanelAction): Resource {
    return item.imageIcon ?? $r('sys.media.ohos_ic_public_more');
  }

  private resolveActionAiraIconId(item: BrowserBottomAddressPanelAction): AiraRenderableIconId | undefined {
    if (item.airaIconId !== undefined) {
      return item.airaIconId;
    }
    if (item.imageIcon !== undefined) {
      return undefined;
    }
    return resolveBrowserBottomAddressPanelActionAiraIconId(item.id);
  }

  private resolveSecondaryActionOperationalIconColor(item: BrowserBottomAddressPanelAction): ResourceColor {
    return this.resolveSecondaryActionImageFillColor(item) ?? this.resolveSecondaryActionTextColor(item);
  }

  private resolveQuickActionCardBackgroundColor(item: BrowserBottomAddressPanelAction): ResourceColor {
    const actionBackgroundColor = this.buildQuickActionVisualState(item).backgroundColor;
    if (actionBackgroundColor !== undefined) {
      return actionBackgroundColor;
    }
    if (this.isHomeContentMode() || this.isWebContentMode()) {
      return resolveBrowserBottomAdaptiveQuickActionBackgroundColor(
        this.resolveSearchForegroundPresentation().tone
      );
    }
    return resolveBrowserBottomExpandedToolbarActionColor(this.resolveNeutralThemeMode());
  }

  private resolveQuickActionCardImageFillColor(item: BrowserBottomAddressPanelAction): ResourceColor | undefined {
    const actionColor = this.buildQuickActionVisualState(item).imageFillColor;
    if (actionColor !== undefined) {
      return actionColor;
    }
    if (this.isHomeContentMode() || this.isWebContentMode()) {
      return resolveBrowserBottomAdaptiveQuickActionIconColor(
        this.resolveSearchForegroundPresentation().tone
      );
    }
    return resolveBrowserBottomExpandedToolbarActionIconColor(this.resolveNeutralThemeMode());
  }

  private resolveToolbarSystemSheetActionBackgroundColor(
    item: BrowserBottomAddressPanelAction
  ): ResourceColor {
    const actionBackgroundColor = this.buildQuickActionVisualState(item).backgroundColor;
    return actionBackgroundColor ??
      resolveBrowserBottomExpandedToolbarActionColor(this.resolveNeutralThemeMode());
  }

  private resolveToolbarSystemSheetActionIconColor(
    item: BrowserBottomAddressPanelAction
  ): ResourceColor | undefined {
    const actionColor = this.buildQuickActionVisualState(item).imageFillColor;
    return actionColor ??
      resolveBrowserBottomExpandedToolbarActionIconColor(this.resolveNeutralThemeMode());
  }

  private buildQuickActionVisualState(item: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelActionVisualState {
    return this.actionVisualViewModel.buildState(item, {
      defaultSelectedBackgroundColor: this.storedAccentColor,
      appProxyActiveBackgroundColor: this.storedAppProxyActiveBackgroundColor,
      selectedForegroundColor: this.storedSelectedIconForegroundColor
    });
  }

  private resolveActionRenderVersion(action: BrowserBottomAddressPanelAction): number {
    const toneVersion = this.resolveChromeIconTone() === 'dark' ? 100000 : 0;
    return toneVersion + (action.renderVersion ?? 0);
  }

  private buildHeaderImageIconRenderKey(actionId: string, renderVersion: number, rotationAngle: number): string {
    return `${this.liveBottomChromePresentation.contentPresentation}:${actionId}:${this.resolveChromeIconTone()}:` +
      `${this.resolveNeutralThemeMode()}:${renderVersion}:${rotationAngle}`;
  }

  private resolveLeadingHeaderActions(): BrowserBottomAddressPanelHeaderAction[] {
    if (this.liveBottomChromePresentation.leadingHeaderActions.length > 0) {
      return this.liveBottomChromePresentation.leadingHeaderActions;
    }
    return [];
  }

  private resolveTrailingHeaderActions(): BrowserBottomAddressPanelHeaderAction[] {
    if (this.liveBottomChromePresentation.trailingHeaderActions.length > 0) {
      return this.liveBottomChromePresentation.trailingHeaderActions;
    }
    return [];
  }

  private dispatchPanelAction(item: BrowserBottomAddressPanelAction): void {
    hilog.info(
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN,
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG,
      `${USER_AGENT_ACTION_DIAGNOSTIC_PREFIX} panel-action id=%{public}s enabled=%{public}s`,
      item.id,
      item.enabled ? '1' : '0'
    );
    if (this.quickActionReorderActive || this.dragConsumedQuickActionId === item.id) {
      this.dragConsumedQuickActionId = undefined;
      this.clearQuickActionDragClickGuard();
      return;
    }
    if (!item.enabled) {
      const message = item.disabledMessage.trim();
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      }
      return;
    }
    this.beginFloatingActionContentExit((): void => {
      this.finishAddressEditing(true);
      this.onAction(item.id);
    });
  }

  private requestToolbarSystemSheetAction(item: BrowserBottomAddressPanelAction): void {
    if (!item.enabled) {
      const message = item.disabledMessage.trim();
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      }
      return;
    }
    this.pendingToolbarSystemSheetAction = item;
    this.toolbarSystemSheetVisible = false;
  }

  private openToolbarSystemSheet(): void {
    if (this.toolbarSystemSheetVisible) {
      return;
    }
    this.pendingToolbarSystemSheetAction = undefined;
    this.toolbarSystemSheetDetentSelection = this.resolveToolbarSystemSheetPreviewHeight(
      this.resolveToolbarRenderSnapshot().layoutState
    );
    this.toolbarSystemSheetVisible = true;
  }

  private handleToolbarSystemSheetDisappear(): void {
    this.toolbarSystemSheetVisible = false;
    this.toolbarSystemSheetDetentSelection = 0;
    const pendingAction = this.pendingToolbarSystemSheetAction;
    this.pendingToolbarSystemSheetAction = undefined;
    if (pendingAction !== undefined) {
      this.onAction(pendingAction.id);
    }
  }

  private dispatchHeaderAction(item: BrowserBottomAddressPanelHeaderAction): void {
    if (!item.enabled) {
      const message = item.disabledMessage.trim();
      if (message.length > 0) {
        this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
      }
      return;
    }
    if (this.shouldDispatchHeaderActionWithoutEditingStateChange(item.id)) {
      this.onHeaderAction(item.id);
      return;
    }
    this.finishAddressEditing(true);
    this.onHeaderAction(item.id);
  }

  private shouldDispatchHeaderActionWithoutEditingStateChange(actionId: string): boolean {
    return actionId === 'openTabs' || actionId === 'copyLink';
  }

  private dispatchReliableHeaderAction(item: BrowserBottomAddressPanelHeaderAction): void {
    if (!this.reliableHeaderActionEnabled) {
      return;
    }
    this.reliableHeaderActionEnabled = false;
    this.finishAddressEditing(true);
    this.onHeaderAction(item.id);
    setTimeout(() => {
      this.reliableHeaderActionEnabled = true;
    }, WEB_BOTTOM_RELIABLE_HEADER_ACTION_THROTTLE_MS);
  }

  private findLiveHeaderAction(actionId: string): BrowserBottomAddressPanelHeaderAction | undefined {
    const leadingActions = this.resolveLeadingHeaderActions();
    for (let index = 0; index < leadingActions.length; index += 1) {
      if (leadingActions[index].id === actionId) {
        return leadingActions[index];
      }
    }
    const trailingActions = this.resolveTrailingHeaderActions();
    for (let index = 0; index < trailingActions.length; index += 1) {
      if (trailingActions[index].id === actionId) {
        return trailingActions[index];
      }
    }
    return undefined;
  }

  private isReliableHeaderAction(item: BrowserBottomAddressPanelHeaderAction): boolean {
    return item.triggerPolicy === 'reliableTrigger';
  }

  private handleBottomChromeIntent(intent: BrowserBottomChromeTapIntent): void {
    hilog.info(
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_DOMAIN,
      USER_AGENT_ACTION_DIAGNOSTIC_LOG_TAG,
      `${USER_AGENT_ACTION_DIAGNOSTIC_PREFIX} chrome-intent kind=%{public}s action=%{public}s slot=%{public}s`,
      intent.kind,
      intent.actionId,
      intent.slotId
    );
    if (intent.disabledMessage.trim().length > 0) {
      this.getUIContext().getPromptAction().showToast({
        message: intent.disabledMessage,
        duration: 1500
      });
      return;
    }
    if (intent.kind === 'activate-editing') {
      this.enterAddressFocus(true);
      return;
    }
    if (intent.kind === 'clear-input') {
      this.clearAddressInput();
      return;
    }
    if (intent.kind === 'restore-current-address') {
      this.restoreCurrentWebAddress();
      return;
    }
    if (intent.kind === 'dispatch-panel-action') {
      this.onAction(intent.actionId as BrowserBottomAddressPanelActionId);
      return;
    }
    if (intent.kind !== 'dispatch-header-action') {
      return;
    }
    if (intent.actionId === 'bottomChromeMenu') {
      this.openToolbarSystemSheet();
      return;
    }
    const item = this.findLiveHeaderAction(intent.actionId);
    if (item === undefined) {
      this.onHeaderAction(intent.actionId);
      return;
    }
    if (this.isReliableHeaderAction(item)) {
      this.dispatchReliableHeaderAction(item);
      return;
    }
    this.dispatchHeaderAction(item);
  }

  private dispatchHomeSuggestion(suggestion: SearchSuggestion): void {
    this.finishAddressEditing(true);
    this.onOpenSuggestion(suggestion);
  }

  private enterAddressFocus(notifyInvocation: boolean): void {
    if (notifyInvocation) {
      this.onAddressFocusPrepare();
    }
    if (!this.addressEditable) {
      if (notifyInvocation) {
        this.applyPanelDetent('middle');
      }
      return;
    }
    if (notifyInvocation) {
      this.applyPanelDetent('middle');
    }
    this.applyAddressFocusState(true, false);
    this.beginAddressFocusRequest();
    this.requestAddressFocusIfPending();
  }

  private syncRequestedPanelDetent(): void {
    this.applyRequestedPanelDetent();
    this.resumeOwnerRequestedAddressFocusIfReady();
  }

  private applyLivePresentation(presentation: BrowserBottomPanelLivePresentation): void {
    const nextRequestedAddressFocused = presentation.addressFocused;
    this.requestedAddressFocused = false;
    this.applyLivePanelMotionState(presentation.panelMotionState);
    this.applyBottomChromePresentation(presentation.bottomChromePresentation);
    this.applyLiveActionSnapshot(presentation.actionSnapshot);
    this.applyReadingContinuation(presentation.readingContinuation);
    this.liveFloatingHeaderVisible = presentation.floatingHeaderVisible;
    this.syncPanelMotionState();
    this.syncBottomChromePresentation();
    this.requestedAddressFocused = nextRequestedAddressFocused;
    this.syncRequestedAddressFocused();
  }

  private applyReadingContinuation(
    presentation: BrowserBottomPanelReadingContinuationPresentation
  ): void {
    const previous = this.liveReadingContinuation;
    if (previous.visible === presentation.visible && previous.title === presentation.title &&
      previous.loading === presentation.loading) {
      return;
    }
    this.liveReadingContinuation = {
      visible: presentation.visible,
      title: presentation.title,
      loading: presentation.loading
    };
    this.liveReadingContinuationRevision += 1;
  }

  private shouldShowReadingContinuation(): boolean {
    return this.liveReadingContinuation.visible && this.shouldRenderUnifiedQuickActionsContent();
  }

  private resolveReadingContinuationHeight(): number {
    return this.shouldShowReadingContinuation() ? WEB_BOTTOM_READING_CONTINUATION_HEIGHT : 0;
  }

  private applyLiveActionSnapshot(snapshot?: BrowserBottomPanelActionSnapshot): void {
    if (snapshot === undefined) {
      return;
    }
    const actionSnapshotChanged = this.liveActionSnapshotRevision !== snapshot.revision;
    this.liveActionSnapshot = snapshot;
    if (actionSnapshotChanged && !this.quickActionReorderActive) {
      this.syncLiveQuickActionOrder(this.resolveBaseUnifiedQuickActions());
    }
    if (actionSnapshotChanged) {
      this.liveActionSnapshotRevision = snapshot.revision;
    }
  }

  private resolveLiveActionSnapshot(): BrowserBottomPanelActionSnapshot | undefined {
    void this.liveActionSnapshotRevision;
    return this.liveActionSnapshot;
  }

  private shouldEnableQuickActionReorder(): boolean {
    return this.livePresentationConnected &&
      !this.quickActionsOnly &&
      !this.viewerInfoActionEnabled &&
      this.isExpandedPanelDetent(this.panelDetent) &&
      this.shouldRenderUnifiedQuickActionsContent();
  }

  private beginQuickActionNativeDrag(index: number, performFeedback: boolean): void {
    if (!this.shouldEnableQuickActionReorder()) {
      return;
    }
    const action = this.resolveUnifiedQuickActions()[index];
    if (action === undefined) {
      return;
    }
    this.clearQuickActionDragClickGuard();
    this.dragConsumedQuickActionId = action.id;
    this.quickActionReorderActive = true;
    if (performFeedback) {
      this.toolbarCustomizationCoordinator.performReorderFeedback();
    }
  }

  private handleQuickActionNativeMove(from: number, to: number): void {
    if (!this.shouldEnableQuickActionReorder() || from === to) {
      return;
    }
    const actions = this.resolveUnifiedQuickActions();
    const action = actions[from];
    if (action === undefined || actions.length <= 0) {
      return;
    }
    const safeTargetIndex = Math.max(0, Math.min(to, actions.length - 1));
    const nextActions = actions.slice();
    const movedActions = nextActions.splice(from, 1);
    const movedAction = movedActions.length > 0 ? movedActions[0] : undefined;
    if (movedAction === undefined) {
      return;
    }
    nextActions.splice(safeTargetIndex, 0, movedAction);
    const nextOrder = nextActions.map(
      (item: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelActionId => item.id
    );
    this.updateLiveQuickActionOrderIds(nextOrder);
    this.dragConsumedQuickActionId = action.id;
    this.toolbarCustomizationCoordinator.persistPrimaryMove(
      action.id,
      safeTargetIndex,
      new BrowserToolbarCustomizationBoundary(
        this.privateMode ? 'session_ephemeral' : 'profile_persistent',
        this.privateMode ? 'private' : 'regular'
      )
    )
      .catch((_error: Error) => {
        this.syncLiveQuickActionOrder(this.resolveBaseUnifiedQuickActions());
        this.getUIContext().getPromptAction().showToast({ message: '底部工具栏更新失败。', duration: 2200 });
      });
  }

  private endQuickActionNativeDrag(): void {
    this.quickActionReorderActive = false;
    this.clearQuickActionDragClickGuard();
    this.quickActionDragClickGuardTimeout = setTimeout(() => {
      this.quickActionDragClickGuardTimeout = -1;
      this.dragConsumedQuickActionId = undefined;
    }, WEB_BOTTOM_QUICK_ACTION_DRAG_CLICK_GUARD_MS);
  }

  private syncLiveQuickActionOrder(actions: BrowserBottomAddressPanelAction[]): void {
    const nextOrder = actions.map(
      (item: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelActionId => item.id
    );
    this.updateLiveQuickActionOrderIds(nextOrder);
  }

  private updateLiveQuickActionOrderIds(nextOrder: BrowserBottomAddressPanelActionId[]): void {
    if (this.isSameQuickActionOrder(nextOrder)) {
      return;
    }
    this.liveQuickActionOrderIds = nextOrder;
    this.toolbarOrderRevision += 1;
  }

  private isSameQuickActionOrder(nextOrder: BrowserBottomAddressPanelActionId[]): boolean {
    if (nextOrder.length !== this.liveQuickActionOrderIds.length) {
      return false;
    }
    for (let index = 0; index < nextOrder.length; index += 1) {
      if (nextOrder[index] !== this.liveQuickActionOrderIds[index]) {
        return false;
      }
    }
    return true;
  }

  private resetQuickActionReorderState(): void {
    this.quickActionReorderActive = false;
    this.dragConsumedQuickActionId = undefined;
    this.clearQuickActionDragClickGuard();
  }

  private clearQuickActionDragClickGuard(): void {
    if (this.quickActionDragClickGuardTimeout < 0) {
      return;
    }
    clearTimeout(this.quickActionDragClickGuardTimeout);
    this.quickActionDragClickGuardTimeout = -1;
  }

  private syncPanelMotionStateFromProp(): void {
    if (this.livePresentationConnected) {
      return;
    }
    this.applyLivePanelMotionState(this.panelMotionState);
    this.syncPanelMotionState();
  }

  private syncBottomChromePresentationFromProp(): void {
    if (this.livePresentationConnected) {
      return;
    }
    this.applyBottomChromePresentation(this.bottomChromePresentation);
    this.syncBottomChromePresentation();
  }

  private applyRequestedPanelDetent(): void {
    const requestedDetent = this.resolveAllowedPanelDetent(this.livePanelMotionState.targetDetent);
    if (this.panelDetent === requestedDetent && this.panelTargetDetent === requestedDetent) {
      return;
    }
    if (this.shouldDeferRequestedCollapseToLow(requestedDetent)) {
      this.beginFloatingActionContentExit((): void => {
        this.beginDeferredRequestedCollapseToLow();
      });
      return;
    }
    this.applyPanelDetent(requestedDetent, true, true);
  }

  private syncPanelMotionState(): void {
    this.syncRequestedPanelDetent();
    this.syncImmediateLowDetentRequest();
  }

  private applyLivePanelMotionState(state: BrowserBottomPanelMotionState): void {
    if (Math.abs(this.livePanelMotionState.panelHeight - state.panelHeight) > 0.01) {
      this.toolbarMotionLayoutRevision += 1;
    }
    this.livePanelMotionState = state;
  }

  private syncImmediateLowDetentRequest(): void {
    const requestVersion = this.livePanelMotionState.immediateLowDetentRequestVersion;
    if (requestVersion <= 0 || this.handledImmediateLowDetentRequestVersion === requestVersion) {
      return;
    }
    this.handledImmediateLowDetentRequestVersion = requestVersion;
    const requestedDetent = this.resolveAllowedPanelDetent(this.livePanelMotionState.targetDetent);
    if (requestedDetent !== 'low') {
      return;
    }
    this.applyPanelDetent('low', false, this.shouldDeferRequestedPanelDetentNotification('low'));
  }

  private syncRequestedAddressFocused(): void {
    if (!this.requestedAddressFocused) {
      this.endInactiveAddressInputSession();
      return;
    }
    if (this.addressFocused === this.requestedAddressFocused) {
      this.requestAddressFocusIfPending();
      return;
    }
    this.resumeOwnerRequestedAddressFocusIfReady();
  }

  private resumeOwnerRequestedAddressFocusIfReady(): void {
    if (!this.requestedAddressFocused || this.addressFocused) {
      return;
    }
    this.enterAddressFocus(false);
  }

  private syncBottomChromePresentation(): void {
    const headerChanged = this.lastChromeHeaderPresentation !==
      this.liveBottomChromePresentation.headerPresentation;
    const contentChanged = this.lastChromeContentPresentation !==
      this.liveBottomChromePresentation.contentPresentation;
    this.lastChromeHeaderPresentation = this.liveBottomChromePresentation.headerPresentation;
    this.lastChromeContentPresentation = this.liveBottomChromePresentation.contentPresentation;
    this.syncAddressInputAdapterFromPresentation();
    this.syncEditingAddressTextFromProps();
    if (contentChanged) {
      this.resetToolbarExpansionStage();
    }
    if (contentChanged && this.isExpandedPanelDetent(this.panelDetent)) {
      this.syncQuickActionLabelContrast(this.panelDetent, this.panelDetent, true);
    }
    if (!headerChanged && !contentChanged) {
      return;
    }
    this.endInactiveAddressInputSession();
    if (!headerChanged) {
      return;
    }
    this.playHeaderButtonsEnterAnimation();
  }

  private applyBottomChromePresentation(presentation: BrowserBottomChromePresentation): void {
    if (this.liveBottomChromePresentation.contentPresentation !== presentation.contentPresentation) {
      this.invalidateToolbarPresentationSnapshot();
    }
    this.liveBottomChromePresentation = presentation;
    this.liveAddressInput = presentation.addressInput;
    this.liveAddressDisplayText = presentation.centerContent.displayText;
    this.liveAddressPlaceholder = presentation.placeholder;
  }

  private syncAddressInputAdapterFromPresentation(): void {
    const nextActive = this.liveBottomChromePresentation.mode === 'center-active-editing';
    if (this.addressInputAdapterActive === nextActive) {
      return;
    }
    this.addressInputAdapterActive = nextActive;
    this.invalidateToolbarPresentationSnapshot();
    this.editingMotionFocusReady = false;
    if (nextActive) {
      this.resetToolbarExpansionStage();
    }
    if (!nextActive) {
      this.clearAddressSelectAllTimeout();
      this.clearAddressFocusRequest();
      this.restorableWebAddressText = '';
      this.editingAddressText = '';
      return;
    }
    this.editingAddressText = this.resolveInitialEditingAddressText();
    this.restorableWebAddressText = this.isWebContentMode() ? this.editingAddressText.trim() : '';
    if (this.isWebContentMode()) {
      this.onAddressChange(this.editingAddressText);
    }
    this.beginAddressFocusRequest();
  }

  private handleBottomChromeEditingFocusReady(): void {
    if (this.liveBottomChromePresentation.mode !== 'center-active-editing' ||
      !this.addressInputAdapterActive) {
      return;
    }
    this.editingMotionFocusReady = true;
    this.beginAddressFocusRequest();
    this.scheduleAddressFocus();
  }

  private playHeaderButtonsEnterAnimation(): void {
    this.clearHeaderButtonsEnterRequest();
    this.headerButtonsEnterProgress = 0;
    this.headerButtonsEnterTimeout = setTimeout(() => {
      this.headerButtonsEnterTimeout = -1;
      animateTo({
        duration: WEB_BOTTOM_HEADER_BUTTON_ENTER_DURATION_MS,
        curve: 'interpolatingSpring(0, 1, 360, 24)'
      }, () => {
        this.headerButtonsEnterProgress = 1;
      });
    }, WEB_BOTTOM_HEADER_BUTTON_ENTER_DELAY_MS);
  }

  private scheduleAddressFocus(): void {
    this.clearAddressFocusTimeout();
    this.requestAddressFocusIfPending();
  }

  private scheduleAddressFocusRetry(): void {
    if (!this.pendingAddressFocusRequest || this.addressFocusAttemptCount >= WEB_BOTTOM_INPUT_FOCUS_MAX_ATTEMPTS ||
      this.addressFocusTimeout >= 0) {
      return;
    }
    this.addressFocusTimeout = setTimeout(() => {
      this.addressFocusTimeout = -1;
      this.requestAddressFocusIfPending();
    }, WEB_BOTTOM_INPUT_FOCUS_RETRY_DELAY_MS);
  }

  private scheduleWebAddressSelectAll(): void {
    this.clearAddressSelectAllTimeout();
    if (!this.shouldSelectAllWebAddress()) {
      return;
    }
    this.addressSelectAllTimeout = setTimeout(() => {
      this.addressSelectAllTimeout = -1;
      if (!this.shouldSelectAllWebAddress()) {
        return;
      }
      this.addressInputController.setTextSelection(0, this.editingAddressText.length, {
        menuPolicy: MenuPolicy.HIDE
      });
    }, WEB_BOTTOM_INPUT_SELECT_ALL_DELAY_MS);
  }

  private requestAddressFocusIfPending(): void {
    if (!this.pendingAddressFocusRequest || !this.addressInputMounted || !this.addressFocused ||
      !this.addressInputAdapterActive || !this.editingMotionFocusReady ||
      this.addressFocusAttemptCount >= WEB_BOTTOM_INPUT_FOCUS_MAX_ATTEMPTS ||
      (this.panelDetent !== 'middle' && this.panelTargetDetent !== 'middle')) {
      return;
    }
    this.clearAddressBlurRequest();
    this.setKeyboardAvoidMode();
    const accepted = focusControl.requestFocus(WEB_BOTTOM_INPUT_FOCUS_ID);
    this.addressFocusAttemptCount += 1;
    if (!accepted) {
      this.scheduleAddressFocusRetry();
      return;
    }
    this.scheduleAddressFocusRetry();
  }

  private acknowledgeAddressFocus(): void {
    this.clearAddressFocusRequest();
  }

  private beginAddressFocusRequest(): void {
    this.pendingAddressFocusRequest = true;
    this.addressFocusAttemptCount = 0;
  }

  private clearAddressFocusRequest(): void {
    this.pendingAddressFocusRequest = false;
    this.addressFocusAttemptCount = 0;
    this.clearAddressFocusTimeout();
  }

  private handleAddressInputChange(value: string): void {
    if (!this.addressInputAdapterActive) {
      return;
    }
    const displayValue = this.normalizeBulkAddressInputChange(value);
    this.editingAddressText = displayValue;
    this.onAddressChange(displayValue);
  }

  private handleAddressInputPaste(content: string, event: PasteEvent): void {
    const extractedUrl = extractFirstUrlFromText(content);
    if (extractedUrl.length === 0 || extractedUrl === content.trim()) {
      return;
    }
    event.preventDefault?.();
    this.handleAddressInputChange(extractedUrl);
  }

  private normalizeBulkAddressInputChange(value: string): string {
    const extractedUrl = extractFirstUrlFromText(value);
    if (extractedUrl.length === 0 || extractedUrl === value.trim()) {
      return value;
    }
    if (!this.isLikelyBulkAddressInputChange(value)) {
      return value;
    }
    return extractedUrl;
  }

  private isLikelyBulkAddressInputChange(value: string): boolean {
    const previousLength = this.editingAddressText.length;
    if (previousLength === 0) {
      return value.trim().length >= WEB_BOTTOM_ADDRESS_BULK_INPUT_MIN_DELTA;
    }
    return Math.abs(value.length - previousLength) >= WEB_BOTTOM_ADDRESS_BULK_INPUT_MIN_DELTA;
  }

  private syncEditingAddressTextFromProps(): void {
    if (!this.addressInputAdapterActive) {
      this.editingAddressText = '';
      return;
    }
    if (this.liveBottomChromePresentation.contentPresentation === 'home') {
      this.editingAddressText = this.liveAddressInput;
    }
  }

  private endInactiveAddressInputSession(): void {
    if (this.requestedAddressFocused) {
      return;
    }
    this.clearAddressFocusRequest();
    this.editingMotionFocusReady = false;
    this.restorableWebAddressText = '';
    this.applyAddressFocusState(false, true);
  }

  private blurAddressInput(): void {
    const ownsInputFocus = this.addressInputActuallyFocused;
    this.clearAddressFocusRequest();
    this.clearAddressBlurRequest();
    if (ownsInputFocus) {
      this.addressInputActuallyFocused = false;
      focusControl.requestFocus('');
      inputMethod.getController().hideTextInput()
        .catch(() => {});
    }
    this.restoreKeyboardAvoidMode();
  }

  private releaseAddressFocusSessionIfOwned(ownsLivePresentation: boolean): void {
    if (!ownsLivePresentation) {
      return;
    }
    this.blurAddressInput();
  }

  private clearAddressFocusTimeout(): void {
    if (this.addressFocusTimeout >= 0) {
      clearTimeout(this.addressFocusTimeout);
      this.addressFocusTimeout = -1;
    }
  }

  private clearAddressSelectAllTimeout(): void {
    if (this.addressSelectAllTimeout >= 0) {
      clearTimeout(this.addressSelectAllTimeout);
      this.addressSelectAllTimeout = -1;
    }
  }

  private clearAddressBlurRequest(): void {
    if (this.addressBlurTimeout >= 0) {
      clearTimeout(this.addressBlurTimeout);
      this.addressBlurTimeout = -1;
    }
  }

  private clearHeaderButtonsEnterRequest(): void {
    if (this.headerButtonsEnterTimeout >= 0) {
      clearTimeout(this.headerButtonsEnterTimeout);
      this.headerButtonsEnterTimeout = -1;
    }
  }

  private clearPanelDetentNotification(): void {
    if (this.panelDetentNotificationTimer >= 0) {
      clearTimeout(this.panelDetentNotificationTimer);
      this.panelDetentNotificationTimer = -1;
    }
    this.pendingPanelDetentNotification = undefined;
  }

  private beginFloatingActionContentExit(completion?: () => void): void {
    this.clearFloatingActionContentEntry();
    if (completion !== undefined) {
      this.pendingFloatingActionContentExitCompletion = completion;
    }
    if (this.floatingActionContentExitActive) {
      return;
    }
    if (!this.floatingActionContentSettled || !this.shouldSequenceFloatingActionContentExit()) {
      this.completeFloatingActionContentExitBarrier();
      return;
    }
    this.floatingActionContentSettled = false;
    this.floatingActionContentExitActive = true;
    this.clearFloatingActionContentExitTimer();
    this.floatingActionContentExitTimer = setTimeout(() => {
      this.floatingActionContentExitTimer = -1;
      this.completeFloatingActionContentExitBarrier();
    }, BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_EXIT_BARRIER_MS);
  }

  private completeFloatingActionContentExitBarrier(): void {
    this.floatingActionContentExitActive = false;
    const completion = this.pendingFloatingActionContentExitCompletion;
    this.pendingFloatingActionContentExitCompletion = undefined;
    if (completion !== undefined) {
      completion();
    }
  }

  private clearFloatingActionContentExitBarrier(): void {
    this.clearFloatingActionContentExitTimer();
    this.pendingFloatingActionContentExitCompletion = undefined;
    this.floatingActionContentExitActive = false;
  }

  private clearFloatingActionContentExitTimer(): void {
    if (this.floatingActionContentExitTimer < 0) {
      return;
    }
    clearTimeout(this.floatingActionContentExitTimer);
    this.floatingActionContentExitTimer = -1;
  }

  private shouldDeferRequestedPanelDetentNotification(detent: HomeSearchPanelDetent): boolean {
    return detent === this.resolveAllowedPanelDetent(this.livePanelMotionState.targetDetent);
  }

  private dispatchPanelDetentChange(
    detent: HomeSearchPanelDetent,
    deferNotification: boolean
  ): void {
    if (!deferNotification) {
      this.clearPanelDetentNotification();
      this.onPanelDetentChange(detent);
      return;
    }
    this.pendingPanelDetentNotification = detent;
    if (this.panelDetentNotificationTimer >= 0) {
      return;
    }
    this.panelDetentNotificationTimer = setTimeout(() => {
      this.panelDetentNotificationTimer = -1;
      const pendingDetent = this.pendingPanelDetentNotification;
      this.pendingPanelDetentNotification = undefined;
      if (pendingDetent === undefined || pendingDetent !== this.panelDetent) {
        return;
      }
      this.onPanelDetentChange(pendingDetent);
    }, 0);
  }

  private applyPanelDetent(
    detent: HomeSearchPanelDetent,
    deferExpandedCollapseUntilSettled: boolean = true,
    deferPanelDetentNotification: boolean = false
  ): void {
    const nextDetent = this.resolveAllowedPanelDetent(detent);
    const previousDetent = this.panelDetent;
    if (nextDetent !== 'middle') {
      this.clearFloatingActionContentEntry();
      this.floatingActionContentGestureRevealed = false;
    }
    if (nextDetent === 'low' &&
      this.isExpandedPanelDetent(previousDetent) &&
      this.floatingActionContentSettled &&
      this.shouldSequenceFloatingActionContentExit()) {
      this.beginFloatingActionContentExit((): void => {
        this.applyPanelDetent(detent, deferExpandedCollapseUntilSettled, deferPanelDetentNotification);
      });
      return;
    }
    this.panelTargetDetent = nextDetent;
    if (nextDetent === 'low' && this.isExpandedPanelDetent(previousDetent)) {
      this.floatingActionContentSettled = false;
    }
    if (deferExpandedCollapseUntilSettled &&
      nextDetent === 'low' &&
      this.isExpandedPanelDetent(previousDetent)) {
      this.panelDragHeight = 0;
      if (this.isHomeHeaderMode()) {
        this.homeDismissAfterLowSettlePending = true;
      }
      if (this.addressInputAdapterActive) {
        this.finishAddressEditing(true);
      }
      return;
    }
    this.panelDetent = nextDetent;
    this.syncQuickActionLabelContrast(nextDetent, previousDetent);
    if (!this.isExpandedPanelDetent(nextDetent)) {
      this.floatingActionContentSettled = false;
      this.resetQuickActionReorderState();
      this.panelDragHeight = 0;
    } else if (nextDetent !== previousDetent || this.panelDragHeight <= 0) {
      this.panelDragHeight = this.resolveFloatingStackMiddlePanelHeight();
    }
    if (this.isCollapsedPanelDetent(previousDetent) && this.isExpandedPanelDetent(nextDetent)) {
      this.resetToolbarExpansionStage();
    }
    if (nextDetent !== 'low') {
      this.homeDismissAfterLowSettlePending = false;
    }
    if (nextDetent !== previousDetent) {
      this.dispatchPanelDetentChange(nextDetent, deferPanelDetentNotification);
    }
    if (previousDetent !== 'low' && nextDetent === 'low') {
      this.resetToolbarExpansionStage();
      this.resetPanelContentScroll();
    }
    if (!this.isExpandedPanelDetent(nextDetent) && this.addressInputAdapterActive) {
      this.finishAddressEditing(true);
    }
  }

  private beginDeferredRequestedCollapseToLow(): void {
    this.clearFloatingActionContentEntry();
    this.panelTargetDetent = 'low';
    this.floatingActionContentSettled = false;
    this.panelDragHeight = 0;
    if (this.isHomeHeaderMode()) {
      this.homeDismissAfterLowSettlePending = true;
    }
  }

  private handleDetentPanelSettled(detent: HomeSearchPanelDetent): void {
    if (this.panelTargetDetent === detent && this.panelDetent !== detent) {
      this.applyPanelDetent(detent, false, this.shouldDeferRequestedPanelDetentNotification(detent));
    }
    if (detent === 'low' && this.homeDismissAfterLowSettlePending) {
      this.homeDismissAfterLowSettlePending = false;
      this.applyAddressFocusState(false, true);
      this.onHomeDismiss();
    }
    if (detent === 'middle') {
      this.panelDragHeight = this.resolveFloatingStackMiddlePanelHeight();
      const nextContentSettled = this.shouldRenderFloatingActionSurface();
      if (nextContentSettled && !this.floatingActionContentSettled &&
        !this.floatingActionContentGestureRevealed) {
        this.beginFloatingActionContentEntry();
      }
      this.floatingActionContentSettled = nextContentSettled;
      this.floatingActionContentGestureRevealed = false;
    } else {
      this.clearFloatingActionContentEntry();
      this.floatingActionContentSettled = false;
      this.floatingActionContentGestureRevealed = false;
    }
    this.onPanelSettled(detent);
  }

  private shouldDeferRequestedCollapseToLow(requestedDetent: HomeSearchPanelDetent): boolean {
    return requestedDetent === 'low' &&
      this.panelTargetDetent !== 'low' &&
      this.isExpandedPanelDetent(this.panelDetent);
  }

  private shouldDeferLowDetentChangeUntilSettled(): boolean {
    return this.panelTargetDetent === 'low' && this.isExpandedPanelDetent(this.panelDetent);
  }

  private shouldDeferHomeDismissUntilLowSettle(): boolean {
    return this.isExpandedPanelDetent(this.panelDetent) ||
      (this.panelTargetDetent === 'low' && this.panelDetent !== 'low');
  }

  private resetPanelContentScroll(): void {
    this.panelContentScroller.scrollTo({
      xOffset: 0,
      yOffset: 0,
      animation: {
        duration: 0,
        curve: Curve.Linear
      }
    });
  }

  private isCollapsedPanelDetent(detent: HomeSearchPanelDetent): boolean {
    return detent === 'peek' || detent === 'low';
  }

  private isExpandedPanelDetent(detent: HomeSearchPanelDetent): boolean {
    return detent === 'middle';
  }

  private resolveAllowedPanelDetent(detent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    if (!this.livePanelMotionState.detentDragEnabled && detent !== 'peek') {
      return 'low';
    }
    if (!this.livePanelMotionState.peekEnabled && detent === 'peek') {
      return 'low';
    }
    return detent;
  }

  private applyAddressFocusState(focused: boolean, dismissKeyboard: boolean): void {
    const previousFocused = this.addressFocused;
    this.addressFocused = focused;
    if (!focused && dismissKeyboard) {
      this.blurAddressInput();
    }
    if (focused !== previousFocused) {
      this.invalidateToolbarPresentationSnapshot();
      this.onAddressFocusStateChange(focused);
    }
  }

  private invalidateToolbarPresentationSnapshot(): void {
    this.toolbarPresentationRevision += 1;
  }

  private finishAddressEditing(dismissKeyboard: boolean): void {
    this.clearAddressSelectAllTimeout();
    this.clearAddressFocusRequest();
    this.editingMotionFocusReady = false;
    this.restorableWebAddressText = '';
    this.applyAddressFocusState(false, dismissKeyboard);
  }

  private setKeyboardAvoidMode(): void {
    this.onKeyboardResizeSessionBegin();
  }

  private restoreKeyboardAvoidMode(): void {
    this.onKeyboardResizeSessionEnd();
  }

  private updatePressedAction(actionId: string, type: TouchType, enabled: boolean): void {
    if (!enabled) {
      this.pressedActionId = '';
      return;
    }
    if (type === TouchType.Down) {
      this.pressedActionId = actionId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedActionId = '';
    }
  }

  private runHeaderAction(actionId: string, enabled: boolean, action: () => void): void {
    if (!enabled) {
      return;
    }
    const now = Date.now();
    if (this.lastHeaderActionId === actionId && now - this.lastHeaderActionAt < WEB_BOTTOM_HEADER_ACTION_DEDUP_MS) {
      return;
    }
    this.lastHeaderActionId = actionId;
    this.lastHeaderActionAt = now;
    action();
  }

  private getAddressText(): string {
    if (this.liveAddressDisplayText.trim().length > 0) {
      return this.liveAddressDisplayText;
    }
    if (this.liveAddressInput.trim().length > 0) {
      return this.liveAddressInput;
    }
    return this.liveAddressPlaceholder;
  }

  private shouldShowWebProtectionConfirmation(): boolean {
    const centerContent = this.liveBottomChromePresentation.centerContent;
    return this.liveBottomChromePresentation.effectiveWeb &&
      centerContent.activeLayer === 'display' &&
      centerContent.webProtectionFeedback.visible;
  }

  private resolveInitialEditingAddressText(): string {
    return this.liveAddressInput;
  }

  private clearAddressInput(): void {
    this.editingAddressText = '';
    this.onAddressChange('');
    this.beginAddressFocusRequest();
    this.requestAddressFocusIfPending();
  }

  private restoreCurrentWebAddress(): void {
    const value = this.restorableWebAddressText;
    if (value.length <= 0) {
      this.getUIContext().getPromptAction().showToast({
        message: '当前没有可编辑的网址。',
        duration: 1500
      });
      return;
    }
    this.editingAddressText = value;
    this.onAddressChange(value);
    this.beginAddressFocusRequest();
    this.requestAddressFocusIfPending();
    this.scheduleWebAddressSelectAll();
  }

  private shouldUseThreeBlockBottomChrome(): boolean {
    return (this.isHomeContentMode() || this.isWebContentMode()) && !this.viewerInfoActionEnabled;
  }

  private resolveFloatingHeaderInteractionWidth(): number {
    if (this.liveBottomChromePresentation.mode !== 'scroll-compact') {
      return 0;
    }
    return Math.max(1, this.liveBottomChromePresentation.frame.centerWidth);
  }

  private resolveFloatingHeaderInteractionHeight(): number {
    if (this.liveBottomChromePresentation.mode !== 'scroll-compact') {
      return 0;
    }
    return Math.max(1, this.liveBottomChromePresentation.frame.centerHeight);
  }

  private resolveFloatingHeaderInteractionOffsetY(): number {
    if (this.liveBottomChromePresentation.mode !== 'scroll-compact') {
      return 0;
    }
    return BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING +
      Math.max(0, this.liveBottomChromePresentation.frame.centerTranslateY);
  }

  private resolveBottomChromeGestureSource(
    startX: number,
    panelWidth: number
  ): BrowserBottomChromeGestureSource {
    void panelWidth;
    if (!this.shouldUseThreeBlockBottomChrome()) {
      return 'center-capsule';
    }
    return this.liveBottomChromePresentation.resolveGestureSource(startX);
  }

  private shouldOpenToolbarSystemSheetFromGesture(
    targetDetent: HomeSearchPanelDetent,
    offsetY: number,
    source: BrowserBottomChromeGestureSource
  ): boolean {
    void targetDetent;
    return source === 'center-capsule' &&
      this.isWebContentMode() &&
      !this.isAddressInputPresentationActive() &&
      Number.isFinite(offsetY) &&
      offsetY < 0;
  }

  private resolveBottomChromeMaterialTint(): ResourceColor {
    return resolveBrowserBottomChromeMaterialTintForMode(this.resolveNeutralThemeMode());
  }

  private bindActiveDownloadIndicator(): void {
    if (!this.activeDownloadIndicatorEnabled || this.downloadIndicatorListenerKey.length > 0) {
      return;
    }
    this.downloadIndicatorListenerKey = sharedDownloadRuntimeService.addCallbacksListener({
      onTaskListChange: (tasks: DownloadV2TaskEntity[]): void => {
        this.downloadIndicatorState = this.downloadToolbarIndicatorViewModel.buildState(tasks);
      }
    });
  }

  private unbindActiveDownloadIndicator(): void {
    if (this.downloadIndicatorListenerKey.length <= 0) {
      return;
    }
    sharedDownloadRuntimeService.removeCallbacksListener(this.downloadIndicatorListenerKey);
    this.downloadIndicatorListenerKey = '';
    this.downloadIndicatorState = createHiddenDownloadToolbarIndicatorState();
  }

  private resolveAddressInputPlaceholder(): string {
    return this.addressInputAdapterActive ? this.liveAddressPlaceholder : '';
  }

  private resolveHeaderButtonEnterProgress(): number {
    return Math.max(0, Math.min(1, this.headerButtonsEnterProgress));
  }

  private resolveHeaderButtonEnterOpacity(): number {
    return 0.45 + (this.resolveHeaderButtonEnterProgress() * 0.55);
  }

  private resolveHeaderIconButtonOpacity(enabled: boolean): number {
    return this.resolveHeaderButtonEnterOpacity() * (enabled ? 1 : WEB_BOTTOM_DISABLED_OPACITY);
  }

  private resolveAddressTextOpacity(): number {
    return this.addressInputAdapterActive ? 0 : 1;
  }

  private resolveAddressTextColor(): ResourceColor {
    return this.getAddressText().length > 0 ? this.resolvePrimaryTextColor() : this.resolveSecondaryTextColor();
  }

  private resolveHeaderButtonEnterScale(): number {
    return 0.72 + (this.resolveHeaderButtonEnterProgress() * 0.28);
  }

  private shouldHeaderActionReceiveTouch(enabled: boolean): boolean {
    return enabled;
  }

  private isHomeHeaderMode(): boolean {
    return this.liveBottomChromePresentation.headerPresentation === 'home';
  }

  private isHomeContentMode(): boolean {
    return this.liveBottomChromePresentation.contentPresentation === 'home';
  }

  private shouldMountExpandedScrollContent(): boolean {
    if (this.shouldUseFloatingActionPanel()) {
      return this.panelDetent === 'middle' ||
        this.shouldRevealExpandedContentFromDrag();
    }
    if (this.panelDetent === 'middle') {
      return true;
    }
    if (this.shouldRevealExpandedContentFromDrag()) {
      return true;
    }
    return this.isHomeContentMode();
  }

  private buildSearchChromeSurfaceState(): BrowserSearchChromeSurfaceState {
    return this.searchChromeSurfaceViewModel.buildState({
      contentMode: this.liveBottomChromePresentation.contentPresentation,
      panelDetent: this.panelDetent,
      addressEditing: this.addressInputAdapterActive,
      addressFocused: this.addressFocused,
      panelDragHeight: this.panelDragHeight,
      lowPanelDragHeight: this.resolveLowPanelDragHeight(),
      dragRevealThreshold: WEB_BOTTOM_DRAG_EXPANDED_CONTENT_REVEAL_THRESHOLD,
      expandedDragRevealSuppressed: this.livePanelMotionState.suppressExpandedContentFromDrag,
      actionPanelContentReady: this.isFloatingActionContentReady(),
      quickActionsOnly: this.quickActionsOnly,
      quickActionsAvailable: this.hasQuickActionSlotsAvailable(),
      suggestionsVisible: this.homeSuggestionsVisible,
      suggestionCount: this.homeSuggestions.length
    });
  }

  private shouldRenderPrimaryActionsContent(): boolean {
    return !this.shouldRenderUnifiedQuickActionsContent() &&
      this.resolvePrimaryActions().length > 0;
  }

  private shouldRenderUnifiedQuickActionsContent(): boolean {
    return this.hasQuickActionSlotsAvailable();
  }

  private hasQuickActionSlotsAvailable(): boolean {
    return (this.liveBottomChromePresentation.contentPresentation === 'web' ||
      this.isHomeContentMode() || this.quickActionsOnly) &&
      this.resolveQuickActionLimit() > 0 &&
      this.resolveQuickActionColumnCount() > 0;
  }

  private shouldRenderSecondaryActionsContent(): boolean {
    if (this.shouldUseFloatingActionPanel()) {
      return false;
    }
    if (this.shouldRenderFloatingSuggestionPanel()) {
      return false;
    }
    if (this.resolveExpandedSecondaryActions().length <= 0) {
      return false;
    }
    if (this.shouldRenderUnifiedQuickActionsContent()) {
      return false;
    }
    return true;
  }

  private shouldRenderQuickActionArea(): boolean {
    if (this.shouldUseFloatingActionPanel() && this.isAddressInputPresentationActive()) {
      return false;
    }
    return this.shouldRenderUnifiedQuickActionsContent() || this.shouldRenderPrimaryActionsContent();
  }

  private shouldDisableExpandedContentVerticalScroll(): boolean {
    return this.shouldRenderUnifiedQuickActionsContent() &&
      !this.isToolbarFullyExpanded() &&
      !this.shouldRenderSecondaryActionsContent();
  }

  private shouldRevealExpandedContentFromDrag(): boolean {
    if (this.livePanelMotionState.suppressExpandedContentFromDrag) {
      return false;
    }
    return this.panelDragHeight > this.resolveLowPanelDragHeight() + WEB_BOTTOM_DRAG_EXPANDED_CONTENT_REVEAL_THRESHOLD;
  }

  private resolveLowPanelDragHeight(): number {
    return BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT + Math.max(0, this.livePanelMotionState.bottomInset);
  }

  private resolveFloatingHeaderSurfaceHeight(): number {
    return BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT + Math.max(0, this.livePanelMotionState.bottomInset);
  }

  private buildDetentMotionState(): BrowserBottomPanelMotionState {
    return {
      targetDetent: this.panelTargetDetent,
      immediateLowDetentRequestVersion: this.livePanelMotionState.immediateLowDetentRequestVersion,
      bottomInset: this.livePanelMotionState.bottomInset,
      panelHeight: this.livePanelMotionState.panelHeight,
      middlePanelHeight: this.resolveMiddlePanelHeight(),
      overlayHostHeight: this.livePanelMotionState.overlayHostHeight,
      keyboardOverlayInset: this.livePanelMotionState.keyboardOverlayInset,
      visible: this.livePanelMotionState.visible,
      detentDragEnabled: this.livePanelMotionState.detentDragEnabled,
      panelExpansionEnabled: this.livePanelMotionState.panelExpansionEnabled,
      suppressExpandedContentFromDrag: this.livePanelMotionState.suppressExpandedContentFromDrag,
      peekEnabled: this.livePanelMotionState.peekEnabled,
      peekGestureEnabled: this.livePanelMotionState.peekGestureEnabled,
      peekToLowAnimationDurationMs: this.livePanelMotionState.peekToLowAnimationDurationMs,
      collapseToPeekAnimationDurationMs: this.livePanelMotionState.collapseToPeekAnimationDurationMs
    };
  }

  private resolveMiddlePanelHeight(): number {
    if (!this.shouldRenderFloatingStackPanel()) {
      return 0;
    }
    const currentMiddleHeight = this.resolveFloatingStackMiddlePanelHeight();
    if (currentMiddleHeight > this.resolveLowPanelDragHeight()) {
      return currentMiddleHeight;
    }
    // The action surface is owned by the native Sheet. The persistent bottom
    // chrome still needs a real middle height so its gesture can track motion
    // while the Sheet is opened from the center capsule.
    if (this.isWebContentMode() && this.hasQuickActionSlotsAvailable()) {
      return Math.max(
        this.resolveLowPanelDragHeight() + 1,
        this.resolveToolbarSystemSheetPreviewHeight(this.resolveToolbarRenderSnapshot().layoutState)
      );
    }
    return currentMiddleHeight;
  }

  private resolveFloatingStackHeightWithoutSuggestion(): number {
    if (this.shouldRenderFloatingActionSurface()) {
      return this.resolveFloatingActionSurfaceHeight();
    }
    return this.resolveFloatingHeaderSurfaceHeight();
  }

  private resolveFloatingActionSurfaceHeight(): number {
    if (!this.shouldRenderFloatingActionSurface()) {
      return WEB_BOTTOM_EXPANDED_CONTENT_IDLE_HEIGHT;
    }
    const layoutState = this.resolveFloatingQuickActionLayoutState();
    return (this.isToolbarFullyExpanded() ?
      layoutState.fullSurfaceHeight : layoutState.previewSurfaceHeight) + this.resolveReadingContinuationHeight();
  }

  private resolveFloatingExpandedHeaderHorizontalInset(): number {
    if (!this.shouldRenderFloatingActionSurface() || !this.hasQuickActionSlotsAvailable()) {
      return 0;
    }
    return Math.max(0, this.responsiveState.quickActionOuterInset);
  }

  private resolveFloatingStackMiddlePanelHeight(): number {
    const baseHeight = this.resolveFloatingStackHeightWithoutSuggestion();
    const suggestionHeight = this.resolveFloatingSuggestionPanelHeight();
    if (suggestionHeight <= 0) {
      return baseHeight;
    }
    return baseHeight +
      BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP +
      suggestionHeight;
  }

  private isToolbarFullExpansionAvailable(): boolean {
    return this.resolveToolbarRenderSnapshot().fullExpansionAvailable;
  }

  private isToolbarFullyExpanded(): boolean {
    return this.toolbarExpansionStage === 'full' && this.isToolbarFullExpansionAvailable();
  }

  private shouldShowToolbarExpansionHint(): boolean {
    return this.toolbarExpansionViewModel.shouldShowExpansionHint(this.isToolbarFullExpansionAvailable());
  }

  private resolveToolbarExpansionHintRotationAngle(): number {
    return this.toolbarExpansionViewModel.resolveExpansionHintRotationAngle(
      this.toolbarExpansionStage,
      this.isToolbarFullExpansionAvailable()
    );
  }

  private resolveToolbarSurfaceTransitionState(): BrowserBottomToolbarSurfaceTransitionState {
    return this.toolbarExpansionViewModel.resolveSurfaceTransition({
      actionSurfaceMounted: this.shouldMountFloatingActionSurface(),
      currentPanelHeight: this.panelDragHeight,
      lowPanelHeight: this.resolveLowPanelDragHeight(),
      previewPanelHeight: this.resolveFloatingQuickActionLayoutState().previewSurfaceHeight
    });
  }

  private resolveFloatingHeaderPresentationOpacity(): number {
    return this.liveFloatingHeaderVisible ? this.resolveToolbarSurfaceTransitionState().searchOpacity : 0;
  }

  private resetToolbarExpansionStage(): void {
    if (this.toolbarExpansionStage !== 'preview') {
      this.toolbarExpansionStage = 'preview';
    }
  }

  private resolveFloatingSuggestionPanelHeight(): number {
    if (!this.shouldReserveFloatingSuggestionPanelHeight()) {
      return 0;
    }
    const baseHeight = this.resolveFloatingHeaderSurfaceHeight();
    const maxPanelHeight = this.resolveMaxFloatingSuggestionPanelHeight();
    const availableHeight = maxPanelHeight - baseHeight - BROWSER_BOTTOM_PANEL_FLOATING_BLOCK_GAP;
    if (availableHeight <= 0) {
      return 0;
    }
    return availableHeight;
  }

  private resolveMaxFloatingSuggestionPanelHeight(): number {
    const hostHeight = this.livePanelMotionState.overlayHostHeight > 0 ? this.livePanelMotionState.overlayHostHeight :
      (this.livePanelMotionState.panelHeight > 0 ? this.livePanelMotionState.panelHeight :
        this.resolveFloatingStackHeightWithoutSuggestion());
    const bottomGap = BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP +
      Math.max(0, this.livePanelMotionState.keyboardOverlayInset);
    const topSafeLimit = Math.max(
      BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT,
      hostHeight - bottomGap - WEB_BOTTOM_SUGGESTION_TOP_SAFE_GAP
    );
    return Math.max(BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_LOW_HEIGHT, topSafeLimit);
  }

  private shouldUseFloatingActionPanel(): boolean {
    return this.buildSearchChromeSurfaceState().floatingStackEnabled;
  }

  private shouldRenderFloatingStackPanel(): boolean {
    return this.buildSearchChromeSurfaceState().floatingStackEnabled;
  }

  private shouldRenderFloatingActionSurface(): boolean {
    return this.shouldRenderLegacyFloatingActionSurface() &&
      this.buildSearchChromeSurfaceState().actionPanelAvailable;
  }

  private shouldRenderLegacyFloatingActionSurface(): boolean {
    return false;
  }

  private shouldMountFloatingActionSurface(): boolean {
    return this.shouldRenderLegacyFloatingActionSurface() &&
      this.buildSearchChromeSurfaceState().actionPanelMounted;
  }

  private shouldPrepareFloatingActionSurface(): boolean {
    return this.floatingActionSurfacePrepared || this.shouldMountFloatingActionSurface();
  }

  private shouldMountFloatingActionContent(): boolean {
    return this.shouldRenderLegacyFloatingActionSurface() &&
      this.buildSearchChromeSurfaceState().actionPanelContentMounted;
  }

  private isFloatingActionContentReady(): boolean {
    return this.floatingActionContentSettled || this.floatingActionContentGestureRevealed;
  }

  private scheduleFloatingActionContentRevealAtBackdropThreshold(offsetY: number): void {
    if (this.floatingActionContentGestureRevealed || this.floatingActionContentSettled ||
      this.floatingActionGestureRevealTimer >= 0 ||
      this.activeChromeGestureSource !== 'center-capsule' ||
      this.toolbarExpansionStage !== 'preview' ||
      !this.shouldRenderFloatingActionSurface() ||
      !Number.isFinite(offsetY) ||
      offsetY > -BROWSER_BOTTOM_PANEL_FLOATING_CONTENT_REVEAL_DISTANCE) {
      return;
    }
    this.floatingActionGestureRevealTimer = setTimeout(() => {
      this.floatingActionGestureRevealTimer = -1;
      if (this.activeChromeGestureSource !== 'center-capsule' ||
        this.floatingActionContentSettled ||
        !this.shouldRenderFloatingActionSurface()) {
        return;
      }
      this.floatingActionContentGestureRevealed = true;
      this.beginFloatingActionContentEntry();
    }, 0);
  }

  private clearFloatingActionGestureReveal(): void {
    if (this.floatingActionGestureRevealTimer >= 0) {
      clearTimeout(this.floatingActionGestureRevealTimer);
      this.floatingActionGestureRevealTimer = -1;
    }
  }

  private shouldSequenceFloatingActionContentExit(): boolean {
    return this.toolbarExpansionStage === 'preview' &&
      this.isExpandedPanelDetent(this.panelDetent) &&
      this.shouldRenderFloatingActionSurface();
  }

  private isAddressInputPresentationActive(): boolean {
    return this.buildSearchChromeSurfaceState().inputPresentationActive;
  }

  private shouldRenderFloatingSuggestionPanel(): boolean {
    return this.shouldMountFloatingSuggestionPanel();
  }

  private shouldReserveFloatingSuggestionPanelHeight(): boolean {
    if (this.shouldMountFloatingSuggestionPanel()) {
      return true;
    }
    if (!this.isAddressInputPresentationActive()) {
      return false;
    }
    // Keep input geometry stable while suggestions are refreshed or briefly empty.
    return this.panelDetent === 'middle' || this.panelTargetDetent === 'middle';
  }

  private shouldMountFloatingSuggestionPanel(): boolean {
    return this.buildSearchChromeSurfaceState().suggestionsPanelMounted;
  }

  private resolveFloatingLayoutMode(): 'stack' | 'input' {
    return this.buildSearchChromeSurfaceState().floatingLayoutMode;
  }

  private shouldUseLightweightCollapsedSearchMotion(): boolean {
    return this.buildSearchChromeSurfaceState().lightweightCollapsedMotion;
  }

  private shouldSelectAllWebAddress(): boolean {
    return this.isWebContentMode() &&
      this.addressInputAdapterActive &&
      this.addressFocused &&
      this.editingAddressText.length > 0;
  }

  private shouldKeepFloatingHeaderDefaultChrome(): boolean {
    return this.resolveFloatingExpandedHeaderHorizontalInset() > 0;
  }

  private shouldUseCollapsedFloatingHeaderDarkBackground(): boolean {
    return this.resolveFloatingHeaderInsetProgress() <= 0.01;
  }

  private resolveFloatingHeaderInsetProgress(): number {
    if (this.resolveFloatingExpandedHeaderHorizontalInset() <= 0) {
      return 0;
    }
    return this.resolveFloatingHeaderTravelProgress();
  }

  private resolveFloatingHeaderGrayProgress(): number {
    return resolveBrowserBottomFloatingHeaderGrayProgress(this.resolveFloatingHeaderTravelProgress());
  }

  private resolveFloatingHeaderTravelProgress(): number {
    const middleHeight = this.resolveMiddlePanelHeight();
    const lowHeight = this.resolveLowPanelDragHeight();
    if (middleHeight <= lowHeight) {
      return 0;
    }
    if (this.panelDragHeight > 0) {
      const travelDistance = Math.max(1, middleHeight - lowHeight);
      return Math.max(0, Math.min(1, (this.panelDragHeight - lowHeight) / travelDistance));
    }
    if (this.panelDetent === 'middle' || this.panelTargetDetent === 'middle') {
      return 1;
    }
    return 0;
  }

  private resolveSecondaryActionBackgroundColor(
    item: BrowserBottomAddressPanelAction,
    pressKey: string
  ): ResourceColor {
    if (this.pressedActionId === pressKey) {
      return this.resolvePressedBackgroundColor();
    }
    return item.selected === true ? this.storedAccentColor : this.resolveCardBackgroundColorValue();
  }

  private resolveSecondaryActionImageFillColor(item: BrowserBottomAddressPanelAction): ResourceColor | undefined {
    if (item.selected === true) {
      return this.storedSelectedIconForegroundColor;
    }
    return undefined;
  }

  private resolveSecondaryActionTextColor(item: BrowserBottomAddressPanelAction): ResourceColor {
    if (!item.enabled) {
      return this.resolveSecondaryTextColor();
    }
    if (item.selected === true) {
      return this.storedSelectedIconForegroundColor;
    }
    return this.resolvePrimaryTextColor();
  }

  private resolveSecondaryActionTrailingTextColor(item: BrowserBottomAddressPanelAction): ResourceColor {
    if (item.selected === true) {
      return this.storedSelectedIconForegroundColor;
    }
    return this.resolveSecondaryTextColor();
  }

  private resolveSecondaryActionScale(pressKey: string): number {
    return this.pressedActionId === pressKey ? WEB_BOTTOM_SECONDARY_ACTION_PRESSED_SCALE : 1;
  }

  private resolvePressedBackground(actionId: string): ResourceColor {
    return this.pressedActionId === actionId ? this.resolvePressedBackgroundColor() :
      $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveCardBackgroundColorValue(): ResourceColor {
    return this.resolveNeutralContainerBackgroundColor();
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    return resolveBrowserBottomNeutralPressedColor(this.resolveNeutralThemeMode());
  }

  private resolveIconColor(enabled: boolean): ResourceColor {
    if (!enabled) {
      return this.resolveSecondaryTextColor();
    }
    return this.resolveIconColorValue();
  }

  private resolveIconColorValue(): ResourceColor {
    return this.resolveNeutralPrimaryContentColor();
  }

  private resolveActionIconOpacity(enabled: boolean): number {
    return enabled ? BROWSER_BOTTOM_NEUTRAL_ICON_ENABLED_OPACITY : BROWSER_BOTTOM_NEUTRAL_ICON_DISABLED_OPACITY;
  }

  private resolveItemTextColor(enabled: boolean): ResourceColor {
    return enabled ? this.resolvePrimaryTextColor() : this.resolveSecondaryTextColor();
  }

  private resolveQuickActionLabelColor(enabled: boolean): ResourceColor {
    if (this.isHomeContentMode() || this.isWebContentMode()) {
      const foreground = this.resolveSearchForegroundPresentation();
      return enabled ? foreground.primaryTextColor : foreground.secondaryTextColor;
    }
    return this.resolveItemTextColor(enabled);
  }

  private buildAdaptiveForegroundRenderKey(): string {
    if (!this.supportsAdaptiveSearchSuggestionForeground()) {
      return this.liveBottomChromePresentation.contentPresentation;
    }
    const foreground = this.resolveSearchForegroundPresentation();
    return `${this.liveBottomChromePresentation.contentPresentation}:${foreground.freshnessKey}`;
  }

  private syncQuickActionLabelContrast(
    nextDetent: HomeSearchPanelDetent,
    previousDetent: HomeSearchPanelDetent,
    forceRefresh: boolean = false
  ): void {
    const expanded = this.isExpandedPanelDetent(nextDetent);
    if (this.isHomeContentMode()) {
      this.quickActionLabelContrastCoordinator.dispose();
      this.quickActionLabelTone = this.homeForegroundPresentation.tone;
      return;
    }
    const request: BrowserBottomToolbarLabelContrastRequest = {
      uiContext: this.getUIContext(),
      componentSnapshotId: this.resolveAdaptiveBackdropSnapshotId(),
      sessionId: this.resolveAdaptiveBackdropSessionId(),
      backdropRevision: this.resolveAdaptiveBackdropFreshnessKey(),
      currentTone: this.quickActionLabelTone,
      expanded: expanded,
      backdropAvailable: this.isAdaptiveBackdropAvailable()
    };
    const applyTone: BrowserBottomToolbarLabelToneApplier = (tone: BrowserBottomToolbarLabelTone): void => {
      this.quickActionLabelTone = tone;
    };
    this.quickActionLabelContrastCoordinator.updateExpansion(
      request,
      forceRefresh || (expanded && !this.isExpandedPanelDetent(previousDetent)),
      applyTone
    );
  }

  private supportsAdaptiveSearchSuggestionForeground(): boolean {
    return this.isHomeContentMode() || this.isWebContentMode();
  }

  private resolveAdaptiveBackdropSnapshotId(): string {
    return this.isWebContentMode() ? this.quickActionLabelSnapshotId : '';
  }

  private resolveAdaptiveBackdropSessionId(): string {
    return this.isWebContentMode() ? this.quickActionLabelTabId : '';
  }

  private resolveAdaptiveBackdropFreshnessKey(): string {
    if (this.isHomeContentMode()) {
      return this.homeForegroundPresentation.freshnessKey;
    }
    return `${this.quickActionLabelBackdropRevision}:${this.liveAddressDisplayText}`;
  }

  private isAdaptiveBackdropAvailable(): boolean {
    if (this.isHomeContentMode()) {
      return true;
    }
    return this.isWebContentMode() && this.quickActionLabelWebPageVisible &&
      this.quickActionLabelControllerAttached;
  }

  private isWebContentMode(): boolean {
    return this.liveBottomChromePresentation.contentPresentation === 'web';
  }

  private resolveSearchForegroundPresentation(): BrowserForegroundPresentation {
    if (this.isHomeContentMode()) {
      return this.homeForegroundPresentation;
    }
    return this.browserForegroundPresentationViewModel.resolveWebPresentation(
      this.quickActionLabelTone,
      this.resolveAdaptiveBackdropFreshnessKey()
    );
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.resolveNeutralPrimaryContentColor();
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.resolveNeutralSecondaryContentColor();
  }

  private resolveNeutralContainerBackgroundColor(): ResourceColor {
    return resolveBrowserBottomNeutralContainerColor(this.resolveNeutralThemeMode());
  }

  private resolveNeutralPrimaryContentColor(): ResourceColor {
    return resolveBrowserBottomNeutralPrimaryColor(this.resolveNeutralThemeMode());
  }

  private resolveNeutralSecondaryContentColor(): ResourceColor {
    return resolveBrowserBottomNeutralSecondaryColor(this.resolveNeutralThemeMode());
  }

  private resolveNeutralThemeMode(): string {
    return this.storedResolvedThemeMode;
  }

  private resolveChromeIconTone(): AppChromeIconTone {
    return AppIconResources.chromeToneForResolvedThemeMode(this.storedResolvedThemeMode);
  }

}
