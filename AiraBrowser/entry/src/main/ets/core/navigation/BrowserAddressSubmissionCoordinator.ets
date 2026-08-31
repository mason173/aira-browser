import {
  BrowserDataBoundaryInput,
  BrowserExperimentSettings,
  ExternalAppSearchTargetId,
  SearchEngineId,
  SearchEngineRecord,
  SearchEngineSettings,
  SearchSuggestionPreferences
} from '../../common/models/BrowserModels';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserCreateTabOptions } from '../tabs/TabManager';
import { BrowserAppUrlOpenCoordinator } from '../browser/BrowserAppUrlOpenCoordinator';
import {
  SearchEngineRoutingMode,
  SearchEngineRoutingResult,
  SearchEngineRoutingService
} from '../../services/search/SearchEngineRoutingService';
import { SearchEngineFallbackRetryAction } from '../../services/search/SearchEngineFallbackRetryService';
import {
  ExternalAppSearchAction,
  ExternalAppSearchPrivateConfirmation,
  ExternalAppSearchService
} from '../../services/search/ExternalAppSearchService';
import {
  ExternalNavigationLaunchRequest,
  ExternalNavigationLaunchResult,
  ExternalNavigationLaunchService,
  ExternalNavigationTargetElement
} from '../../services/web/ExternalNavigationLaunchService';
import { BrowserAddressDisplayCoordinator } from '../browser/BrowserAddressDisplayCoordinator';
import { BrowserQuickSearchSubmissionRecorder } from '../search/BrowserQuickSearchSwitchingCoordinator';
import {
  sharedBrowserHttpsFirstNavigationService
} from '../../services/web/BrowserHttpsFirstNavigationService';

type BrowserAddressSubmissionIntent = 'empty' | 'navigate' | 'search';

interface BrowserAddressSubmissionInput {
  rawInput: string;
  searchEngine: SearchEngineId;
  availableSearchEngines: SearchEngineRecord[];
  searchEngineSettings: SearchEngineSettings;
  routingMode?: SearchEngineRoutingMode;
  experiments?: BrowserExperimentSettings;
  maxProbeWaitMs?: number;
}

interface BrowserAddressSubmissionSessionContext {
  boundary: BrowserCreateTabOptions;
  searchSuggestionPreferences: SearchSuggestionPreferences;
}

interface BrowserAddressSubmissionExecutionInput
  extends BrowserAddressSubmissionInput, BrowserAddressSubmissionSessionContext {
}

interface BrowserExternalAppSearchInput extends BrowserAddressSubmissionSessionContext {
  targetId: ExternalAppSearchTargetId;
  rawQuery: string;
  searchEngineId: SearchEngineId;
  abilityContext: common.UIAbilityContext;
}

export interface BrowserAddressSubmissionResult {
  rawInput: string;
  submittedText: string;
  resolvedUrl: string;
  intent: BrowserAddressSubmissionIntent;
  searchQuery: string;
  searchEngineId: SearchEngineId;
  primarySearchEngineId: SearchEngineId;
  fallbackApplied: boolean;
  fallbackMessage: string;
  httpFallbackUrl: string;
}

export interface BrowserAddressSubmissionHistoryRecordInput {
  submission: BrowserAddressSubmissionResult;
  boundary: BrowserCreateTabOptions;
  preferences: SearchSuggestionPreferences;
}

export interface BrowserAddressSubmissionHistoryRecorder {
  recordSubmittedSearch(input: BrowserAddressSubmissionHistoryRecordInput): Promise<boolean>;
}

export interface BrowserAddressSubmissionPresentation {
  helperMessage: string;
  errorMessage: string;
  toastMessage: string;
}

export interface BrowserAddressSubmissionSessionFacts {
  availableSearchEngines: SearchEngineRecord[];
  searchEngineSettings: SearchEngineSettings;
  experiments: BrowserExperimentSettings;
  boundary: BrowserCreateTabOptions;
  searchSuggestionPreferences: SearchSuggestionPreferences;
  abilityContext: common.UIAbilityContext;
}

export interface BrowserAddressSubmissionShell {
  resolveSessionFacts: () => BrowserAddressSubmissionSessionFacts;
  prepareForNavigation: () => void;
  completeSearchSession: () => void;
  present: (presentation: BrowserAddressSubmissionPresentation) => void;
  confirmPrivateExternalSearch: (presentation: ExternalAppSearchPrivateConfirmation) => Promise<boolean>;
}

