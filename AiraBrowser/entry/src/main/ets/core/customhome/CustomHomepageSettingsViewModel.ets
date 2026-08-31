import {
  CustomHomepageItem,
  CustomHomepageRepositorySnapshot,
  CustomHomepageSettings,
  normalizeCustomHomepageBooleanByItemId,
  normalizeCustomHomepageSystemSearchVisibilityByItemId,
  resolveCustomHomepageForceDarkWebContent,
  resolveCustomHomepageHideToolbarOnScroll,
  resolveCustomHomepageItemBooleanById,
  resolveCustomHomepageSystemEntryButtonVisibility,
  resolveCustomHomepageSystemSearchVisibility
} from '../../common/models/CustomHomepageModels';
import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';
import { BrowserHomepageBackdropAppearanceState } from '../../common/models/BackdropAppearanceModels';

export interface CustomHomepageChoiceViewState {
  id: string;
  title: string;
  subtitle: string;
  url: string;
  isSelected: boolean;
  previewPath: string;
  siteIconPath: string;
  previewResource?: Resource;
  isRemoteUrl: boolean;
}

export interface CustomHomepageRemoteRefreshTargetViewState {
  id: string;
  url: string;
}

export interface CustomHomepageSettingsViewState {
  choices: CustomHomepageChoiceViewState[];
  systemHomepageSelected: boolean;
  customHomepageChromeControlsEnabled: boolean;
  remoteUrlAppearanceControlsEnabled: boolean;
  showSystemSearchBar: boolean;
  showSystemEntryButton: boolean;
  forceDarkRemoteUrlHomepage: boolean;
  hideToolbarOnScroll: boolean;
}

export interface CustomHomepageNativeSettingsAvailabilityState {
  isEnabled: boolean;
  footerText: string;
}

export interface CustomHomepagePreviewPair {
  lightUri: string;
  darkUri: string;
  lightAppearance?: BrowserHomepageBackdropAppearanceState;
  darkAppearance?: BrowserHomepageBackdropAppearanceState;
}

interface CustomHomepageImportSettingsResult {
  settings: CustomHomepageSettings;
  replacedItem?: CustomHomepageItem;
}

interface CustomHomepageRemoteUrlSettingsResult {
  settings: CustomHomepageSettings;
  item: CustomHomepageItem;
}

export class CustomHomepageSettingsViewModel {
  buildState(
    snapshot: CustomHomepageRepositorySnapshot,
    resolvedThemeMode: BrowserResolvedThemeMode = 'light'
  ): CustomHomepageSettingsViewState {
    const settings = snapshot.settings;
    const nativeSettingsAvailability = this.buildNativeHomepageSettingsAvailability(settings);
    return {
      choices: this.buildChoices(settings, resolvedThemeMode),
      systemHomepageSelected: nativeSettingsAvailability.isEnabled,
      customHomepageChromeControlsEnabled: !nativeSettingsAvailability.isEnabled,
      remoteUrlAppearanceControlsEnabled: this.isSelectedRemoteUrlHomepage(settings),
      showSystemSearchBar: resolveCustomHomepageSystemSearchVisibility(settings),
      showSystemEntryButton: resolveCustomHomepageSystemEntryButtonVisibility(settings),
      forceDarkRemoteUrlHomepage: resolveCustomHomepageForceDarkWebContent(settings),
      hideToolbarOnScroll: resolveCustomHomepageHideToolbarOnScroll(settings)
    };
  }

  withSystemSearchBar(
    state: CustomHomepageSettingsViewState,
    visible: boolean
  ): CustomHomepageSettingsViewState {
    return {
      choices: state.choices,
      systemHomepageSelected: state.systemHomepageSelected,
      customHomepageChromeControlsEnabled: state.customHomepageChromeControlsEnabled,
      remoteUrlAppearanceControlsEnabled: state.remoteUrlAppearanceControlsEnabled,
      showSystemSearchBar: visible,
      showSystemEntryButton: state.showSystemEntryButton,
      forceDarkRemoteUrlHomepage: state.forceDarkRemoteUrlHomepage,
      hideToolbarOnScroll: state.hideToolbarOnScroll
    };
  }

