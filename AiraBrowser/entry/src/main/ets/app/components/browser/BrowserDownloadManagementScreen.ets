import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  resolveCenteredDialogControllerWidth,
  CENTERED_DIALOG_CORNER_RADIUS_VP,
  resolveCenteredDialogSurfaceColor,
  showCenteredAlertDialog
} from '../common/CenteredDialogSurface';
import router from '@ohos.router';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import {
  BrowserPrivateBoundaryRouteParams,
  BrowserPrivateBoundaryNavigationService
} from '../../../core/browser/BrowserPrivateBoundaryNavigationService';
import {
  DownloadManagementRowAction,
  DownloadManagementRowState,
  createEmptyDownloadManagementListState,
  DownloadManagementFilterChipView,
  DownloadManagementGroupSelection,
  DownloadManagementGroupState,
  DownloadManagementListState,
  DownloadManagerViewModel
} from '../../../core/download/DownloadManagerViewModel';
import { DownloadSettingsViewModel } from '../../../core/download/DownloadSettingsViewModel';
import { sharedDownloadPolicyService } from '../../bootstrap/BrowserAppRuntime';
import { DownloadLocationDirectoryService } from '../../../services/download/DownloadLocationDirectoryService';
import {
  buildDownloadSelectionTitle,
  canSelectDownloadTask,
  collectSelectableDownloadGuids,
  DownloadSelectionCandidate,
  downloadSelectionEmptyToast,
  pruneDownloadSelection
} from '../../../core/download/DownloadSelectionViewModel';
import {
  DownloadQueryGroup,
  DownloadTaskBoundary,
  getDownloadV2QueryGroup
} from '../../../domain/download/DownloadTypes';
import { DownloadV2Status } from '../../../domain/downloadv2/DownloadV2Types';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { sharedDownloadRuntimeService } from '../../bootstrap/BrowserAppRuntime';
import { BrowserDownloadManagementRow } from './BrowserDownloadManagementRow';
import { BrowserDownloadSettingsDialog } from './BrowserDownloadSettingsDialog';
import { DOWNLOAD_SETTINGS_ROUTE } from '../../router/AppRoutes';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import { AppEmptyState } from '../common/AppEmptyState';
import {
  ManagementHdsMenuAction,
  ManagementHdsScaffold
} from '../common/ManagementHdsScaffold';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';
import { FloatingSelectionToolbar } from '../common/FloatingSelectionToolbar';
import { browserSheetHeaderBlurModifier, resolveBrowserSheetHeaderBlurRadius } from './BrowserModalBottomSheet';
import {
  MANAGEMENT_LARGE_SCREEN_ROW_GAP,
  MANAGEMENT_LARGE_SCREEN_ROW_INSET,
  ManagementLargeScreenIconButton,
  ManagementLargeScreenNavItem,
  ManagementLargeScreenNavSection,
  ManagementLargeScreenShell,
  ManagementLargeScreenTextButton
} from '../common/ManagementLargeScreenShell';

interface HiddenDownloadTaskSnapshot {
  guid: string;
  group: DownloadQueryGroup;
}

interface OptimisticControlSnapshot {
  targetStatus: DownloadV2Status;
  expiresAt: number;
}

type CompletedDownloadDeleteMode = 'task_only' | 'task_and_file';

type BatchDownloadDeleteScope = 'records_only' | 'records_and_files';

const DOWNLOAD_MANAGEMENT_REFRESH_INTERVAL_MS: number = 1500;
const DOWNLOAD_MANAGEMENT_DOMAIN = 0x0000;
const DOWNLOAD_MANAGEMENT_TAG = 'DownloadManagement';
const DOWNLOAD_OPTIMISTIC_CONTROL_GRACE_MS: number = 2200;
const DOWNLOAD_MANAGEMENT_INTERACTION_QUIET_MS: number = 700;
const DOWNLOAD_MANAGEMENT_PROGRESS_BROADCAST_PAUSE_OWNER = 'download_management_interaction';
const LARGE_SCREEN_DOWNLOAD_FILTER_ITEM_WIDTH_VP: number = 112;
const LARGE_SCREEN_DOWNLOAD_SETTINGS_BUTTON_HEIGHT_VP: number = 34;
const DOWNLOAD_IMMERSIVE_TITLE_TOP_INSET: number = 8;
const DOWNLOAD_IMMERSIVE_TITLE_HEIGHT: number = 40;
const DOWNLOAD_IMMERSIVE_TITLE_TO_FILTER_GAP: number = 12;
const DOWNLOAD_FILTER_LAYOUT_HEIGHT: number = 54;
const DOWNLOAD_FILTER_TO_CONTENT_GAP: number = 4;
const DOWNLOAD_EMBEDDED_FILTER_TOP_INSET: number = 8;
const DOWNLOAD_IMMERSIVE_TITLE_TO_CONTENT_GAP: number = 16;
const DOWNLOAD_CONTEXT_MENU_DISMISS_DELAY_MS: number = 240;

class DownloadGroupScrollers {
  private readonly inProgress: Scroller = new Scroller();
  private readonly completed: Scroller = new Scroller();
  private readonly failed: Scroller = new Scroller();
  private readonly paused: Scroller = new Scroller();
  private readonly pending: Scroller = new Scroller();
  private readonly canceled: Scroller = new Scroller();
  private readonly removed: Scroller = new Scroller();
  private readonly all: Scroller = new Scroller();

  scrollerFor(group: string): Scroller {
    if (group === 'completed') {
      return this.completed;
    }
    if (group === 'failed') {
      return this.failed;
    }
    if (group === 'paused') {
      return this.paused;
    }
    if (group === 'pending') {
      return this.pending;
    }
    if (group === 'canceled') {
      return this.canceled;
    }
    if (group === 'removed') {
      return this.removed;
    }
    if (group === 'all') {
      return this.all;
    }
    return this.inProgress;
  }
}
const DOWNLOAD_SELECTION_TOOLBAR_FLOAT_BOTTOM: number = 36;

@Component
export struct BrowserDownloadManagementScreen {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop presentationMode: 'page' | 'native_tab' = 'page';
  @Prop embeddedDataScope: string = '';
  @Prop embeddedPrivacyMode: string = '';
  private downloadManagerViewModel: DownloadManagerViewModel = new DownloadManagerViewModel();
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  private autoRefreshTimer: number = -1;
  private downloadListenerKey: string = '';
  private isRefreshingState: boolean = false;
  private interactionQuietUntil: number = 0;
  private deferredRefreshTimer: number = -1;
  private hasDeferredRefresh: boolean = false;
  private progressBroadcastResumeTimer: number = -1;
  private hasResolvedInitialContentGroup: boolean = false;

