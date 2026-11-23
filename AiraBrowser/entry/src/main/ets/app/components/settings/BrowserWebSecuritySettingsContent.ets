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
      SettingsSection({ title: $r('app.string.settings_privacy_protection_web_security'), secondaryTextColor: this.secondaryTextColor }) {
        this.buildSwitchSurface($r('app.string.settings_privacy_protection_https_first'), 'https_first')
        SettingsFooterText({
          text: $r('app.string.settings_privacy_protection_https_first_footer'),
          secondaryTextColor: this.secondaryTextColor
        })
      }

      SettingsSection({ secondaryTextColor: this.secondaryTextColor }) {
        this.buildSwitchSurface($r('app.string.settings_privacy_protection_safe_browsing'), 'safe_browsing')
        SettingsFooterText({
          text: $r('app.string.settings_privacy_protection_safe_browsing_footer'),
          secondaryTextColor: this.secondaryTextColor
        })
      }

      SettingsSection({ secondaryTextColor: this.secondaryTextColor }) {
        this.buildJavaScriptSurface()
        SettingsFooterText({
          text: $r('app.string.settings_privacy_protection_javascript_footer'),
          secondaryTextColor: this.secondaryTextColor
        })
      }

    }
    .width('100%')
  }

  @Builder
  private buildSwitchSurface(title: ResourceStr, settingId: 'https_first' | 'safe_browsing') {
    if (this.desktopPresentation) {
      SettingsDesktopGroup({ surfaceColor: this.surfaceBackground }) {
        SettingsDesktopSwitchRow({
          title: title,
          checked: settingId === 'https_first' ? this.state.httpsFirstEnabled : this.state.safeBrowsingEnabled,
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          hoverBackgroundColor: this.pressedBackground,
          focusColor: this.resolveFocusColor(),
          onChange: (enabled: boolean): void => {
            this.persistSetting(settingId, enabled);
          }
        })
      }
    } else {
      SettingsGroupCard({ surfaceColor: this.surfaceBackground }) {
        SettingsSwitchRow({
          title: title,
          checked: settingId === 'https_first' ? this.state.httpsFirstEnabled : this.state.safeBrowsingEnabled,
          rowPosition: 'single',
          isEnabled: this.state.canEditSettings && !this.isSaving(),
          primaryTextColor: this.primaryTextColor,
          secondaryTextColor: this.secondaryTextColor,
          pressedBackgroundColor: this.pressedBackground,
          onChange: (enabled: boolean): void => {
            this.persistSetting(settingId, enabled);
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
          title: $r('app.string.settings_privacy_protection_javascript'),
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
          title: $r('app.string.settings_privacy_protection_javascript_exceptions'),
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
          title: $r('app.string.settings_privacy_protection_javascript'),
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
          title: $r('app.string.settings_privacy_protection_javascript_exceptions'),
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

  private resolveJavaScriptExceptionCount(): ResourceStr {
    return this.state.javaScriptSiteExceptionCount > 0
      ? $r('app.string.settings_privacy_protection_javascript_count', this.state.javaScriptSiteExceptionCount)
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
      title: $r('app.string.settings_privacy_protection_javascript_off_title'),
      message: $r('app.string.settings_privacy_protection_javascript_off_message'),
      autoCancel: true,
      primaryButton: { value: $r('app.string.settings_privacy_protection_dialog_cancel'), action: (): void => {} },
      secondaryButton: {
        value: $r('app.string.settings_privacy_protection_javascript_off_confirm'),
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
