import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';

export type PrivateModeUserAuthStatus =
  'success' |
  'cancelled' |
  'failed' |
  'unavailable';

export interface PrivateModeUserAuthResult {
  status: PrivateModeUserAuthStatus;
  code: number;
  message: string;
}

export type PrivateModeUserAuthCallback = (result: PrivateModeUserAuthResult) => void;

export class PrivateModeUserAuthService {
  private authInstance?: userAuth.UserAuthInstance;
  private active: boolean = false;

  authenticate(callback: PrivateModeUserAuthCallback): void {
    this.cancel();
    try {
      const rand = cryptoFramework.createRandom();
      const challenge = rand.generateRandomSync(16).data;
      const authParam: userAuth.AuthParam = {
        challenge: challenge,
        authType: [
          userAuth.UserAuthType.FACE,
          userAuth.UserAuthType.FINGERPRINT
        ],
        authTrustLevel: userAuth.AuthTrustLevel.ATL3
      };
      const widgetParam: userAuth.WidgetParam = {
        title: '隐私模式已锁定',
        navigationButtonText: '取消'
      };
      const authInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
      this.authInstance = authInstance;
      this.active = true;
      authInstance.on('result', {
        onResult: (result: userAuth.UserAuthResult) => {
          this.detach();
          callback(this.mapResult(result));
        }
      });
      authInstance.start();
    } catch (error) {
      this.detach();
      callback(this.mapError(error));
    }
  }

  cancel(): void {
    if (this.authInstance === undefined) {
      return;
    }
    try {
      if (this.active) {
        this.authInstance.cancel();
      }
    } catch (_error) {
    }
    this.detach();
  }

  private detach(): void {
    if (this.authInstance !== undefined) {
      try {
        this.authInstance.off('result');
      } catch (_error) {
      }
    }
    this.authInstance = undefined;
    this.active = false;
  }

  private mapResult(result: userAuth.UserAuthResult): PrivateModeUserAuthResult {
    if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
      return {
        status: 'success',
        code: result.result,
        message: '验证成功'
      };
    }
    return {
      status: result.result === userAuth.UserAuthResultCode.CANCELED ? 'cancelled' : 'failed',
      code: result.result,
      message: this.resolveResultMessage(result.result)
    };
  }

  private mapError(error: Object | Error | undefined): PrivateModeUserAuthResult {
    const businessError = error as BusinessError;
    return {
      status: 'unavailable',
      code: businessError?.code ?? -1,
      message: businessError?.message ?? '当前设备无法发起系统身份验证。'
    };
  }

  private resolveResultMessage(code: number): string {
    if (code === userAuth.UserAuthResultCode.CANCELED) {
      return '已取消验证';
    }
    if (code === userAuth.UserAuthResultCode.TIMEOUT) {
      return '验证超时，请重试';
    }
    if (code === userAuth.UserAuthResultCode.LOCKED) {
      return '系统身份验证暂时锁定，请稍后重试';
    }
    return '验证失败，请重试';
  }
}
