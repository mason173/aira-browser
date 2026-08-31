import { image } from '@kit.ImageKit';
import { HistoryDisplayVisit } from '../../../features/history/HistoryViewModel';
import {
  HistoryTimelineDataSource,
  HistoryTimelineGroup
} from '../../../features/history/HistoryTimelineDataSource';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  RECORD_LIST_CARD_RADIUS,
  RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
  RECORD_LIST_GROUP_SPACE,
  RECORD_LIST_GROUP_TITLE_BOTTOM_PADDING,
  RECORD_LIST_GROUP_TITLE_LEFT_INSET,
  RECORD_LIST_GROUP_TITLE_RIGHT_INSET,
  RECORD_LIST_GROUP_TITLE_SIZE,
  RECORD_LIST_GROUP_TITLE_TOP_PADDING,
  RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_HORIZONTAL_INSET,
  RECORD_LIST_ROW_RADIUS
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SiteIconListRenderState,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { AiraIcon } from '../common/AiraIcon';

const HISTORY_TIMELINE_CACHE_COUNT: number = 4;
const HISTORY_TIMELINE_GROUP_PADDING: number = 4;
const HISTORY_TIMELINE_DELETE_ACTION_WIDTH: number = 72;
const HISTORY_TIMELINE_DELETE_BUTTON_SIZE: number = 40;
const HISTORY_TIMELINE_DELETE_ACTION_DISTANCE: number = 56;
const HISTORY_TIMELINE_TOP_BLUR_RADIUS: number = 20;
@Component
export struct HistoryTimelineList {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  dataSource: HistoryTimelineDataSource = new HistoryTimelineDataSource();
  listScroller: ListScroller = new ListScroller();
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop bookmarkedVisitIds: string[] = [];
  @Prop homeShortcutVisitIds: string[] = [];
  @Prop selectedVisitIds: string[] = [];
  @Prop pressedVisitId: string = '';
  @Prop contextMenuVisitId: string = '';
  @Prop isSelectionMode: boolean = false;
  @Prop contentStartOffset: number = 4;
  private iconLookupSource: SiteIconListRenderState[] = [];
  private iconLookup: Record<string, SiteIconListRenderState | undefined> = {};
  private bookmarkedVisitIdLookupSource: string[] = [];
  private bookmarkedVisitIdLookup: Record<string, boolean> = {};
  private homeShortcutVisitIdLookupSource: string[] = [];
  private homeShortcutVisitIdLookup: Record<string, boolean> = {};
  private selectedVisitIdLookupSource: string[] = [];
  private selectedVisitIdLookup: Record<string, boolean> = {};
  onOpenVisit: (visit: HistoryDisplayVisit) => void = (_visit: HistoryDisplayVisit) => {};
  onOpenContextMenu: (visitId: string) => void = (_visitId: string) => {};
  onUpdatePressedVisit: (visitId: string, type: TouchType) => void = (_visitId: string, _type: TouchType) => {};
  onToggleVisitSelection: (visitId: string) => void = (_visitId: string) => {};
  onSetVisitSelected: (visitId: string, selected: boolean) => void = (_visitId: string, _selected: boolean) => {};
  onContextAction: (visit: HistoryDisplayVisit, title: string) => void =
    (_visit: HistoryDisplayVisit, _title: string) => {};
  onIconLoadError: (
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number
  ) => void = (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number) => {};
  onContextDisappear: () => void = () => {};
  onContextAppear: () => void = () => {};
  onScrollVisibleContentChange: (
    startGroupIndex: number,
    startItemIndex: number,
    endGroupIndex: number,
    endItemIndex: number
  ) => void = (
    _startGroupIndex: number,
    _startItemIndex: number,
    _endGroupIndex: number,
    _endItemIndex: number
  ) => {};
  onReachEnd: () => void = () => {};
  onDeleteVisit: (visit: HistoryDisplayVisit) => void = (_visit: HistoryDisplayVisit) => {};
  onSwipeActionStateChange: (visitId: string, open: boolean) => void =
    (_visitId: string, _open: boolean) => {};

