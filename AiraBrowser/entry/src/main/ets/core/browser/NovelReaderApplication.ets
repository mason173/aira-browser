import {
  NovelReaderAction,
  NovelReaderControlPanel,
  NovelReaderEffect,
  NovelReaderSessionScope,
  NovelReaderSnapshot,
  resolveNovelReadingModeLabel
} from '../../features/novel/NovelReaderModels';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import promptAction from '@ohos.promptAction';
import {
  BrowserClipboardCopyResult,
  BrowserClipboardService
} from '../../services/share/BrowserClipboardService';
import { WebPageShareService } from '../../services/share/WebPageShareService';
import { ReadingWindowBrightnessService } from '../../services/reading/ReadingWindowBrightnessService';
import {
  NovelReaderSessionOperations,
  NovelReaderTakeoverPreviewCapturePort
} from '../../features/novel/NovelReaderController';
import { BrowserWebLoadRuntimeCoordinator } from '../../services/web/BrowserWebLoadRuntimeCoordinator';
import { BrowserConfirmationSink } from './BrowserConfirmationSink';
import { BrowserWebTopImmersionSessionCoordinator } from './BrowserWebTopImmersionSessionCoordinator';
import { BrowserTransientSurfaceCoordinator } from './BrowserTransientSurfaceCoordinator';
import { BrowserSystemSheetType } from './BrowserShellRuntimeContracts';
import { BrowserTabHomeCoordinator } from './BrowserTabHomeCoordinator';
import { BrowserTabSwitchCoordinator } from './BrowserTabSwitchCoordinator';
import { BrowserTabScopedEventContextCoordinator } from './BrowserTabScopedEventContextCoordinator';
import {
  BrowserAcceptedSpaRouteSignal,
  BrowserRuntimeLifecyclePort
} from '../../services/web/BrowserRuntimeLifecyclePort';
import { BrowserAppUrlOpenCoordinator } from './BrowserAppUrlOpenCoordinator';

const NOVEL_READER_STATUS_BAR_OWNER_ID: string = 'novel-reader';
const NOVEL_READER_STATUS_BAR_SOURCE: string = 'novel-reader-setting';

export interface NovelReaderNavigationCommitFacts {
  tabId: string;
  activeTabId: string;
  webPageVisible: boolean;
  pageUrl: string;
  isMainFrame: boolean;
  isSameDocument: boolean;
}

class NovelReaderTakeoverPreviewCaptureAdapter implements NovelReaderTakeoverPreviewCapturePort {
  private readonly captureAction: (tabId: string) => Promise<boolean>;
  private readonly visibilityResolver: (tabId: string) => boolean;
  private readonly contextCoordinator: BrowserTabScopedEventContextCoordinator;

  constructor(
    captureAction: (tabId: string) => Promise<boolean>,
    visibilityResolver: (tabId: string) => boolean,
    contextCoordinator: BrowserTabScopedEventContextCoordinator
  ) {
    this.captureAction = captureAction;
    this.visibilityResolver = visibilityResolver;
    this.contextCoordinator = contextCoordinator;
  }

  async captureSourceTabPreview(tabId: string): Promise<boolean> {
    try {
      return await this.captureAction(tabId);
    } catch (_error) {
      return false;
    }
  }

  isSourceTabCurrent(scope: NovelReaderSessionScope, pageUrl: string): boolean {
    if (!this.visibilityResolver(scope.tabId)) {
      return false;
    }
    const context = this.contextCoordinator.resolveContext(scope.tabId);
    return context.privacyMode === scope.privacyMode && context.dataScope === scope.dataScope &&
      this.normalizePageUrl(this.contextCoordinator.resolvePageUrl(scope.tabId)) ===
        this.normalizePageUrl(pageUrl);
  }

