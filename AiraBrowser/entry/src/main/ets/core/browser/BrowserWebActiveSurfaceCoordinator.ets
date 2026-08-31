import {
  BrowserWebActiveSurfacePlan,
  BrowserWebCertificateRefreshAction
} from './BrowserWebEventCommitCoordinator';
import {
  BrowserShellStateCoordinator,
  BrowserShellVisualState
} from './BrowserShellStateCoordinator';
import { BrowserShellViewModel } from './BrowserShellViewModel';
import {
  BrowserTabRuntimePatch,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import {
  WEB_TRANSIENT_LOADING_TITLE,
  WebPagePresentation
} from '../web/WebRuntimeBridge';
import {
  BrowserSiteControlsActiveSurfaceAction,
  BrowserSiteControlsRuntimeCoordinator
} from './BrowserSiteControlsRuntimeCoordinator';
import {
  BrowserWebNavigationCommittedUrlRestoreState,
  BrowserWebNavigationHistoryTargetPreviewState,
  BrowserWebNavigationStateSyncCoordinator,
  BrowserWebNavigationStateSyncCoordinatorHost
} from '../../services/web/BrowserWebNavigationStateSyncCoordinator';
import {
  BrowserRuntimeLifecyclePort
} from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserAddressDisplayCoordinator } from './BrowserAddressDisplayCoordinator';
import { TelegramWebCompatibilityService } from '../../services/web/TelegramWebCompatibilityService';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserWebScrollInteractionCoordinator } from './BrowserWebScrollInteractionCoordinator';
import {
  BrowserPageChromeThemeSamplingCoordinator,
  BrowserPageChromeThemeSamplingHost,
  BrowserPageChromeThemeVisualSamplingContext
} from './BrowserPageChromeThemeSamplingCoordinator';
import {
  BrowserChromeRuntimeCoordinator,
  BrowserChromeRuntimeState
} from './BrowserChromeRuntimeCoordinator';
import {
  BrowserWebTopSafeAreaColorSampler
} from '../../services/browser/BrowserWebTopSafeAreaColorSampler';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { BrowserLoadingProgressState } from './BrowserLoadingProgressCoordinator';
import {
  BrowserWebPageLifecycleActiveDocumentState,
  BrowserWebPageLifecycleApplicationHost,
  BrowserWebPageLifecycleErrorSurfaceState,
  BrowserWebPageLifecycleRuntimeState,
  BrowserWebPageLifecycleShellFacts
} from './BrowserWebPageLifecycleModels';

export const WEB_ACTIVE_SURFACE_SCROLL_SOURCE_CONTROLLER_ATTACH = 'controller_attach';
export const WEB_ACTIVE_SURFACE_SCROLL_SOURCE_NAVIGATION_RESTORE = 'navigation_restore';

export type BrowserWebActiveSurfaceScrollSource =
  'controller_attach' |
  'navigation_restore' |
  'snapshot_restore';

export type BrowserWebActiveSurfaceActionType =
  'apply_visual_state' |
  'refresh_permissions' |
  'set_certificate_loading' |
  'refresh_certificate' |
  'refresh_tracking' |
  'sync_navigation_state' |
  'persist_active_snapshot';

export interface BrowserWebActiveSurfaceAction {
  type: BrowserWebActiveSurfaceActionType;
  snapshotReason: string;
}

export interface BrowserWebActiveSurfaceActionAdapter {
  applyVisualState: () => boolean;
  applySiteControlsAction: (action: BrowserSiteControlsActiveSurfaceAction) => void;
  syncNavigationState: () => void;
  persistActiveSnapshot: (snapshotReason: string) => void;
}

export interface BrowserWebActiveSurfaceExecutionInput {
  plan: BrowserWebActiveSurfacePlan;
}

export interface BrowserWebActiveSurfaceExecutionContext {
  visualState?: BrowserShellVisualState;
  tabId: string;
  scrollSource: BrowserWebActiveSurfaceScrollSource;
}

