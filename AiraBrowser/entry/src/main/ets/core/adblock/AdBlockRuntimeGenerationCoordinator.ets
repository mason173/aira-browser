import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AdBlockCustomRuleSource,
  AdBlockDailyProtectionActivity,
  AdBlockPreferences,
  AdBlockSettings,
  AdBlockSiteException,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID
} from '../../common/models/BrowserModels';
import {
  AdBlockPreparedSettingsCommit,
  AdBlockRepository,
  AdBlockSettingsMutation
} from '../../data/adblock/AdBlockRepository';
import {
  AdBlockRequestDecision,
  AdBlockRequestEvaluation,
  AdBlockRequestEvaluationInput,
  AdBlockResponseDecision
} from '../../services/adblock/AdBlockRequestEvaluationModels';
import {
  AdBlockNativeRuleProviderResult,
  sharedAdBlockNativeRuleProviderService
} from '../../services/adblock/AdBlockNativeRuleProviderService';
import {
  AdBlockNativeAuthorityBuildResult,
  AdBlockNativeAuthorityEvaluation,
  AdBlockNativeCosmeticResources,
  AdBlockNativeAuthorityEngineService
} from '../../services/adblock/AdBlockNativeAuthorityEngineService';
import {
  AdBlockRuntimeSnapshot
} from './AdBlockRuntimeSnapshot';
import {
  AdBlockNativeAuthorityMetrics
} from './AdBlockNativeAuthorityMetrics';

const MAX_PREPARED_GENERATIONS: number = 4;
const NATIVE_AUTHORITY_METRICS_LOG_INTERVAL: number = 16;
const DOMAIN = 0x0000;
const TAG = 'AdBlockRuntimeGeneration';

export type AdBlockRuntimeRefreshListener = () => void;

export class AdBlockRuntimeGenerationCoordinator {
  private static coordinatorsByRepository: Map<AdBlockRepository, AdBlockRuntimeGenerationCoordinator> =
    new Map<AdBlockRepository, AdBlockRuntimeGenerationCoordinator>();

  private repository: AdBlockRepository;
  private preparedSnapshots: Map<string, AdBlockRuntimeSnapshot> = new Map<string, AdBlockRuntimeSnapshot>();
  private activeSnapshot?: AdBlockRuntimeSnapshot;
  private nextVersion: number = 1;
  private metrics: AdBlockNativeAuthorityMetrics = new AdBlockNativeAuthorityMetrics();
  private mutationTask: Promise<void> = Promise.resolve();
  private nativeAuthorityService: AdBlockNativeAuthorityEngineService = new AdBlockNativeAuthorityEngineService();
  private nativeAuthorityHandle: number = 0;
  private nativeAuthorityIdentity: string = '';
  private nativeAuthorityReferenceKey: string = '';
  private nativeAuthoritySourceIds: string[] = [];
  private nativeAuthorityBuildToken: number = 0;
  private runtimeRefreshGeneration: number = 0;
  private runtimeRefreshListenerSequence: number = 0;
  private runtimeRefreshListeners: Record<string, AdBlockRuntimeRefreshListener | undefined> = {};

  private constructor(repository: AdBlockRepository) {
    this.repository = repository;
  }

  static forRepository(repository: AdBlockRepository): AdBlockRuntimeGenerationCoordinator {
    const existing = AdBlockRuntimeGenerationCoordinator.coordinatorsByRepository.get(repository);
    if (existing !== undefined) {
      return existing;
    }
    const coordinator = new AdBlockRuntimeGenerationCoordinator(repository);
    AdBlockRuntimeGenerationCoordinator.coordinatorsByRepository.set(repository, coordinator);
    coordinator.synchronizeWithRepository();
    return coordinator;
  }

  synchronizeWithRepository(): AdBlockRuntimeSnapshot {
    const settings = this.repository.getSettings();
    const snapshot = this.prepareCandidate(settings);
    this.activateSnapshot(snapshot);
    return snapshot;
  }

