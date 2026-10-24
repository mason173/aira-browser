import { common } from '@kit.AbilityKit';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import {
  AdBlockCustomRuleSource,
  AdBlockSettings
} from '../../common/models/BrowserModels';
import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import { AdBlockRuleSourceMetadataService } from '../../services/adblock/AdBlockRuleSourceMetadataService';
import { AdBlockLocalRuleFileService } from '../../services/adblock/AdBlockLocalRuleFileService';
import { AdBlockRuleListFetchService } from '../../services/adblock/AdBlockRuleListFetchService';
import { AdBlockSubscriptionPolicyService } from '../../services/adblock/AdBlockSubscriptionPolicyService';
import {
  AdBlockNativeRuleProviderResult,
  AdBlockNativeSourcePayloadInfo,
  AdBlockNativeRuleProviderService,
  sharedAdBlockNativeRuleProviderService
} from '../../services/adblock/AdBlockNativeRuleProviderService';
import { AdBlockRuntimeGenerationCoordinator } from './AdBlockRuntimeGenerationCoordinator';
import { AdBlockSettingsBoundary } from './AdBlockSettingsCoordinator';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import {
  APP_PROMOTION_BANNER_RULE_SOURCE_ID,
  BUILT_IN_AD_BLOCK_RULE_SOURCE_ID,
  SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID
} from '../../features/adblock/AdBlockBuiltInRuleSource';
import {
  AdBlockThirdPartyRuleSourceDefinition,
  findAdBlockThirdPartyRuleSource,
  isAdBlockThirdPartyRuleSourceId
} from '../../features/adblock/AdBlockThirdPartyRuleSourceCatalog';

export interface AdBlockRuleSourceResult {
  settings: AdBlockSettings;
  message: string;
  success: boolean;
}

export interface AdBlockThirdPartyRuleConsent {
  sourceId: string;
  sourceTitle: string;
  title: string;
  message: string;
  acceptLabel: string;
  cancelLabel: string;
}

interface AdBlockRemoteFetchGeneration {
  sourceId: string;
  generation: number;
  requiresExistingSource: boolean;
  automatic: boolean;
}

export class AdBlockRuleSourceCoordinator {
  private static mutationTasksByRepository: Map<AdBlockRepository, Promise<void>> =
    new Map<AdBlockRepository, Promise<void>>();
  private static autoUpdateTasksByRepository: Map<AdBlockRepository, Promise<AdBlockRuleSourceResult | undefined>> =
    new Map<AdBlockRepository, Promise<AdBlockRuleSourceResult | undefined>>();
  private static remoteFetchGenerationsByRepository: Map<AdBlockRepository, Map<string, number>> =
    new Map<AdBlockRepository, Map<string, number>>();
  private static nextRemoteFetchGeneration: number = 0;
  private repository: AdBlockRepository;
  private fetchService: AdBlockRuleListFetchService = new AdBlockRuleListFetchService();
  private localFileService: AdBlockLocalRuleFileService = new AdBlockLocalRuleFileService();
  private metadataService: AdBlockRuleSourceMetadataService = new AdBlockRuleSourceMetadataService();
  private runtimeGeneration: AdBlockRuntimeGenerationCoordinator;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private nativeRuleProvider: AdBlockNativeRuleProviderService;

  constructor(
    repository: AdBlockRepository,
    runtimeGeneration?: AdBlockRuntimeGenerationCoordinator,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService(),
    nativeRuleProvider: AdBlockNativeRuleProviderService = sharedAdBlockNativeRuleProviderService
  ) {
    this.repository = repository;
    this.runtimeGeneration = runtimeGeneration ?? AdBlockRuntimeGenerationCoordinator.forRepository(repository);
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.nativeRuleProvider = nativeRuleProvider;
  }

