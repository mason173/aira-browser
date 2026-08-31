import { BrowserHomeSurfaceProfile } from './BrowserHomeSurfaceProfileViewModel';
import { BrowserRecentlyClosedTabRecord } from './BrowserRecentlyClosedTabsService';
import { BrowserTabsOverlayAnimationViewModel } from './BrowserTabsOverlayAnimationViewModel';
import { CustomHomepagePresentationState } from '../customhome/CustomHomepagePresentationViewModel';

export interface BrowserHomePagePresentationInput {
  showHomePage: boolean;
  tabsOverviewSceneBackgroundVisible: boolean;
  sceneHitTestEnabled: boolean;
  homeRevealFromTabsProgress: number;
  homeRevealFromTabsInteractionBlocked: boolean;
  startupEntranceState: BrowserHomeStartupEntranceVisualState;
}

export interface BrowserHomePagePresentationState {
  scale: number;
  searchBackdropScale: number;
  opacity: number;
  hitTestEnabled: boolean;
}

export interface BrowserHomeStartupEntranceVisualState {
  opacity: number;
  scale: number;
  hitTestBlocked: boolean;
}

export interface BrowserHomeContentEntrancePresentationState {
  opacity: number;
  offsetY: number;
}

export interface BrowserHomeSurfaceContentPresentationInput {
  entranceProgress: number;
}

export interface BrowserHomeSurfaceContentPresentationState {
  entranceState: BrowserHomeContentEntrancePresentationState;
  contentOpacity: number;
  contentOffsetY: number;
}

export interface BrowserHomeRecentlyClosedSectionRefreshInput {
  showHomePage: boolean;
  recentlyClosedExpanded: boolean;
  sectionMounted: boolean;
  previousRecords: BrowserRecentlyClosedTabRecord[];
  nextRecords: BrowserRecentlyClosedTabRecord[];
  displayLimit: number;
}

const HOME_CONTENT_ENTRANCE_DURATION_MS: number = 160;
const HOME_CONTENT_ENTRANCE_DELAY_MS: number = 0;
const HOME_CONTENT_ENTRANCE_OFFSET_Y: number = 10;
const HOME_CONTENT_ENTRANCE_INITIAL_OPACITY: number = 0.72;
const HOME_CONTENT_ENTRANCE_CURVE: string = 'cubic-bezier(0.2, 0, 0, 1)';
const THIRD_PARTY_HOME_STARTUP_INITIAL_SCALE: number = 0.9;
const THIRD_PARTY_HOME_STARTUP_ENTRANCE_DELAY_MS: number = 0;
const THIRD_PARTY_HOME_STARTUP_ENTRANCE_DURATION_MS: number = 400;
const THIRD_PARTY_HOME_STARTUP_ENTRANCE_CURVE: string = 'cubic-bezier(0.2, 0, 0, 1)';
const SYSTEM_HOME_STARTUP_ENTRANCE_DELAY_MS: number = 140;

export class BrowserHomePresentationViewModel {
  private tabsOverlayAnimationViewModel: BrowserTabsOverlayAnimationViewModel =
    new BrowserTabsOverlayAnimationViewModel();

  buildPageState(input: BrowserHomePagePresentationInput): BrowserHomePagePresentationState {
    const revealProgress = this.clampProgress(input.homeRevealFromTabsProgress);
    return {
      scale: this.tabsOverlayAnimationViewModel.resolveHomeRevealScale(revealProgress) *
        input.startupEntranceState.scale,
      searchBackdropScale: 1,
      opacity: this.resolvePageOpacity(input, revealProgress),
      hitTestEnabled: input.sceneHitTestEnabled &&
        !input.homeRevealFromTabsInteractionBlocked &&
        !input.startupEntranceState.hitTestBlocked
    };
  }

  buildStartupEntranceVisualState(
    progress: number,
    initialScale: number = 1
  ): BrowserHomeStartupEntranceVisualState {
    const clamped = this.clampProgress(progress);
    const clampedInitialScale = Math.max(0, Math.min(1, initialScale));
    return {
      opacity: clamped,
      scale: clampedInitialScale + (1 - clampedInitialScale) * clamped,
      hitTestBlocked: clamped < 1
    };
  }

  resolveStartupEntranceInitialScale(thirdPartyHomepageActive: boolean): number {
    return thirdPartyHomepageActive ? THIRD_PARTY_HOME_STARTUP_INITIAL_SCALE : 1;
  }

  getStartupEntranceDelayMs(thirdPartyHomepageActive: boolean): number {
    return thirdPartyHomepageActive ?
      THIRD_PARTY_HOME_STARTUP_ENTRANCE_DELAY_MS :
      SYSTEM_HOME_STARTUP_ENTRANCE_DELAY_MS;
  }

