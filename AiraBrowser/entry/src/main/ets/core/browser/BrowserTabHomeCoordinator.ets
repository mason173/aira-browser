import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDataScope,
  BrowserHomeShortcutLayoutDensity,
  BrowserProfileId,
  BrowserResolvedThemeMode,
  BrowserSessionPrivacyMode,
  BrowserThemeMode,
  DEFAULT_BROWSER_PROFILE_ID,
  SearchEngineId,
  SearchEngineRecord,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  BrowserHomepageBackdropAppearanceEffectInput,
  BrowserHomepageBackdropAppearanceSource,
  BrowserHomepageBackdropAppearanceState,
  cloneBrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';
import { HomeWallpaperPresentationState } from '../../common/models/WallpaperModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import {
  HomeResponsiveLayoutInput,
  HomeResponsiveLayoutState,
  HomeResponsiveLayoutViewModel
} from '../../features/newtab/HomeResponsiveLayoutViewModel';
import { HomeShortcutUserAction } from '../../features/newtab/HomeShortcutTypes';
import { BrowserOfflineFastFailureCoordinator } from '../../services/web/BrowserOfflineFastFailureCoordinator';
import {
  BrowserTabBackgroundSessionSyncCoordinator
} from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import {
  BrowserRuntimeLifecyclePort,
  BrowserRuntimeMutationPort
} from '../../services/web/BrowserRuntimeLifecyclePort';
import { TelegramWebCompatibilityService } from '../../services/web/TelegramWebCompatibilityService';
import {
  BrowserThemePaletteService,
  ResolvedBrowserThemeTokens
} from '../../services/theme/BrowserThemePaletteService';
import {
  BrowserCreateTabOptions,
  BrowserTabRuntimePatch,
  BrowserTabState
} from '../tabs/TabManager';
import { WebpageTranslationCoordinator } from '../translation/WebpageTranslationCoordinator';
import { WebEventRouter } from '../web/WebEventRouter';
import { WebRecoveryManager } from '../web/WebRecoveryManager';
import { WebStateSnapshotStore } from '../web/WebStateSnapshotStore';
import {
  CustomHomepageRuntimeCoordinator,
  CustomHomepageRuntimeShellState
} from '../customhome/CustomHomepageRuntimeCoordinator';
import { AppReviewPromptCoordinator } from '../review/AppReviewPromptCoordinator';
import {
  SearchEngineSelectionCoordinator,
  SearchEngineSelectionSnapshot
} from '../search/SearchEngineSelectionCoordinator';
import { ReleaseNoticePresentationCoordinator } from '../update/ReleaseNoticePresentationCoordinator';
import { HomeWallpaperCoordinator, HomeWallpaperRefreshResult } from '../wallpaper/HomeWallpaperCoordinator';
import { HomeWallpaperInteractionColorViewModel } from '../wallpaper/HomeWallpaperInteractionColorViewModel';
import {
  HomeShortcutApplicationSnapshot,
  HomeShortcutStateCoordinator
} from '../shortcuts/HomeShortcutStateCoordinator';
import {
  BrowserSnapshotApplicationHost,
  BrowserSnapshotPersistenceHost,
  BrowserTabRecoveryCoordinator
} from './BrowserTabRecoveryCoordinator';
import { BrowserHomePresentationSessionCoordinator } from './BrowserHomePresentationSessionCoordinator';
import {
  BrowserHomeSurfaceProfile,
  BrowserHomeSurfaceProfileViewModel,
  BrowserHomeSurfaceScene
} from './BrowserHomeSurfaceProfileViewModel';
import { BrowserBackdropEffectViewModel } from './BrowserBackdropEffectViewModel';
import { BrowserFullscreenSessionCoordinator } from './BrowserFullscreenSessionCoordinator';
import { BrowserHomepageBackdropAppearanceCoordinator } from './BrowserHomepageBackdropAppearanceCoordinator';
import {
  BrowserRecentlyClosedApplicationCoordinator,
  BrowserRecentlyClosedApplicationSnapshot,
  BrowserRecentlyClosedUserAction
} from './BrowserRecentlyClosedApplicationCoordinator';
import { BrowserTransientSurfaceCoordinator } from './BrowserTransientSurfaceCoordinator';
import {
  BrowserHomeChromeInteractionInput,
  BrowserHomeChromeScrollCoordinator,
  BrowserHomeChromeScrollMode
} from './BrowserHomeChromeScrollCoordinator';
import {
  BrowserBottomChromeHomeScrollDecision,
  BrowserBottomChromeScrollPresentation
} from './BrowserBottomChromeScrollCoordinator';
import {
  HomeContentSectionsPresentationState,
  HomeContentThemePresentationState
} from './HomeContentPresentationState';
import { BrowserSearchSuggestionCoordinator } from './BrowserSearchSuggestionCoordinator';
import {
  BrowserSearchEngineChromePresentation,
  BrowserSearchEnginePresentationViewModel
} from './BrowserSearchEnginePresentationViewModel';
import { BrowserShellStateCoordinator, BrowserShellVisualState } from './BrowserShellStateCoordinator';
import {
  BrowserBottomAddressTransientMessageContext
} from './BrowserBottomAddressTransientMessageViewModel';
import { BrowserRootBottomPanelSessionCoordinator } from './BrowserRootBottomPanelSessionCoordinator';
import { BrowserTabPreviewCoordinator } from './BrowserTabPreviewCoordinator';
import { BrowserTabSessionPersistenceCoordinator } from './BrowserTabSessionPersistenceCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserTabsOverviewSessionCoordinator } from './BrowserTabsOverviewSessionCoordinator';
import {
  BrowserTabsOverviewThemeState,
  BrowserTabsOverviewThemeViewModel
} from './tabsOverview/BrowserTabsOverviewThemeViewModel';
import { BrowserThemeModeCoordinator } from './BrowserThemeModeCoordinator';
import {
  BrowserArkWebMediaTakeoverCoordinator
} from './media/BrowserArkWebMediaTakeoverCoordinator';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import {
  BrowserForegroundPresentation,
  BrowserForegroundPresentationViewModel
} from './BrowserForegroundPresentationViewModel';

const DEFAULT_DEGRADED_HOME_MESSAGE = '当前标签页连续恢复失败，已回到首页。';
const HOME_SURFACE_REVEAL_DEFERRED_WORK_DELAY_MS: number = 144;
const HOME_SURFACE_STEADY_DEFERRED_WORK_DELAY_MS: number = 48;
const TAB_HOME_LOG_DOMAIN: number = 0x0000;
const TAB_HOME_LOG_TAG: string = 'BrowserTabHome';

