import { pasteboard } from '@kit.BasicServicesKit';
import { showCenteredAlertDialog } from '../components/common/CenteredDialogSurface';
import router from '@ohos.router';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../core/theme/BrowserThemeViewState';
import {
  HuaweiAccountInfoViewModel,
  HuaweiAccountInfoViewState
} from '../../core/settings/HuaweiAccountInfoViewModel';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import { HuaweiAccountInfoContent } from '../components/account/HuaweiAccountInfoContent';
import { SettingsScrollBody } from '../components/settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import {
  sharedAiraSyncConfigStore,
  sharedActivityRepository,
  sharedHuaweiAccountMutationCoordinator,
  sharedMembershipFeature,
  sharedPreferencesRepository
} from '../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';
import { resolveAiraHuaweiAccountIdentity } from '../../common/models/AiraSyncModels';

@Entry
@Component
struct HuaweiAccountInfoPage {
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string = '#FFFFFF';
  private viewModel: HuaweiAccountInfoViewModel = new HuaweiAccountInfoViewModel();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private themePreferencesListenerKey: string = '';
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @State private isBusy: boolean = false;
  @State private state: HuaweiAccountInfoViewState = this.viewModel.buildState(
    sharedAiraSyncConfigStore.getSettings(),
    sharedMembershipFeature.getState()
  );
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  onPageShow(): void {
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '账号信息',
        backIconKind: 'back',
        pageBackground: this.theme.pageBackground,
        headerButtonBackground: this.theme.controlBackground,
        primaryTextColor: this.theme.textPrimary,
        onBack: () => {
          router.back();
        }
      }) {
        SettingsScrollBody({
          contentSpace: 14,
          topPadding: 6,
          bottomPadding: 24
        }) {
          HuaweiAccountInfoContent({
            state: this.state,
            theme: this.theme,
            iconForegroundColor: this.storedSettingsIconForegroundColor,
            isBusy: this.isBusy,
            contentMode: 'page',
            onCopyAccountId: () => {
              this.copyAccountId();
            },
            onRequestSignOut: () => {
              this.confirmSignOut();
            }
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.theme.pageBackground)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  private refreshState(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const boundaryState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
    this.refreshThemeState();
    this.state = this.buildCurrentViewState();
    sharedAiraSyncConfigStore.initialize()
      .then(() => {
        this.state = this.buildCurrentViewState();
        return sharedHuaweiAccountMutationCoordinator.reconcileIdentity(
          this.resolveCurrentHuaweiUid(),
          this.buildDataBoundaryInput()
        );
      })
      .then(() => {
        this.state = this.buildCurrentViewState();
      })
      .catch((_error: Error) => {
      });
  }

  private buildCurrentViewState(): HuaweiAccountInfoViewState {
    const settings = sharedAiraSyncConfigStore.getSettings();
    const uid = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
    const activityState = sharedActivityRepository.getState();
    const activityTotals = activityState.accountUid === uid ? activityState.totals : [];
    return this.viewModel.buildState(
      settings,
      sharedMembershipFeature.getState(),
      activityTotals
    );
  }

  private resolveCurrentHuaweiUid(): string {
    const settings = sharedAiraSyncConfigStore.getSettings();
    return resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
  }

  private confirmSignOut(): void {
    if (!this.state.canSignOut || this.isBusy) {
      return;
    }
    if (!sharedHuaweiAccountMutationCoordinator.canSignOut(this.buildDataBoundaryInput())) {
      this.showToast('请回到普通会话后退出华为账号。');
      return;
    }
    showCenteredAlertDialog({
      title: '退出华为账号吗',
      message: '退出后会关闭书签云同步并清除本机保存的华为账号身份，本机书签不会删除。WebDAV 配置和同步状态会保留。',
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '退出',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.signOutHuaweiAccount();
        }
      }
    });
  }

  private signOutHuaweiAccount(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (this.isBusy) {
      return;
    }
    this.isBusy = true;
    sharedHuaweiAccountMutationCoordinator.signOut(this.buildDataBoundaryInput())
      .then((result) => {
        if (!result.ok) {
          this.showToast(result.message.length > 0 ? result.message : result.title);
          return;
        }
        this.refreshState();
        this.showToast(result.title);
        router.back();
      })
      .catch((error: Error) => {
        this.showToast(error.message.length > 0 ? error.message : '退出失败');
      })
      .finally(() => {
        this.isBusy = false;
      });
  }

  private buildDataBoundaryInput(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private copyAccountId(): void {
    const settings = sharedAiraSyncConfigStore.getSettings();
    const uid = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
    if (uid.length <= 0) {
      this.showToast('当前没有可复制的账号 ID');
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, uid);
      pasteboard.getSystemPasteboard().setData(data)
        .then(() => {
          this.showToast('账号 ID 已复制');
        })
        .catch((_error: Error) => {
          this.showToast('复制失败，请稍后重试');
        });
    } catch (_error) {
      this.showToast('复制失败，请稍后重试');
    }
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
  }

  private showToast(message: string): void {
    this.getUIContext().getPromptAction().showToast({
      message: message,
      duration: 1800
    });
  }

  private bindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length > 0) {
      return;
    }
    this.themePreferencesListenerKey = sharedPreferencesRepository.subscribe((_preferences, scope) => {
      if (scope === 'theme_mode' || scope === 'appearance') {
        this.refreshThemeState();
      }
    });
  }

  private unbindThemePreferencesUpdates(): void {
    if (this.themePreferencesListenerKey.length <= 0) {
      return;
    }
    sharedPreferencesRepository.unsubscribe(this.themePreferencesListenerKey);
    this.themePreferencesListenerKey = '';
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
