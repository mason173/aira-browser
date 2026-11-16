import { common } from '@kit.AbilityKit';
import { BrowserClipboardService } from '../../services/share/BrowserClipboardService';
import { WebPageQrCodeImage, WebPageQrCodeService } from '../../services/share/WebPageQrCodeService';
import { WebPageShareService } from '../../services/share/WebPageShareService';

export type BrowserPageShareAction = 'close' | 'copy' | 'save_qr' | 'system_share';

export interface BrowserPageShareSnapshot {
  title: string;
  url: string;
  qrSource: string;
  qrLoading: boolean;
  savingQr: boolean;
}

export const EMPTY_BROWSER_PAGE_SHARE_SNAPSHOT: BrowserPageShareSnapshot = {
  title: '',
  url: '',
  qrSource: '',
  qrLoading: false,
  savingQr: false
};

interface BrowserPageShareSession {
  context: common.UIAbilityContext;
  title: string;
  url: string;
  qr?: WebPageQrCodeImage;
  qrLoading: boolean;
}

export interface BrowserPageShareShell {
  publishSnapshot: (snapshot: BrowserPageShareSnapshot) => void;
  openDialog: () => void;
  closeDialog: () => void;
  showToast: (message: ResourceStr) => void;
}

export class BrowserPageShareCoordinator {
  private readonly clipboardService: BrowserClipboardService;
  private readonly webPageShareService: WebPageShareService;
  private readonly qrService: WebPageQrCodeService;
  private readonly shell: BrowserPageShareShell;
  private session?: BrowserPageShareSession;
  private closing: boolean = false;
  private savingQr: boolean = false;
  private sharing: boolean = false;

  constructor(
    clipboardService: BrowserClipboardService,
    webPageShareService: WebPageShareService,
    qrService: WebPageQrCodeService,
    shell: BrowserPageShareShell
  ) {
    this.clipboardService = clipboardService;
    this.webPageShareService = webPageShareService;
    this.qrService = qrService;
    this.shell = shell;
  }

  open(context: common.UIAbilityContext, title: string, url: string): void {
    if (this.session !== undefined) {
      return;
    }
    const link = url.trim();
    if (link.length === 0) {
      this.shell.showToast($r('app.string.web_page_share_no_url'));
      return;
    }
    const session: BrowserPageShareSession = {
      context: context,
      title: title.trim() || link,
      url: link,
      qrLoading: true
    };
    this.session = session;
    this.publish(session);
    this.shell.openDialog();
    void this.generateQr(session);
  }

  handleAction(action: BrowserPageShareAction): void {
    const session = this.session;
    if (session === undefined || this.closing) {
      return;
    }
    switch (action) {
      case 'close':
        this.close();
        return;
      case 'copy':
        void this.copyLink(session);
        return;
      case 'save_qr':
        void this.saveQr(session);
        return;
      case 'system_share':
        void this.shareThroughSystem(session);
        return;
    }
  }

  close(): void {
    if (this.session === undefined || this.closing) {
      return;
    }
    this.handleWillDisappear();
    this.shell.closeDialog();
  }

  handleWillDisappear(): void {
    this.closing = true;
  }

  handleDidDisappear(): void {
    this.session = undefined;
    this.closing = false;
    this.shell.publishSnapshot(EMPTY_BROWSER_PAGE_SHARE_SNAPSHOT);
  }

  private async generateQr(session: BrowserPageShareSession): Promise<void> {
    try {
      session.qr = await this.qrService.generate(session.url);
    } catch (_error) {
      session.qr = undefined;
    }
    session.qrLoading = false;
    this.publish(session);
  }

  private async copyLink(session: BrowserPageShareSession): Promise<void> {
    const result = await this.clipboardService.copyText({
      value: session.url,
      emptyMessage: $r('app.string.web_page_share_no_url'),
      successMessage: $r('app.string.reader_copy_link_done')
    });
    if (this.session === session && !this.closing) {
      if (result.ok) {
        this.close();
      }
      this.shell.showToast(result.message);
    }
  }

  private async saveQr(session: BrowserPageShareSession): Promise<void> {
    if (session.qr === undefined || this.savingQr) {
      return;
    }
    this.savingQr = true;
    this.publish(session);
    try {
      if (await this.qrService.saveToGallery(session.context, session.qr)) {
        this.shell.showToast($r('app.string.context_menu_image_saved'));
      }
    } catch (_error) {
      this.shell.showToast($r('app.string.context_menu_image_save_failed'));
    } finally {
      this.savingQr = false;
      if (this.session !== undefined) {
        this.publish(this.session);
      }
    }
  }

  private async shareThroughSystem(session: BrowserPageShareSession): Promise<void> {
    if (this.sharing) {
      return;
    }
    this.sharing = true;
    try {
      await this.webPageShareService.shareWebPage(session.context, {
        title: session.title,
        url: session.url
      });
    } catch (_error) {
      this.shell.showToast($r('app.string.web_page_share_failed'));
    } finally {
      this.sharing = false;
    }
  }

  private publish(session: BrowserPageShareSession): void {
    if (this.session !== session || this.closing) {
      return;
    }
    this.shell.publishSnapshot({
      title: session.title,
      url: session.url,
      qrSource: session.qr?.source ?? '',
      qrLoading: session.qrLoading,
      savingQr: this.savingQr
    });
  }
}
