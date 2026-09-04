import {
  createDefaultSyncExperienceViewState,
  SyncExperiencePreActiveStatusKind,
  SyncExperienceViewState
} from '../../../core/sync/SyncExperienceViewModel';
import { AiraSyncProviderKind } from '../../../common/models/AiraSyncModels';
import { PersonalizationSyncContentId } from '../../../common/models/PersonalizationSyncModels';
import {
  PersonalizationSyncItemState,
  PersonalizationSyncSettingsViewModel
} from '../../../core/sync/PersonalizationSyncSettingsViewModel';
import {
  SyncFirstActivationItemId,
  SyncFirstActivationItemsCoordinator,
  SyncFirstActivationItemsState
} from '../../../core/sync/SyncFirstActivationItemsCoordinator';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  SettingsActionButton,
  SettingsNavigationRow
} from '../settings/SettingsRows';
import { SettingsColoredTileIconResources } from '../../../core/resources/SettingsColoredTileIconResources';
import { SyncFirstActivationFlowSheet } from './SyncFirstActivationFlowSheet';
import { SyncGoalSelectionSheet } from './SyncGoalSelectionSheet';
import {
  SyncExperienceSelectionDialog,
  SyncExperienceSelectionKind
} from './SyncExperienceSelectionDialog';
import { createCenteredDialogMaterial } from '../common/CenteredDialogSurface';
import { SyncContentSwitchCard } from './SyncContentSwitchCard';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsContentKind } from '../../../core/settings/SettingsContentLayoutPolicy';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';

const DEFAULT_SYNC_EXPERIENCE_STATE: SyncExperienceViewState = createDefaultSyncExperienceViewState();

