import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { UserScriptSourceEditScreen } from '../components/userscripts/UserScriptSourceEditScreen';
import { BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY } from '../../core/theme/BrowserThemeStorageKeys';
import {
  sharedPreferencesRepository,
  sharedUserScriptInstallSessionCoordinator
} from '../bootstrap/BrowserAppRuntime';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { AppServiceModeGateService } from '../../services/settings/AppServiceModeGateService';

@Entry
@Component
struct UserScriptSourceEditPage {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  @State private source: string = '';
  private manualSourceEditToken: string = '';

  aboutToAppear(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    const params = router.getParams() as Record<string, string | undefined> | undefined;
    this.manualSourceEditToken = params?.manualSourceEditToken ?? '';
    this.source = sharedUserScriptInstallSessionCoordinator.getManualSourceEditSource(
      this.manualSourceEditToken
    );
  }

  aboutToDisappear(): void {
    sharedUserScriptInstallSessionCoordinator.abandonManualSourceEdit(
      this.manualSourceEditToken
    );
  }

  build() {
    Column() {
      UserScriptSourceEditScreen({
        source: this.source,
        onSourceChange: (source: string) => {
          this.source = source;
          sharedUserScriptInstallSessionCoordinator.editManualSource(this.manualSourceEditToken, source);
        },
        onSave: () => {
          this.saveSource();
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

  private saveSource(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    if (!sharedUserScriptInstallSessionCoordinator.completeManualSourceEdit(
      this.manualSourceEditToken,
      this.source
    )) {
      this.getUIContext().getPromptAction().showToast({
        message: '脚本编辑会话已失效，请返回后重试。',
        duration: 1800
      });
      return;
    }
    router.back();
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.navigationCoordinator.back();
    return false;
  }
}
