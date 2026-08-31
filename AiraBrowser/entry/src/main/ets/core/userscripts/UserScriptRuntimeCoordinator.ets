import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import urlUtils from '@ohos.url';
import {
  UserScriptRuntimeExecutionResultInput,
  UserScriptRuntimeSkippedResultInput,
  UserScriptRuntimeStateRepository
} from '../../data/userscripts/UserScriptRuntimeStateRepository';
import { UserScriptValueStateStore } from '../../data/userscripts/UserScriptValueStateStore';
import {
  cloneInstalledUserScriptState,
  InstalledUserScriptState,
  UserScriptResourceRecord,
  UserScriptRunAt
} from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptRuntimeStateRecord } from '../../features/userscripts/UserScriptRuntimeStateModels';
import {
  UserScriptExecutionReport,
  UserScriptInjectionSummary,
  UserScriptPageActionsState,
  UserScriptPageMenuCommandView,
  UserScriptRuntimeEligibility
} from '../../features/userscripts/UserScriptRuntimeModels';
import {
  UserScriptInjectionRequest,
  UserScriptInjectionService
} from '../../services/userscripts/UserScriptInjectionService';
import { UserScriptCapabilityContractService } from '../../services/userscripts/UserScriptCapabilityContractService';
import { UserScriptExecutionReportCodec } from '../../services/userscripts/UserScriptExecutionReportCodec';
import { normalizeUserScriptJavaScriptResult } from '../../services/userscripts/UserScriptJavaScriptResultCodec';
import { UserScriptMatchService } from '../../services/userscripts/UserScriptMatchService';
import { UserScriptUrlCompatibilityService } from '../../services/userscripts/UserScriptUrlCompatibilityService';
import {
  UserScriptRuntimeCompatibilityCommand,
  UserScriptRuntimeCompatibilityService
} from '../../services/userscripts/UserScriptRuntimeCompatibilityService';
import {
  UserScriptAutomaticDocumentSignal,
  UserScriptNativeBridgeCoordinator
} from './UserScriptNativeBridgeCoordinator';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { UserScriptPageActionsViewModel } from './UserScriptPageActionsViewModel';
import { UserScriptRuntimeReadinessCoordinator } from './UserScriptRuntimeReadinessCoordinator';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';

interface RawUserScriptMenuCommandResult {
  success?: boolean;
  errorMessage?: string;
}

interface UserScriptDocumentStartItemCacheEntry {
  apiOnly: boolean;
  artifactKey: string;
  bridgeToken: string;
  script: InstalledUserScriptState;
  valueSnapshotLiteral: string;
  item: ScriptItem;
}

interface UserScriptDocumentStartResolvedItem {
  key: string;
  item: ScriptItem;
}

interface UserScriptAutomaticDocumentState {
  documentToken: string;
  pageUrl: string;
  documentEndRunStarted: boolean;
  documentEndRunAttemptCount: number;
  documentIdleRunStarted: boolean;
  documentIdleRunAttemptCount: number;
}

interface UserScriptExecutionDurationSummary {
  measuredCount: number;
  totalMs: number;
  maxMs: number;
  documentStartMs: number;
  documentEndMs: number;
  documentIdleMs: number;
}

export interface UserScriptDocumentStartScriptBundle {
  items: ScriptItem[];
  key: string;
}

const USER_SCRIPT_RUNTIME_LOG_DOMAIN: number = 0x0000;
const USER_SCRIPT_RUNTIME_LOG_TAG: string = 'UserScriptRuntime';
const USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';
const USER_SCRIPT_PERF_DIAGNOSTIC_TAG: string = 'UserScriptPerfDiag';
const USER_SCRIPT_NO_REPORT_FAILURE: string = 'javascript-execution-failed-without-report';
const USER_SCRIPT_BATCH_NO_REPORT_FAILURE: string = 'javascript-batch-execution-failed-without-report';
const USER_SCRIPT_STALE_DOCUMENT_FAILURE: string = 'userscript-stale-document';
const USER_SCRIPT_STALE_DOCUMENT_RESULT: string = '{"staleDocument":true}';
const USER_SCRIPT_DOCUMENT_START_WARMUP_DELAY_MS: number = 280;
const USER_SCRIPT_AUTOMATIC_RUN_ATS: UserScriptRunAt[] = [
  'document-start',
  'document-end',
  'document-idle'
];
const USER_SCRIPT_ALWAYS_CURRENT_DOCUMENT: () => boolean = (): boolean => true;

export class UserScriptRuntimeCoordinator {
  private valueStore: UserScriptValueStateStore;
  private runtimeStateRepository: UserScriptRuntimeStateRepository;
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private matchService: UserScriptMatchService = new UserScriptMatchService();
  private urlCompatibilityService: UserScriptUrlCompatibilityService = new UserScriptUrlCompatibilityService();
  private injectionService: UserScriptInjectionService = new UserScriptInjectionService();
  private executionReportCodec: UserScriptExecutionReportCodec = new UserScriptExecutionReportCodec();
  private compatibilityService: UserScriptRuntimeCompatibilityService = new UserScriptRuntimeCompatibilityService();
  private nativeBridgeCoordinator: UserScriptNativeBridgeCoordinator;
  private pageActionsViewModel: UserScriptPageActionsViewModel;
  private readinessCoordinator: UserScriptRuntimeReadinessCoordinator;
  private runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  private preferencesRepository: PreferencesRepository;
  private documentIdentityInstallItemCache: ScriptItem | undefined = undefined;
  private documentStartRuntimeFactoryItemCache: ScriptItem | undefined = undefined;
  private documentStartItemCacheByScriptId:
    Record<string, UserScriptDocumentStartItemCacheEntry | undefined> = {};
  private documentEndPreparedSourceCache: Record<string, string | undefined> = {};
  private documentEndPreparedSourceCacheKey: Record<string, string | undefined> = {};
  private documentStartCacheHitCount: number = 0;
  private documentStartCacheMissCount: number = 0;
  private documentStartWarmupTimer: number = -1;
  private documentStartWarmupGeneration: number = 0;
  private automaticDocumentStateByTabId: Record<string, UserScriptAutomaticDocumentState | undefined> = {};
  private blockedAutomaticDocumentTabIds: Record<string, boolean | undefined> = {};

  constructor(
    valueStore: UserScriptValueStateStore,
    runtimeStateRepository: UserScriptRuntimeStateRepository,
    nativeBridgeCoordinator: UserScriptNativeBridgeCoordinator,
    pageActionsViewModel: UserScriptPageActionsViewModel,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    readinessCoordinator: UserScriptRuntimeReadinessCoordinator,
    preferencesRepository: PreferencesRepository
  ) {
    this.valueStore = valueStore;
    this.runtimeStateRepository = runtimeStateRepository;
    this.nativeBridgeCoordinator = nativeBridgeCoordinator;
    this.pageActionsViewModel = pageActionsViewModel;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.readinessCoordinator = readinessCoordinator;
    this.preferencesRepository = preferencesRepository;
    this.nativeBridgeCoordinator.setAutomaticDocumentSignalListener(
      (signal: UserScriptAutomaticDocumentSignal): void => {
        this.handleAutomaticDocumentSignal(signal);
      }
    );
  }

  createNativeBridge(
    controller: webview.WebviewController,
    tabId: string,
    resolveCurrentUrl: () => string
  ): Object {
    return this.nativeBridgeCoordinator.createBridge(controller, tabId, resolveCurrentUrl);
  }

  handleNativeDownloadTaskSnapshots(tasks: DownloadV2TaskEntity[]): void {
    this.nativeBridgeCoordinator.handleDownloadTaskSnapshots(tasks);
  }

  createInitialPageActionsState(): UserScriptPageActionsState {
    return this.pageActionsViewModel.createInitialState();
  }

  async buildPageActionsStateForPage(
    tabId: string,
    url: string,
    privateMode: boolean
  ): Promise<UserScriptPageActionsState> {
    const normalizedUrl = url.trim();
    return await this.pageActionsViewModel.buildState(
      normalizedUrl,
      this.runtimeLifecyclePort.resolveController(tabId),
      this.resolveEligibility(normalizedUrl, privateMode)
    );
  }