interface BrowserTabHomeShellState {
  tabs: BrowserTabState[];
  activeTabId: string;
  runtimeDegradedMessage: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
  controllerAttached: boolean;
  bottomAddressTransientMessageContext: BrowserBottomAddressTransientMessageContext;
  homeDataScope: BrowserDataScope;
  currentDataScope: BrowserDataScope;
  currentPrivacyMode: BrowserSessionPrivacyMode;
  currentBoundaryPrivate: boolean;
  customHomepageRuntimeState: CustomHomepageRuntimeShellState;
  optimisticThemeMode: BrowserThemeMode;
  viewportWidth: number;
  viewportHeight: number;
  homeSearchFocused: boolean;
  homepageBackdropPrivateMode: boolean;
  homepageBackdropAppearanceState: BrowserHomepageBackdropAppearanceState;
  homeShortcutApplicationSnapshot: HomeShortcutApplicationSnapshot;
}

export interface BrowserTabHomeContentAction {
  type: 'shortcut' | 'open_shortcut_picker' | 'recently_closed' |
    'restore_recently_closed' | 'open_home_settings' | 'scroll' | 'scroll_stop';
  shortcutAction?: HomeShortcutUserAction;
  recentlyClosedAction?: BrowserRecentlyClosedUserAction;
  recordId?: string;
  scrollSource?: string;
  scrollOffsetY?: number;
  scrollAtEnd?: boolean;
}

export interface BrowserTabHomeScrollActionFacts {
  input: BrowserHomeChromeInteractionInput;
  currentPresentation: BrowserBottomChromeScrollPresentation;
}

export interface BrowserHomeSystemChromePolicyState {
  scene: BrowserHomeSurfaceScene;
  homeSystemSearchEligible: boolean;
  systemEntryButtonVisible: boolean;
  homeScrollMode: BrowserHomeChromeScrollMode;
  bottomPanelHomeSearchVisible: boolean;
  expandedToolbarBackdropRequired: boolean;
}

interface BrowserTabHomeBoundaryStateApplication {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  searchEngineSelection: SearchEngineSelectionSnapshot;
}

interface BrowserTabHomeAppearanceStateApplication {
  showHomeShortcuts: boolean;
  homeShortcutLayoutDensity: BrowserHomeShortcutLayoutDensity;
  homeTokens: ResolvedBrowserThemeTokens;
  tabsOverviewThemeState: BrowserTabsOverviewThemeState;
}

interface BrowserTabHomeStateApplication {
  activeTabId?: string;
  tabSequence?: number;
  tabsForOverviewPreviewSync?: BrowserTabState[];
  visualState?: BrowserShellVisualState;
  helperMessage?: string;
  boundaryState?: BrowserTabHomeBoundaryStateApplication;
  searchEngineSelection?: SearchEngineSelectionSnapshot;
  errorMessage?: string;
  appearanceState?: BrowserTabHomeAppearanceStateApplication;
  homeWallpaperState?: HomeWallpaperPresentationState;
  homepageBackdropAppearanceState?: BrowserHomepageBackdropAppearanceState;
  tabsOverviewThemeState?: BrowserTabsOverviewThemeState;
  incrementArkWebMediaTakeoverRevision?: boolean;
  runtimeDegradedMessage?: string;
  resetHomeTransientUiState?: boolean;
  clearNavigationState?: boolean;
  clearControllerAttachment?: boolean;
  invalidateWebSessionTransition?: boolean;
  incrementThemeModeActionVersion?: boolean;
  themeModeToastMessage?: string;
  endSearchInvocation?: boolean;
  resetHomeSearchPresentation?: boolean;
}

export interface BrowserTabHomeShell {
  readState: () => BrowserTabHomeShellState;
  applyState: (application: BrowserTabHomeStateApplication) => void;
  cancelBottomPanelBackdropFocusTransition: () => void;
  restoreHomeBottomPanel: (detent: 'peek' | 'low') => void;
  syncThemeAppStorage: () => void;
  syncBottomPanelStatusBarStyle: () => void;
  showToast: (message: string) => void;
  resolveHomeScrollActionFacts: () => BrowserTabHomeScrollActionFacts;
  applyHomeScrollDecision: (decision: BrowserBottomChromeHomeScrollDecision) => void;
}

interface BrowserTabHomeDependencies {
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  runtimeMutationPort: BrowserRuntimeMutationPort;
  hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  webTabsController: BrowserWebTabsController;
  offlineFastFailureCoordinator: BrowserOfflineFastFailureCoordinator;
  snapshotStore: WebStateSnapshotStore;
  tabRecoveryCoordinator: BrowserTabRecoveryCoordinator;
  snapshotApplicationHost: BrowserSnapshotApplicationHost;
  webpageTranslationCoordinator: WebpageTranslationCoordinator;
  webEventRouter: WebEventRouter;
  visibleUrlService: TelegramWebCompatibilityService;
  snapshotPersistenceHost: BrowserSnapshotPersistenceHost;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  tabPreviewCoordinator: BrowserTabPreviewCoordinator;
  webRecoveryManager: WebRecoveryManager;
  customHomepageRuntimeCoordinator: CustomHomepageRuntimeCoordinator;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  tabSessionPersistenceCoordinator: BrowserTabSessionPersistenceCoordinator;
  searchSuggestionCoordinator: BrowserSearchSuggestionCoordinator;
  appReviewPromptCoordinator: AppReviewPromptCoordinator;
  resolveReleaseNoticePresentationCoordinator: () => ReleaseNoticePresentationCoordinator;
  resolveTabsOverviewSessionCoordinator: () => BrowserTabsOverviewSessionCoordinator;
  resolveHomePresentationSessionCoordinator: () => BrowserHomePresentationSessionCoordinator;
  resolveRootBottomPanelSessionCoordinator: () => BrowserRootBottomPanelSessionCoordinator;
  preferencesRepository: PreferencesRepository;
  searchEngineSelectionCoordinator: SearchEngineSelectionCoordinator;
  homeShortcutStateCoordinator: HomeShortcutStateCoordinator;
  recentlyClosedApplicationCoordinator: BrowserRecentlyClosedApplicationCoordinator;
  restoreRecentlyClosedRecord: (recordId: string) => void;
  transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  themeModeCoordinator: BrowserThemeModeCoordinator;
  themePaletteService: BrowserThemePaletteService;
  tabsOverviewThemeViewModel: BrowserTabsOverviewThemeViewModel;
  homeWallpaperCoordinator: HomeWallpaperCoordinator;
  wallpaperRepository: WallpaperRepository;
  backdropEffectViewModel: BrowserBackdropEffectViewModel;
  homepageBackdropAppearanceCoordinator: BrowserHomepageBackdropAppearanceCoordinator;
  arkWebMediaTakeoverCoordinator: BrowserArkWebMediaTakeoverCoordinator;
  fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator;
}

