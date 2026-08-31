import { webview } from '@kit.ArkWeb';
import { TabCrashReason, TabRestoreReason } from '../../common/models/BrowserModels';
import { BrowserFaultClassifier } from '../../core/browser/BrowserFaultClassifier';
import {
  BrowserControllerAttachmentHost,
  BrowserControllerAttachmentOptions
} from '../../core/browser/BrowserRuntimeLifecycleCoordinator';
import {
  BrowserWebActiveSurfaceActionExecutor,
  BrowserWebActiveSurfaceCoordinator,
  BrowserWebActiveSurfaceVisualStateHost,
  WEB_ACTIVE_SURFACE_SCROLL_SOURCE_CONTROLLER_ATTACH
} from '../../core/browser/BrowserWebActiveSurfaceCoordinator';
import { BrowserWebActiveSurfacePlan } from '../../core/browser/BrowserWebEventCommitCoordinator';
import { BrowserWebTabsController } from '../../core/browser/BrowserWebTabsController';
import { BrowserTabRuntimePatch } from '../../core/tabs/TabManager';
import { WebControllerBootstrapConfig, WebControllerBootstrapper } from '../../core/web/WebControllerBootstrapper';
import { WebTabRuntimeRecord } from '../../core/web/WebTabRuntime';
import { BrowserHostedRuntimeSurfacePort } from './BrowserHostedRuntimeSurfacePort';
import {
  BrowserRuntimeControllerAttachedState,
  BrowserRuntimeLifecyclePort
} from './BrowserRuntimeLifecyclePort';
import {
  ArkWebSslDecisionCacheController,
  sharedBrowserSslDecisionCacheRuntime
} from './BrowserSslDecisionCacheRuntime';

export interface BrowserControllerAttachmentRuntimeCoordinatorHost {
  getActiveTabId: () => string;
  buildBootstrapConfig: () => WebControllerBootstrapConfig;
  applyBootstrapConfig: (config: WebControllerBootstrapConfig) => void;
  applyActiveController: (controller: webview.WebviewController) => void;
  applyUserAgent: (controller: webview.WebviewController, pageUrl: string) => void;
  finalizeControllerAttachment: () => void;
  recordRuntimeEvent: (type: string, message: string, tabId: string) => void;
  appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string) => void;
  recordLoadFailure: (tabId: string, message: string) => void;
  applyTabRuntimePatch: (tabId: string, patch: BrowserTabRuntimePatch) => void;
  setRestoreEventContext: (tabId: string, targetUrl: string) => void;
  releaseEventContext: (tabId: string) => void;
  restoreActiveSession: (reason: TabRestoreReason) => void;
}

export class BrowserControllerAttachmentRuntimeCoordinator {
  private readonly bootstrapper: WebControllerBootstrapper;
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  private readonly faultClassifier: BrowserFaultClassifier;
  private readonly activeSurfaceCoordinator: BrowserWebActiveSurfaceCoordinator;
  private readonly activeSurfaceExecutor: BrowserWebActiveSurfaceActionExecutor;
  private readonly activeSurfaceHost: BrowserWebActiveSurfaceVisualStateHost;
  private readonly webTabsController: BrowserWebTabsController;
  private readonly host: BrowserControllerAttachmentRuntimeCoordinatorHost;

  constructor(
    bootstrapper: WebControllerBootstrapper,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort,
    faultClassifier: BrowserFaultClassifier,
    activeSurfaceCoordinator: BrowserWebActiveSurfaceCoordinator,
    activeSurfaceExecutor: BrowserWebActiveSurfaceActionExecutor,
    activeSurfaceHost: BrowserWebActiveSurfaceVisualStateHost,
    webTabsController: BrowserWebTabsController,
    host: BrowserControllerAttachmentRuntimeCoordinatorHost
  ) {
    this.bootstrapper = bootstrapper;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.hostedRuntimeSurfacePort = hostedRuntimeSurfacePort;
    this.faultClassifier = faultClassifier;
    this.activeSurfaceCoordinator = activeSurfaceCoordinator;
    this.activeSurfaceExecutor = activeSurfaceExecutor;
    this.activeSurfaceHost = activeSurfaceHost;
    this.webTabsController = webTabsController;
    this.host = host;
  }

  markControllerAttached(tabId: string): WebTabRuntimeRecord | undefined {
    return this.runtimeLifecyclePort.markControllerAttached(tabId);
  }

  markControllerAttachedWithState(tabId: string, fallback: boolean): BrowserRuntimeControllerAttachedState {
    return this.runtimeLifecyclePort.markControllerAttachedWithState(tabId, fallback);
  }

  resolveLiveRuntimeControllerState(tabId: string, fallback: boolean): boolean {
    return this.runtimeLifecyclePort.resolveLiveRuntimeControllerState(tabId, fallback);
  }

  handleAttached(tabId: string, options: BrowserControllerAttachmentOptions = {}): void {
    this.runtimeLifecyclePort.handleAttached(tabId, this.buildControllerAttachmentHost(), options);
  }

