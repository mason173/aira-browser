import { common } from '@kit.AbilityKit';
import { resolveAppResourceText } from '../resources/AppResourceText';
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
          totalBytes: 0,
          referer: effect.referer,
          userAgent: effect.userAgent
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
      helperMessage: resolveAppResourceText($r('app.string.link_opening')),
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
      this.shell.publishHelper(resolveAppResourceText($r('app.string.link_opened_private_tab')));
    });
  }

  private openPrivateWindow(url: string): void {
    void this.dependencies.privateTabCoordinator.openPrivateWindow(url).then((opened: boolean): void => {
      if (!opened) {
        this.shell.showToast(resolveAppResourceText($r('app.string.browser_browser_private_tab_coordinator_006')));
        return;
      }
      this.shell.publishHelper(resolveAppResourceText($r('app.string.link_opened_private_window')));
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
      emptyMessage: resolveAppResourceText($r('app.string.history_copy_empty')),
      successMessage: resolveAppResourceText($r('app.string.reader_copy_link_done'))
    }).then((result: BrowserClipboardCopyResult): void => {
      this.shell.publishHelper(result.message);
      this.shell.showToast(result.message);
    }).catch((error: Object): void => {
      this.shell.publishError(resolveAppResourceText($r('app.string.link_copy_failed_detail', JSON.stringify(error))));
      this.shell.showToast(resolveAppResourceText($r('app.string.reader_copy_link_failed')));
    });
  }

  private shareLink(title: string, url: string): void {
    const facts = this.shell.readFacts();
    this.dependencies.webPageShareService.shareWebPage(facts.context, {
      title: title,
      url: url
    }).catch((_error: Error): void => {
      this.shell.showToast(resolveAppResourceText($r('app.string.reader_share_failed')));
    });
  }
}
