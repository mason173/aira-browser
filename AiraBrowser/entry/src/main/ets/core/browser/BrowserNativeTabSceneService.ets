import urlUtils from '@ohos.url';
import { BookmarkStorageScope } from '../../common/models/BrowserModels';
import { SettingsCenterDestination } from '../settings/SettingsCenterViewModel';

export type BrowserNativeTabScene =
  'bookmarks' | 'history' | 'settings' | 'downloads' | 'user_scripts' | 'app_proxy' | 'saved_pages';

export const BOOKMARK_NATIVE_TAB_URL: string = 'aira://system/bookmarks';
export const BOOKMARK_NATIVE_TAB_TITLE: string = '书签';
export const HISTORY_NATIVE_TAB_URL: string = 'aira://system/history';
export const HISTORY_NATIVE_TAB_TITLE: string = '历史记录';
export const SETTINGS_NATIVE_TAB_URL: string = 'aira://system/settings';
export const SETTINGS_NATIVE_TAB_TITLE: string = '设置';
export const DOWNLOADS_NATIVE_TAB_URL: string = 'aira://system/downloads';
export const DOWNLOADS_NATIVE_TAB_TITLE: string = '下载管理';
export const USER_SCRIPTS_NATIVE_TAB_URL: string = 'aira://system/user-scripts';
export const USER_SCRIPTS_NATIVE_TAB_TITLE: string = '用户脚本';
export const APP_PROXY_NATIVE_TAB_URL: string = 'aira://system/app-proxy';
export const APP_PROXY_NATIVE_TAB_TITLE: string = '应用内代理';
export const SAVED_PAGES_NATIVE_TAB_URL: string = 'aira://system/saved_pages';
export const SAVED_PAGES_NATIVE_TAB_TITLE: string = '已保存的页面';

export interface BookmarkNativeTabRouteState {
  folderId: string;
  query: string;
  scope: BookmarkStorageScope;
}

export interface HistoryNativeTabRouteState {
  query: string;
  view: 'timeline' | 'sites';
  site: string;
}

export interface SettingsNativeTabRouteState {
  destination: SettingsCenterDestination;
}

export interface BrowserNativeTabOpenRequest {
  scene: BrowserNativeTabScene;
  settingsDestination?: SettingsCenterDestination;
}

/**
 * Single policy owner for browser-internal native tab URLs.
 *
 * Native tabs participate in Window Session tab ordering and persistence, but
 * they never materialize an ArkWeb runtime.
 */
export class BrowserNativeTabSceneService {
  resolveScene(rawUrl: string): BrowserNativeTabScene | undefined {
    const normalizedUrl = rawUrl.trim();
    if (normalizedUrl.length <= 0) {
      return undefined;
    }
    try {
      const parsed = urlUtils.URL.parseURL(normalizedUrl);
      const protocol = parsed.protocol.replace(':', '').toLowerCase();
      const host = parsed.hostname.toLowerCase();
      const path = parsed.pathname.replace(/\/$/, '').toLowerCase();
      if (protocol === 'aira' && host === 'system' && path === '/bookmarks') {
        return 'bookmarks';
      }
      if (protocol === 'aira' && host === 'system' && path === '/history') {
        return 'history';
      }
      if (protocol === 'aira' && host === 'system' && path === '/settings') {
        return 'settings';
      }
      if (protocol === 'aira' && host === 'system' && path === '/downloads') {
        return 'downloads';
      }
      if (protocol === 'aira' && host === 'system' && path === '/user-scripts') {
        return 'user_scripts';
      }
      if (protocol === 'aira' && host === 'system' && path === '/app-proxy') {
        return 'app_proxy';
      }
      if (protocol === 'aira' && host === 'system' && path === '/saved_pages') {
        return 'saved_pages';
      }
    } catch (_error) {
      const baseUrl = normalizedUrl.split('?')[0].toLowerCase();
      if (baseUrl === BOOKMARK_NATIVE_TAB_URL) {
        return 'bookmarks';
      }
      if (baseUrl === HISTORY_NATIVE_TAB_URL) {
        return 'history';
      }
      if (baseUrl === SETTINGS_NATIVE_TAB_URL) {
        return 'settings';
      }
      if (baseUrl === DOWNLOADS_NATIVE_TAB_URL) {
        return 'downloads';
      }
      if (baseUrl === USER_SCRIPTS_NATIVE_TAB_URL) {
        return 'user_scripts';
      }
      if (baseUrl === APP_PROXY_NATIVE_TAB_URL) {
        return 'app_proxy';
      }
      return baseUrl === SAVED_PAGES_NATIVE_TAB_URL ? 'saved_pages' : undefined;
    }
    return undefined;
  }

  resolveSceneForTab(url: string, pendingUrl: string = ''): BrowserNativeTabScene | undefined {
    const targetUrl = pendingUrl.trim().length > 0 ? pendingUrl : url;
    return this.resolveScene(targetUrl);
  }

  resolveCanonicalTitleForTab(url: string, pendingUrl: string = ''): string | undefined {
    const scene = this.resolveSceneForTab(url, pendingUrl);
    switch (scene) {
      case 'bookmarks':
        return BOOKMARK_NATIVE_TAB_TITLE;
      case 'history':
        return HISTORY_NATIVE_TAB_TITLE;
      case 'settings':
        return SETTINGS_NATIVE_TAB_TITLE;
      case 'downloads':
        return DOWNLOADS_NATIVE_TAB_TITLE;
      case 'user_scripts':
        return USER_SCRIPTS_NATIVE_TAB_TITLE;
      case 'app_proxy':
        return APP_PROXY_NATIVE_TAB_TITLE;
      case 'saved_pages':
        return SAVED_PAGES_NATIVE_TAB_TITLE;
      default:
        return undefined;
    }
  }

