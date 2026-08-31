import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HostedWebNodeCallbacks } from '../web/HostedWebNode';

const WEB_EVENT_HOST_LOG_DOMAIN: number = 0x0000;
const WEB_EVENT_HOST_LOG_TAG: string = 'BrowserWebEventHost';

export interface BrowserWebEventHostHandlers {
  onControllerAttached: (tabId: string) => void;
  onBeforeWebBuild: (tabId: string) => void;
  onPageVisible: (tabId: string, event: OnPageVisibleEvent) => void;
  onPageBegin: (tabId: string, event: OnPageBeginEvent) => void;
  onPageEnd: (tabId: string, event: OnPageEndEvent) => void;
  onNativeMediaPlayerObserved: (tabId: string, mediaInfo: webview.MediaInfo) => void;
  onAudioStateChanged: (tabId: string, playing: boolean) => void;
  onLoadFinished: (tabId: string) => void;
  onProgressChange: (tabId: string, event: OnProgressChangeEvent) => void;
  onScroll: (tabId: string, event: OnScrollEvent) => void;
  onTouch: (tabId: string, event: TouchEvent) => void;
  onNavigationEntryCommitted: (tabId: string, details: LoadCommittedDetails) => void;
  onTitleReceive: (tabId: string, event: OnTitleReceiveEvent) => void;
  onFaviconReceived: (tabId: string, event: OnFaviconReceivedEvent) => void;
  onSearchResultReceive: (tabId: string, event: OnSearchResultReceiveEvent) => void;
  onErrorReceive: (tabId: string, event: OnErrorReceiveEvent) => void;
  onPermissionRequest: (tabId: string, request: PermissionRequest) => void;
  onGeolocationShow: (tabId: string, event: OnGeolocationShowEvent) => void;
  onWindowNew: (tabId: string, event: OnWindowNewEvent) => void;
  onWindowExit: (tabId: string) => void;
  onActivateContent: (tabId: string) => void;
  onShowFileSelector: (tabId: string, event: OnShowFileSelectorEvent) => boolean;
  onPrompt: (tabId: string, event: OnPromptEvent) => void;
  onConfirm: (tabId: string, event: OnConfirmEvent) => void;
  onAlert: (tabId: string, event: OnAlertEvent) => void;
  onHttpAuthRequest: (tabId: string, event: OnHttpAuthRequestEvent) => void;
  onSslErrorEvent: (tabId: string, event: SslErrorEvent) => void;
  onLoadIntercept: (tabId: string, event: OnLoadInterceptEvent) => boolean;
  onInterceptRequest: (tabId: string, event: OnInterceptRequestEvent) => WebResourceResponse | null;
  onOverrideUrlLoading: (tabId: string, request: WebResourceRequest) => boolean;
  onDownloadStart: (tabId: string, event: OnDownloadStartEvent) => void;
  onUserScriptInstallRequest: (tabId: string, url: string) => void;
  onHistoryApiUrlChange: (tabId: string, payloadJson: string) => void;
  onPageChromeThemeSignal: (tabId: string, payloadJson: string) => void;
  onPageBehaviorSignal: (tabId: string, payloadJson: string) => void;
  onAdBlockCosmeticHidden: (tabId: string, payloadJson: string) => void;
  onAdBlockManualHidden: (tabId: string, payloadJson: string) => void;
  onContextMenuShow: (tabId: string, event: OnContextMenuShowEvent, controller: webview.WebviewController) => boolean;
  onContextMenuHide: (tabId: string) => void;
  onFullScreenEnter: (tabId: string, event: FullScreenEnterEvent) => void;
  onFullScreenExit: (tabId: string) => void;
}

