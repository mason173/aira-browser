import {
  BrowserBottomAddressPanelAction,
  BrowserBottomAddressPanelActionId,
  BrowserBottomAddressPanelViewModel
} from './BrowserBottomAddressPanelViewModel';
import { BrowserBottomPanelActionCatalog } from './BrowserBottomPanelActionCatalog';
import { BrowserBottomPanelActionSnapshot } from './BrowserBottomPanelActionPresentationCoordinator';
import { BrowserLargeScreenInputProfile } from './BrowserLargeScreenTabStripViewModel';
import {
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
} from './BrowserDesktopMenuPresentationTokens';
import {
  bottomPanelActionTitle,
  bottomPanelManageScripts,
  bottomPanelPageTools,
  bottomPanelWebZoom,
  bottomPanelZoomUnavailable,
  resourceStrPresent
} from './BrowserBottomPanelText';

export const BROWSER_LARGE_SCREEN_PAGE_TOOLS_TITLE: ResourceStr = bottomPanelPageTools();
export const BROWSER_LARGE_SCREEN_SCRIPT_MANAGEMENT_TITLE: ResourceStr = bottomPanelManageScripts();
export const BROWSER_LARGE_SCREEN_PRIVACY_MODE_TITLE: ResourceStr = bottomPanelActionTitle('newPrivateTab');
export const BROWSER_LARGE_SCREEN_WEB_ZOOM_TITLE: ResourceStr = bottomPanelWebZoom();

export type BrowserLargeScreenToolbarMenuSectionId = 'destinations' | 'page' | 'zoom' | 'preferences';
export type BrowserLargeScreenToolbarMenuPageToolGroupId = 'reading' | 'media' | 'development' | 'more';
export type BrowserLargeScreenToolbarMenuActivation = 'browser_action' | 'web_zoom' | 'user_script_management';

export interface BrowserLargeScreenToolbarMenuEntry {
  action: BrowserBottomAddressPanelAction;
  showsSelection: boolean;
  activation: BrowserLargeScreenToolbarMenuActivation;
}

export interface BrowserLargeScreenToolbarMenuPageToolGroup {
  id: BrowserLargeScreenToolbarMenuPageToolGroupId;
  title: ResourceStr;
  items: BrowserLargeScreenToolbarMenuEntry[];
}

export interface BrowserLargeScreenToolbarMenuSection {
  id: BrowserLargeScreenToolbarMenuSectionId;
  items: BrowserLargeScreenToolbarMenuEntry[];
  pageTools: BrowserLargeScreenToolbarMenuPageToolGroup[];
}

export interface BrowserLargeScreenToolbarMenuPlan {
  sections: BrowserLargeScreenToolbarMenuSection[];
}

export interface BrowserLargeScreenToolbarMenuHeight {
  contentHeightVp: number;
  maxHeightVp: number;
  heightVp: number;
  scrollable: boolean;
}

interface BrowserLargeScreenToolbarMenuPageToolGroupSpec {
  id: BrowserLargeScreenToolbarMenuPageToolGroupId;
  title: ResourceStr;
  actionIds: BrowserBottomAddressPanelActionId[];
}

const DESTINATION_ACTION_IDS: BrowserBottomAddressPanelActionId[] = [
  'history',
  'openBookmarks',
  'downloads',
  'novel'
];
const PAGE_ACTION_IDS: BrowserBottomAddressPanelActionId[] = [
  'copyLink',
  'share',
  'print'
];
const PREFERENCE_ACTION_IDS: BrowserBottomAddressPanelActionId[] = [
  'scanQr',
  'appProxySettings',
  'newPrivateTab',
  'settings'
];
export const BROWSER_LARGE_SCREEN_OVERFLOW_MENU_SECTION_GAP_VP: number = 8;
export const BROWSER_LARGE_SCREEN_OVERFLOW_MENU_GROUP_HEADER_HEIGHT_VP: number = 28;
const OVERFLOW_MENU_BOTTOM_MARGIN_VP: number = 8;
const EMPTY_PAGE_TOOLS: BrowserLargeScreenToolbarMenuPageToolGroup[] = [];
const EMPTY_MENU_PLAN: BrowserLargeScreenToolbarMenuPlan = { sections: [] };

