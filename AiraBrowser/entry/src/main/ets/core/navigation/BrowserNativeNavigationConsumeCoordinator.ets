import { BrowserAppUrlOpenRequest } from '../browser/BrowserAppUrlOpenCoordinator';
import {
  BrowserNavigationRouteParams,
  BrowserPendingNavigationConsumeResult,
  BrowserPendingShellIntent,
  consumePendingBrowserShellIntent,
  consumePendingBrowserNavigationRequestWithRouteFallback
} from './BrowserNativeNavigationRequestCenter';

export interface BrowserNativeNavigationConsumeHost {
  getRouteParams: () => BrowserNavigationRouteParams | undefined;
  getConsumedRouteToken: () => string;
  setConsumedRouteToken: (routeToken: string) => void;
  getActiveTabId: () => string;
  openBrowserRequest: (request: BrowserAppUrlOpenRequest) => void;
  openTabsOverview: () => void;
  returnHome: () => void;
}

export class BrowserNativeNavigationConsumeCoordinator {
  private readonly host: BrowserNativeNavigationConsumeHost;

  constructor(host: BrowserNativeNavigationConsumeHost) {
    this.host = host;
  }

  consume(): void {
    this.consumeShellIntent(consumePendingBrowserShellIntent());
    const activeTabId = this.host.getActiveTabId();
    const consumeResult: BrowserPendingNavigationConsumeResult = consumePendingBrowserNavigationRequestWithRouteFallback(
      this.host.getRouteParams(),
      this.host.getConsumedRouteToken()
    );
    const request = consumeResult.request;
    if (request.url.trim().length > 0 && consumeResult.routeToken.length > 0) {
      this.host.setConsumedRouteToken(consumeResult.routeToken);
    }
    if (request.url.trim().length === 0) {
      return;
    }
    this.host.openBrowserRequest({
      url: request.url,
      title: request.title,
      intent: request.intent,
      source: request.source,
      profileId: request.profileId,
      privacyMode: request.privacyMode,
      dataScope: request.dataScope,
      openerTabId: activeTabId,
      requestId: request.requestId
    });
  }

  private consumeShellIntent(intent: BrowserPendingShellIntent): void {
    if (intent === 'open_tabs_overview') {
      this.host.openTabsOverview();
      return;
    }
    if (intent === 'return_home') {
      this.host.returnHome();
    }
  }

}
