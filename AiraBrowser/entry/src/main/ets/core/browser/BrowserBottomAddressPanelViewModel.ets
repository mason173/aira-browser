import { AppChromeIconTone } from '../resources/AppIconResources';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import {
  BrowserBottomPanelActionCatalog,
  BrowserBottomPanelActionId
} from './BrowserBottomPanelActionCatalog';
import {
  BrowserBottomPanelActionEnablement,
  BrowserBottomPanelActionEnablementById,
  resolveBrowserBottomPanelActionEnablement
} from './BrowserBottomPanelActionEnablement';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';
import { BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS } from './BrowserBottomPanelMotionTokens';
import {
  bottomPanelExit,
  bottomPanelExitFullScreen,
  bottomPanelExitPrivate,
  bottomPanelFindUnavailable,
  sameResourceStr
} from './BrowserBottomPanelText';

export type BrowserBottomAddressPanelActionId = BrowserBottomPanelActionId;

export interface BrowserBottomPanelMotionState {
  targetDetent: HomeSearchPanelDetent;
  immediateLowDetentRequestVersion: number;
  bottomInset: number;
  panelHeight: number;
  middlePanelHeight: number;
  overlayHostHeight: number;
  keyboardOverlayInset: number;
  floatingBottomLiftVp: number;
  visible: boolean;
  detentDragEnabled: boolean;
  panelExpansionEnabled: boolean;
  suppressExpandedContentFromDrag: boolean;
  peekEnabled: boolean;
  peekGestureEnabled: boolean;
  peekToLowAnimationDurationMs: number;
  collapseToPeekAnimationDurationMs: number;
}

export const DEFAULT_BROWSER_BOTTOM_PANEL_MOTION_STATE: BrowserBottomPanelMotionState = {
  targetDetent: 'low',
  immediateLowDetentRequestVersion: 0,
  bottomInset: 0,
  panelHeight: 0,
  middlePanelHeight: 0,
  overlayHostHeight: 0,
  keyboardOverlayInset: 0,
  floatingBottomLiftVp: 0,
  visible: true,
  detentDragEnabled: true,
  panelExpansionEnabled: true,
  suppressExpandedContentFromDrag: false,
  peekEnabled: false,
  peekGestureEnabled: false,
  peekToLowAnimationDurationMs: BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS,
  collapseToPeekAnimationDurationMs: BROWSER_BOTTOM_PANEL_MOTION_DURATION_MS
};

export interface BrowserBottomAddressPanelAction {
  id: BrowserBottomAddressPanelActionId;
  title: ResourceStr;
  trailingText?: ResourceStr;
  icon: Resource;
  imageIcon?: Resource;
  airaIconId?: AiraRenderableIconId;
  enabled: boolean;
  disabledMessage: ResourceStr;
  selected?: boolean;
  renderVersion?: number;
}

export interface BrowserBottomAddressPanelHeaderAction {
  id: string;
  title: ResourceStr;
  icon: Resource;
  imageIcon?: Resource;
  airaIconId?: AiraRenderableIconId;
  enabled: boolean;
  disabledMessage: ResourceStr;
  triggerPolicy: BrowserBottomAddressPanelHeaderActionTriggerPolicy;
  renderVersion?: number;
}

export type BrowserBottomAddressPanelHeaderActionTriggerPolicy = 'enabledState' | 'reliableTrigger';