  private normalizePageUrl(value: string): string {
    const trimmed = value.trim();
    const fragmentIndex = trimmed.indexOf('#');
    const withoutFragment = fragmentIndex >= 0 ? trimmed.substring(0, fragmentIndex) : trimmed;
    return withoutFragment.endsWith('/') ? withoutFragment.substring(0, withoutFragment.length - 1) : withoutFragment;
  }
}

export class NovelReaderApplicationDependencies {
  webTopImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator;
  webNavigationApplication: BrowserWebLoadRuntimeCoordinator;
  transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator;
  confirmationPresenter: BrowserConfirmationSink;
  readingWindowBrightnessService: ReadingWindowBrightnessService;
  tabHomeCoordinator: BrowserTabHomeCoordinator;
  tabSwitchCoordinator: BrowserTabSwitchCoordinator;
  tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator;
  runtimeLifecyclePort: BrowserRuntimeLifecyclePort;
  appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator;
  captureSourceTabPreview: (tabId: string) => Promise<boolean>;
  isSourceTabVisible: (tabId: string) => boolean;
  handleAction: (action: NovelReaderAction) => void;

  constructor(
    webTopImmersionSessionCoordinator: BrowserWebTopImmersionSessionCoordinator,
    webNavigationApplication: BrowserWebLoadRuntimeCoordinator,
    transientSurfaceCoordinator: BrowserTransientSurfaceCoordinator,
    confirmationPresenter: BrowserConfirmationSink,
    readingWindowBrightnessService: ReadingWindowBrightnessService,
    tabHomeCoordinator: BrowserTabHomeCoordinator,
    tabSwitchCoordinator: BrowserTabSwitchCoordinator,
    tabScopedEventContextCoordinator: BrowserTabScopedEventContextCoordinator,
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    appUrlOpenCoordinator: BrowserAppUrlOpenCoordinator,
    captureSourceTabPreview: (tabId: string) => Promise<boolean>,
    isSourceTabVisible: (tabId: string) => boolean,
    handleAction: (action: NovelReaderAction) => void
  ) {
    this.webTopImmersionSessionCoordinator = webTopImmersionSessionCoordinator;
    this.webNavigationApplication = webNavigationApplication;
    this.transientSurfaceCoordinator = transientSurfaceCoordinator;
    this.confirmationPresenter = confirmationPresenter;
    this.readingWindowBrightnessService = readingWindowBrightnessService;
    this.tabHomeCoordinator = tabHomeCoordinator;
    this.tabSwitchCoordinator = tabSwitchCoordinator;
    this.tabScopedEventContextCoordinator = tabScopedEventContextCoordinator;
    this.runtimeLifecyclePort = runtimeLifecyclePort;
    this.appUrlOpenCoordinator = appUrlOpenCoordinator;
    this.captureSourceTabPreview = captureSourceTabPreview;
    this.isSourceTabVisible = isSourceTabVisible;
    this.handleAction = handleAction;
  }
}

export class NovelReaderApplication {
  private readonly dependencies: NovelReaderApplicationDependencies;
  private readonly clipboardService: BrowserClipboardService = new BrowserClipboardService();
  private readonly shareService: WebPageShareService = new WebPageShareService();
  private readonly takeoverPreviewCapturePort: NovelReaderTakeoverPreviewCapturePort;
  private boundSession?: NovelReaderSessionOperations;

  constructor(dependencies: NovelReaderApplicationDependencies) {
    this.dependencies = dependencies;
    this.takeoverPreviewCapturePort = new NovelReaderTakeoverPreviewCaptureAdapter(
      dependencies.captureSourceTabPreview,
      dependencies.isSourceTabVisible,
      dependencies.tabScopedEventContextCoordinator
    );
    dependencies.runtimeLifecyclePort.setAcceptedSpaRouteSignalListener(
      (signal: BrowserAcceptedSpaRouteSignal): void => this.handleAcceptedSpaRoute(signal)
    );
  }

