import {
  CustomHomepageItem,
  CustomHomepageSettings,
  resolveCustomHomepageForceDarkWebContent,
  resolveCustomHomepageHideToolbarOnScroll,
  resolveCustomHomepageSystemEntryButtonVisibility,
  resolveCustomHomepageSystemSearchVisibility
} from '../../common/models/CustomHomepageModels';
import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';
import {
  resolveWebAppearancePolicy,
  WebAppearancePolicy
} from '../web/WebAppearancePolicy';

type CustomHomepagePresentationKind = 'system' | 'custom_web' | 'custom_unavailable';

export interface CustomHomepagePresentationState {
  kind: CustomHomepagePresentationKind;
  shouldRenderCustomHtml: boolean;
  webUrl: string;
  isRemoteUrlHomepage: boolean;
  shouldForceDarkWebContent: boolean;
  showSystemEntryButton: boolean;
  showSystemSearchBar: boolean;
  hideToolbarOnScroll: boolean;
  unavailableTitle: string;
  unavailableMessage: string;
}

interface CustomHomepageRefreshInput {
  forceReload: boolean;
  previousUrl: string;
  previousRenderKey: string;
  settings: CustomHomepageSettings;
  resolvedThemeMode?: BrowserResolvedThemeMode;
}

interface CustomHomepageRefreshPlan {
  state: CustomHomepagePresentationState;
  renderKey: string;
  renderKeyChanged: boolean;
}

interface CustomHomepageWebAppearancePolicyInput {
  state: CustomHomepagePresentationState;
  resolvedThemeMode: BrowserResolvedThemeMode;
  backgroundColor: string;
}

export class CustomHomepagePresentationViewModel {
  buildState(settings: CustomHomepageSettings): CustomHomepagePresentationState {
    const selectedItem = this.resolveSelectedItem(settings);
    const webUrl = this.resolveWebUrl(settings, selectedItem);
    const customHomepageSelected = settings.mode === 'custom_html';
    const shouldRenderCustomHtml = customHomepageSelected && webUrl.length > 0;
    const isRemoteUrlHomepage = selectedItem?.kind === 'remote_url';
    const kind = this.resolvePresentationKind(customHomepageSelected, shouldRenderCustomHtml);
    const showSystemSearchBar = resolveCustomHomepageSystemSearchVisibility(settings);
    return {
      kind: kind,
      shouldRenderCustomHtml: shouldRenderCustomHtml,
      webUrl: webUrl,
      isRemoteUrlHomepage: isRemoteUrlHomepage,
      shouldForceDarkWebContent: shouldRenderCustomHtml && this.shouldForceDarkWebContent(settings, selectedItem),
      showSystemEntryButton: shouldRenderCustomHtml && resolveCustomHomepageSystemEntryButtonVisibility(settings),
      showSystemSearchBar: showSystemSearchBar,
      hideToolbarOnScroll: showSystemSearchBar && resolveCustomHomepageHideToolbarOnScroll(settings),
      unavailableTitle: kind === 'custom_unavailable' ? '自定义主页不可用' : '',
      unavailableMessage: kind === 'custom_unavailable'
        ? '当前选择的自定义主页没有可加载地址，请重新选择或导入主页。'
        : ''
    };
  }

  buildRenderKey(settings: CustomHomepageSettings, resolvedThemeMode: BrowserResolvedThemeMode = 'light'): string {
    const selectedItem = this.resolveSelectedItem(settings);
    const sourceIdentity = selectedItem?.identityKey.trim() || settings.selectedItemId.trim();
    const documentSourceKey = this.buildDocumentSourceKey(selectedItem);
    const forceDarkKey = this.shouldApplyForcedDarkWebContent(settings, selectedItem, resolvedThemeMode) ?
      'force-dark' :
      'normal';
    return [
      settings.mode,
      settings.selectedItemId,
      sourceIdentity,
      documentSourceKey,
      resolvedThemeMode,
      forceDarkKey,
      this.resolveWebUrl(settings, selectedItem)
    ].join('|');
  }

  private buildDocumentSourceKey(item: CustomHomepageItem | undefined): string {
    if (item === undefined) {
      return '';
    }
    return [
      item.kind,
      item.filePath,
      item.fileUri,
      item.rootPath,
      item.packageRootPath,
      item.entryPath,
      item.manifestPath,
      item.remoteUrl,
      `${item.packageSize}`,
      `${item.extractedSize}`,
      `${item.byteSize}`
    ].join('~');
  }

  buildRefreshPlan(input: CustomHomepageRefreshInput): CustomHomepageRefreshPlan {
    const state = this.buildState(input.settings);
    const nextRenderKey = this.buildRenderKey(input.settings, input.resolvedThemeMode);
    const renderKeyChanged = input.forceReload || input.previousUrl !== state.webUrl ||
      input.previousRenderKey !== nextRenderKey;
    return {
      state: state,
      renderKey: nextRenderKey,
      renderKeyChanged: renderKeyChanged
    };
  }

  buildWebAppearancePolicy(input: CustomHomepageWebAppearancePolicyInput): WebAppearancePolicy {
    const shouldForceDark = input.state.shouldForceDarkWebContent && input.resolvedThemeMode === 'dark';
    return resolveWebAppearancePolicy({
      darkMode: shouldForceDark ? WebDarkMode.On : WebDarkMode.Off,
      forceDarkAccess: shouldForceDark,
      backgroundColor: input.backgroundColor,
      prefersDarkColorScheme: shouldForceDark
    });
  }

  private resolvePresentationKind(
    customHomepageSelected: boolean,
    shouldRenderCustomHtml: boolean
  ): CustomHomepagePresentationKind {
    if (!customHomepageSelected) {
      return 'system';
    }
    if (shouldRenderCustomHtml) {
      return 'custom_web';
    }
    return 'custom_unavailable';
  }

  private resolveSelectedItem(settings: CustomHomepageSettings): CustomHomepageItem | undefined {
    if (settings.mode !== 'custom_html') {
      return undefined;
    }
    if (settings.selectedItemId.length > 0) {
      return settings.items.find((candidate): boolean => {
        return candidate.id === settings.selectedItemId;
      });
    }
    return undefined;
  }

  private resolveWebUrl(settings: CustomHomepageSettings, selectedItem = this.resolveSelectedItem(settings)): string {
    if (settings.mode !== 'custom_html') {
      return '';
    }
    if (selectedItem?.kind === 'remote_url') {
      return selectedItem.remoteUrl.trim();
    }
    return this.buildFileUrlFromPath(selectedItem?.filePath ?? '');
  }

  private shouldForceDarkWebContent(
    settings: CustomHomepageSettings,
    selectedItem: CustomHomepageItem | undefined
  ): boolean {
    return settings.mode === 'custom_html' && selectedItem?.kind === 'remote_url' &&
      resolveCustomHomepageForceDarkWebContent(settings);
  }

  private shouldApplyForcedDarkWebContent(
    settings: CustomHomepageSettings,
    selectedItem: CustomHomepageItem | undefined,
    resolvedThemeMode: BrowserResolvedThemeMode
  ): boolean {
    return resolvedThemeMode === 'dark' && this.shouldForceDarkWebContent(settings, selectedItem);
  }

  private buildFileUrlFromPath(path: string): string {
    const normalizedPath = path.trim();
    if (normalizedPath.length === 0) {
      return '';
    }
    if (normalizedPath.startsWith('file://')) {
      return normalizedPath;
    }
    return `file://${normalizedPath}`;
  }
}
