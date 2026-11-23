import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { DownloadLocationDirectoryService } from './DownloadLocationDirectoryService';
import { fileManagerService } from '@kit.FileManagerServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import { DownloadFileNameService } from './DownloadFileNameService';
import {
  DownloadFilenameConflictPlan,
  DownloadFilenameConflictService
} from './DownloadFilenameConflictService';

const DOWNLOAD_FILE_RESOLUTION_DOMAIN = 0x0000;
const DOWNLOAD_FILE_RESOLUTION_TAG = 'DownloadFileResolution';
const LOCAL_COPY_CHUNK_BYTES = 256 * 1024;
const USER_DOWNLOAD_DOCS_ROOT_URI = 'file://docs/storage/Users/currentUser/Download';
const USER_DOWNLOAD_DOCS_MARKER = '/storage/Users/currentUser/Download/';
const AIRA_DOWNLOAD_FOLDER_NAME = 'Aira';
const PUBLIC_DOWNLOAD_ROOT_LABEL = 'Download';

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
  destinationLabel?: string;
  isExported: boolean;
  /**
   * True when a configured custom download folder was skipped (probe or write
   * failed) and the file went to the system download location instead, so the
   * completion message should tell the user their folder choice needs a fix.
   */
  customDirectoryBypassed?: boolean;
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
  persistToDirectory(
    localPath: string,
    suggestedFileName: string,
    directoryUri: string,
    directoryLabel: string
  ): Promise<DownloadPersistResult | undefined>;
}

export class DownloadFileResolutionService implements DownloadFileResolutionAdapter {
  private static reservedExportUris: Set<string> = new Set<string>();
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
    if (normalizedPath.length <= 0) {
      return 'missing';
    }
    const existed = await this.pathExists(normalizedPath);
    if (existed) {
      await fileIo.unlink(normalizedPath);
    }
    // A restored task may no longer have a native handle to cancel. Remove its
    // entity validator even when the partial file has already been deleted.
    const metadataPaths = [`${normalizedPath}.aira-resume`, `${normalizedPath}.aira-resume.tmp`];
    for (const metadataPath of metadataPaths) {
      if (await this.pathExists(metadataPath)) {
        await fileIo.unlink(metadataPath);
      }
    }
    return existed ? 'deleted' : 'missing';
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

  async persistToDirectory(
    localPath: string,
    suggestedFileName: string,
    directoryUri: string,
    directoryLabel: string
  ): Promise<DownloadPersistResult | undefined> {
    const savedFileName = this.sanitizeFileName(suggestedFileName);
    const directoryService = new DownloadLocationDirectoryService();
    try {
      // Activation only refreshes a persisted grant. When it reports failure the
      // folder may still be writable through the live picker grant, so the write
      // below is what actually decides. Bailing out here is what silently threw
      // away the user's chosen folder and fell back to the system save dialog.
      const activation = await directoryService.activateDirectory(directoryUri);
      if (!activation.usable) {
        hilog.warn(
          DOWNLOAD_FILE_RESOLUTION_DOMAIN,
          DOWNLOAD_FILE_RESOLUTION_TAG,
          'directory activation unavailable, attempting write anyway uri=%{public}s detail=%{public}s',
          directoryUri,
          activation.diagnosticMessage
        );
      }
      // A dead grant (app update, reboot) can still let path-channel opens
      // "succeed" by creating 0-byte shells the file manager shows. Probing the
      // URI transports with real bytes decide before any download file name is
      // created. New-child open(URI, CREATE) can report ENOENT even though the
      // export's URI-copy transport works; the probe checks that path too.
      if (!await directoryService.verifyDirectoryWritable(directoryUri)) {
        hilog.warn(
          DOWNLOAD_FILE_RESOLUTION_DOMAIN,
          DOWNLOAD_FILE_RESOLUTION_TAG,
          'directory probe not writable, falling back to system downloads file=%{public}s uri=%{public}s',
          savedFileName,
          directoryUri
        );
        return {
          status: 'failed',
          finalDisplayPath: this.buildTemporaryDisplayPath(savedFileName),
          isExported: false
        };
      }
      const exportResolution = this.buildExportResolution(savedFileName, directoryUri);
      const targetUri = await this.copyLocalPathWithoutOverwrite(
        localPath,
        exportResolution.targetUri,
        exportResolution.conflictResolvedUri
      );
      const label = directoryLabel.trim().length > 0
        ? directoryLabel.trim()
        : directoryService.buildDirectoryLocationLabel(directoryUri);
      return {
        status: 'exported',
        finalFileUri: targetUri,
        finalDisplayPath: `${label}/${savedFileName}`,
        destinationLabel: label,
        isExported: true
      };
    } catch (error) {
      const diagnosticMessage = this.stringifyError(error);
      hilog.error(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'persist directory failed file=%{public}s uri=%{public}s error=%{public}s',
        savedFileName,
        directoryUri,
        diagnosticMessage
      );
      return {
        status: 'failed',
        finalDisplayPath: this.buildTemporaryDisplayPath(savedFileName),
        isExported: false
      };
    }
  }

