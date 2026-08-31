import {
  BrowserAppearanceSettings,
  BrowserThemePaletteId
} from '../../../common/models/BrowserModels';
import {
  BrowserThemePaletteViewModel,
  ThemePaletteOptionGroupState,
  ThemePaletteOptionState,
  ThemePaletteSettingsState
} from '../../../core/theme/BrowserThemePaletteViewModel';
import {
  sharedBrowserThemeModeCoordinator,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsPresentationScrollBody,
  SettingsSectionTitle
} from './SettingsLayout';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { SettingsDetailInteractionCoordinator } from '../../../core/settings/SettingsDetailInteractionCoordinator';

const THEME_PALETTE_CARD_CORNER_RADIUS: number = 22;
const THEME_PALETTE_GRID_GAP: number = 12;
const THEME_PALETTE_RADIO_GROUP: string = 'theme-palette-options-embedded';

/**
 * Large-screen embedded body of the theme palette page (no page scaffold / back
 * bar). Selecting a palette applies immediately and stays on the grid; the
 * settings workspace header owns the back action. Phone keeps using
 * ThemePaletteSettingsPage untouched.
 */
@Component
export struct ThemePaletteSettingsContent {
  private viewModel: BrowserThemePaletteViewModel = new BrowserThemePaletteViewModel();
  private interactionCoordinator: SettingsDetailInteractionCoordinator =
    new SettingsDetailInteractionCoordinator(sharedPreferencesRepository);
  @Prop dataScope: string = '';
  @Prop privacyMode: string = '';
  @Prop desktopPresentation: boolean = false;
  @State private state: ThemePaletteSettingsState =
    this.viewModel.buildState(
      sharedPreferencesRepository.getPreferences().appearance.themePaletteId,
      sharedBrowserThemeModeCoordinator.resolveEffectiveMode(),
      '',
      ''
    );
  @State private isSelectingOption: boolean = false;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('refreshState')
  private storedResolvedThemeMode: string = 'light';

  aboutToAppear(): void {
    this.isSelectingOption = false;
    this.refreshState();
  }

  build() {
    SettingsPresentationScrollBody({
      contentSpace: 18,
      desktopPresentation: this.desktopPresentation,
      bottomPadding: 22
    }) {
      this.buildContent()
    }
  }

  @Builder
  private buildContent() {
    ForEach(this.state.groups, (group: ThemePaletteOptionGroupState) => {
      this.buildPaletteGroup(group)
    }, (group: ThemePaletteOptionGroupState) => `${this.resolveThemeRenderKey()}:${group.id}`)
  }

