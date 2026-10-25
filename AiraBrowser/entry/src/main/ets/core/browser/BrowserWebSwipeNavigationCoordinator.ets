import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import vibrator from '@ohos.vibrator';
import { webview } from '@kit.ArkWeb';
import { BrowserWebHistoryDirection, canTraverseWebHistory } from '../web/BrowserWebComponentController';
import {
  WEB_SWIPE_NAVIGATION_BRIDGE,
  WebSwipeNavigationScriptService
} from '../../services/web/WebSwipeNavigationScriptService';

export interface BrowserWebSwipeNavigationHost {
  isEnabled: () => boolean;
  isEligible: (tabId: string) => boolean;
  resolvePanelDetent: () => HomeSearchPanelDetent;
  resolveController: (tabId: string) => webview.WebviewController | undefined;
  navigate: (direction: BrowserWebHistoryDirection) => void;
}

class WebSwipeNavigationBridge {
  private readonly readCapabilities: () => number;
  private readonly requestNavigation: (direction: string, url: string) => void;
  private readonly requestReadyFeedback: (direction: string, url: string) => void;

  constructor(
    readCapabilities: () => number,
    requestNavigation: (direction: string, url: string) => void,
    requestReadyFeedback: (direction: string, url: string) => void
  ) {
    this.readCapabilities = readCapabilities;
    this.requestNavigation = requestNavigation;
    this.requestReadyFeedback = requestReadyFeedback;
  }

  getCapabilities(): number { return this.readCapabilities(); }
  navigate(direction: string, url: string): void { this.requestNavigation(direction, url); }
  ready(direction: string, url: string): void { this.requestReadyFeedback(direction, url); }
}

interface WebSwipeTouchSession {
  tabId: string;
  controller: webview.WebviewController;
  url: string;
  // Zero while the physical finger remains down; only release starts the bridge grace period.
  expiresAt: number;
  readyFeedbackSent: boolean;
}

export class BrowserWebSwipeNavigationCoordinator {
  private readonly scripts: WebSwipeNavigationScriptService = new WebSwipeNavigationScriptService();
  private touchSession?: WebSwipeTouchSession;

  private readonly host: BrowserWebSwipeNavigationHost;

  constructor(host: BrowserWebSwipeNavigationHost) { this.host = host; }

  reset(tabId?: string): void {
    if (tabId === undefined || this.touchSession?.tabId === tabId) this.touchSession = undefined;
  }

  handleControllerAttached(tabId: string): void {
    const controller = this.host.resolveController(tabId);
    if (controller === undefined) return;
    try { controller.deleteJavaScriptRegister(WEB_SWIPE_NAVIGATION_BRIDGE); } catch (_) {}
    try {
      controller.registerJavaScriptProxy(new WebSwipeNavigationBridge(
        (): number => this.capabilities(tabId, controller),
        (direction: string, url: string): void => this.requestNavigation(tabId, controller, direction, url),
        (direction: string, url: string): void => this.requestReadyFeedback(tabId, controller, direction, url)
      ), WEB_SWIPE_NAVIGATION_BRIDGE, ['getCapabilities', 'navigate', 'ready']);
    } catch (_) {}
  }

  sync(tabIds: string[]): void {
    const enabled = this.host.isEnabled();
    if (!enabled) tabIds.forEach((tabId: string): void => this.reset(tabId));
    const script = this.scripts.buildRuntimeScript(enabled);
    tabIds.forEach((tabId: string): void => {
      const controller = this.host.resolveController(tabId);
      if (controller === undefined) return;
      try { void controller.runJavaScript(script).catch((): void => {}); } catch (_) {}
    });
  }

  handleTouch(tabId: string, event: TouchEvent): void {
    if (!this.host.isEnabled() || event.type === TouchType.Cancel || event.touches.length > 1) {
      this.reset(tabId);
      return;
    }
    if (event.type === TouchType.Move) return;
    if (!this.isEligible(tabId)) { this.reset(tabId); return; }
    if (event.type === TouchType.Down) {
      this.reset();
      const controller = this.host.resolveController(tabId);
      if (controller === undefined || event.touches.length !== 1) return;
      try {
        const url = controller.getUrl();
        if (!/^https?:\/\//i.test(url)) return;
        this.touchSession = {
          tabId: tabId, controller: controller, url: url, expiresAt: 0, readyFeedbackSent: false
        };
      } catch (_) {}
    } else if (event.type === TouchType.Up && this.touchSession?.tabId === tabId) {
      // ArkUI and DOM touch-end callbacks can arrive in either order.
      this.touchSession.expiresAt = Date.now() + 350;
    }
  }

  private isEligible(tabId: string): boolean {
    // Scrolling/reading with the toolbar tucked away must not disable history gestures.
    return this.host.isEligible(tabId) && this.host.resolvePanelDetent() !== 'middle';
  }

  private capabilities(tabId: string, controller: webview.WebviewController): number {
    if (!this.host.isEnabled() || !this.isEligible(tabId) ||
      this.host.resolveController(tabId) !== controller) return 0;
    try {
      return 1 | (canTraverseWebHistory(controller, 'back') ? 2 : 0) |
        (canTraverseWebHistory(controller, 'forward') ? 4 : 0);
    } catch (_) { return 0; }
  }

  private resolveValidTouchSession(
    tabId: string, controller: webview.WebviewController, direction: string, url: string
  ): WebSwipeTouchSession | undefined {
    if (direction !== 'back' && direction !== 'forward') return undefined;
    const session = this.touchSession;
    if (session === undefined || session.tabId !== tabId || session.controller !== controller ||
      session.url !== url || (session.expiresAt > 0 && Date.now() > session.expiresAt) ||
      !(this.capabilities(tabId, controller) & (direction === 'back' ? 2 : 4))) return undefined;
    try { if (controller.getUrl() !== url) return undefined; } catch (_) { return undefined; }
    return session;
  }

  private requestReadyFeedback(
    tabId: string, controller: webview.WebviewController, direction: string, url: string
  ): void {
    const session = this.resolveValidTouchSession(tabId, controller, direction, url);
    // This tick means "release to navigate". Never deliver it after physical release,
    // or repeatedly while holding/jittering around the threshold in one gesture.
    if (session === undefined || session.expiresAt !== 0 || session.readyFeedbackSent) return;
    session.readyFeedbackSent = true;
    try {
      vibrator.startVibration({ type: 'time', duration: 18 }, { usage: 'touch' })
        .catch((_error: Error) => {});
    } catch (_error) {
      // An unavailable motor must not consume or interrupt the pending gesture.
    }
  }

  private requestNavigation(
    tabId: string, controller: webview.WebviewController, direction: string, url: string
  ): void {
    if (direction !== 'back' && direction !== 'forward') return;
    if (this.resolveValidTouchSession(tabId, controller, direction, url) === undefined) return;
    // Consume before dispatch: one physical touch sequence can issue at most one native command.
    this.reset();
    this.host.navigate(direction);
  }
}
