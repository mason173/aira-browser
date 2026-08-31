import {
  WebContextMenuOverlayAction,
  WebLinkContextMenuItem,
  WebLinkContextMenuState
} from '../../../core/web/WebLinkContextMenuCoordinator';
import { WebContextMenuOverlayLayout } from '../../../core/web/WebContextMenuOverlayCoordinator';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { uiMaterial } from '@kit.ArkUI';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';

const WEB_CONTEXT_MENU_PHONE_BACKDROP_BLUR_RADIUS: number = 36;
const WEB_CONTEXT_MENU_LIGHT_BACKDROP_COLOR: string = '#26000000';
const WEB_CONTEXT_MENU_DARK_BACKDROP_COLOR: string = '#33000000';
const WEB_CONTEXT_MENU_PHONE_TEXT_SIZE_FP: number = 15;
const WEB_CONTEXT_MENU_PHONE_TEXT_LINE_HEIGHT_VP: number = 22;
const WEB_CONTEXT_MENU_HORIZONTAL_PADDING: number = 14;
const WEB_CONTEXT_MENU_PHONE_RADIUS_VP: number = 18;
const WEB_CONTEXT_MENU_Z_INDEX: number = 94;

const HIDDEN_WEB_CONTEXT_MENU_STATE: WebLinkContextMenuState = {
  visible: false,
  kind: 'link',
  tabId: '',
  url: '',
  title: '',
  x: -1,
  y: -1,
  items: []
};

const HIDDEN_WEB_CONTEXT_MENU_LAYOUT: WebContextMenuOverlayLayout = {
  visible: false,
  pressXVp: 0,
  pressYVp: 0,
  menuLeftVp: 0,
  menuTopVp: 0,
  menuWidthVp: 0,
  menuHeightVp: 0,
  maxHeightVp: 0,
  placement: 'bottom_right',
  presentation: 'touch'
};

