import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  BrowserGeneralSettings,
  BrowserTabAutoClosePolicy
} from '../../common/models/BrowserModels';
import {
  GeneralTabAutoCloseOptionState,
  GeneralTabAutoCloseSettingsState,
  GeneralTabAutoCloseSettingsViewModel
} from '../../core/settings/GeneralTabAutoCloseSettingsViewModel';
import { sharedPreferencesRepository } from '../bootstrap/BrowserAppRuntime';
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
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { readBrowserBoundaryRouteState } from '../../common/utils/RouteParamUtils';
import { SettingsDetailInteractionCoordinator } from '../../core/settings/SettingsDetailInteractionCoordinator';

@Entry
@Component
struct GeneralTabAutoCloseSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private viewModel: GeneralTabAutoCloseSettingsViewModel = new GeneralTabAutoCloseSettingsViewModel();
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
  @State private state: GeneralTabAutoCloseSettingsState = this.viewModel.buildState(
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
        title: '自动关闭标签页',
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
      title: '常规标签页',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.state.tabAutoCloseOptions, (option: GeneralTabAutoCloseOptionState, index: number) => {
          SettingsOptionRow({
            title: option.title,
            rowPosition: this.resolveRowPosition(index, this.state.tabAutoCloseOptions.length),
            isSelected: this.state.tabAutoClosePolicy === option.policy,
            selectedIndicatorColor: this.storedAccentColor,
            onAction: () => {
              this.updatePolicy(option.policy);
            }
          })
          if (index < this.state.tabAutoCloseOptions.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: GeneralTabAutoCloseOptionState) => option.policy)
      }
      SettingsFooterText({
        text: this.state.footer,
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  private updatePolicy(policy: BrowserTabAutoClosePolicy): void {
    if (this.generalSettings.tabAutoClosePolicy === policy) {
      return;
    }
    const previousSettings = this.generalSettings;
    const nextSettings = this.viewModel.buildGeneralSettingsWithPolicy(this.generalSettings, policy);
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
