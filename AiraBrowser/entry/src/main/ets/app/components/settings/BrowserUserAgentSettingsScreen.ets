import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  CenteredDialogSurface,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import {
  BrowserUserAgentMode,
  BrowserUserAgentPresetId,
  BrowserUserAgentSettings
} from '../../../common/models/BrowserModels';
import {
  BrowserCustomUserAgentOptionView,
  BrowserUserAgentOptionView,
  BrowserUserAgentSettingsViewModel,
  BrowserUserAgentSettingsViewState
} from '../../../core/settings/BrowserUserAgentSettingsViewModel';
import {
  BrowserUserAgentSettingsBoundary,
  BrowserUserAgentSettingsCoordinator,
  BrowserUserAgentSettingsMutationResult
} from '../../../core/settings/BrowserUserAgentSettingsCoordinator';
import {
  BrowserUserAgentService,
  SYSTEM_DEFAULT_USER_AGENT_PRESET_ID
} from '../../../services/web/BrowserUserAgentService';
import {
  sharedBrowserUserAgentSettingsRepository,
  sharedSavedSiteSettingRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsActionButton,
  SettingsOptionRow,
  SettingsStaticValueRow
} from './SettingsRows';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import { SettingsNoticeCard } from './SettingsNoticeCard';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from './SettingsLayout';
import {
  SettingsDesktopDivider,
  SettingsDesktopGroup,
  SettingsDesktopOptionRow,
  SettingsDesktopStaticValueRow
} from './SettingsDesktopRows';
import { isPrivateBoundaryRoute } from '../../../common/utils/RouteParamUtils';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { sharedSettingsNoticeDismissalRepository } from '../../bootstrap/BrowserAppRuntime';
import { SETTINGS_NOTICE_USER_AGENT } from '../../../data/preferences/SettingsNoticeDismissalRepository';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from './SettingsTargetReveal';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

const BROWSER_USER_AGENT_CUSTOM_RADIO_GROUP: string = 'browser-user-agent-custom-list';
const BROWSER_USER_AGENT_DELETE_SWIPE_WIDTH: number = 88;
const BROWSER_USER_AGENT_DELETE_BUTTON_SIZE: number = 44;
const BROWSER_USER_AGENT_CUSTOM_ROW_HEIGHT: number = 58;