  isNativeTabUrl(url: string): boolean {
    return this.resolveScene(url) !== undefined;
  }

  isWebRuntimeEligible(url: string, pendingUrl: string = ''): boolean {
    return this.resolveSceneForTab(url, pendingUrl) === undefined;
  }

  buildBookmarkRoute(state: BookmarkNativeTabRouteState): string {
    const params: string[] = [];
    const folderId = state.folderId.trim();
    const query = state.query.trim();
    if (folderId.length > 0) {
      params.push(`id=${encodeURIComponent(folderId)}`);
    }
    if (query.length > 0) {
      params.push(`q=${encodeURIComponent(query)}`);
    }
    params.push(`scope=${state.scope === 'private' ? 'private' : 'regular'}`);
    return `${BOOKMARK_NATIVE_TAB_URL}?${params.join('&')}`;
  }

  parseBookmarkRoute(rawUrl: string, fallbackScope: BookmarkStorageScope = 'regular'): BookmarkNativeTabRouteState {
    if (this.resolveScene(rawUrl) !== 'bookmarks') {
      return {
        folderId: '',
        query: '',
        scope: fallbackScope
      };
    }
    const values = this.parseQueryValues(rawUrl);
    return {
      folderId: values.get('id')?.trim() ?? '',
      query: values.get('q')?.trim() ?? '',
      scope: values.get('scope') === 'private' ? 'private' : fallbackScope
    };
  }

  buildHistoryRoute(state: HistoryNativeTabRouteState): string {
    const params: string[] = [];
    const query = state.query.trim();
    const site = state.site.trim();
    if (query.length > 0) {
      params.push(`q=${encodeURIComponent(query)}`);
    }
    if (state.view === 'sites') {
      params.push('view=sites');
    }
    if (site.length > 0) {
      params.push(`site=${encodeURIComponent(site)}`);
    }
    return params.length > 0 ? `${HISTORY_NATIVE_TAB_URL}?${params.join('&')}` : HISTORY_NATIVE_TAB_URL;
  }

  parseHistoryRoute(rawUrl: string): HistoryNativeTabRouteState {
    if (this.resolveScene(rawUrl) !== 'history') {
      return { query: '', view: 'timeline', site: '' };
    }
    const values = this.parseQueryValues(rawUrl);
    return {
      query: values.get('q')?.trim() ?? '',
      view: values.get('view') === 'sites' ? 'sites' : 'timeline',
      site: values.get('site')?.trim() ?? ''
    };
  }

  buildSettingsRoute(state: SettingsNativeTabRouteState): string {
    return state.destination === 'general'
      ? SETTINGS_NATIVE_TAB_URL
      : `${SETTINGS_NATIVE_TAB_URL}?destination=${encodeURIComponent(state.destination)}`;
  }

  parseSettingsRoute(rawUrl: string): SettingsNativeTabRouteState {
    if (this.resolveScene(rawUrl) !== 'settings') {
      return { destination: 'general' };
    }
    return {
      destination: this.normalizeSettingsDestination(this.parseQueryValues(rawUrl).get('destination'))
    };
  }

  private parseQueryValues(rawUrl: string): Map<string, string> {
    const values: Map<string, string> = new Map<string, string>();
    const queryIndex = rawUrl.indexOf('?');
    if (queryIndex < 0 || queryIndex >= rawUrl.length - 1) {
      return values;
    }
    rawUrl.substring(queryIndex + 1).split('&').forEach((part: string): void => {
      const separatorIndex = part.indexOf('=');
      const rawKey = separatorIndex >= 0 ? part.substring(0, separatorIndex) : part;
      const rawValue = separatorIndex >= 0 ? part.substring(separatorIndex + 1) : '';
      const key = this.decodeQueryValue(rawKey).trim().toLowerCase();
      if (key.length > 0 && !values.has(key)) {
        values.set(key, this.decodeQueryValue(rawValue));
      }
    });
    return values;
  }

  private decodeQueryValue(value: string): string {
    try {
      return decodeURIComponent(value.replace(/\+/g, ' '));
    } catch (_error) {
      return value;
    }
  }

  private normalizeSettingsDestination(rawValue: string | undefined): SettingsCenterDestination {
    switch (rawValue?.trim()) {
      case 'app_service_mode':
      case 'advanced_settings':
      case 'aira_pro':
      case 'general':
      case 'custom_homepage':
      case 'toolbar_customization':
      case 'search':
      case 'privacy_security':
      case 'private_mode':
      case 'site_settings':
      case 'ad_blocker':
      case 'web_features':
      case 'user_scripts':
      case 'webpage_translation':
      case 'web_apps':
      case 'passwords':
      case 'downloads':
      case 'user_agent':
      case 'appearance_toolbar':
      case 'experiments':
      case 'sync':
      case 'about':
        return rawValue.trim() as SettingsCenterDestination;
      default:
        return 'general';
    }
  }
}

export const browserNativeTabSceneService: BrowserNativeTabSceneService = new BrowserNativeTabSceneService();
