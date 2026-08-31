import {
  BrowserRootBottomPanelShellAction,
  BrowserRootBottomPanelShellEffect
} from './BrowserRootBottomPanelSessionCoordinator';

export interface BrowserRootBottomPanelShellActionHost {
  openDocumentViewerInfo: () => void;
  scanQrCode: () => void;
  togglePrivateMode: () => void;
  openTextZoom: () => void;
  openSiteReport: () => void;
  openTabsOverview: () => void;
  requestBrowserBack: () => void;
  showActionRejection: (message: string) => void;
}

export class BrowserRootBottomPanelShellActionExecutor {
  private readonly host: BrowserRootBottomPanelShellActionHost;

  constructor(host: BrowserRootBottomPanelShellActionHost) {
    this.host = host;
  }

  applyEffect(effect: BrowserRootBottomPanelShellEffect): void {
    if (effect.kind === 'action_rejection') {
      this.host.showActionRejection(effect.message);
      return;
    }
    this.apply(effect.action);
  }

  apply(action: BrowserRootBottomPanelShellAction): void {
    switch (action) {
      case 'open_document_viewer_info':
        this.host.openDocumentViewerInfo();
        return;
      case 'scan_qr':
        this.host.scanQrCode();
        return;
      case 'toggle_private_mode':
        this.host.togglePrivateMode();
        return;
      case 'open_text_zoom':
        this.host.openTextZoom();
        return;
      case 'open_site_report':
        this.host.openSiteReport();
        return;
      case 'open_tabs_overview':
        this.host.openTabsOverview();
        return;
      case 'request_browser_back':
        this.host.requestBrowserBack();
        return;
    }
  }
}
