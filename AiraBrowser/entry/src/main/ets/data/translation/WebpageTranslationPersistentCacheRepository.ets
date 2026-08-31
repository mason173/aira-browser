import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';

const CACHE_DIR_NAME: string = 'webpage-translation-cache';
const CACHE_VERSION: number = 1;
const CACHE_SHARD_COUNT: number = 64;
const MAX_RECORDS_PER_SHARD: number = 500;
const MAX_TEXT_CHARS_PER_SHARD: number = 180000;

export interface WebpageTranslationCacheRecord {
  key: string;
  providerNamespace: string;
  sourceLanguage: string;
  targetLanguage: string;
  sourceText: string;
  translatedText: string;
  sourceHash: string;
  updatedAt: number;
  lastUsedAt: number;
  useCount: number;
  textChars: number;
}

interface WebpageTranslationCacheShardPayload {
  version: number;
  records: WebpageTranslationCacheRecord[];
}

export class WebpageTranslationPersistentCacheRepository {
  private textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private loadedShards: Record<string, WebpageTranslationCacheRecord[]> = {};
  private dirtyShards: Record<string, boolean> = {};

  async find(key: string): Promise<WebpageTranslationCacheRecord | undefined> {
    const shard = this.resolveShard(key);
    const records = await this.loadShard(shard);
    const index = records.findIndex((record: WebpageTranslationCacheRecord) => record.key === key);
    if (index < 0) {
      return undefined;
    }
    records[index].lastUsedAt = Date.now();
    records[index].useCount = Math.max(0, Math.floor(records[index].useCount)) + 1;
    this.dirtyShards[shard] = true;
    return records[index];
  }

  async upsert(record: WebpageTranslationCacheRecord): Promise<void> {
    const shard = this.resolveShard(record.key);
    const records = await this.loadShard(shard);
    const index = records.findIndex((current: WebpageTranslationCacheRecord) => current.key === record.key);
    if (index >= 0) {
      const previous = records[index];
      records[index] = {
        key: record.key,
        providerNamespace: record.providerNamespace,
        sourceLanguage: record.sourceLanguage,
        targetLanguage: record.targetLanguage,
        sourceText: record.sourceText,
        translatedText: record.translatedText,
        sourceHash: record.sourceHash,
        updatedAt: record.updatedAt,
        lastUsedAt: record.lastUsedAt,
        useCount: Math.max(1, Math.floor(previous.useCount) + 1),
        textChars: record.textChars
      };
    } else {
      records.push(record);
    }
    this.loadedShards[shard] = this.pruneShard(records);
    this.dirtyShards[shard] = true;
    await this.flushShard(shard);
  }

  async upsertMany(records: WebpageTranslationCacheRecord[]): Promise<void> {
    const byShard: Record<string, WebpageTranslationCacheRecord[]> = {};
    records.forEach((record: WebpageTranslationCacheRecord) => {
      const shard = this.resolveShard(record.key);
      if (byShard[shard] === undefined) {
        byShard[shard] = [];
      }
      byShard[shard].push(record);
    });

    const shards = Object.keys(byShard);
    for (let index = 0; index < shards.length; index += 1) {
      const shard = shards[index];
      const currentRecords = await this.loadShard(shard);
      const nextRecords = currentRecords.slice();
      byShard[shard].forEach((record: WebpageTranslationCacheRecord) => {
        const existingIndex = nextRecords.findIndex((current: WebpageTranslationCacheRecord) => current.key === record.key);
        if (existingIndex >= 0) {
          const previous = nextRecords[existingIndex];
          nextRecords[existingIndex] = {
            key: record.key,
            providerNamespace: record.providerNamespace,
            sourceLanguage: record.sourceLanguage,
            targetLanguage: record.targetLanguage,
            sourceText: record.sourceText,
            translatedText: record.translatedText,
            sourceHash: record.sourceHash,
            updatedAt: record.updatedAt,
            lastUsedAt: record.lastUsedAt,
            useCount: Math.max(1, Math.floor(previous.useCount) + 1),
            textChars: record.textChars
          };
        } else {
          nextRecords.push(record);
        }
      });
      this.loadedShards[shard] = this.pruneShard(nextRecords);
      this.dirtyShards[shard] = true;
      await this.flushShard(shard);
    }
  }

  buildKey(providerNamespace: string, sourceLanguage: string, targetLanguage: string, sourceText: string): string {
    return [
      this.normalizeNamespace(providerNamespace),
      this.normalizeLanguage(sourceLanguage),
      this.normalizeLanguage(targetLanguage),
      this.hashText(this.normalizeText(sourceText))
    ].join('::');
  }

  buildSourceHash(sourceText: string): string {
    return this.hashText(this.normalizeText(sourceText));
  }

  normalizeText(value: string): string {
    return value.replace(/\s+/g, ' ').trim().toLowerCase();
  }

  private pruneShard(records: WebpageTranslationCacheRecord[]): WebpageTranslationCacheRecord[] {
    const sorted = records.slice().sort((left: WebpageTranslationCacheRecord, right: WebpageTranslationCacheRecord) => {
      return right.lastUsedAt - left.lastUsedAt;
    });
    const retained: WebpageTranslationCacheRecord[] = [];
    let textChars = 0;
    for (let index = 0; index < sorted.length; index += 1) {
      const record = sorted[index];
      const nextChars = textChars + Math.max(0, Math.floor(record.textChars));
      if (retained.length >= MAX_RECORDS_PER_SHARD || nextChars > MAX_TEXT_CHARS_PER_SHARD) {
        continue;
      }
      retained.push(record);
      textChars = nextChars;
    }
    return retained;
  }