  bindSession(
    session: NovelReaderSessionOperations,
    publishSnapshot: (snapshot: NovelReaderSnapshot) => void
  ): void {
    this.boundSession = session;
    session.connectTakeoverPreviewCapture(this.takeoverPreviewCapturePort);
    session.connectSessionListener({
      onSnapshotChanged: publishSnapshot,
      onEffect: (effect: NovelReaderEffect): boolean => this.apply(effect)
    });
  }

  handlePageReady(
    session: NovelReaderSessionOperations,
    tabId: string,
    activeTabId: string,
    webPageVisible: boolean,
    pageUrl: string,
    acceptedNavigationCommit: boolean = false
  ): void {
    const context = this.dependencies.tabScopedEventContextCoordinator.resolveContext(tabId);
    session.handlePageReadyForAutoDetection(this.dependencies.runtimeLifecyclePort, {
      tabId: tabId,
      activeTabId: activeTabId,
      webPageVisible: webPageVisible,
      pageUrl: pageUrl,
      acceptedNavigationCommitUrl: acceptedNavigationCommit ? pageUrl : '',
      scope: {
        tabId: tabId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      }
    });
  }

  handleNavigationEntryCommitted(
    session: NovelReaderSessionOperations,
    facts: NovelReaderNavigationCommitFacts
  ): void {
    if (!facts.isMainFrame || !facts.isSameDocument) {
      return;
    }
    this.reconcileAcceptedPageRoute(session, facts.tabId, facts.activeTabId,
      facts.webPageVisible, facts.pageUrl);
    if (!session.shouldHandleSpaRouteReprobe()) {
      return;
    }
    this.handlePageReady(
      session,
      facts.tabId,
      facts.activeTabId,
      facts.webPageVisible,
      facts.pageUrl,
      true
    );
  }

  private handleAcceptedSpaRoute(signal: BrowserAcceptedSpaRouteSignal): void {
    const session: NovelReaderSessionOperations | undefined = this.boundSession;
    const activeWebTab: boolean = this.dependencies.runtimeLifecyclePort.isActiveWebTab(signal.tabId);
    if (session === undefined || !activeWebTab) {
      return;
    }
    this.reconcileAcceptedPageRoute(session, signal.tabId, signal.tabId, true, signal.url);
    if (!session.shouldHandleSpaRouteReprobe()) {
      return;
    }
    this.handlePageReady(session, signal.tabId, signal.tabId, true, signal.url, true);
  }

  private reconcileAcceptedPageRoute(
    session: NovelReaderSessionOperations,
    tabId: string,
    activeTabId: string,
    webPageVisible: boolean,
    pageUrl: string
  ): void {
    const context = this.dependencies.tabScopedEventContextCoordinator.resolveContext(tabId);
    session.reconcileReentryForPageReady({
      tabId: tabId,
      activeTabId: activeTabId,
      webPageVisible: webPageVisible,
      pageUrl: pageUrl,
      acceptedNavigationCommitUrl: pageUrl,
      scope: {
        tabId: tabId,
        privacyMode: context.privacyMode,
        dataScope: context.dataScope
      }
    });
  }

