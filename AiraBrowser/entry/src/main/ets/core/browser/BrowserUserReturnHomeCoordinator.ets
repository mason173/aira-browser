import {
  BrowserCreateTabOptions,
  BrowserTabState
} from '../tabs/TabManager';
import { BrowserTabCloseCoordinator } from './BrowserTabCloseCoordinator';

export type BrowserUserReturnHomeSource = 'bottom_gesture' | 'bottom_toolbar_home';

export interface BrowserUserReturnHomeRequest {
  source: BrowserUserReturnHomeSource;
  showHomePage: boolean;
  showTabsSheet: boolean;
  activeTab: BrowserTabState | undefined;
  activeTabId: string;
}

export interface BrowserUserReturnHomeFlowRequest extends BrowserUserReturnHomeRequest {
  tabs: BrowserTabState[];
}

export interface BrowserUserReturnHomePlan {
  shouldCloseCurrentTab: boolean;
  shouldPlayDirectHomeReveal: boolean;
  tabId: string;
  homeOptions: BrowserCreateTabOptions;
  helperMessage: string;
}

export interface BrowserUserReturnHomeFlowHost {
  goHomePreservingCurrentTab: () => Promise<void>;
  prepareDirectHomeReveal: () => Promise<void>;
}

export class BrowserUserReturnHomeCoordinator {
  private readonly tabCloseCoordinator: BrowserTabCloseCoordinator;

  constructor(tabCloseCoordinator: BrowserTabCloseCoordinator) {
    this.tabCloseCoordinator = tabCloseCoordinator;
  }

  async runFlow(request: BrowserUserReturnHomeFlowRequest, host: BrowserUserReturnHomeFlowHost): Promise<void> {
    const plan = this.buildPlan(request);
    if (!plan.shouldCloseCurrentTab || request.activeTab === undefined) {
      await host.goHomePreservingCurrentTab();
      return;
    }
    const shouldPlayDirectHomeReveal = plan.shouldPlayDirectHomeReveal;
    if (shouldPlayDirectHomeReveal) {
      await host.prepareDirectHomeReveal();
    }
    await this.tabCloseCoordinator.closeCurrentTabForUserReturnHome({
      activeTab: request.activeTab,
      helperMessage: plan.helperMessage,
      homeOptions: plan.homeOptions,
      shouldPlayDirectHomeReveal: shouldPlayDirectHomeReveal,
      cleanupReason: 'return_home_after_reveal'
    });
  }

  buildPlan(request: BrowserUserReturnHomeRequest): BrowserUserReturnHomePlan {
    const activeTab = request.activeTab;
    const shouldPlayDirectHomeReveal = this.shouldPlayDirectHomeReveal(request);
    if (request.showHomePage || request.showTabsSheet || activeTab === undefined ||
      activeTab.isHome || activeTab.id !== request.activeTabId) {
      return {
        shouldCloseCurrentTab: false,
        shouldPlayDirectHomeReveal,
        tabId: activeTab?.id ?? request.activeTabId,
        homeOptions: this.buildHomeOptionsFromTab(activeTab),
        helperMessage: '已回到主页'
      };
    }
    return {
      shouldCloseCurrentTab: true,
      shouldPlayDirectHomeReveal,
      tabId: activeTab.id,
      homeOptions: this.buildHomeOptionsFromTab(activeTab),
      helperMessage: '已关闭网页并回到主页'
    };
  }

  private shouldPlayDirectHomeReveal(request: BrowserUserReturnHomeRequest): boolean {
    return !request.showTabsSheet;
  }

  private buildHomeOptionsFromTab(tab: BrowserTabState | undefined): BrowserCreateTabOptions {
    if (tab === undefined) {
      return {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
    }
    return {
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope
    };
  }

}
