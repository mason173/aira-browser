import { BrowserHomePageStyle } from '../../../common/models/HomePagePresentationSettingsModels';
import {
  HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY
} from '../../../common/constants/HomePagePresentationStorageKeys';
import { ShortcutRecord } from '../../../common/models/BrowserModels';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import { BrowserForegroundPresentationViewModel } from '../../../core/browser/BrowserForegroundPresentationViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_LAYOUT_DENSITY_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  isHomeSystemShortcut,
  resolveHomeSystemShortcutDefinitionByUrl
} from '../../../services/shortcuts/HomeSystemShortcutCatalog';
import { resolveHomeWallpaperRenderedMaskOpacity } from '../../../services/wallpaper/HomeWallpaperAnalysisPolicy';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
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
 */
@Component
export struct SystemHomepageLivePreview {
  private foregroundViewModel: BrowserForegroundPresentationViewModel = new BrowserForegroundPresentationViewModel();
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F4F6F8';
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

  build() {
    if (this.style === 'centered') {
      this.buildCenteredFrame()
    } else {
      this.buildClassicFrame()
    }
  }

  @Builder
  private buildClassicFrame() {
    Stack() {
      this.buildWallpaperLayer()
      Column() {
        Column({ space: this.unit(CLASSIC_SECTION_GAP) }) {
          Column() {
            if (this.storedShowFavoritesTitle) {
              this.buildSectionTitle('收藏')
            }
            this.buildClassicShortcutGrid(this.buildClassicTiles())
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          if (this.showRecentlyClosed) {
            Column() {
              if (this.storedShowRecentlyClosedTitle) {
                this.buildSectionTitle('最近关闭')
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
          top: this.unit(CLASSIC_PAGE_PADDING),
          left: this.unit(CLASSIC_PAGE_PADDING),
          right: this.unit(CLASSIC_PAGE_PADDING)
        })
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
        .clip(true)

        this.buildFloatingToolbar()
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
    Stack() {
      this.buildWallpaperLayer()
      Column() {
        Column()
          .width('100%')
          .height(this.resolveCenteredHeaderTop())
        Image($rawfile('home_centered_wordmark.svg'))
          .width(this.unit(150))
          .height(this.unit(45))
          .objectFit(ImageFit.Contain)
          .fillColor(this.resolvePrimaryText())
        this.buildOutlinedSearch('搜索或输入网址')
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
        this.buildSplitBottomBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolveContentBackground())
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .clip(true)
  }

  @Builder
  private buildWallpaperLayer() {
    Stack() {
      if (this.hasImageWallpaper()) {
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
      Text('暂无最近关闭')
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
      Text('设置')
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
        Text('搜索或输入网址')
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
      AiraIcon({
        airaIconId: 'browser.toolbar.scanQr',
        iconSize: this.unit(14),
        iconColor: this.resolvePrimaryText()
      })
    }
    .width('88%')
    .height(this.unit(36))
    .margin({ top: this.unit(18) })
    .padding({ left: this.unit(14), right: this.unit(8) })
    .border({ width: 1.5, color: this.resolvePrimaryText() })
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
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildTabBadge() {
    Text('1')
      .fontSize(this.unit(13))
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedPrimaryTextColor)
      .textAlign(TextAlign.Center)
      .width(this.unit(21))
      .height(this.unit(21))
      .borderRadius(this.unit(5))
      .border({ width: Math.max(1, this.unit(2)), color: this.storedPrimaryTextColor })
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
      iconColor: this.storedPrimaryTextColor
    })
  }

  private buildClassicTiles(): HomepagePreviewTile[] {
    return this.buildShortcutTiles();
  }

  private buildCenteredTiles(): HomepagePreviewTile[] {
    const tiles: HomepagePreviewTile[] = this.buildShortcutTiles();
    tiles.push(this.buildChromeTile('settings', '主页设置', 'browser.home.settings'));
    tiles.push(this.buildChromeTile('add', '添加', 'browser.tabs.add'));
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
        title: shortcut.title.length > 0 ? shortcut.title : '收藏',
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

  private hasImageWallpaper(): boolean {
    return this.wallpaper.kind === 'image' && this.wallpaper.imagePath.length > 0;
  }

  private resolveContentBackground(): ResourceColor {
    return this.hasImageWallpaper() ? Color.Transparent : this.storedPageBackgroundColor;
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
    const searchCenterOffset = this.unit(53 + 32 + 18);
    const liftedCenter = this.cardHeight / 2 - this.unit(36);
    return Math.max(this.unit(12), liftedCenter - searchCenterOffset);
  }

  private resolveFloatingToolbarWidth(): number {
    return Math.max(1, this.cardWidth - this.unit(16) * 2);
  }

  private unit(size: number): number {
    return Math.max(1, Math.round(size * this.cardWidth / REFERENCE_PHONE_WIDTH));
  }
}
