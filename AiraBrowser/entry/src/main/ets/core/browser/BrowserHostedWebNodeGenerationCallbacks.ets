import { webview } from '@kit.ArkWeb';
import { HostedWebNodeCallbacks } from '../web/HostedWebNode';

export type BrowserHostedWebNodeGenerationGuard = (
  tabId: string,
  generation: number
) => boolean;

export function buildGenerationBoundHostedWebNodeCallbacks(
  tabId: string,
  generation: number,
  callbacks: HostedWebNodeCallbacks,
  isCurrent: BrowserHostedWebNodeGenerationGuard
): HostedWebNodeCallbacks {
  return {
    onControllerAttached: (eventTabId: string): void => {
      if (eventTabId === tabId && isCurrent(tabId, generation)) {
        callbacks.onControllerAttached(eventTabId);
      }
    },
    onBeforeWebBuild: (eventTabId: string): void => {
      if (eventTabId === tabId && isCurrent(tabId, generation)) {
        callbacks.onBeforeWebBuild?.(eventTabId);
      }
    },
    onPageVisible: (eventTabId: string, event: OnPageVisibleEvent): void => {
      if (eventTabId === tabId && isCurrent(tabId, generation)) {
        callbacks.onPageVisible(eventTabId, event);
      }
    },
    onPageBegin: callbacks.onPageBegin,
    onPageEnd: callbacks.onPageEnd,
    onNativeMediaPlayerObserved: callbacks.onNativeMediaPlayerObserved === undefined ? undefined :
      (eventTabId: string, mediaInfo: webview.MediaInfo): void => {
        if (eventTabId === tabId && isCurrent(tabId, generation)) {
          callbacks.onNativeMediaPlayerObserved?.(eventTabId, mediaInfo);
        }
      },
    onAudioStateChanged: callbacks.onAudioStateChanged === undefined ? undefined :
      (eventTabId: string, playing: boolean): void => {
        if (eventTabId === tabId && isCurrent(tabId, generation)) {
          callbacks.onAudioStateChanged?.(eventTabId, playing);
        }
      },
    onLoadFinished: callbacks.onLoadFinished,
    onProgressChange: callbacks.onProgressChange,
    onScroll: callbacks.onScroll,
    onTouch: callbacks.onTouch,
    onNavigationEntryCommitted: callbacks.onNavigationEntryCommitted,
    onTitleReceive: callbacks.onTitleReceive,
    onFaviconReceived: callbacks.onFaviconReceived,
    onSearchResultReceive: callbacks.onSearchResultReceive,
    onErrorReceive: callbacks.onErrorReceive,
    onPermissionRequest: callbacks.onPermissionRequest,
    onGeolocationShow: callbacks.onGeolocationShow,
    onWindowNew: callbacks.onWindowNew,
    onWindowExit: callbacks.onWindowExit,
    onActivateContent: callbacks.onActivateContent,
    onShowFileSelector: callbacks.onShowFileSelector,
    onPrompt: callbacks.onPrompt,
    onConfirm: callbacks.onConfirm,
    onAlert: callbacks.onAlert,
    onHttpAuthRequest: callbacks.onHttpAuthRequest,
    onSslErrorEvent: callbacks.onSslErrorEvent,
    onLoadIntercept: callbacks.onLoadIntercept,
    onInterceptRequest: callbacks.onInterceptRequest,
    onOverrideUrlLoading: callbacks.onOverrideUrlLoading,
    onDownloadStart: callbacks.onDownloadStart,
    onUserScriptInstallRequest: callbacks.onUserScriptInstallRequest,
    onHistoryApiUrlChange: callbacks.onHistoryApiUrlChange,
    onPageChromeThemeSignal: callbacks.onPageChromeThemeSignal,
    onPageBehaviorSignal: (eventTabId: string, payloadJson: string): void => {
      if (eventTabId === tabId && isCurrent(tabId, generation)) {
        callbacks.onPageBehaviorSignal(eventTabId, payloadJson);
      }
    },
    onAdBlockCosmeticHidden: callbacks.onAdBlockCosmeticHidden,
    onAdBlockManualHidden: callbacks.onAdBlockManualHidden,
    onContextMenuShow: callbacks.onContextMenuShow,
    onContextMenuHide: callbacks.onContextMenuHide,
    onFullScreenEnter: callbacks.onFullScreenEnter,
    onFullScreenExit: callbacks.onFullScreenExit
  };
}
