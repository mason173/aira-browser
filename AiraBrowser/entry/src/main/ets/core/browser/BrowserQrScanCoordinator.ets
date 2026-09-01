import { common } from '@kit.AbilityKit';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import {
  AiraDesktopLoginConfirmResponseBody,
  AiraDesktopLoginFunctionService
} from '../../services/auth/AiraDesktopLoginFunctionService';
import {
  DesktopLoginQrPayload,
  DesktopLoginQrScanService
} from '../../services/auth/DesktopLoginQrScanService';
import { BrowserQrScanResult, BrowserQrScanService } from '../../services/browser/BrowserQrScanService';
import {
  BrowserWifiQrCodeService,
  BrowserWifiQrCredentials
} from '../../services/browser/BrowserWifiQrCodeService';
import { BrowserClipboardService } from '../../services/share/BrowserClipboardService';

export type BrowserQrScanNavigationTarget = 'scanned_url' | 'account_settings';
export type BrowserQrScanSurface = 'desktop_login_confirm' | 'wifi_credentials';
export type BrowserWifiQrResultAction = 'copy_password' | 'dismiss';
export type BrowserDesktopLoginConfirmAction = 'cancel' | 'confirm';

export interface BrowserQrScanSessionSnapshot {
  desktopLoginConfirming: boolean;
  desktopLoginUid: string;
  desktopLoginDisplayName: string;
  desktopLoginAvatarUri: string;
  wifiCredentials: BrowserWifiQrCredentials | undefined;
}

export interface BrowserQrScanShell {
  publishSnapshot: (snapshot: BrowserQrScanSessionSnapshot) => void;
  showToast: (message: string) => void;
  openNavigation: (target: BrowserQrScanNavigationTarget, value: string) => void;
  setSurfaceVisible: (surface: BrowserQrScanSurface, visible: boolean) => void;
}

export const DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT: BrowserQrScanSessionSnapshot = {
  desktopLoginConfirming: false,
  desktopLoginUid: '',
  desktopLoginDisplayName: '',
  desktopLoginAvatarUri: '',
  wifiCredentials: undefined
};

export class BrowserQrScanCoordinator {
  private readonly syncConfigStore: AiraSyncConfigStore;
  private readonly shell: BrowserQrScanShell;
  private readonly desktopLoginQrScanService: DesktopLoginQrScanService;
  private readonly desktopLoginService: AiraDesktopLoginFunctionService;
  private readonly qrScanService: BrowserQrScanService;
  private readonly wifiQrCodeService: BrowserWifiQrCodeService;
  private readonly clipboardService: BrowserClipboardService;
  private snapshot: BrowserQrScanSessionSnapshot = DEFAULT_BROWSER_QR_SCAN_SESSION_SNAPSHOT;
  private pendingDesktopLoginSessionId: string = '';
  private pendingDesktopLoginSecret: string = '';
  private desktopLoginGeneration: number = 0;
  private desktopLoginSurfaceVisible: boolean = false;

  constructor(
    syncConfigStore: AiraSyncConfigStore,
    shell: BrowserQrScanShell,
    desktopLoginQrScanService?: DesktopLoginQrScanService,
    desktopLoginService?: AiraDesktopLoginFunctionService,
    qrScanService?: BrowserQrScanService,
    wifiQrCodeService?: BrowserWifiQrCodeService,
    clipboardService?: BrowserClipboardService
  ) {
    this.syncConfigStore = syncConfigStore;
    this.shell = shell;
    this.desktopLoginQrScanService = desktopLoginQrScanService ?? new DesktopLoginQrScanService();
    this.desktopLoginService = desktopLoginService ?? new AiraDesktopLoginFunctionService();
    this.qrScanService = qrScanService ?? new BrowserQrScanService();
    this.wifiQrCodeService = wifiQrCodeService ?? new BrowserWifiQrCodeService();
    this.clipboardService = clipboardService ?? new BrowserClipboardService();
  }

  async scan(context: common.Context): Promise<void> {
    const result = await this.qrScanService.scan(context);
    this.applyScanResult(result);
  }

  handleDesktopLoginConfirmAction(action: BrowserDesktopLoginConfirmAction): void {
    if (action === 'cancel') {
      this.shell.setSurfaceVisible('desktop_login_confirm', false);
      return;
    }
    void this.confirmDesktopLogin();
  }

