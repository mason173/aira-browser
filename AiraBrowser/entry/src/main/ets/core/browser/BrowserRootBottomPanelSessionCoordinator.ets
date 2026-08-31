import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import {
  BrowserRootAddressInputSessionCoordinator,
  BrowserRootAddressInputSessionEndPlan,
  BrowserRootAddressInputSessionSnapshot
} from './BrowserRootAddressInputSessionCoordinator';
import {
  HomeSearchDismissInput,
  HomeSearchOverlayViewModel,
  HomeSearchReleaseInput,
  HomeSearchReleasePlan
} from './HomeSearchOverlayViewModel';
import { BrowserThemeMode } from '../../common/models/BrowserModels';
import {
  BrowserBottomAddressPanelHeaderAction,
  BrowserBottomPanelMotionState
} from './BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelResponsiveState } from './BrowserBottomPanelResponsiveViewModel';
import {
  BROWSER_BOTTOM_PANEL_COLLAPSE_TO_PEEK_ANIMATION_DURATION_MS,
  BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS,
  BROWSER_BOTTOM_PANEL_PEEK_TO_LOW_ANIMATION_DURATION_MS,
  resolveBrowserBottomPanelMiddleSnapCurve
} from './BrowserBottomPanelMotionTokens';
import { BrowserBottomPanelActionId } from './BrowserBottomPanelActionCatalog';
import {
  BrowserBottomPanelActionEnablement,
  BrowserBottomPanelActionEnablementById
} from './BrowserBottomPanelActionEnablement';
import { BrowserHomeActionAvailabilityCoordinator } from './BrowserHomeActionAvailabilityCoordinator';
import {
  BrowserBottomPanelActionSnapshot,
  BrowserBottomPanelActionTarget,
  BrowserBottomPanelActionTargetInput
} from './BrowserBottomPanelActionPresentationCoordinator';
import {
  BrowserRootBottomPanelLayoutInput,
  BrowserRootBottomPanelLayoutModel,
  BrowserRootBottomPanelLayoutState
} from './BrowserRootBottomPanelLayoutModel';
import {
  BrowserBottomAddressPresentationInput,
  BrowserBottomAddressSuggestionInput,
  BrowserBottomAddressTransientMessageContext,
  BrowserBottomAddressTransientMessageState,
  BrowserBottomAddressTransientMessageViewModel,
  EMPTY_BROWSER_BOTTOM_ADDRESS_TRANSIENT_MESSAGE_STATE
} from './BrowserBottomAddressTransientMessageViewModel';
import {
  BrowserBottomChromeGestureSource,
  BrowserBottomChromePresentation,
  BrowserBottomChromePresentationFacts,
  BrowserBottomChromePresentationViewModel
} from './BrowserBottomChromePresentationViewModel';
import {
  BrowserWebProtectionFeedbackPresentation
} from './BrowserWebProtectionFeedbackSessionCoordinator';
import {
  BrowserBottomChromeHomeScrollDecision,
  BrowserBottomChromeScrollPresentation,
  BrowserBottomChromeWebScrollDecision
} from './BrowserBottomChromeScrollCoordinator';
import {
  BrowserSearchEngineChromePresentation
} from './BrowserSearchEnginePresentationViewModel';
import { BrowserToolbarSlotActionState } from './BrowserToolbarCustomizationViewModel';
import {
  BrowserSearchBackdropPresentationViewModel,
  BrowserSearchBackdropSettlePlan
} from './BrowserSearchBackdropPresentationViewModel';
import {
  BrowserSearchBackdropPresentationChannel
} from './BrowserSearchBackdropPresentationChannel';
import {
  BrowserBottomPanelLivePresentation,
  BrowserBottomPanelReadingContinuationPresentation,
  HIDDEN_BROWSER_BOTTOM_PANEL_READING_CONTINUATION
} from './BrowserBottomPanelPresentationChannel';
import { NovelReaderSnapshot } from '../../features/novel/NovelReaderModels';
import vibrator from '@ohos.vibrator';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserToolbarInteractionActionState,
  BrowserToolbarInteractionKind,
  BrowserToolbarSlotId
} from './BrowserToolbarCustomizationViewModel';

export {
  BrowserRootAddressInputSessionSnapshot
} from './BrowserRootAddressInputSessionCoordinator';
export {
  BrowserRootBottomPanelLayoutInput,
  BrowserRootBottomPanelLayoutState
} from './BrowserRootBottomPanelLayoutModel';
export {
  BrowserBottomPanelActionSnapshot,
  BrowserBottomPanelActionTarget,
  BrowserBottomPanelActionTargetInput
} from './BrowserBottomPanelActionPresentationCoordinator';
export {
  BrowserBottomAddressPresentationInput,
  BrowserBottomAddressSuggestionInput,
  BrowserBottomAddressTransientMessageContext
} from './BrowserBottomAddressTransientMessageViewModel';

export type BrowserRootBottomPanelDetentApplication = 'none' | 'assign' | 'apply';
export type BrowserRootBottomPanelActionDispatchTiming = 'immediate' | 'after_low_settle';
export type BrowserRootBottomPanelScene = 'home' | 'web' | 'inactive';
export type BrowserRootBottomPanelHeaderPresentation = 'home' | 'address';
export type BrowserRootBottomPanelContentPresentation = 'home' | 'web';
export type BrowserRootBottomPanelActionSource = 'panel' | 'header';
export type BrowserBottomPanelHostMode = 'hidden' | 'browser';
export type BrowserRootBottomPanelSearchHostPreparationStatus = 'ready' | 'cancelled' | 'timed_out';

export class BrowserRootBottomPanelSearchHostPreparationResult {
  status: BrowserRootBottomPanelSearchHostPreparationStatus;
  generation: number;

  constructor(status: BrowserRootBottomPanelSearchHostPreparationStatus, generation: number) {
    this.status = status;
    this.generation = generation;
  }
}

class BrowserRootBottomPanelSearchHostPreparationDeferred {
  readonly promise: Promise<BrowserRootBottomPanelSearchHostPreparationResult>;
  private resolver?: (result: BrowserRootBottomPanelSearchHostPreparationResult) => void = undefined;
  private resolved: boolean = false;

  constructor() {
    this.promise = new Promise<BrowserRootBottomPanelSearchHostPreparationResult>((resolve) => {
      this.resolver = resolve;
    });
  }

  resolve(result: BrowserRootBottomPanelSearchHostPreparationResult): void {
    if (this.resolved || this.resolver === undefined) {
      return;
    }
    this.resolved = true;
    this.resolver(result);
    this.resolver = undefined;
  }
}

interface BrowserRootBottomPanelPendingSearchHostPreparation {
  generation: number;
  deferred: BrowserRootBottomPanelSearchHostPreparationDeferred;
  timer: number;
}

export interface BrowserRootBottomPanelDeferredWorkHandle {
  cancel: () => void;
}

interface BrowserRootBottomPanelDeferredWorkEntry {
  id: number;
  work: () => void;
  timer: number;
  cancelled: boolean;
}


export interface BrowserRootBottomPanelDetentInput {
  webVideoControllerActive: boolean;
  documentViewerActive: boolean;
  documentViewerExpansionEnabled: boolean;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
  currentDetent: HomeSearchPanelDetent;
}

export interface BrowserRootBottomChromeImmersionInput {
  effectiveWebMode: boolean;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
  assistantVideoTakeoverActive: boolean;
}

export interface BrowserRootBottomPanelMotionInput {
  currentDetent: HomeSearchPanelDetent;
  immediateLowDetentRequestVersion: number;
  layoutState: BrowserRootBottomPanelLayoutState;
  showHomePage: boolean;
  keyboardOverlayInset: number;
  fullScreenModeEnabled: boolean;
  documentViewerActive: boolean;
  documentViewerScrollCollapseEnabled: boolean;
  documentViewerExpansionEnabled: boolean;
}

export interface BrowserRootBottomPanelPeekInput {
  fullScreenModeEnabled: boolean;
  documentViewerActive: boolean;
  documentViewerScrollCollapseEnabled: boolean;
}

export interface BrowserRootBottomPanelPeekGestureInput {
  documentViewerActive: boolean;
}

export interface BrowserRootBottomPanelExpansionInput {
  documentViewerActive: boolean;
  documentViewerExpansionEnabled: boolean;
}

export interface BrowserRootBottomPanelDetentDragInput {
  fullScreenModeEnabled: boolean;
  expansionEnabled: boolean;
}

export interface BrowserRootBottomPanelCommittedDetentInput {
  effectiveWebMode: boolean;
  nextDetent: HomeSearchPanelDetent;
  webVideoControllerActive: boolean;
  documentViewerActive: boolean;
  documentViewerExpansionEnabled: boolean;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
}

export interface BrowserRootBottomPanelCommittedDetentState {
  detent: HomeSearchPanelDetent;
  clearWebAddressDraft: boolean;
  hideStatusBarForFullScreenMode: boolean;
}

export interface BrowserRootBottomPanelExpandedScrimInput {
  readerModeVisible: boolean;
  novelReaderVisible: boolean;
  homePageVisible: boolean;
  tabsSheetVisible: boolean;
  webPageVisible: boolean;
  bottomPanelHostVisible: boolean;
  detent: HomeSearchPanelDetent;
  backdropProgress: number;
}

export interface BrowserRootBottomPanelExpandedScrimState {
  visible: boolean;
  mounted: boolean;
  surfaceEligible: boolean;
  blockHitTest: boolean;
  backdropProgress: number;
}

export interface BrowserRootBottomPanelGestureInput {
  showHomePage: boolean;
  showTabsSheet: boolean;
  webPageVisible: boolean;
  currentDetent: HomeSearchPanelDetent;
  addressFocused: boolean;
  offsetY: number;
  source: BrowserBottomChromeGestureSource;
  peekGestureEnabled: boolean;
  documentViewerActive: boolean;
  webVideoControllerActive: boolean;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
}

export interface BrowserRootBottomPanelGestureFrame {
  phase: 'start' | 'update';
  panelHeight: number;
  middlePanelHeight: number;
  lowPanelHeight: number;
  expansionEnabled: boolean;
}

export type BrowserRootBottomPanelGestureIntent = 'none' | 'return_home' | 'hide_search';
type BrowserRootBottomPanelGestureOwner = 'none' | 'search_panel' | 'return_home';
export type BrowserBottomPanelBackdropSurface = 'home' | 'web';

export interface BrowserRootBottomPanelGesturePresentation {
  intent: BrowserRootBottomPanelGestureIntent;
  text: string;
  armed: boolean;
  progress: number;
}

export interface BrowserRootBottomPanelGestureState {
  suppressSearchBackdrop: boolean;
  thresholdFeedbackRequested: boolean;
}

export interface BrowserRootBottomPanelGestureReleasePlan {
  interceptPanelReleaseTarget?: HomeSearchPanelDetent;
  settleBackdropToLow: boolean;
  shouldReturnHome: boolean;
  toolbarActionSlotId?: BrowserToolbarSlotId;
}

export interface BrowserRootBottomPanelGestureReleaseEffects {
  settleBackdropToLow: () => void;
  returnHome: () => void;
}

interface BrowserRootBottomPanelGestureResolution {
  returnHomeActive: boolean;
  suppressSearchBackdrop: boolean;
  presentation: BrowserRootBottomPanelGesturePresentation;
}

export interface BrowserRootBottomPanelPresentationState {
  gesturePrompt: BrowserRootBottomPanelGesturePresentation;
  returnHomeGestureActive: boolean;
  scrollPresentation: BrowserBottomChromeScrollPresentation;
  transientMessage: BrowserBottomAddressTransientMessageState;
}

export interface BrowserRootBottomPanelPresentationSnapshot extends BrowserRootBottomPanelPresentationState {
  revision: number;
}

export interface BrowserRootBottomPanelSessionSink {
  publishPresentationSnapshot: (snapshot: BrowserRootBottomPanelPresentationSnapshot) => void;
  isHomePageVisible: () => boolean;
  applyChromePlan: (plan: BrowserRootBottomPanelChromePlan) => void;
  applyShellEffect: (effect: BrowserRootBottomPanelShellEffect) => void;
}

export interface BrowserBottomPanelHostInput {
  scene: BrowserRootBottomPanelScene;
  homeSearchBarVisible: boolean;
  homeSearchSessionActive: boolean;
  readerModeVisible: boolean;
  novelReaderVisible: boolean;
  viewportHeight: number;
  browserHostHeight: number;
}

export interface BrowserBottomPanelHostState {
  mode: BrowserBottomPanelHostMode;
  scene: BrowserRootBottomPanelScene;
  hostHeight: number;
  zIndex: number;
  interactiveOutsidePanel: boolean;
  tabsOverviewHomeEntryEligible: boolean;
}

const BROWSER_ROOT_BOTTOM_PANEL_GESTURE_ACTIVE_OFFSET_Y: number = 8;
const BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_MIN_OFFSET_Y: number = 30;
const BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_CONTINUE_TEXT: string = '继续下滑隐藏';
const BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_RELEASE_TEXT: string = '松手隐藏';
const BROWSER_BOTTOM_PANEL_HOST_Z_INDEX: number = 198;
// The panel owns the animation timer, but a remount can cancel that timer before
// the shell receives onPanelSettled. Keep action completion in the session owner.
const BROWSER_ROOT_BOTTOM_PANEL_ACTION_SETTLE_FALLBACK_MS: number =
  BROWSER_BOTTOM_PANEL_PEEK_TO_LOW_ANIMATION_DURATION_MS + 120;
