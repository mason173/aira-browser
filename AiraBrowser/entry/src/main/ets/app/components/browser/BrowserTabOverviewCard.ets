import { image } from '@kit.ImageKit';
import {
  BrowserTabOverviewCardPresentation,
  BrowserTabsOverlayRect,
  BrowserTabsOverlayViewModel
} from '../../../core/browser/BrowserTabsOverlayViewModel';
import { BrowserTabState } from '../../../core/tabs/TabManager';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BROWSER_TABS_OVERVIEW_CARD_CORNER_RADIUS } from '../../../core/browser/BrowserTabsOverviewVisualTokens';
import { AiraIcon } from '../common/AiraIcon';

const TAB_OVERVIEW_PENDING_SKELETON_RADIUS: number = 7;
const TAB_OVERVIEW_CARD_BORDER_WIDTH: number = 0.5;
const TAB_OVERVIEW_KEYBOARD_BADGE_SIZE: number = 32;
const TAB_OVERVIEW_KEYBOARD_BADGE_RADIUS: number = 16;
const TAB_OVERVIEW_CARD_CLOSE_BUTTON_SIZE: number = 32;
const TAB_OVERVIEW_CARD_CLOSE_BUTTON_MARGIN: number = 8;
const TAB_OVERVIEW_CARD_CLOSE_BUTTON_ICON_SIZE: number = 18;
const TAB_OVERVIEW_CARD_CLOSE_BUTTON_REVEAL_MS: number = 120;
const TAB_OVERVIEW_PRIVATE_SNAPSHOT_BLUR_RADIUS: number = 32;

export interface BrowserTabOverviewCardSelectRect {
  left: number;
  top: number;
  width: number;
  height: number;
}

@Reusable
@Component
export struct BrowserTabOverviewCard {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop tab: BrowserTabState;
  @Watch('syncRenderableSnapshotFromProps')
  @Prop presentation: BrowserTabOverviewCardPresentation;
  @Watch('syncRenderableSnapshotFromProps')
  @Prop snapshotImageUri: string = '';
  @Watch('syncRenderableSnapshotFromProps')
  @Prop snapshotPixelMap: image.PixelMap | undefined = undefined;
  @Prop snapshotAspectFitEnabled: boolean = false;
  @Prop previewHeight: number = 1;
  @Prop cardWidth: number = 132;
  @Prop previewCardOpacity: number = 1;
  @Prop snapshotImageOpacity: number = 1;
  @Prop decorationOpacity: number = 1;
  @Prop coveredByMorph: boolean = false;
  @Prop tabEnabled: boolean = true;
  @Prop trackPreviewRectChanges: boolean = false;
  @Prop closeButtonEnabled: boolean = true;
  @Prop closeButtonAlwaysVisible: boolean = false;
  @Prop keyboardBadgeText: string = '';
  @Prop showKeyboardBadge: boolean = false;
  @State private closeButtonHovered: boolean = false;
  @State private renderSnapshotImageUri: string = '';
  @State private renderSnapshotPixelMap: image.PixelMap | undefined = undefined;
  @State private renderSnapshotImageWidth: number = 0;
  @State private renderSnapshotImageHeight: number = 0;
  private tabsOverlayViewModel: BrowserTabsOverlayViewModel = new BrowserTabsOverlayViewModel();

  onCloseTab: (tabId: string) => void = (_tabId: string) => {};
  onPreviewRectChange: (
    tabId: string,
    left: number,
    top: number,
    width: number,
    height: number
  ) => void = (_tabId: string, _left: number, _top: number, _width: number, _height: number) => {};

  aboutToAppear(): void {
    this.syncRenderableSnapshotFromProps();
  }

