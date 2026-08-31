import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import router from '@ohos.router';
import { UserScriptDetailScreen } from '../components/userscripts/UserScriptDetailScreen';
import { UserScriptDetailState } from '../../core/userscripts/UserScriptDetailViewModel';
import {
  UserScriptManagementAction,
  UserScriptManagementEffect,
  UserScriptManagementSessionCoordinator,
  UserScriptManagementSurfaceFacts,
  UserScriptManagementTransition
} from '../../core/userscripts/UserScriptManagementSessionCoordinator';
import {
  createUserScriptManagementSessionCoordinator,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';
import { USER_SCRIPTS_ROUTE } from '../router/AppRoutes';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';

@Entry
@Component
struct UserScriptDetailPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private managementSession: UserScriptManagementSessionCoordinator = createUserScriptManagementSessionCoordinator();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private scriptId: string = '';
  private dataScope: string = '';
  private privacyMode: string = '';
  private boundarySource: string = '';
  @State private state: UserScriptDetailState = this.managementSession.detailSnapshot('');

  aboutToAppear(): void {
    this.resolveRouteParams();
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.managementSession.activate(new UserScriptManagementSurfaceFacts(true, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      loggedIn: true
    }));
    this.managementSession.setObserver((transition: UserScriptManagementTransition): void => {
      this.applyManagementTransition(transition);
    });
  }

  onPageShow(): void {
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.managementSession.setObserver(undefined);
  }

  build() {
    Column() {
      UserScriptDetailScreen({
        state: this.state,
        onToggleScript: (enabled: boolean) => {
          this.toggleScript(enabled);
        },
        onOpenExtensionsPage: () => {
          this.openExtensionsPage();
        },
        onDeleteScript: () => {
          this.confirmDeleteScript();
        }
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  private resolveRouteParams(): void {
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.scriptId = String(params?.scriptId ?? '').trim();
    const boundary = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundary.dataScope;
    this.privacyMode = boundary.privacyMode;
    this.boundarySource = boundary.boundarySource;
  }

  private refreshState(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.state = this.managementSession.detailSnapshot(this.scriptId);
  }

  private toggleScript(enabled: boolean): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.scriptId.length === 0) {
      return;
    }
    this.managementSession.action(UserScriptManagementAction.toggleScript(this.scriptId, enabled));
  }

  private openExtensionsPage(): void {
    router.pushUrl({
      url: USER_SCRIPTS_ROUTE,
      params: {
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      }
    }).catch((_error: Error) => {});
  }

  private confirmDeleteScript(): void {
    if (this.scriptId.length === 0) {
      return;
    }
    this.managementSession.action(UserScriptManagementAction.requestDeleteScript(this.scriptId));
  }

  private showDeleteScriptDialog(scriptId: string, scriptName: string): void {
    showCenteredAlertDialog({
      title: '删除用户脚本',
      message: `确定删除“${scriptName}”吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.deleteScript(scriptId);
        }
      }
    });
  }

  private deleteScript(scriptId: string): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.managementSession.action(UserScriptManagementAction.deleteScript(scriptId));
  }

  private applyManagementTransition(transition: UserScriptManagementTransition): void {
    this.refreshState();
    transition.effects.forEach((effect: UserScriptManagementEffect): void => {
      if (effect.kind === 'confirm_delete_script') {
        this.showDeleteScriptDialog(effect.scriptId, effect.scriptName);
        return;
      }
      if (effect.kind === 'script_deleted' && effect.scriptId === this.scriptId) {
        router.back();
      }
    });
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