  build() {
    List({ scroller: this.listScroller, space: 0 }) {
      LazyForEach(this.dataSource, (group: HistoryTimelineGroup, groupIndex: number) => {
        ListItemGroup({ header: this.buildDateHeader(group) }) {
          LazyForEach(group.itemDataSource, (visit: HistoryDisplayVisit) => {
            ListItem() {
              this.buildVisitRecord(visit)
            }
            .width('100%')
            .margin({ left: HISTORY_TIMELINE_GROUP_PADDING, right: HISTORY_TIMELINE_GROUP_PADDING })
            .clip(true)
            .swipeAction(this.isSelectionMode ? {} : {
              end: {
                builder: () => {
                  this.buildDeleteSwipeAction(visit)
                },
                onAction: () => {
                  this.onDeleteVisit(visit);
                },
                onStateChange: (state: SwipeActionState) => {
                  this.onSwipeActionStateChange(visit.id, state !== SwipeActionState.COLLAPSED);
                },
                actionAreaDistance: HISTORY_TIMELINE_DELETE_ACTION_DISTANCE
              }
            })
          }, (visit: HistoryDisplayVisit) => visit.id)
        }
        .width('100%')
        .margin({ top: groupIndex > 0 ? RECORD_LIST_GROUP_SPACE : 0 })
        .padding({ bottom: HISTORY_TIMELINE_GROUP_PADDING })
        .backgroundColor(this.storedSurfaceBackgroundColor)
        .borderRadius(RECORD_LIST_CARD_RADIUS)
        .clip(true)
      }, (group: HistoryTimelineGroup) => group.key)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 4 })
    .contentStartOffset(this.contentStartOffset)
    .linearGradientBlur(HISTORY_TIMELINE_TOP_BLUR_RADIUS, {
      fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
      direction: GradientDirection.Bottom
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Off)
    .cachedCount(HISTORY_TIMELINE_CACHE_COUNT)
    .onScrollVisibleContentChange((start: VisibleListContentInfo, end: VisibleListContentInfo) => {
      this.onScrollVisibleContentChange(
        start.index,
        start.itemIndexInGroup ?? -1,
        end.index,
        end.itemIndexInGroup ?? -1
      );
    })
    .onReachEnd(() => {
      this.onReachEnd();
    })
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }

  @Builder
  private buildDateHeader(group: HistoryTimelineGroup) {
    Text(group.label)
      .width('100%')
      .fontSize(RECORD_LIST_GROUP_TITLE_SIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedSecondaryTextColor)
      .padding({
        left: RECORD_LIST_GROUP_TITLE_LEFT_INSET + HISTORY_TIMELINE_GROUP_PADDING,
        right: RECORD_LIST_GROUP_TITLE_RIGHT_INSET + HISTORY_TIMELINE_GROUP_PADDING,
        top: RECORD_LIST_GROUP_TITLE_TOP_PADDING,
        bottom: RECORD_LIST_GROUP_TITLE_BOTTOM_PADDING
      })
  }