  private async loadShard(shard: string): Promise<WebpageTranslationCacheRecord[]> {
    const cached = this.loadedShards[shard];
    if (cached !== undefined) {
      return cached;
    }
    const path = this.buildShardPath(shard);
    if (!await this.exists(path)) {
      this.loadedShards[shard] = [];
      return this.loadedShards[shard];
    }
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = await fileIo.stat(path);
        const size = Math.max(0, Math.floor(stat.size));
        if (size <= 0 || size > 2 * 1024 * 1024) {
          this.loadedShards[shard] = [];
          return this.loadedShards[shard];
        }
        const buffer = new ArrayBuffer(size);
        const readLength = await fileIo.read(file.fd, buffer);
        if (readLength <= 0) {
          this.loadedShards[shard] = [];
          return this.loadedShards[shard];
        }
        const text = this.textDecoder.decodeToString(new Uint8Array(buffer, 0, readLength));
        const payload = JSON.parse(text) as WebpageTranslationCacheShardPayload;
        this.loadedShards[shard] = this.normalizeRecords(payload);
        return this.loadedShards[shard];
      } finally {
        await fileIo.close(file);
      }
    } catch (_error) {
      this.loadedShards[shard] = [];
      return this.loadedShards[shard];
    }
  }

  private async flushShard(shard: string): Promise<void> {
    if (this.dirtyShards[shard] !== true) {
      return;
    }
    await this.ensureDir(this.getCacheDir());
    const payload: WebpageTranslationCacheShardPayload = {
      version: CACHE_VERSION,
      records: this.loadedShards[shard] ?? []
    };
    const encoded = this.textEncoder.encodeInto(JSON.stringify(payload));
    const file = await fileIo.open(
      this.buildShardPath(shard),
      fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
    );
    try {
      await fileIo.write(file.fd, encoded.buffer as ArrayBuffer);
    } finally {
      await fileIo.close(file);
    }
    this.dirtyShards[shard] = false;
  }

  private normalizeRecords(payload: WebpageTranslationCacheShardPayload): WebpageTranslationCacheRecord[] {
    if (payload.version !== CACHE_VERSION || !Array.isArray(payload.records)) {
      return [];
    }
    const records: WebpageTranslationCacheRecord[] = [];
    payload.records.forEach((record: WebpageTranslationCacheRecord) => {
      const normalized = this.normalizeRecord(record);
      if (normalized !== undefined) {
        records.push(normalized);
      }
    });
    return this.pruneShard(records);
  }

  private normalizeRecord(record: WebpageTranslationCacheRecord): WebpageTranslationCacheRecord | undefined {
    const key = String(record.key ?? '').trim();
    const sourceText = String(record.sourceText ?? '').trim();
    const translatedText = String(record.translatedText ?? '').trim();
    if (key.length === 0 || sourceText.length === 0 || translatedText.length === 0) {
      return undefined;
    }
    return {
      key: key,
      providerNamespace: String(record.providerNamespace ?? '').trim(),
      sourceLanguage: this.normalizeLanguage(record.sourceLanguage ?? ''),
      targetLanguage: this.normalizeLanguage(record.targetLanguage ?? ''),
      sourceText: sourceText,
      translatedText: translatedText,
      sourceHash: String(record.sourceHash ?? '').trim(),
      updatedAt: Math.max(0, Math.floor(record.updatedAt ?? 0)),
      lastUsedAt: Math.max(0, Math.floor(record.lastUsedAt ?? 0)),
      useCount: Math.max(0, Math.floor(record.useCount ?? 0)),
      textChars: Math.max(sourceText.length + translatedText.length, Math.floor(record.textChars ?? 0))
    };
  }

  private resolveShard(key: string): string {
    const hash = this.hashText(key);
    const shardIndex = parseInt(hash.substring(0, 8), 16) % CACHE_SHARD_COUNT;
    return shardIndex.toString(16).padStart(2, '0');
  }

  private hashText(value: string): string {
    let left = 2166136261;
    let right = 2166136261 ^ 0x9e3779b9;
    for (let index = 0; index < value.length; index += 1) {
      const code = value.charCodeAt(index);
      left ^= code;
      left = Math.imul(left, 16777619);
      right ^= code + index;
      right = Math.imul(right, 16777619);
    }
    return (left >>> 0).toString(16).padStart(8, '0') + (right >>> 0).toString(16).padStart(8, '0');
  }

  private normalizeNamespace(value: string): string {
    return value.trim().toLowerCase();
  }

  private normalizeLanguage(value: string): string {
    return value.trim().toLowerCase();
  }

  private buildShardPath(shard: string): string {
    return `${this.getCacheDir()}/${CACHE_VERSION}-${shard}.json`;
  }

  private getCacheDir(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${CACHE_DIR_NAME}`;
  }

  private async ensureDir(dir: string): Promise<void> {
    try {
      if (await fileIo.access(dir)) {
        return;
      }
    } catch (_error) {
    }
    try {
      await fileIo.mkdir(dir, true);
    } catch (_error) {
    }
  }

  private async exists(path: string): Promise<boolean> {
    try {
      return await fileIo.access(path);
    } catch (_error) {
      return false;
    }
  }
}
