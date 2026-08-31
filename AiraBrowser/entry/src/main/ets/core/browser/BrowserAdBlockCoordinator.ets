import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  AdBlockCustomRuleSource
} from '../../common/models/BrowserModels';
import { webview } from '@kit.ArkWeb';
import urlUtils from '@ohos.url';
import {
  AdBlockRuntimeCosmeticHiddenResult,
  AdBlockRuntimePageProtectionSnapshot,
  AdBlockRuntimeStatsCoordinator
} from '../adblock/AdBlockRuntimeStatsCoordinator';
import { findAdBlockThirdPartyRuleSource } from '../../features/adblock/AdBlockThirdPartyRuleSourceCatalog';
import { AdBlockRuntimeSnapshot } from '../adblock/AdBlockRuntimeSnapshot';
import { AdBlockRuntimeGenerationCoordinator } from '../adblock/AdBlockRuntimeGenerationCoordinator';
import {
  AdBlockProtectionActivitySummary,
  AdBlockRepository
} from '../../data/adblock/AdBlockRepository';
import { AdBlockPagePolicyResult, AdBlockPolicyService } from '../../services/adblock/AdBlockPolicyService';
import {
  AdBlockRequestEvaluationInput
} from '../../services/adblock/AdBlockRequestEvaluationModels';
import {
  AdBlockRequestClassification,
  AdBlockRequestClassifierService
} from '../../services/adblock/AdBlockRequestClassifierService';
import {
  AdBlockCspRequestIdentity,
  AdBlockCspResponseInput,
  AdBlockResponseFactoryService
} from '../../services/adblock/AdBlockResponseFactoryService';
import {
  AdBlockRustCosmeticResourceAdapterService
} from '../../services/adblock/AdBlockRustCosmeticResourceAdapterService';
import {
  AdBlockCosmeticInjectionService,
  AdBlockCosmeticInjectionSummary
} from '../../services/adblock/AdBlockCosmeticInjectionService';
import {
  AdBlockNativeRuleProviderResult,
  sharedAdBlockNativeRuleProviderService
} from '../../services/adblock/AdBlockNativeRuleProviderService';
import { AdBlockPingRequestSignalService } from '../../services/adblock/AdBlockPingRequestSignalService';
import { BrowserRuntimeLifecyclePort } from '../../services/web/BrowserRuntimeLifecyclePort';
import { AdBlockRuleSourceCoordinator } from '../adblock/AdBlockRuleSourceCoordinator';

const AD_BLOCK_PING_NATIVE_BRIDGE_NAME: string = '__airaAdBlockPingNativeBridge';
const AD_BLOCK_PING_NATIVE_BRIDGE_METHODS: string[] = ['mark'];
const AD_BLOCK_RUNTIME_BOOT_RETRY_DELAYS_MS: number[] = [
  10 * 1000,
  30 * 1000,
  60 * 1000,
  2 * 60 * 1000,
  5 * 60 * 1000
];

class BrowserAdBlockPingNativeBridge {
  private readonly tabId: string;
  private readonly signalService: AdBlockPingRequestSignalService;

  constructor(tabId: string, signalService: AdBlockPingRequestSignalService) {
    this.tabId = tabId;
    this.signalService = signalService;
  }

  mark(url: string): void {
    this.signalService.record(this.tabId, String(url ?? ''));
  }
}

export interface BrowserAdBlockRequestContext {
  tabId: string;
  request: WebResourceRequest;
  pageUrl: string;
  capabilitySupported: boolean;
  controllerAttached: boolean;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
  strengthenForSmoothScroll: boolean;
}

