import { sharedPreferencesRepository } from '../../app/bootstrap/BrowserAppRuntime';
import {
  BrowserResolvedThemeMode,
  BrowserThemeMode,
  BrowserUserAgentSettings
} from '../../common/models/BrowserModels';
import {
  BrowserDesktopSiteMode,
  BrowserUserAgentService
} from '../../services/web/BrowserUserAgentService';
import { AppChromeIconTone } from '../resources/AppIconResources';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import { BrowserBookmarkActionState } from './BrowserBookmarkActionCoordinator';
import { isSecureCurrentSiteUrl } from './AddressDisplayFormatter';
import { BrowserBottomPanelActionId } from './BrowserBottomPanelActionCatalog';
import {
  BrowserBottomAddressPanelAction,
  BrowserBottomAddressPanelActionId,
  BrowserBottomAddressPanelBuildInput,
  BrowserBottomAddressPanelHeaderAction,
  BrowserBottomAddressPanelViewModel,
  BrowserBottomToolbarLayoutInput
} from './BrowserBottomAddressPanelViewModel';
import {
  BrowserBottomPanelActionEnablement,
  BrowserBottomPanelActionEnablementById
} from './BrowserBottomPanelActionEnablement';
import { BrowserBottomPanelResponsiveState } from './BrowserBottomPanelResponsiveViewModel';
import { BrowserScreenOrientationMode, BrowserScreenOrientationViewModel } from './BrowserScreenOrientationViewModel';
import { BrowserWebTextZoomViewModel } from './BrowserWebTextZoomViewModel';
import { BrowserDesktopSiteModeSheetViewModel } from './BrowserDesktopSiteModeSheetViewModel';
import {
  BrowserWebSurfaceActionEntryInput,
  BrowserWebSurfaceActionEntryViewModel,
  BrowserWebSurfaceActionTarget,
  BrowserWebSurfaceActionTargetInput
} from './BrowserWebSurfaceActionEntryViewModel';
import { WebpageTranslationEntryViewModel } from '../translation/WebpageTranslationEntryViewModel';
import {
  BrowserToolbarCustomizationViewModel,
  BrowserToolbarSlotActionState
} from './BrowserToolbarCustomizationViewModel';

export interface BrowserBottomPanelActionSurfaceInput {
  activeTabIsWebPage: boolean;
  webPageVisible: boolean;
  tabsSheetVisible: boolean;
  targetUrls: string[];
}

export interface BrowserBottomPanelActionAvailabilityInput {
  surface: BrowserBottomPanelActionSurfaceInput;
  pageFindEnabled: boolean;
  bookmarkActionState: BrowserBookmarkActionState;
  manualElementHideEnabled: boolean;
  elementInspectionEnabled: boolean;
}

export type BrowserBottomPanelActionTargetInput = BrowserWebSurfaceActionTargetInput;
export type BrowserBottomPanelActionTarget = BrowserWebSurfaceActionTarget;

export interface BrowserRootBottomPanelActionPresentationFacts {
  currentUrl: string;
  addressInput: string;
  chromeIconTone: AppChromeIconTone;
  currentDocumentViewerPage: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  manualElementHideRuleCount: number;
  manualElementHideEnabled: boolean;
  elementInspectionEnabled: boolean;
  privateModeActive: boolean;
}

export interface BrowserBottomPanelActionPresentationInput {
  currentUrl: string;
  addressInput: string;
  chromeIconTone: AppChromeIconTone;
  currentDocumentViewerPage: boolean;
  effectiveWebMode: boolean;
  effectiveHomeMode: boolean;
  canGoBack: boolean;
  canGoForward: boolean;
  manualElementHideRuleCount: number;
  manualElementHideEnabled: boolean;
  elementInspectionEnabled: boolean;
  privateModeActive: boolean;
}

export interface BrowserBottomPanelActionSnapshot {
  revision: number;
  actionInput: BrowserBottomAddressPanelBuildInput;
  primaryActionOverrides?: BrowserBottomAddressPanelAction[];
  secondaryActionOverrides?: BrowserBottomAddressPanelAction[];
  quickActionOverrides?: BrowserBottomAddressPanelAction[];
  actionRenderKey: string;
  presentationKey: string;
}