export class BrowserWebEventHostCoordinator {
  buildCallbacks(handlers: BrowserWebEventHostHandlers): HostedWebNodeCallbacks {
    return {
      onControllerAttached: (tabId: string) =>
        this.runVoid('controller_attached', tabId, () => handlers.onControllerAttached(tabId)),
      onBeforeWebBuild: (tabId: string) =>
        this.runVoid('before_web_build', tabId, () => handlers.onBeforeWebBuild(tabId)),
      onPageVisible: (tabId: string, event: OnPageVisibleEvent) =>
        this.runVoid('page_visible', tabId, () => handlers.onPageVisible(tabId, event)),
      onPageBegin: (tabId: string, event: OnPageBeginEvent) =>
        this.runVoid('page_begin', tabId, () => handlers.onPageBegin(tabId, event)),
      onPageEnd: (tabId: string, event: OnPageEndEvent) =>
        this.runVoid('page_end', tabId, () => handlers.onPageEnd(tabId, event)),
      onNativeMediaPlayerObserved: (tabId: string, mediaInfo: webview.MediaInfo) =>
        this.runVoid('native_media_player_observed', tabId,
          () => handlers.onNativeMediaPlayerObserved(tabId, mediaInfo)),
      onAudioStateChanged: (tabId: string, playing: boolean) =>
        this.runVoid('audio_state_changed', tabId, () => handlers.onAudioStateChanged(tabId, playing)),
      onLoadFinished: (tabId: string) =>
        this.runVoid('load_finished', tabId, () => handlers.onLoadFinished(tabId)),
      onProgressChange: (tabId: string, event: OnProgressChangeEvent) =>
        this.runVoid('progress_change', tabId, () => handlers.onProgressChange(tabId, event)),
      onScroll: (tabId: string, event: OnScrollEvent) =>
        this.runVoid('scroll', tabId, () => handlers.onScroll(tabId, event)),
      onTouch: (tabId: string, event: TouchEvent) =>
        this.runVoid('touch', tabId, () => handlers.onTouch(tabId, event)),
      onNavigationEntryCommitted: (tabId: string, details: LoadCommittedDetails) =>
        this.runVoid('navigation_entry_committed', tabId, () => handlers.onNavigationEntryCommitted(tabId, details)),
      onTitleReceive: (tabId: string, event: OnTitleReceiveEvent) =>
        this.runVoid('title_receive', tabId, () => handlers.onTitleReceive(tabId, event)),
      onFaviconReceived: (tabId: string, event: OnFaviconReceivedEvent) =>
        this.runVoid('favicon_received', tabId, () => handlers.onFaviconReceived(tabId, event)),
      onSearchResultReceive: (tabId: string, event: OnSearchResultReceiveEvent) =>
        this.runVoid('search_result_receive', tabId, () => handlers.onSearchResultReceive(tabId, event)),
      onErrorReceive: (tabId: string, event: OnErrorReceiveEvent) =>
        this.runVoid('error_receive', tabId, () => handlers.onErrorReceive(tabId, event)),
      onPermissionRequest: (tabId: string, request: PermissionRequest) =>
        this.runVoid('permission_request', tabId, () => handlers.onPermissionRequest(tabId, request)),
      onGeolocationShow: (tabId: string, event: OnGeolocationShowEvent) =>
        this.runVoid('geolocation_show', tabId, () => handlers.onGeolocationShow(tabId, event)),
      onWindowNew: (tabId: string, event: OnWindowNewEvent) =>
        this.runVoid('window_new', tabId, () => handlers.onWindowNew(tabId, event)),
      onWindowExit: (tabId: string) =>
        this.runVoid('window_exit', tabId, () => handlers.onWindowExit(tabId)),
      onActivateContent: (tabId: string) =>
        this.runVoid('activate_content', tabId, () => handlers.onActivateContent(tabId)),
      onShowFileSelector: (tabId: string, event: OnShowFileSelectorEvent) =>
        this.runBoolean('show_file_selector', tabId, false, false,
          () => handlers.onShowFileSelector(tabId, event)),
      onPrompt: (tabId: string, event: OnPromptEvent) => {
        return this.runBoolean('prompt', tabId, true, false, () => handlers.onPrompt(tabId, event));
      },
      onConfirm: (tabId: string, event: OnConfirmEvent) => {
        return this.runBoolean('confirm', tabId, true, false, () => handlers.onConfirm(tabId, event));
      },
      onAlert: (tabId: string, event: OnAlertEvent) => {
        return this.runBoolean('alert', tabId, true, false, () => handlers.onAlert(tabId, event));
      },
      onHttpAuthRequest: (tabId: string, event: OnHttpAuthRequestEvent) => {
        return this.runBoolean('http_auth_request', tabId, true, false,
          () => handlers.onHttpAuthRequest(tabId, event));
      },
      onSslErrorEvent: (tabId: string, event: SslErrorEvent) =>
        this.runVoid('ssl_error_event', tabId, () => handlers.onSslErrorEvent(tabId, event)),
      onLoadIntercept: (tabId: string, event: OnLoadInterceptEvent) =>
        this.runBoolean('load_intercept', tabId, false, false, () => handlers.onLoadIntercept(tabId, event)),
      onInterceptRequest: (tabId: string, event: OnInterceptRequestEvent) =>
        this.runResponse('intercept_request', tabId, () => handlers.onInterceptRequest(tabId, event)),
      onOverrideUrlLoading: (tabId: string, request: WebResourceRequest) =>
        this.runBoolean('override_url_loading', tabId, false, false,
          () => handlers.onOverrideUrlLoading(tabId, request)),
      onDownloadStart: (tabId: string, event: OnDownloadStartEvent) =>
        this.runVoid('download_start', tabId, () => handlers.onDownloadStart(tabId, event)),
      onUserScriptInstallRequest: (tabId: string, url: string) =>
        this.runVoid('userscript_install_request', tabId, () => handlers.onUserScriptInstallRequest(tabId, url)),
      onHistoryApiUrlChange: (tabId: string, payloadJson: string) =>
        this.runVoid('history_api_url_change', tabId, () => handlers.onHistoryApiUrlChange(tabId, payloadJson)),
      onPageChromeThemeSignal: (tabId: string, payloadJson: string) =>
        this.runVoid('page_chrome_theme_signal', tabId,
          () => handlers.onPageChromeThemeSignal(tabId, payloadJson)),
      onPageBehaviorSignal: (tabId: string, payloadJson: string) =>
        this.runVoid('page_behavior_signal', tabId, () => handlers.onPageBehaviorSignal(tabId, payloadJson)),
      onAdBlockCosmeticHidden: (tabId: string, payloadJson: string) =>
        this.runVoid('adblock_cosmetic_hidden', tabId, () => handlers.onAdBlockCosmeticHidden(tabId, payloadJson)),
      onAdBlockManualHidden: (tabId: string, payloadJson: string) =>
        this.runVoid('adblock_manual_hidden', tabId, () => handlers.onAdBlockManualHidden(tabId, payloadJson)),
      onContextMenuShow: (tabId: string, event: OnContextMenuShowEvent, controller: webview.WebviewController) => {
        return this.runBoolean('context_menu_show', tabId, false,
          false,
          () => handlers.onContextMenuShow(tabId, event, controller));
      },
      onContextMenuHide: (tabId: string) =>
        this.runVoid('context_menu_hide', tabId, () => handlers.onContextMenuHide(tabId)),
      onFullScreenEnter: (tabId: string, event: FullScreenEnterEvent) =>
        this.runVoid('fullscreen_enter', tabId, () => handlers.onFullScreenEnter(tabId, event)),
      onFullScreenExit: (tabId: string) =>
        this.runVoid('fullscreen_exit', tabId, () => handlers.onFullScreenExit(tabId))
    };
  }

