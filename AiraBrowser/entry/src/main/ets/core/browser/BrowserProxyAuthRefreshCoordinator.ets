import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { BrowserHostedRuntimeSurfacePort } from '../../services/web/BrowserHostedRuntimeSurfacePort';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserRuntimeRefreshStateSink } from './BrowserRuntimeRefreshStateSink';

export interface BrowserProxyRuntimeRefreshRequest {
  settings: BrowserExperimentSettings;
  activeTab?: BrowserTabState;
  showHomePage: boolean;
}

export interface BrowserProxyRuntimeRefreshHost {
  resetProxyCredentialAttempts: () => void;
}

export class BrowserProxyAuthRefreshCoordinator {
  private readonly hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort;
  private readonly runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private readonly runtimeRefreshStateSink: BrowserRuntimeRefreshStateSink;
  private lastSignature: string = '';

  constructor(
    hostedRuntimeSurfacePort: BrowserHostedRuntimeSurfacePort,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    runtimeRefreshStateSink: BrowserRuntimeRefreshStateSink
  ) {
    this.hostedRuntimeSurfacePort = hostedRuntimeSurfacePort;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.runtimeRefreshStateSink = runtimeRefreshStateSink;
  }

  remember(settings: BrowserExperimentSettings): void {
    this.lastSignature = this.buildSignature(settings);
  }

  shouldRebuildHostedWebNode(settings: BrowserExperimentSettings): boolean {
    const nextSignature = this.buildSignature(settings);
    if (this.lastSignature.length <= 0) {
      this.lastSignature = nextSignature;
      return false;
    }
    if (this.lastSignature === nextSignature) {
      return false;
    }
    this.lastSignature = nextSignature;
    return true;
  }

  handleSettingsRefresh(
    request: BrowserProxyRuntimeRefreshRequest,
    host: BrowserProxyRuntimeRefreshHost
  ): void {
    if (!this.shouldRebuildHostedWebNode(request.settings)) {
      return;
    }
    if (!this.hasUsableProxy(request.settings)) {
      return;
    }
    const activeTab = request.activeTab;
    if (activeTab === undefined) {
      return;
    }
    if (activeTab.isHome) {
      return;
    }
    if (request.showHomePage) {
      return;
    }
    host.resetProxyCredentialAttempts();
    this.hostedRuntimeSurfacePort.release(activeTab.id, 'context_switch');
    this.replaceActiveController(host, activeTab);
  }

  handlePendingRuntimeRefresh(
    request: BrowserProxyRuntimeRefreshRequest,
    host: BrowserProxyRuntimeRefreshHost
  ): void {
    host.resetProxyCredentialAttempts();
    this.releaseAllHostedRuntimes('proxy_settings_changed');
    const activeTab = request.activeTab;
    if (activeTab === undefined || activeTab.isHome || request.showHomePage) {
      return;
    }
    this.replaceActiveController(host, activeTab);
  }

  private replaceActiveController(
    host: BrowserProxyRuntimeRefreshHost,
    activeTab: BrowserTabState
  ): void {
    const runtime = this.runtimeLifecyclePort.replaceControllerForRuntimeRefresh(activeTab.id);
    if (runtime === undefined) {
      return;
    }
    this.runtimeRefreshStateSink.applyReplacementRuntimeState(runtime);
    this.hostedRuntimeSurfacePort.syncActiveFromHost(activeTab, runtime);
  }

  private releaseAllHostedRuntimes(reason: 'proxy_settings_changed'): void {
    this.hostedRuntimeSurfacePort.releaseAll(reason);
  }

  private buildSignature(settings: BrowserExperimentSettings): string {
    return [
      settings.appProxyEnabled ? '1' : '0',
      settings.appProxy.scheme,
      settings.appProxy.host.trim(),
      String(settings.appProxy.port),
      settings.appProxy.bypassHosts.trim()
    ].join('|');
  }

  private hasUsableProxy(settings: BrowserExperimentSettings): boolean {
    return settings.appProxyEnabled && settings.appProxy.host.trim().length > 0 && settings.appProxy.port > 0;
  }
}