  @Builder
  private buildPaletteGroup(group: ThemePaletteOptionGroupState) {
    Column({ space: 8 }) {
      SettingsSectionTitle({
        title: group.title,
        secondaryTextColor: this.state.textSecondary,
        leftPadding: 2
      })

      Grid() {
        ForEach(group.options, (option: ThemePaletteOptionState) => {
          GridItem() {
            this.buildPaletteOption(option)
          }
        }, (option: ThemePaletteOptionState) => `${this.resolveThemeRenderKey()}:${option.id}`)
      }
      .width('100%')
      .columnsTemplate('1fr 1fr')
      .columnsGap(THEME_PALETTE_GRID_GAP)
      .rowsGap(THEME_PALETTE_GRID_GAP)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildPaletteOption(option: ThemePaletteOptionState) {
    Row({ space: 10 }) {
      Stack() {
        Row()
          .width(34)
          .height(34)
          .borderRadius(17)
          .backgroundColor(option.previewColor)

        Column()
          .width(16)
          .height(16)
          .borderRadius(8)
          .backgroundColor(option.darkPreviewColor)
          .position({ x: 22, y: 22 })
      }
      .width(42)
      .height(42)

      Column() {
        Text(option.title)
          .width('100%')
          .fontSize(15)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Bold)
          .fontColor(this.state.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({
        value: option.id,
        group: THEME_PALETTE_RADIO_GROUP
      })
        .checked(option.isSelected)
        .enabled(this.isPaletteOptionInteractive())
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({
          checkedBackgroundColor: this.state.accentColor
        })
    }
    .width('100%')
    .padding({ left: 12, right: 10, top: 12, bottom: 12 })
    .borderRadius(this.desktopPresentation ? 8 : THEME_PALETTE_CARD_CORNER_RADIUS)
    .backgroundColor(this.state.surfaceBackground)
    .alignItems(VerticalAlign.Center)
    .opacity(this.isPaletteOptionInteractive() ? 1 : 0.48)
    .onClick(() => {
      if (this.isPaletteOptionInteractive()) {
        this.requestSelectPalette(option.id);
      }
    })
  }

  private isPaletteOptionInteractive(): boolean {
    return !this.isSelectingOption;
  }

  private refreshState(): void {
    const preferences = sharedPreferencesRepository.getPreferences();
    this.state = this.viewModel.buildState(
      preferences.appearance.themePaletteId,
      sharedBrowserThemeModeCoordinator.resolveEffectiveMode(preferences.themeMode),
      this.dataScope,
      this.privacyMode
    );
  }

  private resolveThemeRenderKey(): string {
    return `${this.storedResolvedThemeMode}:${this.state.pageBackground}:${this.state.surfaceBackground}:` +
      `${this.state.controlBackground}:${this.state.accentColor}:${this.state.textPrimary}:` +
      `${this.state.textSecondary}`;
  }

  private requestSelectPalette(paletteId: BrowserThemePaletteId): void {
    if (this.isSelectingOption) {
      return;
    }
    const currentSettings = sharedPreferencesRepository.getPreferences().appearance;
    if (currentSettings.themePaletteId === paletteId) {
      return;
    }
    const nextSettings: BrowserAppearanceSettings = {
      bottomToolbarScrollBehavior: currentSettings.bottomToolbarScrollBehavior,
      globalImmersionEnabled: currentSettings.globalImmersionEnabled,
      alwaysTopImmersionEnabled: currentSettings.alwaysTopImmersionEnabled,
      forceDarkWebContentEnabled: currentSettings.forceDarkWebContentEnabled,
      blurPrivateTabPreviews: currentSettings.blurPrivateTabPreviews,
      showHomeRecentlyClosed: currentSettings.showHomeRecentlyClosed,
      showHomeShortcuts: currentSettings.showHomeShortcuts,
      homeRecentlyClosedLimit: currentSettings.homeRecentlyClosedLimit,
      homeShortcutLayoutDensity: currentSettings.homeShortcutLayoutDensity,
      homeShortcutIconSizeRatio: currentSettings.homeShortcutIconSizeRatio,
      siteIconCornerRadiusRatio: currentSettings.siteIconCornerRadiusRatio,
      themePaletteId: paletteId,
      tabsOverviewLayoutStyle: currentSettings.tabsOverviewLayoutStyle,
      tabsOverviewCloseButtonAlwaysVisible: currentSettings.tabsOverviewCloseButtonAlwaysVisible,
      showDesktopBookmarkBar: currentSettings.showDesktopBookmarkBar
    };
    this.isSelectingOption = true;
    this.interactionCoordinator.commitAppearanceSettings({
      dataScope: this.dataScope,
      privacyMode: this.privacyMode
    }, nextSettings)
      .then((appearance: BrowserAppearanceSettings) => {
        this.isSelectingOption = false;
        this.state = this.viewModel.buildState(
          appearance.themePaletteId,
          sharedBrowserThemeModeCoordinator.resolveEffectiveMode(),
          this.dataScope,
          this.privacyMode
        );
      })
      .catch((_error: Error) => {
        this.isSelectingOption = false;
        this.refreshState();
        this.showToast('主题色更新失败。');
      });
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