export interface BrowserAdBlockSiteProtectionToggleContext {
  pageUrl: string;
  capabilitySupported: boolean;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserAdBlockSiteProtectionToggleResult {
  success: boolean;
  siteEnabled: boolean;
  summary: string;
  toast: string;
}

export interface BrowserAdBlockPageRuntimeContext {
  tabId: string;
  pageUrl: string;
  capabilitySupported: boolean;
  controllerAttached: boolean;
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserAdBlockControllerApplyResult {
  capabilitySupported: boolean;
}

export interface BrowserAdBlockProtectionStatusResult {
  capabilitySupported: boolean;
  availabilityState: BrowserAdBlockProtectionAvailabilityState;
  summary: string;
  siteToggleEnabled: boolean;
  siteEnabled: boolean;
}

export interface BrowserAdBlockSiteProtectionStateResult {
  siteToggleEnabled: boolean;
  siteEnabled: boolean;
}

export type BrowserAdBlockPrivacyCoverageState =
  'enabled' |
  'preparing' |
  'disabled' |
  'failed' |
  'site_disabled' |
  'unavailable';

export type BrowserAdBlockProtectionAvailabilityState =
  'active_with_actions' |
  'active_without_actions' |
  'site_disabled' |
  'global_disabled_or_unconfigured' |
  'capability_unavailable';

export interface BrowserAdBlockPrivacyCoverageResult {
  state: BrowserAdBlockPrivacyCoverageState;
  summary: string;
}

export interface BrowserAdBlockManualHiddenContext {
  tabId: string;
  hiddenElementCount: number;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
}

export interface BrowserAdBlockCosmeticHiddenPayloadContext {
  tabId: string;
  payloadJson: string;
  currentPageUrl: string;
}

export interface BrowserAdBlockUrlTransformResult {
  url: string;
  changed: boolean;
}

interface BrowserAdBlockCosmeticHiddenPayload {
  count?: number;
  hiddenElementCount?: number;
  placeholderCollapsedCount?: number;
  hiddenClickRectCount?: number;
  eventX?: number;
  eventY?: number;
  pageUrl?: string;
  phase?: string;
}

export class BrowserAdBlockCoordinator {
  private static runtimeBootPreparationPromises: Map<AdBlockRepository, Promise<void>> =
    new Map<AdBlockRepository, Promise<void>>();
  private static runtimeBootPreparedRepositories: Set<AdBlockRepository> = new Set<AdBlockRepository>();
  private static runtimeBootFailureCounts: Map<AdBlockRepository, number> = new Map<AdBlockRepository, number>();
  private static runtimeBootRetryNotBefore: Map<AdBlockRepository, number> = new Map<AdBlockRepository, number>();
  private repository: AdBlockRepository;
  private statsCoordinator: AdBlockRuntimeStatsCoordinator;
  private runtimeGeneration: AdBlockRuntimeGenerationCoordinator;
  private policyService: AdBlockPolicyService = new AdBlockPolicyService();
  private requestClassifier: AdBlockRequestClassifierService = new AdBlockRequestClassifierService();
  private responseFactory: AdBlockResponseFactoryService = new AdBlockResponseFactoryService();
  private cosmeticResourceAdapter: AdBlockRustCosmeticResourceAdapterService =
    new AdBlockRustCosmeticResourceAdapterService();
  private cosmeticInjectionService: AdBlockCosmeticInjectionService = new AdBlockCosmeticInjectionService();
  private pingRequestSignalService: AdBlockPingRequestSignalService = new AdBlockPingRequestSignalService();
  private runtimeBootPreparationPromise?: Promise<void>;
  private latestRuntimeContext?: BrowserAdBlockPageRuntimeContext;
  private latestRuntimeLifecyclePort?: BrowserRuntimeLifecyclePort;
  private urlTransformRedirectGuards: Map<string, boolean> = new Map<string, boolean>();
  private privateSiteProtectionOverrides: Map<string, boolean> = new Map<string, boolean>();
  private handledRuntimeRefreshGeneration: number;

  constructor(repository: AdBlockRepository) {
    this.repository = repository;
    this.statsCoordinator = new AdBlockRuntimeStatsCoordinator(repository);
    this.runtimeGeneration = AdBlockRuntimeGenerationCoordinator.forRepository(repository);
    this.handledRuntimeRefreshGeneration = this.runtimeGeneration.getRuntimeRefreshGeneration();
  }

  subscribeRuntimeRefresh(listener: () => void): string {
    return this.runtimeGeneration.subscribeRuntimeRefresh(listener);
  }

  unsubscribeRuntimeRefresh(key: string): void {
    this.runtimeGeneration.unsubscribeRuntimeRefresh(key);
  }

  consumePendingRuntimeRefresh(): boolean {
    const refreshGeneration = this.runtimeGeneration.getRuntimeRefreshGeneration();
    if (refreshGeneration <= this.handledRuntimeRefreshGeneration) {
      return false;
    }
    this.handledRuntimeRefreshGeneration = refreshGeneration;
    return true;
  }

  static prepareRuntimeBootStateForRepository(repository: AdBlockRepository): Promise<void> {
    const runtimeGeneration = AdBlockRuntimeGenerationCoordinator.forRepository(repository);
    const existing = BrowserAdBlockCoordinator.runtimeBootPreparationPromises.get(repository);
    if (existing !== undefined) {
      return existing;
    }
    if (BrowserAdBlockCoordinator.isRepositoryRuntimeReady(repository)) {
      runtimeGeneration.synchronizeWithRepository();
      return BrowserAdBlockCoordinator.completeRustV1NativeArtifactCleanup(repository)
        .then((): Promise<boolean> => BrowserAdBlockCoordinator.reconcileNativeRulesForRepository(repository))
        .then((nativeReady: boolean): void => {
          if (nativeReady) {
            BrowserAdBlockCoordinator.clearRuntimeBootRetry(repository);
          } else {
            BrowserAdBlockCoordinator.runtimeBootPreparedRepositories.delete(repository);
            BrowserAdBlockCoordinator.recordRuntimeBootFailure(repository);
          }
        });
    }
    const promise = repository.initializeRuntimeBootState()
      .then(async (): Promise<void> => {
        await BrowserAdBlockCoordinator.completeRustV1NativeArtifactCleanup(repository);
        runtimeGeneration.synchronizeWithRepository();
        let nativeReady = await BrowserAdBlockCoordinator.reconcileNativeRulesForRepository(repository);
        let unresolvedSourceIds: string[] = [];
        if (!nativeReady) {
          unresolvedSourceIds = await new AdBlockRuleSourceCoordinator(
            repository,
            runtimeGeneration
          ).restoreMissingNativeSourcePayloads();
          runtimeGeneration.synchronizeWithRepository();
          nativeReady = await BrowserAdBlockCoordinator.reconcileNativeRulesForRepository(repository, true);
        }
        if (unresolvedSourceIds.length === 0 && nativeReady) {
          BrowserAdBlockCoordinator.runtimeBootPreparedRepositories.add(repository);
          BrowserAdBlockCoordinator.clearRuntimeBootRetry(repository);
        } else {
          BrowserAdBlockCoordinator.runtimeBootPreparedRepositories.delete(repository);
          BrowserAdBlockCoordinator.recordRuntimeBootFailure(repository);
        }
      })
      .catch((error: Error): void => {
        BrowserAdBlockCoordinator.runtimeBootPreparedRepositories.delete(repository);
        BrowserAdBlockCoordinator.recordRuntimeBootFailure(repository);
        throw error;
      })
      .finally(() => {
        if (BrowserAdBlockCoordinator.runtimeBootPreparationPromises.get(repository) === promise) {
          BrowserAdBlockCoordinator.runtimeBootPreparationPromises.delete(repository);
        }
      });
    BrowserAdBlockCoordinator.runtimeBootPreparationPromises.set(repository, promise);
    return promise;
  }

