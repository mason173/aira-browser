import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { UserScriptInstallScreen } from './UserScriptInstallScreen';
import {
  UserScriptManualSourceEditOwner,
  UserScriptInstallExistingTarget,
  UserScriptInstallSessionObserver,
  UserScriptInstallSessionState,
  UserScriptInstallSourceResult,
  buildEmptyUserScriptInstallExistingTarget
} from '../../../core/userscripts/UserScriptInstallSessionCoordinator';
import {
  resolveUserScriptInstallLoadErrorMessage,
  UserScriptInstallPreviewState,
  UserScriptsSettingsViewModel
} from '../../../core/userscripts/UserScriptsSettingsViewModel';
import { USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE } from '../../../services/userscripts/UserScriptSourceFetchService';
import {
  UserScriptPackageMutationResult,
  UserScriptPackageSuccessResult
} from '../../../core/userscripts/UserScriptPackageLifecycleCoordinator';
import {
  sharedPreferencesRepository,
  sharedUserScriptInstallSessionCoordinator
} from '../../bootstrap/BrowserAppRuntime';
import { AIRA_PRO_ROUTE } from '../../router/AppRoutes';
import { EntitlementDecision } from '../../../common/models/MembershipModels';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import {
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

export type UserScriptInstallEntryMode = 'prepared_manual_install' | 'direct_web_install';

@Component
export struct UserScriptInstallSheetContent {
  @Prop initialSourceUrl: string = '';
  @Prop entryMode: UserScriptInstallEntryMode = 'direct_web_install';
  @Prop dataScope: string = 'profile_persistent';
  @Prop privacyMode: string = 'regular';
  @Prop transparentSurface: boolean = false;
  manualSourceInstallOwner?: UserScriptManualSourceEditOwner;
  manualSourceInstallToken: string = '';
  onRequestClose: () => void = () => {};
  onRequestCloseWithAccess?: (manualSourceInstallToken: string) => void;
  onCommitSettled: () => void = () => {};
  onInstalled: (result: UserScriptPackageSuccessResult) => void = (_result: UserScriptPackageSuccessResult) => {};
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private viewModel: UserScriptsSettingsViewModel = new UserScriptsSettingsViewModel();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private sessionRevision: number = -1;
  private installSurfaceObserverToken: string = '';
  private installSurfaceAccessInitialized: boolean = false;
  private installSurfaceAccessOwner?: UserScriptManualSourceEditOwner;
  private installSurfaceAccessToken: string = '';
  private installSurfaceDataScope: string = 'profile_persistent';
  private installSurfacePrivacyMode: string = 'regular';
  private pageVisible: boolean = false;
  @State private source: string = '';
  @State private preview: UserScriptInstallPreviewState = this.viewModel.buildInstallPreview(undefined, [], '');
  @State private existingTarget: UserScriptInstallExistingTarget = buildEmptyUserScriptInstallExistingTarget();
  @State private importBusy: boolean = false;
  @State private commitBusy: boolean = false;
  @State private loadErrorMessage: string = '';
  aboutToAppear(): void {
    this.freezeInstallSurfaceAccess();
    this.pageVisible = true;
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const initialSourceUrl = this.initialSourceUrl.trim();
    const initialState = this.entryMode === 'prepared_manual_install' ?
      sharedUserScriptInstallSessionCoordinator.getStateForInstallSurface(
        this.installSurfaceAccessOwner,
        this.installSurfaceAccessToken
      ) : sharedUserScriptInstallSessionCoordinator.resetForInstallSurface(
        this.installSurfaceAccessOwner,
        this.installSurfaceAccessToken
      );
    if (initialState === undefined) {
      this.requestClose();
      return;
    }
    this.applySessionState(initialState);
    if (!this.observeInstallSession()) {
      this.requestClose();
      return;
    }
    if (this.entryMode === 'direct_web_install' && this.source.length === 0) {
      if (initialSourceUrl.length > 0) {
        this.importBusy = true;
        void this.loadSourceFromInitialUrl(initialSourceUrl);
      } else {
        this.loadErrorMessage = '没有可读取的脚本地址。';
      }
    }
  }

  onPageShow(): void {
    this.pageVisible = true;
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const state = sharedUserScriptInstallSessionCoordinator.getStateForInstallSurface(
      this.installSurfaceAccessOwner,
      this.installSurfaceAccessToken
    );
    if (state === undefined || !this.observeInstallSession()) {
      this.requestClose();
      return;
    }
    if (state.revision !== this.sessionRevision) {
      this.applySessionState(state);
    }
  }

  onPageHide(): void {
    this.detachInstallSession(false);
  }

  aboutToDisappear(): void {
    this.detachInstallSession(true);
  }

  private detachInstallSession(cancelImport: boolean): void {
    this.pageVisible = false;
    sharedUserScriptInstallSessionCoordinator.clearInstallSurfaceObserver(
      this.installSurfaceObserverToken
    );
    this.installSurfaceObserverToken = '';
    if (cancelImport) {
      sharedUserScriptInstallSessionCoordinator.cancelImport();
    }
  }

  build() {
    Column() {
      UserScriptInstallScreen({
        source: this.source,
        sourceUrl: this.initialSourceUrl,
        loadErrorMessage: this.loadErrorMessage,
        preview: this.preview,
        existingTarget: this.existingTarget,
        importBusy: this.importBusy,
        installBusy: this.commitBusy,
        onSave: () => {
          this.saveScript();
        },
        onRetry: () => {
          this.retryInitialSourceLoad();
        },
        onClose: () => {
          if (!this.commitBusy) {
            this.requestClose();
          }
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.transparentSurface ? Color.Transparent : this.storedPageBackgroundColor)
  }

  private applySessionState(state: UserScriptInstallSessionState): void {
    this.sessionRevision = state.revision;
    this.source = state.source;
    this.existingTarget = state.existingTarget;
    if (state.preview === undefined) {
      this.preview = this.viewModel.buildInstallPreview(undefined, [], '');
    } else {
      switch (state.preview.status) {
        case 'failed':
          this.preview = this.viewModel.buildInstallPreview(
            undefined,
            state.preview.warnings,
            state.preview.errorMessage
          );
          break;
        case 'duplicate':
        case 'ready':
          this.preview = this.viewModel.buildInstallPreview(state.preview.candidate, state.preview.warnings, '');
          break;
      }
    }
    this.importBusy = state.importBusy;
    this.commitBusy = state.commitBusy;
    this.loadErrorMessage = resolveUserScriptInstallLoadErrorMessage(
      state.source,
      state.importBusy,
      state.helperMessage
    );
  }

  private observeInstallSession(): boolean {
    const observer: UserScriptInstallSessionObserver = (state: UserScriptInstallSessionState): void => {
      this.applySessionState(state);
    };
    const token = sharedUserScriptInstallSessionCoordinator.observeInstallSurface(
      observer,
      this.installSurfaceAccessOwner,
      this.installSurfaceAccessToken
    );
    if (token.length === 0) {
      return false;
    }
    this.installSurfaceObserverToken = token;
    return true;
  }

  private saveScript(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (!this.preview.saveEnabled || this.commitBusy) {
      return;
    }
    sharedUserScriptInstallSessionCoordinator.commit({
      dataScope: this.installSurfaceDataScope,
      privacyMode: this.installSurfacePrivacyMode,
      loggedIn: true
    }, this.installSurfaceAccessOwner, this.installSurfaceAccessToken)
      .then((result: UserScriptPackageMutationResult) => {
        if (!this.pageVisible) {
          return;
        }
        this.handleSaveResult(result);
        this.onCommitSettled();
      })
      .catch((error: Error) => {
        if (!this.pageVisible) {
          return;
        }
        this.showSaveFailure(error.message.length > 0 ? error.message : '保存脚本失败。');
        this.onCommitSettled();
      });
  }

  private openAiraProForDeniedInstall(decision: EntitlementDecision): void {
    if (decision.primaryAction !== 'open_pro') {
      return;
    }
    router.pushUrl({
      url: AIRA_PRO_ROUTE
    }).catch((_error: Error) => {});
  }

  private async loadSourceFromInitialUrl(url: string): Promise<void> {
    const result = await sharedUserScriptInstallSessionCoordinator.loadSource({
      type: 'url',
      url: url
    });
    this.handleSourceLoadResult(result);
  }

  private handleSourceLoadResult(result: UserScriptInstallSourceResult): void {
    if (!this.pageVisible) {
      return;
    }
    this.applySourceLoadResult(result);
  }

  private applySourceLoadResult(result: UserScriptInstallSourceResult): void {
    switch (result.status) {
      case 'cancelled':
        this.importBusy = false;
        return;
      case 'failed':
        this.importBusy = false;
        this.loadErrorMessage = result.errorMessage.trim().length > 0 ?
          result.errorMessage.trim() : USER_SCRIPT_SOURCE_DOWNLOAD_FAILED_MESSAGE;
        return;
      case 'loaded':
        this.applySessionState(result.state);
        return;
    }
  }

  private retryInitialSourceLoad(): void {
    const url = this.initialSourceUrl.trim();
    if (url.length === 0 || this.importBusy || this.commitBusy) {
      return;
    }
    this.importBusy = true;
    this.loadErrorMessage = '';
    void this.loadSourceFromInitialUrl(url);
  }

  private handleSaveResult(result: UserScriptPackageMutationResult): void {
    switch (result.status) {
      case 'installed':
      case 'updated':
        this.onInstalled(result);
        return;
      case 'denied':
        this.showSaveFailure(result.errorMessage, result.warnings);
        this.openAiraProForDeniedInstall(result.entitlementDecision);
        return;
      case 'failed':
        this.showSaveFailure(result.errorMessage, result.warnings);
        return;
    }
  }

  private showSaveFailure(message: string, warnings: string[] = []): void {
    const state = sharedUserScriptInstallSessionCoordinator.getStateForInstallSurface(
      this.installSurfaceAccessOwner,
      this.installSurfaceAccessToken
    );
    if (state === undefined) {
      this.requestClose();
      return;
    }
    if (state.preview === undefined || state.preview.status === 'failed') {
      this.preview = this.viewModel.buildInstallPreview(undefined, warnings, message);
      return;
    }
    this.preview = this.viewModel.buildInstallPreview(state.preview.candidate, warnings, message);
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.requestClose();
    return false;
  }

  private freezeInstallSurfaceAccess(): void {
    if (this.installSurfaceAccessInitialized) {
      return;
    }
    this.installSurfaceAccessInitialized = true;
    this.installSurfaceDataScope = this.dataScope;
    this.installSurfacePrivacyMode = this.privacyMode;
    const owner = this.manualSourceInstallOwner;
    if (owner !== undefined) {
      this.installSurfaceAccessOwner = {
        windowId: owner.windowId,
        surface: owner.surface,
        dataScope: owner.dataScope,
        privacyMode: owner.privacyMode,
        boundarySource: owner.boundarySource,
        hostSessionId: owner.hostSessionId
      };
      this.installSurfaceDataScope = owner.dataScope;
      this.installSurfacePrivacyMode = owner.privacyMode;
    }
    this.installSurfaceAccessToken = this.manualSourceInstallToken.trim();
  }

  private requestClose(): void {
    if (this.onRequestCloseWithAccess !== undefined) {
      this.onRequestCloseWithAccess(this.installSurfaceAccessToken);
      return;
    }
    this.onRequestClose();
  }
}
