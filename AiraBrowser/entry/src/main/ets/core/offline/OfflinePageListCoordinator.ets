import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService,
  BrowserPrivacyEffectTargetScope
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import {
  OfflinePageDeleteResult,
  OfflinePageListState,
  OfflinePageOpenStatus,
  OfflinePageRecord
} from '../../common/models/OfflinePageModels';
import { OfflinePageFileStore } from '../../data/offline/OfflinePageFileStore';
import { OfflinePageRepository } from '../../data/offline/OfflinePageRepository';
import { OfflinePageListViewModel } from './OfflinePageListViewModel';

export interface OfflinePageListCoordinatorOptions {
  repository: OfflinePageRepository;
  fileStore?: OfflinePageFileStore;
  viewModel?: OfflinePageListViewModel;
  privacyEffectPolicy?: BrowserPrivacyEffectPolicyService;
  profileBoundaryService?: BrowserProfileBoundaryService;
}

export class OfflinePageListCoordinator {
  private repository: OfflinePageRepository;
  private fileStore: OfflinePageFileStore;
  private viewModel: OfflinePageListViewModel;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(options: OfflinePageListCoordinatorOptions) {
    this.repository = options.repository;
    this.fileStore = options.fileStore ?? new OfflinePageFileStore();
    this.viewModel = options.viewModel ?? new OfflinePageListViewModel();
    this.privacyEffectPolicy = options.privacyEffectPolicy ?? new BrowserPrivacyEffectPolicyService();
    this.profileBoundaryService = options.profileBoundaryService ?? new BrowserProfileBoundaryService();
  }

  async load(dataScope: string, privacyMode: string, limit?: number): Promise<OfflinePageListState> {
    if (!this.isAllowed(
      'regular_profile_management_read',
      'regular_profile_data',
      dataScope,
      privacyMode
    )) {
      return this.viewModel.buildFailureState('当前隐私策略不允许读取已保存页面');
    }
    try {
      await this.repository.initialize();
      const records = await this.repository.list(limit);
      const persistStatusRepairs = !this.profileBoundaryService.isSessionEphemeral({
        dataScope: dataScope,
        privacyMode: privacyMode
      });
      const verifiedRecords = await this.verifyOpenStatuses(records, persistStatusRepairs);
      return this.viewModel.buildState(verifiedRecords);
    } catch (_error) {
      return this.viewModel.buildFailureState('已保存页面读取失败');
    }
  }

  async delete(pageId: string, dataScope: string, privacyMode: string): Promise<OfflinePageDeleteResult> {
    if (!this.isAllowed(
      'regular_profile_management_mutation',
      'regular_profile_data',
      dataScope,
      privacyMode
    )) {
      return {
        ok: false,
        message: '当前隐私策略不允许删除离线页面'
      };
    }
    const normalizedId = pageId.trim();
    if (normalizedId.length === 0) {
      return {
        ok: false,
        message: '未找到要删除的离线页面'
      };
    }
    try {
      const record = await this.repository.findById(normalizedId);
      if (record === undefined) {
        return {
          ok: false,
          message: '离线页面不存在'
        };
      }
      await this.deleteFiles(record);
      await this.repository.delete(record.id);
      return {
        ok: true,
        message: '离线页面已删除'
      };
    } catch (_error) {
      return {
        ok: false,
        message: '删除离线页面失败'
      };
    }
  }

  canNavigate(dataScope: string, privacyMode: string): boolean {
    return this.isAllowed(
      'regular_profile_management_navigation',
      'regular_profile_data',
      dataScope,
      privacyMode
    );
  }

  private async deleteFiles(record: OfflinePageRecord): Promise<void> {
    await this.fileStore.removePage(record.id);
  }

  private async verifyOpenStatuses(
    records: OfflinePageRecord[],
    persistStatusRepairs: boolean
  ): Promise<OfflinePageRecord[]> {
    const verified: OfflinePageRecord[] = [];
    for (let index = 0; index < records.length; index += 1) {
      verified.push(await this.verifyOpenStatus(records[index], persistStatusRepairs));
    }
    return verified;
  }

  private async verifyOpenStatus(
    record: OfflinePageRecord,
    persistStatusRepair: boolean
  ): Promise<OfflinePageRecord> {
    if (await this.fileStore.textFileAvailable(record.snapshotPath)) {
      if (record.openStatus === 'available') {
        return record;
      }
      const nextRecord = this.cloneRecordWithOpenStatus(record, 'available');
      if (persistStatusRepair) {
        await this.repository.upsert(nextRecord);
      }
      return nextRecord;
    }
    if (record.openStatus === 'missing_snapshot') {
      return record;
    }
    const nextRecord = this.cloneRecordWithOpenStatus(record, 'missing_snapshot');
    if (persistStatusRepair) {
      await this.repository.upsert(nextRecord);
    }
    return nextRecord;
  }

  private cloneRecordWithOpenStatus(
    record: OfflinePageRecord,
    openStatus: OfflinePageOpenStatus
  ): OfflinePageRecord {
    return {
      id: record.id,
      originalUrl: record.originalUrl,
      normalizedUrl: record.normalizedUrl,
      urlHash: record.urlHash,
      title: record.title,
      siteName: record.siteName,
      host: record.host,
      savedAt: record.savedAt,
      updatedAt: record.updatedAt,
      snapshotPath: record.snapshotPath,
      manifestPath: record.manifestPath,
      previewImageUri: record.previewImageUri,
      faviconUri: record.faviconUri,
      totalBytes: record.totalBytes,
      resourceCount: record.resourceCount,
      failedResourceCount: record.failedResourceCount,
      saveStatus: record.saveStatus,
      openStatus: openStatus
    };
  }

  private isAllowed(
    intent: BrowserPrivacyEffectIntent,
    targetScope: BrowserPrivacyEffectTargetScope,
    dataScope: string,
    privacyMode: string
  ): boolean {
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: targetScope,
      targetIsClear: true
    }).outcome === 'allow';
  }
}
