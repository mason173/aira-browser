import {
  HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY,
  HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY
} from '../../../common/constants/HomePagePresentationStorageKeys';
import {
  HOME_RECENTLY_CLOSED_LIMIT_OPTIONS,
  HomePageSettingsCoordinator,
  HomePageSettingsSnapshot
} from '../../../core/settings/HomePageSettingsCoordinator';
import {
  HOME_SHORTCUT_ICON_SIZE_MAX_RATIO,
  HOME_SHORTCUT_ICON_SIZE_MIN_RATIO,
  SITE_ICON_CORNER_RADIUS_MAX_RATIO,
  SITE_ICON_CORNER_RADIUS_MIN_RATIO,
  SiteIconAppearanceSettingsViewModel
} from '../../../core/settings/SiteIconAppearanceSettingsViewModel';
import {
  BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
  BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  sharedCustomHomepageRepository,
  sharedHomePagePresentationSettingsRepository,
  sharedPreferencesRepository
} from '../../bootstrap/BrowserAppRuntime';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsSection
} from './SettingsLayout';
import { SettingsNavigationRow, SettingsSwitchRow } from './SettingsRows';

const HOME_ICON_SIZE_SLIDER_MIN: number = Math.round(HOME_SHORTCUT_ICON_SIZE_MIN_RATIO * 100);
const HOME_ICON_SIZE_SLIDER_MAX: number = Math.round(HOME_SHORTCUT_ICON_SIZE_MAX_RATIO * 100);
const HOME_ICON_RADIUS_SLIDER_MIN: number = Math.round(SITE_ICON_CORNER_RADIUS_MIN_RATIO * 100);
const HOME_ICON_RADIUS_SLIDER_MAX: number = Math.round(SITE_ICON_CORNER_RADIUS_MAX_RATIO * 100);
const HOME_SETTINGS_SLIDER_HEIGHT: number = 40;
const HOME_SETTINGS_SLIDER_TRACK_THICKNESS: number = 20;
const HOME_SETTINGS_SLIDER_TRACK_RADIUS: number = 10;
const HOME_SETTINGS_SLIDER_BLOCK_SIZE: number = 16;

@Component
export struct HomeNativeSettingsContent {
  private coordinator: HomePageSettingsCoordinator = new HomePageSettingsCoordinator(
    sharedPreferencesRepository,
    sharedCustomHomepageRepository,
    sharedHomePagePresentationSettingsRepository
  );
  private iconAppearanceViewModel: SiteIconAppearanceSettingsViewModel =
    new SiteIconAppearanceSettingsViewModel();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop isEnabled: boolean = true;
  @Prop iconAppearanceEnabled: boolean = true;
  @Prop wallpaperLabel: string = '跟随主题色';
  @Prop @Watch('refreshState') refreshRevision: number = 0;
  onSettingsChanged?: () => void;
  onOpenWallpaperSettings: () => void = () => {};
  @State private settingsBusy: boolean = false;
  @State private showFavorites: boolean = true;
  @State private compactFavorites: boolean = false;
  @State private showFavoritesTitle: boolean = true;
  @State private iconSizeRatio: number = 0.54;
  @State private iconCornerRadiusRatio: number = 0.3;
  @State private showShortcutNames: boolean = true;
  @State private showRecentlyClosed: boolean = true;
  @State private showRecentlyClosedTitle: boolean = true;
  @State private recentlyClosedLimit: number = 8;
  @State private showSystemSearch: boolean = true;
  @State private hideSystemSearchOnScroll: boolean = true;
  @State private showSettingsButton: boolean = true;

  aboutToAppear(): void {
    this.refreshState();
  }

