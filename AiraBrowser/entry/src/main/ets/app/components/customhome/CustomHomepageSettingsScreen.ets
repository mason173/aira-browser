import { common } from '@kit.AbilityKit';
import {
  resolveCenteredDialogControllerWidth,
  resolveCenteredDialogSurfaceColor,
  CENTERED_DIALOG_CORNER_RADIUS_VP,
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
  CustomHomepageItemChromeViewState,
  CustomHomepageRemoteRefreshTargetViewState,
  CustomHomepageSettingsViewModel,
  CustomHomepageSettingsViewState,
  CustomHomepageSystemChoiceViewState
} from '../../../core/customhome/CustomHomepageSettingsViewModel';
import { SystemHomepageSelectionService } from '../../../core/customhome/SystemHomepageSelectionService';
import {
  BrowserHomePageStyle,
  normalizeBrowserHomePageStyle
} from '../../../common/models/HomePagePresentationSettingsModels';
import { HOME_PAGE_PRESENTATION_HOME_PAGE_STYLE_KEY } from '../../../common/constants/HomePagePresentationStorageKeys';
import { HomePageSettingsCoordinator } from '../../../core/settings/HomePageSettingsCoordinator';
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
  sharedHomePagePresentationSettingsRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository,
  sharedShortcutRepository,
  sharedWallpaperRepository
} from '../../bootstrap/BrowserAppRuntime';
import { HomeShortcutLogicService } from '../../../services/shortcuts/HomeShortcutLogicService';
import { WallpaperPresentationService } from '../../../services/wallpaper/WallpaperPresentationService';
import { CustomHomepagePicker } from './CustomHomepagePicker';
import { HomepagePreviewClosedItem } from './SystemHomepageLivePreview';
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
  SettingsSection,
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
import { SystemHomepageCards } from './SystemHomepageCards';
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
import { BrowserResolvedThemeMode, ShortcutRecord } from '../../../common/models/BrowserModels';
import { BrowserRecentlyClosedTabRecord } from '../../../core/browser/BrowserRecentlyClosedTabsService';
import { SiteIconUriCacheEntry } from '../../../common/models/SiteIconModels';
import { SiteIconService } from '../../../services/siteicons/SiteIconService';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState,
  WallpaperRepositorySnapshot
} from '../../../common/models/WallpaperModels';
import { BrowserHomepageBackdropAppearanceState } from '../../../common/models/BackdropAppearanceModels';
import { CustomHomepageItem } from '../../../common/models/CustomHomepageModels';
import {
  CustomHomepageSiteIconHydrationCoordinator,
  CustomHomepageSiteIconHydrationResult
} from '../../../core/customhome/CustomHomepageSiteIconHydrationCoordinator';
import { CustomHomepageRemoteUrlDialog } from './CustomHomepageRemoteUrlDialog';
import { CustomHomepageSettingsPageBinding } from '../../../core/customhome/CustomHomepageSettingsPageBinding';
import { CustomHomepageEnvironmentService } from '../../../services/customhome/CustomHomepageEnvironmentService';
import { applyDesktopDialogSheetChrome } from '../common/DesktopDialogSheetChrome';
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
  private systemHomepageSelectionService: SystemHomepageSelectionService = new SystemHomepageSelectionService(
    this.coordinator,
    sharedHomePagePresentationSettingsRepository,
    new HomePageSettingsCoordinator(
      sharedPreferencesRepository,
      sharedCustomHomepageRepository,
      sharedHomePagePresentationSettingsRepository
    ),
    sharedPreferencesRepository
  );
  private shortcutLogicService: HomeShortcutLogicService = new HomeShortcutLogicService();
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
  @StorageProp(HOME_PAGE_PRESENTATION_HOME_PAGE_STYLE_KEY) private storedHomePageStyle: string = 'classic';
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
  @State private previewLayoutState: CustomHomepagePreviewLayoutState =
    this.previewViewModel.buildCarouselLayoutState({
      viewportWidth: 390,
      viewportHeight: 844,
      availableWidth: 358,
      availableHeight: 640
    });
  @State private previewShortcuts: ShortcutRecord[] = [];
  @State private previewShowsShortcuts: boolean = true;
  @State private previewWallpaper: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @State private previewClosedItems: HomepagePreviewClosedItem[] = [];
  @State private previewShowsRecentlyClosed: boolean = true;
  @State private previewContentRevision: number = 0;
  @State private carouselFocusedIndex: number = 0;
  @State private carouselJumpToken: number = 0;
  @State private pickerBodyHeight: number = 0;
  @State private homepageSettingsSheetVisible: boolean = false;
  @State private homepageSettingsItemId: string = '';
  @State private homepageSettingsChrome: CustomHomepageItemChromeViewState =
    this.viewModel.buildEmptyItemChromeState();
  private carouselFocusedKey: string = '';
  private carouselPositioned: boolean = false;
  private siteIconScheduleVersion: number = 0;
  private closedIconScheduleVersion: number = 0;
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
    alignment: DialogAlignment.Center,
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
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('s'),
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
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('xs'),
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
    this.refreshPreviewShortcuts();
  }

  private handlePageShow(): void {
    this.refreshState();
    this.refreshPreviewWindowViewport();
    this.refreshPreviewShortcuts();
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
    if (this.homepageSettingsSheetVisible) {
      this.homepageSettingsSheetVisible = false;
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
      this.buildSettingsPageBody()
    }
    .width('100%')
    .height('100%')
    .bindSheet(
      $$this.homepageSettingsSheetVisible,
      this.buildHomepageSettingsSheet(),
      this.buildHomepageSettingsSheetOptions()
    )
  }

  @Builder
  private buildSettingsPageBody() {
    Stack() {
      if (this.presentationMode === 'embedded') {
        this.buildEmbeddedSettingsSurface()
      } else {
        Column() {
          SettingsHdsScaffold({
            title: '主页设置',
            backIconKind: 'back',
            pageBackground: this.resolveSettingsCanvasColor(),
            headerButtonBackground: this.storedPressedBackgroundColor,
            primaryTextColor: this.storedPrimaryTextColor,
            dividerColor: this.storedDividerColor,
            menuActions: this.buildHeaderActions(),
            collapseMenuActions: true,
            suppressContentBlur: true,
            onBack: () => {
              this.handlePageBack();
            }
          }) {
            this.buildHomepagePickerSurface()
          }
        }
        .width('100%')
        .height('100%')
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
    .backgroundColor(this.resolveSettingsCanvasColor())
    .onAreaChange((_oldArea: Area, _newArea: Area) => {
      this.refreshPreviewWindowViewport();
    })
    .bindSheet($$this.homepageInfoSheetVisible, this.buildHomepageInfoSheet(), applyDesktopDialogSheetChrome({
      // Embedded on large screen: center the info sheet instead of a bottom sheet.
      preferType: this.presentationMode === 'embedded' ? SheetType.CENTER : SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: this.presentationMode !== 'embedded',
      showClose: true,
      onDisappear: () => {
        this.handleHomepageInfoSheetDisappear();
      }
    }, 'm', this.presentationMode === 'embedded'))
  }

  @Builder
  private buildEmbeddedSettingsSurface() {
    Column({ space: 12 }) {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '主页设置',
          showTitle: false,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          primaryActionText: '添加网址主页',
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

          Button('添加网址主页')
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

      Column() {
        this.buildHomepagePickerSurface()
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 4 })
    .backgroundColor(this.resolveSettingsCanvasColor())
  }

  @Builder
  private buildHomepagePickerSurface() {
    CustomHomepagePicker({
      cards: this.viewModel.buildCarouselCards(this.state),
      choices: this.state.choices,
      layoutState: this.previewLayoutState,
      shortcuts: this.previewShortcuts,
      showShortcuts: this.previewShowsShortcuts,
      wallpaper: this.previewWallpaper,
      closedItems: this.previewClosedItems,
      showRecentlyClosed: this.previewShowsRecentlyClosed,
      previewRevision: this.previewContentRevision,
      pageBackground: this.resolveSettingsCanvasColor(),
      focusedIndex: this.carouselFocusedIndex,
      jumpToken: this.carouselJumpToken,
      busy: this.busy,
      onCardFocus: (index: number) => {
        this.onCarouselFocus(index);
      },
      onApply: () => {
        this.applyFocusedHomepage();
      },
      onOpenSettings: (choice: CustomHomepageChoiceViewState) => {
        this.openHomepageSettings(choice);
      }
    })
    .width('100%')
    .height('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updatePickerArea(newArea);
    })
  }

  private buildHomepageSettingsSheetOptions(): SheetOptions {
    return applyDesktopDialogSheetChrome({
      preferType: this.presentationMode === 'embedded' ? SheetType.CENTER : SheetType.BOTTOM,
      height: this.presentationMode === 'embedded' ? SheetSize.FIT_CONTENT : '72%',
      title: this.buildHomepageSettingsSheetTitle(),
      dragBar: this.presentationMode !== 'embedded',
      showClose: true,
      backgroundColor: this.storedPageBackgroundColor,
      onDisappear: () => {
        this.homepageSettingsItemId = '';
      }
    }, 'm', this.presentationMode === 'embedded');
  }

  private buildHomepageSettingsSheetTitle(): SheetTitleOptions {
    return {
      title: '主页设置'
    };
  }

  @Builder
  private buildHomepageSettingsSheet() {
    Column() {
      SettingsPresentationScrollBody({
        desktopPresentation: false,
        topPadding: 4,
        bottomPadding: 28,
        contentSpace: 16
      }) {
        SettingsSection({
          title: '这个主页',
          secondaryTextColor: this.storedSecondaryTextColor
        }) {
          this.buildHomepageSettingsActions()
        }
        SettingsSection({
          title: '主页系统入口',
          secondaryTextColor: this.storedSecondaryTextColor
        }) {
          this.buildHomepageSettingsChrome()
        }
        if (this.homepageSettingsChrome.isRemoteUrl) {
          this.buildHomepageSettingsAppearance()
          this.buildHomepageSettingsMaintenance()
        }
        this.buildDeveloperGuideEntry()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildHomepageSettingsActions() {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsDesktopNavigationRow({
          title: '查看信息',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onAction: () => {
            this.openFocusedHomepageInfo();
          }
        })
        SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
        SettingsDesktopNavigationRow({
          title: '导出',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onAction: () => {
            this.exportFocusedHomepage();
          }
        })
        SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
        SettingsDesktopNavigationRow({
          title: '删除',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onAction: () => {
            this.removeFocusedHomepage();
          }
        })
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsNavigationRow({
          title: '查看信息',
          rowPosition: 'first',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.openFocusedHomepageInfo();
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '导出',
          rowPosition: 'middle',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.exportFocusedHomepage();
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsNavigationRow({
          title: '删除',
          rowPosition: 'last',
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onAction: () => {
            this.removeFocusedHomepage();
          }
        })
      }
    }
  }

  @Builder
  private buildHomepageSettingsChrome() {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsDesktopSwitchRow({
          title: '在此主页显示系统搜索',
          checked: this.homepageSettingsChrome.showSystemSearchBar,
          isEnabled: !this.systemChromeBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onChange: (checked: boolean) => {
            this.updateFocusedHomepageSearchBar(checked);
          }
        })
        SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
        SettingsDesktopSwitchRow({
          title: '滚动时显示或隐藏',
          checked: this.homepageSettingsChrome.hideToolbarOnScroll,
          isEnabled: !this.systemChromeBusy && this.homepageSettingsChrome.showSystemSearchBar,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onChange: (checked: boolean) => {
            this.updateFocusedHomepageHideToolbarOnScroll(checked);
          }
        })
        SettingsDesktopDivider({ dividerColor: this.storedDividerColor })
        SettingsDesktopSwitchRow({
          title: '显示系统入口按钮',
          checked: this.homepageSettingsChrome.showSystemEntryButton,
          isEnabled: !this.systemChromeBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          hoverBackgroundColor: this.storedPressedBackgroundColor,
          focusColor: this.storedAccentColor,
          onChange: (checked: boolean) => {
            this.updateFocusedHomepageSystemEntryButton(checked);
          }
        })
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '在此主页显示系统搜索',
          checked: this.homepageSettingsChrome.showSystemSearchBar,
          rowPosition: 'first',
          isEnabled: !this.systemChromeBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateFocusedHomepageSearchBar(checked);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '滚动时显示或隐藏',
          checked: this.homepageSettingsChrome.hideToolbarOnScroll,
          rowPosition: 'middle',
          isEnabled: !this.systemChromeBusy && this.homepageSettingsChrome.showSystemSearchBar,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateFocusedHomepageHideToolbarOnScroll(checked);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '显示系统入口按钮',
          checked: this.homepageSettingsChrome.showSystemEntryButton,
          rowPosition: 'last',
          isEnabled: !this.systemChromeBusy,
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          pressedBackgroundColor: this.storedPressedBackgroundColor,
          onChange: (checked: boolean) => {
            this.updateFocusedHomepageSystemEntryButton(checked);
          }
        })
      }
    }
    SettingsFooterText({
      text: '以上设置只保存到这个第三方主页。系统入口按钮只在第三方主页上显示。',
      secondaryTextColor: this.storedSecondaryTextColor
    })
  }

  @Builder
  private buildHomepageSettingsAppearance() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '主页行为',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      if (this.desktopPresentation) {
        SettingsDesktopGroup({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsDesktopSwitchRow({
            title: '尝试强制深色模式',
            checked: this.homepageSettingsChrome.forceDarkRemoteUrlHomepage,
            isEnabled: !this.systemChromeBusy,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            hoverBackgroundColor: this.storedPressedBackgroundColor,
            focusColor: this.storedAccentColor,
            onChange: (checked: boolean) => {
              this.updateFocusedHomepageForceDarkMode(checked);
            }
          })
        }
      } else {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
          SettingsSwitchRow({
            title: '尝试强制深色模式',
            checked: this.homepageSettingsChrome.forceDarkRemoteUrlHomepage,
            rowPosition: 'single',
            isEnabled: !this.systemChromeBusy,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            onChange: (checked: boolean) => {
              this.updateFocusedHomepageForceDarkMode(checked);
            }
          })
        }
      }
      SettingsFooterText({
        text: '强制深色模式仅对网址主页生效。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
    .width('100%')
  }

  @Builder
  private buildHomepageSettingsMaintenance() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '维护',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      if (this.desktopPresentation) {
        SettingsDesktopActionButton({
          title: '刷新主页预览图',
          isEnabled: !this.busy,
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
          isEnabled: !this.busy,
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
  private buildSystemHomepageSection() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '系统主页',
        secondaryTextColor: this.storedSecondaryTextColor
      })
      SystemHomepageCards({
        choices: this.state.systemChoices,
        busy: this.busy,
        layoutState: this.previewLayoutState,
        onSelect: (style: BrowserHomePageStyle) => {
          this.selectSystemHomepageStyle(style);
        }
      })
      SettingsFooterText({
        text: '内置主页随 Aira 更新，不需要下载。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
    .width('100%')
  }

  @Builder
  private buildHomepageListSection() {
    Column({ space: 10 }) {
      SettingsSectionTitle({
        title: '第三方主页',
        secondaryTextColor: this.storedSecondaryTextColor
      })
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
      SettingsFooterText({
        text: '卡片右上角可查看信息、导出或删除。',
        secondaryTextColor: this.storedSecondaryTextColor
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

  private buildHeaderActions(): SettingsHdsMenuAction[] {
    return [{
      label: '开发文档',
      airaIconId: 'browser.toolbar.savedPages',
      enabled: true,
      action: () => {
        this.openDeveloperGuide();
      }
    }, {
      label: '添加网址主页',
      airaIconId: 'browser.toolbar.copyLink',
      enabled: !this.busy,
      action: () => {
        this.openRemoteHomepageDialog();
      }
    }, {
      label: '导入主页',
      airaIconId: 'browser.tabs.add',
      enabled: !this.busy,
      action: () => {
        this.importHtmlFile();
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
    if (this.homepageSettingsSheetVisible) {
      this.homepageSettingsSheetVisible = false;
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

  private refreshState(followCarouselSelection: boolean = false): void {
    const follow = followCarouselSelection || !this.carouselPositioned;
    this.coordinator.ensureReady()
      .then(() => {
        this.applyRefreshedHomepageState(follow);
      })
      .catch((_error: Error) => {
        this.applyRefreshedHomepageState(follow);
      });
  }

  private applyRefreshedHomepageState(followCarouselSelection: boolean): void {
    this.state = this.buildThemedState();
    this.selectedChoiceId = this.resolveSelectedChoiceId(this.state);
    this.bumpHomepageListRevision();
    this.scheduleSiteIconHydration();
    this.syncCarouselFocus(followCarouselSelection);
    this.reloadHomepageSettingsChrome();
    this.carouselPositioned = true;
  }

  private importHtmlFile(): void {
    if (this.busy) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.busy = true;
    this.coordinator.importCustomHomepage(context)
      .then((result: CustomHomepageImportResult) => {
        this.applyRefreshedHomepageState(result.imported);
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
        this.applyRefreshedHomepageState(true);
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

  private selectSystemHomepageStyle(style: BrowserHomePageStyle): void {
    if (this.busy || this.isActiveSystemHomepageStyle(style)) {
      return;
    }
    this.busy = true;
    this.systemHomepageSelectionService.selectSystemHomepageStyle(style)
      .then(() => {
        this.refreshState();
        this.showToast('已切换主页');
      })
      .catch((error: Error) => {
        this.showToast(`切换主页失败：${this.stringifyError(error)}`);
        this.refreshState();
      })
      .finally(() => {
        this.busy = false;
      });
  }

  private isActiveSystemHomepageStyle(style: BrowserHomePageStyle): boolean {
    const active = this.state.systemChoices.find(
      (choice: CustomHomepageSystemChoiceViewState): boolean => choice.isActive
    );
    return active !== undefined && active.style === style;
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
    return this.viewModel.buildState(
      sharedCustomHomepageRepository.getSnapshot(),
      this.resolveCurrentThemeMode(),
      normalizeBrowserHomePageStyle(this.storedHomePageStyle)
    );
  }

  private resolveSettingsCanvasColor(): string {
    if (this.resolveCurrentThemeMode() !== 'light') {
      return this.storedPageBackgroundColor;
    }
    return this.deepenLightCanvasColor(this.storedPageBackgroundColor);
  }

  private deepenLightCanvasColor(color: string): string {
    const normalized = color.trim();
    if (!/^#[0-9A-Fa-f]{6}$/.test(normalized)) {
      return normalized.length > 0 ? normalized : '#E0E2E5';
    }
    const factor = 0.9;
    return `#${this.toCanvasHex(parseInt(normalized.substring(1, 3), 16) * factor)}${this.toCanvasHex(parseInt(normalized.substring(3, 5), 16) * factor)}${this.toCanvasHex(parseInt(normalized.substring(5, 7), 16) * factor)}`;
  }

  private toCanvasHex(channel: number): string {
    const clamped = Math.max(0, Math.min(255, Math.round(channel)));
    const hex = clamped.toString(16);
    return hex.length < 2 ? `0${hex}` : hex;
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
    const availableHeight = this.pickerBodyHeight > 0 ?
      this.pickerBodyHeight :
      Math.max(320, this.previewViewportHeight - 120);
    this.previewLayoutState = this.previewViewModel.buildCarouselLayoutState({
      viewportWidth: this.previewViewportWidth,
      viewportHeight: this.previewViewportHeight,
      availableWidth: this.previewAvailableWidth > 0 ? this.previewAvailableWidth : this.previewViewportWidth,
      availableHeight: availableHeight
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

  private updatePickerArea(area: Area): void {
    const nextHeight = this.parseAreaDimension(area.height);
    const nextWidth = this.parseAreaDimension(area.width);
    let changed = false;
    if (nextHeight !== this.pickerBodyHeight) {
      this.pickerBodyHeight = nextHeight;
      changed = true;
    }
    if (nextWidth !== this.previewAvailableWidth) {
      this.previewAvailableWidth = nextWidth;
      changed = true;
    }
    if (changed) {
      this.refreshPreviewLayoutState();
    }
  }

  private refreshPreviewShortcuts(): void {
    const appearance = sharedPreferencesRepository.getPreferences().appearance;
    this.previewShowsShortcuts = appearance.showHomeShortcuts;
    this.previewShowsRecentlyClosed = appearance.showHomeRecentlyClosed;
    void this.loadPreviewSurface()
      .then(() => {
        this.notePreviewSurfaceChanged();
      })
      .catch((_error: Error) => {
        this.applyCachedPreviewSurface();
        this.notePreviewSurfaceChanged();
      });
  }

  private notePreviewSurfaceChanged(): void {
    this.previewContentRevision = this.previewContentRevision + 1;
    this.carouselJumpToken = this.carouselJumpToken + 1;
  }

  private loadPreviewSurface(): Promise<void> {
    return sharedShortcutRepository.initialize()
      .then(() => sharedShortcutRepository.refresh())
      .then((shortcuts: ShortcutRecord[]) => {
        this.previewShortcuts = this.shortcutLogicService.filterAppOwnedShortcuts(shortcuts);
        return sharedWallpaperRepository.initialize();
      })
      .then((snapshot: WallpaperRepositorySnapshot) => {
        this.previewWallpaper = new WallpaperPresentationService().buildPresentationState(snapshot);
        return sharedRecentlyClosedTabRepository.refresh();
      })
      .then((records: BrowserRecentlyClosedTabRecord[]): void => {
        this.previewClosedItems = this.buildPreviewClosedItems(records);
      });
  }

  private applyCachedPreviewSurface(): void {
    this.previewShortcuts = this.shortcutLogicService.filterAppOwnedShortcuts(sharedShortcutRepository.listAll());
    this.previewWallpaper = new WallpaperPresentationService()
      .buildPresentationState(sharedWallpaperRepository.getSnapshot());
    this.previewClosedItems = this.buildPreviewClosedItems(sharedRecentlyClosedTabRepository.listRecords());
  }

  private buildPreviewClosedItems(records: BrowserRecentlyClosedTabRecord[]): HomepagePreviewClosedItem[] {
    const siteIconService = new SiteIconService();
    const visibleRecords = records.slice(0, 2);
    const items: HomepagePreviewClosedItem[] = [];
    visibleRecords.forEach((record: BrowserRecentlyClosedTabRecord) => {
      const url = this.resolveClosedRecordUrl(record);
      const title = record.tab.title.trim();
      items.push({
        key: record.id,
        title: title.length > 0 ? title : (url.length > 0 ? url : '未命名标签页'),
        subtitle: this.shortcutLogicService.extractDomainFromUrl(url),
        iconUri: this.resolveClosedRecordIconUri(record, url, siteIconService)
      });
    });
    this.schedulePreviewClosedIconHydration(visibleRecords);
    return items;
  }

  private resolveClosedRecordIconUri(
    record: BrowserRecentlyClosedTabRecord,
    url: string,
    siteIconService: SiteIconService
  ): string {
    const storedIcon = (record.siteIconUri ?? '').trim();
    if (storedIcon.length > 0) {
      return storedIcon;
    }
    return siteIconService.peekUri(url);
  }

  private schedulePreviewClosedIconHydration(records: BrowserRecentlyClosedTabRecord[]): void {
    const pending = records.filter((record: BrowserRecentlyClosedTabRecord): boolean => {
      return this.resolveClosedRecordUrl(record).length > 0 && (record.siteIconUri ?? '').trim().length === 0;
    });
    if (pending.length <= 0) {
      return;
    }
    const scheduleVersion = this.closedIconScheduleVersion + 1;
    this.closedIconScheduleVersion = scheduleVersion;
    const urls = pending.map((record: BrowserRecentlyClosedTabRecord): string => this.resolveClosedRecordUrl(record));
    void new SiteIconService().resolveCachedUris(urls).then((entries: SiteIconUriCacheEntry[]): void => {
      if (this.closedIconScheduleVersion !== scheduleVersion) {
        return;
      }
      this.applyPreviewClosedIcons(pending, entries);
    });
  }

  private applyPreviewClosedIcons(
    records: BrowserRecentlyClosedTabRecord[],
    entries: SiteIconUriCacheEntry[]
  ): void {
    let changed = false;
    const next: HomepagePreviewClosedItem[] = [];
    this.previewClosedItems.forEach((item: HomepagePreviewClosedItem) => {
      if (item.iconUri.length > 0) {
        next.push(item);
        return;
      }
      const record = records.find((candidate: BrowserRecentlyClosedTabRecord): boolean => candidate.id === item.key);
      const url = record === undefined ? '' : this.resolveClosedRecordUrl(record);
      const entry = entries.find((candidate: SiteIconUriCacheEntry): boolean => candidate.url === url);
      const iconUri = entry === undefined ? '' : entry.uri.trim();
      if (iconUri.length <= 0) {
        next.push(item);
        return;
      }
      changed = true;
      next.push({
        key: item.key,
        title: item.title,
        subtitle: item.subtitle,
        iconUri: iconUri
      });
    });
    if (changed) {
      this.previewClosedItems = next;
    }
  }

  private resolveClosedRecordUrl(record: BrowserRecentlyClosedTabRecord): string {
    const url = (record.tab.url ?? '').trim();
    if (url.length > 0) {
      return url;
    }
    const lastGoodUrl = (record.tab.lastGoodUrl ?? '').trim();
    if (lastGoodUrl.length > 0) {
      return lastGoodUrl;
    }
    return (record.tab.pendingUrl ?? '').trim();
  }

  private syncCarouselFocus(followSelection: boolean): void {
    const cards = this.viewModel.buildCarouselCards(this.state);
    if (cards.length <= 0) {
      this.carouselFocusedIndex = 0;
      this.carouselFocusedKey = '';
      return;
    }
    const preferredKey = followSelection ? '' : this.carouselFocusedKey;
    const index = this.viewModel.resolveCarouselIndex(cards, preferredKey);
    const nextKey = cards[index].key;
    const shouldJump = followSelection || !this.carouselPositioned || nextKey !== this.carouselFocusedKey ||
      index !== this.carouselFocusedIndex;
    this.carouselFocusedIndex = index;
    this.carouselFocusedKey = nextKey;
    if (shouldJump) {
      this.carouselJumpToken = this.carouselJumpToken + 1;
    }
  }

  private onCarouselFocus(index: number): void {
    const cards = this.viewModel.buildCarouselCards(this.state);
    if (index < 0 || index >= cards.length || cards[index].key === this.carouselFocusedKey) {
      return;
    }
    this.carouselFocusedIndex = index;
    this.carouselFocusedKey = cards[index].key;
  }

  private applyFocusedHomepage(): void {
    const cards = this.viewModel.buildCarouselCards(this.state);
    if (this.carouselFocusedIndex < 0 || this.carouselFocusedIndex >= cards.length) {
      return;
    }
    const card = cards[this.carouselFocusedIndex];
    if (card.isCurrent) {
      return;
    }
    if (card.kind === 'system') {
      this.selectSystemHomepageStyle(card.systemStyle);
      return;
    }
    const choice = this.state.choices.find((item: CustomHomepageChoiceViewState): boolean => {
      return item.id === card.choiceId;
    });
    if (choice !== undefined) {
      this.applyFocusedCustomHomepage(choice);
    }
  }

  private applyFocusedCustomHomepage(choice: CustomHomepageChoiceViewState): void {
    if (this.busy || choice.id === this.selectedChoiceId) {
      return;
    }
    const previousState = this.state;
    const previousSelectedChoiceId = this.selectedChoiceId;
    this.applySelectedChoiceId(choice.id);
    this.runSelectionAction(
      this.coordinator.selectCustomHomepage(choice.id),
      previousState,
      previousSelectedChoiceId,
      '已切换主页',
      '切换主页失败',
      false
    );
  }

  private openHomepageSettings(choice: CustomHomepageChoiceViewState): void {
    this.homepageSettingsItemId = choice.id;
    this.reloadHomepageSettingsChrome();
    this.homepageSettingsSheetVisible = true;
  }

  private reloadHomepageSettingsChrome(): void {
    if (this.homepageSettingsItemId.length <= 0) {
      return;
    }
    this.homepageSettingsChrome = this.viewModel.buildItemChromeState(
      sharedCustomHomepageRepository.getSnapshot().settings,
      this.homepageSettingsItemId
    );
  }

  private resolveHomepageSettingsChoice(): CustomHomepageChoiceViewState | undefined {
    return this.state.choices.find((choice: CustomHomepageChoiceViewState): boolean => {
      return choice.id === this.homepageSettingsItemId;
    });
  }

  private openFocusedHomepageInfo(): void {
    const choice = this.resolveHomepageSettingsChoice();
    this.homepageSettingsSheetVisible = false;
    if (choice !== undefined) {
      this.openHomepageInfo(choice);
    }
  }

  private exportFocusedHomepage(): void {
    const choice = this.resolveHomepageSettingsChoice();
    this.homepageSettingsSheetVisible = false;
    if (choice !== undefined) {
      this.exportCustomHomepage(choice);
    }
  }

  private removeFocusedHomepage(): void {
    const choice = this.resolveHomepageSettingsChoice();
    this.homepageSettingsSheetVisible = false;
    if (choice !== undefined) {
      this.removeCustomHomepage(choice);
    }
  }

  private updateFocusedHomepageSearchBar(visible: boolean): void {
    this.updateFocusedHomepageChrome('search', visible);
  }

  private updateFocusedHomepageSystemEntryButton(visible: boolean): void {
    this.updateFocusedHomepageChrome('entry', visible);
  }

  private updateFocusedHomepageForceDarkMode(enabled: boolean): void {
    this.updateFocusedHomepageChrome('dark', enabled);
  }

  private updateFocusedHomepageHideToolbarOnScroll(enabled: boolean): void {
    if (!this.homepageSettingsChrome.showSystemSearchBar) {
      return;
    }
    this.updateFocusedHomepageChrome('scroll', enabled);
  }

  private updateFocusedHomepageChrome(
    field: 'search' | 'entry' | 'dark' | 'scroll',
    value: boolean
  ): void {
    const itemId = this.homepageSettingsItemId;
    if (itemId.length <= 0 || this.systemChromeBusy) {
      return;
    }
    const previous = this.homepageSettingsChrome;
    if (!this.focusedChromeWouldChange(previous, field, value)) {
      return;
    }
    this.homepageSettingsChrome = this.copyFocusedChrome(previous, field, value);
    this.systemChromeBusy = true;
    this.runFocusedHomepageChromeUpdate(itemId, field, value)
      .then(() => {
        this.reloadHomepageSettingsChrome();
        this.state = this.buildThemedState();
        this.showToast(this.resolveFocusedChromeMessage(field, value));
      })
      .catch((error: Error) => {
        this.homepageSettingsChrome = previous;
        this.showToast(`更新主页设置失败：${this.stringifyError(error)}`);
      })
      .finally(() => {
        this.systemChromeBusy = false;
      });
  }

  private focusedChromeWouldChange(
    chrome: CustomHomepageItemChromeViewState,
    field: 'search' | 'entry' | 'dark' | 'scroll',
    value: boolean
  ): boolean {
    if (field === 'search') {
      return chrome.showSystemSearchBar !== value;
    }
    if (field === 'entry') {
      return chrome.showSystemEntryButton !== value;
    }
    if (field === 'dark') {
      return chrome.forceDarkRemoteUrlHomepage !== value;
    }
    return chrome.hideToolbarOnScroll !== value;
  }

  private copyFocusedChrome(
    chrome: CustomHomepageItemChromeViewState,
    field: 'search' | 'entry' | 'dark' | 'scroll',
    value: boolean
  ): CustomHomepageItemChromeViewState {
    return {
      itemId: chrome.itemId,
      showSystemSearchBar: field === 'search' ? value : chrome.showSystemSearchBar,
      showSystemEntryButton: field === 'entry' ? value : chrome.showSystemEntryButton,
      forceDarkRemoteUrlHomepage: field === 'dark' ? value : chrome.forceDarkRemoteUrlHomepage,
      hideToolbarOnScroll: field === 'scroll' ? value : chrome.hideToolbarOnScroll,
      isRemoteUrl: chrome.isRemoteUrl
    };
  }

  private runFocusedHomepageChromeUpdate(
    itemId: string,
    field: 'search' | 'entry' | 'dark' | 'scroll',
    value: boolean
  ): Promise<void> {
    if (field === 'search') {
      return this.coordinator.updateItemHomepageSearchBar(itemId, value);
    }
    if (field === 'entry') {
      return this.coordinator.updateItemHomepageSystemEntryButton(itemId, value);
    }
    if (field === 'dark') {
      return this.coordinator.updateItemHomepageForceDarkMode(itemId, value);
    }
    return this.coordinator.updateItemHomepageHideToolbarOnScroll(itemId, value);
  }

  private resolveFocusedChromeMessage(
    field: 'search' | 'entry' | 'dark' | 'scroll',
    value: boolean
  ): string {
    if (field === 'search') {
      return value ? '已在此主页显示系统搜索' : '已在此主页隐藏系统搜索';
    }
    if (field === 'entry') {
      return value ? '已显示系统入口按钮' : '已隐藏系统入口按钮';
    }
    if (field === 'dark') {
      return value ? '网址主页强制深色已开启' : '网址主页将尊重网页原本外观';
    }
    return value ? '当前主页已启用滚动显示或隐藏' : '当前主页已关闭滚动显示或隐藏';
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
