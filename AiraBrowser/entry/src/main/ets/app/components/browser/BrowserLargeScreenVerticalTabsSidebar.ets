import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserLargeScreenTabProjection,
  BrowserLargeScreenTabStripPresentation
} from '../../../core/browser/BrowserLargeScreenTabStripViewModel';
import {
  BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP,
  resolveBrowserLargeScreenTabDisplayTitle
} from '../../../core/browser/BrowserLargeScreenTabTitleSlotPolicy';
import {
  BrowserLargeScreenTabContextActionId,
  BrowserLargeScreenTabStripIntent
} from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import {
  BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP,
  BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP
} from '../../../core/browser/BrowserLargeScreenVerticalTabsPolicy';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY,
  BROWSER_APPEARANCE_STORAGE_VERTICAL_TABS_ENABLED_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveSiteIconFallbackLabel } from '../../../common/utils/SiteIconFallbackUtils';
import {
  SiteIconListPresenter,
  SiteIconListResolvedIcon,
  SiteIconListRenderState,
  SiteIconListTarget
} from '../../../core/siteicons/SiteIconListPresenter';
import { AiraIcon } from '../common/AiraIcon';
import { SiteIconView } from '../common/SiteIconView';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem,
  buildBrowserDesktopMenuOptions
} from './BrowserDesktopContextMenu';
import {
  BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
  BROWSER_DESKTOP_MENU_TAB_STRIP_BLANK_WIDTH_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BrowserLargeScreenTabStripBlankMenuItem,
  BrowserLargeScreenTabStripBlankMenuModel,
  buildBrowserLargeScreenTabStripBlankMenuModel
} from '../../../core/browser/BrowserLargeScreenTabStripBlankAreaPolicy';
import {
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP } from '../../../core/browser/BrowserLargeScreenTitleBarTokens';
import {
  sharedBrowserLargeScreenWindowChromeService
} from '../../../services/browser/BrowserLargeScreenWindowChromeService';

const TAB_ICON_SIZE_VP: number = 16;
const TAB_ICON_SLOT_SIZE_VP: number = 36;
const TAB_ROW_HEIGHT_VP: number = 40;
const TAB_ROW_INSET_VP: number = 8;
const HEADER_BUTTON_SIZE_VP: number = 32;
const CLOSE_BUTTON_SIZE_VP: number = 22;
const CLOSE_ICON_SIZE_VP: number = 12;
const AUDIO_ICON_SIZE_VP: number = 14;
const PEEK_COLLAPSE_DELAY_MS: number = 80;
const PEEK_EXPAND_DURATION_MS: number = 260;
const PEEK_COLLAPSE_DURATION_MS: number = 220;

const DEFAULT_TAB_STRIP_PRESENTATION: BrowserLargeScreenTabStripPresentation = {
  allTabs: [],
  visibleTabs: [],
  hiddenTabIds: [],
  selectedTabId: '',
  overflowVisible: false,
  dragEnabled: false,
  hoverVisible: false,
  newTabVisible: false,
  titleBarHeightVp: BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP,
  titleButtonWidthVp: 0,
  windowMoveEnabled: false,
  availableWidthVp: 0,
  consumedWidthVp: 0
};

/**
 * PC vertical tab sidebar.
 *
 * Pinned open is an in-flow column. Collapsed is a fixed icon rail. Hover grows
 * only the region to the right of that rail; the icons stay put and the page
 * inset does not change. The pin control is the only layout-width change.
 */
@Component
export struct BrowserLargeScreenVerticalTabsSidebar {
  @Prop windowChromeLeaseId: string = '';
  @Prop windowMoveEnabled: boolean = false;
  @Prop headerHeightVp: number = 48;
  @Watch('syncSiteIcons')
  @Prop tabStrip: BrowserLargeScreenTabStripPresentation = DEFAULT_TAB_STRIP_PRESENTATION;
  @Prop recentlyClosed: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  @Watch('syncCollapsedPresentation')
  @Prop collapsed: boolean = true;
  onIntent: (intent: BrowserLargeScreenTabStripIntent) => void =
    (_intent: BrowserLargeScreenTabStripIntent): void => {};
  onSetCollapsed: (collapsed: boolean) => void = (_collapsed: boolean): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = '#5F6875';
  @StorageProp(BROWSER_APPEARANCE_STORAGE_VERTICAL_TABS_ENABLED_KEY)
  private storedVerticalTabsEnabled: boolean = true;

