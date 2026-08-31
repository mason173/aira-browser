import {
  InstalledUserScriptState,
  resolveUserScriptPackageSource,
  UserScriptPackageCandidate
} from '../../features/userscripts/UserScriptMetadataModels';
import { UserScriptMetadataParserService } from './UserScriptMetadataParserService';
import {
  UserScriptSourceFetchResult,
  UserScriptSourceFetchService
} from './UserScriptSourceFetchService';

export type UserScriptUpdateStatus =
  'unsupported' |
  'up-to-date' |
  'available' |
  'updated' |
  'failed';

export interface UserScriptUpdateResult {
  scriptId: string;
  scriptName: string;
  status: UserScriptUpdateStatus;
  previousVersion: string;
  nextVersion: string;
  checkedAt: number;
  message: string;
  warnings: string[];
}

export interface UserScriptUpdatePackageResult extends UserScriptUpdateResult {
  candidate?: UserScriptPackageCandidate;
}

interface UserScriptRemoteMetadata {
  version: string;
  downloadUrl: string;
}

export class UserScriptUpdateService {
  private sourceFetchService: UserScriptSourceFetchService;
  private parser: UserScriptMetadataParserService;

  constructor(
    sourceFetchService: UserScriptSourceFetchService = new UserScriptSourceFetchService(),
    parser: UserScriptMetadataParserService = new UserScriptMetadataParserService()
  ) {
    this.sourceFetchService = sourceFetchService;
    this.parser = parser;
  }

  async checkScript(record: InstalledUserScriptState, checkedAt: number = Date.now()): Promise<UserScriptUpdateResult> {
    if (!this.canCheckUpdates(record)) {
      return this.buildResult(record, 'unsupported', checkedAt, '未提供更新地址');
    }

    const metadataUrl = this.resolveMetadataUrl(record);
    const metadataFetchResult: UserScriptSourceFetchResult =
      await this.sourceFetchService.fetchSource(metadataUrl, true);
    if (!metadataFetchResult.ok) {
      return this.buildResult(record, 'failed', checkedAt, metadataFetchResult.errorMessage);
    }

    const remoteMetadata = this.parseRemoteMetadata(metadataFetchResult.source);
    const remoteVersion = remoteMetadata.version.length > 0 ? remoteMetadata.version : record.version;
    const needsResourceRematerialization = this.needsResourceRematerialization(record);
    if (this.compareVersions(remoteVersion, record.version) <= 0 && !needsResourceRematerialization) {
      return this.buildResult(record, 'up-to-date', checkedAt, '已是最新版本', remoteVersion);
    }
    if (this.resolveDownloadUrl(record, remoteMetadata).length === 0) {
      return this.buildResult(record, 'failed', checkedAt, '发现新版本，但没有下载地址', remoteVersion);
    }
    return this.buildResult(
      record,
      'available',
      checkedAt,
      needsResourceRematerialization && this.compareVersions(remoteVersion, record.version) <= 0
        ? '脚本资源需要兼容性更新'
        : `发现新版本 ${record.version} -> ${remoteVersion}`,
      remoteVersion
    );
  }