export interface BrowserBottomAddressPanelBuildInput {
  chromeIconTone?: AppChromeIconTone;
  privateModeActive?: boolean;
  actionEnablement: BrowserBottomPanelActionEnablementById;
  pageFindEnabled: boolean;
  readerModeEnabled: boolean;
  webpageTranslationEnabled: boolean;
  offlinePageSaveEnabled: boolean;
  offlinePageSaveDisabledMessage: ResourceStr;
  bookmarksEnabled: boolean;
  bookmarksActionLabel: ResourceStr;
  bookmarksActionIcon: Resource;
  bookmarksActionDisabledMessage: ResourceStr;
  bookmarksActionSelected?: boolean;
  bookmarksActionVersion?: number;
  userAgentActionLabel: ResourceStr;
  userAgentActionTrailingText: ResourceStr;
  userAgentActionIcon: Resource;
  userAgentActionVersion?: number;
  textZoomActionLabel: ResourceStr;
  textZoomActionTrailingText: ResourceStr;
  textZoomActionIcon: Resource;
  textZoomActionVersion?: number;
  webZoomActionLabel: ResourceStr;
  webZoomActionTrailingText: ResourceStr;
  webZoomActionIcon: Resource;
  webZoomActionVersion?: number;
  userAgentPresetActionLabel: ResourceStr;
  userAgentPresetActionTrailingText: ResourceStr;
  userAgentPresetActionIcon: Resource;
  userAgentPresetActionVersion?: number;
  screenOrientationActionLabel: ResourceStr;
  screenOrientationActionTrailingText: ResourceStr;
  screenOrientationActionIcon: Resource;
  screenOrientationActionVersion?: number;
  themeModeActionLabel: ResourceStr;
  themeModeActionTrailingText: ResourceStr;
  themeModeActionIcon: Resource;
  themeModeActionVersion?: number;
  fullScreenModeActionLabel: ResourceStr;
  fullScreenModeActionTrailingText: ResourceStr;
  fullScreenModeActionIcon: Resource;
  fullScreenModeActionVersion?: number;
  fullScreenModeEnabled?: boolean;
  appProxyActive?: boolean;
}

export interface BrowserBottomToolbarLayoutInput {
  primaryActionIds: BrowserBottomAddressPanelActionId[];
  secondaryActionIds: BrowserBottomAddressPanelActionId[];
}

export function filterBrowserBottomAddressPanelActionsHiddenByVisiblePrimary(
  actions: BrowserBottomAddressPanelAction[],
  visiblePrimaryActions: BrowserBottomAddressPanelAction[]
): BrowserBottomAddressPanelAction[] {
  if (visiblePrimaryActions.length <= 0) {
    return actions;
  }
  return actions.filter((action: BrowserBottomAddressPanelAction) => {
    return !visiblePrimaryActions.some((primaryAction: BrowserBottomAddressPanelAction) => {
      return primaryAction.id === action.id;
    });
  });
}

export function resolveBrowserBottomAddressPanelActionAiraIconId(
  actionId: BrowserBottomAddressPanelActionId
): AiraRenderableIconId {
  return BrowserBottomPanelActionCatalog.iconId(actionId);
}

function resolveBrowserBottomAddressPanelActionTitle(actionId: BrowserBottomAddressPanelActionId): ResourceStr {
  return BrowserBottomPanelActionCatalog.title(actionId);
}

function resolveBrowserBottomAddressPanelActionTrailingText(actionId: BrowserBottomAddressPanelActionId): ResourceStr {
  return BrowserBottomPanelActionCatalog.subtitle(actionId);
}

function resolveBookmarkActionTrailingText(bookmarkActionLabel: ResourceStr): ResourceStr {
  return sameResourceStr(bookmarkActionLabel, resolveBrowserBottomAddressPanelActionTitle('bookmark'))
    ? resolveBrowserBottomAddressPanelActionTrailingText('bookmark')
    : '';
}

