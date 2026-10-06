import { BrowserToolbarPreview } from './BrowserToolbarPreview';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserSplitToolbarButtonRow } from '../browser/BrowserSplitToolbarChrome';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarChromeStyle,
  BrowserToolbarLayoutSettings
} from '../../../common/models/BrowserModels';
import {
  isSplitFamilyStyle,
  resolveScrollTopImmersionFooter,
  resolveSplitToolbarScrollBehavior,
  resolveTopImmersionPreference,
  shouldShowAlwaysTopImmersionSetting,
  shouldShowToolbarTopImmersionSettings,
  ToolbarTopImmersionPreference,
  ToolbarTopImmersionSwitch
} from '../../../core/browser/BrowserToolbarChromeStylePolicy';
import {
  BrowserToolbarScrollBehaviorOptionState,
  BrowserToolbarScrollBehaviorSettingsViewModel
} from '../../../core/settings/BrowserToolbarScrollBehaviorSettingsViewModel';
import {
  BrowserToolbarCenterCapsuleSwipeUpOptionState,
  BrowserToolbarCustomizationState,
  BrowserToolbarCustomizationViewModel,
  BrowserToolbarInteractionActionId,
  BrowserToolbarInteractionActionState,
  BrowserToolbarInteractionKind,
  BrowserToolbarSlotActionState,
  BrowserToolbarSlotInteractionState,
  BrowserToolbarSlotId
} from '../../../core/browser/BrowserToolbarCustomizationViewModel';
import { bottomPanelPinnedAs } from '../../../core/browser/BrowserBottomPanelText';
import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  BrowserSplitToolbarCustomizationViewModel,
  BrowserSplitToolbarSlotDetail
} from '../../../core/browser/BrowserSplitToolbarCustomizationViewModel';
import {
  BrowserSplitToolbarInteractionKind,
  BrowserSplitToolbarScene,
  BrowserSplitToolbarSlotId,
  isSplitToolbarSlotId
} from '../../../core/browser/BrowserSplitToolbarCustomizationPolicy';
import {
  BrowserBottomChromePresentation,
  BrowserBottomChromePresentationViewModel,
  BrowserBottomChromeTapIntent
} from '../../../core/browser/BrowserBottomChromePresentationViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AppIconResources } from '../../../core/resources/AppIconResources';
import {
  resolveBrowserBottomFloatingMaterialShadowColor,
  resolveBrowserBottomNeutralPrimaryColor,
  resolveBrowserBottomNeutralSecondaryColor,
  resolveBrowserBottomNeutralPressedColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsOptionRow,
  SettingsRowPosition,
  SettingsSwitchRow
} from './SettingsRows';
import {
  SettingsDesktopActionButton,
  SettingsDesktopDivider,
  SettingsDesktopGroup,
  SettingsDesktopNavigationRow,
  SettingsDesktopOptionRow
} from './SettingsDesktopRows';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';
import {
  BrowserToolbarCustomizationBoundary,
  BrowserToolbarCustomizationCoordinator
} from '../../../core/browser/BrowserToolbarCustomizationCoordinator';
import {
  resolveBrowserBottomChromeEdgeHighlightColor,
  resolveBrowserBottomChromeMaterialTintForMode
} from '../browser/BrowserFloatingGlassMaterialTokens';
import {
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS,
  BrowserImmersiveSheetLayout,
  BrowserSheetIconButton,
  browserSheetHeaderBlurModifier
} from '../browser/BrowserModalBottomSheet';
import { BrowserPhoneSettingsSheetHeader } from '../browser/BrowserPhoneSettingsSheetHeader';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';

const TOOLBAR_NEUTRAL_PRESSED_BACKGROUND: string = '#14000000';
const TOOLBAR_PREVIEW_HEIGHT: number = 52;
const TOOLBAR_PREVIEW_SECTION_HEIGHT: number = 12 + TOOLBAR_PREVIEW_HEIGHT + 12;
const TOOLBAR_SLOT_RADIO_GROUP_PREFIX: string = 'browser-toolbar-slot-action';
const TOOLBAR_CENTER_CAPSULE_RADIO_GROUP: string = 'browser-toolbar-center-capsule-swipe-up';
const TOOLBAR_SLOT_PICKER_DESTINATION: string = 'toolbarSlotActionPicker';
/**
 * pop() and the overview @State write share one click. Navigation drops that write, so the
 * label is republished after the slide if the home-page callback does not run.
 */
const TOOLBAR_SHEET_OVERVIEW_REFRESH_FALLBACK_MS: number = 480;
/**
 * Half-modal title bar from HdsNavigationTitleMode.MODAL: 8vp top padding, 56vp bar, 64vp backplate.
 * The 40vp button is centered in that bar, so it starts 16vp below the sheet content, level with close.
 */
const TOOLBAR_SHEET_MODAL_TOP_PADDING: number = 8;
const TOOLBAR_SHEET_MODAL_TITLE_BAR_HEIGHT: number = 56;
const TOOLBAR_SHEET_HEADER_BUTTON_SIZE: number = 40;
const TOOLBAR_SHEET_HEADER_BUTTON_TOP: number = TOOLBAR_SHEET_MODAL_TOP_PADDING +
  (TOOLBAR_SHEET_MODAL_TITLE_BAR_HEIGHT - TOOLBAR_SHEET_HEADER_BUTTON_SIZE) / 2;
const TOOLBAR_SHEET_CONTENT_TOP_INSET: number =
  TOOLBAR_SHEET_MODAL_TOP_PADDING + TOOLBAR_SHEET_MODAL_TITLE_BAR_HEIGHT;
/** GRADIENT_BLUR default: blur fades in over the first 8vp of scroll, and is absent at rest. */
const TOOLBAR_SHEET_BLUR_SCROLL_RANGE_VP: number = 8;
/** Which question the toolbar's single Sheet is asking. */
type BrowserToolbarSheetQuestion = 'slot' | 'center_capsule' | 'split_slot';
export type BrowserToolbarDesktopView = 'overview' | 'scroll_behavior';

class ToolbarSlotPickerParams {
}

/**
 * The middle-bar choice list owns the check it shows.
 *
 * The sheet home page does not repaint a parent state write made from the row click, so the
 * check stayed on the previous row until the sheet was closed and built again. A Radio group is
 * also page-scoped: recreating the rows in the same group restores that old check. Each choice
 * therefore gets a new group, and the visible selection is state on this list.
 */
@Component
struct BrowserToolbarCenterCapsuleSwipeUpOptions {
  @Prop options: BrowserToolbarCenterCapsuleSwipeUpOptionState[] = [];
  @Prop @Watch('onSelectedActionIdChanged') selectedActionId: string = 'tools';
  @Prop desktopPresentation: boolean = false;
  @Prop saving: boolean = false;
  @Prop surfaceColor: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop selectedIndicatorColor: ResourceColor = '';
  onSelect?: (actionId: string) => boolean;
  @State private displayedActionId: string = 'tools';
  @State private selectionRevision: number = 0;

  aboutToAppear(): void {
    this.displayedActionId = this.resolveIncomingActionId();
  }

  build() {
    SettingsGroupCard({
      surfaceColor: this.surfaceColor,
      desktopPresentation: this.desktopPresentation
    }) {
      ForEach(this.options, (option: BrowserToolbarCenterCapsuleSwipeUpOptionState, index: number) => {
        SettingsOptionRow({
          title: option.title,
          desktopPresentation: this.desktopPresentation,
          rowPosition: this.resolveRowPosition(index, this.options.length),
          isSelected: option.actionId === this.displayedActionId,
          isEnabled: !this.saving,
          radioGroup: `${TOOLBAR_CENTER_CAPSULE_RADIO_GROUP}-${option.actionId}-${this.selectionRevision}`,
          radioValue: option.actionId,
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          selectedIndicatorColor: this.selectedIndicatorColor,
          onAction: (): void => {
            this.selectAction(option.actionId);
          }
        })
        if (index < this.options.length - 1) {
          SettingsGroupDivider({ dividerColor: this.dividerColor })
        }
      }, (option: BrowserToolbarCenterCapsuleSwipeUpOptionState): string =>
        `${option.actionId}:${this.selectionRevision}:` +
          `${option.actionId === this.displayedActionId ? 'selected' : 'idle'}`)
    }
  }

