import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { common } from '@kit.AbilityKit';
import router from '@ohos.router';
import {
  UserScriptManagementAction,
  UserScriptManagementEffect,
  UserScriptManagementSessionCoordinator,
  UserScriptManagementSheet,
  UserScriptManagementSnapshot,
  UserScriptManagementSurfaceFacts,
  UserScriptManagementTransition
} from '../../../core/userscripts/UserScriptManagementSessionCoordinator';
import { UserScriptDetailState } from '../../../core/userscripts/UserScriptDetailViewModel';
import {
  createUserScriptManagementSessionCoordinator,
  sharedPreferencesRepository,
  sharedUserScriptInstallSessionCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import {
  BROWSER_SHELL_ROUTE,
  USER_SCRIPT_DETAIL_ROUTE,
  USER_SCRIPT_SOURCE_EDIT_ROUTE
} from '../../router/AppRoutes';
import {
  requestOpenBrowserUrlWithRouteParams
} from '../../../core/navigation/BrowserNativeNavigationRequestCenter';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import { UserScriptExportService } from '../../../services/userscripts/UserScriptExportService';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP
} from '../../../core/browser/BrowserModalPresentationTokens';
import { UserScriptDetailScreen } from './UserScriptDetailScreen';
import { UserScriptInstallSheetContent } from './UserScriptInstallSheetContent';
import { UserScriptManualUrlDialog } from './UserScriptManualUrlDialog';
import { UserScriptRiskConsentSheet } from './UserScriptRiskConsentSheet';
import { UserScriptUpdateSheet } from './UserScriptUpdateSheet';
import { UserScriptsScreen } from './UserScriptsScreen';
import {
  UserScriptManualSourceEditOwner,
  UserScriptInstallSourceRequest,
  UserScriptInstallSourceResult
} from '../../../core/userscripts/UserScriptInstallSessionCoordinator';
import {
  USER_SCRIPT_MANUAL_SOURCE_EDIT_COMPLETION_REVISION_KEY
} from '../../../core/userscripts/UserScriptManualSourceEditCompletionSignal';
import { UserScriptExternalImportRuntime } from '../../../core/userscripts/UserScriptExternalImportRuntime';
import { BrowserWindowRuntime } from '../../runtime/BrowserWindowRuntime';
import {
  AppWindowModalLayout,
  AppWindowModalLayoutService
} from '../../../services/layout/AppWindowModalLayoutService';

export type UserScriptManagementPresentationMode = 'page' | 'native_tab';
type UserScriptManagementActiveSurface = UserScriptManagementSheet | 'install';

