import { Want, common } from '@kit.AbilityKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { filePreview } from '@kit.PreviewKit';
import { systemShare } from '@kit.ShareKit';
import wantConstant from '@ohos.app.ability.wantConstant';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  DownloadFileResolutionAdapter,
  DownloadFileResolutionService
} from './DownloadFileResolutionService';

export interface DownloadFollowupExecutionResult {
  success: boolean;
  finalFileUri?: string;
  userMessage?: string;
}

export interface DownloadFollowupTask {
  suggestedFileName: string;
  mimeType?: string;
  tempLocalPath?: string;
  finalFileUri?: string;
}

const APK_MIME_TYPE = 'application/vnd.android.package-archive';
const WANT_ACTION_VIEW_DATA = 'ohos.want.action.viewData';
const WANT_PARAMETER_SHOW_DEFAULT_PICKER = 'ohos.ability.params.showDefaultPicker';
const WANT_PARAMETER_FILE_NAME = 'fileName';
const WANT_PARAMETER_DISPLAY_NAME = 'displayName';

interface DownloadFileMimeMapping {
  extension: string;
  mimeType: string;
}

interface DownloadFileNameParameter {
  name: string;
}

const DOWNLOAD_FILE_MIME_MAPPINGS: DownloadFileMimeMapping[] = [
  { extension: '.apk', mimeType: APK_MIME_TYPE },
  { extension: '.hap', mimeType: 'application/octet-stream' },
  { extension: '.app', mimeType: 'application/octet-stream' },
  { extension: '.pdf', mimeType: 'application/pdf' },
  { extension: '.txt', mimeType: 'text/plain' },
  { extension: '.md', mimeType: 'text/markdown' },
  { extension: '.markdown', mimeType: 'text/markdown' },
  { extension: '.json', mimeType: 'application/json' },
  { extension: '.html', mimeType: 'text/html' },
  { extension: '.htm', mimeType: 'text/html' },
  { extension: '.jpg', mimeType: 'image/jpeg' },
  { extension: '.jpeg', mimeType: 'image/jpeg' },
  { extension: '.png', mimeType: 'image/png' },
  { extension: '.webp', mimeType: 'image/webp' },
  { extension: '.gif', mimeType: 'image/gif' },
  { extension: '.bmp', mimeType: 'image/bmp' },
  { extension: '.svg', mimeType: 'image/svg+xml' },
  { extension: '.mp4', mimeType: 'video/mp4' },
  { extension: '.m4v', mimeType: 'video/mp4' },
  { extension: '.webm', mimeType: 'video/webm' },
  { extension: '.mov', mimeType: 'video/quicktime' },
  { extension: '.mkv', mimeType: 'video/x-matroska' },
  { extension: '.mp3', mimeType: 'audio/mpeg' },
  { extension: '.m4a', mimeType: 'audio/mp4' },
  { extension: '.wav', mimeType: 'audio/wav' },
  { extension: '.flac', mimeType: 'audio/flac' },
  { extension: '.zip', mimeType: 'application/zip' },
  { extension: '.rar', mimeType: 'application/vnd.rar' },
  { extension: '.7z', mimeType: 'application/x-7z-compressed' },
  { extension: '.gz', mimeType: 'application/gzip' },
  { extension: '.tar', mimeType: 'application/x-tar' },
  { extension: '.doc', mimeType: 'application/msword' },
  { extension: '.docx', mimeType: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document' },
  { extension: '.xls', mimeType: 'application/vnd.ms-excel' },
  { extension: '.xlsx', mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' },
  { extension: '.ppt', mimeType: 'application/vnd.ms-powerpoint' },
  { extension: '.pptx', mimeType: 'application/vnd.openxmlformats-officedocument.presentationml.presentation' }
];

export class DownloadFollowupService {
  private fileResolutionService: DownloadFileResolutionAdapter;

  constructor(fileResolutionService: DownloadFileResolutionAdapter = new DownloadFileResolutionService()) {
    this.fileResolutionService = fileResolutionService;
  }

  async openFile(task: DownloadFollowupTask): Promise<DownloadFollowupExecutionResult> {
    const targetUri = this.resolveReadableFileUri(task);
    if (targetUri === undefined) {
      return {
        success: false,
        userMessage: '无法打开下载文件：文件不存在或尚未落地。'
      };
    }

    if (this.isApkFile(task, targetUri)) {
      if (await this.tryOpenWithExternalHandler(targetUri, task, true)) {
        return {
          success: true,
          finalFileUri: targetUri
        };
      }
      if (await this.tryOpenPreview(targetUri, task)) {
        return {
          success: true,
          finalFileUri: targetUri
        };
      }
      return {
        success: false,
        userMessage: `无法打开下载文件：${task.suggestedFileName}。`
      };
    }

    const previewCapability = await this.resolvePreviewCapability(targetUri);
    if (previewCapability !== false && await this.tryOpenPreview(targetUri, task)) {
      return {
        success: true,
        finalFileUri: targetUri
      };
    }
    if (await this.tryOpenWithExternalHandler(targetUri, task, false)) {
      return {
        success: true,
        finalFileUri: targetUri
      };
    }
    if (previewCapability === false && await this.tryOpenPreview(targetUri, task)) {
      return {
        success: true,
        finalFileUri: targetUri
      };
    }
    return {
      success: false,
      userMessage: `无法打开下载文件：${task.suggestedFileName}。`
    };
  }

  private async resolvePreviewCapability(targetUri: string): Promise<boolean | undefined> {
    try {
      return await filePreview.canPreview(this.getUIAbilityContext(), targetUri);
    } catch (_error) {
      return undefined;
    }
  }

  private async tryOpenPreview(targetUri: string, task: DownloadFollowupTask): Promise<boolean> {
    const previewInfo: filePreview.PreviewInfo = {
      title: task.suggestedFileName,
      uri: targetUri,
      mimeType: this.resolveOpenFileMimeType(task, targetUri)
    };
    try {
      await filePreview.openPreview(this.getUIAbilityContext(), previewInfo);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private async tryOpenWithExternalHandler(
    targetUri: string,
    task: DownloadFollowupTask,
    forcePicker: boolean
  ): Promise<boolean> {
    const want = this.buildOpenFileWant(targetUri, task, forcePicker);
    try {
      await this.getUIAbilityContext().startAbility(want);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private isApkFile(task: DownloadFollowupTask, targetUri: string): boolean {
    const extensionMimeType = this.resolveMimeTypeFromFileHints(task, targetUri);
    return extensionMimeType === APK_MIME_TYPE;
  }

  async openLocation(task: DownloadFollowupTask): Promise<DownloadFollowupExecutionResult> {
    const targetUri = this.resolveReadableFileUri(task);
    if (targetUri === undefined) {
      return {
        success: false,
        userMessage: '无法打开下载位置：文件不存在或尚未落地。'
      };
    }

    try {
      await this.shareFileUri(targetUri, task);
      return {
        success: true,
        finalFileUri: targetUri,
        userMessage: `已提供下载文件位置入口：${task.suggestedFileName}。`
      };
    } catch (_error) {
      return {
        success: false,
        userMessage: `无法打开下载位置：${task.suggestedFileName}。`
      };
    }
  }

  private async shareFileUri(uri: string, task: DownloadFollowupTask): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: this.resolveShareUtd(task, uri),
      uri: uri,
      title: task.suggestedFileName,
      label: task.suggestedFileName,
      description: uri
    };
    const data = new systemShare.SharedData(record);
    const controller = new systemShare.ShareController(data);
    await controller.show(this.getUIAbilityContext(), {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DEFAULT
    });
  }

  private resolveReadableFileUri(task: DownloadFollowupTask): string | undefined {
    const finalFileUri = task.finalFileUri?.trim() ?? '';
    if (finalFileUri.length > 0) {
      return finalFileUri;
    }
    const tempLocalPath = task.tempLocalPath?.trim() ?? '';
    if (tempLocalPath.length === 0) {
      return undefined;
    }
    return this.resolveUriFromLocalPath(tempLocalPath);
  }

  private resolveUriFromLocalPath(path: string): string | undefined {
    try {
      return this.fileResolutionService.resolveUriFromLocalPath(path);
    } catch (_error) {
      return undefined;
    }
  }

  private buildOpenFileWant(targetUri: string, task: DownloadFollowupTask, forcePicker: boolean): Want {
    const params: Record<string, Object> = {};
    params[wantConstant.Params.PARAMS_STREAM] = [targetUri];
    if (forcePicker) {
      params[WANT_PARAMETER_SHOW_DEFAULT_PICKER] = true;
      const fileNameParameter: DownloadFileNameParameter = {
        name: task.suggestedFileName
      };
      params[WANT_PARAMETER_FILE_NAME] = fileNameParameter;
      params[WANT_PARAMETER_DISPLAY_NAME] = task.suggestedFileName;
    }
    const mimeType = this.resolveOpenFileMimeType(task, targetUri);
    if (mimeType.length > 0) {
      return {
        action: WANT_ACTION_VIEW_DATA,
        uri: targetUri,
        type: mimeType,
        flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
        parameters: params
      };
    }
    return {
      action: WANT_ACTION_VIEW_DATA,
      uri: targetUri,
      flags: wantConstant.Flags.FLAG_AUTH_READ_URI_PERMISSION,
      parameters: params
    };
  }

  private resolveOpenFileMimeType(task: DownloadFollowupTask, targetUri: string): string {
    const normalizedMimeType = this.normalizeMimeType(task.mimeType);
    const extensionMimeType = this.resolveMimeTypeFromFileHints(task, targetUri);
    if (extensionMimeType === APK_MIME_TYPE) {
      return extensionMimeType;
    }
    if (this.isGenericMimeType(normalizedMimeType)) {
      return extensionMimeType;
    }
    return normalizedMimeType;
  }

  private resolveShareUtd(task: DownloadFollowupTask, targetUri: string): string {
    const mimeType = this.resolveOpenFileMimeType(task, targetUri);
    if (mimeType.length <= 0) {
      return uniformTypeDescriptor.UniformDataType.FILE_URI;
    }
    try {
      const utd = uniformTypeDescriptor.getUniformDataTypeByMIMEType(mimeType).trim();
      return utd.length > 0 ? utd : uniformTypeDescriptor.UniformDataType.FILE_URI;
    } catch (_error) {
      return uniformTypeDescriptor.UniformDataType.FILE_URI;
    }
  }

  private resolveMimeTypeFromFileHints(task: DownloadFollowupTask, targetUri: string): string {
    const values: string[] = [
      task.suggestedFileName,
      task.tempLocalPath ?? '',
      task.finalFileUri ?? '',
      targetUri
    ];
    for (let valueIndex = 0; valueIndex < values.length; valueIndex += 1) {
      const extension = this.resolveFileExtension(values[valueIndex]);
      if (extension.length <= 0) {
        continue;
      }
      const matched = this.resolveMimeTypeFromExtension(extension);
      if (matched.length > 0) {
        return matched;
      }
    }
    return '';
  }

  private resolveMimeTypeFromExtension(extension: string): string {
    for (let index = 0; index < DOWNLOAD_FILE_MIME_MAPPINGS.length; index += 1) {
      const mapping = DOWNLOAD_FILE_MIME_MAPPINGS[index];
      if (mapping.extension === extension) {
        return mapping.mimeType;
      }
    }
    return '';
  }

  private resolveFileExtension(value: string): string {
    const normalized = value.split('?')[0].split('#')[0].trim().toLowerCase();
    const slashIndex = normalized.lastIndexOf('/');
    const fileName = slashIndex >= 0 ? normalized.substring(slashIndex + 1) : normalized;
    const dotIndex = fileName.lastIndexOf('.');
    if (dotIndex <= 0 || dotIndex >= fileName.length - 1) {
      return '';
    }
    const extension = fileName.substring(dotIndex);
    return /^[.][a-z0-9]{1,8}$/.test(extension) ? extension : '';
  }

  private normalizeMimeType(mimeType: string | undefined): string {
    return mimeType?.split(';')[0].trim().toLowerCase() ?? '';
  }

  private isGenericMimeType(mimeType: string): boolean {
    return mimeType.length <= 0 ||
      mimeType === 'application/octet-stream' ||
      mimeType === 'binary/octet-stream' ||
      mimeType === 'application/x-download' ||
      mimeType === 'application/download' ||
      mimeType === 'application/force-download';
  }

  private getUIAbilityContext(): common.UIAbilityContext {
    return AppRuntimeContext.getUIAbilityContext();
  }
}
