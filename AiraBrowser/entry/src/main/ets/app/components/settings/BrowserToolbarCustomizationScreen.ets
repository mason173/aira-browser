import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserBottomToolbarScrollBehavior,
  BrowserToolbarLayoutSettings
} from '../../../common/models/BrowserModels';
import {
  BrowserToolbarScrollBehaviorOptionState,
  BrowserToolbarScrollBehaviorSettingsViewModel
} from '../../../core/settings/BrowserToolbarScrollBehaviorSettingsViewModel';
import {
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
  SettingsRowPosition
} from './SettingsRows';
import {
  SettingsDesktopActionButton,
  SettingsDesktopDivider,
  SettingsDesktopGroup,
  SettingsDesktopNavigationRow,
  SettingsDesktopOptionRow
} from './SettingsDesktopRows';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';
import { BrowserBottomChromeRenderer } from '../browser/BrowserBottomChromeRenderer';
import {
  BrowserToolbarCustomizationBoundary,
  BrowserToolbarCustomizationCoordinator
} from '../../../core/browser/BrowserToolbarCustomizationCoordinator';
import {
  resolveBrowserBottomChromeMaterialTintForMode
} from '../browser/BrowserFloatingGlassMaterialTokens';
import {
  BrowserSheetIconButton
} from '../browser/BrowserModalBottomSheet';
import { CenteredDialogSurface } from '../common/CenteredDialogSurface';

const TOOLBAR_NEUTRAL_PRESSED_BACKGROUND: string = '#14000000';
const TOOLBAR_PREVIEW_DEFAULT_WIDTH: number = 358;
const TOOLBAR_SLOT_RADIO_GROUP_PREFIX: string = 'browser-toolbar-slot-action';
type BrowserToolbarSlotSheetMode = 'overview' | 'picker';
export type BrowserToolbarDesktopView = 'overview' | 'scroll_behavior';

