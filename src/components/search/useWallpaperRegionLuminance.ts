import { useEffect, useState } from 'react';
import { useWallpaperBackdropSnapshot } from '@/components/wallpaper/WallpaperBackdropContext';

const HEX_COLOR_PATTERN = /#[0-9a-fA-F]{6}/g;

export type WallpaperRegionLuminance = {
  average: number;
  p15: number;
  p85: number;
};

function clamp01(value: number) {
  if (!Number.isFinite(value)) return 0;
  return Math.min(1, Math.max(0, value));
}

function srgbChannelToLinear(channel: number) {
  const normalized = clamp01(channel / 255);
  if (normalized <= 0.04045) return normalized / 12.92;
  return ((normalized + 0.055) / 1.055) ** 2.4;
}

function resolveRelativeLuminance(red: number, green: number, blue: number) {
  return (
    (0.2126 * srgbChannelToLinear(red))
    + (0.7152 * srgbChannelToLinear(green))
    + (0.0722 * srgbChannelToLinear(blue))
  );
}

function hexToRgb(hex: string) {
  const normalized = hex.replace('#', '');
  const parsed = Number.parseInt(normalized, 16);
  return {
    red: (parsed >> 16) & 255,
    green: (parsed >> 8) & 255,
    blue: parsed & 255,
  };
}

function resolveGradientLuminanceStats(gradient: string): WallpaperRegionLuminance | null {
  const gradientHexes = gradient.match(HEX_COLOR_PATTERN) || [];
  if (gradientHexes.length === 0) return null;

  const luminanceSamples = gradientHexes.map((hex) => {
    const color = hexToRgb(hex);
    return resolveRelativeLuminance(color.red, color.green, color.blue);
  }).sort((left, right) => left - right);

  const sampleCount = luminanceSamples.length;
  const average = luminanceSamples.reduce((sum, value) => sum + value, 0) / sampleCount;
  const p15 = luminanceSamples[Math.max(0, Math.round((sampleCount - 1) * 0.15))] ?? average;
  const p85 = luminanceSamples[Math.min(sampleCount - 1, Math.round((sampleCount - 1) * 0.85))] ?? average;

  return {
    average: clamp01(average),
    p15: clamp01(p15),
    p85: clamp01(p85),
  };
}

export function useWallpaperRegionLuminance(surfaceNode: HTMLElement | null, enabled = true) {
  const wallpaperBackdrop = useWallpaperBackdropSnapshot();
  void surfaceNode;
  const [luminance, setLuminance] = useState<WallpaperRegionLuminance | null>(() => (
    enabled && wallpaperBackdrop?.wallpaperMode === 'color'
      ? resolveGradientLuminanceStats(wallpaperBackdrop.colorWallpaperGradient)
      : null
  ));

  useEffect(() => {
    if (!enabled) {
      setLuminance(null);
      return;
    }

    setLuminance(
      wallpaperBackdrop?.wallpaperMode === 'color'
        ? resolveGradientLuminanceStats(wallpaperBackdrop.colorWallpaperGradient)
        : null,
    );
  }, [
    enabled,
    wallpaperBackdrop?.colorWallpaperGradient,
    wallpaperBackdrop?.wallpaperMode,
  ]);

  return luminance;
}
