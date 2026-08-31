import { BROWSER_GLOBAL_SYMBOL_WEIGHT } from './BrowserIconStyle';
import { BrowserArkWebMediaButtonState } from '../../../core/browser/media/BrowserArkWebMediaTakeoverCoordinator';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';

const ARKWEB_MEDIA_BUTTON_SIZE: number = 48;
const ARKWEB_MEDIA_ICON_SIZE: number = 22;
const ARKWEB_MEDIA_BUSY_OPACITY: number = 0.7;

@Component
export struct BrowserArkWebMediaTakeoverFloatingButton {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop sourceCount: number = 0;
  @Prop controllable: boolean = false;
  @Prop busy: boolean = false;
  @Prop buttonColor: ResourceColor = '';
  @Prop iconColor: ResourceColor = '';
  onButtonTap: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: ARKWEB_MEDIA_BUTTON_SIZE,
        surfaceHeight: ARKWEB_MEDIA_BUTTON_SIZE,
        surfaceRadius: ARKWEB_MEDIA_BUTTON_SIZE / 2,
        tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Button({ type: ButtonType.Circle }) {
          SymbolGlyph($r('sys.symbol.play_fill'))
            .fontSize(ARKWEB_MEDIA_ICON_SIZE)
            .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
            .fontColor([this.iconColor])
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .enabled(!this.busy)
        .stateEffect(true)
        .accessibilityText(this.buildAccessibilityText())
        .onClick(() => {
          this.onButtonTap();
        })
      }
    }
    .width(ARKWEB_MEDIA_BUTTON_SIZE)
    .height(ARKWEB_MEDIA_BUTTON_SIZE)
    .opacity(this.busy ? ARKWEB_MEDIA_BUSY_OPACITY : 1)
  }

  private buildAccessibilityText(): string {
    if (!this.controllable) {
      return 'ArkWeb 已识别网页视频，当前页面暂未提供可控制的视频会话';
    }
    if (this.sourceCount > 1) {
      return `ArkWeb 视频接管，发现 ${this.sourceCount} 个媒体源`;
    }
    return 'ArkWeb 视频接管';
  }
}

@Component
export struct BrowserArkWebMediaTakeoverFloatingButtonHost {
  @Prop state: BrowserArkWebMediaButtonState;
  @Prop buttonColor: ResourceColor = '';
  @Prop iconColor: ResourceColor = '';
  @Prop layerIndex: number = 0;
  onButtonTap: () => void = (): void => {};

  build() {
    BrowserArkWebMediaTakeoverFloatingButton({
      sourceCount: this.state.sourceCount,
      controllable: this.state.controllable,
      busy: this.state.busy,
      buttonColor: this.buttonColor,
      iconColor: this.iconColor,
      onButtonTap: this.onButtonTap
    })
      .position({ x: this.state.x, y: this.state.y })
      .zIndex(this.layerIndex)
  }
}
