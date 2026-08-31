import {
  WallpaperImageOptionViewState,
  WallpaperModeOptionViewState,
  WallpaperSettingsViewState
} from '../../../core/wallpaper/WallpaperSettingsViewModel';
import {
  WallpaperSettingsLayoutPolicy,
  WallpaperSettingsLayoutState
} from '../../../core/wallpaper/WallpaperSettingsLayoutPolicy';
import { WallpaperMode } from '../../../common/models/WallpaperModels';
import {
  SettingsOptionRow
} from '../settings/SettingsRows';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsSection
} from '../settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const WALLPAPER_IMAGE_CARD_CORNER_RADIUS: number = 22;
const WALLPAPER_IMAGE_SELECTION_HEIGHT: number = 54;
const WALLPAPER_IMAGE_CARD_RADIO_GROUP: string = 'wallpaper-image-options';
const WALLPAPER_IMAGE_SELECTED_BORDER_WIDTH: number = 2;
const WALLPAPER_CUSTOM_REPLACE_CAPSULE_WIDTH: number = 60;
const WALLPAPER_CUSTOM_REPLACE_CAPSULE_HEIGHT: number = 28;
const WALLPAPER_CUSTOM_REPLACE_CAPSULE_BOTTOM_MARGIN: number = 14;
const WALLPAPER_CUSTOM_REPLACE_CAPSULE_END_MARGIN: number = 14;

