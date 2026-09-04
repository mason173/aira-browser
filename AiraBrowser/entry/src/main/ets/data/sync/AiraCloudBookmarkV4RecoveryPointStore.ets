import { util } from '@kit.ArkTS';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo } from '@kit.CoreFileKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
  AiraCloudBookmarkV4RecoveryPoint,
  AiraCloudBookmarkV4RecoveryPointCreateRequest
} from '../../common/models/AiraCloudBookmarkV4BootstrapModels';

const RECOVERY_DIRECTORY_NAME: string = 'aira-cloud-bookmark-v4-recovery';
const BACKUP_SUFFIX: string = '.aira-backup';
const METADATA_SUFFIX: string = '.meta.json';
const TEMP_SUFFIX: string = '.tmp';
const RETENTION_MS: number = 30 * 24 * 60 * 60 * 1000;
const MIN_RECENT_RECOVERY_POINTS: number = 3;
const MAX_BACKUP_BYTES: number = 64 * 1024 * 1024;

export interface AiraCloudBookmarkV4RecoveryFileAdapter {
  ensureDirectory(): Promise<void>;
  writeAndSync(fileName: string, bytes: Uint8Array): Promise<void>;
  rename(sourceName: string, targetName: string): Promise<void>;
  read(fileName: string): Promise<Uint8Array>;
  list(): Promise<string[]>;
  remove(fileName: string): Promise<void>;
}

class SandboxAiraCloudBookmarkV4RecoveryFileAdapter implements
  AiraCloudBookmarkV4RecoveryFileAdapter {
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');

  async ensureDirectory(): Promise<void> {
    const directory = this.directory();
    if (!await fileIo.access(directory)) {
      await fileIo.mkdir(directory, true);
    }
  }

  async writeAndSync(fileName: string, bytes: Uint8Array): Promise<void> {
    const path = this.path(fileName);
    let file: fileIo.File | undefined = undefined;
    try {
      file = fileIo.openSync(
        path,
        fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC
      );
      const buffer = new ArrayBuffer(bytes.byteLength);
      new Uint8Array(buffer).set(bytes);
      const written = fileIo.writeSync(file.fd, buffer);
      if (written !== bytes.byteLength) {
        throw new Error('恢复点文件写入不完整。');
      }
      fileIo.fsyncSync(file.fd);
    } finally {
      if (file !== undefined) {
        fileIo.closeSync(file);
      }
    }
  }

  async rename(sourceName: string, targetName: string): Promise<void> {
    const targetPath = this.path(targetName);
    try {
      await fileIo.unlink(targetPath);
    } catch (_error) {
    }
    await fileIo.rename(this.path(sourceName), targetPath);
  }

  async read(fileName: string): Promise<Uint8Array> {
    return this.encoder.encodeInto(fileIo.readTextSync(this.path(fileName)));
  }

  async list(): Promise<string[]> {
    try {
      return await fileIo.listFile(this.directory());
    } catch (_error) {
      return [];
    }
  }

  async remove(fileName: string): Promise<void> {
    try {
      await fileIo.unlink(this.path(fileName));
    } catch (_error) {
    }
  }

  private directory(): string {
    return `${AppRuntimeContext.getApplicationContext().filesDir}/${RECOVERY_DIRECTORY_NAME}`;
  }

  private path(fileName: string): string {
    return `${this.directory()}/${fileName}`;
  }
}

export class AiraCloudBookmarkV4RecoveryPointStore {
  private readonly adapter: AiraCloudBookmarkV4RecoveryFileAdapter;
  private readonly nowProvider: () => number;
  private readonly idProvider: () => string;
  private readonly protectedRecoveryPointIdsProvider: () => Promise<string[]>;
  private readonly encoder: util.TextEncoder = util.TextEncoder.create('utf-8');
  private readonly decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
  private mutationTask: Promise<void> = Promise.resolve();

