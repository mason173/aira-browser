import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserLargeScreenInputProfile,
  BrowserLargeScreenTabProjection,
  BrowserLargeScreenTabStripPresentation
} from '../../../core/browser/BrowserLargeScreenTabStripViewModel';
import {
  BrowserLargeScreenTabContextActionId,
  BrowserLargeScreenTabStripIntent
} from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
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
import { BrowserDesktopContextMenu, BrowserDesktopContextMenuItem } from './BrowserDesktopContextMenu';
import { BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP } from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BROWSER_LARGE_SCREEN_TITLE_BAR_ACTION_GAP_VP,
  BROWSER_LARGE_SCREEN_TITLE_BAR_ACTION_SIZE_VP,
  BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP,
  BROWSER_LARGE_SCREEN_TITLE_BAR_TAB_LIST_WIDTH_VP,
  BROWSER_LARGE_SCREEN_TITLE_BAR_LEADING_PADDING_VP,
  BROWSER_LARGE_SCREEN_TITLE_BAR_MIN_DRAG_WIDTH_VP,
  BROWSER_LARGE_SCREEN_TITLE_BAR_TRAILING_PADDING_VP
} from '../../../core/browser/BrowserLargeScreenTitleBarTokens';
import {
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { BrowserLargeScreenTabListPopover } from './BrowserLargeScreenTabListPopover';
import {
  sharedBrowserLargeScreenWindowChromeService
} from '../../../services/browser/BrowserLargeScreenWindowChromeService';

const TAB_HEIGHT_VP: number = 32;
const TAB_CONTENT_EDGE_PADDING_VP: number = 16;
const TAB_ICON_SIZE_VP: number = 14;
const TAB_CLOSE_ICON_SIZE_VP: number = 12;
const TAB_CLOSE_BUTTON_SIZE_VP: number = 24;
const TAB_AUDIO_ICON_SIZE_VP: number = 14;
const TAB_CLOSE_BUTTON_EDGE_PADDING_VP: number =
  TAB_CONTENT_EDGE_PADDING_VP - (TAB_CLOSE_BUTTON_SIZE_VP - TAB_CLOSE_ICON_SIZE_VP) / 2;
const TAB_SEPARATOR_HEIGHT_VP: number = 18;
const TAB_ACTIVE_SHAPE_RADIUS_VP: number = 10;
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

@Component
export struct BrowserLargeScreenTabStripSurface {
  @Prop windowChromeLeaseId: string = '';
  @Watch('syncSiteIcons')
  @Prop presentation: BrowserLargeScreenTabStripPresentation = DEFAULT_TAB_STRIP_PRESENTATION;
  @Prop recentlyClosed: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  @Prop inputProfile: BrowserLargeScreenInputProfile = 'touch';
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  onIntent: (intent: BrowserLargeScreenTabStripIntent) => void =
    (_intent: BrowserLargeScreenTabStripIntent): void => {};

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

  @State private hoveredTabId: string = '';
  @State private tabIconStates: SiteIconListRenderState[] = [];
  private siteIconListPresenter: SiteIconListPresenter = new SiteIconListPresenter();

  aboutToAppear(): void {
    this.siteIconListPresenter.bindDomainUpdates(
      (): SiteIconListTarget[] => this.buildSiteIconTargets(),
      (result: SiteIconListResolvedIcon): void => this.applyResolvedSiteIcon(result)
    );
    this.syncSiteIcons();
  }

  aboutToDisappear(): void {
    this.siteIconListPresenter.dispose();
  }

  build() {
    Row({ space: 0 }) {
      this.buildTabListEntry()

      Row({ space: 0 }) {
        ForEach(this.presentation.visibleTabs, (tab: BrowserLargeScreenTabProjection, index: number) => {
          this.buildTab(tab, index)
        }, (tab: BrowserLargeScreenTabProjection): string =>
          `${tab.id}:${tab.active ? 'active' : 'inactive'}:${tab.widthVp}` +
          `:${tab.pinned ? 'p' : ''}${tab.muted ? 'm' : ''}${tab.audible ? 'a' : ''}:${tab.title}`)
      }
      .width(this.presentation.consumedWidthVp)
      .height(this.resolveTitleBarHeightVp())
      .alignItems(VerticalAlign.Bottom)
      .clip(true)

      if (this.presentation.newTabVisible) {
        Row()
          .width(BROWSER_LARGE_SCREEN_TITLE_BAR_ACTION_GAP_VP)
          .height(this.resolveTitleBarHeightVp())
          .hitTestBehavior(HitTestMode.None)

        this.buildFixedAction('browser.tabs.add', '新建标签页', {
          kind: 'new_tab',
          tabId: ''
        })
      }

      this.buildWindowMoveRegion()

    }
    .width('100%')
    .height(this.resolveTitleBarHeightVp())
    .padding({
      left: BROWSER_LARGE_SCREEN_TITLE_BAR_LEADING_PADDING_VP,
      right: BROWSER_LARGE_SCREEN_TITLE_BAR_TRAILING_PADDING_VP + this.presentation.titleButtonWidthVp
    })
    .alignItems(VerticalAlign.Bottom)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildTabListEntry() {
    Row() {
      BrowserLargeScreenTabListPopover({
        presentation: this.presentation,
        recentlyClosed: this.recentlyClosed,
        tabIconStates: this.tabIconStates,
        inputProfile: this.inputProfile,
        viewportWidthVp: this.viewportWidthVp,
        viewportHeightVp: this.viewportHeightVp,
        onIntent: (intent: BrowserLargeScreenTabStripIntent): void => {
          this.onIntent(intent);
        }
      })
    }
    .width(BROWSER_LARGE_SCREEN_TITLE_BAR_TAB_LIST_WIDTH_VP)
    .height(this.resolveTitleBarHeightVp())
    .padding({ right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildWindowMoveRegion() {
    Row()
      .layoutWeight(1)
      .height(this.resolveTitleBarHeightVp())
      .constraintSize({ minWidth: BROWSER_LARGE_SCREEN_TITLE_BAR_MIN_DRAG_WIDTH_VP })
      .onTouch((event: TouchEvent): void => {
        this.handleWindowMoveTouch(event);
      })
      .accessibilityText('拖动窗口')
  }

  @Builder
  private buildTab(tab: BrowserLargeScreenTabProjection, index: number) {
    Stack({ alignContent: Alignment.End }) {
      if (tab.active) {
        this.buildActiveTabBackground(tab.widthVp)
      }

      if (tab.pinned) {
        this.buildPinnedTabBody(tab)
      } else {
        this.buildRegularTabBody(tab)
      }

      if (this.shouldShowTabSeparator(index)) {
        Divider()
          .vertical(true)
          .height(TAB_SEPARATOR_HEIGHT_VP)
          .strokeWidth(1)
          .color(this.storedDividerColor)
      }
    }
    .width(tab.widthVp)
    .height(TAB_HEIGHT_VP)
    .onHover((hovered: boolean) => {
      this.hoveredTabId = hovered ? tab.id : (this.hoveredTabId === tab.id ? '' : this.hoveredTabId);
    })
    .bindContextMenu(this.buildTabContextMenu(tab), ResponseType.RightClick)
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
  private buildRegularTabBody(tab: BrowserLargeScreenTabProjection) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 6 }) {
          this.buildTabIcon(tab)

          Text(this.resolveTabTitle(tab))
            .layoutWeight(1)
            .fontSize(13)
            .fontWeight(tab.active ? FontWeight.Medium : FontWeight.Regular)
            .fontColor(tab.active ? this.storedPrimaryTextColor : this.storedSecondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(TAB_HEIGHT_VP)
      .padding({ left: TAB_CONTENT_EDGE_PADDING_VP, right: 4 })
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .hoverEffect(HoverEffect.None)
      .accessibilityText(`切换到${this.resolveTabTitle(tab)}`)
      .onClick(() => {
        this.onIntent({ kind: 'select_tab', tabId: tab.id });
      })

      if (tab.audible || tab.muted) {
        this.buildAudioIndicator(tab)
      }

      if (tab.closable && (tab.active || this.hoveredTabId === tab.id || !this.presentation.hoverVisible)) {
        Button({ type: ButtonType.Circle }) {
          AiraIcon({
            airaIconId: 'browser.tabs.overviewClose',
            iconSize: TAB_CLOSE_ICON_SIZE_VP,
            iconColor: this.storedSecondaryTextColor
          })
        }
        .width(TAB_CLOSE_BUTTON_SIZE_VP)
        .height(TAB_CLOSE_BUTTON_SIZE_VP)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(true)
        .accessibilityText(`关闭${this.resolveTabTitle(tab)}`)
        .onClick(() => {
          this.onIntent({ kind: 'close_tab', tabId: tab.id });
        })
      }
    }
    .width(tab.widthVp)
    .height(TAB_HEIGHT_VP)
    .padding({ right: TAB_CLOSE_BUTTON_EDGE_PADDING_VP })
    .borderRadius({ topLeft: 8, topRight: 8 })
    .backgroundColor(this.resolveTabBackground(tab))
  }

  @Builder
  private buildPinnedTabBody(tab: BrowserLargeScreenTabProjection) {
    Button({ type: ButtonType.Normal }) {
      this.buildTabIcon(tab)
    }
    .width(tab.widthVp)
    .height(TAB_HEIGHT_VP)
    .padding(0)
    .borderRadius({ topLeft: 8, topRight: 8 })
    .backgroundColor(this.resolveTabBackground(tab))
    .stateEffect(false)
    .hoverEffect(HoverEffect.None)
    .accessibilityText(`切换到${this.resolveTabTitle(tab)}`)
    .onClick(() => {
      this.onIntent({ kind: 'select_tab', tabId: tab.id });
    })
  }

  @Builder
  private buildAudioIndicator(tab: BrowserLargeScreenTabProjection) {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: tab.muted ? 'videoAssistant.gesture.volumeMuted' : 'videoAssistant.gesture.volumeHigh',
        iconSize: TAB_AUDIO_ICON_SIZE_VP,
        iconColor: this.storedSecondaryTextColor
      })
    }
    .width(TAB_CLOSE_BUTTON_SIZE_VP)
    .height(TAB_CLOSE_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(tab.muted ? `取消${this.resolveTabTitle(tab)}静音` : `将${this.resolveTabTitle(tab)}静音`)
    .onClick(() => {
      this.onIntent({ kind: 'tab_context_action', tabId: tab.id, actionId: 'toggle_mute' });
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
        this.onIntent({
          kind: 'tab_context_action',
          tabId: tab.id,
          actionId: actionId
        });
      }
    })
  }

  @Builder
  private buildActiveTabBackground(widthVp: number) {
    Stack() {
      Row()
        .width(widthVp - TAB_ACTIVE_SHAPE_RADIUS_VP * 2)
        .height(TAB_HEIGHT_VP)
        .borderRadius({
          topLeft: TAB_ACTIVE_SHAPE_RADIUS_VP,
          topRight: TAB_ACTIVE_SHAPE_RADIUS_VP
        })
        .backgroundColor(this.storedSurfaceBackgroundColor)
        .position({ x: TAB_ACTIVE_SHAPE_RADIUS_VP, y: 0 })

      Row()
        .width(widthVp)
        .height(TAB_ACTIVE_SHAPE_RADIUS_VP)
        .backgroundColor(this.storedSurfaceBackgroundColor)
        .position({ x: 0, y: TAB_HEIGHT_VP - TAB_ACTIVE_SHAPE_RADIUS_VP })

      Row()
        .width(TAB_ACTIVE_SHAPE_RADIUS_VP * 2)
        .height(TAB_ACTIVE_SHAPE_RADIUS_VP * 2)
        .borderRadius(TAB_ACTIVE_SHAPE_RADIUS_VP)
        .backgroundColor(this.storedPageBackgroundColor)
        .position({
          x: -TAB_ACTIVE_SHAPE_RADIUS_VP,
          y: TAB_HEIGHT_VP - TAB_ACTIVE_SHAPE_RADIUS_VP * 2
        })

      Row()
        .width(TAB_ACTIVE_SHAPE_RADIUS_VP * 2)
        .height(TAB_ACTIVE_SHAPE_RADIUS_VP * 2)
        .borderRadius(TAB_ACTIVE_SHAPE_RADIUS_VP)
        .backgroundColor(this.storedPageBackgroundColor)
        .position({
          x: widthVp - TAB_ACTIVE_SHAPE_RADIUS_VP,
          y: TAB_HEIGHT_VP - TAB_ACTIVE_SHAPE_RADIUS_VP * 2
        })
    }
    .width(widthVp)
    .height(TAB_HEIGHT_VP)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildFixedAction(
    iconId: 'browser.toolbar.tabs' | 'browser.tabs.add',
    accessibilityText: string,
    intent: BrowserLargeScreenTabStripIntent
  ) {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: 16,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(BROWSER_LARGE_SCREEN_TITLE_BAR_ACTION_SIZE_VP)
    .height(BROWSER_LARGE_SCREEN_TITLE_BAR_ACTION_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(accessibilityText)
    .onClick(() => {
      this.onIntent(intent);
    })
  }

  private resolveTabTitle(tab: BrowserLargeScreenTabProjection): string {
    const title = tab.title.trim();
    return title.length > 0 ? title : '新标签页';
  }

  private resolveTitleBarHeightVp(): number {
    return Math.max(BROWSER_LARGE_SCREEN_TITLE_BAR_BASE_HEIGHT_VP, this.presentation.titleBarHeightVp);
  }

  private handleWindowMoveTouch(event: TouchEvent): void {
    if (!this.presentation.windowMoveEnabled || event.type !== TouchType.Down) {
      return;
    }
    sharedBrowserLargeScreenWindowChromeService.startMovingLease(this.windowChromeLeaseId);
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
    return this.presentation.allTabs
      .filter((tab: BrowserLargeScreenTabProjection): boolean =>
        !tab.privateMode && tab.url.trim().length > 0)
      .map((tab: BrowserLargeScreenTabProjection): SiteIconListTarget => {
        return {
          id: tab.id,
          url: tab.url
        };
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

  private shouldShowTabSeparator(index: number): boolean {
    const currentTab = this.presentation.visibleTabs[index];
    const nextTab = this.presentation.visibleTabs[index + 1];
    if (currentTab === undefined || nextTab === undefined || currentTab.active || nextTab.active) {
      return false;
    }
    return this.hoveredTabId !== currentTab.id && this.hoveredTabId !== nextTab.id;
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

  private resolveTabBackground(tab: BrowserLargeScreenTabProjection): ResourceColor {
    if (tab.active) {
      return $r('sys.color.ohos_id_color_background_transparent');
    }
    if (this.hoveredTabId === tab.id) {
      return this.storedControlBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }
}
