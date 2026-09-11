import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  SiteIconCachedFile,
  SiteIconCacheMetadata,
  SiteIconCachePruneOptions,
  SiteIconCachePruneResult,
  SiteIconCacheState,
  SiteIconCandidateSource,
  SiteIconMetadataRecord
} from '../../common/models/SiteIconModels';
import { BrowserDatabase, sharedBrowserDatabase } from '../database/BrowserDatabase';

const SITE_ICON_CACHE_DIR_NAME: string = 'site-icons';
const SITE_ICON_CACHE_VERSION: string = 'v2';
const MIN_UNKNOWN_CACHE_REPLACEMENT_SCORE: number = 130000;

interface SiteIconCachePruneCandidate {
  domain: string;
  path: string;
  metadataPath: string;
  extension: string;
  metadataExtension: string;
  bytes: number;
  lastUsedAt: number;
}

export interface SiteIconCachedDomainFile {
  domain: string;
  file: SiteIconCachedFile;
}

export class SiteIconCacheStore {
  private textEncoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private textDecoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private database: BrowserDatabase;

  constructor(database: BrowserDatabase = sharedBrowserDatabase) {
    this.database = database;
  }

  async findCachedIcon(domain: string): Promise<SiteIconCachedFile | undefined> {
    return this.findCachedIconInDir(domain, this.getCacheDir(), 'disk');
  }

  async findCachedIconsByDomains(domains: string[]): Promise<SiteIconCachedDomainFile[]> {
    const normalizedDomains = this.normalizeDomains(domains);
    if (normalizedDomains.length === 0) {
      return [];
    }

    const entries: SiteIconCachedDomainFile[] = [];
    const resolvedDomains: string[] = [];
    const records = await this.listDatabaseMetadataByDomains(normalizedDomains);
    for (let index = 0; index < records.length; index += 1) {
      const record = records[index];
      const path = this.toFilePath(record.fileUri);
      if (!this.isPathInCacheDir(path)) {
        await this.database.deleteSiteIconMetadata(record.domain);
        continue;
      }
      const isUsable = await this.isCachedIconUsable(path);
      if (!isUsable) {
        await this.database.deleteSiteIconMetadata(record.domain);
        continue;
      }
      const metadata = this.normalizeMetadata({
        source: record.source,
        iconUrl: record.iconUrl,
        extension: record.extension,
        qualityScore: record.qualityScore,
        width: record.width,
        height: record.height,
        updatedAt: record.updatedAt,
        lastAccessedAt: record.lastAccessedAt
      });
      entries.push({
        domain: record.domain,
        file: this.applyMetadata({
          path: path,
          uri: this.toImageUri(path),
          cacheState: 'disk'
        }, metadata)
      });
      resolvedDomains.push(record.domain);
      await this.touchMetadataAccess(record.domain);
    }

    for (let index = 0; index < normalizedDomains.length; index += 1) {
      const domain = normalizedDomains[index];
      if (resolvedDomains.indexOf(domain) >= 0) {
        continue;
      }
      const file = await this.findCachedIcon(domain);
      if (file === undefined) {
        continue;
      }
      entries.push({
        domain: domain,
        file: file
      });
    }
    return entries;
  }