  constructor(
    adapter?: AiraCloudBookmarkV4RecoveryFileAdapter,
    nowProvider: () => number = (): number => Date.now(),
    idProvider?: () => string,
    protectedRecoveryPointIdsProvider: () => Promise<string[]> = (): Promise<string[]> => Promise.resolve([])
  ) {
    this.adapter = adapter ?? new SandboxAiraCloudBookmarkV4RecoveryFileAdapter();
    this.nowProvider = nowProvider;
    this.idProvider = idProvider ?? ((): string => {
      return `v4-${this.nowProvider()}-${Math.floor(Math.random() * 1000000000)}`;
    });
    this.protectedRecoveryPointIdsProvider = protectedRecoveryPointIdsProvider;
  }

  create(request: AiraCloudBookmarkV4RecoveryPointCreateRequest): Promise<AiraCloudBookmarkV4RecoveryPoint> {
    let result: AiraCloudBookmarkV4RecoveryPoint | undefined = undefined;
    return this.enqueue(async (): Promise<void> => {
      result = await this.createNow(request);
    }).then((): AiraCloudBookmarkV4RecoveryPoint => {
      if (result === undefined) {
        throw new Error('恢复点创建失败。');
      }
      return result;
    });
  }

  async readVerifiedPayload(
    backupId: string,
    expectedUid: string = '',
    expectedSha256: string = ''
  ): Promise<string> {
    const safeId = this.requireSafeId(backupId);
    const metadata = await this.readMetadata(safeId);
    if ((expectedUid.length > 0 && metadata.uid !== expectedUid.trim()) ||
      (expectedSha256.length > 0 && metadata.sha256 !== expectedSha256.trim())) {
      throw new Error('书签恢复点与当前升级记录不匹配。');
    }
    const bytes = await this.adapter.read(metadata.fileName);
    if (bytes.byteLength !== metadata.byteLength || this.sha256Hex(bytes) !== metadata.sha256) {
      throw new Error('书签恢复点校验失败。');
    }
    return this.decoder.decodeToString(bytes);
  }

  private async createNow(
    request: AiraCloudBookmarkV4RecoveryPointCreateRequest
  ): Promise<AiraCloudBookmarkV4RecoveryPoint> {
    const uid = request.uid.trim();
    if (uid.length === 0 || request.payload.length === 0) {
      throw new Error('无法为当前账号创建书签恢复点。');
    }
    const bytes = this.encoder.encodeInto(request.payload);
    if (bytes.byteLength > MAX_BACKUP_BYTES) {
      throw new Error('书签恢复点超过大小限制。');
    }
    const backupId = this.requireSafeId(this.idProvider());
    const fileName = `${backupId}${BACKUP_SUFFIX}`;
    const temporaryFileName = `${fileName}${TEMP_SUFFIX}`;
    const metadataFileName = `${backupId}${METADATA_SUFFIX}`;
    const temporaryMetadataFileName = `${metadataFileName}${TEMP_SUFFIX}`;
    const point: AiraCloudBookmarkV4RecoveryPoint = {
      backupId: backupId,
      uid: uid,
      protocol: AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL,
      reason: 'aira_cloud_v4_bootstrap',
      status: 'ready',
      fileName: fileName,
      sha256: this.sha256Hex(bytes),
      byteLength: bytes.byteLength,
      remoteCommitId: request.remoteCommitId.trim(),
      createdAt: Math.max(0, Math.floor(this.nowProvider()))
    };

    await this.adapter.ensureDirectory();
    await this.adapter.writeAndSync(temporaryFileName, bytes);
    await this.adapter.rename(temporaryFileName, fileName);
    const committedBytes = await this.adapter.read(fileName);
    if (committedBytes.byteLength !== point.byteLength || this.sha256Hex(committedBytes) !== point.sha256) {
      throw new Error('书签恢复点写入后校验失败。');
    }
    const metadataBytes = this.encoder.encodeInto(JSON.stringify(point));
    await this.adapter.writeAndSync(temporaryMetadataFileName, metadataBytes);
    await this.adapter.rename(temporaryMetadataFileName, metadataFileName);
    const verifiedMetadata = await this.readMetadata(backupId);
    if (verifiedMetadata.sha256 !== point.sha256 || verifiedMetadata.uid !== point.uid) {
      throw new Error('书签恢复点元数据校验失败。');
    }
    await this.pruneNow();
    return point;
  }

