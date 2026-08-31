import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  NovelChapterArtifactCachePort,
  NovelChapterArtifactCacheReadResult,
  NovelChapterArtifactCacheRecord,
  NovelContentKind
} from '../../features/novel/NovelReaderModels';
import {
  sharedNovelSourceIdentityService
} from '../../services/novel/NovelSourceIdentityService';

interface NovelChapterArtifactCacheDocument extends NovelChapterArtifactCacheRecord {
  schemaVersion: number;
}

interface NovelChapterBookReferenceDocument {
  schemaVersion: number;
  bookDetailUrl: string;
  canonicalUrl: string;
  cachedAt: number;
}

interface NovelChapterArtifactFileEntry {
  path: string;
  size: number;
  modifiedAt: number;
}

const NOVEL_CHAPTER_CACHE_SCHEMA_VERSION: number = 1;
const NOVEL_CHAPTER_CACHE_DIR_NAME: string = 'novel-chapter-artifacts-v1';
const NOVEL_CHAPTER_CACHE_REFRESH_INTERVAL_MS: number = 6 * 60 * 60 * 1000;
const NOVEL_CHAPTER_CACHE_MAX_ARTIFACTS: number = 256;
const NOVEL_CHAPTER_CACHE_MAX_BOOK_REFERENCES: number = 500;
const NOVEL_CHAPTER_CACHE_MAX_TOTAL_BYTES: number = 96 * 1024 * 1024;
const NOVEL_CHAPTER_CACHE_MAX_ARTIFACT_BYTES: number = 4 * 1024 * 1024;
const NOVEL_CHAPTER_CACHE_MAX_REFERENCE_BYTES: number = 16 * 1024;
const NOVEL_CHAPTER_CACHE_MAX_ID_LENGTH: number = 8192;
const NOVEL_CHAPTER_CACHE_MAX_URL_LENGTH: number = 4096;
const NOVEL_CHAPTER_CACHE_MAX_TITLE_LENGTH: number = 240;
const NOVEL_CHAPTER_CACHE_MAX_PARAGRAPHS: number = 20000;
const NOVEL_CHAPTER_CACHE_MAX_PARAGRAPH_LENGTH: number = 100000;
const NOVEL_CHAPTER_CACHE_MAX_IMAGES: number = 4096;

/**
 * 持久章节工件 adapter。正文按 canonical Chapter URL 分文件，书架入口只保存一个最近章节引用。
 * 读取永不因时间过期而丢弃工件；过期仅提示 Controller 静默后台刷新。
 */
export class NovelChapterArtifactCacheRepository implements NovelChapterArtifactCachePort {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private mutationTask: Promise<void> = Promise.resolve();
  private cleanupTask: Promise<void> = Promise.resolve();
  private writeSequence: number = 0;

