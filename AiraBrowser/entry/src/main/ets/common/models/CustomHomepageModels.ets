import { BrowserHomepageBackdropAppearanceState } from './BackdropAppearanceModels';

type CustomHomepageMode = 'system' | 'custom_html';
export type CustomHomepageItemKind = 'single_html' | 'zip_package' | 'remote_url';

export interface CustomHomepageItem {
  id: string;
  identityKey: string;
  kind: CustomHomepageItemKind;
  fileName: string;
  filePath: string;
  fileUri: string;
  rootPath: string;
  packageRootPath: string;
  entryPath: string;
  manifestPath: string;
  packageName: string;
  version: string;
  author: string;
  description: string;
  previewPath: string;
  previewUri: string;
  previewLightUri: string;
  previewDarkUri: string;
  hasLightAppearanceEvidence?: boolean;
  hasDarkAppearanceEvidence?: boolean;
  appearanceLight?: BrowserHomepageBackdropAppearanceState;
  appearanceDark?: BrowserHomepageBackdropAppearanceState;
  remoteUrl: string;
  siteIconUri: string;
  packageSize: number;
  extractedSize: number;
  byteSize: number;
  importedAt: number;
  updatedAt: number;
}

export interface CustomHomepageSettings {
  mode: CustomHomepageMode;
  selectedItemId: string;
  items: CustomHomepageItem[];
  updatedAt: number;
  systemHomepageShowSystemSearchBar: boolean;
  showSystemSearchBarByItemId: Record<string, boolean>;
  showSystemEntryButtonByItemId: Record<string, boolean>;
  forceDarkWebContentByItemId: Record<string, boolean>;
  hideToolbarOnScrollByItemId: Record<string, boolean>;
  hideToolbarOnScroll: boolean;
}

export const DEFAULT_CUSTOM_HOMEPAGE_SETTINGS: CustomHomepageSettings = {
  mode: 'system',
  selectedItemId: '',
  items: [],
  updatedAt: 0,
  systemHomepageShowSystemSearchBar: true,
  showSystemSearchBarByItemId: {},
  showSystemEntryButtonByItemId: {},
  forceDarkWebContentByItemId: {},
  hideToolbarOnScrollByItemId: {},
  hideToolbarOnScroll: false
};

export function normalizeCustomHomepageBooleanByItemId(
  items: CustomHomepageItem[],
  value: Record<string, boolean> | undefined,
  missingValue: boolean
): Record<string, boolean> {
  const normalized: Record<string, boolean> = {};
  items.forEach((item: CustomHomepageItem) => {
    const storedValue = value !== undefined ? value[item.id] : undefined;
    normalized[item.id] = typeof storedValue === 'boolean' ? storedValue : missingValue;
  });
  return normalized;
}

export function normalizeCustomHomepageSystemSearchVisibilityByItemId(
  items: CustomHomepageItem[],
  value: Record<string, boolean> | undefined,
  missingValue: boolean = true
): Record<string, boolean> {
  return normalizeCustomHomepageBooleanByItemId(items, value, missingValue);
}

export function resolveCustomHomepageItemBooleanById(
  value: Record<string, boolean>,
  itemId: string,
  missingValue: boolean
): boolean {
  const storedValue = value[itemId];
  return typeof storedValue === 'boolean' ? storedValue : missingValue;
}

export function resolveCustomHomepageSystemSearchVisibility(settings: CustomHomepageSettings): boolean {
  if (settings.mode === 'custom_html' && settings.selectedItemId.length > 0) {
    return resolveCustomHomepageItemBooleanById(
      settings.showSystemSearchBarByItemId,
      settings.selectedItemId,
      true
    );
  }
  return settings.systemHomepageShowSystemSearchBar;
}

export function resolveCustomHomepageSystemEntryButtonVisibility(settings: CustomHomepageSettings): boolean {
  if (settings.mode !== 'custom_html' || settings.selectedItemId.length <= 0) {
    return false;
  }
  return resolveCustomHomepageItemBooleanById(
    settings.showSystemEntryButtonByItemId,
    settings.selectedItemId,
    false
  );
}

export function resolveCustomHomepageForceDarkWebContent(settings: CustomHomepageSettings): boolean {
  if (settings.mode !== 'custom_html' || settings.selectedItemId.length <= 0) {
    return false;
  }
  return resolveCustomHomepageItemBooleanById(
    settings.forceDarkWebContentByItemId,
    settings.selectedItemId,
    true
  );
}

export function resolveCustomHomepageHideToolbarOnScroll(settings: CustomHomepageSettings): boolean {
  if (settings.mode === 'custom_html' && settings.selectedItemId.length > 0) {
    return resolveCustomHomepageItemBooleanById(
      settings.hideToolbarOnScrollByItemId,
      settings.selectedItemId,
      false
    );
  }
  return settings.hideToolbarOnScroll;
}

export interface CustomHomepageRepositorySnapshot {
  settings: CustomHomepageSettings;
}
