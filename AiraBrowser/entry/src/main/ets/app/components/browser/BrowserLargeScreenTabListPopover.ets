import { KeyCode } from '@kit.InputKit';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserLargeScreenInputProfile,
  BrowserLargeScreenTabStripPresentation
} from '../../../core/browser/BrowserLargeScreenTabStripViewModel';
import { BrowserLargeScreenTabStripIntent } from '../../../core/browser/BrowserLargeScreenShellIntentApplication';
import {
  BrowserRecentlyClosedApplicationSnapshot,
  createBrowserRecentlyClosedApplicationSnapshot
} from '../../../core/browser/BrowserRecentlyClosedApplicationCoordinator';
import { SiteIconListRenderState } from '../../../core/siteicons/SiteIconListPresenter';
import {
  BrowserLargeScreenTabListOpenRowPresentation,
  BrowserLargeScreenTabListPopoverPresentation,
  BrowserLargeScreenTabListPopoverViewModel,
  BrowserLargeScreenTabListRecentRowPresentation,
  BrowserLargeScreenTabListTimeRefreshCoordinator
} from '../../../core/browser/BrowserLargeScreenTabListPopoverViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import { SiteIconView } from '../common/SiteIconView';

const TAB_LIST_TRIGGER_SIZE_VP: number = 32;
const TAB_LIST_TRIGGER_ICON_SIZE_VP: number = 15;
const TAB_LIST_POPUP_RADIUS_VP: number = 8;
const TAB_LIST_POPUP_TARGET_SPACE_VP: number = 4;
const TAB_LIST_SECTION_HEADER_HEIGHT_VP: number = 40;
const TAB_LIST_RECENT_HEADER_HEIGHT_VP: number = 44;
const TAB_LIST_ROW_HEIGHT_VP: number = 52;
const TAB_LIST_ICON_SIZE_VP: number = 20;
const TAB_LIST_CLOSE_BUTTON_SIZE_VP: number = 28;
const TAB_LIST_CLOSE_ICON_SIZE_VP: number = 12;
const TAB_LIST_EMPTY_HEIGHT_VP: number = 64;

const EMPTY_TAB_STRIP_PRESENTATION: BrowserLargeScreenTabStripPresentation = {
  allTabs: [],
  visibleTabs: [],
  hiddenTabIds: [],
  selectedTabId: '',
  overflowVisible: false,
  dragEnabled: false,
  hoverVisible: false,
  newTabVisible: false,
  titleBarHeightVp: 40,
  titleButtonWidthVp: 0,
  windowMoveEnabled: false,
  availableWidthVp: 0,
  consumedWidthVp: 0
};

