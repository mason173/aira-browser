import { Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { CustomHomepagePackageImportError } from './CustomHomepageFileService';

const WANT_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';
const WANT_ACTION_SEND_DATA: string = 'ohos.want.action.sendData';
const ZIP_UTD: string = 'general.zip-archive';
const ZIP_MIME_TYPE: string = 'application/zip';

type CustomHomepageExternalSourceErrorCode = 'multiple_files' | 'missing_file' | 'unsupported_type';

class CustomHomepageExternalSourceError extends Error {
  readonly code: CustomHomepageExternalSourceErrorCode;

  constructor(code: CustomHomepageExternalSourceErrorCode, message: string) {
    super(message);
    this.name = 'CustomHomepageExternalSourceError';
    this.code = code;
  }
}

export class CustomHomepageExternalImportService {
  isCandidate(want: Want): boolean {
    const action = String(want.action ?? '').trim();
    if (action === WANT_ACTION_SEND_DATA) {
      return true;
    }
    if (action !== WANT_ACTION_VIEW_DATA) {
      return false;
    }
    return this.isZipDescriptor(String(want.type ?? '')) || this.isZipUri(String(want.uri ?? ''));
  }

  async resolveSourceUri(want: Want): Promise<string> {
    const action = String(want.action ?? '').trim();
    if (action === WANT_ACTION_SEND_DATA) {
      return await this.resolveSharedSourceUri(want);
    }
    const uri = String(want.uri ?? '').trim();
    this.ensureUsableZipSource(uri, String(want.type ?? ''));
    return uri;
  }

  buildUserFacingError(error: Object | undefined): string {
    const message = this.stringifyError(error);
    if (error instanceof CustomHomepagePackageImportError) {
      if (error.code === 'missing_manifest') {
        return '这不是 Aira 主页包。Aira 不是解压缩工具，仅支持根目录包含 aira-homepage.json 的 ZIP 主页包。';
      }
      if (error.code === 'invalid_zip') {
        return '这不是有效的 Aira 主页包。请确认文件是完整的 ZIP 主页包后重试。';
      }
    }
    if (error instanceof CustomHomepageExternalSourceError) {
      return error.message;
    }
    return `无法作为 Aira 主页包导入：${message} Aira 不是解压缩工具，仅支持符合主页包规范的 ZIP 文件。`;
  }

  private async resolveSharedSourceUri(want: Want): Promise<string> {
    let records: systemShare.SharedRecord[] = [];
    try {
      const sharedData = await systemShare.getSharedData(want);
      records = sharedData.getRecords();
    } catch (_error) {}
    const fileRecords = records.filter((record: systemShare.SharedRecord): boolean => {
      return String(record.uri ?? '').trim().length > 0;
    });
    if (fileRecords.length > 1) {
      throw new CustomHomepageExternalSourceError(
        'multiple_files',
        'Aira 主页导入只支持接收一个 ZIP 文件。'
      );
    }
    if (fileRecords.length === 1) {
      const record = fileRecords[0];
      const uri = String(record.uri ?? '').trim();
      this.ensureUsableZipSource(uri, String(record.utd ?? ''), String(want.type ?? ''));
      return uri;
    }
    const directUri = String(want.uri ?? '').trim();
    this.ensureUsableZipSource(directUri, String(want.type ?? ''));
    return directUri;
  }

  private ensureUsableZipSource(uri: string, descriptor: string, fallbackDescriptor: string = ''): void {
    if (uri.length <= 0) {
      throw new CustomHomepageExternalSourceError('missing_file', '未收到可读取的主页包文件。');
    }
    if (!this.isZipDescriptor(descriptor) &&
      !this.isZipDescriptor(fallbackDescriptor) &&
      !this.isZipUri(uri)) {
      throw new CustomHomepageExternalSourceError(
        'unsupported_type',
        'Aira 主页导入只支持 ZIP 主页包。'
      );
    }
  }

  private isZipDescriptor(rawDescriptor: string): boolean {
    const descriptor = rawDescriptor.trim().toLowerCase();
    return descriptor === ZIP_UTD || descriptor === ZIP_MIME_TYPE;
  }

  private isZipUri(rawUri: string): boolean {
    const normalized = rawUri.trim().split('?')[0].split('#')[0].toLowerCase();
    return normalized.endsWith('.zip');
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.trim().length > 0) {
      return error.message.trim();
    }
    const message = JSON.stringify(error);
    return message.length > 0 ? message : '未知错误';
  }
}
