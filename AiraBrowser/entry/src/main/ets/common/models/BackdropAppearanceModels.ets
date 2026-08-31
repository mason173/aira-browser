import { BrowserResolvedThemeMode } from './BrowserModels';

export type BrowserHomepageBackdropAppearanceSourceKind =
  'system_home' |
  'custom_url_home' |
  'custom_imported_home';

export type BrowserHomepageBackdropForegroundTone = 'light' | 'dark';

export interface BrowserHomepageBackdropAppearanceSource {
  kind: BrowserHomepageBackdropAppearanceSourceKind;
  id: string;
  version: string;
  privateMode: boolean;
  storedAppearance?: BrowserHomepageBackdropAppearanceState;
}

export interface BrowserHomepageBackdropAppearanceEffectInput {
  resolvedThemeMode: BrowserResolvedThemeMode;
  tintColor: string;
  tintOpacity: number;
  effectSignature: string;
}

export interface BrowserHomepageBackdropAppearanceState {
  available: boolean;
  sourceKey: string;
  snapshotSignature: string;
  algorithmVersion: number;
  resolvedThemeMode: BrowserResolvedThemeMode;
  toolbarSurfaceColor: string;
  toolbarForegroundTone: BrowserHomepageBackdropForegroundTone;
  toolbarLabelTextColor: string;
  toolbarPrimaryTextColor: string;
  toolbarSecondaryTextColor: string;
  toolbarPressedOverlayColor: string;
  toolbarOutlineColor: string;
  updatedAt: number;
  volatileOnly: boolean;
}

export const BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION: number = 6;

export const DEFAULT_BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_STATE: BrowserHomepageBackdropAppearanceState = {
  available: false,
  sourceKey: '',
  snapshotSignature: '',
  algorithmVersion: BROWSER_HOMEPAGE_BACKDROP_APPEARANCE_ALGORITHM_VERSION,
  resolvedThemeMode: 'light',
  toolbarSurfaceColor: '',
  toolbarForegroundTone: 'dark',
  toolbarLabelTextColor: '',
  toolbarPrimaryTextColor: '',
  toolbarSecondaryTextColor: '',
  toolbarPressedOverlayColor: '',
  toolbarOutlineColor: '',
  updatedAt: 0,
  volatileOnly: false
};

export function cloneBrowserHomepageBackdropAppearanceState(
  state: BrowserHomepageBackdropAppearanceState
): BrowserHomepageBackdropAppearanceState {
  return {
    available: state.available,
    sourceKey: state.sourceKey,
    snapshotSignature: state.snapshotSignature,
    algorithmVersion: state.algorithmVersion,
    resolvedThemeMode: state.resolvedThemeMode,
    toolbarSurfaceColor: state.toolbarSurfaceColor,
    toolbarForegroundTone: state.toolbarForegroundTone,
    toolbarLabelTextColor: state.toolbarLabelTextColor,
    toolbarPrimaryTextColor: state.toolbarPrimaryTextColor,
    toolbarSecondaryTextColor: state.toolbarSecondaryTextColor,
    toolbarPressedOverlayColor: state.toolbarPressedOverlayColor,
    toolbarOutlineColor: state.toolbarOutlineColor,
    updatedAt: state.updatedAt,
    volatileOnly: state.volatileOnly
  };
}