const PAGE_TOOL_GROUP_SPECS: BrowserLargeScreenToolbarMenuPageToolGroupSpec[] = [
  { id: 'reading', title: $r('app.string.bottom_panel_group_reading'), actionIds: ['find', 'reader', 'translate'] },
  { id: 'media', title: $r('app.string.bottom_panel_group_media'), actionIds: ['video', 'offline'] },
  {
    id: 'development',
    title: $r('app.string.bottom_panel_group_development'),
    actionIds: ['scripts', 'elementInspection', 'manualElementHide', 'userAgent']
  },
  { id: 'more', title: '', actionIds: ['addToDesktop', 'themeMode', 'reportSite', 'savedPages'] }
];

/**
 * Pointer shells use a fixed desktop menu. Phone toolbar customization still owns the touch
 * projection, but it must not decide desktop order or which desktop rows exist.
 */
export function projectBrowserLargeScreenPointerToolbarMenu(
  actions: BrowserBottomAddressPanelAction[],
  webZoomAvailable: boolean
): BrowserLargeScreenToolbarMenuPlan {
  const sections: BrowserLargeScreenToolbarMenuSection[] = [];
  const destinations: BrowserLargeScreenToolbarMenuEntry[] =
    projectEntries(actions, DESTINATION_ACTION_IDS, webZoomAvailable);
  if (destinations.length > 0) {
    sections.push({
      id: 'destinations',
      items: destinations,
      pageTools: EMPTY_PAGE_TOOLS
    });
  }
  const pageItems: BrowserLargeScreenToolbarMenuEntry[] =
    projectEntries(actions, PAGE_ACTION_IDS, webZoomAvailable);
  const pageTools: BrowserLargeScreenToolbarMenuPageToolGroup[] =
    projectPageToolGroups(actions, webZoomAvailable);
  if (pageItems.length > 0 || pageTools.length > 0) {
    sections.push({
      id: 'page',
      items: pageItems,
      pageTools: pageTools
    });
  }
  const zoomItems: BrowserLargeScreenToolbarMenuEntry[] =
    projectEntries(actions, ['textZoom'], webZoomAvailable);
  if (zoomItems.length > 0) {
    sections.push({
      id: 'zoom',
      items: zoomItems,
      pageTools: EMPTY_PAGE_TOOLS
    });
  }
  const preferences: BrowserLargeScreenToolbarMenuEntry[] =
    projectEntries(actions, PREFERENCE_ACTION_IDS, webZoomAvailable);
  if (preferences.length > 0) {
    sections.push({
      id: 'preferences',
      items: preferences,
      pageTools: EMPTY_PAGE_TOOLS
    });
  }
  return { sections: sections };
}

/**
 * The system Menu sizes to its rows and does not scroll. Pointer overflow uses this
 * height instead: content is the rows, headers and section gaps; the cap is the
 * space under the toolbar. A shorter window scrolls rather than dropping rows.
 */
export function resolveBrowserLargeScreenOverflowMenuHeight(
  plan: BrowserLargeScreenToolbarMenuPlan,
  viewportHeightVp: number,
  reservedTopVp: number
): BrowserLargeScreenToolbarMenuHeight {
  const contentHeightVp = measureOverflowMenuContentHeight(plan);
  if (!Number.isFinite(viewportHeightVp) || viewportHeightVp <= 0) {
    return {
      contentHeightVp: contentHeightVp,
      maxHeightVp: contentHeightVp,
      heightVp: contentHeightVp,
      scrollable: false
    };
  }
  const availableHeightVp = viewportHeightVp - Math.max(0, reservedTopVp) - OVERFLOW_MENU_BOTTOM_MARGIN_VP;
  const minimumHeightVp = BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP + BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP * 2;
  const maxHeightVp = Math.max(minimumHeightVp, availableHeightVp);
  const heightVp = Math.min(contentHeightVp, maxHeightVp);
  return {
    contentHeightVp: contentHeightVp,
    maxHeightVp: maxHeightVp,
    heightVp: heightVp,
    scrollable: contentHeightVp > maxHeightVp
  };
}

