import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WebpageTranslationRuntimeBridge } from '../../services/web/WebpageTranslationRuntimeBridge';

const WEBPAGE_TRANSLATION_DYNAMIC_POLL_INTERVAL_MS: number = 1400;
const WEBPAGE_TRANSLATION_LIFECYCLE_LOG_DOMAIN: number = 0x0000;
const WEBPAGE_TRANSLATION_LIFECYCLE_LOG_TAG: string = 'QFWebTranslateLife';

export interface WebpageTranslationRuntimeSignalChange {
  routeChanged: boolean;
  pageChanged: boolean;
}

export type WebpageTranslationLifecycleEvent =
  'page_begin' |
  'page_end' |
  'first_contentful_paint' |
  'first_meaningful_paint' |
  'refresh_or_history' |
  'spa_route_changed' |
  'tab_activated' |
  'tab_deactivated' |
  'runtime_detached' |
  'tab_destroyed';

export interface WebpageTranslationLifecycleSnapshot {
  event: WebpageTranslationLifecycleEvent;
  url: string;
  dynamicTrackingPaused: boolean;
  pollingActive: boolean;
  pageSignalVersion: string;
  routeSignalVersion: string;
  at: number;
}

export class WebpageTranslationLifecycleCoordinator {
  private dynamicPollingTimer: number = 0;
  private pageSignalVersion: string = '0';
  private routeSignalVersion: string = '0';
  private dynamicTrackingPaused: boolean = false;
  private dynamicPollInFlight: boolean = false;
  private dynamicPollHandler?: () => Promise<void>;
  private currentUrl: string = '';

  pauseDynamicTranslation(): void {
    this.dynamicTrackingPaused = true;
    this.stopDynamicTranslationPolling();
  }

  resumeDynamicTranslation(): void {
    this.dynamicTrackingPaused = false;
  }

  isDynamicTrackingPaused(): boolean {
    return this.dynamicTrackingPaused;
  }

  stopDynamicTranslationPolling(): void {
    if (this.dynamicPollingTimer !== 0) {
      clearInterval(this.dynamicPollingTimer);
      this.dynamicPollingTimer = 0;
    }
    this.dynamicPollHandler = undefined;
  }

  handlePageBegin(url: string): WebpageTranslationLifecycleSnapshot {
    this.stopDynamicTranslationPolling();
    this.resetSignalVersions();
    return this.recordLifecycleEvent('page_begin', url);
  }

  handlePageEnd(url: string): WebpageTranslationLifecycleSnapshot {
    return this.recordLifecycleEvent('page_end', url);
  }

  handleFirstContentfulPaint(url: string): WebpageTranslationLifecycleSnapshot {
    return this.recordLifecycleEvent('first_contentful_paint', url);
  }

  handleFirstMeaningfulPaint(url: string): WebpageTranslationLifecycleSnapshot {
    return this.recordLifecycleEvent('first_meaningful_paint', url);
  }

  handleRefreshOrBackForward(url: string): WebpageTranslationLifecycleSnapshot {
    this.stopDynamicTranslationPolling();
    this.resetSignalVersions();
    return this.recordLifecycleEvent('refresh_or_history', url);
  }

  handleSpaRouteChanged(url: string): WebpageTranslationLifecycleSnapshot {
    this.stopDynamicTranslationPolling();
    this.resetSignalVersions();
    return this.recordLifecycleEvent('spa_route_changed', url);
  }

  handleTabActivated(url: string): WebpageTranslationLifecycleSnapshot {
    this.resetSignalVersions();
    return this.recordLifecycleEvent('tab_activated', url);
  }

  handleTabDeactivated(): WebpageTranslationLifecycleSnapshot {
    this.stopDynamicTranslationPolling();
    this.resetSignalVersions();
    return this.recordLifecycleEvent('tab_deactivated', this.currentUrl);
  }

  handleRuntimeDetached(): WebpageTranslationLifecycleSnapshot {
    this.stopDynamicTranslationPolling();
    this.resetSignalVersions();
    return this.recordLifecycleEvent('runtime_detached', this.currentUrl);
  }