  withSystemEntryButton(
    state: CustomHomepageSettingsViewState,
    visible: boolean
  ): CustomHomepageSettingsViewState {
    return {
      choices: state.choices,
      systemHomepageSelected: state.systemHomepageSelected,
      customHomepageChromeControlsEnabled: state.customHomepageChromeControlsEnabled,
      remoteUrlAppearanceControlsEnabled: state.remoteUrlAppearanceControlsEnabled,
      showSystemSearchBar: state.showSystemSearchBar,
      showSystemEntryButton: visible,
      forceDarkRemoteUrlHomepage: state.forceDarkRemoteUrlHomepage,
      hideToolbarOnScroll: state.hideToolbarOnScroll
    };
  }

  withForceDarkRemoteUrlHomepage(
    state: CustomHomepageSettingsViewState,
    enabled: boolean
  ): CustomHomepageSettingsViewState {
    return {
      choices: state.choices,
      systemHomepageSelected: state.systemHomepageSelected,
      customHomepageChromeControlsEnabled: state.customHomepageChromeControlsEnabled,
      remoteUrlAppearanceControlsEnabled: state.remoteUrlAppearanceControlsEnabled,
      showSystemSearchBar: state.showSystemSearchBar,
      showSystemEntryButton: state.showSystemEntryButton,
      forceDarkRemoteUrlHomepage: enabled,
      hideToolbarOnScroll: state.hideToolbarOnScroll
    };
  }

  withHideToolbarOnScroll(
    state: CustomHomepageSettingsViewState,
    enabled: boolean
  ): CustomHomepageSettingsViewState {
    return {
      choices: state.choices,
      systemHomepageSelected: state.systemHomepageSelected,
      customHomepageChromeControlsEnabled: state.customHomepageChromeControlsEnabled,
      remoteUrlAppearanceControlsEnabled: state.remoteUrlAppearanceControlsEnabled,
      showSystemSearchBar: state.showSystemSearchBar,
      showSystemEntryButton: state.showSystemEntryButton,
      forceDarkRemoteUrlHomepage: state.forceDarkRemoteUrlHomepage,
      hideToolbarOnScroll: enabled
    };
  }

  withChoices(
    state: CustomHomepageSettingsViewState,
    choices: CustomHomepageChoiceViewState[]
  ): CustomHomepageSettingsViewState {
    return {
      choices: choices,
      systemHomepageSelected: state.systemHomepageSelected,
      customHomepageChromeControlsEnabled: state.customHomepageChromeControlsEnabled,
      remoteUrlAppearanceControlsEnabled: state.remoteUrlAppearanceControlsEnabled,
      showSystemSearchBar: state.showSystemSearchBar,
      showSystemEntryButton: state.showSystemEntryButton,
      forceDarkRemoteUrlHomepage: state.forceDarkRemoteUrlHomepage,
      hideToolbarOnScroll: state.hideToolbarOnScroll
    };
  }

  buildNativeHomepageSettingsAvailability(
    settings: CustomHomepageSettings
  ): CustomHomepageNativeSettingsAvailabilityState {
    const isEnabled = !this.isCustomHomepageSelected(settings);
    return {
      isEnabled: isEnabled,
      footerText: isEnabled ?
        '图标外观、壁纸和系统搜索设置仅对 Aira 原生主页生效；第三方主页在“自定义主页”中单独设置。' :
        '当前正在使用第三方主页，Aira 原生主页设置暂不可调整；当前主页的显示与滚动行为可在“自定义主页”中设置。'
    };
  }

  buildSystemSettings(current: CustomHomepageSettings): CustomHomepageSettings {
    return this.withSelectedItem(current, '');
  }

  buildCustomSettings(current: CustomHomepageSettings, itemId: string): CustomHomepageSettings {
    return this.withSelectedItem(current, itemId);
  }

  buildImportedSettings(current: CustomHomepageSettings, item: CustomHomepageItem): CustomHomepageSettings {
    return this.buildImportedSettingsResult(current, item).settings;
  }

