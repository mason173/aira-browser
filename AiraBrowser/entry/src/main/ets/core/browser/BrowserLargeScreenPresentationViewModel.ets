import {
  BrowserLargeScreenInputProfile,
  BrowserLargeScreenTabProjectionInput,
  BrowserLargeScreenTabStripPolicy,
  BrowserLargeScreenTabStripPresentation,
  BrowserLargeScreenTabStripViewModel,
  BrowserLargeScreenWindowProfile
} from './BrowserLargeScreenTabStripViewModel';
import { BrowserTabState, isBrowserTabTerminalBackAvailable } from '../tabs/TabManager';
import {
  BrowserLargeScreenTabCapabilityFacts,
  BrowserLargeScreenTabSnapshotAdapter
} from './BrowserLargeScreenTabSnapshotAdapter';
import {
  BrowserLargeScreenWindowFactsInput,
  BrowserLargeScreenWindowFactsPolicy,
  BrowserLargeScreenWindowFactsSnapshot,
  BrowserLargeScreenWindowFactsViewModel
} from './BrowserLargeScreenWindowFactsViewModel';
import {
  BrowserLargeScreenSidePanelFacts,
  BrowserLargeScreenSidePanelPresentation,
  BrowserLargeScreenSidePanelViewModel
} from './BrowserLargeScreenSidePanelViewModel';
import {
  BrowserLargeScreenTopChromeActionFacts,
  BrowserLargeScreenTopChromeActionPresentation,
  BrowserLargeScreenTopChromeActionViewModel
} from './BrowserLargeScreenTopChromeActionViewModel';
import { browserNativeTabSceneService } from './BrowserNativeTabSceneService';
import {
  BROWSER_LARGE_SCREEN_TITLE_BAR_FIXED_CHROME_WIDTH_VP
} from './BrowserLargeScreenTitleBarTokens';

export {
  BrowserLargeScreenSidePanelFacts,
  BrowserLargeScreenSidePanelPresentation,
  BrowserLargeScreenSidePanelState,
  BrowserLargeScreenSidePanelPosition
} from './BrowserLargeScreenSidePanelViewModel';

export type BrowserLargeScreenTopChromeDensity = 'full' | 'compact';
export type BrowserLargeScreenActiveTabScene =
  'home' | 'web' | 'bookmarks' | 'history' | 'settings' | 'downloads' | 'user_scripts' |
  'app_proxy' | 'saved_pages';

export interface BrowserLargeScreenActiveTabChromePresentation {
  scene: BrowserLargeScreenActiveTabScene;
  tabId: string;
  title: string;
  displayUrl: string;
  nativeRouteUrl: string;
  canGoBack: boolean;
  canGoForward: boolean;
  loading: boolean;
  privateMode: boolean;
}

export interface BrowserLargeScreenPresentationLayoutFacts {
  availableWidthVp: number;
  titleButtonWidthVp: number;
  titleButtonHeightVp: number;
  windowTitleBarIntegrated: boolean;
  safeTopInsetVp: number;
  windowProfile: BrowserLargeScreenWindowProfile;
  inputProfile: BrowserLargeScreenInputProfile;
  activeTabId: string;
  dragSupported: boolean;
  keyboardHintsAvailable: boolean;
  bottomStatusAvailable: boolean;
  tabStripPolicy: BrowserLargeScreenTabStripPolicy;
  sidePanel: BrowserLargeScreenSidePanelFacts;
  topChromeActionFacts: BrowserLargeScreenTopChromeActionFacts;
}

export interface BrowserLargeScreenPresentationFacts extends BrowserLargeScreenPresentationLayoutFacts {
  tabs: BrowserLargeScreenTabProjectionInput[];
  activeTabChrome?: BrowserLargeScreenActiveTabChromePresentation;
}

export interface BrowserLargeScreenPresentationSourceFacts {
  window: BrowserLargeScreenWindowFactsInput;
  windowPolicy: BrowserLargeScreenWindowFactsPolicy;
  activeTabId: string;
  bottomStatusAvailable: boolean;
  tabStripPolicy: BrowserLargeScreenTabStripPolicy;
  sidePanel: BrowserLargeScreenSidePanelFacts;
  topChromeActionFacts: BrowserLargeScreenTopChromeActionFacts;
  tabs: BrowserTabState[];
  tabCapabilities: BrowserLargeScreenTabCapabilityFacts;
}

