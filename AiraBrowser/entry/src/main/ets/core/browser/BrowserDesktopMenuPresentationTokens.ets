/**
 * Shared desktop pointer-menu geometry and typography.
 *
 * Native dropdown menus, tab context menus, and custom Web context menus must
 * consume these values so their container and hover shapes stay identical.
 * Horizontal and vertical insets are equal, and the item radius is the outer
 * radius minus that inset, so a hovered row follows the same arc as the menu
 * instead of being clipped into a different corner.
 */
export const BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP: number = 18;
export const BROWSER_DESKTOP_MENU_COMPACT_WIDTH_VP: number = 188;
export const BROWSER_DESKTOP_MENU_WIDTH_VP: number = 216;
export const BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP: number = 248;
export const BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP: number = 12;
export const BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP: number = 44;
export const BROWSER_DESKTOP_MENU_TEXT_SIZE_FP: number = 14;
export const BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP: number = 20;
export const BROWSER_DESKTOP_MENU_SHORTCUT_TEXT_SIZE_FP: number = 12;
export const BROWSER_DESKTOP_MENU_SHORTCUT_LINE_HEIGHT_VP: number = 18;
export const BROWSER_DESKTOP_MENU_LABEL_SHORTCUT_GAP_VP: number = 12;
export const BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP: number = 6;
export const BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP: number = 6;
export const BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP: number = 10;
/** Reserved gutter for the checked state so labels stay aligned across a check group. */
export const BROWSER_DESKTOP_MENU_CHECKMARK_GUTTER_VP: number = 18;
export const BROWSER_DESKTOP_MENU_CHECKMARK_SIZE_FP: number = 14;
export const BROWSER_DESKTOP_MENU_DISABLED_OPACITY: number = 0.38;
export const BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP: number = 0.5;
export const BROWSER_DESKTOP_MENU_DIVIDER_HORIZONTAL_MARGIN_VP: number = 10;
/** Soft blur for pointer menus. The popup clips anything outside its box, so callers must pad by the bleed. */
export const BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP: number = 32;
export const BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP: number = 6;
export const BROWSER_DESKTOP_MENU_SHADOW_BLEED_VP: number =
  BROWSER_DESKTOP_MENU_SHADOW_RADIUS_VP + BROWSER_DESKTOP_MENU_SHADOW_OFFSET_Y_VP;
/** Vertical space taken by the bookmark flyout divider, including its own margins. */
export const BROWSER_DESKTOP_MENU_DIVIDER_BLOCK_VP: number = 8.5;

/** Top of a row inside a cascade column, relative to the cascade itself. */
export function desktopSubmenuRowTop(
  columnTopVp: number,
  leadingVp: number,
  rowIndex: number,
  scrollOffsetVp: number
): number {
  const top = columnTopVp + leadingVp + rowIndex * BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP - scrollOffsetVp;
  return top > 0 ? top : 0;
}

/**
 * Place a nested menu on the hovered row. Shift it up only when it would extend past the
 * menu's available height, so a short submenu does not jump back to the top.
 */
export function alignDesktopSubmenuTop(
  rowTopVp: number,
  submenuHeightVp: number,
  availableHeightVp: number
): number {
  const aligned = rowTopVp > 0 ? rowTopVp : 0;
  if (submenuHeightVp <= 0 || availableHeightVp <= submenuHeightVp) {
    return aligned;
  }
  const maxTop = availableHeightVp - submenuHeightVp;
  return aligned < maxTop ? aligned : maxTop;
}
