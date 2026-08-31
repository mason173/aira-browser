import { BrowserTabState } from '../tabs/TabManager';
import { WebPagePresentation } from '../web/WebRuntimeBridge';
import { WebRestoreRecoveryPlan } from '../web/WebRecoveryManager';
import { BrowserAddressDisplayCoordinator } from './BrowserAddressDisplayCoordinator';
import { BrowserShellViewModel } from './BrowserShellViewModel';

export interface BrowserShellVisualState {
  showHomePage: boolean;
  showPageErrorSurface: boolean;
  currentUrl: string;
  pendingWebUrl: string;
  addressInput: string;
  currentTitle: string;
  errorMessage: string;
  helperMessage: string;
  runtimeDegradedMessage: string;
  pageProgress: number;
  isLoading: boolean;
  resetScrollMask: boolean;
}

export class BrowserShellStateCoordinator {
  private readonly shellViewModel: BrowserShellViewModel;
  private readonly addressDisplayCoordinator: BrowserAddressDisplayCoordinator;

  constructor(
    shellViewModel: BrowserShellViewModel = new BrowserShellViewModel(),
    addressDisplayCoordinator: BrowserAddressDisplayCoordinator = new BrowserAddressDisplayCoordinator()
  ) {
    this.shellViewModel = shellViewModel;
    this.addressDisplayCoordinator = addressDisplayCoordinator;
  }

  buildHomeState(runtimeDegradedMessage: string = ''): BrowserShellVisualState {
    return {
      showHomePage: true,
      showPageErrorSurface: false,
      currentUrl: '',
      pendingWebUrl: '',
      addressInput: '',
      currentTitle: '新标签页',
      errorMessage: '',
      helperMessage: '已回到主页',
      runtimeDegradedMessage: runtimeDegradedMessage,
      pageProgress: 0,
      isLoading: false,
      resetScrollMask: true
    };
  }

  buildNativeTabState(tab: BrowserTabState): BrowserShellVisualState {
    return {
      showHomePage: false,
      showPageErrorSurface: false,
      currentUrl: tab.url,
      pendingWebUrl: '',
      addressInput: '',
      currentTitle: tab.title,
      errorMessage: '',
      helperMessage: '',
      runtimeDegradedMessage: '',
      pageProgress: 100,
      isLoading: false,
      resetScrollMask: true
    };
  }

  buildActiveTabState(
    tab: BrowserTabState,
    activeTabId: string,
    runtimeDegradedMessage: string = ''
  ): BrowserShellVisualState {
    const pendingUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url;
    return {
      showHomePage: false,
      showPageErrorSurface: tab.runtimeState === 'error' || tab.runtimeState === 'crashed',
      currentUrl: tab.url,
      pendingWebUrl: pendingUrl,
      addressInput: this.addressDisplayCoordinator.resolveCommittedDisplay(tab.id, pendingUrl),
      currentTitle: tab.title,
      errorMessage: tab.runtimeState === 'error' || tab.runtimeState === 'crashed' ? tab.lastError : '',
      helperMessage: this.shellViewModel.getTabRuntimePresentation(tab, activeTabId).helperMessage,
      runtimeDegradedMessage: runtimeDegradedMessage,
      pageProgress: tab.runtimeState === 'active' ? 100 : 0,
      isLoading: tab.runtimeState === 'loading' || tab.runtimeState === 'restoring',
      resetScrollMask: true
    };
  }

  buildLiveRuntimeState(
    tab: BrowserTabState,
    activeTabId: string,
    helperMessage: string = '',
    runtimeDegradedMessage: string = ''
  ): BrowserShellVisualState {
    const state = this.buildActiveTabState(tab, activeTabId, runtimeDegradedMessage);
    return {
      showHomePage: state.showHomePage,
      showPageErrorSurface: false,
      currentUrl: state.currentUrl,
      pendingWebUrl: state.pendingWebUrl,
      addressInput: state.addressInput,
      currentTitle: state.currentTitle,
      errorMessage: state.errorMessage,
      helperMessage: helperMessage.length > 0 ? helperMessage : state.helperMessage,
      runtimeDegradedMessage: state.runtimeDegradedMessage,
      pageProgress: 100,
      isLoading: false,
      resetScrollMask: false
    };
  }

  buildPagePresentationState(
    presentation: WebPagePresentation,
    runtimeDegradedMessage: string = ''
  ): BrowserShellVisualState {
    return {
      showHomePage: false,
      showPageErrorSurface: false,
      currentUrl: presentation.currentUrl,
      pendingWebUrl: presentation.currentUrl,
      addressInput: presentation.addressInput,
      currentTitle: presentation.currentTitle,
      errorMessage: '',
      helperMessage: presentation.helperMessage,
      runtimeDegradedMessage: runtimeDegradedMessage,
      pageProgress: presentation.pageProgress,
      isLoading: presentation.isLoading,
      resetScrollMask: false
    };
  }

  buildRestoreTransitionState(tab: BrowserTabState, restorePlan: WebRestoreRecoveryPlan): BrowserShellVisualState {
    const pendingUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url;
    return {
      showHomePage: false,
      showPageErrorSurface: false,
      currentUrl: tab.url,
      pendingWebUrl: pendingUrl,
      addressInput: this.addressDisplayCoordinator.resolveCommittedDisplay(tab.id, pendingUrl),
      currentTitle: tab.title,
      errorMessage: '',
      helperMessage: restorePlan.helperMessage,
      runtimeDegradedMessage: '',
      pageProgress: 0,
      isLoading: true,
      resetScrollMask: false
    };
  }

  buildSnapshotRestoreSuccessState(tab: BrowserTabState): BrowserShellVisualState {
    const pendingUrl = tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url;
    return {
      showHomePage: false,
      showPageErrorSurface: false,
      currentUrl: tab.url,
      pendingWebUrl: pendingUrl,
      addressInput: this.addressDisplayCoordinator.resolveCommittedDisplay(tab.id, pendingUrl),
      currentTitle: tab.title,
      errorMessage: '',
      helperMessage: '已恢复标签页',
      runtimeDegradedMessage: '',
      pageProgress: 100,
      isLoading: false,
      resetScrollMask: false
    };
  }

  buildPageErrorState(tab: BrowserTabState, errorMessage: string, runtimeDegradedMessage: string): BrowserShellVisualState {
    return {
      showHomePage: false,
      showPageErrorSurface: true,
      currentUrl: tab.url,
      pendingWebUrl: tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url,
      addressInput: this.addressDisplayCoordinator.resolveCommittedDisplay(
        tab.id,
        tab.pendingUrl.length > 0 ? tab.pendingUrl : tab.url
      ),
      currentTitle: tab.title,
      errorMessage: errorMessage,
      helperMessage: tab.runtimeState === 'crashed' ? '当前标签页运行时异常' : '当前页面打开失败',
      runtimeDegradedMessage: runtimeDegradedMessage,
      pageProgress: 0,
      isLoading: false,
      resetScrollMask: false
    };
  }
}