export class BrowserBottomAddressPanelViewModel {
  buildPrimaryActions(input: BrowserBottomAddressPanelBuildInput, visibleLimit: number = 4): BrowserBottomAddressPanelAction[] {
    const leadingActions: BrowserBottomAddressPanelAction[] = [
      {
        id: 'scanQr',
        title: resolveBrowserBottomAddressPanelActionTitle('scanQr'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('scanQr'),
        icon: $r('sys.symbol.qrcode'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('scanQr'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'scripts',
        title: resolveBrowserBottomAddressPanelActionTitle('scripts'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('scripts'),
        icon: $r('sys.symbol.puzzle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('scripts'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'video',
        title: resolveBrowserBottomAddressPanelActionTitle('video'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('video'),
        icon: $r('sys.symbol.doc_text_magnifyingglass_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('video'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'downloads',
        title: resolveBrowserBottomAddressPanelActionTitle('downloads'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('downloads'),
        icon: $r('sys.symbol.download_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('downloads'),
        enabled: true,
        disabledMessage: ''
      }
    ];
    const pinnedTrailingActions: BrowserBottomAddressPanelAction[] = [
      {
        id: 'history',
        title: resolveBrowserBottomAddressPanelActionTitle('history'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('history'),
        icon: $r('sys.symbol.clock_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('history'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'openBookmarks',
        title: resolveBrowserBottomAddressPanelActionTitle('openBookmarks'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('openBookmarks'),
        icon: $r('sys.symbol.bookmark_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('openBookmarks'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'appProxySettings',
        title: resolveBrowserBottomAddressPanelActionTitle('appProxySettings'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('appProxySettings'),
        icon: $r('sys.symbol.compass_circle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('appProxySettings'),
        enabled: true,
        disabledMessage: '',
        selected: input.appProxyActive === true
      },
      {
        id: 'home',
        title: resolveBrowserBottomAddressPanelActionTitle('home'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('home'),
        icon: $r('sys.symbol.house_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('home'),
        enabled: true,
        disabledMessage: ''
      }
    ];
    return this.applyActionEnablement(input, this.selectPrimaryActionsForLimit(
      leadingActions,
      pinnedTrailingActions,
      visibleLimit
    ));
  }

  private selectPrimaryActionsForLimit(
    leadingActions: BrowserBottomAddressPanelAction[],
    pinnedTrailingActions: BrowserBottomAddressPanelAction[],
    visibleLimit: number
  ): BrowserBottomAddressPanelAction[] {
    const limit = Math.max(1, Math.floor(visibleLimit));
    if (limit <= pinnedTrailingActions.length) {
      return pinnedTrailingActions.slice(0, limit);
    }
    const leadingLimit = Math.min(leadingActions.length, limit - pinnedTrailingActions.length);
    return pinnedTrailingActions.concat(leadingActions.slice(0, leadingLimit));
  }

  buildSecondaryActions(
    input: BrowserBottomAddressPanelBuildInput,
    visiblePrimaryActions: BrowserBottomAddressPanelAction[] = []
  ): BrowserBottomAddressPanelAction[] {
    const privateModeActive = input.privateModeActive === true;
    const actions: BrowserBottomAddressPanelAction[] = [
      {
        id: 'bookmark',
        title: input.bookmarksActionLabel,
        trailingText: resolveBookmarkActionTrailingText(input.bookmarksActionLabel),
        icon: input.bookmarksActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('bookmark'),
        enabled: true,
        disabledMessage: '',
        selected: input.bookmarksActionSelected === true,
        renderVersion: input.bookmarksActionVersion
      },
      {
        id: 'scanQr',
        title: resolveBrowserBottomAddressPanelActionTitle('scanQr'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('scanQr'),
        icon: $r('sys.symbol.qrcode'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('scanQr'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'newPrivateTab',
        title: privateModeActive ? bottomPanelExitPrivate() : resolveBrowserBottomAddressPanelActionTitle('newPrivateTab'),
        trailingText: privateModeActive ? bottomPanelExit() : resolveBrowserBottomAddressPanelActionTrailingText('newPrivateTab'),
        icon: $r('sys.symbol.lock_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('newPrivateTab'),
        enabled: true,
        disabledMessage: '',
        selected: privateModeActive,
        renderVersion: privateModeActive ? 1 : 0
      },
      {
        id: 'share',
        title: resolveBrowserBottomAddressPanelActionTitle('share'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('share'),
        icon: $r('sys.symbol.arrow_up'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('share'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'sendToDesktop',
        title: resolveBrowserBottomAddressPanelActionTitle('sendToDesktop'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('sendToDesktop'),
        icon: $r('sys.symbol.rectangle_on_rectangle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('sendToDesktop'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'print',
        title: resolveBrowserBottomAddressPanelActionTitle('print'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('print'),
        icon: $r('sys.symbol.doc_text_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('print'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'userAgent',
        title: resolveBrowserBottomAddressPanelActionTitle('userAgent'),
        trailingText: input.userAgentActionTrailingText,
        icon: input.userAgentActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('userAgent'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.userAgentActionVersion
      },
      {
        id: 'textZoom',
        title: resolveBrowserBottomAddressPanelActionTitle('textZoom'),
        trailingText: input.textZoomActionTrailingText,
        icon: input.textZoomActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('textZoom'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.textZoomActionVersion
      },
      {
        id: 'webZoom',
        title: resolveBrowserBottomAddressPanelActionTitle('webZoom'),
        trailingText: input.webZoomActionTrailingText,
        icon: input.webZoomActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('webZoom'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.webZoomActionVersion
      },
      {
        id: 'find',
        title: resolveBrowserBottomAddressPanelActionTitle('find'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('find'),
        icon: $r('sys.symbol.magnifyingglass'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('find'),
        enabled: input.pageFindEnabled,
        disabledMessage: input.pageFindEnabled ? '' : bottomPanelFindUnavailable()
      },
      {
        id: 'fullScreenMode',
        title: resolveBrowserBottomAddressPanelActionTitle('fullScreenMode'),
        trailingText: input.fullScreenModeEnabled === true
          ? bottomPanelExitFullScreen()
          : input.fullScreenModeActionTrailingText,
        icon: input.fullScreenModeActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('fullScreenMode'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.fullScreenModeActionVersion
      },
      {
        id: 'manualElementHide',
        title: resolveBrowserBottomAddressPanelActionTitle('manualElementHide'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('manualElementHide'),
        icon: $r('sys.symbol.wand_and_stars_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('manualElementHide'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'elementInspection',
        title: resolveBrowserBottomAddressPanelActionTitle('elementInspection'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('elementInspection'),
        icon: $r('sys.symbol.doc_text_magnifyingglass_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('elementInspection'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'reader',
        title: resolveBrowserBottomAddressPanelActionTitle('reader'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('reader'),
        icon: $r('sys.symbol.doc_text_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('reader'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'novel',
        title: resolveBrowserBottomAddressPanelActionTitle('novel'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('novel'),
        icon: $r('sys.symbol.doc_text_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('novel'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'translate',
        title: resolveBrowserBottomAddressPanelActionTitle('translate'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('translate'),
        icon: $r('sys.symbol.translate_square_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('translate'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'scripts',
        title: resolveBrowserBottomAddressPanelActionTitle('scripts'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('scripts'),
        icon: $r('sys.symbol.puzzle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('scripts'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'themeMode',
        title: resolveBrowserBottomAddressPanelActionTitle('themeMode'),
        trailingText: input.themeModeActionTrailingText,
        icon: input.themeModeActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('themeMode'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.themeModeActionVersion
      },
      {
        id: 'userAgentPreset',
        title: resolveBrowserBottomAddressPanelActionTitle('userAgentPreset'),
        trailingText: input.userAgentPresetActionTrailingText,
        icon: input.userAgentPresetActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('userAgentPreset'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.userAgentPresetActionVersion
      },
      {
        id: 'screenOrientation',
        title: resolveBrowserBottomAddressPanelActionTitle('screenOrientation'),
        trailingText: input.screenOrientationActionTrailingText,
        icon: input.screenOrientationActionIcon,
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('screenOrientation'),
        enabled: true,
        disabledMessage: '',
        renderVersion: input.screenOrientationActionVersion
      },
      {
        id: 'addToDesktop',
        title: resolveBrowserBottomAddressPanelActionTitle('addToDesktop'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('addToDesktop'),
        icon: $r('sys.symbol.plus'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('addToDesktop'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'offline',
        title: resolveBrowserBottomAddressPanelActionTitle('offline'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('offline'),
        icon: $r('sys.symbol.download_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('offline'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'video',
        title: resolveBrowserBottomAddressPanelActionTitle('video'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('video'),
        icon: $r('sys.symbol.doc_text_magnifyingglass_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('video'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'siteInfo',
        title: resolveBrowserBottomAddressPanelActionTitle('siteInfo'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('siteInfo'),
        icon: $r('sys.symbol.compass_circle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('siteInfo'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'reportSite',
        title: resolveBrowserBottomAddressPanelActionTitle('reportSite'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('reportSite'),
        icon: $r('sys.symbol.exclamationmark_triangle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('reportSite'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'openBookmarks',
        title: resolveBrowserBottomAddressPanelActionTitle('openBookmarks'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('openBookmarks'),
        icon: $r('sys.symbol.bookmark'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('openBookmarks'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'history',
        title: resolveBrowserBottomAddressPanelActionTitle('history'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('history'),
        icon: $r('sys.symbol.clock_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('history'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'savedPages',
        title: resolveBrowserBottomAddressPanelActionTitle('savedPages'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('savedPages'),
        icon: $r('sys.symbol.archivebox_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('savedPages'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'downloads',
        title: resolveBrowserBottomAddressPanelActionTitle('downloads'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('downloads'),
        icon: $r('sys.symbol.download_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('downloads'),
        enabled: true,
        disabledMessage: ''
      },
      {
        id: 'appProxySettings',
        title: resolveBrowserBottomAddressPanelActionTitle('appProxySettings'),
        trailingText: resolveBrowserBottomAddressPanelActionTrailingText('appProxySettings'),
        icon: $r('sys.symbol.compass_circle_fill'),
        airaIconId: resolveBrowserBottomAddressPanelActionAiraIconId('appProxySettings'),
        enabled: true,
        disabledMessage: '',
        selected: input.appProxyActive === true
      }
    ];
    return filterBrowserBottomAddressPanelActionsHiddenByVisiblePrimary(
      this.applyActionEnablement(input, actions),
      visiblePrimaryActions
    );
  }

  buildActionsByLayout(
    input: BrowserBottomAddressPanelBuildInput,
    layout: BrowserBottomToolbarLayoutInput,
    visibleLimit: number = 8
  ): BrowserBottomAddressPanelAction[] {
    const catalog = this.buildActionCatalog(input);
    return this.resolveActionsByIds(catalog, layout.primaryActionIds, Math.max(0, Math.min(8, Math.floor(visibleLimit))));
  }

  buildSecondaryActionsByLayout(
    input: BrowserBottomAddressPanelBuildInput,
    layout: BrowserBottomToolbarLayoutInput,
    visiblePrimaryActions: BrowserBottomAddressPanelAction[] = []
  ): BrowserBottomAddressPanelAction[] {
    const catalog = this.buildActionCatalog(input);
    const secondaryActionIds = layout.primaryActionIds.slice(8).concat(layout.secondaryActionIds);
    const secondaryActions = this.resolveActionsByIds(catalog, secondaryActionIds, catalog.length);
    return filterBrowserBottomAddressPanelActionsHiddenByVisiblePrimary(secondaryActions, visiblePrimaryActions);
  }

  buildQuickActionsByLayout(
    input: BrowserBottomAddressPanelBuildInput,
    layout: BrowserBottomToolbarLayoutInput
  ): BrowserBottomAddressPanelAction[] {
    const catalog = this.buildActionCatalog(input);
    return this.resolveActionsByIds(catalog, layout.primaryActionIds, catalog.length);
  }

  private buildActionCatalog(input: BrowserBottomAddressPanelBuildInput): BrowserBottomAddressPanelAction[] {
    const secondaryActions = this.buildSecondaryActions(input, []);
    const primaryActions = this.buildPrimaryActions(input, 8);
    const catalog: BrowserBottomAddressPanelAction[] = [];
    secondaryActions.concat(primaryActions).forEach((action: BrowserBottomAddressPanelAction) => {
      if (catalog.some((item: BrowserBottomAddressPanelAction) => item.id === action.id)) {
        return;
      }
      catalog.push(action);
    });
    return catalog;
  }

  private resolveActionsByIds(
    catalog: BrowserBottomAddressPanelAction[],
    actionIds: BrowserBottomAddressPanelActionId[],
    limit: number
  ): BrowserBottomAddressPanelAction[] {
    const actions: BrowserBottomAddressPanelAction[] = [];
    actionIds.forEach((actionId: BrowserBottomAddressPanelActionId) => {
      if (actions.length >= limit) {
        return;
      }
      const action = catalog.find((item: BrowserBottomAddressPanelAction) => item.id === actionId);
      if (action !== undefined) {
        actions.push(action);
      }
    });
    return actions;
  }

  private applyActionEnablement(
    input: BrowserBottomAddressPanelBuildInput,
    actions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    return actions.map((action: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelAction => {
      const enablement: BrowserBottomPanelActionEnablement = resolveBrowserBottomPanelActionEnablement(
        input.actionEnablement,
        action.id,
        action.enabled,
        action.disabledMessage
      );
      return {
        id: action.id,
        title: action.title,
        trailingText: action.trailingText,
        icon: action.icon,
        imageIcon: action.imageIcon,
        airaIconId: action.airaIconId,
        enabled: enablement.enabled,
        disabledMessage: enablement.disabledMessage,
        selected: action.selected,
        renderVersion: action.renderVersion
      };
    });
  }
}