  getStartupEntranceDurationMs(thirdPartyHomepageActive: boolean): number {
    return thirdPartyHomepageActive ?
      THIRD_PARTY_HOME_STARTUP_ENTRANCE_DURATION_MS :
      this.getRevealDurationMs();
  }

  getStartupEntranceCurve(thirdPartyHomepageActive: boolean): Curve | string {
    return thirdPartyHomepageActive ?
      THIRD_PARTY_HOME_STARTUP_ENTRANCE_CURVE :
      this.getRevealCurve();
  }

  buildContentEntranceState(progress: number): BrowserHomeContentEntrancePresentationState {
    const safeProgress = this.clampProgress(progress);
    return {
      opacity: HOME_CONTENT_ENTRANCE_INITIAL_OPACITY +
        (1 - HOME_CONTENT_ENTRANCE_INITIAL_OPACITY) * safeProgress,
      offsetY: (1 - safeProgress) * HOME_CONTENT_ENTRANCE_OFFSET_Y
    };
  }

  buildSurfaceContentPresentationState(
    input: BrowserHomeSurfaceContentPresentationInput
  ): BrowserHomeSurfaceContentPresentationState {
    const entranceState = this.buildContentEntranceState(input.entranceProgress);
    return {
      entranceState,
      contentOpacity: entranceState.opacity,
      contentOffsetY: entranceState.offsetY
    };
  }

  getContentEntranceDurationMs(): number {
    return HOME_CONTENT_ENTRANCE_DURATION_MS;
  }

  getContentEntranceDelayMs(): number {
    return HOME_CONTENT_ENTRANCE_DELAY_MS;
  }

  getContentEntranceCurve(): string {
    return HOME_CONTENT_ENTRANCE_CURVE;
  }

  getRevealDurationMs(): number {
    return this.tabsOverlayAnimationViewModel.getHomeRevealDurationMs();
  }

  getRevealCurve(): Curve | string {
    return this.tabsOverlayAnimationViewModel.getHomeRevealCurve();
  }

  shouldMountHomePage(showHomePage: boolean, customHomepageState: CustomHomepagePresentationState): boolean {
    return showHomePage || this.shouldKeepCustomHomepageWebResident(customHomepageState);
  }

  shouldKeepCustomHomepageWebResident(customHomepageState: CustomHomepagePresentationState): boolean {
    return this.shouldRenderCustomHtmlHomepage(customHomepageState);
  }

  shouldRenderCustomHtmlHomepage(customHomepageState: CustomHomepagePresentationState): boolean {
    return customHomepageState.shouldRenderCustomHtml;
  }

  shouldShowCustomHomepageUnavailableSurface(customHomepageState: CustomHomepagePresentationState): boolean {
    return customHomepageState.kind === 'custom_unavailable';
  }

  shouldUseSystemHomepageWallpaperBackdrop(profile: BrowserHomeSurfaceProfile): boolean {
    return profile.wallpaperMode === 'system_wallpaper';
  }

  shouldRemountRecentlyClosedSection(input: BrowserHomeRecentlyClosedSectionRefreshInput): boolean {
    if (!input.showHomePage || !input.recentlyClosedExpanded || !input.sectionMounted) {
      return false;
    }
    const previousKeys = this.buildRecentlyClosedDisplayKeys(input.previousRecords, input.displayLimit);
    const nextKeys = this.buildRecentlyClosedDisplayKeys(input.nextRecords, input.displayLimit);
    if (previousKeys.length !== nextKeys.length) {
      return true;
    }
    for (let index = 0; index < previousKeys.length; index += 1) {
      if (previousKeys[index] !== nextKeys[index]) {
        return true;
      }
    }
    return false;
  }

  private buildRecentlyClosedDisplayKeys(records: BrowserRecentlyClosedTabRecord[], displayLimit: number): string[] {
    const limit = Math.max(0, Math.floor(displayLimit));
    if (limit <= 0) {
      return [];
    }
    return records
      .slice()
      .sort((left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord): number => {
        if (right.closedAt !== left.closedAt) {
          return right.closedAt - left.closedAt;
        }
        return right.id.localeCompare(left.id);
      })
      .slice(0, limit)
      .map((record: BrowserRecentlyClosedTabRecord): string => this.buildRecentlyClosedDisplayKey(record));
  }

  private buildRecentlyClosedDisplayKey(record: BrowserRecentlyClosedTabRecord): string {
    return [
      record.id,
      `${record.closedAt}`,
      record.tab.title,
      record.tab.url,
      record.tab.lastGoodUrl,
      record.tab.pendingUrl
    ].join('\n');
  }

  private clampProgress(progress: number): number {
    return Math.max(0, Math.min(1, progress));
  }

  private resolvePageOpacity(input: BrowserHomePagePresentationInput, revealProgress: number): number {
    if (!input.showHomePage && !input.tabsOverviewSceneBackgroundVisible) {
      return 0;
    }
    return revealProgress * input.startupEntranceState.opacity;
  }
}
