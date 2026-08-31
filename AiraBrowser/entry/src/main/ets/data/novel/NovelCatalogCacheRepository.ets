import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  NovelCatalogCachePort,
  NovelCatalogCacheRecord,
  NovelCatalogEntry,
  NovelCatalogPageCursor
} from '../../features/novel/NovelReaderModels';

interface NovelCatalogCacheDocument extends NovelCatalogCacheRecord {
  schemaVersion: number;
}

interface NovelCatalogCacheFileEntry {
  path: string;
  size: number;
  modifiedAt: number;
}

const NOVEL_CATALOG_CACHE_SCHEMA_VERSION: number = 2;
const NOVEL_CATALOG_CACHE_DIR_NAME: string = 'novel-catalog-snapshots-v1';
const NOVEL_CATALOG_CACHE_MAX_FILES: number = 48;
const NOVEL_CATALOG_CACHE_MAX_TOTAL_BYTES: number = 32 * 1024 * 1024;
const NOVEL_CATALOG_CACHE_MAX_FILE_BYTES: number = 6 * 1024 * 1024;
const NOVEL_CATALOG_CACHE_MAX_ENTRIES: number = 8000;
const NOVEL_CATALOG_CACHE_MAX_ID_LENGTH: number = 8192;
const NOVEL_CATALOG_CACHE_MAX_URL_LENGTH: number = 4096;
const NOVEL_CATALOG_CACHE_MAX_TITLE_LENGTH: number = 240;

/** 每本书一个可替换文件，避免超长目录放大书架 Preferences 的读写成本。 */
export class NovelCatalogCacheRepository implements NovelCatalogCachePort {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private mutationTask: Promise<void> = Promise.resolve();
  private cleanupTask: Promise<void> = Promise.resolve();
  private writeSequence: number = 0;

  async read(bookId: string): Promise<NovelCatalogCacheRecord | undefined> {
    await this.mutationTask.catch((_error: Error): void => {});
    return this.readNow(bookId);
  }

  private async readNow(bookId: string): Promise<NovelCatalogCacheRecord | undefined> {
    const path: string = this.buildPath(bookId);
    if (path.length === 0) {
      return undefined;
    }
    let file: fileIo.File | undefined = undefined;
    try {
      const stat = await fileIo.stat(path);
      if (stat.isDirectory() || stat.size <= 0 || stat.size > NOVEL_CATALOG_CACHE_MAX_FILE_BYTES) {
        await this.removePath(path);
        return undefined;
      }
      file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      const payload = new ArrayBuffer(Math.floor(stat.size));
      const readLength: number = await fileIo.read(file.fd, payload);
      if (readLength !== payload.byteLength) {
        await fileIo.close(file);
        file = undefined;
        await this.removePath(path);
        return undefined;
      }
      const raw: string = this.decoder.decodeWithStream(new Uint8Array(payload), { stream: false });
      let parsed: NovelCatalogCacheDocument;
      try {
        parsed = JSON.parse(raw) as NovelCatalogCacheDocument;
      } catch (_parseError) {
        await fileIo.close(file);
        file = undefined;
        await this.removePath(path);
        return undefined;
      }
      const normalized: NovelCatalogCacheRecord | undefined = this.normalize(parsed, bookId);
      if (parsed.schemaVersion !== NOVEL_CATALOG_CACHE_SCHEMA_VERSION || normalized === undefined) {
        await fileIo.close(file);
        file = undefined;
        await this.removePath(path);
        return undefined;
      }
      return normalized;
    } catch (_error) {
      return undefined;
    } finally {
      if (file !== undefined) {
        await fileIo.close(file).catch((_error: Error): void => {});
      }
    }
  }