  buildImportedSettingsResult(
    current: CustomHomepageSettings,
    item: CustomHomepageItem
  ): CustomHomepageImportSettingsResult {
    const matchingItem = this.findImportReplacementItem(current, item);
    const importedItem = matchingItem !== undefined ? this.buildReplacementItem(matchingItem, item) : item;
    const nextItems = matchingItem !== undefined ?
      [importedItem].concat(current.items.filter((candidate: CustomHomepageItem): boolean => candidate.id !== matchingItem.id)) :
      [importedItem].concat(current.items);
    return {
      settings: this.normalizeSettings({
        mode: 'custom_html',
        selectedItemId: importedItem.id,
        items: nextItems,
        updatedAt: Date.now(),
        systemHomepageShowSystemSearchBar: current.systemHomepageShowSystemSearchBar,
        showSystemSearchBarByItemId: current.showSystemSearchBarByItemId,
        showSystemEntryButtonByItemId: current.showSystemEntryButtonByItemId,
        forceDarkWebContentByItemId: current.forceDarkWebContentByItemId,
        hideToolbarOnScrollByItemId: current.hideToolbarOnScrollByItemId,
        hideToolbarOnScroll: current.hideToolbarOnScroll
      }),
      replacedItem: matchingItem
    };
  }

  findImportReplacementItem(current: CustomHomepageSettings, item: CustomHomepageItem): CustomHomepageItem | undefined {
    const identityKey = this.normalizeIdentityKey(item.identityKey);
    if (identityKey.length <= 0) {
      return undefined;
    }
    return current.items.find((candidate: CustomHomepageItem): boolean => {
      return this.normalizeIdentityKey(candidate.identityKey) === identityKey;
    });
  }

  private buildReplacementItem(previous: CustomHomepageItem, imported: CustomHomepageItem): CustomHomepageItem {
    return {
      id: previous.id,
      identityKey: this.normalizeIdentityKey(imported.identityKey),
      kind: imported.kind,
      fileName: imported.fileName,
      filePath: imported.filePath,
      fileUri: imported.fileUri,
      rootPath: imported.rootPath,
      packageRootPath: imported.packageRootPath,
      entryPath: imported.entryPath,
      manifestPath: imported.manifestPath,
      packageName: imported.packageName,
      version: imported.version,
      author: imported.author,
      description: imported.description,
      previewPath: imported.previewPath,
      previewUri: imported.previewUri,
      previewLightUri: imported.previewLightUri,
      previewDarkUri: imported.previewDarkUri,
      hasLightAppearanceEvidence: imported.hasLightAppearanceEvidence,
      hasDarkAppearanceEvidence: imported.hasDarkAppearanceEvidence,
      appearanceLight: imported.appearanceLight,
      appearanceDark: imported.appearanceDark,
      remoteUrl: imported.remoteUrl,
      siteIconUri: imported.siteIconUri.trim().length > 0 ? imported.siteIconUri : previous.siteIconUri,
      packageSize: imported.packageSize,
      extractedSize: imported.extractedSize,
      byteSize: imported.byteSize,
      importedAt: previous.importedAt > 0 ? previous.importedAt : imported.importedAt,
      updatedAt: imported.updatedAt
    };
  }

  private normalizeIdentityKey(value: string): string {
    return value.trim().toLowerCase();
  }

  buildRemoteUrlSettingsResult(
    current: CustomHomepageSettings,
    url: string,
    title: string
  ): CustomHomepageRemoteUrlSettingsResult {
    const now = Date.now();
    const normalizedTitle = title.trim().length > 0 ? title.trim() : url.trim();
    const item: CustomHomepageItem = {
      id: `home_${now}_${Math.floor(Math.random() * 1000000)}`,
      identityKey: `remote_url:${url.trim().toLowerCase()}`,
      kind: 'remote_url',
      fileName: normalizedTitle,
      filePath: url.trim(),
      fileUri: url.trim(),
      rootPath: '',
      packageRootPath: '',
      entryPath: '',
      manifestPath: '',
      packageName: normalizedTitle,
      version: '',
      author: '',
      description: '',
      previewPath: '',
      previewUri: '',
      previewLightUri: '',
      previewDarkUri: '',
      remoteUrl: url.trim(),
      siteIconUri: '',
      packageSize: 0,
      extractedSize: 0,
      byteSize: 0,
      importedAt: now,
      updatedAt: now
    };
    return {
      settings: this.buildImportedSettings(current, item),
      item: item
    };
  }

