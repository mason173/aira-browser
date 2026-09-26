export const FEATURE_INTRO_GATE_TRACK_MAX_WIDTH_VP: number = 520;
export const FEATURE_INTRO_GATE_TRACK_HEIGHT_VP: number = 62;
export const FEATURE_INTRO_GATE_KNOB_VP: number = 50;
export const FEATURE_INTRO_GATE_KNOB_INSET_VP: number = 6;
export const FEATURE_INTRO_GATE_UNLOCK_RATIO: number = 0.86;

const FEATURE_INTRO_GATE_LABEL_FADE: number = 1.35;

export function featureIntroGateBackdropColor(resolvedMode: string): string {
  return resolvedMode === 'dark' ? '#000000' : '#FFFFFF';
}

export function resolveFeatureIntroGateLogoSize(windowWidthVp: number): number {
  const scaled = Math.round(windowWidthVp * 0.23);
  return Math.min(100, Math.max(72, scaled));
}

export function resolveFeatureIntroGateLogoTop(windowHeightVp: number, topInsetVp: number, logoSizeVp: number): number {
  const preferred = Math.round(windowHeightVp * 0.28);
  const minimum = topInsetVp + 24;
  const maximum = Math.max(minimum, windowHeightVp - logoSizeVp - 160);
  return Math.min(Math.max(preferred, minimum), maximum);
}

export function resolveFeatureIntroGateTravel(trackWidthVp: number): number {
  const travel = trackWidthVp - FEATURE_INTRO_GATE_KNOB_VP - FEATURE_INTRO_GATE_KNOB_INSET_VP * 2;
  return travel > 0 ? travel : 0;
}

export function clampFeatureIntroGateDrag(offsetVp: number, travelVp: number): number {
  if (travelVp <= 0) {
    return 0;
  }
  return Math.min(travelVp, Math.max(0, offsetVp));
}

export function isFeatureIntroGateUnlocked(offsetVp: number, travelVp: number): boolean {
  if (travelVp <= 0) {
    return false;
  }
  return offsetVp >= travelVp * FEATURE_INTRO_GATE_UNLOCK_RATIO;
}

export function resolveFeatureIntroGateLabelOpacity(offsetVp: number, travelVp: number): number {
  if (travelVp <= 0) {
    return 1;
  }
  const faded = 1 - (offsetVp / travelVp) * FEATURE_INTRO_GATE_LABEL_FADE;
  return faded > 0 ? faded : 0;
}