interface BrowserTabsOverviewDismissHomeRequest {
  activeTab: BrowserTabState | undefined;
  activeTabId: string;
  runtimeDegradedMessage: string;
  tabs: BrowserTabState[];
}

interface BrowserTabsOverviewHomeTabCreationApplication {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  createdTabId: string;
  helperMessage: string;
  options: BrowserCreateTabOptions;
  keepTabsOverviewMounted: boolean;
  playHomeReveal: boolean;
}

interface BrowserDegradeBrokenActiveTabRequest {
  tabId: string;
  snapshotPath: string;
  degradedReason: string;
}

interface BrowserGoHomeApplicationResult {
  tabId: string;
  nextActiveTabId: string;
  visualState: BrowserShellVisualState;
  tabs: BrowserTabState[];
}

interface BrowserDegradeBrokenActiveTabApplicationResult {
  tabId: string;
  runtimeDegradedMessage: string;
  tabPatch: BrowserTabRuntimePatch;
  toastMessage: string;
}

export interface BrowserTabHomeContentPresentationFacts {
  responsiveLayout: HomeResponsiveLayoutState;
  shortcuts: HomeShortcutApplicationSnapshot;
  recentlyClosed: BrowserRecentlyClosedApplicationSnapshot;
  viewportWidth: number;
  viewportHeight: number;
  bottomPanelLowHeight: number;
  privateMode: boolean;
}

export interface BrowserTabHomeContentThemeFacts {
  wallpaperState: HomeWallpaperPresentationState;
  themeBackgroundColor: ResourceColor;
  themedPrimaryTextColor: ResourceColor;
  themedSecondaryTextColor: ResourceColor;
  themedPressedBackgroundColor: ResourceColor;
  controlBackgroundColor: ResourceColor;
  accentColor: ResourceColor;
}

export class BrowserTabHomeCoordinator {
  private readonly dependencies: BrowserTabHomeDependencies;
  private readonly shell: BrowserTabHomeShell;
  private shellStateCoordinator: BrowserShellStateCoordinator = new BrowserShellStateCoordinator();
  private readonly homeWallpaperInteractionColorViewModel: HomeWallpaperInteractionColorViewModel =
    new HomeWallpaperInteractionColorViewModel();
  private readonly browserForegroundPresentationViewModel: BrowserForegroundPresentationViewModel =
    new BrowserForegroundPresentationViewModel();
  private readonly homeSurfaceProfileViewModel: BrowserHomeSurfaceProfileViewModel =
    new BrowserHomeSurfaceProfileViewModel();
  private readonly homeResponsiveLayoutViewModel: HomeResponsiveLayoutViewModel =
    new HomeResponsiveLayoutViewModel();
  private readonly homeChromeScrollCoordinator: BrowserHomeChromeScrollCoordinator =
    new BrowserHomeChromeScrollCoordinator();
  private readonly searchEnginePresentationViewModel: BrowserSearchEnginePresentationViewModel =
    new BrowserSearchEnginePresentationViewModel();
  private deferredWorkRunId: number = 0;
  private deferredWorkTimer: number = -1;
  private optimisticThemeModeOverride: BrowserThemeMode | '' = '';

  constructor(dependencies: BrowserTabHomeDependencies, shell: BrowserTabHomeShell) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  handleContentAction(action: BrowserTabHomeContentAction): void {
    if (action.type === 'shortcut') {
      if (action.shortcutAction !== undefined) {
        this.dependencies.homeShortcutStateCoordinator.handleUserAction(action.shortcutAction);
      }
      return;
    }
    if (action.type === 'open_shortcut_picker') {
      this.dependencies.homeShortcutStateCoordinator.openSelectionSession();
      return;
    }
    if (action.type === 'recently_closed') {
      if (action.recentlyClosedAction !== undefined) {
        this.dependencies.recentlyClosedApplicationCoordinator.handleUserAction(action.recentlyClosedAction);
      }
      return;
    }
    if (action.type === 'restore_recently_closed') {
      if (action.recordId !== undefined) {
        this.dependencies.restoreRecentlyClosedRecord(action.recordId);
      }
      return;
    }
    if (action.type === 'open_home_settings') {
      this.shell.applyState({ endSearchInvocation: true });
      this.dependencies.transientSurfaceCoordinator.openSystemSheet('homeSettings');
      return;
    }
    if (action.type === 'scroll_stop') {
      this.homeChromeScrollCoordinator.finishNativeHomeScroll();
      return;
    }
    const facts = this.shell.resolveHomeScrollActionFacts();
    const state = this.shell.readState();
    const profile = this.buildHomeSurfaceProfile();
    const scrollBehavior =
      this.dependencies.preferencesRepository.getPreferences().appearance.bottomToolbarScrollBehavior;
    const decision = this.homeChromeScrollCoordinator.handleScrollEvent({
      profile: profile,
      customHomepageState: state.customHomepageRuntimeState.presentation,
      interaction: facts.input,
      currentPresentation: facts.currentPresentation,
      scrollBehavior: scrollBehavior
    }, {
      type: 'move',
      source: action.scrollSource ?? 'system',
      scrollOffsetY: action.scrollOffsetY ?? 0,
      nativeAtEnd: action.scrollAtEnd
    });
    if (decision !== undefined) {
      this.shell.applyHomeScrollDecision(decision);
    }
  }

  resetHomeScrollChrome(): void {
    this.homeChromeScrollCoordinator.reset();
  }

  schedulePromptEvaluations(): void {
    this.dependencies.appReviewPromptCoordinator.scheduleEvaluation();
    this.dependencies.resolveReleaseNoticePresentationCoordinator().scheduleEvaluation();
  }

  buildResponsiveLayoutState(
    input: HomeResponsiveLayoutInput,
    shortcutLayoutDensity: BrowserHomeShortcutLayoutDensity
  ): HomeResponsiveLayoutState {
    return this.homeResponsiveLayoutViewModel.buildState(input, shortcutLayoutDensity);
  }

  resolveCustomHomepageErrorBottomInset(
    responsiveLayout: HomeResponsiveLayoutState,
    bottomPanelLowHeight: number
  ): number {
    return Math.max(0, bottomPanelLowHeight) + responsiveLayout.bottomSpacerExtra;
  }

