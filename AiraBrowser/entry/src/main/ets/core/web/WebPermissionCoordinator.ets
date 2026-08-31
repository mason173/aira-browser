import { common } from '@kit.AbilityKit';
import {
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings
} from '../../common/models/BrowserModels';
import {
  BrowserFaultClassifier,
  BrowserFaultDescriptor
} from '../browser/BrowserFaultClassifier';
import { BrowserSiteControlsRuntimeCoordinator } from '../browser/BrowserSiteControlsRuntimeCoordinator';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserTabScopedEventContextCoordinator } from '../browser/BrowserTabScopedEventContextCoordinator';
import {
  PendingGeolocationPermissionRequest,
  PendingSitePermissionPromptState,
  PendingWebPermissionPromptItem,
  PendingWebPermissionRequest
} from '../browser/BrowserShellRuntimeContracts';
import { SystemSettingsLaunchService } from '../../services/system/SystemSettingsLaunchService';
import { SystemPermissionGrantResult } from '../../services/system/SystemPermissionService';
import { PermissionPolicyService } from '../../services/web/PermissionPolicyService';
import { SiteInteractionLogicService } from '../../services/web/SiteInteractionLogicService';
import { SitePolicyService } from '../../services/web/SitePolicyService';

type WebPermissionCoordinatorMessageKind = 'helper' | 'error' | 'toast';

interface WebPermissionPromptPresentation {
  title: string;
  message: string;
}

interface WebPermissionMessageEffect {
  type: 'message';
  kind: WebPermissionCoordinatorMessageKind;
  message: string;
}

interface WebPermissionSitePromptEffect {
  type: 'open_site_permission_prompt';
  tabId: string;
  presentation: WebPermissionPromptPresentation;
}

interface WebPermissionSystemSettingPromptEffect {
  type: 'open_system_permission_setting_prompt';
  tabId: string;
  title: string;
  message: string;
}

interface WebPermissionFlowStateEffect {
  type: 'permission_flow_state';
  tabId: string;
  active: boolean;
}

export type WebPermissionCoordinatorEffect =
  WebPermissionMessageEffect |
  WebPermissionSitePromptEffect |
  WebPermissionSystemSettingPromptEffect |
  WebPermissionFlowStateEffect;

interface WebPermissionCoordinatorSink {
  resolveAbilityContext: () => common.UIAbilityContext;
  resolveCurrentSiteOrigin: () => string;
  applyEffect: (effect: WebPermissionCoordinatorEffect) => void;
}

export interface WebPermissionCoordinatorOptions {
  sitePolicyService: SitePolicyService;
  browserFaultClassifier: BrowserFaultClassifier;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  siteInteractionLogicService: SiteInteractionLogicService;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  systemSettingsLaunchService: SystemSettingsLaunchService;
  sink: WebPermissionCoordinatorSink;
}

export class WebPermissionCoordinator {
  private readonly permissionPolicyService: PermissionPolicyService;
  private readonly sitePolicyService: SitePolicyService;
  private readonly browserFaultClassifier: BrowserFaultClassifier;
  private readonly tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  private readonly siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  private readonly siteInteractionLogicService: SiteInteractionLogicService;
  private readonly backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  private readonly systemSettingsLaunchService: SystemSettingsLaunchService;
  private readonly sink: WebPermissionCoordinatorSink;
  private pendingPrompt?: PendingSitePermissionPromptState;
  private permissionFlowInFlight: boolean = false;
  private pendingSystemPermissionSettingKinds: SitePermissionKind[] = [];

  constructor(options: WebPermissionCoordinatorOptions) {
    this.permissionPolicyService = new PermissionPolicyService(options.sitePolicyService);
    this.sitePolicyService = options.sitePolicyService;
    this.browserFaultClassifier = options.browserFaultClassifier;
    this.tabScopedEventContextCoordinator = options.tabScopedEventContextCoordinator;
    this.siteControlsRuntimeCoordinator = options.siteControlsRuntimeCoordinator;
    this.siteInteractionLogicService = options.siteInteractionLogicService;
    this.backgroundSessionSyncCoordinator = options.backgroundSessionSyncCoordinator;
    this.systemSettingsLaunchService = options.systemSettingsLaunchService;
    this.sink = options.sink;
  }