  handleControllerAttachedSignal(tabId: string): void {
    const attachedController = this.runtimeLifecyclePort.resolveController(tabId);
    if (attachedController !== undefined) {
      sharedBrowserSslDecisionCacheRuntime.handleControllerAttached(
        new ArkWebSslDecisionCacheController(attachedController)
      );
    }
    const eventConsumption = this.webTabsController.onControllerAttached(tabId);
    this.handleAttached(tabId, {
      windowOpenEventConsumedByPageController: eventConsumption
    });
  }

  hasAttachedController(tabId: string, runtime?: WebTabRuntimeRecord): boolean {
    return this.runtimeLifecyclePort.resolveController(tabId, runtime) !== undefined &&
      this.hostedRuntimeSurfacePort.isHostedControllerAttached(tabId);
  }

  bootstrapAttachedController(tabId: string, runtime?: WebTabRuntimeRecord): void {
    const controller = this.runtimeLifecyclePort.resolveController(tabId, runtime);
    if (controller === undefined) {
      return;
    }
    const config = this.host.buildBootstrapConfig();
    this.host.applyBootstrapConfig(config);
    this.bootstrapper.bootstrapAttachedController(controller, config);
  }

  activateAttachedController(tabId: string, targetUrl: string, runtime?: WebTabRuntimeRecord): boolean {
    const controller = this.runtimeLifecyclePort.resolveController(tabId, runtime);
    if (controller === undefined) {
      return false;
    }
    this.host.applyActiveController(controller);
    this.host.applyUserAgent(controller, targetUrl);
    try {
      controller.onActive();
      return true;
    } catch (_error) {
      return false;
    }
  }

  recordRuntimeEvent(type: string, message: string, tabId: string): void {
    this.host.recordRuntimeEvent(type, message, tabId);
  }

  appendRestoreTraceBreadcrumb(tabId: string, breadcrumb: string): void {
    this.host.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
  }

  private applyAttachFailure(tabId: string, message: string, crashReason: TabCrashReason): void {
    const fault = this.faultClassifier.classifyAttachFailure(message);
    this.host.recordRuntimeEvent(fault.telemetryType, fault.userMessage, tabId);
    this.host.appendRestoreTraceBreadcrumb(tabId, fault.breadcrumb);
    this.host.recordLoadFailure(tabId, fault.userMessage);
    this.runtimeLifecyclePort.markTabCrashed(tabId, fault.userMessage, crashReason);
    this.host.applyTabRuntimePatch(tabId, {
      runtimeState: 'crashed',
      lastError: fault.userMessage,
      lastRestoreReason: 'controller_attach',
      lastCrashReason: crashReason
    });
    if (tabId !== this.host.getActiveTabId()) {
      return;
    }
    this.activeSurfaceCoordinator.applyLoadFailurePresentationWithHost(
      {
        plan: this.buildLoadFailurePlan()
      },
      fault.userMessage,
      'Web 控制器附着失败，可以点“重试恢复”重新接管页面。',
      this.activeSurfaceExecutor,
      this.activeSurfaceHost,
      {
        tabId: tabId,
        scrollSource: WEB_ACTIVE_SURFACE_SCROLL_SOURCE_CONTROLLER_ATTACH
      }
    );
  }

  private buildControllerAttachmentHost(): BrowserControllerAttachmentHost {
    return {
      hasAttachedController: (tabId: string, runtime?: WebTabRuntimeRecord): boolean => {
        return this.hasAttachedController(tabId, runtime);
      },
      applyAttachFailure: (tabId: string, message: string, crashReason: TabCrashReason): void => {
        this.applyAttachFailure(tabId, message, crashReason);
      },
      bootstrapAttachedController: (tabId: string, runtime?: WebTabRuntimeRecord): void => {
        this.bootstrapAttachedController(tabId, runtime);
      },
      recordRuntimeEvent: (type: string, message: string, tabId: string): void => {
        this.host.recordRuntimeEvent(type, message, tabId);
      },
      appendRestoreTraceBreadcrumb: (tabId: string, breadcrumb: string): void => {
        this.host.appendRestoreTraceBreadcrumb(tabId, breadcrumb);
      },
      activateAttachedController: (
        tabId: string,
        targetUrl: string,
        runtime?: WebTabRuntimeRecord
      ): boolean => {
        return this.activateAttachedController(tabId, targetUrl, runtime);
      },
      setRestoreEventContext: (tabId: string, targetUrl: string): void => {
        this.host.setRestoreEventContext(tabId, targetUrl);
      },
      releaseEventContext: (tabId: string): void => {
        this.host.releaseEventContext(tabId);
      },
      restoreActiveSession: (reason: TabRestoreReason): void => {
        this.host.restoreActiveSession(reason);
      },
      finalizeControllerAttachment: (): void => {
        this.host.finalizeControllerAttachment();
      }
    };
  }

  private buildLoadFailurePlan(): BrowserWebActiveSurfacePlan {
    return {
      shouldApplyVisualState: true,
      shouldRefreshPermissions: false,
      certificateAction: 'none',
      shouldRefreshTracking: false,
      shouldSyncNavigationState: false,
      shouldPersistActiveSnapshot: false,
      snapshotReason: ''
    };
  }
}