export class BrowserAddressSubmissionCoordinator {
  private readonly routingService: SearchEngineRoutingService;
  private readonly historyRecorder?: BrowserAddressSubmissionHistoryRecorder;
  private readonly addressDisplayCoordinator: BrowserAddressDisplayCoordinator;
  private readonly externalAppSearchService: ExternalAppSearchService;
  private readonly externalNavigationLaunchService: ExternalNavigationLaunchService;
  private readonly appUrlOpenCoordinator?: BrowserAppUrlOpenCoordinator;
  private readonly quickSearchSubmissionRecorder?: BrowserQuickSearchSubmissionRecorder;
  private readonly shell: BrowserAddressSubmissionShell;
  private submissionGeneration: number = 0;
  private diagnosticSubmissionSequence: number = 0;

  constructor(
    shell: BrowserAddressSubmissionShell,
    routingService: SearchEngineRoutingService = new SearchEngineRoutingService(),
    historyRecorder?: BrowserAddressSubmissionHistoryRecorder,
    addressDisplayCoordinator: BrowserAddressDisplayCoordinator = new BrowserAddressDisplayCoordinator(),
    appUrlOpenCoordinator?: BrowserAppUrlOpenCoordinator,
    quickSearchSubmissionRecorder?: BrowserQuickSearchSubmissionRecorder,
    externalAppSearchService: ExternalAppSearchService = new ExternalAppSearchService(),
    externalNavigationLaunchService: ExternalNavigationLaunchService = new ExternalNavigationLaunchService()
  ) {
    this.routingService = routingService;
    this.historyRecorder = historyRecorder;
    this.addressDisplayCoordinator = addressDisplayCoordinator;
    this.appUrlOpenCoordinator = appUrlOpenCoordinator;
    this.externalAppSearchService = externalAppSearchService;
    this.externalNavigationLaunchService = externalNavigationLaunchService;
    this.quickSearchSubmissionRecorder = quickSearchSubmissionRecorder;
    this.shell = shell;
  }

  async submitAddress(
    rawInput: string,
    searchEngine: SearchEngineId,
    routingMode: SearchEngineRoutingMode = 'configured',
    maxProbeWaitMs: number = 900
  ): Promise<void> {
    const diagnosticId = ++this.diagnosticSubmissionSequence;
    const diagnosticStartedAt = Date.now();
    hilog.info(
      0x0000,
      'HomeSearchDiag',
      '[DIAG-home-submit-20260828] submit_begin id=%{public}d inputLength=%{public}d engine=%{public}s routing=%{public}s',
      diagnosticId,
      rawInput.length,
      searchEngine,
      routingMode
    );
    const facts = this.shell.resolveSessionFacts();
    const input: BrowserAddressSubmissionExecutionInput = {
      rawInput: rawInput,
      searchEngine: searchEngine,
      availableSearchEngines: facts.availableSearchEngines,
      searchEngineSettings: facts.searchEngineSettings,
      routingMode: routingMode,
      experiments: facts.experiments,
      maxProbeWaitMs: maxProbeWaitMs,
      boundary: facts.boundary,
      searchSuggestionPreferences: facts.searchSuggestionPreferences
    };
    const effects = this.shell;
    const generation = this.beginSubmission();
    let submission: BrowserAddressSubmissionResult;
    try {
      submission = await this.resolveSubmission(input);
    } catch (_error) {
      hilog.error(
        0x0000,
        'HomeSearchDiag',
        '[DIAG-home-submit-20260828] resolve_error id=%{public}d elapsedMs=%{public}d',
        diagnosticId,
        Date.now() - diagnosticStartedAt
      );
      if (this.isCurrentSubmission(generation)) {
        this.presentMessage(effects, '地址解析失败，请稍后重试。');
      }
      return;
    }
    hilog.info(
      0x0000,
      'HomeSearchDiag',
      '[DIAG-home-submit-20260828] resolve_end id=%{public}d elapsedMs=%{public}d intent=%{public}s resolvedLength=%{public}d fallback=%{public}s',
      diagnosticId,
      Date.now() - diagnosticStartedAt,
      submission.intent,
      submission.resolvedUrl.length,
      submission.fallbackApplied ? 'true' : 'false'
    );
    if (!this.isCurrentSubmission(generation)) {
      hilog.info(
        0x0000,
        'HomeSearchDiag',
        '[DIAG-home-submit-20260828] submit_stale id=%{public}d elapsedMs=%{public}d',
        diagnosticId,
        Date.now() - diagnosticStartedAt
      );
      return;
    }
    this.quickSearchSubmissionRecorder?.recordAddressSubmission({
      intent: submission.intent,
      query: submission.searchQuery,
      searchEngineId: submission.searchEngineId,
      resolvedUrl: submission.resolvedUrl
    });
    if (submission.resolvedUrl.length === 0) {
      this.presentMessage(effects, '先输入一个网址或搜索词。');
      return;
    }

    const helperMessage = submission.fallbackApplied && submission.fallbackMessage.length > 0
      ? submission.fallbackMessage
      : '准备打开页面';
    this.recordSubmittedSearchQuery(
      submission,
      input.boundary,
      input.searchSuggestionPreferences
    );
    this.recordAddressDisplaySubmission(submission);
    effects.prepareForNavigation();
    effects.present({
      helperMessage: helperMessage,
      errorMessage: '',
      toastMessage: submission.fallbackApplied ? submission.fallbackMessage : ''
    });
    this.openResolvedUrl(submission.resolvedUrl, helperMessage, input.boundary, submission.httpFallbackUrl);
    hilog.info(
      0x0000,
      'HomeSearchDiag',
      '[DIAG-home-submit-20260828] open_requested id=%{public}d totalMs=%{public}d intent=%{public}s',
      diagnosticId,
      Date.now() - diagnosticStartedAt,
      submission.intent
    );
  }

