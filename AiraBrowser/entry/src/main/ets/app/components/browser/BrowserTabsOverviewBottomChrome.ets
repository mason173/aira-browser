import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING,
  BROWSER_BOTTOM_CHROME_TEXT_SIZE,
  BROWSER_FLOATING_CHROME_PRESSED_SCALE,
  BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
  BROWSER_FLOATING_CHROME_RELEASE_CURVE,
  BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import { BrowserBottomPanelResponsiveViewModel } from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import { BrowserTabsOverviewSection } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { SegmentedTabs } from '../common/SegmentedTabs';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  resolveBrowserBottomFloatingMaterialShadowColor,
  resolveBrowserBottomNeutralPrimaryColor,
  resolveBrowserBottomNeutralSecondaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserBottomChromeImmersiveMaterialSurface } from './BrowserBottomChromeImmersiveMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForTone } from './BrowserFloatingGlassMaterialTokens';

export const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT: number = 52;
export const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP: number = 16;
export const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE: number =
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP + BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING;

const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE: number = 52;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP: number = 8;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_ICON_SIZE: number = 24;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET: number = 4;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_RADIUS: number = 6;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_OFFSET_Y: number = 2;

@Component
export struct BrowserTabsOverviewBottomChrome {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @Prop selectedSection: BrowserTabsOverviewSection = 'tabs';
  @Prop regularTabsLabel: string = '0 个标签页';
  @Prop viewportWidth: number = 390;
  @Prop viewportHeight: number = 844;
  @Prop surfaceOpacity: number = 1;
  @Prop chromeInteractionEnabled: boolean = true;
  @Prop regularChromeIconTone: AppChromeIconTone = 'light';
  @Prop adaptiveForeground: boolean = true;
  @State private pressedOuterScaleTarget: string = '';
  @State private pressedOuterScale: number = 1;

  onReturn: () => void = () => {};
  onCreateHome: () => void = () => {};
  onSwitchToTabs: () => void = () => {};
  onSwitchToPrivacy: () => void = () => {};

  private responsiveViewModel: BrowserBottomPanelResponsiveViewModel = new BrowserBottomPanelResponsiveViewModel();

  aboutToDisappear(): void {
    this.resetOuterPressScale();
  }

