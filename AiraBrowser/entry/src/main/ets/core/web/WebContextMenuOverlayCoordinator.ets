import {
  BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP,
  BROWSER_DESKTOP_MENU_WIDTH_VP
} from '../browser/BrowserDesktopMenuPresentationTokens';

export type WebContextMenuOverlayPlacement =
  'bottom_right' |
  'bottom_left' |
  'top_right' |
  'top_left';

type WebContextMenuHorizontalSide = 'left' | 'right';
type WebContextMenuVerticalSide = 'top' | 'bottom';
export type WebContextMenuOverlayPresentation = 'touch' | 'desktop';

export interface WebContextMenuRawPoint {
  rawWebXPx: number;
  rawWebYPx: number;
}

export interface WebContextMenuViewportGeometry {
  rootWidthVp: number;
  rootHeightVp: number;
  webLeftVp: number;
  webTopVp: number;
  webWidthVp: number;
  webHeightVp: number;
}

export interface WebContextMenuMeasuredSize {
  menuWidthVp: number;
  menuHeightVp: number;
}

interface WebContextMenuOverlayPolicy {
  edgeInsetVp: number;
  pressGapVp: number;
  minMenuWidthVp: number;
  preferredMenuWidthVp: number;
  maxMenuWidthVp: number;
  rowHeightVp: number;
  verticalPaddingVp: number;
  dividerWidthVp: number;
}

export interface WebContextMenuOverlayLayoutRequest {
  point: WebContextMenuRawPoint;
  geometry: WebContextMenuViewportGeometry;
  itemCount: number;
  dividerCount: number;
  presentation: WebContextMenuOverlayPresentation;
}

export interface WebContextMenuOverlayLayout {
  visible: boolean;
  pressXVp: number;
  pressYVp: number;
  menuLeftVp: number;
  menuTopVp: number;
  menuWidthVp: number;
  menuHeightVp: number;
  maxHeightVp: number;
  placement: WebContextMenuOverlayPlacement;
  presentation: WebContextMenuOverlayPresentation;
}

interface WebContextMenuHorizontalPlacement {
  side: WebContextMenuHorizontalSide;
  positionVp: number;
}

interface WebContextMenuVerticalPlacement {
  side: WebContextMenuVerticalSide;
  positionVp: number;
}

const DEFAULT_WEB_CONTEXT_MENU_EDGE_INSET_VP: number = 8;
const DEFAULT_WEB_CONTEXT_MENU_PRESS_GAP_VP: number = 6;
const DEFAULT_WEB_CONTEXT_MENU_MIN_WIDTH_VP: number = 220;
const DEFAULT_WEB_CONTEXT_MENU_PREFERRED_WIDTH_VP: number = 248;
const DEFAULT_WEB_CONTEXT_MENU_MAX_WIDTH_VP: number = 320;
const DEFAULT_WEB_CONTEXT_MENU_ROW_HEIGHT_VP: number = 44;
const DEFAULT_WEB_CONTEXT_MENU_VERTICAL_PADDING_VP: number = 6;
const DEFAULT_WEB_CONTEXT_MENU_DIVIDER_WIDTH_VP: number = 1;

