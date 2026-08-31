import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  PersonalizationSettingsChangeOrigin,
  PersonalizationSettingsLocalChangeHandler,
  PersonalizationSyncItemDeletionRecorder
} from '../../common/models/PersonalizationSyncModels';
import {
  CustomHomepageItem,
  CustomHomepageItemKind,
  CustomHomepageRepositorySnapshot,
  CustomHomepageSettings,
  DEFAULT_CUSTOM_HOMEPAGE_SETTINGS,
  normalizeCustomHomepageBooleanByItemId,
  normalizeCustomHomepageSystemSearchVisibilityByItemId
} from '../../common/models/CustomHomepageModels';
import {
  BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
  BrowserHomepageBackdropAppearanceState,
  cloneBrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';

const PREFERENCES_NAME: string = 'aira_browser_custom_homepage';
const CUSTOM_HOMEPAGE_SETTINGS_KEY: string = 'custom_homepage_settings';

type CustomHomepageRepositoryChangeListener = (snapshot: CustomHomepageRepositorySnapshot) => void;

export class CustomHomepageRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private settings: CustomHomepageSettings = this.cloneSettings(DEFAULT_CUSTOM_HOMEPAGE_SETTINGS);
  private initializationPromise?: Promise<CustomHomepageRepositorySnapshot>;
  private initialized: boolean = false;
  private listenerSequence: number = 0;
  private listeners: Record<string, CustomHomepageRepositoryChangeListener | undefined> = {};
  private deletionRecorder?: PersonalizationSyncItemDeletionRecorder;
  private localChangeHandler?: PersonalizationSettingsLocalChangeHandler;

  constructor(deletionRecorder?: PersonalizationSyncItemDeletionRecorder) {
    this.deletionRecorder = deletionRecorder;
  }

  setLocalChangeHandler(handler?: PersonalizationSettingsLocalChangeHandler): void {
    this.localChangeHandler = handler;
  }

  async initialize(): Promise<CustomHomepageRepositorySnapshot> {
    if (this.initialized) {
      return this.getSnapshot();
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.getStore()
        .then(async (store: preferences.Preferences): Promise<CustomHomepageRepositorySnapshot> => {
          const rawSettings = String(store.getSync(CUSTOM_HOMEPAGE_SETTINGS_KEY, ''));
          this.settings = this.normalizeSettings(this.parseSettings(rawSettings));
          if (rawSettings.trim() !== JSON.stringify(this.settings)) {
            await this.persistSettings(this.settings, 'system');
          }
          this.initialized = true;
          return this.getSnapshot();
        })
        .finally(() => {
          this.initializationPromise = undefined;
        });
    }
    return this.initializationPromise;
  }

  getSnapshot(): CustomHomepageRepositorySnapshot {
    return {
      settings: this.getSettings()
    };
  }

  getSettings(): CustomHomepageSettings {
    return this.cloneSettings(this.settings);
  }

  subscribe(listener: CustomHomepageRepositoryChangeListener): string {
    this.listenerSequence += 1;
    const key = `custom-homepage-listener-${this.listenerSequence}`;
    this.listeners[key] = listener;
    return key;
  }

  unsubscribe(key: string): void {
    this.listeners[key] = undefined;
  }

  async saveSettings(
    settings: CustomHomepageSettings,
    origin: PersonalizationSettingsChangeOrigin = 'local'
  ): Promise<void> {
    return this.persistSettings(this.normalizeSettings(settings), origin);
  }

  async removeItem(itemId: string): Promise<void> {
    const normalizedId = itemId.trim();
    const existing = this.settings.items.find((item: CustomHomepageItem): boolean => item.id === normalizedId);
    if (existing === undefined) {
      return;
    }
    const previous = this.getSettings();
    const selectedItemId = this.settings.selectedItemId === normalizedId ? '' : this.settings.selectedItemId;
    const deletedAt = Date.now();
    await this.persistSettings(this.normalizeSettings({
      mode: selectedItemId.length > 0 ? 'custom_html' : 'system',
      selectedItemId: selectedItemId,
      items: this.settings.items.filter((item: CustomHomepageItem): boolean => item.id !== normalizedId),
      updatedAt: deletedAt,
      systemHomepageShowSystemSearchBar: this.settings.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: this.settings.showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: this.settings.showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: this.settings.forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: this.settings.hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: this.settings.hideToolbarOnScroll
    }), 'local');
    if (existing.kind === 'remote_url') {
      try {
        await this.deletionRecorder?.(normalizedId, deletedAt);
      } catch (error) {
        await this.persistSettings(previous, 'system');
        throw new Error(error instanceof Error ? error.message : JSON.stringify(error));
      }
    }
  }

  private parseSettings(value: string): CustomHomepageSettings | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as CustomHomepageSettings;
    } catch (_error) {
      return undefined;
    }
  }

  private normalizeSettings(value: CustomHomepageSettings | undefined): CustomHomepageSettings {
    const items = this.normalizeItems(value);
    const customModeRequested = value?.mode === 'custom_html';
    const selectedItemId = customModeRequested ? this.normalizeSelectedItemId(value?.selectedItemId, items) : '';
    const selectedItem = customModeRequested ? this.findItemById(items, selectedItemId) : undefined;
    const hasSelectedItem = selectedItem !== undefined;
    const showSystemSearchBarByItemId = normalizeCustomHomepageSystemSearchVisibilityByItemId(
      items,
      value?.showSystemSearchBarByItemId
    );
    const showSystemEntryButtonByItemId = normalizeCustomHomepageBooleanByItemId(
      items,
      value?.showSystemEntryButtonByItemId,
      false
    );
    const forceDarkWebContentByItemId = normalizeCustomHomepageBooleanByItemId(
      items,
      value?.forceDarkWebContentByItemId,
      true
    );
    const hideToolbarOnScrollByItemId = normalizeCustomHomepageBooleanByItemId(
      items,
      value?.hideToolbarOnScrollByItemId,
      false
    );
    const hideToolbarOnScroll = typeof value?.hideToolbarOnScroll === 'boolean' ?
      value.hideToolbarOnScroll :
      DEFAULT_CUSTOM_HOMEPAGE_SETTINGS.hideToolbarOnScroll;
    return {
      mode: customModeRequested && hasSelectedItem ? 'custom_html' : 'system',
      selectedItemId: hasSelectedItem ? selectedItemId : '',
      items: items,
      updatedAt: this.normalizeTimestamp(value?.updatedAt),
      systemHomepageShowSystemSearchBar: typeof value?.systemHomepageShowSystemSearchBar === 'boolean' ?
        value.systemHomepageShowSystemSearchBar :
        DEFAULT_CUSTOM_HOMEPAGE_SETTINGS.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: hideToolbarOnScroll
    };
  }

  private async persistSettings(
    settings: CustomHomepageSettings,
    origin: PersonalizationSettingsChangeOrigin
  ): Promise<void> {
    const previous = this.getSettings();
    this.settings = this.cloneSettings(settings);
    const store = await this.getStore();
    store.putSync(CUSTOM_HOMEPAGE_SETTINGS_KEY, JSON.stringify(this.settings));
    store.flushSync();
    this.initialized = true;
    this.notifyChanged();
    if (origin === 'local' && this.hasSyncRelevantChange(previous, this.settings)) {
      this.localChangeHandler?.();
    }
  }

  private hasSyncRelevantChange(
    previous: CustomHomepageSettings,
    next: CustomHomepageSettings
  ): boolean {
    return previous.systemHomepageShowSystemSearchBar !== next.systemHomepageShowSystemSearchBar ||
      previous.hideToolbarOnScroll !== next.hideToolbarOnScroll;
  }

  private notifyChanged(): void {
    const snapshot = this.getSnapshot();
    Object.keys(this.listeners).forEach((key: string) => {
      const listener = this.listeners[key];
      if (listener !== undefined) {
        listener(snapshot);
      }
    });
  }

  private cloneSettings(settings: CustomHomepageSettings): CustomHomepageSettings {
    return {
      mode: settings.mode,
      selectedItemId: settings.selectedItemId,
      items: settings.items.map((item: CustomHomepageItem): CustomHomepageItem => this.cloneItem(item)),
      updatedAt: settings.updatedAt,
      systemHomepageShowSystemSearchBar: settings.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: normalizeCustomHomepageSystemSearchVisibilityByItemId(
        settings.items,
        settings.showSystemSearchBarByItemId
      ),
      showSystemEntryButtonByItemId: normalizeCustomHomepageBooleanByItemId(
        settings.items,
        settings.showSystemEntryButtonByItemId,
        false
      ),
      forceDarkWebContentByItemId: normalizeCustomHomepageBooleanByItemId(
        settings.items,
        settings.forceDarkWebContentByItemId,
        true
      ),
      hideToolbarOnScrollByItemId: normalizeCustomHomepageBooleanByItemId(
        settings.items,
        settings.hideToolbarOnScrollByItemId,
        false
      ),
      hideToolbarOnScroll: settings.hideToolbarOnScroll
    };
  }

  private normalizeItems(value: CustomHomepageSettings | undefined): CustomHomepageItem[] {
    const rawItems: CustomHomepageItem[] = value !== undefined && Array.isArray(value.items) ? value.items : [];
    const normalizedItems: CustomHomepageItem[] = [];
    rawItems.forEach((item: CustomHomepageItem) => {
      const normalizedItem = this.normalizeItem(item);
      if (normalizedItem !== undefined && this.findItemById(normalizedItems, normalizedItem.id) === undefined) {
        normalizedItems.push(normalizedItem);
      }
    });
    return normalizedItems.sort((left: CustomHomepageItem, right: CustomHomepageItem): number => {
      return right.importedAt - left.importedAt;
    });
  }

  private normalizeItem(item: CustomHomepageItem | undefined): CustomHomepageItem | undefined {
    const kind = this.normalizeItemKind(item?.kind);
    const remoteUrl = this.normalizeString(item?.remoteUrl);
    if (kind === 'remote_url') {
      if (remoteUrl.length === 0) {
        return undefined;
      }
      const importedAt = this.normalizeTimestamp(item?.importedAt);
      const id = this.normalizeString(item?.id);
      if (id.length === 0) {
        return undefined;
      }
      return {
        id: id,
        identityKey: this.normalizeIdentityKey(item),
        kind: 'remote_url',
        fileName: this.normalizeString(item?.fileName).length > 0 ? this.normalizeString(item?.fileName) : remoteUrl,
        filePath: remoteUrl,
        fileUri: remoteUrl,
        rootPath: '',
        packageRootPath: '',
        entryPath: '',
        manifestPath: '',
        packageName: this.normalizeString(item?.packageName),
        version: this.normalizeString(item?.version),
        author: this.normalizeString(item?.author),
        description: this.normalizeString(item?.description),
        previewPath: this.normalizeString(item?.previewPath),
        previewUri: this.normalizeString(item?.previewUri),
        previewLightUri: this.normalizeString(item?.previewLightUri),
        previewDarkUri: this.normalizeString(item?.previewDarkUri),
        hasLightAppearanceEvidence: this.normalizeOptionalBoolean(item?.hasLightAppearanceEvidence),
        hasDarkAppearanceEvidence: this.normalizeOptionalBoolean(item?.hasDarkAppearanceEvidence),
        appearanceLight: this.normalizeAppearanceState(item?.appearanceLight),
        appearanceDark: this.normalizeAppearanceState(item?.appearanceDark),
        remoteUrl: remoteUrl,
        siteIconUri: this.normalizeString(item?.siteIconUri),
        packageSize: 0,
        extractedSize: 0,
        byteSize: 0,
        importedAt: importedAt > 0 ? importedAt : Date.now(),
        updatedAt: this.normalizeTimestamp(item?.updatedAt)
      };
    }
    const filePath = this.normalizeString(item?.filePath);
    const fileUri = this.normalizeString(item?.fileUri);
    if (filePath.length === 0 || fileUri.length === 0) {
      return undefined;
    }
    const importedAt = this.normalizeTimestamp(item?.importedAt);
    const id = this.normalizeString(item?.id);
    if (id.length === 0) {
      return undefined;
    }
    const packageRootPath = this.normalizeString(item?.packageRootPath);
    const rootPath = this.normalizeString(item?.rootPath);
    const entryPath = this.normalizeString(item?.entryPath);
    return {
      id: id,
      identityKey: this.normalizeIdentityKey(item),
      kind: kind,
      fileName: this.normalizeString(item?.fileName).length > 0 ? this.normalizeString(item?.fileName) : 'homepage.html',
      filePath: filePath,
      fileUri: fileUri,
      rootPath: rootPath.length > 0 ? rootPath : filePath,
      packageRootPath: packageRootPath,
      entryPath: entryPath,
      manifestPath: this.normalizeString(item?.manifestPath),
      packageName: this.normalizeString(item?.packageName),
      version: this.normalizeString(item?.version),
      author: this.normalizeString(item?.author),
      description: this.normalizeString(item?.description),
      previewPath: this.normalizeString(item?.previewPath),
      previewUri: this.normalizeString(item?.previewUri),
      previewLightUri: this.normalizeString(item?.previewLightUri),
      previewDarkUri: this.normalizeString(item?.previewDarkUri),
      hasLightAppearanceEvidence: this.normalizeOptionalBoolean(item?.hasLightAppearanceEvidence),
      hasDarkAppearanceEvidence: this.normalizeOptionalBoolean(item?.hasDarkAppearanceEvidence),
      appearanceLight: this.normalizeAppearanceState(item?.appearanceLight),
      appearanceDark: this.normalizeAppearanceState(item?.appearanceDark),
      remoteUrl: '',
      siteIconUri: this.normalizeString(item?.siteIconUri),
      packageSize: this.normalizeInteger(item?.packageSize),
      extractedSize: this.normalizeInteger(item?.extractedSize),
      byteSize: this.normalizeInteger(item?.byteSize),
      importedAt: importedAt > 0 ? importedAt : Date.now(),
      updatedAt: this.normalizeTimestamp(item?.updatedAt)
    };
  }

  private normalizeSelectedItemId(value: string | undefined, items: CustomHomepageItem[]): string {
    const selectedItemId = this.normalizeString(value);
    if (this.findItemById(items, selectedItemId) !== undefined) {
      return selectedItemId;
    }
    return '';
  }

  private findItemById(items: CustomHomepageItem[], id: string): CustomHomepageItem | undefined {
    const normalizedId = id.trim();
    return items.find((item: CustomHomepageItem) => item.id === normalizedId);
  }

  private cloneItem(item: CustomHomepageItem): CustomHomepageItem {
    return {
      id: item.id,
      identityKey: item.identityKey,
      kind: item.kind,
      fileName: item.fileName,
      filePath: item.filePath,
      fileUri: item.fileUri,
      rootPath: item.rootPath,
      packageRootPath: item.packageRootPath,
      entryPath: item.entryPath,
      manifestPath: item.manifestPath,
      packageName: item.packageName,
      version: item.version,
      author: item.author,
      description: item.description,
      previewPath: item.previewPath,
      previewUri: item.previewUri,
      previewLightUri: item.previewLightUri,
      previewDarkUri: item.previewDarkUri,
      hasLightAppearanceEvidence: item.hasLightAppearanceEvidence,
      hasDarkAppearanceEvidence: item.hasDarkAppearanceEvidence,
      appearanceLight: this.cloneAppearanceState(item.appearanceLight),
      appearanceDark: this.cloneAppearanceState(item.appearanceDark),
      remoteUrl: item.remoteUrl,
      siteIconUri: item.siteIconUri,
      packageSize: item.packageSize,
      extractedSize: item.extractedSize,
      byteSize: item.byteSize,
      importedAt: item.importedAt,
      updatedAt: item.updatedAt
    };
  }

  private normalizeString(value: string | undefined): string {
    return typeof value === 'string' ? value.trim() : '';
  }

  private normalizeOptionalBoolean(value: boolean | undefined): boolean | undefined {
    return typeof value === 'boolean' ? value : undefined;
  }

  private normalizeAppearanceState(
    state: BrowserHomepageBackdropAppearanceState | undefined
  ): BrowserHomepageBackdropAppearanceState | undefined {
    const sourceKey = this.normalizeString(state?.sourceKey);
    const snapshotSignature = this.normalizeString(state?.snapshotSignature);
    if (state === undefined || !state.available ||
      state.algorithmVersion !== BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION ||
      sourceKey.length <= 0 ||
      snapshotSignature.length <= 0) {
      return undefined;
    }
    const normalized = cloneBrowserHomepageBackdropAppearanceState(state);
    normalized.sourceKey = sourceKey;
    normalized.snapshotSignature = snapshotSignature;
    normalized.algorithmVersion = BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION;
    normalized.resolvedThemeMode = normalized.resolvedThemeMode === 'dark' ? 'dark' : 'light';
    normalized.toolbarForegroundTone = normalized.toolbarForegroundTone === 'light' ? 'light' : 'dark';
    normalized.toolbarLabelTextColor = this.normalizeString(normalized.toolbarLabelTextColor);
    normalized.toolbarPrimaryTextColor = this.normalizeString(normalized.toolbarPrimaryTextColor);
    normalized.toolbarSecondaryTextColor = this.normalizeString(normalized.toolbarSecondaryTextColor);
    normalized.updatedAt = this.normalizeTimestamp(normalized.updatedAt);
    normalized.volatileOnly = false;
    return normalized;
  }

  private cloneAppearanceState(
    state: BrowserHomepageBackdropAppearanceState | undefined
  ): BrowserHomepageBackdropAppearanceState | undefined {
    return state === undefined ? undefined : cloneBrowserHomepageBackdropAppearanceState(state);
  }

  private normalizeItemKind(value: string | undefined): CustomHomepageItemKind {
    if (value === 'zip_package' || value === 'remote_url') {
      return value;
    }
    return 'single_html';
  }

  private normalizeTimestamp(value: number | undefined): number {
    return typeof value === 'number' && isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeInteger(value: number | undefined): number {
    return typeof value === 'number' && isFinite(value) && value > 0 ? Math.floor(value) : 0;
  }

  private normalizeIdentityKey(item: CustomHomepageItem | undefined): string {
    const explicitKey = this.normalizeString(item?.identityKey);
    if (explicitKey.length > 0) {
      return explicitKey.toLowerCase();
    }
    const kind = this.normalizeItemKind(item?.kind);
    if (kind === 'remote_url') {
      const remoteUrl = this.normalizeString(item?.remoteUrl);
      return remoteUrl.length > 0 ? `remote_url:${remoteUrl.toLowerCase()}` : '';
    }
    if (kind === 'zip_package') {
      const packageName = this.normalizeString(item?.packageName);
      if (packageName.length > 0) {
        return `zip_package:name:${packageName.toLowerCase()}`;
      }
    }
    const fileName = this.normalizeString(item?.fileName);
    return fileName.length > 0 ? `${kind}:${fileName.toLowerCase()}` : '';
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}