export interface BrowserWebActiveSurfaceHost {
  applyShellVisualState: (state: BrowserShellVisualState) => void;
  applySiteControlsAction: (action: BrowserSiteControlsActiveSurfaceAction) => void;
  syncNavigationState: () => void;
  persistActiveTabSnapshot: (snapshotReason: string) => void;
}

export interface BrowserWebActiveSurfaceVisualStateHost extends BrowserWebActiveSurfaceHost {
  buildLiveRuntimeVisualState: (
    tab: BrowserTabState,
    helperMessage: string,
    runtimeDegradedMessage: string
  ) => BrowserShellVisualState;
  buildPagePresentationVisualState: (presentation: WebPagePresentation) => BrowserShellVisualState;
  buildLoadFailureVisualState: (
    tabId: string,
    userMessage: string,
    degradedReason: string
  ) => BrowserShellVisualState | undefined;
  buildSnapshotRestoreVisualState: (tabId: string) => BrowserShellVisualState | undefined;
}

export interface BrowserWebActiveSurfaceFacts {
  tabs: BrowserTabState[];
  activeTabId: string;
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
  webPageVisible: boolean;
  showTabsSheet: boolean;
  controllerAttached: boolean;
  pageErrorSurfaceVisible: boolean;
  renderedPageErrorSurfaceVisible: boolean;
  pageErrorSurfaceReloadHold: boolean;
  activeErrorDocumentRetryTabId: string;
  chromeRuntimeState: BrowserChromeRuntimeState;
  webScrollExperimentSettings: BrowserExperimentSettings;
  currentWindowId: string;
  hostedWebSurfaceSuspended: boolean;
  visualSamplingSuppressed: boolean;
}

export interface BrowserWebActiveSurfaceNavigationState {
  canGoBack: boolean;
  canGoForward: boolean;
}

export interface BrowserWebActiveSurfaceStateApplication {
  visualState?: BrowserShellVisualState;
  navigationState?: BrowserWebActiveSurfaceNavigationState;
  committedUrlRestoreState?: BrowserWebNavigationCommittedUrlRestoreState;
  historyTargetPreviewState?: BrowserWebNavigationHistoryTargetPreviewState;
  chromeRuntimeState?: BrowserChromeRuntimeState;
  helperMessage?: string;
  loadingProgressState?: BrowserLoadingProgressState;
  incrementVideoAssistantPresentationRevision?: boolean;
  tabs?: BrowserTabState[];
  activeDocumentState?: BrowserWebPageLifecycleActiveDocumentState;
  errorMessage?: string;
  runtimeDegradedMessage?: string;
  loading?: boolean;
  controllerAttached?: boolean;
  errorSurfaceState?: BrowserWebPageLifecycleErrorSurfaceState;
}

export interface BrowserWebActiveSurfaceShell {
  readFacts: () => BrowserWebActiveSurfaceFacts;
  applyState: (application: BrowserWebActiveSurfaceStateApplication) => void;
  persistActiveTabSnapshot: (snapshotReason: string) => void;
  resolvePageChromeThemeVisualSamplingContext: () => BrowserPageChromeThemeVisualSamplingContext;
  syncBottomPanelStatusBarStyle: () => void;
  exitVideoAssistantFullscreen: () => void;
  clearRootBottomChromeScrollVisualCollapse: () => void;
  openSystemNetworkSettings: () => void;
}

export interface BrowserWebActiveSurfaceDependencies {
  tabManager: BrowserTabManagerPort;
  shellStateCoordinator: BrowserShellStateCoordinator;
  shellViewModel: BrowserShellViewModel;
  resolveTabSwitchCoordinator: () => BrowserTabSwitchCoordinator;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  addressDisplayCoordinator: BrowserAddressDisplayCoordinator;
  resolveVisibleUrlService: () => TelegramWebCompatibilityService;
  chromeRuntimeCoordinator: BrowserChromeRuntimeCoordinator;
  colorSampler: BrowserWebTopSafeAreaColorSampler;
  resolveWebTabsController: () => BrowserWebTabsController;
  resolveWebScrollInteractionCoordinator: () => BrowserWebScrollInteractionCoordinator;
  resolveSiteControlsRuntimeCoordinator: () => BrowserSiteControlsRuntimeCoordinator;
  finishActivePageLoadingProgress: () => void;
  navigationStateScrollDeferredDelayMs: number;
}

