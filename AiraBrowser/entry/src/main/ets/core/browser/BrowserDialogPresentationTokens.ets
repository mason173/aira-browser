/**
 * Single numeric owner for large-screen centered dialogs.
 *
 * Values follow the reference-image language in
 * docs/aira-desktop-dialog-design-spec.md. Call sites declare a tier; they do
 * not own these numbers.
 */

export const DESKTOP_DIALOG_CORNER_RADIUS_VP: number = 24;
export const DESKTOP_DIALOG_NARROW_CORNER_RADIUS_VP: number = 20;
export const DESKTOP_DIALOG_EDGE_VP: number = 24;
export const DESKTOP_DIALOG_NARROW_PADDING_VP: number = 20;
export const DESKTOP_DIALOG_PADDING_VP: number = 24;
export const DESKTOP_DIALOG_CONTENT_TOP_PADDING_VP: number = 24;
export const DESKTOP_DIALOG_ACTION_TOP_GAP_VP: number = 22;
export const DESKTOP_DIALOG_TITLE_FONT_SIZE_FP: number = 19;
export const DESKTOP_DIALOG_BODY_FONT_SIZE_FP: number = 13.5;
export const DESKTOP_DIALOG_ACTION_HEIGHT_VP: number = 40;
export const DESKTOP_DIALOG_ACTION_FONT_SIZE_FP: number = 14;
export const DESKTOP_DIALOG_ACTION_GAP_VP: number = 12;
export const DESKTOP_DIALOG_ACTION_LABEL_UNIT_VP: number = 14;
export const DESKTOP_DIALOG_ACTION_LABEL_PADDING_VP: number = 40;
export const DESKTOP_DIALOG_NARROW_WINDOW_VP: number = 600;
export const DESKTOP_DIALOG_STACK_ACTIONS_WINDOW_VP: number = 480;
export const DESKTOP_DIALOG_STEP_DOWN_WINDOW_VP: number = 1000;
export const DESKTOP_DIALOG_ENTER_DURATION_MS: number = 120;
export const DESKTOP_DIALOG_HEIGHT_CAP_VP: number = 720;
export const DESKTOP_DIALOG_DESTRUCTIVE_FILL: string = '#FFD8D5';
export const DESKTOP_DIALOG_DESTRUCTIVE_TEXT: string = '#E03127';

export type DesktopDialogTier = 'xs' | 's' | 'm' | 'l' | 'xl';

export class DesktopDialogTierSpec {
  readonly id: DesktopDialogTier;
  readonly widthVp: number;
  readonly minWidthVp: number;
  readonly maxHeightVp: number;

  constructor(id: DesktopDialogTier, widthVp: number, minWidthVp: number, maxHeightVp: number) {
    this.id = id;
    this.widthVp = widthVp;
    this.minWidthVp = minWidthVp;
    this.maxHeightVp = maxHeightVp;
  }
}

export function desktopDialogTierSpec(tier: DesktopDialogTier): DesktopDialogTierSpec {
  if (tier === 'xs') {
    return new DesktopDialogTierSpec('xs', 360, 320, 560);
  }
  if (tier === 's') {
    return new DesktopDialogTierSpec('s', 420, 320, 560);
  }
  if (tier === 'm') {
    return new DesktopDialogTierSpec('m', 520, 360, 640);
  }
  if (tier === 'l') {
    return new DesktopDialogTierSpec('l', 640, 420, 720);
  }
  return new DesktopDialogTierSpec('xl', 720, 480, 720);
}
