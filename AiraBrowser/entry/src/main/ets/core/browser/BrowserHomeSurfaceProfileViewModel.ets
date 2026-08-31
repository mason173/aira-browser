import { CustomHomepagePresentationState } from '../customhome/CustomHomepagePresentationViewModel';

export type BrowserHomeSurfaceKind =
  'system_native' |
  'imported_web_home' |
  'remote_web_home' |
  'unavailable';

export type BrowserHomeSurfaceScene = 'system_home' | 'third_party_home' | 'web_page' | 'hidden';
export type BrowserHomeSurfaceRenderer = 'native_home' | 'web_home' | 'fallback';
export type BrowserHomeSurfaceWallpaperMode = 'system_wallpaper' | 'theme_background';
export type BrowserHomeForegroundBackdropSource = 'system_home' | 'web_home' | 'theme';

export interface BrowserHomeSurfaceProfileInput {
  showHomePage: boolean;
  webPageVisible: boolean;
  thirdPartyHomepageAllowed: boolean;
  customHomepageState: CustomHomepagePresentationState;
  customHomepageWebVisible: boolean;
}

export interface BrowserHomeSurfaceProfile {
  surfaceKind: BrowserHomeSurfaceKind;
  scene: BrowserHomeSurfaceScene;
  renderer: BrowserHomeSurfaceRenderer;
  wallpaperMode: BrowserHomeSurfaceWallpaperMode;
  foregroundBackdropSource: BrowserHomeForegroundBackdropSource;
  bottomSearchVisible: boolean;
  systemEntryButtonVisible: boolean;
  expandedToolbarBackdropRequired: boolean;
}

export class BrowserHomeSurfaceProfileViewModel {
  buildProfile(input: BrowserHomeSurfaceProfileInput): BrowserHomeSurfaceProfile {
    const surfaceKind = this.resolveSurfaceKind(input.customHomepageState, input.thirdPartyHomepageAllowed);
    const scene = this.resolveScene(input, surfaceKind);
    const bottomSearchVisible = this.resolveBottomSearchVisible(scene, input.customHomepageState);
    const expandedToolbarBackdropRequired = bottomSearchVisible &&
      (scene === 'system_home' || scene === 'third_party_home');
    return {
      surfaceKind: surfaceKind,
      scene: scene,
      renderer: this.resolveRenderer(surfaceKind),
      wallpaperMode: surfaceKind === 'system_native' ? 'system_wallpaper' : 'theme_background',
      foregroundBackdropSource: this.resolveForegroundBackdropSource(surfaceKind, input.customHomepageWebVisible),
      bottomSearchVisible: bottomSearchVisible,
      systemEntryButtonVisible: this.resolveSystemEntryButtonVisible(scene, input),
      expandedToolbarBackdropRequired: expandedToolbarBackdropRequired
    };
  }

  private resolveSurfaceKind(
    customHomepageState: CustomHomepagePresentationState,
    thirdPartyHomepageAllowed: boolean
  ): BrowserHomeSurfaceKind {
    if (!thirdPartyHomepageAllowed) {
      return 'system_native';
    }
    if (customHomepageState.kind === 'system') {
      return 'system_native';
    }
    if (customHomepageState.kind === 'custom_unavailable') {
      return 'unavailable';
    }
    if (customHomepageState.isRemoteUrlHomepage) {
      return 'remote_web_home';
    }
    return 'imported_web_home';
  }

  private resolveScene(
    input: BrowserHomeSurfaceProfileInput,
    surfaceKind: BrowserHomeSurfaceKind
  ): BrowserHomeSurfaceScene {
    if (input.showHomePage) {
      return surfaceKind === 'system_native' ? 'system_home' : 'third_party_home';
    }
    if (input.webPageVisible) {
      return 'web_page';
    }
    return 'hidden';
  }

  private resolveRenderer(surfaceKind: BrowserHomeSurfaceKind): BrowserHomeSurfaceRenderer {
    if (surfaceKind === 'system_native') {
      return 'native_home';
    }
    if (this.isWebHomeSurfaceKind(surfaceKind)) {
      return 'web_home';
    }
    return 'fallback';
  }

  private resolveForegroundBackdropSource(
    surfaceKind: BrowserHomeSurfaceKind,
    customHomepageWebVisible: boolean
  ): BrowserHomeForegroundBackdropSource {
    if (surfaceKind === 'system_native') {
      return 'system_home';
    }
    if (this.isWebHomeSurfaceKind(surfaceKind) && customHomepageWebVisible) {
      return 'web_home';
    }
    return 'theme';
  }

  private isWebHomeSurfaceKind(surfaceKind: BrowserHomeSurfaceKind): boolean {
    return surfaceKind === 'imported_web_home' || surfaceKind === 'remote_web_home';
  }

  private resolveBottomSearchVisible(
    scene: BrowserHomeSurfaceScene,
    customHomepageState: CustomHomepagePresentationState
  ): boolean {
    if (scene === 'system_home') {
      return customHomepageState.showSystemSearchBar;
    }
    if (scene === 'third_party_home') {
      return customHomepageState.showSystemSearchBar;
    }
    return false;
  }

  private resolveSystemEntryButtonVisible(
    scene: BrowserHomeSurfaceScene,
    input: BrowserHomeSurfaceProfileInput
  ): boolean {
    return scene === 'third_party_home' &&
      input.customHomepageWebVisible &&
      input.customHomepageState.showSystemEntryButton;
  }

}