  hasPendingPrompt(): boolean {
    return this.pendingPrompt !== undefined;
  }

  handleProtectedResourcePermissionRequest(tabId: string, request: PermissionRequest): void {
    if (this.permissionFlowInFlight) {
      request.deny();
      return;
    }
    let origin = '';
    let resources: string[] = [];
    try {
      origin = request.getOrigin();
      resources = request.getAccessibleResource();
    } catch (_error) {
      request.deny();
      return;
    }

    this.beginProtectedResourcePermissionFlow(tabId, origin, resources, request);
  }

  handleGeolocationPermissionRequest(tabId: string, event: OnGeolocationShowEvent): void {
    if (this.permissionFlowInFlight) {
      event.geolocation.invoke(event.origin, false, false);
      return;
    }
    const decision = this.permissionPolicyService.resolveGeolocationDecision(
      event.origin,
      this.tabScopedEventContextCoordinator.resolveProfileId(tabId),
      this.tabScopedEventContextCoordinator.resolveDataScope(tabId)
    );
    if (decision.action === 'deny') {
      event.geolocation.invoke(event.origin, false, false);
      return;
    }

    this.rememberPermissionOrigin(decision.origin);
    if (decision.action === 'block') {
      event.geolocation.invoke(event.origin, false, false);
      return;
    }

    const pendingRequest: PendingGeolocationPermissionRequest = {
      tabId: tabId,
      origin: decision.origin,
      geolocation: event.geolocation
    };
    this.setPermissionFlowInFlight(pendingRequest.tabId, true);
    this.backgroundSessionSyncCoordinator.protect(
      pendingRequest.tabId,
      '站点权限流程等待网站或系统权限决策，暂不回收 runtime。'
    );
    if (decision.action === 'allow') {
      this.grantGeolocationPermission(pendingRequest);
      return;
    }
    this.showGeolocationPermissionDialog(pendingRequest);
  }

  async allowPendingPermissionForSession(): Promise<boolean> {
    const prompt = this.consumePendingPrompt();
    if (prompt === undefined) {
      return false;
    }
    if (prompt.type === 'protected_resource' && prompt.protectedResourceRequest !== undefined) {
      const item = this.getCurrentProtectedResourcePromptItem(prompt.protectedResourceRequest);
      if (item === undefined) {
        this.denyProtectedResourceFlow(prompt.protectedResourceRequest);
        return false;
      }
      this.rememberAllowedForSession(prompt.protectedResourceRequest.tabId, prompt.protectedResourceRequest.origin,
        [item.kind]);
      return this.advanceProtectedResourcePermissionFlow(prompt.protectedResourceRequest);
    }
    if (prompt.geolocationRequest !== undefined) {
      this.rememberAllowedForSession(prompt.geolocationRequest.tabId, prompt.geolocationRequest.origin, ['location']);
      this.grantGeolocationPermission(prompt.geolocationRequest);
    }
    return false;
  }

  async allowPendingPermissionDuringUse(): Promise<boolean> {
    const prompt = this.consumePendingPrompt();
    if (prompt === undefined) {
      return false;
    }
    if (prompt.type === 'protected_resource' && prompt.protectedResourceRequest !== undefined) {
      return this.persistThenAdvanceProtectedResourcePermission(prompt.protectedResourceRequest);
    }
    if (prompt.geolocationRequest !== undefined) {
      await this.persistThenGrantGeolocationPermission(prompt.geolocationRequest);
    }
    return false;
  }

