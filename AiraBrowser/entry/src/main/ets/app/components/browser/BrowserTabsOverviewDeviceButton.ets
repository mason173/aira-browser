import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import {
  BROWSER_FLOATING_CHROME_PRESSED_SCALE,
  BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
  BROWSER_FLOATING_CHROME_RELEASE_CURVE,
  BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import {
  resolveBrowserBottomFloatingMaterialShadowColor,
  resolveBrowserBottomNeutralPressedColor,
  resolveBrowserBottomNeutralPrimaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { AiraIcon } from '../common/AiraIcon';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForTone } from './BrowserFloatingGlassMaterialTokens';
import { BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE } from './BrowserTabsOverviewClearButton';

const BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_EDGE_GAP: number = 16;
const BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_ICON_SIZE: number = 24;
const BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_SHADOW_RADIUS: number = 6;
const BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_SHADOW_OFFSET_Y: number = 2;

@Component
export struct BrowserTabsOverviewDeviceButton {
  @Prop topSafeInsetVp: number = 0;
  @Prop surfaceOpacity: number = 1;
  @Prop interactionEnabled: boolean = true;
  @Prop regularChromeIconTone: AppChromeIconTone = 'light';
  @Prop adaptiveForeground: boolean = true;
  @State private pressed: boolean = false;
  @State private pressedScale: number = 1;

  onOpenDeviceTabs: () => void = () => {};

  aboutToDisappear(): void {
    this.pressed = false;
    this.pressedScale = 1;
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE,
        surfaceHeight: BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE,
        surfaceRadius: BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE / 2,
        tintColor: this.resolveMaterialTint()
      }) {
        Stack({ alignContent: Alignment.Center }) {
          AiraIcon({
            airaIconId: 'settings.themeMode.system',
            iconSize: BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_ICON_SIZE,
            iconColor: this.resolvePrimaryColor()
          })
            .hitTestBehavior(HitTestMode.None)

          Button()
            .width('100%')
            .height('100%')
            .type(ButtonType.Normal)
            .backgroundColor(this.pressed ? this.resolvePressedColor() :
              $r('sys.color.ohos_id_color_background_transparent'))
            .borderRadius(BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE / 2)
            .stateEffect(false)
            .monopolizeEvents(true)
            .hitTestBehavior(HitTestMode.Block)
            .accessibilityText('电脑标签页')
            .onTouch((event: TouchEvent) => {
              this.updatePressedState(event.type);
            })
            .onClick(() => {
              if (this.interactionEnabled) {
                this.onOpenDeviceTabs();
              }
            })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width(BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE)
    .height(BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE)
    .position({
      x: BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_EDGE_GAP,
      y: this.resolveTop()
    })
    .borderRadius(BROWSER_TABS_OVERVIEW_CLEAR_BUTTON_SIZE / 2)
    .opacity(this.resolveSurfaceOpacity())
    .shadow(this.resolveMaterialShadow())
    .scale({ x: this.pressedScale, y: this.pressedScale })
  }

  private updatePressedState(touchType: TouchType): void {
    if (!this.interactionEnabled) {
      this.pressed = false;
      this.pressedScale = 1;
      return;
    }
    if (touchType === TouchType.Down) {
      this.pressed = true;
      animateTo({
        duration: BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
        curve: Curve.EaseOut
      }, () => {
        this.pressedScale = BROWSER_FLOATING_CHROME_PRESSED_SCALE;
      });
      return;
    }
    if (touchType === TouchType.Up || touchType === TouchType.Cancel) {
      this.pressed = false;
      animateTo({
        duration: BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS,
        curve: BROWSER_FLOATING_CHROME_RELEASE_CURVE
      }, () => {
        this.pressedScale = 1;
      });
    }
  }

  private resolveMaterialTint(): ResourceColor {
    return resolveBrowserFloatingGlassMaterialTintForTone(this.regularChromeIconTone);
  }

  private resolveMaterialMode(): string {
    return this.regularChromeIconTone === 'dark' ? 'dark' : 'light';
  }

  private resolvePrimaryColor(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.icon_primary') :
      resolveBrowserBottomNeutralPrimaryColor(this.resolveMaterialMode());
  }

  private resolvePressedColor(): ResourceColor {
    return resolveBrowserBottomNeutralPressedColor(this.resolveMaterialMode());
  }

  private resolveMaterialShadow(): ShadowOptions {
    return {
      radius: BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_SHADOW_RADIUS,
      color: resolveBrowserBottomFloatingMaterialShadowColor(this.resolveMaterialMode()),
      offsetX: 0,
      offsetY: BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_SHADOW_OFFSET_Y
    };
  }

  private resolveTop(): number {
    return Math.max(
      BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_EDGE_GAP,
      Math.max(0, this.topSafeInsetVp) + BROWSER_TABS_OVERVIEW_DEVICE_BUTTON_EDGE_GAP
    );
  }

  private resolveSurfaceOpacity(): number {
    if (!Number.isFinite(this.surfaceOpacity)) {
      return 1;
    }
    return Math.max(0, Math.min(1, this.surfaceOpacity));
  }
}