@Component
export struct BrowserToolbarCustomizationScreen {
  private viewModel: BrowserToolbarCustomizationViewModel = new BrowserToolbarCustomizationViewModel();
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
  @State private state: BrowserToolbarCustomizationState =
    this.viewModel.buildState(sharedPreferencesRepository.getPreferences().toolbarLayout);
  @State private saving: boolean = false;
  @State private toolbarPreviewWidth: number = TOOLBAR_PREVIEW_DEFAULT_WIDTH;
  @State private selectedSlotId: BrowserToolbarSlotId = 'leading';
  @State private selectedInteractionKind: BrowserToolbarInteractionKind = 'tap';
  @State private slotSheetMode: BrowserToolbarSlotSheetMode = 'overview';
  @State private slotSheetRevision: number = 0;
  @State private slotSheetVisible: boolean = false;
  @State private desktopView: BrowserToolbarDesktopView = 'overview';

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
    .bindSheet($$this.slotSheetVisible, this.buildSlotSelectionSheet(), {
      preferType: this.desktopPresentation ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: !this.desktopPresentation,
      showClose: true,
      onDisappear: () => {
        this.slotSheetVisible = false;
        this.slotSheetMode = 'overview';
      }
    })
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
          title: this.desktopView === 'scroll_behavior' ? '滚动行为' : '工具栏设置',
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
      this.buildToolbarPreviewSection()
      this.buildToolbarBehaviorSection()
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
        title: '网页滚动时',
        secondaryTextColor: this.storedSecondaryTextColor
      }) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          ForEach(this.scrollBehaviorViewModel.buildStateForBehavior(this.scrollBehavior).options, (
            option: BrowserToolbarScrollBehaviorOptionState,
            index: number
          ) => {
            SettingsDesktopOptionRow({
              title: option.title,
              isSelected: option.behavior === this.scrollBehavior,
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
            if (index < this.scrollBehaviorViewModel.buildStateForBehavior(this.scrollBehavior).options.length - 1) {
              SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
            }
          }, (option: BrowserToolbarScrollBehaviorOptionState) => `toolbar-scroll-workspace-${option.behavior}`)
        }
        SettingsFooterText({
          text: this.scrollBehaviorViewModel.buildStateForBehavior(this.scrollBehavior).footerText,
          secondaryTextColor: this.storedSecondaryTextColor
        })
      }
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
            title: '滚动行为',
            value: this.scrollBehaviorViewModel.formatBehaviorTitle(this.scrollBehavior),
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
            title: '滚动行为',
            value: this.scrollBehaviorViewModel.formatBehaviorTitle(this.scrollBehavior),
            rowPosition: 'single',
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
        text: '选择浏览网页时工具栏保持显示、收起为胶囊或完全隐藏。',
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
        Column() {
          BrowserBottomChromeRenderer({
            presentation: this.buildToolbarPreviewPresentation(),
            materialTint: resolveBrowserBottomChromeMaterialTintForMode(this.storedResolvedThemeMode),
            materialShadowColor: resolveBrowserBottomFloatingMaterialShadowColor(this.storedResolvedThemeMode),
            primaryIconColor: resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode),
            disabledIconColor: resolveBrowserBottomNeutralSecondaryColor(this.storedResolvedThemeMode),
            primaryTextColor: resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode),
            secondaryTextColor: resolveBrowserBottomNeutralSecondaryColor(this.storedResolvedThemeMode),
            pressedBackgroundColor: resolveBrowserBottomNeutralPressedColor(this.storedResolvedThemeMode),
            chromeIconTone: AppIconResources.chromeToneForResolvedThemeMode(this.storedResolvedThemeMode),
            onIntent: (intent: BrowserBottomChromeTapIntent): void => {
              this.handleToolbarPreviewIntent(intent);
            }
          })
            .width('100%')
            .height(52)
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })
        .onAreaChange((_oldArea: Area, newArea: Area) => {
          const width = this.parseAreaDimension(newArea.width);
          if (width > 1) {
            this.toolbarPreviewWidth = width;
          }
        })
      }
      SettingsFooterText({
        text: '点击按钮可分别设置单击、长按和两侧按钮上滑动作。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildSlotSelectionSheet() {
    if (this.desktopPresentation) {
      CenteredDialogSurface({ fillHeight: true }) {
        this.buildSlotSelectionSheetContent()
      }
    } else {
      this.buildSlotSelectionSheetContent()
    }
  }

  @Builder
  private buildSlotSelectionSheetContent() {
    ForEach([this.resolveSlotSheetRenderKey()], (_renderKey: string) => {
      if (this.slotSheetMode === 'picker') {
        this.buildInteractionActionPicker()
      } else {
        this.buildSlotInteractionOverview()
      }
    }, (renderKey: string) => renderKey)
  }

  @Builder
  private buildSlotInteractionOverview() {
    Column({ space: 16 }) {
      Column({ space: 4 }) {
        Text(this.resolveSelectedSlotTitle())
          .width('100%')
          .fontSize(this.desktopPresentation ? 18 : 21)
          .fontWeight(this.desktopPresentation ? FontWeight.Medium : FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)

        Text('选择要自定义的操作')
          .width('100%')
          .fontSize(13)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')

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
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 18, bottom: 24 })
    .backgroundColor(this.desktopPresentation ? Color.Transparent : this.resolvePageBackgroundColor())
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
        this.selectedInteractionKind = interaction.kind;
        this.slotSheetMode = 'picker';
      }
    })
  }

  @Builder
  private buildInteractionActionPicker() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        BrowserSheetIconButton({
          icon: $r('sys.symbol.chevron_left'),
          iconSize: 18,
          buttonSize: 36,
          actionEnabled: !this.saving,
          iconColor: this.storedSecondaryTextColor,
          accessibilityLabel: '返回操作概览',
          onAction: () => {
            this.slotSheetMode = 'overview';
          }
        })

        Column({ space: 2 }) {
          Text(this.resolveSelectedInteraction().title)
            .width('100%')
            .fontSize(this.desktopPresentation ? 18 : 21)
            .fontWeight(this.desktopPresentation ? FontWeight.Medium : FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
          Text(this.resolveSelectedSlotTitle())
            .width('100%')
            .fontSize(13)
            .fontColor(this.storedSecondaryTextColor)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Scroll() {
        Column({ space: 14 }) {
          if (this.resolvePickerGroup('none').length > 0) {
            this.buildPickerActionGroup('无动作', this.resolvePickerGroup('none'))
          }
          this.buildPickerActionGroup('浏览器', this.resolvePickerGroup('header'))
          this.buildPickerActionGroup('工具栏', this.resolvePickerGroup('panel'))
        }
        .width('100%')
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 24 })
    .backgroundColor(this.desktopPresentation ? Color.Transparent : this.resolvePageBackgroundColor())
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
            rowPosition: this.resolveSlotSheetRowPosition(index, actions.length),
            isSelected: this.isInteractionActionSelected(action.id),
            isEnabled: !this.saving,
            radioGroup: `${TOOLBAR_SLOT_RADIO_GROUP_PREFIX}-${this.selectedSlotId}-${this.selectedInteractionKind}`,
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

  private updateScrollBehavior(behavior: BrowserBottomToolbarScrollBehavior): void {
    if (this.saving || this.scrollBehavior === behavior) {
      return;
    }
    const previousBehavior = this.scrollBehavior;
    this.scrollBehavior = behavior;
    this.saving = true;
    this.customizationCoordinator.persistScrollBehavior(
      behavior,
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
        this.showToast('工具栏滚动行为更新失败。');
      });
  }

  private confirmResetToolbarLayout(): void {
    if (this.saving) {
      return;
    }
    showCenteredAlertDialog({
      title: '恢复默认工具栏',
      message: '会恢复四个按钮的单击、长按和上滑设置，不会改变展开工具栏的快捷入口顺序。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '恢复默认',
        action: () => {
          this.applySettings(this.viewModel.resetAllSlotActions(this.settings));
        }
      }
    });
  }

  private buildToolbarPreviewPresentation(): BrowserBottomChromePresentation {
    return this.chromePresentationViewModel.buildPresentation({
      scene: 'web',
      addressFocused: false,
      addressEditable: true,
      currentDetent: 'low',
      scrollPresentation: 'resting',
      returnHomeDrag: false,
      returnHomeProgress: 0,
      panelWidth: Math.max(1, this.toolbarPreviewWidth),
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
  }

  private handleToolbarPreviewIntent(intent: BrowserBottomChromeTapIntent): void {
    if (!this.isToolbarSlotId(intent.slotId)) {
      return;
    }
    this.selectedSlotId = intent.slotId as BrowserToolbarSlotId;
    this.slotSheetMode = 'overview';
    this.slotSheetVisible = true;
  }

  private isToolbarSlotId(slotId: string): boolean {
    return slotId === 'leading' || slotId === 'menu' || slotId === 'refresh' || slotId === 'tabs';
  }

  private selectInteractionAction(actionId: BrowserToolbarInteractionActionId): void {
    if (this.saving) {
      return;
    }
    const nextSettings = this.viewModel.replaceSlotInteraction(
      this.settings,
      this.selectedSlotId,
      this.selectedInteractionKind,
      actionId
    );
    this.slotSheetMode = 'overview';
    this.applySettings(nextSettings);
  }

  private resetSelectedSlotAction(): void {
    if (this.saving) {
      return;
    }
    const nextSettings = this.viewModel.resetSlotAction(this.settings, this.selectedSlotId);
    this.applySettings(nextSettings);
  }

  private resolveSelectedSlotAction(): BrowserToolbarSlotActionState {
    return this.viewModel.findSlotAction(this.state, this.selectedSlotId) as BrowserToolbarSlotActionState;
  }

  private resolveSelectedSlotTitle(): string {
    return this.resolveSelectedSlotAction().slotTitle;
  }

  private resolveSelectedInteraction(): BrowserToolbarSlotInteractionState {
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
    return this.viewModel.buildInteractionActionCatalog(
      this.settings,
      this.selectedSlotId,
      this.selectedInteractionKind
    ).filter((action: BrowserToolbarInteractionActionState): boolean => action.dispatchKind === dispatchKind);
  }

  private resolveSlotSheetRowPosition(index: number, count: number): SettingsRowPosition {
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
    return this.state.slotActions.some((slot: BrowserToolbarSlotActionState): boolean => !slot.isProfileDefault);
  }

  private refreshState(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.settings = preferences.toolbarLayout;
    this.scrollBehavior = preferences.appearance.bottomToolbarScrollBehavior;
    this.state = this.viewModel.buildState(this.settings);
    this.slotSheetRevision += 1;
  }

  private resolveSlotSheetRenderKey(): string {
    return `${this.slotSheetMode}|${this.selectedSlotId}|${this.selectedInteractionKind}|${this.slotSheetRevision}`;
  }

  private resolvePageBackgroundColor(): ResourceColor {
    return this.normalizeColor(this.storedPageBackgroundColor, DEFAULT_THEME_PALETTE.light.pageBackground);
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

  private applySettings(settings: BrowserToolbarLayoutSettings): void {
    if (this.saving) {
      return;
    }
    const nextSettings = this.viewModel.normalizeSettings(settings);
    this.settings = nextSettings;
    this.state = this.viewModel.buildState(nextSettings);
    this.slotSheetRevision += 1;
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
        this.slotSheetRevision += 1;
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
