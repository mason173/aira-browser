import { common } from '@kit.AbilityKit';
import {
  BrowserClipboardCopyResult,
  BrowserClipboardService
} from '../../services/share/BrowserClipboardService';
import { WebPageShareService } from '../../services/share/WebPageShareService';
import { BrowserAppUrlOpenCoordinator } from '../browser/BrowserAppUrlOpenCoordinator';
import { BrowserBookmarkActionCoordinator } from '../browser/BrowserBookmarkActionCoordinator';
import { BrowserDownloadConfirmOverlayCoordinator } from '../browser/BrowserDownloadConfirmOverlayCoordinator';
import { BrowserForegroundTabCreationCoordinator } from '../browser/BrowserForegroundTabCreationCoordinator';
import { BrowserPrivateTabCoordinator } from '../browser/BrowserPrivateTabCoordinator';
import { BrowserTabScopedEventContextCoordinator } from '../browser/BrowserTabScopedEventContextCoordinator';
import {
  WebContextMenuEffect,
  WebLinkContextMenuActionApplication
} from './WebLinkContextMenuCoordinator';

export interface WebLinkContextMenuActionShellFacts {
  context: common.UIAbilityContext;
  activeTabId: string;
  homeShortcutScenarioId: string;
}

export interface WebLinkContextMenuActionShell {
  readFacts: () => WebLinkContextMenuActionShellFacts;
  showToast: (message: string) => void;
  publishError: (message: string) => void;
  publishHelper: (message: string) => void;
  saveOffline: (tabId: string, url: string, title: string) => void;
}

interface WebLinkContextMenuFixedActionDependencies {
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  bookmarkActionCoordinator: BrowserBookmarkActionCoordinator;
  clipboardService: BrowserClipboardService;
  downloadConfirmOverlayCoordinator: BrowserDownloadConfirmOverlayCoordinator;
  foregroundTabCreationCoordinator: BrowserForegroundTabCreationCoordinator;
  privateTabCoordinator: BrowserPrivateTabCoordinator;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  webPageShareService: WebPageShareService;
}

export class WebLinkContextMenuFixedActionApplication implements WebLinkContextMenuActionApplication {
  private readonly dependencies: WebLinkContextMenuFixedActionDependencies;
  private readonly shell: WebLinkContextMenuActionShell;

  constructor(
    dependencies: WebLinkContextMenuFixedActionDependencies,
    shell: WebLinkContextMenuActionShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
  }

  applyEffects(effects: WebContextMenuEffect[]): void {
    for (let index = 0; index < effects.length; index += 1) {
      this.applyEffect(effects[index]);
    }
  }

  private applyEffect(effect: WebContextMenuEffect): void {
    const message = String(effect.message ?? '');
    const tabId = String(effect.tabId ?? '');
    const url = String(effect.url ?? '');
    const title = String(effect.title ?? '');
    switch (effect.type) {
      case 'toast':
        this.shell.showToast(message);
        return;
      case 'error_message':
        this.shell.publishError(message);
        return;
      case 'helper_message':
        this.shell.publishHelper(message);
        return;
      case 'open_current_link':
        this.openCurrentLink(tabId, url);
        return;
      case 'open_private_tab':
        this.openPrivateTabInCurrentWindow(url, title);
        return;
      case 'open_private_window':
        this.openPrivateWindow(url);
        return;
      case 'copy_link':
        this.copyLink(url);
        return;
      case 'share_link':
        this.shareLink(title, url);
        return;
      case 'add_bookmark':
        this.addBookmark(tabId, url, title);
        return;
      case 'save_offline':
        this.shell.saveOffline(tabId, url, title);
        return;
      case 'download_link':
        this.dependencies.downloadConfirmOverlayCoordinator.requestAndPresent({
          url: url,
          totalBytes: 0
        });
        return;
    }
  }

  private openCurrentLink(tabId: string, url: string): void {
    const createOptions = this.dependencies.tabScopedEventContextCoordinator.buildCreateOptions(tabId);
    this.dependencies.appUrlOpenCoordinator.open({
      url: url,
      title: url,
      intent: 'current_tab',
      source: 'app_ui',
      helperMessage: '正在打开链接',
      profileId: createOptions.profileId,
      privacyMode: createOptions.privacyMode,
      dataScope: createOptions.dataScope,
      createOptions: createOptions,
      openerTabId: createOptions.openerTabId
    });
  }

  private openPrivateTabInCurrentWindow(url: string, title: string): void {
    void this.dependencies.foregroundTabCreationCoordinator.createNewTab({
      initialUrl: url,
      initialTitle: title,
      options: this.dependencies.privateTabCoordinator.buildPrivateTabCreateOptions(),
      runtimeOptions: {}
    }).then((): void => {
      this.shell.publishHelper('已在隐私标签页中打开链接。');
    });
  }

  private openPrivateWindow(url: string): void {
    void this.dependencies.privateTabCoordinator.openPrivateWindow(url).then((opened: boolean): void => {
      if (!opened) {
        this.shell.showToast('隐私窗口打开失败，请重试。');
        return;
      }
      this.shell.publishHelper('已在新的隐私窗口中打开链接。');
    });
  }

  private addBookmark(tabId: string, url: string, title: string): void {
    const facts = this.shell.readFacts();
    this.dependencies.bookmarkActionCoordinator.startAdd({
      source: 'context_link',
      title: title.length > 0 ? title : url,
      url: url,
      dataScope: this.dependencies.tabScopedEventContextCoordinator.resolveDataScope(tabId),
      privacyMode: this.dependencies.tabScopedEventContextCoordinator.resolvePrivacyMode(tabId),
      enabled: url.trim().length > 0,
      homeShortcutScenarioId: facts.homeShortcutScenarioId
    });
  }

  private copyLink(url: string): void {
    this.dependencies.clipboardService.copyText({
      value: url,
      emptyMessage: '当前没有可复制的链接。',
      successMessage: '链接已复制。'
    }).then((result: BrowserClipboardCopyResult): void => {
      this.shell.publishHelper(result.message);
      this.shell.showToast(result.message);
    }).catch((error: Object): void => {
      this.shell.publishError(`复制失败：${JSON.stringify(error)}`);
      this.shell.showToast('复制失败，请稍后重试。');
    });
  }

  private shareLink(title: string, url: string): void {
    const facts = this.shell.readFacts();
    this.dependencies.webPageShareService.shareWebPage(facts.context, {
      title: title,
      url: url
    }).catch((_error: Error): void => {
      this.shell.showToast('分享失败，请稍后重试。');
    });
  }
}