  private static async completeRustV1NativeArtifactCleanup(repository: AdBlockRepository): Promise<void> {
    await repository.ensureRustV1NativeRuleArtifactCleanup(
      (): Promise<void> => sharedAdBlockNativeRuleProviderService.clearAllArtifacts()
    );
  }

  private static async reconcileNativeRulesForRepository(
    repository: AdBlockRepository,
    forceSourceValidation: boolean = false
  ): Promise<boolean> {
    try {
      const settings = repository.getSettings();
      const nativeResult = await sharedAdBlockNativeRuleProviderService.reconcile(settings, forceSourceValidation);
      const expectedSourceIds: string[] = sharedAdBlockNativeRuleProviderService.resolveEffectiveSources(settings)
        .map((source: AdBlockCustomRuleSource): string => source.id);
      const hasEveryExpectedSource = expectedSourceIds.every((sourceId: string): boolean => {
        return nativeResult.sourceIds.indexOf(sourceId) >= 0;
      });
      const authorityReady = await BrowserAdBlockCoordinator.reconcileNativeAuthority(repository, nativeResult);
      return nativeResult.success && hasEveryExpectedSource && authorityReady;
    } catch (_error) {
      return false;
    }
  }

  private static reconcileNativeAuthority(
    repository: AdBlockRepository,
    nativeResult: AdBlockNativeRuleProviderResult
  ): Promise<boolean> {
    return AdBlockRuntimeGenerationCoordinator.forRepository(repository).reconcileNativeAuthority(nativeResult);
  }

  private static isRepositoryRuntimeReady(repository: AdBlockRepository): boolean {
    return repository.isRuntimeBootStateReady() &&
      BrowserAdBlockCoordinator.runtimeBootPreparedRepositories.has(repository);
  }

  private static canRetryRuntimeBootPreparation(repository: AdBlockRepository): boolean {
    return Date.now() >= (BrowserAdBlockCoordinator.runtimeBootRetryNotBefore.get(repository) ?? 0);
  }

  private static recordRuntimeBootFailure(repository: AdBlockRepository): void {
    const failureCount = BrowserAdBlockCoordinator.runtimeBootFailureCounts.get(repository) ?? 0;
    const delayIndex = Math.min(failureCount, AD_BLOCK_RUNTIME_BOOT_RETRY_DELAYS_MS.length - 1);
    BrowserAdBlockCoordinator.runtimeBootFailureCounts.set(repository, failureCount + 1);
    BrowserAdBlockCoordinator.runtimeBootRetryNotBefore.set(
      repository,
      Date.now() + AD_BLOCK_RUNTIME_BOOT_RETRY_DELAYS_MS[delayIndex]
    );
  }

  private static clearRuntimeBootRetry(repository: AdBlockRepository): void {
    BrowserAdBlockCoordinator.runtimeBootFailureCounts.delete(repository);
    BrowserAdBlockCoordinator.runtimeBootRetryNotBefore.delete(repository);
  }

  resetPageStats(tabId: string): void {
    this.pingRequestSignalService.clearTab(tabId);
    this.statsCoordinator.resetPageStats(tabId);
  }

  getPageBlockedCount(tabId: string): number {
    return this.statsCoordinator.getPageBlockedCount(tabId);
  }

  getPageProtectionSnapshot(tabId: string): AdBlockRuntimePageProtectionSnapshot {
    return this.statsCoordinator.getPageProtectionSnapshot(tabId);
  }

  getProtectionActivitySummary(now: number = Date.now()): AdBlockProtectionActivitySummary {
    return this.repository.getProtectionActivitySummary(now);
  }

  clearPrivateSiteProtectionOverrides(profileId: BrowserProfileId): void {
    const prefix = `${profileId}\u0001`;
    this.privateSiteProtectionOverrides.forEach((_enabled: boolean, key: string): void => {
      if (key.startsWith(prefix)) {
        this.privateSiteProtectionOverrides.delete(key);
      }
    });
  }

  configureControllerForPage(
    context: BrowserAdBlockPageRuntimeContext,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): BrowserAdBlockControllerApplyResult {
    this.ensureRuntimeBootStatePrepared(context, runtimeLifecyclePort);
    return this.applyControllerForPage(context, runtimeLifecyclePort);
  }

  private applyControllerForPage(
    context: BrowserAdBlockPageRuntimeContext,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): BrowserAdBlockControllerApplyResult {
    if (!context.capabilitySupported || !context.controllerAttached) {
      return { capabilitySupported: context.capabilitySupported };
    }
    const controller = runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return { capabilitySupported: context.capabilitySupported };
    }
    this.registerPingNativeBridge(context.tabId, controller);
    return { capabilitySupported: context.capabilitySupported };
  }

