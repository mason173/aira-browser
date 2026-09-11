import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import router from '@ohos.router';
import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
import { BrowserDownloadSettingsScreen } from './BrowserDownloadSettingsScreen';
import {
  BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP
} from '../../../core/browser/BrowserModalPresentationTokens';
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
import { AppWindowModalLayoutService } from '../../../services/layout/AppWindowModalLayoutService';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';

interface HiddenDownloadTaskSnapshot {
  guid: string;
  group: DownloadQueryGroup;
}

interface OptimisticControlSnapshot {
  targetStatus: DownloadV2Status;
  expiresAt: number;
}

type CompletedDownloadDeleteMode = 'task_only' | 'task_and_file';

const DOWNLOAD_MANAGEMENT_REFRESH_INTERVAL_MS: number = 1500;
const DOWNLOAD_MANAGEMENT_DOMAIN = 0x0000;
const DOWNLOAD_MANAGEMENT_TAG = 'DownloadManagement';
const DOWNLOAD_OPTIMISTIC_CONTROL_GRACE_MS: number = 2200;
const DOWNLOAD_MANAGEMENT_INTERACTION_QUIET_MS: number = 700;
const DOWNLOAD_MANAGEMENT_PROGRESS_BROADCAST_PAUSE_OWNER = 'download_management_interaction';
const LARGE_SCREEN_DOWNLOAD_FILTER_ITEM_WIDTH_VP: number = 112;
const LARGE_SCREEN_DOWNLOAD_SETTINGS_BUTTON_HEIGHT_VP: number = 34;
const LARGE_SCREEN_DOWNLOAD_SETTINGS_POPUP_WIDTH_VP: number = 440;
const LARGE_SCREEN_DOWNLOAD_SETTINGS_POPUP_HEIGHT_VP: number = 600;
const LARGE_SCREEN_DOWNLOAD_SETTINGS_POPUP_RESERVED_TOP_VP: number = 112;
const DOWNLOAD_IMMERSIVE_TITLE_TOP_INSET: number = 8;
const DOWNLOAD_IMMERSIVE_TITLE_HEIGHT: number = 40;
const DOWNLOAD_IMMERSIVE_TITLE_TO_FILTER_GAP: number = 12;
const DOWNLOAD_FILTER_LAYOUT_HEIGHT: number = 54;
const DOWNLOAD_FILTER_TO_CONTENT_GAP: number = 4;
const DOWNLOAD_EMBEDDED_FILTER_TOP_INSET: number = 8;
const DOWNLOAD_IMMERSIVE_TITLE_TO_CONTENT_GAP: number = 16;
const DOWNLOAD_IMMERSIVE_TOP_BLUR_RADIUS: number = 20;

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
  @State statusText: string = '';
  @State cancelConfirmGuid: string = '';
  @State cancelConfirmFileName: string = '';
  @State completedDeleteConfirmGuid: string = '';
  @State completedDeleteConfirmFileName: string = '';
  @State completedDeleteConfirmMode: CompletedDownloadDeleteMode = 'task_only';
  @State locallyHiddenTasks: HiddenDownloadTaskSnapshot[] = [];
  @State private downloadSettingsPopupVisible: boolean = false;
  @State private viewportWidthVp: number = 0;
  @State private viewportHeightVp: number = 0;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  private groupSwiperController: SwiperController = new SwiperController();
  private optimisticControlByGuid: Map<string, OptimisticControlSnapshot> = new Map();
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();

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
      this.statusText = '下载列表加载失败';
      hilog.error(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'aboutToAppear failed: %{public}s',
        this.stringifyError(error)
      );
    }
  }

  aboutToDisappear(): void {
    this.logDownloadManagementLifecycle('about_to_disappear');
    this.stopAutoRefreshTimer();
    this.stopDeferredRefreshTimer();
    this.releaseProgressBroadcastPause();
    this.unbindDownloadUpdates();
  }

  build() {
    Column() {
      ManagementHdsScaffold({
        title: '下载',
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
    .expandSafeArea([SafeAreaType.SYSTEM, SafeAreaType.CUTOUT], this.resolveSystemSafeAreaEdges())
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateViewportSize(newArea);
    })
    .onAppear(() => {
      this.presentCancelDialogIfNeeded();
      this.presentCompletedDeleteDialogIfNeeded();
    })
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
    Button('下载设置', { type: ButtonType.Normal })
      .height(LARGE_SCREEN_DOWNLOAD_SETTINGS_BUTTON_HEIGHT_VP)
      .padding({ left: 16, right: 16 })
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedPrimaryTextColor)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .border({ width: 1, color: this.storedDividerColor })
      .borderRadius(LARGE_SCREEN_DOWNLOAD_SETTINGS_BUTTON_HEIGHT_VP / 2)
      .stateEffect(true)
      .accessibilityText('展开下载设置')
      .onClick((): void => {
        this.downloadSettingsPopupVisible = !this.downloadSettingsPopupVisible;
      })
      .bindPopup(this.downloadSettingsPopupVisible, {
        builder: this.buildLargeScreenDownloadSettingsPopup,
        placement: Placement.BottomRight,
        popupColor: this.storedPageBackgroundColor,
        enableArrow: false,
        autoCancel: true,
        mask: false,
        targetSpace: 8,
        width: this.resolveDownloadSettingsPopupWidth(),
        radius: BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP,
        shadow: {
          radius: 20,
          color: $r('app.color.elevation_shadow'),
          offsetX: 0,
          offsetY: 8
        },
        onStateChange: (event: PopupStateChangeParam): void => {
          this.downloadSettingsPopupVisible = event.isVisible;
        }
      })
  }

  @Builder
  private buildLargeScreenDownloadSettingsPopup() {
    Column() {
      BrowserDownloadSettingsScreen({
        showBackButton: false,
        showTitleBar: false,
        useTopSafeInset: false,
        boundary: this.getCurrentDownloadBoundary()
      })
    }
    .width(this.resolveDownloadSettingsPopupWidth())
    .height(this.resolveDownloadSettingsPopupHeight())
    .borderRadius(BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP)
    .clip(true)
  }

  private resolveDownloadSettingsPopupWidth(): number {
    return this.modalLayoutService.resolvePopupWidth(
      this.viewportWidthVp,
      LARGE_SCREEN_DOWNLOAD_SETTINGS_POPUP_WIDTH_VP
    );
  }

  private resolveDownloadSettingsPopupHeight(): number {
    return this.modalLayoutService.resolvePopupHeight(
      this.viewportHeightVp,
      LARGE_SCREEN_DOWNLOAD_SETTINGS_POPUP_HEIGHT_VP,
      LARGE_SCREEN_DOWNLOAD_SETTINGS_POPUP_RESERVED_TOP_VP
    );
  }

  private updateViewportSize(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.viewportWidthVp) {
      this.viewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.viewportHeightVp) {
      this.viewportHeightVp = height;
    }
  }

  private buildHeaderMenuActions(): ManagementHdsMenuAction[] {
    if (this.presentationMode === 'native_tab') {
      return [];
    }
    const actions: ManagementHdsMenuAction[] = [
      {
        label: '下载设置',
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
      Text('下载管理仅限当前私密会话')
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
      Text('下载管理入口来自私密会话；此页不会读取或展示常规浏览资料。')
        .width('100%')
        .fontSize(12)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
      Text('当前页只显示这个私密窗口里的下载任务；下载设置为设备范围。')
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
          onAction: (guid: string, action: DownloadManagementRowAction): void => {
            this.handleRowAction(guid, action);
          }
        })
      }, (row: DownloadManagementRowState) => row.guid)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildDownloadGroupPage(group: DownloadQueryGroup, centerEmptyStateInViewport: boolean) {
    Scroll() {
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
    .linearGradientBlur(this.presentationMode === 'native_tab' ? 0 : DOWNLOAD_IMMERSIVE_TOP_BLUR_RADIUS, {
      fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
      direction: GradientDirection.Bottom
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
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
      title: '没有下载内容',
      message: '开始下载后，这里会显示文件、进度和完成状态。'
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
      this.statusText = '下载列表加载失败';
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
        this.statusText = '下载列表加载失败';
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
      title: '取消下载？',
      message: `这会删除当前下载任务和已下载的临时文件。\n\n${this.cancelConfirmFileName}`,
      autoCancel: true,
      primaryButton: {
        value: '继续下载',
        action: () => {
          this.cancelConfirmGuid = '';
          this.cancelConfirmFileName = '';
        }
      },
      secondaryButton: {
        value: '确认取消',
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
    this.cancelConfirmFileName = item?.suggestedFileName ?? '当前下载';
    this.presentCancelDialogIfNeeded();
  }

  private async confirmCancelDownload(guid: string): Promise<void> {
    const boundary = this.getCurrentDownloadBoundary();
    this.hideTaskLocally(guid);
    const succeeded = await sharedDownloadRuntimeService.cancelAndRemoveTaskForBoundary(guid, boundary);
    if (!succeeded) {
      this.showTaskLocally(guid);
    }
    this.completeAsyncDownloadTaskAction(succeeded, '下载已取消并删除。', '当前下载暂时不能取消。');
  }

  private presentCompletedDeleteDialogIfNeeded(): void {
    if (this.completedDeleteConfirmGuid.length === 0) {
      return;
    }
    const deleteFile = this.completedDeleteConfirmMode === 'task_and_file';
    showCenteredAlertDialog({
      title: deleteFile ? '删除任务和文件？' : '仅删除下载任务？',
      message: deleteFile
        ? `下载任务会从 Aira 中删除，对应文件将移入系统回收站。\n\n${this.completedDeleteConfirmFileName}`
        : `只删除 Aira 中的下载任务，对应文件会保留。\n\n${this.completedDeleteConfirmFileName}`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
          this.clearCompletedDeleteConfirmation();
        }
      },
      secondaryButton: {
        value: deleteFile ? '删除任务和文件' : '仅删除任务',
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
    this.completedDeleteConfirmFileName = item?.suggestedFileName ?? '当前下载';
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
      '下载任务已删除，文件已保留。',
      '当前下载任务暂时不能删除。'
    );
  }

  private async confirmDeleteCompletedTaskAndFile(guid: string): Promise<void> {
    const boundary = this.getCurrentDownloadBoundary();
    this.hideTaskLocally(guid);
    const result = await sharedDownloadRuntimeService.deleteCompletedFileAndRemoveRecordForBoundary(guid, boundary);
    if (!result.recordRemoved) {
      this.showTaskLocally(guid);
      const failureText = result.fileStatus === 'not_found'
        ? '当前下载记录已发生变化，请刷新后重试。'
        : '文件删除失败，下载任务已保留。';
      this.showToast(failureText);
      this.completeAsyncDownloadTaskAction(false, '', failureText);
      return;
    }
    const successText = result.fileStatus === 'deleted'
      ? '下载任务已删除，文件已移入回收站。'
      : '文件已不存在，下载任务已删除。';
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
      this.statusText = `打开下载设置失败：${this.stringifyError(error)}`;
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
      this.completeControlAction(guid, succeeded, '下载已暂停。', '当前下载暂时不能暂停。');
      return;
    }
    if (action === 'resume') {
      const succeeded = await sharedDownloadRuntimeService.resumeTaskForBoundary(guid, boundary);
      this.completeControlAction(guid, succeeded, '下载已继续。', '当前下载暂时不能继续。');
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
      this.completeDownloadTaskAction(succeeded, '下载记录已移除。', '当前下载记录暂时不能移除。');
      return;
    }
    if (action === 'retry') {
      const succeeded = await sharedDownloadRuntimeService.retryTaskForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, '下载任务已重新开始。', '当前下载暂时不能重试。');
      return;
    }
    if (action === 'open_file') {
      const succeeded = await sharedDownloadRuntimeService.openFileForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, '正在打开下载文件。', '当前下载暂时不能打开。');
      return;
    }
    if (action === 'open_location') {
      const succeeded = await sharedDownloadRuntimeService.openLocationForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, '正在打开文件位置。', '当前下载暂时不能定位。');
      return;
    }
    if (action === 'save_to_system') {
      const succeeded = await sharedDownloadRuntimeService.saveTaskToSystemDownloadsForBoundary(guid, boundary);
      this.completeAsyncDownloadTaskAction(succeeded, '已保存到系统下载目录。', '当前下载暂时不能保存到系统下载目录。');
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
      this.showToast('当前没有可复制的下载链接。');
      this.completeDownloadTaskAction(false, '', '当前没有可复制的下载链接。');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, url);
      await pasteboard.getSystemPasteboard().setData(data);
      this.showToast('下载链接已复制。');
      this.completeDownloadTaskAction(true, '下载链接已复制。', '');
    } catch (error) {
      hilog.warn(
        DOWNLOAD_MANAGEMENT_DOMAIN,
        DOWNLOAD_MANAGEMENT_TAG,
        'copy download link failed guid=%{public}s error=%{public}s',
        guid,
        this.stringifyError(error)
      );
      this.showToast('复制失败，请稍后重试。');
      this.completeDownloadTaskAction(false, '', '复制失败，请稍后重试。');
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
