import { common, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CustomHomepageItem,
  CustomHomepageRepositorySnapshot,
} from '../../common/models/CustomHomepageModels';
import { CustomHomepageRepository } from '../../data/customhome/CustomHomepageRepository';
import {
  CustomHomepageValueRepository,
  sharedCustomHomepageValueRepository
} from '../../data/customhome/CustomHomepageValueRepository';
import {
  CustomHomepageFileService,
  CustomHomepagePreparedPackageImport
} from '../../services/customhome/CustomHomepageFileService';
import { CustomHomepagePreferenceService } from '../../services/customhome/CustomHomepagePreferenceService';
import {
  CustomHomepageExternalImportService
} from '../../services/customhome/CustomHomepageExternalImportService';
import { CustomHomepageUrlService } from '../../services/customhome/CustomHomepageUrlService';
import {
  CustomHomepagePreviewPair,
  CustomHomepageSettingsViewModel
} from './CustomHomepageSettingsViewModel';
import {
  CustomHomepageExternalImportEnvelope,
  CustomHomepageExternalImportListener,
  CustomHomepageExternalImportRuntime,
  CustomHomepageExternalImportStageResult
} from './CustomHomepageExternalImportRuntime';

const CUSTOM_HOMEPAGE_LOG_DOMAIN: number = 0x0000;
const CUSTOM_HOMEPAGE_LOG_TAG: string = 'CustomHomepage';

export interface CustomHomepageImportResult {
  imported: boolean;
  updated: boolean;
}

export interface CustomHomepagePreparedImportResult {
  prepared: CustomHomepagePreparedPackageImport;
  item: CustomHomepageItem;
  updated: boolean;
}

export interface CustomHomepageExternalImportPresentationHost {
  presentPrepared: (item: CustomHomepageItem, actionLabel: string) => void;
  presentFailure: (message: string) => void;
  setActionEnabled: (enabled: boolean) => void;
  dismiss: () => void;
  notifyCommitted: (result: CustomHomepageImportResult) => void;
  notifyCommitFailure: (message: string) => void;
}

export interface CustomHomepageExternalImportLaunchHost {
  waitForContentReady: () => Promise<void>;
  openSettings: (source: string) => Promise<boolean>;
}

export interface CustomHomepageRemoteAddResult {
  itemId: string;
  url: string;
}

export class CustomHomepageSettingsCoordinator {
  private repository: CustomHomepageRepository;
  private fileService: CustomHomepageFileService;
  private urlService: CustomHomepageUrlService;
  private viewModel: CustomHomepageSettingsViewModel;
  private preferenceService: CustomHomepagePreferenceService;
  private valueRepository: CustomHomepageValueRepository;
  private externalImportService: CustomHomepageExternalImportService;
  private initialized: boolean = false;
  private externalImportRequestSequence: number = 0;
  private latestExternalImportRequestId: string = '';
  private externalImportIngressDestroyed: boolean = false;
  private externalImportPresentationHost?: CustomHomepageExternalImportPresentationHost;
  private externalImportPrepared?: CustomHomepagePreparedPackageImport;
  private externalImportCommitting: boolean = false;
  private externalImportListener: CustomHomepageExternalImportListener = (): void => {
    this.consumePendingExternalImportPresentation();
  };

  constructor(
    repository: CustomHomepageRepository,
    fileService: CustomHomepageFileService = new CustomHomepageFileService(),
    urlService: CustomHomepageUrlService = new CustomHomepageUrlService(),
    viewModel: CustomHomepageSettingsViewModel = new CustomHomepageSettingsViewModel(),
    preferenceService: CustomHomepagePreferenceService = new CustomHomepagePreferenceService(),
    valueRepository: CustomHomepageValueRepository = sharedCustomHomepageValueRepository,
    externalImportService: CustomHomepageExternalImportService = new CustomHomepageExternalImportService()
  ) {
    this.repository = repository;
    this.fileService = fileService;
    this.urlService = urlService;
    this.viewModel = viewModel;
    this.preferenceService = preferenceService;
    this.valueRepository = valueRepository;
    this.externalImportService = externalImportService;
  }

  async ensureReady(): Promise<void> {
    await this.ensureSnapshot();
  }