  resolveProtectionStatus(
    context: BrowserAdBlockPageRuntimeContext,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): BrowserAdBlockProtectionStatusResult {
    try {
      const controller = runtimeLifecyclePort.resolveActiveController();
      const snapshot = this.resolveSnapshot();
      const policy = this.resolveEffectivePagePolicy(snapshot, {
        tabId: context.tabId,
        pageUrl: context.pageUrl,
        capabilitySupported: context.capabilitySupported,
        controllerAttached: context.controllerAttached && controller !== undefined,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      });
      const siteState = this.resolveSiteProtectionState({
        pageUrl: context.pageUrl,
        capabilitySupported: context.capabilitySupported,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      });
      const nativeAuthorityReady = this.runtimeGeneration.isNativeAuthorityReady();
      if (!policy.enabledForPage || controller === undefined || !nativeAuthorityReady) {
        return {
          capabilitySupported: context.capabilitySupported,
          availabilityState: this.resolveProtectionAvailabilityState(snapshot, policy, siteState.siteEnabled, undefined, context.tabId),
          summary: policy.enabledForPage && controller !== undefined && !nativeAuthorityReady
            ? '网页内容过滤引擎暂不可用'
            : this.buildSummary(policy.summary, context.tabId),
          siteToggleEnabled: siteState.siteToggleEnabled,
          siteEnabled: siteState.siteEnabled
        };
      }
      return {
        capabilitySupported: context.capabilitySupported,
        availabilityState: this.resolveProtectionAvailabilityState(
          snapshot,
          policy,
          siteState.siteEnabled,
          true,
          context.tabId
        ),
        summary: this.buildSummary(policy.summary, context.tabId),
        siteToggleEnabled: siteState.siteToggleEnabled,
        siteEnabled: siteState.siteEnabled
      };
    } catch (_error) {
      return {
        capabilitySupported: false,
        availabilityState: 'capability_unavailable',
        summary: this.policyService.buildCapabilityUnavailableSummary(),
        siteToggleEnabled: false,
        siteEnabled: false
      };
    }
  }

  recordCosmeticSelectors(
    tabId: string,
    selectors: string[],
    hiddenElementCount: number,
    placeholderCollapsedCount: number = 0
  ): void {
    this.statsCoordinator.recordCosmeticSelectors(
      tabId,
      selectors,
      hiddenElementCount,
      placeholderCollapsedCount
    );
  }

  recordCosmeticHiddenElements(tabId: string, hiddenElementCount: number): void {
    this.statsCoordinator.recordCosmeticHiddenElements(tabId, hiddenElementCount);
  }

  recordCosmeticHiddenFromPayload(
    context: BrowserAdBlockCosmeticHiddenPayloadContext
  ): AdBlockRuntimeCosmeticHiddenResult {
    try {
      const payload = JSON.parse(context.payloadJson) as BrowserAdBlockCosmeticHiddenPayload;
      const totalCount = this.normalizeRuntimeCount(Number.parseInt(`${payload.count ?? 0}`, 10));
      let hiddenElementCount = this.normalizeRuntimeCount(
        Number.parseInt(`${payload.hiddenElementCount ?? 0}`, 10)
      );
      if (hiddenElementCount <= 0 && totalCount > 0) {
        hiddenElementCount = totalCount;
      }
      const pageUrl = `${payload.pageUrl ?? ''}`.trim();
      if (pageUrl.length <= 0) {
        return this.emptyCosmeticHiddenResult();
      }
      return this.statsCoordinator.recordCosmeticHiddenFromRuntime({
        tabId: context.tabId,
        pageUrl: pageUrl,
        currentPageUrl: context.currentPageUrl,
        hiddenElementCount: hiddenElementCount
      });
    } catch (_error) {
      return this.emptyCosmeticHiddenResult();
    }
  }

  recordManualElementsHidden(context: BrowserAdBlockManualHiddenContext): void {
    this.statsCoordinator.recordManualElementsHidden({
      tabId: context.tabId,
      hiddenElementCount: context.hiddenElementCount,
      profileId: context.profileId,
      dataScope: context.dataScope
    });
  }

  async injectCosmeticRulesForPage(
    context: BrowserAdBlockPageRuntimeContext,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort
  ): Promise<AdBlockCosmeticInjectionSummary> {
    const snapshot = this.resolveSnapshot();
    const policy = this.resolveEffectivePagePolicy(snapshot, context);
    const cosmeticElementBlockingEnabled = snapshot.settings.preferences.enabled && !policy.allowlisted;
    if (!cosmeticElementBlockingEnabled) {
      this.statsCoordinator.clearCosmeticStatsContext(context.tabId);
      await this.cosmeticInjectionService.clearForPage(runtimeLifecyclePort.resolveController(context.tabId));
      return this.skippedCosmeticInjection('disabled');
    }
    const controller = runtimeLifecyclePort.resolveController(context.tabId);
    const candidates = await this.cosmeticInjectionService.collectSelectorCandidates(controller);
    const resources = this.runtimeGeneration.resolveNativeCosmeticResources(
      context.pageUrl,
      candidates.classes,
      candidates.ids
    );
    if (resources === undefined) {
      this.statsCoordinator.clearCosmeticStatsContext(context.tabId);
      await this.cosmeticInjectionService.clearForPage(controller);
      return this.skippedCosmeticInjection('native_authority_unavailable');
    }
    const cosmeticPlan = this.cosmeticResourceAdapter.buildExecutionPlan(resources);
    await this.cosmeticInjectionService.executeInjectedScript(controller, resources.injectedScript);
    const summary = await this.cosmeticInjectionService.injectForPage(
      controller,
      context.pageUrl,
      cosmeticPlan,
      true
    );
    if (summary.skipped) {
      this.statsCoordinator.clearCosmeticStatsContext(context.tabId);
      return summary;
    }
    this.statsCoordinator.setCosmeticStatsContext(context.tabId, context.profileId, context.dataScope);
    return summary;
  }

