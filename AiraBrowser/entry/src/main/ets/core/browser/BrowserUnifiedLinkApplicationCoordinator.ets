import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { ExternalNavigationPolicyService } from '../../services/web/ExternalNavigationPolicyService';
import {
  BrowserUnifiedLinkAction,
  BrowserUnifiedLinkResult
} from '../../services/web/BrowserUnifiedLinkLogic';
import { SiteIconService } from '../../services/siteicons/SiteIconService';
import { BrowserRecentActionManager } from '../web/BrowserRecentActionManager';
import {
  BrowserExternalNavigationInfoBarApplicationCoordinator,
  BrowserExternalNavigationInfoBarApplicationShell,
  BrowserExternalNavigationInfoBarPromptRequest,
  BrowserExternalNavigationPromptUserAction as BrowserExternalNavigationInfoBarUserAction
} from './BrowserExternalNavigationInfoBarApplicationCoordinator';
import { BrowserExternalNavigationRuntimeStateCoordinator } from './BrowserExternalNavigationRuntimeStateCoordinator';
import { BrowserFaultClassifier } from './BrowserFaultClassifier';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  ExternalNavigationPromptPageContext,
  ExternalNavigationPromptPageContextInput,
  ExternalNavigationPromptState
} from './ExternalNavigationPromptViewModel';

type BrowserUnifiedLinkApplicationAction =
  'none' |
  'record_block_and_toast' |
  'record_allow_and_open_external' |
  'record_deny' |
  'record_prompt_and_show_info_bar' |
  'load_fallback_in_web';

type BrowserUnifiedLinkApplicationPolicyAction =
  'allow' |
  'block' |
  'prompt' |
  'deny';

interface BrowserUnifiedLinkApplicationPlan {
  action: BrowserUnifiedLinkApplicationAction;
  policyAction: BrowserUnifiedLinkApplicationPolicyAction;
  tabId: string;
  url: string;
  appName: string;
  message: string;
  allowed: boolean;
  shouldShowToast: boolean;
  shouldOpenExternal: boolean;
  shouldShowInfoBar: boolean;
  fallbackUrl: string;
  createdAt: number;
}

export type BrowserExternalNavigationPromptUserAction = BrowserExternalNavigationInfoBarUserAction;

export type BrowserUnifiedLinkApplicationShell = BrowserExternalNavigationInfoBarApplicationShell;

interface BrowserUnifiedLinkApplicationCoordinatorDependencies {
  externalNavigationPolicyService: ExternalNavigationPolicyService;
  externalNavigationRuntimeStateCoordinator: BrowserExternalNavigationRuntimeStateCoordinator;
  faultClassifier: BrowserFaultClassifier;
  preferencesRepository: PreferencesRepository;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  recentActionManager: BrowserRecentActionManager;
  siteIconService?: SiteIconService;
}

const EMPTY_APPLICATION_PLAN: BrowserUnifiedLinkApplicationPlan = {
  action: 'none',
  policyAction: 'deny',
  tabId: '',
  url: '',
  appName: '',
  message: '',
  allowed: false,
  shouldShowToast: false,
  shouldOpenExternal: false,
  shouldShowInfoBar: false,
  fallbackUrl: '',
  createdAt: 0
};

export class BrowserUnifiedLinkApplicationCoordinator {
  private readonly shell: BrowserUnifiedLinkApplicationShell;
  private readonly infoBarApplicationCoordinator: BrowserExternalNavigationInfoBarApplicationCoordinator;

  constructor(
    dependencies: BrowserUnifiedLinkApplicationCoordinatorDependencies,
    shell: BrowserUnifiedLinkApplicationShell
  ) {
    this.shell = shell;
    this.infoBarApplicationCoordinator = new BrowserExternalNavigationInfoBarApplicationCoordinator({
      externalNavigationRuntimeStateCoordinator: dependencies.externalNavigationRuntimeStateCoordinator,
      faultClassifier: dependencies.faultClassifier,
      preferencesRepository: dependencies.preferencesRepository,
      tabScopedEventContextCoordinator: dependencies.tabScopedEventContextCoordinator,
      recentActionManager: dependencies.recentActionManager,
      externalNavigationPolicyService: dependencies.externalNavigationPolicyService,
      siteIconService: dependencies.siteIconService
    }, shell);
  }