  handleTabDestroyed(): WebpageTranslationLifecycleSnapshot {
    this.stopDynamicTranslationPolling();
    this.resetSignalVersions();
    return this.recordLifecycleEvent('tab_destroyed', this.currentUrl);
  }

  async startDynamicTranslationPolling(
    controller: webview.WebviewController,
    runtimeBridge: WebpageTranslationRuntimeBridge,
    onPoll: () => Promise<void>
  ): Promise<void> {
    this.stopDynamicTranslationPolling();
    try {
      await runtimeBridge.startDynamicTracking(controller);
      this.pageSignalVersion = await runtimeBridge.getPageSignalVersion(controller);
      this.routeSignalVersion = await runtimeBridge.getRouteSignalVersion(controller);
    } catch (_error) {
      return;
    }
    if (this.dynamicTrackingPaused) {
      return;
    }
    this.dynamicPollHandler = onPoll;
    this.dynamicPollingTimer = setInterval(() => {
      this.triggerDynamicPoll();
    }, WEBPAGE_TRANSLATION_DYNAMIC_POLL_INTERVAL_MS);
    this.triggerDynamicPoll();
  }

  async readSignalChange(
    controller: webview.WebviewController,
    runtimeBridge: WebpageTranslationRuntimeBridge
  ): Promise<WebpageTranslationRuntimeSignalChange> {
    const nextRouteSignalVersion = await runtimeBridge.getRouteSignalVersion(controller);
    const nextPageSignalVersion = await runtimeBridge.getPageSignalVersion(controller);
    if (nextRouteSignalVersion !== this.routeSignalVersion) {
      this.routeSignalVersion = nextRouteSignalVersion;
      this.pageSignalVersion = nextPageSignalVersion;
      return {
        routeChanged: true,
        pageChanged: true
      };
    }
    if (nextPageSignalVersion === this.pageSignalVersion) {
      return {
        routeChanged: false,
        pageChanged: false
      };
    }
    this.pageSignalVersion = nextPageSignalVersion;
    return {
      routeChanged: false,
      pageChanged: true
    };
  }

  private triggerDynamicPoll(): void {
    const pollHandler = this.dynamicPollHandler;
    if (this.dynamicPollInFlight || pollHandler === undefined) {
      return;
    }
    this.dynamicPollInFlight = true;
    let pollPromise: Promise<void>;
    try {
      pollPromise = pollHandler();
    } catch (_error) {
      this.dynamicPollInFlight = false;
      return;
    }
    pollPromise
      .then(() => {
        this.dynamicPollInFlight = false;
      })
      .catch(() => {
        this.dynamicPollInFlight = false;
      });
  }

  private resetSignalVersions(): void {
    this.pageSignalVersion = '0';
    this.routeSignalVersion = '0';
  }

  private recordLifecycleEvent(
    event: WebpageTranslationLifecycleEvent,
    url: string
  ): WebpageTranslationLifecycleSnapshot {
    this.currentUrl = url;
    const snapshot: WebpageTranslationLifecycleSnapshot = {
      event: event,
      url: url,
      dynamicTrackingPaused: this.dynamicTrackingPaused,
      pollingActive: this.dynamicPollingTimer !== 0,
      pageSignalVersion: this.pageSignalVersion,
      routeSignalVersion: this.routeSignalVersion,
      at: Date.now()
    };
    hilog.info(
      WEBPAGE_TRANSLATION_LIFECYCLE_LOG_DOMAIN,
      WEBPAGE_TRANSLATION_LIFECYCLE_LOG_TAG,
      'lifecycle event=%{public}s url=%{public}s paused=%{public}s polling=%{public}s pageSignal=%{public}s routeSignal=%{public}s',
      snapshot.event,
      snapshot.url,
      snapshot.dynamicTrackingPaused ? 'true' : 'false',
      snapshot.pollingActive ? 'true' : 'false',
      snapshot.pageSignalVersion,
      snapshot.routeSignalVersion
    );
    return snapshot;
  }
}
