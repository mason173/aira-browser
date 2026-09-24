import { image } from '@kit.ImageKit';
import { HistorySiteGroup } from '../../../features/history/HistoryViewModel';
import { SiteIconListRenderState, SiteIconListTarget } from '../../../core/siteicons/SiteIconListPresenter';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { WebsiteIconView } from '../common/WebsiteIconView';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem,
  buildBrowserDesktopMenuOptions
} from '../browser/BrowserDesktopContextMenu';
import { BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP } from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  RECORD_LIST_ROW_SUBTITLE_SIZE,
  RECORD_LIST_ROW_TITLE_SIZE
} from '../common/RecordListTokens';
import {
  MANAGEMENT_LARGE_SCREEN_ROW_GAP,
  MANAGEMENT_LARGE_SCREEN_ROW_INSET,
  MANAGEMENT_LARGE_SCREEN_ROW_RADIUS
} from '../common/ManagementLargeScreenShell';

const HISTORY_SITE_ROW_HEIGHT: number = 52;

@Component
export struct HistoryLargeScreenSites {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY)
  private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;

  @Prop sites: HistorySiteGroup[] = [];
  @Prop icons: SiteIconListRenderState[] = [];
  listScroller: ListScroller = new ListScroller();
  @State private hoveredSiteKey: string = '';
  onOpenSite: (site: HistorySiteGroup) => void = (_site: HistorySiteGroup): void => {};
  onOpenLatest: (site: HistorySiteGroup, openInNewTab: boolean) => void =
    (_site: HistorySiteGroup, _openInNewTab: boolean): void => {};
  onCopyLink: (site: HistorySiteGroup) => void = (_site: HistorySiteGroup): void => {};
  onDeleteSite: (site: HistorySiteGroup) => void = (_site: HistorySiteGroup): void => {};
  onReachEnd: () => void = (): void => {};
  onIconLoadError: (target: SiteIconListTarget, currentUri: string, sourceRevision: number) => void =
    (_target: SiteIconListTarget, _currentUri: string, _sourceRevision: number): void => {};

  build() {
    List({ scroller: this.listScroller, space: MANAGEMENT_LARGE_SCREEN_ROW_GAP }) {
      ForEach(this.sites, (site: HistorySiteGroup) => {
        ListItem() {
          this.buildSiteRow(site)
        }
        .width('100%')
      }, (site: HistorySiteGroup): string => site.key)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
      right: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
      top: 8,
      bottom: MANAGEMENT_LARGE_SCREEN_ROW_INSET
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
    .scrollBar(BarState.Auto)
    .cachedCount(8)
    .onReachEnd((): void => this.onReachEnd())
  }

  @Builder
  private buildSiteRow(site: HistorySiteGroup) {
    Column() {
      Row({ space: 12 }) {
        WebsiteIconView({
          iconUri: this.getIconState(site.key)?.path ?? '',
          iconPixelMap: this.getIconPixelMap(site.key),
          fallbackLabel: resolveSiteIconFallbackLabel(site.title, site.host),
          variant: 'list',
          iconSize: 30,
          contentRatio: 1,
          cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
          preferPixelMap: this.getIconPixelMap(site.key) !== undefined,
          sourceRevision: this.getIconState(site.key)?.sourceRevision ?? 0,
          containerBackgroundColor: this.storedControlBackgroundColor,
          frameBorderColor: this.storedDividerColor,
          textColor: this.storedPrimaryTextColor,
          onIconLoadError: (iconUri: string, sourceRevision: number): void => {
            this.onIconLoadError({ id: site.key, url: site.latestUrl, domain: site.host }, iconUri, sourceRevision);
          }
        })

        Column({ space: 3 }) {
          Text(site.host)
            .width('100%')
            .fontSize(RECORD_LIST_ROW_TITLE_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${site.visitCount} 次访问 · ${site.uniqueUrlCount} 个页面 · 最近 ${site.latestTitle}`)
            .width('100%')
            .fontSize(RECORD_LIST_ROW_SUBTITLE_SIZE)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

      }
      .width('100%')
      .height(HISTORY_SITE_ROW_HEIGHT)
      .padding({
        left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
        right: MANAGEMENT_LARGE_SCREEN_ROW_INSET
      })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.hoveredSiteKey === site.key
        ? this.storedPageBackgroundColor
        : this.storedSurfaceBackgroundColor)
      .borderRadius(MANAGEMENT_LARGE_SCREEN_ROW_RADIUS)
      .clip(true)
      .onHover((hovered: boolean): void => {
        this.hoveredSiteKey = hovered ? site.key : '';
      })
      .onClick((): void => this.onOpenSite(site))
      .bindContextMenu(this.buildSiteContextMenu(site), ResponseType.RightClick, buildBrowserDesktopMenuOptions())
    }
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
  }

  @Builder
  private buildSiteContextMenu(site: HistorySiteGroup) {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP }) {
      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
          label: '查看此站点的记录',
          onAction: (): void => this.onOpenSite(site)
        })
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
          label: '打开最近访问页面',
          onAction: (): void => this.onOpenLatest(site, false)
        })
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
          label: '在新标签页中打开最近访问页面',
          onAction: (): void => this.onOpenLatest(site, true)
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
          label: '复制最近访问链接',
          onAction: (): void => this.onCopyLink(site)
        })
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP,
          label: '删除此站点的历史记录',
          onAction: (): void => this.onDeleteSite(site)
        })
      }
    }
  }

  private getIconState(siteKey: string): SiteIconListRenderState | undefined {
    return this.icons.find((item: SiteIconListRenderState): boolean => item.id === siteKey);
  }

  private getIconPixelMap(siteKey: string): image.PixelMap | undefined {
    return this.getIconState(siteKey)?.pixelMap;
  }
}
