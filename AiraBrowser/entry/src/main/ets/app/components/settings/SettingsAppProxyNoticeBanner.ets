import {
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const SETTINGS_APP_PROXY_NOTICE_HEIGHT: number = 34;
const SETTINGS_APP_PROXY_NOTICE_BOTTOM_SPACE: number = 8;
const SETTINGS_APP_PROXY_NOTICE_REVEALED_HEIGHT: number =
  SETTINGS_APP_PROXY_NOTICE_HEIGHT + SETTINGS_APP_PROXY_NOTICE_BOTTOM_SPACE;
const SETTINGS_APP_PROXY_NOTICE_RADIUS: number = 14;
const SETTINGS_APP_PROXY_NOTICE_DOT_SIZE: number = 8;
const SETTINGS_APP_PROXY_NOTICE_PULSE_MS: number = 860;
const SETTINGS_APP_PROXY_NOTICE_PULSE_MIN_OPACITY: number = 0.38;
const SETTINGS_APP_PROXY_NOTICE_PULSE_MIN_SCALE: number = 0.76;
const SETTINGS_APP_PROXY_NOTICE_ACTION_WIDTH: number = 58;
const SETTINGS_APP_PROXY_NOTICE_ACTION_HEIGHT: number = 30;
const SETTINGS_APP_PROXY_NOTICE_REVEAL_DELAY_MS: number = 500;
const SETTINGS_APP_PROXY_NOTICE_REVEAL_MS: number = 260;

@Component
export struct SettingsAppProxyNoticeBanner {
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop message: ResourceStr = '';
  @Prop surfaceColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop statusColor: ResourceColor = '';
  private revealTimer: number = -1;
  @State private pulseOpacity: number = 1;
  @State private pulseScale: number = 1;
  @State private presented: boolean = false;
  onAction?: () => void;

  aboutToAppear(): void {
    this.scheduleReveal();
    this.startPulse();
  }

  aboutToDisappear(): void {
    this.clearRevealTimer();
  }

  build() {
    Column() {
      Row({ space: 9 }) {
        Circle()
          .width(SETTINGS_APP_PROXY_NOTICE_DOT_SIZE)
          .height(SETTINGS_APP_PROXY_NOTICE_DOT_SIZE)
          .fill(this.statusColor)
          .opacity(this.pulseOpacity)
          .scale({
            x: this.pulseScale,
            y: this.pulseScale
          })
          .animation({
            duration: SETTINGS_APP_PROXY_NOTICE_PULSE_MS,
            curve: Curve.EaseInOut,
            iterations: -1,
            playMode: PlayMode.Alternate
          })

        Text(this.message)
          .layoutWeight(1)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Button() {
          Text('设置')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.resolveAccentColor())
            .maxLines(1)
        }
        .width(SETTINGS_APP_PROXY_NOTICE_ACTION_WIDTH)
        .height(SETTINGS_APP_PROXY_NOTICE_ACTION_HEIGHT)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(true)
        .onClick(() => {
          this.onAction?.();
        })
      }
      .width('100%')
      .height(SETTINGS_APP_PROXY_NOTICE_HEIGHT)
      .padding({ left: 13, right: 12 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.resolveSurfaceColor())
      .borderRadius(SETTINGS_APP_PROXY_NOTICE_RADIUS)
    }
    .width('100%')
    .height(this.presented ? SETTINGS_APP_PROXY_NOTICE_REVEALED_HEIGHT : 0)
    .opacity(this.presented ? 1 : 0)
    .clip(true)
    .animation({
      duration: SETTINGS_APP_PROXY_NOTICE_REVEAL_MS,
      curve: Curve.EaseOut
    })
  }

  private scheduleReveal(): void {
    this.clearRevealTimer();
    this.presented = false;
    this.revealTimer = setTimeout(() => {
      this.presented = true;
      this.revealTimer = -1;
    }, SETTINGS_APP_PROXY_NOTICE_REVEAL_DELAY_MS);
  }

  private clearRevealTimer(): void {
    if (this.revealTimer >= 0) {
      clearTimeout(this.revealTimer);
      this.revealTimer = -1;
    }
  }

  private startPulse(): void {
    this.pulseOpacity = 1;
    this.pulseScale = 1;
    setTimeout(() => {
      this.pulseOpacity = SETTINGS_APP_PROXY_NOTICE_PULSE_MIN_OPACITY;
      this.pulseScale = SETTINGS_APP_PROXY_NOTICE_PULSE_MIN_SCALE;
    }, 0);
  }

  private resolveSurfaceColor(): ResourceColor {
    return `${this.surfaceColor}`.length > 0 ? this.surfaceColor : this.storedSurfaceBackgroundColor;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveAccentColor(): ResourceColor {
    return `${this.accentColor}`.length > 0 ? this.accentColor : this.resolvePrimaryTextColor();
  }
}
