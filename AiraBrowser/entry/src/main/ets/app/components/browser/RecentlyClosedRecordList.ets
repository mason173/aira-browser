import { image } from '@kit.ImageKit';
import { BrowserRecentlyClosedTabRecord } from '../../../core/browser/BrowserRecentlyClosedTabsService';
import { HomeRecentlyClosedIconState } from '../../../core/browser/HomeRecentlyClosedIconHydrationCoordinator';
import { RecentlyClosedRecordTimeViewModel } from '../../../core/browser/RecentlyClosedRecordTimeViewModel';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveBrowserOperationalIconColor } from '../../../core/theme/BrowserOperationalIconTheme';
import {
  SiteIconListPresenter,
  SiteIconListResolvedIcon,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
  RECORD_LIST_ROW_PRESSED_HORIZONTAL_INSET,
  RECORD_LIST_ROW_PRESSED_VERTICAL_INSET
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';
import { normalizeHomeWallpaperTransitionDuration } from '../../../core/wallpaper/HomeWallpaperPresentationTokens';
import { BrowserRecentlyClosedUserAction } from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { HomeRecentlyClosedLayoutViewModel } from '../../../features/newtab/HomeRecentlyClosedLayoutViewModel';
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem } from './BrowserDesktopContextMenu';
import { BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP } from '../../../core/browser/BrowserDesktopMenuPresentationTokens';

interface RecentlyClosedRecordRow {
  rowIndex: number;
  records: BrowserRecentlyClosedTabRecord[];
}

export type RecentlyClosedIconResolveMode = 'memory' | 'cacheOnly';

const RECENTLY_CLOSED_TOUCH_MENU_WIDTH: number = 188;
const RECENTLY_CLOSED_CONTEXT_MENU_DISMISS_DELAY_MS: number = 240;
const RECENTLY_CLOSED_TIME_REFRESH_MS: number = 60 * 1000;

@Component
export struct RecentlyClosedRecordList {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Watch('syncSiteIcons')
  @Prop records: BrowserRecentlyClosedTabRecord[] = [];
  @Prop contentWidth: number = 0;
  @Prop leftInset: number = 16;
  @Prop rightInset: number = 16;
  @Prop recordLimit: number = 0;
  @Prop columns: number = 1;
  @Prop columnGap: number = 0;
  @Prop rowGap: number = 0;
  @Prop alignPartialRowsToStart: boolean = false;
  @Prop showEmptyState: boolean = true;
  @Prop emptyShowIcon: boolean = true;
  @Prop emptyTitle: string = '还没有最近关闭的标签页';
  @Prop emptyMessage: string = '关闭网页后，这里会显示可恢复的会话记录。';
  @Prop emptyTopPadding: number = 44;
  @Prop emptyBottomPadding: number = 96;
  @Prop showRestoreTrailing: boolean = true;
  @Prop homeShortcutRecordIds: string[] = [];
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @Prop pressedBackgroundColor: ResourceColor = '#DDE4EC';
  @Prop pressedBackdropBlurRadius: number = 0;
  @Prop textShadow: Array<ShadowOptions> = [];
  @Prop foregroundTransitionDurationMs: number = 0;
  @Prop iconResolveMode: RecentlyClosedIconResolveMode = 'cacheOnly';
  @Prop externalIconHydrationOnly: boolean = false;
  @Watch('resetTransientRowState')
  @Prop renderVersion: number = 0;
  @Watch('syncSiteIcons')
  @Prop iconSyncVersion: number = 0;
  @Prop icons: HomeRecentlyClosedIconState[] = [];
  @State private iconStates: HomeRecentlyClosedIconState[] = [];
  @State private pressedRecordId: string = '';
  @State private contextMenuRecordId: string = '';
  @State private timeRenderTick: number = 0;
  private timeRefreshTimer: number = -1;

  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private timeViewModel: RecentlyClosedRecordTimeViewModel = new RecentlyClosedRecordTimeViewModel();
  private layoutViewModel: HomeRecentlyClosedLayoutViewModel = new HomeRecentlyClosedLayoutViewModel();