  async addSource(url: string, boundary: AdBlockSettingsBoundary): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    const normalizedUrl = this.metadataService.normalizeSubscriptionUrl(url);
    if (!this.isValidSubscriptionUrl(normalizedUrl)) {
      return {
        settings: this.repository.getSettings(),
        message: resolveAppResourceText($r('app.string.adblock_subscription_https_required')),
        success: false
      };
    }
    return this.fetchAndStore(normalizedUrl, undefined);
  }

  buildThirdPartyPresetConsent(sourceId: string): AdBlockThirdPartyRuleConsent | undefined {
    const definition = findAdBlockThirdPartyRuleSource(sourceId);
    if (definition === undefined) {
      return undefined;
    }
    const existing = this.findSource(sourceId);
    if (existing !== undefined && existing.url === definition.url && existing.ruleCount > 0) {
      return undefined;
    }
    return {
      sourceId: definition.id,
      sourceTitle: definition.title,
      title: resolveAppResourceText($r('app.string.adblock_third_party_title')),
      message: resolveAppResourceText($r('app.string.adblock_third_party_message', definition.title, definition.sourceHost)),
      acceptLabel: resolveAppResourceText($r('app.string.adblock_third_party_accept')),
      cancelLabel: resolveAppResourceText($r('app.string.settings_custom_home_cancel'))
    };
  }

  async downloadAndEnableThirdPartyPreset(
    sourceId: string,
    boundary: AdBlockSettingsBoundary
  ): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    const definition = findAdBlockThirdPartyRuleSource(sourceId);
    if (definition === undefined) {
      return this.buildMissingSourceResult();
    }
    const existing = this.findSource(sourceId);
    if (existing !== undefined && existing.url === definition.url && existing.ruleCount > 0) {
      return this.setSourceEnabled(sourceId, true, boundary);
    }
    return this.fetchAndStore(definition.url, undefined, definition);
  }

  async refreshSource(sourceId: string, boundary: AdBlockSettingsBoundary): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    const source = this.findSource(sourceId);
    if (source === undefined) {
      return {
        settings: this.repository.getSettings(),
        message: resolveAppResourceText($r('app.string.adblock_source_missing')),
        success: false
      };
    }
    if (source.sourceType === 'system') {
      return {
        settings: this.repository.getSettings(),
        message: resolveAppResourceText($r('app.string.adblock_preset_no_refresh')),
        success: true
      };
    }
    if (source.sourceType === 'local') {
      return this.readLocalAndStore(source.url, source.title, source);
    }
    return this.fetchAndStore(source.url, source);
  }

  async autoUpdateDueRemoteSources(): Promise<AdBlockRuleSourceResult | undefined> {
    const pending = AdBlockRuleSourceCoordinator.autoUpdateTasksByRepository.get(this.repository);
    if (pending !== undefined) {
      return pending;
    }
    const task = this.updateDueRemoteSources();
    AdBlockRuleSourceCoordinator.autoUpdateTasksByRepository.set(this.repository, task);
    try {
      return await task;
    } finally {
      AdBlockRuleSourceCoordinator.autoUpdateTasksByRepository.delete(this.repository);
    }
  }

  private async updateDueRemoteSources(): Promise<AdBlockRuleSourceResult | undefined> {
    if (!this.canAutoUpdateRemoteSources()) {
      return undefined;
    }
    const now = Date.now();
    const dueSources = this.repository.getSettings().customRuleSources.filter((source: AdBlockCustomRuleSource) => {
      return this.shouldAutoUpdateRemoteSource(source, now);
    });
    let result: AdBlockRuleSourceResult | undefined = undefined;
    for (const candidate of dueSources) {
      // A manual change may have removed/disabled/refreshed a source while an
      // earlier download was pending. Re-read before each request.
      if (!this.canAutoUpdateRemoteSources()) {
        break;
      }
      const source = this.findSource(candidate.id);
      if (source === undefined || !this.shouldAutoUpdateRemoteSource(source, Date.now())) {
        continue;
      }
      result = await this.fetchAndStore(source.url, source, undefined, true);
    }
    return result;
  }

  private canAutoUpdateRemoteSources(): boolean {
    const preferences = this.repository.getSettings().preferences;
    return preferences.enabled && preferences.updateOnForeground;
  }

  async importLocalSource(uri: string, boundary: AdBlockSettingsBoundary): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    const title = this.metadataService.buildTitle(uri);
    return this.readLocalAndStore(uri, title, undefined);
  }

  async restoreMissingNativeSourcePayloads(): Promise<string[]> {
    await this.repository.initializeMetadata();
    const unresolvedSourceIds: string[] = [];
    const sources = this.repository.getSettings().customRuleSources.filter((source: AdBlockCustomRuleSource) => {
      return source.sourceType !== 'system' && source.enabled && source.url.trim().length > 0;
    });
    for (const source of sources) {
      try {
        const payloadInfo = await this.inspectNativeSourcePayloadBestEffort(source.id);
        if (payloadInfo !== undefined) {
          if (source.payloadIdentity !== payloadInfo.identity ||
            source.nativeNetworkRuleCount !== payloadInfo.networkRuleCount ||
            source.nativeCosmeticRuleCount !== payloadInfo.cosmeticRuleCount ||
            source.ruleCount !== payloadInfo.ruleCount) {
            const upgraded = this.cloneSource(source);
            upgraded.payloadIdentity = payloadInfo.identity;
            upgraded.nativeNetworkRuleCount = payloadInfo.networkRuleCount;
            upgraded.nativeCosmeticRuleCount = payloadInfo.cosmeticRuleCount;
            upgraded.ruleCount = payloadInfo.ruleCount;
            await this.runtimeGeneration.upsertCustomRuleSource(upgraded);
          }
          continue;
        }
        if (source.sourceType === 'local') {
          const result = await this.readLocalAndStore(source.url, source.title, source);
          if (!result.success) {
            unresolvedSourceIds.push(source.id);
          }
        } else {
          const result = await this.fetchAndStore(source.url, source);
          if (!result.success) {
            unresolvedSourceIds.push(source.id);
          }
        }
      } catch (_error) {
        unresolvedSourceIds.push(source.id);
      }
    }
    return unresolvedSourceIds;
  }

  pickLocalRuleFile(context: common.UIAbilityContext): Promise<string | undefined> {
    return this.localFileService.pickRuleFileUri(context);
  }

  async setSourceEnabled(
    sourceId: string,
    enabled: boolean,
    boundary: AdBlockSettingsBoundary
  ): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    return this.enqueueRepositoryMutation(async (): Promise<AdBlockRuleSourceResult> => {
      const source = this.findSource(sourceId);
      if (source === undefined) {
        return this.buildMissingSourceResult();
      }
      if (enabled) {
        return this.enableSourceWithinMutation(source);
      }
      const settings = await this.runtimeGeneration.updateCustomRuleSourceEnabled(sourceId, enabled);
      if (!await this.activateNativeAuthority(settings)) {
        const restoredSettings = await this.runtimeGeneration.updateCustomRuleSourceEnabled(sourceId, source.enabled);
        await this.reconcileNativeRulesBestEffort(restoredSettings);
        return this.buildNativeActivationFailureResult(restoredSettings);
      }
      return {
        settings: settings,
        message: enabled
          ? resolveAppResourceText($r('app.string.adblock_custom_enabled'))
          : resolveAppResourceText($r('app.string.adblock_custom_disabled')),
        success: true
      };
    });
  }

  private async enableSourceWithinMutation(source: AdBlockCustomRuleSource): Promise<AdBlockRuleSourceResult> {
    let payloadStaged: boolean = false;
    let payloadCommitted: boolean = false;
    let sourceCommitted: boolean = false;
    let fetchGeneration: AdBlockRemoteFetchGeneration | undefined = undefined;
    try {
      let payloadInfo: AdBlockNativeSourcePayloadInfo | undefined =
        await this.inspectNativeSourcePayloadBestEffort(source.id);
      let restoredPayload: boolean = false;
      let updateIntervalMs: number | undefined = source.updateIntervalMs;
      if (payloadInfo === undefined) {
        let payload: string;
        if (source.sourceType === 'local') {
          payload = await this.localFileService.readRuleFile(source.url);
        } else {
          fetchGeneration = this.beginRemoteFetch(source.id, true);
          const subscription = await this.fetchService.fetchSubscription(source.url);
          payload = subscription.text;
          updateIntervalMs = subscription.updateIntervalMs;
        }
        payloadStaged = true;
        await this.nativeRuleProvider.stageSourcePayload(source.id, payload);
        payloadInfo = await this.nativeRuleProvider.validateStagedSourcePayload(source.id);
        if (payloadInfo.ruleCount <= 0) {
          throw new Error(resolveAppResourceText($r('app.string.adblock_no_rules_parsed')));
        }
        this.requireCurrentRemoteFetch(fetchGeneration);
        await this.nativeRuleProvider.commitStagedSourcePayload(source.id);
        payloadCommitted = true;
        this.requireCurrentRemoteFetch(fetchGeneration);
        restoredPayload = true;
      }

      const enabledSource = this.cloneSource(source);
      enabledSource.enabled = true;
      enabledSource.payloadIdentity = payloadInfo.identity;
      enabledSource.nativeNetworkRuleCount = payloadInfo.networkRuleCount;
      enabledSource.nativeCosmeticRuleCount = payloadInfo.cosmeticRuleCount;
      enabledSource.ruleCount = payloadInfo.ruleCount;
      enabledSource.updatedAt = Date.now();
      if (restoredPayload) {
        enabledSource.lastUpdatedAt = enabledSource.updatedAt;
        enabledSource.updateIntervalMs = updateIntervalMs;
        enabledSource.lastAttemptAt = enabledSource.updatedAt;
        enabledSource.lastError = '';
      }
      const settings = await this.runtimeGeneration.upsertCustomRuleSource(enabledSource);
      sourceCommitted = true;
      const nativeResult: AdBlockNativeRuleProviderResult = await this.nativeRuleProvider.reconcile(settings);
      if (!nativeResult.success ||
        (settings.preferences.enabled && nativeResult.sourceIds.indexOf(source.id) < 0) ||
        !await this.acceptNativeAuthority(settings, nativeResult)) {
        throw new Error(resolveAppResourceText($r('app.string.adblock_native_load_failed')));
      }
      if (payloadCommitted) {
        await this.nativeRuleProvider.completeStagedSourcePayload(source.id);
      }
      return {
        settings: settings,
        message: resolveAppResourceText($r('app.string.adblock_custom_enabled')),
        success: true
      };
    } catch (error) {
      try {
        if (payloadCommitted) {
          await this.nativeRuleProvider.rollbackStagedSourcePayload(source.id);
        } else if (payloadStaged) {
          await this.nativeRuleProvider.discardStagedSourcePayload(source.id);
        }
      } catch (_rollbackError) {
      }
      const restoredSettings = sourceCommitted
        ? await this.runtimeGeneration.upsertCustomRuleSource(source)
        : this.repository.getSettings();
      await this.reconcileNativeRulesBestEffort(restoredSettings);
      if (fetchGeneration !== undefined && !this.isCurrentRemoteFetch(fetchGeneration)) {
        return this.buildSupersededFetchResult();
      }
      return this.buildNativeActivationFailureResult(restoredSettings, this.stringifyError(error));
    } finally {
      this.finishRemoteFetch(fetchGeneration);
    }
  }

  async removeSource(sourceId: string, boundary: AdBlockSettingsBoundary): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    if (this.isRemovedBuiltInRuleSourceId(sourceId) || isAdBlockThirdPartyRuleSourceId(sourceId)) {
      return {
        settings: this.repository.getSettings(),
        message: resolveAppResourceText($r('app.string.adblock_preset_cannot_delete')),
        success: false
      };
    }
    AdBlockRuleSourceCoordinator.remoteFetchGenerationsByRepository.get(this.repository)?.delete(sourceId);
    return this.enqueueRepositoryMutation(async (): Promise<AdBlockRuleSourceResult> => {
      const existing = this.findSource(sourceId);
      const settings = await this.runtimeGeneration.removeCustomRuleSource(sourceId);
      if (!await this.activateNativeAuthority(settings)) {
        const restoredSettings = existing === undefined
          ? settings
          : await this.runtimeGeneration.upsertCustomRuleSource(existing);
        await this.reconcileNativeRulesBestEffort(restoredSettings);
        return this.buildNativeActivationFailureResult(restoredSettings);
      }
      await this.nativeRuleProvider.removeSourcePayload(sourceId);
      return {
        settings: settings,
        message: resolveAppResourceText($r('app.string.adblock_custom_deleted')),
        success: true
      };
    });
  }

  private async fetchAndStore(
    url: string,
    existing?: AdBlockCustomRuleSource,
    preset?: AdBlockThirdPartyRuleSourceDefinition,
    automatic: boolean = false
  ): Promise<AdBlockRuleSourceResult> {
    const title = preset?.title ?? existing?.title ?? this.metadataService.buildTitle(url);
    const sourceId = existing?.id ?? preset?.id ?? this.metadataService.buildSource(url, title).id;
    const fetchGeneration = this.beginRemoteFetch(sourceId,
      existing !== undefined || this.findSource(sourceId) !== undefined, automatic);
    try {
      await this.repository.initializeMetadata();
      this.requireCurrentRemoteFetch(fetchGeneration);
      const subscription = await this.fetchService.fetchSubscription(url,
        (): boolean => this.isCurrentRemoteFetch(fetchGeneration));
      // A disabled automatic refresh must not compile a newly downloaded list
      // or overwrite retained source metadata after the user turned filtering off.
      this.requireCurrentRemoteFetch(fetchGeneration);
      const source = this.metadataService.buildSource(url, title, existing);
      source.updateIntervalMs = subscription.updateIntervalMs;
      if (preset !== undefined) {
        source.id = preset.id;
        source.title = preset.title;
        source.enabled = true;
      }
      const settings = await this.storeRemoteSource(source, subscription.text, preset !== undefined, fetchGeneration);
      return {
        settings: settings,
        message: this.buildSuccessMessage(existing === undefined, source),
        success: true
      };
    } catch (error) {
      return await this.buildFailureResult(url, title, this.stringifyError(error), existing, 'remote', fetchGeneration);
    } finally {
      this.finishRemoteFetch(fetchGeneration);
    }
  }

  private async readLocalAndStore(
    uri: string,
    title: string,
    existing?: AdBlockCustomRuleSource
  ): Promise<AdBlockRuleSourceResult> {
    try {
      await this.repository.initializeMetadata();
      const payload = await this.localFileService.readRuleFile(uri);
      const source = this.metadataService.buildLocalSource(uri, title, existing);
      const settings = await this.storeSource(source, payload, false);
      return {
        settings: settings,
        message: this.buildSuccessMessage(existing === undefined, source),
        success: true
      };
    } catch (error) {
      return this.buildFailureResult(uri, title, this.stringifyError(error), existing, 'local');
    }
  }

  private async storeRemoteSource(
    source: AdBlockCustomRuleSource,
    payload: string,
    forceEnabled: boolean,
    fetchGeneration: AdBlockRemoteFetchGeneration
  ): Promise<AdBlockSettings> {
    return this.storeSource(source, payload, forceEnabled, fetchGeneration);
  }

  private async storeSource(
    source: AdBlockCustomRuleSource,
    payload: string,
    forceEnabled: boolean,
    fetchGeneration?: AdBlockRemoteFetchGeneration
  ): Promise<AdBlockSettings> {
    return this.enqueueRepositoryMutation(async (): Promise<AdBlockSettings> => {
      this.requireCurrentRemoteFetch(fetchGeneration);
      const existing = this.findSource(source.id);
      source.enabled = forceEnabled ? true : (existing?.enabled ?? source.enabled);
      source.createdAt = existing?.createdAt ?? source.createdAt;
      let sourceCommitted: boolean = false;
      let payloadCommitted: boolean = false;
      try {
        await this.nativeRuleProvider.stageSourcePayload(source.id, payload);
        this.requireCurrentRemoteFetch(fetchGeneration);
        const payloadInfo = await this.nativeRuleProvider.validateStagedSourcePayload(source.id);
        source.payloadIdentity = payloadInfo.identity;
        source.nativeNetworkRuleCount = payloadInfo.networkRuleCount;
        source.nativeCosmeticRuleCount = payloadInfo.cosmeticRuleCount;
        source.ruleCount = payloadInfo.ruleCount;
        if (source.ruleCount <= 0) {
          throw new Error(resolveAppResourceText($r('app.string.adblock_no_rules_parsed')));
        }
        this.requireCurrentRemoteFetch(fetchGeneration);
        await this.nativeRuleProvider.commitStagedSourcePayload(source.id);
        payloadCommitted = true;
        this.requireCurrentRemoteFetch(fetchGeneration);
        const settings = await this.runtimeGeneration.upsertCustomRuleSource(source);
        sourceCommitted = true;
        const nativeResult = await this.nativeRuleProvider.reconcile(settings);
        if (!await this.acceptNativeAuthority(settings, nativeResult)) {
          throw new Error(resolveAppResourceText($r('app.string.adblock_native_load_failed')));
        }
        await this.nativeRuleProvider.completeStagedSourcePayload(source.id);
        return settings;
      } catch (error) {
        try {
          if (payloadCommitted) {
            await this.nativeRuleProvider.rollbackStagedSourcePayload(source.id);
          } else {
            await this.nativeRuleProvider.discardStagedSourcePayload(source.id);
          }
        } catch (_rollbackError) {
        }
        if (sourceCommitted) {
          const restoredSettings = existing === undefined
            ? await this.runtimeGeneration.removeCustomRuleSource(source.id)
            : await this.runtimeGeneration.upsertCustomRuleSource(existing);
          await this.reconcileNativeRulesBestEffort(restoredSettings);
        }
        throw new Error(this.stringifyError(error));
      }
    });
  }

  private async reconcileNativeRulesBestEffort(settings: AdBlockSettings): Promise<void> {
    try {
      await this.activateNativeAuthority(settings);
    } catch (_error) {
    }
  }

  private async inspectNativeSourcePayloadBestEffort(
    sourceId: string
  ): Promise<AdBlockNativeSourcePayloadInfo | undefined> {
    try {
      return await this.nativeRuleProvider.inspectSourcePayload(sourceId);
    } catch (_error) {
      return undefined;
    }
  }

  private async activateNativeAuthority(settings: AdBlockSettings): Promise<boolean> {
    try {
      const nativeResult = await this.nativeRuleProvider.reconcile(settings);
      return this.acceptNativeAuthority(settings, nativeResult);
    } catch (_error) {
      return false;
    }
  }

  private async acceptNativeAuthority(
    settings: AdBlockSettings,
    nativeResult: AdBlockNativeRuleProviderResult
  ): Promise<boolean> {
    if (!nativeResult.success || !this.hasEveryEnabledSource(settings, nativeResult)) {
      return false;
    }
    return this.runtimeGeneration.reconcileNativeAuthority(nativeResult);
  }

  private hasEveryEnabledSource(
    settings: AdBlockSettings,
    nativeResult: AdBlockNativeRuleProviderResult
  ): boolean {
    return this.nativeRuleProvider.resolveEffectiveSources(settings)
      .every((source: AdBlockCustomRuleSource): boolean => {
        return nativeResult.sourceIds.indexOf(source.id) >= 0;
      });
  }

  private findSource(sourceId: string): AdBlockCustomRuleSource | undefined {
    return this.repository.getSettings().customRuleSources.find((item: AdBlockCustomRuleSource) => item.id === sourceId);
  }

  private cloneSource(source: AdBlockCustomRuleSource): AdBlockCustomRuleSource {
    return {
      id: source.id,
      payloadIdentity: source.payloadIdentity,
      title: source.title,
      url: source.url,
      sourceType: source.sourceType,
      enabled: source.enabled,
      nativeNetworkRuleCount: source.nativeNetworkRuleCount,
      nativeCosmeticRuleCount: source.nativeCosmeticRuleCount,
      ruleCount: source.ruleCount,
      lastUpdatedAt: source.lastUpdatedAt,
      updateIntervalMs: source.updateIntervalMs,
      lastAttemptAt: source.lastAttemptAt,
      lastError: source.lastError,
      createdAt: source.createdAt,
      updatedAt: source.updatedAt
    };
  }

  private enqueueRepositoryMutation<T>(operation: () => Promise<T>): Promise<T> {
    const previous: Promise<void> = AdBlockRuleSourceCoordinator.mutationTasksByRepository.get(this.repository) ??
      Promise.resolve();
    const result: Promise<T> = previous
      .catch((_error: Error): void => {})
      .then(async (): Promise<T> => {
        await this.repository.ensureRustV1NativeRuleArtifactCleanup(
          (): Promise<void> => this.nativeRuleProvider.clearAllArtifacts()
        );
        return operation();
      });
    const tail: Promise<void> = result.then(
      (_value: T): void => {},
      (_error: Error): void => {}
    );
    AdBlockRuleSourceCoordinator.mutationTasksByRepository.set(this.repository, tail);
    return result;
  }

  private buildMissingSourceResult(): AdBlockRuleSourceResult {
    return {
      settings: this.repository.getSettings(),
      message: resolveAppResourceText($r('app.string.adblock_source_missing')),
      success: false
    };
  }

  private buildNativeActivationFailureResult(
    settings: AdBlockSettings,
    message?: string
  ): AdBlockRuleSourceResult {
    return {
      settings: settings,
      message: message ?? resolveAppResourceText($r('app.string.adblock_native_load_failed')),
      success: false
    };
  }

  private canWriteDevicePreference(boundary: AdBlockSettingsBoundary): boolean {
    const privacyMode = normalizeBrowserSessionPrivacyMode(boundary.privacyMode);
    const dataScope = normalizeBrowserDataScope(boundary.dataScope, privacyMode);
    return this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: 'device_preferences',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private buildPolicyDeniedResult(): AdBlockRuleSourceResult {
    return {
      settings: this.repository.getSettings(),
      message: resolveAppResourceText($r('app.string.adblock_ui_ad_block_custom_rules_host_003')),
      success: false
    };
  }

  private isValidSubscriptionUrl(url: string): boolean {
    return url.startsWith('https://') && url.indexOf('.') > 0;
  }

  private buildSuccessMessage(imported: boolean, source: AdBlockCustomRuleSource): string {
    if (imported) {
      return resolveAppResourceText($r('app.string.adblock_rules_imported', source.ruleCount));
    }
    return resolveAppResourceText($r('app.string.adblock_rules_updated', source.ruleCount));
  }

  private async buildFailureResult(
    url: string,
    title: string,
    message: string,
    existing: AdBlockCustomRuleSource | undefined,
    sourceType: 'remote' | 'local',
    fetchGeneration?: AdBlockRemoteFetchGeneration
  ): Promise<AdBlockRuleSourceResult> {
    if (fetchGeneration !== undefined && !this.isCurrentRemoteFetch(fetchGeneration)) {
      return this.buildSupersededFetchResult();
    }
    if (existing === undefined) {
      return {
        settings: this.repository.getSettings(),
        message: message,
        success: false
      };
    }
    return this.enqueueRepositoryMutation(async (): Promise<AdBlockRuleSourceResult> => {
      if (fetchGeneration !== undefined && !this.isCurrentRemoteFetch(fetchGeneration)) {
        return this.buildSupersededFetchResult();
      }
      const current = this.findSource(existing.id);
      if (current === undefined) {
        return {
          settings: this.repository.getSettings(),
          message: message,
          success: false
        };
      }
      const failedSource = this.metadataService.buildFailedSource(url, title, message, current);
      failedSource.sourceType = sourceType;
      const settings = await this.runtimeGeneration.upsertCustomRuleSource(failedSource);
      return {
        settings: settings,
        message: failedSource.lastError,
        success: false
      };
    });
  }

  private beginRemoteFetch(
    sourceId: string,
    requiresExistingSource: boolean,
    automatic: boolean = false
  ): AdBlockRemoteFetchGeneration {
    let generations = AdBlockRuleSourceCoordinator.remoteFetchGenerationsByRepository.get(this.repository);
    if (generations === undefined) {
      generations = new Map<string, number>();
      AdBlockRuleSourceCoordinator.remoteFetchGenerationsByRepository.set(this.repository, generations);
    }
    const generation = ++AdBlockRuleSourceCoordinator.nextRemoteFetchGeneration;
    generations.set(sourceId, generation);
    return { sourceId: sourceId, generation: generation,
      requiresExistingSource: requiresExistingSource, automatic: automatic };
  }

  private isCurrentRemoteFetch(fetch: AdBlockRemoteFetchGeneration): boolean {
    const source = this.findSource(fetch.sourceId);
    return (!fetch.automatic || (this.canAutoUpdateRemoteSources() && source?.enabled === true)) &&
      AdBlockRuleSourceCoordinator.remoteFetchGenerationsByRepository.get(this.repository)
      ?.get(fetch.sourceId) === fetch.generation &&
      (!fetch.requiresExistingSource || source !== undefined);
  }

  private requireCurrentRemoteFetch(fetch: AdBlockRemoteFetchGeneration | undefined): void {
    if (fetch !== undefined && !this.isCurrentRemoteFetch(fetch)) {
      throw new Error(resolveAppResourceText($r('app.string.adblock_source_missing')));
    }
  }

  private finishRemoteFetch(fetch: AdBlockRemoteFetchGeneration | undefined): void {
    if (fetch === undefined) {
      return;
    }
    const generations = AdBlockRuleSourceCoordinator.remoteFetchGenerationsByRepository.get(this.repository);
    if (generations?.get(fetch.sourceId) === fetch.generation) {
      generations.delete(fetch.sourceId);
      if (generations.size === 0) {
        AdBlockRuleSourceCoordinator.remoteFetchGenerationsByRepository.delete(this.repository);
      }
    }
  }

  private buildSupersededFetchResult(): AdBlockRuleSourceResult {
    // A newer operation owns both the payload and the UI status. In particular,
    // stale failures must not replace a later success with an error/retry delay.
    return { settings: this.repository.getSettings(), message: '', success: false };
  }

  private shouldAutoUpdateRemoteSource(source: AdBlockCustomRuleSource, now: number): boolean {
    if (this.isRemovedBuiltInRuleSourceId(source.id)) {
      return false;
    }
    if (source.sourceType !== 'remote') {
      return false;
    }
    if (!source.enabled || source.ruleCount <= 0 || source.url.trim().length <= 0) {
      return false;
    }
    return new AdBlockSubscriptionPolicyService().isDue(source, now);
  }

  private isRemovedBuiltInRuleSourceId(sourceId: string): boolean {
    return sourceId === BUILT_IN_AD_BLOCK_RULE_SOURCE_ID ||
      sourceId === SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID ||
      sourceId === APP_PROMOTION_BANNER_RULE_SOURCE_ID;
  }

  private stringifyError(error: Error | Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const maybeError = error as Error;
    if (maybeError.message !== undefined && maybeError.message.length > 0) {
      return maybeError.message;
    }
    return resolveAppResourceText($r('app.string.adblock_subscription_update_failed'));
  }
}
