import { image } from '@kit.ImageKit';
import { ShortcutRecord } from '../../../common/models/BrowserModels';
import {
  HomeShortcutLayoutMetrics,
  HomeShortcutMoveRequest
} from '../../../services/shortcuts/HomeShortcutLogicService';
import {
  HomeShortcutContextAction,
  HomeShortcutContextActionId,
  HomeShortcutIconState,
  HomeShortcutUserAction
} from '../../../features/newtab/HomeShortcutTypes';
import { HomeShortcutInteractionFeedbackService } from '../../../features/newtab/HomeShortcutInteractionFeedbackService';
import { HomeShortcutViewModel } from '../../../features/newtab/HomeShortcutViewModel';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  isHomeSystemShortcut,
  resolveHomeSystemShortcutDefinitionByUrl
} from '../../../services/shortcuts/HomeSystemShortcutCatalog';
import {
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveBrowserOperationalIconColor } from '../../../core/theme/BrowserOperationalIconTheme';
import { AppEmptyState } from '../common/AppEmptyState';
import { WebsiteIconView } from '../common/WebsiteIconView';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';
import { HOME_WALLPAPER_APPEARANCE_TRANSITION_MS } from '../../../core/wallpaper/HomeWallpaperPresentationTokens';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserHomeShortcutMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';
import { AiraIcon } from '../common/AiraIcon';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY } from
  '../../../common/constants/HomePagePresentationStorageKeys';
import { HOME_CONTEXT_MENU_RADIUS } from '../../../features/newtab/HomeContextMenuTokens';
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem } from './BrowserDesktopContextMenu';

const HOME_SHORTCUT_ICON_BORDER_WIDTH: number = 0;
const HOME_FIXED_SHORTCUT_ICON_SIZE_VP: number = 24;
const HOME_SHORTCUT_MIN_INTERACTION_WIDTH_VP: number = 48;
const HOME_SHORTCUT_MIN_GLYPH_SIZE_VP: number = 18;
const HOME_SHORTCUT_MIN_FALLBACK_FONT_SIZE_VP: number = 16;
const HOME_SHORTCUT_CONTEXT_MENU_DISMISS_DELAY_MS: number = 240;
const HOME_SHORTCUT_PRESSED_SCALE: number = 0.92;
const HOME_SHORTCUT_PRESSED_OPACITY: number = 0.84;
const HOME_SHORTCUT_CONTEXT_MENU_LONG_PRESS_DURATION_MS: number = 450;
const HOME_SHORTCUT_PRESS_DURATION_MS: number = 90;
const HOME_SHORTCUT_RELEASE_DURATION_MS: number = 320;