export class WebContextMenuOverlayCoordinator {
  createHiddenLayout(): WebContextMenuOverlayLayout {
    return {
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
  }

  private createDefaultPolicy(presentation: WebContextMenuOverlayPresentation): WebContextMenuOverlayPolicy {
    const desktop = presentation === 'desktop';
    return {
      edgeInsetVp: DEFAULT_WEB_CONTEXT_MENU_EDGE_INSET_VP,
      pressGapVp: DEFAULT_WEB_CONTEXT_MENU_PRESS_GAP_VP,
      minMenuWidthVp: desktop ? BROWSER_DESKTOP_MENU_WIDTH_VP : DEFAULT_WEB_CONTEXT_MENU_MIN_WIDTH_VP,
      preferredMenuWidthVp: desktop ? BROWSER_DESKTOP_MENU_WIDTH_VP : DEFAULT_WEB_CONTEXT_MENU_PREFERRED_WIDTH_VP,
      maxMenuWidthVp: desktop ? BROWSER_DESKTOP_MENU_WIDTH_VP : DEFAULT_WEB_CONTEXT_MENU_MAX_WIDTH_VP,
      rowHeightVp: desktop ? BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP : DEFAULT_WEB_CONTEXT_MENU_ROW_HEIGHT_VP,
      verticalPaddingVp: desktop ? BROWSER_DESKTOP_MENU_VERTICAL_INSET_VP : DEFAULT_WEB_CONTEXT_MENU_VERTICAL_PADDING_VP,
      dividerWidthVp: desktop ? BROWSER_DESKTOP_MENU_DIVIDER_WIDTH_VP : DEFAULT_WEB_CONTEXT_MENU_DIVIDER_WIDTH_VP
    };
  }

  buildInitialLayout(request: WebContextMenuOverlayLayoutRequest): WebContextMenuOverlayLayout {
    return this.buildLayout(request, undefined);
  }

  buildMeasuredLayout(
    request: WebContextMenuOverlayLayoutRequest,
    measuredSize: WebContextMenuMeasuredSize
  ): WebContextMenuOverlayLayout {
    return this.buildLayout(request, measuredSize);
  }

  private buildLayout(
    request: WebContextMenuOverlayLayoutRequest,
    measuredSize: WebContextMenuMeasuredSize | undefined
  ): WebContextMenuOverlayLayout {
    if (request.itemCount <= 0) {
      return this.createHiddenLayout();
    }
    const policy = this.createDefaultPolicy(request.presentation);
    const geometry = this.normalizeGeometry(request.geometry);
    const edgeInsetVp = this.clamp(policy.edgeInsetVp, 0, Math.max(0, Math.min(geometry.rootWidthVp, geometry.rootHeightVp) / 2));
    const menuWidthVp = this.resolveMenuWidth(geometry.rootWidthVp, policy, measuredSize);
    const maxHeightVp = Math.max(1, geometry.rootHeightVp - edgeInsetVp * 2);
    const menuHeightVp = Math.min(
      this.resolveMenuHeight(request.itemCount, request.dividerCount, policy, measuredSize),
      maxHeightVp
    );
    const pressXVp = this.resolvePressX(request.point, geometry, edgeInsetVp);
    const pressYVp = this.resolvePressY(request.point, geometry, edgeInsetVp);
    const horizontal = this.resolveHorizontalPlacement(pressXVp, menuWidthVp, geometry.rootWidthVp, policy.pressGapVp, edgeInsetVp);
    const vertical = this.resolveVerticalPlacement(pressYVp, menuHeightVp, geometry.rootHeightVp, policy.pressGapVp, edgeInsetVp);
    return {
      visible: true,
      pressXVp: pressXVp,
      pressYVp: pressYVp,
      menuLeftVp: horizontal.positionVp,
      menuTopVp: vertical.positionVp,
      menuWidthVp: menuWidthVp,
      menuHeightVp: menuHeightVp,
      maxHeightVp: maxHeightVp,
      placement: this.resolvePlacement(vertical.side, horizontal.side),
      presentation: request.presentation
    };
  }

  private normalizeGeometry(geometry: WebContextMenuViewportGeometry): WebContextMenuViewportGeometry {
    const rootWidthVp = this.positive(geometry.rootWidthVp);
    const rootHeightVp = this.positive(geometry.rootHeightVp);
    const webLeftVp = this.clamp(this.nonNegative(geometry.webLeftVp), 0, rootWidthVp);
    const webTopVp = this.clamp(this.nonNegative(geometry.webTopVp), 0, rootHeightVp);
    return {
      rootWidthVp: rootWidthVp,
      rootHeightVp: rootHeightVp,
      webLeftVp: webLeftVp,
      webTopVp: webTopVp,
      webWidthVp: this.clamp(this.positive(geometry.webWidthVp), 1, Math.max(1, rootWidthVp - webLeftVp)),
      webHeightVp: this.clamp(this.positive(geometry.webHeightVp), 1, Math.max(1, rootHeightVp - webTopVp))
    };
  }

  private resolvePressX(point: WebContextMenuRawPoint, geometry: WebContextMenuViewportGeometry, edgeInsetVp: number): number {
    const localXVp = point.rawWebXPx >= 0 ? this.clamp(px2vp(Math.max(0, point.rawWebXPx)), 0, geometry.webWidthVp) :
      Math.round(geometry.webWidthVp / 2);
    return this.clamp(geometry.webLeftVp + localXVp, edgeInsetVp, Math.max(edgeInsetVp, geometry.rootWidthVp - edgeInsetVp));
  }

  private resolvePressY(point: WebContextMenuRawPoint, geometry: WebContextMenuViewportGeometry, edgeInsetVp: number): number {
    const localYVp = point.rawWebYPx >= 0 ? this.clamp(px2vp(Math.max(0, point.rawWebYPx)), 0, geometry.webHeightVp) :
      Math.round(geometry.webHeightVp / 2);
    return this.clamp(geometry.webTopVp + localYVp, edgeInsetVp, Math.max(edgeInsetVp, geometry.rootHeightVp - edgeInsetVp));
  }

  private resolveMenuWidth(
    rootWidthVp: number,
    policy: WebContextMenuOverlayPolicy,
    measuredSize: WebContextMenuMeasuredSize | undefined
  ): number {
    const maxAvailableWidth = Math.max(1, rootWidthVp - policy.edgeInsetVp * 2);
    if (measuredSize !== undefined && measuredSize.menuWidthVp > 1) {
      return this.clamp(measuredSize.menuWidthVp, 1, maxAvailableWidth);
    }
    return this.clamp(
      policy.preferredMenuWidthVp,
      Math.min(policy.minMenuWidthVp, maxAvailableWidth),
      Math.min(policy.maxMenuWidthVp, maxAvailableWidth)
    );
  }

  private resolveMenuHeight(
    itemCount: number,
    dividerCount: number,
    policy: WebContextMenuOverlayPolicy,
    measuredSize: WebContextMenuMeasuredSize | undefined
  ): number {
    if (measuredSize !== undefined && measuredSize.menuHeightVp > 1) {
      return measuredSize.menuHeightVp;
    }
    return Math.max(
      1,
      itemCount * policy.rowHeightVp +
        policy.verticalPaddingVp * 2 +
        Math.max(0, dividerCount) * policy.dividerWidthVp
    );
  }

  private resolveHorizontalPlacement(
    pressXVp: number,
    menuWidthVp: number,
    rootWidthVp: number,
    pressGapVp: number,
    edgeInsetVp: number
  ): WebContextMenuHorizontalPlacement {
    if (pressXVp + pressGapVp + menuWidthVp <= rootWidthVp - edgeInsetVp) {
      return {
        side: 'right',
        positionVp: this.clamp(pressXVp + pressGapVp, edgeInsetVp, Math.max(edgeInsetVp, rootWidthVp - edgeInsetVp - menuWidthVp))
      };
    }
    return {
      side: 'left',
      positionVp: this.clamp(pressXVp - pressGapVp - menuWidthVp, edgeInsetVp, Math.max(edgeInsetVp, rootWidthVp - edgeInsetVp - menuWidthVp))
    };
  }

  private resolveVerticalPlacement(
    pressYVp: number,
    menuHeightVp: number,
    rootHeightVp: number,
    pressGapVp: number,
    edgeInsetVp: number
  ): WebContextMenuVerticalPlacement {
    if (pressYVp + pressGapVp + menuHeightVp <= rootHeightVp - edgeInsetVp) {
      return {
        side: 'bottom',
        positionVp: this.clamp(pressYVp + pressGapVp, edgeInsetVp, Math.max(edgeInsetVp, rootHeightVp - edgeInsetVp - menuHeightVp))
      };
    }
    return {
      side: 'top',
      positionVp: this.clamp(pressYVp - pressGapVp - menuHeightVp, edgeInsetVp, Math.max(edgeInsetVp, rootHeightVp - edgeInsetVp - menuHeightVp))
    };
  }

  private resolvePlacement(
    verticalSide: WebContextMenuVerticalSide,
    horizontalSide: WebContextMenuHorizontalSide
  ): WebContextMenuOverlayPlacement {
    if (verticalSide === 'top') {
      return horizontalSide === 'left' ? 'top_left' : 'top_right';
    }
    return horizontalSide === 'left' ? 'bottom_left' : 'bottom_right';
  }

  private positive(value: number): number {
    return Number.isFinite(value) && value > 0 ? value : 1;
  }

  private nonNegative(value: number): number {
    return Number.isFinite(value) && value > 0 ? value : 0;
  }

  private clamp(value: number, minValue: number, maxValue: number): number {
    return Math.min(Math.max(value, minValue), Math.max(minValue, maxValue));
  }
}