  @State private hoveredTabId: string = '';
  @State private sidebarWidthVp: number = BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP;
  @State private tabIconStates: SiteIconListRenderState[] = [];
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();
  private hoverInside: boolean = false;
  private shieldHovered: boolean = false;
  private peekCollapseTimer: number = -1;
  private lastRowActionKey: string = '';
  private lastRowActionAtMs: number = 0;

  aboutToAppear(): void {
    this.sidebarWidthVp = this.collapsed
      ? BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP
      : BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP;
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
    this.syncSiteIcons();
  }

  aboutToDisappear(): void {
    this.clearPeekCollapseTimer();
    this.siteIconListPresenter.dispose();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildSidebarHoverShield()
      Column({ space: 0 }) {
      this.buildHeader()
      Divider()
        .strokeWidth(1)
        .color(this.storedDividerColor)
        .margin({ left: 12, right: 12 })
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.tabStrip.allTabs, (tab: BrowserLargeScreenTabProjection): void => {
            this.buildTabHoverPlate(tab)
          }, (tab: BrowserLargeScreenTabProjection): string =>
            `${tab.id}:${tab.active ? 'a' : ''}:${tab.pinned ? 'p' : ''}${tab.muted ? 'm' : ''}:${tab.title}`)
          this.buildNewTabHoverPlate()
        }
        .width('100%')
        .padding({ top: 6, bottom: 8 })
        .alignItems(HorizontalAlign.Start)
        .backgroundColor(this.storedPageBackgroundColor)
        .hitTestBehavior(HitTestMode.Default)
        .onHover((hovered: boolean): void => {
          if (hovered) {
            this.noteHover(true);
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .scrollable(ScrollDirection.Vertical)
      .backgroundColor(this.storedPageBackgroundColor)
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .hitTestBehavior(HitTestMode.Transparent)
    }
    .width(this.sidebarWidthVp)
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .clip(false)
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .border({
      width: { right: this.sidebarBorderWidthVp() },
      color: this.storedDividerColor
    })
    .shadow({
      radius: this.overlayShadowRadius(),
      color: '#24000000',
      offsetX: this.overlayShadowOffsetX(),
      offsetY: 0
    })
    .onHover((hovered: boolean): void => {
      this.noteHover(hovered);
    })
    .onMouse((event: MouseEvent): void => {
      if (event.action === MouseAction.Move) {
        this.notePointerInside();
      }
    })
    .bindContextMenu(
      this.buildBlankContextMenu(),
      ResponseType.RightClick,
      buildBrowserDesktopMenuOptions({ preview: MenuPreviewMode.NONE })
    )
  }

  @Builder
  private buildSidebarHoverShield() {
    Button({ type: ButtonType.Normal }) {
      Row()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .padding(0)
    .borderRadius(0)
    .backgroundColor(this.storedPageBackgroundColor)
    .stateEffect(false)
    .hoverEffect(HoverEffect.None)
    .hitTestBehavior(HitTestMode.Default)
    .onHover((hovered: boolean): void => {
      this.shieldHovered = hovered;
      if (hovered) {
        this.notePointerInside();
      }
    })
    .onMouse((event: MouseEvent): void => {
      if (event.action === MouseAction.Move) {
        this.shieldHovered = true;
        this.notePointerInside();
      }
    })
  }

  @Builder
  private buildHeader() {
    Row() {
      Column() {
        this.buildPinButton()
      }
      .width(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP)
      .height('100%')
      .flexShrink(0)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      Row()
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .height('100%')
        .hitTestBehavior(this.windowMoveEnabled ? HitTestMode.Default : HitTestMode.None)
        .onTouch((event: TouchEvent): void => {
          this.handleWindowMoveTouch(event);
        })
    }
    .width('100%')
    .height(this.resolveHeaderHeightVp())
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildPinButton() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: this.collapsed ? 'browser.tabs.verticalExpanded' : 'browser.tabs.verticalCollapsed',
        iconSize: 18,
        iconColor: this.storedSecondaryTextColor
      })
    }
    .width(HEADER_BUTTON_SIZE_VP)
    .height(HEADER_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(this.collapsed ? '固定垂直标签页' : '收起垂直标签页')
    .onClick((): void => {
      this.togglePinned();
    })
  }

