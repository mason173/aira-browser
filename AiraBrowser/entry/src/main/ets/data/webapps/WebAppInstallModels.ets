export type DesktopWebEntryInstallState = 'pending' | 'installed';

export const DESKTOP_WEB_SHORTCUT_SOURCE: string = 'desktop_web_page';
export const DESKTOP_WEB_SHORTCUT_ID_PREFIX: string = 'aira_web_page_';

export interface DesktopWebShortcutWantKeys {
  source: string;
  shortcutId: string;
  createdAt: string;
  title: string;
  iconPath: string;
  scope: string;
  manifestUrl: string;
  origin: string;
  themeColor: string;
}

export const DESKTOP_WEB_SHORTCUT_WANT_KEYS: DesktopWebShortcutWantKeys = {
  source: 'aira.shortcutSource',
  shortcutId: 'aira.shortcutId',
  createdAt: 'aira.shortcutCreatedAt',
  title: 'aira.shortcutTitle',
  iconPath: 'aira.shortcutIconPath',
  scope: 'aira.webAppScope',
  manifestUrl: 'aira.webAppManifestUrl',
  origin: 'aira.webAppOrigin',
  themeColor: 'aira.webAppThemeColor'
};

export interface DesktopWebEntryRecord {
  shortcutId: string;
  installState: DesktopWebEntryInstallState;
  title: string;
  iconPath: string;
  launchUrl: string;
  currentUrl: string;
  origin: string;
  manifestUrl: string;
  scope: string;
  display: string;
  themeColor: string;
  backgroundColor: string;
  settings: DesktopWebEntrySettings;
  createdAt: number;
  updatedAt: number;
}

export interface DesktopWebEntrySettings {
  defaultFullscreen: boolean;
}

export const DEFAULT_DESKTOP_WEB_ENTRY_SETTINGS: DesktopWebEntrySettings = {
  defaultFullscreen: false
};

export interface DesktopWebEntryUpsertInput {
  shortcutId: string;
  installState?: DesktopWebEntryInstallState;
  title: string;
  iconPath: string;
  launchUrl: string;
  currentUrl: string;
  origin: string;
  manifestUrl?: string;
  scope?: string;
  display?: string;
  themeColor?: string;
  backgroundColor?: string;
  settings?: DesktopWebEntrySettings;
}

export function normalizeDesktopWebEntryInstallState(value: string | undefined): DesktopWebEntryInstallState {
  return value === 'pending' ? 'pending' : 'installed';
}

export function buildDesktopWebEntryRecord(input: DesktopWebEntryUpsertInput, now: number): DesktopWebEntryRecord {
  return {
    shortcutId: input.shortcutId,
    installState: input.installState ?? 'installed',
    title: input.title,
    iconPath: input.iconPath,
    launchUrl: input.launchUrl,
    currentUrl: input.currentUrl,
    origin: input.origin,
    manifestUrl: input.manifestUrl ?? '',
    scope: input.scope ?? '',
    display: input.display ?? '',
    themeColor: input.themeColor ?? '',
    backgroundColor: input.backgroundColor ?? '',
    settings: normalizeDesktopWebEntrySettings(input.settings),
    createdAt: now,
    updatedAt: now
  };
}

export function normalizeDesktopWebEntrySettings(
  value: DesktopWebEntrySettings | undefined
): DesktopWebEntrySettings {
  return {
    defaultFullscreen: value?.defaultFullscreen === true ? true : DEFAULT_DESKTOP_WEB_ENTRY_SETTINGS.defaultFullscreen
  };
}