  async write(value: NovelCatalogCacheRecord): Promise<void> {
    const normalized: NovelCatalogCacheRecord | undefined = this.normalize(value, value.bookId);
    if (normalized === undefined) {
      return;
    }
    this.mutationTask = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        const existing: NovelCatalogCacheRecord | undefined = await this.readNow(normalized.bookId);
        if (existing !== undefined && existing.catalogUrl === normalized.catalogUrl) {
          normalized.entries = this.mergeEntries(existing.entries, normalized.entries);
          normalized.complete = existing.complete || normalized.complete;
          normalized.cachedAt = Math.max(existing.cachedAt, normalized.cachedAt);
          normalized.totalHint = Math.max(existing.totalHint, normalized.totalHint);
          normalized.pageCursor = this.mergeCursor(existing.pageCursor, normalized.pageCursor);
          if (normalized.sourceLatest.length === 0) {
            normalized.sourceLatest = existing.sourceLatest;
          }
        }
        await this.writeNow(normalized);
      });
    return this.mutationTask;
  }

  private async writeNow(value: NovelCatalogCacheRecord): Promise<void> {
    const finalPath: string = this.buildPath(value.bookId);
    if (finalPath.length === 0) {
      return;
    }
    const document: NovelCatalogCacheDocument = {
      schemaVersion: NOVEL_CATALOG_CACHE_SCHEMA_VERSION,
      bookId: value.bookId,
      catalogUrl: value.catalogUrl,
      sourceLatest: value.sourceLatest,
      complete: value.complete,
      cachedAt: value.cachedAt,
      entries: this.cloneEntries(value.entries),
      totalHint: value.totalHint,
      pageCursor: value.pageCursor === undefined ? undefined : this.cloneCursor(value.pageCursor)
    };
    const bytes: Uint8Array = this.encoder.encodeInto(JSON.stringify(document));
    if (bytes.byteLength <= 0 || bytes.byteLength > NOVEL_CATALOG_CACHE_MAX_FILE_BYTES) {
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
      const written: number = await fileIo.write(file.fd, bytes.buffer as ArrayBuffer);
      await fileIo.close(file);
      file = undefined;
      if (written !== bytes.byteLength) {
        throw new Error('novel-catalog-cache-partial-write');
      }
      await this.removePath(finalPath);
      await fileIo.rename(tempPath, finalPath);
      this.scheduleCleanup();
    } catch (_error) {
      if (file !== undefined) {
        await fileIo.close(file).catch((_closeError: Error): void => {});
      }
      await this.removePath(tempPath);
      throw new Error('novel-catalog-cache-write-failed');
    }
  }

  private normalize(
    value: NovelCatalogCacheRecord,
    expectedBookId: string
  ): NovelCatalogCacheRecord | undefined {
    const bookId: string = String(value.bookId ?? '').trim();
    const catalogUrl: string = this.normalizeUrl(value.catalogUrl);
    if (bookId.length === 0 || bookId.length > NOVEL_CATALOG_CACHE_MAX_ID_LENGTH ||
      bookId !== expectedBookId.trim() || catalogUrl.length === 0 || !Array.isArray(value.entries)) {
      return undefined;
    }
    const entries: NovelCatalogEntry[] = [];
    const seen: Record<string, boolean> = {};
    for (let index: number = 0;
      index < value.entries.length && entries.length < NOVEL_CATALOG_CACHE_MAX_ENTRIES;
      index += 1) {
      const title: string = String(value.entries[index].title ?? '').trim()
        .substring(0, NOVEL_CATALOG_CACHE_MAX_TITLE_LENGTH);
      const url: string = this.normalizeUrl(value.entries[index].url);
      const rawOrdinal: number = Number(value.entries[index].ordinal);
      const ordinal: number = Number.isFinite(rawOrdinal) && rawOrdinal >= 0
        ? Math.floor(rawOrdinal)
        : index;
      if (title.length === 0 || url.length === 0 || seen[url] === true) {
        continue;
      }
      seen[url] = true;
      entries.push({ ordinal: ordinal, title: title, url: url });
    }
    if (entries.length === 0) {
      return undefined;
    }
    return {
      bookId: bookId,
      catalogUrl: catalogUrl,
      sourceLatest: String(value.sourceLatest ?? '').trim().substring(0, NOVEL_CATALOG_CACHE_MAX_TITLE_LENGTH),
      complete: value.complete === true,
      cachedAt: Math.max(0, Math.floor(Number.isFinite(value.cachedAt) ? value.cachedAt : 0)),
      entries: entries,
      totalHint: Math.max(0, Math.floor(Number.isFinite(value.totalHint) ? value.totalHint : 0)),
      pageCursor: this.normalizeCursor(value.pageCursor)
    };
  }

  private normalizeCursor(value: NovelCatalogPageCursor | undefined): NovelCatalogPageCursor | undefined {
    if (value === undefined) {
      return undefined;
    }
    const ruleId: string = String(value.ruleId ?? '').trim();
    const bookToken: string = String(value.bookToken ?? '').trim();
    const initialPage: number = Math.max(0, Math.floor(Number(value.initialPage ?? 0)));
    const nextPage: number = Math.max(0, Math.floor(Number(value.nextPage)));
    const pageSize: number = Math.max(1, Math.floor(Number(value.pageSize)));
    const totalHint: number = Math.max(0, Math.floor(Number(value.totalHint)));
    const totalPages: number = Math.max(0, Math.floor(Number(value.totalPages)));
    if (ruleId.length === 0 || ruleId.length > 80 || bookToken.length === 0 || bookToken.length > 160 ||
      !Number.isFinite(initialPage) || !Number.isFinite(nextPage) || !Number.isFinite(pageSize) ||
      !Number.isFinite(totalHint) ||
      !Number.isFinite(totalPages)) {
      return undefined;
    }
    return {
      ruleId: ruleId,
      bookToken: bookToken,
      initialPage: initialPage,
      nextPage: nextPage,
      pageSize: pageSize,
      totalHint: totalHint,
      totalPages: totalPages
    };
  }

  private cloneCursor(value: NovelCatalogPageCursor): NovelCatalogPageCursor {
    return {
      ruleId: value.ruleId,
      bookToken: value.bookToken,
      initialPage: value.initialPage,
      nextPage: value.nextPage,
      pageSize: value.pageSize,
      totalHint: value.totalHint,
      totalPages: value.totalPages
    };
  }

  private cloneEntries(entries: NovelCatalogEntry[]): NovelCatalogEntry[] {
    return entries.map((entry: NovelCatalogEntry): NovelCatalogEntry => ({
      ordinal: entry.ordinal,
      title: entry.title,
      url: entry.url
    }));
  }

  private mergeEntries(current: NovelCatalogEntry[], incoming: NovelCatalogEntry[]): NovelCatalogEntry[] {
    const merged: NovelCatalogEntry[] = this.cloneEntries(current);
    for (let incomingIndex: number = 0; incomingIndex < incoming.length; incomingIndex += 1) {
      const entry: NovelCatalogEntry = incoming[incomingIndex];
      for (let index: number = merged.length - 1; index >= 0; index -= 1) {
        if (merged[index].url === entry.url || merged[index].ordinal === entry.ordinal) {
          merged.splice(index, 1);
        }
      }
      merged.push({ ordinal: entry.ordinal, title: entry.title, url: entry.url });
    }
    merged.sort((left: NovelCatalogEntry, right: NovelCatalogEntry): number =>
      left.ordinal === right.ordinal ? left.url.localeCompare(right.url) : left.ordinal - right.ordinal);
    return merged;
  }

  private mergeCursor(
    current: NovelCatalogPageCursor | undefined,
    incoming: NovelCatalogPageCursor | undefined
  ): NovelCatalogPageCursor | undefined {
    if (current === undefined) {
      return incoming === undefined ? undefined : this.cloneCursor(incoming);
    }
    if (incoming === undefined || current.ruleId !== incoming.ruleId ||
      current.bookToken !== incoming.bookToken) {
      return this.cloneCursor(current);
    }
    const merged: NovelCatalogPageCursor = this.cloneCursor(incoming);
    merged.totalHint = Math.max(current.totalHint, incoming.totalHint);
    merged.totalPages = Math.max(current.totalPages, incoming.totalPages);
    return merged;
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
    const entries: NovelCatalogCacheFileEntry[] = [];
    for (let index: number = 0; index < fileNames.length; index += 1) {
      if (!fileNames[index].endsWith('.json')) {
        continue;
      }
      const path: string = `${directory}/${fileNames[index]}`;
      try {
        const stat = await fileIo.stat(path);
        if (stat.isDirectory() || stat.size <= 0 || stat.size > NOVEL_CATALOG_CACHE_MAX_FILE_BYTES) {
          await this.removePath(path);
          continue;
        }
        entries.push({ path: path, size: Math.floor(stat.size), modifiedAt: Math.floor(stat.mtime) });
      } catch (_error) {
      }
    }
    entries.sort((left: NovelCatalogCacheFileEntry, right: NovelCatalogCacheFileEntry): number =>
      left.modifiedAt - right.modifiedAt);
    let totalBytes: number = entries.reduce(
      (total: number, entry: NovelCatalogCacheFileEntry): number => total + entry.size,
      0
    );
    while (entries.length > NOVEL_CATALOG_CACHE_MAX_FILES ||
      totalBytes > NOVEL_CATALOG_CACHE_MAX_TOTAL_BYTES) {
      const removed: NovelCatalogCacheFileEntry | undefined = entries.shift();
      if (removed === undefined) {
        return;
      }
      await this.removePath(removed.path);
      totalBytes = Math.max(0, totalBytes - removed.size);
    }
  }

  private normalizeUrl(value: string): string {
    const normalized: string = String(value ?? '').trim();
    const lower: string = normalized.toLowerCase();
    if (normalized.length === 0 || normalized.length > NOVEL_CATALOG_CACHE_MAX_URL_LENGTH ||
      (!lower.startsWith('https://') && !lower.startsWith('http://'))) {
      return '';
    }
    return normalized;
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

  private buildPath(bookId: string): string {
    const normalized: string = bookId.trim();
    if (normalized.length === 0 || normalized.length > NOVEL_CATALOG_CACHE_MAX_ID_LENGTH ||
      !AppRuntimeContext.hasApplicationContext()) {
      return '';
    }
    return `${this.getDirectory()}/${this.sha256Hex(normalized)}.json`;
  }

  private getDirectory(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${NOVEL_CATALOG_CACHE_DIR_NAME}`;
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
}

export const sharedNovelCatalogCacheRepository: NovelCatalogCacheRepository =
  new NovelCatalogCacheRepository();
