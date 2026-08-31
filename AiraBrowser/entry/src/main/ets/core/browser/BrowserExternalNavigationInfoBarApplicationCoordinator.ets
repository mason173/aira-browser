import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import {
  ExternalNavigationOpenResult,
  ExternalNavigationPolicyService,
  ExternalNavigationPromptPreflightResult
} from '../../services/web/ExternalNavigationPolicyService';
import { SiteIconService } from '../../services/siteicons/SiteIconService';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import { BrowserFaultClassifier } from './BrowserFaultClassifier';
import {
  BrowserExternalNavigationInfoBarDecisionPlan,
  BrowserInfoBarQueue
} from './BrowserInfoBarQueue';
import { BrowserExternalNavigationRuntimeStateCoordinator } from './BrowserExternalNavigationRuntimeStateCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  ExternalNavigationPromptPageContext,
  ExternalNavigationPromptPageContextInput,
  ExternalNavigationPromptPresentationContext,
  ExternalNavigationPromptState,
  ExternalNavigationPromptViewModel
} from './ExternalNavigationPromptViewModel';

export interface BrowserExternalNavigationInfoBarApplicationCoordinatorDependencies {
  externalNavigationRuntimeStateCoordinator: BrowserExternalNavigationRuntimeStateCoordinator;
  faultClassifier: BrowserFaultClassifier;
  preferencesRepository: PreferencesRepository;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  recentActionManager: BrowserRecentActionManager;
  externalNavigationPolicyService?: ExternalNavigationPolicyService;
  siteIconService?: SiteIconService;
}

export interface BrowserExternalNavigationInfoBarApplicationShell {
  readPromptPresentationContext: (tabId: string) => ExternalNavigationPromptPresentationContext;
  publishPromptState: (state: ExternalNavigationPromptState) => void;
  openExternalLink: (url: string) => Promise<ExternalNavigationOpenResult>;
  setExternalNavigationHelperMessage: (message: string) => void;
  setExternalNavigationErrorMessage: (message: string) => void;
  showToast: (message: string) => void;
}

export interface BrowserExternalNavigationInfoBarPromptRequest {
  tabId: string;
  url: string;
  appName: string;
  createdAt: number;
}

export type BrowserExternalNavigationPromptUserAction = 'open' | 'dismiss';

export class BrowserExternalNavigationInfoBarApplicationCoordinator {
  private readonly externalNavigationPolicyService: ExternalNavigationPolicyService;
  private readonly siteIconService: SiteIconService;
  private readonly externalNavigationRuntimeStateCoordinator: BrowserExternalNavigationRuntimeStateCoordinator;
  private readonly faultClassifier: BrowserFaultClassifier;
  private readonly preferencesRepository: PreferencesRepository;
  private readonly tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  private readonly recentActionManager: BrowserRecentActionManager;
  private readonly shell: BrowserExternalNavigationInfoBarApplicationShell;
  private readonly infoBarQueue: BrowserInfoBarQueue = new BrowserInfoBarQueue();
  private readonly externalNavigationPromptViewModel: ExternalNavigationPromptViewModel =
    new ExternalNavigationPromptViewModel();
  private promptState: ExternalNavigationPromptState = this.infoBarQueue.createHiddenExternalNavigationState();
  private activeExternalNavigationPromptId: string = '';

  constructor(
    dependencies: BrowserExternalNavigationInfoBarApplicationCoordinatorDependencies,
    shell: BrowserExternalNavigationInfoBarApplicationShell
  ) {
    this.externalNavigationRuntimeStateCoordinator = dependencies.externalNavigationRuntimeStateCoordinator;
    this.faultClassifier = dependencies.faultClassifier;
    this.preferencesRepository = dependencies.preferencesRepository;
    this.tabScopedEventContextCoordinator = dependencies.tabScopedEventContextCoordinator;
    this.recentActionManager = dependencies.recentActionManager;
    this.externalNavigationPolicyService =
      dependencies.externalNavigationPolicyService ?? new ExternalNavigationPolicyService();
    this.siteIconService = dependencies.siteIconService ?? new SiteIconService();
    this.shell = shell;
  }

  createInitialPromptState(): ExternalNavigationPromptState {
    return this.infoBarQueue.createHiddenExternalNavigationState();
  }

  async showPromptAfterPreflight(
    request: BrowserExternalNavigationInfoBarPromptRequest
  ): Promise<ExternalNavigationPromptState | undefined> {
    try {
      const preflight = await this.externalNavigationPolicyService.resolvePromptPreflight(request.url);
      if (preflight.action === 'show_unavailable_message') {
        this.showPreflightUnavailable(request.tabId, request.url, preflight);
        return undefined;
      }
      return this.showPrompt({
        tabId: request.tabId,
        url: request.url,
        appName: preflight.appName.length > 0 ? preflight.appName : request.appName,
        createdAt: request.createdAt
      });
    } catch (_error) {
      return this.showPrompt(request);
    }
  }