export class BrowserWebActiveSurfaceCoordinator {
  private readonly dependencies: BrowserWebActiveSurfaceDependencies;
  private readonly shell: BrowserWebActiveSurfaceShell;
  private readonly actionExecutor: BrowserWebActiveSurfaceActionExecutor;
  private readonly visualStateHost: BrowserWebActiveSurfaceVisualStateHost;
  private readonly navigationStateSyncCoordinator: BrowserWebNavigationStateSyncCoordinator;
  private readonly pageChromeThemeSamplingCoordinator: BrowserPageChromeThemeSamplingCoordinator;
  private readonly pageLifecycleHost: BrowserWebPageLifecycleApplicationHost;

  constructor(
    dependencies: BrowserWebActiveSurfaceDependencies,
    shell: BrowserWebActiveSurfaceShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    this.actionExecutor = new BrowserWebActiveSurfaceActionExecutor();
    this.navigationStateSyncCoordinator = new BrowserWebNavigationStateSyncCoordinator(
      this.buildNavigationStateSyncHost(),
      dependencies.navigationStateScrollDeferredDelayMs
    );
    this.pageChromeThemeSamplingCoordinator = new BrowserPageChromeThemeSamplingCoordinator({
      runtimeLifecyclePort: dependencies.runtimeLifecyclePort,
      tabManager: dependencies.tabManager,
      chromeRuntimeCoordinator: dependencies.chromeRuntimeCoordinator,
      resolveWebScrollInteractionCoordinator: dependencies.resolveWebScrollInteractionCoordinator,
      colorSampler: dependencies.colorSampler
    }, this.buildPageChromeThemeSamplingHost());
    this.visualStateHost = this.buildVisualStateHost();
    this.pageLifecycleHost = this.buildPageLifecycleHost();
  }

  getActionExecutor(): BrowserWebActiveSurfaceActionExecutor {
    return this.actionExecutor;
  }

  getVisualStateHost(): BrowserWebActiveSurfaceVisualStateHost {
    return this.visualStateHost;
  }

  getNavigationStateSyncCoordinator(): BrowserWebNavigationStateSyncCoordinator {
    return this.navigationStateSyncCoordinator;
  }

  getPageChromeThemeSamplingCoordinator(): BrowserPageChromeThemeSamplingCoordinator {
    return this.pageChromeThemeSamplingCoordinator;
  }

  getPageLifecycleHost(): BrowserWebPageLifecycleApplicationHost {
    return this.pageLifecycleHost;
  }

  applyVisualState(state: BrowserShellVisualState): void {
    this.visualStateHost.applyShellVisualState(state);
  }

  applyPagePresentation(
    input: BrowserWebActiveSurfaceExecutionInput,
    presentation: WebPagePresentation,
    context: BrowserWebActiveSurfaceExecutionContext
  ): void {
    this.executePlanWithHost(
      input,
      this.actionExecutor,
      this.visualStateHost,
      {
        visualState: this.visualStateHost.buildPagePresentationVisualState(presentation),
        tabId: context.tabId,
        scrollSource: context.scrollSource
      }
    );
  }

  applyLiveRuntimePresentation(
    tab: BrowserTabState,
    helperMessage: string,
    runtimeDegradedMessage: string,
    context: BrowserWebActiveSurfaceExecutionContext
  ): void {
    const plan: BrowserWebActiveSurfacePlan = {
      shouldApplyVisualState: true,
      shouldRefreshPermissions: true,
      certificateAction: 'refresh',
      shouldRefreshTracking: true,
      shouldSyncNavigationState: true,
      shouldPersistActiveSnapshot: false,
      snapshotReason: ''
    };
    this.executePlanWithHost({ plan: plan }, this.actionExecutor, this.visualStateHost, {
      visualState: this.visualStateHost.buildLiveRuntimeVisualState(
        tab,
        helperMessage,
        runtimeDegradedMessage
      ),
      tabId: context.tabId,
      scrollSource: context.scrollSource
    });
  }

