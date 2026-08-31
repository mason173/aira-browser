import { common } from '@kit.AbilityKit';
import { BrowserBoundaryRouteState, isPrivateBoundaryRoute } from '../../common/utils/RouteParamUtils';
import {
  LocalBackupImportResult,
  LocalBackupInspection,
  LocalBackupSelection
} from '../../features/backup/LocalBackupModels';
import { LocalBackupFileService } from '../../services/backup/LocalBackupFileService';
import { LocalBackupService } from '../../services/backup/LocalBackupService';
import { SyncExperienceCoordinator } from '../sync/SyncExperienceCoordinator';

export type LocalBackupActionStatus = 'completed' | 'cancelled' | 'failed';

export interface LocalBackupActionOutcome {
  status: LocalBackupActionStatus;
  title: string;
  message: string;
  inspection?: LocalBackupInspection;
  importResult?: LocalBackupImportResult;
}

export interface LocalBackupSyncExperienceDomain {
  runLocalBackupImport<T>(operation: () => Promise<T>): Promise<T>;
  recordBookmarkMutation(changedAt: number): Promise<void>;
  notifyPersonalizationLocalSettingsChanged(): void;
}

export class LocalBackupCoordinator {
  private readonly backupService: LocalBackupService;
  private readonly fileService: LocalBackupFileService;
  private readonly syncExperienceCoordinator: SyncExperienceCoordinator | LocalBackupSyncExperienceDomain;

  constructor(
    backupService: LocalBackupService,
    syncExperienceCoordinator: SyncExperienceCoordinator | LocalBackupSyncExperienceDomain,
    fileService: LocalBackupFileService = new LocalBackupFileService()
  ) {
    this.backupService = backupService;
    this.syncExperienceCoordinator = syncExperienceCoordinator;
    this.fileService = fileService;
  }

  async exportBackup(
    context: common.UIAbilityContext,
    selection: LocalBackupSelection,
    boundary: BrowserBoundaryRouteState
  ): Promise<LocalBackupActionOutcome> {
    if (!this.isBoundaryAllowed(boundary)) {
      return this.failure('当前隐私会话不能导出普通资料。');
    }
    try {
      const uri = await this.fileService.pickExportUri(context);
      if (uri === undefined) {
        return this.cancelled();
      }
      const payload = await this.backupService.buildExportPayload(selection);
      await this.fileService.writePayload(uri, payload);
      return {
        status: 'completed',
        title: '导出完成',
        message: '本地备份文件已保存。'
      };
    } catch (error) {
      return this.failure(this.stringifyError(error));
    }
  }

  async prepareImport(
    context: common.UIAbilityContext,
    boundary: BrowserBoundaryRouteState
  ): Promise<LocalBackupActionOutcome> {
    if (!this.isBoundaryAllowed(boundary)) {
      return this.failure('当前隐私会话不能导入普通资料。');
    }
    try {
      const uri = await this.fileService.pickImportUri(context);
      if (uri === undefined) {
        return this.cancelled();
      }
      const inspection = this.backupService.inspectPayload(await this.fileService.readPayload(uri));
      return {
        status: 'completed',
        title: '',
        message: '',
        inspection: inspection
      };
    } catch (error) {
      return this.failure(this.stringifyError(error));
    }
  }

  async importPrepared(
    inspection: LocalBackupInspection,
    selection: LocalBackupSelection,
    boundary: BrowserBoundaryRouteState
  ): Promise<LocalBackupActionOutcome> {
    if (!this.isBoundaryAllowed(boundary)) {
      return this.failure('当前隐私会话不能导入普通资料。');
    }
    try {
      const result = await this.syncExperienceCoordinator.runLocalBackupImport(
        async (): Promise<LocalBackupImportResult> => {
          const importResult = await this.backupService.importDocument(inspection.document, selection);
          if (selection.bookmarks && inspection.document.sections.bookmarks !== undefined &&
            importResult.bookmarkCount > 0) {
            await this.syncExperienceCoordinator.recordBookmarkMutation(Date.now());
          }
          if (selection.personalization && inspection.document.sections.personalization !== undefined &&
            importResult.personalizationCount > 0) {
            this.syncExperienceCoordinator.notifyPersonalizationLocalSettingsChanged();
          }
          return importResult;
        }
      );
      return {
        status: 'completed',
        title: '导入完成',
        message: this.buildImportSummary(result),
        importResult: result
      };
    } catch (error) {
      return this.failure(
        `${this.stringifyError(error)} 已完成的内容不会自动回滚，请检查后重试。`
      );
    }
  }

  private isBoundaryAllowed(boundary: BrowserBoundaryRouteState): boolean {
    return !isPrivateBoundaryRoute(boundary.dataScope, boundary.privacyMode);
  }

  private buildImportSummary(result: LocalBackupImportResult): string {
    const parts: string[] = [];
    if (result.bookmarkCount > 0) {
      parts.push(`${result.bookmarkCount} 个书签节点`);
    }
    if (result.historyCount > 0) {
      parts.push(`${result.historyCount} 条历史记录`);
    }
    if (result.personalizationCount > 0) {
      parts.push(`${result.personalizationCount} 组常用设置`);
    }
    if (result.userScriptCount > 0) {
      parts.push(`${result.userScriptCount} 个用户脚本`);
    }
    if (result.userScriptValueCount > 0) {
      parts.push(`${result.userScriptValueCount} 项脚本数据`);
    }
    const restored = parts.length > 0 ? `已恢复${parts.join('、')}。` : '所选内容已经存在，无需更改。';
    if (result.skippedUserScriptCount <= 0) {
      return restored;
    }
    return `${restored} 另有 ${result.skippedUserScriptCount} 个脚本未能恢复。`;
  }

  private cancelled(): LocalBackupActionOutcome {
    return { status: 'cancelled', title: '', message: '' };
  }

  private failure(message: string): LocalBackupActionOutcome {
    return {
      status: 'failed',
      title: '操作失败',
      message: message.length > 0 ? message : '未知错误'
    };
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return '操作失败，请稍后重试。';
  }
}
