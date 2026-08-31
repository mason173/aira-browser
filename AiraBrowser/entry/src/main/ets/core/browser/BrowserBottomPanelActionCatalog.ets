import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';

export type BrowserBottomPanelActionId =
  'bookmark' |
  'scanQr' |
  'openBookmarks' |
  'scripts' |
  'find' |
  'settings' |
  'appProxySettings' |
  'home' |
  'share' |
  'sendToDesktop' |
  'print' |
  'copyLink' |
  'addToDesktop' |
  'userAgent' |
  'textZoom' |
  'userAgentPreset' |
  'screenOrientation' |
  'themeMode' |
  'fullScreenMode' |
  'manualElementHide' |
  'elementInspection' |
  'translate' |
  'reader' |
  'novel' |
  'video' |
  'offline' |
  'savedPages' |
  'downloads' |
  'history' |
  'siteInfo' |
  'reportSite' |
  'openOriginal' |
  'details' |
  'exportPage' |
  'deletePage' |
  'decreaseFont' |
  'increaseFont' |
  'theme' |
  'readAloud' |
  'lineHeight' |
  'pageWidth' |
  'viewerInfo' |
  'newTab' |
  'newPrivateTab' |
  'closeAllTabs' |
  'clearHistory';

export type BrowserBottomPanelSurface = 'web' | 'home' | 'tabs' | 'viewer' | 'offline' | 'reader';

export interface BrowserBottomPanelActionCatalogEntry {
  id: BrowserBottomPanelActionId;
  title: string;
  subtitle: string;
  customizable: boolean;
  surfaces: BrowserBottomPanelSurface[];
}

export class BrowserBottomPanelActionCatalog {
  private static cachedEntries?: BrowserBottomPanelActionCatalogEntry[];
  private static cachedEntriesById?: Map<BrowserBottomPanelActionId, BrowserBottomPanelActionCatalogEntry>;

  static customizableActionIds(): BrowserBottomPanelActionId[] {
    return BrowserBottomPanelActionCatalog.entries()
      .filter((entry: BrowserBottomPanelActionCatalogEntry) => entry.customizable)
      .map((entry: BrowserBottomPanelActionCatalogEntry) => entry.id);
  }

  static entry(actionId: BrowserBottomPanelActionId): BrowserBottomPanelActionCatalogEntry {
    const item = BrowserBottomPanelActionCatalog.resolveEntriesById().get(actionId);
    return item ?? {
      id: actionId,
      title: '工具',
      subtitle: '',
      customizable: false,
      surfaces: []
    };
  }

  static title(actionId: BrowserBottomPanelActionId): string {
    return BrowserBottomPanelActionCatalog.entry(actionId).title;
  }

  static subtitle(actionId: BrowserBottomPanelActionId): string {
    return BrowserBottomPanelActionCatalog.entry(actionId).subtitle;
  }