  onAction: (action: BrowserRecentlyClosedUserAction) => void =
    (_action: BrowserRecentlyClosedUserAction) => {};
  onRestoreRecord: (recordId: string) => void = (_recordId: string) => {};
  onOpenHomeSettings: () => void = () => {};

  aboutToAppear(): void {
    if (!this.externalIconHydrationOnly) {
      this.siteIconListPresenter.bindDomainUpdates(
        (): SiteIconListTarget[] => this.buildSiteIconTargets(this.resolveDisplayRecords()),
        (result: SiteIconListResolvedIcon): void => {
          this.setIconPath(result.id, result.uri);
        }
      );
    }
    this.syncSiteIcons();
    this.scheduleTimeRefresh();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
    this.cancelTimeRefresh();
  }

  build() {
    Column({ space: 0 }) {
      this.buildRecordContent(this.resolveDisplayRecords())
    }
    .width('100%')
  }

  @Builder
  private buildRecordContent(records: BrowserRecentlyClosedTabRecord[]) {
    if (records.length <= 0) {
      if (this.showEmptyState) {
        AppEmptyState({
          airaIconId: 'browser.toolbar.tabs',
          showIcon: this.emptyShowIcon,
          title: this.emptyTitle,
          message: this.emptyMessage,
          topPadding: this.emptyTopPadding,
          bottomPadding: this.emptyBottomPadding,
          primaryTextColor: this.resolvePrimaryTextColor(),
          secondaryTextColor: this.resolveSecondaryTextColor(),
          textShadow: this.textShadow,
          foregroundTransitionDurationMs: this.foregroundTransitionDurationMs
        })
      }
    } else if (this.resolveColumnCount() <= 1) {
      ForEach(records, (record: BrowserRecentlyClosedTabRecord, index: number) => {
        this.buildRecordRow(record, index < records.length - 1)
      }, (record: BrowserRecentlyClosedTabRecord) => this.buildDisplayRecordKey(record))
    } else {
      Column({ space: this.rowGap }) {
        ForEach(this.resolveRecordRowsFor(records), (row: RecentlyClosedRecordRow) => {
          Row({ space: this.columnGap }) {
            ForEach(row.records, (record: BrowserRecentlyClosedTabRecord) => {
              Column() {
                this.buildRecordRow(record, false)
              }
              .width(this.resolveRecordCellWidth())
              .constraintSize({ minWidth: 0 })
            }, (record: BrowserRecentlyClosedTabRecord) => this.buildDisplayRecordKey(record))
          }
          .width(this.alignPartialRowsToStart
            ? this.resolveRecordGridWidth()
            : this.resolveRecordRowWidth(row.records.length))
        }, (row: RecentlyClosedRecordRow) => this.buildRecordRowKey(row))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: this.leftInset, right: this.rightInset })
    }
  }

  @Builder
  private buildRecordRow(record: BrowserRecentlyClosedTabRecord, showDivider: boolean) {
    Column() {
      WebsiteRecordRow({
        iconUri: this.resolveRecordIconUri(record),
        iconPixelMap: this.resolveRecordIconPixelMap(record),
        fallbackLabel: this.resolveRecordFallbackLabel(record),
        title: this.resolveRecordTitle(record),
        titleMeta: this.resolveRecordTime(record),
        subtitle: this.resolveRecordSubtitle(record),
        pressed: this.pressedRecordId === record.id,
        menuVisible: this.contextMenuRecordId === record.id,
        showDivider: showDivider,
        leftInset: this.leftInset,
        rightInset: this.rightInset,
        menuWidth: RECENTLY_CLOSED_TOUCH_MENU_WIDTH,
        iconSize: RECORD_LIST_ROW_FAVICON_SIZE,
        iconSlotSize: RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
        iconContentRatio: RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
        iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        pressedHorizontalInset: RECORD_LIST_ROW_PRESSED_HORIZONTAL_INSET,
        pressedVerticalInset: RECORD_LIST_ROW_PRESSED_VERTICAL_INSET,
        primaryTextColor: this.resolvePrimaryTextColor(),
        secondaryTextColor: this.resolveSecondaryTextColor(),
        fallbackIconTextColor: this.resolveOperationalIconColor(),
        previewPrimaryTextColor: this.primaryTextColor,
        previewSecondaryTextColor: this.secondaryTextColor,
        pressedBackgroundColor: this.pressedBackgroundColor,
        preferPixelMap: true,
        pressedBackdropBlurRadius: this.pressedBackdropBlurRadius,
        textShadow: this.textShadow,
        foregroundTransitionDurationMs: this.foregroundTransitionDurationMs,
        onTouchAction: (type: TouchType) => {
          this.updatePressedRecord(record.id, type);
        },
        onOpenMenu: () => {
          this.openContextMenu(record.id);
        },
        onRowClick: () => {
          this.onRestoreRecord(record.id);
        },
        onMenuAppear: () => {
          this.pressedRecordId = record.id;
        },
        onMenuDisappear: () => {
          this.contextMenuRecordId = '';
          this.pressedRecordId = '';
        },
        trailing: () => {
          if (this.showRestoreTrailing) {
            this.buildRestoreTrailing()
          }
        },
        previewTrailing: () => {
          if (this.showRestoreTrailing) {
            this.buildRestoreTrailing()
          }
        },
        menuContent: () => {
          this.buildTouchMenuItems(record)
        }
      })
    }
    .width('100%')
    .bindContextMenu(this.buildRightClickContextMenu(record), ResponseType.RightClick, {
      onAppear: () => {
        this.contextMenuRecordId = '';
        this.pressedRecordId = record.id;
      },
      onDisappear: () => {
        if (this.pressedRecordId === record.id) {
          this.pressedRecordId = '';
        }
      }
    })
  }

  @Builder
  private buildRightClickContextMenu(record: BrowserRecentlyClosedTabRecord) {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP }) {
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
          label: '重新打开',
          onAction: (): void => {
            this.onRestoreRecord(record.id);
          }
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
          label: '复制链接',
          itemEnabled: this.resolveRecordUrl(record).length > 0,
          onAction: (): void => {
            this.onAction({ type: 'copy_record_url', recordId: record.id });
          }
        })

        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
          label: this.isRecordAddedToHome(record) ? '从主页移除' : '添加到主页',
          itemEnabled: this.resolveRecordUrl(record).length > 0,
          onAction: (): void => {
            this.onAction({ type: 'toggle_home_shortcut', recordId: record.id });
          }
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
          label: '删除记录',
          onAction: (): void => {
            this.onAction({ type: 'request_delete_record', recordId: record.id });
          }
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
          label: '主页设置',
          onAction: (): void => {
            this.runAfterContextMenuDismiss(() => {
              this.onOpenHomeSettings();
            });
          }
        })
      }
    }
  }

  @Builder
  private buildRestoreTrailing() {
    SymbolGlyph($r('sys.symbol.arrow_counterclockwise'))
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor([this.resolveSecondaryTextColor()])
      .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
  }

  @Builder
  private buildTouchMenuItems(record: BrowserRecentlyClosedTabRecord) {
    MenuItem({ content: '重新打开' })
      .onClick(() => {
        this.onRestoreRecord(record.id);
      })

    MenuItem({ content: '复制链接' })
      .enabled(this.resolveRecordUrl(record).length > 0)
      .onClick(() => {
        this.onAction({ type: 'copy_record_url', recordId: record.id });
      })

    MenuItem({ content: this.isRecordAddedToHome(record) ? '从主页移除' : '添加到主页' })
      .enabled(this.resolveRecordUrl(record).length > 0)
      .onClick(() => {
        this.onAction({ type: 'toggle_home_shortcut', recordId: record.id });
      })

    MenuItem({ content: '删除记录' })
      .onClick(() => {
        this.onAction({ type: 'request_delete_record', recordId: record.id });
      })

    MenuItem({ content: '主页设置' })
      .onClick(() => {
        this.runAfterContextMenuDismiss(() => {
          this.onOpenHomeSettings();
        });
      })
  }

  private resolveDisplayRecords(): BrowserRecentlyClosedTabRecord[] {
    if (this.recordLimit > 0) {
      return this.records.slice(0, this.recordLimit);
    }
    return this.records.slice();
  }

  private resolveOperationalIconColor(): ResourceColor {
    return resolveBrowserOperationalIconColor(this.storedResolvedThemeMode);
  }

  private resolveRecordRowsFor(records: BrowserRecentlyClosedTabRecord[]): RecentlyClosedRecordRow[] {
    const columnCount = this.resolveColumnCount();
    const rows: RecentlyClosedRecordRow[] = [];
    for (let startIndex = 0; startIndex < records.length; startIndex += columnCount) {
      rows.push({
        rowIndex: rows.length,
        records: records.slice(startIndex, startIndex + columnCount)
      });
    }
    return rows;
  }

  private buildRecordRowKey(row: RecentlyClosedRecordRow): string {
    const recordIds = row.records.map((record: BrowserRecentlyClosedTabRecord) => record.id).join('|');
    return `${this.buildDisplayLimitKey()}:${recordIds}`;
  }

  private buildDisplayRecordKey(record: BrowserRecentlyClosedTabRecord): string {
    return `${this.buildDisplayLimitKey()}:${record.id}`;
  }

  private buildDisplayLimitKey(): string {
    return `${Math.max(0, Math.floor(this.recordLimit))}`;
  }

  private resolveColumnCount(): number {
    return this.layoutViewModel.resolveColumnCount(this.columns);
  }

  private resolveRecordCellWidth(): number {
    return this.layoutViewModel.resolveRecordCellWidth(
      this.contentWidth,
      this.leftInset,
      this.rightInset,
      this.columns,
      this.columnGap
    );
  }

  private resolveRecordRowWidth(recordCount: number): number {
    return this.layoutViewModel.resolveRecordRowWidth(
      recordCount,
      this.contentWidth,
      this.leftInset,
      this.rightInset,
      this.columns,
      this.columnGap
    );
  }

  private resolveRecordGridWidth(): number {
    return this.layoutViewModel.resolveRecordGridWidth(
      this.contentWidth,
      this.leftInset,
      this.rightInset,
      this.columns,
      this.columnGap
    );
  }

  private resetTransientRowState(): void {
    this.contextMenuRecordId = '';
    this.pressedRecordId = '';
  }

  private syncSiteIcons(): void {
    const records = this.resolveDisplayRecords();
    const activeIds: Record<string, boolean> = {};
    records.forEach((record: BrowserRecentlyClosedTabRecord) => {
      activeIds[record.id] = true;
    });
    const retainedIconStates = this.iconStates.filter((item: HomeRecentlyClosedIconState) => activeIds[item.id] === true);
    if (retainedIconStates.length !== this.iconStates.length) {
      this.iconStates = retainedIconStates;
    }
    if (activeIds[this.pressedRecordId] !== true) {
      this.pressedRecordId = '';
    }
    if (activeIds[this.contextMenuRecordId] !== true) {
      this.contextMenuRecordId = '';
    }
    if (this.externalIconHydrationOnly) {
      return;
    }
    if (this.iconResolveMode === 'memory') {
      this.syncResolvedFavicons(records, true);
    } else {
      this.syncResolvedFavicons(records, false);
    }
  }

  private syncResolvedFavicons(records: BrowserRecentlyClosedTabRecord[], memoryOnly: boolean): void {
    this.siteIconListPresenter.resolveTargets(
      this.buildSiteIconTargets(records),
      (result: SiteIconListResolvedIcon): void => {
        if (result.uri.length > 0) {
          this.setIconPath(result.id, result.uri);
        }
      },
      {
        resolutionPolicy: memoryOnly ? 'memoryOnly' : 'remoteAllowed',
        shouldSkipTarget: (target: SiteIconListTarget): boolean => this.shouldShowImageIcon(target.id)
      }
    );
  }

  private buildSiteIconTargets(records: BrowserRecentlyClosedTabRecord[]): SiteIconListTarget[] {
    return records
      .map((record: BrowserRecentlyClosedTabRecord): SiteIconListTarget => {
        return {
          id: record.id,
          url: this.resolveRecordUrl(record),
          initialIconUri: this.iconResolveMode === 'memory' ? '' : this.resolveStoredRecordIconUri(record)
        };
      })
      .filter((target: SiteIconListTarget): boolean => target.id.length > 0 && target.url.length > 0);
  }

  private updatePressedRecord(recordId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedRecordId = recordId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedRecordId = '';
    }
  }

  private openContextMenu(recordId: string): void {
    this.contextMenuRecordId = recordId;
    this.pressedRecordId = recordId;
  }

  private runAfterContextMenuDismiss(action: () => void): void {
    this.contextMenuRecordId = '';
    this.pressedRecordId = '';
    setTimeout(action, RECENTLY_CLOSED_CONTEXT_MENU_DISMISS_DELAY_MS);
  }

  private resolveRecordTitle(record: BrowserRecentlyClosedTabRecord): string {
    const title = record.tab.title.trim();
    if (title.length > 0) {
      return title;
    }
    const url = this.resolveRecordUrl(record);
    return url.length > 0 ? url : '未命名标签页';
  }

  private resolveRecordSubtitle(record: BrowserRecentlyClosedTabRecord): string {
    return this.resolveRecordUrl(record);
  }

  private resolveRecordTime(record: BrowserRecentlyClosedTabRecord): string {
    this.timeRenderTick;
    return this.timeViewModel.formatClosedTime(record.closedAt);
  }

  private resolveRecordUrl(record: BrowserRecentlyClosedTabRecord): string {
    if (record.tab.url.trim().length > 0) {
      return record.tab.url.trim();
    }
    if (record.tab.lastGoodUrl.trim().length > 0) {
      return record.tab.lastGoodUrl.trim();
    }
    return record.tab.pendingUrl.trim();
  }

  private resolveRecordIconUri(record: BrowserRecentlyClosedTabRecord): string {
    const iconPath = this.getIconPath(record.id);
    if (iconPath.length > 0) {
      return iconPath;
    }
    return this.resolveStoredRecordIconUri(record);
  }

  private resolveRecordIconPixelMap(record: BrowserRecentlyClosedTabRecord): image.PixelMap | undefined {
    const state = this.getIconState(record.id);
    return state?.pixelMap;
  }

  private resolveStoredRecordIconUri(record: BrowserRecentlyClosedTabRecord): string {
    return (record.siteIconUri ?? '').trim();
  }

  private isRecordAddedToHome(record: BrowserRecentlyClosedTabRecord): boolean {
    return this.homeShortcutRecordIds.indexOf(record.id) >= 0;
  }

  private resolveRecordFallbackLabel(record: BrowserRecentlyClosedTabRecord): string {
    return resolveSiteIconFallbackLabel(this.resolveRecordTitle(record), this.resolveRecordUrl(record));
  }

  private scheduleTimeRefresh(): void {
    this.cancelTimeRefresh();
    this.timeRefreshTimer = setTimeout(() => {
      this.timeRefreshTimer = -1;
      this.timeRenderTick += 1;
      this.scheduleTimeRefresh();
    }, RECENTLY_CLOSED_TIME_REFRESH_MS);
  }

  private cancelTimeRefresh(): void {
    if (this.timeRefreshTimer >= 0) {
      clearTimeout(this.timeRefreshTimer);
      this.timeRefreshTimer = -1;
    }
  }

  private getIconPath(recordId: string): string {
    const state = this.getIconState(recordId);
    return state === undefined ? '' : state.path;
  }

  private shouldShowImageIcon(recordId: string): boolean {
    const state = this.getIconState(recordId);
    return state !== undefined && state.path.length > 0;
  }

  private getIconState(recordId: string): HomeRecentlyClosedIconState | undefined {
    const externalState = this.icons.find((item: HomeRecentlyClosedIconState) => item.id === recordId);
    if (externalState !== undefined && externalState.path.length > 0) {
      return externalState;
    }
    return this.iconStates.find((item: HomeRecentlyClosedIconState) => item.id === recordId);
  }

  private setIconPath(recordId: string, path: string): void {
    const existing = this.iconStates.find((item: HomeRecentlyClosedIconState) => item.id === recordId);
    if (existing !== undefined && existing.path === path) {
      return;
    }
    const next = this.iconStates.filter((item: HomeRecentlyClosedIconState) => item.id !== recordId);
    this.iconStates = next.concat([{ id: recordId, path: path }]);
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor;
  }

  private resolveForegroundTransitionDuration(): number {
    return normalizeHomeWallpaperTransitionDuration(this.foregroundTransitionDurationMs);
  }
}