function measureOverflowMenuContentHeight(plan: BrowserLargeScreenToolbarMenuPlan): number {
  let itemCount = 0;
  let headerCount = 0;
  let blockCount = 0;
  plan.sections.forEach((section: BrowserLargeScreenToolbarMenuSection): void => {
    if (section.items.length > 0 || section.pageTools.length > 0) {
      blockCount += 1;
    }
    itemCount += section.items.length;
    section.pageTools.forEach((group: BrowserLargeScreenToolbarMenuPageToolGroup): void => {
      itemCount += group.items.length;
      if (resourceStrPresent(group.title)) {
        headerCount += 1;
      }
    });
  });
  return BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP * 2 +
    itemCount * BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP +
    headerCount * BROWSER_LARGE_SCREEN_OVERFLOW_MENU_GROUP_HEADER_HEIGHT_VP +
    Math.max(0, blockCount - 1) * BROWSER_LARGE_SCREEN_OVERFLOW_MENU_SECTION_GAP_VP;
}

export class BrowserLargeScreenToolbarMenuViewModel {
  private readonly bottomPanelViewModel: BrowserBottomAddressPanelViewModel =
    new BrowserBottomAddressPanelViewModel();

  resolveActions(
    snapshot: BrowserBottomPanelActionSnapshot | undefined,
    inputProfile: BrowserLargeScreenInputProfile,
    webZoomAvailable: boolean = false
  ): BrowserBottomAddressPanelAction[] {
    if (snapshot === undefined) {
      return [];
    }
    const primaryActions = snapshot.primaryActionOverrides ??
      this.bottomPanelViewModel.buildPrimaryActions(snapshot.actionInput, 8);
    const secondaryActions = snapshot.secondaryActionOverrides ??
      this.bottomPanelViewModel.buildSecondaryActions(snapshot.actionInput, primaryActions);
    const actions = this.mergeUniqueActions(primaryActions, secondaryActions);
    if (inputProfile === 'touch') {
      return actions;
    }
    return actions
      .filter((action: BrowserBottomAddressPanelAction): boolean =>
        this.isAvailableForPointerShell(action.id))
      .map((action: BrowserBottomAddressPanelAction): BrowserBottomAddressPanelAction =>
        this.projectPointerAction(action, webZoomAvailable));
  }

  resolvePointerMenu(
    snapshot: BrowserBottomPanelActionSnapshot | undefined,
    webZoomAvailable: boolean
  ): BrowserLargeScreenToolbarMenuPlan {
    if (snapshot === undefined) {
      return EMPTY_MENU_PLAN;
    }
    return projectBrowserLargeScreenPointerToolbarMenu(
      this.resolveCatalogActions(snapshot),
      webZoomAvailable
    );
  }

  private resolveCatalogActions(
    snapshot: BrowserBottomPanelActionSnapshot
  ): BrowserBottomAddressPanelAction[] {
    return this.mergeUniqueActions(
      this.bottomPanelViewModel.buildPrimaryActions(snapshot.actionInput, 8),
      this.bottomPanelViewModel.buildSecondaryActions(snapshot.actionInput, [])
    );
  }

  private mergeUniqueActions(
    primaryActions: BrowserBottomAddressPanelAction[],
    secondaryActions: BrowserBottomAddressPanelAction[]
  ): BrowserBottomAddressPanelAction[] {
    const result: BrowserBottomAddressPanelAction[] = [];
    primaryActions.concat(secondaryActions).forEach((action: BrowserBottomAddressPanelAction): void => {
      if (!result.some((candidate: BrowserBottomAddressPanelAction): boolean => candidate.id === action.id)) {
        result.push(action);
      }
    });
    return result;
  }

  private isAvailableForPointerShell(actionId: BrowserBottomAddressPanelActionId): boolean {
    return actionId !== 'bookmark' &&
      actionId !== 'home' &&
      actionId !== 'siteInfo' &&
      actionId !== 'fullScreenMode' &&
      actionId !== 'sendToDesktop' &&
      actionId !== 'screenOrientation';
  }

  private projectPointerAction(
    action: BrowserBottomAddressPanelAction,
    webZoomAvailable: boolean
  ): BrowserBottomAddressPanelAction {
    if (action.id !== 'textZoom') {
      return action;
    }
    return {
      id: action.id,
      title: BROWSER_LARGE_SCREEN_WEB_ZOOM_TITLE,
      trailingText: action.trailingText,
      icon: action.icon,
      imageIcon: action.imageIcon,
      airaIconId: action.airaIconId,
      enabled: webZoomAvailable,
      disabledMessage: webZoomAvailable ? '' : bottomPanelZoomUnavailable(),
      selected: action.selected,
      renderVersion: action.renderVersion
    };
  }
}

