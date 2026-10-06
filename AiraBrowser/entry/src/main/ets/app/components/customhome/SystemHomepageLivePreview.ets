import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  BrowserHomePageStyle,
  usesCenteredHomeFrame
} from '../../../common/models/HomePagePresentationSettingsModels';
import {
  HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY,
  HOME_PAGE_PRESENTATION_HOME_LOGO_SCALE_RATIO_KEY
} from '../../../common/constants/HomePagePresentationStorageKeys';
import { BrowserHomeShortcutLayoutDensity, ShortcutRecord } from '../../../common/models/BrowserModels';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState,
  resolveHomeWallpaperAutoColor
} from '../../../common/models/WallpaperModels';
import { BrowserForegroundPresentationViewModel } from '../../../core/browser/BrowserForegroundPresentationViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_LAYOUT_DENSITY_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  isHomeSystemShortcut,
  resolveHomeSystemShortcutDefinitionByUrl
} from '../../../services/shortcuts/HomeSystemShortcutCatalog';
import { resolveHomeWallpaperRenderedMaskOpacity } from '../../../services/wallpaper/HomeWallpaperAnalysisPolicy';
import {
  HOME_LOGO_SCALE_DEFAULT_RATIO,
  resolveHomeLogoHeightVp
} from '../../../core/settings/HomeLogoSettingsPolicy';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import { HomeLogoMark } from '../browser/HomeLogoMark';
import { AiraIcon } from '../common/AiraIcon';
import {
  RECORD_LIST_ROW_CONTENT_SPACE,
  RECORD_LIST_ROW_FAVICON_SIZE,
  RECORD_LIST_ROW_FALLBACK_FONT_SIZE,
  RECORD_LIST_ROW_HEIGHT,
  RECORD_LIST_ROW_SUBTITLE_SIZE,
  RECORD_LIST_ROW_TITLE_SIZE
} from '../common/RecordListTokens';
import { WebsiteIconView } from '../common/WebsiteIconView';
import {
  applyCenteredHomeShortcutLayout,
  CENTERED_HOME_HEADER_BOTTOM_GAP,
  CENTERED_HOME_SEARCH_HEIGHT,
  CENTERED_HOME_WORDMARK_HEIGHT,
  CENTERED_HOME_WORDMARK_SEARCH_GAP,
  resolveCenteredHomeFrame,
  resolveCenteredHomeSearchFieldWidth
} from '../../../features/newtab/CenteredHomeShortcutLayoutPolicy';
import {
  HomeResponsiveLayoutState,
  HomeResponsiveLayoutViewModel
} from '../../../features/newtab/HomeResponsiveLayoutViewModel';
import {
  HomeShortcutLayoutMetrics,
  HomeShortcutLogicService
} from '../../../services/shortcuts/HomeShortcutLogicService';

const CLASSIC_COLUMNS: number = 4;
const CENTERED_COLUMNS: number = 5;
const PREVIEW_CLOSED_ROW_LIMIT: number = 2;
const REFERENCE_PHONE_WIDTH: number = 360;
const CLASSIC_PAGE_PADDING: number = 8;
const CLASSIC_SECTION_INSET: number = 10;
const CLASSIC_SECTION_TITLE_SIZE: number = 18;
const CLASSIC_SECTION_GAP: number = 14;
const CLASSIC_COMPACT_COLUMNS: number = 5;
const CLASSIC_SHORTCUT_TILE: number = 65;
const CLASSIC_COMPACT_SHORTCUT_TILE: number = 58;
const CLASSIC_SHORTCUT_TITLE_SIZE: number = 12;
const CLASSIC_SHORTCUT_TITLE_GAP: number = 4;
const CLASSIC_SHORTCUT_TITLE_BLOCK: number = 18;
const CLASSIC_SHORTCUT_ROW_GAP: number = 20;
const CLASSIC_SHORTCUT_GRID_TOP: number = 10;
const CLASSIC_SHORTCUT_GLYPH: number = 24;
const CLASSIC_SHORTCUT_FALLBACK_FONT: number = 20;
const CLASSIC_SHORTCUT_CORNER_RATIO: number = 0.3;
const CLASSIC_SETTINGS_WIDTH: number = 78;
const CLASSIC_SETTINGS_HEIGHT: number = 32;
const CLASSIC_SETTINGS_FONT: number = 13;
const DESKTOP_PREVIEW_MIN_WIDTH: number = 840;
const DESKTOP_CONTENT_INSET: number = 10;
const DESKTOP_CLOSED_ROW_LIMIT: number = 2;
const DESKTOP_SEARCH_RADIUS: number = 24;
const DESKTOP_SEARCH_BORDER: number = 2;

export interface HomepagePreviewClosedItem {
  key: string;
  title: string;
  subtitle: string;
  iconUri: string;
}

interface HomepagePreviewTile {
  key: string;
  title: string;
  iconUri: string;
  fallbackLabel: string;
  chromeIcon: AiraRenderableIconId;
  isChrome: boolean;
}

/**
 * Miniature of a built-in homepage. Icons, wallpaper, and recently closed rows
 * come from the same live homepage state, so edits on the real home show up here.
 * Classic is the favorites grid plus recently closed and the floating three-block toolbar.
 * Centered pins the wordmark and outlined search near the screen center, then packs
 * circular icons downward. That home hides the split address row, so only the bottom bar shows.
 * A large-screen card keeps only the homepage content: the shared middle rail, the real
 * column counts, and no phone bottom bar. The desktop tab strip stays outside the card.
 */