export interface BrowserBottomPanelActionSnapshotInput {
  presentation: BrowserRootBottomPanelActionPresentationFacts;
  contentMode: 'home' | 'web';
  addressFocused: boolean;
  effectiveHomeMode: boolean;
  effectiveWebMode: boolean;
  surface: BrowserBottomPanelActionSurfaceInput;
  pageFindEnabled: boolean;
  appProxyActive: boolean;
  bookmarkActionState: BrowserBookmarkActionState;
  bookmarkActionVersion: number;
  privateTabModeActive: boolean;
  desktopSiteMode: BrowserDesktopSiteMode;
  userAgentActionVersion: number;
  textZoomRatio: number;
  textZoomActionVersion: number;
  userAgentPresetSettings: BrowserUserAgentSettings;
  userAgentPresetActionVersion: number;
  screenOrientationMode: BrowserScreenOrientationMode;
  screenOrientationActionVersion: number;
  themeMode: BrowserThemeMode;
  resolvedThemeMode: BrowserResolvedThemeMode;
  themeModeIcon: Resource;
  themeModeActionVersion: number;
  fullScreenModeEnabled: boolean;
  fullScreenModeActionVersion: number;
  toolbarLayoutVersion: number;
  responsiveLayoutKey: string;
  responsiveState: BrowserBottomPanelResponsiveState;
}

export class BrowserBottomPanelActionPresentationCoordinator {
  private viewModel: BrowserBottomAddressPanelViewModel = new BrowserBottomAddressPanelViewModel();
  private webSurfaceActionEntryViewModel: BrowserWebSurfaceActionEntryViewModel =
    new BrowserWebSurfaceActionEntryViewModel();
  private webpageTranslationEntryViewModel: WebpageTranslationEntryViewModel =
    new WebpageTranslationEntryViewModel();
  private userAgentService: BrowserUserAgentService = new BrowserUserAgentService();
  private screenOrientationViewModel: BrowserScreenOrientationViewModel = new BrowserScreenOrientationViewModel();
  private textZoomViewModel: BrowserWebTextZoomViewModel = new BrowserWebTextZoomViewModel();
  private desktopSiteModeViewModel: BrowserDesktopSiteModeSheetViewModel =
    new BrowserDesktopSiteModeSheetViewModel();
  private toolbarCustomizationViewModel: BrowserToolbarCustomizationViewModel =
    new BrowserToolbarCustomizationViewModel();
  private snapshotRevision: number = 0;
  private cachedSnapshotKey: string = '';
  private cachedSnapshot?: BrowserBottomPanelActionSnapshot;

  resolveActionSnapshot(input: BrowserBottomPanelActionSnapshotInput): BrowserBottomPanelActionSnapshot {
    const snapshotKey = this.buildSnapshotKey(input);
    if (this.cachedSnapshot !== undefined && this.cachedSnapshotKey === snapshotKey) {
      return this.cachedSnapshot;
    }
    const actionInput = this.buildAddressPanelActionInput(input);
    const presentationInput = this.buildActionPresentationInput(input);
    const actionRenderKey = this.buildAddressPanelActionRenderKey(actionInput, presentationInput);
    const shouldResolveOverrides = this.shouldResolveActionOverrides(input.contentMode, input.addressFocused);
    const primaryActionOverrides = shouldResolveOverrides
      ? this.resolvePrimaryActions(presentationInput, actionInput, input.responsiveState)
      : undefined;
    const secondaryActionOverrides = shouldResolveOverrides
      ? this.resolveSecondaryActions(
        presentationInput,
        actionInput,
        primaryActionOverrides,
        input.responsiveState
      )
      : undefined;
    const quickActionOverrides = shouldResolveOverrides
      ? this.resolveQuickActions(presentationInput, actionInput, input.responsiveState)
      : undefined;
    this.snapshotRevision += 1;
    const snapshot: BrowserBottomPanelActionSnapshot = {
      revision: this.snapshotRevision,
      actionInput,
      primaryActionOverrides,
      secondaryActionOverrides,
      quickActionOverrides,
      presentationKey: snapshotKey,
      actionRenderKey
    };
    this.cachedSnapshotKey = snapshotKey;
    this.cachedSnapshot = snapshot;
    return snapshot;
  }

  resolveTarget(input: BrowserBottomPanelActionTargetInput): BrowserBottomPanelActionTarget {
    return this.webSurfaceActionEntryViewModel.resolveTarget(input);
  }

  resolveActionEnablement(
    actionId: BrowserBottomPanelActionId,
    input: BrowserBottomPanelActionAvailabilityInput
  ): BrowserBottomPanelActionEnablement {
    return this.buildActionEnablementFromAvailability(input)[actionId] ?? {
      enabled: true,
      disabledMessage: ''
    };
  }