  @Builder
  private buildVisitRecord(visit: HistoryDisplayVisit) {
    HistoryTimelineRecordRow({
      iconUri: this.getIconPathById(visit.id),
      iconPixelMap: this.getIconPixelMap(visit.id),
      iconSourceRevision: this.getIconSourceRevision(visit.id),
      fallbackLabel: resolveSiteIconFallbackLabel(visit.title, visit.host.length > 0 ? visit.host : visit.url),
      title: visit.title,
      subtitle: visit.url,
      pressed: this.pressedVisitId === visit.id,
      menuVisible: !this.isSelectionMode && this.contextMenuVisitId === visit.id,
      duplicateCount: visit.duplicateCount,
      bookmarked: this.isVisitBookmarked(visit.id),
      addedToHome: this.isVisitAddedToHome(visit.id),
      selected: this.isVisitSelected(visit.id),
      selectionMode: this.isSelectionMode,
      rowBorderRadius: this.resolveDefaultVisitRowRadius(),
      iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      host: visit.host,
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.onIconLoadError({
          id: visit.id,
          url: visit.url,
          domain: visit.host
        }, iconUri, sourceRevision);
      },
      onTouchAction: (type: TouchType) => {
        this.onUpdatePressedVisit(visit.id, type);
      },
      onOpenMenu: () => {
        this.onOpenContextMenu(visit.id);
      },
      onRowClick: () => {
        if (this.isSelectionMode) {
          this.onToggleVisitSelection(visit.id);
        } else {
          this.onOpenVisit(visit);
        }
      },
      onMenuAppear: () => {
        this.onContextAppear();
      },
      onMenuDisappear: () => {
        this.onContextDisappear();
      },
      onSelectedChange: (isSelected: boolean) => {
        this.onSetVisitSelected(visit.id, isSelected);
      },
      onContextAction: (title: string) => {
        this.onContextAction(visit, title);
      }
    })
      .reuseId('history_timeline_visit')
  }

  @Builder
  private buildDeleteSwipeAction(visit: HistoryDisplayVisit) {
    Row() {
      Button() {
        AiraIcon({
          airaIconId: 'browser.tabs.delete',
          iconSize: 20,
          iconColor: this.storedSurfaceBackgroundColor
        })
      }
      .width(HISTORY_TIMELINE_DELETE_BUTTON_SIZE)
      .height(HISTORY_TIMELINE_DELETE_BUTTON_SIZE)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor($r('app.color.permission_blocked'))
      .stateEffect(true)
      .accessibilityText('删除历史记录')
      .onClick(() => {
        this.onDeleteVisit(visit);
      })
    }
    .width(HISTORY_TIMELINE_DELETE_ACTION_WIDTH)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  private resolveDefaultVisitRowRadius(): BorderRadiuses {
    return {
      topLeft: RECORD_LIST_ROW_RADIUS,
      topRight: RECORD_LIST_ROW_RADIUS,
      bottomLeft: RECORD_LIST_ROW_RADIUS,
      bottomRight: RECORD_LIST_ROW_RADIUS
    };
  }

  private isVisitSelected(visitId: string): boolean {
    return this.getSelectedVisitIdLookup()[visitId] === true;
  }

  private isVisitBookmarked(visitId: string): boolean {
    return this.getBookmarkedVisitIdLookup()[visitId] === true;
  }

  private isVisitAddedToHome(visitId: string): boolean {
    return this.getHomeShortcutVisitIdLookup()[visitId] === true;
  }

  private getIconPathById(visitId: string): string {
    return this.getIconState(visitId)?.path ?? '';
  }

  private getIconPixelMap(visitId: string): image.PixelMap | undefined {
    return this.getIconState(visitId)?.pixelMap;
  }

  private getIconSourceRevision(visitId: string): number {
    return this.getIconState(visitId)?.sourceRevision ?? 0;
  }

  private getIconState(visitId: string): SiteIconListRenderState | undefined {
    if (this.iconLookupSource !== this.icons) {
      this.iconLookupSource = this.icons;
      this.iconLookup = this.buildIconLookup(this.icons);
    }
    return this.iconLookup[visitId];
  }

  private getBookmarkedVisitIdLookup(): Record<string, boolean> {
    if (this.bookmarkedVisitIdLookupSource !== this.bookmarkedVisitIds) {
      this.bookmarkedVisitIdLookupSource = this.bookmarkedVisitIds;
      this.bookmarkedVisitIdLookup = this.buildIdLookup(this.bookmarkedVisitIds);
    }
    return this.bookmarkedVisitIdLookup;
  }

  private getHomeShortcutVisitIdLookup(): Record<string, boolean> {
    if (this.homeShortcutVisitIdLookupSource !== this.homeShortcutVisitIds) {
      this.homeShortcutVisitIdLookupSource = this.homeShortcutVisitIds;
      this.homeShortcutVisitIdLookup = this.buildIdLookup(this.homeShortcutVisitIds);
    }
    return this.homeShortcutVisitIdLookup;
  }

  private getSelectedVisitIdLookup(): Record<string, boolean> {
    if (this.selectedVisitIdLookupSource !== this.selectedVisitIds) {
      this.selectedVisitIdLookupSource = this.selectedVisitIds;
      this.selectedVisitIdLookup = this.buildIdLookup(this.selectedVisitIds);
    }
    return this.selectedVisitIdLookup;
  }

  private buildIconLookup(icons: SiteIconListRenderState[]): Record<string, SiteIconListRenderState | undefined> {
    const lookup: Record<string, SiteIconListRenderState | undefined> = {};
    icons.forEach((item: SiteIconListRenderState) => {
      lookup[item.id] = item;
    });
    return lookup;
  }

  private buildIdLookup(ids: string[]): Record<string, boolean> {
    const lookup: Record<string, boolean> = {};
    ids.forEach((id: string) => {
      lookup[id] = true;
    });
    return lookup;
  }
}