@Component
export struct SystemHomepageLivePreview {
  private foregroundViewModel: BrowserForegroundPresentationViewModel = new BrowserForegroundPresentationViewModel();
  private homeLayoutViewModel: HomeResponsiveLayoutViewModel = new HomeResponsiveLayoutViewModel();
  private shortcutLogicService: HomeShortcutLogicService = new HomeShortcutLogicService();
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F4F6F8';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(HOME_PAGE_PRESENTATION_HOME_LOGO_SCALE_RATIO_KEY)
  private storedLogoScaleRatio: number = HOME_LOGO_SCALE_DEFAULT_RATIO;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @StorageProp(BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY)
  private storedIconSizeRatio: number = 0.54;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY)
  private storedIconCornerRatio: number = 0.3;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_LAYOUT_DENSITY_KEY)
  private storedShortcutLayoutDensity: string = 'standard';
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY)
  private storedShowShortcutNames: boolean = true;
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY)
  private storedShowFavoritesTitle: boolean = true;
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY)
  private storedShowRecentlyClosedTitle: boolean = true;
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY)
  private storedShowSettingsButton: boolean = true;
  @Prop style: BrowserHomePageStyle = 'classic';
  @Prop shortcuts: ShortcutRecord[] = [];
  @Prop showShortcuts: boolean = true;
  @Prop wallpaper: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop closedItems: HomepagePreviewClosedItem[] = [];
  @Prop showRecentlyClosed: boolean = true;
  @Prop cardWidth: number = 220;
  @Prop cardHeight: number = 460;
  @Prop desktopPresentation: boolean = false;
  @Prop viewportWidth: number = 0;
  @Prop viewportHeight: number = 0;

  build() {
    if (this.usesDesktopPreview()) {
      if (usesCenteredHomeFrame(this.style)) {
        this.buildDesktopCenteredFrame()
      } else {
        this.buildDesktopClassicFrame()
      }
    } else if (usesCenteredHomeFrame(this.style)) {
      this.buildCenteredFrame()
    } else {
      this.buildClassicFrame()
    }
  }

  @Builder
  private buildDesktopClassicFrame() {
    Stack() {
      this.buildWallpaperLayer()
      Column() {
        Column({ space: this.desktopUnit(this.desktopLayout().sectionVerticalGap) }) {
          Column() {
            if (this.storedShowFavoritesTitle) {
              this.buildDesktopSectionTitle(previewText($r('app.string.homepage_preview_favorites'), '收藏'))
            }
            this.buildDesktopShortcutGrid(this.buildClassicTiles(), false)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.showRecentlyClosed) {
            Column() {
              if (this.storedShowRecentlyClosedTitle) {
                this.buildDesktopSectionTitle(previewText($r('app.string.settings_home_recently_closed'), '最近关闭'))
              }
              this.buildDesktopClosedGrid()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          if (this.storedShowSettingsButton) {
            this.buildDesktopSettingsPill()
          }
        }
        .width(this.desktopRailWidth())
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolveContentBackground())
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildDesktopCenteredFrame() {
    Stack() {
      this.buildWallpaperLayer()
      Column() {
        Column()
          .width('100%')
          .height(this.desktopCenteredHeaderTop())
        HomeLogoMark({
          heightVp: this.desktopUnit(CENTERED_HOME_WORDMARK_HEIGHT),
          maxWidthVp: this.desktopRailWidth(),
          tintColor: this.resolvePrimaryText()
        })
        this.buildDesktopSearch()
        if (this.style === 'centered') {
          Column() {
            this.buildDesktopShortcutGrid(this.buildCenteredTiles(), true)
          }
          .width(this.desktopRailWidth())
          .layoutWeight(1)
          .margin({ top: this.desktopUnit(CENTERED_HOME_HEADER_BOTTOM_GAP) })
          .alignItems(HorizontalAlign.Center)
          .clip(true)
        } else {
          Column()
            .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolveContentBackground())
      .alignItems(HorizontalAlign.Center)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildDesktopSectionTitle(title: string) {
    Row({ space: this.desktopUnit(8) }) {
      Text(title)
        .layoutWeight(1)
        .fontSize(this.desktopUnit(CLASSIC_SECTION_TITLE_SIZE))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvePrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(this.desktopUnit(CLASSIC_SECTION_TITLE_SIZE))
        .fontWeight(FontWeight.Bold)
        .fontColor([this.resolveSecondaryText()])
    }
    .width('100%')
    .padding({
      left: this.desktopUnit(DESKTOP_CONTENT_INSET),
      right: this.desktopUnit(DESKTOP_CONTENT_INSET),
      top: this.desktopUnit(8),
      bottom: this.desktopUnit(12)
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildDesktopShortcutGrid(tiles: HomepagePreviewTile[], centered: boolean) {
    Column({ space: this.desktopUnit(this.desktopMetrics().rowGap) }) {
      ForEach(this.buildRows(tiles, this.desktopMetrics().columns), (row: HomepagePreviewTile[]) => {
        Row({ space: this.desktopColumnGap() }) {
          ForEach(row, (tile: HomepagePreviewTile) => {
            this.buildDesktopTile(tile, centered)
          }, (tile: HomepagePreviewTile) => tile.key)
        }
        .width('100%')
        .justifyContent(centered && row.length < this.desktopMetrics().columns ?
          FlexAlign.Center : FlexAlign.Start)
      }, (row: HomepagePreviewTile[]) => row.length > 0 ? row[0].key : 'empty-row')
    }
    .width('100%')
    .padding({
      left: this.desktopUnit(DESKTOP_CONTENT_INSET),
      right: this.desktopUnit(DESKTOP_CONTENT_INSET)
    })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDesktopTile(tile: HomepagePreviewTile, centered: boolean) {
    Column({ space: this.storedShowShortcutNames ? this.desktopUnit(this.desktopMetrics().titleTopGap) : 0 }) {
      if (tile.isChrome) {
        Stack() {
          AiraIcon({
            airaIconId: tile.chromeIcon,
            iconSize: Math.max(1, Math.round(this.desktopTileSize() * 0.42)),
            iconColor: this.storedPrimaryTextColor
          })
        }
        .width(this.desktopTileSize())
        .height(this.desktopTileSize())
        .borderRadius(this.desktopTileSize() * (centered ? 0.5 : this.resolveClassicIconCornerRatio()))
        .backgroundColor(this.storedControlBackgroundColor)
      } else {
        WebsiteIconView({
          iconUri: tile.iconUri,
          fallbackLabel: tile.fallbackLabel,
          variant: 'compact',
          iconSize: this.desktopTileSize(),
          cornerRadiusRatio: centered ? 0.5 : this.resolveClassicIconCornerRatio(),
          contentRatio: this.resolveShortcutIconContentRatio(),
          fallbackFontSize: Math.max(1, Math.round(this.desktopTileSize() * 0.32)),
          containerBackgroundColor: this.storedControlBackgroundColor,
          textColor: this.storedPrimaryTextColor,
          hitTestMode: HitTestMode.None
        })
      }
      if (this.storedShowShortcutNames) {
        Text(tile.title)
          .fontSize(this.desktopTitleSize())
          .fontColor(centered ? this.resolveSecondaryText() : this.resolvePrimaryText())
          .height(this.desktopUnit(this.desktopMetrics().titleBlockHeight))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width(this.desktopTileSize())
      }
    }
    .width(this.desktopTileSize())
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildDesktopClosedGrid() {
    if (this.desktopClosedItems().length <= 0) {
      Text(previewText($r('app.string.custom_home_ui_system_homepage_live_preview_001'), '暂无最近关闭'))
        .width('100%')
        .fontSize(this.desktopUnit(RECORD_LIST_ROW_TITLE_SIZE))
        .fontColor(this.resolveSecondaryText())
        .maxLines(1)
        .textAlign(TextAlign.Center)
    } else {
      Column({ space: this.desktopUnit(this.desktopLayout().recentlyClosedRowGap) }) {
        ForEach(this.buildClosedRows(this.desktopClosedItems(), this.desktopLayout().recentlyClosedColumns),
          (row: HomepagePreviewClosedItem[]) => {
            Row({ space: this.desktopUnit(this.desktopLayout().recentlyClosedColumnGap) }) {
              ForEach(row, (item: HomepagePreviewClosedItem) => {
                this.buildDesktopClosedCell(item)
              }, (item: HomepagePreviewClosedItem) => `${item.key}:${item.iconUri}`)
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)
          }, (row: HomepagePreviewClosedItem[]) => row.length > 0 ? row[0].key : 'empty-closed-row')
      }
      .width('100%')
      .padding({
        left: this.desktopUnit(DESKTOP_CONTENT_INSET),
        right: this.desktopUnit(DESKTOP_CONTENT_INSET)
      })
    }
  }

  @Builder
  private buildDesktopClosedCell(item: HomepagePreviewClosedItem) {
    Row({ space: this.desktopUnit(8) }) {
      WebsiteIconView({
        iconUri: item.iconUri,
        fallbackLabel: resolveSiteIconFallbackLabel(item.title, item.subtitle),
        variant: 'compact',
        iconSize: this.desktopUnit(RECORD_LIST_ROW_FAVICON_SIZE),
        cornerRadiusRatio: this.resolveClassicIconCornerRatio(),
        contentRatio: 1,
        fallbackFontSize: this.desktopUnit(RECORD_LIST_ROW_FALLBACK_FONT_SIZE),
        containerBackgroundColor: this.storedControlBackgroundColor,
        textColor: this.storedPrimaryTextColor,
        hitTestMode: HitTestMode.None
      })
      Column({ space: this.desktopUnit(2) }) {
        Text(item.title)
          .fontSize(this.desktopUnit(RECORD_LIST_ROW_TITLE_SIZE))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolvePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.subtitle)
          .fontSize(this.desktopUnit(RECORD_LIST_ROW_SUBTITLE_SIZE))
          .fontColor(this.resolveSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width(this.desktopClosedCellWidth())
    .height(this.desktopUnit(RECORD_LIST_ROW_HEIGHT))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildDesktopSettingsPill() {
    Row() {
      Text(previewText($r('app.string.bottom_panel_action_settings'), '设置'))
        .fontSize(this.desktopUnit(CLASSIC_SETTINGS_FONT))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width(this.desktopUnit(CLASSIC_SETTINGS_WIDTH))
    .height(this.desktopUnit(CLASSIC_SETTINGS_HEIGHT))
    .borderRadius(this.desktopUnit(CLASSIC_SETTINGS_HEIGHT) / 2)
    .backgroundColor(this.storedControlBackgroundColor)
    .justifyContent(FlexAlign.Center)
    .alignSelf(ItemAlign.Center)
    .margin({ top: this.desktopUnit(2) })
  }

  @Builder
  private buildDesktopSearch() {
    Row() {
      Text(previewText($r('app.string.aira_search_card_placeholder'), '搜索或输入网址'))
        .fontSize(this.desktopUnit(16))
        .fontColor(this.resolveSecondaryText())
        .maxLines(1)
        .layoutWeight(1)
      if (this.style !== 'minimal') {
        AiraIcon({
          airaIconId: 'browser.toolbar.scanQr',
          iconSize: this.desktopUnit(20),
          iconColor: this.resolvePrimaryText()
        })
      }
    }
    .width(this.desktopSearchWidth())
    .height(this.desktopUnit(CENTERED_HOME_SEARCH_HEIGHT))
    .margin({ top: this.desktopUnit(CENTERED_HOME_WORDMARK_SEARCH_GAP) })
    .padding({ left: this.desktopUnit(18), right: this.desktopUnit(8) })
    .border({
      width: Math.max(1, this.desktopUnit(DESKTOP_SEARCH_BORDER)),
      color: this.style === 'minimal' ? this.resolveSecondaryText() : this.resolvePrimaryText()
    })
    .borderRadius(this.desktopUnit(DESKTOP_SEARCH_RADIUS))
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildClassicFrame() {
    Stack() {
      this.buildWallpaperLayer()
      Column() {
        Column({ space: this.unit(CLASSIC_SECTION_GAP) }) {
          Column() {
            if (this.storedShowFavoritesTitle) {
              this.buildSectionTitle(previewText($r('app.string.homepage_preview_favorites'), '收藏'))
            }
            this.buildClassicShortcutGrid(this.buildClassicTiles())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.showRecentlyClosed) {
            Column() {
              if (this.storedShowRecentlyClosedTitle) {
                this.buildSectionTitle(previewText($r('app.string.settings_home_recently_closed'), '最近关闭'))
              }
              this.buildRecentlyClosedRows()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          if (this.storedShowSettingsButton) {
            this.buildSettingsPill()
          }
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          top: this.unit(CLASSIC_PAGE_PADDING) + 22,
          left: this.unit(CLASSIC_PAGE_PADDING),
          right: this.unit(CLASSIC_PAGE_PADDING)
        })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .clip(true)

        if (this.style === 'search_dock') {
          this.buildDockToolbar()
        } else {
          this.buildFloatingToolbar()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolveContentBackground())
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildCenteredFrame() {
    Stack({ alignContent: Alignment.Top }) {
      this.buildWallpaperLayer()
      Column() {
        Column()
          .width('100%')
          .height(this.style === 'minimal' ?
            Math.max(this.resolveCenteredHeaderTop(), this.unit(104)) : this.resolveCenteredHeaderTop())
        HomeLogoMark({
          heightVp: this.unit(CENTERED_HOME_WORDMARK_HEIGHT),
          maxWidthVp: Math.max(1, this.cardWidth - this.unit(24)),
          tintColor: this.resolvePrimaryText()
        })
        this.buildOutlinedSearch(previewText($r('app.string.aira_search_card_placeholder'), '搜索或输入网址'))
        if (this.style === 'centered') {
          Column() {
            this.buildShortcutGrid(this.buildCenteredTiles(), CENTERED_COLUMNS, 0.5, true)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({
            left: this.unit(8),
            right: this.unit(8),
            top: this.unit(16)
          })
          .alignItems(HorizontalAlign.Start)
          .justifyContent(FlexAlign.Start)
          .clip(true)
        } else {
          Column()
            .layoutWeight(1)
        }
        this.buildSplitBottomBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolveContentBackground())
      .alignItems(HorizontalAlign.Center)

      if (this.style === 'minimal') {
        this.buildMinimalTopSearchRow()
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildMinimalTopSearchRow() {
    Row() {
      Row({ space: this.unit(6) }) {
        AiraIcon({
          airaIconId: 'browser.toolbar.search',
          iconSize: this.unit(22),
          iconColor: this.resolvePrimaryText()
        })
        Text(previewText($r('app.string.bottom_panel_action_home'), '主页'))
          .fontSize(this.unit(18))
          .fontColor(this.resolvePrimaryText())
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(VerticalAlign.Center)

      AiraIcon({
        airaIconId: 'browser.toolbar.scanQr',
        iconSize: this.unit(22),
        iconColor: this.resolvePrimaryText()
      })
    }
    .width('88%')
    .height(this.unit(52))
    .margin({ top: this.unit(16) })
    .padding({ left: this.unit(12), right: this.unit(10) })
    .borderRadius(this.unit(18))
    .alignSelf(ItemAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildWallpaperLayer() {
    Stack() {
      if (this.wallpaper.kind === 'auto') {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(resolveHomeWallpaperAutoColor(this.storedResolvedThemeMode === 'dark'))
      } else if (this.wallpaper.kind === 'solid' && this.wallpaper.solidColor.length > 0) {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.wallpaper.solidColor)
      } else if ((this.wallpaper.kind === 'image' || this.wallpaper.kind === 'video') &&
        this.wallpaper.imagePath.length > 0) {
        Image(this.wallpaper.imagePath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .backgroundColor(this.storedPageBackgroundColor)
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor('#000000')
          .opacity(resolveHomeWallpaperRenderedMaskOpacity(this.wallpaper.maskOpacity))
      } else {
        Row()
          .width('100%')
          .height('100%')
          .backgroundColor(this.storedPageBackgroundColor)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildSectionTitle(title: string) {
    Row({ space: this.unit(8) }) {
      Text(title)
        .layoutWeight(1)
        .fontSize(this.unit(CLASSIC_SECTION_TITLE_SIZE))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvePrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(this.unit(CLASSIC_SECTION_TITLE_SIZE))
        .fontWeight(FontWeight.Bold)
        .fontColor([this.resolveSecondaryText()])
    }
    .width('100%')
    .padding({
      left: this.unit(CLASSIC_SECTION_INSET),
      right: this.unit(CLASSIC_SECTION_INSET),
      top: this.unit(8),
      bottom: this.unit(12)
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildShortcutGrid(
    tiles: HomepagePreviewTile[],
    columns: number,
    cornerRatio: number,
    circles: boolean
  ) {
    Column({ space: this.unit(circles ? 10 : 8) }) {
      ForEach(this.buildRows(tiles, columns), (row: HomepagePreviewTile[]) => {
        Row() {
          ForEach(row, (tile: HomepagePreviewTile) => {
            this.buildTile(tile, columns, cornerRatio)
          }, (tile: HomepagePreviewTile) => tile.key)
        }
        .width('100%')
        .justifyContent(FlexAlign.Start)
      }, (row: HomepagePreviewTile[]) => row.length > 0 ? row[0].key : 'empty-row')
    }
    .width('100%')
  }

  @Builder
  private buildTile(tile: HomepagePreviewTile, columns: number, cornerRatio: number) {
    Column({ space: this.unit(3) }) {
      if (tile.isChrome) {
        Stack() {
          AiraIcon({
            airaIconId: tile.chromeIcon,
            iconSize: this.iconSize(columns) * 0.52,
            iconColor: this.storedPrimaryTextColor
          })
        }
        .width(this.iconSize(columns))
        .height(this.iconSize(columns))
        .borderRadius(this.iconSize(columns) * cornerRatio)
        .backgroundColor(this.storedControlBackgroundColor)
      } else {
        WebsiteIconView({
          iconUri: tile.iconUri,
          fallbackLabel: tile.fallbackLabel,
          variant: 'compact',
          iconSize: this.iconSize(columns),
          cornerRadiusRatio: cornerRatio,
          contentRatio: this.resolveShortcutIconContentRatio(),
          fallbackFontSize: this.unit(10),
          containerBackgroundColor: this.storedControlBackgroundColor,
          textColor: this.storedPrimaryTextColor,
          hitTestMode: HitTestMode.None
        })
      }
      if (this.storedShowShortcutNames) {
        Text(tile.title)
          .fontSize(this.unit(9))
          .fontColor(this.resolveSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('92%')
      }
    }
    .width(`${100 / columns}%`)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildClassicShortcutGrid(tiles: HomepagePreviewTile[]) {
    Column({ space: this.unit(CLASSIC_SHORTCUT_ROW_GAP) }) {
      ForEach(this.buildRows(tiles, this.classicColumnCount()), (row: HomepagePreviewTile[]) => {
        Row({ space: this.classicShortcutColumnGap() }) {
          ForEach(row, (tile: HomepagePreviewTile) => {
            this.buildClassicTile(tile)
          }, (tile: HomepagePreviewTile) => tile.key)
        }
        .width(tiles.length < this.classicColumnCount() ? this.classicPartialRowWidth(tiles.length) : '100%')
        .justifyContent(FlexAlign.Start)
      }, (row: HomepagePreviewTile[]) => row.length > 0 ? row[0].key : 'empty-row')
    }
    .width('100%')
    .padding({
      left: this.unit(CLASSIC_SECTION_INSET),
      right: this.unit(CLASSIC_SECTION_INSET),
      top: this.unit(CLASSIC_SHORTCUT_GRID_TOP)
    })
    .alignItems(tiles.length < this.classicColumnCount() ? HorizontalAlign.Center : HorizontalAlign.Start)
  }

  @Builder
  private buildClassicTile(tile: HomepagePreviewTile) {
    Column({ space: this.storedShowShortcutNames ? this.unit(CLASSIC_SHORTCUT_TITLE_GAP) : 0 }) {
      if (tile.isChrome) {
        Stack() {
          AiraIcon({
            airaIconId: tile.chromeIcon,
            iconSize: Math.min(this.unit(this.classicTileReference()), this.unit(CLASSIC_SHORTCUT_GLYPH)),
            iconColor: this.storedPrimaryTextColor
          })
        }
        .width(this.unit(this.classicTileReference()))
        .height(this.unit(this.classicTileReference()))
        .borderRadius(this.unit(this.classicTileReference()) * this.resolveClassicIconCornerRatio())
        .backgroundColor(this.storedControlBackgroundColor)
      } else {
        WebsiteIconView({
          iconUri: tile.iconUri,
          fallbackLabel: tile.fallbackLabel,
          variant: 'compact',
          iconSize: this.unit(this.classicTileReference()),
          cornerRadiusRatio: this.resolveClassicIconCornerRatio(),
          contentRatio: this.resolveShortcutIconContentRatio(),
          fallbackFontSize: this.unit(CLASSIC_SHORTCUT_FALLBACK_FONT),
          containerBackgroundColor: this.storedControlBackgroundColor,
          textColor: this.storedPrimaryTextColor,
          hitTestMode: HitTestMode.None
        })
      }
      if (this.storedShowShortcutNames) {
        Text(tile.title)
          .fontSize(this.unit(CLASSIC_SHORTCUT_TITLE_SIZE))
          .fontColor(this.resolvePrimaryText())
          .height(this.unit(CLASSIC_SHORTCUT_TITLE_BLOCK))
          .lineHeight(this.unit(CLASSIC_SHORTCUT_TITLE_BLOCK))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .width('100%')
      }
    }
    .width(this.unit(this.classicTileReference()))
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildRecentlyClosedRows() {
    if (this.resolveVisibleClosedItems().length <= 0) {
      Text(previewText($r('app.string.custom_home_ui_system_homepage_live_preview_001'), '暂无最近关闭'))
        .width('100%')
        .fontSize(this.unit(RECORD_LIST_ROW_TITLE_SIZE))
        .fontColor(this.resolveSecondaryText())
        .maxLines(1)
        .textAlign(TextAlign.Center)
    } else {
      Column({ space: 0 }) {
        ForEach(this.resolveVisibleClosedItems(), (item: HomepagePreviewClosedItem) => {
          this.buildRecentlyClosedRow(item)
        }, (item: HomepagePreviewClosedItem) => `${item.key}:${item.iconUri}`)
      }
      .width('100%')
      .padding({
        left: this.unit(CLASSIC_SECTION_INSET),
        right: this.unit(CLASSIC_SECTION_INSET)
      })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private buildRecentlyClosedRow(item: HomepagePreviewClosedItem) {
    Row({ space: this.unit(RECORD_LIST_ROW_CONTENT_SPACE) }) {
      WebsiteIconView({
        iconUri: item.iconUri,
        fallbackLabel: resolveSiteIconFallbackLabel(item.title, item.subtitle),
        variant: 'compact',
        iconSize: this.unit(RECORD_LIST_ROW_FAVICON_SIZE),
        cornerRadiusRatio: this.resolveClassicIconCornerRatio(),
        contentRatio: 1,
        fallbackFontSize: this.unit(RECORD_LIST_ROW_FALLBACK_FONT_SIZE),
        containerBackgroundColor: this.storedControlBackgroundColor,
        textColor: this.storedPrimaryTextColor,
        hitTestMode: HitTestMode.None
      })
      Column({ space: this.unit(4) }) {
        Text(item.title)
          .fontSize(this.unit(RECORD_LIST_ROW_TITLE_SIZE))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolvePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.subtitle)
          .fontSize(this.unit(RECORD_LIST_ROW_SUBTITLE_SIZE))
          .fontColor(this.resolveSecondaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(this.unit(RECORD_LIST_ROW_HEIGHT))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSettingsPill() {
    Row() {
      Text(previewText($r('app.string.bottom_panel_action_settings'), '设置'))
        .fontSize(this.unit(CLASSIC_SETTINGS_FONT))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width(this.unit(CLASSIC_SETTINGS_WIDTH))
    .height(this.unit(CLASSIC_SETTINGS_HEIGHT))
    .borderRadius(this.unit(CLASSIC_SETTINGS_HEIGHT) / 2)
    .backgroundColor(this.storedControlBackgroundColor)
    .justifyContent(FlexAlign.Center)
    .alignSelf(ItemAlign.Center)
    .margin({ top: this.unit(2), bottom: this.unit(14) })
  }

  @Builder
  private buildFloatingToolbar() {
    Row({ space: this.unit(4) }) {
      this.buildRoundChromeButton('browser.toolbar.back')
      Row() {
        this.buildFloatingSlotIcon('browser.toolbar.menu')
        Text(previewText($r('app.string.aira_search_card_placeholder'), '搜索或输入网址'))
          .fontSize(this.unit(15))
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        this.buildFloatingSlotIcon('browser.toolbar.refresh')
      }
      .layoutWeight(1)
      .height(this.unit(48))
      .borderRadius(this.unit(24))
      .backgroundColor(this.storedControlBackgroundColor)
      .alignItems(VerticalAlign.Center)
      this.buildRoundChromeButton('browser.toolbar.tabs')
    }
    .width(this.resolveFloatingToolbarWidth())
    .height(this.unit(48))
    .margin({ bottom: this.unit(25) })
    .alignSelf(ItemAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  /**
   * 搜索导航主页 rest toolbar: an edge-to-edge dock band with a search box on top and a fixed
   * navigation row below, instead of the classic floating capsule.
   */
  @Builder
  private buildDockToolbar() {
    Column() {
      Row() {
        AiraIcon({
          airaIconId: 'browser.toolbar.search',
          iconSize: this.unit(16),
          iconColor: this.storedSecondaryTextColor
        })
        Text(previewText($r('app.string.aira_search_card_placeholder'), '搜索或输入网址'))
          .fontSize(this.unit(13))
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
        AiraIcon({
          airaIconId: 'browser.toolbar.scanQr',
          iconSize: this.unit(16),
          iconColor: this.storedSecondaryTextColor
        })
      }
      .width('100%')
      .height(this.unit(34))
      .padding({ left: this.unit(12), right: this.unit(12) })
      .borderRadius(this.unit(17))
      .backgroundColor(this.resolveContentBackground())
      .alignItems(VerticalAlign.Center)

      Row() {
        this.buildToolbarIcon('browser.toolbar.back')
        this.buildToolbarIcon('browser.toolbar.forward')
        this.buildToolbarIcon('browser.toolbar.menu')
        this.buildTabBadge()
        this.buildToolbarIcon('browser.toolbar.home')
      }
      .width('100%')
      .height(this.unit(40))
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({
      left: this.unit(12),
      right: this.unit(12),
      top: this.unit(6),
      bottom: this.unit(8)
    })
    .backgroundColor(this.resolveSplitBarBackground())
  }

  @Builder
  private buildFloatingSlotIcon(iconId: AiraRenderableIconId) {
    Stack() {
      AiraIcon({
        airaIconId: iconId,
        iconSize: this.unit(22),
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(this.unit(40))
    .height(this.unit(48))
  }

  @Builder
  private buildOutlinedSearch(placeholder: string) {
    Row() {
      Text(placeholder)
        .fontSize(this.unit(12))
        .fontColor(this.resolveSecondaryText())
        .maxLines(1)
        .layoutWeight(1)
      if (this.style !== 'minimal') {
        AiraIcon({
          airaIconId: 'browser.toolbar.scanQr',
          iconSize: this.unit(14),
          iconColor: this.resolvePrimaryText()
        })
      }
    }
    .width('88%')
    .height(this.unit(36))
    .margin({ top: this.unit(18) })
    .padding({ left: this.unit(14), right: this.unit(8) })
    .border({
      width: 1.5,
      color: this.style === 'minimal' ? this.resolveSecondaryText() : this.resolvePrimaryText()
    })
    .borderRadius(this.unit(18))
    .backgroundColor(Color.Transparent)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSplitBottomBar() {
    Column() {
      Row() {
        this.buildToolbarIcon('browser.shortcut.bookmarks')
        this.buildToolbarIcon('browser.shortcut.history')
        this.buildTabBadge()
        this.buildToolbarIcon('browser.toolbar.menu')
      }
      .width('100%')
      .height(this.unit(56))
      .justifyContent(FlexAlign.SpaceEvenly)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(this.unit(64))
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.resolveSplitBarBackground())
  }

  @Builder
  private buildTabBadge() {
    Text('1')
      .fontSize(this.unit(13))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.resolvePrimaryText())
      .textAlign(TextAlign.Center)
      .width(this.unit(21))
      .height(this.unit(21))
      .borderRadius(this.unit(5))
      .border({ width: Math.max(1, this.unit(2)), color: this.resolvePrimaryText() })
  }

  @Builder
  private buildRoundChromeButton(iconId: AiraRenderableIconId) {
    Stack() {
      AiraIcon({
        airaIconId: iconId,
        iconSize: this.unit(22),
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(this.unit(48))
    .height(this.unit(48))
    .borderRadius(this.unit(24))
    .backgroundColor(this.storedControlBackgroundColor)
  }

  @Builder
  private buildToolbarIcon(iconId: AiraRenderableIconId) {
    AiraIcon({
      airaIconId: iconId,
      iconSize: this.unit(25),
      iconColor: this.resolvePrimaryText()
    })
  }

  private buildClassicTiles(): HomepagePreviewTile[] {
    const tiles = this.buildShortcutTiles();
    if (this.showShortcuts) {
      tiles.push(this.buildChromeTile('add', previewText($r('app.string.settings_custom_home_add'), '添加'), 'browser.tabs.add'));
    }
    return tiles;
  }

  private buildCenteredTiles(): HomepagePreviewTile[] {
    const tiles: HomepagePreviewTile[] = this.buildShortcutTiles();
    tiles.push(this.buildChromeTile('add', previewText($r('app.string.settings_custom_home_add'), '添加'), 'browser.tabs.add'));
    return tiles;
  }

  private buildShortcutTiles(): HomepagePreviewTile[] {
    if (!this.showShortcuts) {
      return [];
    }
    const tiles: HomepagePreviewTile[] = [];
    this.shortcuts.forEach((shortcut: ShortcutRecord, index: number) => {
      const systemIcon = isHomeSystemShortcut(shortcut) ?
        resolveHomeSystemShortcutDefinitionByUrl(shortcut.url)?.iconId : undefined;
      tiles.push({
        key: `${shortcut.id}:${index}:${shortcut.position}:${shortcut.icon ?? ''}:${systemIcon ?? ''}`,
        title: shortcut.title.length > 0 ? shortcut.title : previewText($r('app.string.homepage_preview_favorites'), '收藏'),
        iconUri: systemIcon === undefined ? (shortcut.icon ?? '') : '',
        fallbackLabel: this.resolveFallback(shortcut.title),
        chromeIcon: systemIcon ?? 'browser.shortcut.home',
        isChrome: systemIcon !== undefined
      });
    });
    return tiles;
  }

  private resolveVisibleClosedItems(): HomepagePreviewClosedItem[] {
    return this.closedItems.slice(0, PREVIEW_CLOSED_ROW_LIMIT);
  }

  /** A photo paints an image; a flat color and auto black/white paint themselves. */
  private hasPaintedWallpaper(): boolean {
    if (this.wallpaper.kind === 'auto') {
      return true;
    }
    if (this.wallpaper.kind === 'solid') {
      return this.wallpaper.solidColor.length > 0;
    }
    if (this.wallpaper.kind === 'video') {
      return this.wallpaper.imagePath.length > 0 || this.wallpaper.videoPath.length > 0;
    }
    return this.wallpaper.kind === 'image' && this.wallpaper.imagePath.length > 0;
  }

  private resolveContentBackground(): ResourceColor {
    return this.hasPaintedWallpaper() ? Color.Transparent : this.storedPageBackgroundColor;
  }

  /**
   * 简约 and 极简 clear the split bar over a painted wallpaper, same as the live homepage.
   * A theme-color card keeps the page fill, which already matches the content behind it.
   */
  private resolveSplitBarBackground(): ResourceColor {
    return this.hasPaintedWallpaper() ? Color.Transparent : this.storedPageBackgroundColor;
  }

  private resolvePrimaryText(): ResourceColor {
    return this.foregroundViewModel.resolveHomePresentation({
      foregroundBackdropSource: 'system_home',
      wallpaperState: this.wallpaper,
      themeBackgroundColor: this.storedPageBackgroundColor,
      themedPrimaryTextColor: this.storedPrimaryTextColor,
      themedSecondaryTextColor: this.storedSecondaryTextColor
    }).primaryTextColor;
  }

  private resolveSecondaryText(): ResourceColor {
    return this.foregroundViewModel.resolveHomePresentation({
      foregroundBackdropSource: 'system_home',
      wallpaperState: this.wallpaper,
      themeBackgroundColor: this.storedPageBackgroundColor,
      themedPrimaryTextColor: this.storedPrimaryTextColor,
      themedSecondaryTextColor: this.storedSecondaryTextColor
    }).secondaryTextColor;
  }

  private buildChromeTile(key: string, title: string, iconId: AiraRenderableIconId): HomepagePreviewTile {
    return {
      key: key,
      title: title,
      iconUri: '',
      fallbackLabel: title,
      chromeIcon: iconId,
      isChrome: true
    };
  }

  private buildRows(tiles: HomepagePreviewTile[], columns: number): HomepagePreviewTile[][] {
    const rows: HomepagePreviewTile[][] = [];
    for (let index = 0; index < tiles.length; index += columns) {
      rows.push(tiles.slice(index, index + columns));
    }
    return rows;
  }

  private resolveFallback(title: string): string {
    const trimmed = title.trim();
    return trimmed.length > 0 ? trimmed.substring(0, 1) : '#';
  }

  private iconSize(columns: number): number {
    const contentWidth = this.resolveClassicContentWidth();
    return Math.max(16, Math.round(contentWidth / columns * 0.62));
  }

  private resolveClassicContentWidth(): number {
    return Math.max(1, this.cardWidth - this.unit(24));
  }

  private classicShortcutColumnGap(): number {
    const contentWidth = Math.max(
      1,
      this.cardWidth - this.unit(CLASSIC_PAGE_PADDING) * 2 - this.unit(CLASSIC_SECTION_INSET) * 2
    );
    const columns = this.classicColumnCount();
    const leftover = contentWidth - this.unit(this.classicTileReference()) * columns;
    return Math.max(0, Math.round(leftover / Math.max(1, columns - 1)));
  }

  private classicPartialRowWidth(itemCount: number): number {
    const count = Math.max(1, Math.min(this.classicColumnCount(), itemCount));
    return this.unit(this.classicTileReference()) * count +
      this.classicShortcutColumnGap() * Math.max(0, count - 1);
  }

  private classicUsesCompactLayout(): boolean {
    return this.storedShortcutLayoutDensity === 'compact';
  }

  private classicColumnCount(): number {
    return this.classicUsesCompactLayout() ? CLASSIC_COMPACT_COLUMNS : CLASSIC_COLUMNS;
  }

  private classicTileReference(): number {
    return this.classicUsesCompactLayout() ? CLASSIC_COMPACT_SHORTCUT_TILE : CLASSIC_SHORTCUT_TILE;
  }

  private resolveShortcutIconContentRatio(): number {
    if (!Number.isFinite(this.storedIconSizeRatio)) {
      return 0.54;
    }
    return Math.max(0.45, Math.min(1, this.storedIconSizeRatio));
  }

  private resolveClassicIconCornerRatio(): number {
    if (!Number.isFinite(this.storedIconCornerRatio)) {
      return CLASSIC_SHORTCUT_CORNER_RATIO;
    }
    return Math.max(0, Math.min(0.5, this.storedIconCornerRatio));
  }

  private resolveCenteredHeaderTop(): number {
    const logoHeight = resolveHomeLogoHeightVp(
      this.unit(CENTERED_HOME_WORDMARK_HEIGHT),
      this.storedLogoScaleRatio
    );
    const searchCenterOffset = logoHeight +
      this.unit(CENTERED_HOME_WORDMARK_SEARCH_GAP) +
      this.unit(CENTERED_HOME_SEARCH_HEIGHT / 2);
    const liftedCenter = this.cardHeight / 2 - this.unit(36);
    return Math.max(this.unit(12), liftedCenter - searchCenterOffset);
  }

  private resolveFloatingToolbarWidth(): number {
    return Math.max(1, this.cardWidth - this.unit(16) * 2);
  }

  private unit(size: number): number {
    return Math.max(1, Math.round(size * this.cardWidth / REFERENCE_PHONE_WIDTH));
  }

  private usesDesktopPreview(): boolean {
    return this.desktopPresentation &&
      this.viewportWidth >= DESKTOP_PREVIEW_MIN_WIDTH &&
      this.viewportHeight > 0;
  }

  private desktopLayout(): HomeResponsiveLayoutState {
    const state = this.homeLayoutViewModel.buildState({
      shellFamily: 'large_screen',
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight
    }, this.desktopShortcutDensity());
    return usesCenteredHomeFrame(this.style) ? applyCenteredHomeShortcutLayout(state) : state;
  }

  private desktopShortcutDensity(): BrowserHomeShortcutLayoutDensity {
    return usesCenteredHomeFrame(this.style) || this.classicUsesCompactLayout() ? 'compact' : 'standard';
  }

  private desktopMetrics(): HomeShortcutLayoutMetrics {
    return this.desktopLayout().shortcutMetrics;
  }

  private desktopScale(): number {
    return this.cardWidth / Math.max(1, this.viewportWidth);
  }

  private desktopUnit(size: number): number {
    if (size <= 0) {
      return 0;
    }
    return Math.max(1, Math.round(size * this.desktopScale()));
  }

  private desktopRailWidth(): number {
    return Math.min(this.cardWidth, Math.max(1, this.desktopUnit(this.desktopLayout().shortcutGridWidth)));
  }

  private desktopGridWidthVp(): number {
    return Math.max(1, this.desktopLayout().shortcutGridWidth - DESKTOP_CONTENT_INSET * 2);
  }

  private desktopTileSize(): number {
    return Math.max(8, this.desktopUnit(
      this.shortcutLogicService.getTileSize(this.desktopGridWidthVp(), this.desktopMetrics())
    ));
  }

  private desktopColumnGap(): number {
    return this.desktopUnit(
      this.shortcutLogicService.getAlignedGridColumnGap(this.desktopGridWidthVp(), this.desktopMetrics())
    );
  }

  private desktopTitleSize(): number {
    return Math.max(1, this.desktopUnit(
      this.shortcutLogicService.getTitleFontSize(this.desktopGridWidthVp(), this.desktopMetrics())
    ));
  }

  private desktopContentWidth(): number {
    return Math.max(1, this.desktopRailWidth() - this.desktopUnit(DESKTOP_CONTENT_INSET) * 2);
  }

  private desktopClosedItems(): HomepagePreviewClosedItem[] {
    const columns = Math.max(1, this.desktopLayout().recentlyClosedColumns);
    return this.closedItems.slice(0, columns * DESKTOP_CLOSED_ROW_LIMIT);
  }

  private desktopClosedCellWidth(): number {
    const columns = Math.max(1, this.desktopLayout().recentlyClosedColumns);
    const gap = this.desktopUnit(this.desktopLayout().recentlyClosedColumnGap);
    const available = this.desktopContentWidth() - gap * Math.max(0, columns - 1);
    return Math.max(1, Math.floor(available / columns));
  }

  private desktopCenteredHeaderTop(): number {
    const frame = resolveCenteredHomeFrame({
      viewportHeight: this.viewportHeight,
      topSafeInset: 0,
      bottomChromeReserve: 0,
      logoHeightVp: resolveHomeLogoHeightVp(
        CENTERED_HOME_WORDMARK_HEIGHT,
        this.storedLogoScaleRatio
      )
    });
    return this.desktopUnit(frame.headerTop);
  }

  private desktopSearchWidth(): number {
    const fieldWidth = resolveCenteredHomeSearchFieldWidth(true, this.desktopLayout().shortcutGridWidth);
    return Math.min(this.desktopRailWidth(), Math.max(1, this.desktopUnit(fieldWidth)));
  }

  private buildClosedRows(
    items: HomepagePreviewClosedItem[],
    columns: number
  ): HomepagePreviewClosedItem[][] {
    const rows: HomepagePreviewClosedItem[][] = [];
    const width = Math.max(1, columns);
    for (let index = 0; index < items.length; index += width) {
      rows.push(items.slice(index, index + width));
    }
    return rows;
  }
}

function previewText(resource: Resource, fallback: string): string {
  const resolved = resolveAppResourceText(resource);
  return resolved.length > 0 ? resolved : fallback;
}