  private async confirmDesktopLogin(): Promise<void> {
    if (this.snapshot.desktopLoginConfirming) {
      return;
    }
    const sessionId = this.pendingDesktopLoginSessionId.trim();
    const secret = this.pendingDesktopLoginSecret.trim();
    if (sessionId.length <= 0 || secret.length <= 0) {
      this.clearDesktopLoginSession();
      this.shell.setSurfaceVisible('desktop_login_confirm', false);
      this.shell.showToast('二维码登录凭证已失效，请重新扫码。');
      return;
    }
    const generation = this.desktopLoginGeneration;
    this.setDesktopLoginConfirming(true);
    try {
      const account = this.syncConfigStore.getSettings().huaweiCloud;
      if (account.uid.trim().length <= 0) {
        if (!this.isCurrentDesktopLoginGeneration(generation)) {
          return;
        }
        this.clearDesktopLoginSession();
        this.shell.setSurfaceVisible('desktop_login_confirm', false);
        this.shell.showToast('请先登录华为账号');
        this.shell.openNavigation('account_settings', '');
        return;
      }
      const result = await this.desktopLoginService.confirm(
        sessionId,
        secret,
        account.uid,
        account.displayName,
        account.photoUrl
      );
      if (!this.isCurrentDesktopLoginGeneration(generation)) {
        return;
      }
      this.clearDesktopLoginSession();
      this.shell.setSurfaceVisible('desktop_login_confirm', false);
      this.presentDesktopLoginConfirmationResult(result);
    } catch (error) {
      if (!this.isCurrentDesktopLoginGeneration(generation)) {
        return;
      }
      if (this.desktopLoginSurfaceVisible) {
        this.setDesktopLoginConfirming(false);
      } else {
        this.clearDesktopLoginSession();
      }
      this.shell.showToast(this.resolveErrorMessage(error as Error, '桌面插件登录失败'));
    }
  }

  handleWifiResultAction(action: BrowserWifiQrResultAction): void {
    if (action === 'copy_password') {
      void this.copyWifiPassword();
      return;
    }
    this.shell.setSurfaceVisible('wifi_credentials', false);
  }

  private async copyWifiPassword(): Promise<void> {
    const password = this.snapshot.wifiCredentials?.password ?? '';
    const result = await this.clipboardService.copyText({
      value: password,
      emptyMessage: '二维码未包含 Wi-Fi 密码。',
      successMessage: 'Wi-Fi 密码已复制',
      failureMessage: '复制 Wi-Fi 密码失败，请稍后重试。'
    });
    this.shell.showToast(result.message);
  }

  handleSurfaceDismissed(surface: BrowserQrScanSurface): void {
    if (surface === 'desktop_login_confirm') {
      this.desktopLoginSurfaceVisible = false;
      if (!this.snapshot.desktopLoginConfirming) {
        this.clearDesktopLoginSession();
      }
      return;
    }
    if (this.snapshot.wifiCredentials === undefined) {
      return;
    }
    this.snapshot = {
      desktopLoginConfirming: this.snapshot.desktopLoginConfirming,
      desktopLoginUid: this.snapshot.desktopLoginUid,
      desktopLoginDisplayName: this.snapshot.desktopLoginDisplayName,
      desktopLoginAvatarUri: this.snapshot.desktopLoginAvatarUri,
      wifiCredentials: undefined
    };
    this.publishSnapshot();
  }

  resetSession(): void {
    this.desktopLoginGeneration += 1;
    this.pendingDesktopLoginSessionId = '';
    this.pendingDesktopLoginSecret = '';
    this.desktopLoginSurfaceVisible = false;
    this.snapshot = {
      desktopLoginConfirming: false,
      desktopLoginUid: '',
      desktopLoginDisplayName: '',
      desktopLoginAvatarUri: '',
      wifiCredentials: undefined
    };
    this.publishSnapshot();
  }