  @State downloadListState: DownloadManagementListState = createEmptyDownloadManagementListState();
  @State isSessionEphemeral: boolean = false;
  @State selectedGroup: DownloadQueryGroup = 'in_progress';
  @State desktopQuery: string = '';
  @State statusText: string = '';
  @State cancelConfirmGuid: string = '';
  @State cancelConfirmFileName: string = '';
  @State completedDeleteConfirmGuid: string = '';
  @State completedDeleteConfirmFileName: string = '';
  @State completedDeleteConfirmMode: CompletedDownloadDeleteMode = 'task_only';
  @State locallyHiddenTasks: HiddenDownloadTaskSnapshot[] = [];
  @State isSelectionMode: boolean = false;
  @State selectedGuids: string[] = [];
  @State private downloadSettingsDialogRevision: number = 0;
  @State private headerBlurRadius: number = 0;
  private groupScrollers: DownloadGroupScrollers = new DownloadGroupScrollers();
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  private downloadSettingsDialogOpen: boolean = false;
  private pageActive: boolean = true;
  // CustomDialogController is only valid when it is a member-variable
  // initializer inside the component; rebuilding it per open is unsupported and
  // crashed the PC surface. One controller is reused, and each open is signalled
  // through openRevision so the dialog re-reads the saved settings.
  private downloadSettingsDialogController: CustomDialogController = new CustomDialogController({
    builder: BrowserDownloadSettingsDialog({
      openRevision: $downloadSettingsDialogRevision,
      resolveBoundary: (): DownloadTaskBoundary => {
        return this.getCurrentDownloadBoundary();
      },
      onClose: (): void => {
        this.closeDownloadSettingsDialog();
      },
      onChooseCustomLocation: (): void => {
        this.pickCustomDownloadLocationFromDialog();
      }
    }),
    alignment: DialogAlignment.Center,
    autoCancel: true,
    customStyle: false,
    backgroundColor: resolveCenteredDialogSurfaceColor(),
    backgroundBlurStyle: BlurStyle.NONE,
    cornerRadius: CENTERED_DIALOG_CORNER_RADIUS_VP,
    width: resolveCenteredDialogControllerWidth('m'),
    onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
      this.downloadSettingsDialogOpen = false;
      dismissDialogAction.dismiss();
    }
  });

  private groupSwiperController: SwiperController = new SwiperController();
  private optimisticControlByGuid: Map<string, OptimisticControlSnapshot> = new Map();

  aboutToAppear(): void {
    try {
      let routeParams: BrowserPrivateBoundaryRouteParams | undefined;
      if (this.presentationMode === 'native_tab') {
        routeParams = {
          dataScope: this.embeddedDataScope,
          privacyMode: this.embeddedPrivacyMode,
          boundarySource: this.embeddedPrivacyMode === 'private' ? 'private_session' : 'profile'
        };
      } else {
        routeParams = router.getParams() as BrowserPrivateBoundaryRouteParams | undefined;
      }
      hilog.info(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'aboutToAppear begin params=%{public}s activeWindow=%{public}s',
        JSON.stringify(routeParams ?? {}),
        BrowserWindowRuntime.getActiveWindowId()
      );
      this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(routeParams);
      this.logDownloadManagementLifecycle('about_to_appear');
      this.bindDownloadUpdates();
      this.requestDownloadRepositoryInitialization();
    } catch (error) {
      this.downloadListState = createEmptyDownloadManagementListState();
      this.statusText = resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_004'));
      hilog.error(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'aboutToAppear failed: %{public}s',
        this.stringifyError(error)
      );
    }
  }

  aboutToDisappear(): void {
    this.pageActive = false;
    this.closeDownloadSettingsDialog();
    this.logDownloadManagementLifecycle('about_to_disappear');
    this.stopAutoRefreshTimer();
    this.stopDeferredRefreshTimer();
    this.releaseProgressBroadcastPause();
    this.unbindDownloadUpdates();
  }

  build() {
    if (this.presentationMode === 'native_tab') {
      this.buildDesktopWorkspace()
    } else {
      this.buildPhoneWorkspace()
    }
  }

  @Builder
  private buildPhoneWorkspace() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.buildManagementScaffold()

      this.buildSelectionToolbarOverlay()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], this.resolveSystemSafeAreaEdges())
    .onAppear(() => {
      this.presentCancelDialogIfNeeded();
      this.presentCompletedDeleteDialogIfNeeded();
    })
  }

  @Builder
  private buildDesktopWorkspace() {
    ManagementLargeScreenShell({
      title: this.resolveScreenTitle(),
      badge: this.resolveDesktopBadge(),
      searchPlaceholder: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_038')),
      searchQuery: this.desktopQuery,
      onSearchChange: (value: string): void => {
        this.desktopQuery = value;
      },
      sidebar: (): void => {
        this.buildDesktopSidebar()
      },
      toolbarActions: (): void => {
        this.buildDesktopToolbarActions()
      },
      content: (): void => {
        this.buildDesktopContent()
      }
    })
    .onAppear(() => {
      this.presentCancelDialogIfNeeded();
      this.presentCompletedDeleteDialogIfNeeded();
    })
  }

  @Builder
  private buildDesktopSidebar() {
    ManagementLargeScreenNavSection({ title: resolveAppResourceText($r('app.string.settings_web_downloads')) })
    ForEach(this.downloadListState.groups, (group: DownloadManagementGroupState) => {
      ManagementLargeScreenNavItem({
        title: group.label,
        count: `${group.count}`,
        selected: this.selectedGroup === group.group,
        iconId: group.group === 'completed' ? 'browser.shortcut.downloads' : 'settings.downloads',
        onSelect: (): void => {
          this.selectGroup(group.group);
        }
      })
    }, (group: DownloadManagementGroupState): string => group.group)
  }

  @Builder
  private buildDesktopToolbarActions() {
    if (this.isSelectionMode) {
      ManagementLargeScreenTextButton({
        label: resolveAppResourceText($r('app.string.ui_select_all')),
        onAction: (): void => {
          this.selectAllVisibleRows();
        }
      })
      ManagementLargeScreenTextButton({
        label: resolveAppResourceText($r('app.string.settings_delete')),
        isEnabled: this.selectedGuids.length > 0,
        onAction: (): void => {
          this.confirmDeleteSelectedRows();
        }
      })
      ManagementLargeScreenTextButton({
        label: resolveAppResourceText($r('app.string.settings_site_info_done')),
        onAction: (): void => {
          this.exitSelectionMode();
        }
      })
    } else if (this.shouldShowLargeScreenDownloadSettings()) {
      ManagementLargeScreenIconButton({
        iconId: 'settings.general',
        label: resolveAppResourceText($r('app.string.settings_web_download_settings')),
        onAction: (): void => {
          this.openDownloadSettingsDialog();
        }
      })
    }
  }

  @Builder
  private buildDesktopContent() {
    Column() {
      if (this.isSessionEphemeral) {
        Text(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_033')))
          .width('100%')
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .padding({
            left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
            right: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
            top: 12
          })
      }
      if (this.resolveDesktopRows().length === 0) {
        this.buildEmptyState()
      } else {
        List({ space: MANAGEMENT_LARGE_SCREEN_ROW_GAP }) {
          ForEach(this.resolveDesktopRows(), (row: DownloadManagementRowState) => {
            ListItem() {
              BrowserDownloadManagementRow({
                row: row,
                presentation: 'desktop_row',
                selectionMode: this.isSelectionMode,
                selected: this.isRowSelected(row.guid),
                onAction: (guid: string, action: DownloadManagementRowAction): void => {
                  this.handleRowAction(guid, action);
                },
                onToggleSelection: (guid: string): void => {
                  this.toggleRowSelection(guid);
                }
              })
            }
          }, (row: DownloadManagementRowState): string =>
            `${row.guid}:${this.isRowSelected(row.guid) ? 'selected' : 'idle'}:${this.isSelectionMode ? 'edit' : 'browse'}`)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({
          left: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
          right: MANAGEMENT_LARGE_SCREEN_ROW_INSET,
          top: 8,
          bottom: MANAGEMENT_LARGE_SCREEN_ROW_INSET
        })
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildManagementScaffold() {
    Column() {
      ManagementHdsScaffold({
        title: this.resolveScreenTitle(),
        backIconKind: 'close',
        showBackButton: this.presentationMode !== 'native_tab',
        useTopSafeInset: this.presentationMode !== 'native_tab',
        pageBackground: this.storedPageBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: this.isSessionEphemeral,
        immersiveContent: this.presentationMode !== 'native_tab',
        menuActions: this.buildHeaderMenuActions(),
        onBack: () => {
          if (this.isSelectionMode) {
            this.exitSelectionMode();
            return;
          }
          router.back();
        }
      }) {
        Stack({ alignContent: Alignment.TopStart }) {
          this.buildDownloadPages()

          if (this.getAvailableGroups().length > 0) {
            Column() {
              this.buildPinnedGroupFilters()
            }
            .width('100%')
            .position({ x: 0, y: this.resolveDownloadFiltersTopInset() })
            .zIndex(2)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(this.storedPageBackgroundColor)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildSelectionToolbarOverlay() {
    if (this.isSelectionMode) {
      Stack({ alignContent: Alignment.Bottom }) {
        FloatingSelectionToolbar({
          actions: [
            {
              airaIconId: 'browser.toolbar.selectAll',
              title: resolveAppResourceText($r('app.string.ui_select_all')),
              action: (): void => {
                this.selectAllVisibleRows();
              }
            },
            {
              airaIconId: 'browser.tabs.delete',
              title: resolveAppResourceText($r('app.string.settings_delete')),
              action: (): void => {
                this.confirmDeleteSelectedRows();
              }
            }
          ]
        })
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: DOWNLOAD_SELECTION_TOOLBAR_FLOAT_BOTTOM })
      .hitTestBehavior(HitTestMode.Transparent)
      .zIndex(60)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
  }

  private resolveScreenTitle(): string {
    if (this.isSelectionMode) {
      return buildDownloadSelectionTitle(this.selectedGuids.length);
    }
    return resolveAppResourceText($r('app.string.settings_web_downloads'));
  }

  @Builder
  private buildDownloadPages() {
    if (this.isSessionEphemeral && this.areAllGroupsEmpty()) {
      this.buildDownloadGroupPage(this.selectedGroup, true)
    } else {
      Swiper(this.groupSwiperController) {
        ForEach(this.getAvailableGroups(), (group: DownloadManagementGroupState) => {
          this.buildDownloadGroupPage(group.group, false)
        }, (group: DownloadManagementGroupState) => group.group)
      }
      .index(this.resolveSelectedGroupIndex())
      .indicator(false)
      .loop(false)
      .duration(280)
      .cachedCount(3)
      .width('100%')
      .height('100%')
      .onTouch((event: TouchEvent) => {
        this.handleInteractionTouch(event);
      })
      .onChange((index: number) => {
        this.syncSelectedGroupFromIndex(index);
      })
    }
  }

  @Builder
  private buildPinnedGroupFilters() {
    Row({ space: 12 }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: this.resolveGroupFilterWidth(),
        surfaceHeight: 36,
        surfaceRadius: 18,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
        fallbackColor: this.storedControlBackgroundColor,
        backgroundBlurEnabled: false
      }) {
        SegmentedTabs({
          options: this.buildGroupTabOptions(),
          selectedId: this.selectedGroup,
          barHeight: 36,
          itemHeight: 30,
          fontSize: 14,
          barPadding: 3,
          fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
          barMaterialEnabled: false,
          onSelect: (id: string) => {
            this.selectGroup(id as DownloadQueryGroup);
          }
        })
          .width('100%')
          .height(36)
      }

      if (this.shouldShowLargeScreenDownloadSettings()) {
        Blank()
          .layoutWeight(1)

        this.buildLargeScreenDownloadSettingsButton()
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: 8, bottom: 10 })
  }

  @Builder
  private buildLargeScreenDownloadSettingsButton() {
    Button(resolveAppResourceText($r('app.string.settings_web_download_settings')), { type: ButtonType.Normal })
      .height(LARGE_SCREEN_DOWNLOAD_SETTINGS_BUTTON_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedPrimaryTextColor)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .border({ width: 1, color: this.storedDividerColor })
      .borderRadius(LARGE_SCREEN_DOWNLOAD_SETTINGS_BUTTON_HEIGHT_VP / 2)
      .stateEffect(true)
      .accessibilityText(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_037')))
      .onClick((): void => {
        this.openDownloadSettingsDialog();
      })
  }

  private openDownloadSettingsDialog(): void {
    if (this.downloadSettingsDialogOpen) {
      return;
    }
    // The folder picker closes this dialog and reopens it afterwards. The
    // controller is reused because a CustomDialogController cannot be rebuilt
    // outside the component initializer; bumping openRevision makes the
    // reopened dialog re-read the saved settings instead.
    this.downloadSettingsDialogRevision += 1;
    this.downloadSettingsDialogOpen = true;
    this.downloadSettingsDialogController.open();
  }

  private closeDownloadSettingsDialog(): void {
    if (!this.downloadSettingsDialogOpen) {
      return;
    }
    this.downloadSettingsDialogOpen = false;
    try {
      this.downloadSettingsDialogController.close();
    } catch (_error) {
    }
  }

  private pickCustomDownloadLocationFromDialog(): void {
    this.closeDownloadSettingsDialog();
    setTimeout((): void => {
      void this.chooseCustomDownloadLocationAfterDialog();
    }, 180);
  }

  private async chooseCustomDownloadLocationAfterDialog(): Promise<void> {
    const directoryService = new DownloadLocationDirectoryService();
    const settingsViewModel = new DownloadSettingsViewModel();
    try {
      if (!directoryService.isFolderSelectionSupported()) {
        this.showToast(resolveAppResourceText($r('app.string.settings_web_download_folder_unsupported_fallback')));
      } else {
        const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const result = await directoryService.selectDirectory(context);
        if (result.status === 'unusable_folder') {
          this.showToast(resolveAppResourceText($r('app.string.settings_web_download_folder_unavailable')));
        } else if (result.status === 'selected' && result.selection !== undefined) {
          const selection = result.selection;
          // Advisory probe: a false negative must not discard the user's pick,
          // because the export path handles a real write failure on its own.
          const isWritable = await directoryService.verifyDirectoryWritable(selection.uri);
          const boundary = this.getCurrentDownloadBoundary();
          const currentSettings = sharedDownloadPolicyService.readSettings(boundary);
          const nextSettings = settingsViewModel.buildSettingsPatch(currentSettings, {
            defaultLocation: 'custom',
            customLocationUri: selection.uri,
            customLocationLabel: selection.label
          });
          await sharedDownloadPolicyService.updateSettings(boundary, nextSettings);
          if (currentSettings.customLocationUri.length > 0 &&
            currentSettings.customLocationUri !== selection.uri) {
            void directoryService.releaseDirectory(currentSettings.customLocationUri);
          }
          if (!isWritable) {
            this.showToast(resolveAppResourceText($r('app.string.settings_web_download_folder_selected_fallback')));
          } else if (!result.isPersisted) {
            this.showToast(resolveAppResourceText($r('app.string.settings_web_download_folder_selected_reauth')));
          }
        }
      }
    } catch (error) {
      this.showToast(resolveAppResourceText($r('app.string.settings_web_download_folder_failed')));
      hilog.error(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'choose download location failed: %{public}s',
        this.stringifyError(error)
      );
    }
    if (this.pageActive) {
      this.openDownloadSettingsDialog();
    }
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    if (this.presentationMode === 'native_tab' || this.isSelectionMode) {
      return [];
    }
    const actions: ManagementHdsMenuAction[] = [
      {
        label: resolveAppResourceText($r('app.string.settings_web_download_settings')),
        icon: $r('sys.symbol.gearshape_fill'),
        action: () => {
          this.openDownloadSettingsPage();
        }
      }
    ];
    return actions;
  }

  @Builder
  private buildPrivateBoundaryCard() {
    Column({ space: 8 }) {
      Text(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_008')))
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
      Text(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_009')))
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
      Text(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_036')))
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(22)
  }

  @Builder
  private buildDownloadCardTree(group: DownloadQueryGroup, centerEmptyStateInViewport: boolean) {
    Column() {
      if (centerEmptyStateInViewport && this.getRowsForGroup(group).length === 0) {
        Column({ space: 12 }) {
          Blank()
            .layoutWeight(1)

          this.buildEmptyState()

          Blank()
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .justifyContent(FlexAlign.Start)
      } else if (this.getRowsForGroup(group).length === 0) {
        this.buildEmptyState()
      } else {
        this.buildRows(group)
      }
    }
    .width('100%')
  }

  @Builder
  private buildRows(group: DownloadQueryGroup) {
    Column({ space: 12 }) {
      ForEach(this.getRowsForGroup(group), (row: DownloadManagementRowState) => {
        BrowserDownloadManagementRow({
          row: row,
          selectionMode: this.isSelectionMode,
          selected: this.isRowSelected(row.guid),
          onAction: (guid: string, action: DownloadManagementRowAction): void => {
            this.handleRowAction(guid, action);
          },
          onToggleSelection: (guid: string): void => {
            this.toggleRowSelection(guid);
          }
        })
      }, (row: DownloadManagementRowState) =>
        `${row.guid}:${this.isRowSelected(row.guid) ? 'selected' : 'idle'}:${this.isSelectionMode ? 'edit' : 'browse'}`)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildDownloadGroupPage(group: DownloadQueryGroup, centerEmptyStateInViewport: boolean) {
    Scroll(this.groupScrollers.scrollerFor(group)) {
      Column({ space: 14 }) {
        if (this.isSessionEphemeral) {
          this.buildPrivateBoundaryCard()
        }
        this.buildDownloadCardTree(group, centerEmptyStateInViewport)
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: this.resolveDownloadContentTopInset(),
        bottom: 22
      })
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .attributeModifier(browserSheetHeaderBlurModifier(this.presentationMode === 'native_tab' ? 0 : this.headerBlurRadius))
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
    .onDidScroll(() => {
      this.headerBlurRadius = resolveBrowserSheetHeaderBlurRadius(
        this.groupScrollers.scrollerFor(group).currentOffset().yOffset
      );
    })
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], this.resolveSystemSafeAreaEdges())
  }

  private resolveDownloadFiltersTopInset(): number {
    if (this.presentationMode === 'native_tab') {
      return DOWNLOAD_EMBEDDED_FILTER_TOP_INSET;
    }
    return Math.max(0, Math.ceil(this.topSafeInsetVp)) + DOWNLOAD_IMMERSIVE_TITLE_TOP_INSET +
      DOWNLOAD_IMMERSIVE_TITLE_HEIGHT + DOWNLOAD_IMMERSIVE_TITLE_TO_FILTER_GAP;
  }

  private resolveDownloadContentTopInset(): number {
    if (this.getAvailableGroups().length > 0) {
      return this.resolveDownloadFiltersTopInset() + DOWNLOAD_FILTER_LAYOUT_HEIGHT + DOWNLOAD_FILTER_TO_CONTENT_GAP;
    }
    if (this.presentationMode === 'native_tab') {
      return DOWNLOAD_EMBEDDED_FILTER_TOP_INSET;
    }
    return Math.max(0, Math.ceil(this.topSafeInsetVp)) + DOWNLOAD_IMMERSIVE_TITLE_TOP_INSET +
      DOWNLOAD_IMMERSIVE_TITLE_HEIGHT + DOWNLOAD_IMMERSIVE_TITLE_TO_CONTENT_GAP;
  }

  @Builder
  private buildEmptyState() {
    AppEmptyState({
      airaIconId: 'settings.downloads',
      title: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_043')),
      message: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_019'))
    })
  }

  private refreshState(): void {
    if (this.isRefreshingState) {
      hilog.info(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'refresh skipped reason=reentrant selected=%{public}s',
        this.selectedGroup
      );
      return;
    }
    this.isRefreshingState = true;
    try {
      const boundary = this.getCurrentDownloadBoundary();
      hilog.info(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'refresh begin selected=%{public}s boundary=%{public}s',
        this.selectedGroup,
        this.buildBoundarySummary(boundary)
      );
      const baseListState = this.downloadManagerViewModel.buildManagementListStateSnapshot(sharedDownloadRuntimeService, boundary);
      const groupSelection: DownloadManagementGroupSelection =
        this.downloadManagerViewModel.resolveManagementGroupSelection(
          baseListState,
          this.selectedGroup,
          this.hasResolvedInitialContentGroup
        );
      this.selectedGroup = groupSelection.group;
      this.hasResolvedInitialContentGroup = groupSelection.initialContentResolved;
      const latestListState = this.filterLocallyHiddenListState(
        baseListState
      );
      this.downloadListState = this.reconcileRowStateList(latestListState);
      this.pruneSelectionToVisibleRows();
      this.syncSwiperToSelectedGroup(false);
      this.updateAutoRefreshTimer();
      const selectedRows = this.getRowsForGroup(this.selectedGroup);
      hilog.info(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'refresh group=%{public}s count=%{public}d boundary=%{public}s',
        this.selectedGroup,
        selectedRows.length,
        this.buildBoundarySummary(boundary)
      );
    } catch (error) {
      this.downloadListState = createEmptyDownloadManagementListState();
      this.statusText = resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_004'));
      this.stopAutoRefreshTimer();
      hilog.error(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'refreshState failed: %{public}s',
        this.stringifyError(error)
      );
    } finally {
      this.isRefreshingState = false;
    }
  }

  private reconcileRowStateList(nextState: DownloadManagementListState): DownloadManagementListState {
    const existingRowsByGuid: Map<string, DownloadManagementRowState> = new Map();
    this.downloadListState.groups.forEach((group: DownloadManagementGroupState) => {
      group.rows.forEach((row: DownloadManagementRowState) => {
        existingRowsByGuid.set(row.guid, row);
      });
    });
    const nextGroups: DownloadManagementGroupState[] = [];
    const visibleGuids: string[] = [];
    nextState.groups.forEach((group: DownloadManagementGroupState) => {
      const nextRows: DownloadManagementRowState[] = [];
      group.rows.forEach((row: DownloadManagementRowState) => {
        const existingRow = existingRowsByGuid.get(row.guid);
        const resolvedRow = existingRow ?? row;
        if (existingRow !== undefined) {
          existingRow.syncFromRow(row);
        }
        this.reconcileOptimisticControl(resolvedRow, row);
        nextRows.push(resolvedRow);
        visibleGuids.push(row.guid);
      });
      nextGroups.push({
        group: group.group,
        label: group.label,
        count: group.count,
        rows: nextRows
      });
    });
    this.pruneOptimisticControls(visibleGuids);
    return {
      groups: nextGroups
    };
  }

  private bindDownloadUpdates(): void {
    this.unbindDownloadUpdates();
    this.downloadListenerKey = sharedDownloadRuntimeService.addCallbacksListener({
      onTaskListChange: () => {
        this.logDownloadManagementLifecycle('listener_task_list_change');
        this.requestDeferredRefresh('listener_task_list_change');
      },
      onInfo: (message: string) => {
        this.statusText = message;
        this.logDownloadManagementLifecycle(`listener_info:${message}`);
        this.requestDeferredRefresh('listener_info');
      },
      onError: (message: string) => {
        this.statusText = message;
        this.logDownloadManagementLifecycle(`listener_error:${message}`);
        this.requestDeferredRefresh('listener_error');
      }
    });
    this.logDownloadManagementLifecycle(`bind_updates:${this.downloadListenerKey}`);
  }

  private requestDownloadRepositoryInitialization(): void {
    void sharedDownloadRuntimeService.initializeRepository()
      .catch((error: Error) => {
        this.statusText = resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_004'));
        hilog.error(
          DOWNLOAD_MANAGEMENT_DOMAIN,
          DOWNLOAD_MANAGEMENT_TAG,
          'repository initialization failed: %{public}s',
          this.stringifyError(error)
        );
      });
  }

  private requestDeferredRefresh(reason: string): void {
    if (!this.isInteractionQuiet()) {
      this.hasDeferredRefresh = false;
      this.refreshState();
      return;
    }
    this.hasDeferredRefresh = true;
    this.logDownloadManagementLifecycle(`refresh_deferred:${reason}`);
    this.scheduleDeferredRefresh();
  }

  private scheduleDeferredRefresh(): void {
    if (!this.hasDeferredRefresh || this.deferredRefreshTimer >= 0) {
      return;
    }
    const delayMs = Math.max(0, this.interactionQuietUntil - Date.now()) + 32;
    this.deferredRefreshTimer = setTimeout(() => {
      this.deferredRefreshTimer = -1;
      if (this.isInteractionQuiet()) {
        this.scheduleDeferredRefresh();
        return;
      }
      if (!this.hasDeferredRefresh) {
        return;
      }
      this.hasDeferredRefresh = false;
      this.logDownloadManagementLifecycle('refresh_deferred_flush');
      this.refreshState();
    }, delayMs);
  }

  private stopDeferredRefreshTimer(): void {
    if (this.deferredRefreshTimer >= 0) {
      clearTimeout(this.deferredRefreshTimer);
      this.deferredRefreshTimer = -1;
    }
    this.hasDeferredRefresh = false;
  }

  private markInteractionQuiet(): void {
    this.interactionQuietUntil = Date.now() + DOWNLOAD_MANAGEMENT_INTERACTION_QUIET_MS;
    sharedDownloadRuntimeService.setTaskListProgressBroadcastPaused(
      DOWNLOAD_MANAGEMENT_PROGRESS_BROADCAST_PAUSE_OWNER,
      true
    );
    this.scheduleProgressBroadcastResume();
  }

  private isInteractionQuiet(): boolean {
    return Date.now() < this.interactionQuietUntil;
  }

  private handleInteractionTouch(event: TouchEvent): void {
    if (event.type === TouchType.Down || event.type === TouchType.Move) {
      this.markInteractionQuiet();
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.markInteractionQuiet();
      this.scheduleDeferredRefresh();
    }
  }

  private scheduleProgressBroadcastResume(): void {
    if (this.progressBroadcastResumeTimer >= 0) {
      clearTimeout(this.progressBroadcastResumeTimer);
      this.progressBroadcastResumeTimer = -1;
    }
    const delayMs = Math.max(0, this.interactionQuietUntil - Date.now()) + 32;
    this.progressBroadcastResumeTimer = setTimeout(() => {
      this.progressBroadcastResumeTimer = -1;
      if (this.isInteractionQuiet()) {
        this.scheduleProgressBroadcastResume();
        return;
      }
      sharedDownloadRuntimeService.setTaskListProgressBroadcastPaused(
        DOWNLOAD_MANAGEMENT_PROGRESS_BROADCAST_PAUSE_OWNER,
        false
      );
    }, delayMs);
  }

  private releaseProgressBroadcastPause(): void {
    if (this.progressBroadcastResumeTimer >= 0) {
      clearTimeout(this.progressBroadcastResumeTimer);
      this.progressBroadcastResumeTimer = -1;
    }
    sharedDownloadRuntimeService.setTaskListProgressBroadcastPaused(
      DOWNLOAD_MANAGEMENT_PROGRESS_BROADCAST_PAUSE_OWNER,
      false
    );
  }

  private updateAutoRefreshTimer(): void {
    if (sharedDownloadRuntimeService.hasRealtimeActivity(this.getCurrentDownloadBoundary())) {
      this.startAutoRefreshTimer();
      return;
    }
    this.stopAutoRefreshTimer();
  }

  private unbindDownloadUpdates(): void {
    if (this.downloadListenerKey.length === 0) {
      return;
    }
    this.logDownloadManagementLifecycle(`unbind_updates:${this.downloadListenerKey}`);
    sharedDownloadRuntimeService.removeCallbacksListener(this.downloadListenerKey);
    this.downloadListenerKey = '';
  }

  private startAutoRefreshTimer(): void {
    if (this.autoRefreshTimer >= 0) {
      return;
    }
    this.stopAutoRefreshTimer();
    this.autoRefreshTimer = setInterval(() => {
      if (!sharedDownloadRuntimeService.hasRealtimeActivity(this.getCurrentDownloadBoundary())) {
        this.logDownloadManagementLifecycle('auto_refresh_idle_stop');
        this.stopAutoRefreshTimer();
        return;
      }
      sharedDownloadRuntimeService.refreshActiveDownloads(false);
      this.logDownloadManagementLifecycle('auto_refresh_tick');
      this.requestDeferredRefresh('auto_refresh_tick');
    }, DOWNLOAD_MANAGEMENT_REFRESH_INTERVAL_MS);
    this.logDownloadManagementLifecycle(`start_auto_refresh:${DOWNLOAD_MANAGEMENT_REFRESH_INTERVAL_MS}`);
  }

  private stopAutoRefreshTimer(): void {
    if (this.autoRefreshTimer >= 0) {
      this.logDownloadManagementLifecycle('stop_auto_refresh');
      clearInterval(this.autoRefreshTimer);
      this.autoRefreshTimer = -1;
    }
  }

  private buildGroupFilterLabel(group: DownloadManagementFilterChipView): string {
    if (group.count > 0) {
      return `${group.label} ${group.count}`;
    }
    return group.label;
  }

  private selectGroup(group: DownloadQueryGroup): void {
    this.markInteractionQuiet();
    this.hasResolvedInitialContentGroup = true;
    this.selectedGroup = group;
    this.logDownloadManagementLifecycle(`select_group:${group}`);
    this.syncSwiperToSelectedGroup(true);
    this.scheduleDeferredRefresh();
  }

  private presentCancelDialogIfNeeded(): void {
    if (this.cancelConfirmGuid.length === 0) {
      return;
    }
    showCenteredAlertDialog({
      title: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_017')),
      message: resolveAppResourceText($r('app.string.download_cancel_message', this.cancelConfirmFileName)),
      autoCancel: true,
      primaryButton: {
        value: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_045')),
        action: () => {
          this.cancelConfirmGuid = '';
          this.cancelConfirmFileName = '';
        }
      },
      secondaryButton: {
        value: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_044')),
        action: () => {
          const guid = this.cancelConfirmGuid;
          this.cancelConfirmGuid = '';
          this.cancelConfirmFileName = '';
          void this.confirmCancelDownload(guid);
        }
      },
      cancel: () => {
        this.cancelConfirmGuid = '';
        this.cancelConfirmFileName = '';
      }
    });
  }

  private requestCancelDownload(guid: string): void {
    const item = sharedDownloadRuntimeService.listTasksSnapshot(this.getCurrentDownloadBoundary())
      .find((candidate) => candidate.guid === guid);
    this.cancelConfirmGuid = guid;
    this.cancelConfirmFileName = item?.suggestedFileName ?? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_020'));
    this.presentCancelDialogIfNeeded();
  }

  private async confirmCancelDownload(guid: string): Promise<void> {
    const boundary = this.getCurrentDownloadBoundary();
    this.hideTaskLocally(guid);
    const succeeded = await sharedDownloadRuntimeService.cancelAndRemoveTaskForBoundary(guid, boundary);
    if (!succeeded) {
      this.showTaskLocally(guid);
    }
    this.completeAsyncDownloadTaskAction(succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_005')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_024')));
  }

  private presentCompletedDeleteDialogIfNeeded(): void {
    if (this.completedDeleteConfirmGuid.length === 0) {
      return;
    }
    const deleteFile = this.completedDeleteConfirmMode === 'task_and_file';
    showCenteredAlertDialog({
      title: deleteFile ? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_016')) : resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_012')),
      message: deleteFile
        ? resolveAppResourceText($r('app.string.download_delete_file_message', this.completedDeleteConfirmFileName))
        : resolveAppResourceText($r('app.string.download_delete_task_message', this.completedDeleteConfirmFileName)),
      autoCancel: true,
      primaryButton: {
        value: resolveAppResourceText($r('app.string.settings_account_cancel')),
        action: () => {
          this.clearCompletedDeleteConfirmation();
        }
      },
      secondaryButton: {
        value: deleteFile ? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_015')) : resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_013')),
        action: () => {
          const guid = this.completedDeleteConfirmGuid;
          const mode = this.completedDeleteConfirmMode;
          this.clearCompletedDeleteConfirmation();
          if (mode === 'task_and_file') {
            void this.confirmDeleteCompletedTaskAndFile(guid);
            return;
          }
          this.confirmDeleteCompletedTaskOnly(guid);
        }
      },
      cancel: () => {
        this.clearCompletedDeleteConfirmation();
      }
    });
  }

  private requestCompletedDelete(guid: string, mode: CompletedDownloadDeleteMode): void {
    const item = sharedDownloadRuntimeService.listTasksSnapshot(this.getCurrentDownloadBoundary())
      .find((candidate) => candidate.guid === guid);
    this.completedDeleteConfirmGuid = guid;
    this.completedDeleteConfirmFileName = item?.suggestedFileName ?? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_020'));
    this.completedDeleteConfirmMode = mode;
    this.presentCompletedDeleteDialogIfNeeded();
  }

  private clearCompletedDeleteConfirmation(): void {
    this.completedDeleteConfirmGuid = '';
    this.completedDeleteConfirmFileName = '';
    this.completedDeleteConfirmMode = 'task_only';
  }

  private confirmDeleteCompletedTaskOnly(guid: string): void {
    const boundary = this.getCurrentDownloadBoundary();
    this.hideTaskLocally(guid);
    const succeeded = sharedDownloadRuntimeService.removeTaskRecordForBoundary(guid, boundary);
    if (!succeeded) {
      this.showTaskLocally(guid);
    }
    this.completeDownloadTaskAction(
      succeeded,
      resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_001')),
      resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_021'))
    );
  }

  private async confirmDeleteCompletedTaskAndFile(guid: string): Promise<void> {
    const boundary = this.getCurrentDownloadBoundary();
    this.hideTaskLocally(guid);
    const result = await sharedDownloadRuntimeService.deleteCompletedFileAndRemoveRecordForBoundary(guid, boundary);
    if (!result.recordRemoved) {
      this.showTaskLocally(guid);
      const failureText = result.fileStatus === 'not_found'
        ? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_030'))
        : resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_039'));
      this.showToast(failureText);
      this.completeAsyncDownloadTaskAction(false, '', failureText);
      return;
    }
    const successText = result.fileStatus === 'deleted'
      ? resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_002'))
      : resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_040'));
    this.showToast(successText);
    this.completeAsyncDownloadTaskAction(true, successText, '');
  }

  private openDownloadSettingsPage(): void {
    this.logDownloadManagementLifecycle('open_download_settings');
    router.pushUrl({
      url: DOWNLOAD_SETTINGS_ROUTE,
      params: {
        dataScope: this.getCurrentDownloadBoundary().dataScope,
        privacyMode: this.getCurrentDownloadBoundary().privacyMode
      }
    }).catch((error: Error) => {
      this.statusText = resolveAppResourceText($r('app.string.download_settings_open_failed', this.stringifyError(error)));
    });
  }

  private logDownloadManagementLifecycle(stage: string): void {
    const boundary = this.getCurrentDownloadBoundary();
    hilog.info(
      DOWNLOAD_MANAGEMENT_DOMAIN,
      DOWNLOAD_MANAGEMENT_TAG,
      'lifecycle stage=%{public}s selected=%{public}s boundary=%{public}s status=%{public}s rows=%{public}d hidden=%{public}d',
      stage,
      this.selectedGroup,
      this.buildBoundarySummary(boundary),
      this.statusText,
      this.getRowsForGroup(this.selectedGroup).length,
      this.locallyHiddenTasks.length
    );
  }

  private buildBoundarySummary(boundary: DownloadTaskBoundary): string {
    const counts = sharedDownloadRuntimeService.getStatusCountsSnapshot(boundary);
    return `window=${boundary.windowId} privacy=${boundary.privacyMode} scope=${boundary.dataScope} ` +
      `active=${counts.active} pending=${counts.pending} paused=${counts.paused} completed=${counts.completed} failed=${counts.failed}`;
  }

  private stringifyError(error: Object): string {
    try {
      const serialized = JSON.stringify(error);
      if (serialized !== undefined && serialized !== '{}') {
        return serialized;
      }
    } catch (_err) {
    }
    return `${error}`;
  }

  private getCurrentDownloadBoundary(): DownloadTaskBoundary {
    return {
      windowId: BrowserWindowRuntime.getActiveWindowId(),
      profileId: 'profile-main',
      privacyMode: this.isSessionEphemeral ? 'private' : 'regular',
      dataScope: this.isSessionEphemeral ? 'session_ephemeral' : 'profile_persistent'
    };
  }

  private resolveSystemSafeAreaEdges(): SafeAreaEdge[] {
    return this.presentationMode === 'native_tab' ? [] : [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM];
  }

  private async handleDownloadTaskAction(guid: string, action: DownloadManagementRowAction): Promise<void> {
    const boundary = this.getCurrentDownloadBoundary();
    if (action === 'pause') {
      const succeeded = await sharedDownloadRuntimeService.pauseTaskForBoundary(guid, boundary);
      this.completeControlAction(guid, succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_006')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_027')));
      return;
    }
    if (action === 'resume') {
      const succeeded = await sharedDownloadRuntimeService.resumeTaskForBoundary(guid, boundary);
      this.completeControlAction(guid, succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_007')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_028')));
      return;
    }
    if (action === 'cancel') {
      this.requestCancelDownload(guid);
      return;
    }
    if (action === 'remove_record') {
      const succeeded = sharedDownloadRuntimeService.removeTaskRecordForBoundary(guid, boundary);
      if (!succeeded) {
        this.showTaskLocally(guid);
      }
      this.completeDownloadTaskAction(succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_010')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_032')));
      return;
    }
    if (action === 'retry') {
      const succeeded = await sharedDownloadRuntimeService.retryTaskForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_003')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_029')));
      return;
    }
    if (action === 'open_file') {
      const succeeded = await sharedDownloadRuntimeService.openFileForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_041')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_026')));
      return;
    }
    if (action === 'open_location') {
      const succeeded = await sharedDownloadRuntimeService.openLocationForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_042')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_025')));
      return;
    }
    if (action === 'save_to_system') {
      const succeeded = await sharedDownloadRuntimeService.saveTaskToSystemDownloadsForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_018')), resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_022')));
      return;
    }
    if (action === 'copy_link') {
      await this.copyDownloadLink(guid);
      return;
    }
  }

  private completeDownloadTaskAction(succeeded: boolean, successText: string, failureText: string): void {
    this.statusText = succeeded ? successText : failureText;
    this.refreshState();
  }

  private completeControlAction(guid: string, succeeded: boolean, successText: string, failureText: string): void {
    if (!succeeded) {
      this.optimisticControlByGuid.delete(guid);
    }
    this.completeDownloadTaskAction(succeeded, successText, failureText);
  }

  private completeAsyncDownloadTaskAction(succeeded: boolean, successText: string, failureText: string): void {
    this.statusText = succeeded ? successText : failureText;
    this.refreshState();
  }

  private showToast(message: string): void {
    if (message.length === 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private handleRowAction(guid: string, action: DownloadManagementRowAction): void {
    if (action === 'enter_selection') {
      this.runAfterContextMenuDismiss((): void => {
        this.enterSelectionMode(guid);
      });
      return;
    }
    if (this.isSelectionMode) {
      return;
    }
    if (action === 'cancel') {
      this.requestCancelDownload(guid);
      return;
    }
    if (action === 'remove_record' && this.findVisibleRowByGuid(guid)?.status === 'completed') {
      this.requestCompletedDelete(guid, 'task_only');
      return;
    }
    if (action === 'delete_task_and_file') {
      this.requestCompletedDelete(guid, 'task_and_file');
      return;
    }
    this.applyOptimisticRowAction(guid, action);
    void this.handleDownloadTaskAction(guid, action);
  }

  private async copyDownloadLink(guid: string): Promise<void> {
    const task = sharedDownloadRuntimeService.listTasksSnapshot(this.getCurrentDownloadBoundary())
      .find((candidate) => candidate.guid === guid);
    const url = task?.request.url.trim() ?? '';
    if (url.length === 0) {
      this.showToast(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_034')));
      this.completeDownloadTaskAction(false, '', resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_034')));
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToast(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_011')));
      this.completeDownloadTaskAction(true, resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_011')), '');
    } catch (error) {
      hilog.warn(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'copy download link failed guid=%{public}s error=%{public}s',
        guid,
        this.stringifyError(error)
      );
      this.showToast(resolveAppResourceText($r('app.string.ui_copy_failed')));
      this.completeDownloadTaskAction(false, '', resolveAppResourceText($r('app.string.ui_copy_failed')));
    }
  }

  private hideTaskLocally(guid: string): void {
    if (this.findHiddenTaskSnapshotIndex(guid) >= 0) {
      return;
    }
    this.locallyHiddenTasks = this.locallyHiddenTasks.concat([{
      guid: guid,
      group: this.resolveVisibleGroupForGuid(guid)
    }]);
    this.refreshState();
  }

  private hideTasksLocally(guids: string[]): void {
    const nextHidden: HiddenDownloadTaskSnapshot[] = [];
    guids.forEach((guid: string) => {
      if (this.findHiddenTaskSnapshotIndex(guid) >= 0) {
        return;
      }
      nextHidden.push({
        guid: guid,
        group: this.resolveVisibleGroupForGuid(guid)
      });
    });
    if (nextHidden.length === 0) {
      return;
    }
    this.locallyHiddenTasks = this.locallyHiddenTasks.concat(nextHidden);
  }

  private showTaskLocally(guid: string): void {
    this.locallyHiddenTasks = this.locallyHiddenTasks
      .filter((task: HiddenDownloadTaskSnapshot) => task.guid !== guid);
    this.refreshState();
  }

  private filterLocallyHiddenListState(state: DownloadManagementListState): DownloadManagementListState {
    if (this.locallyHiddenTasks.length <= 0) {
      return state;
    }
    const hiddenGuids = this.locallyHiddenTasks.map((task: HiddenDownloadTaskSnapshot) => task.guid);
    return {
      groups: state.groups.map((group: DownloadManagementGroupState): DownloadManagementGroupState => {
        const hiddenCount = this.locallyHiddenTasks
          .filter((task: HiddenDownloadTaskSnapshot) => task.group === group.group).length;
        return {
          group: group.group,
          label: group.label,
          count: Math.max(0, group.count - hiddenCount),
          rows: group.rows.filter((row: DownloadManagementRowState) => hiddenGuids.indexOf(row.guid) < 0)
        };
      })
    };
  }

  private findHiddenTaskSnapshotIndex(guid: string): number {
    return this.locallyHiddenTasks.findIndex((task: HiddenDownloadTaskSnapshot) => task.guid === guid);
  }

  private resolveVisibleGroupForGuid(guid: string): DownloadQueryGroup {
    const row = this.findVisibleRowByGuid(guid);
    if (row !== undefined) {
      return this.resolveCountedGroupFromStatus(row.status);
    }
    const task = sharedDownloadRuntimeService.listTasksSnapshot(this.getCurrentDownloadBoundary())
      .find((candidate) => candidate.guid === guid);
    if (task !== undefined) {
      return this.resolveCountedGroupFromStatus(task.status);
    }
    return this.selectedGroup;
  }

  private resolveCountedGroupFromStatus(status: DownloadV2Status): DownloadQueryGroup {
    const group = getDownloadV2QueryGroup(status);
    if (group === 'completed') {
      return 'completed';
    }
    if (group === 'in_progress' || group === 'pending' || group === 'paused' || group === 'failed') {
      return 'in_progress';
    }
    return this.selectedGroup;
  }

  private removeVisibleRow(guid: string): void {
    this.downloadListState = {
      groups: this.downloadListState.groups.map((group: DownloadManagementGroupState): DownloadManagementGroupState => {
        const nextRows = group.rows.filter((row: DownloadManagementRowState) => row.guid !== guid);
        const removedCount = group.rows.length === nextRows.length ? 0 : 1;
        return {
          group: group.group,
          label: group.label,
          count: Math.max(0, group.count - removedCount),
          rows: nextRows
        };
      })
    };
  }

  private applyOptimisticCancel(guid: string): void {
    this.hideTaskLocally(guid);
    this.removeVisibleRow(guid);
  }

  private applyOptimisticPause(guid: string): void {
    const row = this.findVisibleRowByGuid(guid);
    this.rememberOptimisticControl(guid, 'paused');
    if (row === undefined) {
      return;
    }
    this.downloadManagerViewModel.applyOptimisticStatus(row, 'paused');
  }

  private applyOptimisticResume(guid: string): void {
    const row = this.findVisibleRowByGuid(guid);
    this.rememberOptimisticControl(guid, 'running');
    if (row === undefined) {
      return;
    }
    this.downloadManagerViewModel.applyOptimisticStatus(row, 'running');
  }

  private applyOptimisticRowAction(guid: string, action: DownloadManagementRowAction): void {
    if (action === 'pause') {
      this.applyOptimisticPause(guid);
      return;
    }
    if (action === 'resume') {
      this.applyOptimisticResume(guid);
      return;
    }
    if (action === 'cancel' || action === 'remove_record') {
      this.applyOptimisticCancel(guid);
    }
  }

  private rememberOptimisticControl(guid: string, targetStatus: DownloadV2Status): void {
    this.optimisticControlByGuid.set(guid, {
      targetStatus: targetStatus,
      expiresAt: Date.now() + DOWNLOAD_OPTIMISTIC_CONTROL_GRACE_MS
    });
  }

  private reconcileOptimisticControl(row: DownloadManagementRowState, sourceRow: DownloadManagementRowState): void {
    const optimisticControl = this.optimisticControlByGuid.get(row.guid);
    if (optimisticControl === undefined) {
      return;
    }
    if (Date.now() > optimisticControl.expiresAt || sourceRow.status === optimisticControl.targetStatus) {
      this.optimisticControlByGuid.delete(row.guid);
      return;
    }
    if (!this.downloadManagerViewModel.shouldRetainOptimisticStatus(
      optimisticControl.targetStatus,
      sourceRow.status
    )) {
      this.optimisticControlByGuid.delete(row.guid);
      return;
    }
    this.downloadManagerViewModel.applyOptimisticStatus(row, optimisticControl.targetStatus);
  }

  private pruneOptimisticControls(visibleGuids: string[]): void {
    if (this.optimisticControlByGuid.size <= 0) {
      return;
    }
    const visibleGuidSet = new Set<string>(visibleGuids);
    Array.from(this.optimisticControlByGuid.keys()).forEach((guid: string) => {
      const optimisticControl = this.optimisticControlByGuid.get(guid);
      if (optimisticControl === undefined) {
        return;
      }
      if (Date.now() > optimisticControl.expiresAt || !visibleGuidSet.has(guid)) {
        this.optimisticControlByGuid.delete(guid);
      }
    });
  }

  private getAvailableGroups(): DownloadManagementGroupState[] {
    return this.downloadListState.groups.slice();
  }

  private buildGroupTabOptions(): SegmentedTabOption[] {
    return this.getAvailableGroups().map((group: DownloadManagementGroupState): SegmentedTabOption => {
      return {
        id: group.group,
        title: this.buildGroupFilterLabel(group)
      };
    });
  }

  private resolveGroupFilterWidth(): string | number {
    if (this.presentationMode !== 'native_tab') {
      return '100%';
    }
    return Math.max(
      LARGE_SCREEN_DOWNLOAD_FILTER_ITEM_WIDTH_VP,
      this.getAvailableGroups().length * LARGE_SCREEN_DOWNLOAD_FILTER_ITEM_WIDTH_VP
    );
  }

  private shouldShowLargeScreenDownloadSettings(): boolean {
    return this.presentationMode === 'native_tab';
  }

  private getRowsForGroup(group: DownloadQueryGroup): DownloadManagementRowState[] {
    const matchedGroup = this.downloadListState.groups.find((item: DownloadManagementGroupState) => item.group === group);
    return matchedGroup === undefined ? [] : matchedGroup.rows;
  }

  private resolveDesktopRows(): DownloadManagementRowState[] {
    const query = this.desktopQuery.trim().toLowerCase();
    const rows = this.getRowsForGroup(this.selectedGroup);
    if (query.length === 0) {
      return rows;
    }
    return rows.filter((row: DownloadManagementRowState): boolean => row.fileName.toLowerCase().includes(query));
  }

  private resolveDesktopBadge(): string {
    if (this.isSelectionMode) {
      return '';
    }
    return resolveAppResourceText($r('app.string.history_item_count', this.resolveDesktopRows().length));
  }

  private findVisibleRowByGuid(guid: string): DownloadManagementRowState | undefined {
    for (let index = 0; index < this.downloadListState.groups.length; index += 1) {
      const row = this.downloadListState.groups[index].rows.find((candidate: DownloadManagementRowState) => candidate.guid === guid);
      if (row !== undefined) {
        return row;
      }
    }
    return undefined;
  }

  private areAllGroupsEmpty(): boolean {
    return this.downloadListState.groups.every((group: DownloadManagementGroupState) => group.rows.length === 0);
  }

  private resolveSelectedGroupIndex(): number {
    const groups = this.getAvailableGroups();
    const selectedIndex = groups.findIndex((group: DownloadManagementGroupState) => group.group === this.selectedGroup);
    return selectedIndex >= 0 ? selectedIndex : 0;
  }

  private enterSelectionMode(initialGuid?: string): void {
    if (!this.canEnterSelectionMode()) {
      this.showToast(resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_035')));
      return;
    }
    this.isSelectionMode = true;
    this.selectedGuids = [];
    if (initialGuid !== undefined && initialGuid.length > 0) {
      this.setRowSelected(initialGuid, true);
    }
  }

  private exitSelectionMode(): void {
    this.isSelectionMode = false;
    this.selectedGuids = [];
  }

  private canEnterSelectionMode(): boolean {
    return this.collectSelectableRows().length > 0;
  }

  private collectSelectableRows(): DownloadSelectionCandidate[] {
    const candidates: DownloadSelectionCandidate[] = [];
    this.downloadListState.groups.forEach((group: DownloadManagementGroupState) => {
      group.rows.forEach((row: DownloadManagementRowState) => {
        candidates.push({
          guid: row.guid,
          status: row.status
        });
      });
    });
    return candidates;
  }

  private isRowSelected(guid: string): boolean {
    return this.selectedGuids.indexOf(guid) >= 0;
  }

  private setRowSelected(guid: string, isSelected: boolean): void {
    const row = this.findVisibleRowByGuid(guid);
    if (row === undefined || !canSelectDownloadTask(row.status)) {
      this.selectedGuids = this.selectedGuids.filter((selectedGuid: string) => selectedGuid !== guid);
      return;
    }
    const selected = this.selectedGuids.slice();
    const index = selected.indexOf(guid);
    if (isSelected && index < 0) {
      selected.push(guid);
    } else if (!isSelected && index >= 0) {
      selected.splice(index, 1);
    }
    this.selectedGuids = selected;
  }

  private toggleRowSelection(guid: string): void {
    this.setRowSelected(guid, !this.isRowSelected(guid));
  }

  private selectAllVisibleRows(): void {
    this.selectedGuids = collectSelectableDownloadGuids(this.collectSelectableRows());
  }

  private pruneSelectionToVisibleRows(): void {
    if (this.selectedGuids.length === 0) {
      return;
    }
    const selectableRows = this.collectSelectableRows();
    this.selectedGuids = pruneDownloadSelection(
      this.selectedGuids,
      collectSelectableDownloadGuids(selectableRows)
    );
    if (this.isSelectionMode && selectableRows.length === 0) {
      this.exitSelectionMode();
    }
  }

  private confirmDeleteSelectedRows(): void {
    if (this.selectedGuids.length === 0) {
      this.showToast(downloadSelectionEmptyToast());
      return;
    }
    const selectedCount = this.selectedGuids.length;
    showCenteredAlertDialog({
      title: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_014')),
      message: resolveAppResourceText($r('app.string.download_delete_selected_message', selectedCount)),
      autoCancel: true,
      buttonDirection: DialogButtonDirection.VERTICAL,
      buttons: [
        {
          value: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_013')),
          action: (): void => {
            this.deleteSelectedRows('records_only');
          }
        },
        {
          value: resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_015')),
          fontColor: $r('app.color.permission_blocked'),
          action: (): void => {
            this.deleteSelectedRows('records_and_files');
          }
        },
        {
          value: resolveAppResourceText($r('app.string.settings_account_cancel')),
          action: (): void => {
          }
        }
      ]
    });
  }

  private deleteSelectedRows(scope: BatchDownloadDeleteScope): void {
    const deletingGuids = this.selectedGuids.slice();
    if (deletingGuids.length === 0) {
      return;
    }
    this.hideTasksLocally(deletingGuids);
    this.exitSelectionMode();
    this.refreshState();
    if (scope === 'records_and_files') {
      void this.deleteSelectedRowsAndFiles(deletingGuids);
      return;
    }
    const boundary = this.getCurrentDownloadBoundary();
    let removedCount = 0;
    deletingGuids.forEach((guid: string) => {
      if (sharedDownloadRuntimeService.removeTaskRecordForBoundary(guid, boundary)) {
        removedCount += 1;
      }
    });
    this.showToast(removedCount > 0
      ? resolveAppResourceText($r('app.string.download_deleted_records', removedCount))
      : resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_031')));
    this.refreshState();
  }

  private async deleteSelectedRowsAndFiles(deletingGuids: string[]): Promise<void> {
    const boundary = this.getCurrentDownloadBoundary();
    let removedCount = 0;
    for (let index = 0; index < deletingGuids.length; index += 1) {
      const result = await sharedDownloadRuntimeService.deleteCompletedFileAndRemoveRecordForBoundary(
        deletingGuids[index],
        boundary
      );
      if (result.recordRemoved) {
        removedCount += 1;
      }
    }
    this.showToast(removedCount > 0
      ? resolveAppResourceText($r('app.string.download_deleted_items', removedCount))
      : resolveAppResourceText($r('app.string.browser_ui_browser_download_management_screen_023')));
    this.refreshState();
  }

  private runAfterContextMenuDismiss(action: () => void): void {
    setTimeout(action, DOWNLOAD_CONTEXT_MENU_DISMISS_DELAY_MS);
  }

  private syncSelectedGroupFromIndex(index: number): void {
    const groups = this.getAvailableGroups();
    if (index < 0 || index >= groups.length) {
      return;
    }
    const nextGroup = groups[index].group;
    if (nextGroup === this.selectedGroup) {
      return;
    }
    this.markInteractionQuiet();
    this.hasResolvedInitialContentGroup = true;
    this.selectedGroup = nextGroup;
    this.logDownloadManagementLifecycle(`swipe_group:${nextGroup}`);
    this.scheduleDeferredRefresh();
  }

  private syncSwiperToSelectedGroup(withAnimation: boolean): void {
    const index = this.resolveSelectedGroupIndex();
    if (withAnimation) {
      this.groupSwiperController.changeIndex(index);
      return;
    }
    this.groupSwiperController.changeIndex(index, false);
  }

}
