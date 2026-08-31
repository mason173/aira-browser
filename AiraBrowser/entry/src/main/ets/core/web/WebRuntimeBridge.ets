import { webview } from '@kit.ArkWeb';
import { BrowserDownloadNavigationStateCoordinator } from '../browser/BrowserDownloadNavigationStateCoordinator';
import { BrowserTabState } from '../tabs/TabManager';

export interface WebNavigationState {
  history: string[];
  index: number;
}

export interface WebNavigationCapabilities {
  canGoBack: boolean;
  canGoForward: boolean;
}

export interface WebPagePresentation {
  currentUrl: string;
  addressInput: string;
  currentTitle: string;
  helperMessage: string;
  pageProgress: number;
  isLoading: boolean;
}

export interface WebNavigateHistoryResult {
  handled: boolean;
  navigation: WebNavigationState;
  targetUrl?: string;
  errorMessage?: string;
}

export interface WebSessionRestorePlan {
  tabId: string;
  snapshotPath: string;
  targetUrl: string;
  helperMessage: string;
}

export interface WebWindowOpenAction {
  type: 'ignore' | 'download' | 'external' | 'new_tab';
  targetUrl: string;
  helperMessage: string;
  title: string;
}

export interface WebFileSelectorPlan {
  type: 'save' | 'select' | 'folder_unsupported';
  suggestedName: string;
  maxSelectNumber: number;
  suffixFilters: string[];
}

export interface WebHttpAuthDialogModel {
  host: string;
  realm: string;
}

export interface WebSslWarningModel {
  title: string;
  message: string;
  cancelLabel: string;
  confirmLabel: string;
}

const WEB_FILE_FILTER_IMAGES: string = '图片|.jpg,.jpeg,.png,.gif,.bmp,.webp,.svg,.heic,.heif';
const WEB_FILE_FILTER_VIDEOS: string = '视频|.mp4,.mov,.m4v,.mkv,.webm,.avi';
const WEB_FILE_FILTER_AUDIOS: string = '音频|.mp3,.m4a,.aac,.wav,.flac,.ogg,.opus';
const WEB_FILE_FILTER_TEXTS: string = '文本|.txt,.md,.csv,.json,.xml,.log';
export const WEB_TRANSIENT_LOADING_TITLE: string = '页面加载中';

export class WebRuntimeBridge {
  private downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator;

  constructor(downloadNavigationStateCoordinator: BrowserDownloadNavigationStateCoordinator) {
    this.downloadNavigationStateCoordinator = downloadNavigationStateCoordinator;
  }

  getCapabilitySummary(): string {
    return 'Web 组件运行时、事件桥接、下载与导航状态将统一收口到 core/web。';
  }

  getDefaultSearchPlaceholder(): string {
    return '搜索或输入网址';
  }

  getInitialHomeUrl(): string {
    return 'https://developer.huawei.com/consumer/cn/doc/';
  }

  createController(): webview.WebviewController {
    return new webview.WebviewController();
  }

  loadPendingUrl(controller: webview.WebviewController, pendingUrl: string, currentUrl: string): void {
    const targetUrl = pendingUrl.length > 0 ? pendingUrl : currentUrl;
    if (targetUrl.length === 0) {
      return;
    }
    controller.loadUrl(targetUrl);
  }

  buildSessionRestorePlan(tab: BrowserTabState, reason: string): WebSessionRestorePlan | undefined {
    if (tab.isHome) {
      return undefined;
    }

    return {
      tabId: tab.id,
      snapshotPath: tab.webStatePath,
      targetUrl: this.resolveSessionRestoreTargetUrl(tab),
      helperMessage: reason === 'controller-attach' ? '正在恢复标签页内容' : '正在切换标签页内容'
    };
  }

  resolvePageBegin(event: OnPageBeginEvent, addressDisplayText: string): WebPagePresentation {
    return {
      currentUrl: event.url,
      addressInput: addressDisplayText,
      currentTitle: WEB_TRANSIENT_LOADING_TITLE,
      helperMessage: '页面正在加载',
      pageProgress: 0,
      isLoading: true
    };
  }