  applyLoadFailurePresentation(
    input: BrowserWebActiveSurfaceExecutionInput,
    userMessage: string,
    degradedReason: string,
    context: BrowserWebActiveSurfaceExecutionContext
  ): void {
    this.applyLoadFailurePresentationWithHost(
      input,
      userMessage,
      degradedReason,
      this.actionExecutor,
      this.visualStateHost,
      context
    );
  }

  applySnapshotRestorePresentation(
    input: BrowserWebActiveSurfaceExecutionInput,
    context: BrowserWebActiveSurfaceExecutionContext
  ): void {
    this.executePlanWithHost(input, this.actionExecutor, this.visualStateHost, {
      visualState: this.visualStateHost.buildSnapshotRestoreVisualState(context.tabId),
      tabId: context.tabId,
      scrollSource: context.scrollSource
    });
  }

  private buildActions(input: BrowserWebActiveSurfaceExecutionInput): BrowserWebActiveSurfaceAction[] {
    const actions: BrowserWebActiveSurfaceAction[] = [];
    this.pushAction(actions, input.plan.shouldApplyVisualState, 'apply_visual_state', input.plan);
    this.pushAction(actions, input.plan.shouldRefreshPermissions, 'refresh_permissions', input.plan);
    this.pushCertificateAction(actions, input.plan.certificateAction, input.plan);
    this.pushAction(actions, input.plan.shouldRefreshTracking, 'refresh_tracking', input.plan);
    this.pushAction(actions, input.plan.shouldSyncNavigationState, 'sync_navigation_state', input.plan);
    this.pushAction(
      actions,
      input.plan.shouldPersistActiveSnapshot && input.plan.snapshotReason.length > 0,
      'persist_active_snapshot',
      input.plan
    );
    return actions;
  }

  executePlan(
    input: BrowserWebActiveSurfaceExecutionInput,
    executor: BrowserWebActiveSurfaceActionExecutor,
    adapter: BrowserWebActiveSurfaceActionAdapter
  ): void {
    this.buildActions(input).forEach((action: BrowserWebActiveSurfaceAction) => {
      executor.executeAction(action, adapter);
    });
  }

  executePlanWithHost(
    input: BrowserWebActiveSurfaceExecutionInput,
    executor: BrowserWebActiveSurfaceActionExecutor,
    host: BrowserWebActiveSurfaceHost,
    context: BrowserWebActiveSurfaceExecutionContext
  ): void {
    this.executePlan(input, executor, this.buildHostAdapter(host, context));
  }

  applyLoadFailurePresentationWithHost(
    input: BrowserWebActiveSurfaceExecutionInput,
    userMessage: string,
    degradedReason: string,
    executor: BrowserWebActiveSurfaceActionExecutor,
    host: BrowserWebActiveSurfaceVisualStateHost,
    context: BrowserWebActiveSurfaceExecutionContext
  ): void {
    this.executePlanWithHost(input, executor, host, {
      visualState: host.buildLoadFailureVisualState(context.tabId, userMessage, degradedReason),
      tabId: context.tabId,
      scrollSource: context.scrollSource
    });
  }

  private pushCertificateAction(
    actions: BrowserWebActiveSurfaceAction[],
    certificateAction: BrowserWebCertificateRefreshAction,
    plan: BrowserWebActiveSurfacePlan
  ): void {
    switch (certificateAction) {
      case 'set_loading':
        this.pushAction(actions, true, 'set_certificate_loading', plan);
        break;
      case 'refresh':
        this.pushAction(actions, true, 'refresh_certificate', plan);
        break;
      case 'none':
      default:
        break;
    }
  }

  private pushAction(
    actions: BrowserWebActiveSurfaceAction[],
    shouldPush: boolean,
    type: BrowserWebActiveSurfaceActionType,
    plan: BrowserWebActiveSurfacePlan
  ): void {
    if (!shouldPush) {
      return;
    }
    actions.push({
      type: type,
      snapshotReason: plan.snapshotReason
    });
  }

