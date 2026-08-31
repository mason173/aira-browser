import {
  BrowserAppProxyProfile,
  BrowserAppProxySettings,
  BrowserExperimentSettings
} from '../../common/models/BrowserModels';
import {
  AppProxyHostResolutionService,
  sharedAppProxyHostResolutionService
} from '../web/AppProxyHostResolutionService';

export interface HttpAuthCredentialPolicy {
  persistCredential: boolean;
  summary: string;
}

export interface HttpAuthCredentialDecision {
  shouldAutoConfirm: boolean;
  username: string;
  password: string;
  isProxyAuthentication: boolean;
}

export class HttpAuthCredentialPolicyService {
  private attemptedProxyAuthSignatures: string[] = [];
  private hostResolutionService: AppProxyHostResolutionService;

  constructor(hostResolutionService: AppProxyHostResolutionService = sharedAppProxyHostResolutionService) {
    this.hostResolutionService = hostResolutionService;
  }

  resetProxyCredentialAttempts(): void {
    this.attemptedProxyAuthSignatures = [];
  }

  resolvePolicy(): HttpAuthCredentialPolicy {
    return {
      persistCredential: false,
      summary: 'HTTP Auth 凭据仅用于本次认证请求；应用代理凭据会优先用于匹配的代理认证。'
    };
  }

  resolveProxyCredentialDecision(
    requestHostValue: string,
    requestRealm: string,
    settings: BrowserExperimentSettings
  ): HttpAuthCredentialDecision {
    if (!settings.appProxyEnabled || settings.appProxy.port <= 0) {
      return this.buildManualDecision();
    }

    if (!this.hostResolutionService.matchesConfiguredProxyHost(requestHostValue, settings.appProxy.host)) {
      return this.buildManualDecision();
    }

    const username = this.sanitizeCredentialText(settings.appProxy.username);
    const password = settings.appProxy.password;
    if (username.length === 0 || password.length === 0) {
      return {
        shouldAutoConfirm: false,
        username: username,
        password: '',
        isProxyAuthentication: true
      };
    }

    const signature = this.buildProxyAuthSignature(requestHostValue, requestRealm, settings);
    if (this.attemptedProxyAuthSignatures.includes(signature)) {
      return {
        shouldAutoConfirm: false,
        username: username,
        password: '',
        isProxyAuthentication: true
      };
    }

    this.rememberProxyAuthSignature(signature);
    return {
      shouldAutoConfirm: true,
      username: username,
      password: password,
      isProxyAuthentication: true
    };
  }

  sanitizeCredentialText(value: string): string {
    return value.trim();
  }

  buildSettingsWithConfirmedProxyCredential(
    requestHostValue: string,
    current: BrowserExperimentSettings,
    username: string,
    password: string,
    now: number = Date.now()
  ): BrowserExperimentSettings | undefined {
    const sanitizedUsername = this.sanitizeCredentialText(username);
    if (!current.appProxyEnabled ||
      current.appProxy.port <= 0 ||
      sanitizedUsername.length <= 0 ||
      password.length <= 0 ||
      !this.hostResolutionService.matchesConfiguredProxyHost(requestHostValue, current.appProxy.host)) {
      return undefined;
    }
    const nextProxy = this.buildProxySettingsWithCredential(
      current.appProxy,
      sanitizedUsername,
      password,
      now
    );
    const targetProfile = this.resolveActiveProxyProfile(current);
    if (targetProfile === undefined) {
      return {
        pauseWebAnimationsDuringScroll: current.pauseWebAnimationsDuringScroll,
        reduceMediaMotionDuringScroll: current.reduceMediaMotionDuringScroll,
        strengthenAdBlockingForSmoothScroll: current.strengthenAdBlockingForSmoothScroll,
        pullRefreshEnabled: current.pullRefreshEnabled,
        forceEnableWebZoom: current.forceEnableWebZoom,
        smartGripTabsActionsEnabled: current.smartGripTabsActionsEnabled,
        webVideoTakeoverEnabled: current.webVideoTakeoverEnabled,
        novelModeEnabled: current.novelModeEnabled,
        novelAutoTakeoverEnabled: current.novelAutoTakeoverEnabled,
        appProxyActiveProfileId: current.appProxyActiveProfileId,
        appProxyProfiles: current.appProxyProfiles,
        appProxyEnabled: current.appProxyEnabled,
        appProxy: nextProxy
      };
    }
    const nextProfiles = current.appProxyProfiles.map((profile: BrowserAppProxyProfile): BrowserAppProxyProfile => {
      if (profile.id !== targetProfile.id) {
        return profile;
      }
      return {
        id: profile.id,
        name: profile.name,
        settings: nextProxy,
        createdAt: profile.createdAt,
        updatedAt: now
      };
    });
    return {
      pauseWebAnimationsDuringScroll: current.pauseWebAnimationsDuringScroll,
      reduceMediaMotionDuringScroll: current.reduceMediaMotionDuringScroll,
      strengthenAdBlockingForSmoothScroll: current.strengthenAdBlockingForSmoothScroll,
      pullRefreshEnabled: current.pullRefreshEnabled,
      forceEnableWebZoom: current.forceEnableWebZoom,
      smartGripTabsActionsEnabled: current.smartGripTabsActionsEnabled,
      webVideoTakeoverEnabled: current.webVideoTakeoverEnabled,
      novelModeEnabled: current.novelModeEnabled,
      novelAutoTakeoverEnabled: current.novelAutoTakeoverEnabled,
      appProxyActiveProfileId: targetProfile.id,
      appProxyProfiles: nextProfiles,
      appProxyEnabled: current.appProxyEnabled,
      appProxy: nextProxy
    };
  }

  private buildManualDecision(): HttpAuthCredentialDecision {
    return {
      shouldAutoConfirm: false,
      username: '',
      password: '',
      isProxyAuthentication: false
    };
  }

  private resolveActiveProxyProfile(settings: BrowserExperimentSettings): BrowserAppProxyProfile | undefined {
    for (let index = 0; index < settings.appProxyProfiles.length; index += 1) {
      const profile = settings.appProxyProfiles[index];
      if (profile.id === settings.appProxyActiveProfileId) {
        return profile;
      }
    }
    return settings.appProxyProfiles[0];
  }

  private buildProxySettingsWithCredential(
    settings: BrowserAppProxySettings,
    username: string,
    password: string,
    updatedAt: number
  ): BrowserAppProxySettings {
    return {
      scheme: settings.scheme,
      host: settings.host,
      port: settings.port,
      username: username,
      password: password,
      bypassHosts: settings.bypassHosts,
      updatedAt: updatedAt
    };
  }

  private buildProxyAuthSignature(
    requestHostValue: string,
    requestRealm: string,
    settings: BrowserExperimentSettings
  ): string {
    return [
      this.hostResolutionService.normalizeComparableHost(requestHostValue),
      requestRealm.trim(),
      this.hostResolutionService.normalizeComparableHost(settings.appProxy.host),
      String(settings.appProxy.port),
      settings.appProxy.username.trim(),
      String(settings.appProxy.updatedAt)
    ].join('|');
  }

  private rememberProxyAuthSignature(signature: string): void {
    this.attemptedProxyAuthSignatures.push(signature);
    if (this.attemptedProxyAuthSignatures.length > 12) {
      this.attemptedProxyAuthSignatures.shift();
    }
  }
}
