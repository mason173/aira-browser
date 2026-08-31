import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { OfflinePageRecord } from '../../common/models/OfflinePageModels';
import { OfflinePageFileStore } from '../../data/offline/OfflinePageFileStore';
import { OfflinePageRepository } from '../../data/offline/OfflinePageRepository';
import { BrowserPrivacyEffectPolicyService } from '../privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export interface OfflinePageExportResult {
  ok: boolean;
  message: string;
}

export class OfflinePageExportService {
  private repository: OfflinePageRepository;
  private fileStore: OfflinePageFileStore;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    repository: OfflinePageRepository,
    fileStore: OfflinePageFileStore = new OfflinePageFileStore(),
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.fileStore = fileStore;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  async exportPage(
    context: common.UIAbilityContext,
    pageId: string,
    dataScope: string,
    privacyMode: string
  ): Promise<OfflinePageExportResult> {
    const normalizedPageId = pageId.trim();
    if (normalizedPageId.length === 0) {
      return {
        ok: false,
        message: '未找到要导出的离线页面'
      };
    }
    try {
      await this.repository.initialize();
      const record = await this.repository.findById(normalizedPageId);
      if (record === undefined) {
        return {
          ok: false,
          message: '离线页面不存在'
        };
      }
      if (!await this.fileStore.textFileAvailable(record.snapshotPath)) {
        return {
          ok: false,
          message: '离线网页文件不存在'
        };
      }
      const targetUri = await this.pickSaveUri(context, this.buildExportFileName(record));
      if (targetUri.length <= 0) {
        return {
          ok: false,
          message: '已取消导出'
        };
      }
      if (!this.canExport(dataScope, privacyMode)) {
        return {
          ok: false,
          message: '当前隐私策略不允许导出离线页面'
        };
      }
      const html = await this.fileStore.readText(record.snapshotPath);
      await this.writeTextToUri(targetUri, html);
      return {
        ok: true,
        message: '已导出网页文件'
      };
    } catch (_error) {
      return {
        ok: false,
        message: '导出网页失败'
      };
    }
  }

  private canExport(dataScope: string, privacyMode: string): boolean {
    return this.privacyEffectPolicy.decide({
      intent: 'regular_profile_management_export',
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: dataScope,
        privacyMode: privacyMode
      }),
      targetScope: 'user_selected_external_location',
      targetIsClear: true
    }).outcome === 'allow';
  }

  private async pickSaveUri(context: common.UIAbilityContext, fileName: string): Promise<string> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save({
      newFileNames: [fileName],
      fileSuffixChoices: ['HTML|.html']
    });
    if (uris.length <= 0) {
      return '';
    }
    return uris[0];
  }

  private async writeTextToUri(uri: string, payload: string): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload);
    } finally {
      await fileIo.close(file);
    }
  }

  private buildExportFileName(record: OfflinePageRecord): string {
    const title = record.title.trim().length > 0 ? record.title : record.host;
    const safeTitle = this.sanitizeFileName(title.length > 0 ? title : 'saved-page');
    const timestamp = this.formatTimestamp(record.savedAt > 0 ? record.savedAt : Date.now());
    return `${safeTitle}-${timestamp}.html`;
  }

  private sanitizeFileName(value: string): string {
    const sanitized = value.trim()
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, '_')
      .replace(/_+/g, '_');
    const trimmed = sanitized.replace(/^_+|_+$/g, '');
    if (trimmed.length <= 0) {
      return 'saved-page';
    }
    return trimmed.substring(0, 72);
  }

  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    const year = date.getFullYear();
    const month = this.pad2(date.getMonth() + 1);
    const day = this.pad2(date.getDate());
    const hour = this.pad2(date.getHours());
    const minute = this.pad2(date.getMinutes());
    return `${year}${month}${day}-${hour}${minute}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : `${value}`;
  }
}
