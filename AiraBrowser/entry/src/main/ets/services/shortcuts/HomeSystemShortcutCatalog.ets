import {
  HomeSystemShortcutTarget,
  ShortcutKind,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';

export type HomeSystemShortcutIconId =
  'browser.shortcut.bookmarks' |
  'browser.shortcut.history' |
  'browser.shortcut.downloads' |
  'browser.toolbar.savedPages' |
  'browser.toolbar.tabs' |
  'browser.shortcut.scripts' |
  'settings.adBlocker' |
  'browser.shortcut.settings';

const HOME_SYSTEM_SHORTCUT_URL_PREFIX: string = 'aira://system/';

export interface HomeSystemShortcutDefinition {
  target: HomeSystemShortcutTarget;
  title: string;
  url: string;
  iconId: HomeSystemShortcutIconId;
}

const HOME_SYSTEM_SHORTCUT_DEFINITIONS: HomeSystemShortcutDefinition[] = [
  { target: 'bookmarks', title: '书签', url: 'aira://system/bookmarks', iconId: 'browser.shortcut.bookmarks' },
  { target: 'history', title: '历史记录', url: 'aira://system/history', iconId: 'browser.shortcut.history' },
  { target: 'downloads', title: '下载管理', url: 'aira://system/downloads', iconId: 'browser.shortcut.downloads' },
  { target: 'saved_pages', title: '我的网页', url: 'aira://system/saved_pages', iconId: 'browser.toolbar.savedPages' },
  { target: 'tabs', title: '标签页', url: 'aira://system/tabs', iconId: 'browser.toolbar.tabs' },
  { target: 'user_scripts', title: '用户脚本', url: 'aira://system/user_scripts', iconId: 'browser.shortcut.scripts' },
  { target: 'ad_block', title: '广告拦截', url: 'aira://system/ad_block', iconId: 'settings.adBlocker' },
  { target: 'settings', title: '设置', url: 'aira://system/settings', iconId: 'browser.shortcut.settings' }
];

export function getHomeSystemShortcutDefinitions(): HomeSystemShortcutDefinition[] {
  return HOME_SYSTEM_SHORTCUT_DEFINITIONS.map(withLocalizedHomeSystemShortcutTitle);
}

function withLocalizedHomeSystemShortcutTitle(
  definition: HomeSystemShortcutDefinition
): HomeSystemShortcutDefinition {
  return {
    target: definition.target,
    title: resolveHomeSystemShortcutTitle(definition.target),
    url: definition.url,
    iconId: definition.iconId
  };
}

function resolveHomeSystemShortcutTitle(target: HomeSystemShortcutTarget): string {
  switch (target) {
    case 'bookmarks':
      return resolveAppResourceText($r('app.string.app_shortcut_bookmarks'));
    case 'history':
      return resolveAppResourceText($r('app.string.app_shortcut_history'));
    case 'downloads':
      return resolveAppResourceText($r('app.string.app_shortcut_downloads'));
    case 'saved_pages':
      return resolveAppResourceText($r('app.string.offline_pages_desktop_title'));
    case 'tabs':
      return resolveAppResourceText($r('app.string.offline_action_tabs'));
    case 'user_scripts':
      return resolveAppResourceText($r('app.string.settings_pro_benefit_scripts'));
    case 'ad_block':
      return resolveAppResourceText($r('app.string.home_shortcut_ad_block'));
    case 'settings':
      return resolveAppResourceText($r('app.string.app_shortcut_settings'));
    default:
      return '';
  }
}

export function resolveHomeShortcutKind(kind: ShortcutKind | undefined): ShortcutKind {
  return kind === 'system' ? 'system' : 'web';
}

export function isHomeSystemShortcut(shortcut: ShortcutRecord): boolean {
  return resolveHomeShortcutKind(shortcut.kind) === 'system';
}

export function resolveHomeSystemShortcutDefinition(
  target: HomeSystemShortcutTarget
): HomeSystemShortcutDefinition | undefined {
  const definition = HOME_SYSTEM_SHORTCUT_DEFINITIONS.find((item: HomeSystemShortcutDefinition) => {
    return item.target === target;
  });
  return definition === undefined ? undefined : withLocalizedHomeSystemShortcutTitle(definition);
}

export function resolveHomeSystemShortcutDefinitionByUrl(
  url: string
): HomeSystemShortcutDefinition | undefined {
  const target = resolveHomeSystemShortcutTarget(url);
  if (target === undefined) {
    return undefined;
  }
  return resolveHomeSystemShortcutDefinition(target);
}

export function resolveHomeSystemShortcutTarget(url: string): HomeSystemShortcutTarget | undefined {
  const normalizedUrl = url.trim().toLowerCase();
  if (!normalizedUrl.startsWith(HOME_SYSTEM_SHORTCUT_URL_PREFIX)) {
    return undefined;
  }
  const rawTarget = normalizedUrl.substring(HOME_SYSTEM_SHORTCUT_URL_PREFIX.length);
  const definition = HOME_SYSTEM_SHORTCUT_DEFINITIONS.find((item: HomeSystemShortcutDefinition) => {
    return item.target === rawTarget;
  });
  return definition?.target;
}

export function resolveHomeSystemShortcutTargetValue(value: string): HomeSystemShortcutTarget | undefined {
  const definition = HOME_SYSTEM_SHORTCUT_DEFINITIONS.find((definition: HomeSystemShortcutDefinition) => {
    return definition.target === value;
  });
  return definition?.target;
}
