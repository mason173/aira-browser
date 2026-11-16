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
  systemHomepageShowSystemSearchBar: boolean;
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
  // The render identity is composed of independent dimensions. Only the document
  // source or the engine-level pipeline (forced dark) needs a new ArkWeb
  // generation; a plain appearance change repaints the mounted document.
  sourceKey: string;
  appearanceKey: string;
  renderPipelineKey: string;
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
      systemHomepageShowSystemSearchBar: settings.systemHomepageShowSystemSearchBar,
      showSystemSearchBar: showSystemSearchBar,
      hideToolbarOnScroll: showSystemSearchBar && resolveCustomHomepageHideToolbarOnScroll(settings),
      unavailableTitle: kind === 'custom_unavailable' ? '自定义主页不可用' : '',
      unavailableMessage: kind === 'custom_unavailable'
        ? '当前选择的自定义主页没有可加载地址，请重新选择或导入主页。'
        : ''
    };
  }

  /**
   * Identity of the document itself: which homepage is selected and where its
   * bytes come from. A change here means a different document has to be loaded,
   * so it is the only dimension allowed to materialize a new ArkWeb generation.
   */
  buildSourceKey(settings: CustomHomepageSettings): string {
    const selectedItem = this.resolveSelectedItem(settings);
    const sourceIdentity = selectedItem?.identityKey.trim() || settings.selectedItemId.trim();
    return [
      settings.mode,
      settings.selectedItemId,
      sourceIdentity,
      this.buildDocumentSourceKey(selectedItem),
      this.resolveWebUrl(settings, selectedItem)
    ].join('|');
  }

  /**
   * Appearance painted onto that document: the resolved theme. None of it changes
   * the document's bytes, so it must never cost a runtime rebuild.
   */
  buildAppearanceKey(
    settings: CustomHomepageSettings,
    resolvedThemeMode: BrowserResolvedThemeMode = 'light'
  ): string {
    void settings;
    return resolvedThemeMode;
  }

  /**
   * The dimensions ArkWeb applies at the engine level rather than in CSS: the
   * forced-dark toggle and the Web node's own background. `darkMode` and
   * `forceDarkAccess` cannot be changed by running script in the page, so a change
   * here still has to rebuild the document instead of repainting it in place.
   *
   * For an imported local homepage this is constant (`shouldForceDarkWebContent`
   * is only ever true for `remote_url`), which is precisely why the imported case
   * gets the cheap path on a theme flip while a URL homepage keeps the correct
   * forced-dark pipeline by rebuilding.
   */
  buildRenderPipelineKey(
    settings: CustomHomepageSettings,
    resolvedThemeMode: BrowserResolvedThemeMode = 'light'
  ): string {
    const selectedItem = this.resolveSelectedItem(settings);
    return this.shouldApplyForcedDarkWebContent(settings, selectedItem, resolvedThemeMode) ?
      'force-dark' :
      'normal';
  }

  // The composed key keeps its historical field order on purpose: it is persisted
  // inside the cold-start cover metadata, so changing its shape would invalidate
  // every stored cover and put a flash back on the first launch after an update.
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
      sourceKey: this.buildSourceKey(input.settings),
      appearanceKey: this.buildAppearanceKey(input.settings, input.resolvedThemeMode),
      renderPipelineKey: this.buildRenderPipelineKey(input.settings, input.resolvedThemeMode),
      renderKeyChanged: renderKeyChanged
    };
  }

  /**
   * Appearance policy for the third-party home document.
   *
   * Two independent decisions live here and must not be conflated:
   *
   * 1. **Whether to invert the page** — `darkMode: On` + `forceDarkAccess: true`. Only
   *    a URL-backed homepage ever asks for this (`shouldForceDarkWebContent` is false
   *    for imported local packages).
   * 2. **What colour scheme the document is told it is in** — this must follow the
   *    system, always.
   *
   * The second one is what a dark-mode cold start actually depends on. `WebDarkMode.Off`
   * is not neutral: it disables web dark mode for the node, overrides the system
   * setting, and makes the document report `prefers-color-scheme: light` while the
   * device is dark. An imported homepage whose dark theme sits behind that media query
   * then paints its light theme on the first frame and flips once its own script runs —
   * the flash. `WebDarkMode.Auto` is the value that means "do not invert, but keep the
   * media query honest".
   */
  buildWebAppearancePolicy(input: CustomHomepageWebAppearancePolicyInput): WebAppearancePolicy {
    const shouldForceDark = input.state.shouldForceDarkWebContent && input.resolvedThemeMode === 'dark';
    return resolveWebAppearancePolicy({
      darkMode: shouldForceDark ? WebDarkMode.On : WebDarkMode.Auto,
      forceDarkAccess: shouldForceDark,
      backgroundColor: input.backgroundColor,
      prefersDarkColorScheme: input.resolvedThemeMode === 'dark'
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
