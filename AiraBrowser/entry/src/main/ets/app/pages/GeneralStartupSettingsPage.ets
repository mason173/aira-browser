import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserGeneralSettings,
  BrowserStartupRestorePolicy
} from '../../common/models/BrowserModels';
import {
  GeneralStartupRestoreOptionState,
  GeneralStartupSettingsState,
  GeneralStartupSettingsViewModel
} from '../../core/settings/GeneralStartupSettingsViewModel';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
import { SettingsOptionRow } from '../components/settings/SettingsRows';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
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
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { SettingsDetailInteractionCoordinator } from '../../core/settings/SettingsDetailInteractionCoordinator';

@Entry
@Component
struct GeneralStartupSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: GeneralStartupSettingsViewModel = new GeneralStartupSettingsViewModel();
  private interactionCoordinator: SettingsDetailInteractionCoordinator =
    new SettingsDetailInteractionCoordinator(sharedPreferencesRepository);
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private generalSettings: BrowserGeneralSettings = sharedPreferencesRepository.getPreferences().general;
  @State private state: GeneralStartupSettingsState = this.viewModel.buildState(
    sharedPreferencesRepository.getPreferences().general
  );
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';

  aboutToAppear(): void {
    this.syncBoundaryRouteState();
    this.refreshState();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '启动行为',
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
          this.buildStartupSection()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildStartupSection() {
    SettingsSection({
      title: '启动时',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.state.startupOptions, (option: GeneralStartupRestoreOptionState, index: number) => {
          SettingsOptionRow({
            title: option.title,
            rowPosition: this.resolveRowPosition(index, this.state.startupOptions.length),
            isSelected: this.state.startupRestorePolicy === option.policy,
            selectedIndicatorColor: this.storedAccentColor,
            onAction: () => {
              this.updateStartupRestorePolicy(option.policy);
            }
          })
          if (index < this.state.startupOptions.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        })
      }
    }
  }

  private updateStartupRestorePolicy(policy: BrowserStartupRestorePolicy): void {
    if (this.generalSettings.startupRestorePolicy === policy) {
      return;
    }
    const previousSettings = this.generalSettings;
    const nextSettings = this.viewModel.buildGeneralSettingsWithStartupRestorePolicy(this.generalSettings, policy);
    this.applyGeneralSettings(nextSettings, previousSettings);
  }

  private applyGeneralSettings(nextSettings: BrowserGeneralSettings, previousSettings: BrowserGeneralSettings): void {
    this.applyState(nextSettings);
    this.interactionCoordinator.commitGeneralSettings({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    }, nextSettings)
      .then((settings: BrowserGeneralSettings) => {
        this.applyState(settings);
      })
      .catch((_error: Error) => {
        this.applyState(previousSettings);
      });
  }

  private refreshState(): void {
    this.applyState(sharedPreferencesRepository.getPreferences().general);
  }

  private applyState(settings: BrowserGeneralSettings): void {
    this.generalSettings = settings;
    this.state = this.viewModel.buildState(settings);
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
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }
}