@Component
export struct WebContextMenuOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @State private pressedItemKey: string = '';
  @Prop state: WebLinkContextMenuState = HIDDEN_WEB_CONTEXT_MENU_STATE;
  @Prop layout: WebContextMenuOverlayLayout = HIDDEN_WEB_CONTEXT_MENU_LAYOUT;
  onAction: (action: WebContextMenuOverlayAction) => void = (_action: WebContextMenuOverlayAction): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildBackdrop()

      if (this.resolveVisible()) {
        this.buildMenuSurface()
      }
    }
    .width('100%')
    .height('100%')
    .zIndex(WEB_CONTEXT_MENU_Z_INDEX)
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  private buildBackdrop() {
    Stack()
      .width('100%')
      .height('100%')
      .backdropBlur(this.resolveBackdropBlurRadius())
      .backgroundColor(this.resolveBackdropColor())
      .hitTestBehavior(HitTestMode.Block)
      .onTouch((event: TouchEvent): void => {
        event.stopPropagation();
      })
      .onMouse((event: MouseEvent): void => {
        event.stopPropagation();
      })
      .onClick(() => {
        this.onAction({ type: 'dismiss' });
      })
  }

  @Builder
  private buildMenuSurface() {
    Column() {
      Scroll() {
        Column({ space: 0 }) {
          ForEach(this.resolveItems(), (item: WebLinkContextMenuItem, index: number) => {
            this.buildMenuRow(item, index)
          }, (item: WebLinkContextMenuItem) => this.buildMenuItemKey(item))
        }
        .width('100%')
      }
      .width('100%')
      .constraintSize({ maxHeight: this.resolveMaxHeight() })
      .scrollBar(BarState.Auto)
    }
    .width(this.resolveMenuWidth())
    .padding({
      left: this.resolveMenuHorizontalInset(),
      right: this.resolveMenuHorizontalInset(),
      top: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
      bottom: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
    })
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(this.resolveMenuCornerRadius())
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.THIN,
      materialColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      colorInvert: true,
      applyShadow: true,
      interactive: true
    }))
    .clip(true)
    .hitTestBehavior(HitTestMode.Default)
    .onTouch((event: TouchEvent): void => {
      event.stopPropagation();
    })
    .onMouse((event: MouseEvent): void => {
      event.stopPropagation();
    })
    .position({
      x: this.layout.menuLeftVp,
      y: this.layout.menuTopVp
    })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const widthVp = this.parseAreaDimension(newArea.width);
      const heightVp = this.parseAreaDimension(newArea.height);
      if (widthVp > 1 && heightVp > 1) {
        this.onAction({ type: 'measured', widthVp: widthVp, heightVp: heightVp });
      }
    })
  }

  @Builder
  private buildMenuRow(item: WebLinkContextMenuItem, index: number) {
    Column({ space: 0 }) {
      Row() {
        Text(item.label)
          .fontSize(this.resolveMenuTextSize())
          .lineHeight(this.resolveMenuTextLineHeight())
          .letterSpacing(0)
          .fontWeight(this.resolveMenuTextWeight())
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
      .padding({
        left: this.resolveMenuItemHorizontalPadding(),
        right: this.resolveMenuItemHorizontalPadding()
      })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveMenuItemBackground(item))
      .borderRadius(this.resolveMenuItemCornerRadius())
      .clip(true)
      .hoverEffect(this.isLargeScreenMenu() ? HoverEffect.Highlight : HoverEffect.None)
      .onTouch((event: TouchEvent) => {
        event.stopPropagation();
        this.updatePressedMenuItem(item, event.type);
      })
      .onMouse((event: MouseEvent): void => {
        event.stopPropagation();
      })
      .onClick(() => {
        this.pressedItemKey = '';
        this.onAction({ type: 'select', item: item });
      })

      if (this.shouldShowDividerAfter(index)) {
        Divider()
          .height(this.resolveMenuDividerWidth())
          .color(this.storedDividerColor)
          .opacity(this.isLargeScreenMenu() ? 1 : 0.55)
          .margin({
            left: this.resolveMenuDividerHorizontalMargin(),
            right: this.resolveMenuDividerHorizontalMargin()
          })
      }
    }
    .width('100%')
  }

  private resolveVisible(): boolean {
    return this.state.visible && this.layout.visible && this.resolveItems().length > 0;
  }

  private resolveItems(): WebLinkContextMenuItem[] {
    return this.state.items ?? [];
  }

  private resolveMenuWidth(): number {
    return Math.max(1, this.layout.menuWidthVp);
  }

  private resolveMaxHeight(): number {
    return Math.max(1, this.layout.maxHeightVp);
  }

  private resolveBackdropBlurRadius(): number {
    return this.isLargeScreenMenu() ? 0 : WEB_CONTEXT_MENU_PHONE_BACKDROP_BLUR_RADIUS;
  }

  private resolveBackdropColor(): ResourceColor {
    if (this.isLargeScreenMenu()) {
      return $r('sys.color.ohos_id_color_background_transparent');
    }
    return this.storedResolvedThemeMode === 'dark' ?
      WEB_CONTEXT_MENU_DARK_BACKDROP_COLOR :
      WEB_CONTEXT_MENU_LIGHT_BACKDROP_COLOR;
  }

  private isLargeScreenMenu(): boolean {
    return BrowserWindowRuntime.resolveActiveShellPresentationSurface() === 'large_screen';
  }

  private resolveMenuCornerRadius(): number {
    return this.isLargeScreenMenu()
      ? BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP
      : WEB_CONTEXT_MENU_PHONE_RADIUS_VP;
  }

  private resolveMenuItemCornerRadius(): number {
    return this.isLargeScreenMenu() ? BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP : 0;
  }

  private resolveMenuHorizontalInset(): number {
    return this.isLargeScreenMenu() ? BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP : 0;
  }

  private resolveMenuItemHorizontalPadding(): number {
    return this.isLargeScreenMenu()
      ? BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
      : WEB_CONTEXT_MENU_HORIZONTAL_PADDING;
  }

  private resolveMenuTextSize(): number {
    return this.isLargeScreenMenu()
      ? BROWSER_DESKTOP_MENU_TEXT_SIZE_FP
      : WEB_CONTEXT_MENU_PHONE_TEXT_SIZE_FP;
  }

  private resolveMenuTextLineHeight(): number {
    return this.isLargeScreenMenu()
      ? BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP
      : WEB_CONTEXT_MENU_PHONE_TEXT_LINE_HEIGHT_VP;
  }

  private resolveMenuTextWeight(): FontWeight {
    return this.isLargeScreenMenu() ? FontWeight.Normal : FontWeight.Medium;
  }

  private buildMenuItemKey(item: WebLinkContextMenuItem): string {
    return `${item.action}:${item.scriptId ?? ''}:${item.commandId ?? ''}`;
  }

  private resolveMenuItemBackground(item: WebLinkContextMenuItem): ResourceColor {
    const itemKey = this.buildMenuItemKey(item);
    if (this.pressedItemKey === itemKey) {
      return this.storedPressedBackgroundColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private shouldShowDividerAfter(index: number): boolean {
    const items = this.resolveItems();
    if (index < 0 || index >= items.length - 1) {
      return false;
    }
    if (!this.isLargeScreenMenu()) {
      return true;
    }
    return items[index].group !== items[index + 1].group;
  }

  private resolveMenuDividerWidth(): number {
    return this.isLargeScreenMenu() ? BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP : 1;
  }

  private resolveMenuDividerHorizontalMargin(): number {
    return this.isLargeScreenMenu()
      ? BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP
      : WEB_CONTEXT_MENU_HORIZONTAL_PADDING;
  }

  private updatePressedMenuItem(item: WebLinkContextMenuItem, type: TouchType): void {
    if (type === TouchType.Down) {
      this.pressedItemKey = this.buildMenuItemKey(item);
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedItemKey = '';
    }
  }

  private parseAreaDimension(value: Length): number {
    const rawValue = `${value}`.replace('vp', '').replace('px', '');
    const parsedValue = Number(rawValue);
    return Number.isFinite(parsedValue) ? parsedValue : 0;
  }
}
