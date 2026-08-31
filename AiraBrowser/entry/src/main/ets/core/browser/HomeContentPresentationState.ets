import { ShortcutRecord } from '../../common/models/BrowserModels';
import { BrowserRecentlyClosedTabRecord } from './BrowserRecentlyClosedTabsService';
import { HomeShortcutIconState } from '../../features/newtab/HomeShortcutTypes';
import { HomeRecentlyClosedIconState } from './HomeRecentlyClosedIconHydrationCoordinator';
import { HomeShortcutLayoutMetrics } from '../../services/shortcuts/HomeShortcutLogicService';
import { BrowserForegroundPresentation } from './BrowserForegroundPresentationViewModel';

export interface HomeShortcutPresentationState {
  shortcuts: ShortcutRecord[];
  showAddEntry: boolean;
  gridWidth: number;
  gridTopInset: number;
  layoutVersion: number;
  iconsVersion: number;
  icons: HomeShortcutIconState[];
  metrics: HomeShortcutLayoutMetrics;
}

export interface HomeRecentlyClosedPresentationState {
  sectionId: string;
  records: BrowserRecentlyClosedTabRecord[];
  limit: number;
  columns: number;
  columnGap: number;
  rowGap: number;
  renderVersion: number;
  iconSyncVersion: number;
  icons: HomeRecentlyClosedIconState[];
  homeShortcutRecordIds: string[];
}

export interface HomeContentSectionsPresentationState {
  showRecentlyClosed: boolean;
  centerContentVertically: boolean;
  useSharedSectionWidth: boolean;
  horizontalPadding: number;
  contentTopPadding: number;
  sectionVerticalGap: number;
  bottomSpacerHeight: number;
  shortcuts: HomeShortcutPresentationState;
  recentlyClosed: HomeRecentlyClosedPresentationState;
}

export interface HomeContentRecentlyClosedLayoutState {
  columns: number;
  columnGap: number;
  rowGap: number;
}

export interface HomeContentThemePresentationState extends BrowserForegroundPresentation {
  pressedBackgroundColor: ResourceColor;
  pressedBackdropBlurRadius: number;
  controlBackgroundColor: ResourceColor;
  accentColor: ResourceColor;
}

export function createDefaultHomeContentThemePresentationState(): HomeContentThemePresentationState {
  return {
    tone: 'dark',
    primaryTextColor: '#FF000000',
    secondaryTextColor: '#99000000',
    iconColor: '#FF000000',
    iconTone: 'light',
    textShadow: [],
    freshnessKey: 'default',
    pressedBackgroundColor: '#DDE4EC',
    pressedBackdropBlurRadius: 0,
    controlBackgroundColor: '#E9EDF2',
    accentColor: '#0A59F7'
  };
}

export function createDefaultHomeContentSectionsPresentationState(): HomeContentSectionsPresentationState {
  return {
    showRecentlyClosed: false,
    centerContentVertically: false,
    useSharedSectionWidth: false,
    horizontalPadding: 8,
    contentTopPadding: 44,
    sectionVerticalGap: 14,
    bottomSpacerHeight: 0,
    shortcuts: {
      shortcuts: [],
      showAddEntry: false,
      gridWidth: 0,
      gridTopInset: 0,
      layoutVersion: 0,
      iconsVersion: 0,
      icons: [],
      metrics: {
        columns: 4,
        rowGap: 0,
        columnGap: 0,
        targetTileSize: 54,
        minimumTileSize: 41,
        fallbackColumnWidth: 88,
        titleTopGap: 2,
        titleBlockHeight: 18
      }
    },
    recentlyClosed: {
      sectionId: '',
      records: [],
      limit: 8,
      columns: 1,
      columnGap: 0,
      rowGap: 0,
      renderVersion: 0,
      iconSyncVersion: 0,
      icons: [],
      homeShortcutRecordIds: []
    }
  };
}