  buildContentPresentation(
    facts: BrowserTabHomeContentPresentationFacts
  ): HomeContentSectionsPresentationState {
    const layout = facts.responsiveLayout;
    return {
      showRecentlyClosed: this.dependencies.recentlyClosedApplicationCoordinator.shouldShowHomeSection(
        facts.recentlyClosed,
        facts.privateMode
      ),
      centerContentVertically: layout.centerContentVertically,
      useSharedSectionWidth: layout.useSharedSectionWidth,
      horizontalPadding: layout.contentHorizontalPadding,
      contentTopPadding: layout.contentTopPadding,
      sectionVerticalGap: layout.sectionVerticalGap,
      bottomSpacerHeight: layout.centerContentVertically
        ? layout.bottomSpacerExtra
        : facts.bottomPanelLowHeight + layout.bottomSpacerExtra,
      shortcuts: this.dependencies.homeShortcutStateCoordinator.buildPresentationState(
        facts.shortcuts,
        {
          viewportWidth: facts.viewportWidth,
          viewportHeight: facts.viewportHeight,
          gridWidth: layout.shortcutGridWidth,
          gridTopInset: layout.shortcutGridTopInset,
          metrics: layout.shortcutMetrics
        }
      ),
      recentlyClosed: this.dependencies.recentlyClosedApplicationCoordinator.buildHomePresentationState(
        facts.recentlyClosed,
        {
          columns: layout.recentlyClosedColumns,
          columnGap: layout.recentlyClosedColumnGap,
          rowGap: layout.recentlyClosedRowGap
        }
      )
    };
  }

  buildContentThemePresentation(
    facts: BrowserTabHomeContentThemeFacts
  ): HomeContentThemePresentationState {
    const foreground = this.buildForegroundPresentation(facts);
    const interactionColors = this.homeWallpaperInteractionColorViewModel.resolveInteractionColors(
      facts.wallpaperState,
      facts.themedPressedBackgroundColor
    );
    return {
      tone: foreground.tone,
      primaryTextColor: foreground.primaryTextColor,
      secondaryTextColor: foreground.secondaryTextColor,
      iconColor: foreground.iconColor,
      iconTone: foreground.iconTone,
      textShadow: foreground.textShadow,
      freshnessKey: foreground.freshnessKey,
      pressedBackgroundColor: interactionColors.pressedBackgroundColor,
      pressedBackdropBlurRadius: interactionColors.pressedBackdropBlurRadius,
      controlBackgroundColor: facts.controlBackgroundColor,
      accentColor: facts.accentColor
    };
  }

  buildForegroundPresentation(
    facts: BrowserTabHomeContentThemeFacts
  ): BrowserForegroundPresentation {
    const state = this.shell.readState();
    const profile = this.buildHomeSurfaceProfile();
    return this.browserForegroundPresentationViewModel.resolveHomePresentation({
      foregroundBackdropSource: profile.foregroundBackdropSource,
      backdropAppearanceState: this.resolveCurrentHomepageBackdropAppearanceState(
        state.homepageBackdropAppearanceState,
        state.homepageBackdropPrivateMode
      ),
      wallpaperState: facts.wallpaperState,
      themeBackgroundColor: facts.themeBackgroundColor,
      themedPrimaryTextColor: facts.themedPrimaryTextColor,
      themedSecondaryTextColor: facts.themedSecondaryTextColor
    });
  }

  buildWebForegroundBackdropRevision(tabId: string): string {
    const normalizedTabId = tabId.trim();
    const state = this.shell.readState();
    const tab = state.tabs.find((candidate: BrowserTabState) => candidate.id === normalizedTabId);
    if (tab === undefined) {
      return `${normalizedTabId}:missing`;
    }
    return `${tab.id}:${tab.url}:${tab.title}:${tab.navigationIndex}:${tab.lastLoadedAt}:${tab.webStateUpdatedAt}`;
  }

  buildHomeSurfaceProfile(homeVisibleOverride?: boolean): BrowserHomeSurfaceProfile {
    const state = this.shell.readState();
    return this.homeSurfaceProfileViewModel.buildProfile({
      showHomePage: homeVisibleOverride ?? state.showHomePage,
      webPageVisible: !state.showHomePage,
      thirdPartyHomepageAllowed: !state.currentBoundaryPrivate,
      customHomepageState: state.customHomepageRuntimeState.presentation,
      customHomepageWebVisible: state.customHomepageRuntimeState.surfaceVisible
    });
  }

  buildHomeSystemChromePolicyState(
    homeVisibleOverride?: boolean
  ): BrowserHomeSystemChromePolicyState {
    const state = this.shell.readState();
    const profile = this.buildHomeSurfaceProfile(homeVisibleOverride);
    const scrollBehavior =
      this.dependencies.preferencesRepository.getPreferences().appearance.bottomToolbarScrollBehavior;
    return {
      scene: profile.scene,
      homeSystemSearchEligible: profile.bottomSearchVisible,
      systemEntryButtonVisible: profile.systemEntryButtonVisible,
      homeScrollMode: this.homeChromeScrollCoordinator.resolvePolicyMode(
        profile,
        state.customHomepageRuntimeState.presentation,
        scrollBehavior
      ),
      bottomPanelHomeSearchVisible: profile.bottomSearchVisible,
      expandedToolbarBackdropRequired: profile.expandedToolbarBackdropRequired
    };
  }

  applyHomeSystemChromePolicyTransition(
    previousPolicy: BrowserHomeSystemChromePolicyState,
    nextPolicy: BrowserHomeSystemChromePolicyState
  ): void {
    if (previousPolicy.scene === nextPolicy.scene &&
      previousPolicy.bottomPanelHomeSearchVisible === nextPolicy.bottomPanelHomeSearchVisible &&
      previousPolicy.homeScrollMode === nextPolicy.homeScrollMode &&
      previousPolicy.expandedToolbarBackdropRequired === nextPolicy.expandedToolbarBackdropRequired &&
      previousPolicy.systemEntryButtonVisible === nextPolicy.systemEntryButtonVisible) {
      return;
    }
    const searchBecameHidden = previousPolicy.bottomPanelHomeSearchVisible &&
      !nextPolicy.bottomPanelHomeSearchVisible;
    const homeScrollModeChanged = previousPolicy.homeScrollMode !== nextPolicy.homeScrollMode;
    if (homeScrollModeChanged) {
      this.dependencies.resolveRootBottomPanelSessionCoordinator().restoreScrollPresentation();
      this.resetHomeScrollChrome();
    }
    if (searchBecameHidden) {
      const transientSearchActive = this.shell.readState().homeSearchFocused;
      if (transientSearchActive) {
        return;
      }
      this.shell.applyState({ endSearchInvocation: true });
      this.dependencies.searchSuggestionCoordinator.reset();
      const rootBottomPanel = this.dependencies.resolveRootBottomPanelSessionCoordinator();
      rootBottomPanel.resetDeferredDetentTransition();
      rootBottomPanel.invalidatePresentation();
      if (!homeScrollModeChanged) {
        rootBottomPanel.restoreScrollPresentation();
        this.resetHomeScrollChrome();
      }
      this.shell.applyState({ resetHomeSearchPresentation: true });
      this.shell.syncBottomPanelStatusBarStyle();
    }
  }

