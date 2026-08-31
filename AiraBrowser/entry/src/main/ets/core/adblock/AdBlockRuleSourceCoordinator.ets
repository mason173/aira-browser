import { common } from '@kit.AbilityKit';
import {
  AdBlockCustomRuleSource,
  AdBlockSettings
} from '../../common/models/BrowserModels';
import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import { AdBlockRuleSourceMetadataService } from '../../services/adblock/AdBlockRuleSourceMetadataService';
import { AdBlockLocalRuleFileService } from '../../services/adblock/AdBlockLocalRuleFileService';
import { AdBlockRuleListFetchService } from '../../services/adblock/AdBlockRuleListFetchService';
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

const RULE_SOURCE_AUTO_UPDATE_INTERVAL_MS: number = 10 * 24 * 60 * 60 * 1000;

export class AdBlockRuleSourceCoordinator {
  private static mutationTasksByRepository: Map<AdBlockRepository, Promise<void>> =
    new Map<AdBlockRepository, Promise<void>>();
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
        message: '请输入 HTTPS 规则订阅地址',
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
      title: '启用第三方过滤规则？',
      message: `“${definition.title}”由第三方独立提供和维护。启用后，Aira 将从互联网下载并更新该规则，规则提供方可能记录本次网络请求。\n\nAira 不参与规则内容编写，也无法保证其准确性、适用性或持续可用性。请在遵守你所在地法律法规及相关网站服务条款的前提下使用。\n\n规则来源：${definition.sourceHost}`,
      acceptLabel: '同意并下载',
      cancelLabel: '取消'
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
        message: '未找到这条规则订阅',
        success: false
      };
    }
    if (source.sourceType === 'system') {
      return {
        settings: this.repository.getSettings(),
        message: '系统预置规则无需刷新',
        success: true
      };
    }
    if (source.sourceType === 'local') {
      return this.readLocalAndStore(source.url, source.title, source);
    }
    return this.fetchAndStore(source.url, source);
  }

  async autoUpdateDueRemoteSources(): Promise<AdBlockRuleSourceResult | undefined> {
    if (!this.repository.getSettings().preferences.updateOnForeground) {
      return undefined;
    }
    const now = Date.now();
    const dueSource = this.repository.getSettings().customRuleSources.find((source: AdBlockCustomRuleSource) => {
      return this.shouldAutoUpdateRemoteSource(source, now);
    });
    if (dueSource === undefined) {
      return undefined;
    }
    return this.fetchAndStore(dueSource.url, dueSource);
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
        message: enabled ? '自定义规则已启用' : '自定义规则已关闭',
        success: true
      };
    });
  }

  private async enableSourceWithinMutation(source: AdBlockCustomRuleSource): Promise<AdBlockRuleSourceResult> {
    let payloadStaged: boolean = false;
    let payloadCommitted: boolean = false;
    let sourceCommitted: boolean = false;
    try {
      let payloadInfo: AdBlockNativeSourcePayloadInfo | undefined =
        await this.inspectNativeSourcePayloadBestEffort(source.id);
      let restoredPayload: boolean = false;
      if (payloadInfo === undefined) {
        const payload = source.sourceType === 'local'
          ? await this.localFileService.readRuleFile(source.url)
          : await this.fetchService.fetchText(source.url);
        payloadStaged = true;
        await this.nativeRuleProvider.stageSourcePayload(source.id, payload);
        payloadInfo = await this.nativeRuleProvider.validateStagedSourcePayload(source.id);
        if (payloadInfo.ruleCount <= 0) {
          throw new Error('没有解析到可用规则');
        }
        await this.nativeRuleProvider.commitStagedSourcePayload(source.id);
        payloadCommitted = true;
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
        enabledSource.lastError = '';
      }
      const settings = await this.runtimeGeneration.upsertCustomRuleSource(enabledSource);
      sourceCommitted = true;
      const nativeResult: AdBlockNativeRuleProviderResult = await this.nativeRuleProvider.reconcile(settings);
      if (!nativeResult.success ||
        (settings.preferences.enabled && nativeResult.sourceIds.indexOf(source.id) < 0) ||
        !await this.acceptNativeAuthority(settings, nativeResult)) {
        throw new Error('原生过滤规则加载失败，请重试');
      }
      if (payloadCommitted) {
        await this.nativeRuleProvider.completeStagedSourcePayload(source.id);
      }
      return {
        settings: settings,
        message: '自定义规则已启用',
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
      return this.buildNativeActivationFailureResult(restoredSettings, this.stringifyError(error));
    }
  }

  async removeSource(sourceId: string, boundary: AdBlockSettingsBoundary): Promise<AdBlockRuleSourceResult> {
    if (!this.canWriteDevicePreference(boundary)) {
      return this.buildPolicyDeniedResult();
    }
    if (this.isRemovedBuiltInRuleSourceId(sourceId) || isAdBlockThirdPartyRuleSourceId(sourceId)) {
      return {
        settings: this.repository.getSettings(),
        message: '预置规则不能删除',
        success: false
      };
    }
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
        message: '自定义规则已删除',
        success: true
      };
    });
  }

  private async fetchAndStore(
    url: string,
    existing?: AdBlockCustomRuleSource,
    preset?: AdBlockThirdPartyRuleSourceDefinition
  ): Promise<AdBlockRuleSourceResult> {
    const title = preset?.title ?? existing?.title ?? this.metadataService.buildTitle(url);
    try {
      await this.repository.initializeMetadata();
      const payload = await this.fetchService.fetchText(url);
      const source = this.metadataService.buildSource(url, title, existing);
      if (preset !== undefined) {
        source.id = preset.id;
        source.title = preset.title;
        source.enabled = true;
      }
      const messagePrefix = existing === undefined ? '已导入' : '已更新';
      const settings = await this.storeRemoteSource(source, payload, preset !== undefined);
      return {
        settings: settings,
        message: this.buildSuccessMessage(messagePrefix, source),
        success: true
      };
    } catch (error) {
      return this.buildFailureResult(url, title, this.stringifyError(error), existing, 'remote');
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
      const messagePrefix = existing === undefined ? '已导入' : '已更新';
      const settings = await this.storeSource(source, payload, false);
      return {
        settings: settings,
        message: this.buildSuccessMessage(messagePrefix, source),
        success: true
      };
    } catch (error) {
      return this.buildFailureResult(uri, title, this.stringifyError(error), existing, 'local');
    }
  }

  private async storeRemoteSource(
    source: AdBlockCustomRuleSource,
    payload: string,
    forceEnabled: boolean
  ): Promise<AdBlockSettings> {
    return this.storeSource(source, payload, forceEnabled);
  }

  private async storeSource(
    source: AdBlockCustomRuleSource,
    payload: string,
    forceEnabled: boolean
  ): Promise<AdBlockSettings> {
    return this.enqueueRepositoryMutation(async (): Promise<AdBlockSettings> => {
      const existing = this.findSource(source.id);
      source.enabled = forceEnabled ? true : (existing?.enabled ?? source.enabled);
      source.createdAt = existing?.createdAt ?? source.createdAt;
      let sourceCommitted: boolean = false;
      let payloadCommitted: boolean = false;
      try {
        await this.nativeRuleProvider.stageSourcePayload(source.id, payload);
        const payloadInfo = await this.nativeRuleProvider.validateStagedSourcePayload(source.id);
        source.payloadIdentity = payloadInfo.identity;
        source.nativeNetworkRuleCount = payloadInfo.networkRuleCount;
        source.nativeCosmeticRuleCount = payloadInfo.cosmeticRuleCount;
        source.ruleCount = payloadInfo.ruleCount;
        if (source.ruleCount <= 0) {
          throw new Error('没有解析到可用规则');
        }
        await this.nativeRuleProvider.commitStagedSourcePayload(source.id);
        payloadCommitted = true;
        const settings = await this.runtimeGeneration.upsertCustomRuleSource(source);
        sourceCommitted = true;
        const nativeResult = await this.nativeRuleProvider.reconcile(settings);
        if (!await this.acceptNativeAuthority(settings, nativeResult)) {
          throw new Error('原生过滤规则加载失败，请重试');
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
      message: '未找到这条规则订阅',
      success: false
    };
  }

  private buildNativeActivationFailureResult(
    settings: AdBlockSettings,
    message: string = '原生过滤规则加载失败，请重试'
  ): AdBlockRuleSourceResult {
    return {
      settings: settings,
      message: message,
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
      message: '当前会话不可修改网页内容过滤设置',
      success: false
    };
  }

  private isValidSubscriptionUrl(url: string): boolean {
    return url.startsWith('https://') && url.indexOf('.') > 0;
  }

  private buildSuccessMessage(prefix: string, source: AdBlockCustomRuleSource): string {
    return `${prefix} ${source.ruleCount} 条规则`;
  }

  private async buildFailureResult(
    url: string,
    title: string,
    message: string,
    existing: AdBlockCustomRuleSource | undefined,
    sourceType: 'remote' | 'local'
  ): Promise<AdBlockRuleSourceResult> {
    if (existing === undefined) {
      return {
        settings: this.repository.getSettings(),
        message: message,
        success: false
      };
    }
    return this.enqueueRepositoryMutation(async (): Promise<AdBlockRuleSourceResult> => {
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
    if (source.lastError.trim().length > 0 && now - source.updatedAt < RULE_SOURCE_AUTO_UPDATE_INTERVAL_MS) {
      return false;
    }
    return this.isRuleSourceAutoUpdateDue(source, now);
  }

  private isRemovedBuiltInRuleSourceId(sourceId: string): boolean {
    return sourceId === BUILT_IN_AD_BLOCK_RULE_SOURCE_ID ||
      sourceId === SMOOTH_MODE_AD_BLOCK_RULE_SOURCE_ID ||
      sourceId === APP_PROMOTION_BANNER_RULE_SOURCE_ID;
  }

  private isRuleSourceAutoUpdateDue(source: AdBlockCustomRuleSource, now: number): boolean {
    const lastUpdatedAt = source.lastUpdatedAt > 0 ? source.lastUpdatedAt : source.updatedAt;
    return lastUpdatedAt <= 0 || now - lastUpdatedAt >= RULE_SOURCE_AUTO_UPDATE_INTERVAL_MS;
  }

  private stringifyError(error: Error | Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const maybeError = error as Error;
    if (maybeError.message !== undefined && maybeError.message.length > 0) {
      return maybeError.message;
    }
    return '规则订阅更新失败';
  }
}