  handleInterceptRequest(context: BrowserAdBlockRequestContext): WebResourceResponse | null {
    try {
      const requestUrl = context.request.getRequestUrl();
      const snapshot = this.resolveSnapshot();
      const policy = this.resolveEffectivePagePolicy(snapshot, this.buildPageRuntimeContext(context));
      if (policy.allowlisted) {
        return null;
      }
      const requestMethod = context.request.getRequestMethod();
      const isMainFrame = context.request.isMainFrame();
      const isRedirect = context.request.isRedirect();
      const signaledPing = !isMainFrame &&
        this.pingRequestSignalService.consume(context.tabId, requestUrl, requestMethod);
      const classification: AdBlockRequestClassification = signaledPing
        ? {
          resourceType: 'ping',
          confidence: 'high',
          evidence: ['document_start_ping_signal']
        }
        : this.requestClassifier.classify({
          url: requestUrl,
          pageUrl: context.pageUrl,
          method: requestMethod,
          isMainFrame: isMainFrame,
          isRedirect: isRedirect,
          request: context.request
        });
      const enabledForRequest = this.isFilteringEnabledForRequest(
        snapshot,
        policy,
        context.strengthenForSmoothScroll
      );
      const evaluationInput: AdBlockRequestEvaluationInput = {
        url: requestUrl,
        pageUrl: context.pageUrl,
        method: requestMethod,
        isMainFrame: isMainFrame,
        resourceType: classification.resourceType,
        enabled: enabledForRequest,
        includeResponseEvaluation: true
      };
      const evaluation = this.runtimeGeneration.evaluateNetworkRequest(evaluationInput);
      const decision = evaluation.network;
      if (decision.shouldBlock) {
        const response = decision.redirectDataUrl.length > 0
          ? this.responseFactory.buildRustRedirectResponse(decision.redirectDataUrl)
          : this.responseFactory.buildEmptyResponse(requestUrl);
        this.statsCoordinator.recordNetworkBlocked({
          tabId: context.tabId,
          profileId: context.profileId,
          dataScope: context.dataScope
        });
        return response;
      }
      const transformGuardKey = this.buildUrlTransformRedirectGuardKey(
        context.tabId,
        snapshot.version,
        requestUrl
      );
      const rewrittenUrl = decision.rewrittenUrl.trim();
      if (requestMethod.trim().toUpperCase() === 'GET' && rewrittenUrl.length > 0 &&
        rewrittenUrl !== requestUrl && !this.urlTransformRedirectGuards.has(transformGuardKey)) {
        this.rememberUrlTransformRedirectTarget(context.tabId, snapshot.version, rewrittenUrl);
        if (isMainFrame) {
          this.statsCoordinator.recordUrlParametersRemoved({
            tabId: context.tabId,
            removedParameterCount: this.countRemovedUrlParameters(requestUrl, rewrittenUrl),
            profileId: context.profileId,
            dataScope: context.dataScope
          });
        }
        return this.responseFactory.buildUrlTransformRedirectResponse(rewrittenUrl);
      }

      const cspRequestIdentity: AdBlockCspRequestIdentity = {
        tabId: context.tabId,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope,
        url: requestUrl
      };
      if (this.responseFactory.consumeCspNativeFallback(cspRequestIdentity)) {
        return null;
      }
      const responseDecision = evaluation.response;
      if (responseDecision.cspDirectives.length <= 0) {
        return null;
      }
      const cspResponseInput: AdBlockCspResponseInput = {
        tabId: context.tabId,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope,
        url: requestUrl,
        requestHeaders: context.request.getRequestHeader(),
        directives: responseDecision.cspDirectives
      };
      const response = this.responseFactory.buildCspResponse(cspResponseInput);
      this.statsCoordinator.recordNetworkBlocked({
        tabId: context.tabId,
        profileId: context.profileId,
        dataScope: context.dataScope
      });
      return response;
    } catch (_error) {
      return null;
    }
  }

  shouldBlockMainFrameNavigation(context: BrowserAdBlockRequestContext): boolean {
    try {
      const requestUrl = context.request.getRequestUrl();
      const snapshot = this.resolveSnapshot();
      const policy = this.resolveEffectivePagePolicy(snapshot, this.buildPageRuntimeContext(context));
      if (policy.allowlisted) {
        return false;
      }
      const requestMethod = context.request.getRequestMethod();
      const evaluation = this.runtimeGeneration.evaluateNetworkRequest({
        url: requestUrl,
        pageUrl: context.pageUrl,
        method: requestMethod,
        isMainFrame: true,
        resourceType: 'document',
        enabled: this.isFilteringEnabledForRequest(snapshot, policy, context.strengthenForSmoothScroll),
        includeResponseEvaluation: false
      });
      const decision = evaluation.network;
      if (!decision.shouldBlock) {
        return false;
      }
      if (decision.redirectDataUrl.length > 0) {
        return false;
      }
      this.statsCoordinator.recordNetworkBlocked({
        tabId: context.tabId,
        profileId: context.profileId,
        dataScope: context.dataScope
      });
      return true;
    } catch (_error) {
      return false;
    }
  }