  async denyPendingPermission(): Promise<boolean> {
    const prompt = this.consumePendingPrompt();
    if (prompt === undefined) {
      return false;
    }
    if (prompt.type === 'protected_resource' && prompt.protectedResourceRequest !== undefined) {
      const request = prompt.protectedResourceRequest;
      const item = this.getCurrentProtectedResourcePromptItem(request);
      request.request.deny();
      if (item === undefined) {
        this.backgroundSessionSyncCoordinator.release(request.tabId);
        this.setPermissionFlowInFlight(request.tabId, false);
        return false;
      }
      try {
        await this.persistPermissionRulesForTab(request.tabId, request.origin, [item.kind], 'block');
      } catch (error) {
        this.emitMessage('error', `权限保存失败：${JSON.stringify(error)}`);
      } finally {
        this.backgroundSessionSyncCoordinator.release(request.tabId);
        this.setPermissionFlowInFlight(request.tabId, false);
      }
      return false;
    }
    if (prompt.geolocationRequest !== undefined) {
      const request = prompt.geolocationRequest;
      request.geolocation.invoke(request.origin, false, false);
      try {
        await this.persistPermissionRulesForTab(request.tabId, request.origin, ['location'], 'block');
      } catch (error) {
        this.emitMessage('error', `权限保存失败：${JSON.stringify(error)}`);
      } finally {
        this.backgroundSessionSyncCoordinator.release(request.tabId);
        this.setPermissionFlowInFlight(request.tabId, false);
      }
    }
    return false;
  }

  dismissPendingPermissionPrompt(): void {
    const prompt = this.consumePendingPrompt();
    if (prompt === undefined) {
      return;
    }
    if (prompt.type === 'protected_resource' && prompt.protectedResourceRequest !== undefined) {
      this.backgroundSessionSyncCoordinator.release(prompt.protectedResourceRequest.tabId);
      this.setPermissionFlowInFlight(prompt.protectedResourceRequest.tabId, false);
      prompt.protectedResourceRequest.request.deny();
      return;
    }
    if (prompt.geolocationRequest !== undefined) {
      this.backgroundSessionSyncCoordinator.release(prompt.geolocationRequest.tabId);
      this.setPermissionFlowInFlight(prompt.geolocationRequest.tabId, false);
      prompt.geolocationRequest.geolocation.invoke(prompt.geolocationRequest.origin, false, false);
    }
  }

  requestPendingSystemPermissionSettings(): void {
    const kinds = this.pendingSystemPermissionSettingKinds.slice();
    this.pendingSystemPermissionSettingKinds = [];
    if (kinds.length === 0) {
      return;
    }
    this.requestAppPermissionSettingsForKinds(kinds)
      .then((granted: boolean) => {
        if (granted) {
          this.emitMessage('toast', '系统权限已开启，请重新发起网页请求。');
          return;
        }
        this.emitMessage('toast', '系统权限仍未完全开启，请在系统设置中检查。');
        void this.openSystemSettingsFallback();
      })
      .catch((error: Error) => {
        this.emitMessage('error', `打开系统权限设置失败：${JSON.stringify(error)}`);
        this.emitMessage('toast', '无法直接打开权限设置，请在系统设置中手动开启。');
        void this.openSystemSettingsFallback();
      });
  }

  private beginProtectedResourcePermissionFlow(
    tabId: string,
    origin: string,
    resources: string[],
    request: PermissionRequest
  ): void {
    const profileId = this.tabScopedEventContextCoordinator.resolveProfileId(tabId);
    const dataScope = this.tabScopedEventContextCoordinator.resolveDataScope(tabId);
    const supportedResources: string[] = [];
    const kinds: SitePermissionKind[] = [];
    const promptItems: PendingWebPermissionPromptItem[] = [];
    let normalizedOrigin = '';
    for (let index = 0; index < resources.length; index += 1) {
      const resource = resources[index];
      const decision = this.permissionPolicyService.resolveProtectedResourceDecision(
        origin,
        [resource],
        profileId,
        dataScope
      );
      if (decision.action === 'deny' || decision.action === 'block' || decision.kinds.length !== 1 ||
        decision.resources.length !== 1) {
        request.deny();
        return;
      }
      normalizedOrigin = decision.origin;
      supportedResources.push(decision.resources[0]);
      const kind = decision.kinds[0];
      if (!kinds.includes(kind)) {
        kinds.push(kind);
      }
      if (decision.action === 'prompt' && !promptItems.some((item: PendingWebPermissionPromptItem) => {
        return item.kind === kind;
      })) {
        promptItems.push({
          resource: decision.resources[0],
          kind: kind
        });
      }
    }
    if (normalizedOrigin.length === 0 || supportedResources.length !== resources.length || kinds.length === 0) {
      request.deny();
      return;
    }
    this.rememberPermissionOrigin(normalizedOrigin);
    const pendingRequest: PendingWebPermissionRequest = {
      tabId: tabId,
      origin: normalizedOrigin,
      resources: supportedResources,
      kinds: kinds,
      promptItems: promptItems,
      currentPromptIndex: 0,
      request: request
    };
    this.setPermissionFlowInFlight(pendingRequest.tabId, true);
    this.backgroundSessionSyncCoordinator.protect(
      pendingRequest.tabId,
      '站点权限流程等待网站或系统权限决策，暂不回收 runtime。'
    );
    if (promptItems.length === 0) {
      this.grantProtectedResourcePermission(pendingRequest);
      return;
    }
    this.showProtectedResourcePermissionDialog(pendingRequest);
  }

