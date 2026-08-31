import { BrowserCreateTabOptions, BrowserTabState, BrowserTabManagerPort } from '../tabs/TabManager';
import { BrowserTabTransitionCoordinator, BrowserTabTransitionResult } from './BrowserTabTransitionCoordinator';

export interface BrowserAttachedWindowTabOpenInput {
  tabManager: BrowserTabManagerPort;
  tabs: BrowserTabState[];
  tabSequence: number;
  openerTabId: string;
  targetUrl: string;
  title: string;
  homeUrl: string;
  createOptions: BrowserCreateTabOptions;
}

export interface BrowserAttachedWindowTabOpenPlan {
  transition: BrowserTabTransitionResult;
  targetTabId: string;
}

export class BrowserAttachedWindowTabCoordinator {
  private tabTransitionCoordinator: BrowserTabTransitionCoordinator = new BrowserTabTransitionCoordinator();

  buildOpenPlan(input: BrowserAttachedWindowTabOpenInput): BrowserAttachedWindowTabOpenPlan {
    const transition = this.tabTransitionCoordinator.createTab(
      input.tabManager,
      input.tabs,
      input.tabSequence,
      input.targetUrl,
      input.title,
      input.homeUrl,
      input.createOptions
    );
    return {
      transition: transition,
      targetTabId: transition.activeTabId
    };
  }
}