  cleanNavigationUrl(context: BrowserAdBlockRequestContext): BrowserAdBlockUrlTransformResult {
    try {
      const requestUrl = context.request.getRequestUrl();
      if (!context.request.isMainFrame()) {
        return this.urlTransformUnchanged(requestUrl);
      }
      const requestMethod = context.request.getRequestMethod().trim().toUpperCase();
      if (requestMethod.length > 0 && requestMethod !== 'GET' && requestMethod !== 'HEAD') {
        return this.urlTransformUnchanged(requestUrl);
      }
      const snapshot = this.resolveSnapshot();
      const policy = this.resolveEffectivePagePolicy(snapshot, {
        tabId: context.tabId,
        pageUrl: requestUrl,
        capabilitySupported: context.capabilitySupported,
        controllerAttached: true,
        profileId: context.profileId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      });
      if (policy.allowlisted) {
        return this.urlTransformUnchanged(requestUrl);
      }
      const evaluation = this.runtimeGeneration.evaluateNetworkRequest({
        url: requestUrl,
        pageUrl: requestUrl,
        method: requestMethod,
        isMainFrame: true,
        resourceType: 'document',
        enabled: this.isFilteringEnabledForRequest(snapshot, policy, context.strengthenForSmoothScroll),
        includeResponseEvaluation: false
      });
      const rewrittenUrl = evaluation.network.rewrittenUrl.trim();
      if (evaluation.network.shouldBlock || rewrittenUrl.length <= 0 || rewrittenUrl === requestUrl) {
        return this.urlTransformUnchanged(requestUrl);
      }
      const removedParameterCount = this.countRemovedUrlParameters(requestUrl, rewrittenUrl);
      if (removedParameterCount > 0) {
        this.statsCoordinator.recordNavigationUrlCleaned({
          tabId: context.tabId,
          removedParameterCount: removedParameterCount,
          profileId: context.profileId,
          dataScope: context.dataScope
        });
      }
      return {
        url: rewrittenUrl,
        changed: true
      };
    } catch (_error) {
      return this.urlTransformUnchanged('');
    }
  }

  buildSummary(baseSummary: string, tabId: string): string {
    return this.statsCoordinator.buildPageSummary(baseSummary, tabId);
  }

  resolveSiteProtectionState(
    context: BrowserAdBlockSiteProtectionToggleContext
  ): BrowserAdBlockSiteProtectionStateResult {
    const snapshot = this.resolveSnapshot();
    const siteState = this.policyService.resolveSiteProtectionState(
      snapshot.settings,
      context.pageUrl,
      context.capabilitySupported,
      context.profileId
    );
    const privateOverride = this.resolvePrivateSiteProtectionOverride(
      context.pageUrl,
      context.profileId,
      context.privacyMode,
      context.dataScope
    );
    return {
      siteToggleEnabled: siteState.canToggle,
      siteEnabled: privateOverride ?? siteState.siteEnabled
    };
  }

  resolvePrivacyCoverage(context: BrowserAdBlockPageRuntimeContext): BrowserAdBlockPrivacyCoverageResult {
    const snapshot = this.resolveSnapshot();
    const policy = this.resolveEffectivePagePolicy(snapshot, context);
    if (!context.capabilitySupported) {
      return { state: 'unavailable', summary: '当前设备暂不支持隐私规则保护' };
    }
    if (!snapshot.settings.preferences.enabled) {
      return { state: 'disabled', summary: '请先开启网页内容过滤' };
    }
    if (policy.allowlisted) {
      return {
        state: 'site_disabled',
        summary: context.dataScope === 'session_ephemeral' ? '本次私密会话已关闭本站保护' : '本站网页保护已关闭'
      };
    }
    const source = snapshot.settings.customRuleSources.find((item: AdBlockCustomRuleSource): boolean => {
      return item.id === (findAdBlockThirdPartyRuleSource('third-party-easyprivacy')?.id ?? 'third-party-easyprivacy');
    });
    if (source === undefined || !source.enabled) {
      return { state: 'disabled', summary: 'EasyPrivacy 隐私规则未开启' };
    }
    if (source.lastError.trim().length > 0) {
      return { state: 'failed', summary: 'EasyPrivacy 隐私规则加载失败' };
    }
    if (source.ruleCount <= 0 || !this.hasLoadedRules(source)) {
      return { state: 'preparing', summary: 'EasyPrivacy 隐私规则正在准备' };
    }
    return { state: 'enabled', summary: 'EasyPrivacy 隐私规则正在生效' };
  }

  async toggleSiteProtection(
    context: BrowserAdBlockSiteProtectionToggleContext
  ): Promise<BrowserAdBlockSiteProtectionToggleResult> {
    const settings = this.repository.getSettings();
    const siteState = this.policyService.resolveSiteProtectionState(
      settings,
      context.pageUrl,
      context.capabilitySupported,
      context.profileId
    );
    if (siteState.host.length === 0) {
      return this.buildSiteProtectionToggleFailure('当前页面暂不支持本站网页内容过滤');
    }
    if (!siteState.canToggle) {
      return this.buildSiteProtectionToggleFailure(
        settings.preferences.enabled ? '当前设备暂不支持网页内容过滤' : '请先开启网页内容过滤'
      );
    }
    const effectiveState = this.resolveSiteProtectionState(context);
    if (context.dataScope === 'session_ephemeral' || context.privacyMode === 'private') {
      const nextEnabled = !effectiveState.siteEnabled;
      this.privateSiteProtectionOverrides.set(
        this.buildPrivateSiteProtectionOverrideKey(context.profileId, siteState.host),
        nextEnabled
      );
      return {
        success: true,
        siteEnabled: nextEnabled,
        summary: nextEnabled ? '已开启，仅本次私密会话生效' : '已关闭，仅本次私密会话生效',
        toast: nextEnabled ? '已开启本站网页保护，仅本次私密会话生效' : '已关闭本站网页保护，仅本次私密会话生效'
      };
    }
    if (effectiveState.siteEnabled) {
      await this.runtimeGeneration.addSiteException(siteState.host, context.profileId);
      return {
        success: true,
        siteEnabled: false,
        summary: '此站点已关闭网页内容过滤',
        toast: '已关闭本站网页内容过滤'
      };
    }
    await this.runtimeGeneration.removeSiteException(siteState.host, context.profileId);
    return {
      success: true,
      siteEnabled: true,
      summary: '已开启，暂无拦截',
      toast: '已开启本站网页内容过滤'
    };
  }

