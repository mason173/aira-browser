import {
  BrowserCreateTabOptions,
  BrowserTabMutationResult,
  BrowserTabState,
  BrowserTabManagerPort
} from '../tabs/TabManager';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserTabTransitionResult extends BrowserTabMutationResult {
  helperMessage: string;
}

export class BrowserTabTransitionCoordinator {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  createTab(
    tabManager: BrowserTabManagerPort,
    tabs: BrowserTabState[],
    tabSequence: number,
    initialUrl: string,
    initialTitle: string,
    homeUrl: string,
    options: BrowserCreateTabOptions = {}
  ): BrowserTabTransitionResult {
    const mutation = tabManager.createTab(
      tabs,
      tabSequence,
      initialUrl,
      initialTitle,
      this.resolveCreateTabBoundary(tabs, options)
    );
    return {
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: mutation.tabSequence,
      helperMessage: initialUrl === homeUrl ? '已打开新标签页。' : '已在新标签页中打开链接。'
    };
  }

  createBackgroundTab(
    tabManager: BrowserTabManagerPort,
    tabs: BrowserTabState[],
    activeTabId: string,
    tabSequence: number,
    initialUrl: string,
    initialTitle: string,
    homeUrl: string,
    options: BrowserCreateTabOptions = {}
  ): BrowserTabTransitionResult {
    const mutation = tabManager.createBackgroundTab(
      tabs,
      activeTabId,
      tabSequence,
      initialUrl,
      initialTitle,
      this.resolveCreateTabBoundary(tabs, options)
    );
    return {
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: mutation.tabSequence,
      helperMessage: initialUrl === homeUrl ? '已在后台打开新标签页。' : '已在后台打开链接。'
    };
  }

  switchToTab(
    tabManager: BrowserTabManagerPort,
    tabs: BrowserTabState[],
    activeTabId: string,
    targetTabId: string,
    tabSequence: number
  ): BrowserTabTransitionResult | undefined {
    const targetTab = tabs.find((tab: BrowserTabState) => tab.id === targetTabId);
    if (targetTab === undefined || targetTabId === activeTabId) {
      return undefined;
    }
    const mutation = tabManager.switchToTab(tabs, activeTabId, targetTabId);
    return {
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: Math.max(tabSequence, mutation.tabSequence),
      helperMessage: '已切换标签页。'
    };
  }

  closeTab(
    tabManager: BrowserTabManagerPort,
    tabs: BrowserTabState[],
    activeTabId: string,
    targetTabId: string,
    tabSequence: number
  ): BrowserTabTransitionResult {
    const mutation = tabManager.closeTab(tabs, activeTabId, targetTabId);
    return {
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: Math.max(tabSequence, mutation.tabSequence),
      helperMessage: '已关闭标签页。'
    };
  }

  closeTabAndActivate(
    tabManager: BrowserTabManagerPort,
    tabs: BrowserTabState[],
    activeTabId: string,
    targetTabId: string,
    nextActiveTabId: string,
    tabSequence: number,
    helperMessage: string = '已关闭标签页。'
  ): BrowserTabTransitionResult {
    const mutation = tabManager.closeTab(tabs, activeTabId, targetTabId);
    if (mutation.tabs.some((tab: BrowserTabState) => tab.id === nextActiveTabId) &&
      mutation.activeTabId !== nextActiveTabId) {
      const switchMutation = tabManager.switchToTab(mutation.tabs, mutation.activeTabId, nextActiveTabId);
      return {
        tabs: switchMutation.tabs,
        activeTabId: switchMutation.activeTabId,
        tabSequence: Math.max(tabSequence, switchMutation.tabSequence),
        helperMessage: helperMessage
      };
    }
    return {
      tabs: mutation.tabs,
      activeTabId: mutation.activeTabId,
      tabSequence: Math.max(tabSequence, mutation.tabSequence),
      helperMessage: helperMessage
    };
  }

  private resolveCreateTabBoundary(
    tabs: BrowserTabState[],
    options: BrowserCreateTabOptions
  ): BrowserCreateTabOptions {
    const hasExplicitBoundary =
      options.profileId !== undefined || options.privacyMode !== undefined || options.dataScope !== undefined;
    const activeTab = tabs.find((tab: BrowserTabState) => {
      return tab.runtimeState === 'active' || tab.runtimeState === 'loading' || tab.runtimeState === 'restoring';
    });
    const explicitBoundaryInput = this.buildCreateTabBoundaryInput(options);
    const openerBoundaryInput = this.buildTabBoundaryInput(activeTab);
    const boundary = hasExplicitBoundary
      ? this.profileBoundaryService.buildBoundary(explicitBoundaryInput)
      : this.profileBoundaryService.inheritFromBoundaryInputs(openerBoundaryInput, explicitBoundaryInput);
    return {
      profileId: boundary.profileId,
      privacyMode: boundary.privacyMode,
      dataScope: boundary.dataScope,
      launchContext: options.launchContext,
      openerTabId: options.openerTabId,
      openSource: options.openSource,
      openedByNewWindow: options.openedByNewWindow,
      insertAfterTabId: options.insertAfterTabId
    };
  }

  private buildCreateTabBoundaryInput(options: BrowserCreateTabOptions): BrowserDataBoundaryInput {
    return {
      profileId: options.profileId,
      privacyMode: options.privacyMode,
      dataScope: options.dataScope
    };
  }

  private buildTabBoundaryInput(tab: BrowserTabState | undefined): BrowserDataBoundaryInput | undefined {
    if (tab === undefined) {
      return undefined;
    }
    return {
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    };
  }
}
