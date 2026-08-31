import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserDownloadAutoClearPolicy,
  BrowserHlsSegmentConcurrency,
  BrowserDownloadLocation,
  BrowserPrivateDownloadFilePolicy,
  BrowserPrivateDownloadRecordPolicy,
  BrowserDownloadSettings,
  DEFAULT_BROWSER_PROFILE_ID,
  normalizeBrowserDataScope,
  normalizeBrowserSessionPrivacyMode
} from '../../../common/models/BrowserModels';
import {
  BrowserPrivateBoundaryRouteParams,
  BrowserPrivateBoundaryNavigationService
} from '../../../core/browser/BrowserPrivateBoundaryNavigationService';
import {
  DownloadSettingsOptionView,
  DownloadSettingsSectionState,
  DownloadSettingsViewModel
} from '../../../core/download/DownloadSettingsViewModel';
import { DownloadSettingsScreenController } from '../../../core/download/DownloadSettingsScreenController';
import { DownloadTaskBoundary } from '../../../domain/download/DownloadTypes';
import { sharedDownloadPolicyService } from '../../bootstrap/BrowserAppRuntime';
import { DEFAULT_BROWSER_DOWNLOAD_SETTINGS } from '../../../data/preferences/PreferencesRepository';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import {
  SettingsNavigationRow,
  SettingsOptionRow,
  SettingsStaticValueRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import { SettingsHdsScaffold } from '../settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsFooterText,
  SettingsPresentationScrollBody,
  SettingsScrollBody,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../settings/SettingsTargetReveal';

export type BrowserDownloadSettingsSubpage =
  'main' |
  'hls_concurrency' |
  'auto_clear' |
  'private_file' |
  'private_record';

const DOWNLOAD_SETTINGS_MAIN_DESTINATION: BrowserDownloadSettingsSubpage = 'main';
const DOWNLOAD_SETTINGS_DOMAIN = 0x0000;
const DOWNLOAD_SETTINGS_TAG = 'DownloadSettings';
type DownloadSettingsRowPosition = 'single' | 'first' | 'middle' | 'last';

function buildDownloadSettingsBoundary(
  routeParams: BrowserPrivateBoundaryRouteParams | undefined
): DownloadTaskBoundary {
  const privacyMode = normalizeBrowserSessionPrivacyMode(routeParams?.privacyMode);
  return {
    windowId: BrowserWindowRuntime.getActiveWindowId(),
    profileId: DEFAULT_BROWSER_PROFILE_ID,
    privacyMode: privacyMode,
    dataScope: normalizeBrowserDataScope(routeParams?.dataScope, privacyMode)
  };
}

function readDownloadSettings(boundary: DownloadTaskBoundary): BrowserDownloadSettings {
  return sharedDownloadPolicyService.readSettings(boundary);
}

@Component
export struct BrowserDownloadSettingsScreen {
  private settingsScroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: DownloadSettingsScreenController;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop boundary: DownloadTaskBoundary | undefined = undefined;
  @Prop revealTargetId: string = '';
  @Prop revealRevision: number = 0;
  private downloadSettingsViewModel: DownloadSettingsViewModel = new DownloadSettingsViewModel();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();

  @State isSessionEphemeral: boolean = false;
  @State viewState: DownloadSettingsSectionState =
    new DownloadSettingsViewModel().buildState(DEFAULT_BROWSER_DOWNLOAD_SETTINGS);
  @State askBeforeDownload: boolean = DEFAULT_BROWSER_DOWNLOAD_SETTINGS.askBeforeDownload;
  @State allowCellularDownloads: boolean =
    DEFAULT_BROWSER_DOWNLOAD_SETTINGS.allowCellularDownloads;
  @State autoResumeAfterRestart: boolean =
    DEFAULT_BROWSER_DOWNLOAD_SETTINGS.autoResumeAfterRestart;
  @State autoClearPolicy: BrowserDownloadAutoClearPolicy =
    DEFAULT_BROWSER_DOWNLOAD_SETTINGS.autoClearPolicy;
  @State privateFilePolicy: BrowserPrivateDownloadFilePolicy =
    DEFAULT_BROWSER_DOWNLOAD_SETTINGS.privateFilePolicy;
  @State privateRecordPolicy: BrowserPrivateDownloadRecordPolicy =
    DEFAULT_BROWSER_DOWNLOAD_SETTINGS.privateRecordPolicy;
  @State settingsReady: boolean = false;
  private settingsBoundary: DownloadTaskBoundary = buildDownloadSettingsBoundary(undefined);

  aboutToAppear(): void {
    this.settingsReady = false;
    try {
      const routeParams: BrowserPrivateBoundaryRouteParams | undefined = this.boundary !== undefined
        ? {
          dataScope: this.boundary.dataScope,
          privacyMode: this.boundary.privacyMode,
          boundarySource: 'download_management'
        }
        : router.getParams() as BrowserPrivateBoundaryRouteParams | undefined;
      this.settingsBoundary = this.boundary ?? buildDownloadSettingsBoundary(routeParams);
      this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(routeParams);
      this.applySettingsState(readDownloadSettings(this.settingsBoundary));
      this.settingsReady = true;
      this.controller?.setBackHandler((): boolean => {
        return false;
      });
    } catch (error) {
      hilog.error(
        DOWNLOAD_SETTINGS_DOMAIN,
        DOWNLOAD_SETTINGS_TAG,
        'settings screen aboutToAppear failed: %{public}s',
        this.stringifyError(error)
      );
    }
  }

  aboutToDisappear(): void {
    this.controller?.setBackHandler(undefined);
  }

  build() {
    SettingsHdsScaffold({
      title: this.resolveHeaderTitle(DOWNLOAD_SETTINGS_MAIN_DESTINATION),
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: this.isSessionEphemeral,
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      onBack: () => {
        this.handleBack(DOWNLOAD_SETTINGS_MAIN_DESTINATION);
      }
    }) {
      Column() {
        if (this.settingsReady) {
          SettingsScrollBody({
            topPadding: 16,
            bottomPadding: 22,
            scroller: this.settingsScroller
          }) {
            BrowserDownloadSettingsContent({
              viewState: this.viewState,
              askBeforeDownload: this.askBeforeDownload,
              allowCellularDownloads: this.allowCellularDownloads,
              autoResumeAfterRestart: this.autoResumeAfterRestart,
              autoClearPolicy: this.autoClearPolicy,
              privateFilePolicy: this.privateFilePolicy,
              privateRecordPolicy: this.privateRecordPolicy,
              dividerColor: this.storedDividerColor,
              surfaceBackground: this.storedSurfaceBackgroundColor,
              primaryTextColor: this.storedPrimaryTextColor,
              secondaryTextColor: this.storedSecondaryTextColor,
              accentColor: this.storedAccentColor,
              revealTargetId: this.revealTargetId,
              revealRevision: this.revealRevision,
              scroller: this.settingsScroller,
              onAskBeforeDownloadChange: (value: boolean) => {
                this.updateAskBeforeDownload(value);
              },
              onAllowCellularDownloadsChange: (value: boolean) => {
                this.updateAllowCellularDownloads(value);
              },
              onAutoResumeAfterRestartChange: (value: boolean) => {
                this.updateAutoResumeAfterRestart(value);
              },
              onOpenSubpage: (subpage: BrowserDownloadSettingsSubpage) => {
                this.openSubpage(subpage);
              }
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.storedPageBackgroundColor)
    }
  }

  private resolveHeaderTitle(subpage: BrowserDownloadSettingsSubpage): string {
    switch (subpage) {
      case 'hls_concurrency':
        return 'HLS 分片并发数';
      case 'auto_clear':
        return '自动清理';
      case 'private_file':
        return '私密下载文件';
      case 'private_record':
        return '私密下载记录';
      default:
        return '下载设置';
    }
  }

  private handleBack(subpage: BrowserDownloadSettingsSubpage = DOWNLOAD_SETTINGS_MAIN_DESTINATION): void {
    if (subpage !== DOWNLOAD_SETTINGS_MAIN_DESTINATION) {
      this.navigationCoordinator.back();
      return;
    }
    this.navigationCoordinator.back();
  }

  private openSubpage(subpage: BrowserDownloadSettingsSubpage): void {
    this.navigationCoordinator.openDownloadSettingsOption(subpage, this.buildBoundaryState());
  }

  private buildBoundaryState(): BrowserBoundaryRouteState {
    return {
      dataScope: this.settingsBoundary.dataScope,
      privacyMode: this.settingsBoundary.privacyMode,
      boundarySource: 'download_settings'
    };
  }

  private updateAskBeforeDownload(enabled: boolean): void {
    this.askBeforeDownload = enabled;
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { askBeforeDownload: enabled }
    );
    this.saveDownloadSettings(nextSettings, '下载前询问设置保存失败');
  }

  private updateAutoResumeAfterRestart(enabled: boolean): void {
    this.autoResumeAfterRestart = enabled;
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { autoResumeAfterRestart: enabled }
    );
    this.saveDownloadSettings(nextSettings, '启动后恢复设置保存失败');
  }

  private updateAllowCellularDownloads(enabled: boolean): void {
    this.allowCellularDownloads = enabled;
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { allowCellularDownloads: enabled }
    );
    this.saveDownloadSettings(nextSettings, '移动数据下载设置保存失败');
  }



  private saveDownloadSettings(settings: BrowserDownloadSettings, failurePrefix: string): void {
    const previousSettings = readDownloadSettings(this.settingsBoundary);
    this.viewState = this.downloadSettingsViewModel.buildState(settings);
    this.askBeforeDownload = settings.askBeforeDownload;
    this.allowCellularDownloads = settings.allowCellularDownloads;
    this.autoResumeAfterRestart = settings.autoResumeAfterRestart;
    this.autoClearPolicy = settings.autoClearPolicy;
    this.privateFilePolicy = settings.privateFilePolicy;
    this.privateRecordPolicy = settings.privateRecordPolicy;
    sharedDownloadPolicyService.updateSettings(
      this.settingsBoundary,
      settings
    ).catch((error: Error) => {
      this.viewState = this.downloadSettingsViewModel.buildState(previousSettings);
      this.askBeforeDownload = previousSettings.askBeforeDownload;
      this.allowCellularDownloads = previousSettings.allowCellularDownloads;
      this.autoResumeAfterRestart = previousSettings.autoResumeAfterRestart;
      this.autoClearPolicy = previousSettings.autoClearPolicy;
      this.privateFilePolicy = previousSettings.privateFilePolicy;
      this.privateRecordPolicy = previousSettings.privateRecordPolicy;
      hilog.error(
        DOWNLOAD_SETTINGS_DOMAIN,
        DOWNLOAD_SETTINGS_TAG,
        '%{public}s: %{public}s',
        failurePrefix,
        this.stringifyError(error)
      );
    });
  }



  private stringifyError(error: Error | Object | string): string {
    if (error instanceof Error) {
      return `${error.name}: ${error.message}`;
    }
    if (typeof error === 'string') {
      return error;
    }
    return JSON.stringify(error);
  }

  private applySettingsState(settings: BrowserDownloadSettings): void {
    this.viewState = this.downloadSettingsViewModel.buildState(settings);
    this.askBeforeDownload = settings.askBeforeDownload;
    this.allowCellularDownloads = settings.allowCellularDownloads;
    this.autoResumeAfterRestart = settings.autoResumeAfterRestart;
    this.autoClearPolicy = settings.autoClearPolicy;
    this.privateFilePolicy = settings.privateFilePolicy;
    this.privateRecordPolicy = settings.privateRecordPolicy;
  }
}

@Component
export struct BrowserDownloadSettingsContent {
  private downloadSettingsViewModel: DownloadSettingsViewModel = new DownloadSettingsViewModel();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop viewState: DownloadSettingsSectionState =
    new DownloadSettingsViewModel().buildState(DEFAULT_BROWSER_DOWNLOAD_SETTINGS);
  @Prop askBeforeDownload: boolean = false;
  @Prop allowCellularDownloads: boolean = true;
  @Prop autoResumeAfterRestart: boolean = true;
  @Prop autoClearPolicy: BrowserDownloadAutoClearPolicy = 'manual';
  @Prop privateFilePolicy: BrowserPrivateDownloadFilePolicy = 'prompt_for_location';
  @Prop privateRecordPolicy: BrowserPrivateDownloadRecordPolicy = 'keep_until_window_close';
  @Prop dividerColor: ResourceColor | undefined = undefined;
  @Prop surfaceBackground: ResourceColor | undefined = undefined;
  @Prop primaryTextColor: ResourceColor | undefined = undefined;
  @Prop secondaryTextColor: ResourceColor | undefined = undefined;
  @Prop accentColor: ResourceColor = '';
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('handleRevealRequest') revealTargetId: string = '';
  @Prop @Watch('handleRevealRequest') revealRevision: number = 0;
  scroller?: Scroller;
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );
  onAskBeforeDownloadChange: (value: boolean) => void = (_value: boolean) => {};
  onAllowCellularDownloadsChange: (value: boolean) => void = (_value: boolean) => {};
  onAutoResumeAfterRestartChange: (value: boolean) => void = (_value: boolean) => {};
  onOpenSubpage: (subpage: BrowserDownloadSettingsSubpage) => void = (_subpage: BrowserDownloadSettingsSubpage) => {};

  aboutToAppear(): void {
    this.revealController.bindScroller(this.scroller);
    this.handleRevealRequest();
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    Column({ space: 16 }) {
      this.buildDownloadLocationSection()
      this.buildDownloadConfirmationSection()
      this.buildDownloadNetworkSection()
      this.buildVideoDownloadSection()
      this.buildDownloadResumeSection()
      this.buildDownloadCleanupSection()
      this.buildPrivateDownloadSettingsSection()
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.revealController.rememberContentArea(newArea);
    })
  }

  @Builder
  private buildDownloadLocationSection() {
    SettingsSection({ title: '保存位置' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildDownloadLocationRow()
      }
    }
  }

  @Builder
  private buildDownloadConfirmationSection() {
    SettingsSection({ title: '下载确认' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildAskBeforeDownloadRow()
      }
      SettingsFooterText({
        text: '关闭后，网页触发的下载会直接开始。',
        secondaryTextColor: this.resolveSecondaryTextColor()
      })
    }
  }

  @Builder
  private buildDownloadNetworkSection() {
    SettingsSection({ title: '网络' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildAllowCellularDownloadsRow()
      }
      SettingsFooterText({
        text: this.allowCellularDownloads
          ? '当前允许使用 WLAN 或移动数据下载。'
          : '关闭后，移动数据网络下的任务会等待 WLAN。',
        secondaryTextColor: this.resolveSecondaryTextColor()
      })
    }
  }

  @Builder
  private buildDownloadResumeSection() {
    SettingsSection({ title: '下载恢复' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildAutoResumeAfterRestartRow()
      }
      SettingsFooterText({
        text: '关闭后，重启 Aira 不会自动继续未完成下载。',
        secondaryTextColor: this.resolveSecondaryTextColor()
      })
    }
  }

  @Builder
  private buildVideoDownloadSection() {
    SettingsSection({ title: '分片下载' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildHlsSegmentConcurrencyRow()
      }
      SettingsFooterText({
        text: '仅用于新开始或重试的 M3U8/HLS 分片资源。普通文件下载不受影响。并发越高，资源占用越高。',
        secondaryTextColor: this.resolveSecondaryTextColor()
      })
    }
  }

  @Builder
  private buildDownloadCleanupSection() {
    SettingsSection({ title: '记录清理' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildAutoClearRow()
      }
    }
  }

  @Builder
  private buildPrivateDownloadSettingsSection() {
    SettingsSection({ title: '私密下载' }) {
      SettingsGroupCard({
        surfaceColor: this.resolveSurfaceBackground(),
        desktopPresentation: this.desktopPresentation
      }) {
        this.buildPrivateFilePolicyRow()
        SettingsGroupDivider({ dividerColor: this.resolveDividerColor() })
        this.buildPrivateRecordPolicyRow()
      }
    }
  }

  @Builder
  private buildDownloadLocationRow() {
    SettingsTargetRevealRegion({
      targetId: 'download_location',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsStaticValueRow({
        title: '下载位置',
        desktopPresentation: this.desktopPresentation,
        value: this.viewState.defaultLocationLabel,
        rowPosition: 'single'
      })
    }
  }

  @Builder
  private buildAskBeforeDownloadRow() {
    SettingsTargetRevealRegion({
      targetId: 'ask_before_download',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsSwitchRow({
        title: '下载前询问',
        desktopPresentation: this.desktopPresentation,
        checked: this.askBeforeDownload,
        rowPosition: 'single',
        onChange: (value: boolean): void => {
          this.onAskBeforeDownloadChange(value);
        }
      })
    }
  }

  @Builder
  private buildAllowCellularDownloadsRow() {
    SettingsTargetRevealRegion({
      targetId: 'allow_cellular_downloads',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsSwitchRow({
        title: '允许使用移动数据',
        desktopPresentation: this.desktopPresentation,
        checked: this.allowCellularDownloads,
        rowPosition: 'single',
        onChange: (value: boolean): void => {
          this.onAllowCellularDownloadsChange(value);
        }
      })
    }
  }

  @Builder
  private buildAutoResumeAfterRestartRow() {
    SettingsTargetRevealRegion({
      targetId: 'auto_resume_downloads',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsSwitchRow({
        title: '启动后自动恢复',
        desktopPresentation: this.desktopPresentation,
        checked: this.autoResumeAfterRestart,
        rowPosition: 'single',
        onChange: (value: boolean): void => {
          this.onAutoResumeAfterRestartChange(value);
        }
      })
    }
  }

  @Builder
  private buildHlsSegmentConcurrencyRow() {
    SettingsTargetRevealRegion({
      targetId: 'hls_segment_concurrency',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsNavigationRow({
        title: 'HLS 分片并发数',
        desktopPresentation: this.desktopPresentation,
        value: this.resolveSelectedOptionLabel(
          this.viewState.hlsSegmentConcurrencyOptions,
          this.viewState.hlsSegmentConcurrency
        ),
        rowPosition: 'single',
        onAction: (): void => {
          this.onOpenSubpage('hls_concurrency');
        }
      })
    }
  }

  @Builder
  private buildAutoClearRow() {
    SettingsTargetRevealRegion({
      targetId: 'download_auto_clear',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsNavigationRow({
        title: '自动清理',
        desktopPresentation: this.desktopPresentation,
        value: this.resolveSelectedOptionLabel(this.viewState.autoClearOptions, this.autoClearPolicy),
        rowPosition: 'single',
        onAction: (): void => {
          this.onOpenSubpage('auto_clear');
        }
      })
    }
  }

  @Builder
  private buildPrivateFilePolicyRow() {
    SettingsTargetRevealRegion({
      targetId: 'private_download_file',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsNavigationRow({
        title: '私密下载文件',
        desktopPresentation: this.desktopPresentation,
        value: this.resolveSelectedOptionLabel(this.viewState.privateFileOptions, this.privateFilePolicy),
        rowPosition: this.resolveMainRowPosition(0, 2),
        onAction: (): void => {
          this.onOpenSubpage('private_file');
        }
      })
    }
  }

  @Builder
  private buildPrivateRecordPolicyRow() {
    SettingsTargetRevealRegion({
      targetId: 'private_download_record',
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.accentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsNavigationRow({
        title: '私密下载记录',
        desktopPresentation: this.desktopPresentation,
        value: this.resolveSelectedOptionLabel(this.viewState.privateRecordOptions, this.privateRecordPolicy),
        rowPosition: this.resolveMainRowPosition(1, 2),
        onAction: (): void => {
          this.onOpenSubpage('private_record');
        }
      })
    }
  }

  private handleRevealRequest(): void {
    this.revealController.request(this.revealTargetId, this.revealRevision);
  }

  private resolveDividerColor(): ResourceColor {
    return this.dividerColor === undefined ? this.storedDividerColor : this.dividerColor;
  }

  private resolveSurfaceBackground(): ResourceColor {
    return this.surfaceBackground === undefined ? this.storedSurfaceBackgroundColor : this.surfaceBackground;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }

  private resolveMainRowPosition(index: number, total: number): DownloadSettingsRowPosition {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }

  private resolveSelectedOptionLabel<T>(options: DownloadSettingsOptionView<T>[], value: T): string {
    const matched = options.find((option: DownloadSettingsOptionView<T>) => option.value === value);
    return matched?.label ?? `${value}`;
  }
}

@Component
export struct BrowserDownloadSettingsOptionScreen {
  @Prop desktopPresentation: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private privateBoundaryNavigationService: BrowserPrivateBoundaryNavigationService =
    new BrowserPrivateBoundaryNavigationService();
  subpage: BrowserDownloadSettingsSubpage = 'auto_clear';
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  onBack?: () => void;
  onSettingsChanged?: () => void;
  @State isSessionEphemeral: boolean = false;

  private downloadSettingsViewModel: DownloadSettingsViewModel = new DownloadSettingsViewModel();

  @State downloadSettingsState: DownloadSettingsSectionState =
    this.downloadSettingsViewModel.buildState(DEFAULT_BROWSER_DOWNLOAD_SETTINGS);
  @State isSelectingOption: boolean = false;
  @State isLeaving: boolean = false;
  @State settingsReady: boolean = false;
  private settingsBoundary: DownloadTaskBoundary = buildDownloadSettingsBoundary(undefined);

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.isLeaving = false;
    this.settingsReady = false;
    const routeParams = router.getParams() as BrowserPrivateBoundaryRouteParams | undefined;
    this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(routeParams);
    this.settingsBoundary = buildDownloadSettingsBoundary(routeParams);
    this.refreshState();
  }

  build() {
    SettingsHdsScaffold({
      title: this.resolveHeaderTitle(),
      backIconKind: 'back',
      pageBackground: this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: this.isSessionEphemeral,
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.desktopPresentation,
      onBack: () => {
        this.handleBack();
      }
    }) {
      if (this.settingsReady) {
        this.buildOptionSubpage()
      }
    }
  }

  @Builder
  private buildOptionSubpage() {
    SettingsPresentationScrollBody({
      desktopPresentation: this.desktopPresentation,
      topPadding: 16,
      bottomPadding: 22
    }) {
      SettingsGroupCard({
        surfaceColor: this.storedSurfaceBackgroundColor,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.resolveOptions(), (option: DownloadSettingsOptionView<string>, index: number) => {
          this.buildOptionRow(option, index, this.resolveOptions().length)
          if (index < this.resolveOptions().length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: DownloadSettingsOptionView<string>) => option.value)
      }
    }
  }

  @Builder
  private buildOptionRow(option: DownloadSettingsOptionView<string>, index: number, total: number) {
    SettingsOptionRow({
      title: option.label,
      desktopPresentation: this.desktopPresentation,
      helperText: option.helperText,
      rowPosition: this.resolveOptionRowPosition(index, total),
      isSelected: this.isOptionSelected(option.value),
      isEnabled: this.isOptionRowEnabled(),
      onAction: (): void => {
        this.requestSelectOption(option.value);
      }
    })
  }

  private refreshState(): void {
    const settings = readDownloadSettings(this.settingsBoundary);
    this.downloadSettingsState = this.downloadSettingsViewModel.buildState(settings);
    this.settingsReady = true;
  }

  private resolveHeaderTitle(): string {
    switch (this.subpage) {
      case 'hls_concurrency':
        return 'HLS 分片并发数';
      case 'auto_clear':
        return '自动清理';
      case 'private_file':
        return '私密下载文件';
      case 'private_record':
        return '私密下载记录';
      default:
        return '下载设置';
    }
  }

  private resolveOptions(): DownloadSettingsOptionView<string>[] {
    switch (this.subpage) {
      case 'hls_concurrency':
        return this.downloadSettingsState.hlsSegmentConcurrencyOptions as DownloadSettingsOptionView<string>[];
      case 'auto_clear':
        return this.downloadSettingsState.autoClearOptions as DownloadSettingsOptionView<string>[];
      case 'private_file':
        return this.downloadSettingsState.privateFileOptions as DownloadSettingsOptionView<string>[];
      case 'private_record':
        return this.downloadSettingsState.privateRecordOptions as DownloadSettingsOptionView<string>[];
      default:
        return [];
    }
  }

  private isOptionSelected(value: string): boolean {
    switch (this.subpage) {
      case 'hls_concurrency':
        return this.downloadSettingsState.hlsSegmentConcurrency === value;
      case 'auto_clear':
        return this.downloadSettingsState.autoClearPolicy === value;
      case 'private_file':
        return this.downloadSettingsState.privateFilePolicy === value;
      case 'private_record':
        return this.downloadSettingsState.privateRecordPolicy === value;
      default:
        return false;
    }
  }

  private resolveOptionRowPosition(index: number, total: number): DownloadSettingsRowPosition {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }

  private isOptionRowEnabled(): boolean {
    return !this.isSelectingOption && !this.isLeaving;
  }

  private requestSelectOption(value: string): void {
    if (this.isSelectingOption || this.isLeaving) {
      return;
    }
    this.isSelectingOption = true;
    this.selectOption(value);
  }

  private selectOption(value: string): void {
    switch (this.subpage) {
      case 'hls_concurrency':
        this.updateHlsSegmentConcurrency(value as BrowserHlsSegmentConcurrency);
        return;
      case 'auto_clear':
        this.updateAutoClearPolicy(value as BrowserDownloadAutoClearPolicy);
        return;
      case 'private_file':
        this.updatePrivateFilePolicy(value as BrowserPrivateDownloadFilePolicy);
        return;
      case 'private_record':
        this.updatePrivateRecordPolicy(value as BrowserPrivateDownloadRecordPolicy);
        return;
      default:
        return;
    }
  }

  private updateAutoClearPolicy(policy: BrowserDownloadAutoClearPolicy): void {
    if (this.downloadSettingsState.autoClearPolicy === policy) {
      this.handleBack();
      return;
    }
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { autoClearPolicy: policy }
    );
    this.saveDownloadSettings(nextSettings, '下载自动清理策略保存失败');
  }

  private updateHlsSegmentConcurrency(concurrency: BrowserHlsSegmentConcurrency): void {
    if (this.downloadSettingsState.hlsSegmentConcurrency === concurrency) {
      this.handleBack();
      return;
    }
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { hlsSegmentConcurrency: concurrency }
    );
    this.saveDownloadSettings(nextSettings, 'HLS 分片并发数保存失败');
  }



  private updatePrivateFilePolicy(policy: BrowserPrivateDownloadFilePolicy): void {
    if (this.downloadSettingsState.privateFilePolicy === policy) {
      this.handleBack();
      return;
    }
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { privateFilePolicy: policy }
    );
    this.saveDownloadSettings(nextSettings, '私密下载文件设置保存失败');
  }

  private updatePrivateRecordPolicy(policy: BrowserPrivateDownloadRecordPolicy): void {
    if (this.downloadSettingsState.privateRecordPolicy === policy) {
      this.handleBack();
      return;
    }
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(
      readDownloadSettings(this.settingsBoundary),
      { privateRecordPolicy: policy }
    );
    this.saveDownloadSettings(nextSettings, '私密下载记录设置保存失败');
  }

  private saveDownloadSettings(settings: BrowserDownloadSettings, failurePrefix: string): void {
    sharedDownloadPolicyService.updateSettings(
      this.settingsBoundary,
      settings
    ).then(() => {
      this.refreshState();
      this.onSettingsChanged?.();
      this.handleBack();
    }).catch((error: Error) => {
      this.isSelectingOption = false;
      hilog.error(
        DOWNLOAD_SETTINGS_DOMAIN,
        DOWNLOAD_SETTINGS_TAG,
        '%{public}s: %{public}s',
        failurePrefix,
        this.stringifyError(error)
      );
    });
  }



  private handleBack(): boolean {
    if (this.isLeaving) {
      return true;
    }
    this.isLeaving = true;
    this.onBack?.();
    return true;
  }

  private stringifyError(error: Error | Object | string): string {
    if (error instanceof Error) {
      return `${error.name}: ${error.message}`;
    }
    if (typeof error === 'string') {
      return error;
    }
    return JSON.stringify(error);
  }
}
