import {
  ELEMENT_INSPECTION_OUTLINE_MENU_DIVIDER_SLOT_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_EDGE_INSET_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_BLEED_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_OFFSET_Y_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_RADIUS_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_VERTICAL_INSET_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_WIDTH_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_ROW_HEIGHT_VP,
  ElementInspectionOutlineMenuLayout,
  ElementInspectionOutlineMenuLayoutViewModel
} from '../../../core/browser/ElementInspectionOutlineMenuLayout';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_DISABLED_OPACITY,
  BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { resolveCenteredDialogSurfaceColor } from '../common/CenteredDialogSurface';

export interface ElementInspectionOutlineMenuEntry {
  key: string;
  label: string;
  enabled: boolean;
  group: number;
}

@Component
export struct ElementInspectionOutlineContextMenu {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @Prop entries: ElementInspectionOutlineMenuEntry[] = [];
  @Prop anchorXVp: number = 0;
  @Prop anchorYVp: number = 0;
  @Prop hostWidthVp: number = 1;
  @Prop hostHeightVp: number = 1;
  @State private hoveredKey: string = '';
  onSelect: (key: string) => void = (_key: string): void => {};
  private readonly layoutViewModel: ElementInspectionOutlineMenuLayoutViewModel =
    new ElementInspectionOutlineMenuLayoutViewModel();

  build() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.entries, (entry: ElementInspectionOutlineMenuEntry, index: number) => {
            this.buildEntry(entry, index)
          }, (entry: ElementInspectionOutlineMenuEntry) => entry.key)
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .scrollable(ScrollDirection.Vertical)
      .edgeEffect(EdgeEffect.None)
      .align(Alignment.Top)
      .clip(true)
    }
    .width(this.resolveLayout().widthVp)
    .height(this.resolveLayout().heightVp)
    .padding({
      left: 4,
      right: 4,
      top: ELEMENT_INSPECTION_OUTLINE_MENU_VERTICAL_INSET_VP,
      bottom: ELEMENT_INSPECTION_OUTLINE_MENU_VERTICAL_INSET_VP
    })
    .backgroundColor(resolveCenteredDialogSurfaceColor())
    .backgroundBlurStyle(BlurStyle.NONE)
    .backdropBlur(0)
    .borderRadius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
    .border({ width: 1, color: this.storedDividerColor })
    .shadow({
      radius: ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_RADIUS_VP,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_OFFSET_Y_VP
    })
    .clip(false)
    .hitTestBehavior(HitTestMode.Default)
    .position({
      x: this.resolveLayout().leftVp,
      y: this.resolveLayout().topVp
    })
    .onClick(() => {
    })
    .onMouse((event: MouseEvent) => {
      event.stopPropagation();
    })
  }

  @Builder
  private buildEntry(entry: ElementInspectionOutlineMenuEntry, index: number) {
    Column() {
      if (this.shouldShowDividerBefore(index)) {
        Column() {
          Divider()
            .width('100%')
            .height(BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP)
            .color(this.storedDividerColor)
            .margin({
              left: BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
              right: BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP
            })
        }
        .width('100%')
        .height(ELEMENT_INSPECTION_OUTLINE_MENU_DIVIDER_SLOT_VP)
        .justifyContent(FlexAlign.Center)
      }

      Row() {
        Text(entry.label)
          .layoutWeight(1)
          .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .opacity(entry.enabled ? 1 : BROWSER_DESKTOP_MENU_DISABLED_OPACITY)
      }
      .width('100%')
      .height(ELEMENT_INSPECTION_OUTLINE_MENU_ROW_HEIGHT_VP)
      .padding({
        left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
        right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
      })
      .alignItems(VerticalAlign.Center)
      .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
      .backgroundColor(this.hoveredKey === entry.key && entry.enabled ? '#14000000' : Color.Transparent)
      .hoverEffect(entry.enabled ? HoverEffect.Highlight : HoverEffect.None)
      .onHover((isHover: boolean) => {
        this.hoveredKey = isHover && entry.enabled ? entry.key : '';
      })
      .onClick(() => {
        if (!entry.enabled) {
          return;
        }
        this.onSelect(entry.key);
      })
    }
    .width('100%')
  }

  private shouldShowDividerBefore(index: number): boolean {
    if (index <= 0 || index >= this.entries.length) {
      return false;
    }
    return this.entries[index].group !== this.entries[index - 1].group;
  }

  private resolveLayout(): ElementInspectionOutlineMenuLayout {
    return this.layoutViewModel.resolve({
      anchorXVp: this.anchorXVp,
      anchorYVp: this.anchorYVp,
      hostWidthVp: this.hostWidthVp,
      hostHeightVp: this.hostHeightVp,
      preferredWidthVp: ELEMENT_INSPECTION_OUTLINE_MENU_WIDTH_VP,
      contentHeightVp: this.layoutViewModel.resolveContentHeight(this.entries.length, this.resolveDividerCount()),
      edgeInsetVp: ELEMENT_INSPECTION_OUTLINE_MENU_EDGE_INSET_VP,
      shadowBleedVp: ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_BLEED_VP
    });
  }

  private resolveDividerCount(): number {
    let count = 0;
    for (let index = 1; index < this.entries.length; index += 1) {
      if (this.entries[index].group !== this.entries[index - 1].group) {
        count += 1;
      }
    }
    return count;
  }
}
