export const HOME_WALLPAPER_APPEARANCE_TRANSITION_MS: number = 220;

export function normalizeHomeWallpaperTransitionDuration(durationMs: number): number {
  if (!Number.isFinite(durationMs) || durationMs <= 0) {
    return 0;
  }
  return Math.floor(durationMs);
}