  createInitialPromptState(): ExternalNavigationPromptState {
    return this.infoBarApplicationCoordinator.createInitialPromptState();
  }

  applyResult(result: BrowserUnifiedLinkResult, createdAt: number = Date.now()): void {
    this.applyPlan(this.buildPlan(result, createdAt));
  }

  requestExternalNavigationPrompt(request: BrowserExternalNavigationInfoBarPromptRequest): void {
    void this.infoBarApplicationCoordinator.showPromptAfterPreflight(request);
  }

  handleExternalNavigationPromptAction(action: BrowserExternalNavigationPromptUserAction): void {
    this.infoBarApplicationCoordinator.handleUserAction(action);
  }

  buildExternalNavigationPromptPageContext(
    input: ExternalNavigationPromptPageContextInput
  ): ExternalNavigationPromptPageContext {
    return this.infoBarApplicationCoordinator.buildPageContext(input);
  }

  reconcileExternalNavigationPromptForPageContext(context: ExternalNavigationPromptPageContext): void {
    this.infoBarApplicationCoordinator.handlePageContextChanged(context);
  }

  private buildPlan(
    result: BrowserUnifiedLinkResult,
    createdAt: number
  ): BrowserUnifiedLinkApplicationPlan {
    if (!result.handled || result.action === 'allow_web') {
      return EMPTY_APPLICATION_PLAN;
    }
    switch (result.action) {
      case 'consume_security_block':
        return this.buildRecordPlan(result, 'record_block_and_toast', 'block', false, true, createdAt);
      case 'open_external':
        return this.buildRecordPlan(result, 'record_allow_and_open_external', 'allow', true, false, createdAt);
      case 'deny':
        return this.buildRecordPlan(
          result,
          'record_deny',
          'block',
          false,
          result.reason !== 'external_policy_suppressed',
          createdAt
        );
      case 'show_info_bar':
        return this.buildRecordPlan(
          result,
          'record_prompt_and_show_info_bar',
          'prompt',
          true,
          false,
          createdAt,
          `请求外跳到 ${result.appName}`
        );
      case 'load_fallback_in_web':
        return {
          action: 'load_fallback_in_web',
          policyAction: 'deny',
          tabId: result.tabId,
          url: result.url,
          appName: result.appName,
          message: result.message,
          allowed: false,
          shouldShowToast: false,
          shouldOpenExternal: false,
          shouldShowInfoBar: false,
          fallbackUrl: result.fallbackUrl,
          createdAt: createdAt
        };
      default:
        return EMPTY_APPLICATION_PLAN;
    }
  }

  private applyPlan(plan: BrowserUnifiedLinkApplicationPlan): void {
    if (plan.action === 'none') {
      return;
    }
    if (plan.action === 'load_fallback_in_web') {
      return;
    }
    if (plan.shouldShowInfoBar) {
      this.requestExternalNavigationPrompt({
        tabId: plan.tabId,
        url: plan.url,
        appName: plan.appName,
        createdAt: plan.createdAt
      });
      return;
    }
    if (plan.shouldShowToast) {
      this.shell.showToast(plan.message);
    }
    if (plan.shouldOpenExternal) {
      this.infoBarApplicationCoordinator.openExternalLinkForTab(plan.tabId, plan.url);
    }
  }

  private buildRecordPlan(
    result: BrowserUnifiedLinkResult,
    action: BrowserUnifiedLinkApplicationAction,
    policyAction: BrowserUnifiedLinkApplicationPolicyAction,
    allowed: boolean,
    shouldShowToast: boolean,
    createdAt: number,
    messageOverride: string = ''
  ): BrowserUnifiedLinkApplicationPlan {
    const normalizedAction = result.action as BrowserUnifiedLinkAction;
    return {
      action: action,
      policyAction: policyAction,
      tabId: result.tabId,
      url: result.url,
      appName: result.appName,
      message: messageOverride.length > 0 ? messageOverride : result.message,
      allowed: allowed,
      shouldShowToast: shouldShowToast,
      shouldOpenExternal: normalizedAction === 'open_external',
      shouldShowInfoBar: normalizedAction === 'show_info_bar',
      fallbackUrl: result.fallbackUrl,
      createdAt: createdAt
    };
  }
}
