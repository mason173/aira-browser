import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { scanBarcode, scanCore } from '@kit.ScanKit';

const DESKTOP_LOGIN_QR_PREFIX: string = 'aira://desktop-login?';

export interface DesktopLoginQrPayload {
  sessionId: string;
  secret: string;
}

export class DesktopLoginQrScanService {
  async scan(context: common.Context): Promise<DesktopLoginQrPayload> {
    const result = await scanBarcode.startScanForResult(context, {
      scanTypes: [scanCore.ScanType.QR_CODE],
      enableAlbum: false,
      enableMultiMode: false
    });
    return this.parsePayload(result.originalValue);
  }

  isDesktopLoginPayload(value: string): boolean {
    return value.trim().startsWith(DESKTOP_LOGIN_QR_PREFIX);
  }

  parsePayload(value: string): DesktopLoginQrPayload {
    const normalized = value.trim();
    if (!normalized.startsWith(DESKTOP_LOGIN_QR_PREFIX)) {
      throw this.buildPublicError('invalid_desktop_login_qr', '这不是 Aira 桌面登录二维码。');
    }
    const params = this.parseQuery(normalized.slice(DESKTOP_LOGIN_QR_PREFIX.length));
    const sessionId = params.get('session')?.trim() ?? '';
    const secret = params.get('secret')?.trim() ?? '';
    if (sessionId.length <= 0 || secret.length <= 0) {
      throw this.buildPublicError('invalid_desktop_login_qr', '二维码登录凭证不完整，请刷新电脑端二维码。');
    }
    return {
      sessionId,
      secret
    };
  }

  isUserCancel(error: Error): boolean {
    const businessError = error as BusinessError;
    return businessError.code === 1000500002;
  }

  private parseQuery(query: string): Map<string, string> {
    const params: Map<string, string> = new Map<string, string>();
    query.split('&').forEach((part: string) => {
      const separatorIndex = part.indexOf('=');
      if (separatorIndex <= 0) {
        return;
      }
      const key = this.decode(part.slice(0, separatorIndex));
      const value = this.decode(part.slice(separatorIndex + 1));
      params.set(key, value);
    });
    return params;
  }

  private decode(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, '%20'));
    } catch (_error) {
      return value;
    }
  }

  private buildPublicError(code: string, message: string): Error {
    const error = new Error(message) as DesktopLoginQrError;
    error.code = code;
    return error;
  }
}

interface DesktopLoginQrError extends Error {
  code?: string;
}
