import { WebContextMenuOverlayAction } from '../../../core/web/WebLinkContextMenuCoordinator';
import {
  WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP,
  WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP,
  WebLinkTextSelectionPresentation
} from '../../../core/web/WebLinkTextSelectionCoordinator';
import { BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY } from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct WebLinkTextSelectionOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private textColor: string = '#111318';
  @Prop selection: WebLinkTextSelectionPresentation;
  onAction: (action: WebContextMenuOverlayAction) => void = (_action: WebContextMenuOverlayAction): void => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.selection.toolbarVisible) {
        Row() {
          Button($r('app.string.ui_copy'))
            .layoutWeight(1)
            .height(WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP)
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(this.textColor)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 4, right: 4 })
            .onClick(() => this.onAction({ type: 'copy_selection' }))
          Button($r('app.string.ui_select_all'))
            .layoutWeight(1)
            .height(WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP)
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(this.textColor)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 4, right: 4 })
            .onClick(() => this.onAction({ type: 'select_all_text' }))
          Button($r('app.string.ui_share'))
            .layoutWeight(1)
            .height(WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP)
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(this.textColor)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 4, right: 4 })
            .onClick(() => this.onAction({ type: 'share_selection' }))
          Button($r('app.string.app_shortcut_search'))
            .layoutWeight(1)
            .height(WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP)
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(this.textColor)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .padding({ left: 4, right: 4 })
            .onClick(() => this.onAction({ type: 'search_selection' }))
        }
        .width(this.selection.toolbarWidthVp)
        .height(WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP)
        .padding({ left: 6, right: 6 })
        .backgroundColor($r('app.color.surface_floating_background'))
        .borderRadius(WEB_LINK_TEXT_SELECTION_TOOLBAR_HEIGHT_VP / 2)
        .shadow({ radius: 18, color: '#1A000000', offsetY: 4 })
        .clip(true)
        .position({ x: this.selection.toolbarLeftVp, y: this.selection.toolbarTopVp })
        .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
      }
      if (this.selection.start.visible) {
        WebLinkTextSelectionHandleView({
          xVp: this.selection.start.xVp, yVp: this.selection.start.yVp,
          heightVp: this.selection.start.heightVp, handle: 'start', onAction: this.onAction
        })
      }
      if (this.selection.end.visible) {
        WebLinkTextSelectionHandleView({
          xVp: this.selection.end.xVp, yVp: this.selection.end.yVp,
          heightVp: this.selection.end.heightVp, handle: 'end', onAction: this.onAction
        })
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

}

// Dynamic coordinates are primitive @Prop values. Multi-argument Builder parameters freeze their UI.
@Component
struct WebLinkTextSelectionHandleView {
  @Prop xVp: number = 0;
  @Prop yVp: number = 0;
  @Prop heightVp: number = 20;
  @Prop handle: 'start' | 'end' = 'start';
  onAction: (action: WebContextMenuOverlayAction) => void = (_action: WebContextMenuOverlayAction): void => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Column({ space: 0 }) {
        if (this.handle === 'start') {
          Circle()
            .width(WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP)
            .height(WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP)
            .fill(Color.White)
            .stroke($r('sys.color.ohos_id_color_text_primary_activated'))
            .strokeWidth(1.5)
        }
        Rect()
          .width(2)
          .height(this.heightVp)
          .fill($r('sys.color.ohos_id_color_text_primary_activated'))
        if (this.handle === 'end') {
          Circle()
            .width(WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP)
            .height(WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP)
            .fill(Color.White)
            .stroke($r('sys.color.ohos_id_color_text_primary_activated'))
            .strokeWidth(1.5)
        }
      }
    }
    .width(44)
    .height(Math.max(44, this.heightVp + WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP + 4))
    .position({ x: this.xVp - 22,
      y: this.yVp - (this.handle === 'start' ? WEB_LINK_TEXT_SELECTION_HANDLE_DIAMETER_VP : 0) })
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .gesture(PanGesture({ distance: 1 })
      .onActionStart((event: GestureEvent): void => {
        this.onAction({ type: 'selection_drag_start', handle: this.handle,
          offsetXVp: event.offsetX, offsetYVp: event.offsetY });
      })
      .onActionUpdate((event: GestureEvent): void => {
        this.onAction({ type: 'selection_drag_update', handle: this.handle,
          offsetXVp: event.offsetX, offsetYVp: event.offsetY });
      })
      .onActionEnd((event: GestureEvent): void => {
        this.onAction({ type: 'selection_drag_end', handle: this.handle,
          offsetXVp: event.offsetX, offsetYVp: event.offsetY });
      })
      .onActionCancel((): void => {
        this.onAction({ type: 'selection_drag_end', handle: this.handle });
      }))
  }
}