  private buildSiteProtectionToggleFailure(toast: string): BrowserAdBlockSiteProtectionToggleResult {
    return {
      success: false,
      siteEnabled: false,
      summary: '',
      toast: toast
    };
  }

  private urlTransformUnchanged(url: string): BrowserAdBlockUrlTransformResult {
    return {
      url: url,
      changed: false
    };
  }

  private isFilteringEnabledForRequest(
    snapshot: AdBlockRuntimeSnapshot,
    policy: AdBlockPagePolicyResult,
    strengthenForSmoothScroll: boolean
  ): boolean {
    return snapshot.settings.preferences.enabled &&
      (policy.enabledForPage || (!policy.allowlisted && strengthenForSmoothScroll));
  }

  private countRemovedUrlParameters(originalUrl: string, rewrittenUrl: string): number {
    try {
      const originalKeys = this.parseUrlQueryKeys(urlUtils.URL.parseURL(originalUrl).search);
      const rewrittenKeys = this.parseUrlQueryKeys(urlUtils.URL.parseURL(rewrittenUrl).search);
      let removedCount: number = 0;
      originalKeys.forEach((key: string): void => {
        const rewrittenIndex = rewrittenKeys.indexOf(key);
        if (rewrittenIndex >= 0) {
          rewrittenKeys.splice(rewrittenIndex, 1);
        } else {
          removedCount += 1;
        }
      });
      return Math.max(1, removedCount);
    } catch (_error) {
      return 1;
    }
  }

  private parseUrlQueryKeys(search: string): string[] {
    const query = search.startsWith('?') ? search.substring(1) : search;
    if (query.length <= 0) {
      return [];
    }
    const keys: string[] = [];
    query.split('&').forEach((part: string): void => {
      if (part.length <= 0) {
        return;
      }
      const equalsIndex = part.indexOf('=');
      keys.push(equalsIndex >= 0 ? part.substring(0, equalsIndex) : part);
    });
    return keys;
  }

  private skippedCosmeticInjection(reason: string): AdBlockCosmeticInjectionSummary {
    return {
      injectedSelectorCount: 0,
      hiddenElementCount: 0,
      placeholderCollapsedCount: 0,
      totalActionCount: 0,
      hiddenClickRectCount: 0,
      guardListenerCount: 0,
      selectors: [],
      skipped: true,
      reason: reason
    };
  }

  private normalizeRuntimeCount(value: number): number {
    return typeof value === 'number' && !Number.isNaN(value) && value > 0 ? Math.round(value) : 0;
  }

  private emptyCosmeticHiddenResult(): AdBlockRuntimeCosmeticHiddenResult {
    return {
      totalActionCount: 0,
      hiddenElementCount: 0,
      placeholderCollapsedCount: 0
    };
  }

  private resolveSnapshot(): AdBlockRuntimeSnapshot {
    this.ensureRuntimeBootStatePrepared();
    return this.runtimeGeneration.current();
  }

  private resolveEffectivePagePolicy(
    snapshot: AdBlockRuntimeSnapshot,
    context: BrowserAdBlockPageRuntimeContext
  ): AdBlockPagePolicyResult {
    const privateOverride = this.resolvePrivateSiteProtectionOverride(
      context.pageUrl,
      context.profileId,
      context.privacyMode,
      context.dataScope
    );
    if (privateOverride === undefined) {
      return this.policyService.resolvePagePolicyForRuntime(
        snapshot.policy,
        context.pageUrl,
        context.capabilitySupported,
        context.controllerAttached,
        context.profileId,
        context.privacyMode,
        context.dataScope
      );
    }
    const policyWithoutPersistentSiteExceptions = this.policyService.resolvePagePolicyForRuntime({
      preferences: snapshot.policy.preferences,
      siteExceptions: [],
      enabledRuleSourceCount: snapshot.policy.enabledRuleSourceCount
    }, context.pageUrl, context.capabilitySupported, context.controllerAttached, context.profileId,
      context.privacyMode, context.dataScope);
    if (!privateOverride) {
      return {
        available: policyWithoutPersistentSiteExceptions.available,
        enabledForPage: false,
        allowlisted: true,
        summary: '本次私密会话已关闭本站网页保护'
      };
    }
    if (!policyWithoutPersistentSiteExceptions.enabledForPage) {
      return policyWithoutPersistentSiteExceptions;
    }
    return {
      available: true,
      enabledForPage: true,
      allowlisted: false,
      summary: '已开启，仅本次私密会话生效'
    };
  }

  private buildPageRuntimeContext(context: BrowserAdBlockRequestContext): BrowserAdBlockPageRuntimeContext {
    return {
      tabId: context.tabId,
      pageUrl: context.pageUrl,
      capabilitySupported: context.capabilitySupported,
      controllerAttached: context.controllerAttached,
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope
    };
  }