@Component
export struct WallpaperSettingsContent {
  private layoutPolicy: WallpaperSettingsLayoutPolicy = new WallpaperSettingsLayoutPolicy();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: WallpaperSettingsViewState;
  @State private layoutState: WallpaperSettingsLayoutState = this.layoutPolicy.resolve({
    containerWidth: 390,
    containerHeight: 844
  });
  onModeSelect: (mode: WallpaperMode) => void = (_mode: WallpaperMode) => {};
  onBingRetry: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      this.buildThemeModeSection()
      this.buildImageModeSection()
    }
    .width('100%')
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateResponsiveLayout(
        this.parseAreaDimension(newArea.width),
        this.parseAreaDimension(newArea.height)
      );
    })
  }

  @Builder
  private buildThemeModeSection() {
    SettingsSection({
      title: '壁纸来源',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        this.buildThemeModeOption(this.state.themeOption)
      }
    }
  }

  @Builder
  private buildThemeModeOption(option: WallpaperModeOptionViewState) {
    SettingsOptionRow({
      title: option.title,
      rowPosition: 'single',
      isSelected: option.id === this.state.mode,
      isEnabled: option.isEnabled,
      onAction: () => {
        this.onModeSelect(option.id);
      }
    })
  }

  @Builder
  private buildImageModeSection() {
    Row() {
      Column() {
        SettingsSection({
          title: '图片壁纸',
          secondaryTextColor: this.storedSecondaryTextColor
        }) {
          Row({ space: this.layoutState.cardGap }) {
            ForEach(this.state.imageOptions, (option: WallpaperImageOptionViewState) => {
              this.buildImageModeCard(option)
            }, (option: WallpaperImageOptionViewState) =>
              `${option.id}:${option.previewPath}:${this.state.bingPreviewStatus}:${this.state.mode}:${this.layoutState.mode}`)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)

          if ((this.state.bingPreviewStatusText ?? '').length > 0) {
            this.buildBingPreviewStatus()
          }

          SettingsFooterText({
            text: this.state.footerText,
            secondaryTextColor: this.storedSecondaryTextColor
          })
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: this.layoutState.groupMaxWidth })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildImageModeCard(option: WallpaperImageOptionViewState) {
    Column({ space: 10 }) {
      Button() {
        this.buildImageModePreview(option)
      }
      .width('100%')
      .aspectRatio(this.layoutState.previewAspectRatio)
      .type(ButtonType.Normal)
      .accessibilityText(this.resolvePreviewAccessibilityText(option))
      .padding(0)
      .backgroundColor(this.storedControlBackgroundColor)
      .border({
        width: this.state.mode === option.id ? WALLPAPER_IMAGE_SELECTED_BORDER_WIDTH : 0,
        color: this.storedAccentColor
      })
      .borderRadius(WALLPAPER_IMAGE_CARD_CORNER_RADIUS)
      .clip(true)
      .stateEffect(true)
      .onClick(() => {
        if (option.isEnabled) {
          this.onModeSelect(option.id);
        }
      })

      this.buildImageModeSelection(option)
    }
    .layoutWeight(1)
    .enabled(option.isEnabled)
    .opacity(option.isEnabled ? 1 : 0.48)
  }

  @Builder
  private buildImageModePreview(option: WallpaperImageOptionViewState) {
    Stack({ alignContent: Alignment.Center }) {
      if (!option.isEmpty) {
        Image(option.previewPath)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .interpolation(ImageInterpolation.Medium)
          .borderRadius(WALLPAPER_IMAGE_CARD_CORNER_RADIUS)
          .clip(true)
        if (option.id === 'custom') {
          this.buildCustomReplaceCapsule()
        }
      } else if (option.id === 'bing' && this.state.bingPreviewStatus === 'loading') {
        LoadingProgress()
          .width(30)
          .height(30)
          .color(this.storedAccentColor)
      } else if (option.id === 'bing' && this.state.bingPreviewStatus === 'error') {
        Text('加载失败')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedSecondaryTextColor)
      } else if (option.id === 'custom') {
        SymbolGlyph($r('sys.symbol.plus'))
          .fontSize(34)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.storedSecondaryTextColor])
      } else {
        Text('Bing')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedSecondaryTextColor)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(WALLPAPER_IMAGE_CARD_CORNER_RADIUS)
    .clip(true)
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildCustomReplaceCapsule() {
    Row() {
      Text('更换')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedOnAccentColor)
    }
    .width(WALLPAPER_CUSTOM_REPLACE_CAPSULE_WIDTH)
    .height(WALLPAPER_CUSTOM_REPLACE_CAPSULE_HEIGHT)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedAccentColor)
    .borderRadius(WALLPAPER_CUSTOM_REPLACE_CAPSULE_HEIGHT / 2)
    .clip(true)
    .align(this.layoutState.customActionPlacement === 'end' ? Alignment.BottomEnd : Alignment.Bottom)
    .margin({
      right: this.layoutState.customActionPlacement === 'end' ? WALLPAPER_CUSTOM_REPLACE_CAPSULE_END_MARGIN : 0,
      bottom: WALLPAPER_CUSTOM_REPLACE_CAPSULE_BOTTOM_MARGIN
    })
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildImageModeSelection(option: WallpaperImageOptionViewState) {
    if (this.layoutState.selectionAxis === 'horizontal') {
      Row({ space: 8 }) {
        this.buildImageModeRadio(option)
        this.buildImageModeTitle(option, TextAlign.Start)
      }
      .width('100%')
      .height(WALLPAPER_IMAGE_SELECTION_HEIGHT)
      .padding({ left: 14, right: 14 })
      .alignItems(VerticalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .opacity(this.state.mode === 'theme' ? 0.45 : 1)
      .onClick(() => {
        if (option.isEnabled) {
          this.onModeSelect(option.id);
        }
      })
    } else {
      Column({ space: 6 }) {
        this.buildImageModeRadio(option)
        this.buildImageModeTitle(option, TextAlign.Center)
      }
      .width('100%')
      .height(WALLPAPER_IMAGE_SELECTION_HEIGHT)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
      .opacity(this.state.mode === 'theme' ? 0.45 : 1)
      .onClick(() => {
        if (option.isEnabled) {
          this.onModeSelect(option.id);
        }
      })
    }
  }

  @Builder
  private buildImageModeRadio(option: WallpaperImageOptionViewState) {
    Radio({
      value: option.id,
      group: WALLPAPER_IMAGE_CARD_RADIO_GROUP
    })
      .checked(this.state.mode === option.id)
      .enabled(option.isEnabled)
      .hitTestBehavior(HitTestMode.None)
      .radioStyle({
        checkedBackgroundColor: this.storedAccentColor
      })
  }

  @Builder
  private buildImageModeTitle(option: WallpaperImageOptionViewState, textAlign: TextAlign) {
    Text(option.title)
      .fontSize(15)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedPrimaryTextColor)
      .textAlign(textAlign)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
  }

  @Builder
  private buildBingPreviewStatus() {
    Row({ space: 8 }) {
      if (this.state.bingPreviewStatus === 'loading') {
        LoadingProgress()
          .width(18)
          .height(18)
          .color(this.storedAccentColor)
      }

      Text(this.state.bingPreviewStatusText ?? '')
        .fontSize(13)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
        .layoutWeight(1)

      if (this.state.bingRetryVisible) {
        Button('重试')
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedAccentColor)
          .onClick(() => {
            this.onBingRetry();
          })
      }
    }
    .width('100%')
    .padding({ left: 6, right: 6 })
    .alignItems(VerticalAlign.Center)
  }

  private resolvePreviewAccessibilityText(option: WallpaperImageOptionViewState): string {
    if (option.id === 'custom') {
      return option.isEmpty ? '添加自定义壁纸' : '更换自定义壁纸';
    }
    if (this.state.bingPreviewStatus === 'loading') {
      return '正在加载必应壁纸';
    }
    if (this.state.bingPreviewStatus === 'error' && option.isEmpty) {
      return '必应壁纸加载失败';
    }
    return '使用必应壁纸';
  }

  private updateResponsiveLayout(containerWidth: number, containerHeight: number): void {
    if (containerWidth <= 0 || containerHeight <= 0) {
      return;
    }
    const nextState = this.layoutPolicy.resolve({
      containerWidth,
      containerHeight
    });
    if (this.layoutPolicy.buildRenderKey(nextState) === this.layoutPolicy.buildRenderKey(this.layoutState)) {
      return;
    }
    this.layoutState = nextState;
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

}