@Component
export struct SyncExperienceScreen {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string =
    DEFAULT_THEME_PALETTE.light.settingsIconForeground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop state: SyncExperienceViewState = DEFAULT_SYNC_EXPERIENCE_STATE;
  @Prop isBusy: boolean = false;
  @Prop isSyncing: boolean = false;
  @Prop airaCloudRecoveryAvailable: boolean = false;
  @Prop preActiveStatusKind: SyncExperiencePreActiveStatusKind = 'inactive';
  @Prop isPrivateSession: boolean = false;
  @Link @Watch('handleActiveSheetVisibilityChange') activeSheetVisible: boolean;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop contentKind: SettingsContentKind = 'standard';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('syncActiveSelectionPresentation') desktopGuideNavigationActive: boolean = false;
  @Prop @Watch('syncActiveSelectionPresentation') useLargeScreenSelectionDialog: boolean = false;
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  private contentScroller: Scroller = new Scroller();
  private personalizationViewModel: PersonalizationSyncSettingsViewModel =
    new PersonalizationSyncSettingsViewModel();
  private firstActivationItemsCoordinator: SyncFirstActivationItemsCoordinator =
    new SyncFirstActivationItemsCoordinator();
  @State private activeSheetKind: SyncExperienceSelectionKind = 'none';
  @State private phoneSheetVisible: boolean = false;
  @State private setupFlowActive: boolean = false;
  @State private setupFlowRevision: number = 0;
  @State private firstActivationItemsState: SyncFirstActivationItemsState =
    this.firstActivationItemsCoordinator.buildDefaultState();
  private pendingGoalRemoteKind: AiraSyncProviderKind | undefined = undefined;
  private pendingGoalItems: SyncFirstActivationItemsState | undefined = undefined;
  private pendingWebdavConfiguration: boolean = false;
  private pendingWebdavFirstActivationItems: SyncFirstActivationItemsState | undefined = undefined;
  private largeScreenSelectionDialogOpen: boolean = false;
  onBack: () => void = () => {};
  onGoalSelected: (
    remoteKind: AiraSyncProviderKind,
    firstActivationItems?: SyncFirstActivationItemsState
  ) => void = (_remoteKind: AiraSyncProviderKind, _firstActivationItems?: SyncFirstActivationItemsState) => {};
  onSetupDismissed: () => void = () => {};
  onBookmarkSelected: (enabled: boolean) => void = (_enabled: boolean) => {};
  onHistorySelected: (enabled: boolean) => void = (_enabled: boolean) => {};
  onPersonalizationItemSelected: (
    id: PersonalizationSyncContentId,
    enabled: boolean
  ) => void = (_id: PersonalizationSyncContentId, _enabled: boolean) => {};
  onSyncNow: () => void = () => {};
  onRetryStateLoad: () => void = () => {};
  onOpenAdditionalBackup: () => void = () => {};
  onOpenAiraPro: () => void = () => {};
  onOpenAdvanced: () => void = () => {};
  onRestoreAiraCloudUpgradeBackup: () => void = () => {};
  onOpenDesktopGuide: (restoreSheet: boolean) => void = (_restoreSheet: boolean) => {};
  onConfigureWebdav: (
    firstActivationItems?: SyncFirstActivationItemsState
  ) => void = (_firstActivationItems?: SyncFirstActivationItemsState) => {};
  private largeScreenSelectionDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncExperienceSelectionDialog({
      activeKind: $activeSheetKind,
      itemsState: $firstActivationItemsState,
      goalOptions: this.state.goalOptions,
      isBusy: this.isBusy,
      isPrivateSession: this.isPrivateSession,
      flowRevision: this.setupFlowRevision,
      settingsIconBackgrounds: this.settingsIconBackgrounds,
      onToggle: (id: SyncFirstActivationItemId, enabled: boolean): void => {
        this.firstActivationItemsState = this.firstActivationItemsCoordinator.updateItemEnabled(
          this.firstActivationItemsState,
          id,
          enabled
        );
      },
      onSelectGoal: (remoteKind: AiraSyncProviderKind): void => {
        this.completeGoalSelection(
          remoteKind,
          this.activeSheetKind === 'setup' ? this.firstActivationItemsState : undefined
        );
      },
      onOpenTutorial: (): void => {
        this.onOpenDesktopGuide(true);
      },
      onConfigureWebdav: (): void => {
        this.requestWebdavConfiguration(
          this.activeSheetKind === 'setup' ? this.firstActivationItemsState : undefined
        );
      },
      onClose: (): void => {
        this.dismissActiveSelectionSurface();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial()
  });

  aboutToAppear(): void {
    this.prepareRequiredSetupSheet();
    this.syncActiveSelectionPresentation();
  }

  aboutToDisappear(): void {
    this.closeLargeScreenSelectionDialog();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '同步',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: this.isPrivateSession,
        showBackButton: this.showBackButton,
        showTitleBar: this.showTitleBar,
        useTopSafeInset: this.useTopSafeInset,
        contentKind: this.contentKind,
        desktopPresentation: this.desktopPresentation,
        scrollers: [this.contentScroller],
        onBack: () => {
          this.onBack();
        }
      }) {
        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          contentSpace: 16,
          topPadding: 8,
          bottomPadding: 28,
          scroller: this.contentScroller
        }) {
          if (this.state.hasConfiguredSync) {
            this.buildCloudSyncHeader()
            this.buildSyncContentSections()
            this.buildSyncMethodSection()
            this.buildMoreSection()
            this.buildImmediateSyncAction()
          } else {
            if (this.preActiveStatusKind === 'initial-loading' ||
              this.preActiveStatusKind === 'huawei-activating') {
              this.buildPreActiveLoadingState()
            } else if (this.preActiveStatusKind === 'load-failed' ||
              this.preActiveStatusKind === 'huawei-load-failed') {
              this.buildStateLoadFailure()
            } else {
              this.buildInactiveState()
            }
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .bindSheet($$this.phoneSheetVisible, this.buildActiveSheet(), {
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: true,
      // SyncSetupStepScaffold owns the glass close button in the sheet header.
      showClose: false,
      onDisappear: () => {
        if (this.desktopGuideNavigationActive) {
          return;
        }
        this.activeSheetVisible = false;
        this.finishActiveSelectionDismissal();
      }
    })
  }

  @Builder
  private buildInactiveState() {
    Column({ space: 12 }) {
      this.buildPreActiveIcon()

      Text(this.state.statusTitle)
        .fontSize(this.desktopPresentation ? 15 : 17)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.state.statusMessage)
        .constraintSize({ maxWidth: 360 })
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)

      Column() {
        SettingsActionButton({
          title: '选择同步方式',
          variant: 'filled',
          isEnabled: !this.isPrivateSession && !this.isBusy,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.activeSheetVisible = true;
          }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .padding({ top: 8 })
    }
    .width('100%')
    .constraintSize({ minHeight: 420 })
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildStateLoadFailure() {
    Column({ space: 12 }) {
      this.buildPreActiveIcon()

      Text('暂时无法读取同步状态')
        .fontSize(this.desktopPresentation ? 15 : 17)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.preActiveStatusKind === 'huawei-load-failed'
        ? '华为云空间同步设置可能已经保存，本机数据没有丢失。请重试确认当前状态。'
        : '本机同步设置没有更改，请稍后重试。')
        .constraintSize({ maxWidth: 360 })
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)

      Column() {
        SettingsActionButton({
          title: '重试',
          variant: 'filled',
          isEnabled: !this.isPrivateSession && !this.isBusy,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onRetryStateLoad();
          }
        })
      }
      .width('100%')
      .constraintSize({ maxWidth: 360 })
      .padding({ top: 8 })
    }
    .width('100%')
    .constraintSize({ minHeight: 420 })
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPreActiveLoadingState() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(32)
        .height(32)
        .color(this.storedAccentColor)

      Text(this.preActiveStatusKind === 'huawei-activating' ? '正在开启华为云空间同步' : '正在读取同步状态')
        .fontSize(this.desktopPresentation ? 15 : 17)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.preActiveStatusKind === 'huawei-activating'
        ? '正在保存同步设置，随后会在后台完成初始化；你可以随时离开此页面。'
        : '请稍候')
        .constraintSize({ maxWidth: 360 })
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .constraintSize({ minHeight: 420 })
    .padding({ left: 24, right: 24 })
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPreActiveIcon() {
    Stack({ alignContent: Alignment.Center }) {
      Image(SettingsColoredTileIconResources.requiredForegroundIcon('sync'))
        .width(30)
        .height(30)
        .objectFit(ImageFit.Contain)
    }
    .width(60)
    .height(60)
    .backgroundColor(this.settingsIconBackgrounds.sync)
    .borderRadius(18)
    .clip(true)
  }

  @Builder
  private buildCloudSyncHeader() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Image(SettingsColoredTileIconResources.requiredForegroundIcon('sync'))
          .width(30)
          .height(30)
          .objectFit(ImageFit.Contain)
      }
      .width(60)
      .height(60)
      .backgroundColor(this.settingsIconBackgrounds.sync)
      .borderRadius(18)
      .clip(true)

      Text('云同步')
        .fontSize(this.desktopPresentation ? 15 : 19)
        .fontWeight(this.desktopPresentation ? FontWeight.Medium : FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Text(this.resolveCloudSyncDescription())
        .width('100%')
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .padding({ top: 8, bottom: 4 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildSyncMethodSection() {
    SettingsSection({ title: '同步设置', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsNavigationRow({
          title: '同步方式',
          desktopPresentation: this.desktopPresentation,
          value: this.state.goalLabel,
          icon: $r('sys.symbol.icloud_fill'),
          imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
          iconBackgroundColor: this.storedAccentColor,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'first',
          isEnabled: !this.isPrivateSession && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.openGoalSheet(false);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        if (this.state.airaCloudActive && this.airaCloudRecoveryAvailable) {
          SettingsNavigationRow({
            title: '恢复升级前书签',
            desktopPresentation: this.desktopPresentation,
            value: '恢复后关闭 Aira 云书签',
            icon: $r('sys.symbol.arrow_counterclockwise'),
            imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
            iconBackgroundColor: this.settingsIconBackgrounds.sync,
            iconColor: this.storedSettingsIconForegroundColor,
            rowPosition: 'middle',
            isEnabled: !this.isPrivateSession && !this.isBusy,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onAction: () => {
              this.onRestoreAiraCloudUpgradeBackup();
            }
          })
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        }
        SettingsNavigationRow({
          title: '跨系统互联',
          desktopPresentation: this.desktopPresentation,
          value: '查看教程',
          icon: $r('sys.symbol.link'),
          iconBackgroundColor: this.storedAccentColor,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'last',
          isEnabled: !this.isPrivateSession && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onOpenDesktopGuide(false);
          }
        })
      }
    }
  }

  @Builder
  private buildSyncContentSections() {
    SettingsSection({ title: '同步内容', secondaryTextColor: this.storedSecondaryTextColor }) {
      Grid() {
        GridItem() {
          SyncContentSwitchCard({
            desktopPresentation: this.desktopPresentation,
            title: '书签',
            checked: this.state.bookmarkSelected,
            status: this.state.huaweiSpaceBookmarkUpgradeRequired
              ? '需要重新开启'
              : (this.state.huaweiBookmarkInitializing
                ? '初始化中'
                : (this.state.bookmarkSelected ? '已开启' : '未开启')),
            icon: $r('sys.symbol.bookmark_fill'),
            iconBackgroundColor: this.settingsIconBackgrounds.sync,
            isEnabled: !this.isPrivateSession && !this.isBusy,
            onChange: (enabled: boolean) => {
              this.onBookmarkSelected(enabled);
            }
          })
        }
        GridItem() {
          SyncContentSwitchCard({
            desktopPresentation: this.desktopPresentation,
            title: '历史记录',
            checked: this.state.historySelected,
            status: !this.state.historySupported
              ? '当前方式不支持'
              : (this.state.historySelected ? '已开启' : '未开启'),
            airaIconId: 'browser.shortcut.history',
            iconBackgroundColor: this.settingsIconBackgrounds.sync,
            isEnabled: this.state.historySupported && !this.isPrivateSession && !this.isBusy,
            onChange: (enabled: boolean) => {
              this.onHistorySelected(enabled);
            }
          })
        }
        ForEach(this.state.personalizationItems, (item: PersonalizationSyncItemState) => {
          GridItem() {
            SyncContentSwitchCard({
              desktopPresentation: this.desktopPresentation,
              title: item.title,
              checked: item.enabled,
              status: item.enabled ? '已开启' : '未开启',
              icon: $r('sys.symbol.gearshape_fill'),
              imageIcon: this.resolveItemIcon(item.id),
              airaIconId: this.resolveItemAiraIcon(item.id),
              iconBackgroundColor: this.resolveItemIconBackgroundColor(item.id),
              isEnabled: !this.isPrivateSession && !this.isBusy,
              onChange: (enabled: boolean) => {
                this.onPersonalizationItemSelected(item.id, enabled);
              }
            })
          }
        }, (item: PersonalizationSyncItemState) => `${item.id}:${item.enabled ? 'on' : 'off'}`)
      }
      .columnsTemplate('1fr 1fr')
      .columnsGap(12)
      .rowsGap(12)
      .scrollBar(BarState.Off)
      .height(this.resolveContentGridHeight())
      Text(this.resolveSyncContentFooter())
        .width('100%')
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.storedSecondaryTextColor)
        .padding({ left: 6, right: 6, top: 8 })
    }
  }

  @Builder
  private buildImmediateSyncAction() {
    Column({ space: 8 }) {
      SettingsActionButton({
        title: this.resolveImmediateActionLabel(),
        variant: 'filled',
        isEnabled: (this.state.canSyncNow || this.state.requiresAiraProAction) &&
          !this.isBusy && !this.isPrivateSession,
        accentColor: this.storedAccentColor,
        pressedBackgroundColor: this.storedPressedBackgroundColor,
        onAction: () => {
          if (this.state.requiresAiraProAction) {
            this.onOpenAiraPro();
          } else {
            this.onSyncNow();
          }
        }
      })
      Text(`最近同步：${this.state.lastSyncLabel}`)
        .width('100%')
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
  }

  @Builder
  private buildMoreSection() {
    SettingsSection({ title: '更多', secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        SettingsNavigationRow({
          title: '额外备份',
          desktopPresentation: this.desktopPresentation,
          value: this.state.additionalBackupSummary,
          icon: $r('sys.symbol.externaldrive_fill'),
          imageIcon: SettingsColoredTileIconResources.foregroundIcon('sync'),
          iconBackgroundColor: this.settingsIconBackgrounds.sync,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'first',
          isEnabled: !this.isPrivateSession && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onOpenAdditionalBackup();
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '高级设置',
          desktopPresentation: this.desktopPresentation,
          value: '',
          icon: $r('sys.symbol.gearshape_fill'),
          imageIcon: SettingsColoredTileIconResources.foregroundIcon('general'),
          iconBackgroundColor: this.storedAccentColor,
          iconColor: this.storedSettingsIconForegroundColor,
          rowPosition: 'last',
          isEnabled: !this.isPrivateSession && !this.isBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.onOpenAdvanced();
          }
        })
      }
    }
  }

  private resolveContentGridHeight(): number {
    const itemCount = this.state.personalizationItems.length + 2;
    const rowCount = Math.ceil(itemCount / 2);
    const cardHeight = this.desktopPresentation ? 100 : 118;
    return rowCount * cardHeight + Math.max(0, rowCount - 1) * 12;
  }

  private resolveCloudSyncDescription(): string {
    if (!this.state.masterEnabled) {
      return '云同步已暂停，可在高级设置中重新开启。';
    }
    return '在不同设备间自动保持书签、历史记录、主页收藏、小说书架和常用设置一致。';
  }

  private resolveSyncContentFooter(): string {
    if (this.state.huaweiSpaceBookmarkUpgradeRequired) {
      return '华为云空间书签同步已升级。重新开启后会在后台完成初始化，本机书签和其他同步内容不受影响。';
    }
    if (this.state.huaweiBookmarkInitializing) {
      return '正在从华为云空间拉取并确认完整书签，可离开此页面；稍后会自动重试，也可点“立即同步”。';
    }
    return '关闭某项只会暂停该项同步，不会删除本机或云端已有数据。';
  }

  @Builder
  private buildActiveSheet() {
    if (this.activeSheetKind === 'setup') {
      SyncFirstActivationFlowSheet({
        itemsState: $firstActivationItemsState,
        goalOptions: this.state.goalOptions,
        isBusy: this.isBusy,
        isPrivateSession: this.isPrivateSession,
        flowRevision: this.setupFlowRevision,
        settingsIconBackgrounds: this.settingsIconBackgrounds,
        onToggle: (id: SyncFirstActivationItemId, enabled: boolean) => {
          this.firstActivationItemsState = this.firstActivationItemsCoordinator.updateItemEnabled(
            this.firstActivationItemsState,
            id,
            enabled
          );
        },
        onSelectGoal: (remoteKind: AiraSyncProviderKind) => {
          this.completeGoalSelection(remoteKind, this.firstActivationItemsState);
        },
        onOpenTutorial: () => {
          this.onOpenDesktopGuide(true);
        },
        onConfigureWebdav: () => {
          this.requestWebdavConfiguration(this.firstActivationItemsState);
        },
        onClose: () => {
          this.dismissActiveSelectionSurface();
        }
      })
    } else {
      SyncGoalSelectionSheet({
        options: this.state.goalOptions,
        isBusy: this.isBusy,
        isPrivateSession: this.isPrivateSession,
        radioGroup: 'sync-active-goal',
        onSelect: (remoteKind: AiraSyncProviderKind) => {
          this.completeGoalSelection(remoteKind);
        },
        onOpenTutorial: () => {
          this.onOpenDesktopGuide(true);
        },
        onConfigureWebdav: () => {
          this.requestWebdavConfiguration();
        },
        onClose: () => {
          this.dismissActiveSelectionSurface();
        }
      })
    }
  }

  private handleActiveSheetVisibilityChange(): void {
    this.prepareRequiredSetupSheet();
    this.syncActiveSelectionPresentation();
  }

  private prepareRequiredSetupSheet(): void {
    if (!this.activeSheetVisible || this.state.hasConfiguredSync || this.activeSheetKind !== 'none') {
      return;
    }
    this.firstActivationItemsState = this.firstActivationItemsCoordinator.buildStateFromExperience(
      this.state.bookmarkSelected,
      this.state.historySelected,
      this.state.personalizationItems
    );
    this.setupFlowActive = true;
    this.setupFlowRevision += 1;
    this.activeSheetKind = 'setup';
    this.activeSheetVisible = true;
  }

  private openGoalSheet(firstSetup: boolean): void {
    this.setupFlowActive = firstSetup;
    this.activeSheetKind = 'goal';
    this.activeSheetVisible = true;
  }

  private completeGoalSelection(
    remoteKind: AiraSyncProviderKind,
    firstActivationItems?: SyncFirstActivationItemsState
  ): void {
    this.pendingGoalRemoteKind = remoteKind;
    this.pendingGoalItems = firstActivationItems;
    this.setupFlowActive = false;
    this.dismissActiveSelectionSurface();
  }

  private requestWebdavConfiguration(
    firstActivationItems?: SyncFirstActivationItemsState
  ): void {
    this.pendingWebdavConfiguration = true;
    this.pendingWebdavFirstActivationItems = firstActivationItems;
    this.setupFlowActive = false;
    this.dismissActiveSelectionSurface();
  }

  private syncActiveSelectionPresentation(): void {
    if (this.useLargeScreenSelectionDialog) {
      this.phoneSheetVisible = false;
      if (this.activeSheetVisible && this.activeSheetKind !== 'none' && !this.desktopGuideNavigationActive) {
        this.openLargeScreenSelectionDialog();
      } else {
        this.closeLargeScreenSelectionDialog();
      }
      return;
    }
    this.closeLargeScreenSelectionDialog();
    this.phoneSheetVisible = this.activeSheetVisible;
  }

  private openLargeScreenSelectionDialog(): void {
    if (this.largeScreenSelectionDialogOpen) {
      return;
    }
    this.largeScreenSelectionDialogOpen = true;
    this.largeScreenSelectionDialogController.open();
  }

  private closeLargeScreenSelectionDialog(): void {
    if (!this.largeScreenSelectionDialogOpen) {
      return;
    }
    this.largeScreenSelectionDialogOpen = false;
    this.largeScreenSelectionDialogController.close();
  }

  private dismissActiveSelectionSurface(): void {
    this.activeSheetVisible = false;
    if (this.useLargeScreenSelectionDialog) {
      this.closeLargeScreenSelectionDialog();
      this.finishActiveSelectionDismissal();
      return;
    }
    this.phoneSheetVisible = false;
  }

  private finishActiveSelectionDismissal(): void {
    if (this.desktopGuideNavigationActive) {
      return;
    }
    const pendingRemoteKind = this.pendingGoalRemoteKind;
    const pendingItems = this.pendingGoalItems;
    const shouldConfigureWebdav = this.pendingWebdavConfiguration;
    const pendingWebdavFirstActivationItems = this.pendingWebdavFirstActivationItems;
    const shouldReturnToSettings = this.setupFlowActive && !this.state.hasConfiguredSync;
    this.pendingGoalRemoteKind = undefined;
    this.pendingGoalItems = undefined;
    this.pendingWebdavConfiguration = false;
    this.pendingWebdavFirstActivationItems = undefined;
    this.activeSheetKind = 'none';
    if (shouldConfigureWebdav) {
      this.onConfigureWebdav(pendingWebdavFirstActivationItems);
      return;
    }
    if (pendingRemoteKind !== undefined) {
      this.onGoalSelected(pendingRemoteKind, pendingItems);
      return;
    }
    if (shouldReturnToSettings) {
      this.setupFlowActive = false;
      this.onSetupDismissed();
    }
  }

  private resolveItemIcon(id: PersonalizationSyncContentId): Resource {
    return SettingsColoredTileIconResources.requiredForegroundIcon(
      this.personalizationViewModel.resolveItemIconKey(id)
    );
  }

  private resolveItemAiraIcon(id: PersonalizationSyncContentId): AiraRenderableIconId | undefined {
    if (id === 'novel_bookshelf') {
      return 'browser.toolbar.bookshelf';
    }
    return undefined;
  }

  private resolveItemIconBackgroundColor(id: PersonalizationSyncContentId): ResourceColor {
    return this.personalizationViewModel.resolveItemIconBackgroundColor(id, this.settingsIconBackgrounds);
  }

  private resolveImmediateActionLabel(): string {
    if (this.isSyncing || this.state.statusKind === 'syncing') {
      return '正在同步';
    }
    if (this.state.requiresAiraProAction) {
      return '恢复 Aira Pro';
    }
    return this.state.statusKind === 'attention' ? '重试' : '立即同步';
  }
}
