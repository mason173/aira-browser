import {
  BrowserShellStateCoordinator,
  BrowserShellVisualState
} from '../../core/browser/BrowserShellStateCoordinator';
import { BrowserTabState } from '../../core/tabs/TabManager';
import {
  BrowserNativeTabSceneService,
  browserNativeTabSceneService
} from '../../core/browser/BrowserNativeTabSceneService';

export interface BrowserActiveTabShellStateInput {
  activeTab?: BrowserTabState;
  activeTabId: string;
  showHomePage: boolean;
  tabCount: number;
  runtimeDegradedMessage: string;
  runtimeDegradedReason: string;
}

export interface BrowserActiveTabShellStateApplication {
  activeTab?: BrowserTabState;
  resetHomeTransientUiState: boolean;
  invalidateWebSessionTransition: boolean;
  visualState: BrowserShellVisualState;
  resetHomeNavigationState: boolean;
  tabCount: number;
}

export class BrowserActiveTabShellStateCoordinator {
  private readonly shellStateCoordinator: BrowserShellStateCoordinator;
  private readonly nativeTabSceneService: BrowserNativeTabSceneService;

  constructor(
    shellStateCoordinator: BrowserShellStateCoordinator,
    nativeTabSceneService: BrowserNativeTabSceneService = browserNativeTabSceneService
  ) {
    this.shellStateCoordinator = shellStateCoordinator;
    this.nativeTabSceneService = nativeTabSceneService;
  }

  buildForegroundHomeApplication(
    input: BrowserActiveTabShellStateInput
  ): BrowserActiveTabShellStateApplication {
    return {
      activeTab: input.activeTab,
      resetHomeTransientUiState: false,
      invalidateWebSessionTransition: true,
      visualState: this.shellStateCoordinator.buildHomeState(input.runtimeDegradedMessage),
      resetHomeNavigationState: true,
      tabCount: input.tabCount
    };
  }

  buildActiveTabApplication(input: BrowserActiveTabShellStateInput): BrowserActiveTabShellStateApplication {
    const tab = input.activeTab;
    if (tab !== undefined &&
      this.nativeTabSceneService.resolveSceneForTab(tab.url, tab.pendingUrl) !== undefined) {
      return {
        activeTab: tab,
        resetHomeTransientUiState: true,
        invalidateWebSessionTransition: true,
        visualState: this.shellStateCoordinator.buildNativeTabState(tab),
        resetHomeNavigationState: true,
        tabCount: input.tabCount
      };
    }
    if (tab === undefined || tab.isHome) {
      return {
        activeTab: tab,
        resetHomeTransientUiState: true,
        invalidateWebSessionTransition: true,
        visualState: this.shellStateCoordinator.buildHomeState(
          tab === undefined ? '' : input.runtimeDegradedReason
        ),
        resetHomeNavigationState: true,
        tabCount: input.tabCount
      };
    }
    return {
      activeTab: tab,
      resetHomeTransientUiState: false,
      invalidateWebSessionTransition: false,
      visualState: this.shellStateCoordinator.buildActiveTabState(
        tab,
        input.activeTabId,
        input.runtimeDegradedReason
      ),
      resetHomeNavigationState: false,
      tabCount: input.tabCount
    };
  }
}