  async persistToSystemDownloads(localPath: string, suggestedFileName: string): Promise<DownloadPersistResult | undefined> {
    const directResult = await this.persistToAiraDownloadFolder(localPath, suggestedFileName);
    if (directResult !== undefined) {
      return directResult;
    }
    return this.persistViaSystemDownloadPicker(localPath, suggestedFileName);
  }

  /**
   * Tries to write straight into the user-visible `Download/Aira` folder.
   *
   * The system download picker (DOWNLOAD mode) names its own subfolder
   * `Download/<bundleName>` and some device file managers do not surface that
   * folder, while the in-app copy has always promised `Download/Aira`. Public
   * user directories are grant-scoped, so this is best-effort: when the folder
   * cannot be created or written the caller falls back to the system picker.
   */
  private async persistToAiraDownloadFolder(localPath: string, suggestedFileName: string): Promise<DownloadPersistResult | undefined> {
    const savedFileName = this.sanitizeFileName(suggestedFileName);
    const folderUri = `${USER_DOWNLOAD_DOCS_ROOT_URI}/${AIRA_DOWNLOAD_FOLDER_NAME}`;
    const folderPath = this.resolvePathFromUri(folderUri);
    try {
      if (!await this.pathExists(folderPath)) {
        await fileIo.mkdir(folderPath, true);
      }
      hilog.info(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'direct folder ready path=%{public}s file=%{public}s',
        folderPath,
        savedFileName
      );
      const exportResolution = this.buildExportResolution(savedFileName, folderUri);
      const targetUri = await this.copyLocalPathWithoutOverwrite(
        localPath,
        exportResolution.targetUri,
        exportResolution.conflictResolvedUri
      );
      const folderLabel = this.buildPublicDownloadFolderLabel(targetUri);
      return {
        status: 'exported',
        finalFileUri: targetUri,
        finalDisplayPath: `${folderLabel}/${savedFileName}`,
        destinationLabel: folderLabel,
        isExported: true
      };
    } catch (error) {
      hilog.warn(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'direct folder unavailable, falling back to system download picker file=%{public}s path=%{public}s error=%{public}s',
        savedFileName,
        folderPath,
        this.stringifyError(error)
      );
      await this.removeFolderIfEmpty(folderPath);
      return undefined;
    }
  }

  private async removeFolderIfEmpty(folderPath: string): Promise<void> {
    try {
      await fileIo.rmdir(folderPath);
      hilog.info(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'direct folder removed empty path=%{public}s',
        folderPath
      );
    } catch (_error) {
    }
  }

  private buildPublicDownloadFolderLabel(fileUri: string): string {
    const baseUri = this.resolveBaseUriFromUri(fileUri);
    const markerIndex = baseUri.indexOf(USER_DOWNLOAD_DOCS_MARKER);
    if (markerIndex < 0) {
      return resolveAppResourceText($r('app.string.download_system_downloads'));
    }
    const folderTail = baseUri.substring(markerIndex + USER_DOWNLOAD_DOCS_MARKER.length);
    if (folderTail.length <= 0) {
      return PUBLIC_DOWNLOAD_ROOT_LABEL;
    }
    try {
      return `${PUBLIC_DOWNLOAD_ROOT_LABEL}/${decodeURIComponent(folderTail)}`;
    } catch (_error) {
      return `${PUBLIC_DOWNLOAD_ROOT_LABEL}/${folderTail}`;
    }
  }