  resolveWebpageTranslationPromptAvailability(surface: BrowserBottomPanelActionSurfaceInput): boolean {
    return this.webpageTranslationEntryViewModel.canShowPromptSurface({
      activeTabIsWebPage: surface.activeTabIsWebPage,
      webPageVisible: surface.webPageVisible,
      tabsSheetVisible: surface.tabsSheetVisible,
      targetUrls: surface.targetUrls
    });
  }

  resolveBookmarkActionAvailability(surface: BrowserBottomPanelActionSurfaceInput): boolean {
    for (let index = 0; index < surface.targetUrls.length; index += 1) {
      const lower = surface.targetUrls[index].trim().toLowerCase();
      if (lower.startsWith('http://') || lower.startsWith('https://')) {
        return true;
      }
    }
    return false;
  }

  resolveToolbarSlotActions(): BrowserToolbarSlotActionState[] {
    return this.toolbarCustomizationViewModel.buildSlotActions(
      sharedPreferencesRepository.getPreferences().toolbarLayout
    );
  }

  private buildActionPresentationInput(
    input: BrowserBottomPanelActionSnapshotInput
  ): BrowserBottomPanelActionPresentationInput {
    return {
      currentUrl: input.presentation.currentUrl,
      addressInput: input.presentation.addressInput,
      chromeIconTone: input.presentation.chromeIconTone,
      currentDocumentViewerPage: input.presentation.currentDocumentViewerPage,
      effectiveWebMode: input.effectiveWebMode,
      effectiveHomeMode: input.effectiveHomeMode,
      canGoBack: input.presentation.canGoBack,
      canGoForward: input.presentation.canGoForward,
      manualElementHideRuleCount: input.presentation.manualElementHideRuleCount,
      manualElementHideEnabled: input.presentation.manualElementHideEnabled,
      elementInspectionEnabled: input.presentation.elementInspectionEnabled,
      privateModeActive: input.presentation.privateModeActive
    };
  }

  private buildActionEnablement(
    input: BrowserBottomPanelActionSnapshotInput
  ): BrowserBottomPanelActionEnablementById {
    return this.buildActionEnablementFromAvailability({
      surface: input.surface,
      pageFindEnabled: input.pageFindEnabled,
      bookmarkActionState: input.bookmarkActionState,
      manualElementHideEnabled: input.presentation.manualElementHideEnabled,
      elementInspectionEnabled: input.presentation.elementInspectionEnabled
    });
  }

  private buildActionEnablementFromAvailability(
    input: BrowserBottomPanelActionAvailabilityInput
  ): BrowserBottomPanelActionEnablementById {
    const surface = input.surface;
    const webSurfaceInput = this.buildWebSurfaceInput(surface);
    const webPageActionEnabled = this.webSurfaceActionEntryViewModel.canShowWebPageAction(webSurfaceInput);
    const webPageActionDisabledMessage = this.webSurfaceActionEntryViewModel.resolveDisabledMessage(webSurfaceInput);
    const webpageTranslationEnabled = this.webpageTranslationEntryViewModel.canShowToolbarEntry({
      activeTabIsWebPage: surface.activeTabIsWebPage,
      webPageVisible: surface.webPageVisible,
      tabsSheetVisible: surface.tabsSheetVisible,
      targetUrls: surface.targetUrls
    });
    const bookmarkActionEnabled = this.resolveBookmarkActionAvailability(surface);
    const webPageAction: BrowserBottomPanelActionEnablement = {
      enabled: webPageActionEnabled,
      disabledMessage: webPageActionDisabledMessage
    };
    const translationAction: BrowserBottomPanelActionEnablement = {
      enabled: webpageTranslationEnabled,
      disabledMessage: webpageTranslationEnabled ? '' : webPageActionDisabledMessage
    };
    const bookmarkAction: BrowserBottomPanelActionEnablement = {
      enabled: bookmarkActionEnabled,
      disabledMessage: input.bookmarkActionState.disabledMessage
    };
    const alwaysEnabled: BrowserBottomPanelActionEnablement = {
      enabled: true,
      disabledMessage: ''
    };
    const findAction: BrowserBottomPanelActionEnablement = {
      enabled: input.pageFindEnabled,
      disabledMessage: input.pageFindEnabled ? '' : '当前页面暂不可查找'
    };
    const manualElementHideAction: BrowserBottomPanelActionEnablement = {
      enabled: input.manualElementHideEnabled,
      disabledMessage: input.manualElementHideEnabled ? '' : '当前页面无法标记广告'
    };
    const result: BrowserBottomPanelActionEnablementById = {};
    result.bookmark = bookmarkAction;
    result.scanQr = alwaysEnabled;
    result.openBookmarks = alwaysEnabled;
    result.scripts = alwaysEnabled;
    result.find = findAction;
    result.settings = alwaysEnabled;
    result.appProxySettings = alwaysEnabled;
    result.home = alwaysEnabled;
    result.share = alwaysEnabled;
    result.sendToDesktop = alwaysEnabled;
    result.print = alwaysEnabled;
    result.copyLink = alwaysEnabled;
    result.addToDesktop = alwaysEnabled;
    result.userAgent = alwaysEnabled;
    result.textZoom = alwaysEnabled;
    result.userAgentPreset = alwaysEnabled;
    result.screenOrientation = alwaysEnabled;
    result.themeMode = alwaysEnabled;
    result.fullScreenMode = alwaysEnabled;
    result.manualElementHide = manualElementHideAction;
    result.elementInspection = {
      enabled: input.elementInspectionEnabled,
      disabledMessage: input.elementInspectionEnabled ? '' : '当前页面暂不可审查元素'
    };
    result.translate = translationAction;
    result.reader = webPageAction;
    result.video = alwaysEnabled;
    result.offline = webPageAction;
    result.savedPages = alwaysEnabled;
    result.downloads = alwaysEnabled;
    result.history = alwaysEnabled;
    result.siteInfo = alwaysEnabled;
    result.reportSite = alwaysEnabled;
    result.newPrivateTab = alwaysEnabled;
    return result;
  }

