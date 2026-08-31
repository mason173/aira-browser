import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import {
  BrowserAppProxyScheme,
  BrowserExperimentSettings
} from '../../../common/models/BrowserModels';
import { AppProxySettingsViewModel } from '../../../core/settings/AppProxySettingsViewModel';
import { sharedPreferencesRepository } from '../../bootstrap/BrowserAppRuntime';
import { SettingsHdsScaffold } from './SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsPresentationScrollBody
} from './SettingsLayout';
import { SettingsOptionRow } from './SettingsRows';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsDesktopWorkspaceHeader } from './SettingsDesktopWorkspaceHeader';

interface AppProxyProtocolOption {
  scheme: BrowserAppProxyScheme;
  title: string;
  helperText: string;
}

const APP_PROXY_PROTOCOL_OPTIONS: AppProxyProtocolOption[] = [
  {
    scheme: 'http',
    title: 'HTTP',
    helperText: '适合常见本地调试代理。'
  },
  {
    scheme: 'https',
    title: 'HTTPS',
    helperText: '代理服务器入口使用 TLS。'
  },
  {
    scheme: 'socks5',
    title: 'SOCKS5',
    helperText: '适合通用 TCP 代理服务。'
  }
];
const APP_PROXY_PROTOCOL_SELECTION_KEY: string = 'app_proxy_protocol_selection';
const APP_PROXY_PROTOCOL_SELECTION_REVISION_KEY: string = 'app_proxy_protocol_selection_revision';

/**
 * 代理协议选择页的共享主体：手机端由 AppProxyProtocolSettingsPage 全屏承载，大屏端由代理
 * 资料编辑面板就地承载。选择结果仍通过 AppStorage（选中方案 + 修订号）回传给上一层，返回
 * 统一走 onBack。
 */
@Component
export struct AppProxyProtocolSettingsHost {
  private viewModel: AppProxySettingsViewModel = new AppProxySettingsViewModel();
  @Prop embedded: boolean = false;
  @Prop desktopPresentation: boolean = false;
  @Prop profileId: string = '';
  onBack?: () => void;
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private experiments: BrowserExperimentSettings = sharedPreferencesRepository.getPreferences().experiments;
  @State private selectedScheme: BrowserAppProxyScheme = 'http';
  @State private saving: boolean = false;

  aboutToAppear(): void {
    this.experiments = sharedPreferencesRepository.getPreferences().experiments;
    this.selectedScheme = this.resolveInitialScheme();
    this.saving = false;
  }

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '代理协议',
          showBackButton: true,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          onBack: () => {
            this.handleBack();
          }
        })
      }

      SettingsHdsScaffold({
        title: '代理协议',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showBackButton: !this.desktopPresentation,
        showTitleBar: !this.desktopPresentation,
        useTopSafeInset: !this.embedded,
        desktopPresentation: this.desktopPresentation,
        onBack: () => {
          this.handleBack();
        }
      }) {
        SettingsPresentationScrollBody({
          desktopPresentation: this.desktopPresentation,
          topPadding: 16,
          bottomPadding: 22
        }) {
          SettingsGroupCard({
            surfaceColor: this.storedSurfaceBackgroundColor,
            desktopPresentation: this.desktopPresentation
          }) {
            ForEach(APP_PROXY_PROTOCOL_OPTIONS, (option: AppProxyProtocolOption, index: number) => {
              SettingsOptionRow({
                title: option.title,
                desktopPresentation: this.desktopPresentation,
                helperText: option.helperText,
                rowPosition: this.resolveRowPosition(index, APP_PROXY_PROTOCOL_OPTIONS.length),
                isSelected: this.resolveCurrentScheme() === option.scheme,
                isEnabled: !this.saving,
                selectedIndicatorColor: this.storedAccentColor,
                onAction: () => {
                  void this.selectScheme(option.scheme);
                }
              })
              if (index < APP_PROXY_PROTOCOL_OPTIONS.length - 1) {
                SettingsGroupDivider({ dividerColor: this.storedDividerColor })
              }
            }, (option: AppProxyProtocolOption) => this.resolveOptionRenderKey(option))
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  private async selectScheme(scheme: BrowserAppProxyScheme): Promise<void> {
    if (this.saving) {
      return;
    }
    if (this.resolveCurrentScheme() === scheme) {
      this.handleBack();
      return;
    }
    this.saving = true;
    this.selectedScheme = scheme;
    try {
      AppStorage.setOrCreate(APP_PROXY_PROTOCOL_SELECTION_KEY, scheme);
      const revision = AppStorage.get<number>(APP_PROXY_PROTOCOL_SELECTION_REVISION_KEY) ?? 0;
      AppStorage.setOrCreate(APP_PROXY_PROTOCOL_SELECTION_REVISION_KEY, revision + 1);
      this.handleBack();
    } catch (_error) {
      this.saving = false;
      this.showToast('代理协议更新失败。');
    }
  }

  private resolveOptionRenderKey(option: AppProxyProtocolOption): string {
    return `${this.resolveThemeRenderKey()}:${option.scheme}:` +
      `${this.resolveCurrentScheme() === option.scheme ? '1' : '0'}:${this.saving ? '0' : '1'}`;
  }

  private resolveCurrentScheme(): BrowserAppProxyScheme {
    return this.selectedScheme;
  }

  private resolveInitialScheme(): BrowserAppProxyScheme {
    const pendingScheme = AppStorage.get<string>(APP_PROXY_PROTOCOL_SELECTION_KEY) ?? '';
    if (pendingScheme === 'http' || pendingScheme === 'https' || pendingScheme === 'socks5') {
      return pendingScheme;
    }
    const profile = this.viewModel.findProfile(
      this.experiments,
      this.profileId.length > 0 ? this.profileId : this.experiments.appProxyActiveProfileId
    );
    return profile?.settings.scheme ?? this.experiments.appProxy.scheme;
  }

  private resolveThemeRenderKey(): string {
    return `${this.storedResolvedThemeMode}:${this.storedPageBackgroundColor}:${this.storedSurfaceBackgroundColor}:` +
      `${this.storedPressedBackgroundColor}:${this.storedAccentColor}:${this.storedPrimaryTextColor}:` +
      `${this.storedSecondaryTextColor}:${this.storedDividerColor}`;
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private handleBack(): void {
    if (this.onBack !== undefined) {
      this.onBack();
      return;
    }
    router.back();
  }

  private showToast(message: string): void {
    promptAction.showToast({
      message: message,
      duration: 1800
    });
  }
}
