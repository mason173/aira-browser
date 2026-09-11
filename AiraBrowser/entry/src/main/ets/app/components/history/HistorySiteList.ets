import { image } from '@kit.ImageKit';
import { HistorySiteGroup } from '../../../features/history/HistoryViewModel';
import { HistorySiteListDataSource } from '../../../features/history/HistorySiteListDataSource';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  RECORD_LIST_CARD_RADIUS,
  RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
  RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
  RECORD_LIST_ROW_HORIZONTAL_INSET
} from '../common/RecordListTokens';
import { WebsiteRecordRow } from '../common/WebsiteRecordRow';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SiteIconListRenderState,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';

const HISTORY_SITE_LIST_CACHE_COUNT: number = 8;
const HISTORY_SITE_LIST_GROUP_PADDING: number = 4;
const HISTORY_SITE_LIST_TOP_BLUR_RADIUS: number = 20;
const HISTORY_SITE_ROW_HEIGHT: number = 68;

@Component
export struct HistorySiteList {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  dataSource: HistorySiteListDataSource = new HistorySiteListDataSource();
  listScroller: Scroller = new Scroller();
  @Prop icons: SiteIconListRenderState[] = [];
  @Prop selectedSiteKeys: string[] = [];
  @Prop isSelectionMode: boolean = false;
  @Prop contentStartOffset: number = 4;
  @State private pressedSiteKey: string = '';
  @State private contextMenuSiteKey: string = '';
  private iconLookupSource: SiteIconListRenderState[] = [];
  private iconLookup: Record<string, SiteIconListRenderState | undefined> = {};
  private selectedSiteKeyLookupSource: string[] = [];
  private selectedSiteKeyLookup: Record<string, boolean> = {};
  onOpenSite: (site: HistorySiteGroup) => void = (_site: HistorySiteGroup) => {};
  onDeleteSite: (site: HistorySiteGroup) => void = (_site: HistorySiteGroup) => {};
  onToggleSiteSelection: (siteKey: string) => void = (_siteKey: string) => {};
  onSetSiteSelected: (siteKey: string, selected: boolean) => void = (_siteKey: string, _selected: boolean) => {};
  onIconLoadError: (
    target: SiteIconListTarget,
    currentUri: string,
    sourceRevision: number
  ) => void = (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number) => {};
  onScrollVisibleRange: (start: number, end: number) => void = (_start: number, _end: number) => {};
  onScrollOffsetChange: (offset: number) => void = (_offset: number) => {};

  build() {
    List({ scroller: this.listScroller, space: 0 }) {
      LazyForEach(this.dataSource, (site: HistorySiteGroup, index: number) => {
        ListItem() {
          this.buildSiteCardRow(site, index)
        }
        .width('100%')
        .reuseId('history_site_row')
      }, (site: HistorySiteGroup) => site.key)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, bottom: 4 })
    .contentStartOffset(this.contentStartOffset)
    .linearGradientBlur(HISTORY_SITE_LIST_TOP_BLUR_RADIUS, {
      fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
      direction: GradientDirection.Bottom
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
    .cachedCount(HISTORY_SITE_LIST_CACHE_COUNT)
    .onScrollIndex((start: number, end: number) => {
      this.onScrollVisibleRange(start, end);
    })
    .onDidScroll((_scrollDelta: number, _scrollState: ScrollState) => {
      this.onScrollOffsetChange(this.listScroller.currentOffset().yOffset);
    })
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }

  @Builder
  private buildSiteCardRow(site: HistorySiteGroup, index: number) {
    Column() {
      this.buildSiteRow(site)
    }
    .width('100%')
    .padding({
      left: HISTORY_SITE_LIST_GROUP_PADDING,
      right: HISTORY_SITE_LIST_GROUP_PADDING,
      top: index === 0 ? HISTORY_SITE_LIST_GROUP_PADDING : 0,
      bottom: index >= this.dataSource.totalCount() - 1 ? HISTORY_SITE_LIST_GROUP_PADDING : 0
    })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.resolveSiteCardRadius(index))
    .clip(true)
  }