  private buildWebSurfaceInput(surface: BrowserBottomPanelActionSurfaceInput): BrowserWebSurfaceActionEntryInput {
    return {
      activeTabIsWebPage: surface.activeTabIsWebPage,
      webPageVisible: surface.webPageVisible,
      tabsSheetVisible: surface.tabsSheetVisible,
      targetUrls: surface.targetUrls
    };
  }

  resolvePrimaryActions(
    state: BrowserBottomPanelActionPresentationInput,
    input: BrowserBottomAddressPanelBuildInput,
    responsiveState: BrowserBottomPanelResponsiveState
  ): BrowserBottomAddressPanelAction[] | undefined {
    if (state.currentDocumentViewerPage && state.effectiveWebMode) {
      return this.buildDocumentViewerPrimaryActions();
    }
    return this.buildPrimaryActionsByLayout(state, input, responsiveState);
  }

  resolveSecondaryActions(
    state: BrowserBottomPanelActionPresentationInput,
    input: BrowserBottomAddressPanelBuildInput,
    primaryActions: BrowserBottomAddressPanelAction[] | undefined,
    responsiveState: BrowserBottomPanelResponsiveState
  ): BrowserBottomAddressPanelAction[] | undefined {
    if (state.currentDocumentViewerPage && state.effectiveWebMode) {
      return [];
    }
    return this.buildSecondaryActionsByLayout(
      state,
      input,
      primaryActions ?? this.buildPrimaryActionsByLayout(state, input, responsiveState)
    );
  }

  buildPrimaryActionsByLayout(
    state: BrowserBottomPanelActionPresentationInput,
    input: BrowserBottomAddressPanelBuildInput,
    responsiveState: BrowserBottomPanelResponsiveState
  ): BrowserBottomAddressPanelAction[] {
    let actions = this.viewModel.buildActionsByLayout(
      input,
      this.buildToolbarLayoutInput(),
      responsiveState.quickActionLimit
    );
    if (state.effectiveHomeMode) {
      actions = this.ensureHomeBookshelfAction(actions, input);
    }
    return this.enrichWebActions(state, actions);
  }

  resolveQuickActions(
    state: BrowserBottomPanelActionPresentationInput,
    input: BrowserBottomAddressPanelBuildInput,
    _responsiveState: BrowserBottomPanelResponsiveState
  ): BrowserBottomAddressPanelAction[] | undefined {
    if (state.currentDocumentViewerPage && state.effectiveWebMode) {
      return this.buildDocumentViewerPrimaryActions();
    }
    return this.enrichWebActions(state, this.viewModel.buildQuickActionsByLayout(
      input,
      this.buildToolbarLayoutInput()
    ));
  }