  private onSelectedActionIdChanged(): void {
    const incoming = this.resolveIncomingActionId();
    if (incoming === this.displayedActionId) {
      return;
    }
    this.displayedActionId = incoming;
    this.selectionRevision++;
  }

  private selectAction(actionId: string): void {
    if (this.saving || actionId === this.displayedActionId) {
      return;
    }
    const previousActionId = this.displayedActionId;
    const previousRevision = this.selectionRevision;
    this.displayedActionId = actionId;
    this.selectionRevision++;
    if (this.onSelect?.(actionId) !== true) {
      this.displayedActionId = previousActionId;
      this.selectionRevision = previousRevision;
    }
  }

  private resolveIncomingActionId(): string {
    return this.selectedActionId === 'tabs' ? 'tabs' : 'tools';
  }

  private resolveRowPosition(index: number, count: number): SettingsRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    if (index >= count - 1) {
      return 'last';
    }
    return 'middle';
  }
}

@Component
export struct BrowserToolbarCustomizationScreen {
  private viewModel: BrowserToolbarCustomizationViewModel = new BrowserToolbarCustomizationViewModel();
  private splitViewModel: BrowserSplitToolbarCustomizationViewModel =
    new BrowserSplitToolbarCustomizationViewModel();
  private chromePresentationViewModel: BrowserBottomChromePresentationViewModel =
    new BrowserBottomChromePresentationViewModel();
  private scrollBehaviorViewModel: BrowserToolbarScrollBehaviorSettingsViewModel =
    new BrowserToolbarScrollBehaviorSettingsViewModel();
  private settingsScroller: Scroller = new Scroller();
  private customizationCoordinator: BrowserToolbarCustomizationCoordinator =
    new BrowserToolbarCustomizationCoordinator(sharedPreferencesRepository);
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#1F000000';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = TOOLBAR_NEUTRAL_PRESSED_BACKGROUND;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop showTitleBar: boolean = true;
  @Prop showBackButton: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop initialDesktopView: BrowserToolbarDesktopView = 'overview';
  @Prop showDesktopHeader: boolean = true;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  onBack?: () => void;
  onOpenScrollBehavior?: () => void;
  onSettingsChanged?: () => void;
  @State private settings: BrowserToolbarLayoutSettings =
    sharedPreferencesRepository.getPreferences().toolbarLayout;
  @State private scrollBehavior: BrowserBottomToolbarScrollBehavior =
    sharedPreferencesRepository.getPreferences().appearance.bottomToolbarScrollBehavior;
  @State private toolbarChromeStyle: BrowserToolbarChromeStyle =
    sharedPreferencesRepository.getPreferences().appearance.toolbarChromeStyle;
  @State private webBottomSafeAreaEnabled: boolean =
    sharedPreferencesRepository.getPreferences().experiments.webBottomSafeAreaEnabled;
  @State private globalImmersionEnabled: boolean =
    sharedPreferencesRepository.getPreferences().appearance.globalImmersionEnabled;
  @State private alwaysTopImmersionEnabled: boolean =
    sharedPreferencesRepository.getPreferences().appearance.alwaysTopImmersionEnabled;
  @State private state: BrowserToolbarCustomizationState =
    this.viewModel.buildState(sharedPreferencesRepository.getPreferences().toolbarLayout);
  @State private saving: boolean = false;
  /**
   * The width the toolbar preview is laid out at, or 0 before the first measure.
   *
   * Zero means "not measured yet" rather than "use the default": the preview is built inside a
   * `SettingsGroupCard` that knows its own width, so it can resolve the frame on its first layout pass
   * instead of building at a guessed width and re-laying out every button once the measurement lands.
   * That second pass was the toolbar preview visibly narrowing as the page settled.
   */
  @State private toolbarPreviewWidth: number = 0;
  @State private selectedSlotId: BrowserToolbarSlotId = 'leading';
  @State private splitPreviewScene: BrowserSplitToolbarScene = 'home';
  @State private selectedSplitSlotId: BrowserSplitToolbarSlotId = 'homeLeading';
  @State private selectedInteractionKind: BrowserToolbarInteractionKind = 'tap';
  /**
   * One Sheet, two questions, and a stack for the choice under a question.
   *
   * A node can only host one sheet, and this screen needs a sheet for the four configurable buttons
   * and one for the middle bar, which has no slot of its own. Binding two sheets to this page left
   * only one of them reachable, so the question is state and the sheet itself is single.
   * The action list is a NavDestination on this stack, not a rebuilt builder: pushPath is the system
   * slide, and back pops that destination before the sheet can dismiss.
   * A @State write in that same click does not repaint this home page, so the overview is
   * republished once the home page is current again.
   */
  private sheetNavigationStack: NavPathStack = new NavPathStack();
  private sheetNavigationPopGuardUntilMs: number = 0;
  private sheetOverviewDisposed: boolean = false;
  private sheetOverviewRefreshGeneration: number = 0;
  private sheetRootScroller: Scroller = new Scroller();
  private sheetPickerScroller: Scroller = new Scroller();
  @State private sheetRootBlurRadius: number = 0;
  @State private sheetPickerBlurRadius: number = 0;
  @State private sheetQuestion: BrowserToolbarSheetQuestion = 'slot';
  @State private sheetVisible: boolean = false;
  /** Bumped after the picker returns, so the covered overview reads the action that was just saved. */
  @State private sheetOverviewRevision: number = 0;
  @State private desktopView: BrowserToolbarDesktopView = 'overview';
  /**
   * Resolved once instead of per render.
   *
   * `buildStateForBehavior` allocates a fresh options array and a fresh footer string every call, and
   * the scroll-behaviour pane called it three times per option on every render — once for the `ForEach`
   * source and twice more inside the loop and the divider condition.
   */
  private scrollBehaviorOptions: BrowserToolbarScrollBehaviorOptionState[] =
    this.scrollBehaviorViewModel.buildState(
      sharedPreferencesRepository.getPreferences().appearance).options;
  private scrollBehaviorFooterText: ResourceStr =
    this.scrollBehaviorViewModel.buildState(
      sharedPreferencesRepository.getPreferences().appearance).footerText;
  /**
   * The preview's presentation, kept until its width or the slot actions change.
   *
   * `buildPresentation` assembles a large object — the frame, the compact frame and ten tap targets —
   * and the preview asks for it on every render, including the render the first width measurement
   * triggers. Both inputs are cheap to compare: the width is a number and `state` is reassigned
   * wholesale whenever the settings change, so a reference check is a correct invalidation.
   */
  private previewPresentationCache: BrowserBottomChromePresentation | undefined = undefined;
  private previewPresentationWidth: number = 0;
  private previewPresentationState: BrowserToolbarCustomizationState | undefined = undefined;

  aboutToAppear(): void {
    this.desktopView = this.initialDesktopView;
    this.refreshState();
    this.sheetNavigationStack.setInterception({
      didShow: (_from: NavDestinationContext | 'navBar', to: NavDestinationContext | 'navBar',
        _operation: NavigationOperation, _animated: boolean): void => {
        if (typeof to !== 'string') {
          return;
        }
        this.scheduleSheetOverviewRefresh(0, this.sheetOverviewRefreshGeneration);
      }
    });
  }