  apply(effect: NovelReaderEffect): boolean {
    if (effect.type === 'open_catalog') {
      this.dependencies.transientSurfaceCoordinator.openSystemSheet('novelCatalog');
      return true;
    }
    if (effect.type === 'open_control_panel') {
      this.dependencies.transientSurfaceCoordinator.openSystemSheet(
        this.resolveControlPanelSheet(effect.panel)
      );
      return true;
    }
    if (effect.type === 'close_system_sheet') {
      this.dependencies.transientSurfaceCoordinator.closeSystemSheet();
      return true;
    }
    if (effect.type === 'apply_window_brightness') {
      this.dependencies.readingWindowBrightnessService.apply(
        'novel',
        AppRuntimeContext.getUIAbilityContext(),
        effect.brightnessMode,
        effect.brightnessPercent
      );
      return true;
    }
    if (effect.type === 'restore_window_brightness') {
      this.dependencies.readingWindowBrightnessService.release(
        'novel',
        AppRuntimeContext.getUIAbilityContext()
      );
      return true;
    }
    if (effect.type === 'show_exit_confirmation') {
      const modeLabel: string = resolveNovelReadingModeLabel(effect.contentKind);
      this.dependencies.confirmationPresenter.confirm({
        title: `退出${modeLabel}`,
        message: `确定要退出${modeLabel}并返回原网页吗？`,
        cancelLabel: '继续阅读',
        confirmLabel: '退出',
        onCancel: (): void => this.dependencies.handleAction({ type: 'cancel_close' }),
        onConfirm: (): void => this.dependencies.handleAction({ type: 'confirm_close' })
      });
      return true;
    }
    if (effect.type === 'reveal_browser_home') {
      void this.dependencies.tabHomeCoordinator.goHome();
      return true;
    }
    if (effect.type === 'activate_source_tab') {
      void this.dependencies.tabSwitchCoordinator.switchToTab(effect.tabId);
      return true;
    }
    if (effect.type === 'recover_suspended_reading') {
      if (effect.tabId.length > 0 &&
        this.dependencies.tabSwitchCoordinator.resolveTabSnapshot(effect.tabId) !== undefined) {
        void this.dependencies.tabSwitchCoordinator.switchToTab(effect.tabId).then((): void => {
          this.dependencies.webNavigationApplication.loadUrlForTab(effect.tabId, effect.url, true);
        });
      } else {
        this.dependencies.appUrlOpenCoordinator.open({
          url: effect.url,
          title: effect.title,
          intent: 'current_tab',
          source: 'app_ui',
          privacyMode: 'regular',
          dataScope: 'profile_persistent'
        });
      }
      return true;
    }
    if (effect.type === 'navigate_source_chapter') {
      return this.dependencies.webNavigationApplication.loadUrlForTab(effect.tabId, effect.url, true);
    }
    if (effect.type === 'copy_source_url') {
      void this.clipboardService.copyText({
        value: effect.url,
        emptyMessage: '当前没有可复制的网址。',
        successMessage: '链接已复制。'
      }).then((result: BrowserClipboardCopyResult): void => {
        this.showToast(result.message);
      }).catch((_error: Error): void => {
        this.showToast('复制失败，请稍后重试。');
      });
      return true;
    }
    if (effect.type === 'share_source_url') {
      void this.shareService.shareWebPage(AppRuntimeContext.getUIAbilityContext(), {
        title: effect.title,
        url: effect.url
      }).catch((_error: Error): void => {
        this.showToast('分享失败，请稍后重试。');
      });
      return true;
    }
    if (effect.type === 'toast') {
      this.showToast(effect.message);
      return true;
    }
    if (effect.type === 'status_bar_visibility_release') {
      this.dependencies.webTopImmersionSessionCoordinator.releaseVisibilityOverride(
        NOVEL_READER_STATUS_BAR_OWNER_ID,
        NOVEL_READER_STATUS_BAR_SOURCE
      );
      return true;
    }
    if (effect.type === 'status_bar_visibility_override') {
      this.dependencies.webTopImmersionSessionCoordinator.setVisibilityOverride(
        NOVEL_READER_STATUS_BAR_OWNER_ID,
        effect.visible,
        NOVEL_READER_STATUS_BAR_SOURCE
      );
      return true;
    }
    return false;
  }

  private showToast(message: string): void {
    promptAction.showToast({ message: message, duration: 1500 });
  }

  private resolveControlPanelSheet(panel: NovelReaderControlPanel): BrowserSystemSheetType {
    if (panel === 'appearance') {
      return 'novelReaderAppearance';
    }
    if (panel === 'settings') {
      return 'novelReaderSettings';
    }
    return 'novelReaderText';
  }
}
