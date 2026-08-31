import { fileIo, fileUri } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  OfflinePageDraftCommitResult,
  OfflinePageWriteBytesCommand,
  OfflinePageWriteTextCommand
} from '../../common/models/OfflinePageModels';

const OFFLINE_PAGE_ROOT_DIR_NAME: string = 'offline-pages';
const OFFLINE_PAGE_TMP_DIR_NAME: string = 'tmp';
const OFFLINE_PAGE_PAGES_DIR_NAME: string = 'pages';
const OFFLINE_PAGE_MANIFEST_FILE_NAME: string = 'manifest.json';
const OFFLINE_PAGE_SNAPSHOT_FILE_NAME: string = 'snapshot.html';

export class OfflinePageFileStore {
  private textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');

  getRootDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${OFFLINE_PAGE_ROOT_DIR_NAME}`;
  }

  getPagesDir(): string {
    return `${this.getRootDir()}/${OFFLINE_PAGE_PAGES_DIR_NAME}`;
  }

  getPageDir(pageId: string): string {
    return `${this.getPagesDir()}/${this.sanitizePathSegment(pageId)}`;
  }

  getDraftDir(saveJobId: string): string {
    return `${this.getRootDir()}/${OFFLINE_PAGE_TMP_DIR_NAME}/${this.sanitizePathSegment(saveJobId)}`;
  }

  getManifestPath(pageId: string): string {
    return `${this.getPageDir(pageId)}/${OFFLINE_PAGE_MANIFEST_FILE_NAME}`;
  }

  getSnapshotPath(pageId: string): string {
    return `${this.getPageDir(pageId)}/${OFFLINE_PAGE_SNAPSHOT_FILE_NAME}`;
  }

  getDraftFilePath(saveJobId: string, relativePath: string): string {
    return this.resolveDraftPath(this.getDraftDir(saveJobId), relativePath);
  }

  toFileUri(path: string): string {
    return path.length > 0 ? fileUri.getUriFromPath(path) : '';
  }

  async ensureRoot(): Promise<void> {
    await this.ensureDir(this.getRootDir());
    await this.ensureDir(`${this.getRootDir()}/${OFFLINE_PAGE_TMP_DIR_NAME}`);
    await this.ensureDir(this.getPagesDir());
  }

  async prepareDraft(saveJobId: string): Promise<string> {
    await this.ensureRoot();
    const draftDir = this.getDraftDir(saveJobId);
    await this.removeDirectoryTree(draftDir);
    await this.ensureDir(draftDir);
    await this.ensureDir(`${draftDir}/assets`);
    return draftDir;
  }

  async writeTextToDraft(saveJobId: string, command: OfflinePageWriteTextCommand): Promise<string> {
    const draftDir = this.getDraftDir(saveJobId);
    const targetPath = this.resolveDraftPath(draftDir, command.relativePath);
    await this.ensureParentDir(targetPath);
    const payload = this.textEncoder.encodeInto(command.content);
    await this.writeBytes(targetPath, payload.buffer as ArrayBuffer);
    return targetPath;
  }

  async writeBytesToDraft(saveJobId: string, command: OfflinePageWriteBytesCommand): Promise<string> {
    const draftDir = this.getDraftDir(saveJobId);
    const targetPath = this.resolveDraftPath(draftDir, command.relativePath);
    await this.ensureParentDir(targetPath);
    await this.writeBytes(targetPath, command.bytes);
    return targetPath;
  }

  async readText(path: string): Promise<string> {
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const stat = await fileIo.stat(path);
      const buffer = new ArrayBuffer(Math.max(0, stat.size));
      const readLength = await fileIo.read(file.fd, buffer);
      return this.textDecoder.decodeWithStream(new Uint8Array(buffer.slice(0, readLength)), {
        stream: false
      });
    } finally {
      await fileIo.close(file);
    }
  }

  async commitDraft(
    saveJobId: string,
    pageId: string,
    snapshotFileName: string = OFFLINE_PAGE_SNAPSHOT_FILE_NAME
  ): Promise<OfflinePageDraftCommitResult> {
    await this.ensureRoot();
    const draftDir = this.getDraftDir(saveJobId);
    const pageDir = this.getPageDir(pageId);
    await this.removeDirectoryTree(pageDir);
    await fileIo.rename(draftDir, pageDir);
    const normalizedSnapshotFileName = this.sanitizePathSegment(snapshotFileName);
    const totalBytes = await this.measureDirectoryBytes(pageDir);
    return {
      pageDir: pageDir,
      manifestPath: `${pageDir}/${OFFLINE_PAGE_MANIFEST_FILE_NAME}`,
      snapshotPath: `${pageDir}/${normalizedSnapshotFileName.length > 0 ? normalizedSnapshotFileName : OFFLINE_PAGE_SNAPSHOT_FILE_NAME}`,
      totalBytes: totalBytes
    };
  }

  async moveFileToDraft(saveJobId: string, sourcePath: string, relativePath: string): Promise<string> {
    const normalizedSourcePath = sourcePath.trim();
    if (normalizedSourcePath.length === 0) {
      return '';
    }
    const targetPath = this.getDraftFilePath(saveJobId, relativePath);
    await this.ensureParentDir(targetPath);
    try {
      await fileIo.rename(normalizedSourcePath, targetPath);
    } catch (_renameError) {
      await fileIo.copyFile(normalizedSourcePath, targetPath);
      await fileIo.unlink(normalizedSourcePath);
    }
    return targetPath;
  }

  async pageExists(pageId: string): Promise<boolean> {
    return await this.exists(this.getPageDir(pageId));
  }

  async textFileAvailable(path: string): Promise<boolean> {
    const normalizedPath = path.trim();
    if (normalizedPath.length === 0) {
      return false;
    }
    try {
      const stat = await fileIo.stat(normalizedPath);
      return !stat.isDirectory() && stat.size > 0;
    } catch (_error) {
      return false;
    }
  }

  async removePage(pageId: string): Promise<boolean> {
    return await this.removeDirectoryTree(this.getPageDir(pageId));
  }

  async cleanupDraft(saveJobId: string): Promise<boolean> {
    return await this.removeDirectoryTree(this.getDraftDir(saveJobId));
  }

  async measurePageBytes(pageId: string): Promise<number> {
    return await this.measureDirectoryBytes(this.getPageDir(pageId));
  }

  async measureDirectoryBytes(dir: string): Promise<number> {
    try {
      const names = await fileIo.listFile(dir);
      let total = 0;
      for (let index = 0; index < names.length; index += 1) {
        const path = `${dir}/${names[index]}`;
        total += await this.measurePathBytes(path);
      }
      return total;
    } catch (_error) {
      return 0;
    }
  }

  private async measurePathBytes(path: string): Promise<number> {
    try {
      const stat = await fileIo.stat(path);
      if (stat.isDirectory()) {
        return await this.measureDirectoryBytes(path);
      }
      return Math.max(0, stat.size);
    } catch (_error) {
      return 0;
    }
  }

  private async writeBytes(path: string, bytes: ArrayBuffer): Promise<void> {
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, bytes);
    } finally {
      await fileIo.close(file);
    }
  }

  private async ensureParentDir(path: string): Promise<void> {
    const index = path.lastIndexOf('/');
    if (index <= 0) {
      return;
    }
    await this.ensureDir(path.substring(0, index));
  }

  private async ensureDir(path: string): Promise<void> {
    try {
      if (await fileIo.access(path)) {
        return;
      }
    } catch (_error) {
    }
    await fileIo.mkdir(path, true);
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }

  private async removeDirectoryTree(dir: string): Promise<boolean> {
    if (!await this.exists(dir)) {
      return false;
    }
    try {
      const names = await fileIo.listFile(dir);
      for (let index = 0; index < names.length; index += 1) {
        const path = `${dir}/${names[index]}`;
        const stat = await fileIo.stat(path);
        if (stat.isDirectory()) {
          await this.removeDirectoryTree(path);
        } else {
          await fileIo.unlink(path);
        }
      }
      await fileIo.rmdir(dir);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private resolveDraftPath(draftDir: string, relativePath: string): string {
    const sanitized = relativePath
      .split('/')
      .map((segment: string): string => this.sanitizePathSegment(segment))
      .filter((segment: string): boolean => segment.length > 0)
      .join('/');
    return sanitized.length > 0 ? `${draftDir}/${sanitized}` : `${draftDir}/${OFFLINE_PAGE_SNAPSHOT_FILE_NAME}`;
  }

  private sanitizePathSegment(value: string): string {
    return value.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
  }
}
