import { common } from '@kit.AbilityKit';
import {
  BrowserDataScope,
  BrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserClipboardCopyResult, BrowserClipboardService } from '../../services/share/BrowserClipboardService';
import { WebPageShareService } from '../../services/share/WebPageShareService';
import { ReadingWindowBrightnessService } from '../../services/reading/ReadingWindowBrightnessService';
import { ReaderLinkPolicyService } from '../../services/web/ReaderLinkPolicyService';
import { BrowserCreateTabOptions } from '../tabs/TabManager';
import { BrowserAppUrlOpenCoordinator } from './BrowserAppUrlOpenCoordinator';
import { BrowserConfirmationSink } from './BrowserConfirmationSink';
import {
  BrowserBookmarkActionCoordinator,
  BrowserBookmarkActionState,
  BrowserBookmarkActionTarget
} from './BrowserBookmarkActionCoordinator';
import {
  ArticleReadingSessionOperations,
  ReaderModeEffect,
  ReaderModeEffectApplication
} from './ReaderModeCoordinator';
import {
  ReaderModeAction,
  ReaderModeControlPanel
} from '../../features/reader/ReaderModeModels';
import { BrowserShellRouteCoordinator } from './BrowserShellRouteCoordinator';
import { BrowserSystemSheetType } from './BrowserShellRuntimeContracts';
import { BrowserTransientSurfaceCoordinator } from './BrowserTransientSurfaceCoordinator';
import { BrowserUnifiedLinkApplicationCoordinator } from './BrowserUnifiedLinkApplicationCoordinator';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';

export interface ReaderModeApplicationFacts {
  activeTabId: string;
  currentWebActionUrl: string;
  currentTitle: string;
  articleTitle: string;
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
  homeShortcutScenarioId: string;
  readerVisible: boolean;
}

export interface ReaderModeApplicationShell {
  readFacts: () => ReaderModeApplicationFacts;
  resolveCreateOptions: () => BrowserCreateTabOptions;
  resolveAbilityContext: () => common.UIAbilityContext;
  showToast: (message: string) => void;
  publishHelper: (message: string) => void;
  publishError: (message: string) => void;
  syncStatusBarStyle: () => void;
  closeSpeechVoiceDialog: () => void;
}

export interface ReaderModeApplicationDependencies {
  readerModeCoordinator: ArticleReadingSessionOperations;
  clipboardService: BrowserClipboardService;
  webPageShareService: WebPageShareService;
  bookmarkActionCoordinator: BrowserBookmarkActionCoordinator;
  shellRouteCoordinator: BrowserShellRouteCoordinator;
  transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  unifiedLinkApplicationCoordinator: BrowserUnifiedLinkApplicationCoordinator;
  webTopImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  confirmationPresenter: BrowserConfirmationSink;
  readingWindowBrightnessService: ReadingWindowBrightnessService;
}

export interface ReaderModeSpeechPresentationTiming {
  revealDelayMs: number;
  dismissDurationMs: number;
}

export class ReaderModeApplication implements ReaderModeEffectApplication {
  private readonly dependencies: ReaderModeApplicationDependencies;
  private readonly shell: ReaderModeApplicationShell;
  private readonly speechPresentationTiming: ReaderModeSpeechPresentationTiming;
  private readonly linkPolicyService: ReaderLinkPolicyService = new ReaderLinkPolicyService();

  constructor(
    dependencies: ReaderModeApplicationDependencies,
    shell: ReaderModeApplicationShell,
    speechPresentationTiming: ReaderModeSpeechPresentationTiming
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    this.speechPresentationTiming = speechPresentationTiming;
  }

  apply(effect: ReaderModeEffect): void {
    switch (effect.type) {
      case 'toast':
        this.shell.showToast(effect.message);
        return;
      case 'sync_status_bar_style':
        this.shell.syncStatusBarStyle();
        return;
      case 'present_speech_player':
        this.presentSpeechPlayer();
        return;
      case 'dismiss_speech_player':
        this.dismissSpeechPlayer();
        return;
      case 'reset_speech_player_presentation':
        this.resetSpeechPlayerPresentation();
        return;
      case 'restore_status_bar':
        this.dependencies.webTopImmersionSessionCoordinator.requestVisible(effect.source);
        return;
      case 'copy_link':
        this.copyLink(effect.url);
        return;
      case 'share':
        this.share(effect.title, effect.url);
        return;
      case 'bookmark':
        this.dependencies.bookmarkActionCoordinator.toggle(this.buildBookmarkActionTarget());
        return;
      case 'open_bookmarks':
        void this.dependencies.shellRouteCoordinator.openBookmarkManagerPage();
        return;
      case 'open_link':
        this.openLink(effect.url);
        return;
      case 'open_control_panel':
        this.dependencies.transientSurfaceCoordinator.openSystemSheet(
          this.resolveControlPanelSheet(effect.panel)
        );
        return;
      case 'apply_window_brightness':
        this.dependencies.readingWindowBrightnessService.apply(
          'article',
          this.shell.resolveAbilityContext(),
          effect.brightnessMode,
          effect.brightnessPercent
        );
        return;
      case 'restore_window_brightness':
        this.dependencies.readingWindowBrightnessService.release(
          'article',
          this.shell.resolveAbilityContext()
        );
        return;
      case 'status_bar_visibility':
        this.dependencies.webTopImmersionSessionCoordinator.requestVisibilityIntent(
          effect.visible,
          effect.source
        );
        return;
      case 'record_diagnostic':
        return;
    }
  }

