import { BrowserDataBoundaryInput } from '../../../common/models/BrowserModels';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import {
  BrowserWebSecuritySettingId,
  BrowserWebSecuritySettingsCoordinator,
  BrowserWebSecuritySettingsState,
  sharedBrowserWebSecuritySettingsCoordinator
} from '../../../core/settings/BrowserWebSecuritySettingsCoordinator';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from './SettingsLayout';
import { SettingsNavigationRow, SettingsSwitchRow } from './SettingsRows';
import {
  SettingsDesktopDivider,
  SettingsDesktopGroup,
  SettingsDesktopNavigationRow,
  SettingsDesktopSwitchRow
} from './SettingsDesktopRows';

@Component
export struct BrowserWebSecuritySettingsContent {
  private readonly coordinator: BrowserWebSecuritySettingsCoordinator =
    sharedBrowserWebSecuritySettingsCoordinator;
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop desktopPresentation: boolean = false;
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @State private state: BrowserWebSecuritySettingsState = this.coordinator.buildState();
  @State private savingSettingId: string = '';
  onOpenJavaScriptExceptions?: () => void;

  aboutToAppear(): void {
    this.state = this.coordinator.buildState(this.buildBoundary());
  }

  build() {
    Column({ space: 16 }) {
      SettingsSection({ title: '网页安全', secondaryTextColor: this.secondaryTextColor }) {
        this.buildSwitchSurface('始终优先使用 HTTPS', this.state.httpsFirstEnabled, 'https_first')
        SettingsFooterText({
          text: '优先使用安全连接；网站不支持时再使用 HTTP。',
          secondaryTextColor: this.secondaryTextColor
        })
      }

      SettingsSection({ secondaryTextColor: this.secondaryTextColor }) {
        this.buildSwitchSurface('网站安全提醒', this.state.safeBrowsingEnabled, 'safe_browsing')
        SettingsFooterText({
          text: '开启后，Aira 会借助华为安全检测识别可疑网站，并在页面顶部提醒你。为完成检测，你访问的网址会发送给华为。',
          secondaryTextColor: this.secondaryTextColor
        })
      }

      SettingsSection({ secondaryTextColor: this.secondaryTextColor }) {
        this.buildJavaScriptSurface()
        SettingsFooterText({
          text: '网站通常需要 JavaScript 才能正常登录、支付或播放视频；你可以为特定网站设置例外。',
          secondaryTextColor: this.secondaryTextColor
        })
      }

    }
    .width('100%')
  }

  @Builder
  private buildSwitchSurface(title: ResourceStr, checked: boolean, settingId: string) {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.surfaceBackground }) {
        SettingsDesktopSwitchRow({
          title: title,
          checked: checked,
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          hoverBackgroundColor: this.pressedBackground,
          focusColor: this.resolveFocusColor(),
          onChange: (enabled: boolean): void => {
            this.handleSwitchChange(settingId, enabled);
          }
        })
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
        SettingsSwitchRow({
          title: title,
          checked: checked,
          rowPosition: 'single',
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          pressedBackgroundColor: this.pressedBackground,
          onChange: (enabled: boolean): void => {
            this.handleSwitchChange(settingId, enabled);
          }
        })
      }
    }
  }

  @Builder
  private buildJavaScriptSurface() {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.surfaceBackground }) {
        SettingsDesktopSwitchRow({
          title: '允许 JavaScript',
          checked: this.state.javaScriptEnabled,
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          hoverBackgroundColor: this.pressedBackground,
          focusColor: this.resolveFocusColor(),
          onChange: (enabled: boolean): void => {
            this.requestJavaScriptSetting(enabled);
          }
        })
        SettingsDesktopDivider({ dividerColor: this.dividerColor })
        SettingsDesktopNavigationRow({
          title: 'JavaScript 网站例外',
          value: this.resolveJavaScriptExceptionCount(),
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          hoverBackgroundColor: this.pressedBackground,
          focusColor: this.resolveFocusColor(),
          onAction: (): void => {
            this.openJavaScriptSiteExceptions();
          }
        })
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
        SettingsSwitchRow({
          title: '允许 JavaScript',
          checked: this.state.javaScriptEnabled,
          rowPosition: 'first',
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          pressedBackgroundColor: this.pressedBackground,
          onChange: (enabled: boolean): void => {
            this.requestJavaScriptSetting(enabled);
          }
        })
        SettingsGroupDivider({ dividerColor: this.dividerColor })
        SettingsNavigationRow({
          title: 'JavaScript 网站例外',
          value: this.resolveJavaScriptExceptionCount(),
          rowPosition: 'last',
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          pressedBackgroundColor: this.pressedBackground,
          onAction: (): void => {
            this.openJavaScriptSiteExceptions();
          }
        })
      }
    }
  }

  private handleSwitchChange(settingId: string, enabled: boolean): void {
    if (settingId === 'javascript') {
      this.requestJavaScriptSetting(enabled);
      return;
    }
    this.persistSetting(settingId as BrowserWebSecuritySettingId, enabled);
  }

  private resolveJavaScriptExceptionCount(): string {
    return this.state.javaScriptSiteExceptionCount > 0
      ? `${this.state.javaScriptSiteExceptionCount} 个网站`
      : '';
  }

  private resolveFocusColor(): ResourceColor {
    return this.accentColor;
  }

  private requestJavaScriptSetting(enabled: boolean): void {
    if (enabled) {
      this.persistSetting('javascript', true);
      return;
    }
    showCenteredAlertDialog({
      title: '关闭 JavaScript？',
      message: '大多数网站依赖 JavaScript。关闭后，登录、支付、视频和交互内容可能无法正常使用。',
      autoCancel: true,
      primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: {
        value: '仍要关闭',
        action: (): void => this.persistSetting('javascript', false)
      }
    });
  }

  private persistSetting(settingId: BrowserWebSecuritySettingId, enabled: boolean): void {
    if (!this.state.canEditSettings || this.isSaving()) {
      return;
    }
    const previous = this.state;
    this.savingSettingId = settingId;
    this.coordinator.setSetting(settingId, enabled, this.buildBoundary())
      .then((state: BrowserWebSecuritySettingsState): void => {
        this.state = state;
        this.savingSettingId = '';
      })
      .catch((_error: Error): void => {
        this.state = previous;
        this.savingSettingId = '';
      });
  }

  private openJavaScriptSiteExceptions(): void {
    if (!this.state.canEditSettings) {
      return;
    }
    this.onOpenJavaScriptExceptions?.();
  }

  private buildBoundary(): BrowserDataBoundaryInput {
    return {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    };
  }

  private isSaving(): boolean {
    return this.savingSettingId.length > 0;
  }
}
