import { BrowserResolvedThemeMode } from '../../common/models/BrowserModels';

export interface BrowserBackdropEffectState {
  progress: number;
  contentScale: number;
  blurRadius: number;
  blurEdgeScale: number;
  tintColor: ResourceColor;
  tintOpacity: number;
}

export interface BrowserBackdropEffectTintProfile {
  tintColor: ResourceColor;
  tintMaxOpacity: number;
}

export const DEFAULT_BROWSER_BACKDROP_EFFECT_STATE: BrowserBackdropEffectState = {
  progress: 0,
  contentScale: 1,
  blurRadius: 0,
  blurEdgeScale: 1,
  tintColor: '#000000',
  tintOpacity: 0
};

const BROWSER_BACKDROP_EFFECT_MAX_SCALE: number = 1.05;
const BROWSER_BACKDROP_EFFECT_MAX_BLUR_RADIUS: number = 64;
const HOME_BACKDROP_TINT_PROFILE: BrowserBackdropEffectTintProfile = {
  tintColor: '#000000',
  tintMaxOpacity: 0.18
};
const WEB_LIGHT_SNAPSHOT_TINT_PROFILE: BrowserBackdropEffectTintProfile = {
  tintColor: '#000000',
  tintMaxOpacity: 0.18
};
const WEB_DARK_SNAPSHOT_TINT_PROFILE: BrowserBackdropEffectTintProfile = {
  tintColor: '#FFFFFF',
  tintMaxOpacity: 0.08
};

export class BrowserBackdropEffectViewModel {
  buildHomeLiveState(progress: number): BrowserBackdropEffectState {
    return this.buildState(progress, HOME_BACKDROP_TINT_PROFILE);
  }

  buildTabsHomeRevealState(progress: number): BrowserBackdropEffectState {
    return this.buildState(progress, HOME_BACKDROP_TINT_PROFILE);
  }

  buildWebSnapshotState(
    progress: number,
    resolvedThemeMode: BrowserResolvedThemeMode | string
  ): BrowserBackdropEffectState {
    return this.buildState(progress, this.resolveWebSnapshotTintProfile(resolvedThemeMode));
  }

  buildState(progress: number, tintProfile: BrowserBackdropEffectTintProfile): BrowserBackdropEffectState {
    const safeProgress = this.clampProgress(progress);
    const tintMaxOpacity = this.resolveTintMaxOpacity(tintProfile.tintMaxOpacity);
    return {
      progress: safeProgress,
      contentScale: 1 + (BROWSER_BACKDROP_EFFECT_MAX_SCALE - 1) * safeProgress,
      blurRadius: BROWSER_BACKDROP_EFFECT_MAX_BLUR_RADIUS * safeProgress,
      blurEdgeScale: 1,
      tintColor: tintProfile.tintColor,
      tintOpacity: tintMaxOpacity * safeProgress
    };
  }

  resolveProgress(progress: number, tabsSheetVisible: boolean): number {
    if (tabsSheetVisible) {
      return 0;
    }
    return this.clampProgress(progress);
  }

  private resolveWebSnapshotTintProfile(
    resolvedThemeMode: BrowserResolvedThemeMode | string
  ): BrowserBackdropEffectTintProfile {
    return resolvedThemeMode === 'dark' ? WEB_DARK_SNAPSHOT_TINT_PROFILE : WEB_LIGHT_SNAPSHOT_TINT_PROFILE;
  }

  private resolveTintMaxOpacity(tintMaxOpacity: number): number {
    if (!Number.isFinite(tintMaxOpacity) || tintMaxOpacity <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(1, tintMaxOpacity));
  }

  private clampProgress(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }
    return Math.max(0, Math.min(1, progress));
  }
}