  private buildHostAdapter(
    host: BrowserWebActiveSurfaceHost,
    context: BrowserWebActiveSurfaceExecutionContext
  ): BrowserWebActiveSurfaceActionAdapter {
    return {
      applyVisualState: (): boolean => {
        if (context.visualState === undefined) {
          return false;
        }
        host.applyShellVisualState(context.visualState);
        return true;
      },
      applySiteControlsAction: (action: BrowserSiteControlsActiveSurfaceAction): void => {
        host.applySiteControlsAction(action);
      },
      syncNavigationState: (): void => {
        host.syncNavigationState();
      },
      persistActiveSnapshot: (snapshotReason: string): void => {
        host.persistActiveTabSnapshot(snapshotReason);
      }
    };
  }

  private buildNavigationStateSyncHost(): BrowserWebNavigationStateSyncCoordinatorHost {
    return {
      resolveWebTabsController: (): BrowserWebTabsController => this.dependencies.resolveWebTabsController(),
      resolveActiveTabId: (): string => this.shell.readFacts().activeTabId,
      resolveCurrentUrl: (): string => this.shell.readFacts().currentUrl,
      resolveHistoryTargetIntentUrl: (tabId: string): string =>
        this.dependencies.resolveWebTabsController().resolveHistoryTargetIntentUrl(tabId),
      findTabById: (tabId: string): BrowserTabState | undefined =>
        this.dependencies.tabManager.getTab(this.shell.readFacts().tabs, tabId),
      shouldDeferNavigationStateForWebScroll: (): boolean =>
        this.dependencies.resolveWebScrollInteractionCoordinator()
          .shouldDeferTask('page_navigation_state_update'),
      resolveWebScrollQuietDelayMs: (baseDelayMs: number): number =>
        this.dependencies.resolveWebScrollInteractionCoordinator().getQuietDelayMs(baseDelayMs),
      applyNavigationState: (canGoBack: boolean, canGoForward: boolean): void => {
        this.shell.applyState({
          navigationState: {
            canGoBack: canGoBack,
            canGoForward: canGoForward
          }
        });
      },
      isActiveWebTabVisible: (tabId: string): boolean => {
        const facts = this.shell.readFacts();
        return tabId === facts.activeTabId && facts.webPageVisible;
      },
      resolveCommittedAddressDisplayText: (url: string): string => {
        return this.dependencies.addressDisplayCoordinator.resolveCommittedDisplay(
          this.shell.readFacts().activeTabId,
          this.dependencies.resolveVisibleUrlService().resolveVisibleUrl(url)
        );
      },
      applyTabPatch: (tabId: string, patch: BrowserTabRuntimePatch, persistTabs: boolean): void => {
        this.dependencies.resolveTabSwitchCoordinator().applyTabPatch(tabId, patch, {
          persistTabs: persistTabs
        });
      },
      rememberProvisionalNavigation: (tabId: string, url: string): void => {
        this.dependencies.runtimeLifecyclePort.rememberProvisionalNavigation(tabId, url);
      },
      applyCommittedUrlRestoreState: (state: BrowserWebNavigationCommittedUrlRestoreState): void => {
        this.shell.applyState({ committedUrlRestoreState: state });
      },
      applyHistoryTargetPreviewState: (state: BrowserWebNavigationHistoryTargetPreviewState): void => {
        this.shell.applyState({ historyTargetPreviewState: state });
      },
      finishActivePageLoadingProgress: (): void => {
        this.dependencies.finishActivePageLoadingProgress();
      }
    };
  }

