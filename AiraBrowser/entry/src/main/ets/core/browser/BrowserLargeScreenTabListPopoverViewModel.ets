import { image } from '@kit.ImageKit';
import { resolveSiteIconFallbackLabel } from '../../common/utils/SiteIconFallbackUtils';
import { AppWindowModalLayoutService } from '../../services/layout/AppWindowModalLayoutService';
import { AiraRenderableIconId } from '../resources/GeneratedAiraIconCatalog';
import { SiteIconListRenderState } from '../siteicons/SiteIconListPresenter';
import { formatTopChromeAddress } from './AddressDisplayFormatter';
import { BrowserLargeScreenInputProfile, BrowserLargeScreenTabStripPresentation } from './BrowserLargeScreenTabStripViewModel';
import { BrowserRecentlyClosedApplicationSnapshot } from './BrowserRecentlyClosedApplicationCoordinator';
import { HomeRecentlyClosedIconState } from './HomeRecentlyClosedIconHydrationCoordinator';
import { RecentlyClosedRecordTimeViewModel } from './RecentlyClosedRecordTimeViewModel';

const TAB_LIST_POPUP_WIDTH_VP: number = 400;
const TAB_LIST_POPUP_MIN_HEIGHT_VP: number = 152;
const TAB_LIST_POPUP_FALLBACK_MAX_HEIGHT_VP: number = 560;
const TAB_LIST_POPUP_HEIGHT_RATIO: number = 0.7;
const TAB_LIST_SECTION_HEADER_HEIGHT_VP: number = 40;
const TAB_LIST_RECENT_HEADER_HEIGHT_VP: number = 44;
const TAB_LIST_ROW_HEIGHT_VP: number = 52;
const TAB_LIST_RECENT_MAX_VISIBLE_ROWS: number = 4;
const TAB_LIST_EMPTY_HEIGHT_VP: number = 64;

export interface BrowserLargeScreenTabListOpenRowPresentation {
  tabId: string;
  title: string;
  subtitle: string;
  fallbackLabel: string;
  fallbackIconId?: AiraRenderableIconId;
  iconPath: string;
  iconPixelMap?: image.PixelMap;
  iconSourceRevision: number;
  loadingWithoutIcon: boolean;
  active: boolean;
  actionVisible: boolean;
  key: string;
}

export interface BrowserLargeScreenTabListRecentRowPresentation {
  recordId: string;
  title: string;
  subtitle: string;
  closedTime: string;
  fallbackLabel: string;
  iconPath: string;
  iconPixelMap?: image.PixelMap;
  actionVisible: boolean;
  key: string;
}

export interface BrowserLargeScreenTabListPopoverPresentation {
  openTabs: BrowserLargeScreenTabListOpenRowPresentation[];
  recentlyClosedTabs: BrowserLargeScreenTabListRecentRowPresentation[];
  popupWidthVp: number;
  popupHeightVp: number;
  recentlyClosedListHeightVp: number;
}

export interface BrowserLargeScreenTabListPopoverFacts {
  tabStrip: BrowserLargeScreenTabStripPresentation;
  recentlyClosed: BrowserRecentlyClosedApplicationSnapshot;
  tabIconStates: SiteIconListRenderState[];
  inputProfile: BrowserLargeScreenInputProfile;
  touchInteractionActive: boolean;
  hoveredTabId: string;
  hoveredRecordId: string;
  recentlyClosedExpanded: boolean;
  viewportWidthVp: number;
  viewportHeightVp: number;
  now?: number;
}

/** Owns the non-visual projection and sizing policy for the Large-Screen tab-list popup. */
export class BrowserLargeScreenTabListPopoverViewModel {
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();
  private readonly timeViewModel: RecentlyClosedRecordTimeViewModel = new RecentlyClosedRecordTimeViewModel();

  resolve(facts: BrowserLargeScreenTabListPopoverFacts): BrowserLargeScreenTabListPopoverPresentation {
    const openTabs = this.buildOpenTabRows(facts);
    const recentlyClosedTabs = this.buildRecentlyClosedRows(facts);
    const recentlyClosedListHeightVp = this.resolveRecentlyClosedListHeight(recentlyClosedTabs.length);
    return {
      openTabs: openTabs,
      recentlyClosedTabs: recentlyClosedTabs,
      popupWidthVp: this.modalLayoutService.resolvePopupWidth(facts.viewportWidthVp, TAB_LIST_POPUP_WIDTH_VP),
      popupHeightVp: this.resolvePopupHeight(
        facts.viewportHeightVp,
        openTabs.length,
        facts.recentlyClosedExpanded ? recentlyClosedListHeightVp : 0
      ),
      recentlyClosedListHeightVp: recentlyClosedListHeightVp
    };
  }