export interface BrowserLargeScreenTopChromePresentation {
  density: BrowserLargeScreenTopChromeDensity;
  hoverActionsVisible: boolean;
  keyboardHintsVisible: boolean;
  actions: BrowserLargeScreenTopChromeActionPresentation[];
}

export interface BrowserLargeScreenPresentationSnapshot {
  windowProfile: BrowserLargeScreenWindowProfile;
  inputProfile: BrowserLargeScreenInputProfile;
  topChrome: BrowserLargeScreenTopChromePresentation;
  activeTabChrome: BrowserLargeScreenActiveTabChromePresentation;
  tabStrip: BrowserLargeScreenTabStripPresentation;
  sidePanel: BrowserLargeScreenSidePanelPresentation;
  mainStageWidthVp: number;
  // System status-bar top inset (vp). On a tablet this is the status-bar
  // height that the top chrome must reserve; on a 2-in-1/PC window (system
  // caption present, no phone-style status bar) it collapses to ~0. Mirrors
  // Huawei's PcMainPage holding statusBarHeight for the same purpose.
  safeTopInsetVp: number;
  bottomStatusVisible: boolean;
}

const STRUCTURAL_TAB_STRIP_POLICY: BrowserLargeScreenTabStripPolicy = {
  minimumTabWidthVp: 64,
  maximumTabWidthVp: 240,
  compactTabWidthVp: 64,
  selectedTabExtraWidthVp: 24,
  fixedChromeWidthVp: BROWSER_LARGE_SCREEN_TITLE_BAR_FIXED_CHROME_WIDTH_VP
};

function createEmptyActiveTabChrome(): BrowserLargeScreenActiveTabChromePresentation {
  return {
    scene: 'home',
    tabId: '',
    title: '新标签页',
    displayUrl: '',
    nativeRouteUrl: '',
    canGoBack: false,
    canGoForward: false,
    loading: false,
    privateMode: false
  };
}

/**
 * Owns the non-visual composition of the Large-Screen shell.
 *
 * The module accepts already-shaped WindowStage, input, side-panel, and tab
 * facts. It combines those facts into one renderable snapshot while keeping
 * policy out of the page. It never creates surfaces, Web controllers, tabs,
 * or side-panel content; those remain owned by the existing browser owners.
 */
export class BrowserLargeScreenPresentationViewModel {
  private readonly tabStripViewModel: BrowserLargeScreenTabStripViewModel =
    new BrowserLargeScreenTabStripViewModel();
  private readonly tabSnapshotAdapter: BrowserLargeScreenTabSnapshotAdapter =
    new BrowserLargeScreenTabSnapshotAdapter();
  private readonly windowFactsViewModel: BrowserLargeScreenWindowFactsViewModel =
    new BrowserLargeScreenWindowFactsViewModel();
  private readonly sidePanelViewModel: BrowserLargeScreenSidePanelViewModel =
    new BrowserLargeScreenSidePanelViewModel();
  private readonly topChromeActionViewModel: BrowserLargeScreenTopChromeActionViewModel =
    new BrowserLargeScreenTopChromeActionViewModel();

  /**
   * Produces the stable Large-Screen shell skeleton from Session-owned Window
   * facts before tab/address projections are connected. This keeps the stable
   * Host renderable without asking BrowserShellPage to invent fallback policy.
   */
  resolveStructuralPresentation(
    windowFacts: BrowserLargeScreenWindowFactsSnapshot
  ): BrowserLargeScreenPresentationSnapshot {
    return this.resolvePresentationForTabs(windowFacts, [], '');
  }