  @Builder
  private buildSiteRow(site: HistorySiteGroup) {
    HistorySiteRecordRow({
      iconUri: this.getIconPathById(site.key),
      iconPixelMap: this.getIconPixelMap(site.key),
      fallbackLabel: resolveSiteIconFallbackLabel(site.title, site.host),
      title: site.host,
      subtitle: `${site.visitCount} 次访问 · ${site.uniqueUrlCount} 个页面 · 最近 ${site.latestTitle}`,
      pressed: this.pressedSiteKey === site.key,
      menuVisible: !this.isSelectionMode && this.contextMenuSiteKey === site.key,
      selected: this.isSiteSelected(site.key),
      selectionMode: this.isSelectionMode,
      iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      sourceRevision: this.getIconSourceRevision(site.key),
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.onIconLoadError({
          id: site.key,
          url: site.latestUrl,
          domain: site.host
        }, iconUri, sourceRevision);
      },
      onTouchAction: (type: TouchType) => {
        this.updatePressedSite(site.key, type);
      },
      onOpenMenu: () => {
        this.openContextMenu(site.key);
      },
      onRowClick: () => {
        if (this.isSelectionMode) {
          this.onToggleSiteSelection(site.key);
          return;
        }
        this.onOpenSite(site);
      },
      onMenuDisappear: () => {
        this.contextMenuSiteKey = '';
      },
      onSelectedChange: (selected: boolean) => {
        this.onSetSiteSelected(site.key, selected);
      },
      onOpenSite: () => {
        this.onOpenSite(site);
      },
      onDeleteSite: () => {
        this.onDeleteSite(site);
      }
    })
      .reuseId('history_site_record_row')
  }

  private resolveSiteCardRadius(index: number): BorderRadiuses {
    return {
      topLeft: index === 0 ? RECORD_LIST_CARD_RADIUS : 0,
      topRight: index === 0 ? RECORD_LIST_CARD_RADIUS : 0,
      bottomLeft: index >= this.dataSource.totalCount() - 1 ? RECORD_LIST_CARD_RADIUS : 0,
      bottomRight: index >= this.dataSource.totalCount() - 1 ? RECORD_LIST_CARD_RADIUS : 0
    };
  }

  private updatePressedSite(siteKey: string, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedSiteKey = siteKey;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedSiteKey = '';
    }
  }

  private openContextMenu(siteKey: string): void {
    if (this.isSelectionMode) {
      return;
    }
    this.pressedSiteKey = '';
    this.contextMenuSiteKey = siteKey;
  }

  private isSiteSelected(siteKey: string): boolean {
    return this.getSelectedSiteKeyLookup()[siteKey] === true;
  }

  private getIconPathById(siteKey: string): string {
    return this.getIconState(siteKey)?.path ?? '';
  }

  private getIconPixelMap(siteKey: string): image.PixelMap | undefined {
    return this.getIconState(siteKey)?.pixelMap;
  }

  private getIconSourceRevision(siteKey: string): number {
    return this.getIconState(siteKey)?.sourceRevision ?? 0;
  }

  private getIconState(siteKey: string): SiteIconListRenderState | undefined {
    if (this.iconLookupSource !== this.icons) {
      this.iconLookupSource = this.icons;
      this.iconLookup = this.buildIconLookup(this.icons);
    }
    return this.iconLookup[siteKey];
  }

  private getSelectedSiteKeyLookup(): Record<string, boolean> {
    if (this.selectedSiteKeyLookupSource !== this.selectedSiteKeys) {
      this.selectedSiteKeyLookupSource = this.selectedSiteKeys;
      this.selectedSiteKeyLookup = this.buildIdLookup(this.selectedSiteKeys);
    }
    return this.selectedSiteKeyLookup;
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
struct HistorySiteRecordRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop iconUri: string = '';
  @Prop iconPixelMap: image.PixelMap | undefined = undefined;
  @Prop fallbackLabel: string = '#';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop pressed: boolean = false;
  @Prop menuVisible: boolean = false;
  @Prop selected: boolean = false;
  @Prop selectionMode: boolean = false;
  @Prop iconCornerRadiusRatio: number = 0.3;
  @Prop sourceRevision: number = 0;
  onTouchAction: (type: TouchType) => void = (_type: TouchType) => {};
  onOpenMenu: () => void = () => {};
  onRowClick: () => void = () => {};
  onMenuDisappear: () => void = () => {};
  onSelectedChange: (selected: boolean) => void = (_selected: boolean) => {};
  onOpenSite: () => void = () => {};
  onDeleteSite: () => void = () => {};
  onIconLoadError: (iconUri: string, sourceRevision: number) => void =
    (_iconUri: string, _sourceRevision: number) => {};

  aboutToReuse(params: Record<string, Object>): void {
    this.iconUri = params.iconUri as string;
    this.iconPixelMap = params.iconPixelMap as image.PixelMap | undefined;
    this.fallbackLabel = params.fallbackLabel as string;
    this.title = params.title as string;
    this.subtitle = params.subtitle as string;
    this.pressed = params.pressed as boolean;
    this.menuVisible = params.menuVisible as boolean;
    this.selected = params.selected as boolean;
    this.selectionMode = params.selectionMode as boolean;
    this.iconCornerRadiusRatio = params.iconCornerRadiusRatio as number;
    this.sourceRevision = params.sourceRevision as number;
    this.onTouchAction = params.onTouchAction as (type: TouchType) => void;
    this.onOpenMenu = params.onOpenMenu as () => void;
    this.onRowClick = params.onRowClick as () => void;
    this.onMenuDisappear = params.onMenuDisappear as () => void;
    this.onSelectedChange = params.onSelectedChange as (selected: boolean) => void;
    this.onOpenSite = params.onOpenSite as () => void;
    this.onDeleteSite = params.onDeleteSite as () => void;
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
      rowHeight: HISTORY_SITE_ROW_HEIGHT,
      leftInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      rightInset: RECORD_LIST_ROW_HORIZONTAL_INSET,
      iconSize: RECORD_LIST_ROW_FAVICON_SIZE,
      iconSlotSize: RECORD_LIST_ROW_FAVICON_SLOT_SIZE,
      iconContentRatio: RECORD_LIST_ROW_FAVICON_CONTENT_RATIO,
      iconCornerRadiusRatio: this.iconCornerRadiusRatio,
      fallbackFontSize: RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
      preferPixelMap: this.iconPixelMap !== undefined,
      sourceRevision: this.sourceRevision,
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
      onMenuDisappear: () => {
        this.onMenuDisappear();
      },
      trailing: () => {
        this.buildTrailing()
      },
      menuContent: () => {
        this.buildMenuItems()
      }
    })
  }

  @Builder
  private buildTrailing() {
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
    } else {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.storedSecondaryTextColor])
    }
  }

  @Builder
  private buildMenuItems() {
    MenuItem({ content: '查看记录' })
      .onClick(() => {
        this.onOpenSite();
      })

    MenuItem({ content: '删除该站点记录' })
      .onClick(() => {
        this.onDeleteSite();
      })
  }
}
