import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import { HistoryRetentionSettings } from '../../common/models/BrowserModels';
import {
  sharedHistoryRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository
} from '../bootstrap/BrowserAppRuntime';
import { HistoryFeature, HistoryManagementBoundary } from '../../features/history/HistoryFeature';
import { SettingsOptionRow } from '../components/settings/SettingsRows';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';

interface HistoryRetentionOption {
  id: string;
  title: string;
  settings: HistoryRetentionSettings;
}

const HISTORY_RETENTION_OPTIONS: HistoryRetentionOption[] = [
  {
    id: 'off',
    title: '不保存历史',
    settings: { enabled: false, maxAgeDays: 0, maxRows: 0 }
  },
  {
    id: '10000',
    title: '90 天 / 10000 条',
    settings: { enabled: true, maxAgeDays: 90, maxRows: 10000 }
  },
  {
    id: '30_3000',
    title: '30 天 / 3000 条',
    settings: { enabled: true, maxAgeDays: 30, maxRows: 3000 }
  }
];

@Entry
@Component
struct GeneralHistoryRetentionSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private historyFeature: HistoryFeature =
    new HistoryFeature(sharedHistoryRepository, sharedPreferencesRepository, sharedRecentlyClosedTabRepository);
  @State private retentionSettings: HistoryRetentionSettings = sharedPreferencesRepository.getPreferences().historyRetention;
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.syncBoundaryRouteState();
    this.retentionSettings = sharedPreferencesRepository.getPreferences().historyRetention;
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '历史保留',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({ topPadding: 16 }) {
          this.buildSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildSection() {
    SettingsSection({
      title: '保留条数',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(HISTORY_RETENTION_OPTIONS, (option: HistoryRetentionOption, index: number) => {
          SettingsOptionRow({
            title: option.title,
            helperText: '',
            rowPosition: this.resolveRowPosition(index, HISTORY_RETENTION_OPTIONS.length),
            isSelected: this.isSelected(option.settings),
            selectedIndicatorColor: this.storedAccentColor,
            onAction: () => {
              this.updateRetention(option.settings);
            }
          })
          if (index < HISTORY_RETENTION_OPTIONS.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: HistoryRetentionOption) => this.resolveOptionRenderKey(option))
      }

      SettingsFooterText({
        text: '仅影响常规历史记录，私密标签本来不写历史。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  private updateRetention(settings: HistoryRetentionSettings): void {
    if (this.isSelected(settings)) {
      return;
    }
    const previousSettings = this.retentionSettings;
    this.retentionSettings = settings;
    this.historyFeature.updateHistoryRetentionSettingsForBoundary(settings, {
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    })
      .then((saved: HistoryRetentionSettings) => {
        this.retentionSettings = saved;
        return this.historyFeature.applyRetentionPolicyForManagement(
          saved,
          new HistoryManagementBoundary(this.dataScope, this.privacyMode)
        );
      })
      .catch((_error: Error) => {
        this.retentionSettings = previousSettings;
      });
  }

  private isSelected(settings: HistoryRetentionSettings): boolean {
    return this.retentionSettings.enabled === settings.enabled &&
      this.retentionSettings.maxAgeDays === settings.maxAgeDays &&
      this.retentionSettings.maxRows === settings.maxRows;
  }

  private resolveOptionRenderKey(option: HistoryRetentionOption): string {
    return `${this.resolveThemeRenderKey()}:${option.id}:${this.isSelected(option.settings) ? '1' : '0'}`;
  }

  private resolveThemeRenderKey(): string {
    return `${this.storedResolvedThemeMode}:${this.storedPageBackgroundColor}:${this.storedSurfaceBackgroundColor}:` +
      `${this.storedPressedBackgroundColor}:${this.storedAccentColor}:${this.storedPrimaryTextColor}:` +
      `${this.storedSecondaryTextColor}:${this.storedDividerColor}:${this.storedOnAccentColor}`;
  }

  private syncBoundaryRouteState(): void {
    const boundary = readBrowserBoundaryRouteState({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode,
      boundarySource: this.boundarySource
    });
    this.dataScope = boundary.dataScope;
    this.privacyMode = boundary.privacyMode;
    this.boundarySource = boundary.boundarySource;
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
    if (count <= 1) {
      return 'single';
    }
    if (index <= 0) {
      return 'first';
    }
    if (index >= count - 1) {
      return 'last';
    }
    return 'middle';
  }
}
