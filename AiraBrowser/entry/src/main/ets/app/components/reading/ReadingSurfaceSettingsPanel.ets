import {
  ReaderModeLineHeight,
  ReaderModeTheme
} from '../../../common/models/BrowserModels';
import {
  ReadingPresentationMode,
  ReadingSurfaceAppearance
} from '../../../features/reading/ReadingSurfaceModels';
import { AiraIcon } from '../common/AiraIcon';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import {
  SettingsOptionRow,
  SettingsSwitchRow
} from '../settings/SettingsRows';
import {
  resolveEffectiveReadingTheme,
  resolveReadingThemeChipBackgroundColor,
  resolveReadingThemeTokens
} from './ReadingThemeTokenResolver';

const READING_SETTINGS_HORIZONTAL_PADDING: number = 22;
const READING_SETTINGS_SLIDER_HEIGHT: number = 40;
const READING_SETTINGS_SLIDER_TRACK_THICKNESS: number = 20;
const READING_SETTINGS_SLIDER_TRACK_RADIUS: number = 10;
const READING_SETTINGS_SLIDER_BLOCK_SIZE: number = 16;
const READING_FONT_SIZE_MIN: number = 15;
const READING_FONT_SIZE_MAX: number = 26;
const READING_LINE_HEIGHT_SLIDER_MIN: number = 0;
const READING_LINE_HEIGHT_SLIDER_MAX: number = 2;
const READING_SETTINGS_THEME_ORDER: ReaderModeTheme[] =
  ['light', 'paper', 'sage', 'sepia', 'charcoal', 'dark'];

export type ReadingSurfaceSettingsPanelKind = 'appearance' | 'text' | 'settings';

@Component
export struct ReadingSurfaceSettingsPanel {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop panel: ReadingSurfaceSettingsPanelKind = 'text';
  @Prop appearance: ReadingSurfaceAppearance;
  @Prop mode: ReadingPresentationMode = 'vertical';
  @Prop useAppThemeColors: boolean = false;
  @Prop showPageModeOptions: boolean = true;
  @Prop horizontalPadding: number = READING_SETTINGS_HORIZONTAL_PADDING;
  onAppearanceChange: (appearance: ReadingSurfaceAppearance) => void =
    (_appearance: ReadingSurfaceAppearance): void => {};
  onModeChange: (mode: ReadingPresentationMode) => void =
    (_mode: ReadingPresentationMode): void => {};
  @BuilderParam settingsExtension: () => void = this.emptyBuilder;

  @Builder
  private emptyBuilder() {
  }

  build() {
    if (this.panel === 'appearance') {
      this.buildAppearancePanel()
    } else if (this.panel === 'settings') {
      this.buildSettingsPanel()
    } else {
      this.buildTextPanel()
    }
  }

  @Builder
  private buildAppearancePanel() {
    Column({ space: 14 }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceColor }) {
        SettingsSwitchRow({
          title: '跟随系统亮度',
          checked: this.appearance.brightnessMode === 'system',
          rowPosition: 'first',
          onChange: (enabled: boolean): void => {
            const next: ReadingSurfaceAppearance = this.copyAppearance();
            next.brightnessMode = enabled ? 'system' : 'manual';
            this.onAppearanceChange(next);
          }
        })
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        this.buildBrightnessSlider()
      }

      Row() {
        ForEach(READING_SETTINGS_THEME_ORDER, (theme: ReaderModeTheme) => {
          Column()
            .width(38)
            .height(38)
            .backgroundColor(this.resolveThemeBackgroundColor(theme))
            .borderRadius(19)
            .border({
              width: this.appearance.theme === theme ? 2 : 1,
              color: this.resolveChoiceBorderColor(this.appearance.theme === theme)
            })
            .onClick((): void => {
              const next: ReadingSurfaceAppearance = this.copyAppearance();
              next.theme = theme;
              this.onAppearanceChange(next);
            })
        }, (theme: ReaderModeTheme): string => theme)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding({
      left: this.horizontalPadding,
      right: this.horizontalPadding,
      top: 16,
      bottom: 12
    })
  }