  async submitExternalAppSearch(
    targetId: ExternalAppSearchTargetId,
    rawQuery: string,
    searchEngineId: SearchEngineId
  ): Promise<void> {
    const facts = this.shell.resolveSessionFacts();
    const input: BrowserExternalAppSearchInput = {
      targetId: targetId,
      rawQuery: rawQuery,
      searchEngineId: searchEngineId,
      boundary: facts.boundary,
      searchSuggestionPreferences: facts.searchSuggestionPreferences,
      abilityContext: facts.abilityContext
    };
    const effects = this.shell;
    const action = this.externalAppSearchService.buildAction(input.targetId, input.rawQuery);
    if (action === undefined) {
      this.presentMessage(effects, '先输入一个搜索词。');
      return;
    }
    const generation = this.beginSubmission();
    if (this.requiresPrivateExternalSearchConfirmation(input.boundary)) {
      const confirmed = await effects.confirmPrivateExternalSearch(
        this.externalAppSearchService.buildPrivateConfirmation(action.target)
      );
      if (!confirmed || !this.isCurrentSubmission(generation)) {
        return;
      }
    }
    if (!this.isCurrentSubmission(generation)) {
      return;
    }

    this.recordExternalSearchQuery(action, input);
    effects.prepareForNavigation();
    if (action.openMode === 'current_tab_web') {
      this.openExternalSearchInCurrentTab(action, input, effects);
      return;
    }
    let result: ExternalNavigationLaunchResult;
    try {
      const launchRequest: ExternalNavigationLaunchRequest = {
        url: action.nativeUrl,
        source: 'external_app_search',
        userTriggered: true,
        hideFailureTipDialog: true,
        redactDiagnostics: true
      };
      if (action.nativeTarget !== undefined) {
        const targetElement: ExternalNavigationTargetElement = {
          bundleName: action.nativeTarget.bundleName,
          moduleName: action.nativeTarget.moduleName,
          abilityName: action.nativeTarget.abilityName
        };
        launchRequest.targetElement = targetElement;
        if (action.nativeTarget.action !== undefined) {
          launchRequest.action = action.nativeTarget.action;
        }
      }
      result = await this.externalNavigationLaunchService.openExternalLink(
        input.abilityContext,
        launchRequest
      );
    } catch (_error) {
      if (this.isCurrentSubmission(generation)) {
        this.openExternalSearchFallback(action, input, effects, 'launch_exception', '');
      }
      return;
    }
    if (!this.isCurrentSubmission(generation)) {
      return;
    }
    if (result.success) {
      this.presentMessage(effects, `已交给${action.target.title}处理。`);
      return;
    }
    this.openExternalSearchFallback(action, input, effects, result.status, result.errorCode);
  }