@Component
export struct HomeShortcutSurface {
  @StorageProp(HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY)
  private storedShowShortcutNames: boolean = true;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY)
  private storedHomeShortcutIconSizeRatio: number = 0.54;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY) private storedSiteIconCornerRadiusRatio: number = 0.3;
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string =
    DEFAULT_THEME_PALETTE.light.outline;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop
  @Watch('syncLiveShortcutsFromExternalOrder')
  shortcuts: ShortcutRecord[] = [];
  @Prop
  @Watch('syncLiveShortcutsFromExternalOrder')
  shortcutOrderSignature: string = '';
  @Prop icons: HomeShortcutIconState[] = [];
  @Prop iconsVersion: number = 0;
  @Prop contentOffsetY: number = 0;
  @Prop contentInset: number = 0;
  // Wallpaper-adaptive text colors are for Home labels only; operational icon glyphs use the theme-bound resolver below.
  @Prop primaryTextColor: ResourceColor = '#111318';
  @Prop secondaryTextColor: ResourceColor = '#5F6875';
  @Prop textShadow: Array<ShadowOptions> = [];
  @Prop metrics: HomeShortcutLayoutMetrics = {
    columns: 4,
    rowGap: 0,
    columnGap: 0,
    targetTileSize: 54,
    minimumTileSize: 41,
    fallbackColumnWidth: 88,
    titleTopGap: 2,
    titleBlockHeight: 18
  };
  @Prop gridWidth: number = 0;
  @Prop showAddEntry: boolean = false;
  @Prop alignPartialRowsToStart: boolean = false;
  @Link contextMenuShortcutId: string;
  @Link shortcutDragActive: boolean;

  private viewModel: HomeShortcutViewModel = new HomeShortcutViewModel();
  @State
  private pressedShortcutId: string = '';
  @State
  private addEntryPressed: boolean = false;
  @State
  private liveShortcuts: ShortcutRecord[] = [];
  private frozenIconsVersion: number = -1;
  private dragConsumedShortcutId: string = '';

  onAction: (action: HomeShortcutUserAction) => void = (_action: HomeShortcutUserAction) => {};
  onOpenAddEntry: () => void = () => {};
  onOpenHomeSettings: () => void = () => {};

  aboutToAppear(): void {
    this.syncLiveShortcutsFromExternalOrder();
  }

  aboutToReuse(_params: Record<string, Object>): void {
    this.syncLiveShortcutsFromExternalOrder();
  }

  aboutToDisappear(): void {
    this.resetShortcutInteractionState();
  }

  build() {
    Column() {
      if (this.liveShortcuts.length > 0 || this.showAddEntry) {
        List({ space: this.metrics.rowGap }) {
          ForEach(this.liveShortcuts, (shortcut: ShortcutRecord) => {
            ListItem() {
              Row() {
                ForEach([this.resolveShortcutContentRenderKey()], (_renderKey: string) => {
                  this.buildShortcutCard(shortcut)
                }, (renderKey: string) => `${shortcut.id}|${renderKey}`)
              }
              .width('100%')
              .height(this.resolveShortcutRowHeight())
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
            }
            .height(this.resolveShortcutRowHeight())
            .parallelGesture(
              GestureGroup(
                GestureMode.Sequence,
                LongPressGesture({
                  fingers: 1,
                  repeat: false,
                  duration: HOME_SHORTCUT_CONTEXT_MENU_LONG_PRESS_DURATION_MS
                })
                  .onAction(() => {
                    this.openShortcutContextMenu(shortcut.id);
                  }),
                PanGesture()
                  .onActionStart(() => {
                    this.closeShortcutContextMenuForPan(shortcut.id);
                })
              )
            )
            .bindContextMenu(this.buildDesktopShortcutContextMenu(shortcut), ResponseType.RightClick, {
              onAppear: () => {
                this.contextMenuShortcutId = '';
                this.pressedShortcutId = shortcut.id;
              },
              onDisappear: () => {
                if (this.pressedShortcutId === shortcut.id) {
                  this.pressedShortcutId = '';
                }
              }
            })
          }, (shortcut: ShortcutRecord) => shortcut.id)
            .onMove((from: number, to: number) => {
              this.commitNativeMove(from, to);
            }, {
              onDragStart: (index: number) => {
                this.beginNativeDrag(index);
              },
              onDrop: (_index: number) => {
                this.endNativeDrag();
              }
            })

          if (this.showAddEntry) {
            ListItem() {
              Row() {
                this.buildAddEntryCard()
              }
              .width('100%')
              .height(this.resolveShortcutRowHeight())
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
            }
            .height(this.resolveShortcutRowHeight())
          }
        }
        .width(this.resolveShortcutListWidth())
        .height(this.getGridContentHeight())
        .lanes(this.resolveShortcutLaneCount(), this.resolveShortcutColumnGap())
        .scrollBar(BarState.Off)
        .clip(false)
        .responseRegion({
          x: -this.contentInset,
          y: 0,
          width: Math.max(1, this.resolveShortcutListWidth() + this.contentInset * 2),
          height: this.getGridContentHeight()
        })
        .translate({ y: this.contentOffsetY })
      } else {
        AppEmptyState({
          showIcon: false,
          title: '暂无收藏',
          message: '',
          topPadding: 18,
          bottomPadding: 34,
          horizontalPadding: 10,
          primaryTextColor: this.resolvePrimaryTextColor(),
          secondaryTextColor: this.resolveSecondaryTextColor(),
          textShadow: this.textShadow,
          foregroundTransitionDurationMs: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS
        })
      }
    }
    .width('100%')
    .alignItems(
      this.alignPartialRowsToStart && (this.liveShortcuts.length > 0 || this.showAddEntry)
        ? HorizontalAlign.Start
        : HorizontalAlign.Center
    )
    .padding({ left: this.contentInset, right: this.contentInset })
  }

  @Builder
  private buildShortcutCard(shortcut: ShortcutRecord) {
    Column({ space: this.storedShowShortcutNames ? this.metrics.titleTopGap : 0 }) {
      this.buildShortcutIcon(shortcut)

      if (this.storedShowShortcutNames) {
        Text(this.resolveShortcutDisplayTitle(shortcut))
          .width('100%')
          .height(this.metrics.titleBlockHeight)
          .fontSize(this.viewModel.getShortcutTitleFontSize(this.gridWidth, this.metrics))
          .lineHeight(Math.max(18, this.metrics.titleBlockHeight))
          .fontColor(this.resolvePrimaryTextColor())
          .textShadow(this.textShadow)
          .animation({ duration: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS, curve: Curve.EaseInOut })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
    }
    .width(this.resolveShortcutCardWidth())
    .height(this.resolveShortcutCardHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .scale({
      x: this.pressedShortcutId === shortcut.id ? HOME_SHORTCUT_PRESSED_SCALE : 1,
      y: this.pressedShortcutId === shortcut.id ? HOME_SHORTCUT_PRESSED_SCALE : 1
    })
    .opacity(this.pressedShortcutId === shortcut.id ? HOME_SHORTCUT_PRESSED_OPACITY : 1)
    .animation({
      duration: this.pressedShortcutId === shortcut.id ? HOME_SHORTCUT_PRESS_DURATION_MS :
      HOME_SHORTCUT_RELEASE_DURATION_MS,
      curve: this.pressedShortcutId === shortcut.id ? Curve.EaseOut : 'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressedShortcut(shortcut.id, event.type);
    })
    .onClick(() => {
      this.handleShortcutClick(shortcut);
    })
    .bindContextMenu(this.contextMenuShortcutId === shortcut.id, this.buildTouchShortcutContextMenu(shortcut), {
      preview: this.buildShortcutContextPreview(shortcut),
      previewBorderRadius: 22,
      onDisappear: () => {
        if (this.contextMenuShortcutId === shortcut.id) {
          this.contextMenuShortcutId = '';
        }
        if (this.pressedShortcutId === shortcut.id) {
          this.pressedShortcutId = '';
        }
      }
    })
  }

  @Builder
  private buildShortcutIcon(shortcut: ShortcutRecord) {
    if (isHomeSystemShortcut(shortcut)) {
      this.buildOwnedShortcutIcon(
        this.resolveSystemShortcutIcon(shortcut),
        this.resolveShortcutContainerSize(),
        this.resolveShortcutGlyphSize(this.resolveShortcutContainerSize())
      )
    } else {
      this.buildShortcutSiteIcon(
        shortcut,
        this.resolveShortcutContainerSize(),
        this.resolveShortcutFallbackFontSize(this.resolveShortcutContainerSize())
      )
    }
  }

  @Builder
  private buildOwnedShortcutIcon(iconId: AiraRenderableIconId, size: number, iconSize: number) {
    BrowserFloatingGlassMaterialSurface({
      surfaceWidth: size,
      surfaceHeight: size,
      surfaceRadius: this.resolveShortcutMaterialRadius(size),
      tintColor: resolveBrowserHomeShortcutMaterialTintForMode(this.storedResolvedThemeMode),
      materialBorderWidth: HOME_SHORTCUT_ICON_BORDER_WIDTH,
      materialBorderColor: this.storedOutlineColor
    }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: Math.max(1, Math.min(size, iconSize)),
        iconColor: this.resolveOperationalIconColor()
      })
    }
  }

  @Builder
  private buildAddEntryCard() {
    Column({ space: this.storedShowShortcutNames ? this.metrics.titleTopGap : 0 }) {
      this.buildAddEntryIcon(
        'browser.tabs.add',
        this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics),
        this.resolveShortcutGlyphSize(this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics))
      )

      if (this.storedShowShortcutNames) {
        Text('添加')
          .width('100%')
          .height(this.metrics.titleBlockHeight)
          .fontSize(this.viewModel.getShortcutTitleFontSize(this.gridWidth, this.metrics))
          .lineHeight(Math.max(18, this.metrics.titleBlockHeight))
          .fontColor(this.resolvePrimaryTextColor())
          .textShadow(this.textShadow)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
    }
    .width(Math.max(
      this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics),
      HOME_SHORTCUT_MIN_INTERACTION_WIDTH_VP,
      this.metrics.minimumTileSize
    ))
    .height(this.resolveShortcutRowHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .scale({
      x: this.addEntryPressed ? HOME_SHORTCUT_PRESSED_SCALE : 1,
      y: this.addEntryPressed ? HOME_SHORTCUT_PRESSED_SCALE : 1
    })
    .opacity(this.addEntryPressed ? HOME_SHORTCUT_PRESSED_OPACITY : 1)
    .animation({
      duration: this.addEntryPressed ? HOME_SHORTCUT_PRESS_DURATION_MS : HOME_SHORTCUT_RELEASE_DURATION_MS,
      curve: this.addEntryPressed ? Curve.EaseOut : 'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updateAddEntryPressed(event.type);
    })
    .onClick(() => {
      if (!this.shortcutDragActive && this.contextMenuShortcutId.length <= 0) {
        this.onOpenAddEntry();
      }
    })
  }

  @Builder
  private buildAddEntryIcon(iconId: AiraRenderableIconId, size: number, iconSize: number) {
    BrowserFloatingGlassMaterialSurface({
      surfaceWidth: size,
      surfaceHeight: size,
      surfaceRadius: this.resolveShortcutMaterialRadius(size),
      tintColor: resolveBrowserHomeShortcutMaterialTintForMode(this.storedResolvedThemeMode),
      materialBorderWidth: HOME_SHORTCUT_ICON_BORDER_WIDTH,
      materialBorderColor: this.storedOutlineColor
    }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: Math.max(1, Math.min(size, iconSize)),
        iconColor: this.resolveOperationalIconColor()
      })
    }
  }

  @Builder
  private buildShortcutSiteIcon(shortcut: ShortcutRecord, size: number, fallbackFontSize: number) {
    BrowserFloatingGlassMaterialSurface({
      surfaceWidth: size,
      surfaceHeight: size,
      surfaceRadius: this.resolveShortcutMaterialRadius(size),
      tintColor: resolveBrowserHomeShortcutMaterialTintForMode(this.storedResolvedThemeMode),
      materialBorderWidth: HOME_SHORTCUT_ICON_BORDER_WIDTH,
      materialBorderColor: this.storedOutlineColor
    }) {
      WebsiteIconView({
        iconUri: this.resolveShortcutIconUri(shortcut),
        iconPixelMap: this.resolveShortcutIconPixelMap(shortcut),
        fallbackLabel: this.viewModel.getShortcutFallbackLabel(shortcut),
        variant: 'grid',
        iconSize: size,
        cornerRadiusRatio: this.storedSiteIconCornerRadiusRatio,
        frameBorderWidth: 0,
        contentRatio: this.storedHomeShortcutIconSizeRatio,
        fallbackFontSize: fallbackFontSize,
        fallbackFontWeight: FontWeight.Bolder,
        containerBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
        frameBorderColor: this.storedOutlineColor,
        textColor: this.resolveOperationalIconColor(),
        fit: ImageFit.Contain,
        preferPixelMap: true,
        sourceRevision: this.resolveShortcutIconSourceRevision(shortcut),
        hitTestMode: HitTestMode.None
      })
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildDesktopShortcutContextMenu(shortcut: ShortcutRecord) {
    BrowserDesktopContextMenu() {
      if (isHomeSystemShortcut(shortcut)) {
        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open', '打开')
        }

        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'delete', '从首页移除')
        }
      } else {
        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open', '打开')
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open_new_tab', '新标签页打开')
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open_background_tab', '后台打开')
        }

        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'copy_link', '复制链接')
          this.buildDesktopShortcutContextMenuItem(shortcut, 'edit', '编辑')
        }

        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'delete', '删除')
        }
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
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
  private buildDesktopShortcutContextMenuItem(
    shortcut: ShortcutRecord,
    actionId: HomeShortcutContextActionId,
    label: string
  ) {
    BrowserDesktopContextMenuItem({
      label: label,
      onAction: (): void => {
        this.runAfterContextMenuDismiss(() => {
          this.onAction({
            type: 'shortcut_action',
            shortcutId: shortcut.id,
            actionId: actionId
          });
        });
      }
    })
  }

  @Builder
  private buildTouchShortcutContextMenu(shortcut: ShortcutRecord) {
    Menu() {
      ForEach(this.resolveContextActions(shortcut), (item: HomeShortcutContextAction) => {
        MenuItem({ content: item.title })
          .onClick(() => {
            this.runAfterContextMenuDismiss(() => {
              this.onAction({
                type: 'shortcut_action',
                shortcutId: shortcut.id,
                actionId: item.id
              });
            });
          })
      }, (item: HomeShortcutContextAction) => item.id)

      MenuItem({ content: '主页设置' })
        .onClick(() => {
          this.runAfterContextMenuDismiss(() => {
            this.onOpenHomeSettings();
          });
        })
    }
    .width(216)
    .radius(HOME_CONTEXT_MENU_RADIUS)
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveBrowserHomeShortcutMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }

  @Builder
  private buildShortcutContextPreview(shortcut: ShortcutRecord) {
    Column({ space: 7 }) {
      this.buildShortcutIcon(shortcut)

      Text(this.resolveShortcutDisplayTitle(shortcut))
        .width('100%')
        .fontSize(12)
        .fontColor(this.resolvePrimaryTextColor())
        .textShadow(this.textShadow)
        .animation({ duration: HOME_WALLPAPER_APPEARANCE_TRANSITION_MS, curve: Curve.EaseInOut })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Center)
    }
    .width(Math.max(this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics), 88))
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.storedFloatingSurfaceColor)
    .borderRadius(22)
  }

  private getGridContentHeight(): number {
    const presentationItemCount = this.resolvePresentationItemCount();
    const rowCount = Math.max(1, Math.ceil(presentationItemCount / this.resolveShortcutLaneCount()));
    const defaultHeight = this.viewModel.getGridContentHeight(rowCount, this.gridWidth, this.metrics);
    if (this.storedShowShortcutNames) {
      return defaultHeight;
    }
    return Math.max(
      this.resolveShortcutRowHeight(),
      defaultHeight - rowCount * this.resolveShortcutTitleHeight()
    );
  }

  private resolveShortcutColumnGap(): number {
    const contentWidth = Math.max(1, this.gridWidth - this.contentInset * 2);
    return Math.max(
      this.metrics.columnGap,
      this.viewModel.getAlignedGridColumnGap(contentWidth, this.metrics)
    );
  }

  private resolvePresentationItemCount(): number {
    return this.liveShortcuts.length + (this.showAddEntry ? 1 : 0);
  }

  private resolveShortcutLaneCount(): number {
    return this.viewModel.resolveOccupiedColumnCount(this.resolvePresentationItemCount(), this.metrics);
  }

  private resolveShortcutListWidth(): number {
    return this.viewModel.getOccupiedGridContentWidth(
      this.resolvePresentationItemCount(),
      this.gridWidth,
      this.contentInset,
      this.metrics
    );
  }

  private resolveShortcutCardWidth(): number {
    return Math.max(
      this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics),
      HOME_SHORTCUT_MIN_INTERACTION_WIDTH_VP,
      this.metrics.minimumTileSize
    );
  }

  private resolveShortcutRowHeight(): number {
    const defaultHeight = this.viewModel.getShortcutRowHeight(this.gridWidth, this.metrics);
    return this.storedShowShortcutNames
      ? defaultHeight
      : Math.max(this.resolveShortcutContainerSize(), defaultHeight - this.resolveShortcutTitleHeight());
  }

  private resolveShortcutCardHeight(): number {
    const defaultHeight = this.viewModel.getShortcutCardHeight(this.gridWidth, this.metrics);
    return this.storedShowShortcutNames
      ? defaultHeight
      : Math.max(this.resolveShortcutContainerSize(), defaultHeight - this.resolveShortcutTitleHeight());
  }

  private resolveShortcutTitleHeight(): number {
    return Math.max(0, this.metrics.titleTopGap + this.metrics.titleBlockHeight);
  }

  private resolveShortcutGlyphSize(containerSize: number): number {
    return Math.max(
      HOME_SHORTCUT_MIN_GLYPH_SIZE_VP,
      Math.min(HOME_FIXED_SHORTCUT_ICON_SIZE_VP, Math.round(containerSize * 0.48))
    );
  }

  private resolveShortcutFallbackFontSize(containerSize: number): number {
    return Math.max(
      HOME_SHORTCUT_MIN_FALLBACK_FONT_SIZE_VP,
      Math.min(20, Math.round(containerSize * 0.4))
    );
  }

  private getResolvedIcon(shortcut: ShortcutRecord): HomeShortcutIconState | undefined {
    void this.iconsVersion;
    return this.viewModel.getShortcutResolvedIcon(shortcut, this.icons);
  }

  private resolveShortcutIconUri(shortcut: ShortcutRecord): string {
    const icon = this.getResolvedIcon(shortcut);
    if (icon === undefined) {
      return this.resolveStoredShortcutIconUri(shortcut);
    }
    if (icon.pixelMap === undefined && this.shouldRequirePreparedPixelMap(icon.path)) {
      return '';
    }
    return icon.path;
  }

  private resolveShortcutIconPixelMap(shortcut: ShortcutRecord): image.PixelMap | undefined {
    const icon = this.getResolvedIcon(shortcut);
    return icon?.pixelMap;
  }

  private resolveShortcutIconSourceRevision(shortcut: ShortcutRecord): number {
    const icon = this.getResolvedIcon(shortcut);
    return icon?.revision ?? 0;
  }

  private resolveShortcutContentRenderKey(): string {
    const iconVersion = this.frozenIconsVersion >= 0 ? this.frozenIconsVersion : this.iconsVersion;
    return `${iconVersion}:${this.storedResolvedThemeMode}:` +
      `${this.storedShowShortcutNames ? 'names' : 'icons'}`;
  }

  private resolveStoredShortcutIconUri(shortcut: ShortcutRecord): string {
    if ((shortcut.iconRendering ?? '') === 'letter') {
      return '';
    }
    return (shortcut.icon ?? '').trim();
  }

  private shouldRequirePreparedPixelMap(iconPath: string): boolean {
    const normalizedPath = iconPath.trim();
    return normalizedPath.startsWith('file://') || normalizedPath.startsWith('/');
  }

  private resolveShortcutContainerSize(): number {
    return this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics);
  }

  private resolveShortcutMaterialRadius(size: number): number {
    return Math.max(0, Math.round(size * this.storedSiteIconCornerRadiusRatio));
  }

  private runAfterContextMenuDismiss(action: () => void): void {
    this.contextMenuShortcutId = '';
    this.pressedShortcutId = '';
    setTimeout(action, HOME_SHORTCUT_CONTEXT_MENU_DISMISS_DELAY_MS);
  }

  private openShortcutContextMenu(shortcutId: string): void {
    if (this.shortcutDragActive || this.dragConsumedShortcutId === shortcutId) {
      return;
    }
    HomeShortcutInteractionFeedbackService.performContextMenuFeedback();
    this.pressedShortcutId = shortcutId;
    this.contextMenuShortcutId = shortcutId;
  }

  private closeShortcutContextMenuForPan(shortcutId: string): void {
    if (this.contextMenuShortcutId === shortcutId) {
      this.contextMenuShortcutId = '';
    }
    if (this.pressedShortcutId === shortcutId) {
      this.pressedShortcutId = '';
    }
  }

  private beginNativeDrag(index: number): void {
    const shortcut = this.liveShortcuts[index];
    if (shortcut === undefined) {
      return;
    }
    this.frozenIconsVersion = this.iconsVersion;
    this.dragConsumedShortcutId = shortcut.id;
    this.pressedShortcutId = '';
    this.contextMenuShortcutId = '';
    this.shortcutDragActive = true;
  }

  private commitNativeMove(from: number, to: number): void {
    const shortcut = this.liveShortcuts[from];
    if (shortcut === undefined || this.liveShortcuts.length <= 0) {
      this.endNativeDrag();
      return;
    }
    const safeTo = Math.max(0, Math.min(to, this.liveShortcuts.length - 1));
    this.dragConsumedShortcutId = shortcut.id;
    this.contextMenuShortcutId = '';
    this.pressedShortcutId = '';
    if (safeTo !== from) {
      const movedShortcuts = this.liveShortcuts.splice(from, 1);
      const movedShortcut = movedShortcuts.length > 0 ? movedShortcuts[0] : undefined;
      if (movedShortcut === undefined) {
        this.endNativeDrag();
        return;
      }
      this.liveShortcuts.splice(safeTo, 0, movedShortcut);
      const request: HomeShortcutMoveRequest = {
        shortcutId: shortcut.id,
        expectedFromIndex: from,
        targetIndex: safeTo
      };
      this.onAction({ type: 'move_shortcut', request: request });
    }
    this.endNativeDrag();
  }

  private endNativeDrag(): void {
    this.shortcutDragActive = false;
    this.frozenIconsVersion = -1;
  }

  private syncLiveShortcutsFromExternalOrder(): void {
    const nextShortcuts = this.viewModel.reconcileShortcutOrder(
      this.liveShortcuts,
      this.shortcuts,
      this.shortcutOrderSignature
    );
    if (this.viewModel.buildShortcutContentSignature(nextShortcuts) ===
      this.viewModel.buildShortcutContentSignature(this.liveShortcuts)) {
      return;
    }
    this.liveShortcuts = nextShortcuts;
  }

  private resetShortcutInteractionState(): void {
    this.contextMenuShortcutId = '';
    this.pressedShortcutId = '';
    this.dragConsumedShortcutId = '';
    this.shortcutDragActive = false;
    this.frozenIconsVersion = -1;
    this.addEntryPressed = false;
  }

  private handleShortcutClick(shortcut: ShortcutRecord): void {
    if (this.dragConsumedShortcutId === shortcut.id) {
      this.dragConsumedShortcutId = '';
      return;
    }
    if (this.shortcutDragActive || this.contextMenuShortcutId.length > 0) {
      return;
    }
    this.onAction({
      type: 'shortcut_action',
      shortcutId: shortcut.id,
      actionId: 'open'
    });
  }

  private updatePressedShortcut(shortcutId: string, type: TouchType): void {
    if (type === TouchType.Down) {
      if (this.shortcutDragActive) {
        this.endNativeDrag();
      }
      this.dragConsumedShortcutId = '';
      this.pressedShortcutId = shortcutId;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedShortcutId = '';
    }
  }

  private resolveContextActions(shortcut: ShortcutRecord): HomeShortcutContextAction[] {
    if (isHomeSystemShortcut(shortcut)) {
      return [
        { id: 'open', title: '打开', role: 'normal' },
        { id: 'delete', title: '从首页移除', role: 'destructive' }
      ];
    }
    return [
      { id: 'open', title: '打开', role: 'normal' },
      { id: 'open_new_tab', title: '新标签页打开', role: 'normal' },
      { id: 'open_background_tab', title: '后台打开', role: 'normal' },
      { id: 'copy_link', title: '复制链接', role: 'normal' },
      { id: 'edit', title: '编辑', role: 'normal' },
      { id: 'delete', title: '删除', role: 'destructive' }
    ];
  }

  private resolveShortcutDisplayTitle(shortcut: ShortcutRecord): string {
    return resolveHomeSystemShortcutDefinitionByUrl(shortcut.url)?.title ?? shortcut.title;
  }

  private resolveSystemShortcutIcon(shortcut: ShortcutRecord): AiraRenderableIconId {
    const definition = resolveHomeSystemShortcutDefinitionByUrl(shortcut.url);
    return definition?.iconId ?? 'browser.toolbar.siteInfo';
  }

  private updateAddEntryPressed(type: TouchType): void {
    if (type === TouchType.Down) {
      this.addEntryPressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.addEntryPressed = false;
    }
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor;
  }

  private resolveOperationalIconColor(): ResourceColor {
    return resolveBrowserOperationalIconColor(this.storedResolvedThemeMode);
  }
}
