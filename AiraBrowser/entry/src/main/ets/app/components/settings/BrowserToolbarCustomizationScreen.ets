import { BrowserToolbarPreview } from './BrowserToolbarPreview';
import { BrowserSplitToolbarButtonRow } from '../browser/BrowserSplitToolbarChrome';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarChromeStyle,
  BrowserToolbarLayoutSettings
} from '../../../common/models/BrowserModels';
import { resolveSplitToolbarScrollBehavior } from '../../../core/browser/BrowserToolbarChromeStylePolicy';
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
   */
  private sheetNavigationStack: NavPathStack = new NavPathStack();
  private sheetNavigationPopGuardUntilMs: number = 0;
  private sheetRootScroller: Scroller = new Scroller();
  private sheetPickerScroller: Scroller = new Scroller();
  @State private sheetRootBlurRadius: number = 0;
  @State private sheetPickerBlurRadius: number = 0;
  @State private sheetQuestion: BrowserToolbarSheetQuestion = 'slot';
  @State private sheetVisible: boolean = false;
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
  private scrollBehaviorFooterText: string =
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
      title: '工具栏设置',
      backIconKind: 'back',
      showTitleBar: this.showTitleBar,
      showBackButton: this.showBackButton,
      useTopSafeInset: this.useTopSafeInset,
      pageBackground: this.resolvePageBackgroundColor(),
      headerButtonBackground: this.resolvePressedBackgroundColor(),
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      contentKind: 'canvas',
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
          title: this.desktopView === 'scroll_behavior' ? '滚动时' : '工具栏设置',
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
        title: '浏览网页时',
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
      title: '工具栏样式',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsDesktopOptionRow({
            title: '悬浮工具栏',
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
            title: '上下分栏',
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
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsOptionRow({
            title: '悬浮工具栏',
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
            title: '上下分栏',
            isSelected: this.toolbarChromeStyle === 'split',
            radioGroup: 'browser-toolbar-chrome-style',
            radioValue: 'split',
            rowPosition: 'last',
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.resolvePressedBackgroundColor(),
            onAction: () => {
              this.updateToolbarChromeStyle('split');
            }
          })
        }
      }
      SettingsFooterText({
        text: '上下分栏把地址栏放在顶部、导航放在底部。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildToolbarBehaviorSection() {
    SettingsSection({
      title: '工具栏行为',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsDesktopNavigationRow({
            title: '滚动时',
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
            title: '滚动时',
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
        text: this.toolbarChromeStyle === 'split' ?
          '向下滚动网页时，可以选择保持上下分栏，或同时收起地址栏和底部工具栏。' :
          '向下滚动网页时，工具栏可以保持显示、收起为胶囊或完全隐藏。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildWebBottomSafeAreaSection() {
    SettingsSection({
      title: '网页适配',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '网页底栏防遮挡',
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
        text: '自动留出空间，避免悬浮工具栏挡住网页底部按钮。部分网站可能无法识别。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildToolbarPreviewSection() {
    SettingsSection({
      title: '工具栏预览',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        if (this.toolbarChromeStyle === 'split') {
          this.buildSplitToolbarPreview()
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

  @Builder
  private buildSplitSceneSwitch() {
    Row() {
      this.buildSplitSceneChip('home', '主页')
      this.buildSplitSceneChip('web', '网页')
    }
    .width('100%')
    .height(36)
    .borderRadius(18)
    .clip(true)
    .padding(2)
    .backgroundColor(this.resolvePressedBackgroundColor())
  }

  @Builder
  private buildSplitSceneChip(scene: BrowserSplitToolbarScene, title: string) {
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
      accessibilityLabel: '关闭',
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
  private buildToolbarSheetPage(title: string, showBack: boolean, backLabel: string, kind: string) {
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
  private buildToolbarSheetHeader(title: string, showBack: boolean, backLabel: string) {
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
    this.buildToolbarSheetPage('中间区域上滑', false, '', 'capsule')
  }

  @Builder
  private buildCenterCapsuleSwipeUpOptionGroup(options: BrowserToolbarCenterCapsuleSwipeUpOptionState[]) {
    SettingsGroupCard({
      surfaceColor: this.storedSurfaceBackgroundColor,
      desktopPresentation: this.desktopPresentation
    }) {
      ForEach(options, (option: BrowserToolbarCenterCapsuleSwipeUpOptionState, index: number) => {
        SettingsOptionRow({
          title: option.title,
          desktopPresentation: this.desktopPresentation,
          rowPosition: this.resolveSheetRowPosition(index, options.length),
          isSelected: option.isSelected,
          isEnabled: !this.saving,
          radioGroup: TOOLBAR_CENTER_CAPSULE_RADIO_GROUP,
          radioValue: option.actionId,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          selectedIndicatorColor: this.storedAccentColor,
          onAction: (): void => {
            this.applyCenterCapsuleSwipeUpActionId(option.actionId);
          }
        })
        if (index < options.length - 1) {
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
      }, (option: BrowserToolbarCenterCapsuleSwipeUpOptionState) => option.actionId)
    }
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
      title: '恢复此按钮默认设置',
      variant: 'tonal',
      isEnabled: !this.saving && !this.resolveSplitDetail().isProfileDefault,
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
      Text(`固定为${interaction.action.title}`)
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
      title: '恢复此按钮默认设置',
      variant: 'tonal',
      isEnabled: !this.saving && !this.resolveSelectedSlotAction().isProfileDefault,
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
      value: interaction.action.title,
      airaIconId: interaction.action.airaIconId,
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
  }

  @Builder
  private buildInteractionActionPicker() {
    this.buildToolbarSheetPage(this.resolveSelectedInteraction().title, true, '返回', 'picker')
  }

  @Builder
  private buildPickerBody() {
    if (this.resolvePickerGroup('none').length > 0) {
      this.buildPickerActionGroup('无动作', this.resolvePickerGroup('none'))
    }
    this.buildPickerActionGroup('浏览器', this.resolvePickerGroup('header'))
    this.buildPickerActionGroup('工具栏', this.resolvePickerGroup('panel'))
  }

  @Builder
  private buildPickerActionGroup(title: string, actions: BrowserToolbarInteractionActionState[]) {
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
          title: '恢复默认',
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
      Button('恢复默认')
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
        this.showToast('工具栏样式更新失败。');
      });
  }

  private shouldShowWebBottomSafeAreaSwitch(): boolean {
    return !this.desktopPresentation && this.toolbarChromeStyle === 'floating';
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
        this.showToast('网页底栏防遮挡更新失败。');
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
        this.showToast('滚动时的显示更新失败。');
      });
  }

  private confirmResetToolbarLayout(): void {
    if (this.saving) {
      return;
    }
    showCenteredAlertDialog({
      title: '恢复默认工具栏',
      message: this.toolbarChromeStyle === 'split' ?
        '会恢复上下分栏底部按钮的单击和长按设置，不会改变悬浮工具栏。' :
        '会恢复四个按钮的单击、长按和上滑设置，不会改变展开工具栏的快捷入口顺序。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '恢复默认',
        action: () => {
          this.applySettings(this.toolbarChromeStyle === 'split' ?
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
      placeholder: '搜索或输入网址',
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

  private resolvePreviewFooterText(): string {
    if (this.toolbarChromeStyle !== 'split') {
      return '点击按钮可分别设置单击、长按和两侧按钮上滑动作。';
    }
    if (this.splitPreviewScene === 'home') {
      return '左侧两个按钮可自定义单击和长按。标签页和菜单的单击固定。';
    }
    return '主页按钮可自定义。返回、前进、标签页和菜单的单击固定，长按仍可设置。';
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
    this.popSheetNavigation();
    if (after !== actionId) {
      this.showToast('这个动作已经在这条栏上了。');
      return;
    }
    this.applySettings(nextSettings);
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
    this.popSheetNavigation();
    this.applySettings(nextSettings);
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

  private resolveSelectedSlotTitle(): string {
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
    if (this.toolbarChromeStyle === 'split') {
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
    return this.toolbarChromeStyle === 'split' ? resolveSplitToolbarScrollBehavior(behavior) : behavior;
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
  private applyCenterCapsuleSwipeUpActionId(actionId: string): void {
    if (this.saving) {
      return;
    }
    this.applySettings(this.viewModel.withCenterCapsuleSwipeUpActionId(this.settings, actionId));
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
        this.showToast('底部工具栏更新失败。');
      });
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }
}