  private showProtectedResourcePermissionDialog(pendingRequest: PendingWebPermissionRequest): void {
    const item = this.getCurrentProtectedResourcePromptItem(pendingRequest);
    if (item === undefined) {
      this.denyProtectedResourceFlow(pendingRequest);
      return;
    }
    this.presentPrompt({
      type: 'protected_resource',
      protectedResourceRequest: pendingRequest
    }, '站点权限请求',
      `${this.siteInteractionLogicService.getDisplayOrigin(pendingRequest.origin)} 想使用` +
        `${this.getKindsLabel([item.kind])}。`);
  }

  private showGeolocationPermissionDialog(pendingRequest: PendingGeolocationPermissionRequest): void {
    this.presentPrompt({
      type: 'geolocation',
      geolocationRequest: pendingRequest
    }, '位置权限请求',
      `${this.siteInteractionLogicService.getDisplayOrigin(pendingRequest.origin)} 想获取你的位置信息。`);
  }

  private presentPrompt(
    prompt: PendingSitePermissionPromptState,
    title: string,
    message: string
  ): void {
    this.pendingPrompt = prompt;
    this.sink.applyEffect({
      type: 'open_site_permission_prompt',
      tabId: this.resolvePromptTabId(prompt),
      presentation: {
        title: title,
        message: message
      }
    });
  }

  private resolvePromptTabId(prompt: PendingSitePermissionPromptState): string {
    if (prompt.protectedResourceRequest !== undefined) {
      return prompt.protectedResourceRequest.tabId;
    }
    return prompt.geolocationRequest?.tabId ?? '';
  }

  private consumePendingPrompt(): PendingSitePermissionPromptState | undefined {
    const prompt = this.pendingPrompt;
    this.pendingPrompt = undefined;
    return prompt;
  }

  private getCurrentProtectedResourcePromptItem(
    pendingRequest: PendingWebPermissionRequest
  ): PendingWebPermissionPromptItem | undefined {
    return pendingRequest.promptItems[pendingRequest.currentPromptIndex];
  }

  private advanceProtectedResourcePermissionFlow(pendingRequest: PendingWebPermissionRequest): boolean {
    pendingRequest.currentPromptIndex += 1;
    if (pendingRequest.currentPromptIndex < pendingRequest.promptItems.length) {
      this.showProtectedResourcePermissionDialog(pendingRequest);
      return true;
    }
    this.grantProtectedResourcePermission(pendingRequest);
    return false;
  }

  private denyProtectedResourceFlow(pendingRequest: PendingWebPermissionRequest): void {
    this.pendingPrompt = undefined;
    this.setPermissionFlowInFlight(pendingRequest.tabId, false);
    this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
    pendingRequest.request.deny();
  }