  async executePageCommandForPage(
    tabId: string,
    scriptId: string,
    commandId: string,
    url: string,
    privateMode: boolean
  ): Promise<boolean> {
    if (commandId.trim() === '__aira_run_script__') {
      return await this.executeManualScriptForPage(tabId, scriptId, url, privateMode);
    }
    return await this.executeMenuCommandForPage(tabId, scriptId, commandId, url, privateMode);
  }

  buildContextMenuCommands(url: string, privateMode: boolean): UserScriptPageMenuCommandView[] {
    const normalizedUrl = url.trim();
    if (normalizedUrl.length === 0) {
      return [];
    }
    const eligibility = this.resolveEligibility(normalizedUrl, privateMode);
    if (!eligibility.executionAllowed) {
      return [];
    }
    return this.pageActionsViewModel.buildContextMenuCommands(eligibility);
  }

  async injectForCurrentPage(
    _tabId: string,
    url: string,
    controller: webview.WebviewController | undefined,
    privateMode: boolean,
    runAts: UserScriptRunAt[] = USER_SCRIPT_AUTOMATIC_RUN_ATS,
    isCurrentDocument: () => boolean = USER_SCRIPT_ALWAYS_CURRENT_DOCUMENT,
    expectedDocumentToken: string = ''
  ): Promise<UserScriptInjectionSummary> {
    if (!isCurrentDocument()) {
      return this.emptySummary(url, 'stale_document');
    }
    const eligibilityStartedAt = Date.now();
    const eligibility = this.resolveEligibility(url, privateMode);
    const eligibilityElapsedMs = Date.now() - eligibilityStartedAt;
    const matchingScripts = eligibility.matchingScripts;
    const autoScripts = matchingScripts.filter((script: InstalledUserScriptState): boolean => {
      return USER_SCRIPT_AUTOMATIC_RUN_ATS.includes(script.runAt) && runAts.includes(script.runAt);
    });
    if (!eligibility.executionAllowed) {
      await this.recordSkippedScripts(autoScripts, url, eligibility.blockReason);
      return this.emptySummary(url, eligibility.blockReason);
    }
    if (controller === undefined) {
      await this.recordSkippedScripts(autoScripts, url, 'missing_controller');
      return this.emptySummary(url, 'missing_controller');
    }
    const documentEndScripts = autoScripts.filter((script: InstalledUserScriptState) => script.runAt === 'document-end');
    const documentIdleScripts = autoScripts.filter((script: InstalledUserScriptState) => script.runAt === 'document-idle');
    const documentStartScripts = autoScripts.filter((script: InstalledUserScriptState) => script.runAt === 'document-start');
    if (matchingScripts.length === 0) {
      return this.emptySummary(url, 'no_matching_scripts');
    }
    if (autoScripts.length === 0) {
      return this.emptySummary(url, 'no_matching_automatic_scripts_for_phase');
    }
    let reports = this.filterExecutionReportsForScripts(
      await this.readExecutionReports(controller, url, expectedDocumentToken),
      autoScripts
    );
    if (!isCurrentDocument()) {
      return this.emptySummary(url, 'stale_document');
    }
    const documentLifecycleScripts = documentStartScripts.concat(documentEndScripts);
    const documentLifecycleFallbackScripts = this.resolveMissingExecutionReports(
      documentLifecycleScripts,
      reports
    );
    if (documentLifecycleFallbackScripts.length > 0) {
      reports = reports.concat(
        await this.executeAutomaticScripts(
          documentLifecycleFallbackScripts,
          url,
          controller,
          isCurrentDocument,
          expectedDocumentToken
        )
      );
      if (!isCurrentDocument()) {
        return this.emptySummary(url, 'stale_document');
      }
    }
    let documentIdleFallbackCount = 0;
    if (documentIdleScripts.length > 0) {
      await this.delayDocumentIdleReportRead();
      if (!isCurrentDocument()) {
        return this.emptySummary(url, 'stale_document');
      }
      reports = reports.concat(this.filterExecutionReportsForScripts(
        await this.readExecutionReports(controller, url, expectedDocumentToken),
        documentIdleScripts
      ));
      const documentIdleFallbackScripts = this.resolveMissingExecutionReports(
        documentIdleScripts,
        reports
      );
      documentIdleFallbackCount = documentIdleFallbackScripts.length;
      if (documentIdleFallbackScripts.length > 0) {
        reports = reports.concat(
          await this.executeAutomaticScripts(
            documentIdleFallbackScripts,
            url,
            controller,
            isCurrentDocument,
            expectedDocumentToken
          )
        );
        if (!isCurrentDocument()) {
          return this.emptySummary(url, 'stale_document');
        }
      }
    }
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_RUNTIME_LOG_TAG,
      '[DIAG-userscript-lifecycle-20260814] start=%{public}d end=%{public}d idle=%{public}d reports=%{public}d documentFallback=%{public}d idleFallback=%{public}d host=%{public}s',
      documentStartScripts.length,
      documentEndScripts.length,
      documentIdleScripts.length,
      reports.length,
      documentLifecycleFallbackScripts.length,
      documentIdleFallbackCount,
      this.resolveLogHost(url)
    );
    reports = this.resolveLatestReports(reports);
    const scriptMap = this.buildScriptMap(autoScripts);
    const executionDuration = this.summarizeExecutionDuration(reports, scriptMap);
    const matchingStartProjectedRuleCount = this.countProjectedRulesForScripts(documentStartScripts);
    const matchingStartProjectedRuleMax = this.maxProjectedRulesForScripts(documentStartScripts);
    const matchingStartWildcardCount = documentStartScripts.filter((script: InstalledUserScriptState): boolean => {
      return this.isWildcardOnlyRules(this.urlCompatibilityService.expandRunAtRules(script));
    }).length;
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_PERF_DIAGNOSTIC_TAG,
      '[DIAG-userscript-perf-20260828] phase=post_paint host=%{public}s matching=%{public}d matchingMs=%{public}d automatic=%{public}d startProjectedRules=%{public}d startProjectedMax=%{public}d startWildcard=%{public}d sourceChars=%{public}d startChars=%{public}d endChars=%{public}d idleChars=%{public}d reports=%{public}d measured=%{public}d execTotalMs=%{public}d execMaxMs=%{public}d startExecMs=%{public}d endExecMs=%{public}d idleExecMs=%{public}d fallback=%{public}d',
      this.resolveLogHost(url),
      matchingScripts.length,
      eligibilityElapsedMs,
      autoScripts.length,
      matchingStartProjectedRuleCount,
      matchingStartProjectedRuleMax,
      matchingStartWildcardCount,
      this.sumScriptPayloadChars(autoScripts),
      this.sumScriptPayloadChars(autoScripts.filter((script: InstalledUserScriptState): boolean => script.runAt === 'document-start')),
      this.sumScriptPayloadChars(autoScripts.filter((script: InstalledUserScriptState): boolean => script.runAt === 'document-end')),
      this.sumScriptPayloadChars(autoScripts.filter((script: InstalledUserScriptState): boolean => script.runAt === 'document-idle')),
      reports.length,
      executionDuration.measuredCount,
      executionDuration.totalMs,
      executionDuration.maxMs,
      executionDuration.documentStartMs,
      executionDuration.documentEndMs,
      executionDuration.documentIdleMs,
      documentLifecycleFallbackScripts.length + documentIdleFallbackCount
    );
    const runtimeResults: UserScriptRuntimeExecutionResultInput[] = [];
    for (let index = 0; index < reports.length; index++) {
      const script = scriptMap[reports[index].scriptId];
      const injectionPhase = script?.runAt ?? 'unknown';
      hilog.info(
        USER_SCRIPT_RUNTIME_LOG_DOMAIN,
        USER_SCRIPT_RUNTIME_LOG_TAG,
        'execution_report script=%{public}s name=%{public}s phase=%{public}s success=%{public}s host=%{public}s',
        reports[index].scriptId,
        script?.name ?? '',
        injectionPhase,
        reports[index].success ? 'true' : 'false',
        this.resolveLogHost(url)
      );
      runtimeResults.push({
        scriptId: reports[index].scriptId,
        url: url,
        injectionPhase: injectionPhase,
        success: reports[index].success,
        errorMessage: reports[index].errorMessage
      });
    }
    if (runtimeResults.length > 0 && isCurrentDocument()) {
      await this.runtimeStateRepository.recordExecutionResults(runtimeResults);
    }
    const failedReports = reports.filter((report: UserScriptExecutionReport) => !report.success);
    return {
      injectedScriptCount: autoScripts.length,
      executionReportCount: reports.length,
      failedScriptCount: failedReports.length,
      failedScriptNames: this.resolveFailedScriptNames(failedReports, autoScripts),
      url: url,
      skipReason: ''
    };
  }

  async injectForPage(
    tabId: string,
    url: string,
    privateMode: boolean,
    runAts: UserScriptRunAt[] = USER_SCRIPT_AUTOMATIC_RUN_ATS,
    isCurrentDocument: () => boolean = USER_SCRIPT_ALWAYS_CURRENT_DOCUMENT,
    expectedDocumentToken: string = ''
  ): Promise<UserScriptInjectionSummary> {
    return await this.injectForCurrentPage(
      tabId,
      url,
      this.runtimeLifecyclePort.resolveController(tabId),
      privateMode,
      runAts,
      isCurrentDocument,
      expectedDocumentToken
    );
  }

  clearAutomaticInjectionDocumentForPage(tabId: string): void {
    this.automaticDocumentStateByTabId[tabId] = undefined;
  }

  blockAutomaticInjectionDocumentForPage(tabId: string): void {
    this.blockedAutomaticDocumentTabIds[tabId] = true;
    this.clearAutomaticInjectionDocumentForPage(tabId);
  }

  async executeManualScriptForPage(
    tabId: string,
    scriptId: string,
    url: string,
    privateMode: boolean
  ): Promise<boolean> {
    return await this.executeManualScript(
      scriptId,
      url,
      this.runtimeLifecyclePort.resolveController(tabId),
      privateMode
    );
  }

  async executeMenuCommandForPage(
    tabId: string,
    scriptId: string,
    commandId: string,
    url: string,
    privateMode: boolean
  ): Promise<boolean> {
    const normalizedScriptId = scriptId.trim();
    const normalizedCommandId = commandId.trim();
    const normalizedUrl = url.trim();
    if (normalizedScriptId.length === 0 || normalizedCommandId.length === 0 || normalizedUrl.length === 0) {
      return false;
    }
    const eligibility = this.resolveEligibility(normalizedUrl, privateMode);
    const script = eligibility.matchingScripts.find((candidate: InstalledUserScriptState) => {
      return candidate.id === normalizedScriptId;
    });
    if (script === undefined) {
      return false;
    }
    if (!eligibility.executionAllowed) {
      await this.runtimeStateRepository.recordSkipped(
        normalizedScriptId,
        normalizedUrl,
        script.runAt,
        eligibility.blockReason
      );
      return false;
    }
    const controller = this.runtimeLifecyclePort.resolveController(tabId);
    if (controller === undefined) {
      await this.runtimeStateRepository.recordSkipped(
        normalizedScriptId,
        normalizedUrl,
        script.runAt,
        'missing_controller'
      );
      return false;
    }
    const compatibilityCommand: UserScriptRuntimeCompatibilityCommand | undefined =
      this.compatibilityService.resolveMenuCommand(script, normalizedCommandId);
    const commandSource = compatibilityCommand?.source ??
      this.buildExecuteMenuCommandScript(normalizedScriptId, normalizedCommandId);
    const result = this.normalizeMenuCommandResult(await controller.runJavaScript(commandSource));
    if (result.success) {
      await this.runtimeStateRepository.recordSuccess(normalizedScriptId, normalizedUrl, script.runAt);
      return true;
    }
    const errorMessage = String(result.errorMessage ?? '').trim();
    await this.runtimeStateRepository.recordFailure(
      normalizedScriptId,
      normalizedUrl,
      script.runAt,
      errorMessage.length > 0 ? errorMessage : (compatibilityCommand?.failureReason ?? 'menu-command-failed')
    );
    return false;
  }

  private async executeManualScript(
    scriptId: string,
    url: string,
    controller: webview.WebviewController | undefined,
    privateMode: boolean
  ): Promise<boolean> {
    const normalizedScriptId = scriptId.trim();
    const normalizedUrl = url.trim();
    if (normalizedScriptId.length === 0 || normalizedUrl.length === 0) {
      return false;
    }
    const script = this.readinessCoordinator.findExecutionReadyScript(normalizedScriptId);
    if (script === undefined || !script.enabled) {
      return false;
    }
    const eligibility = this.resolveEligibility(normalizedUrl, privateMode);
    const matchingScript = eligibility.matchingScripts.find((candidate: InstalledUserScriptState) => {
      return candidate.id === normalizedScriptId;
    });
    if (matchingScript === undefined) {
      await this.recordSkippedScripts([script], normalizedUrl, 'url-not-matched');
      return false;
    }
    if (!eligibility.executionAllowed) {
      await this.recordSkippedScripts([matchingScript], normalizedUrl, eligibility.blockReason);
      return false;
    }
    if (controller === undefined) {
      await this.recordSkippedScripts([matchingScript], normalizedUrl, 'missing_controller');
      return false;
    }
    const rawResult = await controller.runJavaScript(
      this.injectionService.buildDocumentEndScript(this.buildInjectionRequests([matchingScript], true))
    );
    const report = this.resolveLatestReports(this.executionReportCodec.parse(rawResult))
      .find((candidate: UserScriptExecutionReport) => candidate.scriptId === normalizedScriptId);
    if (report === undefined) {
      await this.runtimeStateRepository.recordFailure(
        normalizedScriptId,
        normalizedUrl,
        matchingScript.runAt,
        'missing-execution-report'
      );
      return false;
    }
    if (report.success) {
      await this.runtimeStateRepository.recordSuccess(
        normalizedScriptId,
        normalizedUrl,
        matchingScript.runAt
      );
      return true;
    }
    await this.runtimeStateRepository.recordFailure(
      normalizedScriptId,
      normalizedUrl,
      matchingScript.runAt,
      report.errorMessage
    );
    return false;
  }

  resolveEligibility(url: string, privateMode: boolean): UserScriptRuntimeEligibility {
    const matchingScripts = this.matchService.resolveMatchingScripts(
      this.readinessCoordinator.listExecutionReadyScripts(),
      url
    );
    if (privateMode) {
      return {
        executionAllowed: false,
        blockReason: 'private_mode',
        matchingScripts: matchingScripts
      };
    }
    return {
      executionAllowed: true,
      blockReason: 'none',
      matchingScripts: matchingScripts
    };
  }

  hasAutomaticScriptsForPage(url: string, privateMode: boolean): boolean {
    const eligibility = this.resolveEligibility(url, privateMode);
    return eligibility.executionAllowed && eligibility.matchingScripts.some(
      (script: InstalledUserScriptState): boolean => USER_SCRIPT_AUTOMATIC_RUN_ATS.includes(script.runAt)
    );
  }

  scheduleDocumentStartScriptWarmup(privateMode: boolean): void {
    if (privateMode || this.documentStartWarmupTimer >= 0) {
      return;
    }
    const generation = ++this.documentStartWarmupGeneration;
    this.documentStartWarmupTimer = setTimeout((): void => {
      this.documentStartWarmupTimer = -1;
      if (generation !== this.documentStartWarmupGeneration) {
        return;
      }
      try {
        this.buildDocumentStartScriptBundle(false);
      } catch (_error) {
        // A later navigation will retry the normal lazy build path.
      }
    }, USER_SCRIPT_DOCUMENT_START_WARMUP_DELAY_MS);
  }

  cancelDocumentStartScriptWarmup(): void {
    this.documentStartWarmupGeneration += 1;
    if (this.documentStartWarmupTimer < 0) {
      return;
    }
    clearTimeout(this.documentStartWarmupTimer);
    this.documentStartWarmupTimer = -1;
  }

  buildDocumentStartScriptBundle(privateMode: boolean): UserScriptDocumentStartScriptBundle {
    const startedAt = Date.now();
    this.documentStartCacheHitCount = 0;
    this.documentStartCacheMissCount = 0;
    if (privateMode) {
      this.documentStartItemCacheByScriptId = {};
      this.documentEndPreparedSourceCache = {};
      this.documentEndPreparedSourceCacheKey = {};
      const bundle: UserScriptDocumentStartScriptBundle = {
        items: [],
        key: 'userscript-document-start-private-v2'
      };
      hilog.info(
        USER_SCRIPT_RUNTIME_LOG_DOMAIN,
        USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] userscript_bundle private=true scripts=0 items=0 cacheHit=0 cacheMiss=0 elapsedMs=%{public}d',
        Date.now() - startedAt
      );
      return bundle;
    }
    const runtimeScripts = this.readinessCoordinator.listExecutionReadyScripts();
    this.pruneDocumentStartItemCache(runtimeScripts);
    this.pruneDocumentEndPreparedSourceCache(runtimeScripts);
    const runtimeFactoryItems: ScriptItem[] = [];
    const artifactKeys: string[] = ['userscript-document-start-v4-script-rules-diagnostic'];
    if (this.documentIdentityInstallItemCache === undefined) {
      this.documentIdentityInstallItemCache = {
        script: this.injectionService.buildDocumentIdentityInstallScript(
          this.nativeBridgeCoordinator.resolveAutomaticDocumentSignalSecret()
        ),
        scriptRules: ['*']
      };
    }
    runtimeFactoryItems.push(this.documentIdentityInstallItemCache);
    artifactKeys.push('document-identity-v2');
    if (runtimeScripts.some((script: InstalledUserScriptState): boolean => script.enabled)) {
      if (this.documentStartRuntimeFactoryItemCache === undefined) {
        this.documentStartRuntimeFactoryItemCache = {
          script: this.injectionService.buildRuntimeFactoryInstallScript(),
          scriptRules: ['*']
        };
      }
      runtimeFactoryItems.push(this.documentStartRuntimeFactoryItemCache);
      artifactKeys.push('runtime-factory-v1');
    }
    const documentStartItems: ScriptItem[] = [];
    runtimeScripts
      .filter((script: InstalledUserScriptState) => script.enabled && script.runAt === 'document-start')
      .forEach((script: InstalledUserScriptState): void => {
        const resolved = this.resolveDocumentStartScriptItem(script, false);
        documentStartItems.push(resolved.item);
        artifactKeys.push(resolved.key);
      });
    const apiBridgeItems: ScriptItem[] = [];
    runtimeScripts
      .filter((script: InstalledUserScriptState) => script.enabled && script.runAt !== 'document-start')
      .filter((script: InstalledUserScriptState) => this.shouldInstallDocumentStartApiBridge(script))
      .forEach((script: InstalledUserScriptState): void => {
        const resolved = this.resolveDocumentStartScriptItem(script, true);
        if (resolved.item.scriptRules.length > 0) {
          apiBridgeItems.push(resolved.item);
          artifactKeys.push(resolved.key);
        }
      });
    const items = runtimeFactoryItems.concat(documentStartItems).concat(apiBridgeItems);
    const prefilteredItemCount = documentStartItems.filter((item: ScriptItem): boolean => {
      return !this.hasWildcardOnlyScriptRules(item);
    }).length;
    const wildcardFallbackItemCount = documentStartItems.length - prefilteredItemCount;
    const projectedRuleCount = this.countScriptItemRules(documentStartItems);
    const projectedRuleMax = this.maxScriptItemRules(documentStartItems);
    const bundle: UserScriptDocumentStartScriptBundle = {
      items: this.cloneScriptItems(items),
      key: artifactKeys.join('|')
    };
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] userscript_bundle private=false scripts=%{public}d enabled=%{public}d start=%{public}d apiBridge=%{public}d items=%{public}d cacheHit=%{public}d cacheMiss=%{public}d keyLength=%{public}d elapsedMs=%{public}d',
      runtimeScripts.length,
      runtimeScripts.filter((script: InstalledUserScriptState): boolean => script.enabled).length,
      documentStartItems.length,
      apiBridgeItems.length,
      bundle.items.length,
      this.documentStartCacheHitCount,
      this.documentStartCacheMissCount,
      bundle.key.length,
      Date.now() - startedAt
    );
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_PERF_DIAGNOSTIC_TAG,
      '[DIAG-userscript-perf-20260828] phase=document_start_bundle scripts=%{public}d enabled=%{public}d start=%{public}d apiBridge=%{public}d items=%{public}d prefiltered=%{public}d wildcardFallback=%{public}d projectedRules=%{public}d projectedMax=%{public}d sourceChars=%{public}d itemChars=%{public}d cacheHit=%{public}d cacheMiss=%{public}d buildMs=%{public}d',
      runtimeScripts.length,
      runtimeScripts.filter((script: InstalledUserScriptState): boolean => script.enabled).length,
      documentStartItems.length,
      apiBridgeItems.length,
      items.length,
      prefilteredItemCount,
      wildcardFallbackItemCount,
      projectedRuleCount,
      projectedRuleMax,
      this.sumScriptPayloadChars(runtimeScripts.filter((script: InstalledUserScriptState): boolean => {
        return script.enabled && (script.runAt === 'document-start' || this.shouldInstallDocumentStartApiBridge(script));
      })),
      this.sumScriptItemChars(items),
      this.documentStartCacheHitCount,
      this.documentStartCacheMissCount,
      Date.now() - startedAt
    );
    return bundle;
  }

  buildDocumentStartScriptItems(privateMode: boolean): ScriptItem[] {
    return this.buildDocumentStartScriptBundle(privateMode).items;
  }

  private resolveDocumentStartScriptItem(
    script: InstalledUserScriptState,
    apiOnly: boolean
  ): UserScriptDocumentStartResolvedItem {
    const valueView = this.valueStore.readCommittedRuntimeView(script.id);
    const bridgeToken = this.nativeBridgeCoordinator.registerScriptToken(script.id);
    const artifactKey = this.buildDocumentStartArtifactKey(
      script,
      apiOnly,
      bridgeToken,
      this.buildStringFingerprint(valueView.snapshotLiteral)
    );
    const cached = this.documentStartItemCacheByScriptId[script.id];
    if (cached !== undefined && cached.artifactKey === artifactKey &&
      cached.apiOnly === apiOnly &&
      cached.bridgeToken === bridgeToken &&
      this.hasSameDocumentStartArtifactInput(cached.script, script) &&
      cached.valueSnapshotLiteral === valueView.snapshotLiteral) {
      this.documentStartCacheHitCount += 1;
      return {
        key: artifactKey,
        item: this.cloneScriptItem(cached.item)
      };
    }
    const request: UserScriptInjectionRequest = {
      script: script,
      valueSnapshotLiteral: valueView.snapshotLiteral,
      valueRevision: valueView.revision,
      bridgeToken: bridgeToken
    };
    const item: ScriptItem = {
      script: apiOnly ?
        this.injectionService.buildDocumentStartApiScript([request], []) :
        this.injectionService.buildDocumentStartScript([request], []),
      scriptRules: apiOnly ? this.buildDocumentStartApiBridgeScriptRules(script) :
        this.urlCompatibilityService.expandRunAtRules(script)
    };
    this.documentStartItemCacheByScriptId[script.id] = {
      apiOnly: apiOnly,
      artifactKey: artifactKey,
      bridgeToken: bridgeToken,
      script: cloneInstalledUserScriptState(script),
      valueSnapshotLiteral: valueView.snapshotLiteral,
      item: this.cloneScriptItem(item)
    };
    this.documentStartCacheMissCount += 1;
    return {
      key: artifactKey,
      item: item
    };
  }

  private buildDocumentStartArtifactKey(
    script: InstalledUserScriptState,
    apiOnly: boolean,
    bridgeToken: string,
    valueSnapshotFingerprint: string
  ): string {
    return [
      'userscript-document-start-artifact-v4-origin-rules',
      script.id,
      script.updatedAt,
      script.name,
      script.namespace,
      script.version,
      script.description,
      script.enabled ? '1' : '0',
      script.noframes ? '1' : '0',
      script.runAt,
      apiOnly ? 'api' : 'full',
      script.source.length,
      script.matches.join(','),
      script.includes.join(','),
      script.excludeMatches.join(','),
      script.excludes.join(','),
      script.grants.join(','),
      script.requireSources.map((source: string): number => source.length).join(','),
      script.resources.map((resource): string => {
        return `${resource.name}:${resource.url}:${resource.text.length}:${resource.mimeType}:${resource.contentBase64?.length ?? 0}`;
      }).join(','),
      script.connectRules.join(','),
      bridgeToken,
      valueSnapshotFingerprint
    ].join('|');
  }

  private buildStringFingerprint(value: string): string {
    let hash: number = 2166136261;
    for (let index = 0; index < value.length; index++) {
      hash = Math.imul(hash ^ value.charCodeAt(index), 16777619);
    }
    return `${value.length.toString(36)}-${(hash >>> 0).toString(16)}`;
  }

  private hasSameDocumentStartArtifactInput(
    cached: InstalledUserScriptState,
    current: InstalledUserScriptState
  ): boolean {
    return cached.id === current.id &&
      cached.name === current.name &&
      cached.namespace === current.namespace &&
      cached.version === current.version &&
      cached.description === current.description &&
      cached.source === current.source &&
      cached.enabled === current.enabled &&
      cached.noframes === current.noframes &&
      cached.runAt === current.runAt &&
      this.hasSameStringItems(cached.matches, current.matches) &&
      this.hasSameStringItems(cached.includes, current.includes) &&
      this.hasSameStringItems(cached.excludeMatches, current.excludeMatches) &&
      this.hasSameStringItems(cached.excludes, current.excludes) &&
      this.hasSameStringItems(cached.grants, current.grants) &&
      this.hasSameStringItems(cached.requireSources, current.requireSources) &&
      this.hasSameStringItems(cached.connectRules, current.connectRules) &&
      this.hasSameResourceItems(cached.resources, current.resources);
  }

  private hasSameStringItems(cached: string[], current: string[]): boolean {
    if (cached.length !== current.length) {
      return false;
    }
    for (let index = 0; index < cached.length; index++) {
      if (cached[index] !== current[index]) {
        return false;
      }
    }
    return true;
  }

  private hasSameResourceItems(
    cached: UserScriptResourceRecord[],
    current: UserScriptResourceRecord[]
  ): boolean {
    if (cached.length !== current.length) {
      return false;
    }
    for (let index = 0; index < cached.length; index++) {
      const cachedResource = cached[index];
      const currentResource = current[index];
      if (cachedResource.name !== currentResource.name ||
        cachedResource.url !== currentResource.url ||
        cachedResource.text !== currentResource.text ||
        cachedResource.mimeType !== currentResource.mimeType ||
        cachedResource.contentBase64 !== currentResource.contentBase64) {
        return false;
      }
    }
    return true;
  }

  private pruneDocumentStartItemCache(runtimeScripts: InstalledUserScriptState[]): void {
    const retainedCache: Record<string, UserScriptDocumentStartItemCacheEntry | undefined> = {};
    runtimeScripts.forEach((script: InstalledUserScriptState): void => {
      if (!script.enabled || (script.runAt !== 'document-start' &&
        !this.shouldInstallDocumentStartApiBridge(script))) {
        return;
      }
      const cached = this.documentStartItemCacheByScriptId[script.id];
      if (cached !== undefined) {
        retainedCache[script.id] = cached;
      }
    });
    this.documentStartItemCacheByScriptId = retainedCache;
  }

  private pruneDocumentEndPreparedSourceCache(runtimeScripts: InstalledUserScriptState[]): void {
    const retainedSources: Record<string, string | undefined> = {};
    const retainedKeys: Record<string, string | undefined> = {};
    runtimeScripts.forEach((script: InstalledUserScriptState): void => {
      if (!script.enabled || script.runAt === 'document-start') {
        return;
      }
      const source = this.documentEndPreparedSourceCache[script.id];
      const cacheKey = this.documentEndPreparedSourceCacheKey[script.id];
      if (source !== undefined && cacheKey !== undefined) {
        retainedSources[script.id] = source;
        retainedKeys[script.id] = cacheKey;
      }
    });
    this.documentEndPreparedSourceCache = retainedSources;
    this.documentEndPreparedSourceCacheKey = retainedKeys;
  }

  private cloneScriptItems(items: ScriptItem[]): ScriptItem[] {
    return items.map((item: ScriptItem): ScriptItem => {
      return this.cloneScriptItem(item);
    });
  }

  private cloneScriptItem(item: ScriptItem): ScriptItem {
    return {
      script: item.script,
      scriptRules: (item.scriptRules ?? []).slice()
    };
  }

  private handleAutomaticDocumentSignal(signal: UserScriptAutomaticDocumentSignal): void {
    if (this.blockedAutomaticDocumentTabIds[signal.tabId] === true) {
      return;
    }
    const documentToken = signal.documentToken.trim();
    if (documentToken.length === 0) {
      return;
    }
    const pageUrl = signal.pageUrl.trim();
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_PERF_DIAGNOSTIC_TAG,
      '[DIAG-userscript-perf-20260828] phase=%{public}s_signal tab=%{public}s urlLength=%{public}d tokenLength=%{public}d',
      signal.phase,
      signal.tabId,
      pageUrl.length,
      documentToken.length
    );
    let state = this.automaticDocumentStateByTabId[signal.tabId];
    if (signal.phase === 'document_start') {
      if (state === undefined || state.documentToken !== documentToken) {
        this.automaticDocumentStateByTabId[signal.tabId] = {
          documentToken: documentToken,
          pageUrl: pageUrl,
          documentEndRunStarted: false,
          documentEndRunAttemptCount: 0,
          documentIdleRunStarted: false,
          documentIdleRunAttemptCount: 0
        };
      } else if (pageUrl.length > 0) {
        state.pageUrl = pageUrl;
      }
      return;
    }
    if (state === undefined || state.documentToken !== documentToken) {
      return;
    }
    if (pageUrl.length > 0) {
      state.pageUrl = pageUrl;
    }
    this.startAutomaticDocumentInjectionIfReady(signal.tabId, state, signal.phase);
  }

  private startAutomaticDocumentInjectionIfReady(
    tabId: string,
    state: UserScriptAutomaticDocumentState,
    phase: 'document_end' | 'post_paint'
  ): void {
    const isDocumentEndPhase = phase === 'document_end';
    const phaseRunStarted = isDocumentEndPhase ? state.documentEndRunStarted : state.documentIdleRunStarted;
    const phaseAttemptCount = isDocumentEndPhase ?
      state.documentEndRunAttemptCount : state.documentIdleRunAttemptCount;
    if (this.preferencesRepository.getPreferences().appServiceMode === 'basic' ||
      this.blockedAutomaticDocumentTabIds[tabId] === true || phaseRunStarted ||
      phaseAttemptCount >= 2 || state.pageUrl.length === 0 ||
      !this.isCurrentAutomaticDocument(tabId, state.documentToken)) {
      return;
    }
    const runAts: UserScriptRunAt[] = isDocumentEndPhase ?
      ['document-start', 'document-end'] :
      (state.documentEndRunStarted ? ['document-idle'] : ['document-end', 'document-idle']);
    if (isDocumentEndPhase) {
      state.documentEndRunStarted = true;
      state.documentEndRunAttemptCount += 1;
    } else {
      state.documentIdleRunStarted = true;
      state.documentIdleRunAttemptCount += 1;
      // A missed DOMContentLoaded signal must still be recoverable at post-paint.
      if (!state.documentEndRunStarted && runAts.includes('document-end')) {
        state.documentEndRunStarted = true;
      }
    }
    const documentToken = state.documentToken;
    const pageUrl = state.pageUrl;
    const startedAt = Date.now();
    const isCurrentDocument = (): boolean => this.isCurrentAutomaticDocument(tabId, documentToken);
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] userscript_inject_begin tab=%{public}s phase=%{public}s urlLength=%{public}d private=false',
      tabId,
      phase,
      pageUrl.length
    );
    void this.readinessCoordinator.initializeExecutionState().then((): Promise<UserScriptInjectionSummary> => {
      if (!isCurrentDocument()) {
        return Promise.resolve(this.emptySummary(pageUrl, 'stale_document'));
      }
      return this.injectForPage(
        tabId,
        pageUrl,
        false,
        runAts,
        isCurrentDocument,
        documentToken
      );
    }).then((summary: UserScriptInjectionSummary): void => {
      if (!isCurrentDocument()) {
        return;
      }
      hilog.info(
        USER_SCRIPT_RUNTIME_LOG_DOMAIN,
        USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] userscript_inject_end tab=%{public}s phase=%{public}s injected=%{public}d reports=%{public}d failed=%{public}d elapsedMs=%{public}d',
        tabId,
        phase,
        summary.injectedScriptCount,
        summary.executionReportCount,
        summary.failedScriptCount,
        Date.now() - startedAt
      );
    }).catch((_error: Error): void => {
      const currentState = this.automaticDocumentStateByTabId[tabId];
      if (currentState !== state || currentState.documentToken !== documentToken) {
        return;
      }
      if (isDocumentEndPhase) {
        currentState.documentEndRunStarted = false;
      } else {
        currentState.documentIdleRunStarted = false;
        if (runAts.includes('document-end')) {
          currentState.documentEndRunStarted = false;
        }
      }
      hilog.error(
        USER_SCRIPT_RUNTIME_LOG_DOMAIN,
        USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] userscript_inject_error tab=%{public}s phase=%{public}s elapsedMs=%{public}d',
        tabId,
        phase,
        Date.now() - startedAt
      );
      const currentPhaseAttemptCount = isDocumentEndPhase ?
        currentState.documentEndRunAttemptCount : currentState.documentIdleRunAttemptCount;
      if (currentPhaseAttemptCount < 2) {
        setTimeout((): void => {
          this.startAutomaticDocumentInjectionIfReady(tabId, currentState, phase);
        }, 0);
      }
    });
  }

  private isCurrentAutomaticDocument(tabId: string, documentToken: string): boolean {
    return this.blockedAutomaticDocumentTabIds[tabId] !== true &&
      this.automaticDocumentStateByTabId[tabId]?.documentToken === documentToken;
  }

  private filterExecutionReportsForScripts(
    reports: UserScriptExecutionReport[],
    scripts: InstalledUserScriptState[]
  ): UserScriptExecutionReport[] {
    return reports.filter((report: UserScriptExecutionReport): boolean => {
      return scripts.some((script: InstalledUserScriptState): boolean => script.id === report.scriptId);
    });
  }

  private delayDocumentIdleReportRead(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout((): void => {
        resolve();
      }, 300);
    });
  }

  private emptySummary(url: string, skipReason: string): UserScriptInjectionSummary {
    return {
      injectedScriptCount: 0,
      executionReportCount: 0,
      failedScriptCount: 0,
      failedScriptNames: [],
      url: url,
      skipReason: skipReason
    };
  }

  private resolveLogHost(url: string): string {
    try {
      return urlUtils.URL.parseURL(url).hostname.toLowerCase();
    } catch (_error) {
      return '';
    }
  }

  private buildInjectionRequests(
    scripts: InstalledUserScriptState[],
    includeValueSnapshots: boolean = false
  ): UserScriptInjectionRequest[] {
    return scripts.map((script: InstalledUserScriptState): UserScriptInjectionRequest => {
      const valueView = this.valueStore.readCommittedRuntimeView(script.id);
      return {
        script: script,
        valueSnapshotLiteral: includeValueSnapshots ? valueView.snapshotLiteral : '',
        valueRevision: valueView.revision,
        bridgeToken: this.nativeBridgeCoordinator.registerScriptToken(script.id)
      };
    });
  }

  private async readExecutionReports(
    controller: webview.WebviewController,
    _url: string,
    expectedDocumentToken: string = ''
  ): Promise<UserScriptExecutionReport[]> {
    try {
      const rawResult = await controller.runJavaScript(
        this.injectionService.buildExecutionReportReadScript(expectedDocumentToken)
      );
      if (this.isStaleDocumentJavaScriptResult(rawResult)) {
        throw new Error(USER_SCRIPT_STALE_DOCUMENT_FAILURE);
      }
      return this.executionReportCodec.parse(rawResult);
    } catch (error) {
      if (this.isStaleDocumentError(error)) {
        throw this.normalizeThrowable(error as Object);
      }
      return [];
    }
  }

  private async executeScriptsIndependently(
    scripts: InstalledUserScriptState[],
    url: string,
    controller: webview.WebviewController,
    isCurrentDocument: () => boolean,
    expectedDocumentToken: string
  ): Promise<UserScriptExecutionReport[]> {
    const reports: UserScriptExecutionReport[] = [];
    for (let index = 0; index < scripts.length; index += 1) {
      if (!isCurrentDocument()) {
        break;
      }
      const script = scripts[index];
      const injectionSource = this.buildPreparedDocumentEndSource([script], expectedDocumentToken);
      let report: UserScriptExecutionReport | undefined;
      try {
        const rawResult = await controller.runJavaScript(injectionSource);
        if (this.isStaleDocumentJavaScriptResult(rawResult)) {
          throw new Error(USER_SCRIPT_STALE_DOCUMENT_FAILURE);
        }
        report = this.resolveLatestReports(this.executionReportCodec.parse(rawResult))
          .find((candidate: UserScriptExecutionReport) => candidate.scriptId === script.id);
      } catch (error) {
        if (this.isStaleDocumentError(error)) {
          throw this.normalizeThrowable(error as Object);
        }
        report = {
          scriptId: script.id,
          success: false,
          errorMessage: `${USER_SCRIPT_NO_REPORT_FAILURE}:${this.normalizeJavaScriptExecutionFailure(error)}`
        };
      }
      if (report === undefined) {
        report = {
          scriptId: script.id,
          success: false,
          errorMessage: USER_SCRIPT_NO_REPORT_FAILURE
        };
      }
      reports.push(report);
    }
    return reports;
  }

  private async executeAutomaticScripts(
    scripts: InstalledUserScriptState[],
    url: string,
    controller: webview.WebviewController,
    isCurrentDocument: () => boolean,
    expectedDocumentToken: string
  ): Promise<UserScriptExecutionReport[]> {
    if (!isCurrentDocument()) {
      return [];
    }
    const quarantinedScripts = scripts.filter((script: InstalledUserScriptState): boolean => {
      return this.isExecutionQuarantined(script);
    });
    const runnableScripts = scripts.filter((script: InstalledUserScriptState): boolean => {
      return !this.isExecutionQuarantined(script);
    });
    const quarantineReports = quarantinedScripts.map((script: InstalledUserScriptState): UserScriptExecutionReport => {
      return {
        scriptId: script.id,
        success: false,
        errorMessage: USER_SCRIPT_NO_REPORT_FAILURE
      };
    });
    if (runnableScripts.length === 0) {
      return quarantineReports;
    }
    const claimedScripts = await this.claimDocumentExecution(
      runnableScripts,
      url,
      controller,
      expectedDocumentToken
    );
    if (!isCurrentDocument()) {
      return [];
    }
    const duplicateReports = runnableScripts
      .filter((script: InstalledUserScriptState): boolean => {
        return !claimedScripts.some((claimed: InstalledUserScriptState): boolean => claimed.id === script.id);
      })
      .map((script: InstalledUserScriptState): UserScriptExecutionReport => {
        return {
          scriptId: script.id,
          success: true,
          errorMessage: ''
        };
      });
    if (claimedScripts.length === 0) {
      return duplicateReports.concat(quarantineReports);
    }
    const needsIndependentVerification = claimedScripts.some((script: InstalledUserScriptState): boolean => {
      return !this.isExecutionBoundaryVerified(script);
    });
    const executionMode = needsIndependentVerification ? 'independent' : 'batch';
    const executionStartedAt = Date.now();
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] userscript_execute_begin mode=%{public}s scripts=%{public}d host=%{public}s',
      executionMode,
      claimedScripts.length,
      this.resolveLogHost(url)
    );
    const executionReports = needsIndependentVerification
      ? await this.executeScriptsIndependently(
        claimedScripts,
        url,
        controller,
        isCurrentDocument,
        expectedDocumentToken
      )
      : await this.executeVerifiedScriptsAsBatch(claimedScripts, url, controller, expectedDocumentToken);
    hilog.info(
      USER_SCRIPT_RUNTIME_LOG_DOMAIN,
      USER_SCRIPT_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] userscript_execute_end mode=%{public}s scripts=%{public}d reports=%{public}d elapsedMs=%{public}d host=%{public}s',
      executionMode,
      claimedScripts.length,
      executionReports.length,
      Date.now() - executionStartedAt,
      this.resolveLogHost(url)
    );
    return executionReports.concat(duplicateReports).concat(quarantineReports);
  }

  private async claimDocumentExecution(
    scripts: InstalledUserScriptState[],
    url: string,
    controller: webview.WebviewController,
    expectedDocumentToken: string
  ): Promise<InstalledUserScriptState[]> {
    try {
      const rawResult = await controller.runJavaScript(
        this.injectionService.buildDocumentExecutionClaimScript(
          scripts.map((script: InstalledUserScriptState): string => script.id),
          expectedDocumentToken
        )
      );
      if (this.isStaleDocumentJavaScriptResult(rawResult)) {
        throw new Error(USER_SCRIPT_STALE_DOCUMENT_FAILURE);
      }
      const claimedIds = this.parseClaimedScriptIds(rawResult);
      if (claimedIds === undefined) {
        throw new Error('invalid-document-claim-result');
      }
      return scripts.filter((script: InstalledUserScriptState): boolean => {
        return claimedIds.includes(script.id);
      });
    } catch (error) {
      if (this.isStaleDocumentError(error)) {
        throw this.normalizeThrowable(error as Object);
      }
      return scripts;
    }
  }

  private parseClaimedScriptIds(
    rawResult: Object | string | number | boolean | undefined
  ): string[] | undefined {
    const normalized = normalizeUserScriptJavaScriptResult(rawResult);
    if (normalized.length === 0) {
      return undefined;
    }
    try {
      const parsed = JSON.parse(normalized) as string[];
      if (!Array.isArray(parsed)) {
        return undefined;
      }
      const results: string[] = [];
      parsed.forEach((value: string): void => {
        const scriptId = String(value ?? '').trim();
        if (scriptId.length > 0 && !results.includes(scriptId)) {
          results.push(scriptId);
        }
      });
      return results;
    } catch (_error) {
      return undefined;
    }
  }

  private isExecutionQuarantined(script: InstalledUserScriptState): boolean {
    const record = this.runtimeStateRepository.findRecord(script.id);
    return record !== undefined && record.status === 'failed' &&
      record.lastErrorMessage.startsWith(USER_SCRIPT_NO_REPORT_FAILURE);
  }

  private isExecutionBoundaryVerified(script: InstalledUserScriptState): boolean {
    const record: UserScriptRuntimeStateRecord | undefined = this.runtimeStateRepository.findRecord(script.id);
    if (record === undefined || record.status === 'never_run' || record.status === 'skipped') {
      return false;
    }
    return !record.lastErrorMessage.startsWith(USER_SCRIPT_BATCH_NO_REPORT_FAILURE);
  }

  private async executeVerifiedScriptsAsBatch(
    scripts: InstalledUserScriptState[],
    url: string,
    controller: webview.WebviewController,
    expectedDocumentToken: string
  ): Promise<UserScriptExecutionReport[]> {
    const scriptIds = scripts.map((script: InstalledUserScriptState): string => script.id);
    const source = this.buildVerifiedBatchExecutionSource(scripts, expectedDocumentToken);
    let reports: UserScriptExecutionReport[] = [];
    let failureMessage = USER_SCRIPT_BATCH_NO_REPORT_FAILURE;
    try {
      const rawResult = await controller.runJavaScript(source);
      if (this.isStaleDocumentJavaScriptResult(rawResult)) {
        throw new Error(USER_SCRIPT_STALE_DOCUMENT_FAILURE);
      }
      reports = this.resolveLatestReports(this.executionReportCodec.parse(rawResult))
        .filter((report: UserScriptExecutionReport): boolean => scriptIds.includes(report.scriptId));
    } catch (error) {
      if (this.isStaleDocumentError(error)) {
        throw this.normalizeThrowable(error as Object);
      }
      failureMessage = `${USER_SCRIPT_BATCH_NO_REPORT_FAILURE}:${this.normalizeJavaScriptExecutionFailure(error)}`;
    }
    scripts.forEach((script: InstalledUserScriptState): void => {
      if (!reports.some((report: UserScriptExecutionReport): boolean => report.scriptId === script.id)) {
        reports.push({
          scriptId: script.id,
          success: false,
          errorMessage: failureMessage
        });
      }
    });
    return reports;
  }

  private buildVerifiedBatchExecutionSource(
    scripts: InstalledUserScriptState[],
    expectedDocumentToken: string
  ): string {
    return this.buildPreparedDocumentEndSource(scripts, expectedDocumentToken);
  }

  private buildPreparedDocumentEndSource(
    scripts: InstalledUserScriptState[],
    expectedDocumentToken: string = ''
  ): string {
    const preparedScripts = scripts.map((script: InstalledUserScriptState): string => {
      const cacheKey = this.buildPreparedDocumentEndSourceCacheKey(script);
      const cachedSource = this.documentEndPreparedSourceCache[script.id];
      if (cachedSource !== undefined && this.documentEndPreparedSourceCacheKey[script.id] === cacheKey) {
        return cachedSource;
      }
      const source = this.injectionService.buildPreparedDocumentEndScript(this.buildInjectionRequests([script])[0]);
      this.documentEndPreparedSourceCacheKey[script.id] = cacheKey;
      this.documentEndPreparedSourceCache[script.id] = source;
      return source;
    }).join('\n');
    return this.injectionService.buildPreparedDocumentEndBatch(preparedScripts, expectedDocumentToken);
  }

  private buildPreparedDocumentEndSourceCacheKey(script: InstalledUserScriptState): string {
    return [
      script.id,
      script.enabled ? '1' : '0',
      script.updatedAt,
      script.version,
      script.runAt,
      script.source.length,
      script.requireSources.map((source: string): number => source.length).join(','),
      script.resources.map((resource): string => `${resource.name}:${resource.text.length}:${resource.url}`).join(','),
      script.matches.join(','),
      script.includes.join(','),
      script.excludeMatches.join(','),
      script.excludes.join(','),
      script.grants.join(','),
      script.connectRules.join(','),
      this.nativeBridgeCoordinator.registerScriptToken(script.id)
    ].join('|');
  }

  private normalizeJavaScriptExecutionFailure(error: Object): string {
    const message = error instanceof Error ? error.message.trim() : String(error).trim();
    return message.length > 0 ? `javascript-execution-failed:${message}` : 'javascript-execution-failed';
  }

  private normalizeThrowable(error: Object): Error {
    if (error instanceof Error) {
      return error;
    }
    return new Error(String(error));
  }

  private isStaleDocumentJavaScriptResult(
    rawResult: Object | string | number | boolean | undefined
  ): boolean {
    return normalizeUserScriptJavaScriptResult(rawResult) === USER_SCRIPT_STALE_DOCUMENT_RESULT;
  }

  private isStaleDocumentError(error: Object): boolean {
    return error instanceof Error && error.message === USER_SCRIPT_STALE_DOCUMENT_FAILURE;
  }

  private resolveMissingExecutionReports(
    scripts: InstalledUserScriptState[],
    reports: UserScriptExecutionReport[]
  ): InstalledUserScriptState[] {
    return scripts.filter((script: InstalledUserScriptState) => {
      return !reports.some((report: UserScriptExecutionReport) => {
        return report.scriptId === script.id;
      });
    });
  }

  private buildExecuteMenuCommandScript(scriptId: string, commandId: string): string {
    const scriptIdLiteral = JSON.stringify(scriptId);
    const commandIdLiteral = JSON.stringify(commandId);
    return `
;(function airaExecuteUserScriptMenuCommand() {
  try {
    var menus = window.__airaUserScriptMenus || {};
    var commands = menus[${scriptIdLiteral}] || {};
    var command = commands[${commandIdLiteral}];
    if (!command || typeof command.callback !== 'function') {
      throw new Error('menu-command-not-found');
    }
    command.callback();
    return JSON.stringify({ success: true, errorMessage: '' });
  } catch (error) {
    return JSON.stringify({
      success: false,
      errorMessage: String(error && (error.stack || error.message || error) || 'menu-command-failed')
    });
  }
})();
`;
  }

  private normalizeMenuCommandResult(
    rawResult: Object | string | number | boolean | undefined
  ): RawUserScriptMenuCommandResult {
    const normalized = normalizeUserScriptJavaScriptResult(rawResult);
    if (normalized.length === 0) {
      return {
        success: false,
        errorMessage: 'invalid-menu-command-result'
      };
    }
    try {
      const parsed = JSON.parse(normalized) as RawUserScriptMenuCommandResult;
      return {
        success: parsed.success === true,
        errorMessage: String(parsed.errorMessage ?? '').trim()
      };
    } catch (_error) {
      return {
        success: false,
        errorMessage: 'invalid-menu-command-result'
      };
    }
  }

  private resolveLatestReports(reports: UserScriptExecutionReport[]): UserScriptExecutionReport[] {
    const latestByScriptId: Record<string, UserScriptExecutionReport | undefined> = {};
    const orderedScriptIds: string[] = [];
    reports.forEach((report: UserScriptExecutionReport) => {
      if (latestByScriptId[report.scriptId] === undefined) {
        orderedScriptIds.push(report.scriptId);
      }
      latestByScriptId[report.scriptId] = report;
    });
    const results: UserScriptExecutionReport[] = [];
    orderedScriptIds.forEach((scriptId: string) => {
      const report = latestByScriptId[scriptId];
      if (report !== undefined) {
        results.push(report);
      }
    });
    return results;
  }

  private async recordSkippedScripts(
    scripts: InstalledUserScriptState[],
    url: string,
    skipReason: string
  ): Promise<void> {
    if (scripts.length === 0) {
      return;
    }
    const results: UserScriptRuntimeSkippedResultInput[] = scripts.map(
      (script: InstalledUserScriptState): UserScriptRuntimeSkippedResultInput => {
        return {
          scriptId: script.id,
          url: url,
          injectionPhase: script.runAt,
          skipReason: skipReason
        };
      }
    );
    await this.runtimeStateRepository.recordSkippedResults(results);
  }

  private buildScriptMap(scripts: InstalledUserScriptState[]): Record<string, InstalledUserScriptState> {
    const results: Record<string, InstalledUserScriptState> = {};
    scripts.forEach((script: InstalledUserScriptState) => {
      results[script.id] = script;
    });
    return results;
  }

  private sumScriptPayloadChars(scripts: InstalledUserScriptState[]): number {
    return scripts.reduce((total: number, script: InstalledUserScriptState): number => {
      const requires = script.requireSources.reduce((sum: number, source: string): number => sum + source.length, 0);
      const resources = script.resources.reduce((sum: number, resource: UserScriptResourceRecord): number => {
        return sum + resource.text.length + (resource.contentBase64?.length ?? 0);
      }, 0);
      return total + script.source.length + requires + resources;
    }, 0);
  }

  private sumScriptItemChars(items: ScriptItem[]): number {
    return items.reduce((total: number, item: ScriptItem): number => {
      return total + String(item.script ?? '').length;
    }, 0);
  }

  private countScriptItemRules(items: ScriptItem[]): number {
    return items.reduce((total: number, item: ScriptItem): number => {
      return total + (item.scriptRules ?? []).length;
    }, 0);
  }

  private maxScriptItemRules(items: ScriptItem[]): number {
    return items.reduce((maximum: number, item: ScriptItem): number => {
      return Math.max(maximum, (item.scriptRules ?? []).length);
    }, 0);
  }

  private countProjectedRulesForScripts(scripts: InstalledUserScriptState[]): number {
    return scripts.reduce((total: number, script: InstalledUserScriptState): number => {
      return total + this.urlCompatibilityService.expandRunAtRules(script).length;
    }, 0);
  }

  private maxProjectedRulesForScripts(scripts: InstalledUserScriptState[]): number {
    return scripts.reduce((maximum: number, script: InstalledUserScriptState): number => {
      return Math.max(maximum, this.urlCompatibilityService.expandRunAtRules(script).length);
    }, 0);
  }

  private isWildcardOnlyRules(rules: string[]): boolean {
    return rules.length === 1 && rules[0] === '*';
  }

  private hasWildcardOnlyScriptRules(item: ScriptItem): boolean {
    return this.isWildcardOnlyRules(item.scriptRules ?? []);
  }

  private summarizeExecutionDuration(
    reports: UserScriptExecutionReport[],
    scriptMap: Record<string, InstalledUserScriptState>
  ): UserScriptExecutionDurationSummary {
    let measuredCount = 0;
    let totalMs = 0;
    let maxMs = 0;
    let documentStartMs = 0;
    let documentEndMs = 0;
    let documentIdleMs = 0;
    reports.forEach((report: UserScriptExecutionReport): void => {
      if (report.durationMs === undefined || !Number.isFinite(report.durationMs)) {
        return;
      }
      measuredCount += 1;
      totalMs += report.durationMs;
      maxMs = Math.max(maxMs, report.durationMs);
      const runAt = scriptMap[report.scriptId]?.runAt;
      if (runAt === 'document-start') {
        documentStartMs += report.durationMs;
      } else if (runAt === 'document-end') {
        documentEndMs += report.durationMs;
      } else if (runAt === 'document-idle') {
        documentIdleMs += report.durationMs;
      }
    });
    return {
      measuredCount: measuredCount,
      totalMs: Math.round(totalMs),
      maxMs: Math.round(maxMs),
      documentStartMs: Math.round(documentStartMs),
      documentEndMs: Math.round(documentEndMs),
      documentIdleMs: Math.round(documentIdleMs)
    };
  }

  private shouldInstallDocumentStartApiBridge(script: InstalledUserScriptState): boolean {
    const source = script.source;
    return this.capabilityContract.hasGrant(script, 'unsafeWindow') &&
      this.capabilityContract.hasGrant(script, 'GM_info') &&
      source.indexOf('APP_INFO') >= 0 &&
      this.compatibilityService.resolveStandaloneOptionsPageUrls(script).length > 0;
  }

  private shouldInstallDocumentStartApiBridgeForUrl(script: InstalledUserScriptState, url: string): boolean {
    if (!this.shouldInstallDocumentStartApiBridge(script)) {
      return false;
    }
    const normalizedUrl = this.stripQueryAndHash(url);
    return this.compatibilityService.resolveStandaloneOptionsPageUrls(script).some((optionsUrl: string) => {
      return this.stripQueryAndHash(optionsUrl) === normalizedUrl;
    });
  }

  private buildDocumentStartApiBridgeScriptRules(script: InstalledUserScriptState): string[] {
    if (!this.shouldInstallDocumentStartApiBridge(script)) {
      return [];
    }
    const rules: string[] = [];
    this.compatibilityService.resolveStandaloneOptionsPageUrls(script).forEach((url: string): void => {
      const normalizedUrl = url.trim();
      if (!this.isArkWebHttpScriptRule(normalizedUrl)) {
        return;
      }
      this.appendUniqueRule(rules, normalizedUrl);
      this.appendUniqueRule(rules, `${normalizedUrl}?*`);
      this.appendUniqueRule(rules, `${normalizedUrl}#*`);
    });
    return rules;
  }

  private stripQueryAndHash(url: string): string {
    const value = String(url || '').trim();
    let endIndex = value.length;
    const hashIndex = value.indexOf('#');
    const queryIndex = value.indexOf('?');
    if (hashIndex >= 0 && hashIndex < endIndex) {
      endIndex = hashIndex;
    }
    if (queryIndex >= 0 && queryIndex < endIndex) {
      endIndex = queryIndex;
    }
    return value.slice(0, endIndex);
  }

  private resolveFailedScriptNames(
    reports: UserScriptExecutionReport[],
    scripts: InstalledUserScriptState[]
  ): string[] {
    return reports.map((report: UserScriptExecutionReport) => {
      const script = scripts.find((candidate: InstalledUserScriptState) => candidate.id === report.scriptId);
      return script?.name ?? report.scriptId;
    });
  }

  private isArkWebHttpScriptRule(rule: string): boolean {
    const normalizedRule = rule.trim().toLowerCase();
    return normalizedRule.startsWith('http://') || normalizedRule.startsWith('https://');
  }

  private appendUniqueRule(rules: string[], rule: string): void {
    const normalizedRule = rule.trim();
    if (normalizedRule.length > 0 && !rules.includes(normalizedRule)) {
      rules.push(normalizedRule);
    }
  }
}
