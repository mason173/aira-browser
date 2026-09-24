import { describe, expect, it } from '@ohos/hypium';
import {
  ELEMENT_INSPECTION_OUTLINE_MENU_EDGE_INSET_VP,
  ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_BLEED_VP,
  ElementInspectionOutlineMenuLayout,
  ElementInspectionOutlineMenuLayoutViewModel
} from '../main/ets/core/browser/ElementInspectionOutlineMenuLayout';

const VIEW_MODEL: ElementInspectionOutlineMenuLayoutViewModel = new ElementInspectionOutlineMenuLayoutViewModel();
const INSET: number = ELEMENT_INSPECTION_OUTLINE_MENU_EDGE_INSET_VP +
  ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_BLEED_VP;

function resolveLayout(
  anchorXVp: number,
  anchorYVp: number,
  hostWidthVp: number,
  hostHeightVp: number,
  contentHeightVp: number
): ElementInspectionOutlineMenuLayout {
  return VIEW_MODEL.resolve({
    anchorXVp: anchorXVp,
    anchorYVp: anchorYVp,
    hostWidthVp: hostWidthVp,
    hostHeightVp: hostHeightVp,
    preferredWidthVp: 248,
    contentHeightVp: contentHeightVp,
    edgeInsetVp: ELEMENT_INSPECTION_OUTLINE_MENU_EDGE_INSET_VP,
    shadowBleedVp: ELEMENT_INSPECTION_OUTLINE_MENU_SHADOW_BLEED_VP
  });
}

function assertInsideHost(layout: ElementInspectionOutlineMenuLayout, hostWidthVp: number, hostHeightVp: number): void {
  expect(layout.leftVp >= INSET).assertTrue();
  expect(layout.topVp >= INSET).assertTrue();
  expect(layout.leftVp + layout.widthVp <= hostWidthVp - INSET + 0.01).assertTrue();
  expect(layout.topVp + layout.heightVp <= hostHeightVp - INSET + 0.01).assertTrue();
}

export default function elementInspectionOutlineMenuLayoutTest(): void {
  describe('ElementInspectionOutlineMenuLayout', () => {
    it('opens down and right when the menu fits', 0, () => {
      const layout = resolveLayout(120, 80, 800, 700, 320);

      expect(layout.leftVp).assertEqual(120);
      expect(layout.topVp).assertEqual(80);
      expect(layout.widthVp).assertEqual(248);
      expect(layout.heightVp).assertEqual(320);
      assertInsideHost(layout, 800, 700);
    });

    it('flips above the anchor when the bottom of the window cannot hold it', 0, () => {
      const layout = resolveLayout(160, 640, 800, 700, 320);

      expect(layout.topVp).assertEqual(320);
      expect(layout.heightVp).assertEqual(320);
      assertInsideHost(layout, 800, 700);
    });

    it('shifts left when the right edge of the window cannot hold it', 0, () => {
      const layout = resolveLayout(700, 80, 760, 700, 320);

      expect(layout.leftVp).assertEqual(452);
      expect(layout.widthVp).assertEqual(248);
      assertInsideHost(layout, 760, 700);
    });

    it('caps height and keeps the menu inside a short window', 0, () => {
      const layout = resolveLayout(40, 420, 480, 460, 640);

      expect(layout.heightVp).assertEqual(460 - INSET * 2);
      assertInsideHost(layout, 480, 460);
    });
  });
}