  static iconId(actionId: BrowserBottomPanelActionId | string): AiraRenderableIconId {
    switch (actionId) {
      case 'bookmark':
        return 'browser.toolbar.addBookmark';
      case 'scanQr':
        return 'browser.toolbar.scanQr';
      case 'openBookmarks':
        return 'browser.shortcut.bookmarks';
      case 'scripts':
        return 'browser.shortcut.scripts';
      case 'find':
        return 'browser.toolbar.search';
      case 'settings':
        return 'browser.shortcut.settings';
      case 'appProxySettings':
        return 'browser.toolbar.connectionSecurity';
      case 'siteInfo':
        return 'settings.about';
      case 'home':
        return 'browser.shortcut.home';
      case 'share':
        return 'browser.toolbar.sharePage';
      case 'sendToDesktop':
        return 'browser.toolbar.sendToDesktop';
      case 'print':
        return 'browser.toolbar.printPage';
      case 'copyLink':
        return 'browser.toolbar.actionCopyLink';
      case 'addToDesktop':
        return 'browser.toolbar.addToDesktop';
      case 'userAgent':
        return 'settings.siteSettings';
      case 'textZoom':
      case 'increaseFont':
        return 'reader.increaseFont';
      case 'userAgentPreset':
        return 'browser.toolbar.userAgentPreset';
      case 'screenOrientation':
        return 'browser.toolbar.screenOrientation';
      case 'themeMode':
        return 'browser.toolbar.themeMode';
      case 'fullScreenMode':
        return 'browser.toolbar.fullScreen';
      case 'manualElementHide':
        return 'settings.adBlocker';
      case 'elementInspection':
        return 'browser.toolbar.actionElementInspection';
      case 'translate':
        return 'browser.toolbar.actionTranslate';
      case 'reader':
        return 'browser.toolbar.reader';
      case 'novel':
        return 'browser.toolbar.bookshelf';
      case 'video':
        return 'browser.shortcut.pageResources';
      case 'offline':
        return 'browser.toolbar.offline';
      case 'savedPages':
        return 'browser.toolbar.savedPages';
      case 'downloads':
        return 'browser.shortcut.downloads';
      case 'history':
        return 'browser.shortcut.history';
      case 'reportSite':
        return 'browser.toolbar.reportSite';
      case 'openOriginal':
        return 'offline.openOriginal';
      case 'details':
      case 'viewerInfo':
        return 'browser.toolbar.siteInfo';
      case 'exportPage':
        return 'browser.toolbar.shareDocument';
      case 'deletePage':
      case 'closeAllTabs':
      case 'clearHistory':
        return 'browser.tabs.delete';
      case 'decreaseFont':
        return 'reader.decreaseFont';
      case 'theme':
        return 'reader.theme';
      case 'readAloud':
        return 'reader.readAloud';
      case 'lineHeight':
        return 'reader.lineHeight';
      case 'pageWidth':
        return 'reader.pageWidth';
      case 'newTab':
        return 'browser.tabs.add';
      case 'newPrivateTab':
        return 'browser.toolbar.privacyMode';
      default:
        return 'browser.toolbar.more';
    }
  }

  static entries(): BrowserBottomPanelActionCatalogEntry[] {
    if (BrowserBottomPanelActionCatalog.cachedEntries === undefined) {
      BrowserBottomPanelActionCatalog.cachedEntries = BrowserBottomPanelActionCatalog.buildEntries();
    }
    return BrowserBottomPanelActionCatalog.cachedEntries;
  }

  private static resolveEntriesById(): Map<BrowserBottomPanelActionId, BrowserBottomPanelActionCatalogEntry> {
    if (BrowserBottomPanelActionCatalog.cachedEntriesById !== undefined) {
      return BrowserBottomPanelActionCatalog.cachedEntriesById;
    }
    const result = new Map<BrowserBottomPanelActionId, BrowserBottomPanelActionCatalogEntry>();
    BrowserBottomPanelActionCatalog.entries().forEach((entry: BrowserBottomPanelActionCatalogEntry) => {
      result.set(entry.id, entry);
    });
    BrowserBottomPanelActionCatalog.cachedEntriesById = result;
    return result;
  }