  private ensureHomeBookshelfAction(
    actions: BrowserBottomAddressPanelAction[],
    input: BrowserBottomAddressPanelBuildInput
  ): BrowserBottomAddressPanelAction[] {
    if (actions.some((action: BrowserBottomAddressPanelAction): boolean => action.id === 'novel')) {
      return actions;
    }
    const bookshelfAction = this.viewModel.buildSecondaryActions(input, [])
      .find((action: BrowserBottomAddressPanelAction): boolean => action.id === 'novel');
    if (bookshelfAction === undefined) {
      return actions;
    }
    if (actions.length === 0) {
      return [bookshelfAction];
    }
    const homeIndex: number = actions.findIndex((action: BrowserBottomAddressPanelAction): boolean =>
      action.id === 'home');
    const replacementIndex: number = homeIndex >= 0 ? homeIndex : actions.length - 1;
    return actions.map((action: BrowserBottomAddressPanelAction, index: number): BrowserBottomAddressPanelAction =>
      index === replacementIndex ? bookshelfAction : action);
  }

  buildSecondaryActionsByLayout(
    state: BrowserBottomPanelActionPresentationInput,
    input: BrowserBottomAddressPanelBuildInput,
    primaryActions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    const actions = this.viewModel.buildSecondaryActionsByLayout(
      input,
      this.buildToolbarLayoutInput(),
      primaryActions
    );
    return this.enrichWebActions(state, actions);
  }

  enrichWebActions(
    state: BrowserBottomPanelActionPresentationInput,
    actions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    return this.enrichWebActionsInternal(state, actions);
  }

  resolveLeadingHeaderActions(state: BrowserBottomPanelActionPresentationInput): BrowserBottomAddressPanelHeaderAction[] {
    if (state.currentDocumentViewerPage && state.effectiveWebMode) {
      return [];
    }
    if (state.effectiveHomeMode) {
      return [
        this.buildHeaderAction('webBack', '返回', $r('sys.symbol.chevron_left'), false, '',
          'reliableTrigger', 'browser.toolbar.back'),
        this.buildHeaderAction('webForward', '前进', $r('sys.symbol.chevron_right'), false, '',
          'reliableTrigger', 'browser.toolbar.forward')
      ];
    }
    return [
      this.buildHeaderAction('webBack', '返回', $r('sys.symbol.chevron_left'), state.canGoBack, '',
        'reliableTrigger', 'browser.toolbar.back'),
      this.buildHeaderAction('webForward', '前进', $r('sys.symbol.chevron_right'), state.canGoForward, '',
        'reliableTrigger', 'browser.toolbar.forward')
    ];
  }

  resolveTrailingHeaderActions(state: BrowserBottomPanelActionPresentationInput): BrowserBottomAddressPanelHeaderAction[] {
    if (state.currentDocumentViewerPage && state.effectiveWebMode) {
      return [];
    }
    if (state.effectiveHomeMode) {
      return [
        this.buildHeaderAction('webReload', '刷新', $r('sys.symbol.arrow_clockwise'), true, '',
          'enabledState', 'browser.toolbar.refresh'),
        this.buildHeaderAction('openTabs', '标签页', $r('sys.symbol.rectangle_on_rectangle_fill'), true, '',
          'enabledState', 'browser.toolbar.tabs')
      ];
    }
    return [
      this.buildHeaderAction('webReload', '刷新', $r('sys.symbol.arrow_clockwise'), true, '',
        'enabledState', 'browser.toolbar.refresh'),
      this.buildHeaderAction('openTabs', '标签页', $r('sys.symbol.rectangle_on_rectangle_fill'), true, '',
      'enabledState', 'browser.toolbar.tabs')
    ];
  }

  buildToolbarLayoutInput(): BrowserBottomToolbarLayoutInput {
    const toolbarLayout = sharedPreferencesRepository.getPreferences().toolbarLayout;
    const input: BrowserBottomToolbarLayoutInput = {
      primaryActionIds: toolbarLayout.primaryActionIds.map((actionId: string) => actionId as BrowserBottomAddressPanelActionId),
      secondaryActionIds: toolbarLayout.secondaryActionIds.map((actionId: string) => actionId as BrowserBottomAddressPanelActionId)
    };
    return input;
  }

