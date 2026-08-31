export enum BrowserPullRefreshAction {
  UNKNOWN = 0,
  PULL_START = 1,
  PULL_REFRESH = 2,
  PULL_CANCEL = 3,
  PULL_RELEASE = 4,
  PULL_RESET = 5
}

export interface BrowserPullRefreshState {
  action: BrowserPullRefreshAction;
  offsetY: number;
  loadingVisible: boolean;
  enableLoading: boolean;
  refreshInFlight: boolean;
  activeTabId: string;
  generation: number;
}

export type BrowserPullRefreshShellFamily = 'phone' | 'large_screen';
export type BrowserPullRefreshInputProfile = 'touch' | 'pointer' | 'keyboard_pointer';

export interface BrowserPullRefreshContext {
  enabled: boolean;
  activeTabId: string;
  pageUrl: string;
  showHomePage: boolean;
  showTabsSheet: boolean;
  webPageVisible: boolean;
  pageErrorSurfaceVisible: boolean;
  shellFamily: BrowserPullRefreshShellFamily;
  inputProfile: BrowserPullRefreshInputProfile;
}

export interface BrowserPullRefreshPresentation {
  visible: boolean;
  offsetY: number;
  topPlaceHolderHeight: number;
  enableLoading: boolean;
}
