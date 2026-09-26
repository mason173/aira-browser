import { BrowserHomePageStyle } from '../../../common/models/HomePagePresentationSettingsModels';
import { ShortcutRecord } from '../../../common/models/BrowserModels';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import { BrowserForegroundPresentationViewModel } from '../../../core/browser/BrowserForegroundPresentationViewModel';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
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
import { WebsiteIconView } from '../common/WebsiteIconView';

const CLASSIC_COLUMNS: number = 4;
const CENTERED_COLUMNS: number = 5;
const PREVIEW_CLOSED_ROW_LIMIT: number = 2;
const REFERENCE_PHONE_WIDTH: number = 360;

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
        Column() {
          this.buildSectionTitle('收藏')
          this.buildShortcutGrid(this.buildClassicTiles(), CLASSIC_COLUMNS, 0.28, false)
          if (this.showRecentlyClosed) {
            this.buildSectionTitle('最近关闭')
            this.buildRecentlyClosedRows()
          }
          this.buildSettingsPill()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({
          top: this.unit(28),
          left: this.unit(12),
          right: this.unit(12)
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
        .fontSize(this.unit(15))
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvePrimaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(this.unit(14))
        .fontWeight(FontWeight.Bold)
        .fontColor([this.resolveSecondaryText()])
    }
    .width('100%')
    .height(this.unit(28))
    .margin({ top: this.unit(4), bottom: this.unit(2) })
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
          fallbackFontSize: this.unit(10),
          containerBackgroundColor: this.storedControlBackgroundColor,
          textColor: this.storedPrimaryTextColor,
          hitTestMode: HitTestMode.None
        })
      }
      Text(tile.title)
        .fontSize(this.unit(9))
        .fontColor(this.resolveSecondaryText())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
        .width('92%')
    }
    .width(`${100 / columns}%`)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildRecentlyClosedRows() {
    if (this.resolveVisibleClosedItems().length <= 0) {
      Text('暂无最近关闭')
        .width('100%')
        .fontSize(this.unit(11))
        .fontColor(this.resolveSecondaryText())
        .maxLines(1)
        .textAlign(TextAlign.Center)
    } else {
      Column({ space: this.unit(8) }) {
        ForEach(this.resolveVisibleClosedItems(), (item: HomepagePreviewClosedItem) => {
          this.buildRecentlyClosedRow(item)
        }, (item: HomepagePreviewClosedItem) => `${item.key}:${item.iconUri}`)
      }
      .width('100%')
      .padding({ left: this.resolveClassicIconLeadingInset() })
      .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  private buildRecentlyClosedRow(item: HomepagePreviewClosedItem) {
    Row({ space: this.unit(8) }) {
      WebsiteIconView({
        iconUri: item.iconUri,
        fallbackLabel: resolveSiteIconFallbackLabel(item.title, item.subtitle),
        variant: 'compact',
        iconSize: this.unit(22),
        cornerRadius: this.unit(6),
        contentRatio: 1,
        fallbackFontSize: this.unit(10),
        containerBackgroundColor: this.storedControlBackgroundColor,
        textColor: this.storedPrimaryTextColor,
        hitTestMode: HitTestMode.None
      })
      Column({ space: this.unit(3) }) {
        Text(item.title)
          .fontSize(this.unit(11))
          .fontColor(this.resolvePrimaryText())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.subtitle)
          .fontSize(this.unit(9))
          .fontColor(this.resolveSecondaryText())
          .maxLines(1)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .height(this.unit(32))
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSettingsPill() {
    Row() {
      Text('设置')
        .fontSize(this.unit(11))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width(this.unit(64))
    .height(this.unit(26))
    .margin({ top: this.unit(14) })
    .borderRadius(this.unit(13))
    .backgroundColor(this.storedControlBackgroundColor)
    .justifyContent(FlexAlign.Center)
    .alignSelf(ItemAlign.Center)
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
    .margin({ bottom: this.unit(20) })
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

  private resolveClassicIconLeadingInset(): number {
    const columnWidth = this.resolveClassicContentWidth() / CLASSIC_COLUMNS;
    return Math.max(0, Math.round((columnWidth - this.iconSize(CLASSIC_COLUMNS)) / 2));
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
