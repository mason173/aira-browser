import { FrameCallback } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { SiteIconView } from '../common/SiteIconView';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { BrowserTabPreviewState } from '../../../core/browser/BrowserTabPreviewCoordinator';
import {
  BrowserTabOverviewIdentityPresentation,
  BrowserTabOverviewItemPresentation,
  BrowserTabsOverviewIdentityIconSnapshot,
  BrowserTabsOverlayRect,
  BrowserTabsOverlayViewModel
} from '../../../core/browser/BrowserTabsOverlayViewModel';
import {
  BrowserTabsOverviewLayoutState,
  BrowserTabsOverviewLayoutViewModel,
  isSameTabsOverviewLayoutState
} from '../../../core/browser/BrowserTabsOverviewLayoutViewModel';
import {
  BrowserTabsOverviewIdentityMotionState,
  BrowserTabsOverlayAnimationViewModel
} from '../../../core/browser/BrowserTabsOverlayAnimationViewModel';
import {
  BrowserTabsSharedSnapshotTransitionCoordinator,
  BrowserTabsSharedSnapshotTransitionState
} from '../../../core/browser/BrowserTabsSharedSnapshotTransitionCoordinator';
import { BrowserTabState } from '../../../core/tabs/TabManager';
import {
  BrowserTabsOverviewLocalRemovalState,
  BrowserTabsOverviewShadowViewModel
} from '../../../core/browser/BrowserTabsOverviewShadowViewModel';
import { BrowserTabsOverviewSection, BrowserTabsOverviewSectionPolicy } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { sharedBrowserTabsOverviewThumbnailStore } from '../../../core/browser/tabsOverview/BrowserTabsOverviewThumbnailStore';
import { BrowserTabOverviewCardSelectRect } from './BrowserTabOverviewCard';
import { BrowserTabOverviewItem } from './BrowserTabOverviewItem';
import { BrowserTabOverviewListRow } from './BrowserTabOverviewListRow';
import { BrowserTabsSharedSnapshotOverlay } from './BrowserTabsSharedSnapshotOverlay';
import {
  BrowserTabsOverviewBottomChrome,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT
} from './BrowserTabsOverviewBottomChrome';
import { BrowserTabsOverviewSegmentGuide } from './BrowserTabsOverviewSegmentGuide';
import { BrowserTabsOverviewEmptyState } from './BrowserTabsOverviewEmptyState';
import { BrowserCrossDeviceTabsSheet } from './BrowserCrossDeviceTabsOverlay';
import { CrossDeviceTabsEmptyAction } from '../../../core/deviceTabs/CrossDeviceTabsEmptyPresentation';
import {
  BrowserTabsOverviewBottomChromeState,
  BrowserTabsOverviewBottomChromeViewModel
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewBottomChromeViewModel';
import {
  BrowserTabsOverviewSwipeFeedbackService
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSwipeFeedbackService';
import { advanceTabsOverviewSegmentGuide, tabsOverviewSegmentGuideBackGate } from '../../../core/onboarding/TabsOverviewSegmentGuidePolicy';
import { sharedTabsOverviewSegmentGuideRepository } from '../../bootstrap/BrowserAppRuntime';
import {
  BrowserTabsOverviewSwipeDismissPolicy
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSwipeDismissPolicy';
import { BrowserTabsOverviewStackMotion } from '../../../core/browser/tabsOverview/BrowserTabsOverviewStackMotion';
import {
  BrowserTabsOverviewStackCardMetrics,
  BrowserTabsOverviewStackLayoutPolicy
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewStackLayoutPolicy';
import {
  BrowserTabsOverviewStyleEntryPolicy,
  BrowserTabsOverviewStyleEntryProfile
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewStyleEntryPolicy';
import {
  BrowserTabsOverviewSelectionDisplacement,
  BrowserTabsOverviewSelectionDisplacementCoordinator
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSelectionDisplacementCoordinator';
import {
  BrowserTabsFloatingEntryTargetCoordinator,
  BrowserTabsFloatingEntryTargetPreparationState,
  BrowserTabsFloatingEntryTargetRectInput,
  BrowserTabsFloatingEntryTargetRecordedRectResult,
  BrowserTabsFloatingEntryTargetReadyAttemptResult,
  BrowserTabsFloatingEntryTargetResolvedRectResult
} from '../../../core/browser/tabsOverview/BrowserTabsFloatingEntryTargetCoordinator';
import {
  BROWSER_TABS_OVERVIEW_IDENTITY_HORIZONTAL_INSET,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_SIZE,
  BROWSER_TABS_OVERVIEW_IDENTITY_ICON_TEXT_GAP,
  BROWSER_TABS_OVERVIEW_LIST_ROW_CORNER_RADIUS
} from '../../../core/browser/BrowserTabsOverviewVisualTokens';
import {
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY,
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import { BROWSER_CONTENT_FONT_SIZE_SCALE_STORAGE_KEY } from '../../../core/browser/BrowserSystemFontScaleCoordinator';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { SiteIconListRenderState } from '../../../core/siteicons/SiteIconListPresenter';
import { browserSheetHeaderBlurModifier, resolveBrowserSheetHeaderBlurRadius } from './BrowserModalBottomSheet';

const FLOATING_TABS_HORIZONTAL_PADDING: number = 16;
const FLOATING_TABS_TOP_PADDING: number = 28;
// Cards dissolve into the top edge instead of being cut off by it, the same way the
// settings pages and the bookmark/history lists do. The stops are shared by every tab
// layout so a card fades out identically whichever deck the user is in. The band is
// deliberately shorter than the list surfaces': this page's top chrome is only the corner
// button, so a full-height fade was blurring rows the user was still reading.
const FLOATING_TABS_TOP_BLUR_STOPS: Array<[number, number]> = [[1, 0], [1, 0.033], [0, 0.093], [0, 1]];
const FLOATING_TABS_GRID_GAP: number = 16;
const FLOATING_TABS_EXIT_DURATION_MS: number = 280;
const FLOATING_TABS_CLOSE_ALL_COMMIT_DELAY_MS: number = 32;
const FLOATING_TABS_BOTTOM_POSITION_DELAY_MS: number = 0;
const FLOATING_TABS_ENTRY_START_DELAY_MS: number = 32;
const FLOATING_TABS_REORDER_DURATION_MS: number = 360;
const FLOATING_TABS_ENTRY_TARGET_READY_DELAY_MS: number = 0;
const FLOATING_TABS_ENTRY_TARGET_READY_RETRY_MS: number = 16;
const FLOATING_TABS_ENTRY_TARGET_READY_MAX_ATTEMPTS: number = 24;
const FLOATING_TABS_CARDS_Z_INDEX: number = 10;
// Above the shared-snapshot layer (340) so a flattened shrink cannot paint through
// the cards stacked in front of the one that is settling.
const FLOATING_TABS_DECK_FRONT_CARD_Z_INDEX: number = 400;
const FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX: number = 20;
const FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX: number = 25;
const FLOATING_TABS_BOTTOM_CHROME_Z_INDEX: number = 31;
const FLOATING_TABS_SEGMENT_GUIDE_Z_INDEX: number = 500;
const FLOATING_TABS_CROSS_DEVICE_LAYER_Z_INDEX: number = 30;
const HORIZONTAL_DECK_DRAG_START_DISTANCE: number = 6;

class BrowserTabsStackFrameCallback extends FrameCallback {
  private readonly task: (timeInNano: number) => void;

  constructor(task: (timeInNano: number) => void) {
    super();
    this.task = task;
  }

  onFrame(timeInNano: number): void {
    this.task(timeInNano);
  }
}

interface BrowserTabsFloatingItem {
  id: string;
  tab: BrowserTabState;
  presentation: BrowserTabOverviewItemPresentation;
  index: number;
}

interface BrowserTabsFloatingContentPadding {
  top: number;
  bottom: number;
}

interface BrowserTabsListStackMetrics {
  itemHeight: number;
  gap: number;
  spacer: number;
  viewportHeight: number;
  maxScroll: number;
  contentTop: number;
}

@Component
export struct BrowserTabsFloatingOverlay {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY)
  @Watch('handleStoredTabsOverviewLayoutStyleChanged')
  private storedTabsOverviewLayoutStyle: string = 'grid';
  @StorageProp(BROWSER_CONTENT_FONT_SIZE_SCALE_STORAGE_KEY)
  @Watch('handleSystemFontScaleChanged')
  private storedContentFontSizeScale: number = 1;
  @StorageProp(BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY)
  private storedTabsOverviewCloseButtonAlwaysVisible: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';

  @Watch('handleTabsChanged')
  @Prop tabs: BrowserTabState[] = [];
  @Watch('refreshDeckPresentation')
  @Prop previewStates: BrowserTabPreviewState[] = [];
  @Prop activeTabId: string = '';
  @Watch('syncSelectedSectionFromProps')
  @Prop activeSection: BrowserTabsOverviewSection = 'tabs';
  @Prop morphCoveredTabId: string = '';
  @Prop selectionDisplacementTabId: string = '';
  @Watch('syncEntryDisplacementFromProps')
  @Prop entryDisplacementTabId: string = '';
  @Watch('syncEntryDisplacementFromProps')
  @Prop entryDisplacementSettlingEnabled: boolean = false;
  @Watch('handleDeckInteractionChanged')
  @Prop interactionEnabled: boolean = true;
  @Prop sideEntryAnimationEnabled: boolean = true;
  @Prop viewportLeft: number = 0;
  @Prop viewportTop: number = 0;
  @Prop viewportWidth: number = 390;
  @Prop viewportHeight: number = 844;
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomChromeLiftVp: number = 0;
  @Prop backdropBlurRadius: number = 0;
  @Prop backgroundTintEnabled: boolean = true;
  @Prop backgroundSurfaceOpacity: number = -1;
  @Prop layerOpacity: number = 1;
  @Prop homeExitProgress: number = 0;
  @Watch('handleDeckInteractionChanged')
  @Prop exiting: boolean = false;
  @Watch('refreshDeckPresentation')
  @Prop blurPrivateTabPreviews: boolean = true;
  @Prop panelPageBackgroundColor: ResourceColor | undefined = undefined;
  @Prop panelSecondaryTextColor: ResourceColor | undefined = undefined;
  @Prop regularChromeIconTone: AppChromeIconTone = 'light';
  @Watch('startCloseAllTabsAnimationFromRequest')
  @Prop closeAllTabsAnimationRequestVersion: number = 0;
  @Watch('armListEntryCrossfade')
  @Prop entrySharedSnapshotMounted: boolean = false;
  @Watch('armListEntryCrossfade')
  @Prop entrySharedSnapshotState: BrowserTabsSharedSnapshotTransitionState =
    new BrowserTabsSharedSnapshotTransitionCoordinator().buildIdleState();
  @Prop entrySharedSnapshotBackgroundColor: ResourceColor | undefined = undefined;
  // Incremented by the page every time the sheet is opened. While the overlay is
  // resident (mounted but closed) it never re-runs aboutToAppear, so the per-open
  // setup has to be replayed from this signal.
  @Watch('handleOpenRequested')
  @Prop openRequestVersion: number = 0;

  @State private selectedSection: BrowserTabsOverviewSection = 'tabs';
  @State private layoutState: BrowserTabsOverviewLayoutState =
    new BrowserTabsOverviewLayoutViewModel().buildState({
      gridWidth: 0,
      sheetWidth: 360,
      sheetHeight: 844,
      layoutStyle: 'grid'
    });
  @State private entryProgress: number = 0;
  @State private listEntrySnapshotOpacity: number = 1;
  @State private listEntryChromeOpacity: number = 1;
  @State private listEntryFrameOpacity: number = 1;
  @State private listEntryChromeRevealStarted: boolean = false;
  @State private listEntrySurfaceOpacity: number = 0;
  @State private listEntrySurfaceFadeStarted: boolean = false;
  @State private listEntryFrameScale: number = 1;
  @State private listEntryImageBlur: number = 0;
  @State private listEntrySnapshotSuppressed: boolean = false;
  private listEntrySnapshotReleaseTimer: number = 0;
  @State private removalState: BrowserTabsOverviewLocalRemovalState =
    new BrowserTabsOverviewShadowViewModel().buildInitialLocalRemovalState();
  @State private lateMountEntryAnimationEnabled: boolean = false;
  @State private entryDisplacementProgress: number = 1;
  @State private closeAllExitActive: boolean = false;
  @Watch('refreshDeckPresentation')
  @State private siteIconStates: SiteIconListRenderState[] = [];
  @State private chromeMounted: boolean = false;
  @State private segmentGuidePending: boolean = false;
  @State private segmentGuideStep: number = 0;
  @State private bottomChromeRegularTabCount: number = 0;
  /**
   * Continuous deck position, in card units: 2 means the third card is focused, 2.4 means 40% of
   * the way to the fourth.
   *
   * Every card's place in the deck is derived from it, so it has to stay continuous. Snapping it
   * to whole cards would make the whole deck jump each time the finger crossed a midpoint.
   */
  @State private horizontalDeckPosition: number = 0;
  @State private deckItems: BrowserTabsFloatingItem[] = [];
  @State private deckSwipeTabId: string = '';  @State private deckDismissGhostTabId: string = '';
  /**
   * Each card's slot in the deck, keyed by tab id.
   *
   * A card must never read its slot from the `ForEach` item. `ForEach` reuses a node whose key is
   * unchanged without running the item builder again, so the item captured by that card's builder
   * keeps the index it had when the node was created. Reading the slot from a list the card does
   * observe is what lets a removal move the surviving cards at all.
   */
  @State private deckSlotIndexById: Record<string, number> = {};

  private scroller: Scroller = new Scroller();
  @State private headerBlurRadius: number = 0;
  private bottomScrollTimer: number = 0;
  private entryAnimationTimer: number = 0;
  private lateMountEntryAnimationTimer: number = 0;
  private closeAllCommitTimer: number = 0;
  private entryTargetReadyTimer: number = 0;
  private chromeMountTimer: number = 0;
  private entryDisplacementTargetId: string = '';
  private listEntryCrossfadeTabId: string = '';
  private listEntryCrossfadeVersion: number = 0;
  private listEntryCrossfadeTimer: number = 0;
  private entryReturnTabId: string = '';
  /**
   * The tab whose preview has already been composited under the entering morph.
   *
   * Grid and the strip paint that morph above the cards, and used to zero the covered preview
   * until the morph unmounted. The unmount frame then had no image — the card flashed. Once the
   * overlay is up the preview stays painted, including the frame where the overlay drops before
   * the covered-tab id clears.
   */
  private entryMorphPreviewLatchedTabId: string = '';
  /**
   * True only for the cold open, whose cards are mounted as the grid is first built and can
   * fly in as they appear. A resident re-open reuses an already-built grid, so it enters
   * plainly: neither the coordinated fly-in nor a per-card mount fly-in runs there. Letting
   * either run on an already-laid-out grid made cards jump back from off-screen and settle,
   * which read as a jitter.
   */
  private isFirstOpenInFlight: boolean = true;
  private handledCloseAllRequestVersion: number = 0;
  private entryTargetPreparationState: BrowserTabsFloatingEntryTargetPreparationState =
    new BrowserTabsFloatingEntryTargetCoordinator().buildIdleState();
  private layoutViewModel: BrowserTabsOverviewLayoutViewModel = new BrowserTabsOverviewLayoutViewModel();
  private shadowViewModel: BrowserTabsOverviewShadowViewModel = new BrowserTabsOverviewShadowViewModel();
  private overlayViewModel: BrowserTabsOverlayViewModel = new BrowserTabsOverlayViewModel();
  private animationViewModel: BrowserTabsOverlayAnimationViewModel = new BrowserTabsOverlayAnimationViewModel();
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();
  private swipeDismissPolicy: BrowserTabsOverviewSwipeDismissPolicy =
    new BrowserTabsOverviewSwipeDismissPolicy();
  private styleEntryPolicy: BrowserTabsOverviewStyleEntryPolicy =
    new BrowserTabsOverviewStyleEntryPolicy();
  private stackLayoutPolicy: BrowserTabsOverviewStackLayoutPolicy =
    new BrowserTabsOverviewStackLayoutPolicy();
  private deckMotion: BrowserTabsOverviewStackMotion = new BrowserTabsOverviewStackMotion();
  private deckDragActive: boolean = false;
  /**
   * The tab whose dismissal is mid fill-in, if any.
   *
   * This has to be observed state, not a plain field: the deck's touch handling reads it (see
   * `canInteractWithDeck`), and a plain field would leave the cards layer holding whatever
   * `HitTestMode` it rendered last. A dismissal that clears a field the framework cannot see would
   * therefore leave the deck unwatchable — the fill-in lands, and then nothing can be dragged again
   * until the whole overview is closed and reopened.
   */
  @State private pendingDeckDismissTabId: string = '';
  private pendingDeckDismissPosition: number = -1;
  private deckDismissCommitTimer: number = 0;
  /**
   * Whether the deck has been placed on a card for the current entry.
   *
   * `layoutStyle` only resolves to `horizontal_cards` after the first `onAreaChange`, which can run
   * after `initializeForOpen`. Without this latch the deck would be left at card zero whenever the
   * window measured late.
   */
  private deckPositionSeeded: boolean = false;
  private deckMetricsCacheKey: string = '';
  private deckMetricsCache: BrowserTabsOverviewStackCardMetrics[] = [];
  /**
   * Identity of the current item list, refreshed only when the list is rebuilt.
   *
   * The memo below caches metrics by card slot, so the key has to change when a card leaves or
   * shifts: two decks of the same length can hold different tabs at the same slot.
   */
  private deckItemsSignature: string = '';
  /** Order of the recorded slots, so an unchanged list does not replace the map every frame. */
  private deckSlotSignature: string = '';
  private selectionDisplacementCoordinator: BrowserTabsOverviewSelectionDisplacementCoordinator =
    new BrowserTabsOverviewSelectionDisplacementCoordinator();
  private entryTargetCoordinator: BrowserTabsFloatingEntryTargetCoordinator =
    new BrowserTabsFloatingEntryTargetCoordinator();
  private bottomChromeViewModel: BrowserTabsOverviewBottomChromeViewModel =
    new BrowserTabsOverviewBottomChromeViewModel();
  onDismiss: () => void = () => {};
  onCreateTab: () => void = () => {};
  onRequestCloseAll: () => void = () => {};
  onCloseAllAnimationFinished: () => void = () => {};
  onSwitchSectionHome: (section: BrowserTabsOverviewSection) => void = (_section: BrowserTabsOverviewSection) => {};
  onActiveSectionChange: (section: BrowserTabsOverviewSection) => void = (_section: BrowserTabsOverviewSection) => {};
  onSelectTab: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => void =
    (_tabId: string, _rect?: BrowserTabOverviewCardSelectRect) => {};
  onCloseTab: (tabId: string) => void = (_tabId: string) => {};
  onPreviewRectChange: (
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ) => void = (_tabId: string, _left: number, _top: number, _width: number, _height: number) => {};
  onEntryTargetPreviewRectReady: (
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ) => void = (_tabId: string, _left: number, _top: number, _width: number, _height: number) => {};
  onEntrySharedSnapshotRectChange: (rect: BrowserTabsOverlayRect) => void = (_rect: BrowserTabsOverlayRect) => {};
  onEntrySharedSnapshotTap: (tabId: string) => void = (_tabId: string) => {};
  onOpenDeviceTabs: () => void = () => {};
  onOpenRemoteTab: (url: string, title: string) => void = (_url: string, _title: string) => {};
  onCrossDeviceNavigate: (action: CrossDeviceTabsEmptyAction) => boolean =
    (_action: CrossDeviceTabsEmptyAction): boolean => false;
  @Prop crossDeviceDataScope: string = 'profile_persistent';
  @Prop crossDevicePrivacyMode: string = 'regular';

  aboutToAppear(): void {
    // Subscribe once for the lifetime of the component; the identity-icon binding is
    // not per-open, and re-binding it on every open would stack subscriptions.
    this.overlayViewModel.bindIdentityIconUpdates(
      (): BrowserTabsOverviewIdentityIconSnapshot => this.buildIdentityIconSnapshot(),
      (states: SiteIconListRenderState[]): void => {
        this.siteIconStates = states;
      }
    );
    this.initializeForOpen();
    // HDS segmented tabs, the blurred material bar and the corner buttons add a large
    // native subtree on top of the grid. Mount them on the next frame so the first
    // frame stays cheap: it blocks the main thread, so this timer only runs once the
    // grid has been laid out. Only the first open defers them; later opens reuse them.
    this.chromeMountTimer = setTimeout(() => {
      this.chromeMountTimer = 0;
      this.chromeMounted = true;
      this.syncSegmentGuidePresence();
    }, 0);
  }

  private handleOpenRequested(): void {
    // A resident re-open reuses the built grid, so it enters plainly: no coordinated
    // fly-in and no per-card mount fly-in.
    this.isFirstOpenInFlight = false;
    this.initializeForOpen();
  }

  /**
   * Per-open setup. Runs from aboutToAppear on the first open and from
   * openRequestVersion on every later open, because a resident overlay does not
   * remount and therefore never re-enters aboutToAppear.
   */
  private initializeForOpen(): void {
    this.commitPendingDeckDismiss();
    this.stopDeckMotion();
    this.deckPositionSeeded = false;
    this.selectedSection = this.activeSection;
    this.entryReturnTabId = this.activeTabId.trim();
    // A close-all leaves this latched true. It used to be cleared by the remount;
    // a resident overlay must clear it here or every later open stays non-interactive.
    this.closeAllExitActive = false;
    this.segmentGuideStep = 0;
    void this.refreshSegmentGuidePending();
    this.syncLayoutState();
    // A cold open starts at 0 so its freshly mounted cards fly in; a resident re-open starts
    // settled so an already-built grid enters plainly instead of jumping back and settling.
    this.entryProgress = this.isFirstOpenInFlight ? this.resolveEntryInitialProgress() : 1;
    this.entryDisplacementTargetId = this.entryDisplacementTabId.trim();
    this.entryDisplacementProgress = this.resolveEntryDisplacementInitialProgress();
    this.entryTargetPreparationState =
      this.entryTargetCoordinator.clearPreviewRectCache(this.entryTargetPreparationState);
    this.resetEntryTargetPreparation();
    this.beginEntryTargetPreparationIfNeeded();
    this.removalState = this.shadowViewModel.buildInitialLocalRemovalState();
    this.ensureDeckPositionForCurrentSection();
    this.syncEntryDisplacementFromProps();
    this.armListEntryCrossfade();
    this.prepareBottomEntryAnimation();
    this.refreshBottomChromeCounts();
    // Resolve identity icons before the grid is first built. The grid is keyed by tab
    // id, so a later @State update would not repaint already-built cards and every
    // favicon would stay on its letter fallback.
    this.syncSiteIcons();
  }

  aboutToDisappear(): void {
    tabsOverviewSegmentGuideBackGate.setActive(false, () => {});
    this.commitPendingDeckDismiss();
    this.clearDeckDismissCommitTimer();
    this.stopDeckMotion();
    this.clearBottomScrollTimer();
    this.clearEntryAnimationTimer();
    this.clearLateMountEntryAnimationTimer();
    this.clearCloseAllCommitTimer();
    this.clearEntryTargetReadyTimer();
    this.finishListEntryCrossfade();
    this.clearListEntrySnapshotReleaseTimer();
    if (this.chromeMountTimer > 0) {
      clearTimeout(this.chromeMountTimer);
      this.chromeMountTimer = 0;
    }
    this.overlayViewModel.disposeIdentityIcons();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildBackgroundDismissLayer()

      if (this.isCrossDeviceSectionSelected()) {
        // The cross-device page owns the whole content area.
        this.buildCrossDeviceSectionLayer()
      } else {
        this.buildTabCollectionLayers()
      }

      // The entering morph is stacked inside the deck instead of above the cards layer, so the
      // cards that trail the covered one keep the slot they own at rest. The grid, the large card
      // strip and the exit back to the page all paint it from here. A stack entry that has not
      // found its slot yet must not fall back to this layer: that paints the shrink through the
      // cards in front of it.
      if (this.entrySharedSnapshotMounted && !this.shouldMountSharedSnapshotInDeck() &&
        !this.isStackEntryMorph()) {
        this.buildSharedSnapshotOverlay()
      }

      if (this.shouldShowListEntrySurface()) {
        this.buildListEntrySurface()
      }

      if (this.chromeMounted) {
        if (this.shouldPresentSegmentGuide()) {
          BrowserTabsOverviewSegmentGuide({
            stepIndex: this.segmentGuideStep,
            viewportWidth: this.resolveRootWidth(),
            viewportHeight: this.resolveRootHeight(),
            bottomChromeLiftVp: this.bottomChromeLiftVp,
            onAdvance: () => {
              this.advanceSegmentGuide();
            }
          })
          .zIndex(FLOATING_TABS_SEGMENT_GUIDE_Z_INDEX)
        }

        if (this.shouldShowBottomChrome()) {
          BrowserTabsOverviewBottomChrome({
            selectedSection: this.selectedSection,
            regularTabCount: this.bottomChromeRegularTabCount,
            regularTabsLabel: this.buildBottomChromeState().regularTabsLabel,
            viewportWidth: this.resolveRootWidth(),
            viewportHeight: this.resolveRootHeight(),
            bottomChromeLiftVp: this.bottomChromeLiftVp,
            surfaceOpacity: this.resolveBottomChromeOpacity(),
            chromeInteractionEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive,
            regularChromeIconTone: this.regularChromeIconTone,
            adaptiveForeground: true,
            onReturn: () => {
              this.returnToEntryTab();
            },
            onCreateHome: () => {
              this.onCreateTab();
            },
            onSwitchToTabs: () => {
              this.switchSection('tabs');
            },
            onSwitchToPrivacy: () => {
              this.switchSection('privacy');
            },
            onOpenDeviceTabs: () => {
              this.onOpenDeviceTabs();
            },
            onCloseAll: () => {
              this.onRequestCloseAll();
            }
          })
          .zIndex(FLOATING_TABS_BOTTOM_CHROME_Z_INDEX)
        }
      }
    }
    .width(this.resolveRootWidth())
    .height(this.resolveRootHeight())
    .opacity(this.resolveLayerOpacity())
    .onVisibleAreaChange([0], (visible: boolean) => {
      if (visible) {
        // Becoming visible again must not expose a deck frozen between two cards.
        this.settleDeckToNearestCard();
      } else {
        this.stopDeckMotion();
      }
    })
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .onAreaChange((_oldArea: Area, _newArea: Area) => {
      this.syncLayoutState();
      this.syncLocalRemovalStateFromTabs();
    })
  }

  @Builder
  private buildBackgroundDismissLayer() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePanelPageBackgroundColor())
      .opacity(this.resolveBackgroundTintOpacity())
      .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
        HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.interactionEnabled && !this.closeAllExitActive) {
          this.onDismiss();
        }
      })
      .zIndex(0)
  }

  @Builder
  private buildEmptyStateLayer() {
    Column() {
      BrowserTabsOverviewEmptyState({
        selectedSection: this.selectedSection,
        textColor: this.resolvePanelSecondaryTextColor()
      })
        .opacity(0.82 * this.resolveSurfaceProgress())
    }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding({
        left: FLOATING_TABS_HORIZONTAL_PADDING,
        right: FLOATING_TABS_HORIZONTAL_PADDING,
        top: this.resolveContentTopPadding(),
        bottom: this.resolveContentBottomPadding()
      })
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
        HitTestMode.Default : HitTestMode.None)
      .onClick(() => {
        if (this.interactionEnabled && !this.closeAllExitActive) {
          this.onDismiss();
        }
      })
      .zIndex(20)
  }

  @Builder
  private buildEmptyDismissLayer() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .hitTestBehavior(this.shouldAllowEmptyDismiss() ? HitTestMode.Block : HitTestMode.None)
      .onClick(() => {
        if (this.shouldAllowEmptyDismiss()) {
          this.onDismiss();
        }
      })
      .zIndex(25)
  }

  @Builder
  private buildSharedSnapshotOverlay(inDeck: boolean = false) {
    // List clip fade is a different node from the card shrink. Sharing one builder is what let
    // the list opacity isolate the card morph and paint the thumbnail over the still-shrinking page.
    if (!inDeck && this.resolvePaintedStyleEntryProfile().fadesCoveringSnapshot) {
      this.buildListClipSnapshotOverlay()
    } else {
      this.buildCoveringSnapshotOverlay(inDeck)
    }
  }

  @Builder
  private buildCoveringSnapshotOverlay(inDeck: boolean) {
    BrowserTabsSharedSnapshotOverlay({
      state: this.entrySharedSnapshotState,
      imagePixelMap: this.entrySharedSnapshotState.imagePixelMap,
      snapshotBackgroundColor: this.entrySharedSnapshotBackgroundColor,
      // Inside the deck the slot wrapper already owns stacking. Passing the overlay-root
      // 20/25 here would let the morph compete with every card if ArkUI flattens z-index.
      snapshotLayerZIndex: inDeck ? 0 : FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX,
      snapshotDecorationLayerZIndex: inDeck ? 0 : FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX,
      viewportLeft: this.resolveRootLeft(),
      viewportTop: this.resolveRootTop(),
      onSnapshotRectChange: (rect: BrowserTabsOverlayRect) => {
        this.onEntrySharedSnapshotRectChange(rect);
      },
      onSnapshotTap: (tabId: string) => {
        this.onEntrySharedSnapshotTap(tabId);
      },
      imageBlurExtra: 0
    })
    .zIndex(inDeck ? 0 : FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX)
  }

  @Builder
  private buildListClipSnapshotOverlay() {
    BrowserTabsSharedSnapshotOverlay({
      state: this.entrySharedSnapshotState,
      imagePixelMap: this.entrySharedSnapshotState.imagePixelMap,
      snapshotBackgroundColor: this.entrySharedSnapshotBackgroundColor,
      snapshotLayerZIndex: FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX,
      snapshotDecorationLayerZIndex: FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX,
      viewportLeft: this.resolveRootLeft(),
      viewportTop: this.resolveRootTop(),
      onSnapshotRectChange: (rect: BrowserTabsOverlayRect) => {
        this.onEntrySharedSnapshotRectChange(rect);
      },
      onSnapshotTap: (tabId: string) => {
        this.onEntrySharedSnapshotTap(tabId);
      },
      imageBlurExtra: this.listEntryImageBlur
    })
    // Opacity isolates this node. The z-index has to sit on the same node, or the row paints
    // over the page while the window is still cropping down.
    .opacity(this.resolveListEntrySnapshotOpacity())
    .zIndex(FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX)
  }

  @Builder
  private buildListEntrySurface() {
    Row()
      .width(Math.max(1, this.entrySharedSnapshotState.targetRect.width))
      .height(Math.max(1, this.entrySharedSnapshotState.targetRect.height))
      .position({
        x: this.entrySharedSnapshotState.targetRect.left,
        y: this.entrySharedSnapshotState.targetRect.top
      })
      .borderRadius(BROWSER_TABS_OVERVIEW_LIST_ROW_CORNER_RADIUS)
      .backgroundColor(this.storedFloatingSurfaceColor)
      .opacity(this.resolveListEntrySurfaceOpacity())
      .hitTestBehavior(HitTestMode.None)
      .zIndex(FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX + 1)
  }

  private shouldShowListEntrySurface(): boolean {
    if (!this.resolvePaintedStyleEntryProfile().paintsEntrySurface ||
      this.exiting || this.closeAllExitActive) {
      return false;
    }
    const state = this.entrySharedSnapshotState;
    return this.entrySharedSnapshotMounted &&
      state.direction === 'enter' &&
      state.phase !== 'idle' &&
      state.phase !== 'settled' &&
      state.targetRect.width > 0 &&
      state.targetRect.height > 0;
  }

  private resolveListEntrySurfaceOpacity(): number {
    if (!this.listEntrySurfaceFadeStarted && !this.listEntryChromeRevealStarted) {
      return 0;
    }
    return this.listEntrySurfaceOpacity;
  }

  /**
   * The two tab collections share one content branch. It is a builder of its own because an
   * `else` arm inside the overlay's `Stack` may hold exactly one component call.
   */
  @Builder
  private buildTabCollectionLayers() {
    if (this.isSelectedSectionEmpty()) {
      this.buildEmptyStateLayer()
      this.buildEmptyDismissLayer()
    }

    this.buildCardsLayer()
  }

  /**
   * The cross-device page owns the whole content area and is never driven by the local tab
   * count: it lists tabs that live on other installations, so "no local tabs" must not
   * turn it into the ordinary empty state.
   */
  @Builder
  private buildCrossDeviceSectionLayer() {
    BrowserCrossDeviceTabsSheet({
      // The page must clear the status bar and the floating bottom chrome, and both of those
      // are this surface's own live geometry. The component only draws the list, so the
      // insets come from here instead of a constant baked into it.
      contentTopInset: this.resolveCrossDeviceContentTopInset(),
      contentBottomInset: this.resolveCrossDeviceContentBottomInset(),
      dataScope: this.crossDeviceDataScope,
      privacyMode: this.crossDevicePrivacyMode,
      onNavigate: (action: CrossDeviceTabsEmptyAction): boolean => this.onCrossDeviceNavigate(action),
      onOpenRemoteTab: (url: string, title: string): void => {
        this.onOpenRemoteTab(url, title);
      }
    })
      .width('100%')
      .height('100%')
      .opacity(this.resolveSurfaceProgress())
      .attributeModifier(browserSheetHeaderBlurModifier(this.headerBlurRadius, FLOATING_TABS_TOP_BLUR_STOPS))
      .hitTestBehavior((this.interactionEnabled && !this.exiting && !this.closeAllExitActive) ?
        HitTestMode.Default : HitTestMode.None)
      .zIndex(FLOATING_TABS_CROSS_DEVICE_LAYER_Z_INDEX)
  }

  /**
   * The cross-device page is inset like the tab grids: the status bar plus the same breathing
   * room the cards use, never less than the cards' own top padding.
   */
  private resolveCrossDeviceContentTopInset(): number {
    return this.resolveContentTopPadding();
  }

  /**
   * The bottom inset has to be the whole chrome zone, not the cards' content gap: the last
   * remote tab must come to rest above the floating bar instead of behind it.
   */
  private resolveCrossDeviceContentBottomInset(): number {
    return this.resolveContentBottomPadding();
  }

  @Builder
  private buildCardsLayer() {
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      this.buildHorizontalCardsLayer()
    } else if (this.layoutState.layoutStyle === 'stack') {
      this.buildStackCardsLayer()
    } else if (this.layoutState.layoutStyle === 'list') {
      this.buildListLayer()
    } else {
      this.buildGridCardsLayer()
    }
  }

  @Builder
  private buildGridCardsLayer() {
    Grid(this.scroller) {
      ForEach(this.resolveVisibleItems(), (item: BrowserTabsFloatingItem) => {
        GridItem() {
          this.buildCard(item)
        }
        .height(this.layoutState.itemHeight)
      }, (item: BrowserTabsFloatingItem) => this.resolveCardIdentityKey(item))

      ForEach(this.buildBlankSlotKeys(), (_key: string) => {
        this.buildBlankGridItem()
      }, (key: string) => key)
    }
    .width('100%')
    .height('100%')
    .columnsTemplate(this.layoutState.columnsTemplate)
    .columnsGap(FLOATING_TABS_GRID_GAP)
    .rowsGap(FLOATING_TABS_GRID_GAP)
    .cachedCount(8)
    .padding({
      left: FLOATING_TABS_HORIZONTAL_PADDING,
      right: FLOATING_TABS_HORIZONTAL_PADDING,
      top: this.resolveContentTopPadding(),
      bottom: this.resolveContentBottomPadding()
    })
    .attributeModifier(browserSheetHeaderBlurModifier(this.headerBlurRadius, FLOATING_TABS_TOP_BLUR_STOPS))
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll(() => {
      this.headerBlurRadius = resolveBrowserSheetHeaderBlurRadius(this.scroller.currentOffset().yOffset);
    })
    .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
      HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
  }

  /**
   * The large centred card strip.
   *
   * One card per page in a horizontal `List` that snaps to the centre, so a sideways swipe moves to
   * the next page instead of to the next row of a grid. Every card uses the one box the layout state
   * derived from the viewport. A screenshot's pixel size is a capture artifact and must not resize
   * that box, or the page just opened sits lower than its neighbours.
   */
  @Builder
  private buildHorizontalCardsLayer() {
    List({
      space: this.layoutState.gridGap,
      scroller: this.scroller
    }) {
      ForEach(this.resolveVisibleItems(), (item: BrowserTabsFloatingItem) => {
        ListItem() {
          Stack({ alignContent: Alignment.Center }) {
            this.buildCard(item)
          }
          .width('100%')
          .height('100%')
          .padding({
            top: this.resolveHorizontalContentPadding().top,
            bottom: this.resolveHorizontalContentPadding().bottom
          })
          .clip(false)
        }
        .width(this.layoutState.cardWidth)
        .height(this.resolveRootHeight())
        .clip(false)
      }, (item: BrowserTabsFloatingItem) => this.resolveCardIdentityKey(item))
    }
    .width('100%')
    .height('100%')
    .listDirection(Axis.Horizontal)
    .alignListItem(ListItemAlign.Center)
    .scrollSnapAlign(ScrollSnapAlign.CENTER)
    .contentStartOffset(this.resolveHorizontalEdgeInset(true))
    .contentEndOffset(this.resolveHorizontalEdgeInset(false))
    .cachedCount(8)
    .padding({
      left: FLOATING_TABS_HORIZONTAL_PADDING,
      right: FLOATING_TABS_HORIZONTAL_PADDING
    })
    .attributeModifier(browserSheetHeaderBlurModifier(this.headerBlurRadius, FLOATING_TABS_TOP_BLUR_STOPS))
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
      HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
  }

  // Each tab has one render node. Fixed index order matches StackSwipe, so a trailing card
  // covers a leading one throughout the drag; no layer swaps at rounded-index boundaries.
  //
  // Card slots are doubled so the entering morph can hold a slot of its own strictly between the
  // covered card and its successor, instead of being one more layer painted above the whole deck.
  @Builder
  private buildStackCardsLayer() {
    Stack({ alignContent: Alignment.Center }) {
      ForEach(this.resolveDeckItems(), (item: BrowserTabsFloatingItem) => {
        this.buildDeckCard(item)
      }, (item: BrowserTabsFloatingItem) => this.resolveCardIdentityKey(item))

      this.buildDeckEntryMorphSlot()
    }
    .width('100%')
    .height('100%')
    .padding({
      top: this.resolveHorizontalContentPadding().top,
      bottom: this.resolveHorizontalContentPadding().bottom
    })
    // Clip stays on for ordinary deck motion so peeking cards don't paint past the sheet. It drops
    // only while a card is in a vertical dismiss flight, otherwise the fly-out is cut at the stack
    // edge and reads as an instant vanish.
    .clip(this.deckSwipeTabId.length <= 0)
    .attributeModifier(browserSheetHeaderBlurModifier(this.headerBlurRadius, FLOATING_TABS_TOP_BLUR_STOPS))
    .hitTestBehavior(this.canInteractWithDeck() ? HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
    .gesture(
      PanGesture({ direction: PanDirection.Horizontal,
        distance: HORIZONTAL_DECK_DRAG_START_DISTANCE })
        .onActionStart(() => {
          this.beginDeckDrag();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.updateDeckDrag(event.offsetX);
        })
        .onActionEnd((event: GestureEvent) => {
          this.endDeckDrag(event.velocityX);
        })
        .onActionCancel(() => {
          this.cancelDeckDrag();
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildDeckCard(item: BrowserTabsFloatingItem) {
    Stack({ alignContent: Alignment.Center }) {
      this.buildCard(item)
    }
    .width(this.layoutState.cardWidth)
    .height(this.resolveItemHeight())
    .translate({
      x: this.resolveDeckMetrics(item).offsetX,
      y: this.resolveDeckMetrics(item).offsetY
    })
    .scale({ x: this.resolveDeckMetrics(item).scale, y: this.resolveDeckMetrics(item).scale })
    .opacity(item.id === this.deckDismissGhostTabId ? 0 : this.resolveDeckMetrics(item).opacity)
    .zIndex(this.resolveDeckCardLayerZIndex(item))
    .hitTestBehavior(this.resolveDeckMetrics(item).opacity > 0 && item.id !== this.deckDismissGhostTabId ?
      HitTestMode.Default : HitTestMode.None)
  }

  /**
   * Draw order by slot, doubled so the entering morph owns the odd slot between two cards.
   *
   * The card that is leaving takes the top slot: it is on its way out over the cards that are
   * closing the gap behind it, and it must not trade places with them mid-flight.
   */
  private resolveDeckCardLayerZIndex(item: BrowserTabsFloatingItem): number {
    if (item.id === this.deckDismissGhostTabId) {
      return (this.deckItems.length + 1) * 2;
    }
    const slot = this.resolveDeckIndex(item);
    // The shrinking picture can flatten above the deck. Cards in front of the covered
    // card have to stay above that picture, or it shows through the right neighbour.
    const morphSlot = this.resolveDeckEntryMorphSlot();
    if (morphSlot >= 0 && slot > morphSlot) {
      return FLOATING_TABS_DECK_FRONT_CARD_Z_INDEX + slot;
    }
    return slot * 2;
  }

  /**
   * The slot the entering morph plays in while it settles into the covered card.
   *
   * It is held to the covered card's own stacking slot, one level under the cards that trail it, so
   * those cards stay in front of the snapshot for the whole entry and the handover has nothing left
   * to reorder. The holder stays mounted even while it is empty: changing the deck's child list
   * mid-entry would re-run the deck layout and re-measure every card beside the morph.
   */
  @Builder
  private buildDeckEntryMorphSlot() {
    Stack() {
      if (this.shouldMountSharedSnapshotInDeck()) {
        this.buildSharedSnapshotOverlay(true)
      }
    }
    .width('100%')
    .height(this.resolveRootHeight())
    // `position()` resolves against the parent's content box, so the holder is pulled back out of
    // the deck's vertical padding and the morph keeps addressing root coordinates.
    .position({ x: 0, y: -this.resolveHorizontalContentPadding().top })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(this.resolveDeckEntryMorphLayerZIndex())
  }

  @Builder
  private buildBlankGridItem() {
    GridItem() {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .onClick(() => {
          if (this.interactionEnabled && !this.closeAllExitActive) {
            this.onDismiss();
          }
        })
    }
    .height(this.layoutState.itemHeight)
  }

  /**
   * The icon-and-title list.
   *
   * Each row is the tab: the site icon and title on the left, the close button on the right. It
   * shares the grid's scroller so opening still lands on the current tab, and it does not borrow
   * the card swipe — a vertical list already owns that gesture for scrolling.
   *
   * Top and bottom insets are content offsets, not padding. A List clips to its content box by
   * default, so padding cut every row off at the status-bar line and the top blur never saw them.
   * The viewport stays full height, rows can scroll to the top, and the same gradient blur the
   * cards use fades them as they pass under the status bar.
   *
   * Rows stack upward: the most recently used tab is the bottom row, and a short list sits on
   * the bottom instead of the top. Older rows are what you reach by scrolling up.
   */
  @Builder
  private buildListLayer() {
    List({
      space: this.layoutState.gridGap,
      scroller: this.scroller
    }) {
      ForEach(this.resolveListItems(), (item: BrowserTabsFloatingItem, index: number) => {
        ListItem() {
          BrowserTabOverviewListRow({
            tab: item.tab,
            presentation: item.presentation,
            active: item.tab.id === this.activeTabId,
            rowEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive &&
              !this.isSelectionDisplacementActive() && !this.isEntryDisplacementActive() &&
              !this.isMorphCoveredTab(item.tab.id),
            rowHeight: this.layoutState.itemHeight,
            rowTranslateX: this.resolveCardTranslateX(item),
            rowOpacity: this.resolveCardOpacity(item),
            motionDurationMs: this.resolveCardMotionDurationMs(),
            motionCurve: this.resolveCardMotionCurve(),
            motionDelayMs: this.resolveCardMotionDelayMs(item.index),
            onSelect: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => {
              this.selectOverviewTab(tabId, rect);
            },
            onCloseTab: (tabId: string) => {
              this.closeTabFromOverlay(tabId);
            },
            onPreviewRectChange: (tabId: string, left: number, top: number, width: number, height: number) => {
              this.handlePreviewRectChange(tabId, left, top, width, height);
            },
            contentOpacity: this.resolveListRowContentOpacity(item.tab.id),
            frameOpacity: this.resolveListRowFrameOpacity(item.tab.id),
            frameScale: this.resolveListRowFrameScale(item.tab.id)
          })
        }
        .width('100%')
        .height(this.layoutState.itemHeight)
        .margin({ top: index === 0 ? this.resolveListStackMetrics().spacer : 0 })
        .clip(false)
      }, (item: BrowserTabsFloatingItem) => this.resolveCardIdentityKey(item))
    }
    .width('100%')
    .height('100%')
    .cachedCount(8)
    .padding({
      left: FLOATING_TABS_HORIZONTAL_PADDING,
      right: FLOATING_TABS_HORIZONTAL_PADDING
    })
    .contentStartOffset(this.resolveContentTopPadding())
    .contentEndOffset(this.resolveContentBottomPadding())
    .clipContent(ContentClipMode.BOUNDARY)
    .attributeModifier(browserSheetHeaderBlurModifier(this.headerBlurRadius, FLOATING_TABS_TOP_BLUR_STOPS))
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .onDidScroll(() => {
      this.headerBlurRadius = resolveBrowserSheetHeaderBlurRadius(this.scroller.currentOffset().yOffset);
    })
    .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
      HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
  }

  private resolveCardSnapshotImageUri(item: BrowserTabsFloatingItem): string {
    const previewUri = item.presentation.preview.sharedSnapshotImageUri.trim();
    if (previewUri.length > 0) {
      return previewUri;
    }
    return sharedBrowserTabsOverviewThumbnailStore.getThumbnail(item.tab.id)?.imageUri?.trim() ?? '';
  }

  private resolveCardSnapshotPixelMap(_item: BrowserTabsFloatingItem): image.PixelMap | undefined {
    return undefined;
  }

  @Builder
  private buildCard(item: BrowserTabsFloatingItem) {
    BrowserTabOverviewItem({
      tab: item.tab,
      presentation: item.presentation,
      snapshotImageUri: this.resolveCardSnapshotImageUri(item),
      snapshotPixelMap: this.resolveCardSnapshotPixelMap(item),
      snapshotAspectFitEnabled: false,
      snapshotCoverEnabled: this.isStackLayout() || this.isHorizontalCardsLayout(),
      deckShadeOpacity: this.isStackLayout() ? this.resolveDeckMetrics(item).shadeOpacity : 0,
      previewHeight: this.layoutState.previewHeight,
      cardWidth: this.layoutState.cardWidth,
      identityHeaderHeight: this.layoutState.identityHeaderHeight,
      identityPreviewGap: this.layoutState.identityPreviewGap,
      tabTranslateX: this.resolveCardTranslateX(item),
      tabTranslateY: this.resolveCardTranslateY(item),
      tabScale: this.resolveCardScale(item),
      tabOpacity: this.resolveCardOpacity(item),
      identityOpacity: this.resolveIdentityMotion(item).opacity *
        (this.isStackLayout() ? this.resolveDeckMetrics(item).titleOpacity : 1),
      identityTranslateY: this.resolveIdentityMotion(item).translateY,
      previewCardOpacity: 1,
      snapshotImageOpacity: 1,
      decorationOpacity: 1,
      coveredByMorph: this.shouldHideCardSurfaceUnderMorph(item.tab.id),
      tabEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive &&
        !this.isSelectionDisplacementActive() && !this.isEntryDisplacementActive() &&
        !this.isMorphCoveredTab(item.tab.id),
      trackPreviewRectChanges: true,
      motionDurationMs: this.resolveCardMotionDurationMs(),
      motionCurve: this.resolveCardMotionCurve(),
      motionDelayMs: this.resolveCardMotionDelayMs(this.resolveDeckIndex(item)),
      entryMountAnimationEnabled: this.shouldRunLateMountEntryAnimation(item),
      entryMountOffsetX: this.resolveLateMountEntryOffsetX(item),
      entryMountDurationMs: this.animationViewModel.getFloatingCardEntryDurationMs(),
      entryMountCurve: this.animationViewModel.getFloatingCardEntryCurve(),
      entryMountDelayMs: this.resolveCardMotionDelayMs(this.resolveDeckIndex(item)),
      swipeDismissThreshold: this.resolveSwipeDismissThreshold(),
      swipeFlyoutOffset: this.usesUpwardCardDismiss() ? this.resolveRootHeight() : this.resolveRootWidth(),
      swipeDismissMode: this.usesUpwardCardDismiss() ? 'upward' : 'horizontal',
      closeButtonEnabled: true,
      closeButtonAlwaysVisible: this.storedTabsOverviewCloseButtonAlwaysVisible,
      onCloseTab: (tabId: string) => {
        this.closeTabFromOverlay(tabId);
      },
      onSwipeStart: (tabId: string) => {
        if (this.isStackLayout()) {
          // The card's vertical gesture claimed the touch, so the deck's horizontal one is over.
          this.abortDeckMotion();
          this.deckSwipeTabId = tabId;
        }
      },
      onSwipeCancel: (_tabId: string) => {
        this.deckSwipeTabId = '';
      },
      onSwipeEnd: (tabId: string, _offsetX: number, _direction: number) => {
        this.deckSwipeTabId = '';
        this.closeTabFromOverlay(tabId);
      },
      onSwipeThresholdReached: (_tabId: string) => {
        this.performSwipeThresholdFeedback();
      },
      onSelect: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => {
        this.selectOverviewTab(tabId, rect);
      },
      onPreviewRectChange: (tabId: string, left: number, top: number, width: number, height: number) => {
        this.handlePreviewRectChange(tabId, left, top, width, height);
      }
    })
    .width(this.layoutState.cardWidth)
    .height(this.layoutState.itemHeight)
  }

  /**
   * Whether a card is dismissed by flicking it upwards.
   *
   * The strip and the deck are both one card wide, so a sideways flick belongs to their own paging
   * and the dismiss gesture has to take the other axis. The grid has no paging, so it keeps the
   * sideways flick. The list has a close button and a vertical scroller, so it is not a card flick.
   */
  private usesUpwardCardDismiss(): boolean {
    return this.isStackLayout() || this.isHorizontalCardsLayout();
  }

  private startEntryAnimation(): void {
    this.clearEntryAnimationTimer();
    if (!this.sideEntryAnimationEnabled) {
      this.entryProgress = 1;
      return;
    }
    this.entryAnimationTimer = setTimeout(() => {
      this.entryAnimationTimer = 0;
      if (this.exiting) {
        return;
      }
      this.startLateMountEntryAnimationWindow();
      animateTo({
        duration: this.animationViewModel.getFloatingCardEntryDurationMs(),
        curve: this.animationViewModel.getFloatingCardEntryCurve()
      }, () => {
        this.entryProgress = 1;
      });
    }, FLOATING_TABS_ENTRY_START_DELAY_MS);
  }

  private prepareBottomEntryAnimation(): void {
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (this.exiting) {
        return;
      }
      this.positionCardsForCurrentSection();
      this.startEntryAnimation();
    }, FLOATING_TABS_BOTTOM_POSITION_DELAY_MS);
  }

  private prepareSectionSwitchPosition(): void {
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (this.exiting || this.closeAllExitActive) {
        return;
      }
      this.positionCardsForCurrentSection();
    }, FLOATING_TABS_BOTTOM_POSITION_DELAY_MS);
  }

  private positionCardsForCurrentSection(): void {
    if (this.shouldPrepareEntryTarget()) {
      this.scrollToEntryTargetForEntry();
      return;
    }
    this.scrollToBottomForEntry();
  }

  private scrollToEntryTargetForEntry(): void {
    this.beginEntryTargetPreparationIfNeeded();
    const targetTabId = this.resolveEntryTargetTabId();
    if (targetTabId.length <= 0) {
      this.resetEntryTargetPreparation();
      this.scrollToBottomForEntry();
      return;
    }
    const targetIndex = this.resolveDisplacementTargetIndex(targetTabId);
    if (targetIndex < 0) {
      this.resetEntryTargetPreparation();
      this.scrollToBottomForEntry();
      return;
    }
    this.entryTargetPreparationState = this.entryTargetCoordinator.discardPreviewRect(
      this.entryTargetPreparationState,
      targetTabId
    );
    this.entryTargetPreparationState = this.entryTargetCoordinator.markScrollIssued(
      this.entryTargetPreparationState,
      targetTabId,
      this.entryTargetCoordinator.resolveCurrentRectGeneration(this.entryTargetPreparationState)
    );
    if (this.isStackLayout()) {
      this.seedDeckPosition(targetIndex);
    } else if (this.isListLayout()) {
      this.scrollListToBottomAnchor(targetTabId);
    } else {
      this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.CENTER);
    }
    this.scheduleEntryTargetReady(targetTabId, 0, this.entryTargetPreparationState.version);
  }

  private scrollToBottomForEntry(): void {
    const lastItemIndex = this.resolveVisibleItems().length - 1;
    if (lastItemIndex < 0) {
      return;
    }
    if (this.isStackLayout()) {
      // The deck has no scroll position to restore, so opening on a tab means placing the deck on
      // that tab. When the active tab is not in the selected section there is nothing to centre
      // on, and the last card is the honest default.
      const activeTabIndex = this.resolveDisplacementTargetIndex(this.activeTabId);
      this.seedDeckPosition(activeTabIndex >= 0 ? activeTabIndex : lastItemIndex);
      return;
    }
    if (this.isListLayout()) {
      const items = this.resolveListItems();
      if (items.length > 0) {
        this.scrollListToBottomAnchor(items[items.length - 1].tab.id);
      }
      return;
    }
    if (this.isHorizontalCardsLayout()) {
      // The strip centres the active tab; without one the last card is the honest default.
      const activeTabIndex = this.resolveDisplacementTargetIndex(this.activeTabId);
      this.scroller.scrollToIndex(activeTabIndex >= 0 ? activeTabIndex : lastItemIndex, false,
        activeTabIndex >= 0 ? ScrollAlign.CENTER : ScrollAlign.END);
      return;
    }
    this.scroller.scrollToIndex(lastItemIndex, false, ScrollAlign.END);
  }

  private clearBottomScrollTimer(): void {
    if (this.bottomScrollTimer !== 0) {
      clearTimeout(this.bottomScrollTimer);
      this.bottomScrollTimer = 0;
    }
  }

  private clearEntryAnimationTimer(): void {
    if (this.entryAnimationTimer !== 0) {
      clearTimeout(this.entryAnimationTimer);
      this.entryAnimationTimer = 0;
    }
  }

  private clearEntryTargetReadyTimer(): void {
    if (this.entryTargetReadyTimer !== 0) {
      clearTimeout(this.entryTargetReadyTimer);
      this.entryTargetReadyTimer = 0;
    }
  }

  private startLateMountEntryAnimationWindow(): void {
    this.clearLateMountEntryAnimationTimer();
    this.lateMountEntryAnimationEnabled = true;
    this.lateMountEntryAnimationTimer = setTimeout(() => {
      this.lateMountEntryAnimationTimer = 0;
      this.lateMountEntryAnimationEnabled = false;
    }, this.resolveLateMountEntryAnimationWindowMs());
  }

  private clearLateMountEntryAnimationTimer(): void {
    if (this.lateMountEntryAnimationTimer !== 0) {
      clearTimeout(this.lateMountEntryAnimationTimer);
      this.lateMountEntryAnimationTimer = 0;
    }
    this.lateMountEntryAnimationEnabled = false;
  }

  private syncEntryDisplacementFromProps(): void {
    if (!this.isEntryDisplacementActive()) {
      this.entryDisplacementTargetId = '';
      this.entryDisplacementProgress = 1;
      this.resetEntryTargetPreparation();
      return;
    }
    const targetTabId = this.entryDisplacementTabId.trim();
    if (this.entryDisplacementTargetId !== targetTabId) {
      this.entryDisplacementTargetId = targetTabId;
      this.entryDisplacementProgress = 0;
      this.resetEntryTargetPreparation();
      this.beginEntryTargetPreparationIfNeeded();
      this.prepareBottomEntryAnimation();
    }
    if (!this.entryDisplacementSettlingEnabled) {
      // An in-flight value is the settle-watch race: settlingEnabled can drop one @Watch
      // before the tab id clears. Leave it alone. Anything else (including a leftover 1)
      // snaps to the origin; motion duration is 0 here, so this is not a visible fly-out.
      if (this.entryDisplacementProgress > 0 && this.entryDisplacementProgress < 1) {
        return;
      }
      this.entryDisplacementProgress = 0;
      return;
    }
    if (this.entryDisplacementProgress >= 1) {
      return;
    }
    animateTo({
      duration: this.animationViewModel.getSharedSnapshotEnterDurationMs(),
      curve: this.animationViewModel.getSharedSnapshotEnterCurve()
    }, () => {
      this.entryDisplacementProgress = 1;
    });
  }

  /**
   * Only the row the page is shrinking into holds its icon, title and close button.
   * The other rows stay readable for the whole open.
   */
  private resolveListRowContentOpacity(tabId: string): number {
    if (!this.shouldHoldListEntryChrome(tabId)) {
      return 1;
    }
    return this.listEntryChromeRevealStarted ? this.listEntryChromeOpacity : 0;
  }

  private resolveListRowFrameOpacity(tabId: string): number {
    if (!this.isCoveredListEntryRow(tabId) || this.exiting || this.closeAllExitActive) {
      return 1;
    }
    if (this.entrySharedSnapshotState.direction === 'exit') {
      return 1;
    }
    const state = this.entrySharedSnapshotState;
    if (state.phase === 'settled') {
      return 1;
    }
    if (!this.listEntrySurfaceFadeStarted) {
      return 0;
    }
    return this.listEntryFrameOpacity;
  }

  private isCoveredListEntryRow(tabId: string): boolean {
    return this.resolvePaintedStyleEntryProfile().fadesCoveringSnapshot &&
      (this.isMorphCoveredTab(tabId) || this.listEntryCrossfadeTabId === tabId);
  }

  /**
   * The covered row is hidden from the first open frame. Waiting for a timer left the icon and
   * title at full opacity for that click frame.
   */
  private shouldHoldListEntryChrome(tabId: string): boolean {
    if (!this.resolvePaintedStyleEntryProfile().fadesCoveringSnapshot ||
      this.exiting || this.closeAllExitActive) {
      return false;
    }
    if (this.listEntryCrossfadeTabId === tabId) {
      return true;
    }
    if (!this.isMorphCoveredTab(tabId)) {
      return false;
    }
    return this.entrySharedSnapshotState.direction !== 'exit';
  }

  private resolveListRowFrameScale(tabId: string): number {
    if (this.listEntryCrossfadeTabId.length === 0 || !this.isMorphCoveredTab(tabId)) {
      return 1;
    }
    return this.listEntryFrameScale;
  }

  /**
   * The page is the shrinking shape. The row is already complete underneath it, so the
   * only visible join is the picture fading away. Unmount must not restore that opacity.
   * A write during the geometry animateTo would be captured for the whole flight.
   */
  private armListEntryCrossfade(): void {
    if (!this.shouldArmListEntryCrossfade()) {
      this.finishListEntryCrossfade();
      return;
    }
    const tabId = this.resolveMorphCoveredTabId();
    if (this.listEntryCrossfadeTabId === tabId) {
      if (this.entrySharedSnapshotState.progress > 0) {
        this.scheduleListEntryCrossfade(this.listEntryCrossfadeVersion);
      }
      return;
    }
    this.listEntryCrossfadeVersion += 1;
    this.listEntryCrossfadeTabId = tabId;
    this.listEntryChromeRevealStarted = false;
    this.listEntrySurfaceFadeStarted = false;
    this.listEntryChromeOpacity = 0;
    this.listEntryFrameOpacity = 0;
    this.listEntrySurfaceOpacity = 0;
    this.clearListEntryCrossfadeTimer();
    const version = this.listEntryCrossfadeVersion;
    setTimeout(() => {
      if (version !== this.listEntryCrossfadeVersion) {
        return;
      }
      this.listEntrySnapshotSuppressed = false;
      this.listEntrySnapshotOpacity = 1;
      this.listEntryChromeRevealStarted = false;
      this.listEntryChromeOpacity = 0;
      this.listEntryFrameOpacity = 0;
      this.listEntrySurfaceOpacity = 0;
      this.listEntryFrameScale = 1;
      this.listEntryImageBlur = 0;
      this.listEntrySurfaceFadeStarted = true;
      animateTo({
        duration: this.animationViewModel.getListEntryDurationMs(),
        curve: this.animationViewModel.getListEntryCurve()
      }, () => {
        if (version !== this.listEntryCrossfadeVersion) {
          return;
        }
        this.listEntryFrameOpacity = 1;
        this.listEntrySurfaceOpacity = 1;
      });
      if (this.entrySharedSnapshotState.progress > 0) {
        this.scheduleListEntryCrossfade(version);
      }
    }, 0);
  }

  private shouldArmListEntryCrossfade(): boolean {
    if (!this.resolvePaintedStyleEntryProfile().fadesCoveringSnapshot ||
      this.exiting || this.closeAllExitActive) {
      return false;
    }
    const state = this.entrySharedSnapshotState;
    return this.entrySharedSnapshotMounted &&
      state.direction === 'enter' &&
      state.phase !== 'idle' &&
      state.phase !== 'settled' &&
      this.resolveMorphCoveredTabId().length > 0;
  }

  private scheduleListEntryCrossfade(version: number): void {
    if (this.listEntryCrossfadeTimer !== 0 || version !== this.listEntryCrossfadeVersion) {
      return;
    }
    const enterDuration = this.animationViewModel.getListEntryDurationMs();
    const delay = Math.round(enterDuration * this.animationViewModel.getListEntryCrossfadeStartProgress()) +
      this.animationViewModel.getListEntryChromeRevealDelayMs();
    // Wait until the window has finished shrinking onto the row, then fade the title in.
    const fadeDuration = this.animationViewModel.getListEntryDissolveDurationMs();
    this.listEntryCrossfadeTimer = setTimeout(() => {
      this.listEntryCrossfadeTimer = 0;
      if (version !== this.listEntryCrossfadeVersion || !this.shouldArmListEntryCrossfade()) {
        return;
      }
      this.listEntryFrameScale = 1;
      this.listEntrySurfaceOpacity = 1;
      this.listEntryChromeRevealStarted = true;
      this.listEntryChromeOpacity = 0;
      // The bar is already visible. Let the covering copy leave so the title can fade in on it.
      animateTo({
        duration: fadeDuration,
        curve: this.animationViewModel.getListEntryDissolveCurve()
      }, () => {
        if (version !== this.listEntryCrossfadeVersion) {
          return;
        }
        this.listEntryChromeOpacity = 1;
        this.listEntrySurfaceOpacity = 0;
        this.listEntrySnapshotOpacity = 0;
        this.holdListEntrySnapshotHidden(version);
      });
    }, delay);
  }

  private finishListEntryCrossfade(): void {
    if (this.listEntryCrossfadeTabId.length === 0 && this.listEntryCrossfadeTimer === 0) {
      return;
    }
    this.clearListEntryCrossfadeTimer();
    this.listEntryCrossfadeVersion += 1;
    this.listEntryCrossfadeTabId = '';
    // Stay transparent through unmount. Restoring 1 here flashes the page back on.
    this.listEntrySnapshotOpacity = 0;
    this.listEntryChromeOpacity = 1;
    this.listEntryFrameOpacity = 1;
    this.listEntryFrameScale = 1;
    this.listEntryImageBlur = 0;
    this.holdListEntrySnapshotHidden(this.listEntryCrossfadeVersion);
  }

  private holdListEntrySnapshotHidden(version: number): void {
    this.listEntrySnapshotSuppressed = true;
    this.clearListEntrySnapshotReleaseTimer();
    this.listEntrySnapshotReleaseTimer = setTimeout(() => {
      this.listEntrySnapshotReleaseTimer = 0;
      if (version !== this.listEntryCrossfadeVersion) {
        return;
      }
      const state = this.entrySharedSnapshotState;
      if (state.direction === 'enter' && state.phase !== 'idle' && state.phase !== 'settled') {
        return;
      }
      this.listEntrySnapshotSuppressed = false;
      this.listEntrySnapshotOpacity = 1;
    }, 96);
  }

  private clearListEntrySnapshotReleaseTimer(): void {
    if (this.listEntrySnapshotReleaseTimer === 0) {
      return;
    }
    clearTimeout(this.listEntrySnapshotReleaseTimer);
    this.listEntrySnapshotReleaseTimer = 0;
  }

  private resolveListEntrySnapshotOpacity(): number {
    // Only the list builder calls this. A card style must never reach it.
    if (!this.resolvePaintedStyleEntryProfile().fadesCoveringSnapshot) {
      return 1;
    }
    if (this.listEntrySnapshotSuppressed) {
      return 0;
    }
    if (this.entrySharedSnapshotState.direction === 'enter' &&
      this.entrySharedSnapshotState.phase !== 'idle') {
      return this.listEntrySnapshotOpacity;
    }
    return 1;
  }

  private clearListEntryCrossfadeTimer(): void {
    if (this.listEntryCrossfadeTimer === 0) {
      return;
    }
    clearTimeout(this.listEntryCrossfadeTimer);
    this.listEntryCrossfadeTimer = 0;
  }

  private switchSection(section: BrowserTabsOverviewSection): void {
    if (this.closeAllExitActive) {
      return;
    }
    if (this.selectedSection === section) {
      this.onSwitchSectionHome(section);
      return;
    }
    this.applySectionSelection(section);
    this.onActiveSectionChange(section);
  }

  /**
   * A section the shell selects on its own behalf — the cross-device page, after entitlement
   * and sign-in resolved — arrives as the `activeSection` prop. Adopt it without reporting it
   * back, or the two would answer each other forever.
   */
  private syncSelectedSectionFromProps(): void {
    const next = this.activeSection;
    if (next === this.selectedSection) {
      return;
    }
    this.applySectionSelection(next);
  }

  private applySectionSelection(section: BrowserTabsOverviewSection): void {
    this.stopDeckMotion();
    this.deckPositionSeeded = false;
    this.selectedSection = section;
    this.syncSiteIcons();
    this.clearEntryAnimationTimer();
    this.clearLateMountEntryAnimationTimer();
    this.entryProgress = 1;
    this.removalState = this.shadowViewModel.buildInitialLocalRemovalState();
    this.refreshDeckPresentation();
    this.positionCardsForCurrentSection();
    this.prepareSectionSwitchPosition();
    this.refreshBottomChromeCounts();
  }

  private returnToEntryTab(): void {
    const state = this.buildBottomChromeState();
    if (state.returnKind === 'tab' && state.returnTabId.length > 0) {
      this.selectOverviewTab(state.returnTabId);
      return;
    }
    this.onDismiss();
  }

  private buildBottomChromeState(): BrowserTabsOverviewBottomChromeState {
    return this.bottomChromeViewModel.buildState({
      tabs: this.tabs,
      locallyRemovedTabIds: this.removalState.locallyRemovedTabIds,
      entryTabId: this.entryReturnTabId,
      activeTabId: this.activeTabId
    });
  }

  private closeTabFromOverlay(tabId: string): void {
    if (!this.interactionEnabled || this.exiting || this.closeAllExitActive ||
      tabId.trim().length <= 0 || this.isLocallyRemovedTab(tabId)) {
      return;
    }
    if (this.isStackLayout()) {
      this.beginDeckDismiss(tabId);
      return;
    }
    animateTo({
      duration: FLOATING_TABS_REORDER_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardEntryCurve()
    }, () => {
      this.removalState = this.shadowViewModel.markLocalRemoval(this.removalState, tabId);
    });
    this.refreshBottomChromeCounts();
    this.onCloseTab(tabId);
  }

  private performSwipeThresholdFeedback(): void {
    BrowserTabsOverviewSwipeFeedbackService.performThresholdFeedback();
  }

  private startCloseAllTabsAnimationFromRequest(): void {
    const requestVersion = Math.max(0, Math.floor(this.closeAllTabsAnimationRequestVersion));
    if (requestVersion <= 0 || requestVersion === this.handledCloseAllRequestVersion) {
      return;
    }
    this.stopDeckMotion();
    this.handledCloseAllRequestVersion = requestVersion;
    const tabIds = this.resolveSelectedSectionVisibleTabIds();
    if (tabIds.length <= 0) {
      this.onCloseAllAnimationFinished();
      return;
    }
    animateTo({
      duration: FLOATING_TABS_EXIT_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardExitCurve(),
      onFinish: () => {
        if (this.handledCloseAllRequestVersion !== requestVersion) {
          return;
        }
        this.scheduleCloseAllCommit(requestVersion);
      }
    }, () => {
      this.closeAllExitActive = true;
      this.syncSegmentGuidePresence();
    });
  }

  private resolveSelectedSectionVisibleTabIds(): string[] {
    const visibleTabs = this.sectionPolicy.resolveTabsForSection(this.tabs, this.selectedSection);
    const tabIds: string[] = [];
    for (let index = 0; index < visibleTabs.length; index += 1) {
      const tabId = visibleTabs[index].id;
      if (!this.isLocallyRemovedTab(tabId)) {
        tabIds.push(tabId);
      }
    }
    return tabIds;
  }

  private isCrossDeviceSectionSelected(): boolean {
    return this.selectedSection === 'devices';
  }

  private isSelectedSectionEmpty(): boolean {
    if (this.isCrossDeviceSectionSelected()) {
      return false;
    }
    // The deck already holds its item list; rebuilding every presentation here would run on every
    // animation frame, because `horizontalDeckPosition` is a `@State` the deck writes each frame.
    if (this.isStackLayout()) {
      return this.deckItems.length <= 0;
    }
    return this.resolveVisibleItems().length <= 0;
  }

  private shouldAllowEmptyDismiss(): boolean {
    return !this.exiting && !this.closeAllExitActive;
  }

  private scheduleCloseAllCommit(requestVersion: number): void {
    this.clearCloseAllCommitTimer();
    this.closeAllCommitTimer = setTimeout(() => {
      this.closeAllCommitTimer = 0;
      if (this.handledCloseAllRequestVersion !== requestVersion) {
        return;
      }
      this.onCloseAllAnimationFinished();
    }, FLOATING_TABS_CLOSE_ALL_COMMIT_DELAY_MS);
  }

  private clearCloseAllCommitTimer(): void {
    if (this.closeAllCommitTimer === 0) {
      return;
    }
    clearTimeout(this.closeAllCommitTimer);
    this.closeAllCommitTimer = 0;
  }

  private resolveVisibleItems(): BrowserTabsFloatingItem[] {
    const previews = this.buildPreviewMap();
    const visibleTabs = this.sectionPolicy.resolveTabsForSection(this.tabs, this.selectedSection);
    const items: BrowserTabsFloatingItem[] = [];
    for (let index = 0; index < visibleTabs.length; index += 1) {
      const tab = visibleTabs[index];
      if (this.isLocallyRemovedTab(tab.id)) {
        continue;
      }
      items.push({
        id: tab.id,
        tab: tab,
        presentation: this.overlayViewModel.buildItemPresentation(
          tab,
          previews[tab.id],
          this.resolveSiteIconState(tab.id),
          this.blurPrivateTabPreviews
        ),
        index: items.length
      });
    }
    return items;
  }

  // The persisted URI must not be part of the card key. It arrives as the shrink
  // finishes, and a key that changed from the live frame to that file destroyed the
  // card in the handoff frame. A new file reaches the existing card through the
  // thumbnail store instead of by rebuilding it.
  private resolveCardIdentityKey(item: BrowserTabsFloatingItem): string {
    const preview = item.presentation.preview;
    const hasImage = preview.sharedSnapshotImageUri.trim().length > 0 ||
      preview.sharedSnapshotPixelMap !== undefined ||
      (sharedBrowserTabsOverviewThumbnailStore.getThumbnail(item.id)?.imageUri.trim().length ?? 0) > 0;
    return `${item.id}|${preview.previewKind}|${hasImage ? 'image' : 'none'}`;
  }

  private isLocallyRemovedTab(tabId: string): boolean {
    return this.shadowViewModel.isLocallyRemoved(this.removalState, tabId);
  }

  private syncLocalRemovalStateFromTabs(): void {
    this.removalState = this.shadowViewModel.reconcileLocalRemovalState(this.removalState, this.tabs);
  }

  private handleTabsChanged(): void {
    this.syncLocalRemovalStateFromTabs();
    this.refreshDeckPresentation();
    this.syncSiteIcons();
    this.refreshBottomChromeCounts();
  }

  private refreshBottomChromeCounts(): void {
    const state = this.buildBottomChromeState();
    if (state.regularTabCount !== this.bottomChromeRegularTabCount) {
      this.bottomChromeRegularTabCount = state.regularTabCount;
    }
  }

  private syncSiteIcons(): void {
    this.overlayViewModel.syncIdentityIcons(
      (): BrowserTabsOverviewIdentityIconSnapshot => this.buildIdentityIconSnapshot(),
      (states: SiteIconListRenderState[]): void => {
        this.siteIconStates = states;
      }
    );
  }

  private buildIdentityIconSnapshot(): BrowserTabsOverviewIdentityIconSnapshot {
    return {
      tabs: this.tabs,
      section: this.selectedSection,
      iconStates: this.siteIconStates
    };
  }

  private resolveSiteIconState(tabId: string): SiteIconListRenderState | undefined {
    return this.overlayViewModel.resolveIdentityIconState(this.siteIconStates, tabId);
  }

  private buildPreviewMap(): Record<string, BrowserTabPreviewState | undefined> {
    const previewByTabId: Record<string, BrowserTabPreviewState | undefined> = {};
    for (const state of this.previewStates) {
      if (state.tabId.trim().length <= 0) {
        continue;
      }
      previewByTabId[state.tabId] = state;
    }
    return previewByTabId;
  }

  private handlePreviewRectChange(tabId: string, left: number, top: number, width: number, height: number): void {
    // `onAreaChange` reports layout bounds, which ignore the deck's per-card translate and scale;
    // every deck card would report the same centred rectangle. The same geometry that paints the
    // card supplies the rect instead, so the entry morph and the remembered rect stay honest.
    let rect: BrowserTabsOverlayRect;
    const deckRect = this.isStackLayout() ? this.resolveDeckPreviewRect(tabId) : undefined;
    if (deckRect !== undefined) {
      rect = deckRect;
    } else {
      rect = { left: left, top: top, width: width, height: height };
    }
    const recordResult: BrowserTabsFloatingEntryTargetRecordedRectResult =
      this.entryTargetCoordinator.recordPreviewRect(this.entryTargetPreparationState, tabId, rect);
    this.entryTargetPreparationState = recordResult.state;
    if (recordResult.measuredResult.ready) {
      this.publishEntryTargetReady(tabId, recordResult.rect, recordResult.measuredResult);
      return;
    }
    if (recordResult.shouldDefer) {
      if (recordResult.shouldScheduleReady) {
        this.scheduleEntryTargetReady(tabId, 0, recordResult.state.version);
      }
      return;
    }
    this.onPreviewRectChange(tabId, left, top, width, height);
  }

  private scheduleEntryTargetReady(tabId: string, attempt: number, version: number): void {
    this.clearEntryTargetReadyTimer();
    const delayMs = attempt <= 0 ? FLOATING_TABS_ENTRY_TARGET_READY_DELAY_MS : FLOATING_TABS_ENTRY_TARGET_READY_RETRY_MS;
    this.entryTargetReadyTimer = setTimeout(() => {
      this.entryTargetReadyTimer = 0;
      this.publishEntryTargetReadyOrRetry(tabId, attempt, version);
    }, delayMs);
  }

  private publishEntryTargetReadyOrRetry(tabId: string, attempt: number, version: number): void {
    if (!this.shouldPrepareEntryTarget()) {
      return;
    }
    const attemptResult: BrowserTabsFloatingEntryTargetReadyAttemptResult =
      this.entryTargetCoordinator.resolveReadyAttempt({
        state: this.entryTargetPreparationState,
        tabId: tabId,
        version: version,
        targetTabId: this.resolveEntryTargetTabId(),
        predictedRect: this.buildPredictedEntryTargetPreviewRect(tabId),
        attempt: attempt,
        maxAttempts: FLOATING_TABS_ENTRY_TARGET_READY_MAX_ATTEMPTS
      });
    this.entryTargetPreparationState = attemptResult.state;
    if (attemptResult.action === 'publish' && attemptResult.rect !== undefined) {
      const resolvedResult: BrowserTabsFloatingEntryTargetResolvedRectResult = {
        state: attemptResult.state,
        ready: true
      };
      this.publishEntryTargetReady(tabId, attemptResult.rect, resolvedResult);
      return;
    }
    if (attemptResult.action === 'retry') {
      this.scheduleEntryTargetReady(tabId, attemptResult.nextAttempt, version);
    }
  }

  private publishEntryTargetReady(
    tabId: string,
    rect: BrowserTabsOverlayRect,
    result: BrowserTabsFloatingEntryTargetResolvedRectResult
  ): void {
    this.entryTargetPreparationState = result.state;
    this.clearEntryTargetReadyTimer();
    this.onPreviewRectChange(tabId, rect.left, rect.top, rect.width, rect.height);
    this.onEntryTargetPreviewRectReady(tabId, rect.left, rect.top, rect.width, rect.height);
  }

  private resetEntryTargetPreparation(): void {
    this.entryTargetPreparationState = this.entryTargetCoordinator.cancel(this.entryTargetPreparationState);
    this.clearEntryTargetReadyTimer();
  }

  private beginEntryTargetPreparationIfNeeded(): void {
    if (!this.shouldPrepareEntryTarget()) {
      return;
    }
    this.entryTargetPreparationState = this.entryTargetCoordinator.beginPreparation(
      this.entryTargetPreparationState,
      this.resolveEntryTargetTabId()
    );
  }

  private buildPredictedEntryTargetPreviewRect(tabId: string): BrowserTabsOverlayRect | undefined {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return undefined;
    }
    if (this.isListLayout()) {
      return this.buildListEntryTargetPreviewRect(targetTabId);
    }
    const visibleTabIds = this.resolveVisibleTabIds();
    if (this.isHorizontalCardsLayout()) {
      // The strip centres one card per page, so the predicted landing rect is that card's own box.
      if (visibleTabIds.indexOf(targetTabId) < 0) {
        return undefined;
      }
      const targetWidth = this.layoutState.cardWidth;
      const targetHeight = this.layoutState.previewHeight;
      const targetItemHeight = this.layoutState.itemHeight;
      const contentPadding = this.resolveHorizontalContentPadding();
      const availableHeight = Math.max(1,
        this.resolveRootHeight() - contentPadding.top - contentPadding.bottom);
      const usableWidth = Math.max(1, this.resolveRootWidth() - FLOATING_TABS_HORIZONTAL_PADDING * 2);
      return {
        left: this.resolveRootLeft() + FLOATING_TABS_HORIZONTAL_PADDING +
          Math.max(0, (usableWidth - targetWidth) / 2),
        top: this.resolveRootTop() + contentPadding.top +
          Math.max(0, (availableHeight - targetItemHeight) / 2) +
          this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap,
        width: targetWidth,
        height: targetHeight
      };
    }
    if (this.isStackLayout()) {
      if (visibleTabIds.indexOf(targetTabId) < 0) {
        return undefined;
      }
      // Same geometry that paints the focused card, including its 0.98 rest scale. The unscaled
      // layout slot was ~2% larger, so the morph landed full-size and the real card then shrank.
      const deckRect = this.resolveDeckPreviewRect(targetTabId);
      if (deckRect !== undefined) {
        return deckRect;
      }
      return this.buildDeckPreviewRect(this.stackLayoutPolicy.resolveCard(
        0, 0, 1, this.layoutState.cardWidth));
    }
    const columnCount = Math.max(1, Math.floor(this.layoutState.columnCount));
    const slotCount = visibleTabIds.length + this.resolveBlankSlotCount(columnCount, visibleTabIds.length);
    const rectInput: BrowserTabsFloatingEntryTargetRectInput = {
      tabIds: visibleTabIds,
      tabId: targetTabId,
      slotCount: slotCount,
      viewportLeft: this.resolveRootLeft(),
      viewportTop: this.resolveRootTop(),
      viewportHeight: this.resolveRootHeight(),
      horizontalPadding: FLOATING_TABS_HORIZONTAL_PADDING,
      topPadding: this.resolveContentTopPadding(),
      bottomPadding: this.resolveContentBottomPadding(),
      columnCount: columnCount,
      cardWidth: this.layoutState.cardWidth,
      previewHeight: this.layoutState.previewHeight,
      previewTopInset: this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap,
      itemHeight: this.layoutState.itemHeight,
      gridGap: FLOATING_TABS_GRID_GAP
    };
    const rect = this.entryTargetCoordinator.resolvePredictedCenteredPreviewRect(rectInput);
    if (rect === undefined) {
      return undefined;
    }
    return {
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height
    };
  }

  private syncLayoutState(): void {
    const width = this.resolveRootWidth();
    const height = this.resolveRootHeight();
    const nextState = this.layoutViewModel.buildState({
      gridWidth: Math.max(1, width - FLOATING_TABS_HORIZONTAL_PADDING * 2),
      sheetWidth: width,
      sheetHeight: height,
      layoutStyle: this.storedTabsOverviewLayoutStyle,
      uiFontScale: this.resolveOverviewUiFontScale()
    });
    // onAreaChange calls this on every layout pass. Re-assigning an equal @State
    // object forces another grid re-render, so keep the current object when the
    // resolved geometry is unchanged.
    if (isSameTabsOverviewLayoutState(this.layoutState, nextState)) {
      return;
    }
    this.layoutState = nextState;
    if (this.isStackLayout()) {
      // The deck needs its own item list and a starting card as soon as the style is known.
      this.ensureDeckPositionForCurrentSection();
    } else {
      this.deckPositionSeeded = false;
    }
  }

  /**
   * Build the deck's item list and, once per entry, place it on the tab the overlay opened for.
   * Called from both `initializeForOpen` and `syncLayoutState`, because either can be the first to
   * observe the horizontal style.
   */
  private ensureDeckPositionForCurrentSection(): void {
    if (!this.isStackLayout()) {
      return;
    }
    this.refreshDeckPresentation();
    if (this.deckPositionSeeded || this.deckItems.length <= 0) {
      return;
    }
    const targetId = this.shouldPrepareEntryTarget() ? this.resolveEntryTargetTabId() : this.activeTabId;
    const target = this.deckItems.findIndex((item: BrowserTabsFloatingItem): boolean => item.id === targetId);
    this.seedDeckPosition(target >= 0 ? target : Math.max(0, this.deckItems.length - 1));
  }

  private handleSystemFontScaleChanged(): void {
    this.syncLayoutState();
  }

  /**
   * Scale the card title and its header should follow. This is the shell-aware content scale:
   * the phone follows the system, and the large-screen shell is already pinned to 1.
   */
  private resolveOverviewUiFontScale(): number {
    const scale = this.storedContentFontSizeScale;
    if (!Number.isFinite(scale) || scale <= 0) {
      return 1;
    }
    return scale;
  }

  private handleStoredTabsOverviewLayoutStyleChanged(): void {
    const previousStyle = this.layoutState.layoutStyle;
    this.deckPositionSeeded = false;
    this.syncLayoutState();
    if (previousStyle === this.layoutState.layoutStyle) {
      return;
    }
    this.stopDeckMotion();
    this.refreshDeckPresentation();
    this.positionCardsForCurrentSection();
    this.entryTargetPreparationState =
      this.entryTargetCoordinator.clearPreviewRectCache(this.entryTargetPreparationState);
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (!this.exiting) {
        // Re-enters the same entry-target-aware path instead of forcing the deck onto the active
        // tab, which would drop an in-flight entry target.
        this.positionCardsForCurrentSection();
      }
    }, FLOATING_TABS_BOTTOM_POSITION_DELAY_MS);
  }

  private resolveCardTranslateX(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 0;
    }
    if (this.isSelectionDisplacementActive()) {
      return this.resolveSelectionDisplacement(item).x;
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      return this.resolveEntryDisplacement(item).x * (1 - this.resolveEntryDisplacementProgress());
    }
    if (this.exiting || this.closeAllExitActive) {
      return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item));
    }
    const homeExitProgress = this.resolveHomeExitProgress();
    if (homeExitProgress > 0) {
      return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item)) * homeExitProgress;
    }
    if (!this.sideEntryAnimationEnabled) {
      return 0;
    }
    const progress = this.resolveSurfaceProgress();
    return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item)) * (1 - progress);
  }

  private resolveCardTranslateY(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 0;
    }
    if (this.isSelectionDisplacementActive()) {
      return this.resolveSelectionDisplacement(item).y;
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      return this.resolveEntryDisplacement(item).y * (1 - this.resolveEntryDisplacementProgress());
    }
    if (this.exiting || this.closeAllExitActive) {
      return 0;
    }
    return 0;
  }

  private resolveCardScale(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 1;
    }
    if (this.isSelectionDisplacementActive()) {
      // The 0.98 shrink is the grid making room. The strip and the deck keep their own card size.
      return this.selectionDisplacementCoordinator.appliesNeighborDisplacement(this.layoutState.layoutStyle) ?
        0.98 : 1;
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 1;
    }
    if (this.exiting || this.closeAllExitActive) {
      return 0.96;
    }
    const homeExitProgress = this.resolveHomeExitProgress();
    if (homeExitProgress > 0) {
      return 1 - (1 - 0.96) * homeExitProgress;
    }
    return 0.98 + this.resolveSurfaceProgress() * 0.02;
  }

  private resolveCardOpacity(item: BrowserTabsFloatingItem): number {
    if (this.isMorphCoveredTab(item.tab.id)) {
      return 1;
    }
    return 1 - this.resolveHomeExitProgress();
  }

  private resolveIdentityMotion(item: BrowserTabsFloatingItem): BrowserTabsOverviewIdentityMotionState {
    return this.animationViewModel.buildIdentityMotionState({
      coveredByMorph: this.isMorphCoveredTab(item.tab.id),
      transitionMounted: this.entrySharedSnapshotMounted &&
        this.entrySharedSnapshotState.tabId === item.tab.id,
      direction: this.entrySharedSnapshotState.direction,
      progress: this.entrySharedSnapshotState.progress
    });
  }

  private resolveCardMotionDurationMs(): number {
    if (this.isSelectionDisplacementActive()) {
      return this.animationViewModel.getSharedSnapshotExitDurationMs();
    }
    if (this.isSelectionMorphWaitingForDisplacement()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      // Waiting: duration 0 so the origin is a snap while the layer is still hidden.
      // Settling: the same 350ms implicit animation that carries the fly-in. Animating
      // progress while this duration was 0 made ArkUI snap the derived translate to rest.
      if (!this.entryDisplacementSettlingEnabled) {
        return 0;
      }
      return this.animationViewModel.getSharedSnapshotEnterDurationMs();
    }
    if (this.resolveHomeExitProgress() > 0 && !this.exiting && !this.closeAllExitActive) {
      return this.animationViewModel.getHomeRevealExitDurationMs();
    }
    if (!this.sideEntryAnimationEnabled && !this.exiting) {
      return 0;
    }
    return (this.exiting || this.closeAllExitActive) ? FLOATING_TABS_EXIT_DURATION_MS :
      this.animationViewModel.getFloatingCardEntryDurationMs();
  }

  private resolveCardMotionCurve(): Curve | string | ICurve {
    if (this.isSelectionDisplacementActive()) {
      return this.animationViewModel.getSharedSnapshotExitCurve();
    }
    if (this.isEntryDisplacementActive()) {
      return this.animationViewModel.getSharedSnapshotEnterCurve();
    }
    if (this.resolveHomeExitProgress() > 0 && !this.exiting && !this.closeAllExitActive) {
      return this.animationViewModel.getHomeRevealExitCurve();
    }
    return (this.exiting || this.closeAllExitActive) ? this.animationViewModel.getFloatingCardExitCurve() :
      this.animationViewModel.getFloatingCardEntryCurve();
  }

  private resolveCardMotionDelayMs(index: number): number {
    if (this.isSelectionDisplacementActive()) {
      return 0;
    }
    if (this.isEntryDisplacementActive()) {
      return 0;
    }
    if (this.exiting || this.closeAllExitActive) {
      return 0;
    }
    if (this.resolveHomeExitProgress() > 0) {
      return 0;
    }
    if (!this.sideEntryAnimationEnabled) {
      return 0;
    }
    return this.animationViewModel.resolveFloatingCardDelayMs(index, this.layoutState.columnCount);
  }

  private shouldRunLateMountEntryAnimation(item: BrowserTabsFloatingItem): boolean {
    return this.isFirstOpenInFlight &&
      this.lateMountEntryAnimationEnabled &&
      this.sideEntryAnimationEnabled &&
      !this.exiting &&
      !this.closeAllExitActive &&
      !this.isMorphCoveredTab(item.tab.id) &&
      !this.isSelectionDisplacementActive();
  }

  private resolveLateMountEntryOffsetX(item: BrowserTabsFloatingItem): number {
    if (!this.shouldRunLateMountEntryAnimation(item)) {
      return 0;
    }
    return this.resolveLeftFlyOffsetX(this.resolveDeckIndex(item)) * this.resolveSurfaceProgress();
  }

  private resolveLateMountEntryAnimationWindowMs(): number {
    return this.animationViewModel.getFloatingCardEntryDurationMs() +
      this.animationViewModel.getFloatingCardMaxDelayMs() +
      160;
  }

  private resolveSurfaceProgress(): number {
    if (this.exiting && this.isSelectionDisplacementActive()) {
      return Math.max(0, Math.min(1, this.entryProgress));
    }
    if (this.exiting) {
      return 0;
    }
    const exitProgress = this.closeAllExitActive ? 0 : this.resolveHomeExitProgress();
    return Math.max(0, Math.min(1, this.entryProgress)) * (1 - exitProgress);
  }

  private resolveBottomChromeOpacity(): number {
    if (this.exiting || this.closeAllExitActive) {
      return 0;
    }
    return this.resolveSurfaceProgress();
  }

  private resolveLayerOpacity(): number {
    if (!Number.isFinite(this.layerOpacity)) {
      return 1;
    }
    return Math.max(0, Math.min(1, this.layerOpacity));
  }

  private resolveHomeExitProgress(): number {
    if (!Number.isFinite(this.homeExitProgress)) {
      return 0;
    }
    return Math.max(0, Math.min(1, this.homeExitProgress));
  }

  private resolveEntryInitialProgress(): number {
    return this.sideEntryAnimationEnabled ? 0 : 1;
  }

  private resolveEntryDisplacementInitialProgress(): number {
    if (!this.isEntryDisplacementActive()) {
      return 1;
    }
    return 0;
  }

  private resolveContentTopPadding(): number {
    return Math.max(FLOATING_TABS_TOP_PADDING, this.topSafeInsetVp + FLOATING_TABS_TOP_PADDING);
  }

  private resolveContentBottomPadding(): number {
    if (!this.shouldShowBottomChrome()) {
      return FLOATING_TABS_TOP_PADDING;
    }
    return BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE +
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT +
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP;
  }

  private resolveHorizontalContentPadding(): BrowserTabsFloatingContentPadding {
    let top = this.resolveContentTopPadding();
    let bottom = this.resolveContentBottomPadding();
    let overflow = Math.max(0, this.layoutState.itemHeight + top + bottom - this.resolveRootHeight());
    if (overflow <= 0) {
      return { top: top, bottom: bottom };
    }

    const minimumTop = Math.max(0, this.topSafeInsetVp);
    const topReduction = Math.min(overflow, Math.max(0, top - minimumTop));
    top -= topReduction;
    overflow -= topReduction;

    const minimumBottom = this.shouldShowBottomChrome()
      ? BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE + BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT
      : 0;
    const bottomReduction = Math.min(overflow, Math.max(0, bottom - minimumBottom));
    bottom -= bottomReduction;
    return { top: top, bottom: bottom };
  }

  private shouldShowBottomChrome(): boolean {
    return BrowserWindowRuntime.resolveActiveShellPresentationSurface() !== 'large_screen';
  }

  private resolvePanelPageBackgroundColor(): ResourceColor {
    return this.panelPageBackgroundColor ?? this.storedPageBackgroundColor;
  }

  private resolveBackgroundTintOpacity(): number {
    // The API 26 immersive material is intentionally not used for the full-screen
    // overview backdrop. Keep the existing transition opacity on the plain page
    // background so the home surface does not show through unexpectedly.
    return this.resolveBackgroundSurfaceOpacity();
  }

  private resolveBackgroundSurfaceOpacity(): number {
    if (!Number.isFinite(this.backgroundSurfaceOpacity) || this.backgroundSurfaceOpacity < 0) {
      return this.resolveSurfaceProgress();
    }
    return Math.max(0, Math.min(1, this.backgroundSurfaceOpacity));
  }

  private resolvePanelSecondaryTextColor(): ResourceColor {
    return this.panelSecondaryTextColor ?? this.storedSecondaryTextColor;
  }

  private resolveRootWidth(): number {
    return Math.max(1, Math.round(this.viewportWidth));
  }

  private resolveRootHeight(): number {
    return Math.max(1, Math.round(this.viewportHeight));
  }

  private resolveRootLeft(): number {
    return Number.isFinite(this.viewportLeft) ? this.viewportLeft : 0;
  }

  private resolveRootTop(): number {
    return Number.isFinite(this.viewportTop) ? this.viewportTop : 0;
  }

  private resolveLeftFlyOffsetX(index: number): number {
    const column = Math.max(0, Math.floor(index)) % Math.max(1, Math.floor(this.layoutState.columnCount));
    const columnStride = Math.max(1, this.layoutState.cardWidth + FLOATING_TABS_GRID_GAP);
    return -Math.max(this.resolveRootWidth(), this.layoutState.cardWidth) - (column + 1) * columnStride;
  }

  private resolveMorphCoveredTabId(): string {
    return this.morphCoveredTabId.trim();
  }

  /**
   * Whether the entering morph has to be painted from inside the deck.
   *
   * Only an entering morph settles into a deck card and therefore has to interleave with the deck's
   * own draw order. The exit morph grows back out to the page and stays above every card.
   */
  private isStackEntryMorph(): boolean {
    return this.paintsMorphInDeck() &&
      this.entrySharedSnapshotMounted &&
      this.entrySharedSnapshotState.direction === 'enter';
  }

  private shouldMountSharedSnapshotInDeck(): boolean {
    return this.entrySharedSnapshotMounted &&
      this.entrySharedSnapshotState.direction === 'enter' &&
      this.resolveDeckEntryMorphSlot() >= 0;
  }

  /**
   * The covered card's slot, or -1 when the morph is not settling into a card of this deck.
   *
   * This is the card's position in the deck's own list, which is also the slot the deck records for
   * it, so the morph holds a stacking slot that belongs to no other card.
   */
  private resolveDeckEntryMorphSlot(): number {
    if (!this.paintsMorphInDeck()) {
      return -1;
    }
    const coveredTabId = this.resolveMorphCoveredTabId();
    if (coveredTabId.length <= 0) {
      return -1;
    }
    for (let position = 0; position < this.deckItems.length; position += 1) {
      const item: BrowserTabsFloatingItem = this.deckItems[position];
      if (item.id === coveredTabId) {
        // The live position, not `item.index`: a reused card keeps the index it was built with.
        return position;
      }
    }
    return -1;
  }

  /** The deck slot's own layer: strictly above the covered card, strictly below its successor. */
  private resolveDeckEntryMorphLayerZIndex(): number {
    const slot = this.shouldMountSharedSnapshotInDeck() ? this.resolveDeckEntryMorphSlot() : -1;
    return slot < 0 ? 0 : slot * 2 + 1;
  }

  private isMorphCoveredTab(tabId: string): boolean {
    const coveredTabId = this.resolveMorphCoveredTabId();
    return coveredTabId.length > 0 && coveredTabId === tabId;
  }

  /**
   * Hide the card surface only when the morph is not already painting in front of it.
   *
   * An in-deck morph sits one slot above the covered card and covers its preview for the whole
   * entry. The grid and the strip paint the same morph above the cards layer. Zeroing that
   * preview left a hole the frame the morph unmounted — the current card vanished and then
   * popped back. Keeping it painted means unmount only removes the overlay.
   */
  private shouldHideCardSurfaceUnderMorph(tabId: string): boolean {
    if (this.shouldMountSharedSnapshotInDeck()) {
      this.entryMorphPreviewLatchedTabId = '';
      return false;
    }
    if (!this.isMorphCoveredTab(tabId)) {
      if (this.entryMorphPreviewLatchedTabId === tabId) {
        this.entryMorphPreviewLatchedTabId = '';
      }
      return false;
    }
    if (this.entryMorphPreviewLatchedTabId === tabId || this.isEntryMorphOverlayCovering(tabId)) {
      this.entryMorphPreviewLatchedTabId = tabId;
      return false;
    }
    return true;
  }

  /**
   * The root overlay is up and shrinking onto this card, so the card underneath is covered.
   */
  private isEntryMorphOverlayCovering(tabId: string): boolean {
    const state = this.entrySharedSnapshotState;
    return this.entrySharedSnapshotMounted &&
      state.direction === 'enter' &&
      state.tabId === tabId &&
      state.phase !== 'idle' &&
      state.phase !== 'settled';
  }

  private isSelectionDisplacementActive(): boolean {
    return this.selectionDisplacementTabId.trim().length > 0;
  }

  private isSelectionMorphWaitingForDisplacement(): boolean {
    return this.exiting && this.resolveMorphCoveredTabId().length > 0 &&
      !this.isSelectionDisplacementActive();
  }

  private isEntryDisplacementActive(): boolean {
    return !this.sideEntryAnimationEnabled && !this.exiting && this.entryDisplacementTabId.trim().length > 0;
  }

  private shouldPrepareEntryTarget(): boolean {
    return this.isEntryDisplacementActive();
  }

  private resolveEntryTargetTabId(): string {
    return this.entryDisplacementTabId.trim();
  }

  private resolveSelectionDisplacement(item: BrowserTabsFloatingItem): BrowserTabsOverviewSelectionDisplacement {
    return this.selectionDisplacementCoordinator.resolveForLayout(this.layoutState.layoutStyle, {
      tabId: item.tab.id,
      itemIndex: item.index,
      selectedTabId: this.selectionDisplacementTabId,
      selectedIndex: this.resolveSelectionDisplacementIndex(),
      columnCount: this.resolveDisplacementColumnCount(),
      cardWidth: this.layoutState.cardWidth,
      itemHeight: this.layoutState.itemHeight,
      gridGap: this.layoutState.gridGap
    });
  }

  private resolveSelectionDisplacementIndex(): number {
    return this.resolveDisplacementTargetIndex(this.selectionDisplacementTabId);
  }

  private resolveEntryDisplacement(item: BrowserTabsFloatingItem): BrowserTabsOverviewSelectionDisplacement {
    return this.selectionDisplacementCoordinator.resolveForLayout(this.layoutState.layoutStyle, {
      tabId: item.tab.id,
      itemIndex: item.index,
      selectedTabId: this.entryDisplacementTabId,
      selectedIndex: this.resolveEntryDisplacementIndex(),
      columnCount: this.resolveDisplacementColumnCount(),
      cardWidth: this.layoutState.cardWidth,
      itemHeight: this.layoutState.itemHeight,
      gridGap: this.layoutState.gridGap
    });
  }

  /**
   * Grid columns only. The strip and the deck do not use this: their neighbor offset is zero.
   */
  private resolveDisplacementColumnCount(): number {
    return Math.max(1, this.layoutState.columnCount);
  }

  private resolveEntryDisplacementIndex(): number {
    return this.resolveDisplacementTargetIndex(this.entryDisplacementTabId);
  }

  private resolveEntryDisplacementProgress(): number {
    return Math.max(0, Math.min(1, this.entryDisplacementProgress));
  }

  private resolveDisplacementTargetIndex(tabId: string): number {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return -1;
    }
    const items = this.resolveVisibleItems();
    for (const item of items) {
      if (item.tab.id === targetTabId) {
        return item.index;
      }
    }
    return -1;
  }

  private resolveVisibleTabIds(): string[] {
    const items = this.resolveVisibleItems();
    const ids: string[] = [];
    for (const item of items) {
      ids.push(item.tab.id);
    }
    return ids;
  }

  /**
   * The one width and height every card of a style shares.
   *
   * The strip, the grid and the deck all take this from the layout state. A screenshot is drawn
   * inside that box; its pixel size never becomes the box.
   */
  private resolveCardWidth(): number {
    return this.layoutState.cardWidth;
  }

  private resolveItemHeight(): number {
    return this.layoutState.previewHeight + this.layoutState.identityHeaderHeight +
      this.layoutState.identityPreviewGap;
  }

  /**
   * The dismiss gesture runs along the card's own axis: a grid card is swiped sideways, while the
   * horizontal-cards style is swiped up, so the travel that matters is the card's height. Measuring
   * the card keeps the effort the same on every window size instead of a fixed distance that is a
   * fifth of a desktop card and two thirds of a phone one.
   */
  private resolveSwipeDismissThreshold(): number {
    const extent = this.usesUpwardCardDismiss() ?
      this.resolveItemHeight() : this.resolveCardWidth();
    return this.swipeDismissPolicy.resolveThresholdVp(extent);
  }

  /**
   * The stacked deck. Every deck-only behaviour is gated on this instead of on a "not grid" test, so
   * the large card strip can share the overlay without inheriting the deck's geometry.
   */
  private resolvePaintedStyleEntryProfile(): BrowserTabsOverviewStyleEntryProfile {
    return this.styleEntryPolicy.resolve(this.layoutState.layoutStyle);
  }

  /**
   * The deck morph has to know it is a deck before the first layout pass rewrites layoutStyle.
   * Either the painted style or the stored style is enough; a list profile can never say deck.
   */
  private paintsMorphInDeck(): boolean {
    return this.styleEntryPolicy.resolve(this.layoutState.layoutStyle).morphHost === 'deck' ||
      this.styleEntryPolicy.resolve(this.storedTabsOverviewLayoutStyle).morphHost === 'deck';
  }

  private isStackLayout(): boolean {
    return this.layoutState.layoutStyle === 'stack';
  }

  /**
   * The large centred card strip.
   */
  private isHorizontalCardsLayout(): boolean {
    return this.layoutState.layoutStyle === 'horizontal_cards';
  }

  private isListLayout(): boolean {
    return this.layoutState.layoutStyle === 'list';
  }

  /**
   * Where the current row sits after the list is anchored to the bottom.
   *
   * The entry morph starts from this prediction when the row has not reported its own rect yet.
   * A missing rect leaves the list invisible: the cards layer stays at opacity 0 until a target
   * exists. The measured row replaces this once `onAreaChange` arrives.
   */
  private buildListEntryTargetPreviewRect(tabId: string): BrowserTabsOverlayRect | undefined {
    const index = this.resolveListItemIndex(tabId);
    if (index < 0) {
      return undefined;
    }
    const metrics = this.resolveListStackMetrics();
    const itemTop = metrics.spacer + index * (metrics.itemHeight + metrics.gap);
    const scroll = this.resolveListEntryScrollOffset(tabId);
    return {
      left: this.resolveRootLeft() + FLOATING_TABS_HORIZONTAL_PADDING,
      top: this.resolveRootTop() + metrics.contentTop + itemTop - scroll,
      width: Math.max(1, this.layoutState.cardWidth),
      height: metrics.itemHeight
    };
  }

  /**
   * Oldest activity at the top, the tab you just left at the bottom. Equal times keep the
   * current tab below the others so the shrink still lands on the bottom row.
   */
  private resolveListItems(): BrowserTabsFloatingItem[] {
    const source = this.resolveVisibleItems();
    const ordered = source.slice();
    const activeTabId = this.activeTabId;
    ordered.sort((left: BrowserTabsFloatingItem, right: BrowserTabsFloatingItem): number => {
      if (left.tab.lastActiveAt !== right.tab.lastActiveAt) {
        return left.tab.lastActiveAt - right.tab.lastActiveAt;
      }
      if (left.tab.id === activeTabId) {
        return 1;
      }
      if (right.tab.id === activeTabId) {
        return -1;
      }
      return left.index - right.index;
    });
    const items: BrowserTabsFloatingItem[] = [];
    for (let index = 0; index < ordered.length; index += 1) {
      const item = ordered[index];
      items.push({
        id: item.id,
        tab: item.tab,
        presentation: item.presentation,
        index: index
      });
    }
    return items;
  }

  private resolveListItemIndex(tabId: string): number {
    const targetTabId = tabId.trim();
    if (targetTabId.length <= 0) {
      return -1;
    }
    const items = this.resolveListItems();
    for (let index = 0; index < items.length; index += 1) {
      if (items[index].tab.id === targetTabId) {
        return index;
      }
    }
    return -1;
  }

  private resolveListStackMetrics(): BrowserTabsListStackMetrics {
    const itemHeight = Math.max(1, this.layoutState.itemHeight);
    const gap = Math.max(0, this.layoutState.gridGap);
    const count = this.resolveListItems().length;
    const contentTop = this.resolveContentTopPadding();
    const contentBottom = this.resolveContentBottomPadding();
    const viewportHeight = Math.max(1, this.resolveRootHeight() - contentTop - contentBottom);
    const contentHeight = count <= 0 ? 0 : count * itemHeight + Math.max(0, count - 1) * gap;
    const spacer = Math.max(0, viewportHeight - contentHeight);
    return {
      itemHeight: itemHeight,
      gap: gap,
      spacer: spacer,
      viewportHeight: viewportHeight,
      maxScroll: Math.max(0, spacer + contentHeight - viewportHeight),
      contentTop: contentTop
    };
  }

  private resolveListEntryScrollOffset(tabId: string): number {
    const index = this.resolveListItemIndex(tabId);
    if (index < 0) {
      return 0;
    }
    const metrics = this.resolveListStackMetrics();
    const itemBottom = metrics.spacer + index * (metrics.itemHeight + metrics.gap) + metrics.itemHeight;
    return Math.min(metrics.maxScroll, Math.max(0, itemBottom - metrics.viewportHeight));
  }

  private scrollListToBottomAnchor(tabId: string): void {
    this.scroller.scrollTo({
      xOffset: 0,
      yOffset: this.resolveListEntryScrollOffset(tabId),
      animation: false
    });
  }

  /**
   * The inset that centres one strip card in the viewport. Every card has the same width, so the
   * first and the last card use the same inset the layout state already computed.
   */
  private resolveHorizontalEdgeInset(_first: boolean): number {
    return this.layoutState.horizontalContentInset;
  }

  private resolveDeckItems(): BrowserTabsFloatingItem[] {
    const range = this.stackLayoutPolicy.resolveVisibleRange(this.horizontalDeckPosition,
      this.deckItems.length, this.resolveRootWidth(), this.layoutState.cardWidth);
    return this.deckItems.slice(range.first, range.last + 1);
  }

  /**
   * The card's slot in the deck.
   *
   * Read from the recorded map, never from the `ForEach` item: a reused node keeps the item it was
   * built with, so a removal would leave every surviving card on its old slot. The `item.index`
   * fallback only covers a card whose map entry has not been written yet.
   */
  private resolveDeckIndex(item: BrowserTabsFloatingItem): number {
    const slot = this.deckSlotIndexById[item.id];
    return slot === undefined ? item.index : slot;
  }

  private buildDeckSlotMap(ids: string[]): Record<string, number> {
    const slots: Record<string, number> = {};
    for (let index = 0; index < ids.length; index += 1) {
      slots[ids[index]] = index;
    }
    return slots;
  }

  /** Publish the slots of `items`, unless the deck already holds exactly this order. */
  private recordDeckSlots(items: BrowserTabsFloatingItem[]): void {
    const ids: string[] = [];
    for (const item of items) {
      ids.push(item.id);
    }
    const signature = ids.join('|');
    if (signature === this.deckSlotSignature) {
      return;
    }
    this.deckSlotSignature = signature;
    this.deckSlotIndexById = this.buildDeckSlotMap(ids);
  }

  private resolveDeckMetrics(item: BrowserTabsFloatingItem): BrowserTabsOverviewStackCardMetrics {
    // `build()` reads the metrics several times per card per display frame. They are pure in the
    // deck scalar, the recorded slots and the card width, so one memo table serves the whole frame.
    const slot = this.resolveDeckIndex(item);
    const key = `${this.horizontalDeckPosition}|${this.layoutState.cardWidth}|` +
      `${this.deckItemsSignature}|${this.deckSlotSignature}`;
    if (key !== this.deckMetricsCacheKey) {
      this.deckMetricsCacheKey = key;
      this.deckMetricsCache = [];
    }
    const cached = this.deckMetricsCache[slot];
    if (cached !== undefined) {
      return cached;
    }
    const metrics = this.stackLayoutPolicy.resolveCard(slot, this.horizontalDeckPosition,
      this.deckItems.length, this.layoutState.cardWidth);
    this.deckMetricsCache[slot] = metrics;
    return metrics;
  }

  // Presentation construction is driven by data changes, never by an animation frame. The item
  // list is rebuilt only when the tab list itself changes; the per-frame cost is the metrics, and
  // `build()` reads `deckItems` instead of rebuilding presentations.
  private refreshDeckPresentation(): void {
    if (!this.isStackLayout()) { return; }
    const next = this.resolveVisibleItems();
    const previousIds = this.deckItems.map((item: BrowserTabsFloatingItem): string => item.id);
    const nextIds = next.map((item: BrowserTabsFloatingItem): string => item.id);
    const listChanged = previousIds.join('|') !== nextIds.join('|');
    if (listChanged) {
      const position = this.stackLayoutPolicy.reconcilePosition(
        this.horizontalDeckPosition, previousIds, nextIds);
      // A snapshot or icon update can land mid-drag; adopting the position keeps the finger
      // attached instead of cancelling the gesture. Overscroll is preserved on purpose.
      this.horizontalDeckPosition = this.deckMotion.setPosition(position);
      if (!this.deckMotion.isDragging()) {
        this.deckDragActive = false;
      }
      // A card that vanished mid-swipe never reports its own cancel, so the latch is cleared here.
      if (this.deckSwipeTabId.length > 0 && nextIds.indexOf(this.deckSwipeTabId) < 0) {
        this.deckSwipeTabId = '';
      }
    }
    this.deckItems = next;
    this.deckItemsSignature = nextIds.join('|');
    // A fill-in owns the recorded slots until it commits. A preview or an icon can land during those
    // few hundred milliseconds, and re-recording the list that still holds the closed card would put
    // every card back on its old slot halfway through the animation.
    if (this.pendingDeckDismissTabId.length <= 0) {
      this.recordDeckSlots(next);
    }
    // A non-gesture state change must not leave the deck between two cards with no frame left.
    if (listChanged && !this.deckMotion.isDragging()) {
      this.settleDeckToNearestCard();
    }
  }

  private canInteractWithDeck(): boolean {
    return this.interactionEnabled && !this.exiting && !this.closeAllExitActive &&
      !this.isSelectionDisplacementActive() && !this.isEntryDisplacementActive() &&
      this.pendingDeckDismissTabId.length <= 0;
  }

  /** Cancel the gesture and any settle, and leave the position where it is. */
  private stopDeckMotion(): void {
    this.deckMotion.stop();
    this.deckDragActive = false;
    this.deckSwipeTabId = '';
  }

  /**
   * Close a card without re-indexing first: one animation moves the whole deck into its new shape.
   *
   * Taking the card out of the list changes every later card's slot in one assignment, and a card
   * cannot be moved by animating a `ForEach` index change — the node is reused with the item it was
   * built with, and the nonlinear deck layout is not something ArkUI interpolates. So the closed card
   * stays in the list as a ghost while two pieces of state the cards do observe move together: the
   * deck scalar moves to the focus the shorter list will have, and every surviving card moves to its
   * new slot. Cards the removal does not affect keep both values and therefore do not move at all.
   *
   * The new focus is the closed card's successor when it held the focus, and its predecessor when it
   * was the last card — which is exactly what `reconcilePosition` resolves against the shorter list.
   */
  private beginDeckDismiss(tabId: string): void {
    if (this.pendingDeckDismissTabId.length > 0) {
      return;
    }
    this.stopDeckMotion();
    const previousIds = this.deckItems.map((item: BrowserTabsFloatingItem): string => item.id);
    const nextIds = previousIds.filter((id: string): boolean => id !== tabId);
    const position = this.stackLayoutPolicy.reconcilePosition(
      this.horizontalDeckPosition, previousIds, nextIds);
    this.pendingDeckDismissTabId = tabId;
    this.pendingDeckDismissPosition = position;
    this.deckDismissGhostTabId = tabId;
    // The outermost card leaves no slot behind, so nothing moves and the ghost can go at once.
    if (nextIds.length <= 0 || !this.hasDeckSlotChange(previousIds, nextIds, position)) {
      this.commitPendingDeckDismiss();
      return;
    }
    const slots = this.buildDeckSlotMap(nextIds);
    const slotSignature = nextIds.join('|');
    // Armed before the animation: a dismissal that never commits would leave the deck holding a
    // ghost and refusing every pan, which is worse than losing the fill-in's animation.
    this.scheduleDeckDismissCommit();
    animateTo({
      duration: FLOATING_TABS_REORDER_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardEntryCurve()
    }, () => {
      this.horizontalDeckPosition = position;
      this.deckSlotIndexById = slots;
      this.deckSlotSignature = slotSignature;
    });
    this.deckMotion.setPosition(position);
  }

  /**
   * Whether the fill-in has anything to move.
   *
   * A card's place is its slot against the deck scalar, so a removal only moves the cards beyond the
   * removed one, and only towards the focus. Closing the outermost card moves none of them: the fan
   * simply loses that slot, which is why the two end cases need no fill-in at all.
   */
  private hasDeckSlotChange(previousIds: string[], nextIds: string[], position: number): boolean {
    const previousPosition = this.horizontalDeckPosition;
    for (let index = 0; index < nextIds.length; index += 1) {
      const previousIndex = previousIds.indexOf(nextIds[index]);
      if (previousIndex < 0) {
        continue;
      }
      if (Math.abs((previousIndex - previousPosition) - (index - position)) > 0.000001) {
        return true;
      }
    }
    return false;
  }

  /**
   * Finish a dismissal once the fill-in has painted.
   *
   * The timer owns the commit instead of the animation's completion callback, and it doubles as a
   * backstop: a dismissal that never commits would leave the deck holding a ghost and refusing every
   * touch. Committing early is harmless — the committed values are the animation's own end state.
   */
  private scheduleDeckDismissCommit(): void {
    this.clearDeckDismissCommitTimer();
    this.deckDismissCommitTimer = setTimeout(() => {
      this.deckDismissCommitTimer = 0;
      this.commitPendingDeckDismiss();
    }, FLOATING_TABS_REORDER_DURATION_MS);
  }

  private clearDeckDismissCommitTimer(): void {
    if (this.deckDismissCommitTimer <= 0) {
      return;
    }
    clearTimeout(this.deckDismissCommitTimer);
    this.deckDismissCommitTimer = 0;
  }

  private commitPendingDeckDismiss(): void {
    const tabId = this.pendingDeckDismissTabId;
    const position = this.pendingDeckDismissPosition;
    this.clearDeckDismissCommitTimer();
    this.pendingDeckDismissTabId = '';
    this.pendingDeckDismissPosition = -1;
    this.deckDismissGhostTabId = '';
    this.deckSwipeTabId = '';
    if (tabId.length <= 0) {
      return;
    }
    this.stopDeckMotion();
    this.removalState = this.shadowViewModel.markLocalRemoval(this.removalState, tabId);
    this.refreshDeckPresentation();
    this.refreshBottomChromeCounts();
    // `refreshDeckPresentation` anchors on the list that still held the closed card, so its position
    // is not the one the animation already reached. Re-publishing the settled values is a no-op for
    // the cards, because they are where the animation left them.
    if (this.deckItems.length > 0) {
      this.horizontalDeckPosition = this.deckMotion.seed(
        this.stackLayoutPolicy.clamp(position, this.deckItems.length), this.deckItems.length);
    }
    this.recordDeckSlots(this.deckItems);
    this.onCloseTab(tabId);
  }

  /**
   * End the interaction and put the deck back on a card.
   *
   * Anything that interrupts a gesture or a settle without the finger handing over (the layer
   * hides, a card claims the touch, a tab closes) has to come through here. Stopping alone would
   * leave the deck parked between two cards, and the gesture's own `onActionEnd` no longer owns the
   * motion to finish it.
   */
  private abortDeckMotion(): void {
    if (this.pendingDeckDismissTabId.length > 0) {
      this.commitPendingDeckDismiss();
      return;
    }
    this.stopDeckMotion();
    this.settleDeckToNearestCard();
  }

  private settleDeckToNearestCard(): void {
    if (!this.isStackLayout() || this.deckItems.length <= 0) {
      return;
    }
    if (this.exiting || this.closeAllExitActive) {
      // The deck is on its way out; a floor-level position no longer shows, and a reopen reseeds.
      return;
    }
    this.deckMotion.settleToNearest(this.deckItems.length,
      (callback: (time: number) => void): void => { this.scheduleDeckFrame(callback); },
      (position: number): void => { this.horizontalDeckPosition = position; });
  }

  private handleDeckInteractionChanged(): void {
    if (!this.canInteractWithDeck()) {
      this.abortDeckMotion();
      this.segmentGuideStep = 0;
    }
    this.syncSegmentGuidePresence();
  }

  private async refreshSegmentGuidePending(): Promise<void> {
    await sharedTabsOverviewSegmentGuideRepository.initialize();
    this.segmentGuidePending = !sharedTabsOverviewSegmentGuideRepository.hasCompleted();
    this.syncSegmentGuidePresence();
  }

  private shouldPresentSegmentGuide(): boolean {
    return this.segmentGuidePending &&
      this.chromeMounted &&
      this.shouldShowBottomChrome() &&
      this.interactionEnabled &&
      !this.exiting &&
      !this.closeAllExitActive;
  }

  private syncSegmentGuidePresence(): void {
    const showing = this.shouldPresentSegmentGuide();
    tabsOverviewSegmentGuideBackGate.setActive(showing, () => {
      this.advanceSegmentGuide();
    });
  }

  private advanceSegmentGuide(): void {
    if (!this.shouldPresentSegmentGuide()) {
      this.syncSegmentGuidePresence();
      return;
    }
    const next = advanceTabsOverviewSegmentGuide(this.segmentGuideStep);
    if (next.completed) {
      this.segmentGuidePending = false;
      this.segmentGuideStep = 0;
      void sharedTabsOverviewSegmentGuideRepository.markCompleted();
    } else {
      this.segmentGuideStep = next.stepIndex;
    }
    this.syncSegmentGuidePresence();
  }

  private beginDeckDrag(): void {
    if (this.pendingDeckDismissTabId.length > 0) {
      // The gesture reaching the deck means the fill-in has had its time. Finishing it here rather
      // than waiting for the timer cannot leave the deck locked behind a dismissal that never
      // committed, and the committed values are the animation's own end state either way.
      this.commitPendingDeckDismiss();
    }
    if (!this.canInteractWithDeck() || this.deckSwipeTabId.length > 0) { return; }
    this.deckMotion.begin();
    this.deckDragActive = true;
  }

  private updateDeckDrag(offsetX: number): void {
    if (!this.deckDragActive || !this.canInteractWithDeck()) { return; }
    this.horizontalDeckPosition = this.deckMotion.drag(offsetX, this.layoutState.cardWidth, this.deckItems.length);
  }

  private scheduleDeckFrame(callback: (time: number) => void): void {
    this.getUIContext().postFrameCallback(new BrowserTabsStackFrameCallback(callback));
  }

  private endDeckDrag(velocityX: number): void {
    if (!this.deckDragActive) { return; }
    this.deckDragActive = false;
    this.deckMotion.release(velocityX, this.layoutState.cardWidth, this.deckItems.length,
      (callback: (time: number) => void): void => { this.scheduleDeckFrame(callback); },
      (position: number): void => { this.horizontalDeckPosition = position; });
  }

  private cancelDeckDrag(): void {
    if (!this.deckDragActive) { return; }
    this.deckDragActive = false;
    this.deckMotion.cancel(this.deckItems.length,
      (callback: (time: number) => void): void => { this.scheduleDeckFrame(callback); },
      (position: number): void => { this.horizontalDeckPosition = position; });
  }

  private seedDeckPosition(index: number): void {
    if (!this.isStackLayout()) { return; }
    this.stopDeckMotion();
    this.horizontalDeckPosition = this.deckMotion.seed(index, this.deckItems.length);
    this.deckPositionSeeded = true;
  }

  private selectOverviewTab(tabId: string, rect?: BrowserTabOverviewCardSelectRect): void {
    if (this.isStackLayout()) {
      if (this.deckDragActive) { return; }
      // Finish the already accepted close before selection takes ownership of the exit. Otherwise
      // the interaction @Watch commits it during exit and sends a late close into that operation.
      this.commitPendingDeckDismiss();
      this.stopDeckMotion();
      const deckRect = this.resolveDeckPreviewRect(tabId);
      this.onSelectTab(tabId, deckRect === undefined ? rect : this.toSelectRect(deckRect));
      return;
    }
    this.onSelectTab(tabId, rect);
  }

  /**
   * `BrowserTabsOverlayRect` and `BrowserTabOverviewCardSelectRect` describe the same rectangle but
   * are independent types, and ArkTS rejects structural compatibility between them.
   */
  private toSelectRect(rect: BrowserTabsOverlayRect): BrowserTabOverviewCardSelectRect {
    return {
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height
    };
  }

  // onAreaChange reports layout bounds, not the wrapper's live scale/translation. The same
  // geometry that paints the preview supplies the morph rectangle, including the scaled header.
  private resolveDeckPreviewRect(tabId: string): BrowserTabsOverlayRect | undefined {
    const item = this.deckItems.find((candidate: BrowserTabsFloatingItem): boolean => candidate.id === tabId);
    if (item === undefined) { return undefined; }
    return this.buildDeckPreviewRect(this.resolveDeckMetrics(item));
  }

  private buildDeckPreviewRect(metrics: BrowserTabsOverviewStackCardMetrics): BrowserTabsOverlayRect {
    const padding = this.resolveHorizontalContentPadding();
    const centerY = this.resolveRootTop() + padding.top +
      (this.resolveRootHeight() - padding.top - padding.bottom) / 2;
    const header = this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap;
    return {
      left: this.resolveRootLeft() + this.resolveRootWidth() / 2 + metrics.offsetX -
        this.layoutState.cardWidth * metrics.scale / 2,
      top: centerY + (header - this.resolveItemHeight() / 2) * metrics.scale,
      width: this.layoutState.cardWidth * metrics.scale,
      height: this.layoutState.previewHeight * metrics.scale
    };
  }

  private buildBlankSlotKeys(): string[] {
    const safeColumnCount = Math.max(1, Math.floor(this.layoutState.columnCount));
    const itemCount = this.resolveVisibleItems().length;
    const blankSlotCount = this.resolveBlankSlotCount(safeColumnCount, itemCount);
    const keys: string[] = [];
    for (let index = 0; index < blankSlotCount; index += 1) {
      keys.push(`floating-blank-${this.selectedSection}-${itemCount}-${index}`);
    }
    return keys;
  }

  private resolveBlankSlotCount(safeColumnCount: number, itemCount: number): number {
    const remainder = itemCount % safeColumnCount;
    const trailingRowSlotCount = remainder === 0 ? 0 : safeColumnCount - remainder;
    const visibleRowCount = this.resolveVisibleRowCount();
    const visibleSlotCount = visibleRowCount * safeColumnCount;
    return Math.max(trailingRowSlotCount, visibleSlotCount - itemCount);
  }

  private resolveVisibleRowCount(): number {
    const safeItemHeight = Math.max(1, this.layoutState.itemHeight);
    const safeGridGap = Math.max(0, FLOATING_TABS_GRID_GAP);
    const visibleHeight = Math.max(1, this.resolveRootHeight() -
      this.resolveContentTopPadding() - this.resolveContentBottomPadding());
    return Math.max(1, Math.ceil((visibleHeight + safeGridGap) / (safeItemHeight + safeGridGap)));
  }
}