  private runVoid(eventName: string, tabId: string, action: () => void): void {
    try {
      action();
    } catch (error) {
      this.logHandlerFailure(eventName, tabId, error);
    }
  }

  private runBoolean(
    eventName: string,
    tabId: string,
    defaultValue: boolean,
    failureFallback: boolean,
    action: () => boolean | void
  ): boolean {
    try {
      const result = action();
      return typeof result === 'boolean' ? result : defaultValue;
    } catch (error) {
      this.logHandlerFailure(eventName, tabId, error);
      return failureFallback;
    }
  }

  private runResponse(
    eventName: string,
    tabId: string,
    action: () => WebResourceResponse | null
  ): WebResourceResponse | null {
    try {
      return action();
    } catch (error) {
      this.logHandlerFailure(eventName, tabId, error);
      return null;
    }
  }

  private logHandlerFailure(eventName: string, tabId: string, error: Object): void {
    hilog.warn(
      WEB_EVENT_HOST_LOG_DOMAIN,
      WEB_EVENT_HOST_LOG_TAG,
      'web event handler failed event=%{public}s tab=%{public}s error=%{public}s',
      eventName,
      tabId,
      this.stringifyError(error)
    );
  }

  private stringifyError(error: Object): string {
    try {
      return JSON.stringify(error);
    } catch (_stringifyError) {
      return 'unserializable_error';
    }
  }
}
