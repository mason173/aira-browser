import {
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_HORIZONTAL_INSET,
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING,
  BROWSER_FLOATING_CHROME_PRESSED_SCALE,
  BROWSER_FLOATING_CHROME_PRESS_DURATION_MS,
  BROWSER_FLOATING_CHROME_RELEASE_CURVE,
  BROWSER_FLOATING_CHROME_RELEASE_DURATION_MS
} from '../../../core/browser/BrowserBottomAddressPanelMetrics';
import { BrowserBottomPanelResponsiveViewModel } from '../../../core/browser/BrowserBottomPanelResponsiveViewModel';
import { BrowserTabsOverviewSection } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { AppChromeIconTone } from '../../../core/resources/AppIconResources';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  resolveBrowserTabsOverviewFloatingMaterialShadowColor,
  resolveBrowserBottomNeutralPressedColor,
  resolveBrowserBottomNeutralPrimaryColor,
  resolveBrowserBottomNeutralSecondaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserBottomChromeImmersiveMaterialSurface } from './BrowserBottomChromeImmersiveMaterialSurface';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import { resolveBrowserFloatingGlassMaterialTintForTone } from './BrowserFloatingGlassMaterialTokens';

export const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT: number = 44;
export const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_CONTENT_GAP: number = 16;
export const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE: number =
  BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_BOTTOM_GAP + BROWSER_BOTTOM_ADDRESS_PANEL_FLOATING_VERTICAL_PADDING;

const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE: number = 44;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP: number = 8;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_ICON_SIZE: number = 22;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET: number = 4;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_RADIUS: number = 40;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_OFFSET_Y: number = 0;
// The ordinary-tabs segment draws its own icon: a framed tab count instead of a glyph.
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_WIDTH: number = 24;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_HEIGHT: number = 20;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_RADIUS: number = 6;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_BORDER: number = 1.8;
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_OVERFLOW: number = 99;
// The selected segment keeps the neutral family: a grey plate, never the accent colour.
// It is lighter than the neighbouring pressed feedback so a selected segment still reads
// as selected while the finger is down on another one.
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_SELECTED_LIGHT: string = '#E6FFFFFF';
const BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_SELECTED_DARK: string = '#47FFFFFF';

@Component
export struct BrowserTabsOverviewBottomChrome {
  @Prop selectedSection: BrowserTabsOverviewSection = 'tabs';
  @Prop regularTabCount: number = 0;
  @Prop regularTabsLabel: string = '0 个标签页';
  @Prop privacyTabsLabel: string = '隐私标签页';
  @Prop crossDeviceTabsLabel: string = '跨设备标签页';
  @Prop viewportWidth: number = 390;
  @Prop viewportHeight: number = 844;
  @Prop bottomChromeLiftVp: number = 0;
  @Prop surfaceOpacity: number = 1;
  @Prop chromeInteractionEnabled: boolean = true;
  @Prop regularChromeIconTone: AppChromeIconTone = 'light';
  @Prop adaptiveForeground: boolean = true;
  @State private pressedOuterScaleTarget: string = '';
  @State private pressedOuterScale: number = 1;
  @State private pressedSegment: string = '';

  onReturn: () => void = () => {};
  onCreateHome: () => void = () => {};
  onSwitchToTabs: () => void = () => {};
  onSwitchToPrivacy: () => void = () => {};
  onOpenDeviceTabs: () => void = () => {};

  private responsiveViewModel: BrowserBottomPanelResponsiveViewModel = new BrowserBottomPanelResponsiveViewModel();