  private enqueue(operation: () => Promise<void>): Promise<void> {
    const next = this.mutationTask.then(operation, operation);
    this.mutationTask = next.catch((): void => {});
    return next;
  }

  private async readMetadata(backupId: string): Promise<AiraCloudBookmarkV4RecoveryPoint> {
    const bytes = await this.adapter.read(`${backupId}${METADATA_SUFFIX}`);
    let value: AiraCloudBookmarkV4RecoveryPoint;
    try {
      value = JSON.parse(this.decoder.decodeToString(bytes)) as AiraCloudBookmarkV4RecoveryPoint;
    } catch (_error) {
      throw new Error('书签恢复点元数据无效。');
    }
    if (value.backupId !== backupId || value.uid.trim().length === 0 ||
      value.protocol !== AIRA_CLOUD_BOOKMARK_V4_BOOTSTRAP_PROTOCOL ||
      value.reason !== 'aira_cloud_v4_bootstrap' || value.status !== 'ready' ||
      value.fileName !== `${backupId}${BACKUP_SUFFIX}` || !/^[a-f0-9]{64}$/.test(value.sha256) ||
      !Number.isFinite(value.byteLength) || value.byteLength < 0 || value.byteLength > MAX_BACKUP_BYTES ||
      !Number.isFinite(value.createdAt) || value.createdAt < 0) {
      throw new Error('书签恢复点元数据无效。');
    }
    return value;
  }

  private async pruneNow(): Promise<void> {
    let protectedRecoveryPointIds: string[];
    try {
      protectedRecoveryPointIds = (await this.protectedRecoveryPointIdsProvider())
        .map((backupId: string): string => backupId.trim())
        .filter((backupId: string): boolean => backupId.length > 0);
    } catch (_error) {
      return;
    }
    const names = await this.adapter.list();
    const metadataNames = names.filter((name: string): boolean => name.endsWith(METADATA_SUFFIX));
    const points: AiraCloudBookmarkV4RecoveryPoint[] = [];
    for (let index = 0; index < metadataNames.length; index += 1) {
      const backupId = metadataNames[index].substring(0, metadataNames[index].length - METADATA_SUFFIX.length);
      try {
        points.push(await this.readMetadata(backupId));
      } catch (_error) {
        await this.adapter.remove(metadataNames[index]);
      }
    }
    points.sort((left: AiraCloudBookmarkV4RecoveryPoint,
      right: AiraCloudBookmarkV4RecoveryPoint): number => right.createdAt - left.createdAt);
    const oldestRetainedAt = this.nowProvider() - RETENTION_MS;
    for (let index = 0; index < points.length; index += 1) {
      const point = points[index];
      if (protectedRecoveryPointIds.indexOf(point.backupId) >= 0 ||
        index < MIN_RECENT_RECOVERY_POINTS || point.createdAt >= oldestRetainedAt) {
        continue;
      }
      await this.adapter.remove(point.fileName);
      await this.adapter.remove(`${point.backupId}${METADATA_SUFFIX}`);
    }
  }

  private requireSafeId(value: string): string {
    const id = value.trim();
    if (id.length === 0 || id.length > 160 || !/^[A-Za-z0-9._-]+$/.test(id)) {
      throw new Error('书签恢复点标识无效。');
    }
    return id;
  }

  private sha256Hex(bytes: Uint8Array): string {
    const digest = cryptoFramework.createMd('SHA256');
    digest.updateSync({ data: bytes });
    const hashedBytes = (digest.digestSync() as cryptoFramework.DataBlob).data;
    let result = '';
    for (let index = 0; index < hashedBytes.length; index += 1) {
      result += hashedBytes[index].toString(16).padStart(2, '0');
    }
    return result;
  }
}