@Component
export struct BrowserUserAgentSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  onSettingsChange?: (settings: BrowserUserAgentSettings) => void;
  @Prop
  @Watch('syncViewStateFromProp')
  state: BrowserUserAgentSettingsViewState =
    new BrowserUserAgentSettingsViewModel().buildState(sharedBrowserUserAgentSettingsRepository.getSettings());
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  // When embedded in the large-screen UI, present the custom-UA sheet as a
  // centered dialog instead of a phone-style bottom sheet.
  @Prop useCenteredSheet: boolean = false;

  private viewModel: BrowserUserAgentSettingsViewModel = new BrowserUserAgentSettingsViewModel();
  private service: BrowserUserAgentService = new BrowserUserAgentService();
  private settingsCoordinator: BrowserUserAgentSettingsCoordinator =
    new BrowserUserAgentSettingsCoordinator(
      sharedBrowserUserAgentSettingsRepository,
      undefined,
      undefined,
      sharedSavedSiteSettingRepository
    );

  @State viewState: BrowserUserAgentSettingsViewState =
    new BrowserUserAgentSettingsViewModel().buildState(sharedBrowserUserAgentSettingsRepository.getSettings());
  @State currentSettings: BrowserUserAgentSettings = sharedBrowserUserAgentSettingsRepository.getSettings();
  @State customUserAgentNameDraft: string = '';
  @State customUserAgentValueDraft: string = '';
  @State customUserAgentSheetVisible: boolean = false;
  @State isSaving: boolean = false;
  @State errorMessage: string = '';
  @State private showUserAgentNotice: boolean = true;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );

  aboutToAppear(): void {
    this.showUserAgentNotice = !sharedSettingsNoticeDismissalRepository.hasDismissed(SETTINGS_NOTICE_USER_AGENT);
    this.refreshState();
    this.revealController.bindScroller(this.settingsScroller);
    this.handleRevealRequest();
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    SettingsHdsScaffold({
      title: '网页标识',
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: isPrivateBoundaryRoute(this.dataScope, this.privacyMode),
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      contentKind: this.contentKind,
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.navigationCoordinator.back();
      }
    }) {
      Column() {
        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 22,
          scroller: this.settingsScroller,
          onContentAreaChanged: (area: Area): void => {
            this.revealController.rememberContentArea(area);
          }
        }) {
          if (this.showUserAgentNotice) {
            SettingsNoticeCard({
              title: '网页标识会影响兼容性',
              message: this.desktopPresentation
                ? '切换其它桌面端 UA 后，部分网站可能显示或播放异常。'
                : '切换桌面端或自定义 UA 后，部分网站可能显示或播放异常。',
              desktopPresentation: this.desktopPresentation,
              onClosed: () => {
                this.showUserAgentNotice = false;
                this.dismissNotice(SETTINGS_NOTICE_USER_AGENT);
              }
            })
          }
          this.buildSummarySection()
          if (this.desktopPresentation) {
            this.buildOptionSection('桌面端网页', this.resolveDesktopPresentationOptions())
          } else {
            this.buildMobileSection()
            this.buildDesktopSection()
            this.buildCustomUserAgentSection()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.storedPageBackgroundColor)
      .bindSheet($$this.customUserAgentSheetVisible, this.buildCustomUserAgentSheet(), {
        preferType: this.useCenteredSheet ? SheetType.CENTER : SheetType.BOTTOM,
        height: SheetSize.LARGE,
        dragBar: !this.useCenteredSheet,
        showClose: true,
        onDisappear: () => {
          this.customUserAgentSheetVisible = false;
        }
      })
    }
  }

  @Builder
  private buildSummarySection() {
    SettingsTargetRevealRegion({
      targetId: 'default_user_agent',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.storedAccentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsSection({ title: '当前默认' }) {
        if (this.desktopPresentation) {
          SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            SettingsDesktopStaticValueRow({
              title: '默认网页标识',
              value: this.viewState.summary,
              primaryTextColor: this.storedPrimaryTextColor,
              secondaryTextColor: this.storedSecondaryTextColor
            })
          }
        } else {
          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            SettingsStaticValueRow({
            title: '默认网页标识',
            value: this.viewState.summary,
            rowPosition: 'single'
            })
          }
        }
      }
    }
  }

  @Builder
  private buildMobileSection() {
    this.buildOptionSection('移动端网页', this.viewState.mobileOptions)
  }

  @Builder
  private buildDesktopSection() {
    this.buildOptionSection('桌面端网页', this.viewState.desktopOptions)
  }

  private resolveDesktopPresentationOptions(): BrowserUserAgentOptionView[] {
    const options: BrowserUserAgentOptionView[] = [];
    this.viewState.mobileOptions.forEach((option: BrowserUserAgentOptionView) => {
      if (option.id === SYSTEM_DEFAULT_USER_AGENT_PRESET_ID) {
        options.push(option);
      }
    });
    this.viewState.desktopOptions.forEach((option: BrowserUserAgentOptionView) => {
      options.push(option);
    });
    return options;
  }

  @Builder
  private buildCustomInputSection() {
    if (this.viewState.customUserAgents.length > 0) {
      SettingsSection({ title: '自定义 UA' }) {
        if (this.desktopPresentation) {
          SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            this.buildCustomUserAgentList()
          }
        } else {
          SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
            this.buildCustomUserAgentList()
          }
        }
      }
    }
  }

  @Builder
  private buildCustomUserAgentList() {
          List() {
            ForEach(this.viewState.customUserAgents, (option: BrowserCustomUserAgentOptionView, index: number) => {
              this.buildCustomUserAgentListItem(option, index, this.viewState.customUserAgents.length)
            }, (option: BrowserCustomUserAgentOptionView) => option.id)
          }
          .width('100%')
          .height(this.resolveCustomUserAgentListHeight())
          .scrollBar(BarState.Off)
          .divider({
            strokeWidth: 1,
            color: this.storedDividerColor,
            startMargin: 16,
            endMargin: 16
          })
          .edgeEffect(EdgeEffect.None)
  }

  @Builder
  private buildCustomUserAgentSection() {
    this.buildCustomInputSection()
    if (!this.desktopPresentation) {
      SettingsSection({ title: '' }) {
        SettingsTargetRevealRegion({
          targetId: 'custom_user_agent',
          highlightedTargetId: this.highlightedTargetId,
          accentColor: this.storedAccentColor,
          onAreaChanged: (targetId: string, area: Area): void => {
            this.revealController.rememberTargetArea(targetId, area);
          }
        }) {
          SettingsActionButton({
            title: '自定义 UA',
            isEnabled: !this.isSaving,
            accentColor: this.storedPrimaryTextColor,
            pressedBackgroundColor: this.storedSurfaceBackgroundColor,
            onAction: (): void => {
              this.openCustomUserAgentSheet();
            }
          })
        }
      }
    }
  }

  @Builder
  private buildCustomUserAgentListItem(option: BrowserCustomUserAgentOptionView, index: number, total: number) {
    ListItem() {
      this.buildCustomUserAgentRow(option, index, total)
    }
    .swipeAction({
      end: {
        builder: () => {
          this.buildDeleteSwipeAction(option)
        },
        onAction: () => {
          this.confirmAndRemoveCustomUserAgent(option);
        },
        actionAreaDistance: 56
      }
    })
  }

  @Builder
  private buildCustomUserAgentRow(option: BrowserCustomUserAgentOptionView, index: number, total: number) {
    if (this.desktopPresentation) {
      SettingsDesktopOptionRow({
        title: option.title,
        isSelected: this.isCustomUserAgentOptionSelected(option.id),
        isEnabled: !this.isSaving,
        radioGroup: BROWSER_USER_AGENT_CUSTOM_RADIO_GROUP,
        radioValue: option.id,
        primaryTextColor: this.storedPrimaryTextColor,
        secondaryTextColor: this.storedSecondaryTextColor,
        hoverBackgroundColor: this.storedPressedBackgroundColor,
        focusColor: this.storedAccentColor,
        onAction: (): void => {
          this.confirmAndSelectCustomUserAgent(option.id);
        }
      })
    } else {
      SettingsOptionRow({
        title: option.title,
        helperText: option.subtitle,
        rowPosition: this.resolveRowPosition(index, total),
        isSelected: this.isCustomUserAgentOptionSelected(option.id),
        isEnabled: !this.isSaving,
        radioGroup: BROWSER_USER_AGENT_CUSTOM_RADIO_GROUP,
        radioValue: option.id,
        onAction: (): void => {
          this.confirmAndSelectCustomUserAgent(option.id);
        }
      })
    }
  }

  @Builder
  private buildDeleteSwipeAction(option: BrowserCustomUserAgentOptionView) {
    Row() {
      Button() {
        SymbolGlyph($r('sys.symbol.trash_fill'))
          .fontSize(20)
          .fontColor([this.storedSurfaceBackgroundColor])
      }
      .width(BROWSER_USER_AGENT_DELETE_BUTTON_SIZE)
      .height(BROWSER_USER_AGENT_DELETE_BUTTON_SIZE)
      .type(ButtonType.Circle)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor($r('app.color.permission_blocked'))
      .stateEffect(true)
      .accessibilityText('删除')
      .onClick(() => {
        this.confirmAndRemoveCustomUserAgent(option);
      })
    }
    .width(BROWSER_USER_AGENT_DELETE_SWIPE_WIDTH)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildCustomUserAgentSheet() {
    if (this.useCenteredSheet) {
      CenteredDialogSurface({ fillHeight: true }) {
        this.buildCustomUserAgentCenteredContent()
      }
    } else {
      BrowserBottomSheetSurface({
        fullHeight: true,
        horizontalPadding: 0,
        topPadding: 0,
        bottomPadding: 0,
        surfaceColor: this.storedPageBackgroundColor
      }) {
        BrowserImmersiveSheetLayout({
          footerVisible: true,
          scrollContent: () => {
            this.buildCustomUserAgentScrollContent(BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET)
          },
          header: () => {
            this.buildCustomUserAgentSheetHeader()
          },
          footer: () => {
            this.buildCustomUserAgentActionButton()
          }
        })
      }
    }
  }

  @Builder
  private buildCustomUserAgentSheetHeader() {
    // Keep this header in a @Builder. API 24 bindSheet crashes with
    // "class constructor cannot called without 'new'" if BrowserFeatureSheetHeader
    // is constructed directly inside a @BuilderParam arrow function.
    BrowserFeatureSheetHeader({
      title: '自定义 UA',
      leadingAccessibilityLabel: '关闭',
      onLeadingAction: () => {
        this.customUserAgentSheetVisible = false;
      }
    })
  }

  @Builder
  private buildCustomUserAgentCenteredContent() {
    Column({ space: 14 }) {
      Text('自定义 UA')
        .width('100%')
        .fontSize(21)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)

      Scroll() {
        this.buildCustomUserAgentFields(0)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .clip(false)

      this.buildCustomUserAgentActionButton()
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 18, bottom: 18 })
  }

  @Builder
  private buildCustomUserAgentScrollContent(topPadding: number) {
    Scroll() {
      this.buildCustomUserAgentFields(topPadding)
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .clip(false)
  }

  @Builder
  private buildCustomUserAgentFields(topPadding: number) {
    Column({ space: 14 }) {
      this.buildSheetTextInput(
        '名称',
        this.customUserAgentNameDraft,
        '例如：Windows Chrome',
        40,
        (value: string): void => {
          this.customUserAgentNameDraft = value;
        }
      )
      this.buildSheetUserAgentInput()

      if (this.errorMessage.length > 0) {
        Text(this.errorMessage)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor($r('app.color.permission_blocked'))
      }
    }
    .width('100%')
    .constraintSize({ minHeight: '100%' })
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .padding({ left: 16, right: 16, top: topPadding, bottom: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING })
  }

  @Builder
  private buildCustomUserAgentActionButton() {
    BrowserSheetActionButton({
      label: '保存',
      emphasis: 'primary',
      actionEnabled: !this.isSaving && this.customUserAgentValueDraft.trim().length > 0,
      onAction: (): void => {
        this.confirmAndSaveCustomUserAgent();
      }
    })
  }

  @Builder
  private buildSheetTextInput(
    label: string,
    text: string,
    placeholder: string,
    maxLength: number,
    onChange: (value: string) => void
  ) {
    Column({ space: 8 }) {
      Text(label)
        .width('100%')
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)

      TextInput({ text: text, placeholder: placeholder })
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .maxLength(maxLength)
        .backgroundColor(this.useCenteredSheet
          ? $r('sys.color.ohos_id_color_background_transparent')
          : this.storedSurfaceBackgroundColor)
        .border({
          width: { bottom: this.useCenteredSheet ? 1 : 0 },
          color: this.storedDividerColor
        })
        .borderRadius(this.useCenteredSheet ? 0 : 16)
        .padding({ left: this.useCenteredSheet ? 0 : 14, right: this.useCenteredSheet ? 0 : 14 })
        .enabled(!this.isSaving)
        .opacity(this.isSaving ? 0.48 : 1)
        .onChange((value: string) => {
          this.errorMessage = '';
          onChange(value);
        })
    }
    .width('100%')
  }

  @Builder
  private buildSheetUserAgentInput() {
    Column({ space: 8 }) {
      Text('User-Agent')
        .width('100%')
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)

      TextArea({ text: this.customUserAgentValueDraft, placeholder: '粘贴完整 User-Agent' })
        .width('100%')
        .height(160)
        .fontSize(14)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .maxLength(512)
        .backgroundColor(this.useCenteredSheet
          ? $r('sys.color.ohos_id_color_background_transparent')
          : this.storedSurfaceBackgroundColor)
        .border({
          width: { bottom: this.useCenteredSheet ? 1 : 0 },
          color: this.storedDividerColor
        })
        .borderRadius(this.useCenteredSheet ? 0 : 16)
        .padding({
          left: this.useCenteredSheet ? 0 : 14,
          right: this.useCenteredSheet ? 0 : 14,
          top: 12,
          bottom: 12
        })
        .enabled(!this.isSaving)
        .opacity(this.isSaving ? 0.48 : 1)
        .onChange((value: string) => {
          this.customUserAgentValueDraft = value;
          this.errorMessage = '';
        })
    }
    .width('100%')
  }

  @Builder
  private buildOptionSection(title: string, options: BrowserUserAgentOptionView[]) {
    SettingsSection({ title: title }) {
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          this.buildOptionRows(options)
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          this.buildOptionRows(options)
        }
      }
    }
  }

  @Builder
  private buildOptionRows(options: BrowserUserAgentOptionView[]) {
        ForEach(options, (option: BrowserUserAgentOptionView, index: number) => {
          this.buildOptionRow(option, index, options.length)
          if (index < options.length - 1) {
            if (this.desktopPresentation) {
              SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
            } else {
              SettingsGroupDivider({ dividerColor: this.storedDividerColor })
            }
          }
        }, (option: BrowserUserAgentOptionView) => option.id)
  }

  @Builder
  private buildOptionRow(option: BrowserUserAgentOptionView, index: number, total: number) {
    SettingsTargetRevealRegion({
      targetId: `user_agent_preset_${option.id}`,
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.storedAccentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      if (this.desktopPresentation) {
        SettingsDesktopOptionRow({
          title: option.title,
          isSelected: this.isPresetSelected(option.id, option.mode),
          isEnabled: !this.isSaving,
          radioGroup: 'browser-user-agent-presets',
          radioValue: option.id,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onAction: (): void => {
            this.confirmAndSavePreset(option.id);
          }
        })
      } else {
        SettingsOptionRow({
          title: option.title,
          helperText: option.subtitle,
          rowPosition: this.resolveRowPosition(index, total),
          isSelected: this.isPresetSelected(option.id, option.mode),
          isEnabled: !this.isSaving,
          onAction: (): void => {
            this.confirmAndSavePreset(option.id);
          }
        })
      }
    }
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  private syncViewStateFromProp(): void {
    this.viewState = this.state;
    this.currentSettings = sharedBrowserUserAgentSettingsRepository.getSettings();
  }

  private refreshState(): void {
    const settings = sharedBrowserUserAgentSettingsRepository.getSettings();
    this.currentSettings = settings;
    this.viewState = this.viewModel.buildState(settings);
  }

  private confirmAndSavePreset(presetId: BrowserUserAgentPresetId): void {
    const settings = this.service.buildPresetSettings(presetId, this.currentSettings);
    if (!this.service.shouldWarnForSettings(settings)) {
      this.persistSettings(settings);
      return;
    }
    this.showUserAgentRiskNotice(() => {
      this.persistSettings(settings);
    });
  }

  private confirmAndSaveCustomUserAgent(): void {
    const record = this.service.buildCustomUserAgentRecord({
      name: this.customUserAgentNameDraft,
      userAgent: this.customUserAgentValueDraft
    });
    if (record === undefined) {
      this.errorMessage = '请先输入 User-Agent。';
      return;
    }
    this.showUserAgentRiskNotice(() => {
      this.persistCustomUserAgent(this.customUserAgentNameDraft, this.customUserAgentValueDraft);
    });
  }

  private showUserAgentRiskNotice(onConfirm: () => void): void {
    const notice = this.service.getRiskNotice();
    showCenteredAlertDialog({
      title: notice.title,
      message: notice.message,
      autoCancel: true,
      primaryButton: {
        value: notice.cancelText,
        action: () => {
        }
      },
      secondaryButton: {
        value: notice.confirmText,
        action: () => {
          onConfirm();
        }
      }
    });
  }

  private persistSettings(settings: BrowserUserAgentSettings): void {
    const previousViewState = this.viewState;
    const previousSettings = this.currentSettings;
    this.currentSettings = settings;
    this.viewState = this.viewModel.buildState(settings);
    this.isSaving = true;
    this.errorMessage = '';
    this.settingsCoordinator.saveSettings(settings, this.buildBoundary())
      .then((result: BrowserUserAgentSettingsMutationResult) => {
        if (!result.allowed) {
          this.restoreFailedMutation(previousSettings, previousViewState, '当前会话不可修改全局网页标识。');
          return;
        }
        this.applySavedSettings(result.settings);
        this.onSettingsChange?.(result.settings);
        this.isSaving = false;
      })
      .catch((_error: Error) => {
        this.restoreFailedMutation(previousSettings, previousViewState, '保存失败，请稍后重试。');
      });
  }

  private persistCustomUserAgent(name: string, userAgent: string): void {
    const previousViewState = this.viewState;
    const previousSettings = this.currentSettings;
    this.isSaving = true;
    this.errorMessage = '';
    this.settingsCoordinator.upsertCustomUserAgent(name, userAgent, this.buildBoundary())
      .then((result: BrowserUserAgentSettingsMutationResult) => {
        if (!result.allowed) {
          this.restoreFailedMutation(previousSettings, previousViewState, '当前会话不可修改全局网页标识。');
          return;
        }
        this.applySavedSettings(result.settings);
        this.customUserAgentSheetVisible = false;
        this.customUserAgentNameDraft = '';
        this.customUserAgentValueDraft = '';
        this.onSettingsChange?.(result.settings);
        this.isSaving = false;
      })
      .catch((_error: Error) => {
        this.restoreFailedMutation(previousSettings, previousViewState, '保存失败，请稍后重试。');
      });
  }

  private confirmAndSelectCustomUserAgent(recordId: string): void {
    const settings = this.service.buildCustomSettings('', this.currentSettings, recordId);
    if (!this.service.shouldWarnForSettings(settings)) {
      this.selectCustomUserAgent(recordId);
      return;
    }
    this.showUserAgentRiskNotice(() => {
      this.selectCustomUserAgent(recordId);
    });
  }

  private selectCustomUserAgent(recordId: string): void {
    const previousViewState = this.viewState;
    const previousSettings = this.currentSettings;
    this.isSaving = true;
    this.errorMessage = '';
    this.settingsCoordinator.selectCustomUserAgent(recordId, this.buildBoundary())
      .then((result: BrowserUserAgentSettingsMutationResult) => {
        if (!result.allowed) {
          this.restoreFailedMutation(previousSettings, previousViewState, '当前会话不可修改全局网页标识。');
          return;
        }
        this.applySavedSettings(result.settings);
        this.onSettingsChange?.(result.settings);
        this.isSaving = false;
      })
      .catch((_error: Error) => {
        this.restoreFailedMutation(previousSettings, previousViewState, '保存失败，请稍后重试。');
      });
  }

  private confirmAndRemoveCustomUserAgent(option: BrowserCustomUserAgentOptionView): void {
    showCenteredAlertDialog({
      title: '删除自定义 UA',
      message: `删除“${option.title}”后，${this.settingsCoordinator.countCustomUserAgentReferences(option.id)} 个站点将跟随全局网页标识。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        action: () => {
          this.removeCustomUserAgent(option.id);
        }
      }
    });
  }

  private removeCustomUserAgent(recordId: string): void {
    const previousViewState = this.viewState;
    const previousSettings = this.currentSettings;
    this.isSaving = true;
    this.errorMessage = '';
    this.settingsCoordinator.removeCustomUserAgent(recordId, this.buildBoundary())
      .then((result: BrowserUserAgentSettingsMutationResult) => {
        if (!result.allowed) {
          this.restoreFailedMutation(previousSettings, previousViewState, '当前会话不可修改全局网页标识。');
          return;
        }
        this.applySavedSettings(result.settings);
        this.onSettingsChange?.(result.settings);
        this.isSaving = false;
      })
      .catch((_error: Error) => {
        this.restoreFailedMutation(previousSettings, previousViewState, '删除失败，请稍后重试。');
      });
  }

  private buildBoundary(): BrowserUserAgentSettingsBoundary {
    return new BrowserUserAgentSettingsBoundary(this.dataScope, this.privacyMode);
  }

  private restoreFailedMutation(
    settings: BrowserUserAgentSettings,
    viewState: BrowserUserAgentSettingsViewState,
    message: string
  ): void {
    this.currentSettings = settings;
    this.viewState = viewState;
    this.errorMessage = message;
    this.isSaving = false;
  }

  private dismissNotice(noticeId: string): void {
    sharedSettingsNoticeDismissalRepository.dismiss(noticeId).catch((_error: Error) => {});
  }

  private applySavedSettings(settings: BrowserUserAgentSettings): void {
    this.currentSettings = settings;
    this.viewState = this.viewModel.buildState(settings);
  }

  private isPresetSelected(presetId: BrowserUserAgentPresetId, mode: BrowserUserAgentMode): boolean {
    return this.currentSettings.defaultMode === mode && this.currentSettings.selectedPresetId === presetId;
  }

  private isCustomUserAgentSelected(): boolean {
    return this.currentSettings.defaultMode === 'custom';
  }

  private isCustomUserAgentOptionSelected(recordId: string): boolean {
    return this.isCustomUserAgentSelected() && this.currentSettings.selectedCustomUserAgentId === recordId;
  }

  private openCustomUserAgentSheet(): void {
    this.customUserAgentNameDraft = '';
    this.customUserAgentValueDraft = '';
    this.errorMessage = '';
    this.customUserAgentSheetVisible = true;
  }

  private resolveCustomUserAgentListHeight(): number {
    return Math.max(1, this.viewState.customUserAgents.length) * BROWSER_USER_AGENT_CUSTOM_ROW_HEIGHT;
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }
}