  private grantProtectedResourcePermission(pendingRequest: PendingWebPermissionRequest): void {
    this.requestAppPermissionsForKinds(pendingRequest.kinds)
      .then((result: SystemPermissionGrantResult) => {
        this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
        if (!result.granted) {
          pendingRequest.request.deny();
          const fault = this.browserFaultClassifier.classifyPermissionDenied(
            result.message
          );
          const label = this.getKindsLabel(pendingRequest.kinds);
          this.presentPermissionFaultDescriptor(label, fault);
          if (result.settingsRequired) {
            this.presentSystemPermissionSettingPrompt(
              pendingRequest.tabId,
              pendingRequest.kinds,
              label,
              result.locationServiceEnabled
            );
          }
          this.setPermissionFlowInFlight(pendingRequest.tabId, false);
          return;
        }

        pendingRequest.request.grant(pendingRequest.resources);
        this.setPermissionFlowInFlight(pendingRequest.tabId, false);
      })
      .catch((error: Error) => {
        this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
        pendingRequest.request.deny();
        const fault = this.browserFaultClassifier.classifyPermissionDenied(
          `权限授权失败：${JSON.stringify(error)}`
        );
        this.emitMessage('error', fault.userMessage);
        this.presentPermissionFaultDescriptor(
          this.getKindsLabel(pendingRequest.kinds),
          fault,
          '权限授权失败，已拒绝网页请求。'
        );
        this.setPermissionFlowInFlight(pendingRequest.tabId, false);
      });
  }

  private grantGeolocationPermission(pendingRequest: PendingGeolocationPermissionRequest): void {
    this.requestAppPermissionsForKinds(['location'])
      .then((result: SystemPermissionGrantResult) => {
        this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
        if (!result.granted) {
          pendingRequest.geolocation.invoke(pendingRequest.origin, false, false);
          const fault = this.browserFaultClassifier.classifyPermissionDenied(
            result.message
          );
          this.presentPermissionFaultDescriptor('位置信息', fault);
          if (result.settingsRequired) {
            this.presentSystemPermissionSettingPrompt(
              pendingRequest.tabId,
              ['location'],
              '位置信息',
              result.locationServiceEnabled
            );
          }
          this.setPermissionFlowInFlight(pendingRequest.tabId, false);
          return;
        }

        pendingRequest.geolocation.invoke(pendingRequest.origin, true, false);
        this.setPermissionFlowInFlight(pendingRequest.tabId, false);
      })
      .catch((error: Error) => {
        this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
        pendingRequest.geolocation.invoke(pendingRequest.origin, false, false);
        const fault = this.browserFaultClassifier.classifyPermissionDenied(
          `定位授权失败：${JSON.stringify(error)}`
        );
        this.emitMessage('error', fault.userMessage);
        this.presentPermissionFaultDescriptor(
          '位置信息',
          fault,
          '定位授权失败，已拒绝网页请求。'
        );
        this.setPermissionFlowInFlight(pendingRequest.tabId, false);
      });
  }

  private rememberAllowedForSession(tabId: string, origin: string, kinds: SitePermissionKind[]): void {
    this.sitePolicyService.setPermissionAllowedForSessionForOrigins(
      [origin],
      kinds,
      this.tabScopedEventContextCoordinator.resolveProfileId(tabId),
      this.tabScopedEventContextCoordinator.resolveDataScope(tabId)
    );
  }

  private presentSystemPermissionSettingPrompt(
    tabId: string,
    kinds: SitePermissionKind[],
    label: string,
    locationServiceEnabled: boolean = true
  ): void {
    this.pendingSystemPermissionSettingKinds = kinds.slice();
    this.sink.applyEffect({
      type: 'open_system_permission_setting_prompt',
      tabId: tabId,
      title: locationServiceEnabled ? '需要开启系统权限' : '需要开启位置信息',
      message: locationServiceEnabled
        ? `Aira 需要系统${label}权限，才能允许网站使用。`
        : '系统位置信息开关未开启，网站暂时无法获取位置。'
    });
  }

  dismissPendingSystemPermissionSettings(): void {
    this.pendingSystemPermissionSettingKinds = [];
  }