  handleUserAction(action: BrowserExternalNavigationPromptUserAction, now: number = Date.now()): void {
    const plan = action === 'open'
      ? this.infoBarQueue.consumeExternalNavigationConfirm()
      : this.infoBarQueue.consumeExternalNavigationDismiss();
    this.activeExternalNavigationPromptId = '';
    this.publishPromptState(plan.promptState);
    void this.applySideEffects(plan, now);
  }

  openExternalLinkForTab(tabId: string, url: string): void {
    void this.executeExternalLinkOpenAfterPreflight(tabId, url);
  }

  buildPageContext(input: ExternalNavigationPromptPageContextInput): ExternalNavigationPromptPageContext {
    return this.externalNavigationPromptViewModel.buildPageContext(input);
  }

  handlePageContextChanged(context: ExternalNavigationPromptPageContext): void {
    if (!this.promptState.visible) {
      return;
    }
    const nextState = this.externalNavigationPromptViewModel.resolveForPageContext(this.promptState, context);
    if (nextState.visible) {
      return;
    }
    this.activeExternalNavigationPromptId = '';
    this.infoBarQueue.clearExternalNavigation();
    this.publishPromptState(nextState);
  }

  private showPrompt(
    request: BrowserExternalNavigationInfoBarPromptRequest
  ): ExternalNavigationPromptState {
    const origin = this.tabScopedEventContextCoordinator.resolveSiteOrigin(request.tabId);
    const model = this.externalNavigationPolicyService.buildDialogModel(
      request.url,
      origin,
      this.tabScopedEventContextCoordinator.resolveDataScope(request.tabId)
    );
    const iconUri = this.resolveImmediateSiteIconUri(origin);
    const promptAppName = request.appName.length > 0 ? request.appName : model.appName;
    const presentation = this.shell.readPromptPresentationContext(request.tabId);
    const plan = this.infoBarQueue.enqueueExternalNavigationPrompt({
      tabId: request.tabId,
      url: request.url,
      appName: promptAppName,
      sourcePageUrl: presentation.sourcePageUrl,
      createdAt: request.createdAt,
      originLabel: model.displayOrigin,
      dataScopeLabel: model.redactedOrigin ? model.displayOrigin : '',
      iconUri: iconUri,
      favicon: presentation.favicon,
      trigger: 'user_gesture'
    });
    this.activeExternalNavigationPromptId = plan.record.id;
    this.externalNavigationRuntimeStateCoordinator.recordPromptShown(plan.record.url, plan.record.createdAt);
    this.publishPromptState(plan.promptState);
    this.hydratePromptPresentation(origin, request, plan.record.id, iconUri);
    return plan.promptState;
  }

  private publishPromptState(state: ExternalNavigationPromptState): void {
    this.promptState = state;
    this.shell.publishPromptState(state);
  }

  private buildPromptAppNameStateUpdate(
    currentState: ExternalNavigationPromptState,
    tabId: string,
    url: string,
    createdAt: number,
    appName: string
  ): ExternalNavigationPromptState | undefined {
    const normalizedAppName = appName.trim();
    if (!currentState.visible ||
      currentState.tabId !== tabId ||
      currentState.url !== url ||
      currentState.createdAt !== createdAt ||
      normalizedAppName.length <= 0 ||
      currentState.appName === normalizedAppName) {
      return undefined;
    }
    return {
      visible: currentState.visible,
      tabId: currentState.tabId,
      url: currentState.url,
      sourcePageUrl: currentState.sourcePageUrl,
      title: `此网站请求打开 ${normalizedAppName}`,
      subtitle: currentState.subtitle,
      appName: normalizedAppName,
      originLabel: currentState.originLabel,
      iconUri: currentState.iconUri,
      favicon: currentState.favicon,
      trigger: currentState.trigger,
      createdAt: currentState.createdAt
    };
  }

  private buildPromptIconUriStateUpdate(
    currentState: ExternalNavigationPromptState,
    tabId: string,
    url: string,
    createdAt: number,
    iconUri: string
  ): ExternalNavigationPromptState | undefined {
    if (!currentState.visible ||
      currentState.tabId !== tabId ||
      currentState.url !== url ||
      currentState.createdAt !== createdAt) {
      return undefined;
    }
    return {
      visible: currentState.visible,
      tabId: currentState.tabId,
      url: currentState.url,
      sourcePageUrl: currentState.sourcePageUrl,
      title: currentState.title,
      subtitle: currentState.subtitle,
      appName: currentState.appName,
      originLabel: currentState.originLabel,
      iconUri: iconUri,
      favicon: currentState.favicon,
      trigger: currentState.trigger,
      createdAt: currentState.createdAt
    };
  }