  @Builder
  private buildBrightnessSlider() {
    Row() {
      AiraIcon({
        airaIconId: 'novelReader.brightnessLow',
        iconSize: 22,
        iconColor: this.resolveSecondaryTextColor()
      })
      Slider({
        value: this.appearance.brightnessPercent,
        min: 20,
        max: 100,
        step: 1,
        style: SliderStyle.InSet
      })
        .layoutWeight(1)
        .height(READING_SETTINGS_SLIDER_HEIGHT)
        .margin({ left: 8, right: 8 })
        .selectedColor(this.useAppThemeColors ? this.storedAccentColor :
          $r('app.color.reader_surface_selection_border'))
        .blockColor(this.storedOnAccentColor)
        .trackColor(this.resolveChipBackgroundColor())
        .trackThickness(READING_SETTINGS_SLIDER_TRACK_THICKNESS)
        .trackBorderRadius(READING_SETTINGS_SLIDER_TRACK_RADIUS)
        .selectedBorderRadius(READING_SETTINGS_SLIDER_TRACK_RADIUS)
        .blockSize({
          width: READING_SETTINGS_SLIDER_BLOCK_SIZE,
          height: READING_SETTINGS_SLIDER_BLOCK_SIZE
        })
        .onChange((value: number): void => {
          const next: ReadingSurfaceAppearance = this.copyAppearance();
          next.brightnessMode = 'manual';
          next.brightnessPercent = Math.round(value);
          this.onAppearanceChange(next);
        })
      AiraIcon({
        airaIconId: 'novelReader.brightnessHigh',
        iconSize: 22,
        iconColor: this.resolveTextColor()
      })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildTextPanel() {
    Column({ space: 14 }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceColor }) {
        this.buildFontSizeSlider()
        SettingsGroupDivider({ dividerColor: this.storedDividerColor })
        this.buildLineHeightSlider()
      }
    }
    .width('100%')
    .padding({
      left: this.horizontalPadding,
      right: this.horizontalPadding,
      top: 16,
      bottom: 12
    })
  }

