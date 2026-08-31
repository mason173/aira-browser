import {
  HomeContentThemePresentationState,
  HomeRecentlyClosedPresentationState,
  createDefaultHomeContentThemePresentationState
} from '../../../core/browser/HomeContentPresentationState';
import { HomeExpandableSectionHeader } from './HomeExpandableSectionHeader';
import { RecentlyClosedRecordList } from './RecentlyClosedRecordList';
import { HOME_WALLPAPER_APPEARANCE_TRANSITION_MS } from '../../../core/wallpaper/HomeWallpaperPresentationTokens';
import { BrowserRecentlyClosedUserAction } from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { HomeRecentlyClosedLayoutViewModel } from '../../../features/newtab/HomeRecentlyClosedLayoutViewModel';

const HOME_SECTION_CONTENT_INSET: number = 10;

@Component
export struct HomeRecentlyClosedSection {
  @Prop expanded: boolean = true;
  @Prop showTitle: boolean = true;
  @Prop contentWidth: number = 0;
  @Prop minimumWidth: number = 0;
  @Prop alignPartialRowsToStart: boolean = false;
  @Prop adaptColumnsToContentWidth: boolean = false;
  @Prop displayLimit: number = 8;
  @Prop recentlyClosed: HomeRecentlyClosedPresentationState = {
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
  };
  @Prop theme: HomeContentThemePresentationState = createDefaultHomeContentThemePresentationState();

  private layoutViewModel: HomeRecentlyClosedLayoutViewModel = new HomeRecentlyClosedLayoutViewModel();

  onAction: (action: BrowserRecentlyClosedUserAction) => void =
    (_action: BrowserRecentlyClosedUserAction) => {};
  onRestoreRecord: (recordId: string) => void = (_recordId: string) => {};
  onOpenHomeSettings: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      if (this.showTitle) {
        HomeExpandableSectionHeader({
          title: '最近关闭',
          expanded: this.expanded,
          leftInset: HOME_SECTION_CONTENT_INSET,
          rightInset: HOME_SECTION_CONTENT_INSET,
          primaryTextColor: this.theme.primaryTextColor,
          secondaryTextColor: this.theme.secondaryTextColor,
          pressedBackgroundColor: this.theme.pressedBackgroundColor,
          pressedBackdropBlurRadius: this.theme.pressedBackdropBlurRadius,
          textShadow: this.theme.textShadow,
          onToggle: () => {
            animateTo({ duration: 180, curve: Curve.EaseInOut }, () => {
              this.onAction({ type: 'toggle_home_section' });
            });
          }
        })
      }

      if (this.expanded || !this.showTitle) {
        ForEach([this.displayLimit], (displayLimit: number) => {
          this.buildRecordList(displayLimit)
        }, (displayLimit: number) => `${displayLimit}`)
      }
    }
    .width(this.resolveSectionWidth())
    .alignSelf(ItemAlign.Center)
    .id(this.recentlyClosed.sectionId)
  }

  @Builder
  private buildRecordList(displayLimit: number) {
    RecentlyClosedRecordList({
      records: this.recentlyClosed.records,
      recordLimit: displayLimit,
      emptyShowIcon: false,
      emptyTitle: '暂无最近关闭',
      emptyMessage: '',
      emptyTopPadding: 8,
      emptyBottomPadding: 28,
      showRestoreTrailing: false,
      contentWidth: this.resolveSectionWidth(),
      leftInset: HOME_SECTION_CONTENT_INSET,
      rightInset: HOME_SECTION_CONTENT_INSET,
      columns: this.resolveColumnCount(),
      columnGap: this.recentlyClosed.columnGap,
      rowGap: this.recentlyClosed.rowGap,
      alignPartialRowsToStart: this.alignPartialRowsToStart,
      homeShortcutRecordIds: this.recentlyClosed.homeShortcutRecordIds,
      primaryTextColor: this.theme.primaryTextColor,
      secondaryTextColor: this.theme.secondaryTextColor,
      pressedBackgroundColor: this.theme.pressedBackgroundColor,
      pressedBackdropBlurRadius: this.theme.pressedBackdropBlurRadius,
      textShadow: this.theme.textShadow,
      foregroundTransitionDurationMs: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS,
      iconResolveMode: 'cacheOnly',
      externalIconHydrationOnly: true,
      renderVersion: this.recentlyClosed.renderVersion,
      iconSyncVersion: this.recentlyClosed.iconSyncVersion,
      icons: this.recentlyClosed.icons,
      onAction: (action: BrowserRecentlyClosedUserAction) => {
        this.onAction(action);
      },
      onRestoreRecord: (recordId: string) => {
        this.onRestoreRecord(recordId);
      },
      onOpenHomeSettings: () => {
        this.onOpenHomeSettings();
      }
    })
  }

  private resolveSectionWidth(): number {
    const displayRecordCount = this.displayLimit > 0
      ? Math.min(this.recentlyClosed.records.length, this.displayLimit)
      : this.recentlyClosed.records.length;
    const contentDrivenWidth = this.layoutViewModel.resolveSectionWidth(
      displayRecordCount,
      this.contentWidth,
      HOME_SECTION_CONTENT_INSET,
      HOME_SECTION_CONTENT_INSET,
      this.resolveColumnCount(),
      this.recentlyClosed.columnGap
    );
    return Math.min(
      Math.max(1, this.contentWidth),
      Math.max(Math.max(0, this.minimumWidth), contentDrivenWidth)
    );
  }

  private resolveColumnCount(): number {
    if (!this.adaptColumnsToContentWidth) {
      return this.layoutViewModel.resolveColumnCount(this.recentlyClosed.columns);
    }
    return this.layoutViewModel.resolveAdaptiveColumnCount(
      this.contentWidth,
      HOME_SECTION_CONTENT_INSET,
      HOME_SECTION_CONTENT_INSET,
      this.recentlyClosed.columns,
      this.recentlyClosed.columnGap
    );
  }

}
