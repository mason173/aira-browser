export type HuaweiAccountOperationStage = 'settings-initialize' | 'auth-initialize' |
  'session-reset' | 'cached-user-read' | 'agc-sign-in' | 'settings-save' |
  'identity-change' | 'huawei-space-capability';

interface HuaweiAccountNativeError {
  code?: number | string;
  message?: string;
}

/** Keep the failing boundary, including non-enumerable BusinessError.message.
 * Never serialize an SDK error object: it can contain credentials or user data.
 */
export class HuaweiAccountOperationError extends Error {
  stage: HuaweiAccountOperationStage;
  code?: number | string;

  constructor(stage: HuaweiAccountOperationStage, error: Object) {
    const detail: HuaweiAccountNativeError = error === null || error === undefined ? {} :
      error as HuaweiAccountNativeError;
    const message = typeof error === 'string' ? error :
      (typeof detail.message === 'string' ? detail.message : '');
    super(HuaweiAccountOperationError.redact(message));
    this.stage = stage;
    this.code = typeof detail.code === 'number' || typeof detail.code === 'string' ? detail.code : undefined;
  }

  static from(stage: HuaweiAccountOperationStage, error: Object): HuaweiAccountOperationError {
    // The adapter knows whether reading the cached user or requesting new
    // credentials failed. Outer orchestration must not replace that evidence.
    return error instanceof HuaweiAccountOperationError ? error : new HuaweiAccountOperationError(stage, error);
  }

  technicalMessage(): string {
    const code = this.code === undefined ? 'unknown' : `${this.code}`;
    const message = this.message.length > 0 ? this.message : '(no native message)';
    return `stage=${this.stage}, code=${code}, message=${message}`;
  }

  private static redact(message: string): string {
    return message
      .replace(/Bearer\s+[^\s,"';}]+/gi, 'Bearer [redacted]')
      .replace(/((?:access[_-]?token|refresh[_-]?token|id[_-]?token|token|authorization[_-]?code|auth[_-]?code|client[_-]?secret|password|unionid|openid|uid)\s*["']?\s*[:=]\s*["']?)[^\s,"';}&]+/gi,
        '$1[redacted]')
      .replace(/https?:\/\/[^\s"'<>]+/gi, '[url]')
      .replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email]')
      .slice(0, 512);
  }
}
