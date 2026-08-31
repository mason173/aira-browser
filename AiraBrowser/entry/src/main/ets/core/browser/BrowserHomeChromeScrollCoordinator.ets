import { BrowserBottomToolbarScrollBehavior } from '../../common/models/BrowserModels';
import { CustomHomepagePresentationState } from '../customhome/CustomHomepagePresentationViewModel';
import {
  BrowserBottomChromeHomeScrollDecision,
  BrowserBottomChromePresentationScrollInput,
  BrowserBottomChromeScrollCoordinator,
  BrowserBottomChromeScrollPresentation
} from './BrowserBottomChromeScrollCoordinator';
import { BrowserHomeSurfaceProfile } from './BrowserHomeSurfaceProfileViewModel';
import { HomeSearchPanelDetent } from './HomeSearchPanelDetentViewModel';

const NATIVE_HOME_END_BOUNCE_ESCAPE_DELTA_PX: number = 12;

export type BrowserHomeChromeScrollMode = 'inactive' | 'fixed' | 'compact' | 'hidden';

export interface BrowserHomeChromeInteractionInput {
  showTabsSheet: boolean;
  addressFocused: boolean;
  currentDetent: HomeSearchPanelDetent;
  documentViewerActive: boolean;
  webVideoControllerActive: boolean;
  webAppImmersiveMode: boolean;
  fullScreenModeEnabled: boolean;
}

export interface BrowserHomeChromeScrollContext {
  profile: BrowserHomeSurfaceProfile;
  customHomepageState: CustomHomepagePresentationState;
  interaction: BrowserHomeChromeInteractionInput;
  currentPresentation: BrowserBottomChromeScrollPresentation;
  scrollBehavior: BrowserBottomToolbarScrollBehavior;
}

export interface BrowserHomeChromeScrollEvent {
  type: 'move' | 'stop';
  source: string;
  scrollOffsetY?: number;
  nativeAtEnd?: boolean;
}

export class BrowserHomeChromeScrollCoordinator {
  private nativeHomeEndBounceActive: boolean = false;
  private nativeHomeEndBounceOffsetY: number = 0;
  private lastDetent: HomeSearchPanelDetent | undefined = undefined;
  private lastMode: BrowserHomeChromeScrollMode = 'inactive';
  private bottomChromeScrollCoordinator: BrowserBottomChromeScrollCoordinator;

  constructor(bottomChromeScrollCoordinator: BrowserBottomChromeScrollCoordinator =
    new BrowserBottomChromeScrollCoordinator()) {
    this.bottomChromeScrollCoordinator = bottomChromeScrollCoordinator;
  }

  resolvePolicyMode(
    profile: BrowserHomeSurfaceProfile,
    customHomepageState: CustomHomepagePresentationState,
    scrollBehavior: BrowserBottomToolbarScrollBehavior
  ): BrowserHomeChromeScrollMode {
    if (!profile.bottomSearchVisible) {
      return 'inactive';
    }
    if (profile.scene === 'system_home') {
      return scrollBehavior;
    }
    if (profile.scene === 'third_party_home') {
      return customHomepageState.hideToolbarOnScroll ? scrollBehavior : 'fixed';
    }
    return 'inactive';
  }

  handleScrollEvent(
    context: BrowserHomeChromeScrollContext,
    event: BrowserHomeChromeScrollEvent,
    now: number = Date.now()
  ): BrowserBottomChromeHomeScrollDecision | undefined {
    if (event.type === 'stop') {
      this.finishNativeHomeScroll();
      return undefined;
    }
    const scrollOffsetY = this.resolveScrollOffset(event);
    if (scrollOffsetY === undefined) {
      return undefined;
    }
    const mode = this.resolvePolicyMode(
      context.profile,
      context.customHomepageState,
      context.scrollBehavior
    );
    const sourceId = this.resolveSurfaceId(event.source);
    const scrollInput = this.buildScrollInput(context, sourceId, scrollOffsetY, mode);
    if (!this.shouldProcessScroll(context.interaction, mode)) {
      this.bottomChromeScrollCoordinator.reset(sourceId, scrollOffsetY);
      this.lastDetent = context.interaction.currentDetent;
      this.lastMode = mode;
      return undefined;
    }
    if (this.lastDetent !== context.interaction.currentDetent || this.lastMode !== mode) {
      this.bottomChromeScrollCoordinator.reset(sourceId, scrollOffsetY);
    }
    const decision = this.bottomChromeScrollCoordinator.handleHomeScroll(scrollInput, now);
    this.lastDetent = decision.detent;
    this.lastMode = mode;
    return decision;
  }

  finishNativeHomeScroll(): void {
    this.nativeHomeEndBounceActive = false;
    this.nativeHomeEndBounceOffsetY = 0;
  }

  reset(): void {
    this.finishNativeHomeScroll();
    this.lastDetent = undefined;
    this.lastMode = 'inactive';
    this.bottomChromeScrollCoordinator.reset();
  }

  private resolveScrollOffset(event: BrowserHomeChromeScrollEvent): number | undefined {
    const normalizedScrollOffsetY = Math.max(0, Math.round(event.scrollOffsetY ?? 0));
    if (event.source.trim() !== 'system') {
      return normalizedScrollOffsetY;
    }
    const isAtEnd = event.nativeAtEnd === true;
    if (this.nativeHomeEndBounceActive) {
      if (isAtEnd || this.nativeHomeEndBounceOffsetY - normalizedScrollOffsetY <
        NATIVE_HOME_END_BOUNCE_ESCAPE_DELTA_PX) {
        return undefined;
      }
      this.nativeHomeEndBounceActive = false;
      this.nativeHomeEndBounceOffsetY = 0;
      return normalizedScrollOffsetY;
    }
    if (isAtEnd) {
      this.nativeHomeEndBounceActive = true;
      this.nativeHomeEndBounceOffsetY = normalizedScrollOffsetY;
      return undefined;
    }
    return normalizedScrollOffsetY;
  }

  private resolveSurfaceId(source: string): string {
    const normalizedSource = source.trim();
    return `home-${normalizedSource.length > 0 ? normalizedSource : 'content'}`;
  }

  private buildScrollInput(
    context: BrowserHomeChromeScrollContext,
    surfaceId: string,
    scrollOffsetY: number,
    mode: BrowserHomeChromeScrollMode
  ): BrowserBottomChromePresentationScrollInput {
    const presentationChangeAllowed = mode === 'compact' || mode === 'hidden';
    return {
      surfaceId: surfaceId,
      scrollOffsetY: scrollOffsetY,
      surfaceVisible: mode !== 'inactive',
      addressFocused: context.interaction.addressFocused,
      currentDetent: context.interaction.currentDetent,
      currentPresentation: context.currentPresentation,
      presentationChangeAllowed: presentationChangeAllowed,
      showTabsSheet: context.interaction.showTabsSheet,
      scrollBehavior: presentationChangeAllowed ? mode : 'fixed'
    };
  }

  private shouldProcessScroll(
    input: BrowserHomeChromeInteractionInput,
    mode: BrowserHomeChromeScrollMode
  ): boolean {
    return mode !== 'inactive' &&
      !input.showTabsSheet &&
      !input.addressFocused &&
      (input.currentDetent === 'low' || input.currentDetent === 'peek') &&
      !input.documentViewerActive &&
      !input.webVideoControllerActive &&
      !input.webAppImmersiveMode &&
      !input.fullScreenModeEnabled;
  }
}