  async writeIcon(
    domain: string,
    extension: string,
    data: ArrayBuffer,
    metadata: SiteIconCacheMetadata,
    forceReplaceExisting: boolean = false
  ): Promise<SiteIconCachedFile> {
    const safeExtension = this.normalizeExtension(extension);
    const current = await this.findCachedIcon(domain);
    if (!forceReplaceExisting && current !== undefined && this.shouldKeepExistingIcon(current, metadata)) {
      return current;
    }

    const now = Date.now();
    const updatedMetadata: SiteIconCacheMetadata = {
      source: metadata.source,
      iconUrl: metadata.iconUrl,
      extension: safeExtension,
      qualityScore: metadata.qualityScore,
      width: this.normalizeDimension(metadata.width),
      height: this.normalizeDimension(metadata.height),
      updatedAt: metadata.updatedAt > 0 ? metadata.updatedAt : now,
      lastAccessedAt: now
    };
    if (current !== undefined && await this.isSameIconPayload(current.path, data)) {
      const retainedExtension = this.normalizeExtension(
        current.extension ?? this.resolveExtensionFromFileName(this.resolveFileNameFromPath(current.path))
      );
      const metadataOnlyUpdate: SiteIconCacheMetadata = {
        source: updatedMetadata.source,
        iconUrl: updatedMetadata.iconUrl,
        extension: retainedExtension.length > 0 ? retainedExtension : safeExtension,
        qualityScore: updatedMetadata.qualityScore,
        width: updatedMetadata.width,
        height: updatedMetadata.height,
        updatedAt: updatedMetadata.updatedAt,
        lastAccessedAt: updatedMetadata.lastAccessedAt
      };
      await this.writeMetadata(domain, metadataOnlyUpdate);
      return this.applyMetadata({
        path: current.path,
        uri: current.uri,
        cacheState: 'disk'
      }, metadataOnlyUpdate);
    }
    const path = this.buildCachePath(this.getCacheDir(), domain, safeExtension);
    await this.ensureDir(this.getCacheDir());
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, data);
    } finally {
      await fileIo.close(file);
    }
    await this.writeMetadata(domain, updatedMetadata);
    return {
      path: path,
      uri: this.toImageUri(path),
      cacheState: 'network',
      source: updatedMetadata.source,
      iconUrl: updatedMetadata.iconUrl,
      extension: updatedMetadata.extension,
      qualityScore: updatedMetadata.qualityScore,
      width: updatedMetadata.width,
      height: updatedMetadata.height,
      updatedAt: updatedMetadata.updatedAt,
      lastAccessedAt: updatedMetadata.lastAccessedAt
    };
  }

  async writeArkWebFavicon(
    domain: string,
    data: ArrayBuffer,
    qualityScore: number,
    width: number,
    height: number
  ): Promise<SiteIconCachedFile> {
    return this.writeIcon(domain, 'png', data, {
      source: 'arkweb',
      iconUrl: `arkweb://${this.normalizeDomain(domain)}/favicon.png`,
      extension: 'png',
      qualityScore: qualityScore,
      width: this.normalizeDimension(width),
      height: this.normalizeDimension(height),
      updatedAt: Date.now()
    });
  }

  resolveIconExtension(iconUrl: string): string {
    const normalized = iconUrl.toLowerCase();
    if (normalized.includes('.png')) {
      return 'png';
    }
    if (normalized.includes('.jpg') || normalized.includes('.jpeg')) {
      return 'jpg';
    }
    if (normalized.includes('.webp')) {
      return 'webp';
    }
    if (normalized.includes('.svg')) {
      return 'svg';
    }
    return 'png';
  }

  isLikelyImagePayload(data: ArrayBuffer): boolean {
    const bytes = new Uint8Array(data);
    if (bytes.length < 4) {
      return false;
    }

    if (bytes[0] === 0x89 && bytes[1] === 0x50 && bytes[2] === 0x4E && bytes[3] === 0x47) {
      return true;
    }
    if (bytes[0] === 0xFF && bytes[1] === 0xD8 && bytes[2] === 0xFF) {
      return true;
    }
    if (bytes[0] === 0x47 && bytes[1] === 0x49 && bytes[2] === 0x46) {
      return true;
    }
    if (bytes.length >= 12 &&
      bytes[0] === 0x52 && bytes[1] === 0x49 && bytes[2] === 0x46 && bytes[3] === 0x46 &&
      bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) {
      return true;
    }
    if (bytes[0] === 0x00 && bytes[1] === 0x00 && (bytes[2] === 0x01 || bytes[2] === 0x02) && bytes[3] === 0x00) {
      return true;
    }

    return this.isLikelySvgPayload(data);
  }

  isLikelySvgPayload(data: ArrayBuffer): boolean {
    return this.looksLikeSvgPayload(new Uint8Array(data));
  }

  private toImageUri(path: string): string {
    if (path.startsWith('file://')) {
      return path;
    }
    return `file://${path}`;
  }

  private toFilePath(uri: string): string {
    if (uri.startsWith('file://')) {
      return uri.substring(7);
    }
    return uri;
  }

  async pruneCache(options: SiteIconCachePruneOptions): Promise<SiteIconCachePruneResult> {
    const result: SiteIconCachePruneResult = {
      scannedFiles: 0,
      retainedFiles: 0,
      removedFiles: 0,
      scannedBytes: 0,
      retainedBytes: 0,
      removedBytes: 0
    };
    const dir = this.getCacheDir();
    if (!await this.exists(dir)) {
      return result;
    }

    const maxFiles = Math.max(1, Math.floor(options.maxFiles));
    const maxBytes = Math.max(1024, Math.floor(options.maxBytes));
    const candidates = await this.listPruneCandidates(dir);
    result.scannedFiles = candidates.length;
    for (let index = 0; index < candidates.length; index += 1) {
      result.scannedBytes += candidates[index].bytes;
    }

    const sorted = candidates.sort((left: SiteIconCachePruneCandidate, right: SiteIconCachePruneCandidate) => {
      return right.lastUsedAt - left.lastUsedAt;
    });
    for (let index = 0; index < sorted.length; index += 1) {
      const candidate = sorted[index];
      const shouldRetain = result.retainedFiles < maxFiles &&
        result.retainedBytes + candidate.bytes <= maxBytes;
      if (shouldRetain) {
        result.retainedFiles += 1;
        result.retainedBytes += candidate.bytes;
        continue;
      }
      if (await this.removePruneCandidate(candidate)) {
        result.removedFiles += 1;
        result.removedBytes += candidate.bytes;
      }
    }
    return result;
  }

  private async findCachedIconInDir(
    domain: string,
    dir: string,
    cacheState: SiteIconCacheState
  ): Promise<SiteIconCachedFile | undefined> {
    const extensions = ['svg', 'png', 'jpg', 'jpeg', 'webp'];
    const metadata = await this.readMetadata(domain);
    if (metadata !== undefined && metadata.extension.length > 0) {
      const metadataPath = this.buildCachePath(dir, domain, metadata.extension);
      if (await this.isCachedIconUsable(metadataPath)) {
        await this.touchMetadataAccess(domain);
        return this.applyMetadata({
          path: metadataPath,
          uri: this.toImageUri(metadataPath),
          cacheState: cacheState
        }, metadata);
      }
    }

    for (let index = 0; index < extensions.length; index += 1) {
      if (metadata !== undefined && extensions[index] === metadata.extension) {
        continue;
      }
      const path = this.buildCachePath(dir, domain, extensions[index]);
      if (await this.isCachedIconUsable(path)) {
        const cached: SiteIconCachedFile = {
          path: path,
          uri: this.toImageUri(path),
          cacheState: cacheState
        };
        await this.migrateDiscoveredCacheFile(domain, path, extensions[index]);
        return cached;
      }
    }
    return undefined;
  }

  private shouldKeepExistingIcon(current: SiteIconCachedFile, incoming: SiteIconCacheMetadata): boolean {
    if (current.qualityScore === undefined) {
      return incoming.qualityScore < MIN_UNKNOWN_CACHE_REPLACEMENT_SCORE;
    }
    return current.qualityScore >= incoming.qualityScore;
  }

  private applyMetadata(
    cached: SiteIconCachedFile,
    metadata: SiteIconCacheMetadata | undefined
  ): SiteIconCachedFile {
    if (metadata === undefined) {
      return cached;
    }
    return {
      path: cached.path,
      uri: cached.uri,
      cacheState: cached.cacheState,
      source: metadata.source,
      iconUrl: metadata.iconUrl,
      extension: metadata.extension,
      qualityScore: metadata.qualityScore,
      width: metadata.width,
      height: metadata.height,
      updatedAt: metadata.updatedAt,
      lastAccessedAt: metadata.lastAccessedAt
    };
  }

  private async readMetadata(domain: string): Promise<SiteIconCacheMetadata | undefined> {
    const databaseRecord = await this.readDatabaseMetadata(domain);
    if (databaseRecord !== undefined) {
      return databaseRecord;
    }

    const path = this.buildMetadataPath(this.getCacheDir(), domain);
    const legacyMetadata = await this.readMetadataFromPath(path);
    if (legacyMetadata !== undefined) {
      await this.writeDatabaseMetadata(domain, legacyMetadata, this.buildCachePath(this.getCacheDir(), domain,
        legacyMetadata.extension));
    }
    return legacyMetadata;
  }

  private async readMetadataFromPath(path: string): Promise<SiteIconCacheMetadata | undefined> {
    if (!await this.exists(path)) {
      return undefined;
    }

    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const stat = await fileIo.stat(path);
        const size = Math.max(0, Math.floor(stat.size));
        if (size <= 0 || size > 4096) {
          return undefined;
        }
        const buffer = new ArrayBuffer(size);
        const readLength = await fileIo.read(file.fd, buffer);
        if (readLength <= 0) {
          return undefined;
        }
        const text = this.textDecoder.decodeToString(new Uint8Array(buffer, 0, readLength)).trim();
        if (text.length === 0) {
          return undefined;
        }
        return this.normalizeMetadata(JSON.parse(text) as SiteIconCacheMetadata);
      } finally {
        await fileIo.close(file);
      }
    } catch (_error) {
      return undefined;
    }
  }

  private async writeMetadata(domain: string, metadata: SiteIconCacheMetadata): Promise<void> {
    const path = this.buildMetadataPath(this.getCacheDir(), domain);
    const payload = this.textEncoder.encodeInto(JSON.stringify(metadata));
    const file = await fileIo.open(path, fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
    try {
      await fileIo.write(file.fd, payload.buffer as ArrayBuffer);
    } finally {
      await fileIo.close(file);
    }
    await this.writeDatabaseMetadata(domain, metadata, this.buildCachePath(this.getCacheDir(), domain,
      metadata.extension));
  }

  private async readDatabaseMetadata(domain: string): Promise<SiteIconCacheMetadata | undefined> {
    try {
      const record = await this.database.findSiteIconMetadata(this.normalizeDomain(domain));
      if (record === undefined) {
        return undefined;
      }
      return this.normalizeMetadata({
        source: record.source,
        iconUrl: record.iconUrl,
        extension: record.extension,
        qualityScore: record.qualityScore,
        width: record.width,
        height: record.height,
        updatedAt: record.updatedAt,
        lastAccessedAt: record.lastAccessedAt
      });
    } catch (_error) {
      return undefined;
    }
  }

  private async listDatabaseMetadataByDomains(domains: string[]): Promise<SiteIconMetadataRecord[]> {
    try {
      return await this.database.listSiteIconMetadataByDomains(domains);
    } catch (_error) {
      return [];
    }
  }

  private async writeDatabaseMetadata(
    domain: string,
    metadata: SiteIconCacheMetadata,
    filePath: string
  ): Promise<void> {
    const normalizedMetadata = this.normalizeMetadata(metadata);
    if (normalizedMetadata === undefined) {
      return;
    }

    const record: SiteIconMetadataRecord = {
      domain: this.normalizeDomain(domain),
      iconUrl: normalizedMetadata.iconUrl,
      source: normalizedMetadata.source,
      extension: normalizedMetadata.extension,
      fileUri: this.toImageUri(filePath),
      qualityScore: normalizedMetadata.qualityScore,
      width: normalizedMetadata.width ?? 0,
      height: normalizedMetadata.height ?? 0,
      lastAccessedAt: normalizedMetadata.lastAccessedAt ?? normalizedMetadata.updatedAt,
      updatedAt: normalizedMetadata.updatedAt
    };
    try {
      await this.database.upsertSiteIconMetadata(record);
    } catch (_error) {
    }
  }

  private async touchMetadataAccess(domain: string): Promise<void> {
    try {
      await this.database.touchSiteIconMetadata(this.normalizeDomain(domain), Date.now());
    } catch (_error) {
    }
  }

  private async migrateDiscoveredCacheFile(domain: string, path: string, extension: string): Promise<void> {
    const metadata = await this.readMetadataFromPath(this.buildMetadataPath(this.getCacheDir(), domain));
    if (metadata !== undefined) {
      await this.writeDatabaseMetadata(domain, {
        source: metadata.source,
        iconUrl: metadata.iconUrl,
        extension: this.normalizeExtension(extension),
        qualityScore: metadata.qualityScore,
        width: metadata.width,
        height: metadata.height,
        updatedAt: metadata.updatedAt,
        lastAccessedAt: Date.now()
      }, path);
    }
  }

  private normalizeMetadata(metadata: SiteIconCacheMetadata): SiteIconCacheMetadata | undefined {
    const extension = this.normalizeExtension(metadata.extension ?? '');
    if (metadata.iconUrl === undefined || metadata.iconUrl.trim().length === 0 ||
      extension.length === 0 ||
      metadata.qualityScore === undefined ||
      metadata.updatedAt === undefined || metadata.updatedAt <= 0 ||
      !this.isKnownSource(metadata.source)) {
      return undefined;
    }
    return {
      source: metadata.source,
      iconUrl: metadata.iconUrl.trim(),
      extension: extension,
      qualityScore: metadata.qualityScore,
      width: this.normalizeDimension(metadata.width),
      height: this.normalizeDimension(metadata.height),
      updatedAt: metadata.updatedAt,
      lastAccessedAt: metadata.lastAccessedAt !== undefined && metadata.lastAccessedAt > 0
        ? metadata.lastAccessedAt
        : metadata.updatedAt
    };
  }

  private async listPruneCandidates(dir: string): Promise<SiteIconCachePruneCandidate[]> {
    const candidates: SiteIconCachePruneCandidate[] = [];
    const indexedPaths: string[] = [];
    await this.appendDatabasePruneCandidates(dir, candidates, indexedPaths);
    let fileNames: string[] = [];
    try {
      fileNames = await fileIo.listFile(dir);
    } catch (_error) {
      return candidates;
    }

    for (let index = 0; index < fileNames.length; index += 1) {
      const fileName = fileNames[index];
      if (!this.isCacheImageFileName(fileName)) {
        continue;
      }
      const path = `${dir}/${fileName}`;
      if (indexedPaths.indexOf(path) >= 0) {
        continue;
      }
      try {
        const stat = await fileIo.stat(path);
        if (stat.isDirectory()) {
          continue;
        }
        const metadataPath = this.resolveMetadataPathForCacheFile(dir, fileName);
        const metadata = metadataPath.length > 0 ? await this.readMetadataFromPath(metadataPath) : undefined;
        const extension = this.resolveExtensionFromFileName(fileName);
        const candidate: SiteIconCachePruneCandidate = {
          domain: this.resolveDomainFromCacheFileName(fileName),
          path: path,
          metadataPath: metadataPath,
          extension: extension,
          metadataExtension: metadata?.extension ?? '',
          bytes: Math.max(0, Math.floor(stat.size)),
          lastUsedAt: metadata?.lastAccessedAt ?? metadata?.updatedAt ?? stat.mtime
        };
        candidates.push(candidate);
      } catch (_error) {
      }
    }
    return candidates;
  }

  private async appendDatabasePruneCandidates(
    dir: string,
    candidates: SiteIconCachePruneCandidate[],
    indexedPaths: string[]
  ): Promise<void> {
    let records: SiteIconMetadataRecord[] = [];
    try {
      records = await this.database.listSiteIconMetadataForPrune();
    } catch (_error) {
      records = [];
    }

    for (let index = 0; index < records.length; index += 1) {
      const record = records[index];
      const path = this.toFilePath(record.fileUri);
      if (!this.isPathInDir(path, dir)) {
        await this.database.deleteSiteIconMetadata(record.domain);
        continue;
      }
      try {
        const stat = await fileIo.stat(path);
        if (stat.isDirectory()) {
          await this.database.deleteSiteIconMetadata(record.domain);
          continue;
        }
        const fileName = this.resolveFileNameFromPath(path);
        const extension = this.resolveExtensionFromFileName(fileName);
        if (!this.isCacheImageFileName(fileName)) {
          await this.database.deleteSiteIconMetadata(record.domain);
          continue;
        }
        candidates.push({
          domain: record.domain,
          path: path,
          metadataPath: this.resolveMetadataPathForCacheFile(dir, fileName),
          extension: extension,
          metadataExtension: this.normalizeExtension(record.extension),
          bytes: Math.max(0, Math.floor(stat.size)),
          lastUsedAt: record.lastAccessedAt > 0 ? record.lastAccessedAt : record.updatedAt
        });
        indexedPaths.push(path);
      } catch (_error) {
        await this.database.deleteSiteIconMetadata(record.domain);
      }
    }
  }

  private async removePruneCandidate(candidate: SiteIconCachePruneCandidate): Promise<boolean> {
    const removed = await this.deleteIfExists(candidate.path);
    if (removed && candidate.metadataPath.length > 0 && candidate.extension === candidate.metadataExtension) {
      await this.deleteIfExists(candidate.metadataPath);
    }
    if (removed && candidate.domain.length > 0) {
      await this.database.deleteSiteIconMetadata(candidate.domain);
    }
    return removed;
  }

  private async deleteIfExists(path: string): Promise<boolean> {
    try {
      if (!await fileIo.access(path)) {
        return false;
      }
      await fileIo.unlink(path);
      return true;
    } catch (_error) {
      return false;
    }
  }

  private isCacheImageFileName(fileName: string): boolean {
    const extension = this.resolveExtensionFromFileName(fileName);
    return extension === 'svg' || extension === 'png' || extension === 'jpg' || extension === 'webp';
  }

  private resolveMetadataPathForCacheFile(dir: string, fileName: string): string {
    const extensionStart = fileName.lastIndexOf('.');
    if (extensionStart <= 0 || !fileName.startsWith(`${SITE_ICON_CACHE_VERSION}-`)) {
      return '';
    }
    return `${dir}/${fileName.substring(0, extensionStart)}.json`;
  }

  private resolveExtensionFromFileName(fileName: string): string {
    const extensionStart = fileName.lastIndexOf('.');
    if (extensionStart < 0 || extensionStart >= fileName.length - 1) {
      return '';
    }
    return this.normalizeExtension(fileName.substring(extensionStart + 1));
  }

  private resolveDomainFromCacheFileName(fileName: string): string {
    const extensionStart = fileName.lastIndexOf('.');
    if (extensionStart <= 0 || !fileName.startsWith(`${SITE_ICON_CACHE_VERSION}-`)) {
      return '';
    }
    return this.normalizeDomain(fileName.substring(SITE_ICON_CACHE_VERSION.length + 1, extensionStart));
  }

  private resolveFileNameFromPath(path: string): string {
    const slashIndex = path.lastIndexOf('/');
    if (slashIndex < 0 || slashIndex >= path.length - 1) {
      return path;
    }
    return path.substring(slashIndex + 1);
  }

  private isPathInCacheDir(path: string): boolean {
    return this.isPathInDir(path, this.getCacheDir());
  }

  private isPathInDir(path: string, dir: string): boolean {
    const normalizedPath = path.trim();
    const normalizedDir = dir.trim();
    return normalizedPath === normalizedDir || normalizedPath.startsWith(`${normalizedDir}/`);
  }

  private isKnownSource(source: SiteIconCandidateSource): boolean {
    switch (source) {
      case 'arkweb':
      case 'override':
      case 'manifest':
      case 'appleTouch':
      case 'documentIcon':
      case 'rootAppleTouch':
      case 'rootIcon':
      case 'remoteFallback':
        return true;
      default:
        return false;
    }
  }

  private async isCachedIconUsable(path: string): Promise<boolean> {
    if (!await this.exists(path)) {
      return false;
    }
    const sample = await this.readIconSample(path);
    return sample.byteLength > 0 && this.isLikelyImagePayload(sample);
  }

  private async readIconSample(path: string): Promise<ArrayBuffer> {
    try {
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const buffer = new ArrayBuffer(512);
        const readLength = await fileIo.read(file.fd, buffer);
        if (readLength <= 0) {
          return new ArrayBuffer(0);
        }
        return buffer.slice(0, readLength);
      } finally {
        await fileIo.close(file);
      }
    } catch (_error) {
      return new ArrayBuffer(0);
    }
  }

  private async isSameIconPayload(path: string, incoming: ArrayBuffer): Promise<boolean> {
    if (incoming.byteLength <= 0 || !await this.exists(path)) {
      return false;
    }
    try {
      const stat = await fileIo.stat(path);
      const size = Math.max(0, Math.floor(stat.size));
      if (size !== incoming.byteLength) {
        return false;
      }
      const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
      try {
        const existing = new ArrayBuffer(size);
        const readLength = await fileIo.read(file.fd, existing);
        if (readLength !== size) {
          return false;
        }
        const existingBytes = new Uint8Array(existing);
        const incomingBytes = new Uint8Array(incoming);
        for (let index = 0; index < size; index += 1) {
          if (existingBytes[index] !== incomingBytes[index]) {
            return false;
          }
        }
        return true;
      } finally {
        await fileIo.close(file);
      }
    } catch (_error) {
      return false;
    }
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

  private looksLikeSvgPayload(bytes: Uint8Array): boolean {
    const limit = Math.min(bytes.length, 256);
    let snippet = '';
    for (let index = 0; index < limit; index += 1) {
      const value = bytes[index];
      if (value === 0) {
        return false;
      }
      snippet += String.fromCharCode(value);
    }
    const normalized = snippet.trim().toLowerCase();
    if (normalized.startsWith('<!doctype html') || normalized.startsWith('<html') ||
      normalized.startsWith('{') || normalized.startsWith('[')) {
      return false;
    }
    return normalized.indexOf('<svg') >= 0;
  }

  private buildCachePath(dir: string, domain: string, extension: string): string {
    return `${dir}/${SITE_ICON_CACHE_VERSION}-${this.buildCacheFileStem(domain)}.${this.normalizeExtension(extension)}`;
  }

  private buildMetadataPath(dir: string, domain: string): string {
    return `${dir}/${SITE_ICON_CACHE_VERSION}-${this.buildCacheFileStem(domain)}.json`;
  }

  private getCacheDir(): string {
    return `${AppRuntimeContext.getApplicationContext().cacheDir}/${SITE_ICON_CACHE_DIR_NAME}`;
  }

  private buildCacheFileStem(domain: string): string {
    return this.normalizeDomain(domain).replace(/[^a-z0-9.-]/g, '_');
  }

  private normalizeDomain(domain: string): string {
    let normalized = domain.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    return normalized;
  }

  private normalizeDomains(domains: string[]): string[] {
    const normalizedDomains: string[] = [];
    for (let index = 0; index < domains.length; index += 1) {
      const domain = this.normalizeDomain(domains[index]);
      if (domain.length === 0 || normalizedDomains.indexOf(domain) >= 0) {
        continue;
      }
      normalizedDomains.push(domain);
    }
    return normalizedDomains;
  }

  private normalizeExtension(extension: string): string {
    const normalized = extension.trim().toLowerCase().replace(/[^a-z0-9]/g, '');
    if (normalized === 'jpeg') {
      return 'jpg';
    }
    if (normalized === 'svg' || normalized === 'png' || normalized === 'jpg' || normalized === 'webp') {
      return normalized;
    }
    return 'png';
  }

  private normalizeDimension(value?: number): number {
    if (value === undefined || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }
}
