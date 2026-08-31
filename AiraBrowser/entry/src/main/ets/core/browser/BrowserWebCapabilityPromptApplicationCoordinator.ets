import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserExperimentSettings } from '../../common/models/BrowserModels';
import { AppProxySettingsCoordinator } from '../settings/AppProxySettingsCoordinator';
import { SystemSettingsLaunchService } from '../../services/system/SystemSettingsLaunchService';
import { HttpAuthCredentialPolicyService } from '../../services/password/HttpAuthCredentialPolicyService';
import { SiteInteractionLogicService } from '../../services/web/SiteInteractionLogicService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import { WebFileSelectorPolicyService } from '../../services/web/WebFileSelectorPolicyService';
import {
  WebSslErrorPolicyDecision,
  WebSslErrorPolicyService
} from '../../services/web/WebSslErrorPolicyService';
import {
  WebPermissionCoordinator,
  WebPermissionCoordinatorEffect
} from '../web/WebPermissionCoordinator';
import {
  BrowserFaultClassifier
} from './BrowserFaultClassifier';
import { BrowserSiteControlsRuntimeCoordinator } from './BrowserSiteControlsRuntimeCoordinator';
import { BrowserTabBackgroundSessionSyncCoordinator } from '../../services/web/BrowserTabBackgroundSessionSyncCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  PendingHttpAuthState,
  PendingSslErrorState
} from './BrowserShellRuntimeContracts';
import { BrowserWebDialogQueueKind } from './BrowserWebDialogQueue';
import { WebRuntimeBridge, WebSslWarningModel } from '../web/WebRuntimeBridge';
import {
  BrowserHttpsFirstFailureDecision,
  BrowserHttpsFirstPreparedFallback,
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';
import { BrowserWebDialogKind } from '../web/BrowserWebComponentController';
import { WebEventRouter } from '../web/WebEventRouter';
import { sharedBrowserContinuationCoordinator } from './BrowserContinuationCoordinator';

const WEB_CAPABILITY_PROMPT_LOG_DOMAIN: number = 0x0000;
const WEB_CAPABILITY_PROMPT_LOG_TAG: string = 'WebCapabilityPrompt';

type BrowserWebCapabilityPromptMessageKind = 'helper' | 'error' | 'toast';

export interface BrowserWebPromptDialogPresentation {
  title: string;
  message: string;
  defaultValue: string;
  inputValue: string;
}

interface BrowserWebConfirmDialogPresentation {
  title: string;
  message: string;
}

interface BrowserWebAlertDialogPresentation {
  title: string;
  message: string;
}

export interface BrowserHttpAuthDialogPresentation {
  host: string;
  realm: string;
  username: string;
  password: string;
  usernameLocked: boolean;
}

export interface BrowserSitePermissionDialogPresentation {
  title: string;
  message: string;
}

export type BrowserSitePermissionPromptAction = 'allow_during_use' | 'allow_for_session' | 'deny';

export function createEmptyBrowserWebPromptDialogPresentation(): BrowserWebPromptDialogPresentation {
  return {
    title: '',
    message: '',
    defaultValue: '',
    inputValue: ''
  };
}

export function createEmptyBrowserHttpAuthDialogPresentation(): BrowserHttpAuthDialogPresentation {
  return {
    host: '',
    realm: '',
    username: '',
    password: '',
    usernameLocked: false
  };
}

export function createEmptyBrowserSitePermissionDialogPresentation(): BrowserSitePermissionDialogPresentation {
  return {
    title: '',
    message: ''
  };
}

interface BrowserWebOpenJavaScriptPromptEffect {
  action: 'open_javascript_prompt';
  presentation: BrowserWebPromptDialogPresentation;
}

interface BrowserWebCloseJavaScriptPromptEffect {
  action: 'close_javascript_prompt';
}

interface BrowserWebOpenJavaScriptConfirmEffect {
  action: 'open_javascript_confirm';
  presentation: BrowserWebConfirmDialogPresentation;
}

interface BrowserWebOpenJavaScriptAlertEffect {
  action: 'open_javascript_alert';
  presentation: BrowserWebAlertDialogPresentation;
}

interface BrowserWebOpenHttpAuthEffect {
  action: 'open_http_auth';
  presentation: BrowserHttpAuthDialogPresentation;
}

interface BrowserWebClearHttpAuthEffect {
  action: 'clear_http_auth';
}

interface BrowserWebCloseHttpAuthEffect {
  action: 'close_http_auth';
}

interface BrowserWebOpenSslWarningEffect {
  action: 'open_ssl_warning';
  tabId: string;
  presentation: WebSslWarningModel;
}

interface BrowserWebOpenHttpsFirstFallbackWarningEffect {
  action: 'open_https_first_fallback_warning';
  tabId: string;
  attemptId: number;
  presentation: WebSslWarningModel;
}

interface BrowserWebOpenSitePermissionEffect {
  action: 'open_site_permission';
  tabId: string;
  presentation: BrowserSitePermissionDialogPresentation;
}

interface BrowserWebOpenSystemPermissionSettingEffect {
  action: 'open_system_permission_setting';
  tabId: string;
  title: string;
  message: string;
}

type BrowserWebCapabilityPromptDialogEffect =
  BrowserWebOpenJavaScriptPromptEffect |
  BrowserWebCloseJavaScriptPromptEffect |
  BrowserWebOpenJavaScriptConfirmEffect |
  BrowserWebOpenJavaScriptAlertEffect |
  BrowserWebOpenHttpAuthEffect |
  BrowserWebClearHttpAuthEffect |
  BrowserWebCloseHttpAuthEffect |
  BrowserWebOpenSslWarningEffect |
  BrowserWebOpenHttpsFirstFallbackWarningEffect |
  BrowserWebOpenSitePermissionEffect |
  BrowserWebOpenSystemPermissionSettingEffect;

interface BrowserWebCapabilityPromptMessageEffect {
  type: 'message';
  kind: BrowserWebCapabilityPromptMessageKind;
  message: string;
}

interface BrowserWebCapabilityPromptDialogApplicationEffect {
  type: 'dialog';
  dialog: BrowserWebCapabilityPromptDialogEffect;
}

export type BrowserWebCapabilityPromptApplicationEffect =
  BrowserWebCapabilityPromptMessageEffect |
  BrowserWebCapabilityPromptDialogApplicationEffect;

export interface BrowserWebCapabilityPromptEffectHandler {
  apply: (effect: BrowserWebCapabilityPromptApplicationEffect) => void;
}

export interface BrowserWebCapabilityPromptApplicationSink {
  resolveAbilityContext: () => common.UIAbilityContext;
  resolveExperiments: () => BrowserExperimentSettings;
  setWebDialogVisible: (tabId: string, kind: BrowserWebDialogKind, visible: boolean) => void;
  resolveEffectHandler: () => BrowserWebCapabilityPromptEffectHandler;
}

export interface BrowserWebCapabilityPromptApplicationDependencies {
  webRuntimeBridge: WebRuntimeBridge;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  backgroundSessionSyncCoordinator: BrowserTabBackgroundSessionSyncCoordinator;
  appProxySettingsCoordinator: AppProxySettingsCoordinator;
  sitePolicyService: SitePolicyService;
  siteControlsRuntimeCoordinator: BrowserSiteControlsRuntimeCoordinator;
  siteInteractionLogicService: SiteInteractionLogicService;
  systemSettingsLaunchService: SystemSettingsLaunchService;
  browserFaultClassifier: BrowserFaultClassifier;
  webEventRouter: WebEventRouter;
}

interface BrowserPendingPromptRecord {
  tabId: string;
  event: OnPromptEvent;
}

interface BrowserPendingConfirmRecord {
  tabId: string;
  event: OnConfirmEvent;
}

interface BrowserPendingAlertRecord {
  tabId: string;
  event: OnAlertEvent;
}

interface BrowserPendingHttpsFirstFallbackRecord {
  decision: BrowserHttpsFirstFailureDecision;
  visible: boolean;
}

export class BrowserWebCapabilityPromptApplicationCoordinator {
  private readonly dependencies: BrowserWebCapabilityPromptApplicationDependencies;
  private readonly sink: BrowserWebCapabilityPromptApplicationSink;
  private readonly fileSelectorPolicyService: WebFileSelectorPolicyService;
  private readonly httpAuthCredentialPolicyService: HttpAuthCredentialPolicyService;
  private readonly sslErrorPolicyService: WebSslErrorPolicyService;
  private readonly webPermissionCoordinator: WebPermissionCoordinator;
  private pendingPrompt?: BrowserPendingPromptRecord;
  private pendingConfirm?: BrowserPendingConfirmRecord;
  private pendingAlert?: BrowserPendingAlertRecord;
  private pendingHttpAuthState: PendingHttpAuthState = {
    tabId: '',
    requestHost: '',
    isProxyAuthentication: false
  };
  private pendingSslErrorState: PendingSslErrorState = {
    tabId: ''
  };
  private pendingSitePermissionContinuationTabId: string = '';
  private pendingHttpsFirstFallbackByTabId:
    Record<string, BrowserPendingHttpsFirstFallbackRecord | undefined> = {};

  constructor(
    dependencies: BrowserWebCapabilityPromptApplicationDependencies,
    sink: BrowserWebCapabilityPromptApplicationSink,
    fileSelectorPolicyService: WebFileSelectorPolicyService = new WebFileSelectorPolicyService(),
    httpAuthCredentialPolicyService: HttpAuthCredentialPolicyService = new HttpAuthCredentialPolicyService(),
    sslErrorPolicyService: WebSslErrorPolicyService = new WebSslErrorPolicyService()
  ) {
    this.dependencies = dependencies;
    this.sink = sink;
    this.fileSelectorPolicyService = fileSelectorPolicyService;
    this.httpAuthCredentialPolicyService = httpAuthCredentialPolicyService;
    this.sslErrorPolicyService = sslErrorPolicyService;
    this.webPermissionCoordinator = new WebPermissionCoordinator({
      sitePolicyService: dependencies.sitePolicyService,
      browserFaultClassifier: dependencies.browserFaultClassifier,
      tabScopedEventContextCoordinator: dependencies.tabScopedEventContextCoordinator,
      siteControlsRuntimeCoordinator: dependencies.siteControlsRuntimeCoordinator,
      siteInteractionLogicService: dependencies.siteInteractionLogicService,
      backgroundSessionSyncCoordinator: dependencies.backgroundSessionSyncCoordinator,
      systemSettingsLaunchService: dependencies.systemSettingsLaunchService,
      sink: {
        resolveAbilityContext: (): common.UIAbilityContext => this.sink.resolveAbilityContext(),
        resolveCurrentSiteOrigin: (): string =>
          this.dependencies.tabScopedEventContextCoordinator.resolveCurrentContext().siteOrigin,
        applyEffect: (effect: WebPermissionCoordinatorEffect): void => this.applyPermissionEffect(effect)
      }
    });
  }

  resetProxyCredentialAttempts(): void {
    this.httpAuthCredentialPolicyService.resetProxyCredentialAttempts();
  }

  hasPendingJavaScriptPrompt(): boolean {
    return this.pendingPrompt !== undefined;
  }

  hasAnyPendingJavaScriptDialog(): boolean {
    return this.pendingPrompt !== undefined || this.pendingConfirm !== undefined || this.pendingAlert !== undefined;
  }

  hasPendingHttpAuth(): boolean {
    return this.pendingHttpAuthState.event !== undefined;
  }

  hasPendingSitePermissionPrompt(): boolean {
    return this.webPermissionCoordinator.hasPendingPrompt();
  }

  clearPendingJavaScriptPrompt(): string {
    const tabId = this.pendingPrompt?.tabId ?? '';
    this.pendingPrompt = undefined;
    this.setDialogVisible(tabId, 'prompt', false);
    return tabId;
  }

  handleJavaScriptPrompt(tabId: string, event: OnPromptEvent): void {
    const normalizedTabId = tabId.trim();
    this.pendingPrompt = {
      tabId: normalizedTabId,
      event: event
    };
    this.setDialogVisible(normalizedTabId, 'prompt', true);
    this.emitDialog({
      action: 'open_javascript_prompt',
      presentation: {
        title: event.url.length > 0 ? event.url : '网页提示',
        message: event.message,
        defaultValue: event.value,
        inputValue: event.value
      }
    });
  }

  confirmJavaScriptPrompt(value: string): void {
    const record = this.pendingPrompt;
    this.pendingPrompt = undefined;
    this.setDialogVisible(record?.tabId ?? '', 'prompt', false);
    record?.event.result.handlePromptConfirm(value);
  }

  cancelJavaScriptPrompt(): void {
    const record = this.pendingPrompt;
    this.pendingPrompt = undefined;
    this.setDialogVisible(record?.tabId ?? '', 'prompt', false);
    record?.event.result.handleCancel();
  }

  handleJavaScriptConfirm(tabId: string, event: OnConfirmEvent): void {
    const normalizedTabId = tabId.trim();
    this.pendingConfirm = {
      tabId: normalizedTabId,
      event: event
    };
    this.setDialogVisible(normalizedTabId, 'confirm', true);
    this.emitDialog({
      action: 'open_javascript_confirm',
      presentation: {
        title: event.url.length > 0 ? event.url : '网页确认',
        message: event.message
      }
    });
  }

  confirmJavaScriptConfirm(): void {
    const record = this.pendingConfirm;
    this.pendingConfirm = undefined;
    this.setDialogVisible(record?.tabId ?? '', 'confirm', false);
    record?.event.result.handleConfirm();
  }

  cancelJavaScriptConfirm(): void {
    const record = this.pendingConfirm;
    this.pendingConfirm = undefined;
    this.setDialogVisible(record?.tabId ?? '', 'confirm', false);
    record?.event.result.handleCancel();
  }

  handleJavaScriptAlert(tabId: string, event: OnAlertEvent): void {
    const normalizedTabId = tabId.trim();
    this.pendingAlert = {
      tabId: normalizedTabId,
      event: event
    };
    this.setDialogVisible(normalizedTabId, 'alert', true);
    this.emitDialog({
      action: 'open_javascript_alert',
      presentation: {
        title: event.url.length > 0 ? event.url : '网页提示',
        message: event.message
      }
    });
  }

  confirmJavaScriptAlert(): void {
    const record = this.pendingAlert;
    this.pendingAlert = undefined;
    this.setDialogVisible(record?.tabId ?? '', 'alert', false);
    record?.event.result.handleConfirm();
  }

  handleJavaScriptDialogBack(tabId: string, kind: BrowserWebDialogQueueKind): boolean {
    if (tabId !== this.dependencies.tabScopedEventContextCoordinator.resolveCurrentContext().activeTabId) {
      return false;
    }
    if (kind === 'prompt') {
      this.cancelJavaScriptPrompt();
      this.emitDialog({ action: 'close_javascript_prompt' });
      return true;
    }
    if (kind === 'confirm') {
      this.cancelJavaScriptConfirm();
      return true;
    }
    this.confirmJavaScriptAlert();
    return true;
  }

  handleShowFileSelector(tabId: string, event: OnShowFileSelectorEvent): boolean {
    this.emitMessage('helper', '正在打开文件选择器');
    this.dependencies.backgroundSessionSyncCoordinator.protect(
      tabId,
      '网页文件选择器打开中，暂不回收 runtime。'
    );
    void this.openWebFileSelector(tabId, event);
    return true;
  }

  handleHttpAuthRequest(tabId: string, event: OnHttpAuthRequestEvent): void {
    const model = this.dependencies.webRuntimeBridge.buildHttpAuthDialogModel(event);
    const experiments = this.sink.resolveExperiments();
    const credentialDecision = this.httpAuthCredentialPolicyService.resolveProxyCredentialDecision(
      model.host,
      model.realm,
      experiments
    );
    hilog.info(
      WEB_CAPABILITY_PROMPT_LOG_DOMAIN,
      WEB_CAPABILITY_PROMPT_LOG_TAG,
      'proxy http auth request tab=%{public}s requestHost=%{public}s realmLength=%{public}d enabled=%{public}s proxyHost=%{public}s proxyPort=%{public}d user=%{public}s updatedAt=%{public}s auto=%{public}s',
      tabId,
      model.host,
      model.realm.length,
      experiments.appProxyEnabled ? '1' : '0',
      experiments.appProxy.host,
      experiments.appProxy.port,
      this.maskDiagnosticText(experiments.appProxy.username),
      String(experiments.appProxy.updatedAt),
      credentialDecision.shouldAutoConfirm ? '1' : '0'
    );
    if (credentialDecision.shouldAutoConfirm) {
      event.handler.confirm(credentialDecision.username, credentialDecision.password);
      return;
    }
    this.pendingHttpAuthState = {
      event: event,
      tabId: tabId,
      requestHost: model.host,
      isProxyAuthentication: credentialDecision.isProxyAuthentication
    };
    this.dependencies.backgroundSessionSyncCoordinator.protect(
      tabId,
      '网页认证对话框等待用户处理，暂不回收 runtime。 auth=http'
    );
    this.setDialogVisible(tabId, 'http_auth', true);
    this.emitDialog({
      action: 'open_http_auth',
      presentation: {
        host: model.host,
        realm: model.realm,
        username: credentialDecision.username,
        password: '',
        usernameLocked: credentialDecision.isProxyAuthentication && credentialDecision.username.length > 0
      }
    });
  }

  confirmHttpAuth(username: string, password: string): void {
    const pending = this.pendingHttpAuthState;
    this.clearPendingHttpAuthState(pending.tabId);
    const sanitizedUsername = this.httpAuthCredentialPolicyService.sanitizeCredentialText(username);
    if (pending.event === undefined) {
      return;
    }
    if (pending.isProxyAuthentication) {
      this.persistConfirmedProxyCredential(pending.tabId, pending.requestHost, sanitizedUsername, password);
    }
    pending.event.handler.confirm(sanitizedUsername, password);
  }

  cancelHttpAuth(): void {
    const event = this.pendingHttpAuthState.event;
    this.clearPendingHttpAuthState(this.pendingHttpAuthState.tabId);
    event?.handler.cancel();
  }

  cancelHttpAuthFromBack(): boolean {
    this.cancelHttpAuth();
    this.emitDialog({ action: 'close_http_auth' });
    return true;
  }

  clearPendingHttpAuthState(tabId: string = this.pendingHttpAuthState.tabId): void {
    if (tabId.length > 0) {
      this.setDialogVisible(tabId, 'http_auth', false);
      this.dependencies.backgroundSessionSyncCoordinator.release(tabId);
    }
    this.pendingHttpAuthState = {
      tabId: '',
      requestHost: '',
      isProxyAuthentication: false
    };
    this.emitDialog({ action: 'clear_http_auth' });
  }

  handleSslErrorEvent(tabId: string, event: SslErrorEvent): void {
    const navigationDecision = event.isMainFrame
      ? this.dependencies.webEventRouter.resolveMainFrameEventDecision(tabId, event.url, 'error_receive')
      : undefined;
    if (navigationDecision !== undefined && !navigationDecision.accepted) {
      event.handler.handleCancel(true);
      return;
    }
    const httpsFirstDecision = sharedBrowserHttpsFirstNavigationService.resolveSslFailureDecision(tabId, {
      requestUrl: event.url,
      isMainFrame: event.isMainFrame,
      isFatalError: event.isFatalError,
      navigationId: navigationDecision?.navigationId ?? 0
    });
    if (httpsFirstDecision.action !== 'normal_failure') {
      event.handler.handleCancel(true);
      if (httpsFirstDecision.delivery === 'suppress_duplicate') {
        return;
      }
      if (httpsFirstDecision.action === 'automatic_http_fallback') {
        const preparedFallback = sharedBrowserHttpsFirstNavigationService.prepareFallback(
          tabId,
          httpsFirstDecision.attemptId
        );
        this.scheduleHttpFallback(preparedFallback);
        return;
      }
      this.handleHttpsFirstFallbackDecision(tabId, httpsFirstDecision);
      return;
    }
    const decision = this.sslErrorPolicyService.decide({
      tabId: tabId,
      activeTabId: this.dependencies.tabScopedEventContextCoordinator.resolveCurrentContext().activeTabId,
      requestUrl: event.url,
      originalUrl: event.originalUrl,
      referrer: event.referrer,
      isMainFrame: event.isMainFrame,
      isFatalError: event.isFatalError
    });
    if (this.applySslCancelIfNeeded(event, decision)) {
      return;
    }
    this.pendingSslErrorState = {
      event: event,
      tabId: tabId
    };
    this.dependencies.backgroundSessionSyncCoordinator.protect(
      tabId,
      '网页 SSL 证书风险提示等待用户处理，暂不回收 runtime。 auth=ssl'
    );
    this.setDialogVisible(tabId, 'ssl_error', true);
    this.emitDialog({
      action: 'open_ssl_warning',
      tabId: tabId,
      presentation: this.dependencies.webRuntimeBridge.buildSslWarningModel(event)
    });
  }

  confirmSslErrorWarning(tabId: string): void {
    const event = this.pendingSslErrorState.event;
    this.clearPendingSslErrorState(tabId);
    event?.handler.handleConfirm();
  }

  cancelSslErrorWarning(
    tabId: string = this.pendingSslErrorState.tabId,
    abortLoading: boolean = true
  ): void {
    const event = this.pendingSslErrorState.event;
    this.clearPendingSslErrorState(tabId);
    event?.handler.handleCancel(abortLoading);
  }

  cancelSslErrorWarningFromBack(tabId: string): boolean {
    const httpsFirstPending = this.pendingHttpsFirstFallbackByTabId[tabId];
    if (httpsFirstPending !== undefined) {
      this.cancelHttpsFirstFallbackWarning(tabId, httpsFirstPending.decision.attemptId);
      return true;
    }
    this.cancelSslErrorWarning(tabId, true);
    return true;
  }

  handleHttpsFirstFallbackDecision(tabId: string, decision: BrowserHttpsFirstFailureDecision): void {
    if (decision.action !== 'require_http_confirmation' || decision.attemptId <= 0) {
      return;
    }
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length === 0) {
      return;
    }
    const existing = this.pendingHttpsFirstFallbackByTabId[normalizedTabId];
    if (existing !== undefined && existing.decision.attemptId !== decision.attemptId) {
      this.clearPendingHttpsFirstFallback(normalizedTabId);
    }
    this.pendingHttpsFirstFallbackByTabId[normalizedTabId] = {
      decision: decision,
      visible: false
    };
    hilog.info(
      WEB_CAPABILITY_PROMPT_LOG_DOMAIN,
      WEB_CAPABILITY_PROMPT_LOG_TAG,
      'https-first fallback pending tab=%{public}s attempt=%{public}d',
      normalizedTabId,
      decision.attemptId
    );
    this.presentPendingHttpsFirstFallback(normalizedTabId);
  }

  handleActiveTabChanged(tabId: string): void {
    this.presentPendingHttpsFirstFallback(tabId);
  }

  handleNavigationStarted(tabId: string): void {
    const pending = this.pendingHttpsFirstFallbackByTabId[tabId];
    if (pending !== undefined &&
      !sharedBrowserHttpsFirstNavigationService.isAttemptCurrent(tabId, pending.decision.attemptId)) {
      this.clearPendingHttpsFirstFallback(tabId);
    }
  }

  handleWebSurfaceVisibilityChanged(tabId: string, visible: boolean): void {
    if (visible) {
      this.presentPendingHttpsFirstFallback(tabId);
    }
  }

  confirmHttpsFirstFallbackWarning(tabId: string, attemptId: number): void {
    const pending = this.pendingHttpsFirstFallbackByTabId[tabId];
    if (pending === undefined || pending.decision.attemptId !== attemptId) {
      return;
    }
    this.clearPendingHttpsFirstFallback(tabId);
    const preparedFallback = sharedBrowserHttpsFirstNavigationService.prepareFallback(
      tabId,
      pending.decision.attemptId,
      true
    );
    hilog.info(
      WEB_CAPABILITY_PROMPT_LOG_DOMAIN,
      WEB_CAPABILITY_PROMPT_LOG_TAG,
      'https-first fallback confirmed tab=%{public}s attempt=%{public}d',
      tabId,
      pending.decision.attemptId
    );
    this.scheduleHttpFallback(preparedFallback);
  }

  cancelHttpsFirstFallbackWarning(tabId: string, attemptId: number): void {
    const pending = this.pendingHttpsFirstFallbackByTabId[tabId];
    if (pending === undefined || pending.decision.attemptId !== attemptId) {
      return;
    }
    const declined = sharedBrowserHttpsFirstNavigationService.declineFallback(
      tabId,
      pending.decision.attemptId
    );
    this.clearPendingHttpsFirstFallback(tabId);
    hilog.info(
      WEB_CAPABILITY_PROMPT_LOG_DOMAIN,
      WEB_CAPABILITY_PROMPT_LOG_TAG,
      'https-first fallback cancelled tab=%{public}s attempt=%{public}d declined=%{public}s',
      tabId,
      pending.decision.attemptId,
      declined ? '1' : '0'
    );
  }

  clearHttpsFirstFallbackForTab(tabId: string): void {
    this.clearPendingHttpsFirstFallback(tabId);
  }

  handleProtectedResourcePermissionRequest(tabId: string, request: PermissionRequest): void {
    this.webPermissionCoordinator.handleProtectedResourcePermissionRequest(tabId, request);
  }

  handleGeolocationPermissionRequest(tabId: string, event: OnGeolocationShowEvent): void {
    this.webPermissionCoordinator.handleGeolocationPermissionRequest(tabId, event);
  }

  async allowPendingPermissionForSession(): Promise<boolean> {
    const hasNextPrompt = await this.webPermissionCoordinator.allowPendingPermissionForSession();
    this.finishSitePermissionContinuationBlocker(hasNextPrompt);
    return hasNextPrompt;
  }

  async allowPendingPermissionDuringUse(): Promise<boolean> {
    const hasNextPrompt = await this.webPermissionCoordinator.allowPendingPermissionDuringUse();
    this.finishSitePermissionContinuationBlocker(hasNextPrompt);
    return hasNextPrompt;
  }

  async denyPendingPermission(): Promise<boolean> {
    const hasNextPrompt = await this.webPermissionCoordinator.denyPendingPermission();
    this.finishSitePermissionContinuationBlocker(hasNextPrompt);
    return hasNextPrompt;
  }

  dismissPendingPermissionPrompt(): void {
    this.webPermissionCoordinator.dismissPendingPermissionPrompt();
    this.finishSitePermissionContinuationBlocker(false);
  }

  handlePendingSitePermissionAction(action: BrowserSitePermissionPromptAction): Promise<boolean> {
    if (action === 'allow_during_use') {
      return this.allowPendingPermissionDuringUse();
    }
    if (action === 'allow_for_session') {
      return this.allowPendingPermissionForSession();
    }
    return this.denyPendingPermission();
  }

  requestPendingSystemPermissionSettings(): void {
    this.webPermissionCoordinator.requestPendingSystemPermissionSettings();
    this.finishSitePermissionContinuationBlocker(false);
  }

  dismissPendingSystemPermissionSettingsPrompt(): void {
    this.webPermissionCoordinator.dismissPendingSystemPermissionSettings();
    this.finishSitePermissionContinuationBlocker(false);
  }

  private clearPendingSslErrorState(tabId: string = this.pendingSslErrorState.tabId): void {
    if (tabId.length > 0) {
      this.setDialogVisible(tabId, 'ssl_error', false);
      this.dependencies.backgroundSessionSyncCoordinator.release(tabId);
    }
    this.pendingSslErrorState = {
      tabId: ''
    };
  }

  private scheduleHttpFallback(preparedFallback: BrowserHttpsFirstPreparedFallback | undefined): void {
    if (preparedFallback === undefined) {
      return;
    }
    setTimeout((): void => {
      sharedBrowserHttpsFirstNavigationService.executePreparedFallback(preparedFallback);
    }, 0);
  }

  private presentPendingHttpsFirstFallback(tabId: string): void {
    const pending = this.pendingHttpsFirstFallbackByTabId[tabId];
    if (pending !== undefined &&
      !sharedBrowserHttpsFirstNavigationService.isAttemptCurrent(tabId, pending.decision.attemptId)) {
      this.clearPendingHttpsFirstFallback(tabId);
      return;
    }
    const activeTabId = this.dependencies.tabScopedEventContextCoordinator.resolveCurrentContext().activeTabId;
    if (pending === undefined || pending.visible || tabId !== activeTabId ||
      !this.dependencies.tabScopedEventContextCoordinator.isWebSurfaceVisible()) {
      return;
    }
    pending.visible = true;
    this.dependencies.backgroundSessionSyncCoordinator.protect(
      tabId,
      'HTTPS-First HTTP 回退提示等待用户处理，暂不回收 runtime。 auth=https_first_http_fallback'
    );
    this.setDialogVisible(tabId, 'ssl_error', true);
    this.emitDialog({
      action: 'open_https_first_fallback_warning',
      tabId: tabId,
      attemptId: pending.decision.attemptId,
      presentation: this.dependencies.webRuntimeBridge.buildHttpsFirstFallbackWarningModel(
        pending.decision.failedUrl,
        pending.decision.fallbackUrl
      )
    });
    hilog.info(
      WEB_CAPABILITY_PROMPT_LOG_DOMAIN,
      WEB_CAPABILITY_PROMPT_LOG_TAG,
      'https-first fallback presented tab=%{public}s attempt=%{public}d',
      tabId,
      pending.decision.attemptId
    );
  }

  private clearPendingHttpsFirstFallback(tabId: string): void {
    const pending = this.pendingHttpsFirstFallbackByTabId[tabId];
    if (pending?.visible === true) {
      this.setDialogVisible(tabId, 'ssl_error', false);
      this.dependencies.backgroundSessionSyncCoordinator.release(tabId);
    }
    this.pendingHttpsFirstFallbackByTabId[tabId] = undefined;
  }


  private async openWebFileSelector(tabId: string, event: OnShowFileSelectorEvent): Promise<void> {
    try {
      const selection = await this.fileSelectorPolicyService.pickUris(
        this.sink.resolveAbilityContext(),
        this.dependencies.webRuntimeBridge.buildFileSelectorPlan(event.fileSelector)
      );
      event.result.handleFileList(selection.uris);
      this.emitMessage('helper', selection.helperMessage);
    } catch (error) {
      const fault = this.dependencies.browserFaultClassifier.classifyFileSelectorFailure(
        `选择文件失败：${JSON.stringify(error)}`
      );
      this.emitMessage('error', fault.userMessage);
      this.emitMessage('helper', '网页选择文件失败');
      try {
        event.result.handleFileList([]);
      } catch (_innerError) {
      }
      this.emitMessage('toast', '选择文件失败，请稍后重试。');
    } finally {
      this.dependencies.backgroundSessionSyncCoordinator.release(tabId);
    }
  }

  private applySslCancelIfNeeded(
    event: SslErrorEvent,
    decision: WebSslErrorPolicyDecision
  ): boolean {
    if (decision.action !== 'cancel_request') {
      return false;
    }
    event.handler.handleCancel(decision.abortLoading);
    return true;
  }

  private persistConfirmedProxyCredential(
    tabId: string,
    requestHost: string,
    username: string,
    password: string
  ): void {
    const nextSettings = this.httpAuthCredentialPolicyService.buildSettingsWithConfirmedProxyCredential(
      requestHost,
      this.sink.resolveExperiments(),
      username,
      password
    );
    if (nextSettings === undefined) {
      return;
    }
    const context = this.dependencies.tabScopedEventContextCoordinator.resolveContext(tabId);
    void this.dependencies.appProxySettingsCoordinator.saveAuthenticatedProxySettings(nextSettings, {
      profileId: context.profileId,
      dataScope: context.dataScope,
      privacyMode: context.privacyMode,
      sessionId: context.tabId
    });
  }

  private applyPermissionEffect(effect: WebPermissionCoordinatorEffect): void {
    if (effect.type === 'permission_flow_state') {
      sharedBrowserContinuationCoordinator.setTransientFlowBlocked(
        effect.tabId,
        'native_permission',
        effect.active
      );
      return;
    }
    if (effect.type === 'message') {
      this.emitMessage(effect.kind, effect.message);
      return;
    }
    if (effect.type === 'open_site_permission_prompt') {
      this.beginSitePermissionContinuationBlocker(effect.tabId);
      this.emitDialog({
        action: 'open_site_permission',
        tabId: effect.tabId,
        presentation: {
          title: effect.presentation.title,
          message: effect.presentation.message
        }
      });
      return;
    }
    this.beginSitePermissionContinuationBlocker(effect.tabId);
    this.emitDialog({
      action: 'open_system_permission_setting',
      tabId: effect.tabId,
      title: effect.title,
      message: effect.message
    });
  }

  private beginSitePermissionContinuationBlocker(tabId: string): void {
    const normalizedTabId = tabId.trim();
    if (this.pendingSitePermissionContinuationTabId.length > 0 &&
      this.pendingSitePermissionContinuationTabId !== normalizedTabId) {
      sharedBrowserContinuationCoordinator.setTransientFlowBlocked(
        this.pendingSitePermissionContinuationTabId,
        'site_permission',
        false
      );
    }
    this.pendingSitePermissionContinuationTabId = normalizedTabId;
    sharedBrowserContinuationCoordinator.setTransientFlowBlocked(normalizedTabId, 'site_permission', true);
  }

  private finishSitePermissionContinuationBlocker(hasNextPrompt: boolean): void {
    if (hasNextPrompt || this.pendingSitePermissionContinuationTabId.length === 0) {
      return;
    }
    sharedBrowserContinuationCoordinator.setTransientFlowBlocked(
      this.pendingSitePermissionContinuationTabId,
      'site_permission',
      false
    );
    this.pendingSitePermissionContinuationTabId = '';
  }

  private setDialogVisible(tabId: string, kind: BrowserWebDialogKind, visible: boolean): void {
    if (tabId.length <= 0) {
      return;
    }
    this.sink.setWebDialogVisible(tabId, kind, visible);
  }

  private emitMessage(kind: BrowserWebCapabilityPromptMessageKind, message: string): void {
    this.sink.resolveEffectHandler().apply({
      type: 'message',
      kind: kind,
      message: message
    });
  }

  private emitDialog(dialog: BrowserWebCapabilityPromptDialogEffect): void {
    this.sink.resolveEffectHandler().apply({
      type: 'dialog',
      dialog: dialog
    });
  }

  private maskDiagnosticText(value: string): string {
    const normalized = value.trim();
    if (normalized.length <= 0) {
      return 'empty';
    }
    return `${normalized.substring(0, 1)}***(${normalized.length})`;
  }
}