  resolvePresentationForTabs(
    windowFacts: BrowserLargeScreenWindowFactsSnapshot,
    tabs: BrowserTabState[],
    activeTabId: string
  ): BrowserLargeScreenPresentationSnapshot {
    const activeTab = tabs.find((tab: BrowserTabState): boolean => tab.id === activeTabId);
    const hasActiveTab = activeTab !== undefined;
    const navigationIndex = activeTab?.navigationIndex ?? -1;
    const navigationCount = activeTab?.navigationHistory.length ?? 0;
    const terminalBackAvailable = isBrowserTabTerminalBackAvailable(activeTab);
    const presentation = this.resolvePresentationFromTabStates({
      availableWidthVp: windowFacts.availableWidthVp,
      titleButtonWidthVp: windowFacts.titleButtonWidthVp,
      titleButtonHeightVp: windowFacts.titleButtonHeightVp,
      windowTitleBarIntegrated: windowFacts.windowTitleBarIntegrated,
      safeTopInsetVp: windowFacts.safeTopInsetVp,
      windowProfile: windowFacts.windowProfile,
      inputProfile: windowFacts.inputProfile,
      activeTabId: activeTabId,
      dragSupported: windowFacts.dragSupported,
      keyboardHintsAvailable: windowFacts.keyboardHintsAvailable,
      bottomStatusAvailable: false,
      tabStripPolicy: STRUCTURAL_TAB_STRIP_POLICY,
      sidePanel: {
        requestedState: 'closed',
        position: 'right',
        contentAvailable: false,
        widthVp: 0,
        minimumMainStageWidthVp: 0
      },
      topChromeActionFacts: {
        windowProfile: windowFacts.windowProfile,
        inputProfile: windowFacts.inputProfile,
        keyboardHintsAvailable: windowFacts.keyboardHintsAvailable,
        hasActiveTab: hasActiveTab,
        canGoBack: navigationIndex > 0 || terminalBackAvailable,
        canGoForward: navigationIndex >= 0 && navigationIndex < navigationCount - 1,
        isLoading: activeTab?.runtimeState === 'loading' || activeTab?.runtimeState === 'restoring',
        hostCapabilities: {
          tabMenuAvailable: true,
          newWindowAvailable: false
        }
      }
    }, tabs, {
      defaultClosable: true
    });
    const nativeScene = activeTab === undefined
      ? undefined
      : browserNativeTabSceneService.resolveSceneForTab(activeTab.url, activeTab.pendingUrl);
    presentation.activeTabChrome = activeTab === undefined
      ? createEmptyActiveTabChrome()
      : {
        scene: nativeScene ?? (activeTab.isHome ? 'home' : 'web'),
        tabId: activeTab.id,
        title: activeTab.title.trim().length > 0 ? activeTab.title : '新标签页',
        displayUrl: nativeScene === undefined && !activeTab.isHome ? this.resolveActiveTabUrl(activeTab) : '',
        nativeRouteUrl: nativeScene !== undefined ? this.resolveActiveTabUrl(activeTab) : '',
        canGoBack: nativeScene !== undefined
          ? navigationIndex > 0
          : (!activeTab.isHome && (navigationIndex > 0 || terminalBackAvailable)),
        canGoForward: nativeScene !== undefined
          ? navigationIndex >= 0 && navigationIndex < navigationCount - 1
          : (!activeTab.isHome && navigationIndex >= 0 && navigationIndex < navigationCount - 1),
        loading: nativeScene === undefined && !activeTab.isHome &&
          (activeTab.runtimeState === 'loading' || activeTab.runtimeState === 'restoring'),
        privateMode: activeTab.privacyMode === 'private'
      };
    return presentation;
  }

  resolvePresentation(facts: BrowserLargeScreenPresentationFacts): BrowserLargeScreenPresentationSnapshot {
    const availableWidthVp = this.normalizeNonNegativeDimension(facts.availableWidthVp);
    const sidePanel = this.sidePanelViewModel.resolve(facts.sidePanel, availableWidthVp);
    const tabStrip = this.tabStripViewModel.resolvePresentation({
      availableWidthVp: availableWidthVp,
      titleButtonWidthVp: facts.titleButtonWidthVp,
      titleButtonHeightVp: facts.titleButtonHeightVp,
      windowTitleBarIntegrated: facts.windowTitleBarIntegrated,
      windowProfile: facts.windowProfile,
      inputProfile: facts.inputProfile,
      activeTabId: facts.activeTabId,
      dragSupported: facts.dragSupported,
      tabs: facts.tabs,
      policy: facts.tabStripPolicy
    });
    return {
      windowProfile: facts.windowProfile,
      inputProfile: facts.inputProfile,
      topChrome: this.resolveTopChrome(facts),
      activeTabChrome: facts.activeTabChrome ?? createEmptyActiveTabChrome(),
      tabStrip: tabStrip,
      sidePanel: sidePanel.presentation,
      mainStageWidthVp: sidePanel.mainStageWidthVp,
      safeTopInsetVp: this.normalizeNonNegativeDimension(facts.safeTopInsetVp),
      bottomStatusVisible: facts.bottomStatusAvailable && sidePanel.mainStageWidthVp > 0
    };
  }