  @Builder
  private buildTabHoverPlate(tab: BrowserLargeScreenTabProjection) {
    Column() {
      this.buildTab(tab)
    }
    .width('100%')
    .padding({ bottom: 2 })
    .backgroundColor(this.storedPageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
    .onHover((hovered: boolean): void => {
      if (hovered) {
        this.noteHover(true);
      }
    })
  }

  @Builder
  private buildNewTabHoverPlate() {
    Column() {
      this.buildNewTabButton()
    }
    .width('100%')
    .padding({ top: 2 })
    .backgroundColor(this.storedPageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
    .onHover((hovered: boolean): void => {
      if (hovered) {
        this.noteHover(true);
      }
    })
  }

  @Builder
  private buildTab(tab: BrowserLargeScreenTabProjection) {
    Stack({ alignContent: Alignment.TopStart }) {
      // Activate on pointer-down. Inside Scroll, a PC mouse click is often claimed
      // by the scroll or context-menu recognizer before mouse-up, so onClick only
      // lands on a perfectly still press.
      this.buildRowActivator(`select_tab:${tab.id}`, `切换到${this.resolveTabTitle(tab)}`, tab.id, 'select_tab')
      this.buildTabHighlight(tab)
      Row() {
        this.buildTabIconSlot(tab)
        Text(this.resolveTabTitle(tab))
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .fontSize(BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP)
          .fontWeight(tab.active ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(tab.active ? this.storedPrimaryTextColor : this.storedSecondaryTextColor)
          .maxLines(1)
          .textAlign(TextAlign.Start)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .ellipsisMode(EllipsisMode.END)
          .wordBreak(WordBreak.BREAK_ALL)
          .opacity(this.detailOpacity())
      }
      .width('100%')
      .height('100%')
      .padding({
        right: this.detailActionsVisible() ? TAB_ROW_INSET_VP + CLOSE_BUTTON_SIZE_VP + 8 : 0
      })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
      if (this.detailActionsVisible()) {
        this.buildTabActions(tab)
      }
    }
    .width('100%')
    .height(TAB_ROW_HEIGHT_VP)
    .backgroundColor(this.storedPageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
    .responseRegion({
      x: 0,
      y: -8,
      width: '100%',
      height: TAB_ROW_HEIGHT_VP + 16
    })
    .onHover((hovered: boolean): void => {
      this.hoveredTabId = hovered ? tab.id : (this.hoveredTabId === tab.id ? '' : this.hoveredTabId);
      if (hovered) {
        this.notePointerInside();
      }
    })
    .onMouse((event: MouseEvent): void => {
      this.activateTabFromPointer(tab.id, 'select_tab', event);
    })
    .onTouch((event: TouchEvent): void => {
      this.activateTabFromTouch(tab.id, 'select_tab', event);
    })
    .bindContextMenu(this.buildTabContextMenu(tab), ResponseType.RightClick, buildBrowserDesktopMenuOptions())
  }

  @Builder
  private buildRowActivator(actionKey: string, accessibilityLabel: string, tabId: string, kind: string) {
    Button({ type: ButtonType.Normal }) {
      Row()
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height(TAB_ROW_HEIGHT_VP)
    .padding(0)
    .borderRadius(0)
    .backgroundColor(Color.Transparent)
    .stateEffect(false)
    .hoverEffect(HoverEffect.None)
    .hitTestBehavior(HitTestMode.Block)
    .accessibilityText(accessibilityLabel)
    .onMouse((event: MouseEvent): void => {
      if (!this.isPrimaryPointerDown(event)) {
        return;
      }
      event.stopPropagation();
      this.dispatchRowAction(actionKey, (): void => {
        this.dispatchRowKind(kind, tabId);
      });
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type !== TouchType.Down) {
        return;
      }
      this.dispatchRowAction(actionKey, (): void => {
        this.dispatchRowKind(kind, tabId);
      });
    })
    .parallelGesture(
      TapGesture({ count: 1 })
        .onAction((): void => {
          this.dispatchRowAction(actionKey, (): void => {
            this.dispatchRowKind(kind, tabId);
          });
        })
    )
    .onClick((): void => {
      this.dispatchRowAction(actionKey, (): void => {
        this.dispatchRowKind(kind, tabId);
      });
    })
  }

  @Builder
  private buildTabHighlight(tab: BrowserLargeScreenTabProjection) {
    if (this.isRailWidth()) {
      Column() {
        Row()
          .width(TAB_ICON_SLOT_SIZE_VP)
          .height(TAB_ICON_SLOT_SIZE_VP)
          .borderRadius(10)
          .backgroundColor(this.resolveTabBackground(tab))
      }
      .width(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP)
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    } else {
      Row() {
        Row()
          .layoutWeight(1)
          .height(TAB_ICON_SLOT_SIZE_VP)
          .borderRadius(10)
          .backgroundColor(this.resolveTabBackground(tab))
      }
      .width('100%')
      .height('100%')
      .padding({ left: TAB_ROW_INSET_VP, right: TAB_ROW_INSET_VP })
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildTabIconSlot(tab: BrowserLargeScreenTabProjection) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        this.buildTabIcon(tab)
      }
      .width(TAB_ICON_SLOT_SIZE_VP)
      .height(TAB_ICON_SLOT_SIZE_VP)
    }
    .width(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP)
    .height('100%')
    .flexShrink(0)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTabActions(tab: BrowserLargeScreenTabProjection) {
    Row({ space: 2 }) {
      Blank()
        .layoutWeight(1)
        .hitTestBehavior(HitTestMode.None)
      if (tab.audible || tab.muted) {
        this.buildAudioButton(tab)
      }
      Button({ type: ButtonType.Circle }) {
        AiraIcon({
          airaIconId: 'browser.tabs.delete',
          iconSize: CLOSE_ICON_SIZE_VP,
          iconColor: this.storedSecondaryTextColor
        })
      }
      .width(CLOSE_BUTTON_SIZE_VP)
      .height(CLOSE_BUTTON_SIZE_VP)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .accessibilityText(`关闭${this.resolveTabTitle(tab)}`)
      .opacity(this.shouldShowClose(tab) ? 1 : 0)
      .hitTestBehavior(this.shouldShowClose(tab) ? HitTestMode.Default : HitTestMode.None)
      .enabled(this.shouldShowClose(tab))
      .onMouse((event: MouseEvent): void => {
        if (!this.isPrimaryPointerDown(event)) {
          return;
        }
        event.stopPropagation();
        this.dispatchRowAction(`close:${tab.id}`, (): void => {
          this.onIntent({ kind: 'close_tab', tabId: tab.id });
        });
      })
      .onTouch((event: TouchEvent): void => {
        if (event.type !== TouchType.Down) {
          return;
        }
        event.stopPropagation();
        this.dispatchRowAction(`close:${tab.id}`, (): void => {
          this.onIntent({ kind: 'close_tab', tabId: tab.id });
        });
      })
      .onClick((): void => {
        this.dispatchRowAction(`close:${tab.id}`, (): void => {
          this.onIntent({ kind: 'close_tab', tabId: tab.id });
        });
      })
    }
    .width('100%')
    .height('100%')
    .padding({ right: TAB_ROW_INSET_VP })
    .alignItems(VerticalAlign.Center)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  private buildNewTabButton() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildRowActivator('new_tab:', '新建标签页', '', 'new_tab')
      Row() {
        Column() {
          Stack({ alignContent: Alignment.Center }) {
            SymbolGlyph($r('sys.symbol.plus'))
              .fontSize(16)
              .fontColor([this.storedSecondaryTextColor])
          }
          .width(TAB_ICON_SLOT_SIZE_VP)
          .height(TAB_ICON_SLOT_SIZE_VP)
        }
        .width(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP)
        .height('100%')
        .flexShrink(0)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        Text('新建标签页')
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .fontSize(BROWSER_LARGE_SCREEN_TAB_TITLE_FONT_SIZE_VP)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .opacity(this.detailOpacity())
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height(TAB_ROW_HEIGHT_VP)
    .backgroundColor(this.storedPageBackgroundColor)
    .hitTestBehavior(HitTestMode.Default)
    .responseRegion({
      x: 0,
      y: -8,
      width: '100%',
      height: TAB_ROW_HEIGHT_VP + 16
    })
    .onHover((hovered: boolean): void => {
      if (hovered) {
        this.notePointerInside();
      }
    })
    .onMouse((event: MouseEvent): void => {
      this.activateTabFromPointer('', 'new_tab', event);
    })
    .onTouch((event: TouchEvent): void => {
      this.activateTabFromTouch('', 'new_tab', event);
    })
  }

  @Builder
  private buildTabIcon(tab: BrowserLargeScreenTabProjection) {
    if (tab.loading && !this.hasResolvedSiteIcon(tab.id)) {
      LoadingProgress()
        .width(TAB_ICON_SIZE_VP)
        .height(TAB_ICON_SIZE_VP)
        .color(this.storedAccentColor)
    } else if (tab.fallbackIconId !== undefined) {
      AiraIcon({
        airaIconId: tab.fallbackIconId,
        iconSize: TAB_ICON_SIZE_VP,
        iconColor: this.storedSecondaryTextColor
      })
    } else {
      SiteIconView({
        iconUri: this.resolveSiteIconState(tab.id)?.path ?? '',
        iconPixelMap: this.resolveSiteIconState(tab.id)?.pixelMap,
        fallbackLabel: resolveSiteIconFallbackLabel(tab.title, tab.url),
        iconSize: TAB_ICON_SIZE_VP,
        cornerRadiusRatio: 0.22,
        frameBorderWidth: 0,
        contentPadding: 0,
        fallbackFontSize: 9,
        fallbackFontWeight: FontWeight.Medium,
        containerBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
        textColor: this.storedSecondaryTextColor,
        fit: ImageFit.Contain,
        preferPixelMap: this.resolveSiteIconState(tab.id)?.pixelMap !== undefined,
        sourceRevision: this.resolveSiteIconState(tab.id)?.sourceRevision ?? 0,
        hitTestMode: HitTestMode.None,
        onIconLoadError: (iconUri: string, sourceRevision: number): void => {
          this.resolveSiteIconPixelMapAfterFailure(tab, iconUri, sourceRevision);
        }
      })
    }
  }

  @Builder
  private buildAudioButton(tab: BrowserLargeScreenTabProjection) {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: tab.muted ? 'videoAssistant.gesture.volumeMuted' : 'videoAssistant.gesture.volumeHigh',
        iconSize: AUDIO_ICON_SIZE_VP,
        iconColor: this.storedSecondaryTextColor
      })
    }
    .width(CLOSE_BUTTON_SIZE_VP)
    .height(CLOSE_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .accessibilityText(tab.muted ? `取消${this.resolveTabTitle(tab)}静音` : `将${this.resolveTabTitle(tab)}静音`)
    .onMouse((event: MouseEvent): void => {
      if (!this.isPrimaryPointerDown(event)) {
        return;
      }
      event.stopPropagation();
      this.dispatchRowAction(`mute:${tab.id}`, (): void => {
        this.onIntent({ kind: 'tab_context_action', tabId: tab.id, actionId: 'toggle_mute' });
      });
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type !== TouchType.Down) {
        return;
      }
      event.stopPropagation();
      this.dispatchRowAction(`mute:${tab.id}`, (): void => {
        this.onIntent({ kind: 'tab_context_action', tabId: tab.id, actionId: 'toggle_mute' });
      });
    })
    .onClick((): void => {
      this.dispatchRowAction(`mute:${tab.id}`, (): void => {
        this.onIntent({ kind: 'tab_context_action', tabId: tab.id, actionId: 'toggle_mute' });
      });
    })
  }

  @Builder
  private buildBlankContextMenu() {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_TAB_STRIP_BLANK_WIDTH_VP }) {
      ForEach(this.buildBlankMenuModel().groups,
        (group: BrowserLargeScreenTabStripBlankMenuItem[]): void => {
          MenuItemGroup() {
            ForEach(group, (item: BrowserLargeScreenTabStripBlankMenuItem): void => {
              this.buildBlankContextMenuItem(item)
            }, (item: BrowserLargeScreenTabStripBlankMenuItem): string => `vertical-blank-${item.id}`)
          }
        }, (group: BrowserLargeScreenTabStripBlankMenuItem[], groupIndex: number): string =>
          `vertical-blank-group-${groupIndex}-${group.length}`)
    }
  }

