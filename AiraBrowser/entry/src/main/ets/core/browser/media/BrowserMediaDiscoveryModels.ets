import { webview } from '@kit.ArkWeb';
import { BrowserSessionPrivacyMode } from '../../../common/models/BrowserModels';
import { MediaProbePolicyContext } from '../../../services/media/MediaProbePolicyService';
import {
  MediaResourceListItem,
  MediaResourceTabCounts
} from '../../../features/mediaDiscovery/MediaResourceProjectionModels';

export interface BrowserMediaDiscoverySurfaceState {
  videoMediaCount: number;
  resourceListItems: MediaResourceListItem[];
  resourceTabCounts: MediaResourceTabCounts;
  resourceScanInProgress: boolean;
}

export interface BrowserMediaDiscoveryRuntimeContext extends MediaProbePolicyContext {
}

export interface BrowserMediaDiscoveryPageInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  controller?: webview.WebviewController;
  runtime: BrowserMediaDiscoveryRuntimeContext;
}

export interface BrowserMediaDiscoveryInterceptInput {
  tabId: string;
  pageUrl: string;
  pageTitle: string;
  privacyMode: BrowserSessionPrivacyMode;
  request: WebResourceRequest;
  controller?: webview.WebviewController;
  runtime: BrowserMediaDiscoveryRuntimeContext;
}

export interface BrowserMediaDiscoveryUserScriptScanInput extends BrowserMediaDiscoveryPageInput {
  isPrivateTab: boolean;
}

export interface BrowserMediaDiscoveryLaunchProbeInput extends BrowserMediaDiscoveryPageInput {
}

export interface BrowserMediaDiscoverySurfaceInput {
  tabId: string;
  runtime: BrowserMediaDiscoveryRuntimeContext;
  resourcePanelOpen?: boolean;
}

export interface BrowserMediaDiscoveryHost {
  resolveActiveTabId: () => string;
  isActiveTab: (tabId: string) => boolean;
  resolvePageUrlForTab: (tabId: string) => string;
  resolvePageTitleForTab: (tabId: string) => string;
  resolvePrivacyModeForTab: (tabId: string) => BrowserSessionPrivacyMode;
  buildRuntimeContext: () => BrowserMediaDiscoveryRuntimeContext;
  resolveInteractionQuietDelayMs: (baseDelayMs: number) => number;
  applyMediaDiscoverySurfaceState: (state: BrowserMediaDiscoverySurfaceState) => void;
  showToast: (message: string) => void;
}