  build() {
    Column({ space: 16 }) {
      this.buildWallpaperSection()
      this.buildFavoritesSection()
      this.buildRecentlyClosedSection()
      this.buildSystemSearchSection()
      this.buildSettingsButtonSection()
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private buildWallpaperSection() {
    SettingsSection({
      title: '主页外观',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsNavigationRow({
          title: '壁纸设置',
          value: this.wallpaperLabel,
          rowPosition: 'single',
          isEnabled: this.resolveControlEnabled(),
          primaryTextColor: this.storedPrimaryTextColor,
          secondaryTextColor: this.storedSecondaryTextColor,
          onAction: () => {
            this.onOpenWallpaperSettings();
          }
        })
      }
    }
  }

  @Builder
  private buildFavoritesSection() {
    SettingsSection({
      title: '收藏设置',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '显示收藏',
          checked: this.showFavorites,
          rowPosition: 'first',
          isEnabled: this.resolveControlEnabled(),
          onChange: (checked: boolean) => {
            const decision = this.coordinator.resolveRecoveryEntryChange('favorites', checked);
            if (!decision.allowed) {
              this.showToast(decision.message);
              return;
            }
            this.showFavorites = checked;
            this.commit(this.coordinator.setFavoritesVisible(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '收藏紧凑排列',
          checked: this.compactFavorites,
          rowPosition: 'middle',
          isEnabled: this.resolveDependentControlEnabled(this.showFavorites),
          onChange: (checked: boolean) => {
            this.compactFavorites = checked;
            this.commit(this.coordinator.setCompactFavorites(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '显示分区标题',
          checked: this.showFavoritesTitle,
          rowPosition: 'middle',
          isEnabled: this.resolveDependentControlEnabled(this.showFavorites),
          onChange: (checked: boolean) => {
            this.showFavoritesTitle = checked;
            AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY, checked);
            this.commit(this.coordinator.setFavoritesTitleVisible(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '显示图标名称',
          checked: this.showShortcutNames,
          rowPosition: 'middle',
          isEnabled: this.resolveDependentControlEnabled(this.showFavorites),
          onChange: (checked: boolean) => {
            this.showShortcutNames = checked;
            AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY, checked);
            this.commit(this.coordinator.setShortcutNamesVisible(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        this.buildIconSizeSlider()
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        this.buildIconRadiusSlider()
      }

      SettingsFooterText({
        text: '关闭分区标题后，收藏会保持展开。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildIconSizeSlider() {
    Column({ space: 12 }) {
      Row() {
        Text('主页图标大小')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .layoutWeight(1)

        Text(`${this.iconAppearanceViewModel.ratioToSliderValue(this.iconSizeRatio)}%`)
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')

      Slider({
        value: this.iconAppearanceViewModel.ratioToSliderValue(this.iconSizeRatio),
        min: HOME_ICON_SIZE_SLIDER_MIN,
        max: HOME_ICON_SIZE_SLIDER_MAX,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .height(HOME_SETTINGS_SLIDER_HEIGHT)
        .enabled(this.resolveIconControlEnabled())
        .opacity(this.resolveIconControlEnabled() ? 1 : 0.48)
        .selectedColor(this.storedAccentColor)
        .blockColor(this.storedOnAccentColor)
        .trackColor(this.storedControlBackgroundColor)
        .trackThickness(HOME_SETTINGS_SLIDER_TRACK_THICKNESS)
        .trackBorderRadius(HOME_SETTINGS_SLIDER_TRACK_RADIUS)
        .selectedBorderRadius(HOME_SETTINGS_SLIDER_TRACK_RADIUS)
        .blockSize({ width: HOME_SETTINGS_SLIDER_BLOCK_SIZE, height: HOME_SETTINGS_SLIDER_BLOCK_SIZE })
        .onChange((value: number, mode: SliderChangeMode) => {
          const ratio = this.iconAppearanceViewModel.sliderValueToIconSizeRatio(value);
          this.iconSizeRatio = ratio;
          AppStorage.setOrCreate(BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY, ratio);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.commit(this.coordinator.setIconSizeRatio(ratio));
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  private buildIconRadiusSlider() {
    Column({ space: 12 }) {
      Row() {
        Text('图标圆角')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .layoutWeight(1)

        Text(`${this.iconAppearanceViewModel.ratioToSliderValue(this.iconCornerRadiusRatio)}%`)
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')

      Slider({
        value: this.iconAppearanceViewModel.ratioToSliderValue(this.iconCornerRadiusRatio),
        min: HOME_ICON_RADIUS_SLIDER_MIN,
        max: HOME_ICON_RADIUS_SLIDER_MAX,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .height(HOME_SETTINGS_SLIDER_HEIGHT)
        .enabled(this.resolveIconControlEnabled())
        .opacity(this.resolveIconControlEnabled() ? 1 : 0.48)
        .selectedColor(this.storedAccentColor)
        .blockColor(this.storedOnAccentColor)
        .trackColor(this.storedControlBackgroundColor)
        .trackThickness(HOME_SETTINGS_SLIDER_TRACK_THICKNESS)
        .trackBorderRadius(HOME_SETTINGS_SLIDER_TRACK_RADIUS)
        .selectedBorderRadius(HOME_SETTINGS_SLIDER_TRACK_RADIUS)
        .blockSize({ width: HOME_SETTINGS_SLIDER_BLOCK_SIZE, height: HOME_SETTINGS_SLIDER_BLOCK_SIZE })
        .onChange((value: number, mode: SliderChangeMode) => {
          const ratio = this.iconAppearanceViewModel.sliderValueToCornerRadiusRatio(value);
          this.iconCornerRadiusRatio = ratio;
          AppStorage.setOrCreate(BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY, ratio);
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.commit(this.coordinator.setIconCornerRadiusRatio(ratio));
          }
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  private buildRecentlyClosedSection() {
    SettingsSection({
      title: '最近关闭',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '显示最近关闭',
          checked: this.showRecentlyClosed,
          rowPosition: 'first',
          isEnabled: this.resolveControlEnabled(),
          onChange: (checked: boolean) => {
            const decision = this.coordinator.resolveRecoveryEntryChange('recently_closed', checked);
            if (!decision.allowed) {
              this.showToast(decision.message);
              return;
            }
            this.showRecentlyClosed = checked;
            this.commit(this.coordinator.setRecentlyClosedVisible(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '显示分区标题',
          checked: this.showRecentlyClosedTitle,
          rowPosition: 'middle',
          isEnabled: this.resolveDependentControlEnabled(this.showRecentlyClosed),
          onChange: (checked: boolean) => {
            this.showRecentlyClosedTitle = checked;
            AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY, checked);
            this.commit(this.coordinator.setRecentlyClosedTitleVisible(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        this.buildRecentlyClosedLimitSlider()
      }

      SettingsFooterText({
        text: '关闭后将清除已有记录，且不再保留新记录。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildRecentlyClosedLimitSlider() {
    Column({ space: 10 }) {
      Row() {
        Text('显示数量')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .layoutWeight(1)

        Text(`${this.recentlyClosedLimit} 条`)
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')

      Slider({
        value: this.coordinator.resolveRecentlyClosedSliderIndex(this.recentlyClosedLimit),
        min: 0,
        max: HOME_RECENTLY_CLOSED_LIMIT_OPTIONS.length - 1,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .height(HOME_SETTINGS_SLIDER_HEIGHT)
        .enabled(this.resolveDependentControlEnabled(this.showRecentlyClosed))
        .opacity(this.resolveDependentControlEnabled(this.showRecentlyClosed) ? 1 : 0.48)
        .selectedColor(this.storedAccentColor)
        .blockColor(this.storedOnAccentColor)
        .trackColor(this.storedControlBackgroundColor)
        .trackThickness(HOME_SETTINGS_SLIDER_TRACK_THICKNESS)
        .trackBorderRadius(HOME_SETTINGS_SLIDER_TRACK_RADIUS)
        .selectedBorderRadius(HOME_SETTINGS_SLIDER_TRACK_RADIUS)
        .blockSize({ width: HOME_SETTINGS_SLIDER_BLOCK_SIZE, height: HOME_SETTINGS_SLIDER_BLOCK_SIZE })
        .onChange((value: number, mode: SliderChangeMode) => {
          const limit = this.coordinator.resolveRecentlyClosedLimitForSliderIndex(value);
          this.recentlyClosedLimit = limit;
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.commit(this.coordinator.setRecentlyClosedLimit(limit));
          }
        })

      Row() {
        ForEach(HOME_RECENTLY_CLOSED_LIMIT_OPTIONS, (limit: number) => {
          Text(`${limit}`)
            .fontSize(11)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
        }, (limit: number) => `${limit}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  private buildSystemSearchSection() {
    SettingsSection({
      title: '系统搜索',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '在主页显示系统搜索',
          checked: this.showSystemSearch,
          rowPosition: 'first',
          isEnabled: this.resolveControlEnabled(),
          onChange: (checked: boolean) => {
            this.showSystemSearch = checked;
            this.commit(this.coordinator.setSystemSearchVisible(checked));
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        SettingsSwitchRow({
          title: '滚动时显示或隐藏',
          checked: this.hideSystemSearchOnScroll,
          rowPosition: 'last',
          isEnabled: this.resolveDependentControlEnabled(this.showSystemSearch),
          onChange: (checked: boolean) => {
            this.hideSystemSearchOnScroll = checked;
            this.commit(this.coordinator.setSystemSearchScrollBehavior(checked));
          }
        })
      }
    }
  }

  @Builder
  private buildSettingsButtonSection() {
    SettingsSection({ secondaryTextColor: this.storedSecondaryTextColor }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        SettingsSwitchRow({
          title: '显示主页设置按钮',
          checked: this.showSettingsButton,
          rowPosition: 'single',
          isEnabled: this.resolveControlEnabled(),
          onChange: (checked: boolean) => {
            const decision = this.coordinator.resolveRecoveryEntryChange('settings_button', checked);
            if (!decision.allowed) {
              this.showToast(decision.message);
              return;
            }
            this.showSettingsButton = checked;
            AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY, checked);
            this.commit(this.coordinator.setSettingsButtonVisible(checked));
          }
        })
      }

      SettingsFooterText({
        text: '收藏、最近关闭和主页设置按钮至少保留一项。',
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  private refreshState(): void {
    void this.refreshRevision;
    this.applySnapshot(this.coordinator.getSnapshot());
  }

  private commit(task: Promise<HomePageSettingsSnapshot>): void {
    if (this.settingsBusy) {
      return;
    }
    this.settingsBusy = true;
    task
      .then((snapshot: HomePageSettingsSnapshot) => {
        this.applySnapshot(snapshot);
        this.onSettingsChanged?.();
      })
      .catch((_error: Error) => {
        this.applySnapshot(this.coordinator.getSnapshot());
      })
      .finally(() => {
        this.settingsBusy = false;
      });
  }

  private applySnapshot(snapshot: HomePageSettingsSnapshot): void {
    this.showFavorites = snapshot.showFavorites;
    this.compactFavorites = snapshot.compactFavorites;
    this.showFavoritesTitle = snapshot.showFavoritesTitle;
    this.iconSizeRatio = snapshot.iconSizeRatio;
    this.iconCornerRadiusRatio = snapshot.iconCornerRadiusRatio;
    this.showShortcutNames = snapshot.showShortcutNames;
    this.showRecentlyClosed = snapshot.showRecentlyClosed;
    this.showRecentlyClosedTitle = snapshot.showRecentlyClosedTitle;
    this.recentlyClosedLimit = snapshot.recentlyClosedLimit;
    this.showSystemSearch = snapshot.showSystemSearch;
    this.hideSystemSearchOnScroll = snapshot.hideSystemSearchOnScroll;
    this.showSettingsButton = snapshot.showSettingsButton;
    AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_FAVORITES_TITLE_KEY, snapshot.showFavoritesTitle);
    AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_SHORTCUT_NAMES_KEY, snapshot.showShortcutNames);
    AppStorage.setOrCreate(
      HOME_PAGE_PRESENTATION_SHOW_RECENTLY_CLOSED_TITLE_KEY,
      snapshot.showRecentlyClosedTitle
    );
    AppStorage.setOrCreate(HOME_PAGE_PRESENTATION_SHOW_SETTINGS_BUTTON_KEY, snapshot.showSettingsButton);
    AppStorage.setOrCreate(
      BROWSER_APPEARANCE_STORAGE_HOME_SHORTCUT_ICON_SIZE_RATIO_KEY,
      snapshot.iconSizeRatio
    );
    AppStorage.setOrCreate(
      BROWSER_APPEARANCE_STORAGE_SITE_ICON_CORNER_RATIO_KEY,
      snapshot.iconCornerRadiusRatio
    );
  }

  private showToast(message: string): void {
    if (message.length <= 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1800
      });
    } catch (_error) {
    }
  }

  private resolveControlEnabled(): boolean {
    return this.isEnabled && !this.settingsBusy;
  }

  private resolveDependentControlEnabled(parentEnabled: boolean): boolean {
    return this.resolveControlEnabled() && parentEnabled;
  }

  private resolveIconControlEnabled(): boolean {
    return this.resolveDependentControlEnabled(this.showFavorites) && this.iconAppearanceEnabled;
  }
}
