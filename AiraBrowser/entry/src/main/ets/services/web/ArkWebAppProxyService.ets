import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserAppProxyScheme,
  BrowserExperimentSettings
} from '../../common/models/BrowserModels';
import { AppProxyHostResolutionService, sharedAppProxyHostResolutionService } from './AppProxyHostResolutionService';

const DOMAIN = 0x0000;
const TAG = 'ArkWebAppProxy';
const PROXY_REAPPLY_SETTLE_DELAY_MS = 180;

export type ArkWebAppProxyApplyStatus =
  'applied' |
  'removed' |
  'skipped_invalid' |
  'failed';

export interface ArkWebAppProxyApplyResult {
  status: ArkWebAppProxyApplyStatus;
  message: string;
  proxyRule: string;
}

export class ArkWebAppProxyService {
  private pendingTask: Promise<ArkWebAppProxyApplyResult> = Promise.resolve(this.buildRemovedResult());
  private lastSignature: string = '';
  private lastProxyRule: string = '';
  private hostResolutionService: AppProxyHostResolutionService;

  constructor(hostResolutionService: AppProxyHostResolutionService = sharedAppProxyHostResolutionService) {
    this.hostResolutionService = hostResolutionService;
  }

  applyFromExperimentSettings(settings: BrowserExperimentSettings): Promise<ArkWebAppProxyApplyResult> {
    return this.enqueueApplyFromExperimentSettings(settings, false, 'settings');
  }

  forceApplyFromExperimentSettings(settings: BrowserExperimentSettings): Promise<ArkWebAppProxyApplyResult> {
    return this.enqueueApplyFromExperimentSettings(settings, true, 'foreground');
  }

  private enqueueApplyFromExperimentSettings(
    settings: BrowserExperimentSettings,
    forceReapply: boolean,
    source: string
  ): Promise<ArkWebAppProxyApplyResult> {
    const snapshot = this.buildSnapshot(settings);
    hilog.info(
      DOMAIN,
      TAG,
      'proxy apply requested source=%{public}s force=%{public}s enabled=%{public}s rule=%{public}s user=%{public}s updatedAt=%{public}s signature=%{public}s lastSignature=%{public}s',
      source,
      forceReapply ? '1' : '0',
      snapshot.appProxyEnabled ? '1' : '0',
      this.buildProxyRule(snapshot),
      this.maskText(snapshot.appProxy.username),
      String(snapshot.appProxy.updatedAt),
      this.buildSignature(snapshot),
      this.lastSignature
    );
    this.pendingTask = this.pendingTask
      .catch((_error: Error) => this.buildRemovedResult())
      .then(() => this.applySnapshot(snapshot, forceReapply));
    return this.pendingTask;
  }

  buildProxyRule(settings: BrowserExperimentSettings): string {
    const host = settings.appProxy.host.trim();
    const port = settings.appProxy.port;
    if (!settings.appProxyEnabled || host.length === 0 || port <= 0) {
      return '';
    }
    return `${this.normalizeProxyScheme(settings.appProxy.scheme)}://${host}:${port}`;
  }

  private applySnapshot(
    snapshot: BrowserExperimentSettings,
    forceReapply: boolean
  ): Promise<ArkWebAppProxyApplyResult> {
    const signature = this.buildSignature(snapshot);
    if (signature === this.lastSignature && !forceReapply) {
      hilog.info(DOMAIN, TAG, 'proxy apply skipped noop signature=%{public}s', signature);
      return Promise.resolve(this.buildNoopResult(snapshot));
    }

    if (signature !== this.lastSignature) {
      this.deleteHttpAuthCredentials(signature);
    }

    if (!snapshot.appProxyEnabled) {
      return this.removeProxyOverride(signature);
    }

    const proxyRule = this.buildProxyRule(snapshot);
    if (proxyRule.length === 0) {
      return this.removeProxyOverride(signature)
        .then(() => this.buildSkippedInvalidResult());
    }

    this.hostResolutionService.refresh(snapshot.appProxy.host);

    if (this.lastProxyRule.length > 0) {
      hilog.info(
        DOMAIN,
        TAG,
        'proxy force remove before reapply previousRule=%{public}s nextRule=%{public}s nextSignature=%{public}s',
        this.lastProxyRule,
        proxyRule,
        signature
      );
      return this.removeProxyOverride('')
        .then(() => this.waitForProxyOverrideSettle())
        .then(() => this.applyProxyOverride(snapshot, signature, proxyRule));
    }

    return this.applyProxyOverride(snapshot, signature, proxyRule);
  }

  private applyProxyOverride(
    snapshot: BrowserExperimentSettings,
    signature: string,
    proxyRule: string
  ): Promise<ArkWebAppProxyApplyResult> {
    try {
      const proxyConfig = new webview.ProxyConfig();
      proxyConfig.insertProxyRule(proxyRule, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
      this.insertBypassRules(proxyConfig, snapshot.appProxy.bypassHosts);
      return new Promise<ArkWebAppProxyApplyResult>((resolve: (result: ArkWebAppProxyApplyResult) => void) => {
        webview.ProxyController.applyProxyOverride(proxyConfig, () => {
          this.lastSignature = signature;
          this.lastProxyRule = proxyRule;
          hilog.info(
            DOMAIN,
            TAG,
            'ArkWeb proxy applied rule=%{public}s signature=%{public}s user=%{public}s updatedAt=%{public}s',
            proxyRule,
            signature,
            this.maskText(snapshot.appProxy.username),
            String(snapshot.appProxy.updatedAt)
          );
          resolve(this.buildAppliedResult(proxyRule));
        });
      });
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to apply ArkWeb proxy: code=%{public}s message=%{public}s',
        String(businessError.code),
        businessError.message
      );
      return Promise.resolve(this.buildFailedResult('ArkWeb 代理应用失败。', proxyRule));
    }
  }