  updatePreferences(preferences: AdBlockPreferences): Promise<AdBlockSettings> {
    return this.enqueueMutation(async (): Promise<AdBlockSettings> => {
      const previousPreferences: AdBlockPreferences = this.repository.getSettings().preferences;
      const enabledChanged: boolean = previousPreferences.enabled !== preferences.enabled;
      const settings = await this.commitMutation({
        kind: 'update_preferences',
        changedAt: Date.now(),
        preferences: preferences
      });
      if (!preferences.enabled) {
        this.nativeAuthorityBuildToken += 1;
        this.releaseNativeAuthority();
        if (enabledChanged) {
          this.requestRuntimeRefresh();
        }
        return settings;
      }
      if (!await this.synchronizeNativeAuthority(settings)) {
        await this.commitMutation({
          kind: 'update_preferences',
          changedAt: Date.now(),
          preferences: previousPreferences
        });
        throw new Error('Rust filtering authority could not be activated.');
      }
      if (enabledChanged) {
        this.requestRuntimeRefresh();
      }
      return settings;
    });
  }

  getRuntimeRefreshGeneration(): number {
    return this.runtimeRefreshGeneration;
  }

  subscribeRuntimeRefresh(listener: AdBlockRuntimeRefreshListener): string {
    this.runtimeRefreshListenerSequence += 1;
    const key = `adblock-runtime-refresh-${this.runtimeRefreshListenerSequence}`;
    this.runtimeRefreshListeners[key] = listener;
    return key;
  }

  unsubscribeRuntimeRefresh(key: string): void {
    this.runtimeRefreshListeners[key] = undefined;
  }