@Reusable
@Component
struct HistoryTimelineRecordRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop iconUri: string = '';
  @Prop iconPixelMap: image.PixelMap | undefined = undefined;
  @Prop iconSourceRevision: number = 0;
  @Prop fallbackLabel: string = '#';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop pressed: boolean = false;
  @Prop menuVisible: boolean = false;
  @Prop duplicateCount: number = 1;
  @Prop bookmarked: boolean = false;
  @Prop addedToHome: boolean = false;
  @Prop selected: boolean = false;
  @Prop selectionMode: boolean = false;
  @Prop rowBorderRadius: BorderRadiuses = { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 };
  @Prop iconCornerRadiusRatio: number = 0.3;
  @Prop host: string = '';
  onTouchAction: (type: TouchType) => void = (_type: TouchType) => {};
  onOpenMenu: () => void = () => {};
  onRowClick: () => void = () => {};
  onMenuAppear: () => void = () => {};
  onMenuDisappear: () => void = () => {};
  onSelectedChange: (selected: boolean) => void = (_selected: boolean) => {};
  onContextAction: (title: string) => void = (_title: string) => {};
  onIconLoadError: (iconUri: string, sourceRevision: number) => void =
    (_iconUri: string, _sourceRevision: number) => {};

  aboutToReuse(params: Record<string, Object>): void {
    this.iconUri = params.iconUri as string;
    this.iconPixelMap = params.iconPixelMap as image.PixelMap | undefined;
    this.iconSourceRevision = params.iconSourceRevision as number;
    this.fallbackLabel = params.fallbackLabel as string;
    this.title = params.title as string;
    this.subtitle = params.subtitle as string;
    this.pressed = params.pressed as boolean;
    this.menuVisible = params.menuVisible as boolean;
    this.duplicateCount = params.duplicateCount as number;
    this.bookmarked = params.bookmarked as boolean;
    this.addedToHome = params.addedToHome as boolean;
    this.selected = params.selected as boolean;
    this.selectionMode = params.selectionMode as boolean;
    this.rowBorderRadius = params.rowBorderRadius as BorderRadiuses;
    this.iconCornerRadiusRatio = params.iconCornerRadiusRatio as number;
    this.host = params.host as string;
    this.onTouchAction = params.onTouchAction as (type: TouchType) => void;
    this.onOpenMenu = params.onOpenMenu as () => void;
    this.onRowClick = params.onRowClick as () => void;
    this.onMenuAppear = params.onMenuAppear as () => void;
    this.onMenuDisappear = params.onMenuDisappear as () => void;
    this.onSelectedChange = params.onSelectedChange as (selected: boolean) => void;
    this.onContextAction = params.onContextAction as (title: string) => void;
    this.onIconLoadError = params.onIconLoadError as (iconUri: string, sourceRevision: number) => void;
  }

  build() {
    WebsiteRecordRow({
      iconUri: this.iconUri,
      iconPixelMap: this.iconPixelMap,
      fallbackLabel: this.fallbackLabel,
      title: this.title,
      subtitle: this.subtitle,
      pressed: this.pressed,
      menuVisible: this.menuVisible,
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rowHeight: RECORD_LIST_ROW_HEIGHT,
      rowBorderRadius: this.rowBorderRadius,
      pressedBorderRadius: this.rowBorderRadius,
      iconSize: RECORD_LIST_ROW_FAVICON_SIZE,
      iconSlotSize: RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
      iconContentRatio: RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
      iconCornerRadiusRatio: this.iconCornerRadiusRatio,
      fallbackFontSize: RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
      preferPixelMap: this.iconPixelMap !== undefined,
      sourceRevision: this.iconSourceRevision,
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.onIconLoadError(iconUri, sourceRevision);
      },
      onTouchAction: (type: TouchType) => {
        this.onTouchAction(type);
      },
      onOpenMenu: () => {
        this.onOpenMenu();
      },
      onRowClick: () => {
        this.onRowClick();
      },
      onMenuAppear: () => {
        this.onMenuAppear();
      },
      onMenuDisappear: () => {
        this.onMenuDisappear();
      },
      trailing: () => {
        this.buildTrailing()
      },
      previewTrailing: () => {
        this.buildPreviewTrailing()
      },
      menuContent: () => {
        this.buildMenuItems()
      }
    })
  }

  @Builder
  private buildTrailing() {
    if (this.duplicateCount > 1) {
      Text(`${this.duplicateCount}`)
        .width(30)
        .height(30)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.storedControlBackgroundColor)
        .borderRadius(15)
    }

    if (this.bookmarked) {
      SymbolGlyph($r('sys.symbol.bookmark_fill'))
        .fontSize(18)
        .fontColor([this.storedSecondaryTextColor])
    }

    if (this.selectionMode) {
      Checkbox()
        .width(20)
        .height(20)
        .shape(CheckBoxShape.CIRCLE)
        .select(this.selected)
        .selectedColor(this.storedAccentColor)
        .onChange((isSelected: boolean) => {
          this.onSelectedChange(isSelected);
        })
    }
  }

  @Builder
  private buildPreviewTrailing() {
    if (this.bookmarked) {
      SymbolGlyph($r('sys.symbol.bookmark_fill'))
        .fontSize(18)
        .fontColor([this.storedSecondaryTextColor])
    }
  }

  @Builder
  private buildMenuItems() {
    ForEach(this.resolveContextActions(), (item: string) => {
      MenuItem({ content: item })
        .onClick(() => {
          this.onContextAction(item);
        })
    }, (item: string) => item)
  }

  private resolveContextActions(): string[] {
    const actions: string[] = [
      '多选',
      this.addedToHome ? '从主页移除' : '添加到主页',
      this.bookmarked ? '取消书签' : '添加书签',
      '分享',
      '复制链接',
      '详情',
      '打开',
      '新标签页打开',
      '后台打开'
    ];
    if (this.host.length > 0) {
      actions.push('删除该站点记录');
    }
    actions.push('删除');
    return actions;
  }
}
