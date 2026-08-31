import { BrowserThemePaletteId } from '../../common/models/BrowserModels';
import { BrowserThemePalette } from './BrowserThemePaletteModels';
import { CURATED_THEME_PALETTES } from './palettes/CuratedThemePalettes';
import {
  AIRA_CLASSIC_THEME_PALETTE,
  DEFAULT_THEME_PALETTE,
  AIRA_ORIGIN_THEME_PALETTE
} from './palettes/DefaultThemePalette';

export const BUILT_IN_THEME_PALETTES: BrowserThemePalette[] = [
  DEFAULT_THEME_PALETTE,
  AIRA_CLASSIC_THEME_PALETTE,
  AIRA_ORIGIN_THEME_PALETTE,
  ...CURATED_THEME_PALETTES
];

export const DEFAULT_BROWSER_THEME_PALETTE_ID: BrowserThemePaletteId = DEFAULT_THEME_PALETTE.id;

export function findBrowserThemePalette(id: BrowserThemePaletteId): BrowserThemePalette {
  return BUILT_IN_THEME_PALETTES.find((palette: BrowserThemePalette) => palette.id === id) ?? DEFAULT_THEME_PALETTE;
}