  loadSearchEngineSelection(): void {
    this.publishSearchEngineSelection(
      this.dependencies.searchEngineSelectionCoordinator.getSnapshot(
        this.shell.readState().currentDataScope
      )
    );
  }

  handleSearchEngineSettingsRevision(): void {
    this.loadSearchEngineSelection();
    this.synchronizeSearchEngineSelectionDependents();
  }

  applySearchEngineSelectionSnapshot(snapshot: SearchEngineSelectionSnapshot): void {
    this.publishSearchEngineSelection(snapshot);
  }

  buildSearchEngineChromePresentation(
    selectedSearchEngine: SearchEngineId,
    availableSearchEngines: SearchEngineRecord[]
  ): BrowserSearchEngineChromePresentation {
    return this.searchEnginePresentationViewModel.buildChromePresentation(
      selectedSearchEngine,
      availableSearchEngines
    );
  }

  selectSearchEngine(searchEngineId: SearchEngineId): void {
    void this.dependencies.searchEngineSelectionCoordinator.select(
      searchEngineId,
      this.shell.readState().currentDataScope
    )
      .then((snapshot: SearchEngineSelectionSnapshot): void => {
        this.publishSearchEngineSelection(snapshot);
        this.synchronizeSearchEngineSelectionDependents();
      })
      .catch((error: Error): void => {
        this.shell.applyState({
          errorMessage: `搜索引擎保存失败：${JSON.stringify(error)}`
        });
      });
  }

  showHomeSurface(
    helperMessage: string,
    boundary: BrowserCreateTabOptions,
    keepTabsOverviewMounted: boolean = false,
    playHomeReveal: boolean = true
  ): void {
    const state = this.shell.readState();
    const shouldPlayHomeReveal = playHomeReveal && !state.showHomePage;
    this.prepareHomePresentation(!keepTabsOverviewMounted, shouldPlayHomeReveal);
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    this.shell.cancelBottomPanelBackdropFocusTransition();
    this.applyBoundary(
      boundary.profileId ?? DEFAULT_BROWSER_PROFILE_ID,
      privacyMode,
      normalizeBrowserDataScope(boundary.dataScope, privacyMode)
    );
    this.shell.applyState({ invalidateWebSessionTransition: true });
    this.shell.applyState({ resetHomeTransientUiState: true });
    if (state.showTabsSheet && !keepTabsOverviewMounted) {
      this.dependencies.resolveTabsOverviewSessionCoordinator().handle({
        type: 'close_to_home_without_sheet_exit'
      });
    } else {
      this.shell.restoreHomeBottomPanel('low');
    }
    this.shell.applyState({
      visualState: this.shellStateCoordinator.buildHomeState(this.shell.readState().runtimeDegradedMessage),
      helperMessage: helperMessage,
      clearNavigationState: true,
      clearControllerAttachment: true
    });
    this.dependencies.resolveRootBottomPanelSessionCoordinator().showTransientMessage(
      helperMessage,
      this.shell.readState().bottomAddressTransientMessageContext
    );
    if (shouldPlayHomeReveal) {
      this.dependencies.resolveHomePresentationSessionCoordinator().playReveal({
        fadeBackdrop: true
      });
    }
    this.scheduleDeferredWork(shouldPlayHomeReveal || !state.showHomePage);
  }

  prepareDirectHomeReveal(): void {
    this.prepareHomePresentation(true, true);
  }

  applyBoundary(
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): void {
    const previousState = this.shell.readState();
    const searchEngineSelection = this.dependencies.searchEngineSelectionCoordinator.handleBoundaryChange(
      previousState.homeDataScope,
      dataScope
    );
    this.shell.applyState({
      boundaryState: {
        profileId: profileId,
        privacyMode: privacyMode,
        dataScope: dataScope,
        searchEngineSelection: searchEngineSelection
      }
    });
    this.shell.syncThemeAppStorage();
    this.refreshAppearance();
    this.dependencies.customHomepageRuntimeCoordinator.syncPrivacyBoundaryBridge();
    this.dependencies.customHomepageRuntimeCoordinator.syncBridge('search_engines');
    this.shell.syncBottomPanelStatusBarStyle();
  }

  refreshAppearance(): void {
    const state = this.shell.readState();
    const preferences = this.dependencies.preferencesRepository.getPreferences();
    const resolvedThemeMode = this.dependencies.themeModeCoordinator.resolveEffectiveMode(state.optimisticThemeMode);
    this.dependencies.customHomepageRuntimeCoordinator.updateThemePreferences({
      themePaletteId: preferences.appearance.themePaletteId
    });
    this.dependencies.recentlyClosedApplicationCoordinator.refreshAppearance();
    this.shell.applyState({
      appearanceState: {
        showHomeShortcuts: preferences.appearance.showHomeShortcuts,
        homeShortcutLayoutDensity: preferences.appearance.homeShortcutLayoutDensity,
        homeTokens: this.dependencies.themePaletteService.resolveTokens(
          preferences.appearance.themePaletteId,
          resolvedThemeMode
        ),
        tabsOverviewThemeState: this.buildTabsOverviewThemeState(
          resolvedThemeMode
        )
      }
    });
    this.refreshBackdropAppearance('home_appearance');
    this.shell.syncBottomPanelStatusBarStyle();
  }

  resolveOptimisticThemeMode(): BrowserThemeMode {
    if (this.optimisticThemeModeOverride !== '') {
      return this.optimisticThemeModeOverride;
    }
    return this.dependencies.themeModeCoordinator.resolveCurrentMode();
  }

  clearOptimisticThemeModeOverride(): void {
    this.optimisticThemeModeOverride = '';
  }

  async toggleThemeModeFromBottomPanel(): Promise<void> {
    const currentMode = this.resolveOptimisticThemeMode();
    const nextMode = this.dependencies.themeModeCoordinator.resolveNextMode(currentMode);
    const previousOptimisticMode = this.optimisticThemeModeOverride;
    this.optimisticThemeModeOverride = nextMode;
    this.shell.applyState({ incrementThemeModeActionVersion: true });
    this.refreshAppearance();
    try {
      const state = this.shell.readState();
      const result = await this.dependencies.themeModeCoordinator.setThemeModeForBoundary(
        nextMode,
        {
          privacyMode: state.currentPrivacyMode,
          dataScope: state.currentDataScope
        }
      );
      if (!result.allowed) {
        this.optimisticThemeModeOverride = previousOptimisticMode;
        this.shell.applyState({ incrementThemeModeActionVersion: true });
        this.refreshAppearance();
        this.shell.applyState({ themeModeToastMessage: result.message });
        return;
      }
      this.optimisticThemeModeOverride = '';
      this.shell.applyState({ incrementThemeModeActionVersion: true });
      this.refreshAppearance();
      this.shell.applyState({ themeModeToastMessage: `已切换为${
        this.dependencies.resolveRootBottomPanelSessionCoordinator().resolveThemeModeActionTitleForMode(result.mode)
      }。` });
    } catch (_error) {
      this.optimisticThemeModeOverride = previousOptimisticMode;
      this.shell.applyState({ incrementThemeModeActionVersion: true });
      this.refreshAppearance();
      this.shell.applyState({ themeModeToastMessage: '外观模式更新失败。' });
    }
  }

