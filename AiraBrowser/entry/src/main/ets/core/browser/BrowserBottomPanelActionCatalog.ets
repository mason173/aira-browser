import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import {
  bottomPanelActionSubtitle,
  bottomPanelActionTitle
} from './BrowserBottomPanelText';

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
  'webZoom' |
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
  title: ResourceStr;
  subtitle: ResourceStr;
  customizable: boolean;
  surfaces: BrowserBottomPanelSurface[];
}

interface BrowserBottomPanelActionCatalogRecord {
  id: BrowserBottomPanelActionId;
  customizable: boolean;
  surfaces: BrowserBottomPanelSurface[];
}

export class BrowserBottomPanelActionCatalog {
  private static cachedEntries?: BrowserBottomPanelActionCatalogRecord[];
  private static cachedEntriesById?: Map<BrowserBottomPanelActionId, BrowserBottomPanelActionCatalogRecord>;

  static customizableActionIds(): BrowserBottomPanelActionId[] {
    return BrowserBottomPanelActionCatalog.entries()
      .filter((entry: BrowserBottomPanelActionCatalogRecord) => entry.customizable)
      .map((entry: BrowserBottomPanelActionCatalogRecord) => entry.id);
  }

  static entry(actionId: BrowserBottomPanelActionId): BrowserBottomPanelActionCatalogEntry {
    const item = BrowserBottomPanelActionCatalog.resolveEntriesById().get(actionId);
    if (item === undefined) {
      return {
        id: actionId,
        title: $r('app.string.bottom_panel_tool'),
        subtitle: '',
        customizable: false,
        surfaces: []
      };
    }
    return BrowserBottomPanelActionCatalog.toEntry(item);
  }

  static title(actionId: BrowserBottomPanelActionId): ResourceStr {
    return bottomPanelActionTitle(actionId);
  }

  static subtitle(actionId: BrowserBottomPanelActionId): ResourceStr {
    return bottomPanelActionSubtitle(actionId);
  }

  private static toEntry(item: BrowserBottomPanelActionCatalogRecord): BrowserBottomPanelActionCatalogEntry {
    return {
      id: item.id,
      title: bottomPanelActionTitle(item.id),
      subtitle: bottomPanelActionSubtitle(item.id),
      customizable: item.customizable,
      surfaces: item.surfaces
    };
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
      case 'webZoom':
        return 'browser.toolbar.zoomIn';
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

  private static entries(): BrowserBottomPanelActionCatalogRecord[] {
    if (BrowserBottomPanelActionCatalog.cachedEntries === undefined) {
      BrowserBottomPanelActionCatalog.cachedEntries = BrowserBottomPanelActionCatalog.buildEntries();
    }
    return BrowserBottomPanelActionCatalog.cachedEntries;
  }

  private static resolveEntriesById(): Map<BrowserBottomPanelActionId, BrowserBottomPanelActionCatalogRecord> {
    if (BrowserBottomPanelActionCatalog.cachedEntriesById !== undefined) {
      return BrowserBottomPanelActionCatalog.cachedEntriesById;
    }
    const result = new Map<BrowserBottomPanelActionId, BrowserBottomPanelActionCatalogRecord>();
    BrowserBottomPanelActionCatalog.entries().forEach((entry: BrowserBottomPanelActionCatalogRecord) => {
      result.set(entry.id, entry);
    });
    BrowserBottomPanelActionCatalog.cachedEntriesById = result;
    return result;
  }

  private static buildEntries(): BrowserBottomPanelActionCatalogRecord[] {
    return [
      { id: 'bookmark', customizable: true, surfaces: ['web', 'reader'] },
      { id: 'scanQr', customizable: true, surfaces: ['web', 'home'] },
      { id: 'share', customizable: true, surfaces: ['web', 'offline', 'reader'] },
      { id: 'sendToDesktop', customizable: true, surfaces: ['web'] },
      { id: 'print', customizable: true, surfaces: ['web'] },
      { id: 'userAgent', customizable: true, surfaces: ['web'] },
      { id: 'textZoom', customizable: true, surfaces: ['web'] },
      { id: 'webZoom', customizable: true, surfaces: ['web'] },
      { id: 'fullScreenMode', customizable: true, surfaces: ['web'] },
      { id: 'manualElementHide', customizable: true, surfaces: ['web'] },
      { id: 'elementInspection', customizable: true, surfaces: ['web'] },
      { id: 'reader', customizable: true, surfaces: ['web', 'offline'] },
      { id: 'novel', customizable: true, surfaces: ['web', 'home'] },
      { id: 'translate', customizable: true, surfaces: ['web'] },
      { id: 'scripts', customizable: true, surfaces: ['web', 'home'] },
      { id: 'themeMode', customizable: true, surfaces: ['web'] },
      { id: 'userAgentPreset', customizable: false, surfaces: [] },
      { id: 'screenOrientation', customizable: true, surfaces: ['web'] },
      { id: 'addToDesktop', customizable: true, surfaces: ['web'] },
      { id: 'offline', customizable: true, surfaces: ['web'] },
      { id: 'video', customizable: true, surfaces: ['web'] },
      { id: 'siteInfo', customizable: true, surfaces: ['web'] },
      { id: 'reportSite', customizable: true, surfaces: ['web'] },
      { id: 'openBookmarks', customizable: true, surfaces: ['web', 'home', 'reader', 'offline'] },
      { id: 'history', customizable: true, surfaces: ['web', 'home'] },
      { id: 'savedPages', customizable: true, surfaces: ['web', 'home'] },
      { id: 'downloads', customizable: true, surfaces: ['web', 'home'] },
      { id: 'settings', customizable: false, surfaces: ['web', 'home'] },
      { id: 'appProxySettings', customizable: true, surfaces: ['web', 'home'] },
      { id: 'home', customizable: true, surfaces: ['web', 'home', 'tabs', 'viewer'] },
      { id: 'find', customizable: true, surfaces: ['web', 'offline', 'reader'] },
      { id: 'openOriginal', customizable: false, surfaces: ['offline'] },
      { id: 'details', customizable: false, surfaces: ['offline'] },
      { id: 'exportPage', customizable: false, surfaces: ['offline'] },
      { id: 'deletePage', customizable: false, surfaces: ['offline'] },
      { id: 'decreaseFont', customizable: false, surfaces: ['reader'] },
      { id: 'increaseFont', customizable: false, surfaces: ['reader'] },
      { id: 'theme', customizable: false, surfaces: ['reader'] },
      { id: 'readAloud', customizable: false, surfaces: ['reader'] },
      { id: 'lineHeight', customizable: false, surfaces: ['reader'] },
      { id: 'pageWidth', customizable: false, surfaces: ['reader'] },
      { id: 'viewerInfo', customizable: false, surfaces: ['viewer'] },
      { id: 'newTab', customizable: false, surfaces: ['tabs'] },
      { id: 'newPrivateTab', customizable: true, surfaces: ['web', 'home', 'tabs'] },
      { id: 'closeAllTabs', customizable: false, surfaces: ['tabs'] },
      { id: 'clearHistory', customizable: false, surfaces: ['tabs'] }
    ];
  }
}
