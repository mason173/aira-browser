import { BrowserBottomToolbarScrollBehavior } from '../../common/models/BrowserModels';
import {
  readBrowserBoundaryRouteState,
  readSettingsTargetRouteState
} from '../../common/utils/RouteParamUtils';
import {
  BrowserToolbarCustomizationBoundary,
  BrowserToolbarCustomizationCoordinator
} from '../../core/browser/BrowserToolbarCustomizationCoordinator';
import {
  BrowserToolbarScrollBehaviorOptionState,
  BrowserToolbarScrollBehaviorSettingsState,
  BrowserToolbarScrollBehaviorSettingsViewModel
} from '../../core/settings/BrowserToolbarScrollBehaviorSettingsViewModel';
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
import { SettingsOptionRow, SettingsRowPosition } from '../components/settings/SettingsRows';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  SettingsTargetRevealController,
  SettingsTargetRevealRegion
} from '../components/settings/SettingsTargetReveal';

const TOOLBAR_SCROLL_BEHAVIOR_RADIO_GROUP: string = 'browser-toolbar-scroll-behavior';

@Entry
@Component
struct BrowserToolbarScrollBehaviorSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private settingsScroller: Scroller = new Scroller();
  private viewModel: BrowserToolbarScrollBehaviorSettingsViewModel =
    new BrowserToolbarScrollBehaviorSettingsViewModel();
  private customizationCoordinator: BrowserToolbarCustomizationCoordinator =
    new BrowserToolbarCustomizationCoordinator(sharedPreferencesRepository);
  @State private dataScope: string = '';
  @State private privacyMode: string = '';
  @State private boundarySource: string = '';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string =
    DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @State private state: BrowserToolbarScrollBehaviorSettingsState = this.viewModel.buildState(
    sharedPreferencesRepository.getPreferences().appearance
  );
  @State private saving: boolean = false;
  @State private settingsRevealTargetId: string = '';
  @State private highlightedTargetId: string = '';
  private revealController: SettingsTargetRevealController = new SettingsTargetRevealController(
    (targetId: string): void => {
      this.highlightedTargetId = targetId;
    }
  );

  aboutToAppear(): void {
    this.syncBoundaryRouteState();
    this.settingsRevealTargetId = readSettingsTargetRouteState().settingsRevealTargetId;
    this.refreshState();
    this.revealController.bindScroller(this.settingsScroller);
    this.revealController.request(
      this.settingsRevealTargetId,
      this.settingsRevealTargetId.length > 0 ? 1 : 0
    );
  }

  aboutToDisappear(): void {
    this.revealController.dispose();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: '滚动行为',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({
          topPadding: 16,
          scroller: this.settingsScroller,
          onContentAreaChanged: (area: Area): void => {
            this.revealController.rememberContentArea(area);
          }
        }) {
          SettingsSection({
            title: '网页滚动时',
            secondaryTextColor: this.storedSecondaryTextColor
          }) {
            SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
              ForEach(this.state.options, (
                option: BrowserToolbarScrollBehaviorOptionState,
                index: number
              ) => {
                this.buildOptionRow(option, index)
                if (index < this.state.options.length - 1) {
                  SettingsGroupDivider({ dividerColor: this.storedDividerColor })
                }
              }, (option: BrowserToolbarScrollBehaviorOptionState): string => option.behavior)
            }
            SettingsFooterText({
              text: this.state.footerText,
              secondaryTextColor: this.storedSecondaryTextColor
            })
          }
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildOptionRow(option: BrowserToolbarScrollBehaviorOptionState, index: number) {
    SettingsTargetRevealRegion({
      targetId: `toolbar_scroll_${option.behavior}`,
      highlightedTargetId: this.highlightedTargetId,
      accentColor: this.storedAccentColor,
      onAreaChanged: (targetId: string, area: Area): void => {
        this.revealController.rememberTargetArea(targetId, area);
      }
    }) {
      SettingsOptionRow({
        title: option.title,
        rowPosition: this.resolveRowPosition(index, this.state.options.length),
        isSelected: this.state.behavior === option.behavior,
        isEnabled: !this.saving,
        selectedIndicatorColor: this.storedAccentColor,
        radioGroup: TOOLBAR_SCROLL_BEHAVIOR_RADIO_GROUP,
        radioValue: option.behavior,
        onAction: (): void => {
          this.updateBehavior(option.behavior);
        }
      })
    }
  }

  private updateBehavior(behavior: BrowserBottomToolbarScrollBehavior): void {
    if (this.saving || this.state.behavior === behavior) {
      return;
    }
    const previousState = this.state;
    this.state = this.viewModel.buildStateForBehavior(behavior);
    this.saving = true;
    this.customizationCoordinator.persistScrollBehavior(
      behavior,
      new BrowserToolbarCustomizationBoundary(this.dataScope, this.privacyMode)
    )
      .then((_savedBehavior) => {
        this.saving = false;
        this.refreshState();
      })
      .catch((_error: Error) => {
        this.saving = false;
        this.state = previousState;
      });
  }

  private refreshState(): void {
    this.state = this.viewModel.buildState(sharedPreferencesRepository.getPreferences().appearance);
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

  private resolveRowPosition(index: number, count: number): SettingsRowPosition {
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