@Component
export struct UserScriptManagementHost {
  @Prop @Watch('handleManualSourceHostBoundaryChanged') presentationMode: UserScriptManagementPresentationMode = 'page';
  @Prop settingsWorkspacePresentation: boolean = false;
  @Prop @Watch('handleRefreshRevisionChanged') refreshRevision: number = 0;
  @Prop @Watch('handleManualSourceHostBoundaryChanged') dataScope: string = '';
  @Prop @Watch('handleManualSourceHostBoundaryChanged') privacyMode: string = '';
  @Prop @Watch('handleManualSourceHostBoundaryChanged') boundarySource: string = '';
  onRequestClose: () => void = () => {};
  onRequestOpenGallerySource: (url: string) => void = (_url: string) => {};
  onSettingsChanged: () => void = () => {};

  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY)
  private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @StorageLink(USER_SCRIPT_MANUAL_SOURCE_EDIT_COMPLETION_REVISION_KEY)
  @Watch('handleManualSourceEditCompletionRevisionChanged')
  private manualSourceEditCompletionRevision: number = 0;

  private managementSession: UserScriptManagementSessionCoordinator =
    createUserScriptManagementSessionCoordinator();
  private exportService: UserScriptExportService = new UserScriptExportService();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);

  @State private managementSnapshot: UserScriptManagementSnapshot = this.managementSession.snapshot();
  @State private activeSurfaceVisible: boolean = false;
  @State private activeSurface: UserScriptManagementActiveSurface = 'none';
  @State private selectedScriptId: string = '';
  @State private detailState: UserScriptDetailState = this.managementSession.detailSnapshot('');
  @State private manualUrlDraft: string = '';
  @State private nativeModalViewportWidthVp: number = 0;
  @State private nativeModalViewportHeightVp: number = 0;
  @State private manualSourceInstallClaimToken: string = '';
  private readonly modalLayoutService: AppWindowModalLayoutService = new AppWindowModalLayoutService();
  private manualSourceEditWindowId: string = '';
  private manualSourceEditSurface: UserScriptManagementPresentationMode = 'page';
  private manualSourceEditDataScope: string = '';
  private manualSourceEditPrivacyMode: string = '';
  private manualSourceEditBoundarySource: string = '';
  private manualSourceInstallHostSessionId: string = '';
  private externalImportListener: () => void = (): void => {
    this.consumePendingExternalImport();
  };
  private manualUrlDialogController: CustomDialogController = new CustomDialogController({
    builder: UserScriptManualUrlDialog({
      urlDraft: $manualUrlDraft,
      onConfirm: () => {
        this.loadManualUrl();
      }
    }),
    customStyle: true,
    autoCancel: true
  });

  aboutToAppear(): void {
    this.manualSourceEditWindowId = BrowserWindowRuntime.resolveWindowIdFromStorage(
      this.getUIContext().getSharedLocalStorage()
    );
    this.manualSourceEditSurface = this.presentationMode;
    this.manualSourceEditDataScope = this.dataScope;
    this.manualSourceEditPrivacyMode = this.privacyMode;
    this.manualSourceEditBoundarySource = this.boundarySource;
    if (!this.ensureOptionalServiceAvailable()) {
      return;
    }
    this.manualSourceInstallHostSessionId = sharedUserScriptInstallSessionCoordinator.registerManualSourceInstallHost(
      this.buildManualSourceEditOwner()
    );
    this.managementSession.setObserver((transition: UserScriptManagementTransition): void => {
      this.applyManagementTransition(transition);
    });
    this.activateManagementSession();
    UserScriptExternalImportRuntime.subscribe(this.externalImportListener);
    this.resumeManualSourceEditIfNeeded();
    this.consumePendingExternalImport();
  }

  private handleRefreshRevisionChanged(): void {
    void this.refreshRevision;
    if (this.ensureOptionalServiceAvailable()) {
      this.activateManagementSession();
      this.resumeManualSourceEditIfNeeded();
      this.handleManualSourceHostBoundaryChanged();
    }
  }

  private handleManualSourceEditCompletionRevisionChanged(): void {
    void this.manualSourceEditCompletionRevision;
    this.resumeManualSourceEditIfNeeded();
    this.handleManualSourceHostBoundaryChanged();
  }

  private handleManualSourceHostBoundaryChanged(): void {
    if (!this.hasManualSourceHostBoundaryChanged()) {
      return;
    }
    if (this.activeSurface === 'install' && this.activeSurfaceVisible) {
      if (!this.isInstallCommitBusy()) {
        this.dismissActiveSurface(this.manualSourceInstallClaimToken);
        this.showToast('浏览边界已切换，请重新添加脚本。');
      }
      return;
    }
    if (sharedUserScriptInstallSessionCoordinator.getState().importBusy) {
      sharedUserScriptInstallSessionCoordinator.cancelImport();
    }
    this.refreshManualSourceHostBoundaryIfIdle();
  }

  aboutToDisappear(): void {
    if (this.activeSurface === 'install' && this.activeSurfaceVisible &&
      this.manualSourceInstallClaimToken.length > 0) {
      sharedUserScriptInstallSessionCoordinator.releaseManualSourceInstall(
        this.buildManualSourceEditOwner(),
        this.manualSourceInstallClaimToken
      );
    }
    sharedUserScriptInstallSessionCoordinator.unregisterManualSourceInstallHost(
      this.buildManualSourceEditOwner()
    );
    this.manualSourceInstallHostSessionId = '';
    UserScriptExternalImportRuntime.unsubscribe(this.externalImportListener);
    this.managementSession.setObserver(undefined);
  }

  build() {
    if (this.presentationMode === 'native_tab') {
      this.buildNativeTabSurface()
    } else {
      this.buildPageSurface()
    }
  }

  @Builder
  private buildPageSurface() {
    Column() {
      this.buildManagementContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .bindSheet($$this.activeSurfaceVisible, this.buildActiveSurface(), {
      preferType: SheetType.BOTTOM,
      height: this.resolvePhoneSheetHeight(),
      dragBar: true,
      showClose: false,
      onWillDismiss: (dismissDialogAction: DismissDialogAction): void => {
        if (!this.isInstallCommitBusy()) {
          dismissDialogAction.dismiss();
        }
      },
      onDisappear: () => {
        this.handleActiveSurfaceDisappear();
      }
    })
  }

  @Builder
  private buildNativeTabSurface() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildManagementContent()

      if (this.activeSurfaceVisible) {
        this.buildNativeModalSurface()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      this.updateNativeModalViewport(newArea);
    })
  }

  @Builder
  private buildManagementContent() {
    Row() {
      if (this.presentationMode === 'native_tab' && this.selectedScriptId.length > 0) {
        UserScriptDetailScreen({
          state: this.detailState,
          showBackButton: true,
          showTitleBar: true,
          useTopSafeInset: false,
          desktopPresentation: this.settingsWorkspacePresentation,
          onBack: () => {
            this.selectedScriptId = '';
          },
          onToggleScript: (enabled: boolean) => {
            this.toggleSelectedScript(enabled);
          },
          onOpenExtensionsPage: () => {
            this.selectedScriptId = '';
          },
          onDeleteScript: () => {
            this.requestSelectedScriptDelete();
          }
        })
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: 1120 })
      } else {
        UserScriptsScreen({
          state: this.managementSnapshot.settings,
          showNotice: this.managementSnapshot.showNotice,
          valueRecovery: this.managementSnapshot.valueRecovery,
          showBackButton: this.presentationMode === 'page',
          showTitleBar: true,
          useTopSafeInset: this.presentationMode === 'page',
          desktopPresentation: this.settingsWorkspacePresentation,
          onAddFromUrl: () => {
            this.openManualUrlDialog();
          },
          onImportFromFile: () => {
            this.importManualFile();
          },
          onEditSource: () => {
            this.openManualSourceEditor();
          },
          onOpenGallerySource: (url: string) => {
            this.openManualGallerySource(url);
          },
          onToggleScript: (scriptId: string, enabled: boolean) => {
            this.managementSession.action(UserScriptManagementAction.toggleScript(scriptId, enabled));
          },
          onEditScript: (scriptId: string) => {
            this.openScriptDetail(scriptId);
          },
          onUpdateScript: (scriptId: string) => {
            this.managementSession.action(UserScriptManagementAction.checkScriptUpdate(scriptId));
          },
          onExportScript: (scriptId: string) => {
            this.managementSession.action(UserScriptManagementAction.requestExportScript(scriptId));
          },
          onUpdateAllScripts: () => {
            this.managementSession.action(UserScriptManagementAction.checkAllUpdates());
          },
          onAutoUpdateChange: (enabled: boolean) => {
            this.managementSession.action(UserScriptManagementAction.setAutoUpdate(enabled));
          },
          onDeleteScript: (scriptId: string) => {
            this.managementSession.action(UserScriptManagementAction.requestDeleteScript(scriptId));
          },
          onDismissNotice: () => {
            this.managementSession.action(UserScriptManagementAction.dismissNotice());
          },
          onBack: () => {
            this.onRequestClose();
          }
        })
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: 1120 })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildActiveSurface() {
    if (this.activeSurface === 'riskConsent') {
      UserScriptRiskConsentSheet({
        state: this.managementSnapshot.riskConsent,
        fillAvailableHeight: this.presentationMode === 'native_tab',
        layoutMode: this.presentationMode === 'native_tab' ? 'large_screen' : 'phone',
        onAccept: () => {
          this.managementSession.action(UserScriptManagementAction.acceptRiskConsent());
        },
        onDecline: () => {
          this.managementSession.action(UserScriptManagementAction.declineRiskConsent());
        }
      })
    } else if (this.activeSurface === 'updateCheck') {
      UserScriptUpdateSheet({
        results: this.managementSnapshot.updateResults,
        checking: this.managementSnapshot.updateChecking,
        updating: this.managementSnapshot.updateInstalling,
        fillAvailableHeight: this.presentationMode === 'native_tab',
        layoutMode: this.presentationMode === 'native_tab' ? 'large_screen' : 'phone',
        onUpdateSelected: () => {
          this.managementSession.action(UserScriptManagementAction.installAvailableUpdates());
        },
        onClose: () => {
          this.managementSession.action(UserScriptManagementAction.sheetDismissed('updateCheck'));
        }
      })
    } else if (this.activeSurface === 'install') {
      ForEach([this.buildInstallSurfaceRenderKey()], (_renderKey: string) => {
        UserScriptInstallSheetContent({
          entryMode: 'prepared_manual_install',
          dataScope: this.dataScope,
          privacyMode: this.privacyMode,
          manualSourceInstallOwner: this.buildManualSourceEditOwner(),
          manualSourceInstallToken: this.manualSourceInstallClaimToken,
          onRequestCloseWithAccess: (manualSourceInstallToken: string) => {
            this.dismissActiveSurface(manualSourceInstallToken);
          },
          onCommitSettled: () => {
            this.handleInstallCommitSettled();
          },
          onInstalled: () => {
            this.dismissActiveSurface(this.manualSourceInstallClaimToken);
            this.activateManagementSession();
            this.onSettingsChanged();
          }
        })
        .width('100%')
        .height('100%')
      }, (renderKey: string) => renderKey)
    } else {
      Column()
    }
  }

  @Builder
  private buildNativeModalSurface() {
    Stack({ alignContent: Alignment.Center }) {
      Button()
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor(this.storedPrimaryTextColor)
        .opacity(0.18)
        .accessibilityText('关闭用户脚本弹窗')
        .onClick(() => {
          this.dismissActiveSurface(this.manualSourceInstallClaimToken);
        })

      Column() {
        this.buildActiveSurface()
      }
      .width(this.resolveNativeModalLayout().width)
      .height(this.resolveNativeModalLayout().height)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(BROWSER_LARGE_SCREEN_MODAL_CORNER_RADIUS_VP)
      .clip(true)
    }
    .width('100%')
    .height('100%')
    .zIndex(40)
  }

  private resolveNativeModalLayout(): AppWindowModalLayout {
    const viewportWidth = this.nativeModalViewportWidthVp > 0 ? this.nativeModalViewportWidthVp : 752;
    const viewportHeight = this.nativeModalViewportHeightVp > 0 ? this.nativeModalViewportHeightVp : 652;
    const installSurface = this.activeSurface === 'install';
    return this.modalLayoutService.resolveModal({
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      preferredWidth: installSurface ? viewportWidth * 0.72 : 560,
      preferredHeight: installSurface ? viewportHeight * 0.88 : 520,
      softMinWidth: 420,
      maxWidth: 720,
      softMinHeight: 0,
      maxHeight: viewportHeight * 0.9
    });
  }

  private updateNativeModalViewport(area: Area): void {
    const width = Number(area.width);
    const height = Number(area.height);
    if (Number.isFinite(width) && width > 0 && width !== this.nativeModalViewportWidthVp) {
      this.nativeModalViewportWidthVp = width;
    }
    if (Number.isFinite(height) && height > 0 && height !== this.nativeModalViewportHeightVp) {
      this.nativeModalViewportHeightVp = height;
    }
  }

  private activateManagementSession(): void {
    this.managementSession.activate(new UserScriptManagementSurfaceFacts(
      true,
      {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        loggedIn: true
      }
    ));
  }

  private consumePendingExternalImport(): void {
    const envelope = UserScriptExternalImportRuntime.consume();
    if (envelope === undefined) {
      return;
    }
    if (sharedUserScriptInstallSessionCoordinator.hasManualSourceInstallClaim()) {
      this.showToast('另一个脚本正在等待安装，请先完成或关闭当前安装。');
      return;
    }
    if (envelope.status === 'failed') {
      sharedUserScriptInstallSessionCoordinator.reset();
      this.showToast(envelope.errorMessage);
      return;
    }
    if (sharedUserScriptInstallSessionCoordinator.getState().source.trim().length === 0) {
      this.showToast('用户脚本预览状态不可用。');
      return;
    }
    this.openInstallSurface();
  }

  private applyManagementTransition(transition: UserScriptManagementTransition): void {
    this.managementSnapshot = transition.snapshot;
    if (this.selectedScriptId.length > 0) {
      this.detailState = this.managementSession.detailSnapshot(this.selectedScriptId);
    }
    this.syncActiveSurface(transition.snapshot.activeSheet);
    transition.effects.forEach((effect: UserScriptManagementEffect): void => {
      this.handleManagementEffect(effect);
    });
  }

  private syncActiveSurface(surface: UserScriptManagementSheet): void {
    if (surface === 'none') {
      if (this.activeSurface !== 'install') {
        this.activeSurfaceVisible = false;
      }
      return;
    }
    this.activeSurface = surface;
    this.activeSurfaceVisible = true;
  }

  private handleManagementEffect(effect: UserScriptManagementEffect): void {
    if (effect.kind === 'exit') {
      this.onRequestClose();
      return;
    }
    if (effect.kind === 'message') {
      this.showToast(effect.message);
      return;
    }
    if (effect.kind === 'settings_changed') {
      this.onSettingsChanged();
      return;
    }
    if (effect.kind === 'confirm_delete_script') {
      this.confirmDeleteScript(effect.scriptId, effect.scriptName);
      return;
    }
    if (effect.kind === 'script_deleted' && effect.scriptId === this.selectedScriptId) {
      this.selectedScriptId = '';
      return;
    }
    if (effect.kind === 'export_script' && effect.script !== undefined) {
      this.exportService.exportScript(this.getPickerContext(), effect.script, {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      })
        .then((result) => {
          this.showToast(result.message);
        })
        .catch((_error: Error) => {
          this.showToast('导出脚本失败，请稍后重试。');
        });
    }
  }

  private openInstallSurface(manualSourceInstallToken: string = ''): void {
    this.manualSourceInstallClaimToken = manualSourceInstallToken.trim();
    this.activeSurface = 'install';
    this.activeSurfaceVisible = true;
  }

  private buildInstallSurfaceRenderKey(): string {
    return this.manualSourceInstallClaimToken.length > 0 ?
      `manual-${this.manualSourceInstallClaimToken}` : 'direct';
  }

  private openManualUrlDialog(): void {
    if (!this.ensureOptionalServiceAvailable()) {
      return;
    }
    this.manualUrlDraft = '';
    this.manualUrlDialogController.open();
  }

  private loadManualUrl(): void {
    const url = this.manualUrlDraft.trim();
    if (url.length <= 0) {
      this.showToast('请输入脚本 URL。');
      return;
    }
    this.loadManualSource({ type: 'url', url: url });
  }

  private importManualFile(): void {
    if (!this.ensureOptionalServiceAvailable()) {
      return;
    }
    this.loadManualSource({ type: 'file', context: this.getPickerContext() });
  }

  private loadManualSource(request: UserScriptInstallSourceRequest): void {
    sharedUserScriptInstallSessionCoordinator.reset();
    void sharedUserScriptInstallSessionCoordinator.loadSource(request)
      .then((result: UserScriptInstallSourceResult) => {
        this.handleManualSourceResult(result);
      })
      .catch((error: Error) => {
        this.showToast(error.message.length > 0 ? error.message : '读取脚本失败。');
      });
  }

  private handleManualSourceResult(result: UserScriptInstallSourceResult): void {
    switch (result.status) {
      case 'cancelled':
        return;
      case 'failed':
        this.showToast(result.errorMessage);
        return;
      case 'duplicate':
        this.showToast(`“${result.duplicate.scriptName}”已经安装。`);
        return;
      case 'loaded':
        this.openInstallSurface();
        return;
    }
  }

  private openManualSourceEditor(): void {
    if (!this.ensureOptionalServiceAvailable()) {
      return;
    }
    if (!this.refreshManualSourceHostBoundaryIfIdle()) {
      this.showToast('脚本编辑或安装仍属于之前的浏览边界，请先完成或关闭。');
      return;
    }
    const editToken = sharedUserScriptInstallSessionCoordinator.beginManualSourceEdit(
      this.buildManualSourceEditOwner()
    );
    if (editToken.length === 0) {
      this.showToast('另一个窗口正在编辑或安装脚本，请稍后重试。');
      return;
    }
    router.pushUrl({
      url: USER_SCRIPT_SOURCE_EDIT_ROUTE,
      params: {
        dataScope: this.manualSourceEditDataScope,
        privacyMode: this.manualSourceEditPrivacyMode,
        boundarySource: this.manualSourceEditBoundarySource,
        manualSourceEditToken: editToken
      }
    }).catch((_error: Error) => {
      sharedUserScriptInstallSessionCoordinator.cancelManualSourceEdit(editToken);
    });
  }

  private resumeManualSourceEditIfNeeded(): void {
    if (this.manualSourceEditWindowId.length === 0) {
      return;
    }
    const owner = this.buildManualSourceEditOwner();
    const completedInstallToken = sharedUserScriptInstallSessionCoordinator.consumeManualSourceEditCompletion(owner);
    if (completedInstallToken.length > 0) {
      this.openInstallSurface(completedInstallToken);
      return;
    }
    const resumedInstallToken = sharedUserScriptInstallSessionCoordinator.resumeManualSourceInstall(owner);
    if (resumedInstallToken.length > 0) {
      this.openInstallSurface(resumedInstallToken);
    }
  }

  private buildManualSourceEditOwner(): UserScriptManualSourceEditOwner {
    return {
      windowId: this.manualSourceEditWindowId,
      surface: this.manualSourceEditSurface,
      dataScope: this.manualSourceEditDataScope,
      privacyMode: this.manualSourceEditPrivacyMode,
      boundarySource: this.manualSourceEditBoundarySource,
      hostSessionId: this.manualSourceInstallHostSessionId
    };
  }

  private refreshManualSourceHostBoundaryIfIdle(): boolean {
    if (this.manualSourceInstallHostSessionId.length === 0) {
      return false;
    }
    if (!this.hasManualSourceHostBoundaryChanged()) {
      return true;
    }
    if (this.activeSurface === 'install' && this.activeSurfaceVisible) {
      return false;
    }
    const currentOwner = this.buildManualSourceEditOwner();
    if (sharedUserScriptInstallSessionCoordinator.hasManualSourceWorkForHost(currentOwner)) {
      return false;
    }
    sharedUserScriptInstallSessionCoordinator.unregisterManualSourceInstallHost(currentOwner);
    this.manualSourceEditSurface = this.presentationMode;
    this.manualSourceEditDataScope = this.dataScope;
    this.manualSourceEditPrivacyMode = this.privacyMode;
    this.manualSourceEditBoundarySource = this.boundarySource;
    this.manualSourceInstallHostSessionId = sharedUserScriptInstallSessionCoordinator.registerManualSourceInstallHost(
      this.buildManualSourceEditOwner()
    );
    return this.manualSourceInstallHostSessionId.length > 0;
  }

  private hasManualSourceHostBoundaryChanged(): boolean {
    return this.manualSourceEditSurface !== this.presentationMode ||
      this.manualSourceEditDataScope !== this.dataScope ||
      this.manualSourceEditPrivacyMode !== this.privacyMode ||
      this.manualSourceEditBoundarySource !== this.boundarySource;
  }

  private openManualGallerySource(url: string): void {
    const targetUrl = url.trim();
    if (targetUrl.length <= 0) {
      return;
    }
    sharedUserScriptInstallSessionCoordinator.reset();
    if (this.presentationMode === 'native_tab') {
      this.onRequestOpenGallerySource(targetUrl);
      return;
    }
    router.back({
      url: BROWSER_SHELL_ROUTE,
      params: requestOpenBrowserUrlWithRouteParams(targetUrl, 'current_tab', '', 'userscript_install')
    });
  }

  private dismissActiveSurface(manualSourceInstallToken: string = ''): void {
    if (this.activeSurface === 'install' &&
      manualSourceInstallToken.trim() !== this.manualSourceInstallClaimToken) {
      return;
    }
    if (this.isInstallCommitBusy()) {
      return;
    }
    const dismissedSurface = this.activeSurface;
    this.activeSurfaceVisible = false;
    this.activeSurface = 'none';
    if (dismissedSurface === 'install') {
      const releasedManualInstall = this.manualSourceInstallClaimToken.length > 0 &&
        sharedUserScriptInstallSessionCoordinator.releaseManualSourceInstall(
          this.buildManualSourceEditOwner(),
          this.manualSourceInstallClaimToken
        );
      this.manualSourceInstallClaimToken = '';
      if (releasedManualInstall) {
        this.refreshManualSourceHostBoundaryIfIdle();
        return;
      }
      sharedUserScriptInstallSessionCoordinator.reset();
      this.refreshManualSourceHostBoundaryIfIdle();
      return;
    }
    if (dismissedSurface !== 'none') {
      this.managementSession.action(UserScriptManagementAction.sheetDismissed(dismissedSurface));
    }
  }

  private isInstallCommitBusy(): boolean {
    return this.activeSurface === 'install' &&
      sharedUserScriptInstallSessionCoordinator.getState().commitBusy;
  }

  private handleInstallCommitSettled(): void {
    if (this.hasManualSourceHostBoundaryChanged()) {
      this.handleManualSourceHostBoundaryChanged();
    }
  }

  private handleActiveSurfaceDisappear(): void {
    this.dismissActiveSurface(this.manualSourceInstallClaimToken);
  }

  private openScriptDetail(scriptId: string): void {
    const normalizedScriptId = scriptId.trim();
    if (normalizedScriptId.length <= 0) {
      return;
    }
    if (this.presentationMode === 'native_tab') {
      this.selectedScriptId = normalizedScriptId;
      this.detailState = this.managementSession.detailSnapshot(normalizedScriptId);
      return;
    }
    router.pushUrl({
      url: USER_SCRIPT_DETAIL_ROUTE,
      params: {
        scriptId: normalizedScriptId,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      }
    }).catch((_error: Error) => {});
  }

  private toggleSelectedScript(enabled: boolean): void {
    if (this.selectedScriptId.length > 0) {
      this.managementSession.action(UserScriptManagementAction.toggleScript(this.selectedScriptId, enabled));
    }
  }

  private requestSelectedScriptDelete(): void {
    if (this.selectedScriptId.length > 0) {
      this.managementSession.action(UserScriptManagementAction.requestDeleteScript(this.selectedScriptId));
    }
  }

  private confirmDeleteScript(scriptId: string, scriptName: string): void {
    showCenteredAlertDialog({
      title: '删除用户脚本',
      message: `确定删除“${scriptName}”吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.managementSession.action(UserScriptManagementAction.deleteScript(scriptId));
        }
      }
    });
  }

  private resolvePhoneSheetHeight(): SheetSize {
    return SheetSize.LARGE;
  }

  private ensureOptionalServiceAvailable(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.onRequestClose();
    return false;
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

  private getPickerContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

}