  private async resolveSubmission(input: BrowserAddressSubmissionExecutionInput): Promise<BrowserAddressSubmissionResult> {
    const submittedText = input.rawInput.trim();
    if (submittedText.length === 0) {
      return this.buildResult(input, submittedText, '', 'empty', '');
    }
    const routed = await this.routingService.resolve({
      rawInput: input.rawInput,
      selectedSearchEngineId: input.searchEngine,
      settings: input.searchEngineSettings,
      availableSearchEngines: input.availableSearchEngines,
      routingMode: input.routingMode,
      experiments: input.experiments,
      maxProbeWaitMs: input.maxProbeWaitMs,
      boundary: {
        dataScope: input.boundary.dataScope,
        privacyMode: input.boundary.privacyMode
      }
    });
    const result = this.buildResultFromRouting(routed);
    const fallbackBoundary: BrowserDataBoundaryInput = {
      profileId: input.boundary.profileId,
      privacyMode: input.boundary.privacyMode,
      dataScope: input.boundary.dataScope
    };
    const rememberedHttpFallbackUrl = sharedBrowserHttpsFirstNavigationService.resolveRememberedHttpFallbackUrl(
      result.httpFallbackUrl,
      fallbackBoundary
    );
    if (rememberedHttpFallbackUrl.length > 0) {
      result.resolvedUrl = rememberedHttpFallbackUrl;
      result.httpFallbackUrl = '';
    }
    return result;
  }

  static buildFallbackRetrySubmission(
    action: SearchEngineFallbackRetryAction,
    primarySearchEngineId: SearchEngineId
  ): BrowserAddressSubmissionResult {
    return {
      rawInput: action.query,
      submittedText: action.query,
      resolvedUrl: action.fallbackSearchUrl,
      intent: 'search',
      searchQuery: action.query,
      searchEngineId: action.fallbackEngineId,
      primarySearchEngineId: primarySearchEngineId,
      fallbackApplied: true,
      fallbackMessage: '',
      httpFallbackUrl: ''
    };
  }

  consumeAutomaticSearchFallback(action: SearchEngineFallbackRetryAction): boolean {
    return this.routingService.consumeLoadFailureFallback({
      primarySearchEngineId: action.primaryEngineId,
      query: action.query
    });
  }

  openAutomaticSearchFallback(action: SearchEngineFallbackRetryAction): void {
    const facts = this.shell.resolveSessionFacts();
    const submission = BrowserAddressSubmissionCoordinator.buildFallbackRetrySubmission(
      action,
      action.primaryEngineId
    );
    const helperMessage = `正在使用${action.fallbackEngineName}搜索`;
    const fallbackMessage = this.routingService.buildFallbackNotice({
      primarySearchEngineId: action.primaryEngineId,
      primarySearchEngineName: action.primaryEngineName,
      fallbackSearchEngineId: action.fallbackEngineId,
      fallbackSearchEngineName: action.fallbackEngineName,
      noticeEnabled: facts.searchEngineSettings.fallbackSearch.noticeEnabled !== false
    });
    this.quickSearchSubmissionRecorder?.recordAddressSubmission({
      intent: submission.intent,
      query: submission.searchQuery,
      searchEngineId: submission.searchEngineId,
      resolvedUrl: submission.resolvedUrl
    });
    this.recordSubmittedSearchQuery(
      submission,
      facts.boundary,
      facts.searchSuggestionPreferences
    );
    this.recordAddressDisplaySubmission(submission);
    this.shell.prepareForNavigation();
    this.shell.present({
      helperMessage: helperMessage,
      errorMessage: '',
      toastMessage: fallbackMessage
    });
    this.openResolvedUrl(action.fallbackSearchUrl, helperMessage, facts.boundary);
  }

  recordSubmittedSearchHistory(
    input: BrowserAddressSubmissionHistoryRecordInput
  ): void {
    if (this.historyRecorder === undefined) {
      return;
    }
    this.historyRecorder.recordSubmittedSearch(input)
      .catch((_error: Error) => {});
  }

  private beginSubmission(): number {
    this.submissionGeneration += 1;
    return this.submissionGeneration;
  }

  private isCurrentSubmission(generation: number): boolean {
    return generation === this.submissionGeneration;
  }

  private requiresPrivateExternalSearchConfirmation(boundary: BrowserCreateTabOptions): boolean {
    return boundary.privacyMode === 'private' || boundary.dataScope === 'session_ephemeral';
  }

  private recordSubmittedSearchQuery(
    submission: BrowserAddressSubmissionResult,
    boundary: BrowserCreateTabOptions,
    preferences: SearchSuggestionPreferences
  ): void {
    this.recordSubmittedSearchHistory({
      submission: submission,
      boundary: boundary,
      preferences: preferences
    });
  }