  refreshWallpaperPresentation(): void {
    const state = this.shell.readState();
    this.dependencies.homeWallpaperCoordinator.refreshForHomeVisible(
      state.viewportWidth,
      state.viewportHeight,
      state.homeSearchFocused
    )
      .then((result: HomeWallpaperRefreshResult) => {
        this.shell.applyState({ homeWallpaperState: result.state });
        this.refreshBackdropAppearance('home_wallpaper');
        if (result.presentationChanged) {
          this.shell.syncBottomPanelStatusBarStyle();
        }
      })
      .catch((_error: Error) => {});
  }

  refreshBackdropAppearance(reason: string): void {
    const state = this.shell.readState();
    void this.dependencies.homepageBackdropAppearanceCoordinator.sync({
      source: this.buildHomepageBackdropAppearanceSource(state.homepageBackdropPrivateMode),
      effect: this.buildHomepageBackdropAppearanceEffect()
    }).then((nextState: BrowserHomepageBackdropAppearanceState) => {
      const latest = this.shell.readState();
      const previousKey = this.dependencies.homepageBackdropAppearanceCoordinator.buildStateRenderKey(
        latest.homepageBackdropAppearanceState
      );
      const nextKey = this.dependencies.homepageBackdropAppearanceCoordinator.buildStateRenderKey(nextState);
      if (previousKey === nextKey) {
        return;
      }
      this.shell.applyState({
        homepageBackdropAppearanceState: cloneBrowserHomepageBackdropAppearanceState(nextState),
        tabsOverviewThemeState: this.buildTabsOverviewThemeState(
          nextState.resolvedThemeMode
        )
      });
      hilog.info(
        TAB_HOME_LOG_DOMAIN,
        TAB_HOME_LOG_TAG,
        'homepage backdrop appearance applied reason=%{public}s available=%{public}s key=%{public}s signature=%{public}s',
        reason,
        nextState.available ? 'true' : 'false',
        nextState.sourceKey,
        nextState.snapshotSignature
      );
    }).catch((error: Error) => {
      hilog.warn(
        TAB_HOME_LOG_DOMAIN,
        TAB_HOME_LOG_TAG,
        'homepage backdrop appearance cache sync failed reason=%{public}s error=%{public}s',
        reason,
        JSON.stringify(error)
      );
    });
  }

  refreshTabsOverviewAppearance(): void {
    const state = this.shell.readState();
    const effectiveMode = this.dependencies.themeModeCoordinator.resolveEffectiveMode(state.optimisticThemeMode);
    this.shell.applyState({
      tabsOverviewThemeState: this.buildTabsOverviewThemeState(
        effectiveMode
      )
    });
  }

  async goHome(): Promise<void> {
    const state = this.shell.readState();
    const activeTab = this.findTabById(state.tabs, state.activeTabId);
    const shouldPlayDirectHomeReveal = !state.showTabsSheet;
    this.prepareHomePresentation(!state.showTabsSheet, !state.showHomePage && shouldPlayDirectHomeReveal);
    if (state.showHomePage) {
      this.shell.applyState({ resetHomeTransientUiState: true });
      this.completeDirectHomeNavigation('low', false);
      this.scheduleDeferredWork(false);
      return;
    }
    const tabId = activeTab?.id ?? state.activeTabId;
    if (activeTab !== undefined && !activeTab.isHome) {
      this.dependencies.webTabsController.stopLoading(tabId);
      this.dependencies.offlineFastFailureCoordinator.cancelForTab(tabId);
      this.applyGoHomeApplicationResult(
        this.buildGoHomeApplicationResult(tabId, state.runtimeDegradedMessage, state.tabs)
      );
    } else {
      this.applyDirectHomeSurface(tabId, state.runtimeDegradedMessage);
    }
    this.completeDirectHomeNavigation(
      shouldPlayDirectHomeReveal ? 'peek' : 'low',
      shouldPlayDirectHomeReveal
    );
  }

  reloadHome(): void {
    const profile = this.buildHomeSurfaceProfile(true);
    if (profile.renderer === 'web_home') {
      this.dependencies.customHomepageRuntimeCoordinator.refresh(true, true);
      return;
    }
    this.dependencies.homeShortcutStateCoordinator.refresh();
    this.dependencies.searchSuggestionCoordinator.refresh();
    this.refreshWallpaperPresentation();
    this.refreshAppearance();
  }

  dismissTabsOverviewToHome(request: BrowserTabsOverviewDismissHomeRequest): void {
    const tabId = request.activeTab?.id ?? request.activeTabId;
    if (request.activeTab === undefined || tabId.trim().length <= 0) {
      this.shell.applyState({
        visualState: this.shellStateCoordinator.buildHomeState(request.runtimeDegradedMessage)
      });
      return;
    }
    this.applyGoHomeApplicationResult(
      this.buildGoHomeApplicationResult(tabId, request.runtimeDegradedMessage, request.tabs)
    );
  }

  applyTabsOverviewHomeTabCreation(application: BrowserTabsOverviewHomeTabCreationApplication): void {
    this.persistActiveTabSnapshot('create-home-tab');
    this.shell.applyState({ tabsForOverviewPreviewSync: application.tabs });
    this.dependencies.tabSwitchCoordinator.synchronizeWebTabsAndPreviewAssets();
    this.shell.applyState({
      activeTabId: application.activeTabId,
      tabSequence: application.tabSequence
    });
    this.showHomeSurface(
      application.helperMessage,
      application.options,
      application.keepTabsOverviewMounted,
      application.playHomeReveal
    );
  }