  private async persistThenAdvanceProtectedResourcePermission(
    pendingRequest: PendingWebPermissionRequest
  ): Promise<boolean> {
    const item = this.getCurrentProtectedResourcePromptItem(pendingRequest);
    if (item === undefined) {
      this.denyProtectedResourceFlow(pendingRequest);
      return false;
    }
    try {
      await this.persistPermissionRulesForTab(pendingRequest.tabId, pendingRequest.origin, [item.kind], 'allow');
      return this.advanceProtectedResourcePermissionFlow(pendingRequest);
    } catch (error) {
      this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
      this.setPermissionFlowInFlight(pendingRequest.tabId, false);
      pendingRequest.request.deny();
      this.emitMessage('error', `权限保存失败：${JSON.stringify(error)}`);
      return false;
    }
  }

  private async persistThenGrantGeolocationPermission(
    pendingRequest: PendingGeolocationPermissionRequest
  ): Promise<void> {
    try {
      await this.persistPermissionRulesForTab(pendingRequest.tabId, pendingRequest.origin, ['location'], 'allow');
      this.grantGeolocationPermission(pendingRequest);
    } catch (error) {
      this.backgroundSessionSyncCoordinator.release(pendingRequest.tabId);
      this.setPermissionFlowInFlight(pendingRequest.tabId, false);
      pendingRequest.geolocation.invoke(pendingRequest.origin, false, false);
      this.emitMessage('error', `权限保存失败：${JSON.stringify(error)}`);
    }
  }

  private persistPermissionRulesForTab(
    tabId: string,
    origin: string,
    kinds: SitePermissionKind[],
    rule: SitePermissionRule
  ): Promise<SitePermissionSettings> {
    const origins = [origin];
    return this.sitePolicyService.persistPermissionRuleForOrigins(
      origins,
      kinds,
      rule,
      this.tabScopedEventContextCoordinator.resolveProfileId(tabId),
      this.tabScopedEventContextCoordinator.resolveDataScope(tabId)
    )
      .then((settings: SitePermissionSettings) => {
        this.siteControlsRuntimeCoordinator.applyPersistedPermissionSettings(
          origins,
          settings,
          this.sink.resolveCurrentSiteOrigin()
        );
        return settings;
      });
  }

  private presentPermissionFaultDescriptor(
    label: string,
    fault: BrowserFaultDescriptor,
    toastMessage: string = fault.userMessage
  ): void {
    this.emitMessage('toast', toastMessage);
  }

  private rememberPermissionOrigin(origin: string): void {
    this.siteControlsRuntimeCoordinator.addRelatedOrigin(origin);
    this.siteControlsRuntimeCoordinator.addRelatedOrigin(this.sink.resolveCurrentSiteOrigin());
  }

  private requestAppPermissionsForKinds(kinds: SitePermissionKind[]): Promise<SystemPermissionGrantResult> {
    return this.permissionPolicyService.requestAppPermissionsForKinds(
      this.sink.resolveAbilityContext(),
      kinds
    );
  }

  private requestAppPermissionSettingsForKinds(kinds: SitePermissionKind[]): Promise<boolean> {
    return this.permissionPolicyService.requestAppPermissionSettingsForKinds(
      this.sink.resolveAbilityContext(),
      kinds
    ).then((result): boolean => result.granted);
  }

  private setPermissionFlowInFlight(tabId: string, active: boolean): void {
    this.permissionFlowInFlight = active;
    this.sink.applyEffect({
      type: 'permission_flow_state',
      tabId: tabId,
      active: active
    });
  }

  private async openSystemSettingsFallback(): Promise<void> {
    const result = await this.systemSettingsLaunchService.openAppPermissionSettings(
      this.sink.resolveAbilityContext()
    );
    this.emitMessage('helper', result.message);
    this.emitMessage('toast', result.message);
  }

  private emitMessage(kind: WebPermissionCoordinatorMessageKind, message: string): void {
    this.sink.applyEffect({
      type: 'message',
      kind: kind,
      message: message
    });
  }

  private getKindsLabel(kinds: SitePermissionKind[]): string {
    return this.sitePolicyService.getSitePermissionKindsLabel(kinds);
  }
}