  async selectSystemHomepage(): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(this.viewModel.buildSystemSettings(snapshot.settings));
  }

  async selectCustomHomepage(itemId: string): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(this.viewModel.buildCustomSettings(snapshot.settings, itemId));
  }

  async updateSystemHomepageSearchBar(visible: boolean): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(
      this.preferenceService.buildSystemHomepageSearchBarSettings(snapshot.settings, visible)
    );
  }

  async updateSelectedHomepageSearchBar(visible: boolean): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(
      this.preferenceService.buildSelectedSystemSearchBarSettings(snapshot.settings, visible)
    );
  }

  async updateSelectedHomepageSystemEntryButton(visible: boolean): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(
      this.preferenceService.buildSelectedSystemEntryButtonSettings(snapshot.settings, visible)
    );
  }

  async updateSelectedHomepageForceDarkMode(enabled: boolean): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(
      this.preferenceService.buildSelectedForceDarkSettings(snapshot.settings, enabled)
    );
  }

  async updateSelectedHomepageHideToolbarOnScroll(enabled: boolean): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(
      this.preferenceService.buildSelectedHideToolbarOnScrollSettings(snapshot.settings, enabled)
    );
  }

  async updateHideToolbarOnScroll(enabled: boolean): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    await this.repository.saveSettings(
      this.preferenceService.buildSystemHomepageHideToolbarOnScrollSettings(snapshot.settings, enabled)
    );
  }

  async importCustomHomepage(context: common.UIAbilityContext): Promise<CustomHomepageImportResult> {
    await this.ensureSnapshot();
    const uri = await this.fileService.pickHomepageFileUri(context);
    if (uri === undefined) {
      return {
        imported: false,
        updated: false
      };
    }
    const snapshot = await this.ensureSnapshot();
    const importedItem = await this.fileService.importHomepageFile(uri);
    const importResult = this.viewModel.buildImportedSettingsResult(snapshot.settings, importedItem);
    await this.repository.saveSettings(importResult.settings);
    if (importResult.replacedItem !== undefined) {
      await this.fileService.removeImportedFile(importResult.replacedItem);
    }
    return {
      imported: true,
      updated: importResult.replacedItem !== undefined
    };
  }

  async prepareExternalHomepageImport(sourceUri: string): Promise<CustomHomepagePreparedImportResult> {
    const prepared = await this.fileService.prepareZipPackage(sourceUri);
    try {
      const snapshot = await this.ensureSnapshot();
      const replacedItem = this.viewModel.findImportReplacementItem(snapshot.settings, prepared.item);
      return {
        prepared: prepared,
        item: prepared.item,
        updated: replacedItem !== undefined
      };
    } catch (error) {
      await this.discardExternalHomepageImportSafely(prepared, 'prepare_snapshot_failure');
      const message = error instanceof Error ? error.message : '主页包预检未完成。';
      throw new Error(message);
    }
  }

  async commitExternalHomepageImport(
    prepared: CustomHomepagePreparedPackageImport
  ): Promise<CustomHomepageImportResult> {
    const snapshot = await this.ensureSnapshot();
    let importedItem: CustomHomepageItem | undefined = undefined;
    try {
      importedItem = await this.fileService.commitPreparedZipPackage(prepared);
      const importResult = this.viewModel.buildImportedSettingsResult(snapshot.settings, importedItem);
      await this.repository.saveSettings(importResult.settings);
      if (importResult.replacedItem !== undefined) {
        await this.fileService.removeImportedFile(importResult.replacedItem)
          .catch((cleanupError: Error): void => {
            this.logExternalImportCleanupFailure('replace_old_package', cleanupError);
          });
      }
      return {
        imported: true,
        updated: importResult.replacedItem !== undefined
      };
    } catch (error) {
      if (importedItem !== undefined) {
        await this.fileService.removeImportedFile(importedItem);
      } else {
        await this.discardExternalHomepageImportSafely(prepared, 'commit_failure');
      }
      const message = error instanceof Error ? error.message : '主页包导入未完成。';
      throw new Error(message);
    }
  }

  async discardExternalHomepageImport(prepared: CustomHomepagePreparedPackageImport): Promise<void> {
    await this.fileService.discardPreparedZipPackage(prepared);
  }

  handleExternalImportWant(
    want: Want,
    source: string,
    host: CustomHomepageExternalImportLaunchHost
  ): boolean {
    if (!this.externalImportService.isCandidate(want)) {
      return false;
    }
    const requestId = `external_home_${Date.now()}_${++this.externalImportRequestSequence}`;
    this.latestExternalImportRequestId = requestId;
    void this.prepareAndStageExternalHomepageImport(want, requestId, source, host);
    return true;
  }

  destroyExternalImportIngress(): void {
    this.externalImportIngressDestroyed = true;
    void this.discardPendingExternalHomepageImport();
  }

  attachExternalImportPresentation(host: CustomHomepageExternalImportPresentationHost): void {
    this.externalImportPresentationHost = host;
    CustomHomepageExternalImportRuntime.subscribe(this.externalImportListener);
    this.consumePendingExternalImportPresentation();
  }

  detachExternalImportPresentation(): void {
    CustomHomepageExternalImportRuntime.unsubscribe(this.externalImportListener);
    this.externalImportPresentationHost = undefined;
    this.discardPresentedExternalImportIfNeeded();
  }

  consumePendingExternalImportPresentation(): void {
    const host = this.externalImportPresentationHost;
    if (host === undefined || this.externalImportCommitting) {
      return;
    }
    const envelope = CustomHomepageExternalImportRuntime.consume();
    if (envelope === undefined) {
      return;
    }
    this.discardPresentedExternalImportIfNeeded();
    if (envelope.status === 'failed') {
      host.presentFailure(envelope.errorMessage);
      return;
    }
    if (envelope.prepared === undefined || envelope.item === undefined) {
      if (envelope.prepared !== undefined) {
        void this.discardExternalHomepageImportSafely(envelope.prepared, 'invalid_envelope');
      }
      host.presentFailure('主页包预检状态不可用。');
      return;
    }
    this.externalImportPrepared = envelope.prepared;
    host.presentPrepared(envelope.item, envelope.updated ? '更新主页' : '导入主页');
  }

  commitPresentedExternalHomepageImport(): void {
    const prepared = this.externalImportPrepared;
    if (prepared === undefined || this.externalImportCommitting) {
      return;
    }
    this.externalImportCommitting = true;
    this.externalImportPresentationHost?.setActionEnabled(false);
    this.commitExternalHomepageImport(prepared)
      .then((result: CustomHomepageImportResult): void => {
        this.externalImportPrepared = undefined;
        this.externalImportCommitting = false;
        const host = this.externalImportPresentationHost;
        host?.dismiss();
        host?.notifyCommitted(result);
        this.consumePendingExternalImportPresentation();
      })
      .catch((error: Error): void => {
        this.externalImportPrepared = undefined;
        this.externalImportCommitting = false;
        const host = this.externalImportPresentationHost;
        host?.dismiss();
        host?.notifyCommitFailure(error.message.length > 0 ? error.message : '未知错误');
        this.consumePendingExternalImportPresentation();
      });
  }

  dismissPresentedExternalHomepageImport(): void {
    if (this.externalImportCommitting) {
      return;
    }
    this.discardPresentedExternalImportIfNeeded();
  }

  async exportCustomHomepage(context: common.UIAbilityContext, itemId: string): Promise<boolean> {
    const snapshot = await this.ensureSnapshot();
    const item = this.viewModel.findItem(snapshot.settings, itemId);
    if (item === undefined) {
      throw new Error('自定义主页不存在。');
    }
    return await this.fileService.exportHomepageFile(context, item);
  }

  async addRemoteHomepage(rawUrl: string): Promise<CustomHomepageRemoteAddResult> {
    const snapshot = await this.ensureSnapshot();
    const url = this.urlService.buildRemoteHomepageUrl(rawUrl);
    const title = this.urlService.buildRemoteHomepageTitle(url);
    const result = this.viewModel.buildRemoteUrlSettingsResult(snapshot.settings, url, title);
    await this.repository.saveSettings(result.settings);
    return {
      itemId: result.item.id,
      url: result.item.remoteUrl
    };
  }

  async removeCustomHomepage(itemId: string): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    const item = this.viewModel.findItem(snapshot.settings, itemId);
    if (item !== undefined) {
      await this.fileService.removeImportedFile(item);
      await this.repository.removeItem(item.id);
      await this.valueRepository.clearValues(item.id);
    }
  }

  async updateRemoteHomepageSiteIcon(itemId: string, siteIconUri: string): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    const item = this.viewModel.findItem(snapshot.settings, itemId);
    if (item === undefined || item.kind !== 'remote_url' || item.siteIconUri === siteIconUri.trim()) {
      return;
    }
    await this.repository.saveSettings(
      this.viewModel.buildSiteIconSettings(snapshot.settings, item.id, siteIconUri)
    );
  }

  async updateRemoteHomepagePreviews(
    itemId: string,
    previews: CustomHomepagePreviewPair
  ): Promise<void> {
    const snapshot = await this.ensureSnapshot();
    const item = this.viewModel.findItem(snapshot.settings, itemId);
    const normalizedLightUri = previews.lightUri.trim();
    const normalizedDarkUri = previews.darkUri.trim();
    if (item === undefined || item.kind !== 'remote_url' ||
      (item.previewLightUri === normalizedLightUri &&
        item.previewDarkUri === normalizedDarkUri &&
        previews.lightAppearance === undefined &&
        previews.darkAppearance === undefined)) {
      return;
    }
    await this.repository.saveSettings(
      this.viewModel.buildPreviewPairSettings(snapshot.settings, item.id, {
        lightUri: normalizedLightUri,
        darkUri: normalizedDarkUri,
        lightAppearance: previews.lightAppearance,
        darkAppearance: previews.darkAppearance
      })
    );
  }

  findItem(itemId: string): CustomHomepageItem | undefined {
    return this.viewModel.findItem(this.repository.getSettings(), itemId);
  }

  private async ensureSnapshot(): Promise<CustomHomepageRepositorySnapshot> {
    if (!this.initialized) {
      const snapshot = await this.repository.initialize();
      this.initialized = true;
      return snapshot;
    }
    return Promise.resolve(this.repository.getSnapshot());
  }

  private async prepareAndStageExternalHomepageImport(
    want: Want,
    requestId: string,
    source: string,
    host: CustomHomepageExternalImportLaunchHost
  ): Promise<void> {
    let envelope: CustomHomepageExternalImportEnvelope;
    try {
      const sourceUri = await this.externalImportService.resolveSourceUri(want);
      const preparedResult = await this.prepareExternalHomepageImport(sourceUri);
      envelope = {
        requestId: requestId,
        status: 'prepared',
        prepared: preparedResult.prepared,
        item: preparedResult.item,
        updated: preparedResult.updated,
        errorMessage: ''
      };
    } catch (error) {
      envelope = {
        requestId: requestId,
        status: 'failed',
        updated: false,
        errorMessage: this.externalImportService.buildUserFacingError(error)
      };
    }
    if (this.externalImportIngressDestroyed || requestId !== this.latestExternalImportRequestId) {
      await this.discardExternalHomepageImportEnvelope(envelope);
      return;
    }
    const stageResult = CustomHomepageExternalImportRuntime.stage(envelope);
    await this.discardDisplacedExternalHomepageImport(stageResult);
    if (stageResult.notifiedListenerCount > 0) {
      return;
    }
    await host.waitForContentReady();
    if (this.externalImportIngressDestroyed || !CustomHomepageExternalImportRuntime.isPending(requestId)) {
      return;
    }
    let handled = false;
    try {
      handled = await host.openSettings(source);
    } catch (_error) {}
    if (!handled) {
      await this.discardPendingExternalHomepageImport(requestId);
    }
  }

  private async discardPendingExternalHomepageImport(requestId: string = ''): Promise<void> {
    const envelope = CustomHomepageExternalImportRuntime.consume(requestId);
    if (envelope === undefined) {
      return;
    }
    await this.discardExternalHomepageImportEnvelope(envelope);
  }

  private async discardExternalHomepageImportEnvelope(
    envelope: CustomHomepageExternalImportEnvelope
  ): Promise<void> {
    const prepared = envelope.prepared;
    if (prepared === undefined) {
      return;
    }
    await this.discardExternalHomepageImportSafely(prepared, 'discard_envelope');
  }

  private async discardDisplacedExternalHomepageImport(
    stageResult: CustomHomepageExternalImportStageResult
  ): Promise<void> {
    const displaced = stageResult.displaced;
    if (displaced === undefined) {
      return;
    }
    await this.discardExternalHomepageImportEnvelope(displaced);
  }

  private discardPresentedExternalImportIfNeeded(): void {
    const prepared = this.externalImportPrepared;
    if (prepared === undefined || this.externalImportCommitting) {
      return;
    }
    this.externalImportPrepared = undefined;
    void this.discardExternalHomepageImportSafely(prepared, 'dismiss_presentation');
  }

  private async discardExternalHomepageImportSafely(
    prepared: CustomHomepagePreparedPackageImport,
    reason: string
  ): Promise<void> {
    try {
      await this.discardExternalHomepageImport(prepared);
    } catch (error) {
      this.logExternalImportCleanupFailure(reason, error);
    }
  }

  private logExternalImportCleanupFailure(reason: string, error: Object | undefined): void {
    const message = error instanceof Error && error.message.trim().length > 0
      ? error.message.trim()
      : '未知清理错误';
    hilog.warn(
      CUSTOM_HOMEPAGE_LOG_DOMAIN,
      CUSTOM_HOMEPAGE_LOG_TAG,
      'External homepage import cleanup failed reason=%{public}s error=%{public}s',
      reason,
      message
    );
  }
}
