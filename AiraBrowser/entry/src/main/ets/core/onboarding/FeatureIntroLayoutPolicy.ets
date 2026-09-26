export interface FeatureIntroLayoutInput {
  windowWidthVp: number;
  windowHeightVp: number;
  topInsetVp: number;
  bottomInsetVp: number;
}

export interface FeatureIntroLayout {
  videoHeightVp: number;
  contentMaxWidthVp: number;
  horizontalPaddingVp: number;
  bottomPaddingVp: number;
}

export const FEATURE_INTRO_VIDEO_ASPECT_WIDTH: number = 9;
export const FEATURE_INTRO_VIDEO_ASPECT_HEIGHT: number = 8;
export const FEATURE_INTRO_CONTENT_MAX_WIDTH_VP: number = 430;
export const FEATURE_INTRO_HORIZONTAL_PADDING_VP: number = 24;
export const FEATURE_INTRO_CONTENT_RESERVE_VP: number = 236;
export const FEATURE_INTRO_MIN_VIDEO_HEIGHT_VP: number = 96;
export const FEATURE_INTRO_MAX_VIDEO_HEIGHT_VP: number = 440;
export const FEATURE_INTRO_BOTTOM_PADDING_VP: number = 24;
export const FEATURE_INTRO_PAGE_BACKGROUND_COLOR: string = '#FFFFFF';

/**
 * One intro video later fills this slot with cover. The slot keeps a 9:8 shape
 * on a normal phone, shrinks on a short window so the title and button remain,
 * and stops growing on a wide window so a tablet does not become an empty band.
 */
export function resolveFeatureIntroLayout(input: FeatureIntroLayoutInput): FeatureIntroLayout {
  const width = positive(input.windowWidthVp);
  const height = positive(input.windowHeightVp);
  const topInset = positive(input.topInsetVp);
  const bottomInset = positive(input.bottomInsetVp);
  const available = Math.max(0, height - topInset - bottomInset);
  const room = Math.max(0, available - FEATURE_INTRO_CONTENT_RESERVE_VP);
  const preferred = width * FEATURE_INTRO_VIDEO_ASPECT_HEIGHT / FEATURE_INTRO_VIDEO_ASPECT_WIDTH;
  const capped = Math.min(preferred, FEATURE_INTRO_MAX_VIDEO_HEIGHT_VP, room);
  const videoHeight = room >= FEATURE_INTRO_MIN_VIDEO_HEIGHT_VP
    ? Math.max(FEATURE_INTRO_MIN_VIDEO_HEIGHT_VP, capped)
    : capped;
  return {
    videoHeightVp: Math.round(videoHeight),
    contentMaxWidthVp: FEATURE_INTRO_CONTENT_MAX_WIDTH_VP,
    horizontalPaddingVp: FEATURE_INTRO_HORIZONTAL_PADDING_VP,
    bottomPaddingVp: Math.max(FEATURE_INTRO_BOTTOM_PADDING_VP, Math.round(bottomInset))
  };
}

function positive(value: number): number {
  return Number.isFinite(value) && value > 0 ? value : 0;
}