  async degradeBrokenActiveTab(request: BrowserDegradeBrokenActiveTabRequest): Promise<void> {
    const degradedResult = this.buildDegradeBrokenActiveTabApplicationResult(request);
    this.dependencies.runtimeMutationPort.terminateRenderProcess(degradedResult.tabId);
    this.shell.applyState({
      runtimeDegradedMessage: degradedResult.runtimeDegradedMessage
    });
    this.dependencies.tabSwitchCoordinator.applyTabPatch(degradedResult.tabId, degradedResult.tabPatch, {
      persistTabs: false
    });
    this.shell.showToast(degradedResult.toastMessage);
    if (request.snapshotPath.trim().length > 0) {
      await this.dependencies.snapshotStore.deleteSnapshot(request.snapshotPath);
      this.dependencies.tabRecoveryCoordinator.applySnapshotApplicationResult(
        this.dependencies.tabRecoveryCoordinator.buildSnapshotDeleteApplicationResult(
          degradedResult.tabId,
          request.snapshotPath,
          'home_reset',
          {
            shouldClearTabSnapshot: true,
            shouldRecordRuntimeEvent: false
          }
        ),
        this.dependencies.snapshotApplicationHost,
        this.shell.readState().activeTabId
      );
    }
    const visualState = this.shellStateCoordinator.buildHomeState(degradedResult.runtimeDegradedMessage);
    this.dependencies.hostedRuntimeSurfacePort.detachActive();
    this.shell.applyState({
      visualState: visualState,
      resetHomeTransientUiState: true,
      clearNavigationState: true,
      clearControllerAttachment: true,
      invalidateWebSessionTransition: true
    });
    this.clearWebEventContext(degradedResult.tabId);
    this.dependencies.webpageTranslationCoordinator.handleTabDestroyedForRuntimeTab(
      degradedResult.tabId,
      this.shell.readState().activeTabId,
      true
    );
    this.dependencies.hostedRuntimeSurfacePort.release(degradedResult.tabId, 'recovery_degraded_home');
    this.dependencies.runtimeLifecyclePort.removeClosedTabRuntime(degradedResult.tabId, 'recovery_degraded_home');
    this.clearVideoAssistantForTab(degradedResult.tabId);
    this.shell.applyState({
      activeTabId: ''
    });
    this.dependencies.tabSwitchCoordinator.commitTabs([], {
      persistTabs: false,
      refreshRuntimeTabIds: []
    });
    this.scheduleDeferredWork(true);
  }

  private buildGoHomeApplicationResult(
    tabId: string,
    runtimeDegradedMessage: string,
    tabs: BrowserTabState[]
  ): BrowserGoHomeApplicationResult {
    return {
      tabId: tabId,
      nextActiveTabId: tabId,
      visualState: this.shellStateCoordinator.buildHomeState(runtimeDegradedMessage),
      tabs: tabs.map((tab: BrowserTabState) => this.cloneTabWithPatch(tab, {
        runtimeState: tab.id === tabId || tab.runtimeState === 'active' ? 'background' : tab.runtimeState,
        lastActiveAt: tab.id === tabId ? Date.now() : tab.lastActiveAt
      }))
    };
  }

  private applyGoHomeApplicationResult(result: BrowserGoHomeApplicationResult): void {
    this.dependencies.hostedRuntimeSurfacePort.detachActive();
    this.shell.applyState({
      activeTabId: result.nextActiveTabId,
      resetHomeTransientUiState: true
    });
    this.dependencies.tabSwitchCoordinator.commitTabs(result.tabs, {
      persistTabs: false,
      refreshRuntimeTabIds: []
    });
    this.shell.applyState({
      visualState: result.visualState,
      clearNavigationState: true,
      clearControllerAttachment: true,
      invalidateWebSessionTransition: true
    });
    this.clearWebEventContext(result.tabId);
    this.scheduleDeferredWork(true);
  }

  private applyDirectHomeSurface(tabId: string, runtimeDegradedMessage: string): void {
    this.dependencies.hostedRuntimeSurfacePort.detachActive();
    this.shell.applyState({
      visualState: this.shellStateCoordinator.buildHomeState(runtimeDegradedMessage),
      resetHomeTransientUiState: true,
      clearNavigationState: true,
      clearControllerAttachment: true,
      invalidateWebSessionTransition: true
    });
    this.clearWebEventContext(tabId);
    this.scheduleDeferredWork(true);
  }

  private buildDegradeBrokenActiveTabApplicationResult(
    request: BrowserDegradeBrokenActiveTabRequest
  ): BrowserDegradeBrokenActiveTabApplicationResult {
    const runtimeDegradedMessage = request.degradedReason.trim().length > 0
      ? request.degradedReason
      : DEFAULT_DEGRADED_HOME_MESSAGE;
    return {
      tabId: request.tabId,
      runtimeDegradedMessage: runtimeDegradedMessage,
      tabPatch: {
        lastCrashReason: 'recovery_degraded_to_home'
      },
      toastMessage: '当前标签页恢复异常，已回到首页保护其他标签页。'
    };
  }

  private prepareHomePresentation(
    shouldResetTabsBackdropHomeReveal: boolean,
    shouldPrepareHomeReveal: boolean
  ): void {
    this.dependencies.tabPreviewCoordinator.cancelScheduledCapture();
    const tabsOverviewSessionCoordinator = this.dependencies.resolveTabsOverviewSessionCoordinator();
    tabsOverviewSessionCoordinator.resetSharedSnapshotState();
    tabsOverviewSessionCoordinator.handle({ type: 'cancel_shared_snapshot_entry' });
    if (shouldResetTabsBackdropHomeReveal) {
      tabsOverviewSessionCoordinator.resetBackdropPresentation();
    }
    if (shouldPrepareHomeReveal) {
      this.dependencies.resolveHomePresentationSessionCoordinator().prepareDirectReveal();
    }
  }

  private scheduleDeferredWork(revealExpected: boolean): void {
    const runId = ++this.deferredWorkRunId;
    if (this.deferredWorkTimer >= 0) {
      clearTimeout(this.deferredWorkTimer);
      this.deferredWorkTimer = -1;
    }
    const delayMs = revealExpected
      ? HOME_SURFACE_REVEAL_DEFERRED_WORK_DELAY_MS
      : HOME_SURFACE_STEADY_DEFERRED_WORK_DELAY_MS;
    this.deferredWorkTimer = setTimeout(() => {
      this.deferredWorkTimer = -1;
      if (this.deferredWorkRunId !== runId) {
        return;
      }
      this.runDeferredHomeSurfaceWork();
    }, delayMs);
  }

  private persistActiveTabSnapshot(reason: string): void {
    void this.dependencies.tabRecoveryCoordinator.runActiveSnapshotPersistFromHost(
      this.dependencies.snapshotStore,
      reason,
      this.dependencies.snapshotPersistenceHost,
      this.shell.readState().controllerAttached
    );
  }

  private completeDirectHomeNavigation(detent: 'peek' | 'low', playHomeReveal: boolean): void {
    this.shell.restoreHomeBottomPanel(detent);
    if (playHomeReveal) {
      this.dependencies.resolveHomePresentationSessionCoordinator().playReveal({
        fadeBackdrop: true,
        restoreBottomPanelFromPeek: true
      });
    }
  }

