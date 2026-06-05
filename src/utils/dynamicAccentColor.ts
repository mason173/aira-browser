import {
  ADAPTIVE_NEUTRAL_ACCENT,
  DEFAULT_ACCENT_COLOR,
  getWallpaperAccentSlotIndex,
  isHexAccentColor,
  resolveAdaptiveNeutralAccent,
  resolveLegacyNamedAccentColor,
} from '@/utils/accentColor';
import type { WallpaperMode } from '@/wallpaper/types';

type DynamicAccentInput = {
  wallpaperMode: WallpaperMode;
  bingWallpaper: string;
  customWallpaper: string | null;
  colorWallpaperId?: string;
};

type ResolveDynamicAccentOptions = {
  forceImageResample?: boolean;
};

type ResolveAccentColorOptions = ResolveDynamicAccentOptions & {
  isDarkTheme: boolean;
};

export const DEFAULT_WALLPAPER_ACCENT_PALETTE = [
  '#3b82f6',
  '#22c55e',
  '#f59e0b',
  '#7c3aed',
  '#ec4899',
  '#0ea5e9',
];

const hexToRgb = (hex: string) => {
  const value = hex.replace('#', '');
  const normalized = value.length === 3 ? value.split('').map((c) => c + c).join('') : value;
  const int = Number.parseInt(normalized, 16);
  return {
    r: (int >> 16) & 255,
    g: (int >> 8) & 255,
    b: int & 255,
  };
};

const resolveForeground = (hex: string) => {
  const { r, g, b } = hexToRgb(hex);
  const toLinear = (v: number) => {
    const s = v / 255;
    return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  };
  const luminance = 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);
  return luminance > 0.36 ? '#111827' : '#ffffff';
};

export const buildRecommendedAccentPaletteFromHexes = (
  _hexes: string[],
  count = DEFAULT_WALLPAPER_ACCENT_PALETTE.length,
): string[] => DEFAULT_WALLPAPER_ACCENT_PALETTE.slice(0, count);

export const sampleAccentPaletteFromImageData = (
  _data: Uint8ClampedArray,
  _width: number,
  _height: number,
): string[] => DEFAULT_WALLPAPER_ACCENT_PALETTE;

export const sampleAccentFromImageData = (
  _data: Uint8ClampedArray,
  _width: number,
  _height: number,
): string => DEFAULT_WALLPAPER_ACCENT_PALETTE[0];

export const resolveDynamicAccentColor = async (
  input: DynamicAccentInput,
  options?: ResolveDynamicAccentOptions,
) => {
  return resolveAccentColorSelection('dynamic', input, {
    ...options,
    isDarkTheme: false,
  });
};

export const resolveWallpaperAccentPalette = async (
  _input: DynamicAccentInput,
  _options?: ResolveDynamicAccentOptions,
) => DEFAULT_WALLPAPER_ACCENT_PALETTE;

export const resolveAccentColorSelection = async (
  selection: string,
  _input: DynamicAccentInput,
  options: ResolveAccentColorOptions,
) => {
  const normalizedSelection = selection.trim() || DEFAULT_ACCENT_COLOR;
  const wallpaperSlotIndex = getWallpaperAccentSlotIndex(normalizedSelection);
  if (wallpaperSlotIndex !== null || normalizedSelection === 'dynamic' || normalizedSelection === DEFAULT_ACCENT_COLOR) {
    const slotIndex = wallpaperSlotIndex ?? 0;
    return DEFAULT_WALLPAPER_ACCENT_PALETTE[slotIndex] || DEFAULT_WALLPAPER_ACCENT_PALETTE[0];
  }
  if (normalizedSelection === ADAPTIVE_NEUTRAL_ACCENT) {
    return resolveAdaptiveNeutralAccent(options.isDarkTheme);
  }
  if (isHexAccentColor(normalizedSelection)) {
    return normalizedSelection;
  }
  const legacyColor = resolveLegacyNamedAccentColor(normalizedSelection, options.isDarkTheme);
  if (legacyColor) return legacyColor;
  return DEFAULT_WALLPAPER_ACCENT_PALETTE[0];
};

export const applyDynamicAccentColor = (hex: string) => {
  const root = document.documentElement;
  const { r, g, b } = hexToRgb(hex);
  root.style.setProperty('--primary', hex);
  root.style.setProperty('--ring', hex);
  root.style.setProperty('--primary-foreground', resolveForeground(hex));
  root.style.setProperty('--tint-rgb', `${r} ${g} ${b}`);
};

export const clearDynamicAccentColor = () => {
  const root = document.documentElement;
  root.style.removeProperty('--primary');
  root.style.removeProperty('--ring');
  root.style.removeProperty('--primary-foreground');
  root.style.removeProperty('--tint-rgb');
};
