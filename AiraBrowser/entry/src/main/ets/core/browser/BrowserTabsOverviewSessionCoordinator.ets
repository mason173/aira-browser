import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  BrowserPrivateModeLockCoordinator,
  BrowserPrivateModeLockReason
} from '../privacy/BrowserPrivateModeLockCoordinator';
import {
  BrowserCreateTabOptions,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import { browserNativeTabSceneService } from './BrowserNativeTabSceneService';
import {
  BrowserCloseTabsToHomeResult,
  BrowserTabCloseCoordinator
} from './BrowserTabCloseCoordinator';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import {
  BrowserPrivateModeTogglePlan,
  BrowserPrivateTabCoordinator
} from './BrowserPrivateTabCoordinator';
import {
  BrowserTabPreviewCoordinator,
  BrowserTabPreviewState
} from './BrowserTabPreviewCoordinator';
import { BrowserTabSharedSnapshotSelectionPolicy } from './BrowserTabSharedSnapshotSelectionPolicy';
import { BrowserWebLayerGeometrySnapshot } from './BrowserWebLayerGeometryCache';
import {
  BrowserTabsOverviewActionBarPolicy,
  BrowserTabsOverviewActionSection,
  BrowserTabsOverviewDeletePlan,
  BrowserTabsOverviewHomeRevealMotion
} from './BrowserTabsOverviewActionBarPolicy';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';
import {
  BrowserTabsSharedSnapshotEntryCoordinator,
  BrowserTabsSharedSnapshotEntryState
} from './BrowserTabsSharedSnapshotEntryCoordinator';
import {
  BrowserTabsSharedSnapshotTransitionCoordinator,
  BrowserTabsSharedSnapshotTransitionState,
  BrowserTabsSharedSnapshotWindowInput,
  BrowserTabsSharedSnapshotTargetRectInput,
  BrowserTabsSharedSnapshotInterruptedEntryExitInput,
  buildBrowserTabsSharedSnapshotIdleState
} from './BrowserTabsSharedSnapshotTransitionCoordinator';
import { BROWSER_TABS_OVERVIEW_CARD_CORNER_RADIUS } from './BrowserTabsOverviewVisualTokens';
import {
  BrowserTabsOverviewSnapshotMorphSource,
  BrowserTabsOverviewSnapshotPipelineCoordinator
} from './tabsOverview/BrowserTabsOverviewSnapshotPipelineCoordinator';
import { BrowserTabsOverlayAnimationViewModel } from './BrowserTabsOverlayAnimationViewModel';
import {
  BrowserHostedWebLayerPresentationViewModel,
  BrowserHostedWebSourceSurfaceHandoffPatch
} from './BrowserHostedWebLayerPresentationViewModel';
import {
  BrowserTabsOverviewEntryMode,
  BrowserTabsOverviewHeaderMode,
  BrowserTabsOverviewSceneDriver,
  BrowserTabsOverviewSceneEntryRunPlan,
  BrowserTabsOverviewScenePhase,
  BrowserTabsOverviewSceneRenderState,
  BrowserTabsOverviewSceneResetPatch,
  BrowserTabsOverviewSceneState
} from './tabsOverview/BrowserTabsOverviewSceneDriver';
import { BrowserTabsOverlayRect } from './BrowserTabsOverlayViewModel';
import {
  BrowserTabsOverviewKeyboardApplicationHost,
  BrowserTabsOverviewKeyboardCoordinator,
  BrowserTabsOverviewKeyboardShellKeyEventInput
} from './tabsOverview/BrowserTabsOverviewKeyboardCoordinator';
import {
  BrowserPrivateProfileCookieLifecycleHost,
  BrowserPrivateProfileLifecycleCoordinator
} from './BrowserPrivateProfileLifecycleCoordinator';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';
import { BrowserBackgroundOpenPromptCoordinator } from './BrowserBackgroundOpenPromptCoordinator';

export type BrowserTabsOverviewSessionSection = 'tabs' | 'privacy';
export type BrowserTabsOverviewSessionPlanKind = 'ignore' | 'open_now' | 'collapse_then_open';

export interface BrowserTabsOverviewSessionOpenRequestInput {
  activeSection: BrowserTabsOverviewSessionSection;
  showTabsSheet: boolean;
  tabsOverlayExiting: boolean;
  rootBottomPanelDetent: HomeSearchPanelDetent;
}

export interface BrowserTabsOverviewPrimarySurfaceInput {
  showHomePage: boolean;
  activeTabIsHome: boolean;
}

export interface BrowserTabsOverviewSharedSnapshotWindowFacts {
  rootViewportLeft: number;
  rootViewportTop: number;
  rootViewportWidth: number;
  rootViewportHeight: number;
  webViewportHostHeight: number;
  webVisualTopInset: number;
  topSafeInsetVp: number;
  bottomSafeInsetVp: number;
  showHomePage: boolean;
  webAppImmersiveMode: boolean;
  hostedWebLayerMeasured: boolean;
  hostedWebLayerLeft: number;
  hostedWebLayerTop: number;
  hostedWebLayerWidth: number;
  hostedWebLayerHeight: number;
  reusableGeometry?: BrowserWebLayerGeometrySnapshot;
}

export interface BrowserTabsOverviewSharedSnapshotDependencies {
  previewCoordinator: BrowserTabPreviewCoordinator;
  snapshotPipelineCoordinator: BrowserTabsOverviewSnapshotPipelineCoordinator;
  hostedWebLayerPresentationViewModel: BrowserHostedWebLayerPresentationViewModel;
}

export interface BrowserTabsOverviewFixedDependencies {
  privateModeLockCoordinator: BrowserPrivateModeLockCoordinator;
  privateProfileLifecycleCoordinator: BrowserPrivateProfileLifecycleCoordinator;
  privateProfileCookieLifecycleHost: BrowserPrivateProfileCookieLifecycleHost;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  webTopImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  backgroundOpenPromptCoordinator: BrowserBackgroundOpenPromptCoordinator;
}

export interface BrowserTabsOverviewSharedSnapshotChromeRevealPlan {
  delayMs: number;
  durationMs: number;
  curve: Curve | string | ICurve;
  overlayOpacity: number;
}

interface BrowserTabsOverviewSharedSnapshotAnimationPlan {
  runId: number;
  initialState: BrowserTabsSharedSnapshotTransitionState;
  durationMs: number;
  curve: Curve | string | ICurve;
  targetProgress: number;
  handoffDelayMs: number;
  sourceSurfaceHandoffPatch: BrowserHostedWebSourceSurfaceHandoffPatch;
  chromeReveal?: BrowserTabsOverviewSharedSnapshotChromeRevealPlan;
}

export interface BrowserTabsOverviewSessionOpenPlan {
  kind: BrowserTabsOverviewSessionPlanKind;
  activeSection: BrowserTabsOverviewSessionSection;
  collapseRootBottomPanelToDefault: boolean;
  openDelayMs: number;
}

export interface BrowserTabsOverviewSessionFacts {
  tabs: BrowserTabState[];
  tabSequence: number;
  tabsOverviewMounted: boolean;
  homeSurfaceVisible: boolean;
  keepHomeResident: boolean;
  currentTabPrivate: boolean;
  activeTabId: string;
  homeUrl: string;
  runtimeDegradedMessage: string;
  rootBottomPanelDetent: HomeSearchPanelDetent;
  rootBottomPanelEffectiveHomeMode: boolean;
  backdropOpenStartProgress: number;
  sharedSnapshotWindow: BrowserTabsOverviewSharedSnapshotWindowFacts;
}

export interface BrowserTabsOverviewSessionPresentationState {
  activeSection: BrowserTabsOverviewSessionSection;
  animationVersion: number;
  entryAnimationActive: boolean;
  headerMode: BrowserTabsOverviewHeaderMode;
  exiting: boolean;
  homeSurfaceCloseInFlight: boolean;
  sceneState: BrowserTabsOverviewSceneState;
  keyboardSelectedTabId: string;
  keyboardSelectionVersion: number;
  keyboardSelectionResetVersion: number;
  showKeyboardNumberBadges: boolean;
  closeAllAnimationRequestVersion: number;
  closeAllAnimationPending: boolean;
  sharedSnapshotState: BrowserTabsSharedSnapshotTransitionState;
  sharedSnapshotRunId: number;
  surface: BrowserTabsOverviewSurfacePresentationState;
}

export interface BrowserTabsOverviewSurfacePresentationState {
  overlayOpacity: number;
  backdropProgress: number;
  entryMode: BrowserTabsOverviewEntryMode;
  webEntryProgress: number;
  homeExitProgress: number;
  webLayerOpacity: number;
  backdropSnapshotVisible: boolean;
  backdropSnapshotOpacity: number;
}

interface BrowserTabsOverviewSurfacePresentationPatch {
  overlayOpacity?: number;
  backdropProgress?: number;
  entryMode?: BrowserTabsOverviewEntryMode;
  webEntryProgress?: number;
  homeExitProgress?: number;
  webLayerOpacity?: number;
  backdropSnapshotVisible?: boolean;
  backdropSnapshotOpacity?: number;
}

interface BrowserTabsOverviewSessionPresentationPatch {
  activeSection?: BrowserTabsOverviewSessionSection;
  animationVersion?: number;
  entryAnimationActive?: boolean;
  headerMode?: BrowserTabsOverviewHeaderMode;
  exiting?: boolean;
  homeSurfaceCloseInFlight?: boolean;
  sceneState?: BrowserTabsOverviewSceneState;
  keyboardSelectedTabId?: string;
  keyboardSelectionVersion?: number;
  keyboardSelectionResetVersion?: number;
  showKeyboardNumberBadges?: boolean;
  closeAllAnimationRequestVersion?: number;
  closeAllAnimationPending?: boolean;
  sharedSnapshotState?: BrowserTabsSharedSnapshotTransitionState;
  sharedSnapshotRunId?: number;
  surface?: BrowserTabsOverviewSurfacePresentationPatch;
}

interface BrowserTabsOverviewSelectionVisualFacts {
  morphSource: BrowserTabsOverviewSnapshotMorphSource;
  hostedWebLayerMeasured: boolean;
  reusableGeometry?: BrowserWebLayerGeometrySnapshot;
  webRect: BrowserTabsOverlayRect;
}

export interface BrowserTabsOverviewHomeSurfacePlan {
  section: BrowserTabsOverviewSessionSection;
  options: BrowserCreateTabOptions;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  authReason: BrowserPrivateModeLockReason;
  helperMessage: string;
}

export interface BrowserTabsOverviewSingleCloseHomePlan {
  shouldRevealHomeFirst: boolean;
  tabIds: string[];
  homeOptions: BrowserCreateTabOptions;
  helperMessage: string;
  revealDelayMs: number;
  homeRevealMotion: BrowserTabsOverviewHomeRevealMotion;
}

export interface BrowserTabsOverviewBackgroundRenderInput {
  showTabsSheet: boolean;
  tabsOverlayExiting: boolean;
  snapshotVisible: boolean;
  openedFromHome: boolean;
  scenePhase: BrowserTabsOverviewScenePhase;
  snapshotOpacity: number;
  homeExitProgress: number;
  backdropProgress: number;
}

export interface BrowserTabsOverviewBackgroundRenderState {
  homeBackdropVisible: boolean;
  homeBackdropOpacity: number;
  homeBackdropEffectProgress: number;
  floatingGlassOpacity: number;
}

export interface BrowserTabsOverviewSceneProjection {
  galleryCoveredTabId: string;
  selectionDisplacementTabId: string;
  entryDisplacementTabId: string;
  entryDisplacementSettlingEnabled: boolean;
  sideEntryAnimationEnabled: boolean;
}

export interface BrowserTabsOverviewSessionResetOptions {
  createSharedSnapshotRunId: boolean;
  resetSharedSnapshotTransition: boolean;
  resetEntrySnapshotFrame: boolean;
  releaseEntrySnapshot: boolean;
  bumpAnimationVersion: boolean;
}

type BrowserTabsOverviewSharedSnapshotEntryReset = 'keep' | 'cancel' | 'finish';

interface BrowserTabsOverviewSessionResetPlan extends BrowserTabsOverviewSessionResetOptions {
  entryStateReset: BrowserTabsOverviewSharedSnapshotEntryReset;
}

type BrowserTabsOverviewSimpleEffectType =
  | 'cancel_bottom_panel_backdrop_focus_transition'
  | 'clear_root_bottom_chrome_scroll'
  | 'release_home_search_focus'
  | 'release_web_bottom_address_focus'
  | 'sync_bottom_panel_status_bar_style'
  | 'reset_home_reveal'
  | 'notify_tab_preview_changed'
  | 'reconcile_external_navigation_prompt'
  | 'refresh_tabs_sheet_appearance'
  | 'reset_web_bottom_address_panel_for_tab_selection'
  | 'apply_closed_overview_reset'
  | 'prepare_home_reveal_from_tabs_overview'
  | 'play_home_reveal_from_tabs_overview'
  | 'finish_tabs_overview_dismiss_home';

interface BrowserTabsOverviewSimpleEffect {
  type: BrowserTabsOverviewSimpleEffectType;
}

interface BrowserTabsOverviewDetentEffect {
  type: 'apply_root_bottom_panel_detent';
  detent: HomeSearchPanelDetent;
}

interface BrowserTabsOverviewTraceEffect {
  type: 'record_session_trace';
  traceType: string;
  message: string;
  tabId: string;
}

interface BrowserTabsOverviewMessageEffect {
  type: 'show_native_toast';
  message: string;
}

interface BrowserTabsOverviewTabEffect {
  type: 'export_tabs_overview_debug_snapshot' | 'flush_scroll_deferred_page_metadata';
  tabId: string;
}

interface BrowserTabsOverviewOptimisticHomeRevealEffect {
  type: 'prepare_optimistic_home_reveal';
  motion: BrowserTabsOverviewHomeRevealMotion;
}

interface BrowserTabsOverviewSectionChangeEffect {
  type: 'apply_section_change';
  options: BrowserCreateTabOptions;
  userMessage: string;
}

interface BrowserTabsOverviewRuntimeEventEffect {
  type: 'record_runtime_event';
  eventType: string;
  message: string;
  tabId: string;
}

interface BrowserTabsOverviewCloseAllConfirmationEffect {
  type: 'show_close_all_confirmation';
  plan: BrowserTabsOverviewDeletePlan;
}

interface BrowserTabsOverviewConfirmPrivateModeSwitchEffect {
  type: 'confirm_private_mode_switch';
  plan: BrowserPrivateModeTogglePlan;
}

interface BrowserTabsOverviewKeyboardMessageEffect {
  type: 'show_keyboard_shortcut_message';
  message: string;
}

export interface BrowserTabsOverviewArkUiAnimationPlan {
  durationMs: number;
  curve: Curve | string | ICurve;
  apply: () => void;
  onFinish?: () => void;
}

interface BrowserTabsOverviewArkUiAnimationEffect {
  type: 'play_tabs_overview_arkui_animation';
  plan: BrowserTabsOverviewArkUiAnimationPlan;
}

interface BrowserTabsOverviewEntryShellEffect {
  type: 'apply_tabs_overview_entry_shell_state';
  shouldResetHomeReveal: boolean;
  shouldShowTabsSheet: boolean;
}

export type BrowserTabsOverviewSessionEffect =
  | BrowserTabsOverviewSimpleEffect
  | BrowserTabsOverviewDetentEffect
  | BrowserTabsOverviewTraceEffect
  | BrowserTabsOverviewMessageEffect
  | BrowserTabsOverviewTabEffect
  | BrowserTabsOverviewOptimisticHomeRevealEffect
  | BrowserTabsOverviewSectionChangeEffect
  | BrowserTabsOverviewRuntimeEventEffect
  | BrowserTabsOverviewCloseAllConfirmationEffect
  | BrowserTabsOverviewConfirmPrivateModeSwitchEffect
  | BrowserTabsOverviewKeyboardMessageEffect
  | BrowserTabsOverviewArkUiAnimationEffect
  | BrowserTabsOverviewEntryShellEffect;

export interface BrowserTabsOverviewCaptureFreshActiveTabPreviewTask {
  type: 'capture_fresh_active_tab_preview';
  tab: BrowserTabState;
  generation: number;
}

export type BrowserTabsOverviewAsyncTask = BrowserTabsOverviewCaptureFreshActiveTabPreviewTask;

export interface BrowserTabsOverviewAsyncTaskResult {
  success: boolean;
}

export interface BrowserTabsOverviewSessionHost {
  readSessionFacts: () => BrowserTabsOverviewSessionFacts;
  executeAsyncTask: (task: BrowserTabsOverviewAsyncTask) => Promise<BrowserTabsOverviewAsyncTaskResult>;
  executeEffect: (effect: BrowserTabsOverviewSessionEffect) => void;
  publishPresentationState: (state: BrowserTabsOverviewSessionPresentationState) => void;
}

export interface BrowserTabsOverviewNumberShortcutCommand {
  type: 'number_shortcut';
  digit: number;
}

export interface BrowserTabsOverviewResolveNumberedTabCommand {
  type: 'resolve_numbered_tab';
  tabs: BrowserTabState[];
  digit: number;
}

export interface BrowserTabsOverviewShellKeyCommand {
  type: 'shell_key';
  input: BrowserTabsOverviewKeyboardShellKeyEventInput;
}

export type BrowserTabsOverviewKeyboardCommand =
  | BrowserTabsOverviewNumberShortcutCommand
  | BrowserTabsOverviewResolveNumberedTabCommand
  | BrowserTabsOverviewShellKeyCommand;

export interface BrowserTabsOverviewKeyboardCommandResult {
  handled: boolean;
  tabId: string;
}

export interface BrowserTabsOverviewSessionRequestOpenFromRootBottomPanelAction {
  type: 'request_open_from_root_bottom_panel';
  section: BrowserTabsOverviewSessionSection;
}

export interface BrowserTabsOverviewSessionRequestOpenAction {
  type: 'request_open';
  section: BrowserTabsOverviewSessionSection;
}

export interface BrowserTabsOverviewSessionCancelDeferredOpenAction {
  type: 'cancel_deferred_open';
}

export interface BrowserTabsOverviewSessionRequestCloseAction {
  type: 'request_close';
  targetHeaderMode?: BrowserTabsOverviewHeaderMode;
}

export interface BrowserTabsOverviewSessionCloseToHomeAction {
  type: 'close_to_home_without_sheet_exit';
}

export interface BrowserTabsOverviewSessionCapturedEntryReadyAction {
  type: 'captured_entry_ready';
  tabId: string;
  generation: number;
}

export interface BrowserTabsOverviewSessionEntryTargetReadyAction {
  type: 'entry_target_ready';
  tabId: string;
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface BrowserTabsOverviewSessionCancelSharedSnapshotEntryAction {
  type: 'cancel_shared_snapshot_entry';
}

export interface BrowserTabsOverviewSessionSelectTabAction {
  type: 'select_tab';
  tabId: string;
}

export interface BrowserTabsOverviewSessionInterruptEntrySelectionAction {
  type: 'interrupt_entry_selection';
  tabId: string;
}

export interface BrowserTabsOverviewSessionDismissToHomeAction {
  type: 'dismiss_to_home';
}

export interface BrowserTabsOverviewSessionCreateHomeAction {
  type: 'create_home';
}

export interface BrowserTabsOverviewSessionCreateHomeTabAction {
  type: 'create_home_tab';
  helperMessage: string;
  options: BrowserCreateTabOptions;
  keepTabsOverviewMounted: boolean;
  playHomeReveal: boolean;
}

export interface BrowserTabsOverviewSessionEnterPrivateAction {
  type: 'enter_private';
  helperMessage: string;
  options: BrowserCreateTabOptions;
}

export interface BrowserTabsOverviewSessionCloseTabAction {
  type: 'close_tab';
  tabId: string;
}

export interface BrowserTabsOverviewSessionRequestCloseAllAction {
  type: 'request_close_all';
}

export interface BrowserTabsOverviewSessionConfirmCloseAllAction {
  type: 'confirm_close_all';
}

export interface BrowserTabsOverviewSessionCloseAllAnimationFinishedAction {
  type: 'close_all_animation_finished';
}

export interface BrowserTabsOverviewSessionChangeSectionAction {
  type: 'change_section';
  section: BrowserTabsOverviewSessionSection;
}

export interface BrowserTabsOverviewSessionActivateSectionHomeAction {
  type: 'activate_section_home';
  section: BrowserTabsOverviewSessionSection;
}

export interface BrowserTabsOverviewSessionKeyboardAction {
  type: 'keyboard';
  command: BrowserTabsOverviewKeyboardCommand;
}

export type BrowserTabsOverviewSessionAction =
  | BrowserTabsOverviewSessionRequestOpenFromRootBottomPanelAction
  | BrowserTabsOverviewSessionRequestOpenAction
  | BrowserTabsOverviewSessionCancelDeferredOpenAction
  | BrowserTabsOverviewSessionRequestCloseAction
  | BrowserTabsOverviewSessionCloseToHomeAction
  | BrowserTabsOverviewSessionCapturedEntryReadyAction
  | BrowserTabsOverviewSessionEntryTargetReadyAction
  | BrowserTabsOverviewSessionCancelSharedSnapshotEntryAction
  | BrowserTabsOverviewSessionSelectTabAction
  | BrowserTabsOverviewSessionInterruptEntrySelectionAction
  | BrowserTabsOverviewSessionDismissToHomeAction
  | BrowserTabsOverviewSessionCreateHomeAction
  | BrowserTabsOverviewSessionCreateHomeTabAction
  | BrowserTabsOverviewSessionEnterPrivateAction
  | BrowserTabsOverviewSessionCloseTabAction
  | BrowserTabsOverviewSessionRequestCloseAllAction
  | BrowserTabsOverviewSessionConfirmCloseAllAction
  | BrowserTabsOverviewSessionCloseAllAnimationFinishedAction
  | BrowserTabsOverviewSessionChangeSectionAction
  | BrowserTabsOverviewSessionActivateSectionHomeAction
  | BrowserTabsOverviewSessionKeyboardAction;

const TABS_OVERVIEW_OPEN_AFTER_COLLAPSE_DELAY_MS: number = 240;
const SINGLE_TAB_CLOSE_HOME_REVEAL_DELAY_MS: number = 380;
const SHARED_SNAPSHOT_MOUNT_DELAY_MS: number = 16;
const SHARED_SNAPSHOT_COMPLETION_GRACE_MS: number = 180;
const REGULAR_HOME_OPTIONS: BrowserCreateTabOptions = {
  profileId: DEFAULT_BROWSER_PROFILE_ID,
  privacyMode: 'regular',
  dataScope: 'profile_persistent'
};

export class BrowserTabsOverviewSessionCoordinator {
  private deferredOpenTimer: number = -1;
  private operationGeneration: number = 0;
  private interruptedSelectionCompletionGeneration: number = -1;
  private homeSurfaceCloseGeneration: number = -1;
  private closeAllConfirmationGeneration: number = -1;
  private backdropSettleRunId: number = 0;
  private backdropHomeRevealRunId: number = 0;
  private lockedSnapshotTabId: string = '';
  private sceneDriver: BrowserTabsOverviewSceneDriver = new BrowserTabsOverviewSceneDriver();
  private presentationState: BrowserTabsOverviewSessionPresentationState = {
    activeSection: 'tabs',
    animationVersion: 0,
    entryAnimationActive: false,
    headerMode: 'home',
    exiting: false,
    homeSurfaceCloseInFlight: false,
    sceneState: this.sceneDriver.buildClosedSceneState(),
    keyboardSelectedTabId: '',
    keyboardSelectionVersion: 0,
    keyboardSelectionResetVersion: 0,
    showKeyboardNumberBadges: false,
    closeAllAnimationRequestVersion: 0,
    closeAllAnimationPending: false,
    sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState(),
    sharedSnapshotRunId: 0,
    surface: {
      overlayOpacity: 0,
      backdropProgress: 0,
      entryMode: 'home',
      webEntryProgress: 1,
      homeExitProgress: 0,
      webLayerOpacity: 1,
      backdropSnapshotVisible: false,
      backdropSnapshotOpacity: 0
    }
  };
  private sharedSnapshotEntryCoordinator: BrowserTabsSharedSnapshotEntryCoordinator =
    new BrowserTabsSharedSnapshotEntryCoordinator();
  private sharedSnapshotEntryState: BrowserTabsSharedSnapshotEntryState =
    this.sharedSnapshotEntryCoordinator.buildIdleState();
  private sharedSnapshotTransitionCoordinator: BrowserTabsSharedSnapshotTransitionCoordinator =
    new BrowserTabsSharedSnapshotTransitionCoordinator();
  private sharedSnapshotAnimationViewModel: BrowserTabsOverlayAnimationViewModel =
    new BrowserTabsOverlayAnimationViewModel();
  private readonly hostedWebLayerPresentationViewModel: BrowserHostedWebLayerPresentationViewModel;
  private selectionPolicy: BrowserTabSharedSnapshotSelectionPolicy = new BrowserTabSharedSnapshotSelectionPolicy();
  private keyboardCoordinator: BrowserTabsOverviewKeyboardCoordinator = new BrowserTabsOverviewKeyboardCoordinator();
  private actionPolicy: BrowserTabsOverviewActionBarPolicy = new BrowserTabsOverviewActionBarPolicy();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private readonly tabManager: BrowserTabManagerPort;
  private readonly privateTabCoordinator: BrowserPrivateTabCoordinator;
  private readonly tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  private readonly tabHomeCoordinator: BrowserTabHomeCoordinator;
  private readonly tabCloseCoordinator: BrowserTabCloseCoordinator;
  private readonly restorePersistedTabPreviews: () => Promise<void>;
  private readonly debugSnapshotExportEnabled: boolean;
  private readonly previewCoordinator: BrowserTabPreviewCoordinator;
  private readonly snapshotPipelineCoordinator: BrowserTabsOverviewSnapshotPipelineCoordinator;
  private readonly fixedDependencies: BrowserTabsOverviewFixedDependencies;
  private resolveHost: () => BrowserTabsOverviewSessionHost;
  private keyboardHost: BrowserTabsOverviewKeyboardApplicationHost = {
    getTabs: (): BrowserTabState[] => this.resolveHost().readSessionFacts().tabs,
    isPrivacySectionActive: (): boolean => this.presentationState.activeSection === 'privacy',
    getActiveTabId: (): string => this.resolveHost().readSessionFacts().activeTabId,
    getSelectedTabId: (): string => this.presentationState.keyboardSelectedTabId,
    applySelection: (tabId: string, showNumberBadges: boolean, resetOpeningSelection: boolean): void => {
      const current = this.presentationState;
      this.updatePresentationState({
        keyboardSelectedTabId: tabId,
        keyboardSelectionVersion: current.keyboardSelectionVersion + 1,
        keyboardSelectionResetVersion: resetOpeningSelection ?
          current.keyboardSelectionResetVersion + 1 : current.keyboardSelectionResetVersion,
        showKeyboardNumberBadges: showNumberBadges
      }, this.resolveHost());
    },
    setNumberBadgesVisible: (visible: boolean): void => {
      this.updatePresentationState({ showKeyboardNumberBadges: visible }, this.resolveHost());
    },
    showShortcutMessage: (message: string): void => {
      this.resolveHost().executeEffect({ type: 'show_keyboard_shortcut_message', message: message });
    },
    finishTabSelection: (tabId: string): Promise<void> => this.selectTab(tabId)
  };

  constructor(
    tabManager: BrowserTabManagerPort,
    privateTabCoordinator: BrowserPrivateTabCoordinator,
    tabSwitchCoordinator: BrowserTabSwitchCoordinator,
    tabHomeCoordinator: BrowserTabHomeCoordinator,
    tabCloseCoordinator: BrowserTabCloseCoordinator,
    restorePersistedTabPreviews: () => Promise<void>,
    debugSnapshotExportEnabled: boolean,
    fixedDependencies: BrowserTabsOverviewFixedDependencies,
    sharedSnapshotDependencies: BrowserTabsOverviewSharedSnapshotDependencies,
    resolveHost: () => BrowserTabsOverviewSessionHost
  ) {
    this.tabManager = tabManager;
    this.privateTabCoordinator = privateTabCoordinator;
    this.tabSwitchCoordinator = tabSwitchCoordinator;
    this.tabHomeCoordinator = tabHomeCoordinator;
    this.tabCloseCoordinator = tabCloseCoordinator;
    this.restorePersistedTabPreviews = restorePersistedTabPreviews;
    this.debugSnapshotExportEnabled = debugSnapshotExportEnabled;
    this.fixedDependencies = fixedDependencies;
    this.previewCoordinator = sharedSnapshotDependencies.previewCoordinator;
    this.snapshotPipelineCoordinator = sharedSnapshotDependencies.snapshotPipelineCoordinator;
    this.hostedWebLayerPresentationViewModel = sharedSnapshotDependencies.hostedWebLayerPresentationViewModel;
    this.resolveHost = resolveHost;
  }

  getPresentationState(): BrowserTabsOverviewSessionPresentationState {
    return this.clonePresentationState(this.presentationState);
  }

  setActiveSection(section: BrowserTabsOverviewSessionSection): void {
    this.updatePresentationState({ activeSection: this.normalizeSection(section) }, this.resolveHost());
  }

  selectTabFromOverlay(
    tabId: string,
    left?: number,
    top?: number,
    width?: number,
    height?: number
  ): void {
    if (this.presentationState.exiting || this.presentationState.homeSurfaceCloseInFlight) {
      return;
    }
    if (left !== undefined && top !== undefined && width !== undefined && height !== undefined) {
      this.rememberSharedSnapshotPreviewRect(tabId, left, top, width, height);
    }
    this.handle({ type: 'select_tab', tabId: tabId });
  }

  requestCloseAllFromOverlay(): void {
    if (this.presentationState.homeSurfaceCloseInFlight) {
      return;
    }
    this.handle({ type: 'request_close_all' });
  }

  closeTabFromOverlay(tabId: string): void {
    if (this.presentationState.homeSurfaceCloseInFlight) {
      return;
    }
    this.handle({ type: 'close_tab', tabId: tabId });
  }

  finishCloseAllAnimationFromOverlay(): void {
    this.handle({ type: 'close_all_animation_finished' });
  }

  private updatePresentationState(
    patch: BrowserTabsOverviewSessionPresentationPatch,
    host: BrowserTabsOverviewSessionHost
  ): void {
    const current = this.presentationState;
    this.presentationState = {
      activeSection: patch.activeSection ?? current.activeSection,
      animationVersion: patch.animationVersion ?? current.animationVersion,
      entryAnimationActive: patch.entryAnimationActive ?? current.entryAnimationActive,
      headerMode: patch.headerMode ?? current.headerMode,
      exiting: patch.exiting ?? current.exiting,
      homeSurfaceCloseInFlight: patch.homeSurfaceCloseInFlight ?? current.homeSurfaceCloseInFlight,
      sceneState: patch.sceneState ?? current.sceneState,
      keyboardSelectedTabId: patch.keyboardSelectedTabId ?? current.keyboardSelectedTabId,
      keyboardSelectionVersion: patch.keyboardSelectionVersion ?? current.keyboardSelectionVersion,
      keyboardSelectionResetVersion: patch.keyboardSelectionResetVersion ?? current.keyboardSelectionResetVersion,
      showKeyboardNumberBadges: patch.showKeyboardNumberBadges ?? current.showKeyboardNumberBadges,
      closeAllAnimationRequestVersion: patch.closeAllAnimationRequestVersion ??
        current.closeAllAnimationRequestVersion,
      closeAllAnimationPending: patch.closeAllAnimationPending ?? current.closeAllAnimationPending,
      sharedSnapshotState: patch.sharedSnapshotState ?? current.sharedSnapshotState,
      sharedSnapshotRunId: patch.sharedSnapshotRunId ?? current.sharedSnapshotRunId,
      surface: this.applySurfacePatch(current.surface, patch.surface)
    };
    host.publishPresentationState(this.clonePresentationState(this.presentationState));
  }

  private clonePresentationState(
    state: BrowserTabsOverviewSessionPresentationState
  ): BrowserTabsOverviewSessionPresentationState {
    return {
      activeSection: state.activeSection,
      animationVersion: state.animationVersion,
      entryAnimationActive: state.entryAnimationActive,
      headerMode: state.headerMode,
      exiting: state.exiting,
      homeSurfaceCloseInFlight: state.homeSurfaceCloseInFlight,
      sceneState: state.sceneState,
      keyboardSelectedTabId: state.keyboardSelectedTabId,
      keyboardSelectionVersion: state.keyboardSelectionVersion,
      keyboardSelectionResetVersion: state.keyboardSelectionResetVersion,
      showKeyboardNumberBadges: state.showKeyboardNumberBadges,
      closeAllAnimationRequestVersion: state.closeAllAnimationRequestVersion,
      closeAllAnimationPending: state.closeAllAnimationPending,
      sharedSnapshotState: state.sharedSnapshotState,
      sharedSnapshotRunId: state.sharedSnapshotRunId,
      surface: this.applySurfacePatch(state.surface)
    };
  }

  private beginBackdropSettleRun(): number {
    this.backdropSettleRunId += 1;
    return this.backdropSettleRunId;
  }

  private cancelBackdropSettleRun(): void {
    this.backdropSettleRunId += 1;
  }

  private isBackdropSettleRunCurrent(runId: number): boolean {
    return this.backdropSettleRunId === runId;
  }

  private beginBackdropHomeRevealRun(): number {
    this.backdropHomeRevealRunId += 1;
    return this.backdropHomeRevealRunId;
  }

  private cancelBackdropHomeRevealRun(): void {
    this.backdropHomeRevealRunId += 1;
  }

  private isBackdropHomeRevealRunCurrent(runId: number): boolean {
    return this.backdropHomeRevealRunId === runId;
  }

  resetBackdropPresentation(): void {
    this.cancelBackdropHomeRevealRun();
    this.hideBackdropSnapshot(this.resolveHost());
  }

  prepareBackdropForHomeReveal(): void {
    this.prepareBackdropHomeRevealWithHost(this.resolveHost());
  }

  playBackdropHomeRevealFade(): void {
    this.playBackdropHomeRevealFadeWithHost(this.resolveHost());
  }

  private prepareBackdropSnapshot(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({
      surface: {
        backdropSnapshotVisible: true,
        backdropSnapshotOpacity: 0
      }
    }, host);
  }

  private showBackdropSnapshot(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({
      surface: {
        backdropSnapshotVisible: true,
        backdropSnapshotOpacity: 1
      }
    }, host);
  }

  private prepareBackdropHomeRevealWithHost(host: BrowserTabsOverviewSessionHost): void {
    this.cancelBackdropHomeRevealRun();
    this.updatePresentationState({ surface: { backdropSnapshotOpacity: 1 } }, host);
  }

  private playBackdropHomeRevealFadeWithHost(host: BrowserTabsOverviewSessionHost): void {
    if (!this.presentationState.surface.backdropSnapshotVisible) {
      return;
    }
    const runId = this.beginBackdropHomeRevealRun();
    host.executeEffect({
      type: 'play_tabs_overview_arkui_animation',
      plan: {
        durationMs: this.sharedSnapshotAnimationViewModel.getHomeRevealDurationMs(),
        curve: this.sharedSnapshotAnimationViewModel.getHomeRevealCurve(),
        apply: (): void => {
          if (this.isBackdropHomeRevealRunCurrent(runId)) {
            this.updatePresentationState({ surface: { backdropSnapshotOpacity: 0 } }, host);
          }
        },
        onFinish: (): void => {
          if (this.isBackdropHomeRevealRunCurrent(runId)) {
            this.hideBackdropSnapshot(host);
          }
        }
      }
    });
  }

  private playBackdropProgressTransition(targetProgress: number, host: BrowserTabsOverviewSessionHost): void {
    const safeTargetProgress = this.clampProgress(targetProgress);
    const currentProgress = this.presentationState.surface.backdropProgress;
    const durationMs = safeTargetProgress > currentProgress ?
      this.sharedSnapshotAnimationViewModel.resolveBackdropEntryDurationMs(currentProgress, safeTargetProgress) :
      this.sharedSnapshotAnimationViewModel.resolveBackdropSettleDurationMs(currentProgress, safeTargetProgress);
    const runId = this.beginBackdropSettleRun();
    const applyProgress = (): void => {
      if (this.isBackdropSettleRunCurrent(runId)) {
        this.updatePresentationState({ surface: { backdropProgress: safeTargetProgress } }, host);
      }
    };
    if (durationMs <= 0) {
      applyProgress();
      return;
    }
    host.executeEffect({
      type: 'play_tabs_overview_arkui_animation',
      plan: {
        durationMs: durationMs,
        curve: Curve.Linear,
        apply: applyProgress,
        onFinish: applyProgress
      }
    });
  }

  private hideBackdropSnapshot(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({
      surface: {
        backdropSnapshotVisible: false,
        backdropSnapshotOpacity: 0
      }
    }, host);
  }

  lockTransitionSnapshot(tabId: string): void {
    this.lockTabsOverviewSnapshot(tabId, this.resolveHost());
  }

  private lockTabsOverviewSnapshot(tabId: string, host: BrowserTabsOverviewSessionHost): void {
    this.unlockTabsOverviewSnapshot(host);
    if (tabId.trim().length <= 0) {
      return;
    }
    this.lockedSnapshotTabId = tabId;
    this.previewCoordinator.lockTransitionSnapshot(tabId);
    host.executeEffect({ type: 'notify_tab_preview_changed' });
  }

  private unlockTabsOverviewSnapshot(host: BrowserTabsOverviewSessionHost): void {
    if (this.lockedSnapshotTabId.trim().length <= 0) {
      return;
    }
    this.previewCoordinator.unlockTransitionSnapshot(this.lockedSnapshotTabId);
    this.lockedSnapshotTabId = '';
    host.executeEffect({ type: 'notify_tab_preview_changed' });
  }

  private applySurfacePatch(
    current: BrowserTabsOverviewSurfacePresentationState,
    patch?: BrowserTabsOverviewSurfacePresentationPatch
  ): BrowserTabsOverviewSurfacePresentationState {
    return {
      overlayOpacity: patch?.overlayOpacity ?? current.overlayOpacity,
      backdropProgress: patch?.backdropProgress ?? current.backdropProgress,
      entryMode: patch?.entryMode ?? current.entryMode,
      webEntryProgress: patch?.webEntryProgress ?? current.webEntryProgress,
      homeExitProgress: patch?.homeExitProgress ?? current.homeExitProgress,
      webLayerOpacity: patch?.webLayerOpacity ?? current.webLayerOpacity,
      backdropSnapshotVisible: patch?.backdropSnapshotVisible ?? current.backdropSnapshotVisible,
      backdropSnapshotOpacity: patch?.backdropSnapshotOpacity ?? current.backdropSnapshotOpacity
    };
  }

  private createSharedSnapshotRunId(): number {
    const nextRunId = this.presentationState.sharedSnapshotRunId + 1;
    this.updatePresentationState({ sharedSnapshotRunId: nextRunId }, this.resolveHost());
    return nextRunId;
  }

  resetSharedSnapshotState(): void {
    this.updatePresentationState({ sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState() }, this.resolveHost());
  }

  rememberSharedSnapshotPreviewRect(
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ): void {
    const host = this.resolveHost();
    const rect = this.buildLocalPreviewRect(left, top, width, height, host);
    this.sharedSnapshotTransitionCoordinator.rememberPreviewRect(
      tabId,
      rect.left,
      rect.top,
      rect.width,
      rect.height
    );
    const state = this.presentationState.sharedSnapshotState;
    if (state.tabId === tabId && state.direction !== 'enter' &&
      this.sharedSnapshotTransitionCoordinator.shouldShowOverlay(state)) {
      this.updatePresentationState({
        sharedSnapshotState: this.sharedSnapshotTransitionCoordinator.withTargetRect(state, rect)
      }, host);
    }
  }

  private buildLocalPreviewRect(
    left: number,
    top: number,
    width: number,
    height: number,
    host: BrowserTabsOverviewSessionHost
  ): BrowserTabsOverlayRect {
    const windowFacts = host.readSessionFacts().sharedSnapshotWindow;
    return {
      left: left - windowFacts.rootViewportLeft,
      top: top - windowFacts.rootViewportTop,
      width: width,
      height: height
    };
  }

  rememberSharedSnapshotEntryFrame(rect: BrowserTabsOverlayRect): void {
    this.snapshotPipelineCoordinator.rememberMeasuredEntryFrameForOwner(rect);
  }

  resetSharedSnapshotEntryFrame(): void {
    this.snapshotPipelineCoordinator.resetMeasuredEntryFrameForOwner();
  }

  hasSharedSnapshotEntryVisual(tabId: string): boolean {
    return this.snapshotPipelineCoordinator.hasEntryPixelMapForTab(tabId) ||
      this.sharedSnapshotTransitionCoordinator.buildImageInput(
        this.resolveSharedSnapshotPreviewState(tabId)
      ) !== undefined;
  }

  shouldShowSharedSnapshotOverlay(
    state: BrowserTabsSharedSnapshotTransitionState = this.presentationState.sharedSnapshotState
  ): boolean {
    return this.sharedSnapshotTransitionCoordinator.shouldShowOverlay(state);
  }

  shouldRenderSharedSnapshotEntryOverlay(
    state: BrowserTabsSharedSnapshotTransitionState = this.presentationState.sharedSnapshotState
  ): boolean {
    return this.shouldShowSharedSnapshotOverlay(state) &&
      (state.direction === 'enter' || this.shouldRenderInterruptedSharedSnapshotExit(state));
  }

  private isSharedSnapshotRunCurrent(runId: number): boolean {
    return this.presentationState.sharedSnapshotRunId === runId;
  }

  shouldRenderInterruptedSharedSnapshotExit(
    state: BrowserTabsSharedSnapshotTransitionState = this.presentationState.sharedSnapshotState
  ): boolean {
    const input: BrowserTabsSharedSnapshotInterruptedEntryExitInput = {
      state: state,
      tabsOverlayExiting: this.presentationState.exiting,
      entryAnimationActive: this.presentationState.entryAnimationActive,
      hasEntryPixelMap: this.snapshotPipelineCoordinator.hasEntryPixelMapForTab(state.tabId)
    };
    return this.sharedSnapshotTransitionCoordinator.shouldRenderInterruptedEntryExit(input);
  }

  private shouldAllowSharedSnapshotEntryInterrupt(): boolean {
    const facts = this.resolveHost().readSessionFacts();
    return facts.tabsOverviewMounted &&
      !this.presentationState.exiting &&
      this.presentationState.entryAnimationActive &&
      this.presentationState.sharedSnapshotState.direction === 'enter' &&
      this.sharedSnapshotTransitionCoordinator.shouldShowOverlay(this.presentationState.sharedSnapshotState);
  }

  private publishSharedSnapshotProgress(
    runId: number,
    targetProgress: number,
    host: BrowserTabsOverviewSessionHost
  ): void {
    if (this.presentationState.sharedSnapshotRunId !== runId) {
      return;
    }
    this.updatePresentationState({
      sharedSnapshotState: this.sharedSnapshotTransitionCoordinator.withProgress(
        this.presentationState.sharedSnapshotState,
        targetProgress
      )
    }, host);
  }

  private playSharedSnapshotTransition(
    plan: BrowserTabsOverviewSharedSnapshotAnimationPlan,
    onComplete: () => void,
    host: BrowserTabsOverviewSessionHost
  ): void {
    let completed = false;
    const finishOnce = (): void => {
      if (completed || !this.isSharedSnapshotRunCurrent(plan.runId)) {
        return;
      }
      completed = true;
      onComplete();
    };
    setTimeout(() => {
      if (!this.isSharedSnapshotRunCurrent(plan.runId) || !this.shouldShowSharedSnapshotOverlay()) {
        finishOnce();
        return;
      }
      this.updatePresentationState({
        surface: {
          webLayerOpacity: plan.sourceSurfaceHandoffPatch.webLayerOpacity,
          webEntryProgress: plan.sourceSurfaceHandoffPatch.webEntryProgress
        }
      }, host);
      host.executeEffect({
        type: 'play_tabs_overview_arkui_animation',
        plan: {
          durationMs: plan.durationMs,
          curve: plan.curve,
          apply: (): void => {
            if (this.isSharedSnapshotRunCurrent(plan.runId)) {
              this.publishSharedSnapshotProgress(plan.runId, plan.targetProgress, host);
            }
          },
          onFinish: (): void => {
            setTimeout(finishOnce, plan.handoffDelayMs);
          }
        }
      });
    }, SHARED_SNAPSHOT_MOUNT_DELAY_MS);
    setTimeout(
      finishOnce,
      SHARED_SNAPSHOT_MOUNT_DELAY_MS + plan.durationMs + plan.handoffDelayMs +
        SHARED_SNAPSHOT_COMPLETION_GRACE_MS
    );
    this.scheduleSharedSnapshotChromeReveal(plan, host);
  }

  private scheduleSharedSnapshotChromeReveal(
    plan: BrowserTabsOverviewSharedSnapshotAnimationPlan,
    host: BrowserTabsOverviewSessionHost
  ): void {
    const revealPlan = plan.chromeReveal;
    if (revealPlan === undefined) {
      return;
    }
    setTimeout(() => {
      if (!this.isSharedSnapshotRunCurrent(plan.runId) || !this.shouldShowSharedSnapshotOverlay()) {
        return;
      }
      host.executeEffect({
        type: 'play_tabs_overview_arkui_animation',
        plan: {
          durationMs: revealPlan.durationMs,
          curve: revealPlan.curve,
          apply: (): void => {
            if (this.isSharedSnapshotRunCurrent(plan.runId)) {
              this.updatePresentationState({
                surface: { overlayOpacity: revealPlan.overlayOpacity }
              }, host);
            }
          }
        }
      });
    }, revealPlan.delayMs);
  }

  handleShellKeyEvent(isTabsOverviewVisible: boolean, event: KeyEvent): boolean {
    return this.handle({
      type: 'keyboard',
      command: {
        type: 'shell_key',
        input: {
          isTabsOverviewVisible: isTabsOverviewVisible,
          isKeyDown: event.type === KeyType.Down,
          isKeyUp: event.type === KeyType.Up,
          keyCode: event.keyCode
        }
      }
    })?.handled ?? false;
  }

  handle(action: BrowserTabsOverviewSessionAction): BrowserTabsOverviewKeyboardCommandResult | undefined {
    const host = this.resolveHost();
    switch (action.type) {
      case 'request_open_from_root_bottom_panel':
        this.requestOpenFromRootBottomPanel(action.section, host);
        return;
      case 'request_open':
        void this.openTabsOverview(action.section, host, this.beginOperation());
        return;
      case 'cancel_deferred_open':
        this.cancelDeferredOpen();
        this.invalidateOperations();
        return;
      case 'request_close':
        this.cancelDeferredOpen();
        this.invalidateOperations();
        this.requestCloseTabsOverview(action.targetHeaderMode, host);
        return;
      case 'close_to_home_without_sheet_exit':
        this.invalidateOperations();
        this.closeTabsOverviewToHomeWithoutSheetExit(host);
        return;
      case 'captured_entry_ready':
        this.handleCapturedEntryReady(action.tabId, action.generation, host);
        return;
      case 'entry_target_ready':
        this.handleEntryTargetReady(
          action.tabId,
          this.buildLocalPreviewRect(action.left, action.top, action.width, action.height, host),
          host
        );
        return;
      case 'cancel_shared_snapshot_entry':
        this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.cancel(this.sharedSnapshotEntryState);
        return;
      case 'select_tab':
        void this.finishSelectionFromOverview(action.tabId, host, this.beginOperation());
        return;
      case 'interrupt_entry_selection':
        this.interruptSharedSnapshotEntrySelection(action.tabId, host);
        return;
      case 'dismiss_to_home':
        this.dismissTabsOverviewToHome(host, this.beginOperation());
        return;
      case 'create_home':
        void this.createHomeSurfaceFromTabsOverview(host, this.beginOperation());
        return;
      case 'create_home_tab':
        this.createHomeTabForSurface(
          action.helperMessage,
          action.options,
          action.keepTabsOverviewMounted,
          action.playHomeReveal,
          host
        );
        return;
      case 'enter_private':
        void this.enterPrivateMode(action.helperMessage, action.options, host, this.beginOperation());
        return;
      case 'close_tab':
        void this.closeTabFromOverview(action.tabId, host, this.beginOperation());
        return;
      case 'request_close_all':
        this.requestCloseAllTabs(host, this.beginOperation());
        return;
      case 'confirm_close_all':
        if (this.closeAllConfirmationGeneration < 0 ||
          !this.isOperationCurrent(this.closeAllConfirmationGeneration)) {
          return;
        }
        this.closeAllConfirmationGeneration = -1;
        this.confirmCloseAllTabs(host);
        return;
      case 'close_all_animation_finished':
        void this.finishCloseAllTabsAfterOverviewAnimation(host, this.beginOperation());
        return;
      case 'change_section':
        void this.changeSection(action.section, host, this.beginOperation());
        return;
      case 'activate_section_home':
        this.activateSectionHome(action.section, host, this.beginOperation());
        return;
      case 'keyboard':
        return this.handleKeyboardCommand(action.command);
    }
  }

  private selectTab(tabId: string): Promise<void> {
    return this.finishSelectionFromOverview(tabId, this.resolveHost(), this.beginOperation());
  }

  revealHomeSurfaceAfterTabClose(
    helperMessage: string,
    homeOptions: BrowserCreateTabOptions,
    homeRevealMotion: BrowserTabsOverviewHomeRevealMotion
  ): Promise<void> {
    return this.revealHomeSurfaceFromTabsOverview(
      helperMessage,
      homeOptions,
      homeRevealMotion,
      this.resolveHost(),
      this.beginOperation()
    );
  }

  private handleKeyboardCommand(command: BrowserTabsOverviewKeyboardCommand): BrowserTabsOverviewKeyboardCommandResult {
    switch (command.type) {
      case 'number_shortcut':
        this.keyboardCoordinator.handleNumberShortcut(command.digit, this.keyboardHost);
        return { handled: true, tabId: '' };
      case 'resolve_numbered_tab':
        return {
          handled: true,
          tabId: this.keyboardCoordinator.resolveNumberedTabId(command.tabs, command.digit)
        };
      case 'shell_key':
        return {
          handled: this.keyboardCoordinator.handleShellKeyEvent(command.input, this.keyboardHost),
          tabId: ''
        };
    }
  }

  private resetKeyboardSelectionForOpening(): void {
    this.keyboardCoordinator.resetSelectionForOpening(this.keyboardHost);
  }

  // A tab counts as the HOME surface only if it is the new-tab/home page — NOT a
  // native surface tab (settings/bookmarks/history/…), which TabManager also
  // flags isHome=true. Native surfaces must open the overview like a normal
  // content tab (capture the visible surface), not via the home-surface branch,
  // which bails when the home surface is not actually on screen — that was why
  // tapping the tabs button did nothing from a settings/bookmarks/history tab.
  private isHomeSurfaceTab(tab: BrowserTabState | undefined): boolean {
    if (tab === undefined || !tab.isHome) {
      return false;
    }
    return browserNativeTabSceneService.resolveSceneForTab(tab.url, tab.pendingUrl) === undefined;
  }

  private shouldOpenFromHomeSurface(input: BrowserTabsOverviewPrimarySurfaceInput): boolean {
    return input.showHomePage || input.activeTabIsHome;
  }

  buildRenderState(
    presentationState: BrowserTabsOverviewSessionPresentationState = this.presentationState
  ): BrowserTabsOverviewSceneRenderState {
    const facts = this.resolveHost().readSessionFacts();
    return this.sceneDriver.buildRenderState({
      sceneState: presentationState.sceneState,
      showHomePage: facts.homeSurfaceVisible,
      showTabsSheet: facts.tabsOverviewMounted,
      keepHomeResident: facts.keepHomeResident,
      sharedSnapshotOverlayVisible: this.shouldShowSharedSnapshotOverlay(presentationState.sharedSnapshotState)
    });
  }

  buildBackgroundRenderState(
    input: BrowserTabsOverviewBackgroundRenderInput
  ): BrowserTabsOverviewBackgroundRenderState {
    const overviewBackdropVisible = input.snapshotVisible &&
      this.shouldShowOverviewBackdrop(input) && this.shouldUseSeparateOverviewBackdrop(input);
    return {
      homeBackdropVisible: overviewBackdropVisible,
      homeBackdropOpacity: overviewBackdropVisible ? this.clampProgress(input.snapshotOpacity) : 0,
      homeBackdropEffectProgress: overviewBackdropVisible ? this.clampProgress(input.backdropProgress) : 0,
      floatingGlassOpacity: this.resolveFloatingGlassOpacity(input)
    };
  }

  projectScene(currentSceneState: BrowserTabsOverviewSceneState): BrowserTabsOverviewSceneProjection {
    const sharedSnapshotState = this.presentationState.sharedSnapshotState;
    const selectionMorphAnimating = sharedSnapshotState.direction === 'exit' &&
      sharedSnapshotState.phase === 'exitAnimating' &&
      sharedSnapshotState.tabId === currentSceneState.morphCoveredTabId;
    return {
      galleryCoveredTabId: this.sceneDriver.resolveGalleryCoveredTabId(currentSceneState),
      selectionDisplacementTabId: this.sceneDriver.resolveSelectionDisplacementTabId(
        currentSceneState,
        selectionMorphAnimating
      ),
      entryDisplacementTabId: this.sceneDriver.resolveEntryDisplacementTabId(currentSceneState),
      entryDisplacementSettlingEnabled: this.sceneDriver.shouldSettleEntryDisplacement(currentSceneState),
      sideEntryAnimationEnabled: this.sceneDriver.shouldRunSideCardEntryAnimation(currentSceneState)
    };
  }

  private requestOpen(input: BrowserTabsOverviewSessionOpenRequestInput): BrowserTabsOverviewSessionOpenPlan {
    const activeSection = this.normalizeSection(input.activeSection);
    if (input.showTabsSheet && !input.tabsOverlayExiting) {
      return this.buildPlan('ignore', activeSection, false, 0);
    }
    if (input.rootBottomPanelDetent === 'middle') {
      return this.buildPlan(
        'collapse_then_open',
        activeSection,
        true,
        TABS_OVERVIEW_OPEN_AFTER_COLLAPSE_DELAY_MS
      );
    }
    return this.buildPlan('open_now', activeSection, false, 0);
  }

  private requestOpenFromRootBottomPanel(
    section: BrowserTabsOverviewSessionSection,
    host: BrowserTabsOverviewSessionHost
  ): void {
    host.executeEffect({ type: 'cancel_bottom_panel_backdrop_focus_transition' });
    const facts = host.readSessionFacts();
    const openPlan = this.requestOpen({
      activeSection: section,
      showTabsSheet: facts.tabsOverviewMounted,
      tabsOverlayExiting: this.presentationState.exiting,
      rootBottomPanelDetent: facts.rootBottomPanelDetent
    });
    if (openPlan.kind === 'ignore') {
      return;
    }
    if (openPlan.kind === 'collapse_then_open') {
      this.collapseExpandedRootBottomPanelForOpen(host);
      this.scheduleDeferredOpen(openPlan.activeSection, openPlan.openDelayMs, host);
      return;
    }
    this.cancelDeferredOpen();
    void this.openTabsOverview(openPlan.activeSection, host, this.beginOperation());
  }

  private async openTabsOverview(
    section: BrowserTabsOverviewSessionSection,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    let facts = host.readSessionFacts();
    if (!this.isOperationCurrent(generation) || (facts.tabsOverviewMounted && !this.presentationState.exiting)) {
      return;
    }
    this.prepareOpenAfterInterruptedSharedSnapshot(host);
    facts = host.readSessionFacts();
    const activeTabIdAtOpen = facts.activeTabId;
    const openedFromHome = this.shouldOpenFromHomeSurface({
      showHomePage: facts.homeSurfaceVisible,
      activeTabIsHome: this.isHomeSurfaceTab(facts.tabs.find((tab: BrowserTabState) => tab.id === activeTabIdAtOpen))
    });
    const initialSection = this.resolveInitialSection(section, host);
    if (initialSection === 'privacy' && !await this.ensurePrivateModeUnlocked(
      'private',
      'session_ephemeral',
      'tabs_overview_private_section'
    )) {
      return;
    }
    if (!this.isPendingOpenCurrent(generation, activeTabIdAtOpen, openedFromHome, host)) {
      return;
    }
    if (!openedFromHome || !this.hasSharedSnapshotEntryVisual(activeTabIdAtOpen)) {
      this.snapshotPipelineCoordinator.releaseSession();
    }
    if (!openedFromHome) {
      host.executeEffect({ type: 'flush_scroll_deferred_page_metadata', tabId: activeTabIdAtOpen });
    }
    this.updatePresentationState({ activeSection: initialSection }, host);
    this.resetKeyboardSelectionForOpening();
    host.executeEffect({ type: 'refresh_tabs_sheet_appearance' });
    if (openedFromHome && !this.shouldContinueHomeSurfaceOpen(activeTabIdAtOpen, host)) {
      return;
    }
    if (!openedFromHome) {
      await this.openFromActiveWebTab(activeTabIdAtOpen, host, generation);
      return;
    }
    this.prepareBackdropSnapshot(host);
    if (!this.isPendingOpenCurrent(generation, activeTabIdAtOpen, true, host)) {
      return;
    }
    facts = host.readSessionFacts();
    if (facts.activeTabId !== activeTabIdAtOpen || !facts.homeSurfaceVisible || facts.tabsOverviewMounted) {
      return;
    }
    this.playTabsOverviewEntryAnimation(true, host, generation);
    void this.restorePersistedTabPreviews();
  }

  private handleCapturedEntryReady(
    tabId: string,
    generation: number,
    host: BrowserTabsOverviewSessionHost
  ): void {
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    const facts = host.readSessionFacts();
    if (!this.sceneDriver.shouldProcessCapturedEntry(this.presentationState.sceneState, {
      tabId: tabId,
      showTabsSheet: facts.tabsOverviewMounted,
      tabsOverlayExiting: this.presentationState.exiting,
      hasEntryPixelMap: this.hasSharedSnapshotEntryVisual(tabId)
    })) {
      return;
    }
    this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.beginTargetPreparationAfterCapturedEntry(
      this.sharedSnapshotEntryState,
      tabId
    );
    const currentSceneState = this.presentationState.sceneState;
    const nextSceneState = this.sceneDriver.buildEntrySnapshotReadyState(currentSceneState, tabId);
    this.updatePresentationState({ sceneState: nextSceneState }, host);
    this.tryStartPreparedSharedSnapshotEnter(tabId, host);
  }

  private handleEntryTargetReady(
    tabId: string,
    targetRect: BrowserTabsOverlayRect,
    host: BrowserTabsOverviewSessionHost
  ): void {
    const facts = host.readSessionFacts();
    const sceneResult = this.sceneDriver.buildActiveCardRectReadyState(
      this.presentationState.sceneState,
      tabId,
      targetRect
    );
    this.updatePresentationState({ sceneState: sceneResult.state }, host);
    if (!sceneResult.shouldStartMorph || !facts.tabsOverviewMounted || this.presentationState.exiting ||
      !this.sharedSnapshotEntryCoordinator.shouldAcceptTargetReady(this.sharedSnapshotEntryState, tabId)) {
      return;
    }
    this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.markTargetReady(
      this.sharedSnapshotEntryState,
      {
        tabId: tabId,
        targetRect: targetRect
      }
    );
    this.tryStartPreparedSharedSnapshotEnter(tabId, host);
  }

  private tryStartPreparedSharedSnapshotEnter(tabId: string, host: BrowserTabsOverviewSessionHost): void {
    if (!this.sharedSnapshotEntryCoordinator.shouldStartSnapshotEnter(this.sharedSnapshotEntryState) ||
      !this.hasSharedSnapshotEntryVisual(tabId)) {
      return;
    }
    const targetRect = this.sharedSnapshotEntryCoordinator.resolveTargetRect(this.sharedSnapshotEntryState);
    if (targetRect === undefined) {
      return;
    }
    this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.markAnimating(this.sharedSnapshotEntryState);
    const transitionPlan = this.buildSharedSnapshotEnterPlan(tabId, targetRect, host);
    if (transitionPlan === undefined) {
      this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.cancel(this.sharedSnapshotEntryState);
      this.resetSharedSnapshotState();
      return;
    }
    this.playSharedSnapshotTransition(transitionPlan, (): void => {
      this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.finish();
      this.updatePresentationState({
        sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState()
      }, host);
      this.snapshotPipelineCoordinator.resetMeasuredEntryFrameForOwner();
      this.updatePresentationState({
        sceneState: this.sceneDriver.buildSettledState(this.presentationState.sceneState)
      }, host);
    }, host);
  }

  private buildSelectionVisualFacts(
    tabId: string,
    facts: BrowserTabsOverviewSessionFacts
  ): BrowserTabsOverviewSelectionVisualFacts {
    const webRect = this.buildSharedSnapshotWebRect(facts.sharedSnapshotWindow);
    return {
      morphSource: this.snapshotPipelineCoordinator.resolveExitMorphSourceForOwner({
        tabId: tabId,
        fallbackWebRect: webRect,
        showHomePage: facts.sharedSnapshotWindow.showHomePage,
        capturedAt: Date.now()
      }),
      hostedWebLayerMeasured: facts.sharedSnapshotWindow.hostedWebLayerMeasured,
      reusableGeometry: facts.sharedSnapshotWindow.reusableGeometry,
      webRect: webRect
    };
  }

  private resolveSharedSnapshotPreviewState(tabId: string): BrowserTabPreviewState | undefined {
    return this.snapshotPipelineCoordinator.buildTransitionPreviewStateForTab(tabId, Date.now());
  }

  private buildSharedSnapshotWebRect(
    facts: BrowserTabsOverviewSharedSnapshotWindowFacts
  ): BrowserTabsOverlayRect {
    return this.snapshotPipelineCoordinator.buildWebRect({
      showHomePage: facts.showHomePage,
      rootViewportWidth: facts.rootViewportWidth,
      rootViewportHeight: facts.rootViewportHeight,
      visualTopInset: facts.showHomePage ? 0 : facts.webVisualTopInset,
      bottomInset: this.resolveSharedSnapshotBottomInset(facts),
      hostedWebLayerMeasured: facts.hostedWebLayerMeasured,
      hostedWebLayerLeft: facts.hostedWebLayerLeft,
      hostedWebLayerTop: facts.hostedWebLayerTop,
      hostedWebLayerWidth: facts.hostedWebLayerWidth,
      hostedWebLayerHeight: facts.hostedWebLayerHeight,
      reusableGeometry: facts.reusableGeometry
    });
  }

  private resolveSharedSnapshotBottomInset(facts: BrowserTabsOverviewSharedSnapshotWindowFacts): number {
    if (!facts.showHomePage && facts.webAppImmersiveMode) {
      return 0;
    }
    return Math.max(0, Math.ceil(facts.bottomSafeInsetVp));
  }

  private buildSharedSnapshotWindowInput(
    facts: BrowserTabsOverviewSharedSnapshotWindowFacts,
    morphSource: BrowserTabsOverviewSnapshotMorphSource
  ): BrowserTabsSharedSnapshotWindowInput {
    return {
      rootWidth: facts.rootViewportWidth,
      rootHeight: facts.rootViewportHeight,
      webLeft: morphSource.sourceRect.left,
      webTop: morphSource.sourceRect.top,
      visualWebTop: morphSource.sourceRect.top,
      webWidth: morphSource.sourceRect.width,
      webHeight: morphSource.sourceRect.height,
      bottomInset: 0,
      sourceImageTopInset: morphSource.sourceImageTopInset
    };
  }

  private buildSharedSnapshotTargetInput(
    tabId: string,
    facts: BrowserTabsOverviewSessionFacts,
    measuredRect?: BrowserTabsOverlayRect
  ): BrowserTabsSharedSnapshotTargetRectInput {
    return {
      tabs: facts.tabs,
      tabId: tabId,
      measuredRect: measuredRect,
      rootWidth: facts.sharedSnapshotWindow.rootViewportWidth,
      rootHeight: facts.sharedSnapshotWindow.rootViewportHeight,
      topSafeInset: facts.sharedSnapshotWindow.topSafeInsetVp
    };
  }

  private buildSharedSnapshotEnterPlan(
    tabId: string,
    preparedTargetRect: BrowserTabsOverlayRect,
    host: BrowserTabsOverviewSessionHost
  ): BrowserTabsOverviewSharedSnapshotAnimationPlan | undefined {
    const runId = this.createSharedSnapshotRunId();
    const facts = host.readSessionFacts();
    const windowFacts = facts.sharedSnapshotWindow;
    const morphSource = this.snapshotPipelineCoordinator.resolveEntryMorphSourceForOwner({
      tabId: tabId,
      fallbackWebRect: this.buildSharedSnapshotWebRect(windowFacts),
      showHomePage: windowFacts.showHomePage,
      capturedAt: Date.now()
    });
    const currentState = this.presentationState.sharedSnapshotState;
    let state: BrowserTabsSharedSnapshotTransitionState | undefined = undefined;
    if (currentState.tabId === tabId && currentState.direction === 'enter' &&
      this.sharedSnapshotTransitionCoordinator.shouldShowOverlay(currentState)) {
      state = this.sharedSnapshotTransitionCoordinator.withTargetRect(currentState, preparedTargetRect);
    } else {
      state = this.sharedSnapshotTransitionCoordinator.buildEnterStateFromContext(
        tabId,
        morphSource.previewState,
        this.buildSharedSnapshotWindowInput(windowFacts, morphSource),
        this.buildSharedSnapshotTargetInput(tabId, facts, preparedTargetRect),
        BROWSER_TABS_OVERVIEW_CARD_CORNER_RADIUS,
        0
      );
    }
    if (state === undefined) {
      this.updatePresentationState({ sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState() }, host);
      return undefined;
    }
    this.previewCoordinator.recordTransitionImageUse(tabId, 'enter');
    this.updatePresentationState({ sharedSnapshotState: state }, host);
    this.snapshotPipelineCoordinator.resetMeasuredEntryFrameForOwner();
    return this.buildSharedSnapshotAnimationPlan(
      state,
      runId,
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotEnterDurationMs(),
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotEnterCurve(),
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotEnterHandoffDelayMs(),
      false
    );
  }

  private buildSharedSnapshotExitPlan(
    tabId: string,
    facts: BrowserTabsOverviewSessionFacts,
    visualFacts: BrowserTabsOverviewSelectionVisualFacts,
    host: BrowserTabsOverviewSessionHost
  ): BrowserTabsOverviewSharedSnapshotAnimationPlan | undefined {
    const runId = this.createSharedSnapshotRunId();
    const windowFacts = facts.sharedSnapshotWindow;
    const previewState = visualFacts.morphSource.previewState;
    const state = this.sharedSnapshotTransitionCoordinator.buildExitStateFromContext(
      tabId,
      previewState,
      this.buildSharedSnapshotWindowInput(windowFacts, visualFacts.morphSource),
      this.buildSharedSnapshotTargetInput(tabId, facts),
      BROWSER_TABS_OVERVIEW_CARD_CORNER_RADIUS,
      0
    );
    if (state === undefined) {
      host.executeEffect({
        type: 'record_session_trace',
        traceType: 'shared_snapshot_exit_missing',
        message: this.selectionPolicy.buildSharedSnapshotExitAnimationDiagnostic(
          tabId,
          previewState,
          visualFacts.webRect,
          { left: 0, top: 0, width: 0, height: 0 },
          { left: 0, top: 0, width: 0, height: 0 },
          false,
          0,
          0
        ),
        tabId: tabId
      });
      this.updatePresentationState({ sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState() }, host);
      return undefined;
    }
    host.executeEffect({
      type: 'record_session_trace',
      traceType: 'shared_snapshot_exit_start',
      message: this.selectionPolicy.buildSharedSnapshotExitAnimationDiagnostic(
        tabId,
        previewState,
        visualFacts.webRect,
        state.sourceRect,
        state.targetRect,
        state.useFullWebSnapshot,
        state.imageWidth,
        state.imageHeight
      ),
      tabId: tabId
    });
    this.previewCoordinator.recordTransitionImageUse(tabId, 'exit');
    this.snapshotPipelineCoordinator.resetMeasuredEntryFrameForOwner();
    return this.buildSharedSnapshotAnimationPlan(
      state,
      runId,
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitDurationMs(),
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitCurve(),
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitHandoffDelayMs(),
      true
    );
  }

  private buildInterruptedSharedSnapshotExitPlan(
    tabId: string,
    host: BrowserTabsOverviewSessionHost
  ): BrowserTabsOverviewSharedSnapshotAnimationPlan | undefined {
    const runId = this.createSharedSnapshotRunId();
    const currentState = this.presentationState.sharedSnapshotState;
    const targetRect = this.sharedSnapshotTransitionCoordinator.buildInterruptedEntryExitTargetRect(
      currentState,
      this.snapshotPipelineCoordinator.getMeasuredEntryFrameForOwner()
    );
    const state = this.sharedSnapshotTransitionCoordinator.buildExitStateFromInterruptedEnter(
      currentState,
      targetRect
    );
    if (state === undefined) {
      return undefined;
    }
    const durationMs = this.sharedSnapshotTransitionCoordinator.resolveInterruptedEntryExitDurationMs(
      currentState,
      targetRect,
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitDurationMs()
    );
    const handoffDelayMs = Math.min(
      40,
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitHandoffDelayMs()
    );
    this.previewCoordinator.recordTransitionImageUse(tabId, 'exit');
    this.snapshotPipelineCoordinator.resetMeasuredEntryFrameForOwner();
    return this.buildSharedSnapshotAnimationPlan(
      state,
      runId,
      durationMs,
      this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitCurve(),
      handoffDelayMs,
      true
    );
  }

  private buildSharedSnapshotAnimationPlan(
    state: BrowserTabsSharedSnapshotTransitionState,
    runId: number,
    durationMs: number,
    curve: Curve | string | ICurve,
    handoffDelayMs: number,
    revealChrome: boolean
  ): BrowserTabsOverviewSharedSnapshotAnimationPlan {
    const chromeReveal = revealChrome ? this.buildSharedSnapshotChromeRevealPlan(durationMs) : undefined;
    return {
      runId: runId,
      initialState: state,
      durationMs: durationMs,
      curve: curve,
      targetProgress: 1,
      handoffDelayMs: handoffDelayMs,
      sourceSurfaceHandoffPatch: this.hostedWebLayerPresentationViewModel
        .buildSharedSnapshotSourceSurfaceHandoffPatch(state.direction),
      chromeReveal: chromeReveal
    };
  }

  private buildSharedSnapshotChromeRevealPlan(durationMs: number): BrowserTabsOverviewSharedSnapshotChromeRevealPlan {
    const revealDurationMs = this.sharedSnapshotAnimationViewModel.getWebChromeSelectionRevealDurationMs();
    return {
      delayMs: Math.max(0, durationMs - revealDurationMs -
        this.sharedSnapshotAnimationViewModel.getSharedSnapshotExitHandoffDelayMs()),
      durationMs: revealDurationMs,
      curve: this.sharedSnapshotAnimationViewModel.getWebChromeSelectionRevealCurve(),
      overlayOpacity: this.sharedSnapshotAnimationViewModel.getSelectionSheetReleasedOpacity()
    };
  }

  private interruptSharedSnapshotEntrySelection(
    tabId: string,
    host: BrowserTabsOverviewSessionHost
  ): void {
    if (!this.shouldAllowSharedSnapshotEntryInterrupt() ||
      tabId !== this.presentationState.sharedSnapshotState.tabId) {
      return;
    }
    host.executeEffect({
      type: 'record_session_trace',
      traceType: 'shared_snapshot_enter_interrupted',
      message: `progress=${this.presentationState.sharedSnapshotState.progress} ` +
        `measured=${this.snapshotPipelineCoordinator.isEntryFrameMeasuredForOwner()}`,
      tabId: tabId
    });
    this.interruptedSelectionCompletionGeneration = this.beginOperation();
    const transitionPlan = this.buildInterruptedSharedSnapshotExitPlan(tabId, host);
    if (transitionPlan === undefined) {
      this.beginSelectionPanelExit(tabId, host);
      this.finishInterruptedSharedSnapshotSelection(host);
      return;
    }
    this.beginSelectionPanelExit(tabId, host, transitionPlan.initialState);
    this.playSharedSnapshotTransition(transitionPlan, (): void => {
      this.updatePresentationState({
        sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState()
      }, host);
      this.finishInterruptedSharedSnapshotSelection(host);
    }, host);
  }

  private finishInterruptedSharedSnapshotSelection(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({ surface: { webLayerOpacity: 1 } }, host);
    if (!this.isInterruptedSelectionCompletionCurrent()) {
      return;
    }
    this.interruptedSelectionCompletionGeneration = -1;
    this.completeTabsOverviewSelectionClose(host);
  }

  private resetSharedSnapshotSession(
    plan: BrowserTabsOverviewSessionResetPlan,
    host: BrowserTabsOverviewSessionHost
  ): void {
    if (plan.entryStateReset === 'cancel') {
      this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.cancel(this.sharedSnapshotEntryState);
    } else if (plan.entryStateReset === 'finish') {
      this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.finish();
    }
    if (plan.createSharedSnapshotRunId || plan.resetSharedSnapshotTransition || plan.bumpAnimationVersion) {
      this.updatePresentationState({
        animationVersion: plan.bumpAnimationVersion ?
          this.presentationState.animationVersion + 1 : this.presentationState.animationVersion,
        sharedSnapshotRunId: plan.createSharedSnapshotRunId ?
          this.presentationState.sharedSnapshotRunId + 1 : this.presentationState.sharedSnapshotRunId,
        sharedSnapshotState: plan.resetSharedSnapshotTransition ?
          buildBrowserTabsSharedSnapshotIdleState() : this.presentationState.sharedSnapshotState
      }, host);
    }
    if (plan.resetEntrySnapshotFrame) {
      this.resetSharedSnapshotEntryFrame();
    }
    if (plan.releaseEntrySnapshot) {
      this.snapshotPipelineCoordinator.releaseSession();
    }
  }

  private requestCloseTabsOverview(
    targetHeaderMode: BrowserTabsOverviewHeaderMode | undefined,
    host: BrowserTabsOverviewSessionHost
  ): void {
    const facts = host.readSessionFacts();
    if (!facts.tabsOverviewMounted || this.presentationState.exiting) {
      return;
    }
    const closePlan = this.sceneDriver.buildClosePlan(
      this.presentationState.sceneState,
      facts.homeSurfaceVisible,
      targetHeaderMode
    );
    const animationVersion = this.presentationState.animationVersion + 1;
    this.updatePresentationState({
      animationVersion: animationVersion,
      entryAnimationActive: closePlan.entryAnimationActive,
      headerMode: closePlan.headerMode,
      exiting: closePlan.exiting,
      homeSurfaceCloseInFlight: false,
      sceneState: closePlan.sceneState
    }, host);
    this.resetSharedSnapshotSession({
      createSharedSnapshotRunId: true,
      resetSharedSnapshotTransition: true,
      resetEntrySnapshotFrame: true,
      releaseEntrySnapshot: false,
      bumpAnimationVersion: false,
      entryStateReset: 'cancel'
    }, host);
    const exitDurationMs = this.sharedSnapshotAnimationViewModel.getExitDurationMs();
    host.executeEffect({
      type: 'play_tabs_overview_arkui_animation',
      plan: {
        durationMs: exitDurationMs,
        curve: this.sharedSnapshotAnimationViewModel.getExitCurve(),
        apply: (): void => {
          if (this.presentationState.animationVersion === animationVersion) {
            this.updatePresentationState({ surface: { overlayOpacity: 0 } }, host);
          }
        }
      }
    });
    setTimeout(() => {
      if (this.presentationState.animationVersion === animationVersion) {
        this.applyClosedOverviewReset('tabs-overview-exit', true, host);
      }
    }, exitDurationMs + 24);
    this.playBackdropProgressTransition(0, host);
  }

  private closeTabsOverviewToHomeWithoutSheetExit(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({ headerMode: 'home' }, host);
    if (!host.readSessionFacts().tabsOverviewMounted) {
      this.applyClosedOverviewReset('tabs-overview-home-close', false, host);
      return;
    }
    this.resetSharedSnapshotSession({
      createSharedSnapshotRunId: true,
      resetSharedSnapshotTransition: true,
      resetEntrySnapshotFrame: true,
      releaseEntrySnapshot: true,
      bumpAnimationVersion: true,
      entryStateReset: 'cancel'
    }, host);
    this.applyClosedOverviewReset('tabs-overview-home-close', false, host);
  }

  private completeTabsOverviewSelectionClose(host: BrowserTabsOverviewSessionHost): void {
    this.resetSharedSnapshotSession({
      createSharedSnapshotRunId: true,
      resetSharedSnapshotTransition: true,
      resetEntrySnapshotFrame: false,
      releaseEntrySnapshot: true,
      bumpAnimationVersion: true,
      entryStateReset: 'finish'
    }, host);
    this.applyClosedOverviewReset('tabs-overview-selection-close', false, host);
  }

  private cancelEntrySnapshotForHomeSurfaceClose(reason: string, host: BrowserTabsOverviewSessionHost): void {
    const facts = host.readSessionFacts();
    const state = this.presentationState.sharedSnapshotState;
    if (state.direction !== 'enter' || !this.shouldShowSharedSnapshotOverlay()) {
      return;
    }
    host.executeEffect({
      type: 'record_session_trace',
      traceType: 'shared_snapshot_enter_cancelled_for_home_close',
      message: `reason=${reason} progress=${state.progress}`,
      tabId: state.tabId.length > 0 ? state.tabId : facts.activeTabId
    });
    this.resetSharedSnapshotSession({
      createSharedSnapshotRunId: true,
      resetSharedSnapshotTransition: true,
      resetEntrySnapshotFrame: true,
      releaseEntrySnapshot: false,
      bumpAnimationVersion: true,
      entryStateReset: 'cancel'
    }, host);
    this.updatePresentationState({
      entryAnimationActive: false,
      surface: {
        webLayerOpacity: 1,
        webEntryProgress: 1
      }
    }, host);
  }

  private scheduleDeferredOpen(
    section: BrowserTabsOverviewSessionSection,
    delayMs: number,
    host: BrowserTabsOverviewSessionHost
  ): void {
    this.cancelDeferredOpen();
    const generation = this.beginOperation();
    this.deferredOpenTimer = setTimeout(() => {
      this.deferredOpenTimer = -1;
      if (!this.isOperationCurrent(generation) ||
        (host.readSessionFacts().tabsOverviewMounted && !this.presentationState.exiting)) {
        return;
      }
      void this.openTabsOverview(this.normalizeSection(section), host, generation);
    }, Math.max(0, Math.round(delayMs)));
  }

  private cancelDeferredOpen(): void {
    if (this.deferredOpenTimer < 0) {
      return;
    }
    clearTimeout(this.deferredOpenTimer);
    this.deferredOpenTimer = -1;
  }

  private async openFromActiveWebTab(
    activeTabIdAtOpen: string,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    const facts = host.readSessionFacts();
    const tab = facts.tabs.find((candidate: BrowserTabState) => candidate.id === activeTabIdAtOpen);
    if (tab === undefined || this.isHomeSurfaceTab(tab) || activeTabIdAtOpen.trim().length <= 0 || facts.homeSurfaceVisible) {
      return;
    }
    const capturedFreshPreview = await this.captureFreshActiveTabPreview(tab, generation, host);
    if (!this.isPendingOpenCurrent(generation, activeTabIdAtOpen, false, host)) {
      return;
    }
    const postCaptureFacts = host.readSessionFacts();
    if (!capturedFreshPreview || postCaptureFacts.activeTabId !== activeTabIdAtOpen ||
      postCaptureFacts.homeSurfaceVisible || postCaptureFacts.tabsOverviewMounted) {
      if (!capturedFreshPreview && postCaptureFacts.activeTabId === activeTabIdAtOpen && !postCaptureFacts.homeSurfaceVisible) {
        host.executeEffect({ type: 'show_native_toast', message: '网页截图生成失败，请重试。' });
      }
      return;
    }
    this.lockTabsOverviewSnapshot(activeTabIdAtOpen, host);
    this.prepareBackdropSnapshot(host);
    if (!this.isPendingOpenCurrent(generation, activeTabIdAtOpen, false, host)) {
      return;
    }
    if (this.debugSnapshotExportEnabled) {
      host.executeEffect({ type: 'export_tabs_overview_debug_snapshot', tabId: activeTabIdAtOpen });
    }
    this.playTabsOverviewEntryAnimation(false, host, generation);
    void this.restorePersistedTabPreviews();
  }

  private playTabsOverviewEntryAnimation(
    openedFromHome: boolean,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): void {
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    const facts = host.readSessionFacts();
    const entryPlan = this.sceneDriver.buildEntryRunPlan(
      openedFromHome,
      facts.activeTabId,
      facts.backdropOpenStartProgress
    );
    const animationVersion = this.presentationState.animationVersion + 1;
    this.updatePresentationState({
      animationVersion: animationVersion,
      entryAnimationActive: entryPlan.entryAnimationActive,
      headerMode: entryPlan.headerMode,
      exiting: entryPlan.exiting,
      sceneState: entryPlan.sceneState,
      homeSurfaceCloseInFlight: false,
      surface: {
        entryMode: entryPlan.overlayPatch.entryMode,
        webEntryProgress: entryPlan.overlayPatch.webEntryProgress,
        homeExitProgress: entryPlan.homeExitProgress,
        overlayOpacity: entryPlan.overlayPatch.overlayOpacity,
        webLayerOpacity: entryPlan.overlayPatch.webLayerOpacity,
        backdropProgress: entryPlan.overlayPatch.backdropProgress
      }
    }, host);
    if (entryPlan.shouldResetEntrySnapshotFrame) {
      this.snapshotPipelineCoordinator.resetMeasuredEntryFrameForOwner();
    }
    host.executeEffect({
      type: 'apply_tabs_overview_entry_shell_state',
      shouldResetHomeReveal: entryPlan.shouldResetHomeReveal,
      shouldShowTabsSheet: entryPlan.shouldShowTabsSheet
    });
    this.fixedDependencies.webTopImmersionSessionCoordinator.requestVisible(entryPlan.statusBarReason);
    if (entryPlan.shouldHideBackgroundOpenPrompt) {
      this.fixedDependencies.backgroundOpenPromptCoordinator.dismissAll();
    }
    this.showBackdropSnapshot(host);
    if (entryPlan.shouldFinishSharedSnapshotEntry) {
      this.resetSharedSnapshotSession({
        createSharedSnapshotRunId: false,
        resetSharedSnapshotTransition: false,
        resetEntrySnapshotFrame: false,
        releaseEntrySnapshot: false,
        bumpAnimationVersion: false,
        entryStateReset: 'finish'
      }, host);
    }
    if (entryPlan.shouldCreateSharedSnapshotRunId) {
      this.resetSharedSnapshotSession({
        createSharedSnapshotRunId: true,
        resetSharedSnapshotTransition: true,
        resetEntrySnapshotFrame: false,
        releaseEntrySnapshot: false,
        bumpAnimationVersion: false,
        entryStateReset: 'keep'
      }, host);
    } else if (entryPlan.shouldClearSharedSnapshotIfHidden && !this.shouldShowSharedSnapshotOverlay()) {
      this.resetSharedSnapshotSession({
        createSharedSnapshotRunId: false,
        resetSharedSnapshotTransition: true,
        resetEntrySnapshotFrame: false,
        releaseEntrySnapshot: false,
        bumpAnimationVersion: false,
        entryStateReset: 'keep'
      }, host);
    }
    if (entryPlan.shouldPrepareActiveCardTarget) {
      this.handleCapturedEntryReady(entryPlan.sceneState.activeTabIdAtOpen, generation, host);
    }
    host.executeEffect({ type: 'sync_bottom_panel_status_bar_style' });
    this.scheduleTabsOverviewEntrySettleFallback(entryPlan, animationVersion, host, generation);
    this.scheduleTabsOverviewEntryBackdropTransition(animationVersion, host);
    this.scheduleTabsOverviewEntryWebReveal(animationVersion, host, generation);
  }

  private scheduleTabsOverviewEntryBackdropTransition(
    animationVersion: number,
    host: BrowserTabsOverviewSessionHost
  ): void {
    setTimeout(() => {
      if (this.isEntryAnimationCurrent(animationVersion, host)) {
        this.playBackdropProgressTransition(1, host);
      }
    }, this.sharedSnapshotAnimationViewModel.getEntryStartDelayMs());
  }

  private scheduleTabsOverviewEntryWebReveal(
    animationVersion: number,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): void {
    setTimeout(() => {
      if (!this.isEntryAnimationCurrent(animationVersion, host)) {
        return;
      }
      host.executeEffect({
        type: 'play_tabs_overview_arkui_animation',
        plan: {
          durationMs: this.sharedSnapshotAnimationViewModel.getHomeRevealDurationMs(),
          curve: this.sharedSnapshotAnimationViewModel.getHomeEntryCurve(),
          apply: (): void => {
            if (this.isEntryAnimationCurrent(animationVersion, host)) {
              this.updatePresentationState({ surface: { webEntryProgress: 1 } }, host);
            }
          },
          onFinish: (): void => {
            this.recoverWebLayerOpacityAfterStaleEntryAnimation(animationVersion, host);
          }
        }
      });
      setTimeout(() => {
        if (this.isOperationCurrent(generation) && this.isEntryAnimationCurrent(animationVersion, host)) {
          this.settleTabsOverviewEntryAnimation(host);
        }
      }, this.sharedSnapshotAnimationViewModel.getHomeRevealSettleDelayMs());
    }, this.sharedSnapshotAnimationViewModel.getEntryStartDelayMs());
  }

  private isEntryAnimationCurrent(
    animationVersion: number,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    const facts = host.readSessionFacts();
    return this.presentationState.animationVersion === animationVersion &&
      facts.tabsOverviewMounted && !this.presentationState.exiting;
  }

  private recoverWebLayerOpacityAfterStaleEntryAnimation(
    animationVersion: number,
    host: BrowserTabsOverviewSessionHost
  ): void {
    const facts = host.readSessionFacts();
    if (this.presentationState.animationVersion === animationVersion || facts.tabsOverviewMounted ||
      this.shouldShowSharedSnapshotOverlay()) {
      return;
    }
    host.executeEffect({
      type: 'record_session_trace',
      traceType: 'tabs_overview_entry_web_layer_recovered',
      message: `staleVersion=${animationVersion} currentVersion=${this.presentationState.animationVersion} ` +
        `opacity=${this.presentationState.surface.webLayerOpacity}`,
      tabId: facts.activeTabId
    });
    this.updatePresentationState({
      surface: {
        webLayerOpacity: 1,
        webEntryProgress: 1
      }
    }, host);
  }

  private scheduleTabsOverviewEntrySettleFallback(
    plan: BrowserTabsOverviewSceneEntryRunPlan,
    animationVersion: number,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): void {
    if (plan.fallbackSettleDelayMs <= 0) {
      return;
    }
    const tabId = plan.sceneState.activeTabIdAtOpen;
    setTimeout(() => {
      if (!this.isOperationCurrent(generation) || this.presentationState.animationVersion !== animationVersion) {
        return;
      }
      this.settleTabsOverviewSceneIfOpening(tabId, host);
    }, plan.fallbackSettleDelayMs);
  }

  private settleTabsOverviewSceneIfOpening(tabId: string, host: BrowserTabsOverviewSessionHost): void {
    const facts = host.readSessionFacts();
    const sceneState = this.presentationState.sceneState;
    if (!facts.tabsOverviewMounted || this.presentationState.exiting || tabId !== sceneState.activeTabIdAtOpen) {
      return;
    }
    if (!this.sceneDriver.shouldSettleOpeningFallback(sceneState, tabId)) {
      return;
    }
    this.resetSharedSnapshotSession({
      createSharedSnapshotRunId: false,
      resetSharedSnapshotTransition: false,
      resetEntrySnapshotFrame: false,
      releaseEntrySnapshot: false,
      bumpAnimationVersion: false,
      entryStateReset: 'cancel'
    }, host);
    this.updatePresentationState({
      sceneState: this.sceneDriver.buildSettledState(sceneState),
      entryAnimationActive: false
    }, host);
  }

  private settleTabsOverviewEntryAnimation(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({
      entryAnimationActive: false,
      sceneState: this.sceneDriver.buildSettledState(this.presentationState.sceneState)
    }, host);
  }

  private prepareOpenAfterInterruptedSharedSnapshot(host: BrowserTabsOverviewSessionHost): void {
    const facts = host.readSessionFacts();
    if (!this.presentationState.exiting && !this.shouldShowSharedSnapshotOverlay()) {
      return;
    }
    const snapshotState = this.presentationState.sharedSnapshotState;
    const snapshotTabId = snapshotState.tabId.length > 0 ? snapshotState.tabId : facts.activeTabId;
    host.executeEffect({
      type: 'record_session_trace',
      traceType: 'shared_snapshot_reentry_cleanup',
      message: `showTabs=${facts.tabsOverviewMounted} ` +
        `exiting=${this.presentationState.exiting} ` +
        `phase=${snapshotState.phase} direction=${snapshotState.direction} ` +
        `progress=${snapshotState.progress}`,
      tabId: snapshotTabId
    });
    this.resetSharedSnapshotSession({
      createSharedSnapshotRunId: true,
      resetSharedSnapshotTransition: true,
      resetEntrySnapshotFrame: true,
      releaseEntrySnapshot: true,
      bumpAnimationVersion: true,
      entryStateReset: 'cancel'
    }, host);
    this.applyClosedOverviewReset(
      'tabs-overview-reentry-cleanup',
      false,
      host,
      this.sceneDriver.buildInterruptedReentryResetPatch(facts.backdropOpenStartProgress)
    );
  }

  private shouldContinueHomeSurfaceOpen(
    activeTabIdAtOpen: string,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    const facts = host.readSessionFacts();
    return this.shouldOpenFromHomeSurface({
      showHomePage: facts.homeSurfaceVisible,
      activeTabIsHome: this.isHomeSurfaceTab(facts.tabs.find((tab: BrowserTabState) => tab.id === activeTabIdAtOpen))
    }) && !facts.tabsOverviewMounted;
  }

  private resolveInitialSection(
    section: BrowserTabsOverviewSessionSection,
    host: BrowserTabsOverviewSessionHost
  ): BrowserTabsOverviewSessionSection {
    return host.readSessionFacts().currentTabPrivate ? 'privacy' : this.normalizeSection(section);
  }

  private collapseExpandedRootBottomPanelForOpen(host: BrowserTabsOverviewSessionHost): void {
    host.executeEffect({ type: 'clear_root_bottom_chrome_scroll' });
    if (host.readSessionFacts().rootBottomPanelEffectiveHomeMode) {
      host.executeEffect({ type: 'release_home_search_focus' });
    } else {
      host.executeEffect({ type: 'release_web_bottom_address_focus' });
    }
    host.executeEffect({ type: 'apply_root_bottom_panel_detent', detent: 'low' });
  }

  private applyClosedOverviewReset(
    reason: string,
    releaseEntrySnapshotAfterReset: boolean,
    host: BrowserTabsOverviewSessionHost,
    patch?: BrowserTabsOverviewSceneResetPatch
  ): void {
    const resetPatch = patch ?? this.sceneDriver.buildClosedResetPatch();
    this.cancelBackdropSettleRun();
    this.updatePresentationState({
      sceneState: resetPatch.sceneState,
      exiting: resetPatch.exiting,
      homeSurfaceCloseInFlight: resetPatch.homeSurfaceCloseInFlight,
      entryAnimationActive: resetPatch.entryAnimationActive,
      surface: {
        webLayerOpacity: resetPatch.webLayerOpacity,
        webEntryProgress: resetPatch.webEntryProgress,
        homeExitProgress: resetPatch.homeExitProgress,
        overlayOpacity: resetPatch.overlayOpacity,
        backdropProgress: resetPatch.backdropProgress
      }
    }, host);
    host.executeEffect({ type: 'apply_closed_overview_reset' });
    host.executeEffect({ type: 'reconcile_external_navigation_prompt' });
    host.executeEffect({ type: 'sync_bottom_panel_status_bar_style' });
    this.fixedDependencies.webTopImmersionSessionCoordinator.syncPolicy(reason);
    host.executeEffect({ type: 'reset_home_reveal' });
    this.unlockTabsOverviewSnapshot(host);
    this.hideBackdropSnapshot(host);
    if (releaseEntrySnapshotAfterReset) {
      this.snapshotPipelineCoordinator.releaseSession();
    }
  }

  private async finishSelectionFromOverview(
    tabId: string,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    let facts = host.readSessionFacts();
    const targetTab = facts.tabs.find((tab: BrowserTabState) => tab.id === tabId);
    if (!this.isTabsOverviewOperationCurrent(generation, host) || targetTab === undefined) {
      return;
    }
    if (targetTab !== undefined && !await this.ensurePrivateModeUnlocked(
      targetTab.privacyMode,
      targetTab.dataScope,
      'switch_private_tab'
    )) {
      return;
    }
    if (!this.isTabsOverviewTargetCurrent(generation, targetTab, host)) {
      return;
    }
    facts = host.readSessionFacts();
    if (this.shouldRestoreActiveWebTabFromHomeOverview(tabId, targetTab, facts)) {
      this.tabSwitchCoordinator.restoreActiveWebTabFromHomeOverview();
    }
    if (tabId !== facts.activeTabId) {
      this.prepareSelectionForSharedSnapshot(tabId, host);
    }
    const selectionFacts = host.readSessionFacts();
    const visualFacts = this.buildSelectionVisualFacts(tabId, selectionFacts);
    const diagnostic = this.selectionPolicy.buildSharedSnapshotExitSelectionDiagnostic({
      tabId: tabId,
      previewState: visualFacts.morphSource.previewState,
      hostedWebLayerMeasured: visualFacts.hostedWebLayerMeasured,
      reusedGeometry: visualFacts.reusableGeometry,
      webRect: visualFacts.webRect
    });
    if (this.selectionPolicy.shouldSkipSharedSnapshotExitForTabSelection({
      previewState: visualFacts.morphSource.previewState,
      hostedWebLayerMeasured: visualFacts.hostedWebLayerMeasured
    })) {
      host.executeEffect({
        type: 'record_session_trace',
        traceType: 'shared_snapshot_selection_direct_close',
        message: diagnostic,
        tabId: tabId
      });
      this.applySelectionPanelExit(tabId, targetTab, host);
      this.completeSelectionClose(host);
      return;
    }
    host.executeEffect({
      type: 'record_session_trace',
      traceType: 'shared_snapshot_selection_decision',
      message: diagnostic,
      tabId: tabId
    });
    const transitionPlan = this.buildSharedSnapshotExitPlan(tabId, selectionFacts, visualFacts, host);
    if (transitionPlan === undefined) {
      this.applySelectionPanelExit(tabId, targetTab, host);
      this.completeSelectionClose(host);
      return;
    }
    this.applySelectionPanelExit(tabId, targetTab, host, transitionPlan.initialState);
    this.playSharedSnapshotTransition(transitionPlan, (): void => {
      this.updatePresentationState({
        sharedSnapshotState: buildBrowserTabsSharedSnapshotIdleState(),
        surface: { webLayerOpacity: 1 }
      }, host);
      if (this.isTabsOverviewSelectionCompletionCurrent(generation, targetTab, host)) {
        this.completeTabsOverviewSelectionClose(host);
      }
    }, host);
  }

  private beginSelectionPanelExit(
    tabId: string,
    host: BrowserTabsOverviewSessionHost,
    sharedSnapshotState?: BrowserTabsSharedSnapshotTransitionState
  ): void {
    this.sharedSnapshotEntryState = this.sharedSnapshotEntryCoordinator.cancel(this.sharedSnapshotEntryState);
    this.updatePresentationState({ entryAnimationActive: true }, host);
    const targetTab = host.readSessionFacts().tabs.find((tab: BrowserTabState) => tab.id === tabId);
    this.applySelectionPanelExit(tabId, targetTab, host, sharedSnapshotState);
  }

  private prepareSelectionForSharedSnapshot(tabId: string, host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({ surface: { webLayerOpacity: 0 } }, host);
    if (!this.tabSwitchCoordinator.applyOverviewSelection(tabId)) {
      this.fixedDependencies.hostedRuntimeSurfacePort.syncCurrentActiveFromHost();
    }
  }

  private applySelectionPanelExit(
    tabId: string,
    targetTab: BrowserTabState | undefined,
    host: BrowserTabsOverviewSessionHost,
    sharedSnapshotState?: BrowserTabsSharedSnapshotTransitionState
  ): void {
    const shouldHideWebLayer = targetTab !== undefined && !targetTab.isHome;
    const plan = this.sceneDriver.buildSelectionPanelExitState(
      this.presentationState.sceneState,
      tabId,
      targetTab?.isHome === true
    );
    this.updatePresentationState({
      sceneState: plan.sceneState,
      headerMode: plan.headerMode,
      exiting: plan.exiting,
      entryAnimationActive: plan.entryAnimationActive,
      sharedSnapshotState: sharedSnapshotState,
      surface: shouldHideWebLayer ? { webLayerOpacity: 0 } : undefined
    }, host);
    if (shouldHideWebLayer) {
      host.executeEffect({
        type: 'reset_web_bottom_address_panel_for_tab_selection'
      });
    }
  }

  private shouldRestoreActiveWebTabFromHomeOverview(
    tabId: string,
    targetTab: BrowserTabState | undefined,
    facts: BrowserTabsOverviewSessionFacts
  ): boolean {
    return tabId === facts.activeTabId && facts.homeSurfaceVisible && targetTab !== undefined && !targetTab.isHome;
  }

  private completeSelectionClose(host: BrowserTabsOverviewSessionHost): void {
    this.updatePresentationState({ surface: { webLayerOpacity: 1 } }, host);
    this.completeTabsOverviewSelectionClose(host);
  }

  private buildHomeSurfacePlan(section: BrowserTabsOverviewSessionSection): BrowserTabsOverviewHomeSurfacePlan {
    const normalizedSection = this.normalizeSection(section);
    const options = normalizedSection === 'privacy' ? this.buildPrivateOptions() : this.buildRegularOptions();
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode);
    const dataScope = normalizeBrowserDataScope(options.dataScope, privacyMode);
    return {
      section: normalizedSection,
      options: options,
      profileId: options.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: privacyMode,
      dataScope: dataScope,
      authReason: 'enter_private_home',
      helperMessage: normalizedSection === 'privacy' ? '已打开隐私标签页' : '已打开新标签页'
    };
  }

  private async createHomeSurfaceFromTabsOverview(
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    if (!this.beginHomeSurfaceClose('create_home', host, generation)) {
      return;
    }
    await this.applyHomeSurfacePlan(
      this.buildHomeSurfacePlan(this.presentationState.activeSection),
      host,
      generation
    );
  }

  private dismissTabsOverviewToHome(host: BrowserTabsOverviewSessionHost, generation: number): void {
    const facts = host.readSessionFacts();
    if (!this.isTabsOverviewOperationCurrent(generation, host) ||
      !(facts.tabsOverviewMounted && !this.presentationState.exiting)) {
      return;
    }
    void this.dismissTabsOverviewToPreparedHome(host, generation);
  }

  private async applyHomeSurfacePlan(
    plan: BrowserTabsOverviewHomeSurfacePlan,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<boolean> {
    try {
      if (!await this.ensurePrivateModeUnlocked(plan.privacyMode, plan.dataScope, plan.authReason)) {
        return false;
      }
      if (!this.isTabsOverviewOperationCurrent(generation, host)) {
        return false;
      }
      await this.restorePrivateModeCookies(plan.privacyMode, plan.dataScope);
      if (!this.isTabsOverviewOperationCurrent(generation, host)) {
        return false;
      }
      this.prepareBackdropHomeRevealWithHost(host);
      host.executeEffect({ type: 'prepare_home_reveal_from_tabs_overview' });
      this.createHomeTabForSurface(plan.helperMessage, plan.options, true, false, host);
      this.updatePresentationState({ activeSection: plan.section }, host);
      await this.playPreparedHomeRevealClose(host, generation);
      return this.isOperationCurrent(generation);
    } finally {
      this.finishHomeSurfaceClose(host, generation);
    }
  }

  private beginHomeSurfaceClose(
    reason: string,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): boolean {
    const facts = host.readSessionFacts();
    if (!facts.tabsOverviewMounted || this.presentationState.homeSurfaceCloseInFlight) {
      host.executeEffect({
        type: 'record_session_trace',
        traceType: 'tabs_overview_home_close_ignored',
        message: `reason=${reason} showTabs=${facts.tabsOverviewMounted} inFlight=${this.presentationState.homeSurfaceCloseInFlight}`,
        tabId: facts.activeTabId
      });
      return false;
    }
    this.homeSurfaceCloseGeneration = generation;
    this.updatePresentationState({ homeSurfaceCloseInFlight: true }, host);
    this.cancelEntrySnapshotForHomeSurfaceClose(reason, host);
    return true;
  }

  private finishHomeSurfaceClose(host: BrowserTabsOverviewSessionHost, generation: number): void {
    if (this.homeSurfaceCloseGeneration !== generation) {
      return;
    }
    this.homeSurfaceCloseGeneration = -1;
    this.updatePresentationState({ homeSurfaceCloseInFlight: false }, host);
  }

  private createHomeTabForSurface(
    helperMessage: string,
    options: BrowserCreateTabOptions,
    keepTabsOverviewMounted: boolean,
    playHomeReveal: boolean,
    host: BrowserTabsOverviewSessionHost
  ): void {
    const facts = host.readSessionFacts();
    const mutation = this.tabManager.createTab(facts.tabs, facts.tabSequence, facts.homeUrl, '新标签页', options);
    this.tabHomeCoordinator.applyTabsOverviewHomeTabCreation({
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: mutation.tabSequence,
      createdTabId: mutation.activeTabId,
      helperMessage: helperMessage,
      options: options,
      keepTabsOverviewMounted: keepTabsOverviewMounted,
      playHomeReveal: playHomeReveal
    });
  }

  private async dismissTabsOverviewToPreparedHome(
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    if (!this.beginHomeSurfaceClose('dismiss_home', host, generation)) {
      return;
    }
    try {
      this.prepareBackdropHomeRevealWithHost(host);
      host.executeEffect({ type: 'prepare_home_reveal_from_tabs_overview' });
      this.prepareDismissHomeSurface(host);
      await this.playPreparedHomeRevealClose(host, generation);
    } finally {
      this.finishHomeSurfaceClose(host, generation);
    }
  }

  private async playPreparedHomeRevealClose(
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    host.executeEffect({ type: 'play_home_reveal_from_tabs_overview' });
    this.playBackdropHomeRevealFadeWithHost(host);
    await this.playHomeRevealExitAnimation(host);
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    this.hideBackdropSnapshot(host);
    this.closeTabsOverviewToHomeWithoutSheetExit(host);
  }

  private async revealHomeSurfaceFromTabsOverview(
    helperMessage: string,
    homeOptions: BrowserCreateTabOptions,
    homeRevealMotion: BrowserTabsOverviewHomeRevealMotion,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    if (!this.isTabsOverviewOperationCurrent(generation, host)) {
      return;
    }
    host.executeEffect({ type: 'prepare_optimistic_home_reveal', motion: homeRevealMotion });
    this.tabHomeCoordinator.showHomeSurface(helperMessage, homeOptions, true, false);
    this.playBackdropProgressTransition(0, host);
    await this.playHomeRevealExitAnimation(host);
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    this.closeTabsOverviewToHomeWithoutSheetExit(host);
    if (homeRevealMotion === 'scale') {
      host.executeEffect({ type: 'play_home_reveal_from_tabs_overview' });
    }
    this.playBackdropHomeRevealFadeWithHost(host);
  }

  private prepareDismissHomeSurface(host: BrowserTabsOverviewSessionHost): void {
    const facts = host.readSessionFacts();
    if (facts.homeSurfaceVisible) {
      this.updatePresentationState({ headerMode: 'home' }, host);
      return;
    }
    const activeTab = facts.tabs.find((tab: BrowserTabState) => tab.id === facts.activeTabId);
    this.tabHomeCoordinator.dismissTabsOverviewToHome({
      activeTab: activeTab,
      activeTabId: facts.activeTabId,
      runtimeDegradedMessage: facts.runtimeDegradedMessage,
      tabs: facts.tabs
    });
    this.updatePresentationState({ headerMode: 'home' }, host);
    host.executeEffect({ type: 'finish_tabs_overview_dismiss_home' });
  }

  private async enterPrivateMode(
    helperMessage: string,
    options: BrowserCreateTabOptions,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode ?? 'private');
    const dataScope = normalizeBrowserDataScope(options.dataScope, privacyMode);
    const facts = host.readSessionFacts();
    if (facts.tabsOverviewMounted) {
      if (!this.beginHomeSurfaceClose('enter_private', host, generation)) {
        return;
      }
      const entered = await this.applyHomeSurfacePlan({
        section: 'privacy',
        options: options,
        profileId: options.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
        privacyMode: privacyMode,
        dataScope: dataScope,
        authReason: 'enter_private_home',
        helperMessage: helperMessage
      }, host, generation);
      if (!entered) {
        return;
      }
    } else {
      if (!await this.ensurePrivateModeUnlocked(privacyMode, dataScope, 'enter_private_home')) {
        return;
      }
      if (!this.isOperationCurrent(generation)) {
        return;
      }
      await this.restorePrivateModeCookies(privacyMode, dataScope);
      if (!this.isOperationCurrent(generation)) {
        return;
      }
      this.updatePresentationState({ activeSection: 'privacy' }, host);
      this.tabHomeCoordinator.showHomeSurface(helperMessage, options, false, true);
    }
    host.executeEffect({
      type: 'record_runtime_event',
      eventType: 'private_mode_entered',
      message: '已进入隐私模式',
      tabId: host.readSessionFacts().activeTabId
    });
  }

  private async changeSection(
    section: BrowserTabsOverviewSessionSection,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    const normalizedSection = this.normalizeSection(section);
    const facts = host.readSessionFacts();
    if (!this.isTabsOverviewOperationCurrent(generation, host) || this.presentationState.activeSection === normalizedSection) {
      return;
    }
    if (normalizedSection === 'privacy' && !await this.ensurePrivateModeUnlocked(
      'private',
      'session_ephemeral',
      'tabs_overview_private_section'
    )) {
      return;
    }
    if (!this.isTabsOverviewOperationCurrent(generation, host)) {
      return;
    }
    this.updatePresentationState({ activeSection: normalizedSection }, host);
    host.executeEffect({
      type: 'apply_section_change',
      options: normalizedSection === 'privacy' ? this.buildPrivateOptions() : this.buildRegularOptions(),
      userMessage: normalizedSection === 'privacy' ? '已切换到隐私模式' : '已切换到普通模式'
    });
  }

  private activateSectionHome(
    section: BrowserTabsOverviewSessionSection,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): void {
    if (!this.isTabsOverviewOperationCurrent(generation, host)) {
      return;
    }
    const plan = this.privateTabCoordinator.buildPrivateModeTogglePlan({
      surface: 'tabs_overview_mode_button',
      requestedTabsOverviewSection: this.normalizeSection(section)
    });
    host.executeEffect({ type: 'confirm_private_mode_switch', plan: plan });
  }

  private requestCloseAllTabs(
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): void {
    const facts = host.readSessionFacts();
    const plan = this.actionPolicy.buildDeletePlan(
      this.resolveActionSection(this.presentationState.activeSection),
      facts.tabs,
      facts.activeTabId
    );
    if (plan.count <= 0) {
      host.executeEffect({ type: 'show_native_toast', message: plan.emptyMessage });
      if (facts.tabs.length === 0) {
        this.dismissTabsOverviewToHome(host, generation);
      }
      return;
    }
    this.closeAllConfirmationGeneration = generation;
    host.executeEffect({ type: 'show_close_all_confirmation', plan: plan });
  }

  private confirmCloseAllTabs(host: BrowserTabsOverviewSessionHost): void {
    const facts = host.readSessionFacts();
    const plan = this.actionPolicy.buildDeletePlan(
      this.resolveActionSection(this.presentationState.activeSection),
      facts.tabs,
      facts.activeTabId
    );
    if (plan.count <= 0) {
      host.executeEffect({ type: 'show_native_toast', message: plan.emptyMessage });
      return;
    }
    if (!facts.tabsOverviewMounted) {
      return;
    }
    if (this.presentationState.closeAllAnimationPending) {
      return;
    }
    this.updatePresentationState({
      closeAllAnimationPending: true,
      closeAllAnimationRequestVersion: this.presentationState.closeAllAnimationRequestVersion + 1
    }, host);
  }

  private async finishCloseAllTabsAfterOverviewAnimation(
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    if (!this.isTabsOverviewOperationCurrent(generation, host) ||
      !this.presentationState.closeAllAnimationPending) {
      return;
    }
    this.updatePresentationState({ closeAllAnimationPending: false }, host);
    await this.closeAllTabs(host, generation);
  }

  private async closeAllTabs(host: BrowserTabsOverviewSessionHost, generation: number): Promise<void> {
    let facts = host.readSessionFacts();
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    const plan = this.actionPolicy.buildDeletePlan(
      this.resolveActionSection(this.presentationState.activeSection),
      facts.tabs,
      facts.activeTabId
    );
    if (plan.count <= 0) {
      return;
    }
    if (facts.tabsOverviewMounted) {
      if (!this.beginHomeSurfaceClose('close_all_tabs', host, generation)) {
        return;
      }
      try {
        await this.revealHomeSurfaceFromTabsOverview(
          plan.helperMessage,
          plan.homeOptions,
          plan.homeRevealMotion,
          host,
          generation
        );
      } finally {
        this.finishHomeSurfaceClose(host, generation);
      }
    } else {
      this.tabHomeCoordinator.showHomeSurface(plan.helperMessage, plan.homeOptions, false, true);
    }
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    const closeResult: BrowserCloseTabsToHomeResult = await this.tabCloseCoordinator.closeTabsToHomeAfterReveal(
      plan.tabIds,
      'close-all-tabs',
      plan.helperMessage,
      'closed_count'
    );
    if (!this.isOperationCurrent(generation)) {
      return;
    }
    host.executeEffect({ type: 'show_native_toast', message: closeResult.helperMessage });
    facts = host.readSessionFacts();
    host.executeEffect({
      type: 'record_runtime_event',
      eventType: plan.runtimeEventType,
      message: `closed=${closeResult.closedCount}`,
      tabId: facts.activeTabId
    });
  }

  private async closeTabFromOverview(
    tabId: string,
    host: BrowserTabsOverviewSessionHost,
    generation: number
  ): Promise<void> {
    const facts = host.readSessionFacts();
    if (!this.isTabsOverviewOperationCurrent(generation, host) || this.presentationState.homeSurfaceCloseInFlight) {
      return;
    }
    const plan = this.buildSingleCloseHomePlan(
      this.resolveActionSection(this.presentationState.activeSection),
      facts.tabs,
      facts.activeTabId,
      tabId
    );
    if (!plan.shouldRevealHomeFirst) {
      await this.tabCloseCoordinator.closeTab(tabId);
      return;
    }
    if (!this.beginHomeSurfaceClose('close_last_tab', host, generation)) {
      return;
    }
    try {
      await this.waitOptimisticCloseDelay(plan.revealDelayMs);
      if (!this.isLastTabCloseTargetCurrent(generation, tabId, host)) {
        return;
      }
      await this.revealHomeSurfaceFromTabsOverview(
        plan.helperMessage,
        plan.homeOptions,
        plan.homeRevealMotion,
        host,
        generation
      );
      if (!this.isOperationCurrent(generation)) {
        return;
      }
      await this.tabCloseCoordinator.closeTabsToHomeAfterReveal(
        plan.tabIds,
        'close-tab-from-overview',
        plan.helperMessage
      );
    } finally {
      this.finishHomeSurfaceClose(host, generation);
    }
  }

  private buildSingleCloseHomePlan(
    section: BrowserTabsOverviewActionSection,
    tabs: BrowserTabState[],
    activeTabId: string,
    tabId: string
  ): BrowserTabsOverviewSingleCloseHomePlan {
    const targetTab = tabs.find((tab: BrowserTabState) => tab.id === tabId);
    if (targetTab === undefined || tabs.length !== 1) {
      return {
        shouldRevealHomeFirst: false,
        tabIds: [tabId],
        homeOptions: REGULAR_HOME_OPTIONS,
        helperMessage: '已关闭标签页。',
        revealDelayMs: 0,
        homeRevealMotion: 'steady'
      };
    }
    const returnPlan = this.actionPolicy.buildReturnPlan(section, tabs, activeTabId);
    return {
      shouldRevealHomeFirst: true,
      tabIds: [tabId],
      homeOptions: returnPlan.homeOptions,
      helperMessage: this.isHomeOptionsSessionEphemeral(returnPlan.homeOptions) ? '已进入隐私模式' : '已回到主页',
      revealDelayMs: SINGLE_TAB_CLOSE_HOME_REVEAL_DELAY_MS,
      homeRevealMotion: 'steady'
    };
  }

  private isHomeOptionsSessionEphemeral(options: BrowserCreateTabOptions): boolean {
    return this.profileBoundaryService.isSessionEphemeral(
      this.profileBoundaryService.buildBoundaryInput(
        options.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
        options.privacyMode ?? 'regular',
        options.dataScope ?? 'profile_persistent'
      )
    );
  }

  private async waitOptimisticCloseDelay(delayMs: number): Promise<void> {
    const duration = Math.max(0, Math.floor(delayMs));
    if (duration <= 0) {
      return;
    }
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), duration);
    });
  }

  private async ensurePrivateModeUnlocked(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope,
    reason: BrowserPrivateModeLockReason
  ): Promise<boolean> {
    return this.fixedDependencies.privateModeLockCoordinator.ensureUnlocked(
      privacyMode,
      dataScope,
      reason
    );
  }

  private async restorePrivateModeCookies(
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): Promise<void> {
    await this.fixedDependencies.privateProfileLifecycleCoordinator.restorePreservedCookiesOnEnterIfNeeded(
      privacyMode,
      dataScope,
      this.fixedDependencies.privateProfileCookieLifecycleHost
    );
  }

  private async playHomeRevealExitAnimation(host: BrowserTabsOverviewSessionHost): Promise<void> {
    if (!host.readSessionFacts().tabsOverviewMounted) {
      return;
    }
    const animationPlan = this.sharedSnapshotAnimationViewModel.buildHomeRevealExitAnimationPlan();
    const animationVersion = this.presentationState.animationVersion;
    await new Promise<void>((resolve: () => void) => {
      host.executeEffect({
        type: 'play_tabs_overview_arkui_animation',
        plan: {
          durationMs: animationPlan.durationMs,
          curve: animationPlan.curve,
          apply: (): void => {
            if (this.presentationState.animationVersion !== animationVersion ||
              !host.readSessionFacts().tabsOverviewMounted) {
              return;
            }
            this.updatePresentationState({
              surface: {
                homeExitProgress: animationPlan.targetState.homeExitProgress,
                backdropProgress: animationPlan.targetState.backdropProgress
              }
            }, host);
          },
          onFinish: resolve
        }
      });
      setTimeout(() => resolve(), animationPlan.completionDelayMs);
    });
  }

  private async captureFreshActiveTabPreview(
    tab: BrowserTabState,
    generation: number,
    host: BrowserTabsOverviewSessionHost
  ): Promise<boolean> {
    const result = await host.executeAsyncTask({
      type: 'capture_fresh_active_tab_preview',
      tab: tab,
      generation: generation
    });
    return result.success;
  }

  private beginOperation(): number {
    this.operationGeneration += 1;
    this.interruptedSelectionCompletionGeneration = -1;
    this.closeAllConfirmationGeneration = -1;
    return this.operationGeneration;
  }

  private invalidateOperations(): void {
    this.operationGeneration += 1;
    this.interruptedSelectionCompletionGeneration = -1;
    this.closeAllConfirmationGeneration = -1;
  }

  private isOperationCurrent(generation: number): boolean {
    return generation === this.operationGeneration;
  }

  private isInterruptedSelectionCompletionCurrent(): boolean {
    return this.interruptedSelectionCompletionGeneration >= 0 &&
      this.interruptedSelectionCompletionGeneration === this.operationGeneration;
  }

  private isPendingOpenCurrent(
    generation: number,
    activeTabIdAtOpen: string,
    openedFromHome: boolean,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    if (!this.isOperationCurrent(generation)) {
      return false;
    }
    const facts = host.readSessionFacts();
    if (facts.tabsOverviewMounted || this.presentationState.exiting || facts.activeTabId !== activeTabIdAtOpen) {
      return false;
    }
    const activeTab = facts.tabs.find((tab: BrowserTabState) => tab.id === activeTabIdAtOpen);
    if (openedFromHome) {
      return this.shouldOpenFromHomeSurface({
        showHomePage: facts.homeSurfaceVisible,
        activeTabIsHome: this.isHomeSurfaceTab(activeTab)
      });
    }
    return !facts.homeSurfaceVisible && activeTab !== undefined && !this.isHomeSurfaceTab(activeTab);
  }

  private isTabsOverviewOperationCurrent(
    generation: number,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    if (!this.isOperationCurrent(generation)) {
      return false;
    }
    const facts = host.readSessionFacts();
    return facts.tabsOverviewMounted && !this.presentationState.exiting;
  }

  private isTabsOverviewTargetCurrent(
    generation: number,
    targetTab: BrowserTabState,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    if (!this.isTabsOverviewOperationCurrent(generation, host)) {
      return false;
    }
    const currentTarget = host.readSessionFacts().tabs.find((tab: BrowserTabState) => tab.id === targetTab.id);
    return currentTarget !== undefined && currentTarget.profileId === targetTab.profileId &&
      currentTarget.privacyMode === targetTab.privacyMode && currentTarget.dataScope === targetTab.dataScope;
  }

  private isTabsOverviewSelectionCompletionCurrent(
    generation: number,
    targetTab: BrowserTabState,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    if (!this.isOperationCurrent(generation)) {
      return false;
    }
    const facts = host.readSessionFacts();
    if (!facts.tabsOverviewMounted || !this.presentationState.exiting) {
      return false;
    }
    const currentTarget = facts.tabs.find((tab: BrowserTabState) => tab.id === targetTab.id);
    return currentTarget !== undefined && currentTarget.profileId === targetTab.profileId &&
      currentTarget.privacyMode === targetTab.privacyMode && currentTarget.dataScope === targetTab.dataScope;
  }

  private isLastTabCloseTargetCurrent(
    generation: number,
    tabId: string,
    host: BrowserTabsOverviewSessionHost
  ): boolean {
    if (!this.isTabsOverviewOperationCurrent(generation, host)) {
      return false;
    }
    const facts = host.readSessionFacts();
    return facts.tabs.length === 1 && facts.tabs[0].id === tabId;
  }

  private resolveActionSection(section: BrowserTabsOverviewSessionSection): BrowserTabsOverviewActionSection {
    return section === 'privacy' ? 'privacy' : 'tabs';
  }

  private buildRegularOptions(): BrowserCreateTabOptions {
    return {
      profileId: DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: 'regular',
      dataScope: 'profile_persistent'
    };
  }

  private shouldShowOverviewBackdrop(input: BrowserTabsOverviewBackgroundRenderInput): boolean {
    if (input.scenePhase === 'openingHomeCards' || input.scenePhase === 'openingMorphingActiveTab') {
      return input.openedFromHome;
    }
    return input.scenePhase === 'closing';
  }

  private shouldUseSeparateOverviewBackdrop(input: BrowserTabsOverviewBackgroundRenderInput): boolean {
    return !input.openedFromHome ||
      (input.scenePhase !== 'openingHomeCards' && input.scenePhase !== 'openingMorphingActiveTab');
  }

  private resolveFloatingGlassOpacity(input: BrowserTabsOverviewBackgroundRenderInput): number {
    if (!input.showTabsSheet) {
      return 0;
    }
    const homeExitProgress = this.clampProgress(input.homeExitProgress);
    return homeExitProgress > 0 ? 1 - homeExitProgress : 1;
  }

  private clampProgress(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }

  private buildPrivateOptions(): BrowserCreateTabOptions {
    return {
      profileId: DEFAULT_BROWSER_PROFILE_ID,
      privacyMode: 'private',
      dataScope: 'session_ephemeral'
    };
  }

  private normalizeSection(section: BrowserTabsOverviewSessionSection): BrowserTabsOverviewSessionSection {
    return section === 'privacy' ? 'privacy' : 'tabs';
  }

  private buildPlan(
    kind: BrowserTabsOverviewSessionPlanKind,
    activeSection: BrowserTabsOverviewSessionSection,
    collapseRootBottomPanelToDefault: boolean,
    openDelayMs: number
  ): BrowserTabsOverviewSessionOpenPlan {
    return {
      kind: kind,
      activeSection: activeSection,
      collapseRootBottomPanelToDefault: collapseRootBottomPanelToDefault,
      openDelayMs: Math.max(0, Math.round(openDelayMs))
    };
  }
}