  private recordExternalSearchQuery(
    action: ExternalAppSearchAction,
    input: BrowserExternalAppSearchInput
  ): void {
    this.recordSubmittedSearchQuery({
      rawInput: action.query,
      submittedText: action.query,
      resolvedUrl: action.fallbackUrl,
      intent: 'search',
      searchQuery: action.query,
      searchEngineId: input.searchEngineId,
      primarySearchEngineId: input.searchEngineId,
      fallbackApplied: false,
      fallbackMessage: '',
      httpFallbackUrl: ''
    }, input.boundary, input.searchSuggestionPreferences);
  }

  private openExternalSearchFallback(
    action: ExternalAppSearchAction,
    input: BrowserExternalAppSearchInput,
    effects: BrowserAddressSubmissionShell,
    status: string,
    errorCode: string
  ): void {
    const helperMessage = `未能打开${action.target.title}，已在 Aira 中搜索。`;
    effects.completeSearchSession();
    this.addressDisplayCoordinator.recordSubmission({
      submittedText: action.query,
      resolvedUrl: action.fallbackUrl,
      intent: 'search'
    });
    effects.present({
      helperMessage: helperMessage,
      errorMessage: '',
      toastMessage: helperMessage
    });
    this.openResolvedUrl(action.fallbackUrl, helperMessage, input.boundary);
  }

  private openExternalSearchInCurrentTab(
    action: ExternalAppSearchAction,
    input: BrowserExternalAppSearchInput,
    effects: BrowserAddressSubmissionShell
  ): void {
    const helperMessage = `已在 Aira 中打开${action.target.title}网页搜索。`;
    effects.completeSearchSession();
    this.addressDisplayCoordinator.recordSubmission({
      submittedText: action.query,
      resolvedUrl: action.fallbackUrl,
      intent: 'search'
    });
    effects.present({
      helperMessage: helperMessage,
      errorMessage: '',
      toastMessage: ''
    });
    this.openResolvedUrl(action.fallbackUrl, helperMessage, input.boundary);
  }

  private presentMessage(effects: BrowserAddressSubmissionShell, helperMessage: string): void {
    effects.present({
      helperMessage: helperMessage,
      errorMessage: '',
      toastMessage: ''
    });
  }

  private recordAddressDisplaySubmission(submission: BrowserAddressSubmissionResult): void {
    this.addressDisplayCoordinator.recordSubmission({
      submittedText: submission.submittedText,
      resolvedUrl: submission.resolvedUrl,
      intent: submission.intent === 'search' ? 'search' : 'navigate'
    });
  }

  private openResolvedUrl(
    resolvedUrl: string,
    helperMessage: string,
    boundary: BrowserCreateTabOptions,
    httpFallbackUrl: string = ''
  ): void {
    if (this.appUrlOpenCoordinator === undefined) {
      return;
    }
    this.appUrlOpenCoordinator.openCurrentAppUi(
      resolvedUrl,
      helperMessage,
      boundary,
      resolvedUrl,
      httpFallbackUrl
    );
  }

  private buildResult(
    input: BrowserAddressSubmissionInput,
    submittedText: string,
    resolvedUrl: string,
    intent: BrowserAddressSubmissionIntent,
    searchQuery: string
  ): BrowserAddressSubmissionResult {
    return {
      rawInput: input.rawInput,
      submittedText: submittedText,
      resolvedUrl: resolvedUrl,
      intent: intent,
      searchQuery: searchQuery,
      searchEngineId: input.searchEngine,
      primarySearchEngineId: input.searchEngine,
      fallbackApplied: false,
      fallbackMessage: '',
      httpFallbackUrl: ''
    };
  }

  private buildResultFromRouting(routed: SearchEngineRoutingResult): BrowserAddressSubmissionResult {
    return {
      rawInput: routed.rawInput,
      submittedText: routed.submittedText,
      resolvedUrl: routed.resolvedUrl,
      intent: routed.intent,
      searchQuery: routed.searchQuery,
      searchEngineId: routed.searchEngineId,
      primarySearchEngineId: routed.primarySearchEngineId,
      fallbackApplied: routed.fallbackApplied,
      fallbackMessage: routed.fallbackMessage,
      httpFallbackUrl: routed.httpFallbackUrl
    };
  }
}