const BROWSER_ROOT_BOTTOM_PANEL_HOME_TO_WEB_TRANSITION_FALLBACK_MS: number =
  BROWSER_BOTTOM_PANEL_PEEK_TO_LOW_ANIMATION_DURATION_MS + 40;
const BROWSER_ROOT_BOTTOM_PANEL_GESTURE_HAPTIC_DURATION_MS: number = 16;
const BROWSER_ROOT_BOTTOM_PANEL_SEARCH_HOST_PREPARATION_TIMEOUT_MS: number = 1500;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';

export interface BrowserRootBottomPanelSemanticInput {
  showHomePage: boolean;
  webPageVisible: boolean;
  homeAddressFocused: boolean;
  webAddressFocused: boolean;
}

export interface BrowserRootBottomPanelSemanticState {
  scene: BrowserRootBottomPanelScene;
  headerPresentation: BrowserRootBottomPanelHeaderPresentation;
  contentPresentation: BrowserRootBottomPanelContentPresentation;
  effectiveHome: boolean;
  effectiveWeb: boolean;
  addressFocused: boolean;
}

export interface BrowserRootBottomPanelSemanticProjection extends BrowserRootBottomPanelSemanticState {
  leadingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
  trailingHeaderActions: BrowserBottomAddressPanelHeaderAction[];
}

export interface BrowserRootBottomChromePresentationInput {
  semanticState: BrowserRootBottomPanelSemanticState;
  responsiveState: BrowserBottomPanelResponsiveState;
  currentDetent: HomeSearchPanelDetent;
  panelExpansionEnabled: boolean;
  addressPresentation: BrowserBottomAddressPresentationInput;
  searchEnginePresentation: BrowserSearchEngineChromePresentation;
  addressEditable: boolean;
  webProtectionFeedback: BrowserWebProtectionFeedbackPresentation;
}

export interface BrowserRootBottomPanelLivePresentationInput extends BrowserRootBottomChromePresentationInput {
  panelMotionState: BrowserBottomPanelMotionState;
  responsiveLayoutKey: string;
  readingSnapshot: NovelReaderSnapshot;
}

export interface BrowserRootBottomPanelHostMountInput {
  showTabsSheet: boolean;
  retainForTabsOverviewEntry: boolean;
  readerModeVisible: boolean;
  novelReaderVisible: boolean;
  webAppImmersiveMode: boolean;
  webVideoControllerFullscreenActive: boolean;
  largeScreenShellActive: boolean;
}

export interface BrowserRootBottomPanelSessionSnapshot {
  isHomeMode: boolean;
  isWebMode: boolean;
  showHomePage: boolean;
  homeSearchFocused: boolean;
  homeSearchOverlayVisible: boolean;
  currentDetent: HomeSearchPanelDetent;
  panelExpansionEnabled: boolean;
}

export interface BrowserRootBottomPanelAddressFocusStateChangeInput {
  focused: boolean;
  isHomeMode: boolean;
  isWebMode: boolean;
}

export interface BrowserRootBottomPanelChromePlan {
  targetDetent?: HomeSearchPanelDetent;
  detentApplication: BrowserRootBottomPanelDetentApplication;
  immediateLowDetent: boolean;
  deferLowDetentUntilSettle: boolean;
  homeDismissAfterLowSettle: boolean;
  shouldResetSearchOverlay: boolean;
  shouldReleaseHomeSearchFocus: boolean;
  shouldFocusHomeSearchInput: boolean;
  shouldClearHomeSearchFocus: boolean;
  shouldClearHomeAddressInput: boolean;
  shouldClearWebAddressFocus: boolean;
  shouldFocusWebAddressInput: boolean;
  shouldClearWebAddressDraft: boolean;
  shouldRestoreScrollPresentation: boolean;
  shouldRequestKeyboardInsetSync: boolean;
  shouldReleaseKeyboardAvoidMode: boolean;
  shouldHideTextInput: boolean;
  shouldReleaseHomeSearchBeforeBackdropEffects: boolean;
  shouldCancelBackdropFocusTransition: boolean;
  shouldCollapseSearchBackdropProgress: boolean;
  shouldEnsureHomeAddressFocusBackdrop: boolean;
  shouldEnsureWebAddressFocusBackdrop: boolean;
  shouldSyncBottomPanelStatusBarStyle: boolean;
  shouldEndSearchInvocationForAction: boolean;
  webStatusBarRestoreReason: string;
}

export interface BrowserRootBottomPanelAddressSubmitPlan {
  rawInput: string;
  chromePlan: BrowserRootBottomPanelChromePlan;
}

export interface BrowserRootBottomPanelHeaderActionDispatch {
  lane: 'header';
  actionId: string;
}

export interface BrowserRootBottomPanelPanelActionDispatch {
  lane: 'home' | 'web';
  actionId: BrowserBottomPanelActionId;
}

export type BrowserRootBottomPanelActionDispatch =
  BrowserRootBottomPanelHeaderActionDispatch | BrowserRootBottomPanelPanelActionDispatch;

export type BrowserRootBottomPanelShellAction =
  'open_document_viewer_info' |
  'scan_qr' |
  'toggle_private_mode' |
  'open_text_zoom' |
  'open_site_report' |
  'open_tabs_overview' |
  'request_browser_back';

export interface BrowserRootBottomPanelShellActionEffect {
  kind: 'action';
  action: BrowserRootBottomPanelShellAction;
}

export interface BrowserRootBottomPanelActionRejectionEffect {
  kind: 'action_rejection';
  message: string;
}

export type BrowserRootBottomPanelShellEffect =
  BrowserRootBottomPanelShellActionEffect | BrowserRootBottomPanelActionRejectionEffect;

export interface BrowserRootBottomPanelActionApplication {
  apply(
    dispatch: BrowserRootBottomPanelActionDispatch,
    showHomePage: boolean
  ): BrowserRootBottomPanelShellAction | undefined;
  buildSemanticProjection(
    semanticState: BrowserRootBottomPanelSemanticState
  ): BrowserRootBottomPanelSemanticProjection;
  resolveActionSnapshot(
    semanticState: BrowserRootBottomPanelSemanticState,
    responsiveState: BrowserBottomPanelResponsiveState,
    responsiveLayoutKey: string
  ): BrowserBottomPanelActionSnapshot;
  resolveActionTarget(input: BrowserBottomPanelActionTargetInput): BrowserBottomPanelActionTarget;
  resolveToolbarActionEnablement(actionId: BrowserBottomPanelActionId): BrowserBottomPanelActionEnablement;
  resolveWebpageTranslationPromptAvailability(): boolean;
  resolveBookmarkActionAvailability(): boolean;
  setWebProtectionFeedbackPhoneChromeCompact(compact: boolean): void;
  resolveToolbarSlotActions(): BrowserToolbarSlotActionState[];
  resolveThemeModeActionTitleForMode(mode: BrowserThemeMode): string;
}

export type BrowserRootBottomPanelActionApplicationResolver = () => BrowserRootBottomPanelActionApplication;

export interface BrowserRootBottomPanelActionTapTransition {
  rejectionMessage?: string;
}

export interface BrowserRootBottomPanelSettledTransition {
  shouldCommitRequestedDetent: boolean;
  shouldDismissHomeSearch: boolean;
}

interface BrowserRootBottomPanelActionTapPlan {
  chromePlan: BrowserRootBottomPanelChromePlan;
  dispatchTiming: BrowserRootBottomPanelActionDispatchTiming;
}

export interface BrowserRootBottomPanelExpandedScrimDismissInput extends BrowserRootBottomPanelSessionSnapshot {
  expandedScrimVisible: boolean;
}

export type BrowserRootBottomPanelTransientSheetOwner =
  'web_page_tools' |
  'element_inspection' |
  'app_proxy_quick' |
  'translation_target_language' |
  'reader_speech_player' |
  'bookmark_folder_selection' |
  'feature_gate' |
  'userscript_page_actions' |
  'wifi_qr_result' |
  'resource_candidates' |
  'hls_takeover';

export interface BrowserRootBottomPanelTransientSheetFacts {
  isWebPageVisible: boolean;
  showTabsSheet: boolean;
  showHomePage: boolean;
  currentDetent: HomeSearchPanelDetent;
  activeTabId: string;
  webAddressFocused: boolean;
}

export class BrowserRootBottomPanelSessionCoordinator {
  private readonly sink: BrowserRootBottomPanelSessionSink;
  private readonly resolveActionApplication: BrowserRootBottomPanelActionApplicationResolver;
  private addressInputSessionCoordinator: BrowserRootAddressInputSessionCoordinator;
  private homeSearchOverlayViewModel: HomeSearchOverlayViewModel;
  private homeActionAvailabilityCoordinator: BrowserHomeActionAvailabilityCoordinator;
  private layoutModel: BrowserRootBottomPanelLayoutModel;
  private transientMessageViewModel: BrowserBottomAddressTransientMessageViewModel;
  private bottomChromePresentationViewModel: BrowserBottomChromePresentationViewModel;
  private searchBackdropPresentationViewModel: BrowserSearchBackdropPresentationViewModel;
  private searchBackdropPresentationChannel: BrowserSearchBackdropPresentationChannel;
  private searchBackdropProgress: number = 0;
  private activeSearchBackdropSettleRunId: number = 0;
  private transientSheetOwners: BrowserRootBottomPanelTransientSheetOwner[] = [];
  private transientSheetReturnDetent?: HomeSearchPanelDetent = undefined;
  private transientSheetReturnTabId: string = '';
  private requestedDetentOverride?: HomeSearchPanelDetent = undefined;
  private programmaticHomeToolbarHostActive: boolean = false;
  private programmaticHomeToolbarRestingChromeHidden: boolean = false;
  private searchPresentationHostReady: boolean = false;
  private searchPresentationHostPreparationActive: boolean = false;
  private searchPresentationHostPreparationGeneration: number = 0;
  private pendingSearchPresentationHostPreparation?: BrowserRootBottomPanelPendingSearchHostPreparation = undefined;
  private homeDismissAfterLowSettlePending: boolean = false;
  private pendingActionAfterCollapsedSettle?: BrowserRootBottomPanelActionDispatch = undefined;
  private pendingActionAfterSettleEffects?: BrowserRootBottomPanelActionDispatch = undefined;
  private pendingActionSettleFallbackTimer: number = -1;
  private homeToWebBottomPanelTransitionActive: boolean = false;
  private homeToWebBottomPanelLowDetentSettled: boolean = false;
  private homeToWebBottomPanelTransitionGeneration: number = 0;
  private homeToWebBottomPanelTransitionTimer: number = -1;
  private homeToWebBottomPanelTransitionId: number = 0;
  private homeToWebBottomPanelTransitionStartedAt: number = 0;
  private deferredNavigationWorkSequence: number = 0;
  private deferredNavigationWork: BrowserRootBottomPanelDeferredWorkEntry[] = [];
  private activeGestureOwner: BrowserRootBottomPanelGestureOwner = 'none';
  private pendingBackdropFocusSurface?: BrowserBottomPanelBackdropSurface = undefined;
  private transientMessageClearTimer: number = -1;
  private presentationSnapshot: BrowserRootBottomPanelPresentationSnapshot = {
    gesturePrompt: {
      intent: 'none',
      text: '',
      armed: false,
      progress: 0
    },
    returnHomeGestureActive: false,
    scrollPresentation: 'resting',
    transientMessage: EMPTY_BROWSER_BOTTOM_ADDRESS_TRANSIENT_MESSAGE_STATE,
    revision: 0
  };

  constructor(
    sink: BrowserRootBottomPanelSessionSink,
    resolveActionApplication: BrowserRootBottomPanelActionApplicationResolver,
    addressInputSessionCoordinator: BrowserRootAddressInputSessionCoordinator =
      new BrowserRootAddressInputSessionCoordinator(),
    homeSearchOverlayViewModel: HomeSearchOverlayViewModel = new HomeSearchOverlayViewModel(),
    layoutModel: BrowserRootBottomPanelLayoutModel = new BrowserRootBottomPanelLayoutModel(),
    homeActionAvailabilityCoordinator: BrowserHomeActionAvailabilityCoordinator =
      new BrowserHomeActionAvailabilityCoordinator(),
    transientMessageViewModel: BrowserBottomAddressTransientMessageViewModel =
      new BrowserBottomAddressTransientMessageViewModel(),
    bottomChromePresentationViewModel: BrowserBottomChromePresentationViewModel =
      new BrowserBottomChromePresentationViewModel(),
    searchBackdropPresentationViewModel: BrowserSearchBackdropPresentationViewModel =
      new BrowserSearchBackdropPresentationViewModel()
  ) {
    this.sink = sink;
    this.resolveActionApplication = resolveActionApplication;
    this.addressInputSessionCoordinator = addressInputSessionCoordinator;
    this.homeSearchOverlayViewModel = homeSearchOverlayViewModel;
    this.layoutModel = layoutModel;
    this.homeActionAvailabilityCoordinator = homeActionAvailabilityCoordinator;
    this.transientMessageViewModel = transientMessageViewModel;
    this.bottomChromePresentationViewModel = bottomChromePresentationViewModel;
    this.searchBackdropPresentationViewModel = searchBackdropPresentationViewModel;
    this.searchBackdropPresentationChannel = new BrowserSearchBackdropPresentationChannel(
      (settleRunId: number): void => {
        this.finishSearchBackdropSettle(settleRunId);
      }
    );
  }

