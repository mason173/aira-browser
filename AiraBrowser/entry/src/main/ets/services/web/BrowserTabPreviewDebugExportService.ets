import { common } from '@kit.AbilityKit';
import { fileUri, picker } from '@kit.CoreFileKit';
import { DownloadFileResolutionService } from '../download/DownloadFileResolutionService';

export type BrowserTabPreviewDebugExportSnapshotKind = 'shared' | 'preview';

export interface BrowserTabPreviewDebugExportSnapshot {
  tabId: string;
  uri: string;
  kind: BrowserTabPreviewDebugExportSnapshotKind;
  width: number;
  height: number;
  capturedAt: number;
  source: string;
}

export interface BrowserTabPreviewDebugExportResult {
  success: boolean;
  targetUri?: string;
  userMessage: string;
}

export class BrowserTabPreviewDebugExportService {
  private fileResolutionService: DownloadFileResolutionService = new DownloadFileResolutionService();

  async exportSnapshot(
    context: common.UIAbilityContext,
    candidate: BrowserTabPreviewDebugExportSnapshot
  ): Promise<BrowserTabPreviewDebugExportResult> {
    const sourceUri = candidate.uri.trim();
    if (sourceUri.length <= 0) {
      return {
        success: false,
        userMessage: '标签页动画快照导出失败：没有可导出的快照文件。'
      };
    }

    try {
      const fileName = this.buildFileName(candidate);
      const documentPicker = new picker.DocumentViewPicker(context);
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      saveOptions.newFileNames = [fileName];
      const targetUris = await documentPicker.save(saveOptions);
      if (targetUris.length <= 0 || targetUris[0].length <= 0) {
        return {
          success: false,
          userMessage: '已取消导出标签页动画快照。'
        };
      }
      const exportResolution = this.fileResolutionService.buildExportResolution(fileName, targetUris[0]);
      const targetUri = await this.fileResolutionService.copyLocalPathWithoutOverwrite(
        new fileUri.FileUri(sourceUri).path,
        exportResolution.targetUri,
        exportResolution.conflictResolvedUri
      );
      return {
        success: true,
        targetUri: targetUri,
        userMessage: `已导出标签页动画快照：${candidate.width}x${candidate.height}。`
      };
    } catch (_error) {
      return {
        success: false,
        userMessage: '标签页动画快照导出失败，请稍后重试。'
      };
    }
  }

  private buildFileName(candidate: BrowserTabPreviewDebugExportSnapshot): string {
    const capturedAt = candidate.capturedAt > 0 ? candidate.capturedAt : Date.now();
    const timestamp = new Date(capturedAt).toISOString()
      .replace(/[:.]/g, '-')
      .replace('T', '_')
      .replace('Z', '');
    return this.sanitizeFileName(`aira-tab-${candidate.kind}-snapshot-${timestamp}-${candidate.tabId}.jpg`);
  }

  private sanitizeFileName(fileName: string): string {
    const sanitized = fileName
      .replace(/[\\/:*?"<>|]/g, '_')
      .replace(/\s+/g, ' ')
      .trim();
    return sanitized.length > 0 ? sanitized : 'aira-tab-snapshot.jpg';
  }
}