  resolveCurrentUrl(): string {
    return this.dependencies.readerModeCoordinator.resolveCurrentUrl(
      this.shell.readFacts().currentWebActionUrl
    );
  }

  buildBookmarkActionState(): BrowserBookmarkActionState {
    return this.dependencies.bookmarkActionCoordinator.buildActionState(this.buildBookmarkActionTarget());
  }

  requestExitConfirmation(): void {
    if (!this.dependencies.readerModeCoordinator.beginExitConfirmation()) {
      return;
    }
    this.dependencies.confirmationPresenter.confirm({
      title: '退出阅读模式',
      message: '确定要退出阅读模式并返回原网页吗？',
      cancelLabel: '继续阅读',
      confirmLabel: '退出',
      onCancel: (): void => {
        this.dependencies.readerModeCoordinator.endExitConfirmation();
      },
      onConfirm: (): void => {
        this.dependencies.readerModeCoordinator.endExitConfirmation();
        this.dependencies.readerModeCoordinator.closeSession();
      }
    });
  }

  handleAction(action: ReaderModeAction): void {
    const facts: ReaderModeApplicationFacts = this.shell.readFacts();
    this.dependencies.readerModeCoordinator.handleAction(action, {
      fallbackTitle: facts.currentTitle,
      fallbackUrl: facts.currentWebActionUrl
    });
  }

  private dismissSpeechPlayer(): void {
    this.dependencies.transientSurfaceCoordinator.dismiss('reader_speech_player');
  }

  private resetSpeechPlayerPresentation(): void {
    this.shell.closeSpeechVoiceDialog();
    this.dependencies.transientSurfaceCoordinator.reset('reader_speech_player');
  }

  private presentSpeechPlayer(): void {
    this.dependencies.transientSurfaceCoordinator.present({
      id: 'reader_speech_player',
      revealDelayMs: this.speechPresentationTiming.revealDelayMs,
      dismissDurationMs: this.speechPresentationTiming.dismissDurationMs,
      shouldReveal: (): boolean => this.shell.readFacts().readerVisible
    });
  }

  private copyLink(url: string): void {
    void this.dependencies.clipboardService.copyText({
      value: url,
      emptyMessage: '当前没有可复制的网址。',
      successMessage: '链接已复制。'
    }).then((result: BrowserClipboardCopyResult): void => {
      this.shell.publishHelper(result.message);
      this.shell.showToast(result.message);
    }).catch((error: Error): void => {
      this.shell.publishError(`复制失败：${JSON.stringify(error)}`);
      this.shell.showToast('复制失败，请稍后重试。');
    });
  }

  private share(title: string, url: string): void {
    void this.dependencies.webPageShareService.shareWebPage(
      this.shell.resolveAbilityContext(),
      { title: title, url: url }
    ).catch((_error: Error): void => {
      this.shell.showToast('分享失败，请稍后重试。');
    });
  }

  private buildBookmarkActionTarget(): BrowserBookmarkActionTarget {
    const facts = this.shell.readFacts();
    const url = this.dependencies.readerModeCoordinator.resolveCurrentUrl(facts.currentWebActionUrl);
    const title = facts.articleTitle.length > 0 ? facts.articleTitle : facts.currentTitle;
    return {
      source: 'reader_article',
      title: title.length > 0 ? title : url,
      url: url,
      dataScope: facts.dataScope,
      privacyMode: facts.privacyMode,
      enabled: url.length > 0,
      homeShortcutScenarioId: facts.homeShortcutScenarioId
    };
  }

  private openLink(url: string): void {
    const decision = this.linkPolicyService.resolve(url);
    if (decision.kind === 'blocked') {
      this.shell.showToast(decision.message);
      return;
    }
    const facts = this.shell.readFacts();
    if (decision.kind === 'external') {
      this.dependencies.unifiedLinkApplicationCoordinator.requestExternalNavigationPrompt({
        tabId: facts.activeTabId,
        url: decision.url,
        appName: '',
        createdAt: Date.now()
      });
      return;
    }
    this.dependencies.readerModeCoordinator.closeSession();
    const createOptions = this.shell.resolveCreateOptions();
    this.dependencies.appUrlOpenCoordinator.openCurrentAppUi(
      decision.url,
      decision.message,
      createOptions
    );
  }

  private resolveControlPanelSheet(panel: ReaderModeControlPanel): BrowserSystemSheetType {
    if (panel === 'appearance') {
      return 'readerAppearance';
    }
    if (panel === 'settings') {
      return 'readerSettings';
    }
    return 'readerText';
  }
}