  addSiteException(
    host: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<AdBlockSettings> {
    return this.enqueueMutation((): Promise<AdBlockSettings> => {
      return this.commitMutation({
        kind: 'add_site_exception',
        changedAt: Date.now(),
        host: host,
        profileId: profileId
      });
    });
  }

  removeSiteException(
    host: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): Promise<AdBlockSettings> {
    return this.enqueueMutation((): Promise<AdBlockSettings> => {
      return this.commitMutation({
        kind: 'remove_site_exception',
        changedAt: Date.now(),
        host: host,
        profileId: profileId
      });
    });
  }

  async upsertCustomRuleSource(source: AdBlockCustomRuleSource): Promise<AdBlockSettings> {
    return this.enqueueMutation(async (): Promise<AdBlockSettings> => {
      const prepared = await this.repository.prepareSettingsMutation({
        kind: 'upsert_rule_source',
        changedAt: Date.now(),
        source: source
      });
      const snapshot = this.prepareCandidate(prepared.settings);
      return this.commitPreparedMutation(prepared, snapshot);
    });
  }

  updateCustomRuleSourceEnabled(sourceId: string, enabled: boolean): Promise<AdBlockSettings> {
    return this.enqueueMutation(async (): Promise<AdBlockSettings> => {
      return this.commitMutation({
        kind: 'set_rule_source_enabled',
        changedAt: Date.now(),
        sourceId: sourceId,
        enabled: enabled
      });
    });
  }

  removeCustomRuleSource(sourceId: string): Promise<AdBlockSettings> {
    return this.enqueueMutation((): Promise<AdBlockSettings> => {
      return this.commitMutation({
        kind: 'remove_rule_source',
        changedAt: Date.now(),
        sourceId: sourceId
      });
    });
  }

  current(): AdBlockRuntimeSnapshot {
    if (this.activeSnapshot === undefined) {
      throw new Error('Ad-block runtime generation is not initialized.');
    }
    return this.activeSnapshot;
  }

  resolveNativeCosmeticResources(
    pageUrl: string,
    classes: string[] = [],
    ids: string[] = []
  ): AdBlockNativeCosmeticResources | undefined {
    const normalizedUrl = pageUrl.trim().toLowerCase();
    if (this.nativeAuthorityHandle <= 0 ||
      (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://'))) {
      return undefined;
    }
    try {
      return this.nativeAuthorityService.getCosmeticResources(
        this.nativeAuthorityHandle,
        pageUrl,
        JSON.stringify(classes),
        JSON.stringify(ids)
      );
    } catch (_error) {
      return undefined;
    }
  }

  evaluateNetworkRequest(input: AdBlockRequestEvaluationInput): AdBlockRequestEvaluation {
    return this.evaluateWithNativeAuthority(input);
  }

  async synchronizeNativeAuthority(settings: AdBlockSettings = this.repository.getSettings()): Promise<boolean> {
    const result = await sharedAdBlockNativeRuleProviderService.reconcile(settings);
    return this.reconcileNativeAuthority(result);
  }

  async reconcileNativeAuthority(result: AdBlockNativeRuleProviderResult): Promise<boolean> {
    const buildToken = this.nativeAuthorityBuildToken + 1;
    this.nativeAuthorityBuildToken = buildToken;
    const snapshot = this.current();
    if (!snapshot.settings.preferences.enabled) {
      this.releaseNativeAuthority();
      return true;
    }
    if (result.success && result.sourceCount === 0) {
      this.releaseNativeAuthority();
      return true;
    }
    if (!result.success || result.identity.length === 0 || result.rulesetPath.length === 0 ||
      result.ruleLineCount <= 0 || result.sourceIds.length === 0) {
      this.releaseNativeAuthority();
      return false;
    }
    const referenceSources = this.resolveNativeAuthorityReferenceSources(snapshot, result.sourceIds);
    if (referenceSources.length !== result.sourceIds.length) {
      this.releaseNativeAuthority();
      return false;
    }
    const referenceKey = this.buildNativeAuthorityReferenceKey(referenceSources);
    if (this.nativeAuthorityIdentity === result.identity &&
      this.nativeAuthorityReferenceKey === referenceKey && this.nativeAuthorityHandle > 0) {
      return true;
    }
    this.releaseNativeAuthority();
    let builtHandle: number = 0;
    try {
      const buildResult: AdBlockNativeAuthorityBuildResult =
        await this.nativeAuthorityService.buildEngine(result.rulesetPath);
      builtHandle = buildResult.handle;
      if (buildResult.ruleCount <= 0) {
        throw new Error('Rust authority compiled no rules.');
      }
      const currentSnapshot = this.current();
      if (!currentSnapshot.settings.preferences.enabled) {
        this.nativeAuthorityService.releaseEngine(builtHandle);
        builtHandle = 0;
        return true;
      }
      const currentSources = this.resolveNativeAuthorityReferenceSources(currentSnapshot, result.sourceIds);
      if (buildToken !== this.nativeAuthorityBuildToken || currentSources.length !== result.sourceIds.length ||
        this.buildNativeAuthorityReferenceKey(currentSources) !== referenceKey) {
        this.nativeAuthorityService.releaseEngine(builtHandle);
        builtHandle = 0;
        return false;
      }
      const backendVersion = this.nativeAuthorityService.backendVersion();
      this.nativeAuthorityHandle = builtHandle;
      builtHandle = 0;
      this.nativeAuthorityIdentity = result.identity;
      this.nativeAuthorityReferenceKey = referenceKey;
      this.nativeAuthoritySourceIds = result.sourceIds.slice();
      this.metrics.recordBuild(backendVersion, result.ruleLineCount);
      this.logNativeAuthorityMetrics('build_ready');
      return true;
    } catch (_error) {
      if (builtHandle > 0) {
        try {
          this.nativeAuthorityService.releaseEngine(builtHandle);
        } catch (_releaseError) {
        }
      }
      if (buildToken === this.nativeAuthorityBuildToken) {
        this.metrics.recordBuildFailure();
        this.logNativeAuthorityMetrics('build_failed', true);
      }
      return false;
    }
  }

  isNativeAuthorityReady(): boolean {
    return this.nativeAuthorityHandle > 0;
  }

  private enqueueMutation<T>(operation: () => Promise<T>): Promise<T> {
    const result: Promise<T> = this.mutationTask
      .catch((_error: Error): void => {})
      .then(operation);
    this.mutationTask = result.then(
      (_value: T): void => {},
      (_error: Error): void => {}
    );
    return result;
  }

  private evaluateWithNativeAuthority(
    input: AdBlockRequestEvaluationInput
  ): AdBlockRequestEvaluation {
    if (!this.nativeAuthorityService.isEligible(input)) {
      return {
        network: this.buildNativeAllowDecision(),
        response: this.emptyResponseDecision()
      };
    }
    if (this.nativeAuthorityHandle <= 0) {
      return {
        network: this.buildNativeAllowDecision(),
        response: this.emptyResponseDecision()
      };
    }
    this.metrics.recordEligibleQuery();
    const nativeStartedAt = this.metrics.startQuery();
    try {
      const nativeEvaluation: AdBlockNativeAuthorityEvaluation =
        this.nativeAuthorityService.evaluate(this.nativeAuthorityHandle, input);
      this.metrics.recordQuery(
        nativeStartedAt,
        nativeEvaluation.shouldBlock,
        nativeEvaluation.redirectDataUrl.length > 0
      );
      this.logNativeAuthorityMetrics('query');
      return {
        network: this.buildNativeDecision(nativeEvaluation),
        response: nativeEvaluation.shouldBlock
          ? this.emptyResponseDecision()
          : this.buildNativeResponseDecision(input, nativeEvaluation.cspDirectives)
      };
    } catch (_error) {
      this.metrics.recordQueryFailure(nativeStartedAt);
      this.logNativeAuthorityMetrics('query_failed', true);
      return {
        network: this.buildNativeAllowDecision(),
        response: this.emptyResponseDecision()
      };
    }
  }

  private buildNativeResponseDecision(
    input: AdBlockRequestEvaluationInput,
    nativeCspDirectives: string
  ): AdBlockResponseDecision {
    if (!input.includeResponseEvaluation) {
      return this.emptyResponseDecision();
    }
    const normalizedCsp = nativeCspDirectives.trim();
    return {
      cspDirectives: normalizedCsp.length > 0 ? [normalizedCsp] : []
    };
  }

  private buildNativeDecision(evaluation: AdBlockNativeAuthorityEvaluation): AdBlockRequestDecision {
    return {
      shouldBlock: evaluation.shouldBlock,
      redirectDataUrl: evaluation.shouldBlock ? evaluation.redirectDataUrl : '',
      rewrittenUrl: evaluation.shouldBlock ? '' : evaluation.rewrittenUrl
    };
  }

  private buildNativeAllowDecision(): AdBlockRequestDecision {
    return {
      shouldBlock: false,
      redirectDataUrl: '',
      rewrittenUrl: ''
    };
  }

  private emptyResponseDecision(): AdBlockResponseDecision {
    return {
      cspDirectives: []
    };
  }

  private logNativeAuthorityMetrics(checkpoint: string, warn: boolean = false): void {
    const snapshot = this.metrics.snapshot();
    if (checkpoint === 'query' && snapshot.queryCount !== 1 &&
      snapshot.queryCount % NATIVE_AUTHORITY_METRICS_LOG_INTERVAL !== 0) {
      return;
    }
    const message =
      'Native authority %{public}s: ready=%{public}s backend=%{public}s rules=%{public}d builds=%{public}d ' +
      'buildFailures=%{public}d eligible=%{public}d queries=%{public}d queryFailures=%{public}d ' +
      'blocked=%{public}d allowed=%{public}d redirects=%{public}d ' +
      'p50=%{public}s p95=%{public}s p99=%{public}s';
    const args: (string | number)[] = [
      checkpoint,
      String(snapshot.ready),
      snapshot.backendVersion,
      snapshot.ruleLineCount,
      snapshot.buildCount,
      snapshot.buildFailureCount,
      snapshot.eligibleQueryCount,
      snapshot.queryCount,
      snapshot.queryFailureCount,
      snapshot.blockedCount,
      snapshot.allowedCount,
      snapshot.redirectCount,
      String(snapshot.queryP50Ms),
      String(snapshot.queryP95Ms),
      String(snapshot.queryP99Ms)
    ];
    if (warn) {
      hilog.warn(DOMAIN, TAG, message, ...args);
      return;
    }
    hilog.info(DOMAIN, TAG, message, ...args);
  }

  private resolveNativeAuthorityReferenceSources(
    snapshot: AdBlockRuntimeSnapshot,
    sourceIds: string[]
  ): AdBlockCustomRuleSource[] {
    if (!snapshot.settings.preferences.enabled) {
      return [];
    }
    const selected: AdBlockCustomRuleSource[] = [];
    sourceIds.forEach((sourceId: string) => {
      const source = snapshot.settings.customRuleSources.find((item: AdBlockCustomRuleSource) => {
        return item.id === sourceId && item.enabled && item.ruleCount > 0;
      });
      if (source !== undefined) {
        selected.push(source);
      }
    });
    return selected;
  }

  private releaseNativeAuthority(): void {
    if (this.nativeAuthorityHandle > 0) {
      try {
        this.nativeAuthorityService.releaseEngine(this.nativeAuthorityHandle);
      } catch (_error) {
      }
    }
    this.nativeAuthorityHandle = 0;
    this.nativeAuthorityIdentity = '';
    this.nativeAuthorityReferenceKey = '';
    this.nativeAuthoritySourceIds = [];
    this.metrics.recordReleased();
  }

  private requestRuntimeRefresh(): void {
    this.runtimeRefreshGeneration += 1;
    Object.keys(this.runtimeRefreshListeners).forEach((key: string): void => {
      const listener = this.runtimeRefreshListeners[key];
      if (listener !== undefined) {
        listener();
      }
    });
  }

  private async commitMutation(mutation: AdBlockSettingsMutation): Promise<AdBlockSettings> {
    const prepared = await this.repository.prepareSettingsMutation(mutation);
    const snapshot = this.prepareCandidate(prepared.settings);
    return this.commitPreparedMutation(prepared, snapshot);
  }

  private async commitPreparedMutation(
    prepared: AdBlockPreparedSettingsCommit,
    snapshot: AdBlockRuntimeSnapshot
  ): Promise<AdBlockSettings> {
    const settings = await this.repository.commitPreparedSettings(prepared);
    if (prepared.shouldPersist && snapshot.key === this.buildKeyForSettings(settings)) {
      this.activateSnapshot(snapshot);
    } else {
      this.synchronizeWithRepository();
    }
    return settings;
  }

  private prepareCandidate(settings: AdBlockSettings): AdBlockRuntimeSnapshot {
    const startedAt = Date.now();
    const runtimeSettings = this.cloneRuntimeSettings(settings);
    const identityStartedAt = Date.now();
    const ruleSetKey = this.buildRuleSetKey(runtimeSettings.customRuleSources);
    const key = this.buildRuntimeKey(runtimeSettings, ruleSetKey);
    const identityDurationMs = Date.now() - identityStartedAt;
    if (this.activeSnapshot !== undefined && this.activeSnapshot.key === key) {
      return this.activeSnapshot;
    }
    const prepared = this.preparedSnapshots.get(key);
    if (prepared !== undefined) {
      return prepared;
    }
    const snapshot: AdBlockRuntimeSnapshot = {
      version: this.nextVersion,
      key: key,
      ruleSetKey: ruleSetKey,
      builtAt: Date.now(),
      settings: runtimeSettings,
      policy: {
        preferences: runtimeSettings.preferences,
        siteExceptions: runtimeSettings.siteExceptions,
        enabledRuleSourceCount: this.countEnabledRuleSources(runtimeSettings.customRuleSources)
      }
    };
    this.validateSnapshot(snapshot, runtimeSettings.customRuleSources);
    this.nextVersion += 1;
    this.rememberPreparedSnapshot(snapshot);
    hilog.info(
      DOMAIN,
      TAG,
      'AdBlock runtime generation built in %{public}dms: identity=%{public}dms rules=%{public}d sources=%{public}d',
      Date.now() - startedAt,
      identityDurationMs,
      this.countRules(runtimeSettings.customRuleSources),
      runtimeSettings.customRuleSources.length
    );
    return snapshot;
  }

  private activateSnapshot(snapshot: AdBlockRuntimeSnapshot): void {
    if (this.activeSnapshot !== undefined && this.activeSnapshot.key === snapshot.key) {
      return;
    }
    this.activeSnapshot = snapshot;
    this.preparedSnapshots.delete(snapshot.key);
    this.releaseNativeAuthorityIfStale(snapshot);
  }

  private releaseNativeAuthorityIfStale(snapshot: AdBlockRuntimeSnapshot): void {
    if (this.nativeAuthorityHandle <= 0 || this.nativeAuthoritySourceIds.length === 0) {
      return;
    }
    const sources = this.resolveNativeAuthorityReferenceSources(snapshot, this.nativeAuthoritySourceIds);
    if (sources.length !== this.nativeAuthoritySourceIds.length ||
      this.buildNativeAuthorityReferenceKey(sources) !== this.nativeAuthorityReferenceKey) {
      this.nativeAuthorityBuildToken += 1;
      this.releaseNativeAuthority();
    }
  }

  private buildNativeAuthorityReferenceKey(sources: AdBlockCustomRuleSource[]): string {
    const parts: string[] = [];
    sources.forEach((source: AdBlockCustomRuleSource) => {
      parts.push(JSON.stringify([
        source.id,
        source.payloadIdentity,
        source.ruleCount,
        source.nativeNetworkRuleCount ?? 0,
        source.nativeCosmeticRuleCount ?? 0,
        source.updatedAt
      ]));
    });
    return parts.join(',');
  }

  private rememberPreparedSnapshot(snapshot: AdBlockRuntimeSnapshot): void {
    if (this.preparedSnapshots.size >= MAX_PREPARED_GENERATIONS) {
      let oldestKey = '';
      this.preparedSnapshots.forEach((_value: AdBlockRuntimeSnapshot, key: string) => {
        if (oldestKey.length === 0) {
          oldestKey = key;
        }
      });
      if (oldestKey.length > 0) {
        this.preparedSnapshots.delete(oldestKey);
      }
    }
    this.preparedSnapshots.set(snapshot.key, snapshot);
  }

  private validateSnapshot(snapshot: AdBlockRuntimeSnapshot, sources: AdBlockCustomRuleSource[]): void {
    let enabledSourceCount = 0;
    sources.forEach((source: AdBlockCustomRuleSource) => {
      if (!source.enabled) {
        return;
      }
      enabledSourceCount += 1;
    });
    if (snapshot.key.length === 0 || snapshot.ruleSetKey.length === 0 || snapshot.version <= 0) {
      throw new Error('Ad-block runtime generation metadata is invalid.');
    }
    if (snapshot.policy.enabledRuleSourceCount !== enabledSourceCount) {
      throw new Error('Ad-block runtime generation policy validation failed.');
    }
  }

  private buildRuntimeKey(settings: AdBlockSettings, ruleSetKey: string): string {
    return JSON.stringify([
      settings.preferences.enabled,
      settings.preferences.updateOnForeground,
      this.buildSiteExceptionKey(settings.siteExceptions),
      ruleSetKey,
      settings.engineUnavailableReason
    ]);
  }

  private buildKeyForSettings(settings: AdBlockSettings): string {
    return this.buildRuntimeKey(settings, this.buildRuleSetKey(settings.customRuleSources));
  }

  private buildSiteExceptionKey(values: AdBlockSiteException[]): string {
    const parts: string[] = [];
    values.forEach((item: AdBlockSiteException) => {
      parts.push(JSON.stringify([
        item.profileId,
        item.host,
        item.includeSubdomains,
        item.createdAt
      ]));
    });
    return parts.length > 0 ? parts.join(',') : 'empty';
  }

  private buildRuleSetKey(values: AdBlockCustomRuleSource[]): string {
    const parts: string[] = [];
    values.forEach((item: AdBlockCustomRuleSource) => {
      parts.push(JSON.stringify([
        item.id,
        item.enabled,
        item.payloadIdentity,
        item.ruleCount,
        item.nativeNetworkRuleCount ?? 0,
        item.nativeCosmeticRuleCount ?? 0
      ]));
    });
    return parts.length > 0 ? parts.join(',') : 'empty';
  }

  private countRules(sources: AdBlockCustomRuleSource[]): number {
    let count = 0;
    sources.forEach((source: AdBlockCustomRuleSource) => {
      count += source.ruleCount;
    });
    return count;
  }

  private cloneRuntimeSettings(settings: AdBlockSettings): AdBlockSettings {
    return {
      preferences: {
        enabled: settings.preferences.enabled,
        updateOnForeground: settings.preferences.updateOnForeground
      },
      siteExceptions: settings.siteExceptions.map((item: AdBlockSiteException) => {
        const cloned: AdBlockSiteException = {
          profileId: item.profileId,
          host: item.host,
          includeSubdomains: item.includeSubdomains,
          createdAt: item.createdAt
        };
        return cloned;
      }),
      customRuleSources: settings.customRuleSources.map((item: AdBlockCustomRuleSource) => {
        const cloned: AdBlockCustomRuleSource = {
          id: item.id,
          payloadIdentity: item.payloadIdentity,
          title: item.title,
          url: item.url,
          sourceType: item.sourceType,
          enabled: item.enabled,
          nativeNetworkRuleCount: item.nativeNetworkRuleCount,
          nativeCosmeticRuleCount: item.nativeCosmeticRuleCount,
          ruleCount: item.ruleCount,
          lastUpdatedAt: item.lastUpdatedAt,
          lastError: item.lastError,
          createdAt: item.createdAt,
          updatedAt: item.updatedAt
        };
        return cloned;
      }),
      stats: {
        statisticsVersion: settings.stats.statisticsVersion,
        totalBlockedCount: settings.stats.totalBlockedCount,
        networkBlockedCount: settings.stats.networkBlockedCount,
        urlParameterRemovedCount: settings.stats.urlParameterRemovedCount,
        cosmeticElementHiddenCount: settings.stats.cosmeticElementHiddenCount,
        manualElementHiddenCount: settings.stats.manualElementHiddenCount,
        totalProtectionActionCount: settings.stats.totalProtectionActionCount,
        dailyProtectionActivity: settings.stats.dailyProtectionActivity.map((
          activity: AdBlockDailyProtectionActivity
        ): AdBlockDailyProtectionActivity => {
          return {
            dayStartedAt: activity.dayStartedAt,
            networkBlockedCount: activity.networkBlockedCount,
            urlParameterRemovedCount: activity.urlParameterRemovedCount,
            cosmeticElementHiddenCount: activity.cosmeticElementHiddenCount,
            manualElementHiddenCount: activity.manualElementHiddenCount,
            totalProtectionActionCount: activity.totalProtectionActionCount
          };
        }),
        updatedAt: settings.stats.updatedAt
      },
      lastRuleUpdateAt: settings.lastRuleUpdateAt,
      engineUnavailableReason: settings.engineUnavailableReason,
      updatedAt: settings.updatedAt
    };
  }

  private countEnabledRuleSources(values: AdBlockCustomRuleSource[]): number {
    let count = 0;
    values.forEach((item: AdBlockCustomRuleSource) => {
      if (item.enabled && item.ruleCount > 0) {
        count += 1;
      }
    });
    return count;
  }
}
