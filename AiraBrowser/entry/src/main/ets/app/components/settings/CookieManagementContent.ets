import {
  SettingsCookiePolicyMode,
  SettingsSitePolicyCoordinator,
  SettingsSitePolicyMutationResult,
  SettingsSitePolicyState
} from '../../../core/settings/SettingsSitePolicyCoordinator';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { SettingsFooterText, SettingsGroupCard, SettingsGroupDivider } from './SettingsLayout';
import { SettingsOptionRow } from './SettingsRows';

interface CookieManagementOptionState {
  mode: SettingsCookiePolicyMode;
  title: string;
}

@Component
export struct CookieManagementContent {
  private readonly coordinator: SettingsSitePolicyCoordinator =
    new SettingsSitePolicyCoordinator(sharedPreferencesRepository);
  @Prop surfaceBackground: ResourceColor = '';
  @Prop dividerColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackground: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop desktopPresentation: boolean = false;
  @State private state: SettingsSitePolicyState = this.coordinator.buildState();
  @State private isSelectingOption: boolean = false;
  onPolicyApplied?: () => void;

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.refreshState();
  }

  build() {
    Column({ space: 10 }) {
      SettingsGroupCard({
        surfaceColor: this.surfaceBackground,
        desktopPresentation: this.desktopPresentation
      }) {
        ForEach(this.buildOptions(), (option: CookieManagementOptionState, index: number) => {
          SettingsOptionRow({
            title: option.title,
            desktopPresentation: this.desktopPresentation,
            rowPosition: this.resolveRowPosition(index, this.buildOptions().length),
            isSelected: option.mode === this.state.cookiePolicyMode,
            isEnabled: this.isOptionEnabled(option.mode),
            radioGroup: 'cookie-management-policy',
            radioValue: option.mode,
            primaryTextColor: this.primaryTextColor,
            secondaryTextColor: this.secondaryTextColor,
            pressedBackgroundColor: this.pressedBackground,
            selectedIndicatorColor: this.accentColor,
            onAction: (): void => {
              this.requestSelectMode(option.mode);
            }
          })
          if (index < this.buildOptions().length - 1) {
            SettingsGroupDivider({ dividerColor: this.dividerColor })
          }
        }, (option: CookieManagementOptionState): string =>
          `${option.mode}:${option.mode === this.state.cookiePolicyMode ? 'selected' : 'idle'}:` +
            `${this.isSelectingOption ? 'saving' : 'ready'}`)
      }

      SettingsFooterText({
        text: this.resolveFooterText(),
        secondaryTextColor: this.secondaryTextColor
      })
    }
    .width('100%')
  }

  private requestSelectMode(mode: SettingsCookiePolicyMode): void {
    if (!this.isOptionEnabled(mode) || mode === this.state.cookiePolicyMode) {
      return;
    }
    this.isSelectingOption = true;
    this.coordinator.setCookiePolicyMode(mode, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    })
      .then((result: SettingsSitePolicyMutationResult): void => {
        this.isSelectingOption = false;
        this.state = result.state;
        if (result.allowed) {
          this.onPolicyApplied?.();
        }
      })
      .catch((_error: Error): void => {
        this.isSelectingOption = false;
        this.refreshState();
      });
  }

  private refreshState(): void {
    this.state = this.coordinator.buildState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    });
  }

  private buildOptions(): CookieManagementOptionState[] {
    return [
      { mode: 'allow_all', title: '不阻止' },
      { mode: 'block_third_party', title: '仅阻止第三方 Cookie' },
      { mode: 'block_all', title: '阻止所有 Cookie' }
    ];
  }

  private isOptionEnabled(mode: SettingsCookiePolicyMode): boolean {
    if (this.isSelectingOption || !this.state.canEditCookiePolicy) {
      return false;
    }
    return mode !== 'allow_all' || !this.state.thirdPartyCookiePolicyLocked;
  }

  private resolveFooterText(): string {
    if (!this.state.canEditCookiePolicy) {
      return '当前私密会话沿用全局 Cookie 策略，请在常规设置中修改。';
    }
    if (this.state.thirdPartyCookiePolicyLocked) {
      return '增强反跟踪已自动拦截第三方 Cookie。关闭增强反跟踪后，可选择“不阻止”。';
    }
    if (this.state.cookiePolicyMode === 'block_all') {
      return '阻止所有 Cookie 可能导致登录、购物车等网页功能无法正常使用。';
    }
    return '阻止第三方 Cookie 可减少跨网站跟踪，同时兼顾大多数网页的正常使用。';
  }

  private resolveRowPosition(index: number, total: number): 'single' | 'first' | 'middle' | 'last' {
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
}
