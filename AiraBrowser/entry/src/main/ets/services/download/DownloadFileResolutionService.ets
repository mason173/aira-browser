import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { DownloadFileNameService } from './DownloadFileNameService';
import {
  DownloadFilenameConflictPlan,
  DownloadFilenameConflictService
} from './DownloadFilenameConflictService';

const DOWNLOAD_FILE_RESOLUTION_DOMAIN = 0x0000;
const DOWNLOAD_FILE_RESOLUTION_TAG = 'DownloadFileResolution';
const LOCAL_COPY_CHUNK_BYTES = 256 * 1024;

export type DownloadLocalDeleteResult =
  'deleted' |
  'missing';

export interface DownloadTemporaryTargetPlan {
  baseDir: string;
  targetPath: string;
  fileName: string;
}

export interface DownloadExportResolution {
  fileName: string;
  displayName: string;
  targetUri: string;
  conflictResolvedUri: string;
  conflictFileName: string;
  conflictAction: string;
}

interface DownloadCopyTargetResolution {
  targetUri: string;
  label: string;
}

export interface DownloadPersistResult {
  status: 'exported' | 'user_canceled' | 'failed';
  finalFileUri?: string;
  finalDisplayPath: string;
  isExported: boolean;
}

export interface DownloadFileResolutionAdapter {
  resolveTemporaryTarget(
    suggestedFileName: string,
    now?: number
  ): Promise<DownloadTemporaryTargetPlan | undefined>;
  sanitizeFileName(fileName: string): string;
  resolveUriFromLocalPath(path: string): string;
  deleteLocalPath(path: string): Promise<DownloadLocalDeleteResult>;
  movePublicDocumentToTrash(uri: string): Promise<DownloadLocalDeleteResult>;
  persistToSystemDownloads(
    localPath: string,
    suggestedFileName: string
  ): Promise<DownloadPersistResult | undefined>;
}

export class DownloadFileResolutionService implements DownloadFileResolutionAdapter {
  private fileNameService: DownloadFileNameService = new DownloadFileNameService();
  private filenameConflictService: DownloadFilenameConflictService = new DownloadFilenameConflictService();

  async resolveTemporaryTarget(suggestedFileName: string, now: number = Date.now()): Promise<DownloadTemporaryTargetPlan | undefined> {
    const baseDir = this.getDownloadsTempDir();
    if (baseDir.length === 0) {
      return undefined;
    }
    try {
      if (!await fileIo.access(baseDir)) {
        await fileIo.mkdir(baseDir, true);
      }
    } catch (_error) {
      try {
        await fileIo.mkdir(baseDir, true);
      } catch (_innerError) {
        return undefined;
      }
    }
    const fileName = this.buildTemporaryFileName(suggestedFileName, now);
    return {
      baseDir: baseDir,
      targetPath: `${baseDir}/${fileName}`,
      fileName: fileName
    };
  }

  buildExportResolution(
    suggestedFileName: string,
    targetBaseUri: string,
    now: number = Date.now()
  ): DownloadExportResolution {
    const fileName = this.sanitizeFileName(suggestedFileName);
    const normalizedTargetBaseUri = this.normalizeTargetBaseUri(targetBaseUri);
    const conflictPlan = this.filenameConflictService.buildUniquifyPlan(fileName);
    return {
      fileName: fileName,
      displayName: fileName,
      targetUri: this.appendFileNameToUri(normalizedTargetBaseUri, fileName),
      conflictResolvedUri: this.appendFileNameToUri(normalizedTargetBaseUri, conflictPlan.fileName),
      conflictFileName: conflictPlan.fileName,
      conflictAction: conflictPlan.conflictAction
    };
  }

  resolveUriFromLocalPath(path: string): string {
    return fileUri.getUriFromPath(path);
  }

  async deleteLocalPath(path: string): Promise<DownloadLocalDeleteResult> {
    const normalizedPath = path.trim();
    if (normalizedPath.length <= 0 || !await this.pathExists(normalizedPath)) {
      return 'missing';
    }
    await fileIo.unlink(normalizedPath);
    return 'deleted';
  }

