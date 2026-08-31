import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

interface NovelBookCoverCacheFileEntry {
  path: string;
  size: number;
  modifiedAt: number;
}

const NOVEL_BOOK_COVER_CACHE_DIR_NAME: string = 'novel-book-cover-thumbnails-v1';
const NOVEL_BOOK_COVER_CACHE_MAX_FILES: number = 640;
const NOVEL_BOOK_COVER_CACHE_MAX_TOTAL_BYTES: number = 64 * 1024 * 1024;
export const NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES: number = 512 * 1024;

export class NovelBookCoverCacheStore {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private cleanupTask: Promise<void> = Promise.resolve();
  private writeSequence: number = 0;

  async read(coverUrl: string): Promise<ArrayBuffer | undefined> {
    const path: string = this.buildPath(coverUrl);
    if (path.length === 0) {
      return undefined;
    }
    let file: fileIo.File | undefined = undefined;
    try {
      const stat = await fileIo.stat(path);
      if (stat.isDirectory() || stat.size <= 0 || stat.size > NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES) {
        await this.removePath(path);
        return undefined;
      }
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const payload = new ArrayBuffer(Math.floor(stat.size));
      const readLength: number = await fileIo.read(file.fd, payload);
      if (readLength !== payload.byteLength || !this.isJpeg(payload)) {
        await fileIo.close(file);
        file = undefined;
        await this.removePath(path);
        return undefined;
      }
      return payload;
    } catch (_error) {
      return undefined;
    } finally {
      if (file !== undefined) {
        await fileIo.close(file).catch((_error: Error): void => {});
      }
    }
  }

  async write(coverUrl: string, payload: ArrayBuffer): Promise<void> {
    const finalPath: string = this.buildPath(coverUrl);
    if (finalPath.length === 0 || payload.byteLength <= 0 ||
      payload.byteLength > NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES || !this.isJpeg(payload)) {
      return;
    }
    if (await this.isUsableFile(finalPath)) {
      return;
    }
    await this.ensureDirectory();
    this.writeSequence += 1;
    const tempPath: string = `${finalPath}.${Date.now()}-${this.writeSequence}.tmp`;
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(
        tempPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      const written: number = await fileIo.write(file.fd, payload);
      await fileIo.close(file);
      file = undefined;
      if (written !== payload.byteLength) {
        throw new Error('novel-cover-cache-partial-write');
      }
      if (await this.isUsableFile(finalPath)) {
        await this.removePath(tempPath);
      } else {
        await fileIo.rename(tempPath, finalPath);
      }
      this.scheduleCleanup();
    } catch (_error) {
      if (file !== undefined) {
        await fileIo.close(file).catch((_error: Error): void => {});
      }
      await this.removePath(tempPath);
      throw new Error('novel-cover-cache-write-failed');
    }
  }

  async remove(coverUrl: string): Promise<void> {
    const path: string = this.buildPath(coverUrl);
    if (path.length > 0) {
      await this.removePath(path);
    }
  }

  private scheduleCleanup(): void {
    this.cleanupTask = this.cleanupTask
      .catch((_error: Error): void => {})
      .then((): Promise<void> => this.prune());
  }

  private async prune(): Promise<void> {
    const directory: string = this.getDirectory();
    let fileNames: string[] = [];
    try {
      fileNames = await fileIo.listFile(directory);
    } catch (_error) {
      return;
    }
    const entries: NovelBookCoverCacheFileEntry[] = [];
    for (let index: number = 0; index < fileNames.length; index += 1) {
      const fileName: string = fileNames[index];
      if (!fileName.endsWith('.jpg')) {
        continue;
      }
      const path: string = `${directory}/${fileName}`;
      try {
        const stat = await fileIo.stat(path);
        if (stat.isDirectory() || stat.size <= 0 || stat.size > NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES) {
          await this.removePath(path);
          continue;
        }
        entries.push({
          path: path,
          size: Math.floor(stat.size),
          modifiedAt: Math.floor(stat.mtime)
        });
      } catch (_error) {
      }
    }
    entries.sort((left: NovelBookCoverCacheFileEntry, right: NovelBookCoverCacheFileEntry): number =>
      left.modifiedAt - right.modifiedAt);
    let totalBytes: number = entries.reduce(
      (total: number, entry: NovelBookCoverCacheFileEntry): number => total + entry.size,
      0
    );
    while (entries.length > NOVEL_BOOK_COVER_CACHE_MAX_FILES ||
      totalBytes > NOVEL_BOOK_COVER_CACHE_MAX_TOTAL_BYTES) {
      const removed: NovelBookCoverCacheFileEntry | undefined = entries.shift();
      if (removed === undefined) {
        return;
      }
      await this.removePath(removed.path);
      totalBytes = Math.max(0, totalBytes - removed.size);
    }
  }

  private async isUsableFile(path: string): Promise<boolean> {
    try {
      const stat = await fileIo.stat(path);
      return !stat.isDirectory() && stat.size > 0 && stat.size <= NOVEL_BOOK_COVER_CACHE_MAX_FILE_BYTES;
    } catch (_error) {
      return false;
    }
  }

  private async ensureDirectory(): Promise<void> {
    const directory: string = this.getDirectory();
    try {
      if (await fileIo.access(directory)) {
        return;
      }
    } catch (_error) {
    }
    await fileIo.mkdir(directory, true);
  }

  private async removePath(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_error) {
    }
  }

  private buildPath(coverUrl: string): string {
    const normalized: string = coverUrl.trim();
    if (normalized.length === 0 || !AppRuntimeContext.hasApplicationContext()) {
      return '';
    }
    return `${this.getDirectory()}/${this.sha256Hex(normalized)}.jpg`;
  }

  private getDirectory(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${NOVEL_BOOK_COVER_CACHE_DIR_NAME}`;
  }

  private sha256Hex(value: string): string {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: this.encoder.encodeInto(value) });
    const bytes: Uint8Array = (digest.digestSync() as cryptoFramework.DataBlob).data;
    let result: string = '';
    for (let index: number = 0; index < bytes.length; index += 1) {
      result += bytes[index].toString(16).padStart(2, '0');
    }
    return result;
  }

  private isJpeg(payload: ArrayBuffer): boolean {
    const bytes = new Uint8Array(payload);
    return bytes.length >= 4 && bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF;
  }
}

export const sharedNovelBookCoverCacheStore: NovelBookCoverCacheStore = new NovelBookCoverCacheStore();
