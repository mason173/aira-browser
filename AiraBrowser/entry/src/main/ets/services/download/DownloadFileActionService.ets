import { fileIo, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { DownloadV2TaskEntity } from '../../domain/downloadv2/DownloadV2TaskEntity';
import { DownloadFileNameService } from './DownloadFileNameService';
import { DownloadLocationDirectoryService } from './DownloadLocationDirectoryService';
import { DownloadFileResolutionAdapter, DownloadFileResolutionService } from './DownloadFileResolutionService';

export type DownloadFileAvailability = 'available' | 'missing' | 'unavailable';
export type DownloadFileRenameFailure = 'missing' | 'unavailable' | 'unsupported' | 'invalid_name' | 'failed';

export interface DownloadFileRenamePlan {
  sourceLocation: string;
  targetLocation: string;
  strategy: 'sandbox_rename' | 'directory_copy' | 'unchanged';
  fileName: string;
  tempFilePath?: string;
  finalFileUri?: string;
  finalDisplayPath?: string;
  verifiedSize?: number;
}

export interface DownloadFileRenamePreparation {
  plan?: DownloadFileRenamePlan;
  failure?: DownloadFileRenameFailure;
}

/** File operations only. The runtime commits task metadata before a copied original is removed. */
export class DownloadFileActionService {
  private static reservedPaths: Set<string> = new Set<string>();
  private files: DownloadFileResolutionAdapter;
  private names: DownloadFileNameService = new DownloadFileNameService();

  constructor(files: DownloadFileResolutionAdapter = new DownloadFileResolutionService()) {
    this.files = files;
  }

  async inspectTask(task: DownloadV2TaskEntity): Promise<DownloadFileAvailability> {
    const destination = task.persistence.destination;
    const grantUri = destination?.uri?.trim() ?? '';
    if (grantUri.length > 0 && (destination?.kind === 'directory' || destination?.kind === 'file')) {
      // Restore only the grant actually selected/persisted by the file provider. Activation
      // does not create a new permission or authorize a path derived from a file URI.
      const directories = new DownloadLocationDirectoryService();
      if (destination.kind === 'directory') await directories.activateDirectory(grantUri);
      else await directories.activateReadableFile(grantUri);
    }
    return this.inspect(task.persistence.finalFileUri?.trim() || task.persistence.tempFilePath?.trim() || '');
  }

  async inspect(location: string): Promise<DownloadFileAvailability> {
    if (location.trim().length === 0) return 'missing';
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(location, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      return stat.isFile() && Number.isFinite(stat.size) && stat.size >= 0 ? 'available' : 'unavailable';
    } catch (error) {
      const code = (error as BusinessError).code;
      return code === 13900002 || code === 1014000002 ? 'missing' : 'unavailable';
    } finally {
      if (file !== undefined) {
        try { await fileIo.close(file); } catch (_error) {}
      }
    }
  }

  async prepareRename(task: DownloadV2TaskEntity, newBaseName: string): Promise<DownloadFileRenamePreparation> {
    const source = task.persistence.finalFileUri?.trim() || task.persistence.tempFilePath?.trim() || '';
    const availability = await this.inspectTask(task);
    if (availability !== 'available') return { failure: availability };
    const oldName = task.resolvedFileName?.trim() || task.suggestedFileName;
    const fileName = this.resolveRenamedFileName(oldName, newBaseName);
    if (fileName === undefined) return { failure: 'invalid_name' };
    if (fileName === oldName) {
      return { plan: {
        sourceLocation: source, targetLocation: source, strategy: 'unchanged', fileName: oldName,
        tempFilePath: task.persistence.tempFilePath, finalFileUri: task.persistence.finalFileUri,
        finalDisplayPath: task.persistence.finalDisplayPath
      } };
    }
    if (!task.persistence.finalFileUri && this.isOwnedSandboxPath(source)) {
      return this.prepareSandboxRename(task, source, fileName);
    }
    const destination = task.persistence.destination;
    if (destination?.kind !== 'directory' || !destination.uri || !task.persistence.finalFileUri) {
      return { failure: 'unsupported' };
    }
    try {
      // A single-file grant is never promoted to a parent grant. Even a saved directory grant
      // must describe this file's actual parent before a rename can create a sibling.
      const parent = new fileUri.FileUri(source).getFullDirectoryUri();
      if (this.normalizeDirectory(parent) !== this.normalizeDirectory(destination.uri) ||
        !await this.files.validateDestination(destination)) {
        return { failure: 'unsupported' };
      }
      const sourceInfo = await this.files.inspectReadableFile(source);
      if (sourceInfo === undefined) return { failure: 'unavailable' };
      const copied = await this.files.persistToDestination(source, fileName, destination);
      const target = copied?.finalFileUri?.trim() ?? '';
      if (copied?.isExported !== true || target.length === 0 || target === source) return { failure: 'failed' };
      const targetInfo = await this.files.inspectReadableFile(target);
      if (targetInfo === undefined || targetInfo.size !== sourceInfo.size) {
        try { await this.files.movePublicDocumentToTrash(target); } catch (_error) {}
        return { failure: 'failed' };
      }
      return { plan: {
        sourceLocation: source, targetLocation: target, strategy: 'directory_copy',
        fileName: copied.finalFileName?.trim() || fileName,
        finalFileUri: target, finalDisplayPath: copied.finalDisplayPath, verifiedSize: sourceInfo.size
      } };
    } catch (_error) {
      return { failure: 'failed' };
    }
  }

  async finishRename(plan: DownloadFileRenamePlan): Promise<boolean> {
    if (plan.strategy !== 'directory_copy') return true;
    try {
      await this.files.movePublicDocumentToTrash(plan.sourceLocation);
      return true;
    } catch (_error) {
      return false;
    }
  }

  async rollbackRename(plan: DownloadFileRenamePlan): Promise<boolean> {
    try {
      if (plan.strategy === 'directory_copy') {
        if (!await this.canRestoreOriginal(plan)) return false;
        await this.files.movePublicDocumentToTrash(plan.targetLocation);
      } else if (plan.strategy === 'sandbox_rename') {
        if (await fileIo.access(plan.sourceLocation)) return false;
        await fileIo.rename(plan.targetLocation, plan.sourceLocation);
      }
      return true;
    } catch (_error) {
      return false;
    }
  }

  async canRestoreOriginal(plan: DownloadFileRenamePlan): Promise<boolean> {
    if (plan.strategy !== 'directory_copy') return true;
    const original = await this.files.inspectReadableFile(plan.sourceLocation);
    return original !== undefined && original.size === plan.verifiedSize;
  }

  releaseRename(plan: DownloadFileRenamePlan): void {
    DownloadFileActionService.reservedPaths.delete(plan.targetLocation);
  }

  canRedownload(task: DownloadV2TaskEntity): boolean {
    if (task.status !== 'completed' || task.request.method.trim().toUpperCase() !== 'GET') return false;
    const url = task.request.originalUrl?.trim() || task.request.url.trim();
    if (!/^https?:\/\//i.test(url) || url.length > 8192 || /[\r\n]/.test(url)) return false;
    // A confirmed missing-file action is still not permission to silently spend an old signed
    // endpoint or replay session credentials. Such files must be requested from their page again.
    if (/[?&](?:[^=&#]*(?:token|signature|credential|authorization|expires|expiry|nonce|secret|auth|api[_-]?key|x-amz|x-goog)[^=&#]*|sig|key|se|sp|sv)=/i.test(url)) return false;
    const authority = url.substring(url.indexOf('://') + 3).split('/')[0];
    if (authority.includes('@')) return false;
    const headers = task.request.headers;
    if (headers !== undefined && Object.keys(headers).some((key: string): boolean =>
      /^(authorization|proxy-authorization|cookie)$/i.test(key))) return false;
    return true;
  }

  private async prepareSandboxRename(
    task: DownloadV2TaskEntity, source: string, requestedName: string
  ): Promise<DownloadFileRenamePreparation> {
    const directory = source.substring(0, source.lastIndexOf('/'));
    let target = '';
    let fileName = requestedName;
    try {
      for (let index = 0; index < 1000; index += 1) {
        fileName = index === 0 ? requestedName : this.names.buildConflictFileName(requestedName, index);
        const candidate = `${directory}/${fileName}`;
        if (DownloadFileActionService.reservedPaths.has(candidate)) continue;
        DownloadFileActionService.reservedPaths.add(candidate);
        target = candidate;
        if (await fileIo.access(candidate)) {
          DownloadFileActionService.reservedPaths.delete(candidate);
          target = '';
          continue;
        }
        break;
      }
      if (target.length === 0) return { failure: 'failed' };
      await fileIo.rename(source, target);
      const display = task.persistence.finalDisplayPath ?? '';
      const slash = display.lastIndexOf('/');
      return { plan: {
        sourceLocation: source, targetLocation: target, strategy: 'sandbox_rename', fileName: fileName,
        tempFilePath: target,
        finalDisplayPath: slash >= 0 ? `${display.substring(0, slash + 1)}${fileName}` : fileName
      } };
    } catch (_error) {
      DownloadFileActionService.reservedPaths.delete(target);
      return { failure: 'failed' };
    }
  }

  private resolveRenamedFileName(oldName: string, newBaseName: string): string | undefined {
    const base = newBaseName.trim();
    if (base.length === 0 || base === '.' || base === '..' || /[\\/\u0000-\u001f]/.test(base)) return undefined;
    const lower = oldName.toLowerCase();
    const compounds: string[] = ['.tar.gz', '.tar.bz2', '.tar.xz'];
    let suffix = '';
    for (let index = 0; index < compounds.length; index += 1) {
      if (lower.endsWith(compounds[index]) && oldName.length > compounds[index].length) {
        suffix = oldName.substring(oldName.length - compounds[index].length);
        break;
      }
    }
    if (suffix.length === 0) {
      const dot = oldName.lastIndexOf('.');
      if (dot > 0 && dot < oldName.length - 1) suffix = oldName.substring(dot);
    }
    return this.names.sanitizeFileName(`${base}${suffix}`);
  }

  private isOwnedSandboxPath(path: string): boolean {
    if (path.includes('://') || path.split('/').some((part: string): boolean => part === '..' || part === '.')) return false;
    try {
      const context = AppRuntimeContext.getApplicationContext();
      return path.startsWith(`${context.filesDir}/`) || path.startsWith(`${context.cacheDir}/`);
    } catch (_error) {
      return false;
    }
  }

  private normalizeDirectory(uri: string): string {
    return uri.replace(/\/+$/, '');
  }
}
