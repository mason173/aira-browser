export const ELEMENT_INSPECTION_OUTLINE_MENU_WIDTH_VP: number = 248;
export const ELEMENT_INSPECTION_OUTLINE_MENU_ROW_HEIGHT_VP: number = 36;
export const ELEMENT_INSPECTION_OUTLINE_MENU_VERTICAL_INSET_VP: number = 6;
export const ELEMENT_INSPECTION_OUTLINE_MENU_DIVIDER_SLOT_VP: number = 9;
export const ELEMENT_INSPECTION_OUTLINE_MENU_EDGE_INSET_VP: number = 8;
export const ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_RADIUS_VP: number = 12;
export const ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_OFFSET_Y_VP: number = 4;
export const ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_BLEED_VP: number =
  ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_RADIUS_VP + ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_OFFSET_Y_VP;

export interface ElementInspectionOutlineMenuLayoutInput {
  anchorXVp: number;
  anchorYVp: number;
  hostWidthVp: number;
  hostHeightVp: number;
  preferredWidthVp: number;
  contentHeightVp: number;
  edgeInsetVp: number;
  shadowBleedVp: number;
}

export interface ElementInspectionOutlineMenuLayout {
  leftVp: number;
  topVp: number;
  widthVp: number;
  heightVp: number;
}

/**
 * Keeps the inspection context menu inside its host, which itself sits inside the app window.
 * A system context menu only avoids the screen, so it can paint onto the desktop past the window.
 */
export class ElementInspectionOutlineMenuLayoutViewModel {
  resolveContentHeight(itemCount: number, dividerCount: number): number {
    const items = Math.max(0, Math.floor(this.finite(itemCount, 0)));
    const dividers = Math.max(0, Math.floor(this.finite(dividerCount, 0)));
    return items * ELEMENT_INSPECTION_OUTLINE_MENU_ROW_HEIGHT_VP +
      dividers * ELEMENT_INSPECTION_OUTLINE_MENU_DIVIDER_SLOT_VP +
      ELEMENT_INSPECTION_OUTLINE_MENU_VERTICAL_INSET_VP * 2;
  }

  resolve(input: ElementInspectionOutlineMenuLayoutInput): ElementInspectionOutlineMenuLayout {
    const inset = Math.max(0, this.finite(input.edgeInsetVp, 0)) +
      Math.max(0, this.finite(input.shadowBleedVp, 0));
    const hostWidth = Math.max(1, this.finite(input.hostWidthVp, 1));
    const hostHeight = Math.max(1, this.finite(input.hostHeightVp, 1));
    const maxWidth = Math.max(1, hostWidth - inset * 2);
    const maxHeight = Math.max(1, hostHeight - inset * 2);
    const width = this.clamp(Math.max(1, this.finite(input.preferredWidthVp, maxWidth)), 1, maxWidth);
    const height = this.clamp(Math.max(1, this.finite(input.contentHeightVp, 1)), 1, maxHeight);
    const anchorX = this.clamp(this.finite(input.anchorXVp, inset), 0, hostWidth);
    const anchorY = this.clamp(this.finite(input.anchorYVp, inset), 0, hostHeight);
    return {
      leftVp: this.resolveOrigin(anchorX, width, hostWidth, inset),
      topVp: this.resolveOrigin(anchorY, height, hostHeight, inset),
      widthVp: width,
      heightVp: height
    };
  }

  private resolveOrigin(anchor: number, size: number, host: number, inset: number): number {
    const minOrigin = Math.min(inset, Math.max(0, host - size));
    const maxOrigin = Math.max(minOrigin, host - inset - size);
    const spaceAfter = host - inset - anchor;
    const spaceBefore = anchor - inset;
    let origin = anchor;
    if (size <= spaceAfter) {
      origin = anchor;
    } else if (size <= spaceBefore) {
      origin = anchor - size;
    } else if (spaceBefore > spaceAfter) {
      origin = anchor - size;
    }
    return this.clamp(origin, minOrigin, maxOrigin);
  }

  private finite(value: number, fallback: number): number {
    return Number.isFinite(value) ? value : fallback;
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.min(maxValue, Math.max(minValue, value));
  }
}
