import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserChromeRuntimeState } from './BrowserChromeRuntimeCoordinator';
import { BrowserLoadingProgressState } from './BrowserLoadingProgressCoordinator';

export interface BrowserWebPageLifecycleShellFacts {
  activeTabId: string;
  webPageVisible: boolean;
  tabsSheetVisible: boolean;
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
  controllerAttached: boolean;
  pageErrorSurfaceVisible: boolean;
  renderedPageErrorSurfaceVisible: boolean;
  pageErrorSurfaceReloadHold: boolean;
  activeErrorDocumentRetryTabId: string;
  browserChromeRuntimeState: BrowserChromeRuntimeState;
  webScrollExperimentSettings: BrowserExperimentSettings;
  currentWindowId: string;
  tabs: BrowserTabState[];
  hostedWebSurfaceSuspended: boolean;
}

export interface BrowserWebPageLifecycleActiveDocumentState {
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
}

export interface BrowserWebPageLifecycleErrorSurfaceState {
  visible: boolean;
  reloadHold: boolean;
  retryTabId: string;
}

export interface BrowserWebPageLifecycleRuntimeState {
  helperMessage?: string;
  errorMessage?: string;
  runtimeDegradedMessage?: string;
  loading?: boolean;
}

export interface BrowserWebPageLifecycleApplicationHost {
  resolveShellFacts: () => BrowserWebPageLifecycleShellFacts;
  applyRuntimeState: (state: BrowserWebPageLifecycleRuntimeState) => void;
  applyLoadingProgressState: (state: BrowserLoadingProgressState) => void;
  exitVideoAssistantFullscreen: () => void;
  invalidateVideoAssistantPresentation: () => void;
  resolveDeferredPresentationDelayMs: (baseDelayMs: number) => number;
  shouldDeferTitleVisualUpdate: (tabId: string) => boolean;
  shouldDeferFaviconVisualUpdate: (tabId: string) => boolean;
  clearRootBottomChromeScrollVisualCollapse: () => void;
  applyBrowserChromeRuntimeState: (state: BrowserChromeRuntimeState) => void;
  syncBottomPanelStatusBarStyle: () => void;
  applyTabs: (tabs: BrowserTabState[]) => void;
  applyActiveDocumentState: (state: BrowserWebPageLifecycleActiveDocumentState) => void;
  applyControllerAttachedState: (attached: boolean) => void;
  applyErrorSurfaceState: (state: BrowserWebPageLifecycleErrorSurfaceState) => void;
  openSystemNetworkSettings: () => void;
}