  private buildAddressPanelActionInput(
    input: BrowserBottomPanelActionSnapshotInput
  ): BrowserBottomAddressPanelBuildInput {
    const actionEnablement = this.buildActionEnablement(input);
    const result: BrowserBottomAddressPanelBuildInput = {
      chromeIconTone: input.presentation.chromeIconTone,
      privateModeActive: input.privateTabModeActive,
      actionEnablement,
      pageFindEnabled: actionEnablement.find?.enabled === true,
      readerModeEnabled: actionEnablement.reader?.enabled === true,
      webpageTranslationEnabled: actionEnablement.translate?.enabled === true,
      offlinePageSaveEnabled: actionEnablement.offline?.enabled === true,
      offlinePageSaveDisabledMessage: actionEnablement.offline?.disabledMessage ?? '',
      bookmarksEnabled: actionEnablement.bookmark?.enabled === true,
      bookmarksActionLabel: input.bookmarkActionState.label,
      bookmarksActionIcon: input.bookmarkActionState.icon,
      bookmarksActionDisabledMessage: actionEnablement.bookmark?.disabledMessage ??
        input.bookmarkActionState.disabledMessage,
      bookmarksActionSelected: actionEnablement.bookmark?.enabled === true && input.bookmarkActionState.hasBookmark,
      bookmarksActionVersion: input.bookmarkActionVersion,
      appProxyActive: input.appProxyActive,
      userAgentActionLabel: '网站版本',
      userAgentActionTrailingText: this.desktopSiteModeViewModel.resolveToolbarLabel(input.desktopSiteMode),
      userAgentActionIcon: this.resolveUserAgentActionIcon(input.desktopSiteMode),
      userAgentActionVersion: input.userAgentActionVersion,
      textZoomActionLabel: '网页文字大小',
      textZoomActionTrailingText: this.textZoomViewModel.buildState(input.textZoomRatio).percentLabel,
      textZoomActionIcon: $r('sys.symbol.doc_text_fill'),
      textZoomActionVersion: input.textZoomActionVersion,
      userAgentPresetActionLabel: '网页标识',
      userAgentPresetActionTrailingText: this.userAgentService.resolveSettingsSummary(input.userAgentPresetSettings),
      userAgentPresetActionIcon: this.resolveUserAgentPresetActionIcon(input.userAgentPresetSettings),
      userAgentPresetActionVersion: input.userAgentPresetActionVersion,
      screenOrientationActionLabel: '屏幕方向',
      screenOrientationActionTrailingText: this.screenOrientationViewModel.resolveLabel(input.screenOrientationMode),
      screenOrientationActionIcon: this.screenOrientationViewModel.resolveIcon(input.screenOrientationMode),
      screenOrientationActionVersion: input.screenOrientationActionVersion,
      themeModeActionLabel: '网页外观',
      themeModeActionTrailingText: this.resolveThemeModeActionTrailingText(input.themeMode, input.resolvedThemeMode),
      themeModeActionIcon: input.themeMode === 'system' ?
        this.resolveSystemThemeModeActionIcon(input.resolvedThemeMode) : input.themeModeIcon,
      themeModeActionVersion: input.themeModeActionVersion,
      fullScreenModeActionLabel: input.fullScreenModeEnabled ? '退出全屏模式' : '全屏模式',
      fullScreenModeActionTrailingText: input.fullScreenModeEnabled ? '已开启' : '沉浸浏览',
      fullScreenModeActionIcon: input.fullScreenModeEnabled ?
        $r('sys.symbol.exit_full_screen') :
        $r('sys.symbol.fullscreen'),
      fullScreenModeActionVersion: input.fullScreenModeActionVersion
    };
    return result;
  }

  buildAddressPanelActionRenderKey(
    input: BrowserBottomAddressPanelBuildInput,
    state: BrowserBottomPanelActionPresentationInput
  ): string {
    return [
      state.effectiveHomeMode ? 'home' : 'not-home',
      state.effectiveWebMode ? 'web' : 'not-web',
      state.currentDocumentViewerPage ? 'viewer' : 'normal',
      state.privateModeActive ? 'private' : 'regular',
      `enablement=${this.buildActionEnablementRenderKey(input.actionEnablement)}`,
      input.pageFindEnabled ? 'find=1' : 'find=0',
      input.readerModeEnabled ? 'reader=1' : 'reader=0',
      input.webpageTranslationEnabled ? 'translate=1' : 'translate=0',
      input.offlinePageSaveEnabled ? 'offline=1' : 'offline=0',
      `offlineMessage=${input.offlinePageSaveDisabledMessage}`,
      input.bookmarksEnabled ? 'bookmark=1' : 'bookmark=0',
      input.bookmarksActionSelected === true ? 'bookmarkSelected=1' : 'bookmarkSelected=0',
      `bookmarkLabel=${input.bookmarksActionLabel}`,
      `bookmarkMessage=${input.bookmarksActionDisabledMessage}`,
      `bookmarkVersion=${input.bookmarksActionVersion ?? 0}`,
      input.appProxyActive === true ? 'proxy=1' : 'proxy=0',
      `ua=${input.userAgentActionLabel}:${input.userAgentActionTrailingText}:${input.userAgentActionVersion ?? 0}`,
      `textZoom=${input.textZoomActionTrailingText}:${input.textZoomActionVersion ?? 0}`,
      `uaPreset=${input.userAgentPresetActionTrailingText}:${input.userAgentPresetActionVersion ?? 0}`,
      `orientation=${input.screenOrientationActionTrailingText}:${input.screenOrientationActionVersion ?? 0}`,
      `theme=${input.themeModeActionTrailingText}:${input.themeModeActionVersion ?? 0}`,
      `fullScreen=${input.fullScreenModeActionLabel}:${input.fullScreenModeActionVersion ?? 0}`
    ].join('|');
  }

