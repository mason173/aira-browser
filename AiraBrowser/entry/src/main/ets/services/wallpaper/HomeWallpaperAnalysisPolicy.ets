export const HOME_IMAGE_WALLPAPER_MASK_OPACITY: number = 36;

export function resolveHomeWallpaperRenderedMaskOpacity(maskOpacity: number): number {
  const normalizedMask = clampHomeWallpaperNumber(maskOpacity, 0, 100) / 100;
  return clampHomeWallpaperNumber(normalizedMask * 0.34, 0.06, 0.42);
}

function clampHomeWallpaperNumber(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) {
    return min;
  }
  return Math.max(min, Math.min(max, value));
}
