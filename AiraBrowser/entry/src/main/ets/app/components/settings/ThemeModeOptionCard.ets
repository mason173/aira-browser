import { BrowserThemeMode } from '../../../common/models/BrowserModels';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const THEME_MODE_PREVIEW_RADIUS: number = 22;
const THEME_MODE_PREVIEW_MIN_HEIGHT: number = 152;
const THEME_MODE_PREVIEW_MAX_HEIGHT: number = 214;
const THEME_MODE_PREVIEW_ASPECT_RATIO: number = 0.82;
const THEME_MODE_DESKTOP_PREVIEW_MAX_HEIGHT: number = 260;
const THEME_MODE_DESKTOP_PREVIEW_ASPECT_RATIO: number = 1.528;
const THEME_MODE_DESKTOP_RADIUS: number = 8;
const THEME_MODE_DESKTOP_RADIO_GROUP: string = 'settings-theme-mode-desktop';

@Component
export struct ThemeModeOptionCard {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop mode: BrowserThemeMode = 'system';
  @Prop title: ResourceStr = '';
  @Prop isSelected: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @State private pressed: boolean = false;
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  onAction?: () => void;

  build() {
    if (this.desktopPresentation) {
      this.buildDesktopCard()
    } else {
      this.buildTouchCard()
    }
  }

  @Builder
  private buildTouchCard() {
    Column({ space: 10 }) {
      this.buildCardContent(false)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled || this.isSelected ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  @Builder
  private buildDesktopCard() {
    Button() {
      Column({ space: 8 }) {
        this.buildCardContent(true)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .padding(6)
    .backgroundColor(this.hovered || this.focused ? this.storedPressedBackgroundColor :
      $r('sys.color.ohos_id_color_background_transparent'))
    .border({ width: this.focused ? 2 : 0, color: this.storedAccentColor })
    .borderRadius(THEME_MODE_DESKTOP_RADIUS)
    .clip(true)
    .enabled(this.isEnabled)
    .focusable(true)
    .opacity(this.isEnabled || this.isSelected ? 1 : 0.48)
    .onHover((hovered: boolean) => {
      this.hovered = hovered && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  @Builder
  private buildCardContent(desktop: boolean) {
    Stack() {
      Image(this.resolvePreviewImage(desktop))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
    }
    .width('100%')
    .aspectRatio(desktop ? THEME_MODE_DESKTOP_PREVIEW_ASPECT_RATIO : THEME_MODE_PREVIEW_ASPECT_RATIO)
    .constraintSize({
      minHeight: desktop ? 132 : THEME_MODE_PREVIEW_MIN_HEIGHT,
      maxHeight: desktop ? THEME_MODE_DESKTOP_PREVIEW_MAX_HEIGHT : THEME_MODE_PREVIEW_MAX_HEIGHT
    })
    .backgroundColor(this.resolvePreviewBackgroundColor())
    .border({
      width: this.isSelected ? 2 : 0,
      color: this.storedAccentColor
    })
    .borderRadius(desktop ? THEME_MODE_DESKTOP_RADIUS : THEME_MODE_PREVIEW_RADIUS)
    .clip(true)

    if (desktop) {
      Row({ space: 8 }) {
        Text(this.title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.resolveTitleColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Radio({ value: this.mode, group: THEME_MODE_DESKTOP_RADIO_GROUP })
          .checked(this.isSelected)
          .enabled(this.isEnabled)
          .hitTestBehavior(HitTestMode.None)
          .radioStyle({ checkedBackgroundColor: this.storedAccentColor })
      }
      .width('100%')
      .padding({ left: 4, right: 4 })
      .alignItems(VerticalAlign.Center)
    } else {
      Text(this.title)
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveTitleColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolvePreviewBackgroundColor(): ResourceColor {
    if (this.pressed && this.isEnabled) {
      return this.storedPressedBackgroundColor;
    }
    if (this.mode === 'dark') {
      return this.storedControlBackgroundColor;
    }
    return this.storedSurfaceBackgroundColor;
  }

  private resolvePreviewImage(desktop: boolean): Resource {
    if (desktop) {
      if (this.mode === 'dark') {
        return $r('app.media.app_settings_theme_mode_desktop_preview_dark');
      }
      return $r('app.media.app_settings_theme_mode_desktop_preview_light');
    }
    if (this.mode === 'dark') {
      return $r('app.media.theme_mode_preview_dark');
    }
    return $r('app.media.theme_mode_preview_light');
  }

  private resolveTitleColor(): ResourceColor {
    return this.isSelected ? this.storedAccentColor : this.storedPrimaryTextColor;
  }
}
