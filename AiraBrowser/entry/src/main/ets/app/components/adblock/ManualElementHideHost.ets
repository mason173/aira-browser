import promptAction from '@ohos.promptAction';
import { ManualElementHideSettingsScreen } from './ManualElementHideSettingsScreen';
import { ManualElementHideSiteRulesHost } from './ManualElementHideSiteRulesHost';
import {
  ManualElementHideSettingsViewModel,
  ManualElementHideSettingsViewState
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
import { MANUAL_ELEMENT_HIDE_SITE_RULES_ROUTE } from '../../router/AppRoutes';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';

/**
 * 手动隐藏元素页的共享主体：手机端由 ManualElementHideSettingsPage 全屏承载，大屏端由
 * 设置工作区就地承载。边界通过 @Prop 传入，返回通过 onBack 回调。
 */
@Component
export struct ManualElementHideHost {
  private viewModel: ManualElementHideSettingsViewModel = new ManualElementHideSettingsViewModel();
  private themeViewStateFactory: BrowserThemeViewStateFactory = new BrowserThemeViewStateFactory();
  private appServiceModeGateService: AppServiceModeGateService =
    new AppServiceModeGateService(sharedPreferencesRepository);
  private themePreferencesListenerKey: string = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop boundarySource: string = '';
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop @Watch('refreshState') refreshRevision: number = 0;
  onBack?: () => void;
  @State private state: ManualElementHideSettingsViewState =
    this.viewModel.buildState(sharedManualElementHideRepository.getSettings());
  @State private selectedHost: string = '';
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
    Column() {
      if (this.desktopPresentation && this.embedded) {
        SettingsDesktopWorkspaceHeader({
          title: this.selectedHost.length > 0 ? this.selectedHost : '已清理页面元素',
          showBackButton: true,
          primaryTextColor: this.theme.textPrimary,
          iconColor: this.theme.textSecondary,
          buttonBackgroundColor: this.theme.controlBackground,
          onBack: () => {
            if (this.selectedHost.length > 0) {
              this.closeSiteRules();
              return;
            }
            this.onBack?.();
          }
        })
      }

      if (this.embedded && this.selectedHost.length > 0) {
        ManualElementHideSiteRulesHost({
          host: this.selectedHost,
          dataScope: this.dataScope,
          privacyMode: this.privacyMode,
          boundarySource: this.boundarySource,
          embedded: true,
          desktopPresentation: this.desktopPresentation,
          onBack: () => {
            this.closeSiteRules();
          },
          onSiteRemoved: () => {
            this.closeSiteRules();
          },
          onRulesChanged: () => {
            this.refreshList();
          }
        })
          .layoutWeight(1)
          .width('100%')
      } else {
        ManualElementHideSettingsScreen({
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
          onOpenSite: (host: string) => {
            this.openSiteRules(host);
          },
          onBack: () => {
            this.onBack?.();
          }
        })
          .layoutWeight(1)
          .width('100%')
      }
    }
    .width('100%')
    .height('100%')
  }

  private refreshState(): void {
    if (!this.ensureOptionalServiceRoute()) {
      return;
    }
    this.refreshThemeState();
    this.refreshList();
  }

  private refreshList(): void {
    this.state = this.viewModel.buildState(sharedManualElementHideRepository.getSettings());
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

  private openSiteRules(host: string): void {
    const nextState = this.viewModel.buildSiteState(sharedManualElementHideRepository.getSettings(), host);
    if (!nextState.hasRules) {
      this.refreshList();
      return;
    }
    if (this.embedded) {
      this.selectedHost = nextState.host;
      return;
    }
    const router = this.getUIContext().getRouter();
    router.pushUrl({
      url: MANUAL_ELEMENT_HIDE_SITE_RULES_ROUTE,
      params: {
        host: nextState.host,
        dataScope: this.dataScope,
        privacyMode: this.privacyMode,
        boundarySource: this.boundarySource
      }
    }).catch((_error: Error) => {
      this.showToast('无法打开网站清理规则，请稍后再试。');
    });
  }

  private closeSiteRules(): void {
    this.selectedHost = '';
    this.refreshList();
  }

  private showToast(message: string): void {
    promptAction.showToast({
      message: message,
      duration: 1800
    });
  }

  private ensureOptionalServiceRoute(): boolean {
    if (this.appServiceModeGateService.canUseOptionalService()) {
      return true;
    }
    this.onBack?.();
    return false;
  }
}