  aboutToDisappear(): void {
    this.sheetOverviewDisposed = true;
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        this.buildDesktopWorkspace()
      } else {
        this.buildTouchPage()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.sheetVisible, this.buildActiveSheet(), applyDesktopDialogSheetChrome({
      preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: !this.desktopPresentation,
      showClose: false,
      onWillDismiss: (action: DismissSheetAction): void => {
        this.handleSheetWillDismiss(action);
      },
      onDisappear: () => {
        this.sheetVisible = false;
        this.sheetQuestion = 'slot';
        this.resetSheetNavigation();
      }
    }, 'm', this.desktopPresentation))
  }

  @Builder
  private buildTouchPage() {
    SettingsHdsScaffold({
      title: $r('app.string.toolbar_settings_title'),
      backIconKind: 'back',
      showTitleBar: this.showTitleBar,
      showBackButton: this.showBackButton,
      useTopSafeInset: this.useTopSafeInset,
      pageBackground: this.resolvePageBackgroundColor(),
      headerButtonBackground: this.resolvePressedBackgroundColor(),
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      contentKind: 'canvas',
      scrollers: [this.settingsScroller],
      onBack: () => {
        this.onBack?.();
      }
    }) {
      this.buildToolbarContent()
    }
  }

  @Builder
  private buildDesktopWorkspace() {
    Column() {
      if (this.showDesktopHeader) {
        SettingsDesktopWorkspaceHeader({
          title: this.desktopView === 'scroll_behavior' ? $r('app.string.toolbar_settings_scroll_title') : $r('app.string.toolbar_settings_title'),
          showBackButton: this.desktopView === 'scroll_behavior',
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.resolvePressedBackgroundColor(),
          onBack: () => {
            this.desktopView = 'overview';
          }
        })
      }

      if (this.desktopView === 'scroll_behavior') {
        this.buildScrollBehaviorContent()
      } else {
        this.buildToolbarContent()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolvePageBackgroundColor())
  }

  @Builder
  private buildToolbarContent() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      bottomPadding: 32,
      scrollEnabled: true,
      scroller: this.settingsScroller
    }) {
      this.buildToolbarStyleSection()
      this.buildToolbarPreviewSection()
      this.buildToolbarBehaviorSection()
      if (this.shouldShowTopImmersionSettings()) {
        this.buildTopImmersionSection()
      }
      if (this.shouldShowWebBottomSafeAreaSwitch()) {
        this.buildWebBottomSafeAreaSection()
      }
      if (this.hasCustomizedToolbarSlots()) {
        this.buildResetButton()
      }
    }
  }

  @Builder
  private buildScrollBehaviorContent() {
    SettingsPresentationScrollBody({
      desktopPresentation: true,
      topPadding: 8,
      bottomPadding: 28
    }) {
      SettingsSection({
        title: $r('app.string.toolbar_settings_browsing_section'),
        secondaryTextColor: this.storedSecondaryTextColor
      }) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          ForEach(this.scrollBehaviorOptions, (
            option: BrowserToolbarScrollBehaviorOptionState,
            index: number
          ) => {
            SettingsDesktopOptionRow({
              title: option.title,
              isSelected: this.isScrollBehaviorOptionSelected(option.behavior),
              isEnabled: !this.saving,
              radioGroup: 'browser-toolbar-scroll-behavior-workspace',
              radioValue: option.behavior,
              primaryTextColor: this.storedPrimaryTextColor,
              secondaryTextColor: this.storedSecondaryTextColor,
              hoverBackgroundColor: this.resolvePressedBackgroundColor(),
              focusColor: this.storedAccentColor,
              onAction: () => {
                this.updateScrollBehavior(option.behavior);
              }
            })
            if (index < this.scrollBehaviorOptions.length - 1) {
              SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
            }
          }, (option: BrowserToolbarScrollBehaviorOptionState) => `toolbar-scroll-workspace-${option.behavior}`)
        }
        SettingsFooterText({
          text: this.scrollBehaviorFooterText,
          secondaryTextColor: this.storedSecondaryTextColor
        })
      }
    }
  }

  @Builder
  private buildToolbarStyleSection() {
    SettingsSection({
      title: $r('app.string.toolbar_settings_style_section'),
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsDesktopOptionRow({
            title: $r('app.string.toolbar_settings_style_floating'),
            isSelected: this.toolbarChromeStyle === 'floating',
            isEnabled: !this.saving,
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'floating',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            hoverBackgroundColor: this.resolvePressedBackgroundColor(),
            focusColor: this.storedAccentColor,
            onAction: () => {
              this.updateToolbarChromeStyle('floating');
            }
          })
          SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
          SettingsDesktopOptionRow({
            title: $r('app.string.toolbar_settings_style_split'),
            isSelected: this.toolbarChromeStyle === 'split',
            isEnabled: !this.saving,
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'split',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            hoverBackgroundColor: this.resolvePressedBackgroundColor(),
            focusColor: this.storedAccentColor,
            onAction: () => {
              this.updateToolbarChromeStyle('split');
            }
          })
          SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
          SettingsDesktopOptionRow({
            title: $r('app.string.toolbar_settings_style_dock'),
            isSelected: this.toolbarChromeStyle === 'dock',
            isEnabled: !this.saving,
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'dock',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            hoverBackgroundColor: this.resolvePressedBackgroundColor(),
            focusColor: this.storedAccentColor,
            onAction: () => {
              this.updateToolbarChromeStyle('dock');
            }
          })
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsOptionRow({
            title: $r('app.string.toolbar_settings_style_floating'),
            isSelected: this.toolbarChromeStyle === 'floating',
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'floating',
            rowPosition: 'first',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.resolvePressedBackgroundColor(),
            onAction: () => {
              this.updateToolbarChromeStyle('floating');
            }
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsOptionRow({
            title: $r('app.string.toolbar_settings_style_split'),
            isSelected: this.toolbarChromeStyle === 'split',
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'split',
            rowPosition: 'middle',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.resolvePressedBackgroundColor(),
            onAction: () => {
              this.updateToolbarChromeStyle('split');
            }
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          SettingsOptionRow({
            title: $r('app.string.toolbar_settings_style_dock'),
            isSelected: this.toolbarChromeStyle === 'dock',
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'dock',
            rowPosition: 'last',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.resolvePressedBackgroundColor(),
            onAction: () => {
              this.updateToolbarChromeStyle('dock');
            }
          })
        }
      }
      SettingsFooterText({
        text: $r('app.string.toolbar_settings_style_footer'),
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildToolbarBehaviorSection() {
    SettingsSection({
      title: $r('app.string.toolbar_settings_behavior_section'),
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsDesktopNavigationRow({
            title: $r('app.string.toolbar_settings_scroll_title'),
            value: this.scrollBehaviorViewModel.formatBehaviorTitle(
              this.scrollBehavior,
              this.toolbarChromeStyle
            ),
            isEnabled: !this.saving,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            hoverBackgroundColor: this.resolvePressedBackgroundColor(),
            focusColor: this.storedAccentColor,
            onAction: (): void => {
              this.desktopView = 'scroll_behavior';
            }
          })
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsNavigationRow({
            title: $r('app.string.toolbar_settings_scroll_title'),
            value: this.scrollBehaviorViewModel.formatBehaviorTitle(
              this.scrollBehavior,
              this.toolbarChromeStyle
            ),
            rowPosition: 'single',
            isEnabled: !this.saving,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.resolvePressedBackgroundColor(),
            onAction: (): void => {
              this.onOpenScrollBehavior?.();
            }
          })
        }
      }
      SettingsFooterText({
        text: this.toolbarChromeStyle === 'dock' ?
          $r('app.string.toolbar_settings_behavior_footer_dock') :
          this.toolbarChromeStyle === 'split' ?
            $r('app.string.toolbar_settings_behavior_footer_split') :
            $r('app.string.toolbar_settings_behavior_footer_floating'),
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildTopImmersionSection() {
    SettingsSection({
      title: $r('app.string.toolbar_settings_top_immersion_section'),
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: $r('app.string.toolbar_settings_scroll_top_immersion'),
          checked: this.globalImmersionEnabled,
          rowPosition: 'single',
          isEnabled: !this.saving && this.isScrollTopImmersionSwitchEnabled(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.resolvePressedBackgroundColor(),
          onChange: (checked: boolean): void => {
            this.updateTopImmersion('scroll', checked);
          }
        })
      }
      SettingsFooterText({
        text: resolveScrollTopImmersionFooter(this.toolbarChromeStyle),
        secondaryTextColor: this.storedSecondaryTextColor
      })
      if (this.shouldShowAlwaysTopImmersionSwitch()) {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsSwitchRow({
            title: $r('app.string.toolbar_settings_always_top_immersion'),
            checked: this.alwaysTopImmersionEnabled,
            rowPosition: 'single',
            isEnabled: !this.saving,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.resolvePressedBackgroundColor(),
            onChange: (checked: boolean): void => {
              this.updateTopImmersion('always', checked);
            }
          })
        }
        SettingsFooterText({
          text: $r('app.string.toolbar_settings_always_top_immersion_footer'),
          secondaryTextColor: this.storedSecondaryTextColor
        })
      }
    }
  }

  @Builder
  private buildWebBottomSafeAreaSection() {
    SettingsSection({
      title: $r('app.string.toolbar_settings_web_fit_section'),
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: $r('app.string.toolbar_settings_web_bottom_safe_area'),
          titleBadge: 'Beta',
          checked: this.webBottomSafeAreaEnabled,
          rowPosition: 'single',
          isEnabled: !this.saving,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.resolvePressedBackgroundColor(),
          onChange: (checked: boolean): void => {
            this.updateWebBottomSafeAreaEnabled(checked);
          }
        })
      }
      SettingsFooterText({
        text: $r('app.string.toolbar_settings_web_bottom_safe_area_footer'),
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildToolbarPreviewSection() {
    SettingsSection({
      title: $r('app.string.toolbar_settings_preview_section'),
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        if (this.toolbarChromeStyle === 'split') {
          this.buildSplitToolbarPreview()
        } else if (this.toolbarChromeStyle === 'dock') {
          this.buildDockToolbarPreview()
        } else {
          this.buildFloatingToolbarPreview()
        }
      }
      SettingsFooterText({
        text: this.resolvePreviewFooterText(),
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildFloatingToolbarPreview() {
    Column() {
      if (this.toolbarPreviewWidth > 1) {
        BrowserToolbarPreview({
          presentation: this.buildToolbarPreviewPresentation(),
          surfaceColor: this.storedSurfaceBackgroundColor,
          iconColor: resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode),
          textColor: resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode),
          viewportColor: resolveBrowserBottomNeutralPressedColor(this.storedResolvedThemeMode),
          edgeHighlightColor: this.resolvePreviewEdgeHighlightColor(),
          onIntent: (intent: BrowserBottomChromeTapIntent): void => {
            this.handleToolbarPreviewIntent(intent);
          }
        })
          .width('100%')
          .height(TOOLBAR_PREVIEW_HEIGHT)
      }
    }
    .width('100%')
    .height(TOOLBAR_PREVIEW_SECTION_HEIGHT)
    .padding({ top: 12, bottom: 12 })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const width = this.parseAreaDimension(newArea.width);
      if (width > 1 && Math.abs(width - this.toolbarPreviewWidth) > 1) {
        this.toolbarPreviewWidth = width;
      }
    })
  }

  @Builder
  private buildSplitToolbarPreview() {
    Column({ space: 12 }) {
      this.buildSplitSceneSwitch()
      BrowserSplitToolbarButtonRow({
        buttons: this.splitViewModel.buildPresentations(
          this.settings,
          this.splitPreviewScene,
          true,
          true
        ),
        homeScene: this.splitPreviewScene === 'home',
        tabCount: 1,
        textColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.resolvePressedBackgroundColor(),
        onTap: (slotId: string): void => {
          this.openSplitSlotSheet(slotId);
        },
        onLongPress: (slotId: string): void => {
          this.openSplitSlotSheet(slotId);
        }
      })
        .width('100%')
        .height(56)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
  }

  /**
   * The dock style paints a resting search box over a five-button row. The row shares the split web
   * bar's slots, so tapping a button opens the same customization sheet the split preview uses.
   */
  @Builder
  private buildDockToolbarPreview() {
    Column({ space: 6 }) {
      Row() {
        AiraIcon({
          airaIconId: 'browser.toolbar.search',
          iconSize: 20,
          iconColor: this.storedSecondaryTextColor
        })
        Text($r('app.string.aira_search_card_placeholder'))
          .layoutWeight(1)
          .fontSize(16)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        AiraIcon({
          airaIconId: 'browser.toolbar.scanQr',
          iconSize: 20,
          iconColor: this.storedSecondaryTextColor
        })
      }
      .width('100%')
      .height(40)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .borderRadius(20)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .shadow({ radius: 6, color: '#14000000', offsetY: 2 })

      BrowserSplitToolbarButtonRow({
        buttons: this.splitViewModel.buildDockPresentations(this.settings, true, true),
        homeScene: false,
        tabCount: 1,
        textColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        pressedBackgroundColor: this.resolvePressedBackgroundColor(),
        onTap: (slotId: string): void => {
          this.openSplitSlotSheet(slotId);
        },
        onLongPress: (slotId: string): void => {
          this.openSplitSlotSheet(slotId);
        }
      })
        .width('100%')
        .height(46)
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 12, bottom: 12 })
  }

  @Builder
  private buildSplitSceneSwitch() {
    Row() {
      this.buildSplitSceneChip('home', $r('app.string.bottom_panel_scene_home'))
      this.buildSplitSceneChip('web', $r('app.string.bottom_panel_scene_web'))
    }
    .width('100%')
    .height(36)
    .borderRadius(18)
    .clip(true)
    .padding(2)
    .backgroundColor(this.resolvePressedBackgroundColor())
  }

  @Builder
  private buildSplitSceneChip(scene: BrowserSplitToolbarScene, title: ResourceStr) {
    Button() {
      Text(title)
        .fontSize(14)
        .fontWeight(this.splitPreviewScene === scene ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.splitPreviewScene === scene ?
          this.storedPrimaryTextColor : this.storedSecondaryTextColor)
    }
    .layoutWeight(1)
    .height(32)
    .backgroundColor(this.splitPreviewScene === scene ?
      this.storedSurfaceBackgroundColor : Color.Transparent)
    .borderRadius(16)
    .type(ButtonType.Normal)
    .stateEffect(false)
    .onClick(() => {
      this.selectSplitPreviewScene(scene);
    })
  }

  @Builder
  private buildActiveSheet() {
    if (this.desktopPresentation) {
      CenteredDialogSurface({ fillHeight: true }) {
        this.buildActiveSheetContent()
      }
    } else {
      this.buildActiveSheetContent()
    }
  }

  @Builder
  private buildActiveSheetContent() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Navigation(this.sheetNavigationStack) {
        this.buildSheetRoot()
      }
      .width('100%')
      .height('100%')
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .hideToolBar(true)
      .hideNavBar(false)
      .navDestination(this.buildSheetDestination)
      .backgroundColor(this.resolveSheetNavigationBackground())
      .clip(true)

      this.buildSheetCloseButton()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSheetCloseButton() {
    BrowserSheetIconButton({
      icon: $r('sys.symbol.xmark'),
      iconSize: 20,
      buttonSize: 40,
      iconColor: this.storedPrimaryTextColor,
      accessibilityLabel: $r('app.string.ui_close'),
      immersiveMaterialEnabled: true,
      onAction: (): void => {
        this.sheetVisible = false;
      }
    })
    .margin({ top: TOOLBAR_SHEET_HEADER_BUTTON_TOP, right: 16 })
    .zIndex(3)
  }

  @Builder
  private buildSheetRoot() {
    if (this.sheetQuestion === 'center_capsule') {
      this.buildCenterCapsuleSwipeUpSheetContent()
    } else if (this.sheetQuestion === 'split_slot') {
      this.buildSplitSlotOverview()
    } else {
      this.buildSlotInteractionOverview()
    }
  }

  @Builder
  private buildSheetDestination(name: string, _param: Object) {
    if (name === TOOLBAR_SLOT_PICKER_DESTINATION) {
      NavDestination() {
        this.buildInteractionActionPicker()
      }
      .width('100%')
      .height('100%')
      .hideTitleBar(true)
      .hideToolBar(true)
      .backgroundColor(this.resolveSheetNavigationBackground())
      .onBackPressed(() => {
        this.popSheetNavigation();
        return true;
      })
    }
  }

  @Builder
  private buildToolbarSheetPage(title: ResourceStr, showBack: boolean, backLabel: ResourceStr, kind: string) {
    BrowserImmersiveSheetLayout({
      horizontalPadding: 0,
      headerTopInset: TOOLBAR_SHEET_MODAL_TOP_PADDING,
      scrollContent: (): void => {
        this.buildToolbarSheetScroll(kind)
      },
      header: (): void => {
        this.buildToolbarSheetHeader(title, showBack, backLabel)
      }
    })
  }

  @Builder
  private buildToolbarSheetHeader(title: ResourceStr, showBack: boolean, backLabel: ResourceStr) {
    BrowserPhoneSettingsSheetHeader({
      title: title,
      showBackButton: showBack,
      backAccessibilityText: backLabel,
      rowHeight: TOOLBAR_SHEET_MODAL_TITLE_BAR_HEIGHT,
      onBack: (): void => {
        this.popSheetNavigation();
      }
    })
  }

  @Builder
  private buildToolbarSheetScroll(kind: string) {
    Scroll(this.resolveSheetScroller(kind)) {
      Column({ space: kind === 'picker' ? 14 : 16 }) {
        if (kind === 'capsule') {
          this.buildCenterCapsuleSwipeUpOptionGroup(
            this.viewModel.buildCenterCapsuleSwipeUpOptions(this.settings))
        } else if (kind === 'split') {
          this.buildSplitSlotBody()
        } else if (kind === 'picker') {
          this.buildPickerBody()
        } else {
          this.buildSlotOverviewBody()
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: TOOLBAR_SHEET_CONTENT_TOP_INSET,
        bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .attributeModifier(browserSheetHeaderBlurModifier(this.resolveSheetBlurRadius(kind)))
    .onAppear(() => {
      this.updateSheetHeaderBlur(kind);
    })
    .onDidScroll(() => {
      this.updateSheetHeaderBlur(kind);
    })
    .clip(false)
  }

  /**
   * The middle bar's own question: native single-choice rows inside the group card every other
   * sheet uses. The title sits in the overlay header so the list can blur under it.
   */
  @Builder
  private buildCenterCapsuleSwipeUpSheetContent() {
    this.buildToolbarSheetPage($r('app.string.toolbar_settings_capsule_swipe_title'), false, '', 'capsule')
  }

  @Builder
  private buildCenterCapsuleSwipeUpOptionGroup(options: BrowserToolbarCenterCapsuleSwipeUpOptionState[]) {
    BrowserToolbarCenterCapsuleSwipeUpOptions({
      options: options,
      selectedActionId: this.resolveCenterCapsuleSwipeUpActionId(options),
      desktopPresentation: this.desktopPresentation,
      saving: this.saving,
      surfaceColor: this.storedSurfaceBackgroundColor,
      dividerColor: this.storedDividerColor,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      selectedIndicatorColor: this.storedAccentColor,
      onSelect: (actionId: string): boolean => {
        return this.applyCenterCapsuleSwipeUpActionId(actionId);
      }
    })
      .key('toolbar-center-capsule-swipe-up-options')
  }

  @Builder
  private buildSplitSlotOverview() {
    this.buildToolbarSheetPage(this.resolveSplitSheetTitle(), false, '', 'split')
  }

  @Builder
  private buildSplitSlotBody() {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      if (this.resolveSplitDetail().tapLocked) {
        this.buildLockedInteractionRow(this.resolveSplitDetail().tap, 'first')
      } else {
        this.buildInteractionOverviewRow(this.resolveSplitDetail().tap, 'first')
      }
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      this.buildInteractionOverviewRow(this.resolveSplitDetail().longPress, 'last')
    }

    SettingsActionButton({
      title: $r('app.string.toolbar_settings_reset_slot'),
      variant: 'tonal',
      isEnabled: this.isSplitSlotResetEnabled(),
      onAction: (): void => {
        this.resetSelectedSlotAction();
      }
    })
  }

  @Builder
  private buildLockedInteractionRow(
    interaction: BrowserToolbarSlotInteractionState,
    rowPosition: SettingsRowPosition
  ) {
    Row() {
      Text(interaction.title)
        .fontSize(this.desktopPresentation ? 15 : 16)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .layoutWeight(1)
      Text(bottomPanelPinnedAs())
      Text(interaction.action.title)
        .fontSize(this.desktopPresentation ? 13 : 14)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .padding({
      left: 16,
      right: 16,
      top: rowPosition === 'first' ? 14 : 14,
      bottom: 14
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSlotInteractionOverview() {
    this.buildToolbarSheetPage(this.resolveSelectedSlotTitle(), false, '', 'slot')
  }

  @Builder
  private buildSlotOverviewBody() {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      this.buildInteractionOverviewRow(this.resolveSelectedSlotAction().tap, 'first')
      SettingsGroupDivider({ dividerColor: this.storedDividerColor })
      if (this.resolveSelectedSlotAction().swipeUp === undefined) {
        this.buildInteractionOverviewRow(this.resolveSelectedSlotAction().longPress, 'last')
      } else {
        this.buildInteractionOverviewRow(this.resolveSelectedSlotAction().longPress, 'middle')
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        this.buildInteractionOverviewRow(
          this.resolveSelectedSlotAction().swipeUp as BrowserToolbarSlotInteractionState,
          'last'
        )
      }
    }

    SettingsActionButton({
      title: $r('app.string.toolbar_settings_reset_slot'),
      variant: 'tonal',
      isEnabled: this.isSlotResetEnabled(),
      onAction: (): void => {
        this.resetSelectedSlotAction();
      }
    })
  }

  @Builder
  private buildInteractionOverviewRow(
    interaction: BrowserToolbarSlotInteractionState,
    rowPosition: SettingsRowPosition
  ) {
    SettingsNavigationRow({
      title: interaction.title,
      desktopPresentation: this.desktopPresentation,
      value: this.resolveOverviewInteraction(interaction.kind).action.title,
      airaIconId: this.resolveOverviewInteraction(interaction.kind).action.airaIconId,
      iconColor: this.storedPrimaryTextColor,
      rowPosition,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      pressedBackgroundColor: this.resolvePressedBackgroundColor(),
      isEnabled: !this.saving,
      onAction: (): void => {
        this.openInteractionPicker(interaction.kind);
      }
    })
    .key(this.resolveOverviewRowKey(interaction.kind))
  }

  @Builder
  private buildInteractionActionPicker() {
    this.buildToolbarSheetPage(this.resolveSelectedInteraction().title, true, $r('app.string.bottom_panel_back'), 'picker')
  }

  @Builder
  private buildPickerBody() {
    if (this.resolvePickerGroup('none').length > 0) {
      this.buildPickerActionGroup($r('app.string.bottom_panel_none'), this.resolvePickerGroup('none'))
    }
    this.buildPickerActionGroup($r('app.string.bottom_panel_picker_browser'), this.resolvePickerGroup('header'))
    this.buildPickerActionGroup($r('app.string.bottom_panel_picker_toolbar'), this.resolvePickerGroup('panel'))
  }

  @Builder
  private buildPickerActionGroup(title: ResourceStr, actions: BrowserToolbarInteractionActionState[]) {
    Column({ space: 6 }) {
      Text(title)
        .width('100%')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedSecondaryTextColor)
        .padding({ left: 4 })

      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(actions, (action: BrowserToolbarInteractionActionState, index: number) => {
          SettingsOptionRow({
            title: action.title,
            desktopPresentation: this.desktopPresentation,
            helperText: action.subtitle,
            leadingAiraIconId: action.airaIconId,
            plainLeadingIcon: true,
            rowPosition: this.resolveSheetRowPosition(index, actions.length),
            isSelected: this.isInteractionActionSelected(action.id),
            isEnabled: !this.saving,
            radioGroup: `${TOOLBAR_SLOT_RADIO_GROUP_PREFIX}-${this.sheetQuestion}-` +
              `${this.selectedSlotId}-${this.selectedSplitSlotId}-${this.selectedInteractionKind}`,
            radioValue: action.id,
            onAction: (): void => {
              this.selectInteractionAction(action.id);
            }
          })
          if (index < actions.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (action: BrowserToolbarInteractionActionState) => action.id)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildResetButton() {
    if (this.desktopPresentation) {
      Row() {
        SettingsDesktopActionButton({
          title: $r('app.string.toolbar_settings_reset'),
          emphasis: 'danger',
          isEnabled: !this.saving,
          hoverBackgroundColor: this.resolvePressedBackgroundColor(),
          dangerColor: this.storedAccentColor,
          onAction: () => {
            this.confirmResetToolbarLayout();
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    } else {
      Button($r('app.string.toolbar_settings_reset'))
        .width('100%')
        .height(44)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedAccentColor)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .enabled(!this.saving)
        .onClick(() => {
          this.confirmResetToolbarLayout();
        })
    }
  }

  private updateToolbarChromeStyle(style: BrowserToolbarChromeStyle): void {
    if (this.saving || this.toolbarChromeStyle === style) {
      return;
    }
    const previousStyle = this.toolbarChromeStyle;
    this.toolbarChromeStyle = style;
    this.refreshScrollBehaviorCopy();
    this.sheetVisible = false;
    this.saving = true;
    this.customizationCoordinator.persistToolbarChromeStyle(
      style,
      new BrowserToolbarCustomizationBoundary(this.dataScope, this.privacyMode)
    )
      .then((savedStyle: BrowserToolbarChromeStyle) => {
        this.saving = false;
        this.toolbarChromeStyle = savedStyle;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.saving = false;
        this.toolbarChromeStyle = previousStyle;
        this.refreshScrollBehaviorCopy();
        this.showToast($r('app.string.toolbar_settings_error_style'));
      });
  }

  private shouldShowWebBottomSafeAreaSwitch(): boolean {
    return !this.desktopPresentation && this.toolbarChromeStyle === 'floating';
  }

  private shouldShowTopImmersionSettings(): boolean {
    return shouldShowToolbarTopImmersionSettings(this.desktopPresentation);
  }

  private shouldShowAlwaysTopImmersionSwitch(): boolean {
    return shouldShowAlwaysTopImmersionSetting(this.toolbarChromeStyle);
  }

  private isScrollTopImmersionSwitchEnabled(): boolean {
    return isSplitFamilyStyle(this.toolbarChromeStyle) || !this.alwaysTopImmersionEnabled;
  }

  private updateTopImmersion(kind: ToolbarTopImmersionSwitch, enabled: boolean): void {
    if (this.saving) {
      return;
    }
    if (kind === 'scroll' && this.globalImmersionEnabled === enabled) {
      return;
    }
    if (kind === 'always' && this.alwaysTopImmersionEnabled === enabled) {
      return;
    }
    const previousGlobal = this.globalImmersionEnabled;
    const previousAlways = this.alwaysTopImmersionEnabled;
    const current: ToolbarTopImmersionPreference = {
      globalImmersionEnabled: previousGlobal,
      alwaysTopImmersionEnabled: previousAlways
    };
    const next = resolveTopImmersionPreference(current, kind, enabled);
    this.globalImmersionEnabled = next.globalImmersionEnabled;
    this.alwaysTopImmersionEnabled = next.alwaysTopImmersionEnabled;
    this.saving = true;
    this.customizationCoordinator.persistTopImmersion(
      kind,
      enabled,
      new BrowserToolbarCustomizationBoundary(this.dataScope, this.privacyMode)
    )
      .then((appearance) => {
        this.saving = false;
        this.globalImmersionEnabled = appearance.globalImmersionEnabled;
        this.alwaysTopImmersionEnabled = appearance.alwaysTopImmersionEnabled;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.saving = false;
        this.globalImmersionEnabled = previousGlobal;
        this.alwaysTopImmersionEnabled = previousAlways;
        this.showToast($r('app.string.toolbar_settings_error_immersion'));
      });
  }

  private updateWebBottomSafeAreaEnabled(enabled: boolean): void {
    if (this.saving || this.webBottomSafeAreaEnabled === enabled) {
      return;
    }
    const previousEnabled = this.webBottomSafeAreaEnabled;
    this.webBottomSafeAreaEnabled = enabled;
    this.saving = true;
    this.customizationCoordinator.persistWebBottomSafeAreaEnabled(
      enabled,
      new BrowserToolbarCustomizationBoundary(this.dataScope, this.privacyMode)
    )
      .then((savedEnabled: boolean) => {
        this.saving = false;
        this.webBottomSafeAreaEnabled = savedEnabled;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.saving = false;
        this.webBottomSafeAreaEnabled = previousEnabled;
        this.showToast($r('app.string.toolbar_settings_error_safe_area'));
      });
  }

  private updateScrollBehavior(behavior: BrowserBottomToolbarScrollBehavior): void {
    const nextBehavior = this.resolveScrollBehaviorForStyle(behavior);
    if (this.saving || this.resolveScrollBehaviorForStyle(this.scrollBehavior) === nextBehavior) {
      return;
    }
    const previousBehavior = this.scrollBehavior;
    this.scrollBehavior = nextBehavior;
    this.saving = true;
    this.customizationCoordinator.persistScrollBehavior(
      nextBehavior,
      new BrowserToolbarCustomizationBoundary(this.dataScope, this.privacyMode)
    )
      .then((savedBehavior: BrowserBottomToolbarScrollBehavior) => {
        this.saving = false;
        this.scrollBehavior = savedBehavior;
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.saving = false;
        this.scrollBehavior = previousBehavior;
        this.showToast($r('app.string.toolbar_settings_error_scroll'));
      });
  }

  private confirmResetToolbarLayout(): void {
    if (this.saving) {
      return;
    }
    showCenteredAlertDialog({
      title: $r('app.string.toolbar_settings_reset_dialog_title'),
      message: isSplitFamilyStyle(this.toolbarChromeStyle) ?
        $r('app.string.toolbar_settings_reset_dialog_split') :
        $r('app.string.toolbar_settings_reset_dialog_floating'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.settings_account_cancel'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.toolbar_settings_reset'),
        action: () => {
          this.applySettings(isSplitFamilyStyle(this.toolbarChromeStyle) ?
            this.splitViewModel.resetAll(this.settings) :
            this.viewModel.resetAllSlotActions(this.settings));
        }
      }
    });
  }

  private buildToolbarPreviewPresentation(): BrowserBottomChromePresentation {
    const width = Math.max(1, this.toolbarPreviewWidth);
    const cached = this.previewPresentationCache;
    if (cached !== undefined && this.previewPresentationWidth === width &&
      this.previewPresentationState === this.state) {
      return cached;
    }
    const presentation = this.chromePresentationViewModel.buildPresentation({
      scene: 'web',
      addressFocused: false,
      addressEditable: true,
      currentDetent: 'low',
      scrollPresentation: 'resting',
      returnHomeDrag: false,
      returnHomeProgress: 0,
      panelWidth: width,
      panelExpansionEnabled: true,
      addressInput: 'https://aira.cool',
      addressDisplayText: 'aira.cool',
      placeholder: resolveAppResourceText($r('app.string.aira_search_card_placeholder')),
      toolbarSlotActions: this.state.slotActions,
      toolbarInteractionProfileActive: true,
      customizationPreview: true,
      leadingHeaderActions: [],
      trailingHeaderActions: []
    });
    this.previewPresentationCache = presentation;
    this.previewPresentationWidth = width;
    this.previewPresentationState = this.state;
    return presentation;
  }

  private resolvePreviewFooterText(): ResourceStr {
    // The dock row is the split web bar, so it carries the split web customization note.
    if (this.toolbarChromeStyle === 'dock') {
      return $r('app.string.toolbar_settings_preview_footer_split_web');
    }
    if (this.toolbarChromeStyle !== 'split') {
      return $r('app.string.toolbar_settings_preview_footer_floating');
    }
    if (this.splitPreviewScene === 'home') {
      return $r('app.string.toolbar_settings_preview_footer_split_home');
    }
    return $r('app.string.toolbar_settings_preview_footer_split_web');
  }

  private selectSplitPreviewScene(scene: BrowserSplitToolbarScene): void {
    if (this.splitPreviewScene === scene) {
      return;
    }
    this.splitPreviewScene = scene;
    this.sheetVisible = false;
  }

  private openSplitSlotSheet(slotId: string): void {
    if (!isSplitToolbarSlotId(slotId)) {
      return;
    }
    this.selectedSplitSlotId = slotId as BrowserSplitToolbarSlotId;
    this.sheetQuestion = 'split_slot';
    this.selectedInteractionKind = 'tap';
    this.resetSheetNavigation();
    this.sheetVisible = true;
  }

  private resolveSplitDetail(): BrowserSplitToolbarSlotDetail {
    return this.splitViewModel.buildSlotDetail(this.settings, this.selectedSplitSlotId) as BrowserSplitToolbarSlotDetail;
  }

  private resolveSplitSheetTitle(): string {
    return this.resolveSplitDetail().sheetTitle;
  }

  private resolveSplitInteractionKind(): BrowserSplitToolbarInteractionKind {
    return this.selectedInteractionKind === 'longPress' ? 'longPress' : 'tap';
  }

  private selectSplitInteractionAction(actionId: BrowserToolbarInteractionActionId): void {
    const kind = this.resolveSplitInteractionKind();
    const before = this.splitViewModel.resolveActionId(this.settings, this.selectedSplitSlotId, kind);
    if (before === actionId) {
      this.popSheetNavigation();
      return;
    }
    const nextSettings = this.splitViewModel.replaceInteraction(
      this.settings,
      this.selectedSplitSlotId,
      kind,
      actionId
    );
    const after = this.splitViewModel.resolveActionId(nextSettings, this.selectedSplitSlotId, kind);
    if (after !== actionId) {
      this.popSheetNavigation();
      this.showToast($r('app.string.toolbar_settings_action_already_on_bar'));
      return;
    }
    this.commitInteractionSelection(nextSettings);
  }

  private handleToolbarPreviewIntent(intent: BrowserBottomChromeTapIntent): void {
    if (!this.isToolbarSlotId(intent.slotId)) {
      // The preview's middle capsule, which is not one of the four buttons.
      this.sheetQuestion = 'center_capsule';
      this.resetSheetNavigation();
      this.sheetVisible = true;
      return;
    }
    this.selectedSlotId = intent.slotId as BrowserToolbarSlotId;
    this.sheetQuestion = 'slot';
    this.resetSheetNavigation();
    this.sheetVisible = true;
  }

  private isToolbarSlotId(slotId: string): boolean {
    return slotId === 'leading' || slotId === 'menu' || slotId === 'refresh' || slotId === 'tabs';
  }

  private selectInteractionAction(actionId: BrowserToolbarInteractionActionId): void {
    if (this.saving) {
      return;
    }
    if (this.sheetQuestion === 'split_slot') {
      this.selectSplitInteractionAction(actionId);
      return;
    }
    const nextSettings = this.viewModel.replaceSlotInteraction(
      this.settings,
      this.selectedSlotId,
      this.selectedInteractionKind,
      actionId
    );
    this.commitInteractionSelection(nextSettings);
  }

  /**
   * pop() and the settings write share this click. Navigation drops the overview repaint,
   * so the label is published again once the home page is current, and again after the slide.
   */
  private commitInteractionSelection(nextSettings: BrowserToolbarLayoutSettings): void {
    const generation = ++this.sheetOverviewRefreshGeneration;
    this.popSheetNavigation();
    this.applySettings(nextSettings);
    this.scheduleSheetOverviewRefresh(TOOLBAR_SHEET_OVERVIEW_REFRESH_FALLBACK_MS, generation);
  }

  private scheduleSheetOverviewRefresh(delayMs: number, generation: number): void {
    setTimeout((): void => {
      if (this.sheetOverviewDisposed || generation !== this.sheetOverviewRefreshGeneration) {
        return;
      }
      this.sheetOverviewRevision++;
    }, delayMs);
  }

  private resolveOverviewInteraction(
    kind: BrowserToolbarInteractionKind
  ): BrowserToolbarSlotInteractionState {
    if (this.sheetQuestion === 'split_slot') {
      const detail = this.resolveSplitDetail();
      return kind === 'longPress' ? detail.longPress : detail.tap;
    }
    const resolved = this.viewModel.findSlotInteraction(this.state, this.selectedSlotId, kind);
    if (resolved !== undefined) {
      return resolved;
    }
    return this.resolveSelectedSlotAction().tap;
  }

  private resolveOverviewRowKey(kind: BrowserToolbarInteractionKind): string {
    const actionId = this.resolveOverviewInteraction(kind).action.id;
    return `${this.sheetQuestion}-${this.selectedSlotId}-${this.selectedSplitSlotId}-${kind}-` +
      `${actionId}-${this.sheetOverviewRevision}`;
  }

  private isSlotResetEnabled(): boolean {
    // Revision is read so this row repaints after the picker pop, not only when saving flips.
    return !this.saving && !this.resolveSelectedSlotAction().isProfileDefault &&
      this.sheetOverviewRevision >= 0;
  }

  private isSplitSlotResetEnabled(): boolean {
    return !this.saving && !this.resolveSplitDetail().isProfileDefault &&
      this.sheetOverviewRevision >= 0;
  }

  private resetSelectedSlotAction(): void {
    if (this.saving) {
      return;
    }
    const nextSettings = this.sheetQuestion === 'split_slot' ?
      this.splitViewModel.resetSlot(this.settings, this.selectedSplitSlotId) :
      this.viewModel.resetSlotAction(this.settings, this.selectedSlotId);
    this.applySettings(nextSettings);
  }

  private resolveSelectedSlotAction(): BrowserToolbarSlotActionState {
    return this.viewModel.findSlotAction(this.state, this.selectedSlotId) as BrowserToolbarSlotActionState;
  }

  private resolveSelectedSlotTitle(): ResourceStr {
    if (this.sheetQuestion === 'split_slot') {
      return this.resolveSplitSheetTitle();
    }
    return this.resolveSelectedSlotAction().slotTitle;
  }

  private resolveSelectedInteraction(): BrowserToolbarSlotInteractionState {
    if (this.sheetQuestion === 'split_slot') {
      const detail = this.resolveSplitDetail();
      return this.selectedInteractionKind === 'longPress' ? detail.longPress : detail.tap;
    }
    return this.viewModel.findSlotInteraction(
      this.state,
      this.selectedSlotId,
      this.selectedInteractionKind
    ) as BrowserToolbarSlotInteractionState;
  }

  private isInteractionActionSelected(actionId: BrowserToolbarInteractionActionId): boolean {
    return this.resolveSelectedInteraction().action.id === actionId;
  }

  private resolvePickerGroup(
    dispatchKind: 'none' | 'header' | 'panel'
  ): BrowserToolbarInteractionActionState[] {
    const catalog = this.sheetQuestion === 'split_slot' ?
      this.splitViewModel.buildActionCatalog(
        this.settings,
        this.selectedSplitSlotId,
        this.resolveSplitInteractionKind()
      ) :
      this.viewModel.buildInteractionActionCatalog(
        this.settings,
        this.selectedSlotId,
        this.selectedInteractionKind
      );
    return catalog.filter((action: BrowserToolbarInteractionActionState): boolean => {
      return action.dispatchKind === dispatchKind;
    });
  }

  private resolveSheetRowPosition(index: number, count: number): SettingsRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    if (index >= count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private hasCustomizedToolbarSlots(): boolean {
    // The dock shares the split web bar's slots, so it has the same customizations to reset.
    if (isSplitFamilyStyle(this.toolbarChromeStyle)) {
      return this.splitViewModel.hasCustomizations(this.settings);
    }
    return this.state.slotActions.some((slot: BrowserToolbarSlotActionState): boolean => !slot.isProfileDefault);
  }

  private refreshState(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.settings = preferences.toolbarLayout;
    this.scrollBehavior = preferences.appearance.bottomToolbarScrollBehavior;
    this.toolbarChromeStyle = preferences.appearance.toolbarChromeStyle;
    this.webBottomSafeAreaEnabled = preferences.experiments.webBottomSafeAreaEnabled;
    this.globalImmersionEnabled = preferences.appearance.globalImmersionEnabled;
    this.alwaysTopImmersionEnabled = preferences.appearance.alwaysTopImmersionEnabled;
    this.refreshScrollBehaviorCopy();
    this.state = this.viewModel.buildState(this.settings);
  }

  private refreshScrollBehaviorCopy(): void {
    const state = this.scrollBehaviorViewModel.buildStateForBehavior(
      this.scrollBehavior,
      this.toolbarChromeStyle
    );
    this.scrollBehaviorOptions = state.options;
    this.scrollBehaviorFooterText = state.footerText;
  }

  private resolveScrollBehaviorForStyle(
    behavior: BrowserBottomToolbarScrollBehavior
  ): BrowserBottomToolbarScrollBehavior {
    return isSplitFamilyStyle(this.toolbarChromeStyle) ?
      resolveSplitToolbarScrollBehavior(behavior) : behavior;
  }

  private isScrollBehaviorOptionSelected(behavior: BrowserBottomToolbarScrollBehavior): boolean {
    return this.resolveScrollBehaviorForStyle(this.scrollBehavior) === behavior;
  }

  private resolvePageBackgroundColor(): ResourceColor {
    return this.normalizeColor(this.storedPageBackgroundColor, DEFAULT_THEME_PALETTE.light.pageBackground);
  }

  /**
   * The preview's rim, over the same tokens the live bar's material edge highlight uses.
   *
   * The settings page can resolve the theme mode, so it hands the preview the colour and the preview
   * stays a plain renderer with no theme lookup of its own.
   */
  private resolvePreviewEdgeHighlightColor(): ResourceColor {
    return resolveBrowserBottomChromeEdgeHighlightColor(this.storedResolvedThemeMode);
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    return this.normalizeColor(this.storedPressedBackgroundColor, TOOLBAR_NEUTRAL_PRESSED_BACKGROUND);
  }

  private normalizeColor(color: string, fallback: string): string {
    const value = `${color}`.trim();
    return value.length > 0 ? value : fallback;
  }


  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private resolveSheetNavigationBackground(): ResourceColor {
    return this.desktopPresentation ? Color.Transparent : this.resolvePageBackgroundColor();
  }

  /**
   * Back inside the sheet belongs to the destination stack.
   *
   * The sheet receives the system back before, or as well as, the NavDestination. Pop when a
   * choice page is showing, and keep that pop from also dismissing the sheet if both callbacks
   * run. At the root, back closes the sheet as before.
   */
  private handleSheetWillDismiss(action: DismissSheetAction): void {
    if (action.reason === DismissReason.PRESS_BACK && this.popSheetNavigation()) {
      return;
    }
    action.dismiss();
  }

  private openInteractionPicker(kind: BrowserToolbarInteractionKind): void {
    this.selectedInteractionKind = kind;
    if (this.sheetNavigationStack.size() > 0) {
      return;
    }
    this.sheetNavigationStack.pushPathByName(
      TOOLBAR_SLOT_PICKER_DESTINATION,
      new ToolbarSlotPickerParams()
    );
  }

  private popSheetNavigation(): boolean {
    const now = Date.now();
    if (now < this.sheetNavigationPopGuardUntilMs) {
      return true;
    }
    if (this.sheetNavigationStack.size() <= 0) {
      return false;
    }
    this.sheetNavigationPopGuardUntilMs = now + 450;
    this.sheetNavigationStack.pop();
    return true;
  }

  private resetSheetNavigation(): void {
    this.sheetNavigationPopGuardUntilMs = 0;
    this.sheetRootBlurRadius = 0;
    this.sheetPickerBlurRadius = 0;
    while (this.sheetNavigationStack.pop(false) !== undefined) {
    }
  }

  private resolveSheetScroller(kind: string): Scroller {
    return kind === 'picker' ? this.sheetPickerScroller : this.sheetRootScroller;
  }

  private resolveSheetBlurRadius(kind: string): number {
    return kind === 'picker' ? this.sheetPickerBlurRadius : this.sheetRootBlurRadius;
  }

  /** Blur stays off until content actually moves under the title, then finishes within 8vp. */
  private updateSheetHeaderBlur(kind: string): void {
    const offset = Math.max(0, this.resolveSheetScroller(kind).currentOffset().yOffset);
    const progress = Math.min(1, offset / TOOLBAR_SHEET_BLUR_SCROLL_RANGE_VP);
    const next = BROWSER_SHEET_IMMERSIVE_TOP_BLUR_RADIUS * progress;
    if (kind === 'picker') {
      if (Math.abs(next - this.sheetPickerBlurRadius) < 0.4) {
        return;
      }
      this.sheetPickerBlurRadius = next;
      return;
    }
    if (Math.abs(next - this.sheetRootBlurRadius) < 0.4) {
      return;
    }
    this.sheetRootBlurRadius = next;
  }

  /** The middle bar's choice, saved through the same path the slots use. */
  private applyCenterCapsuleSwipeUpActionId(actionId: string): boolean {
    if (this.saving) {
      return false;
    }
    this.applySettings(this.viewModel.withCenterCapsuleSwipeUpActionId(this.settings, actionId));
    return true;
  }

  private resolveCenterCapsuleSwipeUpActionId(
    options: BrowserToolbarCenterCapsuleSwipeUpOptionState[]
  ): string {
    const selected = options.find((option: BrowserToolbarCenterCapsuleSwipeUpOptionState): boolean =>
      option.isSelected);
    return selected !== undefined ? selected.actionId : 'tools';
  }

  private applySettings(settings: BrowserToolbarLayoutSettings): void {
    if (this.saving) {
      return;
    }
    const nextSettings = this.viewModel.normalizeSettings(settings);
    this.settings = nextSettings;
    this.state = this.viewModel.buildState(nextSettings);
    this.persistSettings(nextSettings);
  }

  private persistSettings(settings: BrowserToolbarLayoutSettings): void {
    this.saving = true;
    this.customizationCoordinator.persistSettings(
      settings,
      new BrowserToolbarCustomizationBoundary(this.dataScope, this.privacyMode)
    )
      .then((savedSettings: BrowserToolbarLayoutSettings) => {
        this.saving = false;
        this.settings = savedSettings;
        this.state = this.viewModel.buildState(savedSettings);
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.saving = false;
        this.refreshState();
        this.showToast($r('app.string.bottom_panel_toolbar_update_failed'));
      });
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }
}