  private buildActionEnablementRenderKey(enablementById: BrowserBottomPanelActionEnablementById): string {
    return Object.keys(enablementById).sort().map((actionId: string) => {
      const state = enablementById[actionId];
      if (state === undefined) {
        return `${actionId}=missing`;
      }
      return `${actionId}=${state.enabled ? '1' : '0'}:${state.disabledMessage}`;
    }).join(',');
  }

  private buildDocumentViewerPrimaryActions(): BrowserBottomAddressPanelAction[] {
    return [
      {
        id: 'home',
        title: '主页',
        trailingText: '新标签',
        icon: $r('sys.symbol.house_fill'),
        airaIconId: 'browser.shortcut.home',
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'viewerInfo',
        title: '文件信息',
        trailingText: '只读查看',
        icon: $r('sys.symbol.info_circle'),
        airaIconId: 'browser.toolbar.siteInfo',
        enabled: true,
        disabledMessage: ''
      }
    ];
  }

  resolveThemeModeActionTitleForMode(mode: BrowserThemeMode): string {
    if (mode === 'light') {
      return '浅色模式';
    }
    if (mode === 'dark') {
      return '深色模式';
    }
    return '跟随系统外观';
  }

  private resolveUserAgentActionIcon(mode: BrowserDesktopSiteMode): Resource {
    return mode === 'desktop'
      ? $r('sys.symbol.phone_fill')
      : $r('sys.symbol.rectangle_on_rectangle_fill');
  }

  private resolveUserAgentPresetActionIcon(settings: BrowserUserAgentSettings): Resource {
    if (settings.defaultMode === 'desktop') {
      return $r('sys.symbol.rectangle_on_rectangle_fill');
    }
    if (settings.defaultMode === 'custom') {
      return $r('sys.symbol.doc_text_fill');
    }
    if (settings.selectedPresetId === 'arkweb_original') {
      return $r('sys.symbol.shield_checkered');
    }
    return $r('sys.symbol.compass_circle_fill');
  }

  private resolveThemeModeActionTrailingText(
    mode: BrowserThemeMode,
    resolvedThemeMode: BrowserResolvedThemeMode
  ): string {
    if (mode === 'system') {
      return resolvedThemeMode === 'dark' ? '深色模式' : '浅色模式';
    }
    return this.resolveThemeModeActionTitleForMode(mode);
  }

  private resolveSystemThemeModeActionIcon(resolvedThemeMode: BrowserResolvedThemeMode): Resource {
    return resolvedThemeMode === 'dark' ? $r('sys.symbol.moon_fill') : $r('sys.symbol.sun_max_fill');
  }