function projectPageToolGroups(
  actions: BrowserBottomAddressPanelAction[],
  webZoomAvailable: boolean
): BrowserLargeScreenToolbarMenuPageToolGroup[] {
  const groups: BrowserLargeScreenToolbarMenuPageToolGroup[] = [];
  PAGE_TOOL_GROUP_SPECS.forEach((spec: BrowserLargeScreenToolbarMenuPageToolGroupSpec): void => {
    const items: BrowserLargeScreenToolbarMenuEntry[] = projectEntries(actions, spec.actionIds, webZoomAvailable);
    if (items.length === 0) {
      return;
    }
    groups.push({
      id: spec.id,
      title: spec.title,
      items: items
    });
  });
  return groups;
}

function projectEntries(
  actions: BrowserBottomAddressPanelAction[],
  actionIds: BrowserBottomAddressPanelActionId[],
  webZoomAvailable: boolean
): BrowserLargeScreenToolbarMenuEntry[] {
  const entries: BrowserLargeScreenToolbarMenuEntry[] = [];
  actionIds.forEach((actionId: BrowserBottomAddressPanelActionId): void => {
    const action = findAction(actions, actionId) ?? resolveFixedDesktopMenuAction(actionId);
    if (action === undefined) {
      return;
    }
    entries.push(projectEntry(action, webZoomAvailable));
  });
  return entries;
}

/**
 * The fixed pointer menu's own Settings row. The phone toolbar catalog supplies the live action
 * while it still carries one; Settings no longer is one — it moved into the phone toolbar sheet
 * header — so the pointer "..." menu keeps building its own row instead of losing the entry.
 */
function resolveFixedDesktopMenuAction(
  actionId: BrowserBottomAddressPanelActionId
): BrowserBottomAddressPanelAction | undefined {
  if (actionId !== 'settings') {
    return undefined;
  }
  return {
    id: 'settings',
    title: BrowserBottomPanelActionCatalog.title('settings'),
    trailingText: BrowserBottomPanelActionCatalog.subtitle('settings'),
    icon: $r('sys.symbol.gearshape_fill'),
    airaIconId: BrowserBottomPanelActionCatalog.iconId('settings'),
    enabled: true,
    disabledMessage: ''
  };
}

function projectEntry(
  action: BrowserBottomAddressPanelAction,
  webZoomAvailable: boolean
): BrowserLargeScreenToolbarMenuEntry {
  if (action.id === 'textZoom') {
    return {
      action: copyAction(
        action,
        BROWSER_LARGE_SCREEN_WEB_ZOOM_TITLE,
        webZoomAvailable,
        webZoomAvailable ? '' : bottomPanelZoomUnavailable()
      ),
      showsSelection: false,
      activation: 'web_zoom'
    };
  }
  if (action.id === 'scripts') {
    return {
      action: copyAction(action, BROWSER_LARGE_SCREEN_SCRIPT_MANAGEMENT_TITLE, action.enabled, action.disabledMessage),
      showsSelection: false,
      activation: 'user_script_management'
    };
  }
  if (action.id === 'newPrivateTab') {
    return {
      action: copyAction(action, BROWSER_LARGE_SCREEN_PRIVACY_MODE_TITLE, action.enabled, action.disabledMessage),
      showsSelection: true,
      activation: 'browser_action'
    };
  }
  return {
    action: action,
    showsSelection: false,
    activation: 'browser_action'
  };
}

function copyAction(
  action: BrowserBottomAddressPanelAction,
  title: ResourceStr,
  enabled: boolean,
  disabledMessage: ResourceStr
): BrowserBottomAddressPanelAction {
  return {
    id: action.id,
    title: title,
    trailingText: action.trailingText,
    icon: action.icon,
    imageIcon: action.imageIcon,
    airaIconId: action.airaIconId,
    enabled: enabled,
    disabledMessage: disabledMessage,
    selected: action.selected,
    renderVersion: action.renderVersion
  };
}

function findAction(
  actions: BrowserBottomAddressPanelAction[],
  actionId: BrowserBottomAddressPanelActionId
): BrowserBottomAddressPanelAction | undefined {
  for (let index = 0; index < actions.length; index += 1) {
    if (actions[index].id === actionId) {
      return actions[index];
    }
  }
  return undefined;
}
