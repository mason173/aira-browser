import promptAction from '@ohos.promptAction';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import { ManualElementHideSiteRulesScreen } from './ManualElementHideSiteRulesScreen';
import {
  ManualElementHideSettingsViewModel,
  ManualElementHideSiteRulesViewState
} from '../../../core/adblock/ManualElementHideSettingsViewModel';
import {
  sharedManualElementHideRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  BrowserThemeViewState,
  BrowserThemeViewStateFactory
} from '../../../core/theme/BrowserThemeViewState';
import { AppServiceModeGateService } from '../../../services/settings/AppServiceModeGateService';
import {
  ManualElementHideSettingsBoundary,
  ManualElementHideSettingsCoordinator,
  ManualElementHideSettingsMutationResult
} from '../../../core/adblock/ManualElementHideSettingsCoordinator';

@Component
export struct ManualElementHideSiteRulesHost {
  private viewModel: ManualElementHideSettingsViewModel = new ManualElementHideSettingsViewModel();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private settingsCoordinator: ManualElementHideSettingsCoordinator =
    new ManualElementHideSettingsCoordinator(sharedManualElementHideRepository);
  private themePreferencesListenerKey: string = '';
  @Prop host: string = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  onBack: () => void = () => {};
  onSiteRemoved: () => void = () => {};
  onRulesChanged: () => void = () => {};
  @State private state: ManualElementHideSiteRulesViewState =
    this.viewModel.buildSiteState(sharedManualElementHideRepository.getSettings(), '');
  @State private theme: BrowserThemeViewState =
    this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());

  aboutToAppear(): void {
    this.bindThemePreferencesUpdates();
    this.refreshState();
  }

  aboutToDisappear(): void {
    this.unbindThemePreferencesUpdates();
  }

  build() {
    ManualElementHideSiteRulesScreen({
      state: this.state,
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      useTopSafeInset: !this.embedded,
      desktopPresentation: this.desktopPresentation,
      pageBackground: this.theme.pageBackground,
      surfaceBackground: this.theme.surfaceBackground,
      pressedBackground: this.theme.pressedBackground,
      dividerColor: this.theme.divider,
      primaryTextColor: this.theme.textPrimary,
      secondaryTextColor: this.theme.textSecondary,
      onSiteEnabledChange: (host: string, enabled: boolean) => {
        this.updateSiteEnabled(host, enabled);
      },
      onDeleteRule: (host: string, ruleId: string, selector: string) => {
        this.confirmDeleteRule(host, ruleId, selector);
      },
      onClearSite: (host: string) => {
        this.confirmClearSite(host);
      },
      onBack: () => {
        this.onBack();
      }
    })
      .width('100%')
      .height('100%')
  }

  private refreshState(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.refreshThemeState();
    this.refreshRules();
  }

  private refreshRules(): void {
    const nextState = this.viewModel.buildSiteState(sharedManualElementHideRepository.getSettings(), this.host);
    this.state = nextState;
    if (!nextState.hasRules) {
      this.onSiteRemoved();
    }
  }

  private refreshThemeState(): void {
    this.theme = this.themeViewStateFactory.build(sharedPreferencesRepository.getPreferences());
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

  private updateSiteEnabled(host: string, enabled: boolean): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.settingsCoordinator.setSiteEnabled(host, enabled, this.buildBoundary())
      .then((result: ManualElementHideSettingsMutationResult) => {
        this.refreshRules();
        if (!result.allowed) {
          this.showToast('当前会话不可修改页面元素清理设置。');
          return;
        }
        this.onRulesChanged();
      })
      .catch((_error: Error) => {
        this.refreshRules();
        this.showToast('更新失败，请稍后再试。');
      });
  }

  private confirmDeleteRule(host: string, ruleId: string, selector: string): void {
    showCenteredAlertDialog({
      title: '删除这条清理规则',
      message: `删除后，这个元素在刷新或再次打开网页时会恢复显示。\n\n${selector}`,
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
          this.deleteRule(host, ruleId);
        }
      }
    });
  }

  private deleteRule(host: string, ruleId: string): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.settingsCoordinator.removeRule(host, ruleId, this.buildBoundary())
      .then((result: ManualElementHideSettingsMutationResult) => {
        this.refreshRules();
        if (!result.allowed) {
          this.showToast('当前会话不可修改页面元素清理设置。');
          return;
        }
        this.onRulesChanged();
        this.showToast(result.changed ? '已删除这条清理规则。' : '没有找到这条清理规则。');
      })
      .catch((_error: Error) => {
        this.refreshRules();
        this.showToast('删除失败，请稍后再试。');
      });
  }

  private confirmClearSite(host: string): void {
    showCenteredAlertDialog({
      title: '清除这个网站的规则',
      message: `清除后，${host} 上被你隐藏的页面元素在刷新或再次打开时会恢复显示。`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: () => {
        }
      },
      secondaryButton: {
        value: '清除',
        fontColor: $r('app.color.permission_blocked'),
        action: () => {
          this.clearSite(host);
        }
      }
    });
  }

  private clearSite(host: string): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.settingsCoordinator.clearSite(host, this.buildBoundary())
      .then((result: ManualElementHideSettingsMutationResult) => {
        if (!result.allowed) {
          this.refreshRules();
          this.showToast('当前会话不可修改页面元素清理设置。');
          return;
        }
        this.onRulesChanged();
        if (result.changed) {
          this.onSiteRemoved();
        } else {
          this.refreshRules();
        }
        this.showToast(result.changed ? '已清除这个网站的清理规则。' : '没有找到这个网站的清理规则。');
      })
      .catch((_error: Error) => {
        this.refreshRules();
        this.showToast('清除失败，请稍后再试。');
      });
  }

  private showToast(message: string): void {
    promptAction.showToast({
      message: message,
      duration: 1800
    });
  }

  private buildBoundary(): ManualElementHideSettingsBoundary {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.onBack();
    return false;
  }
}