  getPresentationSnapshot(): BrowserRootBottomPanelPresentationSnapshot {
    return this.presentationSnapshot;
  }

  invalidatePresentation(): void {
    this.publishPresentationState({
      gesturePrompt: this.presentationSnapshot.gesturePrompt,
      returnHomeGestureActive: this.presentationSnapshot.returnHomeGestureActive,
      scrollPresentation: this.presentationSnapshot.scrollPresentation,
      transientMessage: this.presentationSnapshot.transientMessage
    });
  }

  beginHomeToWebBottomPanelTransition(): void {
    this.homeToWebBottomPanelTransitionId += 1;
    this.homeToWebBottomPanelTransitionStartedAt = Date.now();
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] panel_transition_begin id=%{public}d',
      this.homeToWebBottomPanelTransitionId
    );
    this.homeToWebBottomPanelTransitionGeneration += 1;
    this.clearHomeToWebBottomPanelTransitionTimer();
    this.cancelDeferredNavigationWork();
    this.homeToWebBottomPanelTransitionActive = true;
    this.homeToWebBottomPanelLowDetentSettled = false;
    this.invalidatePresentation();
  }

  scheduleNavigationWorkAfterPresentation(work: () => void): BrowserRootBottomPanelDeferredWorkHandle | undefined {
    const entry: BrowserRootBottomPanelDeferredWorkEntry = {
      id: ++this.deferredNavigationWorkSequence,
      work: work,
      timer: -1,
      cancelled: false
    };
    if (!this.homeToWebBottomPanelTransitionActive) {
      return undefined;
    }
    this.deferredNavigationWork.push(entry);
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] navigation_queued id=%{public}d workId=%{public}d pending=%{public}d elapsedMs=%{public}d',
      this.homeToWebBottomPanelTransitionId,
      entry.id,
      this.deferredNavigationWork.length,
      Date.now() - this.homeToWebBottomPanelTransitionStartedAt
    );
    return this.buildDeferredNavigationWorkHandle(entry);
  }

  scheduleHomeToWebBottomPanelTransitionCompletion(): void {
    if (!this.homeToWebBottomPanelTransitionActive || this.homeToWebBottomPanelTransitionTimer >= 0) {
      return;
    }
    if (this.homeToWebBottomPanelLowDetentSettled) {
      this.finishHomeToWebBottomPanelTransition(false);
      return;
    }
    const generation = this.homeToWebBottomPanelTransitionGeneration;
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] panel_settle_wait id=%{public}d elapsedMs=%{public}d fallbackMs=%{public}d',
      this.homeToWebBottomPanelTransitionId,
      Date.now() - this.homeToWebBottomPanelTransitionStartedAt,
      BROWSER_ROOT_BOTTOM_PANEL_HOME_TO_WEB_TRANSITION_FALLBACK_MS
    );
    this.homeToWebBottomPanelTransitionTimer = setTimeout((): void => {
      this.homeToWebBottomPanelTransitionTimer = -1;
      if (generation !== this.homeToWebBottomPanelTransitionGeneration) {
        return;
      }
      hilog.warn(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] panel_settle_fallback id=%{public}d elapsedMs=%{public}d',
        this.homeToWebBottomPanelTransitionId,
        Date.now() - this.homeToWebBottomPanelTransitionStartedAt
      );
      this.finishHomeToWebBottomPanelTransition(true);
    }, BROWSER_ROOT_BOTTOM_PANEL_HOME_TO_WEB_TRANSITION_FALLBACK_MS);
  }

  completeHomeToWebBottomPanelTransition(lowDetentSettled: boolean): void {
    if (!this.homeToWebBottomPanelTransitionActive) {
      return;
    }
    if (!lowDetentSettled) {
      return;
    }
    this.homeToWebBottomPanelLowDetentSettled = true;
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] panel_settled id=%{public}d elapsedMs=%{public}d',
      this.homeToWebBottomPanelTransitionId,
      Date.now() - this.homeToWebBottomPanelTransitionStartedAt
    );
    this.finishHomeToWebBottomPanelTransition(false);
  }

  cancelHomeToWebBottomPanelTransition(): void {
    this.homeToWebBottomPanelTransitionGeneration += 1;
    this.clearHomeToWebBottomPanelTransitionTimer();
    this.cancelDeferredNavigationWork();
    if (!this.homeToWebBottomPanelTransitionActive) {
      return;
    }
    this.homeToWebBottomPanelTransitionActive = false;
    this.homeToWebBottomPanelLowDetentSettled = false;
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] panel_transition_cancel id=%{public}d elapsedMs=%{public}d',
      this.homeToWebBottomPanelTransitionId,
      Date.now() - this.homeToWebBottomPanelTransitionStartedAt
    );
    this.invalidatePresentation();
  }

  isHomeToWebBottomPanelTransitionActive(): boolean {
    return this.homeToWebBottomPanelTransitionActive;
  }

  resolveDetent(input: BrowserRootBottomPanelDetentInput): HomeSearchPanelDetent {
    if (input.webVideoControllerActive || input.webAppImmersiveMode || input.fullScreenModeEnabled) {
      return 'peek';
    }
    if (input.documentViewerActive && !input.documentViewerExpansionEnabled) {
      return input.currentDetent === 'peek' ? 'peek' : 'low';
    }
    return input.currentDetent;
  }

  isScrollPresentationActive(): boolean {
    return this.presentationSnapshot.scrollPresentation !== 'resting';
  }

  shouldHideBottomChromeForImmersion(input: BrowserRootBottomChromeImmersionInput): boolean {
    if (!input.effectiveWebMode) {
      return false;
    }
    return input.webAppImmersiveMode || input.fullScreenModeEnabled || input.assistantVideoTakeoverActive;
  }

  resolveActivePanelHeight(layoutState: BrowserRootBottomPanelLayoutState, showHomePage: boolean): number {
    return showHomePage ? layoutState.homePanelHeight : layoutState.webPanelHeight;
  }

  resolveActiveHostHeight(layoutState: BrowserRootBottomPanelLayoutState, showHomePage: boolean): number {
    return showHomePage ? layoutState.homeHostHeight : layoutState.webHostHeight;
  }

  buildMotionState(input: BrowserRootBottomPanelMotionInput): BrowserBottomPanelMotionState {
    const panelExpansionEnabled = this.resolveExpansionEnabled({
      documentViewerActive: input.documentViewerActive,
      documentViewerExpansionEnabled: input.documentViewerExpansionEnabled
    });
    return {
      targetDetent: this.resolveRequestedDetent(input.currentDetent),
      immediateLowDetentRequestVersion: input.immediateLowDetentRequestVersion,
      bottomInset: 0,
      panelHeight: this.resolveActivePanelHeight(input.layoutState, input.showHomePage),
      middlePanelHeight: 0,
      overlayHostHeight: this.resolveActiveHostHeight(input.layoutState, input.showHomePage),
      keyboardOverlayInset: input.keyboardOverlayInset,
      visible: this.presentationSnapshot.scrollPresentation !== 'hidden',
      detentDragEnabled: this.resolveDetentDragEnabled({
        fullScreenModeEnabled: input.fullScreenModeEnabled,
        expansionEnabled: panelExpansionEnabled
      }),
      panelExpansionEnabled: panelExpansionEnabled,
      suppressExpandedContentFromDrag: this.presentationSnapshot.returnHomeGestureActive ||
        this.presentationSnapshot.gesturePrompt.intent === 'return_home',
      peekEnabled: this.resolvePeekEnabled({
        fullScreenModeEnabled: input.fullScreenModeEnabled,
        documentViewerActive: input.documentViewerActive,
        documentViewerScrollCollapseEnabled: input.documentViewerScrollCollapseEnabled
      }),
      peekGestureEnabled: this.resolvePeekGestureEnabled({
        documentViewerActive: input.documentViewerActive
      }),
      peekToLowAnimationDurationMs: BROWSER_BOTTOM_PANEL_PEEK_TO_LOW_ANIMATION_DURATION_MS,
      collapseToPeekAnimationDurationMs: BROWSER_BOTTOM_PANEL_COLLAPSE_TO_PEEK_ANIMATION_DURATION_MS
    };
  }

  resolvePeekEnabled(input: BrowserRootBottomPanelPeekInput): boolean {
    if (input.fullScreenModeEnabled) {
      return true;
    }
    return input.documentViewerActive ? input.documentViewerScrollCollapseEnabled : true;
  }

  resolvePeekGestureEnabled(input: BrowserRootBottomPanelPeekGestureInput): boolean {
    return !input.documentViewerActive;
  }

  resolveExpansionEnabled(input: BrowserRootBottomPanelExpansionInput): boolean {
    return input.documentViewerActive ? input.documentViewerExpansionEnabled : true;
  }

  resolveDetentDragEnabled(input: BrowserRootBottomPanelDetentDragInput): boolean {
    return input.expansionEnabled && !input.fullScreenModeEnabled;
  }

  resolveCommittedDetent(
    input: BrowserRootBottomPanelCommittedDetentInput
  ): BrowserRootBottomPanelCommittedDetentState {
    const state: BrowserRootBottomPanelCommittedDetentState = {
      detent: input.nextDetent,
      clearWebAddressDraft: false,
      hideStatusBarForFullScreenMode: false
    };
    if (!input.effectiveWebMode) {
      return state;
    }
    if (input.webVideoControllerActive) {
      state.detent = 'peek';
      state.clearWebAddressDraft = true;
    } else if (input.documentViewerActive && !input.documentViewerExpansionEnabled) {
      state.detent = input.nextDetent === 'peek' ? 'peek' : 'low';
      state.clearWebAddressDraft = true;
    } else if (input.webAppImmersiveMode) {
      state.detent = 'peek';
      state.clearWebAddressDraft = true;
    }
    if (input.fullScreenModeEnabled && input.nextDetent !== 'peek') {
      state.detent = 'peek';
      state.hideStatusBarForFullScreenMode = true;
    }
    return state;
  }

  buildExpandedScrimState(
    input: BrowserRootBottomPanelExpandedScrimInput
  ): BrowserRootBottomPanelExpandedScrimState {
    const surfaceVisible = input.homePageVisible || input.tabsSheetVisible || input.webPageVisible;
    const surfaceEligible = !input.readerModeVisible && !input.novelReaderVisible && surfaceVisible &&
      !input.tabsSheetVisible &&
      input.bottomPanelHostVisible;
    const visible = surfaceEligible && input.detent === 'middle';
    const progressVisible = input.backdropProgress > 0.01;
    return {
      visible,
      mounted: surfaceEligible && (visible || progressVisible),
      surfaceEligible: surfaceEligible,
      blockHitTest: surfaceEligible && (visible || progressVisible),
      backdropProgress: input.backdropProgress
    };
  }

  getSearchBackdropPresentationChannel(): BrowserSearchBackdropPresentationChannel {
    return this.searchBackdropPresentationChannel;
  }

  resolveSearchBackdropProgress(tabsSheetVisible: boolean, bottomPanelHostVisible: boolean = true): number {
    return this.searchBackdropPresentationViewModel.resolveEffectiveProgress(
      this.searchBackdropProgress,
      tabsSheetVisible,
      bottomPanelHostVisible
    );
  }

  handleGestureFrame(
    input: BrowserRootBottomPanelGestureInput,
    frame: BrowserRootBottomPanelGestureFrame
  ): BrowserRootBottomPanelGestureState {
    if (frame.phase === 'start') {
      this.publishSearchBackdropProgress(this.searchBackdropPresentationViewModel.beginPanelDrag(
        frame.panelHeight,
        frame.middlePanelHeight,
        frame.lowPanelHeight,
        frame.expansionEnabled
      ));
      this.searchBackdropPresentationViewModel.beginGesture(input.currentDetent, this.searchBackdropProgress);
      const gestureState = this.beginGesture(input);
      this.performGestureThresholdFeedbackIfRequested(gestureState);
      return gestureState;
    }
    const gestureState = this.updateGesture(input);
    this.performGestureThresholdFeedbackIfRequested(gestureState);
    this.publishSearchBackdropProgress(this.searchBackdropPresentationViewModel.updateGesture(
      gestureState.suppressSearchBackdrop,
      input.offsetY,
      frame.expansionEnabled
    ));
    return gestureState;
  }

  updateSearchBackdropVisualHeight(
    panelHeight: number,
    expandedHeight: number,
    lowHeight: number,
    expansionEnabled: boolean
  ): void {
    this.publishSearchBackdropProgress(this.searchBackdropPresentationViewModel.updatePanelVisualHeight(
      panelHeight,
      expandedHeight,
      lowHeight,
      expansionEnabled
    ));
  }

  clearSearchBackdropExpandedHeight(): void {
    this.searchBackdropPresentationViewModel.clearExpandedHeight();
  }

  resetSearchBackdropPresentation(): void {
    this.publishSearchBackdropProgress(this.searchBackdropPresentationViewModel.resetInteraction());
  }

  resetForRouteTransitionPresentation(
    preservedOwners: BrowserRootBottomPanelTransientSheetOwner[] = []
  ): void {
    this.cancelSearchPresentationHostPreparation();
    this.activeSearchBackdropSettleRunId = 0;
    this.searchBackdropProgress = this.searchBackdropPresentationViewModel.resetInteraction();
    this.searchBackdropPresentationChannel.publishRouteTransitionSuppression();
    this.resetTransientSheetPresentation(preservedOwners);
    if (this.programmaticHomeToolbarHostActive) {
      this.endProgrammaticHomeToolbarHostSession();
      const plan = this.buildEmptyChromePlan();
      plan.targetDetent = 'low';
      plan.detentApplication = 'assign';
      this.sink.applyChromePlan(plan);
    }
  }

  restoreSearchBackdropPresentation(detent: HomeSearchPanelDetent): void {
    this.activeSearchBackdropSettleRunId = 0;
    this.searchBackdropProgress = this.searchBackdropPresentationViewModel.resolveDetentProgress(detent);
    this.searchBackdropPresentationChannel.publish(this.searchBackdropProgress, 0, Curve.Linear);
  }

  endGestureWithSearchBackdrop(targetDetent: HomeSearchPanelDetent): void {
    this.endGesture();
    this.settleSearchBackdropToDetent(targetDetent);
  }

  settleSearchBackdropToDetent(
    detent: HomeSearchPanelDetent,
    curve: Curve | string | ICurve = Curve.Linear
  ): void {
    const targetProgress = this.searchBackdropPresentationViewModel.resolveDetentProgress(detent);
    if (this.activeSearchBackdropSettleRunId > 0 &&
      Math.abs(this.searchBackdropProgress - targetProgress) <= 0.001) {
      return;
    }
    this.publishSearchBackdropTransition(
      this.searchBackdropPresentationViewModel.prepareDetentSettle(detent, this.searchBackdropProgress),
      curve
    );
  }

  settleSearchBackdropToProgress(
    targetProgress: number,
    maxDurationMs?: number,
    curve: Curve | string | ICurve = Curve.Linear
  ): void {
    this.publishSearchBackdropTransition(
      this.searchBackdropPresentationViewModel.prepareProgressSettle(
        this.searchBackdropProgress,
        targetProgress,
        maxDurationMs
      ),
      curve
    );
  }

  settleSearchBackdropForCommittedDetent(detent: HomeSearchPanelDetent): void {
    if (this.shouldAnimateBackdropDetentProgress(detent)) {
      this.settleSearchBackdropToProgress(
        this.searchBackdropPresentationViewModel.resolveDetentProgress(detent),
        BROWSER_BOTTOM_PANEL_MIDDLE_SNAP_DURATION_MS,
        resolveBrowserBottomPanelMiddleSnapCurve()
      );
      return;
    }
    this.settleSearchBackdropToDetent(detent);
  }

  beginSearchBackdropFocusTransition(
    surface: BrowserBottomPanelBackdropSurface,
    detent: HomeSearchPanelDetent
  ): boolean {
    if (!this.beginBackdropFocusTransition(surface)) {
      return false;
    }
    this.publishSearchBackdropProgress(
      this.searchBackdropPresentationViewModel.beginFocusTransition(detent, this.searchBackdropProgress)
    );
    return true;
  }

  shouldUseDirectSearchBackdropToneEffect(surfaceEligible: boolean, effectiveProgress: number): boolean {
    return this.searchBackdropPresentationViewModel.shouldUseDirectToneEffect({
      surfaceEligible: surfaceEligible,
      progress: effectiveProgress
    });
  }

  private publishSearchBackdropProgress(progress: number | undefined): void {
    if (progress === undefined) {
      return;
    }
    const nextProgress = Math.max(0, Math.min(1, progress));
    if (this.activeSearchBackdropSettleRunId <= 0 &&
      Math.abs(this.searchBackdropProgress - nextProgress) <= 0.001) {
      return;
    }
    this.activeSearchBackdropSettleRunId = 0;
    this.searchBackdropProgress = nextProgress;
    this.searchBackdropPresentationChannel.publish(this.searchBackdropProgress, 0, Curve.Linear);
  }

  private publishSearchBackdropTransition(
    plan: BrowserSearchBackdropSettlePlan,
    curve: Curve | string | ICurve
  ): void {
    this.activeSearchBackdropSettleRunId = plan.durationMs > 0 ? plan.runId : 0;
    this.searchBackdropProgress = Math.max(0, Math.min(1, plan.targetProgress));
    this.searchBackdropPresentationChannel.publish(
      this.searchBackdropProgress,
      plan.durationMs,
      curve,
      plan.runId
    );
  }

  private finishSearchBackdropSettle(settleRunId: number): void {
    if (!this.searchBackdropPresentationViewModel.finishSettle(settleRunId) ||
      this.activeSearchBackdropSettleRunId !== settleRunId) {
      return;
    }
    this.activeSearchBackdropSettleRunId = 0;
    this.completePanelSettleAfterEffects();
  }

  buildHostState(input: BrowserBottomPanelHostInput): BrowserBottomPanelHostState {
    this.syncProgrammaticHomeToolbarPresentation(input);
    const mode = this.resolveHostMode(input);
    return {
      mode,
      scene: input.scene,
      hostHeight: this.resolveHostHeight(mode, input),
      zIndex: BROWSER_BOTTOM_PANEL_HOST_Z_INDEX,
      interactiveOutsidePanel: false,
      tabsOverviewHomeEntryEligible: mode === 'browser' && input.scene === 'home'
    };
  }

  beginGesture(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureState {
    this.activeGestureOwner = this.resolveInitialGestureOwner(input);
    return this.commitGestureState(this.buildGestureState(input));
  }

  updateGesture(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureState {
    return this.commitGestureState(this.buildGestureState(input));
  }

  resolveGestureReleaseIntent(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureIntent {
    const presentation = this.resolveGesturePresentation(input);
    return presentation.armed ? presentation.intent : 'none';
  }

  resolveGestureReleasePlan(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureReleasePlan {
    const intent = this.resolveGestureReleaseIntent(input);
    if (intent === 'return_home') {
      return {
        interceptPanelReleaseTarget: 'low',
        settleBackdropToLow: true,
        shouldReturnHome: false,
        toolbarActionSlotId: this.resolveOuterGestureSlotId(input.source)
      };
    }
    if (this.bottomChromePresentationViewModel.isOuterGestureSource(input.source)) {
      return {
        interceptPanelReleaseTarget: 'low',
        settleBackdropToLow: true,
        shouldReturnHome: false
      };
    }
    return {
      settleBackdropToLow: false,
      shouldReturnHome: false
    };
  }

  commitGestureRelease(
    input: BrowserRootBottomPanelGestureInput,
    effects: BrowserRootBottomPanelGestureReleaseEffects,
    snapshot?: BrowserRootBottomPanelSessionSnapshot
  ): HomeSearchPanelDetent | undefined {
    const plan = this.resolveGestureReleasePlan(input);
    let interceptPanelReleaseTarget = plan.interceptPanelReleaseTarget;
    let settleBackdropToLow = plan.settleBackdropToLow;
    if (plan.toolbarActionSlotId !== undefined && snapshot !== undefined) {
      const swipeAction = this.resolveOuterSwipeAction(input.source);
      const transition = this.handleToolbarInteraction(
        plan.toolbarActionSlotId,
        'swipeUp',
        snapshot,
        false
      );
      if (transition.rejectionMessage !== undefined) {
        // The Session already emitted the rejection through its shell-effect channel.
      } else if (swipeAction?.id === 'bottomChromeMenu') {
        interceptPanelReleaseTarget = 'middle';
        settleBackdropToLow = false;
      }
    }
    if (settleBackdropToLow) {
      effects.settleBackdropToLow();
    }
    if (plan.shouldReturnHome) {
      effects.returnHome();
    }
    return interceptPanelReleaseTarget;
  }

  endGesture(): void {
    this.activeGestureOwner = 'none';
    this.commitPresentationSnapshot({
      gesturePrompt: {
        intent: 'none',
        text: '',
        armed: false,
        progress: 0
      },
      returnHomeGestureActive: false,
      scrollPresentation: this.presentationSnapshot.scrollPresentation,
      transientMessage: this.presentationSnapshot.transientMessage
    });
  }

  applyHomeScrollDecision(decision: BrowserBottomChromeHomeScrollDecision): void {
    this.applyScrollDecision(decision);
  }

  applyWebScrollDecision(decision: BrowserBottomChromeWebScrollDecision): void {
    this.applyScrollDecision(decision);
  }

  restoreScrollPresentation(): void {
    this.setScrollPresentation('resting');
  }

  showTransientMessage(
    message: string,
    context: BrowserBottomAddressTransientMessageContext,
    nowMs: number = Date.now()
  ): void {
    const state = this.transientMessageViewModel.applyMessage(
      this.presentationSnapshot.transientMessage,
      message,
      context,
      nowMs
    );
    this.commitPresentationSnapshot({
      gesturePrompt: this.presentationSnapshot.gesturePrompt,
      returnHomeGestureActive: this.presentationSnapshot.returnHomeGestureActive,
      scrollPresentation: 'resting',
      transientMessage: state
    });
    this.scheduleTransientMessageClear(state, context, nowMs);
  }

  clearTransientMessage(): void {
    this.clearTransientMessageTimer();
    const state = this.transientMessageViewModel.clear(this.presentationSnapshot.transientMessage);
    if (state === this.presentationSnapshot.transientMessage) {
      return;
    }
    this.commitPresentationSnapshot({
      gesturePrompt: this.presentationSnapshot.gesturePrompt,
      returnHomeGestureActive: this.presentationSnapshot.returnHomeGestureActive,
      scrollPresentation: this.presentationSnapshot.scrollPresentation,
      transientMessage: state
    });
  }

  resolveAddressFocused(input: BrowserBottomAddressPresentationInput): boolean {
    return this.transientMessageViewModel.resolveAddressFocused(input);
  }

  resolveAddressInput(input: BrowserBottomAddressPresentationInput): string {
    return this.transientMessageViewModel.resolveAddressInput(input);
  }

  resolveAddressDisplayText(input: BrowserBottomAddressPresentationInput): string {
    return this.transientMessageViewModel.resolveAddressDisplayText(input);
  }

  resolveSuggestionQuery(input: BrowserBottomAddressSuggestionInput): string {
    return this.transientMessageViewModel.resolveSuggestionQuery(input);
  }

  beginBackdropFocusTransition(surface: BrowserBottomPanelBackdropSurface): boolean {
    if (this.pendingBackdropFocusSurface === surface) {
      return false;
    }
    this.pendingBackdropFocusSurface = surface;
    return true;
  }

  cancelBackdropFocusTransition(): void {
    this.pendingBackdropFocusSurface = undefined;
  }

  shouldAnimateBackdropDetentProgress(detent: HomeSearchPanelDetent): boolean {
    return detent === 'middle' && this.pendingBackdropFocusSurface !== undefined;
  }

  completeBackdropFocusTransition(detent: HomeSearchPanelDetent): void {
    if (detent === 'middle') {
      this.pendingBackdropFocusSurface = undefined;
    }
  }

  buildLayoutState(input: BrowserRootBottomPanelLayoutInput): BrowserRootBottomPanelLayoutState {
    return this.layoutModel.buildState(input);
  }

  buildSemanticState(input: BrowserRootBottomPanelSemanticInput): BrowserRootBottomPanelSemanticState {
    return this.buildSemanticStateForScene(this.resolveScene(input), input);
  }

  buildSemanticStateForScene(
    scene: BrowserRootBottomPanelScene,
    input: BrowserRootBottomPanelSemanticInput
  ): BrowserRootBottomPanelSemanticState {
    const effectiveHome = scene === 'home';
    const effectiveWeb = scene === 'web';
    const addressFocused = effectiveHome ? input.homeAddressFocused : (effectiveWeb ? input.webAddressFocused : false);
    return {
      scene,
      headerPresentation: effectiveHome ? 'home' : 'address',
      contentPresentation: effectiveHome ? 'home' : 'web',
      effectiveHome,
      effectiveWeb,
      addressFocused
    };
  }

  buildSemanticProjection(
    semanticState: BrowserRootBottomPanelSemanticState
  ): BrowserRootBottomPanelSemanticProjection {
    return this.resolveActionApplication().buildSemanticProjection(semanticState);
  }

  buildBottomChromePresentation(
    input: BrowserRootBottomChromePresentationInput
  ): BrowserBottomChromePresentation {
    const semanticProjection = this.buildSemanticProjection(input.semanticState);
    const toolbarSlotActions = this.resolveActionApplication().resolveToolbarSlotActions();
    const presentationFacts: BrowserBottomChromePresentationFacts = {
      scene: semanticProjection.scene,
      addressFocused: semanticProjection.addressFocused,
      addressEditable: input.addressEditable,
      currentDetent: input.currentDetent,
      scrollPresentation: this.presentationSnapshot.scrollPresentation,
      returnHomeDrag: this.presentationSnapshot.returnHomeGestureActive,
      returnHomeProgress: this.presentationSnapshot.gesturePrompt.intent === 'return_home' ?
        this.presentationSnapshot.gesturePrompt.progress : 0,
      panelWidth: input.responsiveState.panelWidth,
      expandedChromeWidth: input.responsiveState.expandedChromeWidth,
      floatingHeaderHorizontalPadding: input.responsiveState.floatingHeaderHorizontalPadding,
      restingChromeOuterSize: input.responsiveState.restingChromeOuterSize,
      restingChromeOuterGap: input.responsiveState.restingChromeOuterGap,
      panelExpansionEnabled: input.panelExpansionEnabled,
      addressInput: this.resolveAddressInput(input.addressPresentation),
      addressDisplayText: this.resolveAddressDisplayText(input.addressPresentation),
      placeholder: input.searchEnginePresentation.placeholder,
      searchEnginePresentation: input.searchEnginePresentation,
      toolbarSlotActions,
      toolbarActionEnablement: this.buildToolbarActionEnablement(toolbarSlotActions, input.semanticState),
      toolbarInteractionProfileActive: true,
      gesturePromptText: this.presentationSnapshot.gesturePrompt.text,
      webProtectionFeedback: input.webProtectionFeedback,
      leadingHeaderActions: semanticProjection.leadingHeaderActions,
      trailingHeaderActions: semanticProjection.trailingHeaderActions
    };
    return this.bottomChromePresentationViewModel.buildPresentation(presentationFacts);
  }

  buildLivePresentation(
    input: BrowserRootBottomPanelLivePresentationInput
  ): BrowserBottomPanelLivePresentation {
    return new BrowserBottomPanelLivePresentation(
      input.panelMotionState,
      this.buildBottomChromePresentation(input),
      this.resolveActionSnapshot(
        input.semanticState,
        input.responsiveState,
        input.responsiveLayoutKey
      ),
      this.buildReadingContinuationPresentation(input.readingSnapshot, input.semanticState),
      input.semanticState.addressFocused,
      !this.programmaticHomeToolbarRestingChromeHidden && !this.searchPresentationHostPreparationActive
    );
  }

  prepareHomeSearchPresentationHost(): Promise<BrowserRootBottomPanelSearchHostPreparationResult> {
    this.cancelSearchPresentationHostPreparation();
    this.searchPresentationHostPreparationGeneration += 1;
    const generation = this.searchPresentationHostPreparationGeneration;
    if (this.searchPresentationHostReady) {
      return Promise.resolve(new BrowserRootBottomPanelSearchHostPreparationResult('ready', generation));
    }

    this.searchPresentationHostPreparationActive = true;
    const deferred = new BrowserRootBottomPanelSearchHostPreparationDeferred();
    const pending: BrowserRootBottomPanelPendingSearchHostPreparation = {
      generation: generation,
      deferred: deferred,
      timer: -1
    };
    this.pendingSearchPresentationHostPreparation = pending;

    pending.timer = setTimeout((): void => {
      if (this.pendingSearchPresentationHostPreparation?.generation !== generation) {
        return;
      }
      this.pendingSearchPresentationHostPreparation = undefined;
      this.searchPresentationHostPreparationActive = false;
      deferred.resolve(new BrowserRootBottomPanelSearchHostPreparationResult('timed_out', generation));
      this.invalidatePresentation();
    }, BROWSER_ROOT_BOTTOM_PANEL_SEARCH_HOST_PREPARATION_TIMEOUT_MS);

    const preparationPlan = this.buildEmptyChromePlan();
    preparationPlan.targetDetent = 'low';
    preparationPlan.detentApplication = 'assign';
    preparationPlan.shouldRestoreScrollPresentation = true;
    this.sink.applyChromePlan(preparationPlan);
    return deferred.promise;
  }

  reportSearchPresentationHostReady(measuredPanelHeight: number): void {
    if (!Number.isFinite(measuredPanelHeight) || measuredPanelHeight <= 0) {
      return;
    }
    this.searchPresentationHostReady = true;
    const pending = this.pendingSearchPresentationHostPreparation;
    if (pending === undefined) {
      return;
    }
    this.clearSearchPresentationHostPreparationTimer(pending);
    this.pendingSearchPresentationHostPreparation = undefined;
    pending.deferred.resolve(new BrowserRootBottomPanelSearchHostPreparationResult(
      'ready',
      pending.generation
    ));
  }

  reportSearchPresentationHostDisconnected(): void {
    this.searchPresentationHostReady = false;
    this.cancelSearchPresentationHostPreparation();
  }

  commitPreparedHomeSearchPresentation(
    preparation: BrowserRootBottomPanelSearchHostPreparationResult,
    plan: BrowserRootBottomPanelChromePlan
  ): boolean {
    if (preparation.status !== 'ready' ||
      preparation.generation !== this.searchPresentationHostPreparationGeneration ||
      !this.searchPresentationHostReady) {
      return false;
    }
    this.sink.applyChromePlan(plan);
    this.searchPresentationHostPreparationActive = false;
    this.invalidatePresentation();
    return true;
  }

  cancelSearchPresentationHostPreparation(): void {
    const pending = this.pendingSearchPresentationHostPreparation;
    const wasActive = this.searchPresentationHostPreparationActive;
    this.searchPresentationHostPreparationGeneration += 1;
    this.searchPresentationHostPreparationActive = false;
    if (pending !== undefined) {
      this.clearSearchPresentationHostPreparationTimer(pending);
      this.pendingSearchPresentationHostPreparation = undefined;
      pending.deferred.resolve(new BrowserRootBottomPanelSearchHostPreparationResult(
        'cancelled',
        pending.generation
      ));
    }
    if (wasActive) {
      this.invalidatePresentation();
    }
  }

  buildReadingContinuationPresentation(
    snapshot: NovelReaderSnapshot,
    semanticState: BrowserRootBottomPanelSemanticState
  ): BrowserBottomPanelReadingContinuationPresentation {
    const title = snapshot.bookTitle.trim();
    if (snapshot.phase !== 'suspended' || snapshot.visible || title.length === 0 ||
      (!semanticState.effectiveHome && !semanticState.effectiveWeb)) {
      return HIDDEN_BROWSER_BOTTOM_PANEL_READING_CONTINUATION;
    }
    return {
      visible: true,
      title: title,
      loading: snapshot.openingTransition.status === 'loading'
    };
  }

  resolveActionSnapshot(
    semanticState: BrowserRootBottomPanelSemanticState,
    responsiveState: BrowserBottomPanelResponsiveState,
    responsiveLayoutKey: string
  ): BrowserBottomPanelActionSnapshot {
    return this.resolveActionApplication().resolveActionSnapshot(
      semanticState,
      responsiveState,
      responsiveLayoutKey
    );
  }

  resolveActionTarget(input: BrowserBottomPanelActionTargetInput): BrowserBottomPanelActionTarget {
    return this.resolveActionApplication().resolveActionTarget(input);
  }

  resolveWebpageTranslationPromptAvailability(): boolean {
    return this.resolveActionApplication().resolveWebpageTranslationPromptAvailability();
  }

  resolveBookmarkActionAvailability(): boolean {
    return this.resolveActionApplication().resolveBookmarkActionAvailability();
  }

  resolveThemeModeActionTitleForMode(mode: BrowserThemeMode): string {
    return this.resolveActionApplication().resolveThemeModeActionTitleForMode(mode);
  }

  shouldMountHost(input: BrowserRootBottomPanelHostMountInput): boolean {
    const blockedByTabsOverview = input.showTabsSheet && !input.retainForTabsOverviewEntry;
    return !blockedByTabsOverview &&
      !input.readerModeVisible &&
      !input.novelReaderVisible &&
      !input.webAppImmersiveMode &&
      !input.webVideoControllerFullscreenActive &&
      !input.largeScreenShellActive;
  }

  isKeyboardInsetSyncActive(snapshot: BrowserRootAddressInputSessionSnapshot): boolean {
    return this.addressInputSessionCoordinator.isKeyboardInsetSyncActive(snapshot);
  }

  buildKeyboardHideProtectionUntil(nowMs: number): number {
    return this.addressInputSessionCoordinator.buildKeyboardHideProtectionUntil(nowMs);
  }

  shouldConfirmKeyboardHidden(snapshot: BrowserRootAddressInputSessionSnapshot): boolean {
    return this.addressInputSessionCoordinator.shouldConfirmKeyboardHidden(snapshot);
  }

  buildAddressSessionEndPlan(
    snapshot: BrowserRootAddressInputSessionSnapshot
  ): BrowserRootBottomPanelChromePlan {
    const inputPlan = this.addressInputSessionCoordinator.buildEndPlan(snapshot);
    if (snapshot.isHomeMode && this.programmaticHomeToolbarHostActive) {
      inputPlan.shouldCollapsePanel = true;
      this.endProgrammaticHomeToolbarHostSession(true);
    }
    return this.buildAddressInputChromePlan(inputPlan);
  }

  buildAddressSubmitPlan(
    rawInput: string,
    snapshot: BrowserRootAddressInputSessionSnapshot
  ): BrowserRootBottomPanelAddressSubmitPlan {
    const inputPlan = this.addressInputSessionCoordinator.buildSubmitPlan(rawInput, snapshot);
    const chromePlan = this.buildAddressInputChromePlan(inputPlan);
    chromePlan.shouldRestoreScrollPresentation = inputPlan.shouldRestoreScrollPresentation;
    return {
      rawInput: inputPlan.rawInput,
      chromePlan: chromePlan
    };
  }

  buildHomeAddressFocusOpenPlan(): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = 'middle';
    plan.detentApplication = 'apply';
    plan.shouldResetSearchOverlay = true;
    // Publish the Home input presentation with the detent plan so cold-start Search does not animate in stack mode first.
    plan.shouldFocusHomeSearchInput = true;
    plan.shouldClearHomeAddressInput = true;
    plan.shouldClearWebAddressFocus = true;
    plan.shouldClearWebAddressDraft = true;
    plan.shouldRestoreScrollPresentation = true;
    plan.shouldRequestKeyboardInsetSync = true;
    plan.shouldCancelBackdropFocusTransition = true;
    return plan;
  }

  buildSearchPresentationPlan(scene: BrowserRootBottomPanelContentPresentation): BrowserRootBottomPanelChromePlan {
    return scene === 'home'
      ? this.buildHomeAddressFocusOpenPlan()
      : this.buildWebAddressFocusOpenPlan();
  }

  buildWebAddressFocusOpenPlan(): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = 'middle';
    plan.detentApplication = 'apply';
    plan.shouldFocusWebAddressInput = true;
    plan.shouldRestoreScrollPresentation = true;
    plan.shouldRequestKeyboardInsetSync = true;
    plan.webStatusBarRestoreReason = 'shortcut-address-focus';
    return plan;
  }

  buildAddressFocusStateChangePlan(
    input: BrowserRootBottomPanelAddressFocusStateChangeInput
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    if (input.focused) {
      if (input.isHomeMode) {
        plan.shouldEnsureHomeAddressFocusBackdrop = true;
        return plan;
      }
      if (input.isWebMode) {
        plan.shouldFocusWebAddressInput = true;
        plan.shouldEnsureWebAddressFocusBackdrop = true;
        plan.webStatusBarRestoreReason = 'address-focus';
      }
      return plan;
    }
    if (input.isHomeMode) {
      if (this.homeDismissAfterLowSettlePending) {
        return plan;
      }
      plan.shouldCancelBackdropFocusTransition = true;
      plan.shouldReleaseHomeSearchFocus = true;
      plan.shouldClearHomeSearchFocus = true;
      return plan;
    }
    if (input.isWebMode) {
      plan.shouldCancelBackdropFocusTransition = true;
      plan.shouldClearWebAddressFocus = true;
    }
    return plan;
  }

  buildHomeSearchExitPlan(): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.shouldClearHomeSearchFocus = true;
    return plan;
  }

  shouldMountHomeSearchDismissLayer(input: HomeSearchDismissInput): boolean {
    return this.homeSearchOverlayViewModel.shouldMountDismissLayer(input);
  }

  buildHomeSearchReleasePlan(input: HomeSearchReleaseInput): HomeSearchReleasePlan {
    return this.homeSearchOverlayViewModel.buildReleasePlan(input);
  }

  buildHomeSuggestionOpenPlan(
    snapshot: BrowserRootAddressInputSessionSnapshot
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = 'low';
    plan.detentApplication = 'apply';
    plan.immediateLowDetent = true;
    plan.shouldResetSearchOverlay = true;
    plan.shouldClearHomeSearchFocus = snapshot.homeSearchFocused;
    plan.shouldClearHomeAddressInput = snapshot.isHomeMode;
    plan.shouldClearWebAddressFocus = snapshot.webBottomAddressFocused;
    plan.shouldClearWebAddressDraft = snapshot.webBottomAddressDraft.trim().length > 0;
    plan.shouldReleaseKeyboardAvoidMode = true;
    plan.shouldHideTextInput = true;
    plan.shouldCancelBackdropFocusTransition = true;
    return plan;
  }

  buildExpandedScrimDismissPlan(
    input: BrowserRootBottomPanelExpandedScrimDismissInput
  ): BrowserRootBottomPanelChromePlan {
    const dismissPlan = this.homeSearchOverlayViewModel.buildDismissPlan({
      showHomePage: input.showHomePage,
      homeSearchFocused: input.homeSearchFocused,
      homeSearchOverlayVisible: input.homeSearchOverlayVisible,
      expandedScrimVisible: input.expandedScrimVisible
    });
    if (dismissPlan.shouldDismissHomeSearch) {
      const plan = this.buildEmptyChromePlan();
      plan.shouldReleaseHomeSearchFocus = true;
      plan.shouldClearHomeAddressInput = true;
      return plan;
    }
    if (!dismissPlan.shouldCollapseBottomPanel) {
      return this.buildEmptyChromePlan();
    }
    const plan = this.buildCollapseToLowPlan(input, false);
    plan.deferLowDetentUntilSettle = this.shouldDeferLowDetentUntilSettle(input.currentDetent);
    plan.homeDismissAfterLowSettle = plan.deferLowDetentUntilSettle && input.isHomeMode;
    plan.shouldCollapseSearchBackdropProgress = plan.homeDismissAfterLowSettle;
    if (input.isHomeMode) {
      plan.shouldResetSearchOverlay = false;
      plan.shouldClearHomeSearchFocus = false;
      plan.shouldClearHomeAddressInput = false;
      if (!plan.deferLowDetentUntilSettle) {
        plan.shouldReleaseHomeSearchBeforeBackdropEffects = true;
      }
    }
    return plan;
  }

  handleActionTap(
    source: BrowserRootBottomPanelActionSource,
    actionId: string,
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelActionTapTransition {
    const isHeaderAction = source === 'header';
    if (isHeaderAction && actionId === 'bottomChromeMenu') {
      this.clearPendingActionSettleFallback();
      this.pendingActionAfterCollapsedSettle = undefined;
      this.sink.applyChromePlan(this.buildBottomChromeMenuPlan(snapshot));
      return {};
    }
    if (isHeaderAction && actionId === 'bottomChromeRestore') {
      this.clearPendingActionSettleFallback();
      this.pendingActionAfterCollapsedSettle = undefined;
      this.restoreScrollPresentation();
      return {};
    }
    const isHomeAction = !isHeaderAction && snapshot.isHomeMode;
    if (isHomeAction) {
      const availability = this.homeActionAvailabilityCoordinator.resolve(actionId as BrowserBottomPanelActionId);
      if (!availability.available) {
        this.presentActionRejection(availability.message);
        return {
          rejectionMessage: availability.message
        };
      }
    }
    const plan = this.buildPanelActionTapPlan(actionId, snapshot);
    const dispatch: BrowserRootBottomPanelActionDispatch = isHeaderAction ?
      { lane: 'header', actionId } :
      { lane: isHomeAction ? 'home' : 'web', actionId: actionId as BrowserBottomPanelActionId };
    if (plan.dispatchTiming === 'after_low_settle') {
      this.pendingActionAfterCollapsedSettle = dispatch;
      this.schedulePendingActionSettleFallback();
      this.settleSearchBackdropToDetent('low');
      this.sink.applyChromePlan(plan.chromePlan);
      return {};
    }
    this.clearPendingActionSettleFallback();
    this.pendingActionAfterCollapsedSettle = undefined;
    this.sink.applyChromePlan(plan.chromePlan);
    this.executeActionDispatch(dispatch);
    return {};
  }

  handleToolbarLongPress(
    slotId: BrowserToolbarSlotId,
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelActionTapTransition {
    return this.handleToolbarInteraction(slotId, 'longPress', snapshot, true);
  }

  handleToolbarInteraction(
    slotId: BrowserToolbarSlotId,
    kind: BrowserToolbarInteractionKind,
    snapshot: BrowserRootBottomPanelSessionSnapshot,
    hapticOnRecognition: boolean
  ): BrowserRootBottomPanelActionTapTransition {
    const slot = this.resolveActionApplication().resolveToolbarSlotActions()
      .find((item: BrowserToolbarSlotActionState): boolean => item.id === slotId);
    const interaction = kind === 'tap' ? slot?.tap : (kind === 'longPress' ? slot?.longPress : slot?.swipeUp);
    if (interaction === undefined || interaction.action.isNone) {
      return {};
    }
    if (hapticOnRecognition) {
      this.performGestureFeedback();
    }
    const coreRejection = this.resolveCoreToolbarActionRejection(interaction.action, snapshot);
    if (coreRejection.length > 0) {
      this.presentActionRejection(coreRejection);
      return { rejectionMessage: coreRejection };
    }
    const panelRejection = this.resolvePanelToolbarActionRejection(interaction.action, snapshot);
    if (panelRejection.length > 0) {
      this.presentActionRejection(panelRejection);
      return { rejectionMessage: panelRejection };
    }
    const source: BrowserRootBottomPanelActionSource = interaction.action.dispatchKind === 'header' ?
      'header' : 'panel';
    return this.handleActionTap(source, interaction.action.id, snapshot);
  }

  private executeActionDispatch(dispatch: BrowserRootBottomPanelActionDispatch): void {
    const completionPlan = this.buildEmptyChromePlan();
    completionPlan.shouldEndSearchInvocationForAction = true;
    this.sink.applyChromePlan(completionPlan);
    const shellAction = this.resolveActionApplication().apply(dispatch, this.sink.isHomePageVisible());
    if (shellAction !== undefined) {
      this.sink.applyShellEffect({
        kind: 'action',
        action: shellAction
      });
    }
  }

  private presentActionRejection(message: string): void {
    this.sink.applyShellEffect({
      kind: 'action_rejection',
      message: message
    });
  }

  handlePanelSettled(detent: HomeSearchPanelDetent): BrowserRootBottomPanelSettledTransition {
    let shouldCommitRequestedDetent = false;
    let shouldDismissHomeSearch = false;
    if (this.isCollapsedDetent(detent)) {
      this.endProgrammaticHomeToolbarHostSession(true);
    }
    if (this.requestedDetentOverride === detent) {
      this.requestedDetentOverride = undefined;
      shouldCommitRequestedDetent = true;
      if (detent === 'low' && this.homeDismissAfterLowSettlePending) {
        this.homeDismissAfterLowSettlePending = false;
        shouldDismissHomeSearch = true;
      }
    }
    if (this.isCollapsedDetent(detent) && this.pendingActionAfterCollapsedSettle !== undefined) {
      this.pendingActionAfterSettleEffects = this.pendingActionAfterCollapsedSettle;
      this.pendingActionAfterCollapsedSettle = undefined;
    }
    return {
      shouldCommitRequestedDetent,
      shouldDismissHomeSearch
    };
  }

  completePanelSettleAfterEffects(): void {
    if (this.pendingActionAfterSettleEffects === undefined || this.activeSearchBackdropSettleRunId > 0) {
      return;
    }
    this.clearPendingActionSettleFallback();
    const dispatch = this.pendingActionAfterSettleEffects;
    this.pendingActionAfterSettleEffects = undefined;
    this.executeActionDispatch(dispatch);
  }

  private schedulePendingActionSettleFallback(): void {
    this.clearPendingActionSettleFallback();
    this.pendingActionSettleFallbackTimer = setTimeout(() => {
      this.pendingActionSettleFallbackTimer = -1;
      if (this.pendingActionAfterCollapsedSettle !== undefined) {
        this.pendingActionAfterSettleEffects = this.pendingActionAfterCollapsedSettle;
        this.pendingActionAfterCollapsedSettle = undefined;
      }
      if (this.pendingActionAfterSettleEffects === undefined) {
        return;
      }
      this.activeSearchBackdropSettleRunId = 0;
      this.completePanelSettleAfterEffects();
    }, BROWSER_ROOT_BOTTOM_PANEL_ACTION_SETTLE_FALLBACK_MS);
  }

  private clearPendingActionSettleFallback(): void {
    if (this.pendingActionSettleFallbackTimer < 0) {
      return;
    }
    clearTimeout(this.pendingActionSettleFallbackTimer);
    this.pendingActionSettleFallbackTimer = -1;
  }

  resolveRequestedDetent(defaultDetent: HomeSearchPanelDetent): HomeSearchPanelDetent {
    return this.requestedDetentOverride ?? defaultDetent;
  }

  noteDetentApplication(detent: HomeSearchPanelDetent): void {
    if (detent !== this.requestedDetentOverride) {
      this.requestedDetentOverride = undefined;
    }
  }

  prepareDetentExecution(plan: BrowserRootBottomPanelChromePlan): BrowserRootBottomPanelChromePlan {
    if (plan.deferLowDetentUntilSettle && plan.targetDetent === 'low') {
      this.homeDismissAfterLowSettlePending = plan.homeDismissAfterLowSettle;
      this.requestedDetentOverride = 'low';
      plan.detentApplication = 'none';
      plan.immediateLowDetent = false;
    }
    return plan;
  }

  buildProgrammaticCollapsePlan(
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = 'low';
    plan.detentApplication = 'apply';
    plan.shouldCancelBackdropFocusTransition = true;
    if (snapshot.isHomeMode) {
      plan.deferLowDetentUntilSettle = this.shouldDeferLowDetentUntilSettle(snapshot.currentDetent);
      plan.homeDismissAfterLowSettle = plan.deferLowDetentUntilSettle;
      plan.shouldCollapseSearchBackdropProgress = plan.homeDismissAfterLowSettle;
      if (!plan.deferLowDetentUntilSettle) {
        plan.shouldReleaseHomeSearchFocus = true;
        plan.shouldClearHomeAddressInput = true;
      }
    } else {
      plan.shouldClearWebAddressFocus = true;
      plan.shouldClearWebAddressDraft = true;
    }
    return plan;
  }

  resetDeferredDetentTransition(): void {
    this.requestedDetentOverride = undefined;
    this.homeDismissAfterLowSettlePending = false;
  }

  private buildPanelActionTapPlan(
    actionId: string,
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelActionTapPlan {
    if (actionId === 'webBack' || actionId === 'webForward') {
      return {
        chromePlan: this.buildEmptyChromePlan(),
        dispatchTiming: 'immediate'
      };
    }
    if (actionId === 'fullScreenMode') {
      return {
        chromePlan: this.buildHideToPeekPlan(snapshot),
        dispatchTiming: 'immediate'
      };
    }
    const dispatchAfterLowSettle = this.isExpandedDetent(snapshot.currentDetent);
    return {
      chromePlan: this.buildCollapseToLowPlan(snapshot, !dispatchAfterLowSettle),
      dispatchTiming: dispatchAfterLowSettle ? 'after_low_settle' : 'immediate'
    };
  }

  private buildBottomChromeMenuPlan(
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = snapshot.currentDetent === 'middle' ? 'low' : 'middle';
    plan.detentApplication = 'apply';
    plan.shouldRestoreScrollPresentation = true;
    return plan;
  }

  buildPullRefreshRestorePlan(
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    if (!snapshot.isWebMode || snapshot.currentDetent !== 'peek') {
      return plan;
    }
    plan.targetDetent = 'low';
    plan.detentApplication = 'apply';
    plan.immediateLowDetent = true;
    plan.shouldRestoreScrollPresentation = true;
    return plan;
  }

  buildProgrammaticToolbarExpansionPlan(
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    if (!snapshot.panelExpansionEnabled || snapshot.currentDetent === 'middle') {
      return plan;
    }
    plan.targetDetent = 'middle';
    plan.detentApplication = 'apply';
    plan.shouldRestoreScrollPresentation = true;
    return plan;
  }

  requestProgrammaticToolbarExpansion(snapshot: BrowserRootBottomPanelSessionSnapshot): void {
    this.clearPendingActionSettleFallback();
    this.pendingActionAfterCollapsedSettle = undefined;
    const plan = this.buildProgrammaticToolbarExpansionPlan(snapshot);
    if (snapshot.isHomeMode && (plan.targetDetent === 'middle' || snapshot.currentDetent === 'middle')) {
      this.programmaticHomeToolbarHostActive = true;
    } else {
      this.endProgrammaticHomeToolbarHostSession();
    }
    this.sink.applyChromePlan(plan);
  }

  beginTransientSheetPresentation(
    owner: BrowserRootBottomPanelTransientSheetOwner,
    facts: BrowserRootBottomPanelTransientSheetFacts
  ): BrowserRootBottomPanelChromePlan {
    if (this.transientSheetOwners.indexOf(owner) >= 0) {
      return this.buildEmptyChromePlan();
    }
    this.transientSheetOwners.push(owner);
    if (!facts.isWebPageVisible || facts.showTabsSheet || facts.showHomePage) {
      this.clearTransientSheetReturnCapture();
      return this.buildEmptyChromePlan();
    }
    if (this.transientSheetOwners.length === 1 && facts.currentDetent !== 'peek') {
      this.transientSheetReturnDetent = facts.currentDetent;
      this.transientSheetReturnTabId = facts.activeTabId;
    }
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = 'peek';
    plan.detentApplication = 'assign';
    plan.shouldRestoreScrollPresentation = true;
    plan.shouldClearWebAddressFocus = true;
    plan.shouldClearWebAddressDraft = true;
    return plan;
  }

  endTransientSheetPresentation(
    owner: BrowserRootBottomPanelTransientSheetOwner,
    facts: BrowserRootBottomPanelTransientSheetFacts
  ): BrowserRootBottomPanelChromePlan {
    const ownerIndex = this.transientSheetOwners.indexOf(owner);
    if (ownerIndex < 0) {
      return this.buildEmptyChromePlan();
    }
    this.transientSheetOwners.splice(ownerIndex, 1);
    if (this.transientSheetOwners.length > 0) {
      return this.buildEmptyChromePlan();
    }
    const returnDetent = this.transientSheetReturnDetent;
    const returnTabId = this.transientSheetReturnTabId;
    this.clearTransientSheetReturnCapture();
    if (returnDetent === undefined ||
      returnTabId !== facts.activeTabId ||
      !facts.isWebPageVisible ||
      facts.showTabsSheet ||
      facts.showHomePage ||
      facts.webAddressFocused ||
      facts.currentDetent !== 'peek') {
      return this.buildEmptyChromePlan();
    }
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = returnDetent;
    plan.detentApplication = 'assign';
    plan.shouldRestoreScrollPresentation = true;
    plan.webStatusBarRestoreReason = 'transient-bottom-sheet-dismiss';
    return plan;
  }

  resetTransientSheetPresentation(
    preservedOwners: BrowserRootBottomPanelTransientSheetOwner[] = []
  ): void {
    if (preservedOwners.length <= 0) {
      this.transientSheetOwners = [];
      this.clearTransientSheetReturnCapture();
      return;
    }
    const remainingOwners: BrowserRootBottomPanelTransientSheetOwner[] = [];
    for (let index = 0; index < this.transientSheetOwners.length; index += 1) {
      const owner = this.transientSheetOwners[index];
      if (preservedOwners.indexOf(owner) >= 0) {
        remainingOwners.push(owner);
      }
    }
    this.transientSheetOwners = remainingOwners;
    if (remainingOwners.length <= 0) {
      this.clearTransientSheetReturnCapture();
    }
  }

  private buildGestureState(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureResolution {
    const owner = this.resolveGestureOwner(input);
    return {
      returnHomeActive: owner === 'return_home',
      suppressSearchBackdrop: owner === 'return_home' &&
        Number.isFinite(input.offsetY) &&
        input.offsetY < 0,
      presentation: this.resolveGesturePresentation(input)
    };
  }

  private commitGestureState(state: BrowserRootBottomPanelGestureResolution): BrowserRootBottomPanelGestureState {
    const previousPrompt = this.presentationSnapshot.gesturePrompt;
    const thresholdFeedbackRequested = state.presentation.armed &&
      (!previousPrompt.armed || previousPrompt.intent !== state.presentation.intent);
    let transientMessage = this.presentationSnapshot.transientMessage;
    if (state.presentation.intent !== 'none') {
      this.clearTransientMessageTimer();
      transientMessage = this.transientMessageViewModel.clear(transientMessage);
    }
    this.commitPresentationSnapshot({
      gesturePrompt: state.presentation,
      returnHomeGestureActive: state.returnHomeActive,
      scrollPresentation: this.presentationSnapshot.scrollPresentation,
      transientMessage: transientMessage
    });
    return {
      suppressSearchBackdrop: state.suppressSearchBackdrop,
      thresholdFeedbackRequested: thresholdFeedbackRequested
    };
  }

  private scheduleTransientMessageClear(
    state: BrowserBottomAddressTransientMessageState,
    context: BrowserBottomAddressTransientMessageContext,
    nowMs: number
  ): void {
    this.clearTransientMessageTimer();
    const delayMs = this.transientMessageViewModel.resolveClearDelayMs(state, context, nowMs);
    if (delayMs < 0) {
      return;
    }
    this.transientMessageClearTimer = setTimeout(() => {
      this.transientMessageClearTimer = -1;
      const nextState = this.transientMessageViewModel.clearExpired(
        this.presentationSnapshot.transientMessage,
        state.version,
        context,
        Date.now()
      );
      if (nextState === this.presentationSnapshot.transientMessage) {
        return;
      }
      this.commitPresentationSnapshot({
        gesturePrompt: this.presentationSnapshot.gesturePrompt,
        returnHomeGestureActive: this.presentationSnapshot.returnHomeGestureActive,
        scrollPresentation: this.presentationSnapshot.scrollPresentation,
        transientMessage: nextState
      });
    }, delayMs + 16);
  }

  private clearTransientMessageTimer(): void {
    if (this.transientMessageClearTimer < 0) {
      return;
    }
    clearTimeout(this.transientMessageClearTimer);
    this.transientMessageClearTimer = -1;
  }

  private commitPresentationSnapshot(snapshot: BrowserRootBottomPanelPresentationState): void {
    const current = this.presentationSnapshot;
    if (current.gesturePrompt.intent === snapshot.gesturePrompt.intent &&
      current.gesturePrompt.text === snapshot.gesturePrompt.text &&
      current.gesturePrompt.armed === snapshot.gesturePrompt.armed &&
      current.gesturePrompt.progress === snapshot.gesturePrompt.progress &&
      current.returnHomeGestureActive === snapshot.returnHomeGestureActive &&
      current.scrollPresentation === snapshot.scrollPresentation &&
      current.transientMessage.text === snapshot.transientMessage.text &&
      current.transientMessage.version === snapshot.transientMessage.version &&
      current.transientMessage.contextKey === snapshot.transientMessage.contextKey &&
      current.transientMessage.expiresAtMs === snapshot.transientMessage.expiresAtMs) {
      return;
    }
    this.publishPresentationState(snapshot);
  }

  private publishPresentationState(state: BrowserRootBottomPanelPresentationState): void {
    const snapshot: BrowserRootBottomPanelPresentationSnapshot = {
      gesturePrompt: state.gesturePrompt,
      returnHomeGestureActive: state.returnHomeGestureActive,
      scrollPresentation: state.scrollPresentation,
      transientMessage: state.transientMessage,
      revision: this.presentationSnapshot.revision + 1
    };
    this.presentationSnapshot = snapshot;
    this.sink.publishPresentationSnapshot(snapshot);
  }

  private resolveGesturePresentation(
    input: BrowserRootBottomPanelGestureInput
  ): BrowserRootBottomPanelGesturePresentation {
    if (this.resolveGestureOwner(input) === 'return_home') {
      const swipeAction = this.resolveOuterSwipeAction(input.source);
      const returnHomeGesture = this.bottomChromePresentationViewModel.resolveReturnHomeGesture({
        source: input.source,
        offsetY: input.offsetY,
        eligible: swipeAction !== undefined && !swipeAction.isNone,
        promptText: swipeAction === undefined ? '' : this.resolveSwipeReleasePrompt(swipeAction)
      });
      if (returnHomeGesture.active) {
        return {
          intent: 'return_home',
          text: returnHomeGesture.promptText,
          armed: returnHomeGesture.armed,
          progress: returnHomeGesture.progress
        };
      }
    }
    if (this.canHideSearch(input) && this.isDownwardGesture(input.offsetY)) {
      const armed = this.isHideSearchRelease(input.offsetY);
      return {
        intent: 'hide_search',
        text: armed ? BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_RELEASE_TEXT :
          BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_CONTINUE_TEXT,
        armed,
        progress: this.resolveGestureProgress(
          input.offsetY,
          BROWSER_ROOT_BOTTOM_PANEL_GESTURE_ACTIVE_OFFSET_Y,
          BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_MIN_OFFSET_Y
        )
      };
    }
    return {
      intent: 'none',
      text: '',
      armed: false,
      progress: 0
    };
  }

  private resolveHostMode(input: BrowserBottomPanelHostInput): BrowserBottomPanelHostMode {
    if (input.readerModeVisible || input.novelReaderVisible) {
      return 'hidden';
    }
    if (input.scene === 'home') {
      return input.homeSearchBarVisible || input.homeSearchSessionActive || this.programmaticHomeToolbarHostActive ||
        this.searchPresentationHostPreparationActive ?
        'browser' : 'hidden';
    }
    if (input.scene === 'web') {
      return 'browser';
    }
    return 'hidden';
  }

  private syncProgrammaticHomeToolbarPresentation(input: BrowserBottomPanelHostInput): void {
    if (this.programmaticHomeToolbarHostActive) {
      this.programmaticHomeToolbarRestingChromeHidden = input.scene === 'home' &&
        !input.homeSearchBarVisible &&
        !input.homeSearchSessionActive;
      return;
    }
    if (input.scene !== 'home' || input.homeSearchBarVisible || input.homeSearchSessionActive) {
      this.programmaticHomeToolbarRestingChromeHidden = false;
    }
  }

  private endProgrammaticHomeToolbarHostSession(preserveRestingChromeSuppression: boolean = false): void {
    this.programmaticHomeToolbarHostActive = false;
    if (!preserveRestingChromeSuppression) {
      this.programmaticHomeToolbarRestingChromeHidden = false;
    }
  }

  private clearSearchPresentationHostPreparationTimer(
    pending: BrowserRootBottomPanelPendingSearchHostPreparation
  ): void {
    if (pending.timer < 0) {
      return;
    }
    clearTimeout(pending.timer);
    pending.timer = -1;
  }

  private resolveHostHeight(mode: BrowserBottomPanelHostMode, input: BrowserBottomPanelHostInput): number {
    if (mode !== 'browser') {
      return 0;
    }
    const fallbackHeight = Math.max(0, input.viewportHeight);
    const resolvedHeight = input.browserHostHeight > 0 ? input.browserHostHeight : fallbackHeight;
    if (fallbackHeight <= 0) {
      return Math.max(0, resolvedHeight);
    }
    return Math.max(0, Math.min(resolvedHeight, fallbackHeight));
  }

  private shouldStartReturnHomeGesture(input: BrowserRootBottomPanelGestureInput): boolean {
    return this.canUseRootSearchPanelGesture(input) &&
      this.bottomChromePresentationViewModel.isOuterGestureSource(input.source);
  }

  private resolveInitialGestureOwner(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureOwner {
    return this.shouldStartReturnHomeGesture(input) ? 'return_home' : 'search_panel';
  }

  private resolveOuterGestureSlotId(source: BrowserBottomChromeGestureSource): BrowserToolbarSlotId | undefined {
    if (source === 'leading-outer') {
      return 'leading';
    }
    if (source === 'trailing-outer') {
      return 'tabs';
    }
    return undefined;
  }

  private resolveOuterSwipeAction(
    source: BrowserBottomChromeGestureSource
  ): BrowserToolbarInteractionActionState | undefined {
    const slotId = this.resolveOuterGestureSlotId(source);
    if (slotId === undefined) {
      return undefined;
    }
    return this.resolveActionApplication().resolveToolbarSlotActions()
      .find((slot: BrowserToolbarSlotActionState): boolean => slot.id === slotId)?.swipeUp?.action;
  }

  private resolveSwipeReleasePrompt(action: BrowserToolbarInteractionActionState): string {
    if (action.id === 'webBack') return '松手返回';
    if (action.id === 'webForward') return '松手前进';
    if (action.id === 'bottomChromeMenu') return '松手展开工具栏';
    if (action.id === 'webReload') return '松手刷新';
    if (action.id === 'openTabs') return '松手打开标签页';
    if (action.id === 'newTab') return '松手新建标签页';
    if (action.id === 'home') return '松手关闭并回主页';
    const directVerbActionIds: string[] = [
      'bookmark', 'scanQr', 'copyLink', 'share', 'sendToDesktop', 'print', 'translate', 'find'
    ];
    return directVerbActionIds.includes(action.id) ? `松手${action.title}` : `松手打开${action.title}`;
  }

  private resolveCoreToolbarActionRejection(
    action: BrowserToolbarInteractionActionState,
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): string {
    if (action.dispatchKind !== 'header') {
      return '';
    }
    if (action.id === 'webBack' || action.id === 'webForward') {
      return snapshot.isWebMode ? '' : `当前页面无法${action.title}。`;
    }
    if (action.id === 'bottomChromeMenu') {
      return snapshot.panelExpansionEnabled ? '' : '当前页面无法展开工具栏。';
    }
    if (action.id === 'newTab') {
      return snapshot.isHomeMode || snapshot.isWebMode ? '' : '当前页面无法新建标签页。';
    }
    const semanticState: BrowserRootBottomPanelSemanticState = {
      scene: snapshot.isHomeMode ? 'home' : (snapshot.isWebMode ? 'web' : 'inactive'),
      headerPresentation: snapshot.isHomeMode ? 'home' : 'address',
      contentPresentation: snapshot.isHomeMode ? 'home' : 'web',
      effectiveHome: snapshot.isHomeMode,
      effectiveWeb: snapshot.isWebMode,
      addressFocused: snapshot.homeSearchFocused
    };
    const projection = this.buildSemanticProjection(semanticState);
    const headerAction = projection.leadingHeaderActions.concat(projection.trailingHeaderActions)
      .find((item: BrowserBottomAddressPanelHeaderAction): boolean => item.id === action.id);
    if (headerAction?.enabled === true) {
      return '';
    }
    return `当前页面无法${action.title}。`;
  }

  private resolvePanelToolbarActionRejection(
    action: BrowserToolbarInteractionActionState,
    snapshot: BrowserRootBottomPanelSessionSnapshot
  ): string {
    if (action.dispatchKind !== 'panel' || !snapshot.isWebMode) {
      return '';
    }
    const enablement = this.resolveActionApplication().resolveToolbarActionEnablement(
      action.id as BrowserBottomPanelActionId
    );
    if (enablement.enabled) {
      return '';
    }
    return enablement.disabledMessage.length > 0 ? enablement.disabledMessage : `当前页面无法${action.title}。`;
  }

  private buildToolbarActionEnablement(
    slots: BrowserToolbarSlotActionState[],
    semanticState: BrowserRootBottomPanelSemanticState
  ): BrowserBottomPanelActionEnablementById {
    const result: BrowserBottomPanelActionEnablementById = {};
    slots.forEach((slot: BrowserToolbarSlotActionState): void => {
      const interactions: BrowserToolbarInteractionActionState[] = [slot.tap.action, slot.longPress.action];
      if (slot.swipeUp !== undefined) {
        interactions.push(slot.swipeUp.action);
      }
      interactions.forEach((action: BrowserToolbarInteractionActionState): void => {
        if (action.dispatchKind !== 'panel' || result[action.id] !== undefined) {
          return;
        }
        if (semanticState.effectiveHome) {
          const availability = this.homeActionAvailabilityCoordinator.resolve(
            action.id as BrowserBottomPanelActionId
          );
          result[action.id] = {
            enabled: availability.available,
            disabledMessage: availability.message
          };
          return;
        }
        result[action.id] = semanticState.effectiveWeb ?
          this.resolveActionApplication().resolveToolbarActionEnablement(action.id as BrowserBottomPanelActionId) : {
            enabled: false,
            disabledMessage: `当前页面无法${action.title}。`
          };
      });
    });
    return result;
  }

  private performGestureThresholdFeedbackIfRequested(state: BrowserRootBottomPanelGestureState): void {
    if (state.thresholdFeedbackRequested) {
      this.performGestureFeedback();
    }
  }

  private performGestureFeedback(): void {
    vibrator.startVibration({
      type: 'time',
      duration: BROWSER_ROOT_BOTTOM_PANEL_GESTURE_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private resolveGestureOwner(input: BrowserRootBottomPanelGestureInput): BrowserRootBottomPanelGestureOwner {
    if (this.activeGestureOwner !== 'none') {
      return this.activeGestureOwner;
    }
    return this.resolveInitialGestureOwner(input);
  }

  private canHideSearch(input: BrowserRootBottomPanelGestureInput): boolean {
    return input.source === 'center-capsule' &&
      this.canUseRootSearchPanelGesture(input) &&
      input.peekGestureEnabled &&
      !input.showTabsSheet;
  }

  private canUseRootSearchPanelGesture(input: BrowserRootBottomPanelGestureInput): boolean {
    return (input.showHomePage || input.webPageVisible) &&
      !input.showTabsSheet &&
      input.currentDetent === 'low' &&
      !input.addressFocused &&
      !input.documentViewerActive &&
      !input.webVideoControllerActive &&
      !input.webAppImmersiveMode &&
      !input.fullScreenModeEnabled;
  }

  private isDownwardGesture(offsetY: number): boolean {
    return Number.isFinite(offsetY) && offsetY >= BROWSER_ROOT_BOTTOM_PANEL_GESTURE_ACTIVE_OFFSET_Y;
  }

  private isHideSearchRelease(offsetY: number): boolean {
    return Number.isFinite(offsetY) && offsetY >= BROWSER_ROOT_BOTTOM_PANEL_HIDE_SEARCH_MIN_OFFSET_Y;
  }

  private resolveGestureProgress(offsetY: number, startOffset: number, endOffset: number): number {
    if (!Number.isFinite(offsetY) || endOffset <= startOffset) {
      return 0;
    }
    return Math.max(0, Math.min(1, (offsetY - startOffset) / (endOffset - startOffset)));
  }

  private applyScrollDecision(
    decision: BrowserBottomChromeHomeScrollDecision | BrowserBottomChromeWebScrollDecision
  ): void {
    if (!decision.changed) {
      return;
    }
    this.setScrollPresentation(decision.presentation);
    if (!this.shouldApplyScrollChromePlan(decision)) {
      return;
    }
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = decision.detent;
    plan.detentApplication = 'assign';
    plan.shouldClearWebAddressFocus = decision.shouldClearAddressFocus;
    plan.shouldClearWebAddressDraft = decision.shouldClearAddressDraft;
    plan.shouldSyncBottomPanelStatusBarStyle = decision.shouldSyncStatusBarStyle;
    this.sink.applyChromePlan(plan);
  }

  private shouldApplyScrollChromePlan(
    decision: BrowserBottomChromeHomeScrollDecision | BrowserBottomChromeWebScrollDecision
  ): boolean {
    return decision.detent !== 'low' ||
      decision.shouldClearAddressFocus ||
      decision.shouldClearAddressDraft ||
      decision.shouldSyncStatusBarStyle;
  }

  private setScrollPresentation(presentation: BrowserBottomChromeScrollPresentation): void {
    if (this.presentationSnapshot.scrollPresentation === presentation) {
      return;
    }
    this.resolveActionApplication().setWebProtectionFeedbackPhoneChromeCompact(presentation !== 'resting');
    this.commitPresentationSnapshot({
      gesturePrompt: this.presentationSnapshot.gesturePrompt,
      returnHomeGestureActive: this.presentationSnapshot.returnHomeGestureActive,
      scrollPresentation: presentation,
      transientMessage: this.presentationSnapshot.transientMessage
    });
  }

  private buildCollapseToLowPlan(
    snapshot: BrowserRootBottomPanelSessionSnapshot,
    immediateLowDetent: boolean
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.targetDetent = 'low';
    plan.detentApplication = 'apply';
    plan.immediateLowDetent = immediateLowDetent;
    plan.shouldResetSearchOverlay = snapshot.isHomeMode && (snapshot.homeSearchFocused || snapshot.homeSearchOverlayVisible);
    plan.shouldClearHomeSearchFocus = snapshot.isHomeMode && snapshot.homeSearchFocused;
    plan.shouldClearHomeAddressInput = snapshot.isHomeMode;
    plan.shouldClearWebAddressFocus = snapshot.isWebMode;
    plan.shouldClearWebAddressDraft = snapshot.isWebMode;
    plan.shouldRestoreScrollPresentation = snapshot.isWebMode;
    plan.shouldReleaseKeyboardAvoidMode = true;
    plan.shouldHideTextInput = true;
    plan.shouldCancelBackdropFocusTransition = true;
    return plan;
  }

  private buildHideToPeekPlan(snapshot: BrowserRootBottomPanelSessionSnapshot): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    if (!snapshot.isWebMode) {
      return plan;
    }
    plan.targetDetent = 'peek';
    plan.detentApplication = 'apply';
    plan.shouldRestoreScrollPresentation = true;
    plan.shouldClearWebAddressFocus = true;
    plan.shouldClearWebAddressDraft = true;
    return plan;
  }

  private clearTransientSheetReturnCapture(): void {
    this.transientSheetReturnDetent = undefined;
    this.transientSheetReturnTabId = '';
  }

  private buildAddressInputChromePlan(
    inputPlan: BrowserRootAddressInputSessionEndPlan
  ): BrowserRootBottomPanelChromePlan {
    const plan = this.buildEmptyChromePlan();
    plan.shouldResetSearchOverlay = inputPlan.shouldResetSearchOverlay;
    plan.shouldClearHomeSearchFocus = inputPlan.shouldClearHomeSearchFocus;
    plan.shouldClearHomeAddressInput = inputPlan.shouldClearHomeAddressInput;
    plan.shouldClearWebAddressFocus = inputPlan.shouldClearWebAddressFocus;
    plan.shouldClearWebAddressDraft = inputPlan.shouldClearWebAddressDraft;
    plan.shouldReleaseKeyboardAvoidMode = inputPlan.shouldReleaseKeyboardAvoidMode;
    plan.shouldHideTextInput = inputPlan.shouldHideTextInput;
    plan.webStatusBarRestoreReason = inputPlan.webStatusBarRestoreReason;
    if (inputPlan.shouldCollapsePanel) {
      plan.targetDetent = 'low';
      plan.detentApplication = 'assign';
      plan.shouldSyncBottomPanelStatusBarStyle = true;
    }
    return plan;
  }

  private buildEmptyChromePlan(): BrowserRootBottomPanelChromePlan {
    return {
      detentApplication: 'none',
      immediateLowDetent: false,
      deferLowDetentUntilSettle: false,
      homeDismissAfterLowSettle: false,
      shouldResetSearchOverlay: false,
      shouldReleaseHomeSearchFocus: false,
      shouldFocusHomeSearchInput: false,
      shouldClearHomeSearchFocus: false,
      shouldClearHomeAddressInput: false,
      shouldClearWebAddressFocus: false,
      shouldFocusWebAddressInput: false,
      shouldClearWebAddressDraft: false,
      shouldRestoreScrollPresentation: false,
      shouldRequestKeyboardInsetSync: false,
      shouldReleaseKeyboardAvoidMode: false,
      shouldHideTextInput: false,
      shouldReleaseHomeSearchBeforeBackdropEffects: false,
      shouldCancelBackdropFocusTransition: false,
      shouldCollapseSearchBackdropProgress: false,
      shouldEnsureHomeAddressFocusBackdrop: false,
      shouldEnsureWebAddressFocusBackdrop: false,
      shouldSyncBottomPanelStatusBarStyle: false,
      shouldEndSearchInvocationForAction: false,
      webStatusBarRestoreReason: ''
    };
  }

  private shouldDeferLowDetentUntilSettle(currentDetent: HomeSearchPanelDetent): boolean {
    return currentDetent === 'middle';
  }

  private isExpandedDetent(detent: HomeSearchPanelDetent): boolean {
    return detent === 'middle';
  }

  private isCollapsedDetent(detent: HomeSearchPanelDetent): boolean {
    return detent === 'low' || detent === 'peek';
  }

  private resolveScene(input: BrowserRootBottomPanelSemanticInput): BrowserRootBottomPanelScene {
    if (input.showHomePage) {
      return 'home';
    }
    if (this.homeToWebBottomPanelTransitionActive && input.webPageVisible) {
      return 'home';
    }
    return input.webPageVisible ? 'web' : 'inactive';
  }

  private finishHomeToWebBottomPanelTransition(
    force: boolean
  ): void {
    if (!this.homeToWebBottomPanelTransitionActive ||
      (!force && !this.homeToWebBottomPanelLowDetentSettled)) {
      return;
    }
    this.homeToWebBottomPanelTransitionGeneration += 1;
    this.clearHomeToWebBottomPanelTransitionTimer();
    this.homeToWebBottomPanelTransitionActive = false;
    this.homeToWebBottomPanelLowDetentSettled = false;
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] panel_transition_finish id=%{public}d force=%{public}s elapsedMs=%{public}d queued=%{public}d',
      this.homeToWebBottomPanelTransitionId,
      force ? 'true' : 'false',
      Date.now() - this.homeToWebBottomPanelTransitionStartedAt,
      this.deferredNavigationWork.length
    );
    this.invalidatePresentation();
    this.flushDeferredNavigationWork();
  }

  private clearHomeToWebBottomPanelTransitionTimer(): void {
    if (this.homeToWebBottomPanelTransitionTimer < 0) {
      return;
    }
    clearTimeout(this.homeToWebBottomPanelTransitionTimer);
    this.homeToWebBottomPanelTransitionTimer = -1;
  }

  private buildDeferredNavigationWorkHandle(
    entry: BrowserRootBottomPanelDeferredWorkEntry
  ): BrowserRootBottomPanelDeferredWorkHandle {
    return {
      cancel: (): void => {
        entry.cancelled = true;
        if (entry.timer >= 0) {
          clearTimeout(entry.timer);
          entry.timer = -1;
        }
        this.deferredNavigationWork = this.deferredNavigationWork.filter((candidate) => candidate.id !== entry.id);
      }
    };
  }

  private cancelDeferredNavigationWork(): void {
    const pending = this.deferredNavigationWork;
    this.deferredNavigationWork = [];
    pending.forEach((entry: BrowserRootBottomPanelDeferredWorkEntry): void => {
      entry.cancelled = true;
      if (entry.timer >= 0) {
        clearTimeout(entry.timer);
        entry.timer = -1;
      }
    });
  }

  private flushDeferredNavigationWork(): void {
    const pending = this.deferredNavigationWork;
    this.deferredNavigationWork = [];
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] navigation_flush id=%{public}d count=%{public}d elapsedMs=%{public}d',
      this.homeToWebBottomPanelTransitionId,
      pending.length,
      Date.now() - this.homeToWebBottomPanelTransitionStartedAt
    );
    pending.forEach((entry: BrowserRootBottomPanelDeferredWorkEntry): void => {
      if (entry.cancelled) {
        return;
      }
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] navigation_flush_work id=%{public}d workId=%{public}d elapsedMs=%{public}d',
        this.homeToWebBottomPanelTransitionId,
        entry.id,
        Date.now() - this.homeToWebBottomPanelTransitionStartedAt
      );
      entry.work();
    });
  }

}