  resolvePageEnd(event: OnPageEndEvent, addressDisplayText: string, currentTitle: string): WebPagePresentation {
    return {
      currentUrl: event.url,
      addressInput: addressDisplayText,
      currentTitle: currentTitle,
      helperMessage: '页面已加载完成',
      pageProgress: 100,
      isLoading: false
    };
  }

  syncNavigationState(
    _controller: webview.WebviewController,
    _controllerAttached: boolean,
    _navigation: WebNavigationState
  ): WebNavigationCapabilities {
    return {
      canGoBack: false,
      canGoForward: false
    };
  }

  recordNavigation(navigation: WebNavigationState, url: string): WebNavigationState {
    if (url.length === 0) {
      return navigation;
    }
    if (navigation.index >= 0 && navigation.index < navigation.history.length &&
      this.normalizeNavigationTarget(navigation.history[navigation.index]) === this.normalizeNavigationTarget(url)) {
      return navigation;
    }

    const retainedHistory = navigation.index >= 0 ? navigation.history.slice(0, navigation.index + 1) : [];
    const nextHistory = retainedHistory.concat([url]);
    return {
      history: nextHistory,
      index: nextHistory.length - 1
    };
  }

  navigateHistory(
    controller: webview.WebviewController,
    navigation: WebNavigationState,
    step: number
  ): WebNavigateHistoryResult {
    const nextIndex = navigation.index + step;
    if (nextIndex < 0 || nextIndex >= navigation.history.length) {
      const result: WebNavigateHistoryResult = {
        handled: false,
        navigation: navigation
      };
      return result;
    }

    const targetUrl = navigation.history[nextIndex];
    try {
      controller.loadUrl(targetUrl);
      const nextNavigation: WebNavigationState = {
        history: navigation.history.slice(),
        index: nextIndex
      };
      const result: WebNavigateHistoryResult = {
        handled: true,
        navigation: nextNavigation,
        targetUrl: targetUrl
      };
      return result;
    } catch (error) {
      const result: WebNavigateHistoryResult = {
        handled: true,
        navigation: navigation,
        errorMessage: `历史记录切换失败：${JSON.stringify(error)}`
      };
      return result;
    }
  }

  canLoadInWebView(url: string): boolean {
    const scheme = this.getUrlScheme(url);
    return scheme === 'http' || scheme === 'https' || scheme === 'file' || scheme === 'about' || scheme === 'data' ||
      scheme === 'blob' || scheme === 'javascript';
  }

  buildWindowOpenAction(targetUrl: string, isAlert: boolean): WebWindowOpenAction {
    const trimmedUrl = targetUrl.trim();
    if (trimmedUrl.length === 0) {
      return {
        type: 'ignore',
        targetUrl: '',
        helperMessage: '网页没有提供可打开的地址',
        title: ''
      };
    }

    if (!this.canLoadInWebView(trimmedUrl)) {
      return {
        type: 'download',
        targetUrl: trimmedUrl,
        helperMessage: `尝试处理外部资源：${trimmedUrl}`,
        title: trimmedUrl
      };
    }

    return {
      type: 'new_tab',
      targetUrl: trimmedUrl,
      helperMessage: isAlert ? '已在新标签页中打开弹出页面' : '已在新标签页中打开链接',
      title: isAlert ? '新窗口页面' : trimmedUrl
    };
  }

  buildFileSelectorPlan(fileSelector: FileSelectorParam): WebFileSelectorPlan {
    const mode = fileSelector.getMode();
    if (mode === FileSelectorMode.FileSaveMode) {
      return {
        type: 'save',
        suggestedName: this.resolveWebFileSuggestedName(fileSelector),
        maxSelectNumber: 1,
        suffixFilters: this.resolveWebFileSuffixFilters(fileSelector)
      };
    }

    if (mode === FileSelectorMode.FileOpenFolderMode) {
      return {
        type: 'folder_unsupported',
        suggestedName: '',
        maxSelectNumber: 0,
        suffixFilters: []
      };
    }

    return {
      type: 'select',
      suggestedName: '',
      maxSelectNumber: mode === FileSelectorMode.FileOpenMultipleMode ? 100 : 1,
      suffixFilters: this.resolveWebFileSuffixFilters(fileSelector)
    };
  }