  private resolveProtectionAvailabilityState(
    snapshot: AdBlockRuntimeSnapshot,
    policy: AdBlockPagePolicyResult,
    siteEnabled: boolean,
    controllerPageEnabled: boolean | undefined,
    tabId: string
  ): BrowserAdBlockProtectionAvailabilityState {
    if (!snapshot.settings.preferences.enabled || snapshot.policy.enabledRuleSourceCount <= 0) {
      return 'global_disabled_or_unconfigured';
    }
    if (!siteEnabled || policy.allowlisted) {
      return 'site_disabled';
    }
    if (!policy.available || controllerPageEnabled === undefined) {
      return 'capability_unavailable';
    }
    if (!policy.enabledForPage || !controllerPageEnabled) {
      return 'global_disabled_or_unconfigured';
    }
    return this.statsCoordinator.getPageProtectionSnapshot(tabId).totalActionCount > 0
      ? 'active_with_actions'
      : 'active_without_actions';
  }

  private resolvePrivateSiteProtectionOverride(
    pageUrl: string,
    profileId: BrowserProfileId,
    privacyMode: BrowserSessionPrivacyMode,
    dataScope: BrowserDataScope
  ): boolean | undefined {
    if (privacyMode !== 'private' && dataScope !== 'session_ephemeral') {
      return undefined;
    }
    const host = this.policyService.extractHost(pageUrl);
    if (host.length <= 0) {
      return undefined;
    }
    return this.privateSiteProtectionOverrides.get(
      this.buildPrivateSiteProtectionOverrideKey(profileId, host)
    );
  }

  private buildPrivateSiteProtectionOverrideKey(profileId: BrowserProfileId, host: string): string {
    return `${profileId}\u0001${host.trim().toLowerCase()}`;
  }

  private hasLoadedRules(source: AdBlockCustomRuleSource): boolean {
    return (source.nativeNetworkRuleCount ?? 0) > 0 || (source.nativeCosmeticRuleCount ?? 0) > 0;
  }

  private ensureRuntimeBootStatePrepared(
    context?: BrowserAdBlockPageRuntimeContext,
    runtimeLifecyclePort?: BrowserRuntimeLifecyclePort
  ): void {
    if (context !== undefined && runtimeLifecyclePort !== undefined) {
      this.latestRuntimeContext = this.cloneRuntimeContext(context);
      this.latestRuntimeLifecyclePort = runtimeLifecyclePort;
    }
    if (BrowserAdBlockCoordinator.isRepositoryRuntimeReady(this.repository) ||
      this.runtimeBootPreparationPromise !== undefined ||
      !BrowserAdBlockCoordinator.canRetryRuntimeBootPreparation(this.repository)) {
      return;
    }
    const promise = BrowserAdBlockCoordinator.prepareRuntimeBootStateForRepository(this.repository)
      .then(() => {
        this.applyLatestRuntimeBootState();
      })
      .catch((_error: Error) => undefined)
      .finally(() => {
        if (this.runtimeBootPreparationPromise === promise) {
          this.runtimeBootPreparationPromise = undefined;
        }
      });
    this.runtimeBootPreparationPromise = promise;
  }

  private applyLatestRuntimeBootState(): void {
    if (this.latestRuntimeContext === undefined || this.latestRuntimeLifecyclePort === undefined) {
      return;
    }
    this.applyControllerForPage(this.latestRuntimeContext, this.latestRuntimeLifecyclePort);
  }

  private cloneRuntimeContext(context: BrowserAdBlockPageRuntimeContext): BrowserAdBlockPageRuntimeContext {
    return {
      tabId: context.tabId,
      pageUrl: context.pageUrl,
      capabilitySupported: context.capabilitySupported,
      controllerAttached: context.controllerAttached,
      profileId: context.profileId,
      privacyMode: context.privacyMode,
      dataScope: context.dataScope
    };
  }

  private buildNetworkBlockedDiagnosticsCode(ruleDiagnosticsCode: string): string {
    const normalized = ruleDiagnosticsCode.trim();
    return normalized.length > 0 ? `adblock_network_blocked/${normalized}` : 'adblock_network_blocked';
  }

  private registerPingNativeBridge(tabId: string, controller: webview.WebviewController): void {
    const normalizedTabId = tabId.trim();
    if (normalizedTabId.length <= 0) {
      return;
    }
    try {
      controller.deleteJavaScriptRegister(AD_BLOCK_PING_NATIVE_BRIDGE_NAME);
    } catch (_error) {
    }
    try {
      controller.registerJavaScriptProxy(
        new BrowserAdBlockPingNativeBridge(normalizedTabId, this.pingRequestSignalService),
        AD_BLOCK_PING_NATIVE_BRIDGE_NAME,
        AD_BLOCK_PING_NATIVE_BRIDGE_METHODS
      );
    } catch (_error) {
    }
  }

  private rememberUrlTransformRedirectTarget(tabId: string, snapshotVersion: number, url: string): void {
    if (this.urlTransformRedirectGuards.size >= 512) {
      this.urlTransformRedirectGuards.clear();
    }
    this.urlTransformRedirectGuards.set(
      this.buildUrlTransformRedirectGuardKey(tabId, snapshotVersion, url),
      true
    );
  }

  private buildUrlTransformRedirectGuardKey(tabId: string, snapshotVersion: number, url: string): string {
    return `${tabId}\u0001${snapshotVersion}\u0001${url}`;
  }

}