  private removeProxyOverride(signature: string): Promise<ArkWebAppProxyApplyResult> {
    try {
      return new Promise<ArkWebAppProxyApplyResult>((resolve: (result: ArkWebAppProxyApplyResult) => void) => {
        webview.ProxyController.removeProxyOverride(() => {
          this.lastSignature = signature;
          this.lastProxyRule = '';
          hilog.info(DOMAIN, TAG, 'ArkWeb proxy removed nextSignature=%{public}s', signature);
          resolve(this.buildRemovedResult());
        });
      });
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to remove ArkWeb proxy: code=%{public}s message=%{public}s',
        String(businessError.code),
        businessError.message
      );
      return Promise.resolve(this.buildFailedResult('ArkWeb 代理移除失败。', ''));
    }
  }

  private insertBypassRules(proxyConfig: webview.ProxyConfig, bypassHosts: string): void {
    const rules = bypassHosts.split(',');
    rules.forEach((rawRule: string) => {
      const rule = rawRule.trim();
      if (rule.length > 0) {
        proxyConfig.insertBypassRule(rule);
      }
    });
    proxyConfig.bypassHostnamesWithoutPeriod();
  }

  private waitForProxyOverrideSettle(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), PROXY_REAPPLY_SETTLE_DELAY_MS);
    });
  }

  private deleteHttpAuthCredentials(signature: string): void {
    try {
      const hadCredentials = webview.WebDataBase.existHttpAuthCredentials();
      webview.WebDataBase.deleteHttpAuthCredentials();
      hilog.info(
        DOMAIN,
        TAG,
        'ArkWeb http auth credentials cleared hadCredentials=%{public}s signature=%{public}s',
        hadCredentials ? '1' : '0',
        signature
      );
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        DOMAIN,
        TAG,
        'Failed to clear ArkWeb http auth credentials: code=%{public}s message=%{public}s signature=%{public}s',
        String(businessError.code),
        businessError.message,
        signature
      );
    }
  }

  private buildSnapshot(settings: BrowserExperimentSettings): BrowserExperimentSettings {
    return {
      pauseWebAnimationsDuringScroll: settings.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: settings.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: settings.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: settings.pullRefreshEnabled,
      forceEnableWebZoom: settings.forceEnableWebZoom,
      smartGripTabsActionsEnabled: settings.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: settings.webVideoTakeoverEnabled,
      novelModeEnabled: settings.novelModeEnabled,
      novelAutoTakeoverEnabled: settings.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: settings.appProxyActiveProfileId,
      appProxyProfiles: settings.appProxyProfiles,
      appProxyEnabled: settings.appProxyEnabled,
      appProxy: {
        scheme: settings.appProxy.scheme,
        host: settings.appProxy.host,
        port: settings.appProxy.port,
        username: settings.appProxy.username,
        password: settings.appProxy.password,
        bypassHosts: settings.appProxy.bypassHosts,
        updatedAt: settings.appProxy.updatedAt
      }
    };
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

  private buildNoopResult(settings: BrowserExperimentSettings): ArkWebAppProxyApplyResult {
    const proxyRule = this.buildProxyRule(settings);
    if (settings.appProxyEnabled && proxyRule.length > 0) {
      return this.buildAppliedResult(proxyRule);
    }
    return this.buildRemovedResult();
  }

  private buildAppliedResult(proxyRule: string): ArkWebAppProxyApplyResult {
    return {
      status: 'applied',
      message: `ArkWeb 请求已接入代理：${proxyRule}`,
      proxyRule: proxyRule
    };
  }

  private buildRemovedResult(): ArkWebAppProxyApplyResult {
    return {
      status: 'removed',
      message: 'ArkWeb 代理已关闭。',
      proxyRule: ''
    };
  }

  private buildSkippedInvalidResult(): ArkWebAppProxyApplyResult {
    return {
      status: 'skipped_invalid',
      message: '代理配置不完整，已移除 ArkWeb 代理。',
      proxyRule: ''
    };
  }

  private buildFailedResult(message: string, proxyRule: string): ArkWebAppProxyApplyResult {
    return {
      status: 'failed',
      message: message,
      proxyRule: proxyRule
    };
  }

  private normalizeProxyScheme(scheme: BrowserAppProxyScheme): string {
    if (scheme === 'socks5') {
      return 'socks';
    }
    if (scheme === 'https') {
      return 'https';
    }
    return 'http';
  }

  private maskText(value: string): string {
    const normalized = value.trim();
    if (normalized.length <= 0) {
      return 'empty';
    }
    return `${normalized.substring(0, 1)}***(${normalized.length})`;
  }
}