  buildSiteIconSettings(current: CustomHomepageSettings, itemId: string, siteIconUri: string): CustomHomepageSettings {
    const normalizedId = itemId.trim();
    const normalizedSiteIconUri = siteIconUri.trim();
    if (normalizedId.length <= 0 || normalizedSiteIconUri.length <= 0) {
      return this.normalizeSettings(current);
    }
    let changed = false;
    const nextItems = current.items.map((item: CustomHomepageItem): CustomHomepageItem => {
      if (item.id !== normalizedId || item.kind !== 'remote_url' || item.siteIconUri === normalizedSiteIconUri) {
        return item;
      }
      changed = true;
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
        appearanceLight: item.appearanceLight,
        appearanceDark: item.appearanceDark,
        remoteUrl: item.remoteUrl,
        siteIconUri: normalizedSiteIconUri,
        packageSize: item.packageSize,
        extractedSize: item.extractedSize,
        byteSize: item.byteSize,
        importedAt: item.importedAt,
        updatedAt: Date.now()
      };
    });
    if (!changed) {
      return this.normalizeSettings(current);
    }
    return this.normalizeSettings({
      mode: current.mode,
      selectedItemId: current.selectedItemId,
      items: nextItems,
      updatedAt: Date.now(),
      systemHomepageShowSystemSearchBar: current.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: current.showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: current.showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: current.forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: current.hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: current.hideToolbarOnScroll
    });
  }

  buildPreviewPairSettings(
    current: CustomHomepageSettings,
    itemId: string,
    previews: CustomHomepagePreviewPair
  ): CustomHomepageSettings {
    const normalizedId = itemId.trim();
    const normalizedLightUri = previews.lightUri.trim();
    const normalizedDarkUri = previews.darkUri.trim();
    const lightAppearance = previews.lightAppearance;
    const darkAppearance = previews.darkAppearance;
    const normalizedPreviewUri = this.resolveDefaultPreviewUri(normalizedLightUri, normalizedDarkUri);
    if (normalizedId.length <= 0 || normalizedPreviewUri.length <= 0) {
      return this.normalizeSettings(current);
    }
    let changed = false;
    const nextItems = current.items.map((item: CustomHomepageItem): CustomHomepageItem => {
      if (item.id !== normalizedId || item.kind !== 'remote_url' ||
        (item.previewUri === normalizedPreviewUri &&
          item.previewLightUri === normalizedLightUri &&
          item.previewDarkUri === normalizedDarkUri &&
          lightAppearance === undefined &&
          darkAppearance === undefined)) {
        return item;
      }
      changed = true;
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
        previewPath: normalizedPreviewUri,
        previewUri: normalizedPreviewUri,
        previewLightUri: normalizedLightUri,
        previewDarkUri: normalizedDarkUri,
        hasLightAppearanceEvidence: item.hasLightAppearanceEvidence,
        hasDarkAppearanceEvidence: item.hasDarkAppearanceEvidence,
        appearanceLight: lightAppearance ?? item.appearanceLight,
        appearanceDark: darkAppearance ?? item.appearanceDark,
        remoteUrl: item.remoteUrl,
        siteIconUri: item.siteIconUri,
        packageSize: item.packageSize,
        extractedSize: item.extractedSize,
        byteSize: item.byteSize,
        importedAt: item.importedAt,
        updatedAt: Date.now()
      };
    });
    if (!changed) {
      return this.normalizeSettings(current);
    }
    return this.normalizeSettings({
      mode: current.mode,
      selectedItemId: current.selectedItemId,
      items: nextItems,
      updatedAt: Date.now(),
      systemHomepageShowSystemSearchBar: current.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: current.showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: current.showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: current.forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: current.hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: current.hideToolbarOnScroll
    });
  }

  findItem(settings: CustomHomepageSettings, itemId: string): CustomHomepageItem | undefined {
    const normalizedId = itemId.trim();
    return settings.items.find((item: CustomHomepageItem): boolean => item.id === normalizedId);
  }

  resolveRemoteHomepagePreviewRefreshTargets(
    state: CustomHomepageSettingsViewState
  ): CustomHomepageRemoteRefreshTargetViewState[] {
    return state.choices
      .filter((choice: CustomHomepageChoiceViewState): boolean => {
        return choice.isRemoteUrl && choice.url.trim().length > 0;
      })
      .map((choice: CustomHomepageChoiceViewState): CustomHomepageRemoteRefreshTargetViewState => {
        return {
          id: choice.id,
          url: choice.url.trim()
        };
      });
  }

  private buildChoices(
    settings: CustomHomepageSettings,
    resolvedThemeMode: BrowserResolvedThemeMode
  ): CustomHomepageChoiceViewState[] {
    const choices: CustomHomepageChoiceViewState[] = [];
    settings.items.forEach((item: CustomHomepageItem) => {
      choices.push({
        id: item.id,
        title: this.resolveItemTitle(item),
        subtitle: this.resolveItemSubtitle(item),
        url: item.kind === 'remote_url' ? item.remoteUrl.trim() : item.fileUri.trim(),
        isSelected: settings.mode === 'custom_html' && settings.selectedItemId === item.id,
        previewPath: this.resolveItemPreviewPath(item, settings, resolvedThemeMode),
        siteIconPath: item.siteIconUri.trim(),
        previewResource: undefined,
        isRemoteUrl: item.kind === 'remote_url'
      });
    });
    return choices;
  }

  private resolveItemPreviewPath(
    item: CustomHomepageItem,
    settings: CustomHomepageSettings,
    resolvedThemeMode: BrowserResolvedThemeMode
  ): string {
    const previewUri = item.previewUri.trim();
    const previewPath = item.previewPath.trim();
    const lightUri = item.previewLightUri.trim();
    const darkUri = item.previewDarkUri.trim();
    const shouldUseDark = resolvedThemeMode === 'dark' &&
      (item.kind !== 'remote_url' || resolveCustomHomepageItemBooleanById(
        settings.forceDarkWebContentByItemId,
        item.id,
        true
      ));
    if (shouldUseDark && darkUri.length > 0) {
      return darkUri;
    }
    if (lightUri.length > 0) {
      return lightUri;
    }
    if (darkUri.length > 0) {
      return darkUri;
    }
    return previewUri.length > 0 ? previewUri : previewPath;
  }

  private resolveDefaultPreviewUri(lightUri: string, darkUri: string): string {
    return lightUri.length > 0 ? lightUri : darkUri;
  }

  private withSelectedItem(current: CustomHomepageSettings, itemId: string): CustomHomepageSettings {
    const item = this.findItem(current, itemId);
    if (item === undefined) {
      return this.normalizeSettings({
        mode: 'system',
        selectedItemId: '',
        items: current.items,
        updatedAt: Date.now(),
        systemHomepageShowSystemSearchBar: current.systemHomepageShowSystemSearchBar,
        showSystemSearchBarByItemId: current.showSystemSearchBarByItemId,
        showSystemEntryButtonByItemId: current.showSystemEntryButtonByItemId,
        forceDarkWebContentByItemId: current.forceDarkWebContentByItemId,
        hideToolbarOnScrollByItemId: current.hideToolbarOnScrollByItemId,
        hideToolbarOnScroll: current.hideToolbarOnScroll
      });
    }
    return this.normalizeSettings({
      mode: 'custom_html',
      selectedItemId: item.id,
      items: current.items,
      updatedAt: Date.now(),
      systemHomepageShowSystemSearchBar: current.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: current.showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: current.showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: current.forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: current.hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: current.hideToolbarOnScroll
    });
  }

  private normalizeSettings(settings: CustomHomepageSettings): CustomHomepageSettings {
    const item = this.findItem(settings, settings.selectedItemId);
    const showSystemSearchBarByItemId = normalizeCustomHomepageSystemSearchVisibilityByItemId(
      settings.items,
      settings.showSystemSearchBarByItemId
    );
    const showSystemEntryButtonByItemId = normalizeCustomHomepageBooleanByItemId(
      settings.items,
      settings.showSystemEntryButtonByItemId,
      false
    );
    const forceDarkWebContentByItemId = normalizeCustomHomepageBooleanByItemId(
      settings.items,
      settings.forceDarkWebContentByItemId,
      true
    );
    const hideToolbarOnScrollByItemId = normalizeCustomHomepageBooleanByItemId(
      settings.items,
      settings.hideToolbarOnScrollByItemId,
      false
    );
    if (settings.mode !== 'custom_html' || item === undefined) {
      return {
        mode: 'system',
        selectedItemId: '',
        items: settings.items,
        updatedAt: settings.updatedAt,
        systemHomepageShowSystemSearchBar: settings.systemHomepageShowSystemSearchBar,
        showSystemSearchBarByItemId: showSystemSearchBarByItemId,
        showSystemEntryButtonByItemId: showSystemEntryButtonByItemId,
        forceDarkWebContentByItemId: forceDarkWebContentByItemId,
        hideToolbarOnScrollByItemId: hideToolbarOnScrollByItemId,
        hideToolbarOnScroll: settings.hideToolbarOnScroll
      };
    }
    return {
      mode: 'custom_html',
      selectedItemId: item.id,
      items: settings.items,
      updatedAt: settings.updatedAt,
      systemHomepageShowSystemSearchBar: settings.systemHomepageShowSystemSearchBar,
      showSystemSearchBarByItemId: showSystemSearchBarByItemId,
      showSystemEntryButtonByItemId: showSystemEntryButtonByItemId,
      forceDarkWebContentByItemId: forceDarkWebContentByItemId,
      hideToolbarOnScrollByItemId: hideToolbarOnScrollByItemId,
      hideToolbarOnScroll: settings.hideToolbarOnScroll
    };
  }

  private isSelectedRemoteUrlHomepage(settings: CustomHomepageSettings): boolean {
    if (settings.mode !== 'custom_html') {
      return false;
    }
    const item = this.findItem(settings, settings.selectedItemId);
    return item?.kind === 'remote_url';
  }

  private isCustomHomepageSelected(settings: CustomHomepageSettings): boolean {
    return settings.mode === 'custom_html' && settings.selectedItemId.length > 0;
  }

  private formatByteSize(byteSize: number): string {
    if (byteSize <= 0) {
      return '大小未知';
    }
    if (byteSize < 1024) {
      return `${byteSize} B`;
    }
    const kb = byteSize / 1024;
    if (kb < 1024) {
      return `${this.formatFixed(kb)} KB`;
    }
    return `${this.formatFixed(kb / 1024)} MB`;
  }

  private formatFixed(value: number): string {
    const rounded = Math.round(value * 10) / 10;
    return `${rounded}`;
  }

  private resolveItemTitle(item: CustomHomepageItem): string {
    if (item.kind === 'remote_url') {
      return item.packageName.trim().length > 0 ? item.packageName.trim() : item.remoteUrl;
    }
    if (item.kind === 'zip_package' && item.packageName.trim().length > 0) {
      return item.packageName.trim();
    }
    return item.fileName;
  }

  private resolveItemSubtitle(item: CustomHomepageItem): string {
    if (item.kind === 'remote_url') {
      return item.remoteUrl.trim().length > 0 ? `网址 · ${item.remoteUrl.trim()}` : '网址';
    }
    const size = item.kind === 'zip_package' && item.packageSize > 0 ? item.packageSize : item.byteSize;
    const prefix = item.kind === 'zip_package' ? '主页包' : 'HTML';
    const author = item.author.trim();
    return author.length > 0 ? `${prefix} · ${author} · ${this.formatByteSize(size)}` : `${prefix} · ${this.formatByteSize(size)}`;
  }

}