@Component
export struct BrowserLargeScreenTabListPopover {
  @Prop presentation: BrowserLargeScreenTabStripPresentation = EMPTY_TAB_STRIP_PRESENTATION;
  @Prop recentlyClosed: BrowserRecentlyClosedApplicationSnapshot =
    createBrowserRecentlyClosedApplicationSnapshot();
  @Prop tabIconStates: SiteIconListRenderState[] = [];
  @Prop inputProfile: BrowserLargeScreenInputProfile = 'touch';
  @Prop viewportWidthVp: number = 0;
  @Prop viewportHeightVp: number = 0;
  onIntent: (intent: BrowserLargeScreenTabStripIntent) => void =
    (_intent: BrowserLargeScreenTabStripIntent): void => {};

  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = DEFAULT_THEME_PALETTE.light.floatingSurface;
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY)
  private storedPressedBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY)
  private storedAccentColor: string = DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;

  @State private popupVisible: boolean = false;
  @State private recentlyClosedExpanded: boolean = false;
  @State private hoveredTabId: string = '';
  @State private hoveredRecordId: string = '';
  @State private touchInteractionActive: boolean = false;
  @State private timeRenderTick: number = 0;
  private readonly viewModel: BrowserLargeScreenTabListPopoverViewModel =
    new BrowserLargeScreenTabListPopoverViewModel();
  private readonly timeRefreshCoordinator: BrowserLargeScreenTabListTimeRefreshCoordinator =
    new BrowserLargeScreenTabListTimeRefreshCoordinator((): void => {
      this.timeRenderTick += 1;
    });

  aboutToDisappear(): void {
    this.timeRefreshCoordinator.stop();
  }

  build() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.expandHint',
        iconSize: TAB_LIST_TRIGGER_ICON_SIZE_VP,
        iconColor: this.storedPrimaryTextColor
      })
        .rotate({ angle: this.popupVisible ? 0 : 180 })
        .animation({ duration: 150, curve: Curve.EaseInOut })
    }
    .width(TAB_LIST_TRIGGER_SIZE_VP)
    .height(TAB_LIST_TRIGGER_SIZE_VP)
    .backgroundColor(this.popupVisible
      ? this.storedControlBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText('标签页列表')
    .onTouch((event: TouchEvent): void => {
      this.updateInteractionMode(event);
    })
    .onClick(() => {
      const nextVisible = !this.popupVisible;
      this.popupVisible = nextVisible;
      if (nextVisible) {
        this.timeRefreshCoordinator.start();
      } else {
        this.timeRefreshCoordinator.stop();
      }
    })
    .bindPopup(this.popupVisible, {
      builder: this.buildTabListPopup,
      placement: Placement.BottomLeft,
      popupColor: this.storedFloatingSurfaceColor,
      enableArrow: false,
      autoCancel: true,
      mask: false,
      targetSpace: TAB_LIST_POPUP_TARGET_SPACE_VP,
      width: this.resolvePresentation().popupWidthVp,
      radius: TAB_LIST_POPUP_RADIUS_VP,
      showInSubWindow: false,
      focusable: true,
      shadow: {
        radius: 24,
        color: $r('app.color.elevation_shadow'),
        offsetX: 0,
        offsetY: 8
      },
      onWillDismiss: (action: DismissPopupAction): void => {
        this.closePopup();
        action.dismiss();
      },
      onStateChange: (event: PopupStateChangeParam): void => {
        if (!event.isVisible) {
          this.closePopup();
        }
      }
    })
  }

  @Builder
  private buildTabListPopup() {
    Column({ space: 0 }) {
      this.buildOpenTabsHeader(this.resolvePresentation().openTabs.length)

      Scroll() {
        Column({ space: 2 }) {
          if (this.resolvePresentation().openTabs.length <= 0) {
            this.buildEmptyState('暂无打开的标签页')
          } else {
            ForEach(this.resolvePresentation().openTabs, (tab: BrowserLargeScreenTabListOpenRowPresentation) => {
              this.buildOpenTabRow(tab)
            }, (tab: BrowserLargeScreenTabListOpenRowPresentation): string => tab.key)
          }
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.None)

      Divider()
        .color(this.storedDividerColor)

      this.buildRecentlyClosedHeader(this.resolvePresentation().recentlyClosedTabs.length)

      if (this.recentlyClosedExpanded) {
        Scroll() {
          Column({ space: 2 }) {
            if (this.resolvePresentation().recentlyClosedTabs.length <= 0) {
              this.buildEmptyState('暂无最近关闭的标签页')
            } else {
              ForEach(this.resolvePresentation().recentlyClosedTabs,
                (record: BrowserLargeScreenTabListRecentRowPresentation) => {
                this.buildRecentlyClosedRow(record)
              }, (record: BrowserLargeScreenTabListRecentRowPresentation): string => record.key)
            }
          }
          .width('100%')
          .padding({ left: 8, right: 8, bottom: 8 })
        }
        .width('100%')
        .height(this.resolvePresentation().recentlyClosedListHeightVp)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .width('100%')
    .height(this.resolvePresentation().popupHeightVp)
    .backgroundColor(this.storedFloatingSurfaceColor)
    .border({ width: 1, color: this.storedDividerColor })
    .borderRadius(TAB_LIST_POPUP_RADIUS_VP)
    .clip(true)
    .focusable(true)
    .onKeyEvent((event: KeyEvent): boolean => this.handlePopupKeyEvent(event))
  }

  @Builder
  private buildOpenTabsHeader(openTabCount: number) {
    Row({ space: 8 }) {
      Text('打开的标签页')
        .layoutWeight(1)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)

      Text(`${openTabCount}`)
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
    }
    .width('100%')
    .height(TAB_LIST_SECTION_HEADER_HEIGHT_VP)
    .padding({ left: 16, right: 16 })
  }

  @Builder
  private buildRecentlyClosedHeader(recentlyClosedCount: number) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Text('最近关闭的标签页')
          .layoutWeight(1)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)

        Text(`${recentlyClosedCount}`)
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)

        AiraIcon({
          airaIconId: 'browser.toolbar.expandHint',
          iconSize: 15,
          iconColor: this.storedSecondaryTextColor
        })
          .rotate({ angle: this.recentlyClosedExpanded ? 0 : -90 })
          .animation({ duration: 150, curve: Curve.EaseInOut })
      }
      .width('100%')
    }
    .width('100%')
    .height(TAB_LIST_RECENT_HEADER_HEIGHT_VP)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(true)
    .accessibilityText(this.recentlyClosedExpanded ? '收起最近关闭的标签页' : '展开最近关闭的标签页')
    .onClick(() => {
      this.recentlyClosedExpanded = !this.recentlyClosedExpanded;
    })
  }

  @Builder
  private buildOpenTabRow(tab: BrowserLargeScreenTabListOpenRowPresentation) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          this.buildOpenTabIcon(tab)

          Column({ space: 2 }) {
            Text(tab.title)
              .width('100%')
              .fontSize(13)
              .fontWeight(tab.active ? FontWeight.Medium : FontWeight.Regular)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })

            Text(tab.subtitle)
              .width('100%')
              .fontSize(11)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(TAB_LIST_ROW_HEIGHT_VP)
      .padding({ left: 10, right: 4 })
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .hoverEffect(HoverEffect.None)
      .accessibilityText(`切换到${tab.title}`)
      .onClick(() => {
        this.closePopup();
        this.onIntent({ kind: 'select_tab', tabId: tab.tabId });
      })

      this.buildCloseButton(
        tab.actionVisible,
        `关闭${tab.title}`,
        (): void => {
          this.onIntent({ kind: 'close_tab', tabId: tab.tabId });
        }
      )
    }
    .width('100%')
    .height(TAB_LIST_ROW_HEIGHT_VP)
    .padding({ right: 6 })
    .backgroundColor(this.resolveOpenTabRowBackground(tab))
    .borderRadius(6)
    .onHover((hovered: boolean): void => {
      this.touchInteractionActive = false;
      this.hoveredTabId = hovered
        ? tab.tabId
        : (this.hoveredTabId === tab.tabId ? '' : this.hoveredTabId);
    })
    .onTouch((event: TouchEvent): void => {
      this.updateInteractionMode(event);
    })
  }

  @Builder
  private buildRecentlyClosedRow(record: BrowserLargeScreenTabListRecentRowPresentation) {
    Row({ space: 4 }) {
      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          this.buildRecentlyClosedIcon(record)

          Column({ space: 2 }) {
            Row({ space: 8 }) {
              Text(record.title)
                .layoutWeight(1)
                .fontSize(13)
                .fontColor(this.storedPrimaryTextColor)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })

              Text(record.closedTime)
                .fontSize(10)
                .fontColor(this.storedSecondaryTextColor)
                .maxLines(1)
            }
            .width('100%')

            Text(record.subtitle)
              .width('100%')
              .fontSize(11)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .height(TAB_LIST_ROW_HEIGHT_VP)
      .padding({ left: 10, right: 4 })
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .stateEffect(false)
      .hoverEffect(HoverEffect.None)
      .accessibilityText(`重新打开${record.title}`)
      .onClick(() => {
        this.closePopup();
        this.onIntent({ kind: 'restore_recently_closed', tabId: '', recordId: record.recordId });
      })

      this.buildCloseButton(
        record.actionVisible,
        `删除${record.title}`,
        (): void => {
          this.closePopup();
          this.onIntent({ kind: 'request_delete_recently_closed', tabId: '', recordId: record.recordId });
        }
      )
    }
    .width('100%')
    .height(TAB_LIST_ROW_HEIGHT_VP)
    .padding({ right: 6 })
    .backgroundColor(this.hoveredRecordId === record.recordId
      ? this.storedControlBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(6)
    .onHover((hovered: boolean): void => {
      this.touchInteractionActive = false;
      this.hoveredRecordId = hovered
        ? record.recordId
        : (this.hoveredRecordId === record.recordId ? '' : this.hoveredRecordId);
    })
    .onTouch((event: TouchEvent): void => {
      this.updateInteractionMode(event);
    })
  }

  @Builder
  private buildOpenTabIcon(tab: BrowserLargeScreenTabListOpenRowPresentation) {
    if (tab.loadingWithoutIcon) {
      LoadingProgress()
        .width(TAB_LIST_ICON_SIZE_VP)
        .height(TAB_LIST_ICON_SIZE_VP)
        .color(this.storedAccentColor)
    } else {
      SiteIconView({
        iconUri: tab.iconPath,
        iconPixelMap: tab.iconPixelMap,
        fallbackLabel: tab.fallbackLabel,
        fallbackAiraIconId: tab.fallbackIconId,
        fallbackIconSize: 14,
        iconSize: TAB_LIST_ICON_SIZE_VP,
        cornerRadiusRatio: 0.22,
        frameBorderWidth: 0,
        contentPadding: 0,
        fallbackFontSize: 10,
        fallbackFontWeight: FontWeight.Medium,
        containerBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
        textColor: this.storedSecondaryTextColor,
        fit: ImageFit.Contain,
        preferPixelMap: tab.iconPixelMap !== undefined,
        sourceRevision: tab.iconSourceRevision,
        hitTestMode: HitTestMode.None
      })
    }
  }

  @Builder
  private buildRecentlyClosedIcon(record: BrowserLargeScreenTabListRecentRowPresentation) {
    SiteIconView({
      iconUri: record.iconPath,
      iconPixelMap: record.iconPixelMap,
      fallbackLabel: record.fallbackLabel,
      iconSize: TAB_LIST_ICON_SIZE_VP,
      cornerRadiusRatio: 0.22,
      frameBorderWidth: 0,
      contentPadding: 0,
      fallbackFontSize: 10,
      fallbackFontWeight: FontWeight.Medium,
      containerBackgroundColor: $r('sys.color.ohos_id_color_background_transparent'),
      textColor: this.storedSecondaryTextColor,
      fit: ImageFit.Contain,
      preferPixelMap: record.iconPixelMap !== undefined,
      sourceRevision: 0,
      hitTestMode: HitTestMode.None
    })
  }

  @Builder
  private buildCloseButton(visible: boolean, accessibilityText: string, onClick: () => void) {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.tabs.overviewClose',
        iconSize: TAB_LIST_CLOSE_ICON_SIZE_VP,
        iconColor: this.storedSecondaryTextColor
      })
    }
    .width(TAB_LIST_CLOSE_BUTTON_SIZE_VP)
    .height(TAB_LIST_CLOSE_BUTTON_SIZE_VP)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(visible)
    .visibility(visible ? Visibility.Visible : Visibility.Hidden)
    .accessibilityText(accessibilityText)
    .onClick(() => {
      if (visible) {
        onClick();
      }
    })
  }

  @Builder
  private buildEmptyState(message: string) {
    Row() {
      Text(message)
        .fontSize(12)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
    }
    .width('100%')
    .height(TAB_LIST_EMPTY_HEIGHT_VP)
    .justifyContent(FlexAlign.Center)
  }

  private closePopup(): void {
    this.popupVisible = false;
    this.resetTransientState();
  }

  private resetTransientState(): void {
    this.hoveredTabId = '';
    this.hoveredRecordId = '';
    this.touchInteractionActive = false;
    this.timeRefreshCoordinator.stop();
  }

  private handlePopupKeyEvent(event: KeyEvent): boolean {
    if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE) {
      this.closePopup();
      return true;
    }
    return false;
  }

  private resolveOpenTabRowBackground(tab: BrowserLargeScreenTabListOpenRowPresentation): ResourceColor {
    if (tab.active) {
      return this.storedPressedBackgroundColor;
    }
    if (this.hoveredTabId === tab.tabId) {
      return this.storedControlBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolvePresentation(): BrowserLargeScreenTabListPopoverPresentation {
    this.timeRenderTick;
    return this.viewModel.resolve({
      tabStrip: this.presentation,
      recentlyClosed: this.recentlyClosed,
      tabIconStates: this.tabIconStates,
      inputProfile: this.inputProfile,
      touchInteractionActive: this.touchInteractionActive,
      hoveredTabId: this.hoveredTabId,
      hoveredRecordId: this.hoveredRecordId,
      recentlyClosedExpanded: this.recentlyClosedExpanded,
      viewportWidthVp: this.viewportWidthVp,
      viewportHeightVp: this.viewportHeightVp
    });
  }

  private updateInteractionMode(event: TouchEvent): void {
    if (event.type !== TouchType.Down) {
      return;
    }
    if (event.sourceTool === SourceTool.Finger || event.sourceTool === SourceTool.Pen) {
      this.touchInteractionActive = true;
      this.hoveredTabId = '';
      this.hoveredRecordId = '';
    } else if (event.sourceTool === SourceTool.MOUSE || event.sourceTool === SourceTool.TOUCHPAD) {
      this.touchInteractionActive = false;
    }
  }
}