  aboutToDisappear(): void {
    this.resetOuterPressScale();
    this.pressedSegment = '';
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
      if (this.shouldUseHdsMaterialPlate()) {
        HdsImmersiveMaterialSurface({
          plateWidth: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE,
          plateHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
          plateRadius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2
        })
      }
      BrowserBottomChromeImmersiveMaterialSurface({
        surfaceWidth: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE,
        surfaceHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
        surfaceRadius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2,
        materialTint: this.resolveMaterialTint(),
        fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background'),
        hostMaterialActive: this.shouldUseHdsMaterialPlate()
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
      if (this.shouldUseHdsMaterialPlate()) {
        HdsImmersiveMaterialSurface({
          plateWidth: this.resolveSectionSwitcherWidth(),
          plateHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
          plateRadius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2
        })
      }
      BrowserBottomChromeImmersiveMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT,
        surfaceRadius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2,
        materialTint: this.resolveMaterialTint(),
        fallbackColor: $r('app.color.browser_bottom_toolbar_glass_background'),
        hostMaterialActive: this.shouldUseHdsMaterialPlate()
      }) {
        Row() {
          // Privacy, then the ordinary-tab count, then cross-device: the same three
          // sibling views the bottom bar carries, so the framed count stays the pivot.
          this.buildSegment('privacy', 'browser.toolbar.privacyMode')
          this.buildTabCountSegment()
          this.buildSegment('device', 'settings.themeMode.system')
        }
        .width('100%')
        .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT)
        .padding(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET)
        .alignItems(VerticalAlign.Center)
      }
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 1 })
    .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT)
    .borderRadius(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT / 2)
    .shadow(this.resolveMaterialShadow())
  }

  /**
   * Both arguments are constants at every call site, so the builder's by-value parameters cannot
   * go stale; everything that changes — selection, press state, colours, labels — is read from
   * `this` inside the builder.
   *
   * The segment is a `layoutWeight(1)` cell inside the capsule's padded row. Every segment
   * therefore takes exactly one third of what the inset leaves, so the three plates are equal
   * width, and a selected plate lands at the same inset on every side — the capsule is fully
   * packed by whichever segment is selected.
   */
  @Builder
  private buildSegment(target: string, iconId: AiraRenderableIconId) {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_ICON_SIZE,
        iconColor: this.resolveSegmentContentColor(target)
      })
        .hitTestBehavior(HitTestMode.None)
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 1 })
    .height(this.resolveSegmentHeight())
    .backgroundColor(this.resolveSegmentBackground(target))
    .borderRadius(this.resolveSegmentHeight() / 2)
    .accessibilityText(this.resolveSegmentAccessibilityText(target))
    .onTouch((event: TouchEvent) => {
      this.updatePressedSegment(target, event.type);
    })
    .onClick(() => {
      this.dispatchSegmentAction(target);
    })
  }

  /**
   * The ordinary-tabs segment is its own icon: a rounded frame that carries the live tab
   * count, so the bar reports a number where the neighbouring segments show a glyph.
   */
  @Builder
  private buildTabCountSegment() {
    Stack({ alignContent: Alignment.Center }) {
      Stack({ alignContent: Alignment.Center }) {
        Text(this.resolveTabCountText())
          .fontSize(this.resolveTabCountFontSize())
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveSegmentContentColor('tabs'))
          .minFontScale(1)
          .maxFontScale(1)
          .maxLines(1)
          .textAlign(TextAlign.Center)
          .hitTestBehavior(HitTestMode.None)
      }
      .width(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_WIDTH)
      .height(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_HEIGHT)
      .borderRadius(BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_RADIUS)
      .border({
        width: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_FRAME_BORDER,
        color: this.resolveSegmentContentColor('tabs')
      })
    }
    .layoutWeight(1)
    .constraintSize({ minWidth: 1 })
    .height(this.resolveSegmentHeight())
    .backgroundColor(this.resolveSegmentBackground('tabs'))
    .borderRadius(this.resolveSegmentHeight() / 2)
    .accessibilityText(this.regularTabsLabel)
    .onTouch((event: TouchEvent) => {
      this.updatePressedSegment('tabs', event.type);
    })
    .onClick(() => {
      this.dispatchSegmentAction('tabs');
    })
  }

  private dispatchSegmentAction(target: string): void {
    if (!this.chromeInteractionEnabled) {
      return;
    }
    if (target === 'device') {
      // The cross-device segment is a section tab like its neighbours, but entering it is
      // gated: the shell resolves entitlement and sign-in before the section may be shown,
      // so the segment reports the request instead of switching on its own.
      if (this.selectedSection === 'devices') {
        return;
      }
      this.onOpenDeviceTabs();
      return;
    }
    this.dispatchSectionAction(target as BrowserTabsOverviewSection);
  }

  private updatePressedSegment(target: string, touchType: TouchType): void {
    if (!this.chromeInteractionEnabled) {
      this.pressedSegment = '';
      return;
    }
    if (touchType === TouchType.Down) {
      this.pressedSegment = target;
      return;
    }
    if (touchType === TouchType.Up || touchType === TouchType.Cancel) {
      if (this.pressedSegment === target) {
        this.pressedSegment = '';
      }
    }
  }

  private isSegmentSelected(target: string): boolean {
    if (target === 'tabs') {
      return this.selectedSection === 'tabs';
    }
    if (target === 'privacy') {
      return this.selectedSection === 'privacy';
    }
    return this.selectedSection === 'devices';
  }

  private resolveSegmentHeight(): number {
    return BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT -
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_INSET * 2;
  }

  private resolveSegmentBackground(target: string): ResourceColor {
    if (this.isSegmentSelected(target)) {
      return this.resolveSelectedSegmentColor();
    }
    if (this.pressedSegment === target) {
      return resolveBrowserBottomNeutralPressedColor(this.resolveMaterialMode());
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  /**
   * Selection is a grey plate on both the active and the pressed segment, so the label colour
   * never has to change with the theme: the accent colour is not part of this cluster.
   */
  private resolveSelectedSegmentColor(): ResourceColor {
    return this.resolveMaterialMode() === 'dark' ? BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_SELECTED_DARK :
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SEGMENT_SELECTED_LIGHT;
  }

  private resolveSegmentContentColor(target: string): ResourceColor {
    if (this.isSegmentSelected(target)) {
      return this.resolvePrimaryColor();
    }
    return this.resolveSecondaryColor();
  }

  private resolveSegmentAccessibilityText(target: string): string {
    if (target === 'privacy') {
      return this.privacyTabsLabel;
    }
    if (target === 'device') {
      return this.crossDeviceTabsLabel;
    }
    return this.regularTabsLabel;
  }

  private resolveTabCountText(): string {
    const count = this.resolveNormalizedTabCount();
    return count > BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_OVERFLOW ?
      `${BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_COUNT_OVERFLOW}+` : `${count}`;
  }

  private resolveTabCountFontSize(): number {
    const digits = this.resolveTabCountText().length;
    if (digits <= 1) {
      return 13;
    }
    return digits === 2 ? 11 : 8;
  }

  private resolveNormalizedTabCount(): number {
    if (!Number.isFinite(this.regularTabCount)) {
      return 0;
    }
    return Math.max(0, Math.floor(this.regularTabCount));
  }

  private resolveSecondaryColor(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.font_secondary') :
      resolveBrowserBottomNeutralSecondaryColor(this.resolveMaterialMode());
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

  private shouldUseHdsMaterialPlate(): boolean {
    return isHdsMaterialAvailable();
  }

  /**
   * The middle cluster spans whatever the two outer buttons and the gaps leave over, and
   * the HDS floating bar needs that span as a concrete value rather than a percentage.
   */
  private resolveSectionSwitcherWidth(): number {
    const reserved = (BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_OUTER_SIZE +
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BLOCK_GAP) * 2;
    return Math.max(1, this.resolveChromeWidth() - reserved);
  }

  private resolvePrimaryColor(): ResourceColor {
    return this.adaptiveForeground ? $r('sys.color.icon_primary') :
      resolveBrowserBottomNeutralPrimaryColor(this.resolveMaterialMode());
  }

  private resolveMaterialShadow(): ShadowOptions {
    return {
      radius: BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_SHADOW_RADIUS,
      color: resolveBrowserTabsOverviewFloatingMaterialShadowColor(this.resolveMaterialMode()),
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
    return Math.max(0, this.viewportHeight - this.resolveBottomClearance() -
      BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_HEIGHT);
  }

  private resolveBottomClearance(): number {
    const lift = Number.isFinite(this.bottomChromeLiftVp) ? Math.max(0, this.bottomChromeLiftVp) : 0;
    return BROWSER_TABS_OVERVIEW_BOTTOM_CHROME_BOTTOM_CLEARANCE + lift;
  }

  private resolveSurfaceOpacity(): number {
    if (!Number.isFinite(this.surfaceOpacity)) {
      return 1;
    }
    return Math.max(0, Math.min(1, this.surfaceOpacity));
  }
}