  @Builder
  private buildBlankContextMenuItem(item: BrowserLargeScreenTabStripBlankMenuItem) {
    BrowserDesktopContextMenuItem({
      menuWidthVp: BROWSER_DESKTOP_MENU_TAB_STRIP_BLANK_WIDTH_VP,
      label: item.label,
      shortcut: item.shortcut,
      itemEnabled: item.enabled,
      checked: item.checked,
      onAction: (): void => {
        this.dispatchBlankMenuItem(item);
      }
    })
  }

  @Builder
  private buildTabContextMenu(tab: BrowserLargeScreenTabProjection) {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP }) {
      MenuItemGroup() {
        this.buildTabContextMenuItem(tab, 'new_tab_to_right', '在右侧新增标签页', '', true)
        this.buildTabContextMenuItem(tab, 'move_to_new_window', '将标签页移至新窗口', '', true)
      }
      MenuItemGroup() {
        this.buildTabContextMenuItem(tab, 'reload', '重新加载', 'Ctrl + R', tab.contextMenu.reloadEnabled)
        this.buildTabContextMenuItem(tab, 'duplicate', '复制', '', tab.contextMenu.duplicateEnabled)
      }
      MenuItemGroup() {
        this.buildTabContextMenuItem(
          tab,
          'toggle_pin',
          tab.pinned ? '取消固定' : '固定',
          '',
          tab.contextMenu.pinEnabled
        )
        this.buildTabContextMenuItem(
          tab,
          'toggle_mute',
          tab.muted ? '取消此网站静音' : '将此网站静音',
          '',
          tab.contextMenu.muteEnabled
        )
      }
      MenuItemGroup() {
        this.buildTabContextMenuItem(tab, 'close', '关闭', 'Ctrl + W', tab.contextMenu.closeEnabled)
        this.buildTabContextMenuItem(tab, 'close_others', '关闭其他标签页', '', tab.contextMenu.closeOthersEnabled)
        this.buildTabContextMenuItem(tab, 'close_to_right', '关闭右侧标签页', '', tab.contextMenu.closeRightEnabled)
      }
    }
  }

  @Builder
  private buildTabContextMenuItem(
    tab: BrowserLargeScreenTabProjection,
    actionId: BrowserLargeScreenTabContextActionId,
    label: string,
    shortcut: string,
    itemEnabled: boolean
  ) {
    BrowserDesktopContextMenuItem({
      menuWidthVp: BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP,
      label: label,
      shortcut: shortcut,
      itemEnabled: itemEnabled,
      onAction: (): void => {
        this.onIntent({ kind: 'tab_context_action', tabId: tab.id, actionId: actionId });
      }
    })
  }

  private isPrimaryPointerDown(event: MouseEvent): boolean {
    return event.button === MouseButton.Left && event.action === MouseAction.Press;
  }

  private activateTabFromPointer(tabId: string, kind: string, event: MouseEvent): void {
    if (!this.isPrimaryPointerDown(event)) {
      return;
    }
    this.dispatchRowAction(`${kind}:${tabId}`, (): void => {
      this.dispatchRowKind(kind, tabId);
    });
  }

  private activateTabFromTouch(tabId: string, kind: string, event: TouchEvent): void {
    if (event.type !== TouchType.Down) {
      return;
    }
    this.dispatchRowAction(`${kind}:${tabId}`, (): void => {
      this.dispatchRowKind(kind, tabId);
    });
  }

  private dispatchRowKind(kind: string, tabId: string): void {
    if (kind === 'select_tab') {
      this.onIntent({ kind: 'select_tab', tabId: tabId });
      return;
    }
    if (kind === 'new_tab') {
      this.onIntent({ kind: 'new_tab', tabId: '' });
    }
  }

  private dispatchRowAction(actionKey: string, action: () => void): void {
    const now = Date.now();
    if (actionKey === this.lastRowActionKey && now - this.lastRowActionAtMs < 120) {
      return;
    }
    this.lastRowActionKey = actionKey;
    this.lastRowActionAtMs = now;
    action();
  }

  private resolveHeaderHeightVp(): number {
    return this.collapsed ? 44 : Math.max(44, this.headerHeightVp);
  }

  private expansionProgress(): number {
    const span = BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP -
      BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP;
    if (span <= 0) {
      return this.collapsed ? 0 : 1;
    }
    const raw = (this.sidebarWidthVp - BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP) / span;
    if (raw <= 0) {
      return 0;
    }
    if (raw >= 1) {
      return 1;
    }
    return raw;
  }

  private detailOpacity(): number {
    const faded = (this.expansionProgress() - 0.08) / 0.42;
    if (faded <= 0) {
      return 0;
    }
    if (faded >= 1) {
      return 1;
    }
    return faded;
  }

  private isRailWidth(): boolean {
    return this.sidebarWidthVp <= BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP + 1;
  }

  private detailActionsVisible(): boolean {
    return this.sidebarWidthVp > BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP + 24;
  }

  private sidebarBorderWidthVp(): number {
    return this.collapsed && this.expansionProgress() > 0.04 ? 0 : 1;
  }

  private overlayShadowRadius(): number {
    if (!this.collapsed) {
      return 0;
    }
    return 18 * this.expansionProgress();
  }

  private overlayShadowOffsetX(): number {
    if (!this.collapsed) {
      return 0;
    }
    return 6 * this.expansionProgress();
  }

  private syncCollapsedPresentation(): void {
    this.clearPeekCollapseTimer();
    if (!this.collapsed) {
      this.snapSidebarWidth(BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP);
      return;
    }
    if (this.hoverInside) {
      this.snapSidebarWidth(BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP);
      return;
    }
    this.snapSidebarWidth(BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP);
  }

  private togglePinned(): void {
    this.onSetCollapsed(!this.collapsed);
  }

  private noteHover(hovered: boolean): void {
    if (hovered) {
      this.notePointerInside();
      return;
    }
    this.notePointerMaybeLeft();
  }

  private notePointerInside(): void {
    this.hoverInside = true;
    this.clearPeekCollapseTimer();
    if (!this.collapsed) {
      return;
    }
    if (this.sidebarWidthVp >= BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP - 1) {
      return;
    }
    this.animateSidebarWidth(
      BROWSER_LARGE_SCREEN_VERTICAL_TABS_EXPANDED_WIDTH_VP,
      PEEK_EXPAND_DURATION_MS,
      Curve.FastOutSlowIn
    );
  }

  private notePointerMaybeLeft(): void {
    if (!this.collapsed || !this.hoverInside) {
      return;
    }
    this.clearPeekCollapseTimer();
    this.peekCollapseTimer = setTimeout((): void => {
      if (this.shieldHovered || !this.collapsed) {
        return;
      }
      this.hoverInside = false;
      this.animateSidebarWidth(
        BROWSER_LARGE_SCREEN_VERTICAL_TABS_RAIL_WIDTH_VP,
        PEEK_COLLAPSE_DURATION_MS,
        Curve.EaseInOut
      );
    }, PEEK_COLLAPSE_DELAY_MS);
  }

  private animateSidebarWidth(targetWidthVp: number, durationMs: number, curve: Curve): void {
    animateTo({
      duration: durationMs,
      curve: curve
    }, (): void => {
      this.sidebarWidthVp = targetWidthVp;
    });
  }

  private snapSidebarWidth(targetWidthVp: number): void {
    animateTo({ duration: 0 }, (): void => {
      this.sidebarWidthVp = targetWidthVp;
    });
  }

  private clearPeekCollapseTimer(): void {
    if (this.peekCollapseTimer >= 0) {
      clearTimeout(this.peekCollapseTimer);
      this.peekCollapseTimer = -1;
    }
  }

  private handleWindowMoveTouch(event: TouchEvent): void {
    if (!this.windowMoveEnabled || event.type !== TouchType.Down) {
      return;
    }
    sharedBrowserLargeScreenWindowChromeService.startMovingLease(this.windowChromeLeaseId);
  }

  private shouldShowClose(tab: BrowserLargeScreenTabProjection): boolean {
    if (!tab.closable) {
      return false;
    }
    return tab.active || this.hoveredTabId === tab.id;
  }

  private resolveTabTitle(tab: BrowserLargeScreenTabProjection): string {
    return resolveBrowserLargeScreenTabDisplayTitle(tab.title);
  }

  private resolveTabBackground(tab: BrowserLargeScreenTabProjection): ResourceColor {
    if (tab.active) {
      return this.storedSurfaceBackgroundColor;
    }
    if (this.hoveredTabId === tab.id) {
      return this.storedControlBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private buildBlankMenuModel(): BrowserLargeScreenTabStripBlankMenuModel {
    return buildBrowserLargeScreenTabStripBlankMenuModel(
      this.recentlyClosed.recordCount,
      this.storedVerticalTabsEnabled
    );
  }

  private dispatchBlankMenuItem(item: BrowserLargeScreenTabStripBlankMenuItem): void {
    if (!item.enabled || item.actionKind === 'none') {
      return;
    }
    if (item.actionKind === 'new_tab') {
      this.onIntent({ kind: 'new_tab', tabId: '' });
      return;
    }
    if (item.actionKind === 'restore_latest_recently_closed') {
      this.onIntent({ kind: 'restore_latest_recently_closed', tabId: '' });
      return;
    }
    if (item.actionKind === 'close_all_tabs') {
      this.onIntent({ kind: 'close_all_tabs', tabId: '' });
      return;
    }
    if (item.actionKind === 'toggle_vertical_tabs') {
      this.onIntent({ kind: 'toggle_vertical_tabs', tabId: '' });
    }
  }

  private syncSiteIcons(): void {
    const targets = this.buildSiteIconTargets();
    this.tabIconStates = this.tabIconStates.filter((state: SiteIconListRenderState): boolean => {
      const target = targets.find((candidate: SiteIconListTarget): boolean => candidate.id === state.id);
      return target !== undefined && this.siteIconListPresenter.hasResolvedIcon([state], target);
    });
    this.siteIconListPresenter.resolveTargets(
      targets,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result),
      {
        shouldSkipTarget: (target: SiteIconListTarget): boolean =>
          this.siteIconListPresenter.hasResolvedIcon(this.tabIconStates, target)
      }
    );
  }

  private buildSiteIconTargets(): SiteIconListTarget[] {
    return this.tabStrip.allTabs
      .filter((tab: BrowserLargeScreenTabProjection): boolean =>
        !tab.privateMode && tab.url.trim().length > 0)
      .map((tab: BrowserLargeScreenTabProjection): SiteIconListTarget => {
        return { id: tab.id, url: tab.url };
      });
  }

  private applyResolvedSiteIcon(result: SiteIconListResolvedIcon): void {
    this.tabIconStates = this.siteIconListPresenter.applyResolvedIcon(this.tabIconStates, result);
  }

  private resolveSiteIconState(tabId: string): SiteIconListRenderState | undefined {
    return this.tabIconStates.find((state: SiteIconListRenderState): boolean => state.id === tabId);
  }

  private hasResolvedSiteIcon(tabId: string): boolean {
    const state = this.resolveSiteIconState(tabId);
    return state !== undefined && (state.path.length > 0 || state.pixelMap !== undefined);
  }

  private resolveSiteIconPixelMapAfterFailure(
    tab: BrowserLargeScreenTabProjection,
    iconUri: string,
    sourceRevision: number
  ): void {
    if (tab.url.trim().length <= 0) {
      return;
    }
    this.siteIconListPresenter.resolvePixelMapAfterUriFailure(
      { id: tab.id, url: tab.url },
      iconUri,
      sourceRevision,
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
  }
}