  async movePublicDocumentToTrash(uri: string): Promise<DownloadLocalDeleteResult> {
    const normalizedUri = uri.trim();
    if (normalizedUri.length <= 0) {
      return 'missing';
    }
    try {
      const trashUri = await fileManagerService.deleteToTrash(normalizedUri);
      hilog.info(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'move public document to trash uri=%{public}s trashUri=%{public}s',
        normalizedUri,
        trashUri
      );
      return 'deleted';
    } catch (error) {
      const businessError = error as BusinessError;
      if (businessError.code === 1014000002) {
        hilog.info(
          DOWNLOAD_FILE_RESOLUTION_DOMAIN,
          DOWNLOAD_FILE_RESOLUTION_TAG,
          'public document already missing uri=%{public}s',
          normalizedUri
        );
        return 'missing';
      }
      hilog.warn(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'move public document to trash failed uri=%{public}s code=%{public}d error=%{public}s',
        normalizedUri,
        businessError.code ?? 0,
        businessError.message ?? this.stringifyError(error)
      );
      const failureMessage: string =
        `delete_to_trash_failed code=${businessError.code ?? 0} message=${businessError.message ?? ''}`;
      throw new Error(failureMessage);
    }
  }

  async persistToSystemDownloads(localPath: string, suggestedFileName: string): Promise<DownloadPersistResult | undefined> {
    try {
      const savedFileName = this.sanitizeFileName(suggestedFileName);
      const sourceSize = await this.getFileSize(localPath);
      hilog.info(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'persist begin file=%{public}s sourceSize=%{public}d',
        savedFileName,
        sourceSize
      );
      const documentPicker = new picker.DocumentViewPicker();
      const saveOptions = new picker.DocumentSaveOptions();
      saveOptions.pickerMode = picker.DocumentPickerMode.DOWNLOAD;
      saveOptions.newFileNames = [savedFileName];
      const result = await documentPicker.save(saveOptions);
      if (result.length <= 0 || result[0].length <= 0) {
        hilog.info(DOWNLOAD_FILE_RESOLUTION_DOMAIN, DOWNLOAD_FILE_RESOLUTION_TAG, 'persist canceled file=%{public}s', savedFileName);
        return {
          status: 'user_canceled',
          finalDisplayPath: this.buildTemporaryDisplayPath(savedFileName),
          isExported: false
        };
      }
      hilog.info(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'persist picker file=%{public}s baseUri=%{public}s',
        savedFileName,
        result[0]
      );
      const exportResolution = this.buildExportResolution(savedFileName, result[0]);
      const targetUri = await this.copyLocalPathWithoutOverwrite(
        localPath,
        exportResolution.targetUri,
        exportResolution.conflictResolvedUri
      );
      return {
        status: 'exported',
        finalFileUri: targetUri,
        finalDisplayPath: targetUri,
        isExported: true
      };
    } catch (error) {
      hilog.error(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'persist failed file=%{public}s error=%{public}s',
        suggestedFileName,
        this.stringifyError(error)
      );
      return {
        status: 'failed',
        finalDisplayPath: this.buildTemporaryDisplayPath(suggestedFileName),
        isExported: false
      };
    }
  }

  sanitizeFileName(fileName: string): string {
    return this.fileNameService.sanitizeFileName(fileName);
  }

  buildTemporaryDisplayPath(fileName: string): string {
    return `Aira 临时下载目录/${this.sanitizeFileName(fileName)}`;
  }

  private getDownloadsTempDir(): string {
    try {
      return `${AppRuntimeContext.getApplicationContext().filesDir}/downloads/incomplete`;
    } catch (_error) {
      return '';
    }
  }

  private buildTemporaryFileName(suggestedFileName: string, now: number): string {
    return `${now}-${this.sanitizeFileName(suggestedFileName)}`;
  }

  private normalizeTargetBaseUri(targetBaseUri: string): string {
    return targetBaseUri.endsWith('/') ? targetBaseUri.slice(0, -1) : targetBaseUri;
  }