  private applyScanResult(result: BrowserQrScanResult): void {
    if (result.status === 'canceled') {
      return;
    }
    if (result.status !== 'success') {
      this.showToastIfPresent(result.message);
      return;
    }
    if (this.wifiQrCodeService.isWifiPayload(result.value)) {
      this.applyWifiPayload(result.value);
      return;
    }
    if (this.desktopLoginQrScanService.isDesktopLoginPayload(result.value)) {
      this.applyDesktopLoginPayload(result.value);
      return;
    }
    this.shell.openNavigation('scanned_url', result.value);
  }

  private applyDesktopLoginPayload(value: string): void {
    const account = this.syncConfigStore.getSettings().huaweiCloud;
    if (account.uid.trim().length <= 0) {
      this.shell.showToast('请先登录华为账号');
      this.shell.openNavigation('account_settings', '');
      return;
    }
    let payload: DesktopLoginQrPayload;
    try {
      payload = this.desktopLoginQrScanService.parsePayload(value);
    } catch (error) {
      this.shell.showToast(this.resolveErrorMessage(
        error as Error,
        '二维码登录凭证不完整，请刷新电脑端二维码。'
      ));
      return;
    }
    this.desktopLoginGeneration += 1;
    this.pendingDesktopLoginSessionId = payload.sessionId;
    this.pendingDesktopLoginSecret = payload.secret;
    this.desktopLoginSurfaceVisible = true;
    this.snapshot = {
      desktopLoginConfirming: false,
      desktopLoginUid: account.uid,
      desktopLoginDisplayName: account.displayName,
      desktopLoginAvatarUri: account.photoUrl,
      wifiCredentials: undefined
    };
    this.publishSnapshot();
    this.shell.setSurfaceVisible('desktop_login_confirm', true);
  }

  private applyWifiPayload(value: string): void {
    let credentials: BrowserWifiQrCredentials;
    try {
      credentials = this.wifiQrCodeService.parsePayload(value);
    } catch (error) {
      this.shell.showToast(this.resolveErrorMessage(error as Error, '无法识别 Wi-Fi 二维码。'));
      return;
    }
    this.clearDesktopLoginSession(false);
    this.snapshot = {
      desktopLoginConfirming: false,
      desktopLoginUid: '',
      desktopLoginDisplayName: '',
      desktopLoginAvatarUri: '',
      wifiCredentials: credentials
    };
    this.publishSnapshot();
    this.shell.setSurfaceVisible('wifi_credentials', true);
  }

  private presentDesktopLoginConfirmationResult(result: AiraDesktopLoginConfirmResponseBody): void {
    if (result.ok === true && result.status === 'confirmed') {
      this.shell.showToast('可以回到电脑继续使用 Aira-sync。');
      return;
    }
    const message = result.message?.trim() ?? '桌面插件登录确认失败，请刷新二维码后重试。';
    this.shell.showToast(message.length > 0 ? message : '登录失败');
  }

  private setDesktopLoginConfirming(confirming: boolean): void {
    this.snapshot = {
      desktopLoginConfirming: confirming,
      desktopLoginUid: this.snapshot.desktopLoginUid,
      desktopLoginDisplayName: this.snapshot.desktopLoginDisplayName,
      desktopLoginAvatarUri: this.snapshot.desktopLoginAvatarUri,
      wifiCredentials: this.snapshot.wifiCredentials
    };
    this.publishSnapshot();
  }

  private clearDesktopLoginSession(publish: boolean = true): void {
    this.desktopLoginGeneration += 1;
    this.pendingDesktopLoginSessionId = '';
    this.pendingDesktopLoginSecret = '';
    this.desktopLoginSurfaceVisible = false;
    this.snapshot = {
      desktopLoginConfirming: false,
      desktopLoginUid: '',
      desktopLoginDisplayName: '',
      desktopLoginAvatarUri: '',
      wifiCredentials: this.snapshot.wifiCredentials
    };
    if (publish) {
      this.publishSnapshot();
    }
  }

  private isCurrentDesktopLoginGeneration(generation: number): boolean {
    return generation === this.desktopLoginGeneration;
  }

  private publishSnapshot(): void {
    this.shell.publishSnapshot(this.snapshot);
  }

  private showToastIfPresent(message: string): void {
    if (message.trim().length > 0) {
      this.shell.showToast(message);
    }
  }

  private resolveErrorMessage(error: Error, fallback: string): string {
    return error.message.length > 0 ? error.message : fallback;
  }
}
