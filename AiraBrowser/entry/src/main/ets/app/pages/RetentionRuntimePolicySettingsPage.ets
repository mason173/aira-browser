import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import { BrowserRetentionProfileId } from '../../common/models/BrowserModels';
import {
  BrowserBoundaryRouteState,
  readBrowserBoundaryRouteState
} from '../../common/utils/RouteParamUtils';
import { BrowserRetentionSettingsCoordinator } from '../../core/settings/BrowserRetentionSettingsCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import { SettingsOptionRow } from '../components/settings/SettingsRows';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

interface RetentionRuntimePolicyOption {
  id: BrowserRetentionProfileId;
  title: string;
  helperText: string;
}

const RETENTION_RUNTIME_POLICY_RADIO_GROUP: string = 'retention-runtime-policy';
const RETENTION_RUNTIME_POLICY_OPTIONS: RetentionRuntimePolicyOption[] = [
  {
    id: 'memory_saver',
    title: '省电优先',
    helperText: '更快释放后台标签页，适合低内存、发热或耗电明显时使用'
  },
  {
    id: 'balanced',
    title: '均衡',
    helperText: '日常推荐，兼顾切回速度、内存占用和耗电'
  },
  {
    id: 'keep_more_tabs',
    title: '多标签性能',
    helperText: '平时保留更多后台标签页，切回更快但更耗内存和电量'
  }
];

@Entry
@Component
struct RetentionRuntimePolicySettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private retentionSettingsCoordinator: BrowserRetentionSettingsCoordinator =
    new BrowserRetentionSettingsCoordinator(sharedPreferencesRepository);
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private selectedProfileId: BrowserRetentionProfileId =
    sharedPreferencesRepository.getPreferences().retention.profileId;
  @State private isSelectingOption: boolean = false;
  @State private isLeaving: boolean = false;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.isLeaving = false;
    this.syncBoundaryRouteState();
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '标签页运行策略',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showPrivateIndicator: this.isPrivateContext(),
        onBack: () => {
          this.handleBack();
        }
      }) {
        SettingsScrollBody({ topPadding: 16, bottomPadding: 28 }) {
          this.buildContent()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildContent() {
    SettingsSection({
      title: '后台标签页资源管理',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(RETENTION_RUNTIME_POLICY_OPTIONS, (option: RetentionRuntimePolicyOption, index: number) => {
          SettingsOptionRow({
            title: option.title,
            helperText: option.helperText,
            rowPosition: this.resolveRowPosition(index, RETENTION_RUNTIME_POLICY_OPTIONS.length),
            isSelected: option.id === this.selectedProfileId,
            isEnabled: !this.isSelectingOption && !this.isLeaving,
            primaryTextColor: this.storedPrimaryTextColor,
            secondaryTextColor: this.storedSecondaryTextColor,
            pressedBackgroundColor: this.storedPressedBackgroundColor,
            selectedIndicatorColor: this.storedAccentColor,
            radioGroup: RETENTION_RUNTIME_POLICY_RADIO_GROUP,
            radioValue: option.id,
            onAction: () => {
              this.requestSelectProfile(option.id);
            }
          })
          if (index < RETENTION_RUNTIME_POLICY_OPTIONS.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: RetentionRuntimePolicyOption) => this.resolveOptionRenderKey(option))
      }

      SettingsFooterText({
        text: '这是平时的保活偏好。系统内存紧张时，Aira 会临时降低后台保活数量；前台标签页和受保护任务不会被普通回收策略释放。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  private syncBoundaryRouteState(): void {
    const boundaryState: BrowserBoundaryRouteState = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundaryState.dataScope;
    this.privacyMode = boundaryState.privacyMode;
    this.boundarySource = boundaryState.boundarySource;
  }

  private refreshState(): void {
    this.selectedProfileId = sharedPreferencesRepository.getPreferences().retention.profileId;
  }

  private requestSelectProfile(profileId: BrowserRetentionProfileId): void {
    if (this.isSelectingOption || this.isLeaving) {
      return;
    }
    if (profileId === this.selectedProfileId) {
      this.handleBack();
      return;
    }
    this.isSelectingOption = true;
    this.retentionSettingsCoordinator.applyProfile(profileId, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    })
      .then((result) => {
        this.selectedProfileId = result.settings.profileId;
        this.handleBack();
      })
      .catch((_error: Error) => {
        this.isSelectingOption = false;
        this.refreshState();
        this.showToast('标签页运行策略更新失败。');
      });
  }

  private isPrivateContext(): boolean {
    return this.dataScope === 'session_ephemeral' || this.privacyMode === 'private';
  }

  private resolveOptionRenderKey(option: RetentionRuntimePolicyOption): string {
    return `${option.id}:${option.id === this.selectedProfileId ? 'selected' : 'idle'}:` +
      `${this.storedPageBackgroundColor}:${this.storedSurfaceBackgroundColor}:${this.storedPrimaryTextColor}:` +
      `${this.storedSecondaryTextColor}:${this.storedAccentColor}`;
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

  private handleBack(): boolean {
    if (this.isLeaving) {
      return true;
    }
    this.isLeaving = true;
    this.navigationCoordinator.back();
    return true;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }
}
