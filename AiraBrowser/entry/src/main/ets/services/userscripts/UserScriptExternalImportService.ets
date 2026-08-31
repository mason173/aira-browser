import { Want } from '@kit.AbilityKit';

const WANT_ACTION_VIEW_DATA: string = 'ohos.want.action.viewData';

class UserScriptExternalImportSourceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UserScriptExternalImportSourceError';
  }
}

export class UserScriptExternalImportService {
  isCandidate(want: Want): boolean {
    if (String(want.action ?? '').trim() !== WANT_ACTION_VIEW_DATA) {
      return false;
    }
    return this.isUserScriptUri(String(want.uri ?? ''));
  }

  resolveSourceUri(want: Want): string {
    if (!this.isCandidate(want)) {
      throw new UserScriptExternalImportSourceError('Aira 只接收 .user.js 用户脚本文件。');
    }
    const uri = String(want.uri ?? '').trim();
    if (uri.length === 0) {
      throw new UserScriptExternalImportSourceError('未收到可读取的用户脚本文件。');
    }
    return uri;
  }

  buildUserFacingError(error: Object | undefined): string {
    if (error instanceof UserScriptExternalImportSourceError) {
      return error.message;
    }
    if (error instanceof Error && error.message.trim().length > 0) {
      return `无法导入用户脚本：${error.message.trim()}`;
    }
    return '无法导入用户脚本，请确认文件完整且格式正确。';
  }

  private isUserScriptUri(rawUri: string): boolean {
    const normalized = rawUri.trim().split('?')[0].split('#')[0].toLowerCase();
    return normalized.endsWith('.user.js');
  }
}
