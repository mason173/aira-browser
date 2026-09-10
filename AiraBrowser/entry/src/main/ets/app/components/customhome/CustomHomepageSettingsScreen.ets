import { common } from '@kit.AbilityKit';
import {
  createCenteredDialogMaterial,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import {
  CustomHomepageExternalImportPresentationHost,
  CustomHomepageImportResult,
  CustomHomepageRemoteAddResult,
  CustomHomepageSettingsCoordinator
} from '../../../core/customhome/CustomHomepageSettingsCoordinator';
import {
  CustomHomepageRemoteWarmupCoordinator,
  CustomHomepageRemoteWarmupResult,
  CustomHomepageRemoteWarmupTask
} from '../../../core/customhome/CustomHomepageRemoteWarmupCoordinator';
import {
  CustomHomepageChoiceViewState,
  CustomHomepageRemoteRefreshTargetViewState,
  CustomHomepageSettingsViewModel,
  CustomHomepageSettingsViewState
} from '../../../core/customhome/CustomHomepageSettingsViewModel';
import {
  CustomHomepagePreviewLayoutState,
  CustomHomepagePreviewState,
  CustomHomepagePreviewViewModel
} from '../../../core/customhome/CustomHomepagePreviewViewModel';
import {
  CustomHomepageInfoViewModel,
  CustomHomepageInfoViewState
} from '../../../core/customhome/CustomHomepageInfoViewModel';
import {
  sharedBrowserThemeModeCoordinator,
  sharedCustomHomepageRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import { SettingsHdsMenuAction, SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsActionButton,
  SettingsNavigationRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody,
  SettingsSectionTitle
} from '../settings/SettingsLayout';
import {
  SettingsDesktopActionButton,
  SettingsDesktopDivider,
  SettingsDesktopGroup,
  SettingsDesktopNavigationRow,
  SettingsDesktopSwitchRow
} from '../settings/SettingsDesktopRows';
import {
  SettingsDesktopWorkspaceHeader,
  SettingsDesktopWorkspaceHeaderAction
} from '../settings/SettingsDesktopWorkspaceHeader';
import { CustomHomepagePreviewCards } from './CustomHomepagePreviewCards';
import { CustomHomepageInfoSheet } from './CustomHomepageInfoSheet';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SettingsNavigationCoordinator,
  SettingsRouteParams
} from '../../router/SettingsNavigationCoordinator';
import {
  SyncOperationProgressController,
  SyncOperationProgressUiState
} from '../../../core/sync/SyncOperationProgressController';
import { SyncOperationProgressDialog } from '../sync/SyncOperationProgressDialog';
import { CustomHomepageFullscreenPreview } from './CustomHomepageFullscreenPreview';
import { CustomHomepageRemoteWarmupHost } from './CustomHomepageRemoteWarmupHost';
import {
  CustomHomepageUrlService,
  CustomHomepageUrlValidationResult
} from '../../../services/customhome/CustomHomepageUrlService';
import { BrowserResolvedThemeMode } from '../../../common/models/BrowserModels';
import { BrowserHomepageBackdropAppearanceState } from '../../../common/models/BackdropAppearanceModels';
import { CustomHomepageItem } from '../../../common/models/CustomHomepageModels';
import {
  CustomHomepageSiteIconHydrationCoordinator,
  CustomHomepageSiteIconHydrationResult
} from '../../../core/customhome/CustomHomepageSiteIconHydrationCoordinator';
import { CustomHomepageRemoteUrlDialog } from './CustomHomepageRemoteUrlDialog';
import { CustomHomepageSettingsPageBinding } from '../../../core/customhome/CustomHomepageSettingsPageBinding';
import { CustomHomepageEnvironmentService } from '../../../services/customhome/CustomHomepageEnvironmentService';
const CUSTOM_HOMEPAGE_SITE_ICON_CACHE_LIMIT: number = 24;
const CUSTOM_HOMEPAGE_SITE_ICON_NETWORK_PREFETCH_LIMIT: number = 4;
type RemoteHomepageWarmupPurpose = 'add' | 'refresh';
export type CustomHomepageSettingsPresentationMode = 'standalone' | 'embedded';

@Component
export struct CustomHomepageSettingsScreen {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: CustomHomepageSettingsViewModel = new CustomHomepageSettingsViewModel();
  private previewViewModel: CustomHomepagePreviewViewModel = new CustomHomepagePreviewViewModel();
  private environmentService: CustomHomepageEnvironmentService = new CustomHomepageEnvironmentService();
  private infoViewModel: CustomHomepageInfoViewModel = new CustomHomepageInfoViewModel();
  private warmupCoordinator: CustomHomepageRemoteWarmupCoordinator = new CustomHomepageRemoteWarmupCoordinator();
  private siteIconHydrationCoordinator: CustomHomepageSiteIconHydrationCoordinator =
    new CustomHomepageSiteIconHydrationCoordinator();
  private urlService: CustomHomepageUrlService = new CustomHomepageUrlService();
  private coordinator: CustomHomepageSettingsCoordinator =
    new CustomHomepageSettingsCoordinator(sharedCustomHomepageRepository);
  @Prop presentationMode: CustomHomepageSettingsPresentationMode = 'standalone';
  @Prop desktopPresentation: boolean = false;
  pageBinding: CustomHomepageSettingsPageBinding = new CustomHomepageSettingsPageBinding();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('handleResolvedThemeModeChanged')
  private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '';
  @State private state: CustomHomepageSettingsViewState =
    this.buildThemedState();
  @State private selectedChoiceId: string = this.resolveSelectedChoiceId(this.state);
  @State private homepageListRevision: number = 0;
  @State private busy: boolean = false;
  @State private systemChromeBusy: boolean = false;
  @State private remoteHomepageUrlDraft: string = '';
  @State private remoteHomepageUrlError: string = '';
  @State private remoteHomepageWarmupTask: CustomHomepageRemoteWarmupTask | undefined = undefined;
  @State private remoteHomepageWarmupPurpose: RemoteHomepageWarmupPurpose = 'add';
  @State private remoteHomepageProgressTitle: string = '';
  @State private remoteHomepageProgressSubtitle: string = '';
  @State private remoteHomepageProgressValue: number = 0;
  @State private remoteHomepageProgressInProgress: boolean = false;
  @State private remoteHomepageProgressDetailsText: string = '';
  @State private remoteHomepageProgressDetailOpacity: number = 1;
  @State private previewState: CustomHomepagePreviewState = this.previewViewModel.buildInitialState();
  @State private homepageInfoSheetVisible: boolean = false;
  @State private homepageInfoState: CustomHomepageInfoViewState = this.infoViewModel.buildInitialState();
  @State private homepageInfoActionLabel: string = '';
  @State private homepageInfoActionEnabled: boolean = true;
  @State private previewViewportWidth: number = 390;
  @State private previewViewportHeight: number = 844;
  @State private previewAvailableWidth: number = 358;
  @State private previewLayoutState: CustomHomepagePreviewLayoutState = this.previewViewModel.buildLayoutState({
    formFactor: this.environmentService.resolveNativeState().formFactor,
    viewportWidth: 390,
    viewportHeight: 844,
    availableWidth: 358
  });
  private siteIconScheduleVersion: number = 0;
  private externalImportPresentationHost: CustomHomepageExternalImportPresentationHost = {
    presentPrepared: (item: CustomHomepageItem, actionLabel: string): void => {
      this.homepageInfoActionLabel = actionLabel;
      this.homepageInfoActionEnabled = true;
      this.homepageInfoState = this.infoViewModel.buildState(item);
      this.homepageInfoSheetVisible = true;
    },
    presentFailure: (message: string): void => {
      this.presentExternalImportFailure(message);
    },
    setActionEnabled: (enabled: boolean): void => {
      this.homepageInfoActionEnabled = enabled;
    },
    dismiss: (): void => {
      this.resetHomepageInfoPresentation();
    },
    notifyCommitted: (result: CustomHomepageImportResult): void => {
      this.refreshHomepagePresentationAfterExternalImport();
      this.showToast(result.updated ? '已更新自定义主页' : '已导入自定义主页');
    },
    notifyCommitFailure: (message: string): void => {
      this.showToast(`导入主页失败：${message}`);
      this.refreshState();
    }
  };
  private remoteHomepageProgressDialogOpen: boolean = false;
  private remoteHomepageRefreshQueue: CustomHomepageRemoteRefreshTargetViewState[] = [];
  private remoteHomepageRefreshTotalCount: number = 0;
  private remoteHomepageRefreshFinishedCount: number = 0;
  private remoteHomepageRefreshSucceededCount: number = 0;
  private remoteHomepageUrlDialogController: CustomDialogController = new CustomDialogController({
    builder: CustomHomepageRemoteUrlDialog({
      urlDraft: $remoteHomepageUrlDraft,
      errorText: $remoteHomepageUrlError,
      accentColor: this.storedAccentColor,
      controlBackgroundColor: this.storedControlBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      confirm: () => {
        return this.addRemoteHomepage();
      }
    }),
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    autoCancel: true
  });
  private remoteHomepageProgressDialogController: CustomDialogController = new CustomDialogController({
    builder: SyncOperationProgressDialog({
      inProgress: $remoteHomepageProgressInProgress,
      title: $remoteHomepageProgressTitle,
      subtitle: $remoteHomepageProgressSubtitle,
      progress: $remoteHomepageProgressValue,
      details: $remoteHomepageProgressDetailsText,
      detailOpacity: $remoteHomepageProgressDetailOpacity
    }),
    alignment: DialogAlignment.Center,
    autoCancel: false,
    customStyle: false,
    systemMaterial: createCenteredDialogMaterial(),
    onWillDismiss: (dismissDialogAction: DismissDialogAction) => {
      if (!this.remoteHomepageProgressInProgress) {
        dismissDialogAction.dismiss();
      }
    }
  });
  private remoteHomepageProgressController: SyncOperationProgressController = new SyncOperationProgressController(
    (state: SyncOperationProgressUiState): void => {
      this.remoteHomepageProgressTitle = state.title;
      this.remoteHomepageProgressSubtitle = state.subtitle;
      this.remoteHomepageProgressValue = state.progress;
      this.remoteHomepageProgressInProgress = state.inProgress;
      this.remoteHomepageProgressDetailsText = state.details;
      this.remoteHomepageProgressDetailOpacity = state.detailOpacity;
    },
    (): boolean => this.remoteHomepageProgressDialogOpen,
    (): void => {
      this.openRemoteHomepageProgressDialog();
    },
    (): void => {
      this.closeRemoteHomepageProgressDialog();
    },
    (_title: string, _subtitle: string): void => {}
  );

  aboutToAppear(): void {
    this.pageBinding.attach(
      (): boolean => this.handleBackRequest(),
      (): void => this.handlePageShow()
    );
    this.coordinator.attachExternalImportPresentation(this.externalImportPresentationHost);
    this.refreshState();
    this.refreshPreviewWindowViewport();
  }

  private handlePageShow(): void {
    this.refreshState();
    this.refreshPreviewWindowViewport();
    this.coordinator.consumePendingExternalImportPresentation();
  }

  aboutToDisappear(): void {
    this.pageBinding.detach();
    this.coordinator.detachExternalImportPresentation();
    this.remoteHomepageProgressController.dispose();
  }

  private handleResolvedThemeModeChanged(): void {
    this.state = this.buildThemedState();
    this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
    this.bumpHomepageListRevision();
  }

  onBackPress(): boolean {
    return this.handleBackRequest();
  }

  private handleBackRequest(): boolean {
    if (this.remoteHomepageProgressDialogOpen && this.remoteHomepageProgressInProgress) {
      return true;
    }
    if (this.homepageInfoSheetVisible) {
      this.homepageInfoSheetVisible = false;
      return true;
    }
    if (this.previewState.choiceId.length <= 0) {
      return false;
    }
    this.requestCloseHomepagePreview();
    return true;
  }

  build() {
    Stack() {
      if (this.presentationMode === 'embedded') {
        this.buildEmbeddedSettingsSurface()
      } else {
        SettingsHdsScaffold({
          title: '自定义主页',
          backIconKind: 'back',
          pageBackground: this.storedPageBackgroundColor,
          headerButtonBackground: this.storedPressedBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          dividerColor: this.storedDividerColor,
          menuActions: this.buildHeaderActions(),
          onBack: () => {
            this.handlePageBack();
          }
        }) {
          this.buildSettingsScrollBody(16, 36)
        }
      }

      if (this.previewState.choiceId.length > 0 && this.resolvePreviewChoiceIndex() >= 0) {
        CustomHomepageFullscreenPreview({
          choices: this.state.choices,
          initialIndex: this.resolvePreviewChoiceIndex(),
          selectedChoiceId: this.selectedChoiceId,
          busy: this.busy,
          closingTrigger: this.previewState.closeTrigger,
          onClose: () => {
            this.requestCloseHomepagePreview();
          },
          onClosed: () => {
            this.closeHomepagePreview();
          },
          onUse: (choice: CustomHomepageChoiceViewState) => {
            this.usePreviewHomepage(choice);
          }
        })
      }
      if (this.remoteHomepageWarmupTask !== undefined) {
        CustomHomepageRemoteWarmupHost({
          task: this.remoteHomepageWarmupTask,
          hostIdPrefix: 'settings',
          onFinished: (result: CustomHomepageRemoteWarmupResult) => {
            this.handleRemoteHomepageWarmupFinished(result);
          }
        })
        .zIndex(-100)
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .onAreaChange((_oldArea: Area, _newArea: Area) => {
      this.refreshPreviewWindowViewport();
    })
    .bindSheet($$this.homepageInfoSheetVisible, this.buildHomepageInfoSheet(), {
      // Embedded on large screen: center the info sheet instead of a bottom sheet.
      preferType: this.presentationMode === 'embedded' ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: this.presentationMode !== 'embedded',
      showClose: true,
      onDisappear: () => {
        this.handleHomepageInfoSheetDisappear();
      }
    })
  }

  @Builder
  private buildEmbeddedSettingsSurface() {
    Column({ space: 12 }) {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '自定义主页',
          showTitle: false,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          primaryActionText: '添加网址',
          primaryActionLabel: '添加网址主页',
          primaryActionEnabled: !this.busy,
          menuActions: this.buildDesktopHeaderActions(),
          onPrimaryAction: () => {
            this.openRemoteHomepageDialog();
          }
        })
      } else {
        Row({ space: 10 }) {
          Button('导入主页')
            .height(36)
            .type(ButtonType.Normal)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontSize(14)
            .fontColor(this.storedPrimaryTextColor)
            .backgroundColor(this.storedPressedBackgroundColor)
            .borderRadius(12)
            .enabled(!this.busy)
            .onClick(() => {
              this.importHtmlFile();
            })

          Button('添加网址')
            .height(36)
            .type(ButtonType.Normal)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontSize(14)
            .fontColor(this.storedPrimaryTextColor)
            .backgroundColor(this.storedPressedBackgroundColor)
            .borderRadius(12)
            .enabled(!this.busy)
            .onClick(() => {
              this.openRemoteHomepageDialog();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .justifyContent(FlexAlign.End)
      }

      this.buildSettingsScrollBody(0, 28)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4 })
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildSettingsScrollBody(topPadding: number, bottomPadding: number) {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: topPadding,
      bottomPadding: bottomPadding
    }) {
      this.buildHomepageListSection()
      this.buildHomepageChromeSection()
      this.buildHomepageBehaviorSection()
      this.buildHomepageMaintenanceSection()
      this.buildRestoreSystemHomepageSection()
      this.buildDeveloperGuideEntry()
    }
  }

  @Builder
  private buildHomepageInfoSheet() {
    CustomHomepageInfoSheet({
      state: this.homepageInfoState,
      presentation: this.presentationMode === 'embedded' ? 'centered' : 'bottom_sheet',
      actionLabel: this.homepageInfoActionLabel,
      actionEnabled: this.homepageInfoActionEnabled,
      onAction: () => {
        this.coordinator.commitPresentedExternalHomepageImport();
      }
    })
  }

  @Builder
  private buildDeveloperGuideEntry() {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsDesktopNavigationRow({
          title: '自定义主页开发文档',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onAction: () => {
            this.openDeveloperGuide();
          }
        })
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsNavigationRow({
          title: '自定义主页开发文档',
          rowPosition: 'single',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.openDeveloperGuide();
          }
        })
      }
    }
  }

  @Builder
  private buildHomepageListSection() {
    Column({ space: 12 }) {
      CustomHomepagePreviewCards({
        choices: this.state.choices,
        selectedChoiceId: this.selectedChoiceId,
        revision: this.homepageListRevision,
        busy: this.busy,
        layoutState: this.previewLayoutState,
        onSelect: (choice: CustomHomepageChoiceViewState) => {
          this.openHomepagePreview(choice);
        },
        onImport: () => {
          this.importHtmlFile();
        },
        onInfo: (choice: CustomHomepageChoiceViewState) => {
          this.openHomepageInfo(choice);
        },
        onExport: (choice: CustomHomepageChoiceViewState) => {
          this.exportCustomHomepage(choice);
        },
        onRemove: (choice: CustomHomepageChoiceViewState) => {
          this.removeCustomHomepage(choice);
        }
      })
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextAvailableWidth = this.parseAreaDimension(newArea.width);
      if (nextAvailableWidth !== this.previewAvailableWidth) {
        this.previewAvailableWidth = nextAvailableWidth;
        this.refreshPreviewLayoutState();
      }
    })
  }

  @Builder
  private buildHomepageChromeSection() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '主页系统入口',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          this.buildDesktopHomepageChromeRows()
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          this.buildTouchHomepageChromeRows()
        }
      }
      SettingsFooterText({
        text: '以上设置按当前选中的第三方主页单独保存；系统入口按钮仅在第三方主页上显示。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildTouchHomepageChromeRows() {
        SettingsSwitchRow({
          title: '在此主页显示系统搜索',
          checked: this.state.showSystemSearchBar,
          rowPosition: 'first',
          isEnabled: this.areCustomHomepageChromeControlsEnabled(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateSelectedHomepageSearchBar(checked);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '滚动时显示或隐藏',
          checked: this.state.hideToolbarOnScroll,
          rowPosition: 'middle',
          isEnabled: this.areCustomHomepageChromeControlsEnabled() && this.state.showSystemSearchBar,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateSelectedHomepageHideToolbarOnScroll(checked);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '显示系统入口按钮',
          checked: this.state.showSystemEntryButton,
          rowPosition: 'last',
          isEnabled: this.areCustomHomepageChromeControlsEnabled(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateSystemEntryButton(checked);
          }
        })
  }

  @Builder
  private buildDesktopHomepageChromeRows() {
    SettingsDesktopSwitchRow({
      title: '在此主页显示系统搜索',
      checked: this.state.showSystemSearchBar,
      isEnabled: this.areCustomHomepageChromeControlsEnabled(),
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      hoverBackgroundColor: this.storedPressedBackgroundColor,
      focusColor: this.storedAccentColor,
      onChange: (checked: boolean) => {
        this.updateSelectedHomepageSearchBar(checked);
      }
    })
    SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
    SettingsDesktopSwitchRow({
      title: '滚动时显示或隐藏',
      checked: this.state.hideToolbarOnScroll,
      isEnabled: this.areCustomHomepageChromeControlsEnabled() && this.state.showSystemSearchBar,
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      hoverBackgroundColor: this.storedPressedBackgroundColor,
      focusColor: this.storedAccentColor,
      onChange: (checked: boolean) => {
        this.updateSelectedHomepageHideToolbarOnScroll(checked);
      }
    })
    SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
    SettingsDesktopSwitchRow({
      title: '显示系统入口按钮',
      checked: this.state.showSystemEntryButton,
      isEnabled: this.areCustomHomepageChromeControlsEnabled(),
      primaryTextColor: this.storedPrimaryTextColor,
      secondaryTextColor: this.storedSecondaryTextColor,
      hoverBackgroundColor: this.storedPressedBackgroundColor,
      focusColor: this.storedAccentColor,
      onChange: (checked: boolean) => {
        this.updateSystemEntryButton(checked);
      }
    })
  }

  @Builder
  private buildHomepageBehaviorSection() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '网址主页外观',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsDesktopSwitchRow({
            title: '尝试强制深色模式',
            checked: this.state.forceDarkRemoteUrlHomepage,
            isEnabled: this.areRemoteUrlAppearanceRowsEnabled(),
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            hoverBackgroundColor: this.storedPressedBackgroundColor,
            focusColor: this.storedAccentColor,
            onChange: (checked: boolean) => {
              this.updateForceDarkRemoteUrlHomepage(checked);
            }
          })
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsSwitchRow({
          title: '尝试强制深色模式',
          checked: this.state.forceDarkRemoteUrlHomepage,
          rowPosition: 'single',
          isEnabled: this.areRemoteUrlAppearanceRowsEnabled(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateForceDarkRemoteUrlHomepage(checked);
          }
          })
        }
      }
      SettingsFooterText({
        text: '强制深色模式仅对网址主页生效。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildHomepageMaintenanceSection() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '维护',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      if (this.desktopPresentation) {
        SettingsDesktopActionButton({
          title: '刷新主页预览图',
          isEnabled: true,
          accentColor: this.storedAccentColor,
          onAccentColor: this.storedOnPrimaryColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.refreshRemoteHomepagePreviews();
          }
        })
      } else {
        SettingsActionButton({
          title: '刷新主页预览图',
          isEnabled: true,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.refreshRemoteHomepagePreviews();
          }
        })
      }
      SettingsFooterText({
        text: '会重新生成所有网址主页的预览图。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
    .width('100%')
    .padding({ top: 4, left: 8, right: 8 })
  }

  @Builder
  private buildRestoreSystemHomepageSection() {
    Column({ space: 10 }) {
      if (this.desktopPresentation) {
        SettingsDesktopActionButton({
          title: '恢复系统主页',
          isEnabled: !this.busy && !this.state.systemHomepageSelected,
          accentColor: this.storedAccentColor,
          onAccentColor: this.storedOnPrimaryColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.requestRestoreSystemHomepage();
          }
        })
      } else {
        SettingsActionButton({
          title: '恢复系统主页',
          isEnabled: !this.busy && !this.state.systemHomepageSelected,
          accentColor: this.storedAccentColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.requestRestoreSystemHomepage();
          }
        })
      }
      SettingsFooterText({
        text: this.state.systemHomepageSelected
          ? '当前正在使用 Aira 原生主页。'
          : '停止使用当前自定义主页，恢复 Aira 原生主页。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
    .width('100%')
    .padding({ top: 4, left: 8, right: 8 })
  }

  private buildHeaderActions(): SettingsHdsMenuAction[] {
    return [{
      label: '导入主页',
      airaIconId: 'browser.tabs.add',
      enabled: !this.busy,
      action: () => {
        this.importHtmlFile();
      }
    }, {
      label: '添加网址',
      airaIconId: 'browser.toolbar.copyLink',
      enabled: !this.busy,
      action: () => {
        this.openRemoteHomepageDialog();
      }
    }, {
      label: '开发文档',
      airaIconId: 'browser.toolbar.savedPages',
      enabled: true,
      action: () => {
        this.openDeveloperGuide();
      }
    }];
  }

  private buildDesktopHeaderActions(): SettingsDesktopWorkspaceHeaderAction[] {
    return [{
      label: '导入主页',
      action: () => {
        if (!this.busy) {
          this.importHtmlFile();
        }
      }
    }, {
      label: '开发文档',
      action: () => {
        this.openDeveloperGuide();
      }
    }];
  }

  private handlePageBack(): void {
    if (this.remoteHomepageProgressDialogOpen && this.remoteHomepageProgressInProgress) {
      return;
    }
    if (this.previewState.choiceId.length > 0) {
      this.requestCloseHomepagePreview();
      return;
    }
    this.navigationCoordinator.back();
  }

  private openDeveloperGuide(): void {
    this.navigationCoordinator.openCustomHomepageDeveloperGuide({
      dataScope: '',
      privacyMode: '',
      boundarySource: 'custom_homepage_settings'
    }, () => {
      this.showToast('开发文档暂时无法打开，请稍后重试。');
    });
  }

  private openHomepageInfo(choice: CustomHomepageChoiceViewState): void {
    const item = this.coordinator.findItem(choice.id);
    if (item === undefined) {
      this.showToast('自定义主页信息不可用。');
      return;
    }
    this.homepageInfoActionLabel = '';
    this.homepageInfoActionEnabled = true;
    this.homepageInfoState = this.infoViewModel.buildState(item);
    this.homepageInfoSheetVisible = true;
  }

  private presentExternalImportFailure(message: string): void {
    this.resetHomepageInfoPresentation();
    setTimeout(() => {
      showCenteredAlertDialog({
        title: '无法导入主页',
        message: message,
        autoCancel: true,
        confirm: {
          value: '知道了',
          action: () => {}
        }
      });
    }, 0);
  }

  private refreshHomepagePresentationAfterExternalImport(): void {
    this.state = this.buildThemedState();
    this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
    this.bumpHomepageListRevision();
  }

  private handleHomepageInfoSheetDisappear(): void {
    this.coordinator.dismissPresentedExternalHomepageImport();
    this.resetHomepageInfoPresentation();
  }

  private resetHomepageInfoPresentation(): void {
    this.homepageInfoSheetVisible = false;
    this.homepageInfoActionLabel = '';
    this.homepageInfoActionEnabled = true;
  }

  private openHomepagePreview(choice: CustomHomepageChoiceViewState): void {
    this.previewState = this.previewViewModel.openPreview(this.previewState, choice, this.busy);
    void this.resolveSiteIconForChoice(choice, true);
  }

  private requestCloseHomepagePreview(): void {
    this.previewState = this.previewViewModel.requestClose(this.previewState);
  }

  private closeHomepagePreview(): void {
    this.previewState = this.previewViewModel.finishClose(this.previewState);
  }

  private resolvePreviewChoiceIndex(): number {
    return this.previewViewModel.resolvePreviewChoiceIndex(this.state.choices, this.previewState.choiceId);
  }

  private usePreviewHomepage(choice: CustomHomepageChoiceViewState): void {
    if (this.busy) {
      return;
    }
    showCenteredAlertDialog({
      title: '使用该主页',
      message: `确定使用“${choice.title}”作为主页？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '确定',
        action: () => {
          this.applyPreviewHomepage(choice);
        }
      }
    });
  }

  private applyPreviewHomepage(choice: CustomHomepageChoiceViewState): void {
    if (this.busy) {
      return;
    }
    if (choice.id === this.selectedChoiceId) {
      this.closeHomepagePreview();
      this.returnToBrowserHome();
      return;
    }
    const previousState = this.state;
    const previousSelectedChoiceId = this.selectedChoiceId;
    this.applySelectedChoiceId(choice.id);
    this.runSelectionAction(
      this.coordinator.selectCustomHomepage(choice.id),
      previousState,
      previousSelectedChoiceId,
      '已切换为自定义主页',
      '切换主页失败',
      true
    );
  }

  private returnToBrowserHome(): void {
    const params = this.previewViewModel.buildReturnHomeRouteParams();
    const routeParams: SettingsRouteParams = {
      dataScope: params.dataScope,
      privacyMode: params.privacyMode,
      boundarySource: params.boundarySource,
      returnHome: params.returnHome,
      returnHomeToken: params.returnHomeToken
    };
    this.navigationCoordinator.backToBrowserShell(routeParams);
  }

  private refreshState(): void {
    this.coordinator.ensureReady()
      .then(() => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
        this.scheduleSiteIconHydration();
      })
      .catch((error: Error) => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
        this.scheduleSiteIconHydration();
      });
  }

  private importHtmlFile(): void {
    if (this.busy) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.busy = true;
    this.coordinator.importCustomHomepage(context)
      .then((result: CustomHomepageImportResult) => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
        if (result.imported) {
          this.showToast(result.updated ? '已更新自定义主页' : '已导入自定义主页');
        }
      })
      .catch((error: Error) => {
        this.showToast(`导入主页失败：${this.stringifyError(error)}`);
        this.refreshState();
      })
      .finally(() => {
        this.busy = false;
      });
  }

  private exportCustomHomepage(choice: CustomHomepageChoiceViewState): void {
    if (this.busy) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.busy = true;
    this.coordinator.exportCustomHomepage(context, choice.id)
      .then((exported: boolean) => {
        if (exported) {
          this.showToast(`已导出“${choice.title}”`);
        }
      })
      .catch((error: Error) => {
        this.showToast(`导出主页失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  private openRemoteHomepageDialog(): void {
    if (this.busy) {
      return;
    }
    this.remoteHomepageUrlDraft = '';
    this.remoteHomepageUrlError = '';
    this.remoteHomepageUrlDialogController.open();
  }

  private addRemoteHomepage(): boolean {
    if (this.busy) {
      return false;
    }
    const validation: CustomHomepageUrlValidationResult =
      this.urlService.validateRemoteHomepageUrl(this.remoteHomepageUrlDraft);
    if (!validation.valid) {
      this.remoteHomepageUrlError = validation.errorMessage;
      return false;
    }
    this.busy = true;
    this.remoteHomepageUrlDialogController.close();
    this.remoteHomepageProgressController.begin('正在准备主页', '正在后台打开网页');
    this.coordinator.addRemoteHomepage(validation.normalizedUrl)
      .then((result: CustomHomepageRemoteAddResult) => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
        this.scheduleSiteIconHydration();
        this.remoteHomepageProgressController.update('正在准备主页', '正在生成预览图', 36);
        this.remoteHomepageWarmupPurpose = 'add';
        this.remoteHomepageWarmupTask = this.warmupCoordinator.buildTask(result.itemId, result.url);
      })
      .catch((error: Error) => {
        this.busy = false;
        this.remoteHomepageProgressController.complete();
        this.showToast(`添加失败：${this.stringifyError(error)}`);
      });
    return false;
  }

  private updateSystemEntryButton(visible: boolean): void {
    if (!this.areCustomHomepageChromeControlsEnabled() || this.state.showSystemEntryButton === visible) {
      return;
    }
    const previousState = this.state;
    this.applySystemEntryButtonState(visible);
    this.runSystemChromeAction(
      this.coordinator.updateSelectedHomepageSystemEntryButton(visible),
      previousState,
      visible ? '已显示系统入口按钮' : '已隐藏系统入口按钮',
      '更新系统入口按钮失败'
    );
  }

  private updateSelectedHomepageSearchBar(visible: boolean): void {
    if (!this.areCustomHomepageChromeControlsEnabled() || this.state.showSystemSearchBar === visible) {
      return;
    }
    const previousState = this.state;
    this.state = this.viewModel.withSystemSearchBar(this.state, visible);
    this.runSystemChromeAction(
      this.coordinator.updateSelectedHomepageSearchBar(visible),
      previousState,
      visible ? '已在此主页显示系统搜索' : '已在此主页隐藏系统搜索',
      '更新系统搜索失败'
    );
  }

  private updateSelectedHomepageHideToolbarOnScroll(enabled: boolean): void {
    if (!this.areCustomHomepageChromeControlsEnabled() || !this.state.showSystemSearchBar ||
      this.state.hideToolbarOnScroll === enabled) {
      return;
    }
    const previousState = this.state;
    this.state = this.viewModel.withHideToolbarOnScroll(this.state, enabled);
    this.runSystemChromeAction(
      this.coordinator.updateSelectedHomepageHideToolbarOnScroll(enabled),
      previousState,
      enabled ? '当前主页已启用滚动显示或隐藏' : '当前主页已关闭滚动显示或隐藏',
      '更新滚动显示设置失败'
    );
  }

  private updateForceDarkRemoteUrlHomepage(enabled: boolean): void {
    if (!this.areRemoteUrlAppearanceRowsEnabled() || this.state.forceDarkRemoteUrlHomepage === enabled) {
      return;
    }
    const previousState = this.state;
    this.applyRemoteUrlAppearanceState(enabled);
    this.runSystemChromeAction(
      this.coordinator.updateSelectedHomepageForceDarkMode(enabled),
      previousState,
      enabled ? '网址主页强制深色已开启' : '网址主页将尊重网页原本外观',
      '更新网址主页外观失败'
    );
  }

  private requestRestoreSystemHomepage(): void {
    if (this.busy || this.state.systemHomepageSelected) {
      return;
    }
    showCenteredAlertDialog({
      title: '恢复系统主页',
      message: '确定停止使用当前自定义主页并恢复 Aira 原生主页吗？已添加的自定义主页不会被删除，之后仍可重新选择。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '恢复',
        action: () => {
          this.restoreSystemHomepage();
        }
      }
    });
  }

  private restoreSystemHomepage(): void {
    if (this.busy || this.state.systemHomepageSelected) {
      return;
    }
    this.runAction(
      this.coordinator.selectSystemHomepage(),
      '已恢复系统主页',
      '恢复系统主页失败'
    );
  }

  private refreshRemoteHomepagePreviews(): void {
    if (this.busy || this.remoteHomepageWarmupTask !== undefined || this.remoteHomepageRefreshQueue.length > 0) {
      this.showToast('预览图正在刷新，请稍候。');
      return;
    }
    const targets = this.viewModel.resolveRemoteHomepagePreviewRefreshTargets(this.state);
    if (targets.length <= 0) {
      this.showToast('请先添加一个网址主页。');
      return;
    }
    this.busy = true;
    this.remoteHomepageWarmupPurpose = 'refresh';
    this.remoteHomepageRefreshQueue = targets;
    this.remoteHomepageRefreshTotalCount = targets.length;
    this.remoteHomepageRefreshFinishedCount = 0;
    this.remoteHomepageRefreshSucceededCount = 0;
    this.remoteHomepageProgressController.begin('正在刷新预览图', '正在后台打开网页');
    this.startNextRemoteHomepageRefreshTask();
  }

  private removeCustomHomepage(choice: CustomHomepageChoiceViewState): void {
    if (this.busy) {
      return;
    }
    showCenteredAlertDialog({
      title: '删除自定义主页',
      message: `确定删除“${choice.title}”吗？删除后无法恢复。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.confirmRemoveCustomHomepage(choice.id);
        }
      }
    });
  }

  private confirmRemoveCustomHomepage(itemId: string): void {
    if (this.busy) {
      return;
    }
    this.runAction(
      this.coordinator.removeCustomHomepage(itemId),
      '已删除自定义主页',
      '删除自定义主页失败'
    );
  }

  private runAction(
    action: Promise<void>,
    successMessage: string,
    failurePrefix: string
  ): void {
    this.busy = true;
    action
      .then(() => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
        this.scheduleSiteIconHydration();
        this.showToast(successMessage);
      })
      .catch((error: Error) => {
        this.showToast(`${failurePrefix}：${this.stringifyError(error)}`);
        this.refreshState();
      })
      .finally(() => {
        this.busy = false;
      });
  }

  private runSystemChromeAction(
    action: Promise<void>,
    previousState: CustomHomepageSettingsViewState,
    successMessage: string,
    failurePrefix: string
  ): void {
    this.systemChromeBusy = true;
    action
      .then(() => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.showToast(successMessage);
      })
      .catch((error: Error) => {
        this.state = previousState;
        this.selectedChoiceId = this.resolveSelectedChoiceId(previousState);
        this.showToast(`${failurePrefix}：${this.stringifyError(error)}`);
        this.refreshState();
      })
      .finally(() => {
        this.systemChromeBusy = false;
      });
  }

  private runSelectionAction(
    action: Promise<void>,
    previousState: CustomHomepageSettingsViewState,
    previousSelectedChoiceId: string,
    successMessage: string,
    failurePrefix: string,
    returnHomeAfterSuccess: boolean = false
  ): void {
    this.busy = true;
    action
      .then(() => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
        this.showToast(successMessage);
        this.closeHomepagePreview();
        if (returnHomeAfterSuccess) {
          this.returnToBrowserHome();
        }
      })
      .catch((error: Error) => {
        this.state = previousState;
        this.selectedChoiceId = previousSelectedChoiceId;
        this.bumpHomepageListRevision();
        this.showToast(`${failurePrefix}：${this.stringifyError(error)}`);
        this.refreshState();
      })
      .finally(() => {
        this.busy = false;
      });
  }

  private applySelectedChoiceId(selectedId: string): void {
    this.selectedChoiceId = selectedId;
    this.bumpHomepageListRevision();
  }

  private applySystemEntryButtonState(showEntryButton: boolean): void {
    this.state = this.viewModel.withSystemEntryButton(this.state, showEntryButton);
  }

  private areCustomHomepageChromeControlsEnabled(): boolean {
    return !this.busy && !this.systemChromeBusy && this.state.customHomepageChromeControlsEnabled;
  }

  private applyRemoteUrlAppearanceState(enabled: boolean): void {
    this.state = this.viewModel.withForceDarkRemoteUrlHomepage(this.state, enabled);
  }

  private areRemoteUrlAppearanceRowsEnabled(): boolean {
    return !this.busy && !this.systemChromeBusy && this.state.remoteUrlAppearanceControlsEnabled;
  }

  private scheduleSiteIconHydration(): void {
    const scheduleVersion = this.siteIconScheduleVersion + 1;
    this.siteIconScheduleVersion = scheduleVersion;
    setTimeout(() => {
      if (this.siteIconScheduleVersion !== scheduleVersion) {
        return;
      }
      void this.hydrateSiteIcons(scheduleVersion);
    }, 0);
  }

  private async hydrateSiteIcons(scheduleVersion: number): Promise<void> {
    await this.siteIconHydrationCoordinator.hydrateChoices(this.state.choices, {
      cacheLimit: CUSTOM_HOMEPAGE_SITE_ICON_CACHE_LIMIT,
      networkPrefetchLimit: CUSTOM_HOMEPAGE_SITE_ICON_NETWORK_PREFETCH_LIMIT,
      shouldContinue: (): boolean => this.siteIconScheduleVersion === scheduleVersion,
      onResolved: (result: CustomHomepageSiteIconHydrationResult): void => {
        this.applyRemoteSiteIcon(result.choiceId, result.siteIconUri);
      }
    });
  }

  private async resolveSiteIconForChoice(
    choice: CustomHomepageChoiceViewState,
    allowNetwork: boolean
  ): Promise<void> {
    const result = await this.siteIconHydrationCoordinator.resolveChoice(choice, allowNetwork);
    if (result !== undefined) {
      this.applyRemoteSiteIcon(result.choiceId, result.siteIconUri);
    }
  }

  private applyRemoteSiteIcon(choiceId: string, siteIconPath: string): void {
    this.patchChoiceSiteIcon(choiceId, siteIconPath);
    this.persistRemoteSiteIcon(choiceId, siteIconPath);
  }

  private handleRemoteHomepageWarmupFinished(result: CustomHomepageRemoteWarmupResult): void {
    this.remoteHomepageWarmupTask = undefined;
    if (result.previewUri.trim().length > 0) {
      this.persistRemotePreviews(
        result.itemId,
        result.previewLightUri,
        result.previewDarkUri,
        result.previewLightAppearance,
        result.previewDarkAppearance
      );
    }
    if (this.remoteHomepageWarmupPurpose === 'refresh') {
      this.remoteHomepageRefreshFinishedCount += 1;
      if (result.previewUri.trim().length > 0) {
        this.remoteHomepageRefreshSucceededCount += 1;
      }
      if (this.remoteHomepageRefreshQueue.length > 0) {
        this.startNextRemoteHomepageRefreshTask();
        return;
      }
      const succeededCount = this.remoteHomepageRefreshSucceededCount;
      const totalCount = this.remoteHomepageRefreshTotalCount;
      const allSucceeded = totalCount > 0 && succeededCount === totalCount;
      const partiallySucceeded = succeededCount > 0 && succeededCount < totalCount;
      this.resetRemoteHomepageRefreshRun();
      this.busy = false;
      this.remoteHomepageProgressController.finish(
        allSucceeded ? '预览图已刷新' : (partiallySucceeded ? '部分预览图已刷新' : '预览图刷新失败'),
        allSucceeded
          ? '所有网址主页的预览图已保存。'
          : (partiallySucceeded
            ? `已刷新 ${succeededCount}/${totalCount} 个网址主页预览图。`
            : '暂时无法刷新预览图，请稍后重试。'),
        () => {
          this.showToast(allSucceeded ? '预览图已刷新' : (partiallySucceeded ? '部分预览图已刷新' : '预览图刷新失败'));
        },
        false
      );
      return;
    }
    this.busy = false;
    this.remoteHomepageProgressController.finish(
      result.status === 'saved' ? '主页已准备好' : '主页已保存',
      result.message,
      () => {
        this.showToast(result.message);
      },
      false
    );
  }

  private startNextRemoteHomepageRefreshTask(): void {
    const target = this.remoteHomepageRefreshQueue[0];
    if (target === undefined) {
      return;
    }
    this.remoteHomepageRefreshQueue = this.remoteHomepageRefreshQueue.slice(1);
    const currentIndex = this.remoteHomepageRefreshFinishedCount + 1;
    const totalCount = Math.max(1, this.remoteHomepageRefreshTotalCount);
    this.remoteHomepageProgressController.update(
      '正在刷新预览图',
      `正在刷新第 ${currentIndex}/${totalCount} 个网址主页预览图`,
      Math.min(92, Math.round((this.remoteHomepageRefreshFinishedCount / totalCount) * 80) + 12)
    );
    this.remoteHomepageWarmupTask = this.warmupCoordinator.buildTask(target.id, target.url);
  }

  private resetRemoteHomepageRefreshRun(): void {
    this.remoteHomepageRefreshQueue = [];
    this.remoteHomepageRefreshTotalCount = 0;
    this.remoteHomepageRefreshFinishedCount = 0;
    this.remoteHomepageRefreshSucceededCount = 0;
  }

  private persistRemotePreviews(
    choiceId: string,
    lightUri: string,
    darkUri: string,
    lightAppearance?: BrowserHomepageBackdropAppearanceState,
    darkAppearance?: BrowserHomepageBackdropAppearanceState
  ): void {
    const normalizedLightUri = lightUri.trim();
    const normalizedDarkUri = darkUri.trim();
    if (normalizedLightUri.length <= 0 && normalizedDarkUri.length <= 0) {
      return;
    }
    const item = this.coordinator.findItem(choiceId);
    if (item === undefined || item.kind !== 'remote_url' ||
      (item.previewLightUri === normalizedLightUri &&
        item.previewDarkUri === normalizedDarkUri &&
        lightAppearance === undefined &&
        darkAppearance === undefined)) {
      return;
    }
    this.coordinator.updateRemoteHomepagePreviews(choiceId, {
      lightUri: normalizedLightUri,
      darkUri: normalizedDarkUri,
      lightAppearance: lightAppearance,
      darkAppearance: darkAppearance
    })
      .then(() => {
        this.state = this.buildThemedState();
        this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
        this.bumpHomepageListRevision();
      })
      .catch((_error: Error) => {});
  }

  private persistRemoteSiteIcon(choiceId: string, siteIconPath: string): void {
    const normalizedSiteIconPath = siteIconPath.trim();
    if (normalizedSiteIconPath.length <= 0) {
      return;
    }
    const item = this.coordinator.findItem(choiceId);
    if (item === undefined || item.kind !== 'remote_url' || item.siteIconUri === normalizedSiteIconPath) {
      return;
    }
    this.coordinator.updateRemoteHomepageSiteIcon(choiceId, normalizedSiteIconPath)
      .catch((_error: Error) => {});
  }

  private patchChoiceSiteIcon(choiceId: string, siteIconPath: string): void {
    let changed = false;
    const choices = this.state.choices.map((choice: CustomHomepageChoiceViewState): CustomHomepageChoiceViewState => {
      if (choice.id !== choiceId) {
        return choice;
      }
      const nextSiteIconPath = siteIconPath.length > 0 ? siteIconPath : choice.siteIconPath;
      if (nextSiteIconPath === choice.siteIconPath) {
        return choice;
      }
      changed = true;
      return {
        id: choice.id,
        title: choice.title,
        subtitle: choice.subtitle,
        url: choice.url,
        isSelected: choice.isSelected,
        previewPath: choice.previewPath,
        siteIconPath: nextSiteIconPath,
        previewResource: choice.previewResource,
        isRemoteUrl: choice.isRemoteUrl
      };
    });
    if (!changed) {
      return;
    }
    this.state = this.viewModel.withChoices(this.state, choices);
    this.bumpHomepageListRevision();
  }

  private resolveSelectedChoiceId(state: CustomHomepageSettingsViewState): string {
    const selected = state.choices.find((choice: CustomHomepageChoiceViewState): boolean => choice.isSelected);
    return selected?.id ?? '';
  }

  private buildThemedState(): CustomHomepageSettingsViewState {
    return this.viewModel.buildState(sharedCustomHomepageRepository.getSnapshot(), this.resolveCurrentThemeMode());
  }

  private resolveCurrentThemeMode(): BrowserResolvedThemeMode {
    if (this.storedResolvedThemeMode === 'dark') {
      return 'dark';
    }
    if (this.storedResolvedThemeMode === 'light') {
      return 'light';
    }
    return sharedBrowserThemeModeCoordinator.resolveEffectiveMode(
      sharedPreferencesRepository.getPreferences().themeMode
    );
  }

  private bumpHomepageListRevision(): void {
    this.homepageListRevision = this.homepageListRevision + 1;
  }

  private refreshPreviewLayoutState(): void {
    this.previewLayoutState = this.previewViewModel.buildLayoutState({
      formFactor: this.environmentService.resolveNativeState().formFactor,
      viewportWidth: this.previewViewportWidth,
      viewportHeight: this.previewViewportHeight,
      availableWidth: this.previewAvailableWidth
    });
  }

  private refreshPreviewWindowViewport(): void {
    this.environmentService.resolveCurrentWindowViewport()
      .then((viewport) => {
        if (viewport === undefined ||
          (viewport.width === this.previewViewportWidth && viewport.height === this.previewViewportHeight)) {
          return;
        }
        this.previewViewportWidth = viewport.width;
        this.previewViewportHeight = viewport.height;
        this.refreshPreviewLayoutState();
      })
      .catch((_error: Error) => {});
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? Math.max(1, Math.round(parsed)) : 1;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

  private openRemoteHomepageProgressDialog(): void {
    if (this.remoteHomepageProgressDialogOpen) {
      return;
    }
    this.remoteHomepageProgressDialogOpen = true;
    this.remoteHomepageProgressDialogController.open();
  }

  private closeRemoteHomepageProgressDialog(): void {
    if (!this.remoteHomepageProgressDialogOpen) {
      return;
    }
    this.remoteHomepageProgressDialogOpen = false;
    this.remoteHomepageProgressDialogController.close();
  }

  private stringifyError(error: Object | undefined): string {
    if (error instanceof Error && error.message.length > 0) {
      return error.message;
    }
    return JSON.stringify(error);
  }
}