  private appendFileNameToUri(baseUri: string, fileName: string): string {
    return `${baseUri}/${encodeURIComponent(fileName)}`;
  }

  private async uriExists(uri: string): Promise<boolean> {
    try {
      return await fileIo.access(uri);
    } catch (_error) {
      return false;
    }
  }

  async copyLocalPathWithoutOverwrite(
    sourcePath: string,
    targetUri: string,
    conflictResolvedUri: string
  ): Promise<string> {
    const sourceSize = await this.getFileSize(sourcePath);
    hilog.info(
      DOWNLOAD_FILE_RESOLUTION_DOMAIN,
      DOWNLOAD_FILE_RESOLUTION_TAG,
      'copy begin sourceSize=%{public}d targetUri=%{public}s conflictUri=%{public}s',
      sourceSize,
      targetUri,
      conflictResolvedUri
    );
    const resolvedTarget = await this.resolveAvailableCopyTarget(targetUri, conflictResolvedUri);
    try {
      await this.copyLocalPathToUri(sourcePath, resolvedTarget.targetUri, sourceSize, resolvedTarget.label);
      return resolvedTarget.targetUri;
    } catch (error) {
      hilog.error(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'copy target failed error=%{public}s',
        this.stringifyError(error)
      );
      const fallbackStartIndex = resolvedTarget.targetUri === targetUri ? 1 : 2;
      const fallbackTarget = await this.resolveAvailableConflictTarget(targetUri, fallbackStartIndex);
      await this.copyLocalPathToUri(sourcePath, fallbackTarget.targetUri, sourceSize, 'fallback');
      return fallbackTarget.targetUri;
    }
  }

  private async resolveAvailableCopyTarget(
    targetUri: string,
    conflictResolvedUri: string
  ): Promise<DownloadCopyTargetResolution> {
    if (!await this.uriExists(targetUri)) {
      return {
        targetUri: targetUri,
        label: 'target'
      };
    }
    if (!await this.uriExists(conflictResolvedUri)) {
      return {
        targetUri: conflictResolvedUri,
        label: 'conflict'
      };
    }
    return this.resolveAvailableConflictTarget(targetUri, 2);
  }

  private async resolveAvailableConflictTarget(
    targetUri: string,
    startIndex: number
  ): Promise<DownloadCopyTargetResolution> {
    const normalizedStartIndex = Math.max(1, Math.floor(startIndex));
    for (let index = normalizedStartIndex; index <= 999; index += 1) {
      const candidateUri = this.buildConflictCandidateUri(targetUri, index);
      if (!await this.uriExists(candidateUri)) {
        return {
          targetUri: candidateUri,
          label: 'conflict'
        };
      }
    }
    const timestampPlan: DownloadFilenameConflictPlan = this.filenameConflictService.buildUniquifyPlan(
      `${Date.now()}-${this.resolveFileNameFromUri(targetUri)}`,
      1
    );
    return {
      targetUri: this.appendFileNameToUri(this.resolveBaseUriFromUri(targetUri), timestampPlan.fileName),
      label: 'conflict'
    };
  }

  private buildConflictCandidateUri(targetUri: string, conflictIndex: number): string {
    const fileName = this.resolveFileNameFromUri(targetUri);
    const conflictFileName = this.filenameConflictService.buildUniquifiedFileName(fileName, conflictIndex);
    return this.appendFileNameToUri(this.resolveBaseUriFromUri(targetUri), conflictFileName);
  }

  private resolveBaseUriFromUri(uri: string): string {
    const slashIndex = uri.lastIndexOf('/');
    return slashIndex >= 0 ? uri.substring(0, slashIndex) : '';
  }

  private resolveFileNameFromUri(uri: string): string {
    const slashIndex = uri.lastIndexOf('/');
    const encodedName = slashIndex >= 0 ? uri.substring(slashIndex + 1) : uri;
    try {
      const decodedName = decodeURIComponent(encodedName);
      return decodedName.trim().length > 0 ? decodedName : 'download.bin';
    } catch (_error) {
      return encodedName.trim().length > 0 ? encodedName : 'download.bin';
    }
  }

