import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import {
  BrowserDownloadAutoClearPolicy,
  BrowserHlsSegmentConcurrency,
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
import { DownloadLocationDirectoryService } from '../../../services/download/DownloadLocationDirectoryService';
import { DEFAULT_BROWSER_DOWNLOAD_SETTINGS } from '../../../data/preferences/PreferencesRepository';
import { SettingsNavigationCoordinator } from '../../router/SettingsNavigationCoordinator';
import { BrowserBoundaryRouteState } from '../../../common/utils/RouteParamUtils';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import {
  SettingsNavigationRow,
  SettingsOptionRow,
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
  @Prop @Watch('reloadVisibleSettings') refreshRevision: number = 0;
  @Prop embeddedInDialog: boolean = false;
  onOpenEmbeddedSubpage?: (subpage: BrowserDownloadSettingsSubpage) => void;
  /** Lets an embedded host own the folder picker, since the picker cannot run over the dialog. */
  onFolderChangeRequested?: () => void = undefined;
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

  private reloadVisibleSettings(): void {
    if (!this.settingsReady) {
      return;
    }
    this.applySettingsState(readDownloadSettings(this.settingsBoundary));
  }

  build() {
    SettingsHdsScaffold({
      title: this.resolveHeaderTitle(DOWNLOAD_SETTINGS_MAIN_DESTINATION),
      backIconKind: 'back',
      pageBackground: this.resolvePageBackground(),
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: this.isSessionEphemeral,
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.embeddedInDialog,
      scrollers: [this.settingsScroller],
      onBack: () => {
        this.handleBack(DOWNLOAD_SETTINGS_MAIN_DESTINATION);
      }
    }) {
      Column() {
        if (this.settingsReady) {
          SettingsScrollBody({
            topPadding: 16,
            bottomPadding: 22,
            clipContent: this.embeddedInDialog,
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
              surfaceBackground: this.resolveCardSurface(),
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
              },
              onRequestFolderChange: (): void => {
                // Route through the screen's own method: it delegates to an
                // embedded host when present and otherwise opens the picker
                // itself, which is what the phone page path needs.
                this.onRequestFolderChange();
              },
              onResetToSystemDownloadLocation: (): void => {
                this.resetToSystemDownloadLocation();
              }
            })
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.resolvePageBackground())
    }
  }

  private resolvePageBackground(): ResourceColor {
    return this.embeddedInDialog ? Color.Transparent : this.storedPageBackgroundColor;
  }

  private resolveCardSurface(): ResourceColor {
    return this.embeddedInDialog ? this.storedPageBackgroundColor : this.storedSurfaceBackgroundColor;
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
    if (this.onOpenEmbeddedSubpage !== undefined) {
      this.onOpenEmbeddedSubpage(subpage);
      return;
    }
    this.navigationCoordinator.openDownloadSettingsOption(subpage, this.buildBoundaryState());
  }

  /**
   * The main page no longer routes through the option subpage. When an embedded
   * host owns the picker it takes over; otherwise the phone path picks directly.
   * Devices without folder selection simply keep the current location, because
   * this content has no toast surface of its own.
   */
  private onRequestFolderChange(): void {
    if (!new DownloadLocationDirectoryService().isFolderSelectionSupported()) {
      this.showToast('当前设备不支持选择文件夹。');
      return;
    }
    if (this.onFolderChangeRequested !== undefined) {
      this.onFolderChangeRequested();
      return;
    }
    void this.chooseCustomDownloadLocation();
  }

  /**
   * The way back to the system folder. It also releases the persisted grant on
   * the folder being abandoned, so the app does not keep authorization for a
   * location it no longer uses.
   */
  private resetToSystemDownloadLocation(): void {
    const currentSettings = readDownloadSettings(this.settingsBoundary);
    if (currentSettings.defaultLocation !== 'custom') {
      return;
    }
    const previousUri = currentSettings.customLocationUri;
    const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(currentSettings, {
      defaultLocation: 'system_downloads',
      customLocationUri: '',
      customLocationLabel: ''
    });
    this.saveDownloadSettings(nextSettings, '下载位置保存失败');
    if (previousUri.length > 0) {
      void new DownloadLocationDirectoryService().releaseDirectory(previousUri);
    }
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



  private saveDownloadSettings(
    settings: BrowserDownloadSettings,
    failurePrefix: string,
    silentOnSuccess: boolean = false
  ): void {
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
    ).then(() => {
      if (!silentOnSuccess) {
        this.showToast('已保存');
      }
    }).catch((error: Error) => {
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

  /**
   * Picks and persists a custom download folder from the main settings page.
   * It passes `silentOnSuccess` because the branches below give a more specific
   * message about the folder that was just adopted than a bare "已保存".
   */
  private async chooseCustomDownloadLocation(): Promise<void> {
    const directoryService = new DownloadLocationDirectoryService();
    try {
      if (!directoryService.isFolderSelectionSupported()) {
        this.showToast('当前设备不支持选择文件夹，将使用系统下载目录。');
        return;
      }
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const result = await directoryService.selectDirectory(context);
      if (result.status !== 'selected' || result.selection === undefined) {
        if (result.status === 'unusable_folder') {
          this.showToast('这个文件夹不可用，请换一个再试。');
        }
        return;
      }
      const selection = result.selection;
      // The probe is advisory. It can report a false negative (URI encoding,
      // transient grants), and the export path already falls back on its own,
      // so it must never discard the folder the user just picked.
      const isWritable = await directoryService.verifyDirectoryWritable(selection.uri);
      const currentSettings = readDownloadSettings(this.settingsBoundary);
      const previousUri = currentSettings.customLocationUri;
      const nextSettings = this.downloadSettingsViewModel.buildSettingsPatch(currentSettings, {
        defaultLocation: 'custom',
        customLocationUri: selection.uri,
        customLocationLabel: selection.label
      });
      this.saveDownloadSettings(nextSettings, '下载位置保存失败', true);
      if (previousUri.length > 0 && previousUri !== selection.uri) {
        void directoryService.releaseDirectory(previousUri);
      }
      if (!isWritable) {
        this.showToast('已选择该文件夹。若下载时无法写入，将回退到系统下载目录。');
      } else if (!result.isPersisted) {
        this.showToast('已选择该文件夹。重启应用后需要重新授权。');
      }
    } catch (error) {
      this.showToast('选择下载位置失败');
      hilog.error(
        DOWNLOAD_SETTINGS_DOMAIN,
        DOWNLOAD_SETTINGS_TAG,
        'choose download location failed: %{public}s',
        this.stringifyError(error)
      );
    }
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
  /** Restores the system download folder; the way back from a custom folder. */
  onResetToSystemDownloadLocation: () => void = (): void => {};
  /**
   * Opens the folder picker directly from the main settings page. The embedded
   * dialog host routes this back out to its own owner so the picker runs while
   * the dialog is closed, then the dialog is restored.
   */
  onRequestFolderChange: () => void = (): void => {};

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
        if (this.isUsingCustomDownloadLocation()) {
          SettingsGroupDivider({ dividerColor: this.resolveDividerColor() })
          this.buildRestoreSystemLocationRow()
        }
      }
      SettingsFooterText({
        text: this.isUsingCustomDownloadLocation()
          ? '下载完成后保存到选定的文件夹。私密下载仍按私密设置处理。'
          : '下载完成后保存到这里。私密下载仍按私密设置处理。',
        secondaryTextColor: this.resolveSecondaryTextColor()
      })
    }
  }

  private isUsingCustomDownloadLocation(): boolean {
    return this.viewState.defaultLocation === 'custom' &&
      this.viewState.customLocationUri.trim().length > 0;
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
      SettingsNavigationRow({
        title: '下载位置',
        desktopPresentation: this.desktopPresentation,
        value: this.viewState.defaultLocationLabel,
        rowPosition: this.isUsingCustomDownloadLocation() ? 'first' : 'single',        // One tap straight into the system folder picker. The intermediate
        // "system vs custom" radio page only added a step: both choices end in a
        // folder, and the row already shows which one is active.
        onAction: (): void => {
          this.onRequestFolderChange();
        }
      })
    }
  }

  /**
   * Keeps the way back to the system folder now that the option subpage is gone.
   * Without it, choosing a custom folder would be a one-way door.
   */
  @Builder
  private buildRestoreSystemLocationRow() {
    SettingsNavigationRow({
      title: '恢复系统下载目录',
      desktopPresentation: this.desktopPresentation,
      value: '',
      rowPosition: 'last',
      onAction: (): void => {
        this.onResetToSystemDownloadLocation();
      }
    })
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
  @Prop boundary: DownloadTaskBoundary | undefined = undefined;
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop embeddedInDialog: boolean = false;
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
    if (this.boundary !== undefined) {
      this.settingsBoundary = this.boundary;
      this.isSessionEphemeral = this.boundary.privacyMode === 'private';
    } else {
      const routeParams = router.getParams() as BrowserPrivateBoundaryRouteParams | undefined;
      this.isSessionEphemeral = this.privateBoundaryNavigationService.isSessionEphemeralRoute(routeParams);
      this.settingsBoundary = buildDownloadSettingsBoundary(routeParams);
    }
    this.refreshState();
  }

  build() {
    SettingsHdsScaffold({
      title: this.resolveHeaderTitle(),
      backIconKind: 'back',
      pageBackground: this.embeddedInDialog ? Color.Transparent : this.storedPageBackgroundColor,
      headerButtonBackground: this.storedPressedBackgroundColor,
      primaryTextColor: this.storedPrimaryTextColor,
      dividerColor: this.storedDividerColor,
      showPrivateIndicator: this.isSessionEphemeral,
      showBackButton: this.showBackButton,
      showTitleBar: this.showTitleBar,
      useTopSafeInset: this.useTopSafeInset,
      desktopPresentation: this.embeddedInDialog || this.desktopPresentation,
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
      bottomPadding: 22,
      clipContent: this.embeddedInDialog
    }) {
      SettingsGroupCard({
        surfaceColor: this.embeddedInDialog ? this.storedPageBackgroundColor : this.storedSurfaceBackgroundColor,
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
      this.isSelectingOption = false;
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
      this.isSelectingOption = false;
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
      this.isSelectingOption = false;
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
      this.isSelectingOption = false;
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
      // Stay on the option page. Popping back used to hide the outcome, so the
      // user could not tell whether the choice took effect. The refreshed
      // selection mark plus a toast is the confirmation now.
      this.isSelectingOption = false;
      this.showToast('已保存');
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

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
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
