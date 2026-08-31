import { BrowserTabState } from '../tabs/TabManager';
import { WebAppCurrentUrlService } from '../../services/webapps/WebAppCurrentUrlService';
import {
  WebAppActiveContext,
  WebAppSessionCoordinator,
  WebAppSessionSnapshot,
  sharedWebAppSessionCoordinator
} from './WebAppSessionCoordinator';

export type WebAppExitStatus = 'not_active' | 'exit_scheduled' | 'already_exiting';
export type WebAppExitState = 'idle' | 'exiting' | 'failed';

export interface WebAppExitRequest {
  windowId: string;
  activeTab: BrowserTabState | undefined;
  currentUrl: string;
  reason: string;
}

export interface WebAppExitResult {
  consumed: boolean;
  status: WebAppExitStatus;
}

export interface WebAppExitHost {
  applySessionSnapshot: (snapshot: WebAppSessionSnapshot, source: string) => void;
  terminateSelf: () => Promise<void>;
}

const WEB_APP_EXIT_URL_RECORD_DEADLINE_MS: number = 120;

export class WebAppExitCoordinator {
  private readonly currentUrlService: WebAppCurrentUrlService;
  private readonly sessionCoordinator: WebAppSessionCoordinator;
  private exitStateByWindowId: Record<string, WebAppExitState | undefined> = {};

  constructor(
    currentUrlService: WebAppCurrentUrlService = new WebAppCurrentUrlService(),
    sessionCoordinator: WebAppSessionCoordinator = sharedWebAppSessionCoordinator
  ) {
    this.currentUrlService = currentUrlService;
    this.sessionCoordinator = sessionCoordinator;
  }

  requestTerminalBackExit(request: WebAppExitRequest, host: WebAppExitHost): WebAppExitResult {
    const activeContext = this.sessionCoordinator.getActive(request.windowId);
    if (activeContext === undefined) {
      return {
        consumed: false,
        status: 'not_active'
      };
    }
    const targetWindowId = this.resolveTargetWindowId(request, activeContext);
    if (this.resolveExitState(targetWindowId) === 'exiting') {
      return {
        consumed: true,
        status: 'already_exiting'
      };
    }
    this.exitStateByWindowId[targetWindowId] = 'exiting';
    void this.performTerminalBackExit(request, activeContext, targetWindowId, host);
    return {
      consumed: true,
      status: 'exit_scheduled'
    };
  }

  resolveExitState(windowId: string): WebAppExitState {
    return this.exitStateByWindowId[windowId.trim()] ?? 'idle';
  }

  private async performTerminalBackExit(
    request: WebAppExitRequest,
    activeContext: WebAppActiveContext,
    targetWindowId: string,
    host: WebAppExitHost
  ): Promise<void> {
    await this.recordCurrentUrlWithinDeadline(request, activeContext);
    try {
      await host.terminateSelf();
    } catch (_error) {
      this.exitStateByWindowId[targetWindowId] = 'failed';
      return;
    }

    const clearedSnapshot = this.sessionCoordinator.clear(targetWindowId);
    try {
      host.applySessionSnapshot(clearedSnapshot, 'webapp-exit');
    } catch (_error) {
    }
    this.exitStateByWindowId[targetWindowId] = undefined;
  }

  private async recordCurrentUrlWithinDeadline(
    request: WebAppExitRequest,
    activeContext: WebAppActiveContext
  ): Promise<void> {
    const targetUrl = this.currentUrlService.resolveCommittedExitUrl({
      activeContext: activeContext,
      tab: request.activeTab,
      url: request.currentUrl
    });
    if (targetUrl.length <= 0) {
      return;
    }
    const recordPromise: Promise<void> = this.currentUrlService.recordInstalledWebAppUrl({
      activeContext: activeContext,
      tab: request.activeTab,
      url: targetUrl
    }).then((_recorded: boolean): void => {}).catch((_error: Error): void => {});
    let timeoutTimerId = -1;
    const timeoutPromise: Promise<void> = new Promise((resolve) => {
      timeoutTimerId = setTimeout(() => {
        resolve();
      }, WEB_APP_EXIT_URL_RECORD_DEADLINE_MS);
    });
    await Promise.race([recordPromise, timeoutPromise]);
    if (timeoutTimerId >= 0) {
      clearTimeout(timeoutTimerId);
    }
  }

  private resolveTargetWindowId(request: WebAppExitRequest, activeContext: WebAppActiveContext): string {
    const requestedWindowId = request.windowId.trim();
    return requestedWindowId.length > 0 ? requestedWindowId : activeContext.windowId.trim();
  }

}
