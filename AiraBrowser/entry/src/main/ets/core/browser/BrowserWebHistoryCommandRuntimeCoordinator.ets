import {
  BrowserWebNavigationCommandReason,
  BrowserWebNavigationCommandResult
} from '../web/BrowserWebPageController';
import { BrowserWebHistoryDirection } from '../web/BrowserWebComponentController';
import { WebLinkContextMenuCoordinator } from '../web/WebLinkContextMenuCoordinator';
import { BrowserFullscreenSessionCoordinator } from './BrowserFullscreenSessionCoordinator';
import { BrowserWebTabsController } from './BrowserWebTabsController';
import { BrowserPageFindCoordinator } from './BrowserPageFindCoordinator';
import { BrowserQuickSearchSwitchingCoordinator } from '../search/BrowserQuickSearchSwitchingCoordinator';

export type BrowserWebHistoryCommandSource =
  'toolbar_back' |
  'toolbar_forward' |
  'keyboard_back' |
  'keyboard_forward';

export interface BrowserWebHistoryCommandRuntimeCoordinatorHost {
  resolveActiveTabId: () => string;
  showNativeToast: (message: string) => void;
  showKeyboardShortcutMessage: (message: string) => void;
}

export interface BrowserWebHistoryCommandRuntimeCoordinatorDependencies {
  webTabsController: BrowserWebTabsController;
  pageFindCoordinator: BrowserPageFindCoordinator;
  contextMenuCoordinator: WebLinkContextMenuCoordinator;
  fullscreenSessionCoordinator: BrowserFullscreenSessionCoordinator;
  quickSearchSwitchingCoordinator: BrowserQuickSearchSwitchingCoordinator;
}

export class BrowserWebHistoryCommandRuntimeCoordinator {
  private readonly dependencies: BrowserWebHistoryCommandRuntimeCoordinatorDependencies;
  private readonly host: BrowserWebHistoryCommandRuntimeCoordinatorHost;

  constructor(
    dependencies: BrowserWebHistoryCommandRuntimeCoordinatorDependencies,
    host: BrowserWebHistoryCommandRuntimeCoordinatorHost
  ) {
    this.dependencies = dependencies;
    this.host = host;
  }

  handleSystemBack(): BrowserWebNavigationCommandResult {
    const transientResult = this.consumeSystemBackTransientSurface();
    if (transientResult !== undefined) {
      return transientResult;
    }
    return this.navigate('back');
  }

  handleThreatContainmentReturn(): boolean {
    let result = this.navigate('back');
    if (result.status === 'transient_consumed' && result.reason === 'dialog_back') {
      result = this.navigate('back');
    }
    return result.status !== 'unavailable' && result.status !== 'failed';
  }

  handleRootBottomPanelWebForward(): void {
    this.handleToolbarNavigateForward();
  }

  handleToolbarNavigateBack(): void {
    const result = this.navigate('back');
    this.presentCommandFeedback('back', 'toolbar_back', result, '');
  }

  handleToolbarNavigateForward(): void {
    const result = this.navigate('forward');
    this.presentCommandFeedback('forward', 'toolbar_forward', result, '');
  }

  handleShortcutNavigateBack(): void {
    const result = this.navigate('back');
    this.presentCommandFeedback('back', 'keyboard_back', result, '已后退。');
  }

  handleShortcutNavigateForward(message: string): void {
    const result = this.navigate('forward');
    this.presentCommandFeedback('forward', 'keyboard_forward', result, message);
  }

  private consumeSystemBackTransientSurface(): BrowserWebNavigationCommandResult | undefined {
    const tabId = this.host.resolveActiveTabId();
    if (tabId.length <= 0) {
      return undefined;
    }
    if (this.dependencies.contextMenuCoordinator.isVisibleForTab(tabId)) {
      this.dependencies.contextMenuCoordinator.dismiss();
      return this.buildTransientConsumedResult('web_context_menu');
    }
    if (this.dependencies.pageFindCoordinator.isVisibleForTab(tabId)) {
      this.dependencies.pageFindCoordinator.close(tabId);
      return this.buildTransientConsumedResult('page_find');
    }
    if (tabId === this.host.resolveActiveTabId() &&
      this.dependencies.fullscreenSessionCoordinator.snapshot().fullScreenModeEnabled) {
      void this.dependencies.fullscreenSessionCoordinator.disableFullscreen(true);
      return this.buildTransientConsumedResult('web_fullscreen');
    }
    return undefined;
  }

  private buildTransientConsumedResult(reason: BrowserWebNavigationCommandReason): BrowserWebNavigationCommandResult {
    return {
      status: 'transient_consumed',
      reason: reason,
      targetUrl: '',
      errorMessage: ''
    };
  }

  private navigate(direction: BrowserWebHistoryDirection): BrowserWebNavigationCommandResult {
    const result = direction === 'back'
      ? this.dependencies.webTabsController.goActivePageBackward()
      : this.dependencies.webTabsController.goActivePageForward();
    if (result.status === 'loading_cancelled') {
      this.dependencies.quickSearchSwitchingCoordinator.handleNavigationCancelled(
        this.host.resolveActiveTabId(),
        result.targetUrl
      );
    }
    return result;
  }

  private presentCommandFeedback(
    direction: BrowserWebHistoryDirection,
    source: BrowserWebHistoryCommandSource,
    result: BrowserWebNavigationCommandResult,
    successMessage: string
  ): void {
    let message = '';
    if (result.status === 'unavailable') {
      message = direction === 'back' ? '没有可后退的页面。' : '没有可前进的页面。';
    } else if (result.status === 'failed') {
      message = direction === 'back' ? '后退失败，请重试。' : '前进失败，请重试。';
    } else if (result.status === 'native_issued') {
      message = successMessage;
    }
    if (message.length <= 0) {
      return;
    }
    if (source === 'keyboard_back' || source === 'keyboard_forward') {
      this.host.showKeyboardShortcutMessage(message);
      return;
    }
    this.host.showNativeToast(message);
  }
}