  private resolvePathFromUri(uri: string): string {
    return new fileUri.FileUri(uri).path;
  }

  private async copyLocalPathToUri(sourcePath: string, targetUri: string, sourceSize: number, label: string): Promise<void> {
    const targetPath = this.resolvePathFromUri(targetUri);
    hilog.info(
      DOWNLOAD_FILE_RESOLUTION_DOMAIN,
      DOWNLOAD_FILE_RESOLUTION_TAG,
      'copy attempt label=%{public}s targetPath=%{public}s',
      label,
      targetPath
    );
    try {
      await fileIo.copyFile(sourcePath, targetPath);
      const copiedSize = await this.getFileSize(targetPath);
      hilog.info(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'copy copyFile label=%{public}s sourceSize=%{public}d targetSize=%{public}d',
        label,
        sourceSize,
        copiedSize
      );
      if (sourceSize <= 0 || copiedSize === sourceSize) {
        return;
      }
      hilog.warn(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'copy copyFile size_mismatch label=%{public}s sourceSize=%{public}d targetSize=%{public}d',
        label,
        sourceSize,
        copiedSize
      );
    } catch (error) {
      hilog.error(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'copy copyFile failed label=%{public}s error=%{public}s',
        label,
        this.stringifyError(error)
      );
    }
    await this.rewriteLocalPathToPath(sourcePath, targetPath);
    const rewrittenSize = await this.getFileSize(targetPath);
    hilog.info(
      DOWNLOAD_FILE_RESOLUTION_DOMAIN,
      DOWNLOAD_FILE_RESOLUTION_TAG,
      'copy rewrite label=%{public}s sourceSize=%{public}d targetSize=%{public}d',
      label,
      sourceSize,
      rewrittenSize
    );
    if (sourceSize > 0 && rewrittenSize !== sourceSize) {
      throw new Error(`copy_size_mismatch source=${sourceSize} target=${rewrittenSize}`);
    }
  }

  private async rewriteLocalPathToPath(sourcePath: string, targetPath: string): Promise<void> {
    const input = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
    const output = await fileIo.open(targetPath, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      let inputOffset = 0;
      let outputOffset = 0;
      while (true) {
        const chunk = new ArrayBuffer(LOCAL_COPY_CHUNK_BYTES);
        const bytesRead = await fileIo.read(input.fd, chunk, {
          offset: inputOffset,
          length: LOCAL_COPY_CHUNK_BYTES
        });
        if (bytesRead <= 0) {
          return;
        }
        const payload = bytesRead === chunk.byteLength ? chunk : chunk.slice(0, bytesRead);
        const bytesWritten = await fileIo.write(output.fd, payload, {
          offset: outputOffset,
          length: payload.byteLength
        });
        inputOffset += bytesRead;
        outputOffset += bytesWritten;
      }
    } finally {
      await fileIo.close(input);
      await fileIo.close(output);
    }
  }

  private async getFileSize(path: string): Promise<number> {
    const normalizedPath = path.trim();
    if (normalizedPath.length <= 0) {
      return -1;
    }
    try {
      const stat = await fileIo.stat(normalizedPath);
      return Math.max(0, Math.floor(stat.size));
    } catch (_error) {
      return -1;
    }
  }

  private async pathExists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }

  private stringifyError(error: Object | Error | undefined | null): string {
    if (error === undefined || error === null) {
      return 'unknown';
    }
    const record = error as Record<string, Object | string | number | boolean | undefined>;
    const code = record['code'];
    const message = record['message'];
    if (code !== undefined && code !== null && message !== undefined && message !== null) {
      return 'code=' + String(code) + ' message=' + String(message);
    }
    if (code !== undefined && code !== null) {
      return 'code=' + String(code);
    }
    if (message !== undefined && message !== null) {
      return 'message=' + String(message);
    }
    try {
      return JSON.stringify(error);
    } catch (_jsonError) {
      return String(error);
    }
  }
}
