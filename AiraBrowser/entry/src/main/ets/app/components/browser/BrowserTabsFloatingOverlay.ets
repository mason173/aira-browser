import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTabPreviewState } from '../../../core/browser/BrowserTabPreviewCoordinator';
import {
  BrowserTabOverviewItemPresentation,
  BrowserTabsOverviewIdentityIconSnapshot,
  BrowserTabsOverlayRect,
  BrowserTabsOverlayViewModel
} from '../../../core/browser/BrowserTabsOverlayViewModel';
import {
  BrowserTabsOverviewHorizontalCardFrame,
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
import { BrowserTabOverviewCardSelectRect } from './BrowserTabOverviewCard';
import { BrowserTabOverviewItem } from './BrowserTabOverviewItem';
import { BrowserTabsSharedSnapshotOverlay } from './BrowserTabsSharedSnapshotOverlay';
import {
  BrowserTabsOverviewBottomChrome,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP,
  BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT
} from './BrowserTabsOverviewBottomChrome';
import { BrowserTabsOverviewClearButton } from './BrowserTabsOverviewClearButton';
import { BrowserTabsOverviewDeviceButton } from './BrowserTabsOverviewDeviceButton';
import { BrowserTabsOverviewEmptyState } from './BrowserTabsOverviewEmptyState';
import {
  BrowserTabsOverviewBottomChromeState,
  BrowserTabsOverviewBottomChromeViewModel
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewBottomChromeViewModel';
import {
  BrowserTabsOverviewSwipeFeedbackService
} from '../../../core/browser/tabsOverview/BrowserTabsOverviewSwipeFeedbackService';
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
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY,
  BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { SiteIconListRenderState } from '../../../core/siteicons/SiteIconListPresenter';

const TABS_OVERLAY_LOG_DOMAIN: number = 0x0000;
const TABS_OVERLAY_LOG_TAG: string = 'TabsOverview';
const FLOATING_TABS_HORIZONTAL_PADDING: number = 16;
const FLOATING_TABS_TOP_PADDING: number = 28;
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
const FLOATING_TABS_SHARED_SNAPSHOT_Z_INDEX: number = 20;
const FLOATING_TABS_SHARED_SNAPSHOT_DECORATION_Z_INDEX: number = 25;
const FLOATING_TABS_BOTTOM_CHROME_Z_INDEX: number = 31;
const FLOATING_TABS_CLEAR_BUTTON_Z_INDEX: number = 32;
const FLOATING_TABS_DEVICE_BUTTON_Z_INDEX: number = 32;

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

@Component
export struct BrowserTabsFloatingOverlay {
  @StorageProp(BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_LAYOUT_STYLE_KEY)
  @Watch('handleStoredTabsOverviewLayoutStyleChanged')
  private storedTabsOverviewLayoutStyle: string = 'grid';
  @StorageProp(BROWSER_APPEARANCE_STORAGE_TABS_OVERVIEW_CLOSE_BUTTON_ALWAYS_VISIBLE_KEY)
  private storedTabsOverviewCloseButtonAlwaysVisible: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';

  @Watch('handleTabsChanged')
  @Prop tabs: BrowserTabState[] = [];
  @Prop previewStates: BrowserTabPreviewState[] = [];
  @Prop activeTabId: string = '';
  @Prop activeSection: BrowserTabsOverviewSection = 'tabs';
  @Prop morphCoveredTabId: string = '';
  @Prop selectionDisplacementTabId: string = '';
  @Watch('syncEntryDisplacementFromProps')
  @Prop entryDisplacementTabId: string = '';
  @Watch('syncEntryDisplacementFromProps')
  @Prop entryDisplacementSettlingEnabled: boolean = false;
  @Prop interactionEnabled: boolean = true;
  @Prop sideEntryAnimationEnabled: boolean = true;
  @Prop viewportLeft: number = 0;
  @Prop viewportTop: number = 0;
  @Prop viewportWidth: number = 390;
  @Prop viewportHeight: number = 844;
  @Prop topSafeInsetVp: number = 0;
  @Prop backdropBlurRadius: number = 0;
  @Prop backgroundTintEnabled: boolean = true;
  @Prop backgroundSurfaceOpacity: number = -1;
  @Prop layerOpacity: number = 1;
  @Prop homeExitProgress: number = 0;
  @Prop exiting: boolean = false;
  @Prop blurPrivateTabPreviews: boolean = true;
  @Prop panelPageBackgroundColor: ResourceColor | undefined = undefined;
  @Prop panelSecondaryTextColor: ResourceColor | undefined = undefined;
  @Prop regularChromeIconTone: AppChromeIconTone = 'light';
  @Watch('startCloseAllTabsAnimationFromRequest')
  @Prop closeAllTabsAnimationRequestVersion: number = 0;
  @Prop entrySharedSnapshotMounted: boolean = false;
  @Prop entrySharedSnapshotState: BrowserTabsSharedSnapshotTransitionState =
    new BrowserTabsSharedSnapshotTransitionCoordinator().buildIdleState();
  @Prop entrySharedSnapshotBackgroundColor: ResourceColor | undefined = undefined;

  @State private selectedSection: BrowserTabsOverviewSection = 'tabs';
  @State private layoutState: BrowserTabsOverviewLayoutState =
    new BrowserTabsOverviewLayoutViewModel().buildState({
      gridWidth: 0,
      sheetWidth: 360,
      sheetHeight: 844,
      layoutStyle: 'grid'
    });
  @State private entryProgress: number = 0;
  @State private removalState: BrowserTabsOverviewLocalRemovalState =
    new BrowserTabsOverviewShadowViewModel().buildInitialLocalRemovalState();
  @State private lateMountEntryAnimationEnabled: boolean = false;
  @State private entryDisplacementProgress: number = 1;
  @State private closeAllExitActive: boolean = false;
  @State private siteIconStates: SiteIconListRenderState[] = [];
  @State private chromeMounted: boolean = false;

  private scroller: Scroller = new Scroller();
  private bottomScrollTimer: number = 0;
  private entryAnimationTimer: number = 0;
  private lateMountEntryAnimationTimer: number = 0;
  private closeAllCommitTimer: number = 0;
  private entryTargetReadyTimer: number = 0;
  private chromeMountTimer: number = 0;
  private entryDisplacementTargetId: string = '';
  private entryReturnTabId: string = '';
  private handledCloseAllRequestVersion: number = 0;
  private entryTargetPreparationState: BrowserTabsFloatingEntryTargetPreparationState =
    new BrowserTabsFloatingEntryTargetCoordinator().buildIdleState();
  private layoutViewModel: BrowserTabsOverviewLayoutViewModel = new BrowserTabsOverviewLayoutViewModel();
  private shadowViewModel: BrowserTabsOverviewShadowViewModel = new BrowserTabsOverviewShadowViewModel();
  private overlayViewModel: BrowserTabsOverlayViewModel = new BrowserTabsOverlayViewModel();
  private animationViewModel: BrowserTabsOverlayAnimationViewModel = new BrowserTabsOverlayAnimationViewModel();
  private sectionPolicy: BrowserTabsOverviewSectionPolicy = new BrowserTabsOverviewSectionPolicy();
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

  aboutToAppear(): void {
    this.selectedSection = this.activeSection;
    this.entryReturnTabId = this.activeTabId.trim();
    this.syncLayoutState();
    this.entryProgress = this.resolveEntryInitialProgress();
    this.entryDisplacementTargetId = this.entryDisplacementTabId.trim();
    this.entryDisplacementProgress = this.resolveEntryDisplacementInitialProgress();
    this.entryTargetPreparationState =
      this.entryTargetCoordinator.clearPreviewRectCache(this.entryTargetPreparationState);
    this.resetEntryTargetPreparation();
    this.beginEntryTargetPreparationIfNeeded();
    this.removalState = this.shadowViewModel.buildInitialLocalRemovalState();
    this.overlayViewModel.bindIdentityIconUpdates(
      (): BrowserTabsOverviewIdentityIconSnapshot => this.buildIdentityIconSnapshot(),
      (states: SiteIconListRenderState[]): void => {
        this.siteIconStates = states;
      }
    );
    this.syncEntryDisplacementFromProps();
    this.prepareBottomEntryAnimation();
    // Resolve identity icons before the grid is first built. The grid is keyed by tab
    // id, so a later @State update would not repaint already-built cards and every
    // favicon would stay on its letter fallback.
    this.syncSiteIcons();
    // HDS segmented tabs, the blurred material bar and the corner buttons add a large
    // native subtree on top of the grid. Mount them on the next frame so the first
    // frame stays cheap: it blocks the main thread, so this timer only runs once the
    // grid has been laid out.
    this.chromeMountTimer = setTimeout(() => {
      this.chromeMountTimer = 0;
      this.chromeMounted = true;
    }, 0);
  }

  aboutToDisappear(): void {
    this.clearBottomScrollTimer();
    this.clearEntryAnimationTimer();
    this.clearLateMountEntryAnimationTimer();
    this.clearCloseAllCommitTimer();
    this.clearEntryTargetReadyTimer();
    if (this.chromeMountTimer > 0) {
      clearTimeout(this.chromeMountTimer);
      this.chromeMountTimer = 0;
    }
    this.overlayViewModel.disposeIdentityIcons();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildBackgroundDismissLayer()

      this.buildCardsLayer()

      if (this.isSelectedSectionEmpty()) {
        this.buildEmptyStateLayer()
        this.buildEmptyDismissLayer()
      }

      if (this.entrySharedSnapshotMounted) {
        BrowserTabsSharedSnapshotOverlay({
          state: this.entrySharedSnapshotState,
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
          }
        })
      }

      if (this.chromeMounted) {
        BrowserTabsOverviewClearButton({
          selectedSection: this.selectedSection,
          viewportWidth: this.resolveRootWidth(),
          topSafeInsetVp: this.topSafeInsetVp,
          surfaceOpacity: this.resolveClearButtonOpacity(),
          interactionEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive,
          regularChromeIconTone: this.regularChromeIconTone,
          adaptiveForeground: true,
          onClearAll: () => {
            this.onRequestCloseAll();
          }
        })
        .zIndex(FLOATING_TABS_CLEAR_BUTTON_Z_INDEX)

        if (this.selectedSection === 'tabs') {
          BrowserTabsOverviewDeviceButton({
            topSafeInsetVp: this.topSafeInsetVp,
            surfaceOpacity: this.resolveClearButtonOpacity(),
            interactionEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive,
            regularChromeIconTone: this.regularChromeIconTone,
            adaptiveForeground: true,
            onOpenDeviceTabs: () => {
              this.onOpenDeviceTabs();
            }
          })
          .zIndex(FLOATING_TABS_DEVICE_BUTTON_Z_INDEX)
        }

        if (this.shouldShowBottomChrome()) {
          BrowserTabsOverviewBottomChrome({
            selectedSection: this.selectedSection,
            regularTabsLabel: this.buildBottomChromeState().regularTabsLabel,
            viewportWidth: this.resolveRootWidth(),
            viewportHeight: this.resolveRootHeight(),
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
            }
          })
          .zIndex(FLOATING_TABS_BOTTOM_CHROME_Z_INDEX)
        }
      }
    }
    .width(this.resolveRootWidth())
    .height(this.resolveRootHeight())
    .opacity(this.resolveLayerOpacity())
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
  private buildCardsLayer() {
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      this.buildHorizontalCardsLayer()
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
      }, (item: BrowserTabsFloatingItem) => item.id)

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
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
      HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
  }

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
        .width(this.resolveCardWidth(item))
        .height(this.resolveRootHeight())
        .clip(false)
      }, (item: BrowserTabsFloatingItem) => item.id)
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
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
    .hitTestBehavior((this.interactionEnabled && !this.closeAllExitActive) ?
      HitTestMode.Transparent : HitTestMode.None)
    .zIndex(FLOATING_TABS_CARDS_Z_INDEX)
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

  @Builder
  private buildCard(item: BrowserTabsFloatingItem) {
    BrowserTabOverviewItem({
      tab: item.tab,
      presentation: item.presentation,
      snapshotImageUri: item.presentation.preview.sharedSnapshotImageUri,
      snapshotPixelMap: item.presentation.preview.sharedSnapshotPixelMap,
      snapshotAspectFitEnabled: this.layoutState.layoutStyle === 'horizontal_cards',
      previewHeight: this.resolveCardHeight(item),
      cardWidth: this.resolveCardWidth(item),
      identityHeaderHeight: this.layoutState.identityHeaderHeight,
      identityPreviewGap: this.layoutState.identityPreviewGap,
      tabTranslateX: this.resolveCardTranslateX(item),
      tabTranslateY: this.resolveCardTranslateY(item),
      tabScale: this.resolveCardScale(item),
      tabOpacity: this.resolveCardOpacity(item),
      identityOpacity: this.resolveIdentityMotion(item).opacity,
      identityTranslateY: this.resolveIdentityMotion(item).translateY,
      previewCardOpacity: 1,
      snapshotImageOpacity: 1,
      decorationOpacity: 1,
      coveredByMorph: this.isMorphCoveredTab(item.tab.id),
      tabEnabled: this.interactionEnabled && !this.exiting && !this.closeAllExitActive &&
        !this.isSelectionDisplacementActive() &&
        !this.isMorphCoveredTab(item.tab.id),
      trackPreviewRectChanges: true,
      motionDurationMs: this.resolveCardMotionDurationMs(),
      motionCurve: this.resolveCardMotionCurve(),
      motionDelayMs: this.resolveCardMotionDelayMs(item.index),
      entryMountAnimationEnabled: this.shouldRunLateMountEntryAnimation(item),
      entryMountOffsetX: this.resolveLateMountEntryOffsetX(item),
      entryMountDurationMs: this.animationViewModel.getFloatingCardEntryDurationMs(),
      entryMountCurve: this.animationViewModel.getFloatingCardEntryCurve(),
      entryMountDelayMs: this.resolveCardMotionDelayMs(item.index),
      swipeDismissThreshold: 96,
      swipeFlyoutOffset: this.resolveRootWidth(),
      swipeDismissMode: this.layoutState.layoutStyle === 'horizontal_cards' ? 'upward' : 'horizontal',
      closeButtonEnabled: true,
      closeButtonAlwaysVisible: this.storedTabsOverviewCloseButtonAlwaysVisible,
      onCloseTab: (tabId: string) => {
        this.closeTabFromOverlay(tabId);
      },
      onSwipeEnd: (tabId: string, _offsetX: number, _direction: number) => {
        this.closeTabFromOverlay(tabId);
      },
      onSwipeThresholdReached: (_tabId: string) => {
        this.performSwipeThresholdFeedback();
      },
      onSelect: (tabId: string, rect?: BrowserTabOverviewCardSelectRect) => {
        this.onSelectTab(tabId, rect);
      },
      onPreviewRectChange: (tabId: string, left: number, top: number, width: number, height: number) => {
        this.handlePreviewRectChange(tabId, left, top, width, height);
      }
    })
    .width(this.resolveCardWidth(item))
    .height(this.resolveItemHeight(item))
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
    this.scroller.scrollToIndex(targetIndex, false, ScrollAlign.CENTER);
    this.scheduleEntryTargetReady(targetTabId, 0, this.entryTargetPreparationState.version);
  }

  private scrollToBottomForEntry(): void {
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      const activeTabIndex = this.resolveDisplacementTargetIndex(this.activeTabId);
      if (activeTabIndex >= 0) {
        this.scroller.scrollToIndex(activeTabIndex, false, ScrollAlign.CENTER);
        return;
      }
    }
    const lastItemIndex = this.resolveVisibleItems().length - 1;
    if (lastItemIndex < 0) {
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

  private switchSection(section: BrowserTabsOverviewSection): void {
    if (this.closeAllExitActive) {
      return;
    }
    if (this.selectedSection === section) {
      this.onSwitchSectionHome(section);
      return;
    }
    this.selectedSection = section;
    this.onActiveSectionChange(section);
    this.syncSiteIcons();
    this.clearEntryAnimationTimer();
    this.clearLateMountEntryAnimationTimer();
    this.entryProgress = 1;
    this.removalState = this.shadowViewModel.buildInitialLocalRemovalState();
    this.prepareSectionSwitchPosition();
  }

  private returnToEntryTab(): void {
    const state = this.buildBottomChromeState();
    if (state.returnKind === 'tab' && state.returnTabId.length > 0) {
      this.onSelectTab(state.returnTabId);
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
    animateTo({
      duration: FLOATING_TABS_REORDER_DURATION_MS,
      curve: this.animationViewModel.getFloatingCardEntryCurve()
    }, () => {
      this.removalState = this.shadowViewModel.markLocalRemoval(this.removalState, tabId);
    });
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

  private isSelectedSectionEmpty(): boolean {
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

  private isLocallyRemovedTab(tabId: string): boolean {
    return this.shadowViewModel.isLocallyRemoved(this.removalState, tabId);
  }

  private syncLocalRemovalStateFromTabs(): void {
    this.removalState = this.shadowViewModel.reconcileLocalRemovalState(this.removalState, this.tabs);
  }

  private handleTabsChanged(): void {
    this.syncLocalRemovalStateFromTabs();
    this.syncSiteIcons();
  }

  private syncSiteIcons(): void {
    this.overlayViewModel.syncIdentityIcons(
      (): BrowserTabsOverviewIdentityIconSnapshot => this.buildIdentityIconSnapshot(),
      (states: SiteIconListRenderState[]): void => {
        this.siteIconStates = states;
      }
    );
    // Memory-cached icons resolve synchronously inside syncIdentityIcons, so this
    // count reflects what the first grid build will actually see. If it trails the
    // number of visible cards on a cold start, the card favicons will fall back.
    hilog.info(TABS_OVERLAY_LOG_DOMAIN, TABS_OVERLAY_LOG_TAG,
      'identity icons ready_at_build resolved=%{public}d visible=%{public}d',
      this.countResolvedSiteIcons(), this.resolveVisibleItems().length);
  }

  private countResolvedSiteIcons(): number {
    return this.siteIconStates.filter((state: SiteIconListRenderState): boolean =>
      state.path.trim().length > 0 || state.pixelMap !== undefined).length;
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
    const rect: BrowserTabsOverlayRect = {
      left: left,
      top: top,
      width: width,
      height: height
    };
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
    const visibleTabIds = this.resolveVisibleTabIds();
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      if (visibleTabIds.indexOf(targetTabId) < 0) {
        return undefined;
      }
      const targetItem = this.resolveVisibleItem(targetTabId);
      const targetWidth = targetItem === undefined ? this.layoutState.cardWidth : this.resolveCardWidth(targetItem);
      const targetHeight = targetItem === undefined ? this.layoutState.previewHeight : this.resolveCardHeight(targetItem);
      const targetItemHeight = targetItem === undefined ? this.layoutState.itemHeight : this.resolveItemHeight(targetItem);
      const contentPadding = this.resolveHorizontalContentPadding();
      const topPadding = contentPadding.top;
      const bottomPadding = contentPadding.bottom;
      const availableHeight = Math.max(1, this.resolveRootHeight() - topPadding - bottomPadding);
      const usableWidth = Math.max(1, this.resolveRootWidth() - FLOATING_TABS_HORIZONTAL_PADDING * 2);
      return {
        left: this.resolveRootLeft() + FLOATING_TABS_HORIZONTAL_PADDING +
          Math.max(0, (usableWidth - targetWidth) / 2),
        top: this.resolveRootTop() + topPadding +
          Math.max(0, (availableHeight - targetItemHeight) / 2) +
          this.layoutState.identityHeaderHeight + this.layoutState.identityPreviewGap,
        width: targetWidth,
        height: targetHeight
      };
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
      layoutStyle: this.storedTabsOverviewLayoutStyle
    });
    // onAreaChange calls this on every layout pass. Re-assigning an equal @State
    // object forces another grid re-render, so keep the current object when the
    // resolved geometry is unchanged.
    if (isSameTabsOverviewLayoutState(this.layoutState, nextState)) {
      return;
    }
    this.layoutState = nextState;
  }

  private handleStoredTabsOverviewLayoutStyleChanged(): void {
    const previousStyle = this.layoutState.layoutStyle;
    this.syncLayoutState();
    if (previousStyle === this.layoutState.layoutStyle) {
      return;
    }
    this.entryTargetPreparationState =
      this.entryTargetCoordinator.clearPreviewRectCache(this.entryTargetPreparationState);
    this.clearBottomScrollTimer();
    this.bottomScrollTimer = setTimeout(() => {
      this.bottomScrollTimer = 0;
      if (!this.exiting) {
        this.scrollToBottomForEntry();
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
      return this.resolveLeftFlyOffsetX(item.index);
    }
    const homeExitProgress = this.resolveHomeExitProgress();
    if (homeExitProgress > 0) {
      return this.resolveLeftFlyOffsetX(item.index) * homeExitProgress;
    }
    if (!this.sideEntryAnimationEnabled) {
      return 0;
    }
    const progress = this.resolveSurfaceProgress();
    return this.resolveLeftFlyOffsetX(item.index) * (1 - progress);
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
      return 0.98;
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
    return this.lateMountEntryAnimationEnabled &&
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
    return this.resolveLeftFlyOffsetX(item.index) * this.resolveSurfaceProgress();
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

  private resolveClearButtonOpacity(): number {
    return this.resolveBottomChromeOpacity();
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

  private isMorphCoveredTab(tabId: string): boolean {
    const coveredTabId = this.resolveMorphCoveredTabId();
    return coveredTabId.length > 0 && coveredTabId === tabId;
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
    return this.selectionDisplacementCoordinator.resolveDisplacement({
      tabId: item.tab.id,
      itemIndex: item.index,
      selectedTabId: this.selectionDisplacementTabId,
      selectedIndex: this.resolveSelectionDisplacementIndex(),
      columnCount: this.resolveDisplacementColumnCount(),
      cardWidth: this.resolveCardWidth(item),
      itemHeight: this.resolveItemHeight(item),
      gridGap: this.layoutState.gridGap
    });
  }

  private resolveSelectionDisplacementIndex(): number {
    return this.resolveDisplacementTargetIndex(this.selectionDisplacementTabId);
  }

  private resolveEntryDisplacement(item: BrowserTabsFloatingItem): BrowserTabsOverviewSelectionDisplacement {
    return this.selectionDisplacementCoordinator.resolveDisplacement({
      tabId: item.tab.id,
      itemIndex: item.index,
      selectedTabId: this.entryDisplacementTabId,
      selectedIndex: this.resolveEntryDisplacementIndex(),
      columnCount: this.resolveDisplacementColumnCount(),
      cardWidth: this.resolveCardWidth(item),
      itemHeight: this.resolveItemHeight(item),
      gridGap: this.layoutState.gridGap
    });
  }

  private resolveDisplacementColumnCount(): number {
    if (this.layoutState.layoutStyle === 'horizontal_cards') {
      return Math.max(1, this.resolveVisibleItems().length);
    }
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

  private resolveVisibleItem(tabId: string): BrowserTabsFloatingItem | undefined {
    const targetTabId = tabId.trim();
    for (const item of this.resolveVisibleItems()) {
      if (item.tab.id === targetTabId) {
        return item;
      }
    }
    return undefined;
  }

  private resolveCardWidth(item: BrowserTabsFloatingItem): number {
    if (this.layoutState.layoutStyle !== 'horizontal_cards') {
      return this.layoutState.cardWidth;
    }
    return this.resolveHorizontalCardFrame(item).width;
  }

  private resolveCardHeight(item: BrowserTabsFloatingItem): number {
    if (this.layoutState.layoutStyle !== 'horizontal_cards') {
      return this.layoutState.previewHeight;
    }
    return this.resolveHorizontalCardFrame(item).height;
  }

  private resolveHorizontalCardFrame(item: BrowserTabsFloatingItem): BrowserTabsOverviewHorizontalCardFrame {
    return this.layoutViewModel.resolveHorizontalCardFrame({
      maxWidth: this.layoutState.cardWidth,
      maxHeight: this.layoutState.previewHeight,
      snapshotWidth: item.presentation.preview.sharedSnapshotImageWidth,
      snapshotHeight: item.presentation.preview.sharedSnapshotImageHeight
    });
  }

  private resolveItemHeight(item: BrowserTabsFloatingItem): number {
    return this.resolveCardHeight(item) + this.layoutState.identityHeaderHeight +
      this.layoutState.identityPreviewGap;
  }

  private resolveHorizontalEdgeInset(first: boolean): number {
    const items = this.resolveVisibleItems();
    if (items.length <= 0) {
      return this.layoutState.horizontalContentInset;
    }
    const edgeItem = first ? items[0] : items[items.length - 1];
    const usableWidth = Math.max(1, this.resolveRootWidth() - FLOATING_TABS_HORIZONTAL_PADDING * 2);
    return Math.max(0, (usableWidth - this.resolveCardWidth(edgeItem)) / 2);
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
