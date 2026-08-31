import { common } from '@kit.AbilityKit';
import { fileIo, picker } from '@kit.CoreFileKit';
import { UserScriptExportPayload } from '../../features/userscripts/UserScriptMetadataModels';
import { BrowserPrivacyEffectPolicyService } from '../privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';

export type UserScriptExportStatus = 'exported' | 'canceled' | 'failed';

export interface UserScriptExportResult {
  status: UserScriptExportStatus;
  message: string;
  targetUri?: string;
}

export interface UserScriptExportBoundary {
  dataScope?: string;
  privacyMode?: string;
}

export class UserScriptExportService {
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  async exportScript(
    context: common.UIAbilityContext,
    script: UserScriptExportPayload,
    boundary: UserScriptExportBoundary
  ): Promise<UserScriptExportResult> {
    try {
      const targetUri = await this.pickSaveUri(context, this.buildFileName(script));
      if (targetUri === undefined) {
        return {
          status: 'canceled',
          message: '已取消导出脚本。'
        };
      }
      const decision = this.privacyEffectPolicy.decide({
        intent: 'user_script_export',
        requestingBoundary: this.profileBoundaryService.buildBoundary({
          dataScope: boundary.dataScope,
          privacyMode: boundary.privacyMode
        }),
        targetScope: 'user_selected_external_location',
        targetIsClear: true
      });
      if (decision.outcome !== 'allow') {
        return {
          status: 'failed',
          message: '当前会话不可导出用户脚本。'
        };
      }
      await this.writeSource(targetUri, this.normalizeSource(script.source));
      return {
        status: 'exported',
        message: `已导出“${script.name}”。`,
        targetUri: targetUri
      };
    } catch (_error) {
      return {
        status: 'failed',
        message: '导出脚本失败，请稍后重试。'
      };
    }
  }

  private async pickSaveUri(context: common.UIAbilityContext, fileName: string): Promise<string | undefined> {
    const documentPicker = new picker.DocumentViewPicker(context);
    const uris = await documentPicker.save({
      newFileNames: [fileName],
      fileSuffixChoices: ['用户脚本|.user.js']
    });
    return uris.length > 0 && uris[0].length > 0 ? uris[0] : undefined;
  }

  private async writeSource(uri: string, source: string): Promise<void> {
    const file = await fileIo.open(uri, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, source);
    } finally {
      await fileIo.close(file);
    }
  }

  private buildFileName(script: UserScriptExportPayload): string {
    const baseName = script.name.trim().replace(/\.user\.js$/i, '');
    const sanitized = baseName
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_+|_+$/g, '');
    const safeName = sanitized.length > 0 ? sanitized.substring(0, 72) : 'user-script';
    return `${safeName}.user.js`;
  }

  private normalizeSource(source: string): string {
    return source.endsWith('\n') ? source : `${source}\n`;
  }
}