  build() {
    Row({ space: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP }) {
      this.buildOuterButton('return', 'browser.toolbar.back', '返回进入标签管理前的网页')
      this.buildSectionSwitcher()
      this.buildOuterButton('create-home', 'browser.tabs.overviewAdd', '回到主页')
    }
    .width(this.resolveChromeWidth())
    .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT)
    .position({
      x: this.resolveChromeLeft(),
      y: this.resolveChromeTop()
    })
    .opacity(this.resolveSurfaceOpacity())
    .hitTestBehavior(this.chromeInteractionEnabled ? HitTestMode.Transparent : HitTestMode.None)
  }

  @Builder
  private buildOuterButton(target: string, iconId: AiraRenderableIconId, accessibilityText: string) {
    Stack({ alignContent: Alignment.Center }) {
      BrowserBottomChromeImmersiveMaterialSurface({
        surfaceWidth: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE,
        surfaceHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
        surfaceRadius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2,
        materialTint: this.resolveMaterialTint(),
        fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background')
      }) {
        Stack({ alignContent: Alignment.Center }) {
          AiraIcon({
            airaIconId: iconId,
            iconSize: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_ICON_SIZE,
            iconColor: this.resolvePrimaryColor()
          })
            .hitTestBehavior(HitTestMode.None)

          Button()
            .width('100%')
            .height('100%')
            .type(ButtonType.Normal)
            .backgroundColor(this.resolvePressedBackground(target))
            .borderRadius(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2)
            .stateEffect(false)
            .accessibilityText(accessibilityText)
            .onTouch((event: TouchEvent) => {
              this.updatePressedOuterTarget(target, event.type);
            })
            .onClick(() => {
              this.dispatchOuterAction(target);
            })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE)
    .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT)
    .borderRadius(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2)
    .shadow(this.resolveMaterialShadow())
    .scale({
      x: this.resolveOuterButtonScale(target),
      y: this.resolveOuterButtonScale(target)
    })
  }

  @Builder
  private buildSectionSwitcher() {
    Stack({ alignContent: Alignment.Center }) {
      BrowserBottomChromeImmersiveMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
        surfaceRadius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2,
        materialTint: this.resolveMaterialTint(),
        fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background')
      }) {
        SegmentedTabs({
          options: [
            { id: 'tabs', title: this.regularTabsLabel },
            { id: 'privacy', title: '隐私模式' }
          ],
          selectedId: this.selectedSection,
          barHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
          itemHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT -
            BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET * 2,
          fontSize: BROWSER_BOTTOM_CHROME_TEXT_SIZE,
          barPadding: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET,
          indicatorBackgroundColor: this.storedAccentColor,
          selectedTextColor: this.storedOnAccentColor,
          secondaryTextColor: this.adaptiveForeground ? $r('sys.color.font_secondary') :
            resolveBrowserBottomNeutralSecondaryColor(this.resolveMaterialMode()),
          fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
          barMaterialEnabled: false,
          onSelect: (id: string): void => {
            this.dispatchSectionAction(id as BrowserTabsOverviewSection);
          }
        })
          .width('100%')
          .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT)
      }
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 1 })
    .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT)
    .borderRadius(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2)
    .shadow(this.resolveMaterialShadow())
  }

  private dispatchOuterAction(target: string): void {
    if (!this.chromeInteractionEnabled) {
      return;
    }
    if (target === 'return') {
      this.onReturn();
      return;
    }
    this.onCreateHome();
  }

  private dispatchSectionAction(section: BrowserTabsOverviewSection): void {
    if (!this.chromeInteractionEnabled || section === this.selectedSection) {
      return;
    }
    if (section === 'privacy') {
      this.onSwitchToPrivacy();
      return;
    }
    this.onSwitchToTabs();
  }

  private updatePressedOuterTarget(target: string, touchType: TouchType): void {
    if (!this.chromeInteractionEnabled) {
      this.resetOuterPressScale();
      return;
    }
    if (touchType === TouchType.Down) {
      this.pressedOuterScaleTarget = target;
      animateTo({
        duration: BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
        curve: Curve.EaseOut
      }, () => {
        this.pressedOuterScale = BROWSER_FLOATING_CHROME_PRESSED_SCALE;
      });
      return;
    }
    if (touchType === TouchType.Up || touchType === TouchType.Cancel) {
      if (this.pressedOuterScaleTarget !== target) {
        return;
      }
      animateTo({
        duration: BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS,
        curve: BROWSER_FLOATING_CHROME_RELEASE_CURVE
      }, () => {
        this.pressedOuterScale = 1;
      });
    }
  }

  private resetOuterPressScale(): void {
    this.pressedOuterScaleTarget = '';
    this.pressedOuterScale = 1;
  }

  private resolveOuterButtonScale(target: string): number {
    return this.pressedOuterScaleTarget === target ? this.pressedOuterScale : 1;
  }

  private resolvePressedBackground(target: string): ResourceColor {
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveMaterialTint(): ResourceColor {
    return resolveBrowserFloatingGlassMaterialTintForTone(this.resolveChromeTone());
  }

  private resolvePrimaryColor(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.icon_primary') :
      resolveBrowserBottomNeutralPrimaryColor(this.resolveMaterialMode());
  }

  private resolveMaterialShadow(): ShadowOptions {
    return {
      radius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_RADIUS,
      color: resolveBrowserBottomFloatingMaterialShadowColor(this.resolveMaterialMode()),
      offsetX: 0,
      offsetY: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_OFFSET_Y
    };
  }

  private resolveChromeTone(): AppChromeIconTone {
    return this.regularChromeIconTone;
  }

  private resolveMaterialMode(): string {
    return this.resolveChromeTone() === 'dark' ? 'dark' : 'light';
  }

  private resolveChromeWidth(): number {
    return this.responsiveViewModel.buildState({
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight
    }).panelWidth;
  }

  private resolveChromeLeft(): number {
    const responsiveState = this.responsiveViewModel.buildState({
      viewportWidth: this.viewportWidth,
      viewportHeight: this.viewportHeight
    });
    if (responsiveState.panelWidth > 0) {
      return responsiveState.panelOffsetX;
    }
    return Math.max(0, BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET);
  }

  private resolveChromeTop(): number {
    return Math.max(0, this.viewportHeight - BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE -
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT);
  }

  private resolveSurfaceOpacity(): number {
    if (!Number.isFinite(this.surfaceOpacity)) {
      return 1;
    }
    return Math.max(0, Math.min(1, this.surfaceOpacity));
  }
}