  buildHttpAuthDialogModel(event: OnHttpAuthRequestEvent): WebHttpAuthDialogModel {
    return {
      host: event.host,
      realm: event.realm
    };
  }

  buildSslWarningModel(event: SslErrorEvent): WebSslWarningModel {
    const url = event.url.length > 0 ? event.url : '当前网页';
    return {
      title: '证书安全警告',
      message: `${url} 的证书校验失败。继续访问可能存在风险。`,
      cancelLabel: '返回安全页面',
      confirmLabel: '继续访问'
    };
  }

  buildHttpsFirstFallbackWarningModel(failedUrl: string, fallbackUrl: string): WebSslWarningModel {
    const url = failedUrl.length > 0 ? failedUrl : '当前网页';
    return {
      title: '无法建立安全连接',
      message: `${url} 无法通过 HTTPS 安全访问。你可以返回，或继续使用不安全的 HTTP 连接 ${fallbackUrl}。`,
      cancelLabel: '返回安全页面',
      confirmLabel: '使用 HTTP 继续'
    };
  }

  getUrlScheme(url: string): string {
    const match = url.trim().match(/^([a-z][a-z0-9+.-]*):/i);
    return match === null ? '' : match[1].toLowerCase();
  }

  private resolveSessionRestoreTargetUrl(tab: BrowserTabState): string {
    return this.downloadNavigationStateCoordinator.resolveRestorableNavigation(tab).url;
  }

  private resolveWebFileSuggestedName(fileSelector: FileSelectorParam): string {
    try {
      const suggestedName = fileSelector.getSuggestedName().trim();
      if (suggestedName.length > 0) {
        return suggestedName;
      }
    } catch (_error) {
    }

    const title = fileSelector.getTitle().trim();
    return title.length > 0 ? title : `aira-upload-${Date.now()}`;
  }

  private resolveWebFileSuffixFilters(fileSelector: FileSelectorParam): Array<string> {
    const acceptTypes = fileSelector.getAcceptType()
      .map((item: string) => item.trim().toLowerCase())
      .filter((item: string) => item.length > 0);
    if (acceptTypes.length === 0 || acceptTypes.includes('*/*') || acceptTypes.includes('*')) {
      return [];
    }

    const mappedFilters: string[] = [];
    const extensionFilters: string[] = [];
    acceptTypes.forEach((acceptType: string) => {
      if (acceptType.startsWith('.')) {
        extensionFilters.push(acceptType);
        return;
      }
      switch (acceptType) {
        case 'image/*':
          mappedFilters.push(WEB_FILE_FILTER_IMAGES);
          return;
        case 'video/*':
          mappedFilters.push(WEB_FILE_FILTER_VIDEOS);
          return;
        case 'audio/*':
          mappedFilters.push(WEB_FILE_FILTER_AUDIOS);
          return;
        case 'text/*':
          mappedFilters.push(WEB_FILE_FILTER_TEXTS);
          return;
        case 'application/pdf':
          extensionFilters.push('.pdf');
          return;
        case 'application/json':
          extensionFilters.push('.json');
          return;
        case 'application/zip':
        case 'application/x-zip-compressed':
          extensionFilters.push('.zip');
          return;
        case 'text/plain':
          extensionFilters.push('.txt');
          return;
        case 'text/csv':
          extensionFilters.push('.csv');
          return;
        case 'application/xml':
        case 'text/xml':
          extensionFilters.push('.xml');
          return;
        default:
          return;
      }
    });

    const uniqueMappedFilters = Array.from(new Set(mappedFilters));
    const uniqueExtensions = Array.from(new Set(extensionFilters));
    if (uniqueExtensions.length > 0) {
      uniqueMappedFilters.push(`网页允许的文件|${uniqueExtensions.join(',')}`);
    }
    return uniqueMappedFilters;
  }

  private normalizeNavigationTarget(url: string): string {
    const trimmed = url.trim().toLowerCase();
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }
}