  private buildPageChromeThemeSamplingHost(): BrowserPageChromeThemeSamplingHost {
    return {
      readFacts: () => {
        const facts = this.shell.readFacts();
        return {
          tabs: facts.tabs,
          activeTabId: facts.activeTabId,
          webPageVisible: facts.webPageVisible,
          showTabsSheet: facts.showTabsSheet,
          chromeRuntimeState: facts.chromeRuntimeState,
          visualSamplingSuppressed: facts.visualSamplingSuppressed
        };
      },
      resolveVisualSamplingContext: (): BrowserPageChromeThemeVisualSamplingContext =>
        this.shell.resolvePageChromeThemeVisualSamplingContext(),
      publishChromeRuntimeState: (state: BrowserChromeRuntimeState): void => {
        this.shell.applyState({ chromeRuntimeState: state });
      },
      syncBottomPanelStatusBarStyle: (): void => {
        this.shell.syncBottomPanelStatusBarStyle();
      }
    };
  }

  private buildVisualStateHost(): BrowserWebActiveSurfaceVisualStateHost {
    return {
      applyShellVisualState: (state: BrowserShellVisualState): void => {
        this.shell.applyState({ visualState: state });
      },
      applySiteControlsAction: (action: BrowserSiteControlsActiveSurfaceAction): void => {
        this.dependencies.resolveSiteControlsRuntimeCoordinator().handleActiveSurfaceAction(action);
      },
      syncNavigationState: (): void => {
        this.navigationStateSyncCoordinator.sync();
      },
      persistActiveTabSnapshot: (snapshotReason: string): void => {
        this.shell.persistActiveTabSnapshot(snapshotReason);
      },
      buildLiveRuntimeVisualState: (
        tab: BrowserTabState,
        helperMessage: string,
        runtimeDegradedMessage: string
      ): BrowserShellVisualState => {
        const activeTabId = this.shell.readFacts().activeTabId;
        return this.dependencies.shellStateCoordinator.buildLiveRuntimeState(
          tab,
          activeTabId,
          this.dependencies.shellViewModel.resolveLiveRuntimeHelperMessage(
            tab,
            activeTabId,
            helperMessage
          ),
          runtimeDegradedMessage
        );
      },
      buildPagePresentationVisualState: (presentation: WebPagePresentation): BrowserShellVisualState => {
        const state = this.dependencies.shellStateCoordinator.buildPagePresentationState(presentation);
        const currentTitle = this.shell.readFacts().currentTitle;
        if (presentation.currentTitle === WEB_TRANSIENT_LOADING_TITLE &&
          currentTitle.trim().length > 0) {
          state.currentTitle = currentTitle;
        }
        return state;
      },
      buildLoadFailureVisualState: (
        tabId: string,
        userMessage: string,
        degradedReason: string
      ): BrowserShellVisualState | undefined => {
        const tab = this.dependencies.tabManager.getTab(this.shell.readFacts().tabs, tabId);
        return tab === undefined ? undefined :
          this.dependencies.shellStateCoordinator.buildPageErrorState(tab, userMessage, degradedReason);
      },
      buildSnapshotRestoreVisualState: (tabId: string): BrowserShellVisualState | undefined => {
        const tab = this.dependencies.tabManager.getTab(this.shell.readFacts().tabs, tabId);
        return tab === undefined ? undefined :
          this.dependencies.shellStateCoordinator.buildSnapshotRestoreSuccessState(tab);
      }
    };
  }