  private buildOpenTabRows(
    facts: BrowserLargeScreenTabListPopoverFacts
  ): BrowserLargeScreenTabListOpenRowPresentation[] {
    return facts.tabStrip.allTabs.map((tab): BrowserLargeScreenTabListOpenRowPresentation => {
      const title = tab.title.trim().length > 0 ? tab.title.trim() : '新标签页';
      const formattedAddress = formatTopChromeAddress(tab.url);
      const subtitle = formattedAddress.length > 0
        ? formattedAddress
        : (tab.privateMode ? '隐私标签页' : '新标签页');
      const iconState = this.findOpenTabIconState(facts.tabIconStates, tab.id);
      const iconPath = iconState?.path ?? '';
      return {
        tabId: tab.id,
        title: title,
        subtitle: subtitle,
        fallbackLabel: resolveSiteIconFallbackLabel(tab.title, tab.url),
        fallbackIconId: tab.fallbackIconId,
        iconPath: iconPath,
        iconPixelMap: iconState?.pixelMap,
        iconSourceRevision: iconState?.sourceRevision ?? 0,
        loadingWithoutIcon: tab.loading && iconPath.length <= 0 && iconState?.pixelMap === undefined,
        active: tab.active,
        actionVisible: tab.closable && this.shouldShowRowAction(
          facts.inputProfile,
          facts.touchInteractionActive,
          facts.hoveredTabId === tab.id
        ),
        key: `${tab.id}:${tab.active ? 'active' : 'inactive'}:${tab.title}`
      };
    });
  }

  private buildRecentlyClosedRows(
    facts: BrowserLargeScreenTabListPopoverFacts
  ): BrowserLargeScreenTabListRecentRowPresentation[] {
    const now = facts.now ?? Date.now();
    return facts.recentlyClosed.records.map((record): BrowserLargeScreenTabListRecentRowPresentation => {
      const url = this.resolveRecentlyClosedUrl(record.tab.url, record.tab.lastGoodUrl, record.tab.pendingUrl);
      const title = record.tab.title.trim().length > 0
        ? record.tab.title.trim()
        : (url.length > 0 ? url : '未命名标签页');
      const formattedAddress = formatTopChromeAddress(url);
      const iconState = this.findRecentlyClosedIconState(facts.recentlyClosed.icons, record.id);
      return {
        recordId: record.id,
        title: title,
        subtitle: formattedAddress.length > 0 ? formattedAddress : '网页',
        closedTime: this.timeViewModel.formatClosedTime(record.closedAt, now),
        fallbackLabel: resolveSiteIconFallbackLabel(title, url),
        iconPath: iconState?.path ?? (record.siteIconUri ?? ''),
        iconPixelMap: iconState?.pixelMap,
        actionVisible: this.shouldShowRowAction(
          facts.inputProfile,
          facts.touchInteractionActive,
          facts.hoveredRecordId === record.id
        ),
        key: `${record.id}:${facts.recentlyClosed.renderVersion}:${facts.recentlyClosed.iconSyncVersion}`
      };
    });
  }

  private shouldShowRowAction(
    inputProfile: BrowserLargeScreenInputProfile,
    touchInteractionActive: boolean,
    hovered: boolean
  ): boolean {
    return inputProfile === 'touch' || touchInteractionActive || hovered;
  }

  private resolvePopupHeight(viewportHeightVp: number, openTabCount: number, recentContentHeightVp: number): number {
    const openContentHeightVp = Math.max(TAB_LIST_EMPTY_HEIGHT_VP, openTabCount * TAB_LIST_ROW_HEIGHT_VP);
    const desiredHeightVp = TAB_LIST_SECTION_HEADER_HEIGHT_VP + openContentHeightVp +
      TAB_LIST_RECENT_HEADER_HEIGHT_VP + recentContentHeightVp + 1;
    const maximumHeightVp = Number.isFinite(viewportHeightVp) && viewportHeightVp > 0
      ? Math.max(TAB_LIST_POPUP_MIN_HEIGHT_VP, Math.floor(viewportHeightVp * TAB_LIST_POPUP_HEIGHT_RATIO))
      : TAB_LIST_POPUP_FALLBACK_MAX_HEIGHT_VP;
    return Math.max(TAB_LIST_POPUP_MIN_HEIGHT_VP, Math.min(desiredHeightVp, maximumHeightVp));
  }

  private resolveRecentlyClosedListHeight(recordCount: number): number {
    if (recordCount <= 0) {
      return TAB_LIST_EMPTY_HEIGHT_VP;
    }
    return Math.min(recordCount, TAB_LIST_RECENT_MAX_VISIBLE_ROWS) * TAB_LIST_ROW_HEIGHT_VP + 8;
  }

  private findOpenTabIconState(
    iconStates: SiteIconListRenderState[],
    tabId: string
  ): SiteIconListRenderState | undefined {
    return iconStates.find((state: SiteIconListRenderState): boolean => state.id === tabId);
  }

  private findRecentlyClosedIconState(
    iconStates: HomeRecentlyClosedIconState[],
    recordId: string
  ): HomeRecentlyClosedIconState | undefined {
    return iconStates.find((state: HomeRecentlyClosedIconState): boolean => state.id === recordId);
  }

  private resolveRecentlyClosedUrl(url: string, lastGoodUrl: string, pendingUrl: string): string {
    const candidates = [url, lastGoodUrl, pendingUrl];
    return candidates.find((value: string): boolean => value.trim().length > 0)?.trim() ?? '';
  }
}

export class BrowserLargeScreenTabListTimeRefreshCoordinator {
  private readonly onRefresh: () => void;
  private refreshTimer: number = -1;

  constructor(onRefresh: () => void) {
    this.onRefresh = onRefresh;
  }

  start(): void {
    this.stop();
    this.scheduleNext();
  }

  stop(): void {
    if (this.refreshTimer >= 0) {
      clearTimeout(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private scheduleNext(): void {
    this.refreshTimer = setTimeout((): void => {
      this.refreshTimer = -1;
      this.onRefresh();
      this.scheduleNext();
    }, 60 * 1000);
  }
}