  aboutToReuse(params: Record<string, Object>): void {
    this.tab = params.tab as BrowserTabState;
    this.presentation = params.presentation as BrowserTabOverviewCardPresentation;
    this.snapshotImageUri = params.snapshotImageUri as string;
    this.snapshotPixelMap = params.snapshotPixelMap as image.PixelMap | undefined;
    this.snapshotAspectFitEnabled = (params.snapshotAspectFitEnabled as boolean) === true;
    this.previewHeight = params.previewHeight as number;
    this.cardWidth = params.cardWidth as number;
    this.previewCardOpacity = params.previewCardOpacity as number;
    this.snapshotImageOpacity = params.snapshotImageOpacity as number;
    this.decorationOpacity = params.decorationOpacity as number;
    this.coveredByMorph = (params.coveredByMorph as boolean) === true;
    this.tabEnabled = params.tabEnabled as boolean;
    this.trackPreviewRectChanges = params.trackPreviewRectChanges as boolean;
    this.closeButtonEnabled = params.closeButtonEnabled === undefined ||
      (params.closeButtonEnabled as boolean) === true;
    this.closeButtonAlwaysVisible = (params.closeButtonAlwaysVisible as boolean) === true;
    this.keyboardBadgeText = params.keyboardBadgeText as string;
    this.showKeyboardBadge = params.showKeyboardBadge as boolean;
    this.onCloseTab = params.onCloseTab as (tabId: string) => void;
    this.onPreviewRectChange = params.onPreviewRectChange as (
      tabId: string,
      left: number,
      top: number,
      width: number,
      height: number
    ) => void;
    this.closeButtonHovered = false;
    this.syncRenderableSnapshotFromProps();
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      this.buildTabCardSurface()

      if (this.shouldShowKeyboardBadge()) {
        this.buildKeyboardBadge()
      }

      this.buildCloseButton()
    }
    .width('100%')
    .height('100%')
    .onHover((isHover: boolean) => {
      this.closeButtonHovered = isHover;
    })
  }

  @Builder
  private buildTabCardSurface() {
    Column({ space: 0 }) {
      this.buildPreviewCard()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.getPreviewBackgroundColor())
    .border({ width: TAB_OVERVIEW_CARD_BORDER_WIDTH, color: this.storedOutlineColor })
    .borderRadius(BROWSER_TABS_OVERVIEW_CARD_CORNER_RADIUS)
    .clip(true)
    .opacity(this.resolveEffectivePreviewCardOpacity())
    .zIndex(1)
  }

  @Builder
  private buildPreviewCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildPreviewSurface()
    }
    .width('100%')
    .height(this.previewHeight)
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      if (!this.trackPreviewRectChanges) {
        return;
      }
      this.onPreviewRectChange(
        this.tab.id,
        this.parseAreaPosition(newArea.globalPosition.x),
        this.parseAreaPosition(newArea.globalPosition.y),
        this.parseAreaDimension(newArea.width),
        this.parseAreaDimension(newArea.height)
      );
    })
  }

  @Builder
  private buildKeyboardBadge() {
    Stack({ alignContent: Alignment.Center }) {
      Text(this.keyboardBadgeText)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedOnPrimaryColor)
        .maxLines(1)
        .textAlign(TextAlign.Center)
    }
    .width(TAB_OVERVIEW_KEYBOARD_BADGE_SIZE)
    .height(TAB_OVERVIEW_KEYBOARD_BADGE_SIZE)
    .borderRadius(TAB_OVERVIEW_KEYBOARD_BADGE_RADIUS)
    .backgroundColor(this.storedAccentColor)
    .opacity(this.decorationOpacity)
    .shadow({
      radius: 10,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: 2
    })
    .position({
      x: this.resolveKeyboardBadgeLeft(),
      y: this.resolveKeyboardBadgeTop()
    })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(4)
  }

  @Builder
  private buildCloseButton() {
    Button({ type: ButtonType.Circle }) {
      AiraIcon({
        airaIconId: 'browser.tabs.overviewClose',
        iconSize: TAB_OVERVIEW_CARD_CLOSE_BUTTON_ICON_SIZE,
        iconColor: this.storedPrimaryTextColor
      })
    }
    .width(TAB_OVERVIEW_CARD_CLOSE_BUTTON_SIZE)
    .height(TAB_OVERVIEW_CARD_CLOSE_BUTTON_SIZE)
    .backgroundColor(this.resolveCloseButtonBackgroundColor())
    .opacity(this.resolveCloseButtonOpacity())
    .scale({
      x: this.resolveCloseButtonScale(),
      y: this.resolveCloseButtonScale()
    })
    .shadow({
      radius: 10,
      color: $r('app.color.elevation_shadow'),
      offsetX: 0,
      offsetY: 2
    })
    .position({
      x: TAB_OVERVIEW_CARD_CLOSE_BUTTON_MARGIN,
      y: TAB_OVERVIEW_CARD_CLOSE_BUTTON_MARGIN
    })
    .enabled(this.shouldShowCloseButton())
    .hitTestBehavior(this.shouldShowCloseButton() ? HitTestMode.Default : HitTestMode.None)
    .accessibilityText('关闭标签页')
    .zIndex(5)
    .animation({
      duration: TAB_OVERVIEW_CARD_CLOSE_BUTTON_REVEAL_MS,
      curve: Curve.EaseOut
    })
    .onClick(() => {
      this.onCloseTab(this.tab.id);
    })
  }

  @Builder
  private buildPreviewSurface() {
    if (this.shouldRenderSharedSnapshot()) {
      this.buildSharedSnapshotImage()
    } else if (this.presentation.previewKind === 'home') {
      this.buildHomePreviewPlaceholder()
    } else if (this.presentation.previewKind === 'pending') {
      this.buildPendingPreviewPlaceholder()
    }
  }

  @Builder
  private buildHomePreviewPlaceholder() {
    Column({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        SymbolGlyph($r('sys.symbol.house_fill'))
          .fontSize(32)
          .fontColor([this.storedSecondaryTextColor])
      }
      .width(76)
      .height(76)
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(22)

      Text('新建标签页')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildPendingPreviewPlaceholder() {
    Column({ space: 10 }) {
      Row()
        .width('52%')
        .height(14)
        .borderRadius(TAB_OVERVIEW_PENDING_SKELETON_RADIUS)
        .backgroundColor(this.storedControlBackgroundColor)

      Row()
        .width('86%')
        .height(58)
        .borderRadius(12)
        .backgroundColor(this.storedControlBackgroundColor)

      Column({ space: 7 }) {
        Row()
          .width('100%')
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.storedControlBackgroundColor)

        Row()
          .width('72%')
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.storedControlBackgroundColor)

        Row()
          .width('44%')
          .height(10)
          .borderRadius(5)
          .backgroundColor(this.storedControlBackgroundColor)
      }
      .width('86%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 16, right: 16 })
  }

  private shouldRenderSharedSnapshot(): boolean {
    return this.resolveRenderableSnapshotImageUri().trim().length > 0 ||
      this.resolveRenderableSnapshotPixelMap() !== undefined;
  }

  private resolveEffectivePreviewCardOpacity(): number {
    if (this.coveredByMorph) {
      return 0;
    }
    return this.previewCardOpacity;
  }

  private resolveEffectiveSnapshotImageOpacity(): number {
    if (this.coveredByMorph) {
      return 0;
    }
    return this.snapshotImageOpacity;
  }

  @Builder
  private buildSharedSnapshotImage() {
    if (this.resolveRenderableSnapshotImageUri().trim().length > 0) {
      Image(this.resolveRenderableSnapshotImageUri())
        .width(this.resolveSnapshotImageRenderWidth())
        .height(this.resolveSnapshotImageRenderHeight())
        .objectFit(this.snapshotAspectFitEnabled ? ImageFit.Contain : ImageFit.Fill)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Medium)
        .opacity(this.resolveEffectiveSnapshotImageOpacity())
        .blur(this.resolveSharedSnapshotBlurRadius())
        .position({ x: this.resolveSnapshotImageLeft(), y: this.resolveSnapshotImageTop() })
    } else if (this.resolveRenderableSnapshotPixelMap() !== undefined) {
      Image(this.resolveRenderableSnapshotPixelMap() as image.PixelMap)
        .width(this.resolveSnapshotImageRenderWidth())
        .height(this.resolveSnapshotImageRenderHeight())
        .objectFit(this.snapshotAspectFitEnabled ? ImageFit.Contain : ImageFit.Fill)
        .syncLoad(true)
        .interpolation(ImageInterpolation.Medium)
        .opacity(this.resolveEffectiveSnapshotImageOpacity())
        .blur(this.resolveSharedSnapshotBlurRadius())
        .position({ x: this.resolveSnapshotImageLeft(), y: this.resolveSnapshotImageTop() })
    }
  }

  private resolveSnapshotImageRenderWidth(): number {
    if (this.snapshotAspectFitEnabled) {
      return Math.max(1, this.cardWidth);
    }
    return Math.max(1, this.resolveSnapshotPreviewImageRect().width);
  }

  private resolveSnapshotImageRenderHeight(): number {
    if (this.snapshotAspectFitEnabled) {
      return Math.max(1, this.previewHeight);
    }
    return Math.max(1, this.resolveSnapshotPreviewImageRect().height);
  }

  private resolveSnapshotImageLeft(): number {
    if (this.snapshotAspectFitEnabled) {
      return 0;
    }
    return this.resolveSnapshotPreviewImageRect().left;
  }

  private resolveSnapshotImageTop(): number {
    if (this.snapshotAspectFitEnabled) {
      return 0;
    }
    return this.resolveSnapshotPreviewImageRect().top;
  }

  private resolveSnapshotPreviewImageRect(): BrowserTabsOverlayRect {
    return this.tabsOverlayViewModel.buildSharedSnapshotPreviewImageRect(
      Math.max(1, this.cardWidth),
      Math.max(1, this.previewHeight),
      this.resolveSnapshotImageWidth(),
      this.resolveSnapshotImageHeight()
    );
  }

  private resolveSnapshotImageWidth(): number {
    return Math.max(1, this.renderSnapshotImageWidth);
  }

  private resolveSnapshotImageHeight(): number {
    return Math.max(1, this.renderSnapshotImageHeight);
  }

  private syncRenderableSnapshotFromProps(): void {
    this.renderSnapshotImageUri = this.snapshotImageUri.trim();
    this.renderSnapshotPixelMap = this.snapshotPixelMap;
    this.renderSnapshotImageWidth = Math.max(1, Math.floor(this.presentation.sharedSnapshotImageWidth));
    this.renderSnapshotImageHeight = Math.max(1, Math.floor(this.presentation.sharedSnapshotImageHeight));
  }

  private resolveRenderableSnapshotImageUri(): string {
    const localUri = this.renderSnapshotImageUri.trim();
    return localUri.length > 0 ? localUri : this.snapshotImageUri.trim();
  }

  private resolveRenderableSnapshotPixelMap(): image.PixelMap | undefined {
    return this.renderSnapshotPixelMap ?? this.snapshotPixelMap;
  }

  private getPreviewBackgroundColor(): ResourceColor {
    switch (this.presentation.previewKind) {
      case 'home':
        return this.storedPressedBackgroundColor;
      case 'snapshot':
      case 'pending':
        return this.storedSurfaceBackgroundColor;
      default:
        return $r('sys.color.ohos_id_color_background_transparent');
    }
  }

  private shouldShowKeyboardBadge(): boolean {
    return this.showKeyboardBadge && this.keyboardBadgeText.trim().length > 0;
  }

  private shouldShowCloseButton(): boolean {
    return this.closeButtonEnabled && this.tabEnabled &&
      (this.closeButtonAlwaysVisible || this.closeButtonHovered);
  }

  private resolveCloseButtonOpacity(): number {
    return this.shouldShowCloseButton() ? this.decorationOpacity : 0;
  }

  private resolveCloseButtonScale(): number {
    return this.shouldShowCloseButton() ? 1 : 0.82;
  }

  private resolveCloseButtonBackgroundColor(): ResourceColor {
    return this.storedSurfaceBackgroundColor;
  }

  private resolveKeyboardBadgeLeft(): number {
    return Math.max(0, (this.cardWidth - TAB_OVERVIEW_KEYBOARD_BADGE_SIZE) / 2);
  }

  private resolveKeyboardBadgeTop(): number {
    return Math.max(0, (this.previewHeight - TAB_OVERVIEW_KEYBOARD_BADGE_SIZE) / 2);
  }

  private resolveSharedSnapshotBlurRadius(): number {
    return this.presentation.shouldBlurSnapshot ? TAB_OVERVIEW_PRIVATE_SNAPSHOT_BLUR_RADIUS : 0;
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  private parseAreaPosition(value?: Length): number {
    if (value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