  private async persistViaSystemDownloadPicker(localPath: string, suggestedFileName: string): Promise<DownloadPersistResult | undefined> {
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
      const folderLabel = this.buildPublicDownloadFolderLabel(targetUri);
      return {
        status: 'exported',
        finalFileUri: targetUri,
        finalDisplayPath: `${folderLabel}/${savedFileName}`,
        destinationLabel: folderLabel,
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
    return resolveAppResourceText($r('app.string.download_temp_dir')) + '/' + this.sanitizeFileName(fileName);
  }

  private getDownloadsTempDir(): string {
    try {
      return `${AppRuntimeContext.getApplicationContext().filesDir}/downloads/incomplete`;
    } catch (_error) {
      return '';
    }
  }

  private buildTemporaryFileName(suggestedFileName: string, now: number): string {
    const extension = this.sanitizeFileName(suggestedFileName).match(/\.[a-zA-Z0-9]{1,12}$/)?.[0] ?? '.part';
    return `${now}-${util.generateRandomUUID()}${extension}`;
  }

  private normalizeTargetBaseUri(targetBaseUri: string): string {
    return targetBaseUri.endsWith('/') ? targetBaseUri.slice(0, -1) : targetBaseUri;
  }

  private appendFileNameToUri(baseUri: string, fileName: string): string {
    return `${baseUri}/${encodeURIComponent(fileName)}`;
  }

  private async uriExists(uri: string): Promise<boolean> {
    try {
      // Same reason as verifyDirectoryWritable: convert the URI to a path before
      // handing it to fileIo, rather than passing an app-concatenated URI.
      return await fileIo.access(new fileUri.FileUri(uri).path);
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
      if (this.isPermissionError(error)) {
        // Retrying under a conflict name cannot fix a folder-level permission
        // failure; it would only leave a second 0-byte shell behind.
        throw error instanceof Error ? error : new Error(this.stringifyError(error));
      }
      const fallbackStartIndex = resolvedTarget.targetUri === targetUri ? 1 : 2;
      const fallbackTarget = await this.resolveAvailableConflictTarget(targetUri, fallbackStartIndex);
      try {
        await this.copyLocalPathToUri(sourcePath, fallbackTarget.targetUri, sourceSize, 'fallback');
        return fallbackTarget.targetUri;
      } finally {
        DownloadFileResolutionService.reservedExportUris.delete(fallbackTarget.targetUri);
      }
    } finally {
      DownloadFileResolutionService.reservedExportUris.delete(resolvedTarget.targetUri);
    }
  }

  private async reserveCopyTarget(uri: string, label: string): Promise<DownloadCopyTargetResolution | undefined> {
    if (DownloadFileResolutionService.reservedExportUris.has(uri) || await this.uriExists(uri)) return undefined;
    // Recheck after the asynchronous provider query. All app instances share the
    // reservation so two completed downloads cannot both select an absent name.
    if (DownloadFileResolutionService.reservedExportUris.has(uri)) return undefined;
    DownloadFileResolutionService.reservedExportUris.add(uri);
    return { targetUri: uri, label: label };
  }

  private async resolveAvailableCopyTarget(
    targetUri: string,
    conflictResolvedUri: string
  ): Promise<DownloadCopyTargetResolution> {
    const original = await this.reserveCopyTarget(targetUri, 'target');
    if (original !== undefined) return original;
    const conflict = await this.reserveCopyTarget(conflictResolvedUri, 'conflict');
    if (conflict !== undefined) return conflict;
    return this.resolveAvailableConflictTarget(targetUri, 2);
  }

  private async resolveAvailableConflictTarget(
    targetUri: string,
    startIndex: number
  ): Promise<DownloadCopyTargetResolution> {
    const normalizedStartIndex = Math.max(1, Math.floor(startIndex));
    for (let index = normalizedStartIndex; index <= 999; index += 1) {
      const candidateUri = this.buildConflictCandidateUri(targetUri, index);
      const candidate = await this.reserveCopyTarget(candidateUri, 'conflict');
      if (candidate !== undefined) return candidate;
    }
    const timestampPlan: DownloadFilenameConflictPlan = this.filenameConflictService.buildUniquifyPlan(
      `${util.generateRandomUUID()}-${this.resolveFileNameFromUri(targetUri)}`,
      1
    );
    const uniqueUri = this.appendFileNameToUri(this.resolveBaseUriFromUri(targetUri), timestampPlan.fileName);
    const unique = await this.reserveCopyTarget(uniqueUri, 'conflict');
    if (unique === undefined) throw new Error('copy_destination_unavailable');
    return unique;
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

  /**
   * Copy into a picker folder through the file URI, not a path-to-path copy.
   *
   * `copyFile(sandboxPath, FileUri.path)` can create the name the file manager
   * shows and leave that entry at 0 bytes, while a stat of the converted path
   * still reports the full size. Treating that as success then deletes the
   * temp file, so the only copy the user can find is empty. A URI copy, or a
   * descriptor copy opened from the URI, is what the file manager actually
   * indexes. A failed attempt must not be accepted just because the source
   * size could not be read.
   */
  private async copyLocalPathToUri(sourcePath: string, targetUri: string, sourceSize: number, label: string): Promise<void> {
    if (sourceSize < 0) {
      throw new Error('copy_source_unreadable');
    }
    hilog.info(
      DOWNLOAD_FILE_RESOLUTION_DOMAIN,
      DOWNLOAD_FILE_RESOLUTION_TAG,
      'copy attempt label=%{public}s sourceSize=%{public}d targetUri=%{public}s',
      label,
      sourceSize,
      targetUri
    );
    const sourceUri = this.resolveUriFromLocalPath(sourcePath);
    try {
      await fileIo.copy(sourceUri, targetUri);
      await this.assertExportedSize(targetUri, sourceSize, label, 'uri_copy');
      return;
    } catch (error) {
      hilog.error(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'copy uri failed label=%{public}s error=%{public}s',
        label,
        this.stringifyError(error)
      );
      await this.deleteZeroByteExport(targetUri);
    }
    try {
      await this.copyByFileDescriptor(sourcePath, targetUri, sourceSize, label);
    } catch (error) {
      await this.deleteZeroByteExport(targetUri);
      throw error instanceof Error ? error : new Error(this.stringifyError(error));
    }
  }

  private async copyByFileDescriptor(
    sourcePath: string,
    targetUri: string,
    sourceSize: number,
    label: string
  ): Promise<void> {
    const input = await fileIo.open(sourcePath, fileIo.OpenMode.READ_ONLY);
    let output: fileIo.File | undefined = undefined;
    try {
      output = await this.openExportDestination(targetUri);
      try {
        await fileIo.copyFile(input.fd, output.fd);
      } catch (copyError) {
        hilog.error(
          DOWNLOAD_FILE_RESOLUTION_DOMAIN,
          DOWNLOAD_FILE_RESOLUTION_TAG,
          'copy fd copyFile failed label=%{public}s error=%{public}s',
          label,
          this.stringifyError(copyError)
        );
        const failedOutput = output;
        output = undefined;
        if (failedOutput !== undefined) {
          try {
            await fileIo.close(failedOutput);
          } catch (_closeError) {
          }
        }
        output = await this.openExportDestination(targetUri);
        await this.rewriteFileDescriptors(input.fd, output.fd);
      }
      try {
        await fileIo.fsync(output.fd);
      } catch (syncError) {
        hilog.warn(
          DOWNLOAD_FILE_RESOLUTION_DOMAIN,
          DOWNLOAD_FILE_RESOLUTION_TAG,
          'copy fsync failed label=%{public}s error=%{public}s',
          label,
          this.stringifyError(syncError)
        );
      }
    } finally {
      await fileIo.close(input);
      if (output !== undefined) {
        await fileIo.close(output);
      }
    }
    await this.assertExportedSize(targetUri, sourceSize, label, 'fd_copy');
  }

  private async openExportDestination(targetUri: string): Promise<fileIo.File> {
    const mode = fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC;
    try {
      return await fileIo.open(targetUri, mode);
    } catch (error) {
      if (this.isPermissionError(error)) {
        // A path-channel open after a permission failure does not write bytes;
        // it only creates the 0-byte shell the file manager shows, so refuse it.
        hilog.warn(
          DOWNLOAD_FILE_RESOLUTION_DOMAIN,
          DOWNLOAD_FILE_RESOLUTION_TAG,
          'open export uri permission-denied, refusing path fallback targetUri=%{public}s error=%{public}s',
          targetUri,
          this.stringifyError(error)
        );
        throw error instanceof Error ? error : new Error(this.stringifyError(error));
      }
      hilog.warn(
        DOWNLOAD_FILE_RESOLUTION_DOMAIN,
        DOWNLOAD_FILE_RESOLUTION_TAG,
        'open export uri failed, falling back to path error=%{public}s',
        this.stringifyError(error)
      );
      return await fileIo.open(this.resolvePathFromUri(targetUri), mode);
    }
  }

  private isPermissionError(error: Object | Error | undefined | null): boolean {
    if (error === undefined || error === null) {
      return false;
    }
    const businessError = error as BusinessError;
    return businessError.code === 13900001 || businessError.code === 13900012;
  }

  private async rewriteFileDescriptors(inputFd: number, outputFd: number): Promise<void> {
    let inputOffset = 0;
    while (true) {
      const chunk = new ArrayBuffer(LOCAL_COPY_CHUNK_BYTES);
      const bytesRead = await fileIo.read(inputFd, chunk, {
        offset: inputOffset,
        length: LOCAL_COPY_CHUNK_BYTES
      });
      if (bytesRead <= 0) {
        return;
      }
      const payload = bytesRead === chunk.byteLength ? chunk : chunk.slice(0, bytesRead);
      // read() offset is the file position. write() does not take that same
      // number: the official copy sample only passes the buffer length and lets
      // the destination descriptor advance. Passing the file position here drops
      // everything after the first chunk.
      let written = 0;
      while (written < payload.byteLength) {
        const remaining = written === 0 ? payload : payload.slice(written);
        const bytesWritten = await fileIo.write(outputFd, remaining, { length: remaining.byteLength });
        if (bytesWritten <= 0 || bytesWritten > remaining.byteLength) throw new Error('copy_write_stalled');
        written += bytesWritten;
      }
      inputOffset += bytesRead;
    }
  }

  private async assertExportedSize(
    targetUri: string,
    sourceSize: number,
    label: string,
    stage: string
  ): Promise<void> {
    const exportedSize = await this.readCommittedExportSize(targetUri);
    hilog.info(
      DOWNLOAD_FILE_RESOLUTION_DOMAIN,
      DOWNLOAD_FILE_RESOLUTION_TAG,
      'copy size label=%{public}s stage=%{public}s sourceSize=%{public}d targetSize=%{public}d',
      label,
      stage,
      sourceSize,
      exportedSize
    );
    if (exportedSize !== sourceSize) {
      throw new Error(`copy_size_mismatch source=${sourceSize} target=${exportedSize}`);
    }
  }

  /**
   * A picker folder can report two sizes for one name: the URI the file
   * manager indexes, and the converted path. If they disagree, the smaller one
   * is what the user can actually open, so a full path stat must not hide an
   * empty file-manager entry.
   */
  private async readCommittedExportSize(targetUri: string): Promise<number> {
    const uriSize = await this.getFileSize(targetUri);
    let pathSize = -1;
    try {
      pathSize = await this.getFileSize(this.resolvePathFromUri(targetUri));
    } catch (_error) {
      pathSize = -1;
    }
    if (uriSize >= 0 && pathSize >= 0 && uriSize !== pathSize) {
      return Math.min(uriSize, pathSize);
    }
    return uriSize >= 0 ? uriSize : pathSize;
  }

  private async deleteZeroByteExport(targetUri: string): Promise<void> {
    const visibleSize = await this.readCommittedExportSize(targetUri);
    if (visibleSize > 0) {
      return;
    }
    // visibleSize <= 0 covers both a confirmed 0-byte shell and an entry whose
    // size cannot be read through either channel — the typical state of a
    // permission-broken shell. Unlink either way; a missing entry simply fails.
    try {
      await fileIo.unlink(targetUri);
      return;
    } catch (_error) {
    }
    try {
      await fileIo.unlink(this.resolvePathFromUri(targetUri));
    } catch (_error) {
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
