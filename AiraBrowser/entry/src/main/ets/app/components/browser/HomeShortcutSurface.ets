import { curves } from '@kit.ArkUI';
import { util } from '@kit.ArkTS';
import { HomeShortcutFolderService, HomeShortcutFolderCommand } from '../../../services/shortcuts/HomeShortcutFolderService';
import { HomeShortcutGridPolicy, HomeShortcutGridSlot, HomeShortcutGridSpec, HomeShortcutGridLayout } from '../../../features/newtab/HomeShortcutGridPolicy';
import { HomeShortcutDragSession, HomeShortcutDragState } from '../../../features/newtab/HomeShortcutDragSession';
import { HomeShortcutDragGeometry, HomeShortcutDragViewport, HomeShortcutGridAnchor, HomeShortcutFloatingIcon } from '../../../features/newtab/HomeShortcutDragGeometry';
import { HomeShortcutFolderMotion, HomeShortcutFolderFrame } from '../../../features/newtab/HomeShortcutFolderMotion';
import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { hasBundledShortcutIcon, resolveBundledShortcutIcon } from '../../../core/resources/BundledShortcutIconResources';
import { image } from '@kit.ImageKit';
import { ShortcutRecord } from '../../../common/models/BrowserModels';
import {
  HomeShortcutLayoutMetrics
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
  @Prop containerParentId: string = '';
  @Prop allowMutations: boolean = true;
  onExtractToRoot: () => void = () => {};
  onExtractionChanged: (active: boolean) => void = (_active: boolean) => {};
  resolveRootGrid: (records: ShortcutRecord[]) => HomeShortcutGridAnchor | undefined = (_records: ShortcutRecord[]) => undefined;
  getDragViewport: () => HomeShortcutDragViewport | undefined = () => undefined;
  onDragScroll: (delta: number) => void = (_delta: number) => {};
  onRootDragScroll: (delta: number) => void = (_delta: number) => {};
  getRootDragViewport: () => HomeShortcutDragViewport | undefined = () => undefined;
  onFolderFloatingIcon: (floating: HomeShortcutFloatingIcon) => void = (_floating: HomeShortcutFloatingIcon) => {};
  private folderService: HomeShortcutFolderService = new HomeShortcutFolderService();
  private gridPolicy: HomeShortcutGridPolicy = new HomeShortcutGridPolicy();
  private dragSession: HomeShortcutDragSession = new HomeShortcutDragSession();
  private folderMotion: HomeShortcutFolderMotion = new HomeShortcutFolderMotion();
  private dragGeometry: HomeShortcutDragGeometry = new HomeShortcutDragGeometry();
  private instanceId: string = `home-grid-${util.generateRandomUUID()}`;
  @State private dragState: HomeShortcutDragState = { activeId: '', targetId: '', center: false, orderedIds: [] };
  @State private floatingRecord: ShortcutRecord = { id: '', title: '', url: '', folderName: '', position: 0 };
  @State private floatX: number = 0;
  @State private floatY: number = 0;
  @State private settling: boolean = false;
  private dragStartSlot?: HomeShortcutGridSlot;
  private lastDragX: number = 0;
  private lastDragY: number = 0;
  private dragWindowStartX: number = 0;
  private dragWindowStartY: number = 0;
  private dragWindowX: number = 0;
  private dragWindowY: number = 0;
  private extractionOutsideSince: number = -1;
  private dragSpecSignature: string = '';
  private longPressedShortcutId: string = '';
  @State private extracting: boolean = false;
  @State private extractionRecords: ShortcutRecord[] = [];
  @State private extractionAnchor: HomeShortcutGridAnchor | undefined = undefined;
  @State private extractionOffsetX: number = 0;
  @State private extractionOffsetY: number = 0;
  @State private folderExtracting: boolean = false;
  @State private floatingScale: number = 1;
  @State private floatingIntoFolder: boolean = false;
  private containerCacheRecords?: ShortcutRecord[];
  private containerCacheParent: string = '';
  private containerCache: ShortcutRecord[] = [];
  private layoutCacheKey: string = '';
  private layoutCacheItems?: ShortcutRecord[];
  private projectedCacheItems?: ShortcutRecord[];
  private projectedCacheIds?: string[];
  private projectedCache: ShortcutRecord[] = [];
  private layoutCache: HomeShortcutGridLayout = { slots: [], height: 0 };
  private slotCache: Map<string, HomeShortcutGridSlot> = new Map<string, HomeShortcutGridSlot>();
  private hoverTimer: number = -1;
  private settleTimer: number = -1;
  @State private folderCoverVisible: boolean = false;
  @State private openFolderId: string = '';
  @State private folderProgress: number = 0;
  @State private folderClosing: boolean = false;
  @State private folderAnimating: boolean = false;
  @State private folderTitleDraft: string = '';
  @State private folderRenameRequested: boolean = false;
  @State private folderViewportWidth: number = 360;
  @State private folderViewportHeight: number = 720;
  @State private folderSource: HomeShortcutFolderFrame = { x: 0, y: 0, size: 54 };
  private folderAnimationTimer: number = -1;
  private folderAnimationGeneration: number = 0;
  private folderScroller: Scroller = new Scroller();
  private folderScrollY: number = 0;
  private folderCoverOriginX: number = 0;
  private folderCoverOriginY: number = 0;
  @State private folderFloating: HomeShortcutFloatingIcon = { x: 0, y: 0, size: 0, settling: false };

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
    this.cancelProjectedDrag();
    this.resetShortcutInteractionState();
    this.clearDragTimers();
    this.clearFolderAnimation();
  }

  build() {
    Column() {
      if (this.liveShortcuts.length > 0 || this.showAddEntry || this.showPinnedSettingsEntry) {
        Stack({ alignContent: Alignment.TopStart }) {
          ForEach(this.containerShortcuts(), (shortcut: ShortcutRecord) => {
            Row() { this.buildShortcutCard(shortcut) }
              .width(this.slotFor(shortcut.id).width)
              .height(this.slotFor(shortcut.id).height)
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
              .position({ x: this.slotFor(shortcut.id).x, y: this.slotFor(shortcut.id).y })
              .animation({ duration: 320, curve: Curve.EaseInOut })
              .opacity(this.floatingRecord.id === shortcut.id ? 0 : 1)
              .gesture(GestureGroup(GestureMode.Sequence,
                LongPressGesture({ fingers: 1, repeat: false, duration: HOME_SHORTCUT_CONTEXT_MENU_LONG_PRESS_DURATION_MS })
                  .onAction(() => { this.longPressedShortcutId = shortcut.id; this.pressedShortcutId = shortcut.id; })
                  .onActionEnd(() => { this.finishShortcutLongPress(shortcut.id); }),
                PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
                  .onActionStart((event: GestureEvent) => { this.startProjectedDrag(shortcut, event); })
                  .onActionUpdate((event: GestureEvent) => { this.updateProjectedDrag(event); })
                  .onActionEnd((event: GestureEvent) => { this.finishProjectedDrag(event); })
                  .onActionCancel(() => { this.cancelProjectedDrag(); })
              ))
              .bindContextMenu(this.buildDesktopShortcutContextMenu(shortcut), ResponseType.RightClick,
                buildBrowserDesktopMenuOptions())
          }, (shortcut: ShortcutRecord) => shortcut.id)
          if (this.hasAddEntry()) {
            Row() { this.buildAddEntryCard() }
              .width(this.slotFor('__home_add__').width)
              .height(this.slotFor('__home_add__').height)
              .position({ x: this.slotFor('__home_add__').x, y: this.slotFor('__home_add__').y })
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
              .animation({ duration: 320, curve: Curve.EaseInOut })
          }
          if (this.showPinnedSettingsEntry && !this.extracting) {
            Row() { this.buildPinnedSettingsCard() }
              .width(this.slotFor('__home_settings__').width).height(this.slotFor('__home_settings__').height)
              .position({ x: this.slotFor('__home_settings__').x, y: this.slotFor('__home_settings__').y })
          }
          if (this.floatingRecord.id.length > 0 && (this.containerParentId.length === 0 || this.extracting)) {
            Row() { this.buildShortcutCard(this.floatingRecord) }
              .width(this.dragStartSlot?.width ?? this.resolveShortcutCardWidth())
              .height(this.dragStartSlot?.height ?? this.resolveShortcutRowHeight())
              .justifyContent(FlexAlign.Center)
              .alignItems(VerticalAlign.Top)
              .position({ x: this.floatX, y: this.floatY })
              .scale({ x: this.floatingScale, y: this.floatingScale, centerX: '50%', centerY: this.resolveShortcutContainerSize() / 2 })
              .animation(this.settling ? { duration: 220, curve: Curve.EaseInOut } : undefined)
              .zIndex(20)
              .hitTestBehavior(HitTestMode.None)
          }
        }
        .width(this.resolveShortcutListWidth())
        .height(this.getGridContentHeight())
        .id(this.instanceId)
        .clip(false)
        .translate({ x: this.extractionOffsetX, y: this.extractionOffsetY + this.contentOffsetY })
        .opacity(this.folderCoverVisible ? 0 : 1)
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
    .id(`${this.instanceId}-host`)
    .alignItems(
      this.extracting || this.alignPartialRowsToStart &&
        (this.liveShortcuts.length > 0 || this.showAddEntry || this.showPinnedSettingsEntry)
        ? HorizontalAlign.Start
        : HorizontalAlign.Center
    )
    .padding({ left: this.contentInset, right: this.contentInset })
    .bindContentCover(this.folderCoverVisible, this.buildFolderCover(), {
      modalTransition: ModalTransition.NONE,
      backgroundColor: Color.Transparent,
      onWillDismiss: () => { this.closeFolder(); },
      onDisappear: () => {
        this.clearFolderAnimation(); this.folderCoverVisible = false; this.openFolderId = '';
        this.folderFloating = { x: 0, y: 0, size: 0, settling: false };
      }
    })
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
          .opacity(this.floatingIntoFolder && this.floatingRecord.id === shortcut.id ? 0 : 1)
      }
    }
    .width(this.slotFor(shortcut.id).width)
    .height(this.slotFor(shortcut.id).height)
    .justifyContent(FlexAlign.Start)
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
    Stack() {
      if (shortcut.kind === 'folder') {
        this.buildFolderPreview(shortcut)
      } else {
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
    }
    .width(this.iconSizeFor(shortcut))
    .height(this.iconSizeFor(shortcut))
    .id(`${this.instanceId}-${shortcut.id}`)
    .borderRadius(shortcut.kind === 'folder' ? 22 : this.resolveShortcutMaterialRadius(this.iconSizeFor(shortcut)))
    .border({ width: this.isCenterTarget(shortcut.id) ? 1 : 0, color: '#57FFFFFF' })
    .shadow({ radius: this.isCenterTarget(shortcut.id) ? 6 : 0,
      color: this.isCenterTarget(shortcut.id) ? '#38E8ECF0' : '#00000000' })
    .scale({ x: this.isCenterTarget(shortcut.id) ? 1.02 : 1, y: this.isCenterTarget(shortcut.id) ? 1.02 : 1 })
    .brightness(this.isCenterTarget(shortcut.id) ? 1.04 : 1)
    .animation({ duration: 150, curve: Curve.Ease })
  }

  @Builder
  private buildFolderPreview(shortcut: ShortcutRecord) {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.folderService.listContainer(this.effectiveRecords(), shortcut.id).slice(0, this.folderPreviewCount(shortcut)),
        (child: ShortcutRecord, index: number) => {
          Row() {
            if (shortcut.folderDisplayMode === 'large' && index === 8) this.buildFolderOverflow(shortcut)
            else this.buildShortcutThumbnail(child, this.folderPreviewSize(shortcut))
          }
            .width(this.folderPreviewSize(shortcut))
            .height(this.folderPreviewSize(shortcut))
            .position({ x: 8 + (index % this.folderPreviewColumns(shortcut)) * (this.folderPreviewSize(shortcut) + 4),
              y: 8 + Math.floor(index / this.folderPreviewColumns(shortcut)) * (this.folderPreviewSize(shortcut) + 4) })
            .onClick(() => {
              if (shortcut.folderDisplayMode === 'large') this.handlePreviewChildClick(shortcut, child, index);
              else this.openFolder(shortcut);
            })
            .opacity((this.folderCoverVisible && this.openFolderId === shortcut.id) || this.floatingRecord.id === child.id ? 0 : 1)
        }, (child: ShortcutRecord) => child.id)
    }
    .width(this.iconSizeFor(shortcut))
    .height(this.iconSizeFor(shortcut))
    .backgroundColor(this.storedFloatingSurfaceColor)
    .borderRadius(22)
    .border({ width: 1, color: this.storedOutlineColor })
  }

  @Builder
  private buildFolderOverflow(folder: ShortcutRecord) {
    Stack({ alignContent: Alignment.TopStart }) {
      ForEach(this.folderService.listContainer(this.effectiveRecords(), folder.id).slice(8, 12),
        (child: ShortcutRecord, index: number) => {
          Row() { this.buildShortcutThumbnail(child, (this.folderPreviewSize(folder) - 2) / 2) }
            .position({ x: (index % 2) * (this.folderPreviewSize(folder) + 2) / 2,
              y: Math.floor(index / 2) * (this.folderPreviewSize(folder) + 2) / 2 })
        }, (child: ShortcutRecord) => child.id)
    }.width(this.folderPreviewSize(folder)).height(this.folderPreviewSize(folder))
  }

  @Builder
  private buildShortcutThumbnail(shortcut: ShortcutRecord, size: number) {
    if (hasBundledShortcutIcon(shortcut.url)) {
      this.buildBundledShortcutIcon(shortcut, size)
    } else if (isHomeSystemShortcut(shortcut)) {
      this.buildOwnedShortcutIcon(this.resolveSystemShortcutIcon(shortcut), size, Math.max(10, size * 0.7))
    } else {
      this.buildShortcutSiteIcon(shortcut, size, Math.max(8, size * 0.5))
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
      ForEach(this.resolveContextActions(shortcut), (item: HomeShortcutContextAction) => {
        this.buildDesktopShortcutContextMenuItem(shortcut, item.id, item.title)
      }, (item: HomeShortcutContextAction) => item.id)

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
          this.handleContextAction(shortcut, actionId);
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
              this.handleContextAction(shortcut, item.id);
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

  private containerShortcuts(): ShortcutRecord[] {
    const records = this.effectiveRecords();
    const parent = this.extracting ? '' : this.containerParentId;
    if (records !== this.containerCacheRecords || parent !== this.containerCacheParent) {
      this.containerCache = this.folderService.listContainer(records, parent);
      this.containerCacheRecords = records;
      this.containerCacheParent = parent;
    }
    return this.containerCache;
  }

  private projectedShortcuts(): ShortcutRecord[] {
    const items = this.containerShortcuts();
    const ids = this.dragState.orderedIds;
    if (items === this.projectedCacheItems && ids === this.projectedCacheIds) return this.projectedCache;
    const byId = new Map<string, ShortcutRecord>();
    items.forEach((item: ShortcutRecord): void => { byId.set(item.id, item); });
    this.projectedCacheItems = items;
    this.projectedCacheIds = ids;
    this.projectedCache = ids.length === items.length && new Set(ids).size === items.length &&
      ids.every((id: string): boolean => byId.has(id))
      ? ids.map((id: string): ShortcutRecord => byId.get(id) as ShortcutRecord) : items;
    return this.projectedCache;
  }

  private currentGridSpec(): HomeShortcutGridSpec {
    if (this.extracting && this.extractionAnchor) return this.extractionAnchor.spec;
    const width = this.resolveShortcutListWidth();
    const columns = this.resolveShortcutLaneCount();
    const lane = (width - (columns - 1) * this.resolveShortcutColumnGap()) / columns;
    const mixed = this.containerShortcuts().some((item: ShortcutRecord): boolean =>
      item.kind === 'folder' && item.folderDisplayMode === 'large');
    return { columns: columns, width: width, columnGap: this.resolveShortcutColumnGap(),
      rowGap: this.metrics.rowGap, iconSize: this.resolveShortcutContainerSize(),
      rowHeight: this.containerParentId.length > 0 ? Math.max(80, lane) :
        mixed ? Math.max(lane, this.resolveShortcutRowHeight()) : this.resolveShortcutRowHeight(),
      pinnedSettings: this.showPinnedSettingsEntry, centerPartialRows: this.centerPartialRows };
  }

  private currentGridLayout(): HomeShortcutGridLayout {
    const spec = this.currentGridSpec();
    const items = this.projectedShortcuts();
    const key = JSON.stringify(spec) + (this.hasAddEntry() ? '+' : '-');
    if (key !== this.layoutCacheKey || items !== this.layoutCacheItems) {
      this.layoutCacheItems = items;
      this.layoutCache = this.gridPolicy.layout(items, spec, this.hasAddEntry());
      this.slotCache.clear();
      this.layoutCache.slots.forEach((slot: HomeShortcutGridSlot): void => { this.slotCache.set(slot.id, slot); });
      this.layoutCacheKey = key;
    }
    return this.layoutCache;
  }

  private slotFor(id: string): HomeShortcutGridSlot {
    this.currentGridLayout();
    return this.slotCache.get(id) ??
      { id: id, x: 0, y: 0, width: this.resolveShortcutLaneWidth(), height: this.resolveShortcutRowHeight(), span: 1 };
  }

  private iconSizeFor(shortcut: ShortcutRecord): number {
    const base = this.resolveShortcutContainerSize();
    return shortcut.kind === 'folder' && shortcut.folderDisplayMode === 'large' && this.resolveShortcutLaneCount() >= 2
      ? base + this.resolveShortcutLaneWidth() + this.resolveShortcutColumnGap() : base;
  }

  private folderPreviewColumns(shortcut: ShortcutRecord): number { return shortcut.folderDisplayMode === 'large' ? 3 : 2; }
  private folderPreviewCount(shortcut: ShortcutRecord): number { return shortcut.folderDisplayMode === 'large' ? 9 : 4; }
  private folderPreviewSize(shortcut: ShortcutRecord): number {
    const columns = this.folderPreviewColumns(shortcut);
    return Math.max(10, (this.iconSizeFor(shortcut) - 16 - (columns - 1) * 4) / columns);
  }

  private isCenterTarget(id: string): boolean { return this.dragState.center && this.dragState.targetId === id; }

  private clearDragTimers(): void {
    if (this.hoverTimer >= 0) clearInterval(this.hoverTimer);
    if (this.settleTimer >= 0) clearTimeout(this.settleTimer);
    this.hoverTimer = -1;
    this.settleTimer = -1;
  }

  private effectiveRecords(): ShortcutRecord[] { return this.extracting ? this.extractionRecords : this.liveShortcuts; }
  private hasAddEntry(): boolean { return this.extracting ? this.extractionAnchor?.addEntry ?? false : this.showAddEntry; }

  private gridViewport(): HomeShortcutDragViewport | undefined { return this.nodeViewport(this.instanceId); }

  private nodeViewport(id: string): HomeShortcutDragViewport | undefined {
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(id);
      return { x: this.getUIContext().px2vp(rect.windowOffset.x), y: this.getUIContext().px2vp(rect.windowOffset.y),
        width: this.getUIContext().px2vp(rect.size.width), height: this.getUIContext().px2vp(rect.size.height) };
    } catch (_error) { return undefined; }
  }

  private rootGridAnchor(records: ShortcutRecord[]): HomeShortcutGridAnchor | undefined {
    const measured = this.gridViewport();
    if (!measured) return undefined;
    const items = this.folderService.listContainer(records);
    const count = this.gridPolicy.footprint(items) + (this.showAddEntry ? 1 : 0) + (this.showPinnedSettingsEntry ? 1 : 0);
    const columns = this.viewModel.resolveOccupiedColumnCount(count, this.metrics);
    const width = this.viewModel.getOccupiedGridContentWidth(count, this.gridWidth, this.contentInset, this.metrics);
    const gap = this.resolveShortcutColumnGap();
    const lane = (width - (columns - 1) * gap) / columns;
    const mixed = items.some((item: ShortcutRecord): boolean => item.kind === 'folder' && item.folderDisplayMode === 'large');
    return { x: measured.x + (this.alignPartialRowsToStart ? 0 : (measured.width - width) / 2), y: measured.y,
      addEntry: this.showAddEntry,
      spec: { width: width, columns: columns, columnGap: gap, rowGap: this.metrics.rowGap,
        pinnedSettings: this.showPinnedSettingsEntry,
        iconSize: this.resolveShortcutContainerSize(),
        rowHeight: mixed ? Math.max(lane, this.resolveShortcutRowHeight()) : this.resolveShortcutRowHeight(),
        centerPartialRows: this.centerPartialRows } };
  }

  private startProjectedDrag(shortcut: ShortcutRecord, event: GestureEvent): void {
    if (!this.allowMutations || this.settling) return;
    const origin = this.gridViewport();
    if (!origin) return;
    this.clearDragTimers();
    this.contextMenuShortcutId = '';
    this.pressedShortcutId = '';
    this.dragConsumedShortcutId = shortcut.id;
    this.frozenIconsVersion = this.iconsVersion;
    this.longPressedShortcutId = '';
    this.shortcutDragActive = true;
    HomeShortcutInteractionFeedbackService.performContextMenuFeedback();
    this.floatingScale = 1;
    this.floatingIntoFolder = false;
    this.dragStartSlot = this.slotFor(shortcut.id);
    this.dragWindowStartX = origin.x + this.dragStartSlot.x + (this.dragStartSlot.width - this.iconSizeFor(shortcut)) / 2;
    this.dragWindowStartY = origin.y + this.dragStartSlot.y;
    this.floatingRecord = shortcut;
    this.extractionOutsideSince = -1;
    this.dragSpecSignature = JSON.stringify(this.currentGridSpec());
    this.dragSession.begin(shortcut.id, this.containerShortcuts(), this.currentGridSpec(), this.containerParentId, this.hasAddEntry());
    this.updateProjectedDrag(event);
    this.hoverTimer = setInterval(() => { this.refreshDragIntent(true); }, 25);
  }

  private updateProjectedDrag(event: GestureEvent): void {
    if (this.floatingRecord.id.length === 0 || !this.dragStartSlot || this.settling) return;
    this.dragWindowX = this.dragWindowStartX + event.offsetX;
    this.dragWindowY = this.dragWindowStartY + event.offsetY;
    this.refreshDragIntent();
  }

  private refreshDragIntent(autoScroll: boolean = false): void {
    if (!this.dragStartSlot || this.settling) return;
    if (!this.extracting && JSON.stringify(this.currentGridSpec()) !== this.dragSpecSignature) { this.cancelProjectedDrag(); return; }
    const now = Date.now();
    const viewport = this.extracting ? this.getRootDragViewport() : this.getDragViewport();
    if (viewport) {
      const centerX = this.dragWindowX + this.iconSizeFor(this.floatingRecord) / 2;
      const centerY = this.dragWindowY + this.iconSizeFor(this.floatingRecord) / 2;
      const outside = this.containerParentId.length > 0 && !this.extracting && this.dragGeometry.outside(centerX, centerY, viewport);
      if (outside) {
        if (this.extractionOutsideSince < 0) this.extractionOutsideSince = now;
        if (now - this.extractionOutsideSince >= 500) this.beginFolderExtraction();
      } else {
        this.extractionOutsideSince = -1;
        const delta = this.dragGeometry.scrollStep(centerY, viewport);
        if (delta !== 0 && autoScroll) {
          if (this.extracting) this.onRootDragScroll(delta);
          else this.onDragScroll(delta);
        }
      }
    }
    if (this.extracting) {
      const anchor = this.resolveRootGrid(this.extractionRecords);
      if (anchor && JSON.stringify(anchor.spec) !== this.dragSpecSignature) { this.cancelProjectedDrag(); return; }
      if (anchor && JSON.stringify(anchor) !== JSON.stringify(this.extractionAnchor)) this.extractionAnchor = anchor;
    }
    const measured = this.extracting ? this.nodeViewport(`${this.instanceId}-host`) : this.gridViewport();
    const origin = this.extracting ? this.extractionAnchor : measured;
    if (!origin || !this.dragStartSlot) return;
    if (this.extracting && measured) {
      // The host stays in the folder; only its grid is translated, preserving the gesture node.
      this.extractionOffsetX = origin.x - measured.x;
      this.extractionOffsetY = origin.y - measured.y;
    }
    this.floatX = this.dragWindowX - origin.x - (this.dragStartSlot.width - this.iconSizeFor(this.floatingRecord)) / 2;
    this.floatY = this.dragWindowY - origin.y;
    if (this.containerParentId.length > 0 && !this.extracting) this.onFolderFloatingIcon({
      shortcut: this.floatingRecord, x: this.dragWindowX, y: this.dragWindowY,
      size: this.iconSizeFor(this.floatingRecord), settling: false });
    this.lastDragX = this.floatX - this.dragStartSlot.x;
    this.lastDragY = this.floatY - this.dragStartSlot.y;
    const next = this.dragSession.update({ x: this.lastDragX, y: this.lastDragY }, now);
    if (JSON.stringify(next) !== JSON.stringify(this.dragState)) this.dragState = next;
  }

  private beginFolderExtraction(): boolean {
    if (this.extracting || this.containerParentId.length === 0) return this.extracting;
    const preview = this.folderService.apply(this.liveShortcuts,
      { operation: 'move', shortcutId: this.floatingRecord.id, parentId: '' }, '', Date.now());
    const anchor = this.resolveRootGrid(preview.shortcuts);
    if (!preview.changed || !anchor) return false;
    this.extractionRecords = preview.shortcuts;
    this.extractionAnchor = anchor;
    this.extracting = true;
    this.dragState = { activeId: '', targetId: '', center: false, orderedIds: [] };
    this.dragStartSlot = this.slotFor(this.floatingRecord.id);
    this.dragSpecSignature = JSON.stringify(anchor.spec);
    this.dragSession.begin(this.floatingRecord.id, this.containerShortcuts(), anchor.spec, '', anchor.addEntry);
    this.onFolderFloatingIcon({ x: 0, y: 0, size: 0, settling: false });
    this.onExtractionChanged(true);
    return true;
  }

  private finishProjectedDrag(event: GestureEvent): void {
    if (this.floatingRecord.id.length === 0 || this.settling) return;
    this.updateProjectedDrag(event);
    this.clearDragTimers();
    if (!this.extracting && this.extractionOutsideSince >= 0) this.beginFolderExtraction();
    if (this.extracting) {
      // The extraction, root order and optional new drop target form one mutation.
      this.settling = true;
      const drop = this.dragSession.release();
      const command: HomeShortcutFolderCommand = { operation: 'extract', shortcutId: this.floatingRecord.id,
        dropOperation: drop?.operation === 'merge' ? 'merge' : drop?.operation === 'move' ? 'move' : undefined,
        parentId: drop?.parentId, targetId: drop?.targetId,
        orderedIds: this.dragSession.snapshot().orderedIds,
        createdFolderId: drop?.operation === 'merge' ? `home-folder-${util.generateRandomUUID()}` : undefined };
      const preview = this.folderService.apply(this.liveShortcuts, command, command.createdFolderId ?? '', Date.now());
      if (preview.changed) this.extractionRecords = preview.shortcuts;
      const target = this.slotFor(command.dropOperation === 'merge' ? command.createdFolderId ?? '' :
        command.dropOperation === 'move' ? command.parentId ?? '' : this.floatingRecord.id);
      this.floatX = target.x; this.floatY = target.y;
      if (command.dropOperation) { this.floatingIntoFolder = true; this.floatingScale = 0.3; }
      this.dispatchFolderCommand(command);
      this.settleTimer = setTimeout(() => { this.cancelProjectedDrag(); }, 220);
      return;
    }
    const command = this.dragSession.release();
    this.settling = true;
    if (command) {
      if (command.operation === 'merge') {
        command.createdFolderId = `home-folder-${util.generateRandomUUID()}`;
        command.title = resolveAppResourceText($r('app.string.home_shortcut_folder_default'));
      }
      const preview = this.folderService.apply(this.liveShortcuts, command, command.createdFolderId ?? '', Date.now());
      if (preview.changed) this.liveShortcuts = preview.shortcuts;
      this.dispatchFolderCommand(command);
    }
    if (command?.operation === 'merge' || command?.operation === 'move') {
      this.floatingIntoFolder = true;
      const folderId = command.operation === 'merge' ? command.createdFolderId ?? '' : command.parentId ?? '';
      const folder = this.liveShortcuts.find((item: ShortcutRecord): boolean => item.id === folderId);
      const target = this.slotFor(folderId);
      const index = this.folderService.listContainer(this.liveShortcuts, folderId)
        .findIndex((item: ShortcutRecord): boolean => item.id === this.floatingRecord.id);
      if (folder && index >= 0) {
        const frame = this.folderMotion.previewChild({ x: target.x + (target.width - this.iconSizeFor(folder)) / 2,
          y: target.y, size: this.iconSizeFor(folder) }, index, folder.folderDisplayMode === 'large');
        this.floatingScale = frame.size / this.resolveShortcutContainerSize();
        this.floatX = frame.x + frame.size / 2 - (this.dragStartSlot?.width ?? target.width) / 2;
        this.floatY = frame.y + frame.size / 2 - this.resolveShortcutContainerSize() / 2;
      }
    } else {
      const target = this.slotFor(this.floatingRecord.id);
      this.floatX = target.x; this.floatY = target.y;
    }
    if (this.containerParentId.length > 0) {
      const origin = this.gridViewport();
      if (origin) this.onFolderFloatingIcon({ shortcut: this.floatingRecord,
        x: origin.x + this.floatX + ((this.dragStartSlot?.width ?? 0) - this.resolveShortcutContainerSize()) / 2,
        y: origin.y + this.floatY, size: this.resolveShortcutContainerSize(), settling: true });
    }
    this.dragSession.cancel();
    this.settleTimer = setTimeout(() => { this.cancelProjectedDrag(); }, 220);
  }

  private cancelProjectedDrag(): void {
    const wasExtracting = this.extracting;
    this.clearDragTimers();
    this.dragSession.cancel();
    this.dragState = { activeId: '', targetId: '', center: false, orderedIds: [] };
    this.floatingRecord = { id: '', title: '', url: '', folderName: '', position: 0 };
    this.settling = false;
    this.extracting = false;
    this.extractionRecords = [];
    this.extractionAnchor = undefined;
    this.extractionOffsetX = 0; this.extractionOffsetY = 0;
    this.extractionOutsideSince = -1;
    this.onFolderFloatingIcon({ x: 0, y: 0, size: 0, settling: false });
    this.endNativeDrag();
    if (wasExtracting) { this.onExtractionChanged(false); this.onExtractToRoot(); }
  }

  private dispatchFolderCommand(command: HomeShortcutFolderCommand): void {
    if (!this.allowMutations) return;
    if ((command.operation === 'merge' || command.dropOperation === 'merge') && !command.createdFolderId) command.createdFolderId = `home-folder-${util.generateRandomUUID()}`;
    this.onAction({ type: 'folder_mutation', command: command });
  }

  private handleContextAction(shortcut: ShortcutRecord, action: HomeShortcutContextActionId): void {
    if (action === 'open' && shortcut.kind === 'folder') this.openFolder(shortcut);
    else if (action === 'rename_folder') this.openFolder(shortcut, true);
    else if (action === 'toggle_folder_size') this.dispatchFolderCommand({ operation: 'resize', shortcutId: shortcut.id, large: shortcut.folderDisplayMode !== 'large' });
    else if (action === 'dissolve_folder') this.dispatchFolderCommand({ operation: 'dissolve', shortcutId: shortcut.id });
    else if (action === 'move_out') this.dispatchFolderCommand({ operation: 'move', shortcutId: shortcut.id, parentId: '' });
    else this.onAction({ type: 'shortcut_action', shortcutId: shortcut.id, actionId: action });
  }

  private handlePreviewChildClick(folder: ShortcutRecord, child: ShortcutRecord, index: number): void {
    if (this.shortcutDragActive || this.dragConsumedShortcutId.length > 0) return;
    if (index === 8) this.openFolder(folder);
    else this.onAction({ type: 'shortcut_action', shortcutId: child.id, actionId: 'open' });
  }

  private sourceFolderFrame(shortcut: ShortcutRecord): HomeShortcutFolderFrame {
    try {
      const rect = this.getUIContext().getComponentUtils().getRectangleById(`${this.instanceId}-${shortcut.id}`);
      return { x: this.getUIContext().px2vp(rect.windowOffset.x) - this.folderCoverOriginX,
        y: this.getUIContext().px2vp(rect.windowOffset.y) - this.folderCoverOriginY,
        size: this.getUIContext().px2vp(rect.size.width) };
    } catch (_error) { return { x: 24, y: 120, size: this.iconSizeFor(shortcut) }; }
  }

  private clearFolderAnimation(): number {
    this.folderAnimationGeneration++;
    if (this.folderAnimationTimer >= 0) clearTimeout(this.folderAnimationTimer);
    this.folderAnimationTimer = -1;
    return this.folderAnimationGeneration;
  }

  private openFolder(shortcut: ShortcutRecord, rename: boolean = false): void {
    if (this.containerParentId.length > 0 || this.shortcutDragActive || shortcut.kind !== 'folder') return;
    this.clearFolderAnimation();
    this.folderCoverOriginX = 0; this.folderCoverOriginY = 0;
    this.folderScrollY = 0;
    this.folderExtracting = false;
    this.folderSource = this.sourceFolderFrame(shortcut);
    this.openFolderId = shortcut.id;
    this.folderTitleDraft = shortcut.title;
    this.folderRenameRequested = rename;
    this.folderClosing = false;
    this.folderAnimating = true;
    this.folderProgress = 0;
    this.folderCoverVisible = true;
  }

  private closeFolder(): void {
    if (!this.folderCoverVisible || this.folderClosing || this.shortcutDragActive) return;
    if (this.folderTitleDraft.trim().length > 0 && this.folderTitleDraft.trim() !== this.currentFolder().title) {
      this.dispatchFolderCommand({ operation: 'rename', shortcutId: this.openFolderId, title: this.folderTitleDraft });
    }
    this.folderSource = this.sourceFolderFrame(this.currentFolder());
    const generation = this.clearFolderAnimation();
    this.folderClosing = true;
    this.folderAnimating = true;
    this.folderAnimationTimer = setTimeout(() => {
      if (generation !== this.folderAnimationGeneration) return;
      this.getUIContext().animateTo({ duration: 550, curve: curves.cubicBezierCurve(0.32, 0.72, 0, 1) }, () => { this.folderProgress = 0; });
      this.folderAnimationTimer = setTimeout(() => {
        if (generation !== this.folderAnimationGeneration) return;
        this.folderCoverVisible = false; this.openFolderId = ''; this.folderAnimating = false;
      }, 550);
    }, 16);
  }

  private currentFolder(): ShortcutRecord {
    return this.liveShortcuts.find((item: ShortcutRecord): boolean => item.id === this.openFolderId) ??
      { id: this.openFolderId, kind: 'folder', title: '', url: '', folderName: '', position: 0 };
  }

  private folderPanelWidth(): number { return Math.max(240, Math.min(520, this.folderViewportWidth - 32)); }
  private folderPanelX(): number { return (this.folderViewportWidth - this.folderPanelWidth()) / 2; }
  private folderPanelY(): number { return Math.max(72, this.folderViewportHeight * 0.16); }
  private folderColumns(): number { return Math.max(2, Math.min(4, Math.floor(this.folderPanelWidth() / 80))); }
  private folderGridSpec(): HomeShortcutGridSpec {
    return { columns: this.folderColumns(), width: this.folderPanelWidth(), columnGap: 0, rowGap: 12,
      rowHeight: Math.max(80, this.folderPanelWidth() / this.folderColumns()), centerPartialRows: false };
  }

  private folderMetrics(): HomeShortcutLayoutMetrics {
    return { columns: this.folderColumns(), columnGap: 0, rowGap: 12, targetTileSize: this.resolveShortcutContainerSize(),
      minimumTileSize: this.resolveShortcutContainerSize(), fallbackColumnWidth: 80, titleTopGap: 4, titleBlockHeight: 18 };
  }

  private folderGhostFrame(child: ShortcutRecord, index: number): HomeShortcutFolderFrame {
    const children = this.folderService.listContainer(this.liveShortcuts, this.openFolderId);
    const slot = this.gridPolicy.layout(children, this.folderGridSpec()).slots[index];
    const source = this.folderMotion.previewChild(this.folderSource, index, this.currentFolder().folderDisplayMode === 'large');
    if (!slot) return source;
    const target = this.folderMotion.expandedChild(slot, this.folderPanelX(), this.folderPanelY() - this.folderScrollY, this.resolveShortcutContainerSize());
    return this.folderMotion.interpolate(source, target,
      this.folderMotion.childProgress(this.folderProgress, index, this.folderClosing));
  }

  @Builder
  private buildFolderCover() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {}
        .width('100%').height('100%')
        .backgroundColor('#33000000')
        .backdropBlur(24)
        .opacity(this.folderExtracting ? 0 : this.folderProgress)
        .onClick(() => { this.closeFolder(); })
      Column() {}
        .width(this.folderSource.size + (this.folderPanelWidth() - this.folderSource.size) * this.folderProgress)
        .height(this.folderSource.size + (Math.min(this.folderViewportHeight - this.folderPanelY() - 48,
          this.gridPolicy.layout(this.folderService.listContainer(this.liveShortcuts, this.openFolderId), this.folderGridSpec()).height + 64) - this.folderSource.size) * this.folderProgress)
        .position({ x: this.folderSource.x + (this.folderPanelX() - this.folderSource.x) * this.folderProgress,
          y: this.folderSource.y + (this.folderPanelY() - this.folderSource.y) * this.folderProgress })
        .borderRadius(22 + 10 * this.folderProgress)
        .border({ width: this.shortcutDragActive ? 2.5 : 1, color: this.shortcutDragActive ? '#4DFFFFFF' : '#20FFFFFF' })
        .backgroundColor('#0DFFFFFF')
        .opacity(this.folderExtracting ? 0 : 1)
        .hitTestBehavior(HitTestMode.None)
      if (this.folderAnimating) {
        Text(this.folderTitleDraft)
          .fontSize(12 + 10 * this.folderProgress).fontColor(this.resolvePrimaryTextColor())
          .width(this.folderPanelWidth()).textAlign(TextAlign.Center)
          .position({ x: this.folderSource.x + this.folderSource.size / 2 - this.folderPanelWidth() / 2 +
              (this.folderPanelX() - this.folderSource.x - this.folderSource.size / 2 + this.folderPanelWidth() / 2) * this.folderProgress,
            y: this.folderSource.y + this.folderSource.size + 4 +
              (this.folderPanelY() + 12 - this.folderSource.y - this.folderSource.size - 4) * this.folderProgress })
          .opacity(this.folderProgress)
          .hitTestBehavior(HitTestMode.None)
      }

      Column() {
        Row() {
          TextInput({ text: this.folderTitleDraft })
            .fontSize(22).fontWeight(FontWeight.Medium)
            .fontColor(this.resolvePrimaryTextColor())
            .backgroundColor(Color.Transparent)
            .height(48).layoutWeight(1)
            .defaultFocus(this.folderRenameRequested)
            .enabled(this.allowMutations)
            .onChange((value: string) => { this.folderTitleDraft = value; })
          Button(resolveAppResourceText($r('app.string.ui_close')))
            .type(ButtonType.Normal).borderRadius(22).height(44)
            .onClick(() => { this.closeFolder(); })
        }.height(64).width('100%').opacity(this.folderExtracting ? 0 : 1)
        Scroll(this.folderScroller) {
          HomeShortcutSurface({
            shortcuts: this.liveShortcuts, shortcutOrderSignature: this.viewModel.buildShortcutOrderSignature(this.liveShortcuts),
            icons: this.icons, iconsVersion: this.iconsVersion,
            containerParentId: this.openFolderId, allowMutations: this.allowMutations, metrics: this.folderMetrics(),
            gridWidth: this.folderPanelWidth(), contentInset: 0,
            primaryTextColor: this.primaryTextColor, secondaryTextColor: this.secondaryTextColor,
            showAddEntry: false, iconCornerRadiusRatio: this.iconCornerRadiusRatio,
            textShadow: this.textShadow, contextMenuShortcutId: $contextMenuShortcutId,
            shortcutDragActive: $shortcutDragActive,
            onAction: (action: HomeShortcutUserAction) => { this.onAction(action); },
            getDragViewport: () => this.nodeViewport(`${this.instanceId}-folder-scroll`),
            onDragScroll: (delta: number) => { this.folderScroller.scrollBy(0, delta); },
            getRootDragViewport: this.getDragViewport,
            onRootDragScroll: this.onDragScroll,
            onFolderFloatingIcon: (floating: HomeShortcutFloatingIcon) => {
              if (floating.shortcut?.id !== this.folderFloating.shortcut?.id || floating.x !== this.folderFloating.x ||
                floating.y !== this.folderFloating.y || floating.size !== this.folderFloating.size ||
                floating.settling !== this.folderFloating.settling) this.folderFloating = floating;
            },
            resolveRootGrid: (records: ShortcutRecord[]) => this.rootGridAnchor(records),
            onExtractionChanged: (active: boolean) => { this.folderExtracting = active; },
            onExtractToRoot: () => { this.folderCoverVisible = false; this.openFolderId = ''; this.folderExtracting = false; }
          })
        }.width('100%').height(Math.max(160, this.folderViewportHeight - this.folderPanelY() - 110))
        .id(`${this.instanceId}-folder-scroll`)
        .clip(!this.folderExtracting)
        .scrollBar(BarState.Off)
        .onDidScroll(() => { this.folderScrollY = this.folderScroller.currentOffset().yOffset; })
        .enableScrollInteraction(!this.shortcutDragActive)
      }
      .width(this.folderPanelWidth())
      .position({ x: this.folderPanelX(), y: this.folderPanelY() })
      .opacity(!this.folderAnimating && !this.folderClosing ? 1 : 0)
      .hitTestBehavior(!this.folderAnimating && !this.folderClosing ? HitTestMode.Default : HitTestMode.None)
      ForEach(this.folderService.listContainer(this.liveShortcuts, this.openFolderId), (child: ShortcutRecord, index: number) => {
        if (this.folderAnimating) {
          Row() { this.buildShortcutThumbnail(child, this.resolveShortcutContainerSize()) }
            .width(this.resolveShortcutContainerSize()).height(this.resolveShortcutContainerSize())
            .scale({ x: this.folderGhostFrame(child, index).size / this.resolveShortcutContainerSize(),
              y: this.folderGhostFrame(child, index).size / this.resolveShortcutContainerSize() })
            .position({ x: this.folderGhostFrame(child, index).x + (this.folderGhostFrame(child, index).size - this.resolveShortcutContainerSize()) / 2,
              y: this.folderGhostFrame(child, index).y + (this.folderGhostFrame(child, index).size - this.resolveShortcutContainerSize()) / 2 })
            .animation({ duration: this.folderClosing ? 400 : 600, delay: Math.min(index, 7) * 18,
              curve: this.folderClosing ? curves.cubicBezierCurve(0.32, 0.72, 0, 1) : curves.cubicBezierCurve(0.215, 0.61, 0.355, 1) })
            .opacity(index >= (this.currentFolder().folderDisplayMode === 'large' ? 12 : 4) ? this.folderProgress : 1)
            .hitTestBehavior(HitTestMode.None)
        }
        if (this.folderAnimating && this.storedShowShortcutNames) {
          Text(this.resolveShortcutDisplayTitle(child))
            .width(this.folderPanelWidth() / this.folderColumns()).height(18)
            .fontSize(12).fontColor(this.resolvePrimaryTextColor()).textAlign(TextAlign.Center)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .position({ x: this.folderGhostFrame(child, index).x + this.folderGhostFrame(child, index).size / 2 -
              this.folderPanelWidth() / this.folderColumns() / 2,
              y: this.folderGhostFrame(child, index).y + this.folderGhostFrame(child, index).size + 4 })
            .opacity(this.folderProgress)
            .animation({ duration: this.folderClosing ? 400 : 600, delay: Math.min(index, 7) * 18,
              curve: Curve.EaseInOut })
            .hitTestBehavior(HitTestMode.None)
        }
      }, (child: ShortcutRecord) => child.id)
      if (this.folderFloating.shortcut !== undefined) {
        Row() { this.buildShortcutThumbnail(this.folderFloating.shortcut, this.folderFloating.size) }
          .width(this.folderFloating.size).height(this.folderFloating.size)
          .position({ x: this.folderFloating.x - this.folderCoverOriginX, y: this.folderFloating.y - this.folderCoverOriginY })
          .animation(this.folderFloating.settling ? { duration: 220, curve: Curve.EaseInOut } : undefined)
          .zIndex(30).hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%').height('100%')
    .id(`${this.instanceId}-folder-cover`)
    .onAreaChange((_old: Area, area: Area) => {
      this.folderViewportWidth = Number(area.width);
      this.folderViewportHeight = Number(area.height);
    })
    .onAppear(() => {
      const generation = this.folderAnimationGeneration;
      this.folderAnimationTimer = setTimeout(() => {
        if (generation !== this.folderAnimationGeneration) return;
        const cover = this.nodeViewport(`${this.instanceId}-folder-cover`);
        if (cover) {
          this.folderCoverOriginX = cover.x; this.folderCoverOriginY = cover.y;
          this.folderSource = { x: this.folderSource.x - cover.x, y: this.folderSource.y - cover.y, size: this.folderSource.size };
        }
        this.getUIContext().animateTo({ duration: 765, curve: curves.cubicBezierCurve(0.215, 0.61, 0.355, 1) }, () => { this.folderProgress = 1; });
        this.folderAnimationTimer = setTimeout(() => {
          if (generation === this.folderAnimationGeneration) this.folderAnimating = false;
        }, 765);
      }, 32);
    })
  }

  private getGridContentHeight(): number {
    return this.currentGridLayout().height;
  }

  private resolveShortcutColumnGap(): number {
    if (this.extracting && this.extractionAnchor) return this.extractionAnchor.spec.columnGap;
    if (this.containerParentId.length > 0) return this.metrics.columnGap;
    const contentWidth = Math.max(1, this.gridWidth - this.contentInset * 2);
    return Math.max(
      this.metrics.columnGap,
      this.viewModel.getAlignedGridColumnGap(contentWidth, this.metrics)
    );
  }

  private resolvePresentationItemCount(): number {
    return this.gridPolicy.footprint(this.containerShortcuts()) +
      (this.hasAddEntry() ? 1 : 0) + (this.showPinnedSettingsEntry ? 1 : 0);
  }

  private resolveShortcutLaneCount(): number {
    if (this.extracting && this.extractionAnchor) return this.extractionAnchor.spec.columns;
    if (this.containerParentId.length > 0) return this.metrics.columns;
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
    if (this.extracting && this.extractionAnchor) return this.extractionAnchor.spec.width;
    if (this.containerParentId.length > 0) return this.gridWidth;
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
    if (this.extracting && this.extractionAnchor) return this.extractionAnchor.spec.iconSize ?? this.metrics.targetTileSize;
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

  private finishShortcutLongPress(shortcutId: string): void {
    if (this.longPressedShortcutId !== shortcutId || this.shortcutDragActive || this.settling) return;
    this.longPressedShortcutId = '';
    this.openShortcutContextMenu(shortcutId);
  }

  private openShortcutContextMenu(shortcutId: string): void {
    if (this.shortcutDragActive || this.dragConsumedShortcutId === shortcutId) {
      return;
    }
    HomeShortcutInteractionFeedbackService.performContextMenuFeedback();
    this.pressedShortcutId = shortcutId;
    this.contextMenuShortcutId = shortcutId;
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
    const previousMembers = this.containerShortcuts().map((item: ShortcutRecord): string => item.id).join('|');
    this.liveShortcuts = nextShortcuts;
    if (this.folderCoverVisible && !this.folderExtracting && !this.shortcutDragActive &&
      !this.liveShortcuts.some((item: ShortcutRecord): boolean => item.id === this.openFolderId && item.kind === 'folder')) {
      this.clearFolderAnimation(); this.folderCoverVisible = false; this.openFolderId = '';
    }
    if (this.shortcutDragActive && !this.settling && (this.extracting || previousMembers !==
      this.containerShortcuts().map((item: ShortcutRecord): string => item.id).join('|'))) this.cancelProjectedDrag();
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
    if (shortcut.kind === 'folder') { this.openFolder(shortcut); return; }
    this.onAction({ type: 'shortcut_action', shortcutId: shortcut.id, actionId: 'open' });
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
    if (!this.allowMutations) return [{ id: 'open', title: resolveAppResourceText($r('app.string.ui_open')), role: 'normal' }];
    if (shortcut.kind === 'folder') {
      return [
        { id: 'open', title: resolveAppResourceText($r('app.string.ui_open')), role: 'normal' },
        { id: 'rename_folder', title: resolveAppResourceText($r('app.string.home_shortcut_folder_rename')), role: 'normal' },
        { id: 'toggle_folder_size', title: resolveAppResourceText(shortcut.folderDisplayMode === 'large'
          ? $r('app.string.home_shortcut_folder_small') : $r('app.string.home_shortcut_folder_large')), role: 'normal' },
        { id: 'dissolve_folder', title: resolveAppResourceText($r('app.string.home_shortcut_folder_dissolve')), role: 'normal' }
      ];
    }
    if (this.containerParentId.length > 0) {
      return [
        { id: 'open', title: resolveAppResourceText($r('app.string.ui_open')), role: 'normal' },
        { id: 'move_out', title: resolveAppResourceText($r('app.string.home_shortcut_folder_move_out')), role: 'normal' },
        { id: 'delete', title: resolveAppResourceText($r('app.string.settings_delete')), role: 'destructive' }
      ];
    }
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