  resolvePresentationFromTabStates(
    facts: BrowserLargeScreenPresentationLayoutFacts,
    tabs: BrowserTabState[],
    capabilities: BrowserLargeScreenTabCapabilityFacts
  ): BrowserLargeScreenPresentationSnapshot {
    return this.resolvePresentation({
      availableWidthVp: facts.availableWidthVp,
      titleButtonWidthVp: facts.titleButtonWidthVp,
      titleButtonHeightVp: facts.titleButtonHeightVp,
      windowTitleBarIntegrated: facts.windowTitleBarIntegrated,
      safeTopInsetVp: facts.safeTopInsetVp,
      windowProfile: facts.windowProfile,
      inputProfile: facts.inputProfile,
      activeTabId: facts.activeTabId,
      dragSupported: facts.dragSupported,
      keyboardHintsAvailable: facts.keyboardHintsAvailable,
      bottomStatusAvailable: facts.bottomStatusAvailable,
      tabStripPolicy: facts.tabStripPolicy,
      sidePanel: facts.sidePanel,
      topChromeActionFacts: facts.topChromeActionFacts,
      tabs: this.tabSnapshotAdapter.project(tabs, facts.activeTabId, capabilities)
    });
  }

  resolvePresentationFromSourceFacts(
    facts: BrowserLargeScreenPresentationSourceFacts
  ): BrowserLargeScreenPresentationSnapshot {
    const windowFacts = this.windowFactsViewModel.resolve(facts.window, facts.windowPolicy);
    return this.resolvePresentationFromTabStates({
      availableWidthVp: windowFacts.availableWidthVp,
      titleButtonWidthVp: windowFacts.titleButtonWidthVp,
      titleButtonHeightVp: windowFacts.titleButtonHeightVp,
      windowTitleBarIntegrated: windowFacts.windowTitleBarIntegrated,
      safeTopInsetVp: windowFacts.safeTopInsetVp,
      windowProfile: windowFacts.windowProfile,
      inputProfile: windowFacts.inputProfile,
      activeTabId: facts.activeTabId,
      dragSupported: windowFacts.dragSupported,
      keyboardHintsAvailable: windowFacts.keyboardHintsAvailable,
      bottomStatusAvailable: facts.bottomStatusAvailable,
      tabStripPolicy: facts.tabStripPolicy,
      sidePanel: facts.sidePanel,
      topChromeActionFacts: facts.topChromeActionFacts
    }, facts.tabs, facts.tabCapabilities);
  }

  private resolveTopChrome(
    facts: BrowserLargeScreenPresentationLayoutFacts
  ): BrowserLargeScreenTopChromePresentation {
    const compactWindow = facts.windowProfile === 'compact' || facts.windowProfile === 'subwindow';
    const actionSnapshot = this.topChromeActionViewModel.resolve({
      windowProfile: facts.windowProfile,
      inputProfile: facts.inputProfile,
      keyboardHintsAvailable: facts.keyboardHintsAvailable,
      hasActiveTab: facts.topChromeActionFacts.hasActiveTab,
      canGoBack: facts.topChromeActionFacts.canGoBack,
      canGoForward: facts.topChromeActionFacts.canGoForward,
      isLoading: facts.topChromeActionFacts.isLoading,
      hostCapabilities: facts.topChromeActionFacts.hostCapabilities
    });
    return {
      density: compactWindow ? 'compact' : 'full',
      hoverActionsVisible: actionSnapshot.hoverActionsVisible,
      keyboardHintsVisible: actionSnapshot.keyboardHintsVisible,
      actions: actionSnapshot.actions
    };
  }

  private normalizeNonNegativeDimension(value: number): number {
    if (!Number.isFinite(value) || value <= 0) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }

  private resolveActiveTabUrl(tab: BrowserTabState): string {
    const committedUrl = tab.url.trim();
    if (committedUrl.length > 0) {
      return committedUrl;
    }
    return tab.pendingUrl.trim();
  }
}