  private runDeferredHomeSurfaceWork(): void {
    const state = this.shell.readState();
    this.dependencies.webRecoveryManager.pruneTabs(state.tabs.map((tab: BrowserTabState) => tab.id));
    this.dependencies.customHomepageRuntimeCoordinator.refresh(false, true);
    this.dependencies.customHomepageRuntimeCoordinator.syncBridge('privacy');
    this.dependencies.backgroundSessionSyncCoordinator.sync();
    this.dependencies.tabSessionPersistenceCoordinator.persist();
    this.refreshWallpaperPresentation();
    this.dependencies.searchSuggestionCoordinator.prewarm();
    this.schedulePromptEvaluations();
  }

  private buildTabsOverviewThemeState(resolvedThemeMode: BrowserResolvedThemeMode): BrowserTabsOverviewThemeState {
    return this.dependencies.tabsOverviewThemeViewModel.buildState({
      preferences: this.dependencies.preferencesRepository.getPreferences(),
      resolvedThemeMode: resolvedThemeMode,
      paletteService: this.dependencies.themePaletteService
    });
  }

  private publishSearchEngineSelection(snapshot: SearchEngineSelectionSnapshot): void {
    this.shell.applyState({ searchEngineSelection: snapshot });
  }

  private synchronizeSearchEngineSelectionDependents(): void {
    this.dependencies.searchSuggestionCoordinator.refresh();
    this.dependencies.customHomepageRuntimeCoordinator.syncBridge('search_engines');
  }

  private buildHomepageBackdropAppearanceSource(privateMode: boolean): BrowserHomepageBackdropAppearanceSource {
    const preferences = this.dependencies.preferencesRepository.getPreferences();
    return this.dependencies.homepageBackdropAppearanceCoordinator.buildSource({
      customHomepageSettings: this.dependencies.customHomepageRuntimeCoordinator.getShellState().settings,
      wallpaperSnapshot: this.dependencies.wallpaperRepository.getSnapshot(),
      preferences: preferences,
      resolvedThemeMode: this.dependencies.themeModeCoordinator.resolveEffectiveMode(preferences.themeMode),
      privateMode: privateMode
    });
  }

  private buildHomepageBackdropAppearanceEffect(): BrowserHomepageBackdropAppearanceEffectInput {
    const preferences = this.dependencies.preferencesRepository.getPreferences();
    const resolvedThemeMode = this.dependencies.themeModeCoordinator.resolveEffectiveMode(preferences.themeMode);
    const effectState = this.dependencies.backdropEffectViewModel.buildWebSnapshotState(1, resolvedThemeMode);
    return this.dependencies.homepageBackdropAppearanceCoordinator.buildEffect({
      resolvedThemeMode: resolvedThemeMode,
      tintColor: effectState.tintColor,
      tintOpacity: effectState.tintOpacity
    });
  }

  private resolveCurrentHomepageBackdropAppearanceState(
    state: BrowserHomepageBackdropAppearanceState,
    privateMode: boolean
  ): BrowserHomepageBackdropAppearanceState | undefined {
    const source = this.buildHomepageBackdropAppearanceSource(privateMode);
    const effect = this.buildHomepageBackdropAppearanceEffect();
    const expectedSourceKey = this.dependencies.homepageBackdropAppearanceCoordinator.buildSourceKey(source, effect);
    return state.sourceKey === expectedSourceKey ? state : undefined;
  }

  private clearVideoAssistantForTab(tabId: string): void {
    const webLiveWasActive = this.dependencies.arkWebMediaTakeoverCoordinator.clearTab(tabId);
    if (webLiveWasActive) {
      void this.dependencies.fullscreenSessionCoordinator.exitVideoAssistantFullscreen(false, false);
    }
    this.shell.applyState({ incrementArkWebMediaTakeoverRevision: true });
  }

  private clearWebEventContext(tabId: string): void {
    this.dependencies.webEventRouter.beginNavigation(
      tabId,
      this.dependencies.visibleUrlService.resolveVisibleUrl(''),
      false
    );
  }

  private findTabById(tabs: BrowserTabState[], tabId: string): BrowserTabState | undefined {
    return tabs.find((tab: BrowserTabState) => tab.id === tabId);
  }

  private cloneTabWithPatch(tab: BrowserTabState, patch: BrowserTabRuntimePatch): BrowserTabState {
    return {
      id: tab.id,
      profileId: patch.profileId ?? tab.profileId,
      title: patch.title ?? tab.title,
      url: patch.url ?? tab.url,
      isHome: patch.isHome ?? tab.isHome,
      lastActiveAt: patch.lastActiveAt ?? tab.lastActiveAt,
      pendingUrl: patch.pendingUrl ?? tab.pendingUrl,
      navigationHistory: patch.navigationHistory ?? tab.navigationHistory.slice(),
      navigationIndex: patch.navigationIndex ?? tab.navigationIndex,
      runtimeState: patch.runtimeState ?? tab.runtimeState,
      lastError: patch.lastError ?? tab.lastError,
      lastRestoreReason: patch.lastRestoreReason ?? tab.lastRestoreReason,
      lastDiscardReason: patch.lastDiscardReason ?? tab.lastDiscardReason,
      lastCrashReason: patch.lastCrashReason ?? tab.lastCrashReason,
      lastLoadedAt: patch.lastLoadedAt ?? tab.lastLoadedAt,
      webStatePath: patch.webStatePath ?? tab.webStatePath,
      webStateUpdatedAt: patch.webStateUpdatedAt ?? tab.webStateUpdatedAt,
      scrollOffsetY: patch.scrollOffsetY ?? tab.scrollOffsetY,
      lastGoodUrl: patch.lastGoodUrl ?? tab.lastGoodUrl,
      lastGoodTitle: patch.lastGoodTitle ?? tab.lastGoodTitle,
      lastRestorableUrl: patch.lastRestorableUrl ?? tab.lastRestorableUrl,
      lastRestorableTitle: patch.lastRestorableTitle ?? tab.lastRestorableTitle,
      lastRestoreType: patch.lastRestoreType ?? tab.lastRestoreType,
      privacyMode: patch.privacyMode ?? tab.privacyMode,
      dataScope: patch.dataScope ?? tab.dataScope,
      launchContext: patch.launchContext ?? tab.launchContext,
      openerTabId: patch.openerTabId ?? tab.openerTabId,
      openSource: patch.openSource ?? tab.openSource,
      openedByNewWindow: patch.openedByNewWindow ?? tab.openedByNewWindow,
      pinned: patch.pinned ?? tab.pinned,
      muted: patch.muted ?? tab.muted,
      audible: patch.audible ?? tab.audible
    };
  }
}
