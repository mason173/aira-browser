import { BrowserTabState } from '../tabs/TabManager';

export interface BrowserWindowSuspendedContext {
  tabs: BrowserTabState[];
  activeTabId: string;
  tabSequence: number;
  showHomePage: boolean;
}