  @Builder
  private buildFontSizeSlider() {
    Column({ space: 12 }) {
      Row() {
        Text('字号')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveTextColor())
          .layoutWeight(1)

        Text(`${Math.round(this.appearance.fontSize)}`)
          .fontSize(14)
          .fontColor(this.resolveSecondaryTextColor())
      }
      .width('100%')

      Slider({
        value: this.appearance.fontSize,
        min: READING_FONT_SIZE_MIN,
        max: READING_FONT_SIZE_MAX,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .height(READING_SETTINGS_SLIDER_HEIGHT)
        .selectedColor(this.resolveSliderSelectedColor())
        .blockColor(this.storedOnAccentColor)
        .trackColor(this.resolveChipBackgroundColor())
        .trackThickness(READING_SETTINGS_SLIDER_TRACK_THICKNESS)
        .trackBorderRadius(READING_SETTINGS_SLIDER_TRACK_RADIUS)
        .selectedBorderRadius(READING_SETTINGS_SLIDER_TRACK_RADIUS)
        .blockSize({
          width: READING_SETTINGS_SLIDER_BLOCK_SIZE,
          height: READING_SETTINGS_SLIDER_BLOCK_SIZE
        })
        .onChange((value: number): void => {
          const next: ReadingSurfaceAppearance = this.copyAppearance();
          next.fontSize = Math.max(READING_FONT_SIZE_MIN,
            Math.min(READING_FONT_SIZE_MAX, Math.round(value)));
          this.onAppearanceChange(next);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  private buildLineHeightSlider() {
    Column({ space: 12 }) {
      Row() {
        Text('行间距')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveTextColor())
          .layoutWeight(1)

        Text(this.resolveLineHeightLabel())
          .fontSize(14)
          .fontColor(this.resolveSecondaryTextColor())
      }
      .width('100%')

      Slider({
        value: this.resolveLineHeightSliderValue(),
        min: READING_LINE_HEIGHT_SLIDER_MIN,
        max: READING_LINE_HEIGHT_SLIDER_MAX,
        step: 1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .height(READING_SETTINGS_SLIDER_HEIGHT)
        .selectedColor(this.resolveSliderSelectedColor())
        .blockColor(this.storedOnAccentColor)
        .trackColor(this.resolveChipBackgroundColor())
        .trackThickness(READING_SETTINGS_SLIDER_TRACK_THICKNESS)
        .trackBorderRadius(READING_SETTINGS_SLIDER_TRACK_RADIUS)
        .selectedBorderRadius(READING_SETTINGS_SLIDER_TRACK_RADIUS)
        .blockSize({
          width: READING_SETTINGS_SLIDER_BLOCK_SIZE,
          height: READING_SETTINGS_SLIDER_BLOCK_SIZE
        })
        .onChange((value: number): void => {
          const next: ReadingSurfaceAppearance = this.copyAppearance();
          next.lineHeight = this.resolveLineHeightForSliderValue(value);
          this.onAppearanceChange(next);
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
  }

  @Builder
  private buildSettingsPanel() {
    Column({ space: 14 }) {
      if (this.showPageModeOptions) {
        SettingsGroupCard({ surfaceColor: this.storedSurfaceColor }) {
          this.buildPageModeOption('左右翻页', 'horizontal', 'first')
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildPageModeOption('左右快速', 'horizontalFast', 'middle')
          SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          this.buildPageModeOption('上下滚动', 'vertical', 'last')
        }
      }

      this.settingsExtension()
    }
    .width('100%')
    .padding({
      left: this.horizontalPadding,
      right: this.horizontalPadding,
      top: 16,
      bottom: 12
    })
  }

  @Builder
  private buildPageModeOption(
    label: string,
    mode: ReadingPresentationMode,
    rowPosition: 'first' | 'middle' | 'last'
  ) {
    SettingsOptionRow({
      title: label,
      helperText: '',
      rowPosition: rowPosition,
      isSelected: this.mode === mode,
      isEnabled: true,
      radioGroup: 'reading-presentation-mode',
      radioValue: mode,
      selectedIndicatorColor: this.storedAccentColor,
      onAction: (): void => {
        this.onModeChange(mode);
      }
    })
  }

  private resolveLineHeightSliderValue(): number {
    if (this.appearance.lineHeight === 'compact') {
      return READING_LINE_HEIGHT_SLIDER_MIN;
    }
    if (this.appearance.lineHeight === 'loose') {
      return READING_LINE_HEIGHT_SLIDER_MAX;
    }
    return 1;
  }

  private resolveLineHeightForSliderValue(value: number): ReaderModeLineHeight {
    const roundedValue: number = Math.round(value);
    if (roundedValue <= READING_LINE_HEIGHT_SLIDER_MIN) {
      return 'compact';
    }
    if (roundedValue >= READING_LINE_HEIGHT_SLIDER_MAX) {
      return 'loose';
    }
    return 'comfortable';
  }

  private resolveLineHeightLabel(): string {
    if (this.appearance.lineHeight === 'compact') {
      return '紧凑';
    }
    if (this.appearance.lineHeight === 'loose') {
      return '宽松';
    }
    return '舒适';
  }

  private copyAppearance(): ReadingSurfaceAppearance {
    return {
      fontSize: this.appearance.fontSize,
      theme: this.appearance.theme,
      lineHeight: this.appearance.lineHeight,
      pageWidth: this.appearance.pageWidth,
      brightnessMode: this.appearance.brightnessMode,
      brightnessPercent: this.appearance.brightnessPercent
    };
  }

  private resolveEffectiveTheme(): ReaderModeTheme {
    return resolveEffectiveReadingTheme(this.appearance.theme);
  }

  private resolveThemeBackgroundColor(theme: ReaderModeTheme): ResourceColor {
    return resolveReadingThemeTokens(theme).backgroundColor;
  }

  private resolveTextColor(): ResourceColor {
    if (this.useAppThemeColors) {
      return this.storedPrimaryTextColor;
    }
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    if (this.useAppThemeColors) {
      return this.storedSecondaryTextColor;
    }
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).secondaryTextColor;
  }

  private resolveChipBackgroundColor(): ResourceColor {
    if (this.useAppThemeColors) {
      return this.storedControlBackgroundColor;
    }
    return resolveReadingThemeChipBackgroundColor(this.resolveEffectiveTheme());
  }

  private resolveSliderSelectedColor(): ResourceColor {
    return this.useAppThemeColors
      ? this.storedAccentColor
      : $r('app.color.reader_surface_selection_border');
  }

  private resolveChoiceBorderColor(selected: boolean): ResourceColor {
    if (this.useAppThemeColors) {
      return selected ? this.storedAccentColor : this.storedDividerColor;
    }
    return selected
      ? $r('app.color.reader_surface_selection_border')
      : $r('app.color.reader_surface_unselected_border');
  }
}
