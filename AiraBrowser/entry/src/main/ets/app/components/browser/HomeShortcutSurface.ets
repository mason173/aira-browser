import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { hasBundledShortcutIcon, resolveBundledShortcutIcon } from '../../../core/resources/BundledShortcutIconResources';
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
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem, buildBrowserDesktopMenuOptions } from './BrowserDesktopContextMenu';
import { SiteIconPixelMapCacheService } from '../../../services/siteicons/SiteIconPixelMapCacheService';
import { AiraLoadScrollJankProbe } from '../../../common/debug/AiraLoadScrollJankProbe';

const HOME_SHORTCUT_ICON_BORDER_WIDTH: number = 0;
const HOME_FIXED_SHORTCUT_ICON_SIZE_VP: number = 24;
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
  /**
   * The centered frame pins an undeletable settings tile before the add entry, so the
   * add entry stays the last item. It is not a `ShortcutRecord`, so it can never be
   * reordered, edited, or removed.
   */
  @Prop showPinnedSettingsEntry: boolean = false;
  @Prop alignPartialRowsToStart: boolean = false;
  /** Shifts a short final row to the middle. A single short row is already centered by width. */
  @Prop centerPartialRows: boolean = false;
  /** Negative means use the stored site-icon radius. The centered homepage passes a circle. */
  @Prop iconCornerRadiusRatio: number = -1;
  @Link contextMenuShortcutId: string;
  @Link shortcutDragActive: boolean;

  private viewModel: HomeShortcutViewModel = new HomeShortcutViewModel();
  private siteIconPixelMapCache: SiteIconPixelMapCacheService = new SiteIconPixelMapCacheService();
  @State
  private pressedShortcutId: string = '';
  @State
  private addEntryPressed: boolean = false;
  @State
  private settingsEntryPressed: boolean = false;
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
      if (this.liveShortcuts.length > 0 || this.showAddEntry || this.showPinnedSettingsEntry) {
        // Recreate the lanes list when the add tile's place in the grid changes. A lanes List
        // can keep a layout that never picks up the trailing add item after the grid updates.
        ForEach([this.resolveShortcutGridIdentity()], (_identity: string) => {
        List({ space: this.metrics.rowGap }) {
          ForEach(this.liveShortcuts, (shortcut: ShortcutRecord, index: number) => {
            ListItem() {
              Row() {
                ForEach([this.resolveShortcutContentRenderKey(shortcut)], (_renderKey: string) => {
                  this.buildShortcutCard(shortcut)
                }, (renderKey: string) => `${shortcut.id}|${renderKey}`)
              }
              .width('100%')
              .height(this.resolveShortcutRowHeight())
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
              .offset({ x: this.resolvePartialRowCenterShift(index) })
            }
            .height(this.resolveShortcutRowHeight())
            .clip(false)
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
            .bindContextMenu(this.buildDesktopShortcutContextMenu(shortcut), ResponseType.RightClick, buildBrowserDesktopMenuOptions({
              onAppear: () => {
                this.contextMenuShortcutId = '';
                this.pressedShortcutId = shortcut.id;
              },
              onDisappear: () => {
                if (this.pressedShortcutId === shortcut.id) {
                  this.pressedShortcutId = '';
                }
              }
            }))
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

          if (this.showPinnedSettingsEntry) {
            ListItem() {
              Row() {
                this.buildPinnedSettingsCard()
              }
              .width('100%')
              .height(this.resolveShortcutRowHeight())
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
              .offset({ x: this.resolvePartialRowCenterShift(this.liveShortcuts.length) })
            }
            .height(this.resolveShortcutRowHeight())
            .clip(false)
          }

          if (this.showAddEntry) {
            ListItem() {
              Row() {
                this.buildAddEntryCard()
              }
              .width('100%')
              .height(this.resolveShortcutRowHeight())
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
              .offset({
                x: this.resolvePartialRowCenterShift(
                  this.liveShortcuts.length + (this.showPinnedSettingsEntry ? 1 : 0)
                )
              })
            }
            .height(this.resolveShortcutRowHeight())
            .clip(false)
          }
        }
        .width(this.resolveShortcutListWidth())
        .height(this.getGridContentHeight())
        .lanes(this.resolveShortcutLaneCount(), this.resolveShortcutColumnGap())
        .scrollBar(BarState.Off)
        .clip(false)
        .nestedScroll({
          scrollForward: NestedScrollMode.PARENT_FIRST,
          scrollBackward: NestedScrollMode.PARENT_FIRST
        })
        .responseRegion({
          x: -this.contentInset,
          y: 0,
          width: Math.max(1, this.resolveShortcutListWidth() + this.contentInset * 2),
          height: this.getGridContentHeight()
        })
        .translate({ y: this.contentOffsetY })
        }, (identity: string) => identity)
      } else {
        AppEmptyState({
          showIcon: false,
          title: resolveAppResourceText($r('app.string.bookshelf_empty')),
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
      this.alignPartialRowsToStart &&
        (this.liveShortcuts.length > 0 || this.showAddEntry || this.showPinnedSettingsEntry)
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
    if (hasBundledShortcutIcon(shortcut.url)) {
      // The store page's own icon is the store's; this tile shows the app's instead.
      this.buildBundledShortcutIcon(shortcut, this.resolveShortcutContainerSize())
    } else if (isHomeSystemShortcut(shortcut)) {
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
      fallbackColor: this.resolveShortcutTileColor(),
      backgroundBlurEnabled: false,
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
        Text(resolveAppResourceText($r('app.string.settings_custom_home_add')))
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
    .width(this.resolveShortcutCardWidth())
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

  /**
   * Pinned `主页设置` tile. It sits right before the add entry, which stays last, and is never
   * part of `liveShortcuts`, so reorder, context menus, and removal cannot reach it.
   */
  @Builder
  private buildPinnedSettingsCard() {
    Column({ space: this.storedShowShortcutNames ? this.metrics.titleTopGap : 0 }) {
      this.buildAddEntryIcon(
        'browser.home.settings',
        this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics),
        this.resolveShortcutGlyphSize(this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics))
      )

      if (this.storedShowShortcutNames) {
        Text(resolveAppResourceText($r('app.string.settings_custom_home_title')))
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
    .width(this.resolveShortcutCardWidth())
    .height(this.resolveShortcutRowHeight())
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(18)
    .scale({
      x: this.settingsEntryPressed ? HOME_SHORTCUT_PRESSED_SCALE : 1,
      y: this.settingsEntryPressed ? HOME_SHORTCUT_PRESSED_SCALE : 1
    })
    .opacity(this.settingsEntryPressed ? HOME_SHORTCUT_PRESSED_OPACITY : 1)
    .animation({
      duration: this.settingsEntryPressed ? HOME_SHORTCUT_PRESS_DURATION_MS : HOME_SHORTCUT_RELEASE_DURATION_MS,
      curve: this.settingsEntryPressed ? Curve.EaseOut : 'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updateSettingsEntryPressed(event.type);
    })
    .onClick(() => {
      if (!this.shortcutDragActive && this.contextMenuShortcutId.length <= 0) {
        this.onOpenHomeSettings();
      }
    })
  }

  @Builder
  private buildAddEntryIcon(iconId: AiraRenderableIconId, size: number, iconSize: number) {
    BrowserFloatingGlassMaterialSurface({
      surfaceWidth: size,
      surfaceHeight: size,
      surfaceRadius: this.resolveShortcutMaterialRadius(size),
      fallbackColor: this.resolveShortcutTileColor(),
      backgroundBlurEnabled: false,
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
  private buildBundledShortcutIcon(shortcut: ShortcutRecord, size: number) {
    BrowserFloatingGlassMaterialSurface({
      surfaceWidth: size,
      surfaceHeight: size,
      surfaceRadius: this.resolveShortcutMaterialRadius(size),
      fallbackColor: this.resolveShortcutTileColor(),
      backgroundBlurEnabled: false,
      materialBorderWidth: HOME_SHORTCUT_ICON_BORDER_WIDTH,
      materialBorderColor: this.storedOutlineColor
    }) {
      Image(resolveBundledShortcutIcon(shortcut.url) as Resource)
        .width(this.resolveShortcutContentSize(size))
        .height(this.resolveShortcutContentSize(size))
        .objectFit(ImageFit.Contain)
        .borderRadius(this.resolveShortcutContentRadius(size))
        .clip(true)
        .draggable(false)
        .accessibilityLevel('no-hide-descendants')
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildShortcutSiteIcon(shortcut: ShortcutRecord, size: number, fallbackFontSize: number) {
    BrowserFloatingGlassMaterialSurface({
      surfaceWidth: size,
      surfaceHeight: size,
      surfaceRadius: this.resolveShortcutMaterialRadius(size),
      fallbackColor: this.resolveShortcutTileColor(),
      backgroundBlurEnabled: false,
      materialBorderWidth: HOME_SHORTCUT_ICON_BORDER_WIDTH,
      materialBorderColor: this.storedOutlineColor
    }) {
      WebsiteIconView({
        iconUri: this.resolveShortcutIconUri(shortcut),
        iconPixelMap: this.resolveShortcutIconPixelMap(shortcut),
        fallbackLabel: this.viewModel.getShortcutFallbackLabel(shortcut),
        variant: 'grid',
        iconSize: size,
        cornerRadiusRatio: this.resolveIconCornerRadiusRatio(),
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
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open', resolveAppResourceText($r('app.string.ui_open')))
        }

        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'delete', resolveAppResourceText($r('app.string.browser_ui_home_shortcut_surface_001')))
        }
      } else {
        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open', resolveAppResourceText($r('app.string.ui_open')))
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open_new_tab', resolveAppResourceText($r('app.string.history_open_new_tab_short')))
          this.buildDesktopShortcutContextMenuItem(shortcut, 'open_background_tab', resolveAppResourceText($r('app.string.history_open_background')))
        }

        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'copy_link', resolveAppResourceText($r('app.string.offline_action_copy_link')))
          this.buildDesktopShortcutContextMenuItem(shortcut, 'edit', resolveAppResourceText($r('app.string.ui_edit')))
        }

        MenuItemGroup() {
          this.buildDesktopShortcutContextMenuItem(shortcut, 'delete', resolveAppResourceText($r('app.string.settings_delete')))
        }
      }

      MenuItemGroup() {
        BrowserDesktopContextMenuItem({
          label: resolveAppResourceText($r('app.string.settings_custom_home_title')),
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

      MenuItem({ content: resolveAppResourceText($r('app.string.settings_custom_home_title')) })
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
    return this.liveShortcuts.length +
      (this.showAddEntry ? 1 : 0) +
      (this.showPinnedSettingsEntry ? 1 : 0);
  }

  private resolveShortcutLaneCount(): number {
    return this.viewModel.resolveOccupiedColumnCount(this.resolvePresentationItemCount(), this.metrics);
  }

  /**
   * A full row already spans the centered block. A short final row would otherwise stay on the
   * leading edge, so it shifts by half of the empty lanes and grows out from the middle.
   */
  private resolvePartialRowCenterShift(index: number): number {
    if (!this.centerPartialRows) {
      return 0;
    }
    const columns = this.resolveShortcutLaneCount();
    const total = this.resolvePresentationItemCount();
    if (columns <= 1 || total <= columns) {
      return 0;
    }
    const remainder = total % columns;
    if (remainder === 0 || index < total - remainder) {
      return 0;
    }
    const gap = this.resolveShortcutColumnGap();
    const laneWidth = (this.resolveShortcutListWidth() - gap * (columns - 1)) / columns;
    return ((columns - remainder) / 2) * (laneWidth + gap);
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
    // Labels use the full lane while the icon keeps its independent, smaller size.
    // Staying inside the lane also keeps the trailing add tile within the clipped rail.
    return this.resolveShortcutLaneWidth();
  }

  private resolveShortcutLaneWidth(): number {
    const columns = Math.max(1, this.resolveShortcutLaneCount());
    const gap = this.resolveShortcutColumnGap();
    const listWidth = this.resolveShortcutListWidth();
    return Math.max(1, (listWidth - gap * Math.max(0, columns - 1)) / columns);
  }

  /**
   * Changes when the add tile would move to a different lane. The lanes List is recreated
   * so a previous layout cannot keep that trailing item undisplayed.
   */
  private resolveShortcutGridIdentity(): string {
    return [
      this.resolveShortcutLaneCount(),
      this.resolvePresentationItemCount(),
      this.showAddEntry ? 1 : 0,
      this.showPinnedSettingsEntry ? 1 : 0,
      Math.round(this.gridWidth),
      Math.round(this.metrics.columns)
    ].join('|');
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
    const pixelMap = this.resolveShortcutIconPixelMapInternal(shortcut);
    AiraLoadScrollJankProbe.noteShortcutTileBuild(pixelMap !== undefined);
    return pixelMap;
  }

  private resolveShortcutIconPixelMapInternal(shortcut: ShortcutRecord): image.PixelMap | undefined {
    const icon = this.getResolvedIcon(shortcut);
    if (icon?.pixelMap !== undefined) {
      return icon.pixelMap;
    }
    // Cache-first. While a shortcut has no hydration entry yet this used to return undefined, which
    // made SiteIconView fall through to `Image(<local icon file>)`; ArkUI then decoded the file
    // again at full resolution for every tile of every list rebuild. Prewarming has usually already
    // decoded that same file, so reuse it when it is there.
    const candidatePath = icon !== undefined ? icon.path : this.resolveStoredShortcutIconUri(shortcut);
    return this.readCachedShortcutPixelMap(candidatePath);
  }

  private readCachedShortcutPixelMap(path: string): image.PixelMap | undefined {
    const normalized = path.trim();
    if (normalized.length === 0 || !this.shouldRequirePreparedPixelMap(normalized)) {
      return undefined;
    }
    const cached = this.siteIconPixelMapCache.getCachedPixelMap(normalized);
    if (cached !== undefined) {
      return cached;
    }
    // The prepared-icon store hands back `file://` URIs, while a shortcut may persist a bare path.
    if (normalized.startsWith('file://')) {
      return this.siteIconPixelMapCache.getCachedPixelMap(normalized.substring('file://'.length));
    }
    return this.siteIconPixelMapCache.getCachedPixelMap(`file://${normalized}`);
  }

  private resolveShortcutIconSourceRevision(shortcut: ShortcutRecord): number {
    const icon = this.getResolvedIcon(shortcut);
    return icon?.revision ?? 0;
  }

  /**
   * Key for the per-tile rebuild trigger.
   *
   * It keys on the icon's own `revision`, not on the list-wide `iconsVersion`. `iconsVersion`
   * advances on every hydration snapshot, so one updated icon used to hand all 17 tiles a new key
   * and rebuild the whole grid. The home grid stays mounted behind the tab list by design, so that
   * rebuild landed on the UI thread while a page was being scrolled.
   *
   * `HomeShortcutIconHydrationCoordinator` already advances `revision` only for the icon whose
   * `path` or `pixelMap` actually changed, which is exactly the granularity a tile needs.
   *
   * While a native drag is in flight the tiles must stay put underneath the gesture, so the frozen
   * list-wide version keeps every key stable for the duration of the drag.
   */
  private resolveShortcutContentRenderKey(shortcut: ShortcutRecord): string {
    const iconKey = this.frozenIconsVersion >= 0
      ? this.frozenIconsVersion
      : this.resolveShortcutIconSourceRevision(shortcut);
    const renderKey = `${iconKey}:${this.storedResolvedThemeMode}:` +
      `${this.storedShowShortcutNames ? 'names' : 'icons'}`;
    // Temporary [DEBUG-load-scroll-jank-7c4d] probe: snapshot the whole key set so a theme-mode flip
    // that re-keys all 17 tiles at once can be told apart from per-icon changes.
    AiraLoadScrollJankProbe.noteShortcutRenderKey(
      shortcut.id,
      renderKey,
      this.storedResolvedThemeMode,
      this.storedShowShortcutNames
    );
    return renderKey;
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

  /**
   * The bundled artwork sits in the same inset and radius as a site icon, so the two
   * kinds of tile are indistinguishable in the grid.
   */
  private resolveShortcutContentSize(size: number): number {
    return Math.max(0, size - this.resolveShortcutContentPadding(size) * 2);
  }

  private resolveShortcutContentPadding(size: number): number {
    const ratio = Math.max(0, Math.min(1, this.storedHomeShortcutIconSizeRatio));
    return Math.max(0, Math.round(size * (1 - ratio) / 2));
  }

  private resolveShortcutContentRadius(size: number): number {
    return Math.max(0,
      Math.round(size * this.resolveIconCornerRadiusRatio()) - this.resolveShortcutContentPadding(size));
  }

  private resolveShortcutContainerSize(): number {
    return this.viewModel.getShortcutTileSize(this.gridWidth, this.metrics);
  }

  private resolveShortcutMaterialRadius(size: number): number {
    return Math.max(0, Math.round(size * this.resolveIconCornerRadiusRatio()));
  }

  private resolveIconCornerRadiusRatio(): number {
    if (this.iconCornerRadiusRatio >= 0) {
      return this.iconCornerRadiusRatio;
    }
    return this.storedSiteIconCornerRadiusRatio;
  }

  // Home grid tiles are opaque solid surfaces, not blurred glass: the wallpaper
  // shows through neither the tile nor a per-icon backdrop blur, which keeps a
  // whole grid of icons off the scroll path's blur cost.
  private resolveShortcutTileColor(): ResourceColor {
    return this.storedFloatingSurfaceColor;
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
    this.settingsEntryPressed = false;
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
        { id: 'open', title: resolveAppResourceText($r('app.string.ui_open')), role: 'normal' },
        { id: 'delete', title: resolveAppResourceText($r('app.string.browser_ui_home_shortcut_surface_001')), role: 'destructive' }
      ];
    }
    return [
      { id: 'open', title: resolveAppResourceText($r('app.string.ui_open')), role: 'normal' },
      { id: 'open_new_tab', title: resolveAppResourceText($r('app.string.history_open_new_tab_short')), role: 'normal' },
      { id: 'open_background_tab', title: resolveAppResourceText($r('app.string.history_open_background')), role: 'normal' },
      { id: 'copy_link', title: resolveAppResourceText($r('app.string.offline_action_copy_link')), role: 'normal' },
      { id: 'edit', title: resolveAppResourceText($r('app.string.ui_edit')), role: 'normal' },
      { id: 'delete', title: resolveAppResourceText($r('app.string.settings_delete')), role: 'destructive' }
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

  private updateSettingsEntryPressed(type: TouchType): void {
    if (type === TouchType.Down) {
      this.settingsEntryPressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.settingsEntryPressed = false;
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