  async readChapter(chapterUrl: string): Promise<NovelChapterArtifactCacheReadResult | undefined> {
    let result: NovelChapterArtifactCacheReadResult | undefined = undefined;
    this.mutationTask = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        await this.cleanupTask.catch((_error: Error): void => {});
        result = await this.readChapterNow(chapterUrl);
      });
    await this.mutationTask;
    return result;
  }

  async readLatestForBook(detailUrl: string): Promise<NovelChapterArtifactCacheReadResult | undefined> {
    let result: NovelChapterArtifactCacheReadResult | undefined = undefined;
    this.mutationTask = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        await this.cleanupTask.catch((_error: Error): void => {});
        result = await this.readLatestForBookNow(detailUrl);
      });
    await this.mutationTask;
    return result;
  }

  async write(value: NovelChapterArtifactCacheRecord): Promise<void> {
    const normalized: NovelChapterArtifactCacheRecord | undefined = this.normalizeArtifact(value);
    if (normalized === undefined) {
      throw new Error('novel-chapter-cache-record-invalid');
    }
    this.mutationTask = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        await this.cleanupTask.catch((_error: Error): void => {});
        await this.writeNow(normalized);
      });
    return this.mutationTask;
  }

  async markLatestForBook(value: NovelChapterArtifactCacheRecord): Promise<void> {
    const normalized: NovelChapterArtifactCacheRecord | undefined = this.normalizeArtifact(value);
    if (normalized === undefined) {
      throw new Error('novel-chapter-cache-record-invalid');
    }
    this.mutationTask = this.mutationTask
      .catch((_error: Error): void => {})
      .then(async (): Promise<void> => {
        await this.cleanupTask.catch((_error: Error): void => {});
        await this.writeBookReferenceNow(normalized);
        this.scheduleCleanup();
      });
    return this.mutationTask;
  }

  private async readLatestForBookNow(
    detailUrl: string
  ): Promise<NovelChapterArtifactCacheReadResult | undefined> {
    const detailIdentity: string = sharedNovelSourceIdentityService.normalizeUrl(detailUrl);
    const referencePath: string = this.buildBookReferencePath(detailUrl);
    if (detailIdentity.length === 0 || referencePath.length === 0) {
      return undefined;
    }
    const reference: NovelChapterBookReferenceDocument | undefined =
      await this.readReferenceDocument(referencePath, detailIdentity);
    if (reference === undefined) {
      return undefined;
    }
    const result: NovelChapterArtifactCacheReadResult | undefined =
      await this.readChapterNow(reference.canonicalUrl);
    if (result === undefined ||
      sharedNovelSourceIdentityService.normalizeUrl(result.artifact.bookDetailUrl) !== detailIdentity) {
      await this.removePath(referencePath);
      return undefined;
    }
    return result;
  }

  private async readChapterNow(
    chapterUrl: string
  ): Promise<NovelChapterArtifactCacheReadResult | undefined> {
    const path: string = this.buildChapterPath(chapterUrl);
    if (path.length === 0) {
      return undefined;
    }
    const document: NovelChapterArtifactCacheDocument | undefined = await this.readArtifactDocument(path);
    if (document === undefined) {
      return undefined;
    }
    const normalized: NovelChapterArtifactCacheRecord | undefined = this.normalizeArtifact(document);
    const expectedUrl: string = sharedNovelSourceIdentityService.normalizeUrl(chapterUrl);
    if (document.schemaVersion !== NOVEL_CHAPTER_CACHE_SCHEMA_VERSION || normalized === undefined ||
      sharedNovelSourceIdentityService.normalizeUrl(normalized.canonicalUrl) !== expectedUrl) {
      await this.removePath(path);
      return undefined;
    }
    return {
      artifact: this.cloneArtifact(normalized),
      refreshRecommended: normalized.cachedAt <= 0 ||
        Date.now() - normalized.cachedAt >= NOVEL_CHAPTER_CACHE_REFRESH_INTERVAL_MS
    };
  }

  private async writeNow(value: NovelChapterArtifactCacheRecord): Promise<void> {
    const artifactPath: string = this.buildChapterPath(value.canonicalUrl);
    if (artifactPath.length === 0) {
      throw new Error('novel-chapter-cache-path-invalid');
    }
    const document: NovelChapterArtifactCacheDocument = {
      schemaVersion: NOVEL_CHAPTER_CACHE_SCHEMA_VERSION,
      bookId: value.bookId,
      chapterId: value.chapterId,
      bookDetailUrl: value.bookDetailUrl,
      bookTitle: value.bookTitle,
      canonicalUrl: value.canonicalUrl,
      requestedUrl: value.requestedUrl,
      finalUrl: value.finalUrl,
      title: value.title,
      contentKind: value.contentKind,
      paragraphs: value.paragraphs.slice(),
      images: value.images.slice(),
      prevUrl: value.prevUrl,
      nextUrl: value.nextUrl,
      catalogUrl: value.catalogUrl,
      cachedAt: value.cachedAt
    };
    const artifactBytes: Uint8Array = this.encoder.encodeInto(JSON.stringify(document));
    if (artifactBytes.byteLength <= 0 || artifactBytes.byteLength > NOVEL_CHAPTER_CACHE_MAX_ARTIFACT_BYTES) {
      throw new Error('novel-chapter-cache-artifact-too-large');
    }
    await this.ensureDirectory();
    await this.writeAtomic(artifactPath, artifactBytes);
    await this.writeBookReferenceNow(value);
    this.scheduleCleanup();
  }

  private async writeBookReferenceNow(value: NovelChapterArtifactCacheRecord): Promise<void> {
    if (value.bookDetailUrl.length === 0 || !await this.pathExists(this.buildChapterPath(value.canonicalUrl))) {
      return;
    }
    const referencePath: string = this.buildBookReferencePath(value.bookDetailUrl);
    if (referencePath.length === 0) {
      return;
    }
    const reference: NovelChapterBookReferenceDocument = {
      schemaVersion: NOVEL_CHAPTER_CACHE_SCHEMA_VERSION,
      bookDetailUrl: value.bookDetailUrl,
      canonicalUrl: value.canonicalUrl,
      cachedAt: Date.now()
    };
    const referenceBytes: Uint8Array = this.encoder.encodeInto(JSON.stringify(reference));
    if (referenceBytes.byteLength > 0 &&
      referenceBytes.byteLength <= NOVEL_CHAPTER_CACHE_MAX_REFERENCE_BYTES) {
      await this.writeAtomic(referencePath, referenceBytes);
    }
  }

  private async readArtifactDocument(
    path: string
  ): Promise<NovelChapterArtifactCacheDocument | undefined> {
    const raw: string | undefined = await this.readUtf8Document(path, NOVEL_CHAPTER_CACHE_MAX_ARTIFACT_BYTES);
    if (raw === undefined) {
      return undefined;
    }
    try {
      return JSON.parse(raw) as NovelChapterArtifactCacheDocument;
    } catch (_error) {
      await this.removePath(path);
      return undefined;
    }
  }

  private async readReferenceDocument(
    path: string,
    expectedDetailUrl: string
  ): Promise<NovelChapterBookReferenceDocument | undefined> {
    const raw: string | undefined = await this.readUtf8Document(path, NOVEL_CHAPTER_CACHE_MAX_REFERENCE_BYTES);
    if (raw === undefined) {
      return undefined;
    }
    let parsed: NovelChapterBookReferenceDocument;
    try {
      parsed = JSON.parse(raw) as NovelChapterBookReferenceDocument;
    } catch (_error) {
      await this.removePath(path);
      return undefined;
    }
    const detailUrl: string = this.normalizeNavigableUrl(parsed.bookDetailUrl);
    const canonicalUrl: string = this.normalizeNavigableUrl(parsed.canonicalUrl);
    if (parsed.schemaVersion !== NOVEL_CHAPTER_CACHE_SCHEMA_VERSION ||
      sharedNovelSourceIdentityService.normalizeUrl(detailUrl) !== expectedDetailUrl ||
      canonicalUrl.length === 0) {
      await this.removePath(path);
      return undefined;
    }
    return {
      schemaVersion: NOVEL_CHAPTER_CACHE_SCHEMA_VERSION,
      bookDetailUrl: detailUrl,
      canonicalUrl: canonicalUrl,
      cachedAt: this.normalizeTimestamp(parsed.cachedAt)
    };
  }

  private async readUtf8Document(path: string, maximumBytes: number): Promise<string | undefined> {
    const readablePath: string = await this.resolveReadablePath(path);
    if (readablePath.length === 0) {
      return undefined;
    }
    let file: fileIo.File | undefined = undefined;
    try {
      const stat = await fileIo.stat(readablePath);
      if (stat.isDirectory() || stat.size <= 0 || stat.size > maximumBytes) {
        await this.removePath(readablePath);
        return undefined;
      }
      file = await fileIo.open(readablePath, fileIo.OpenMode.READ_ONLY);
      const payload: ArrayBuffer = new ArrayBuffer(Math.floor(stat.size));
      const readLength: number = await fileIo.read(file.fd, payload);
      if (readLength !== payload.byteLength) {
        await fileIo.close(file);
        file = undefined;
        await this.removePath(readablePath);
        return undefined;
      }
      return this.decoder.decodeWithStream(new Uint8Array(payload), { stream: false });
    } catch (_error) {
      return undefined;
    } finally {
      if (file !== undefined) {
        await fileIo.close(file).catch((_error: Error): void => {});
      }
    }
  }

  private async writeAtomic(finalPath: string, bytes: Uint8Array): Promise<void> {
    this.writeSequence += 1;
    const temporaryPath: string = `${finalPath}.${Date.now()}-${this.writeSequence}.tmp`;
    const backupPath: string = `${finalPath}.bak`;
    let file: fileIo.File | undefined = undefined;
    let movedExisting: boolean = false;
    try {
      await this.removePath(temporaryPath);
      file = await fileIo.open(
        temporaryPath,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      const written: number = await fileIo.write(file.fd, bytes.buffer as ArrayBuffer);
      if (written !== bytes.byteLength) {
        throw new Error('novel-chapter-cache-partial-write');
      }
      await fileIo.fsync(file.fd);
      await fileIo.close(file);
      file = undefined;
      await this.removePath(backupPath);
      if (await this.pathExists(finalPath)) {
        await fileIo.rename(finalPath, backupPath);
        movedExisting = true;
      }
      await fileIo.rename(temporaryPath, finalPath);
      await this.removePath(backupPath);
    } catch (_error) {
      if (file !== undefined) {
        await fileIo.close(file).catch((_closeError: Error): void => {});
      }
      await this.removePath(temporaryPath);
      if (movedExisting && !await this.pathExists(finalPath) && await this.pathExists(backupPath)) {
        await fileIo.rename(backupPath, finalPath).catch((_restoreError: Error): void => {});
      }
      throw new Error('novel-chapter-cache-write-failed');
    }
  }

  private normalizeArtifact(
    value: NovelChapterArtifactCacheRecord
  ): NovelChapterArtifactCacheRecord | undefined {
    const bookId: string = String(value.bookId ?? '').trim();
    const chapterId: string = String(value.chapterId ?? '').trim();
    const bookDetailUrl: string = this.normalizeOptionalUrl(value.bookDetailUrl);
    const canonicalUrl: string = this.normalizeNavigableUrl(value.canonicalUrl);
    const requestedUrl: string = this.normalizeNavigableUrl(value.requestedUrl);
    const finalUrl: string = this.normalizeNavigableUrl(value.finalUrl);
    const catalogUrl: string = this.normalizeOptionalUrl(value.catalogUrl);
    if (bookId.length === 0 || bookId.length > NOVEL_CHAPTER_CACHE_MAX_ID_LENGTH ||
      chapterId.length === 0 || chapterId.length > NOVEL_CHAPTER_CACHE_MAX_ID_LENGTH ||
      canonicalUrl.length === 0 || requestedUrl.length === 0 || finalUrl.length === 0 ||
      !Array.isArray(value.paragraphs) || !Array.isArray(value.images)) {
      return undefined;
    }
    const identityCatalogUrl: string = catalogUrl.length > 0 ? catalogUrl : bookDetailUrl;
    if (bookId !== sharedNovelSourceIdentityService.buildBookIdentity(identityCatalogUrl, canonicalUrl) ||
      chapterId !== sharedNovelSourceIdentityService.buildChapterIdentity(bookId, canonicalUrl) ||
      chapterId !== sharedNovelSourceIdentityService.buildChapterIdentity(bookId, requestedUrl) ||
      chapterId !== sharedNovelSourceIdentityService.buildChapterIdentity(bookId, finalUrl)) {
      return undefined;
    }
    const paragraphs: string[] | undefined = this.normalizeParagraphs(value.paragraphs);
    const images: string[] | undefined = this.normalizeImages(value.images);
    if (paragraphs === undefined || images === undefined ||
      (paragraphs.length === 0 && images.length === 0)) {
      return undefined;
    }
    const contentKind: NovelContentKind = value.contentKind === 'comic' ? 'comic' : 'novel';
    return {
      bookId: bookId,
      chapterId: chapterId,
      bookDetailUrl: bookDetailUrl,
      bookTitle: this.normalizeTitle(value.bookTitle),
      canonicalUrl: canonicalUrl,
      requestedUrl: requestedUrl,
      finalUrl: finalUrl,
      title: this.normalizeTitle(value.title),
      contentKind: contentKind,
      paragraphs: paragraphs,
      images: images,
      prevUrl: this.normalizeOptionalUrl(value.prevUrl),
      nextUrl: this.normalizeOptionalUrl(value.nextUrl),
      catalogUrl: catalogUrl,
      cachedAt: this.normalizeTimestamp(value.cachedAt)
    };
  }

  private normalizeParagraphs(values: string[]): string[] | undefined {
    if (values.length > NOVEL_CHAPTER_CACHE_MAX_PARAGRAPHS) {
      return undefined;
    }
    const paragraphs: string[] = [];
    for (let index: number = 0; index < values.length; index += 1) {
      const paragraph: string = String(values[index] ?? '').trim();
      if (paragraph.length === 0) {
        continue;
      }
      if (paragraph.length > NOVEL_CHAPTER_CACHE_MAX_PARAGRAPH_LENGTH) {
        return undefined;
      }
      paragraphs.push(paragraph);
    }
    return paragraphs;
  }

  private normalizeImages(values: string[]): string[] | undefined {
    if (values.length > NOVEL_CHAPTER_CACHE_MAX_IMAGES) {
      return undefined;
    }
    const images: string[] = [];
    for (let index: number = 0; index < values.length; index += 1) {
      const imageUrl: string = this.normalizeNavigableUrl(values[index]);
      if (String(values[index] ?? '').trim().length === 0) {
        continue;
      }
      if (imageUrl.length === 0) {
        return undefined;
      }
      images.push(imageUrl);
    }
    return images;
  }

  private cloneArtifact(value: NovelChapterArtifactCacheRecord): NovelChapterArtifactCacheRecord {
    return {
      bookId: value.bookId,
      chapterId: value.chapterId,
      bookDetailUrl: value.bookDetailUrl,
      bookTitle: value.bookTitle,
      canonicalUrl: value.canonicalUrl,
      requestedUrl: value.requestedUrl,
      finalUrl: value.finalUrl,
      title: value.title,
      contentKind: value.contentKind,
      paragraphs: value.paragraphs.slice(),
      images: value.images.slice(),
      prevUrl: value.prevUrl,
      nextUrl: value.nextUrl,
      catalogUrl: value.catalogUrl,
      cachedAt: value.cachedAt
    };
  }

  private normalizeNavigableUrl(value: string): string {
    const normalized: string = String(value ?? '').trim();
    const lower: string = normalized.toLowerCase();
    if (normalized.length === 0 || normalized.length > NOVEL_CHAPTER_CACHE_MAX_URL_LENGTH ||
      (!lower.startsWith('https://') && !lower.startsWith('http://'))) {
      return '';
    }
    return normalized;
  }

  private normalizeOptionalUrl(value: string): string {
    const normalized: string = String(value ?? '').trim();
    return normalized.length === 0 ? '' : this.normalizeNavigableUrl(normalized);
  }

  private normalizeTitle(value: string): string {
    const normalized: string = String(value ?? '').trim();
    return normalized.length > NOVEL_CHAPTER_CACHE_MAX_TITLE_LENGTH
      ? normalized.substring(0, NOVEL_CHAPTER_CACHE_MAX_TITLE_LENGTH)
      : normalized;
  }

  private normalizeTimestamp(value: number): number {
    return Number.isFinite(value) && value > 0 ? Math.min(Math.floor(value), Date.now()) : 0;
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
    const artifacts: NovelChapterArtifactFileEntry[] = [];
    const references: NovelChapterArtifactFileEntry[] = [];
    for (let index: number = 0; index < fileNames.length; index += 1) {
      const fileName: string = fileNames[index];
      if (!fileName.endsWith('.chapter.json') && !fileName.endsWith('.book.json')) {
        continue;
      }
      const path: string = `${directory}/${fileName}`;
      try {
        const stat = await fileIo.stat(path);
        const maximumBytes: number = fileName.endsWith('.chapter.json')
          ? NOVEL_CHAPTER_CACHE_MAX_ARTIFACT_BYTES
          : NOVEL_CHAPTER_CACHE_MAX_REFERENCE_BYTES;
        if (stat.isDirectory() || stat.size <= 0 || stat.size > maximumBytes) {
          await this.removePath(path);
          continue;
        }
        const entry: NovelChapterArtifactFileEntry = {
          path: path,
          size: Math.floor(stat.size),
          modifiedAt: Math.floor(stat.mtime)
        };
        if (fileName.endsWith('.chapter.json')) {
          artifacts.push(entry);
        } else {
          references.push(entry);
        }
      } catch (_error) {
      }
    }
    artifacts.sort((left: NovelChapterArtifactFileEntry, right: NovelChapterArtifactFileEntry): number =>
      left.modifiedAt - right.modifiedAt);
    references.sort((left: NovelChapterArtifactFileEntry, right: NovelChapterArtifactFileEntry): number =>
      left.modifiedAt - right.modifiedAt);
    let totalBytes: number = artifacts.reduce(
      (total: number, entry: NovelChapterArtifactFileEntry): number => total + entry.size,
      0
    );
    while (artifacts.length > NOVEL_CHAPTER_CACHE_MAX_ARTIFACTS ||
      totalBytes > NOVEL_CHAPTER_CACHE_MAX_TOTAL_BYTES) {
      const removed: NovelChapterArtifactFileEntry | undefined = artifacts.shift();
      if (removed === undefined) {
        break;
      }
      await this.removePath(removed.path);
      totalBytes = Math.max(0, totalBytes - removed.size);
    }
    while (references.length > NOVEL_CHAPTER_CACHE_MAX_BOOK_REFERENCES) {
      const removed: NovelChapterArtifactFileEntry | undefined = references.shift();
      if (removed === undefined) {
        break;
      }
      await this.removePath(removed.path);
    }
  }

  private async ensureDirectory(): Promise<void> {
    const directory: string = this.getDirectory();
    if (await this.pathExists(directory)) {
      return;
    }
    await fileIo.mkdir(directory, true);
  }

  private async resolveReadablePath(finalPath: string): Promise<string> {
    if (await this.pathExists(finalPath)) {
      return finalPath;
    }
    const backupPath: string = `${finalPath}.bak`;
    if (!await this.pathExists(backupPath)) {
      return '';
    }
    try {
      await fileIo.rename(backupPath, finalPath);
      return finalPath;
    } catch (_error) {
      return backupPath;
    }
  }

  private async pathExists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }

  private async removePath(path: string): Promise<void> {
    try {
      await fileIo.unlink(path);
    } catch (_error) {
    }
  }

  private buildChapterPath(chapterUrl: string): string {
    const identityUrl: string = sharedNovelSourceIdentityService.normalizeUrl(chapterUrl);
    if (identityUrl.length === 0 || identityUrl.length > NOVEL_CHAPTER_CACHE_MAX_URL_LENGTH ||
      !AppRuntimeContext.hasApplicationContext()) {
      return '';
    }
    return `${this.getDirectory()}/${this.sha256Hex(identityUrl)}.chapter.json`;
  }

  private buildBookReferencePath(detailUrl: string): string {
    const normalized: string = sharedNovelSourceIdentityService.normalizeUrl(detailUrl);
    if (normalized.length === 0 || !AppRuntimeContext.hasApplicationContext()) {
      return '';
    }
    return `${this.getDirectory()}/${this.sha256Hex(normalized)}.book.json`;
  }

  private getDirectory(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${NOVEL_CHAPTER_CACHE_DIR_NAME}`;
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

export const sharedNovelChapterArtifactCacheRepository: NovelChapterArtifactCacheRepository =
  new NovelChapterArtifactCacheRepository();