  private resolveImmediateSiteIconUri(origin: string): string {
    return this.siteIconService.peekUri(origin);
  }

  private hydrateCachedSiteIconUri(
    origin: string,
    request: BrowserExternalNavigationInfoBarPromptRequest,
    currentIconUri: string
  ): void {
    const normalizedOrigin = origin.trim();
    if (normalizedOrigin.length <= 0) {
      return;
    }
    void this.siteIconService.readCachedUri(normalizedOrigin).then((iconUri: string): void => {
      const normalizedIconUri = iconUri.trim();
      if (normalizedIconUri.length <= 0 || normalizedIconUri === currentIconUri.trim()) {
        return;
      }
      const nextState = this.buildPromptIconUriStateUpdate(
        this.promptState,
        request.tabId,
        request.url,
        request.createdAt,
        normalizedIconUri
      );
      if (nextState !== undefined) {
        this.publishPromptState(nextState);
      }
    }).catch((_error: Error): void => {
    });
  }

  private hydratePromptPresentation(
    origin: string,
    request: BrowserExternalNavigationInfoBarPromptRequest,
    promptId: string,
    currentIconUri: string
  ): void {
    void this.externalNavigationPolicyService.resolveTargetAppName(request.url)
      .then((appName: string): void => {
        if (this.activeExternalNavigationPromptId !== promptId) {
          return;
        }
        const nextState = this.buildPromptAppNameStateUpdate(
          this.promptState,
          request.tabId,
          request.url,
          request.createdAt,
          appName
        );
        if (nextState !== undefined) {
          this.publishPromptState(nextState);
        }
        this.hydrateCachedSiteIconUri(origin, request, currentIconUri);
      })
      .catch((_error: Error): void => {
        if (this.activeExternalNavigationPromptId !== promptId) {
          return;
        }
        this.hydrateCachedSiteIconUri(origin, request, currentIconUri);
      });
  }

  private async applySideEffects(
    plan: BrowserExternalNavigationInfoBarDecisionPlan,
    now: number
  ): Promise<void> {
    if (plan.action === 'none') {
      return;
    }
    if (plan.action === 'open_external') {
      await this.executeExternalLinkOpen(plan.tabId, plan.url);
      return;
    }
    this.rememberCancel(plan.tabId, plan.url, now);
  }

  private rememberCancel(tabId: string, url: string, now: number): void {
    const settings = this.preferencesRepository.getPreferences().externalNavigation;
    const record = this.externalNavigationPolicyService.buildSuppressionRecord(
      this.tabScopedEventContextCoordinator.resolveSiteOrigin(tabId),
      url,
      now,
      settings.suppressAfterCancelMs
    );
    this.externalNavigationRuntimeStateCoordinator.replaceSuppressionRecords(
      this.externalNavigationPolicyService.upsertSuppressionRecord(
        this.externalNavigationRuntimeStateCoordinator.resolveSuppressionRecords(),
        record
      )
    );
  }

  private async executeExternalLinkOpenAfterPreflight(tabId: string, url: string): Promise<void> {
    try {
      const preflight = await this.externalNavigationPolicyService.resolvePromptPreflight(url);
      if (preflight.action === 'show_unavailable_message') {
        this.showPreflightUnavailable(tabId, url, preflight);
        return;
      }
    } catch (_error) {
    }
    await this.executeExternalLinkOpen(tabId, url);
  }

  private async executeExternalLinkOpen(tabId: string, url: string): Promise<void> {
    this.recentActionManager.reset();
    const result = await this.shell.openExternalLink(url);
    if (result.success) {
      this.shell.setExternalNavigationHelperMessage(
        result.userMessage.length > 0 ? result.userMessage : result.message
      );
      return;
    }
    const failureMessage = result.userMessage.length > 0 ? result.userMessage : result.message;
    const fault = this.faultClassifier.classifyExternalNavigationFailure(failureMessage);
    this.shell.setExternalNavigationErrorMessage(fault.userMessage);
    this.shell.showToast(fault.userMessage);
  }

  private showPreflightUnavailable(
    tabId: string,
    url: string,
    preflight: ExternalNavigationPromptPreflightResult
  ): void {
    this.shell.setExternalNavigationErrorMessage(preflight.message);
    this.shell.showToast(preflight.message);
  }
}