  private static buildEntries(): BrowserBottomPanelActionCatalogEntry[] {
    return [
      { id: 'bookmark', title: '添加书签', subtitle: '当前网页', customizable: true, surfaces: ['web', 'reader'] },
      { id: 'scanQr', title: '扫一扫', subtitle: '二维码', customizable: true, surfaces: ['web', 'home'] },
      { id: 'copyLink', title: '复制链接', subtitle: 'URL', customizable: true, surfaces: ['web', 'offline', 'reader'] },
      { id: 'share', title: '分享网页', subtitle: '系统分享', customizable: true, surfaces: ['web', 'offline', 'reader'] },
      { id: 'sendToDesktop', title: '推送到电脑', subtitle: '打开当前页', customizable: true, surfaces: ['web'] },
      { id: 'print', title: '打印网页', subtitle: '系统打印', customizable: true, surfaces: ['web'] },
      { id: 'userAgent', title: '网站版本', subtitle: '当前站点', customizable: true, surfaces: ['web'] },
      { id: 'textZoom', title: '网页文字大小', subtitle: '字号缩放', customizable: true, surfaces: ['web'] },
      { id: 'fullScreenMode', title: '全屏模式', subtitle: '沉浸浏览', customizable: true, surfaces: ['web'] },
      { id: 'manualElementHide', title: '标记广告', subtitle: '手动隐藏', customizable: true, surfaces: ['web'] },
      { id: 'elementInspection', title: '审查元素', subtitle: '查看网页代码', customizable: true, surfaces: ['web'] },
      { id: 'reader', title: '阅读模式', subtitle: '阅读视图', customizable: true, surfaces: ['web', 'offline'] },
      { id: 'novel', title: '我的书架', subtitle: '收藏的小说', customizable: true, surfaces: ['web', 'home'] },
      { id: 'translate', title: '翻译网页', subtitle: '网页翻译', customizable: true, surfaces: ['web'] },
      { id: 'scripts', title: '用户脚本', subtitle: '脚本管理', customizable: true, surfaces: ['web', 'home'] },
      { id: 'themeMode', title: '外观模式', subtitle: '明暗模式', customizable: true, surfaces: ['web'] },
      { id: 'userAgentPreset', title: '网页标识', subtitle: '高级设置', customizable: false, surfaces: [] },
      { id: 'screenOrientation', title: '屏幕方向', subtitle: '横竖屏', customizable: true, surfaces: ['web'] },
      { id: 'addToDesktop', title: '作为应用安装', subtitle: '安装应用', customizable: true, surfaces: ['web'] },
      { id: 'offline', title: '保存离线网页', subtitle: '离线保存', customizable: true, surfaces: ['web'] },
      { id: 'video', title: '资源嗅探', subtitle: '媒体与文件', customizable: true, surfaces: ['web'] },
      { id: 'siteInfo', title: '站点信息', subtitle: '安全与权限', customizable: true, surfaces: ['web'] },
      { id: 'reportSite', title: '举报网站', subtitle: '反馈问题', customizable: true, surfaces: ['web'] },
      { id: 'openBookmarks', title: '书签', subtitle: '收藏', customizable: true, surfaces: ['web', 'home', 'reader', 'offline'] },
      { id: 'history', title: '历史记录', subtitle: '访问', customizable: true, surfaces: ['web', 'home'] },
      { id: 'savedPages', title: '已保存页面', subtitle: '离线管理', customizable: true, surfaces: ['web', 'home'] },
      { id: 'downloads', title: '下载管理', subtitle: '下载记录', customizable: true, surfaces: ['web', 'home'] },
      { id: 'settings', title: '设置', subtitle: '偏好', customizable: true, surfaces: ['web', 'home'] },
      { id: 'appProxySettings', title: '代理设置', subtitle: '快速切换', customizable: true, surfaces: ['web', 'home'] },
      { id: 'home', title: '主页', subtitle: '新标签', customizable: true, surfaces: ['web', 'home', 'tabs', 'viewer'] },
      { id: 'find', title: '查找网页', subtitle: '页内文字', customizable: true, surfaces: ['web', 'offline', 'reader'] },
      { id: 'openOriginal', title: '打开原网页', subtitle: '在线', customizable: false, surfaces: ['offline'] },
      { id: 'details', title: '页面详情', subtitle: '信息', customizable: false, surfaces: ['offline'] },
      { id: 'exportPage', title: '导出网页', subtitle: 'HTML', customizable: false, surfaces: ['offline'] },
      { id: 'deletePage', title: '删除离线页面', subtitle: '删除', customizable: false, surfaces: ['offline'] },
      { id: 'decreaseFont', title: '减小字号', subtitle: '字号', customizable: false, surfaces: ['reader'] },
      { id: 'increaseFont', title: '增大字号', subtitle: '字号', customizable: false, surfaces: ['reader'] },
      { id: 'theme', title: '切换主题', subtitle: '外观', customizable: false, surfaces: ['reader'] },
      { id: 'readAloud', title: '朗读', subtitle: '语音', customizable: false, surfaces: ['reader'] },
      { id: 'lineHeight', title: '切换行距', subtitle: '排版', customizable: false, surfaces: ['reader'] },
      { id: 'pageWidth', title: '阅读区域宽度', subtitle: '版心', customizable: false, surfaces: ['reader'] },
      { id: 'viewerInfo', title: '文件信息', subtitle: '只读查看', customizable: false, surfaces: ['viewer'] },
      { id: 'newTab', title: '新建标签', subtitle: '普通', customizable: false, surfaces: ['tabs'] },
      { id: 'newPrivateTab', title: '隐私模式', subtitle: '私密', customizable: true, surfaces: ['web', 'home', 'tabs'] },
      { id: 'closeAllTabs', title: '关闭所有标签页', subtitle: '标签页', customizable: false, surfaces: ['tabs'] },
      { id: 'clearHistory', title: '清除历史记录', subtitle: '历史', customizable: false, surfaces: ['tabs'] }
    ];
  }
}
