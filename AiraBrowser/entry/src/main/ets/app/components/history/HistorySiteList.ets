import { image } from '@kit.ImageKit';
import { HistorySiteGroup } from '../../../features/history/HistoryViewModel';
import { HistorySiteListDataSource } from '../../../features/history/HistorySiteListDataSource';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import { RECORD_LIST_CARD_RADIUS } from '../common/RecordListTokens';
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

@Component
export struct HistorySiteList {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
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
    WebsiteRecordRow({
      iconUri: this.getIconPathById(site.key),
      iconPixelMap: this.getIconPixelMap(site.key),
      fallbackLabel: resolveSiteIconFallbackLabel(site.title, site.host),
      title: site.host,
      subtitle: `${site.visitCount} 次访问 · ${site.uniqueUrlCount} 个页面 · 最近 ${site.latestTitle}`,
      pressed: this.pressedSiteKey === site.key,
      menuVisible: !this.isSelectionMode && this.contextMenuSiteKey === site.key,
      rowHeight: 68,
      iconCornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
      preferPixelMap: this.getIconPixelMap(site.key) !== undefined,
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
      trailing: () => {
        this.buildTrailing(site)
      },
      menuContent: () => {
        this.buildMenuItems(site)
      }
    })
  }

  private resolveSiteCardRadius(index: number): BorderRadiuses {
    return {
      topLeft: index === 0 ? RECORD_LIST_CARD_RADIUS : 0,
      topRight: index === 0 ? RECORD_LIST_CARD_RADIUS : 0,
      bottomLeft: index >= this.dataSource.totalCount() - 1 ? RECORD_LIST_CARD_RADIUS : 0,
      bottomRight: index >= this.dataSource.totalCount() - 1 ? RECORD_LIST_CARD_RADIUS : 0
    };
  }

  @Builder
  private buildTrailing(site: HistorySiteGroup) {
    if (this.isSelectionMode) {
      Checkbox()
        .select(this.isSiteSelected(site.key))
        .selectedColor(this.storedAccentColor)
        .onChange((isSelected: boolean) => {
          this.onSetSiteSelected(site.key, isSelected);
        })
    } else {
      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.storedSecondaryTextColor])
    }
  }

  @Builder
  private buildMenuItems(site: HistorySiteGroup) {
    MenuItem({ content: '查看记录' })
      .onClick(() => {
        this.onOpenSite(site);
      })

    MenuItem({ content: '删除该站点记录' })
      .onClick(() => {
        this.onDeleteSite(site);
      })
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