  private enrichWebActionsInternal(
    state: BrowserBottomPanelActionPresentationInput,
    actions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    return actions.map((action: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelAction => {
      if (action.id === 'newPrivateTab') {
        const privateModeActive = state.privateModeActive;
        return {
          id: action.id,
          title: privateModeActive ? '退出隐私模式' : '隐私模式',
          trailingText: privateModeActive ? '退出' : '私密',
          icon: action.icon,
          airaIconId: 'browser.toolbar.privacyMode',
          enabled: action.enabled,
          disabledMessage: action.disabledMessage,
          selected: privateModeActive,
          renderVersion: privateModeActive ? 1 : 0
        };
      }
      if (action.id !== 'manualElementHide') {
        return {
          id: action.id,
          title: action.title,
          trailingText: action.trailingText,
          icon: action.icon,
          imageIcon: action.imageIcon,
          airaIconId: action.airaIconId,
          enabled: action.enabled,
          disabledMessage: action.disabledMessage,
          selected: action.selected === true,
          renderVersion: action.renderVersion
        };
      }
      const ruleCount = state.manualElementHideRuleCount;
      return {
        id: action.id,
        title: '标记广告',
        trailingText: ruleCount > 0 ? `${ruleCount} 条` : '手动隐藏',
        icon: action.icon,
        imageIcon: action.imageIcon,
        airaIconId: action.airaIconId,
        enabled: state.manualElementHideEnabled,
        disabledMessage: '当前页面无法标记广告',
        selected: false,
        renderVersion: ruleCount
      };
    });
  }

  private resolveSiteSecurityTitle(currentUrl: string, addressInput: string): string {
    if (this.isSecureCurrentSite(currentUrl, addressInput)) {
      return '访问安全';
    }
    return '连接未验证';
  }

  private resolveSiteSecurityIcon(currentUrl: string, addressInput: string): Resource {
    if (this.isSecureCurrentSite(currentUrl, addressInput)) {
      return $r('sys.symbol.checkmark_shield_fill');
    }
    return $r('sys.symbol.exclamationmark_shield_fill');
  }

  private isSecureCurrentSite(currentUrl: string, addressInput: string): boolean {
    return isSecureCurrentSiteUrl(currentUrl, addressInput);
  }

  private buildHeaderAction(
    id: string,
    title: string,
    icon: Resource,
    enabled: boolean,
    disabledMessage: string,
    triggerPolicy: 'enabledState' | 'reliableTrigger',
    airaIconId: AiraRenderableIconId
  ): BrowserBottomAddressPanelHeaderAction {
    return {
      id,
      title,
      icon,
      airaIconId,
      enabled,
      disabledMessage,
      triggerPolicy
    };
  }

  private buildSnapshotKey(input: BrowserBottomPanelActionSnapshotInput): string {
    return [
      input.contentMode,
      input.addressFocused ? 'focused' : 'blurred',
      input.effectiveHomeMode ? 'home' : 'not-home',
      input.effectiveWebMode ? 'web' : 'not-web',
      input.surface.activeTabIsWebPage ? 'active-web=1' : 'active-web=0',
      input.surface.webPageVisible ? 'web-visible=1' : 'web-visible=0',
      input.surface.tabsSheetVisible ? 'tabs=1' : 'tabs=0',
      `targets=${JSON.stringify(input.surface.targetUrls)}`,
      input.pageFindEnabled ? 'find=1' : 'find=0',
      input.appProxyActive ? 'proxy=1' : 'proxy=0',
      input.presentation.chromeIconTone,
      input.presentation.currentDocumentViewerPage ? 'viewer=1' : 'viewer=0',
      input.presentation.canGoForward ? 'forward=1' : 'forward=0',
      input.presentation.privateModeActive ? 'private=1' : 'private=0',
      input.privateTabModeActive ? 'private-tab=1' : 'private-tab=0',
      input.presentation.manualElementHideEnabled ? 'manual=1' : 'manual=0',
      `manualCount=${input.presentation.manualElementHideRuleCount}`,
      input.presentation.elementInspectionEnabled ? 'inspect=1' : 'inspect=0',
      `bookmark=${input.bookmarkActionState.hasBookmark ? '1' : '0'}:${input.bookmarkActionState.label}`,
      `bookmarkMessage=${input.bookmarkActionState.disabledMessage}`,
      `bookmarkVersion=${input.bookmarkActionVersion}`,
      `desktop=${input.desktopSiteMode}:${input.userAgentActionVersion}`,
      `textZoom=${input.textZoomRatio}:${input.textZoomActionVersion}`,
      `uaPreset=${input.userAgentPresetActionVersion}`,
      `orientation=${input.screenOrientationMode}:${input.screenOrientationActionVersion}`,
      `theme=${input.themeMode}:${input.resolvedThemeMode}:${input.themeModeActionVersion}`,
      `fullScreen=${input.fullScreenModeEnabled ? '1' : '0'}:${input.fullScreenModeActionVersion}`,
      `toolbar=${input.toolbarLayoutVersion}`,
      `responsive=${input.responsiveLayoutKey}`
    ].join('|');
  }

  private shouldResolveActionOverrides(contentMode: 'home' | 'web', addressFocused: boolean): boolean {
    return !addressFocused && (contentMode === 'home' || contentMode === 'web');
  }
}