  async updateScript(
    record: InstalledUserScriptState,
    checkedAt: number = Date.now()
  ): Promise<UserScriptUpdatePackageResult> {
    if (!this.canCheckUpdates(record)) {
      return this.buildResult(record, 'unsupported', checkedAt, '脚本没有提供更新地址。');
    }

    const metadataUrl = this.resolveMetadataUrl(record);
    const metadataFetchResult: UserScriptSourceFetchResult =
      await this.sourceFetchService.fetchSource(metadataUrl, true);
    if (!metadataFetchResult.ok) {
      return this.buildResult(record, 'failed', checkedAt, metadataFetchResult.errorMessage);
    }

    const remoteMetadata = this.parseRemoteMetadata(metadataFetchResult.source);
    const remoteVersion = remoteMetadata.version.length > 0 ? remoteMetadata.version : record.version;
    const needsResourceRematerialization = this.needsResourceRematerialization(record);
    if (this.compareVersions(remoteVersion, record.version) <= 0 && !needsResourceRematerialization) {
      return this.buildResult(record, 'up-to-date', checkedAt, '已是最新版本。', remoteVersion);
    }

    const downloadUrl = this.resolveDownloadUrl(record, remoteMetadata);
    if (downloadUrl.length === 0) {
      return this.buildResult(record, 'failed', checkedAt, '发现新版本，但脚本没有提供下载地址。', remoteVersion);
    }

    const sourceFetchResult: UserScriptSourceFetchResult = await this.sourceFetchService.fetchSource(downloadUrl, true);
    if (!sourceFetchResult.ok) {
      return this.buildResult(record, 'failed', checkedAt, sourceFetchResult.errorMessage, remoteVersion);
    }

    const parsedSourceUrl = record.sourceUrl.length > 0 ? record.sourceUrl : downloadUrl;
    const parsed = this.parser.parse(
      sourceFetchResult.source,
      resolveUserScriptPackageSource(record.installSource, parsedSourceUrl),
      parsedSourceUrl
    );
    if (!parsed.valid || parsed.candidate === undefined) {
      return this.buildResult(
        record,
        'failed',
        checkedAt,
        parsed.errorMessage.length > 0 ? parsed.errorMessage : '新版脚本格式不正确。',
        remoteVersion,
        parsed.warnings
      );
    }

    return {
      scriptId: record.id,
      scriptName: parsed.candidate.name,
      status: 'updated',
      previousVersion: record.version,
      nextVersion: parsed.candidate.version,
      checkedAt: checkedAt,
      message: needsResourceRematerialization && parsed.candidate.version === record.version
        ? '已刷新脚本资源'
        : `已更新到 ${parsed.candidate.version}`,
      warnings: parsed.warnings,
      candidate: parsed.candidate
    };
  }

  canCheckUpdates(record: InstalledUserScriptState): boolean {
    return record.updateUrl.trim().length > 0 || record.downloadUrl.trim().length > 0;
  }

  private needsResourceRematerialization(record: InstalledUserScriptState): boolean {
    return record.resources.some((resource): boolean => {
      return resource.contentBase64 === undefined;
    });
  }

  private compareVersions(left: string, right: string): number {
    const leftParts = this.tokenizeVersion(left);
    const rightParts = this.tokenizeVersion(right);
    const length = Math.max(leftParts.length, rightParts.length);
    for (let index = 0; index < length; index++) {
      const leftPart = leftParts[index] ?? '0';
      const rightPart = rightParts[index] ?? '0';
      const leftNumber = Number(leftPart);
      const rightNumber = Number(rightPart);
      const bothNumeric = !Number.isNaN(leftNumber) && !Number.isNaN(rightNumber);
      if (bothNumeric && leftNumber !== rightNumber) {
        return leftNumber > rightNumber ? 1 : -1;
      }
      if (!bothNumeric && leftPart !== rightPart) {
        return leftPart > rightPart ? 1 : -1;
      }
    }
    return 0;
  }

  private resolveMetadataUrl(record: InstalledUserScriptState): string {
    return record.updateUrl.trim().length > 0 ? record.updateUrl.trim() : record.downloadUrl.trim();
  }

  private resolveDownloadUrl(record: InstalledUserScriptState, metadata: UserScriptRemoteMetadata): string {
    if (metadata.downloadUrl.length > 0) {
      return metadata.downloadUrl;
    }
    if (record.downloadUrl.trim().length > 0) {
      return record.downloadUrl.trim();
    }
    return '';
  }

  private parseRemoteMetadata(source: string): UserScriptRemoteMetadata {
    return {
      version: this.readMetadataValue(source, 'version'),
      downloadUrl: this.readMetadataValue(source, 'downloadURL')
    };
  }

  private readMetadataValue(source: string, key: string): string {
    const prefix = `// @${key}`;
    const lines = source.split('\n');
    for (let index = 0; index < lines.length; index++) {
      const trimmed = lines[index].trim();
      if (trimmed.startsWith(prefix)) {
        return trimmed.slice(prefix.length).trim();
      }
    }
    return '';
  }

  private tokenizeVersion(value: string): string[] {
    const parts = value.trim().split(/[^0-9A-Za-z]+/);
    return parts.map((part: string) => part.trim()).filter((part: string) => part.length > 0);
  }

  private buildResult(
    record: InstalledUserScriptState,
    status: UserScriptUpdateStatus,
    checkedAt: number,
    message: string,
    nextVersion: string = '',
    warnings: string[] = []
  ): UserScriptUpdateResult {
    return {
      scriptId: record.id,
      scriptName: record.name,
      status: status,
      previousVersion: record.version,
      nextVersion: nextVersion.length > 0 ? nextVersion : record.version,
      checkedAt: checkedAt,
      message: message,
      warnings: warnings
    };
  }

}
