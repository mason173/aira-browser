import { WebSessionRestoreType } from '../../common/models/BrowserModels';
import { BrowserTabRuntimePatch, BrowserTabState } from '../tabs/TabManager';

export type WebSessionStatePatch = BrowserTabRuntimePatch;

export class WebSessionStateStore {
  buildScrollPatch(scrollOffsetY: number): WebSessionStatePatch {
    return {
      scrollOffsetY: Math.max(0, Math.floor(scrollOffsetY))
    };
  }

  buildLoadSuccessPatch(url: string, title: string): WebSessionStatePatch {
    const normalizedUrl = url.trim();
    const normalizedTitle = title.trim();
    return {
      lastGoodUrl: normalizedUrl,
      lastGoodTitle: normalizedTitle.length > 0 ? normalizedTitle : normalizedUrl,
      lastRestorableUrl: normalizedUrl,
      lastRestorableTitle: normalizedTitle.length > 0 ? normalizedTitle : normalizedUrl,
      lastLoadedAt: Date.now()
    };
  }

  buildRestoreTypePatch(restoreType: WebSessionRestoreType, tab: BrowserTabState): WebSessionStatePatch {
    return {
      lastRestoreType: restoreType,
      lastGoodUrl: tab.lastGoodUrl.length > 0 ? tab.lastGoodUrl : tab.url,
      lastGoodTitle: tab.lastGoodTitle.length > 0 ? tab.lastGoodTitle : tab.title,
      lastRestorableUrl: tab.lastRestorableUrl.length > 0
        ? tab.lastRestorableUrl
        : (tab.lastGoodUrl.length > 0 ? tab.lastGoodUrl : tab.url),
      lastRestorableTitle: tab.lastRestorableTitle.length > 0
        ? tab.lastRestorableTitle
        : (tab.lastGoodTitle.length > 0 ? tab.lastGoodTitle : tab.title)
    };
  }

  buildResetPatch(): WebSessionStatePatch {
    return {
      scrollOffsetY: 0,
      lastGoodUrl: '',
      lastGoodTitle: '',
      lastRestorableUrl: '',
      lastRestorableTitle: '',
      lastRestoreType: 'none'
    };
  }
}