  private buildPageLifecycleHost(): BrowserWebPageLifecycleApplicationHost {
    return {
      resolveShellFacts: (): BrowserWebPageLifecycleShellFacts => {
        const facts = this.shell.readFacts();
        return {
          activeTabId: facts.activeTabId,
          webPageVisible: facts.webPageVisible,
          tabsSheetVisible: facts.showTabsSheet,
          currentUrl: facts.currentUrl,
          pendingWebUrl: facts.pendingWebUrl,
          addressInput: facts.addressInput,
          currentTitle: facts.currentTitle,
          controllerAttached: facts.controllerAttached,
          pageErrorSurfaceVisible: facts.pageErrorSurfaceVisible,
          renderedPageErrorSurfaceVisible: facts.renderedPageErrorSurfaceVisible,
          pageErrorSurfaceReloadHold: facts.pageErrorSurfaceReloadHold,
          activeErrorDocumentRetryTabId: facts.activeErrorDocumentRetryTabId,
          browserChromeRuntimeState: facts.chromeRuntimeState,
          webScrollExperimentSettings: facts.webScrollExperimentSettings,
          currentWindowId: facts.currentWindowId,
          tabs: facts.tabs,
          hostedWebSurfaceSuspended: facts.hostedWebSurfaceSuspended
        };
      },
      applyRuntimeState: (state: BrowserWebPageLifecycleRuntimeState): void => {
        this.shell.applyState({
          helperMessage: state.helperMessage,
          errorMessage: state.errorMessage,
          runtimeDegradedMessage: state.runtimeDegradedMessage,
          loading: state.loading
        });
      },
      applyLoadingProgressState: (state: BrowserLoadingProgressState): void => {
        this.shell.applyState({ loadingProgressState: state });
      },
      exitVideoAssistantFullscreen: (): void => {
        this.shell.exitVideoAssistantFullscreen();
      },
      invalidateVideoAssistantPresentation: (): void => {
        this.shell.applyState({ incrementVideoAssistantPresentationRevision: true });
      },
      resolveDeferredPresentationDelayMs: (baseDelayMs: number): number =>
        this.dependencies.resolveWebScrollInteractionCoordinator().getQuietDelayMs(baseDelayMs),
      shouldDeferTitleVisualUpdate: (tabId: string): boolean => {
        const facts = this.shell.readFacts();
        return tabId === facts.activeTabId &&
          this.dependencies.resolveWebScrollInteractionCoordinator()
            .shouldDeferTask('page_title_visual_update');
      },
      shouldDeferFaviconVisualUpdate: (tabId: string): boolean => {
        const facts = this.shell.readFacts();
        return tabId === facts.activeTabId &&
          this.dependencies.resolveWebScrollInteractionCoordinator()
            .shouldDeferTask('page_favicon_visual_update');
      },
      clearRootBottomChromeScrollVisualCollapse: (): void => {
        this.shell.clearRootBottomChromeScrollVisualCollapse();
      },
      applyBrowserChromeRuntimeState: (state: BrowserChromeRuntimeState): void => {
        this.shell.applyState({ chromeRuntimeState: state });
      },
      syncBottomPanelStatusBarStyle: (): void => {
        this.shell.syncBottomPanelStatusBarStyle();
      },
      applyTabs: (tabs: BrowserTabState[]): void => {
        this.shell.applyState({ tabs: tabs });
      },
      applyActiveDocumentState: (state: BrowserWebPageLifecycleActiveDocumentState): void => {
        this.shell.applyState({ activeDocumentState: state });
      },
      applyControllerAttachedState: (attached: boolean): void => {
        this.shell.applyState({ controllerAttached: attached });
      },
      applyErrorSurfaceState: (state: BrowserWebPageLifecycleErrorSurfaceState): void => {
        this.shell.applyState({ errorSurfaceState: state });
      },
      openSystemNetworkSettings: (): void => {
        this.shell.openSystemNetworkSettings();
      }
    };
  }

}

export class BrowserWebActiveSurfaceActionExecutor {
  executeAction(
    action: BrowserWebActiveSurfaceAction,
    adapter: BrowserWebActiveSurfaceActionAdapter
  ): void {
    try {
      switch (action.type) {
        case 'apply_visual_state':
          if (!adapter.applyVisualState()) {
            return;
          }
          return;
        case 'refresh_permissions':
          adapter.applySiteControlsAction('refresh_permissions');
          return;
        case 'set_certificate_loading':
          adapter.applySiteControlsAction('set_certificate_loading');
          return;
        case 'refresh_certificate':
          adapter.applySiteControlsAction('refresh_certificate');
          return;
        case 'refresh_tracking':
          adapter.applySiteControlsAction('refresh_tracking');
          return;
        case 'sync_navigation_state':
          adapter.syncNavigationState();
          return;
        case 'persist_active_snapshot':
          adapter.persistActiveSnapshot(action.snapshotReason);
          return;
        default:
          return;
      }
    } catch (_error) {
      return;
    }
  }
}
