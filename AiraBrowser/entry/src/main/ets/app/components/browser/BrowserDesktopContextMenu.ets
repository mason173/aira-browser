import { LengthMetrics } from '@kit.ArkUI';
import {
  BROWSER_DESKTOP_MENU_CHECKMARK_GUTTER_VP,
  BROWSER_DESKTOP_MENU_CHECKMARK_SIZE_FP,
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_DISABLED_OPACITY,
  BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP,
  BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_LABEL_SHORTCUT_GAP_VP,
  BROWSER_DESKTOP_MENU_SHORTCUT_LINE_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_SHORTCUT_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
  BROWSER_DESKTOP_MENU_WIDTH_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { resolveCenteredDialogSurfaceColor } from '../common/CenteredDialogSurface';

/**
 * Pointer-menu popup surface. The platform default for a context menu is a transparent background
 * combined with a `COMPONENT_ULTRA_THICK` backdrop blur, which washes the labels out over page
 * content. Desktop menus use the same opaque floating surface as centered dialogs instead.
 */
export function resolveBrowserDesktopMenuSurfaceColor(): ResourceColor {
  return resolveCenteredDialogSurfaceColor();
}

/** Options every desktop pointer menu accepts on top of the shared surface. */
export interface BrowserDesktopMenuOptionsInput {
  onAppear?: () => void;
  onDisappear?: () => void;
  preview?: MenuPreviewMode | CustomBuilder;
  previewBorderRadius?: Length | BorderRadiuses | LocalizedBorderRadiuses;
  placement?: Placement;
  enableArrow?: boolean;
  showInSubWindow?: boolean;
}

/**
 * Builds the options for every bindContextMenu/bindMenu that renders
 * {@link BrowserDesktopContextMenu}, so the menu surface and its popup material stay one policy.
 */
export function buildBrowserDesktopMenuOptions(input?: BrowserDesktopMenuOptionsInput): MenuOptions {
  const options: MenuOptions = {
    backgroundColor: resolveBrowserDesktopMenuSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    borderRadius: BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
    placement: input?.placement,
    enableArrow: input?.enableArrow,
    showInSubWindow: input?.showInSubWindow,
    onAppear: input?.onAppear,
    onDisappear: input?.onDisappear,
    preview: input?.preview,
    previewBorderRadius: input?.previewBorderRadius
  };
  return options;
}

@Component
export struct BrowserDesktopContextMenu {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @Prop menuWidthVp: number = BROWSER_DESKTOP_MENU_WIDTH_VP;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Menu() {
      this.content()
    }
    .width(this.menuWidthVp)
    .padding({
      left: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
      right: BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
      top: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
      bottom: BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP
    })
    .radius(BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP)
    .menuItemGroupDivider({
      strokeWidth: LengthMetrics.vp(BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP),
      color: this.storedDividerColor,
      startMargin: LengthMetrics.vp(BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP),
      endMargin: LengthMetrics.vp(BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP)
    })
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct BrowserDesktopContextMenuItem {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop menuWidthVp: number = BROWSER_DESKTOP_MENU_WIDTH_VP;
  @Prop label: string = '';
  @Prop shortcut: string = '';
  @Prop itemEnabled: boolean = true;
  @Prop checked: boolean = false;
  onAction: () => void = () => {};

  build() {
    MenuItem(() => {
      this.buildContent()
    })
    .enabled(this.itemEnabled)
    .padding(0)
    .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
    .clip(true)
    .hoverEffect(this.itemEnabled ? HoverEffect.Highlight : HoverEffect.None)
    .onClick((): void => {
      if (this.itemEnabled) {
        this.onAction();
      }
    })
  }

  @Builder
  private buildContent() {
    Row({ space: BROWSER_DESKTOP_MENU_LABEL_SHORTCUT_GAP_VP }) {
      Row() {
        if (this.checked) {
          SymbolGlyph($r('sys.symbol.checkmark'))
            .fontSize(BROWSER_DESKTOP_MENU_CHECKMARK_SIZE_FP)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.storedPrimaryTextColor])
        }
      }
      .width(BROWSER_DESKTOP_MENU_CHECKMARK_GUTTER_VP)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)

      Text(this.label)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .lineHeight(BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP)
        .letterSpacing(0)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      if (this.shortcut.length > 0) {
        Text(this.shortcut)
          .fontSize(BROWSER_DESKTOP_MENU_SHORTCUT_TEXT_SIZE_FP)
          .lineHeight(BROWSER_DESKTOP_MENU_SHORTCUT_LINE_HEIGHT_VP)
          .letterSpacing(0)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.End)
          .maxLines(1)
      }
    }
    .width(Math.max(1, this.menuWidthVp - BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP * 2))
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
      right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
    })
    .opacity(this.itemEnabled ? 1 : BROWSER_DESKTOP_MENU_DISABLED_OPACITY)
  }
}
