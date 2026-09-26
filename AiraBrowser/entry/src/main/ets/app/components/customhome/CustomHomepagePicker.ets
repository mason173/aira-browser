import { ShortcutRecord } from '../../../common/models/BrowserModels';
import {
  DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE,
  HomeWallpaperPresentationState
} from '../../../common/models/WallpaperModels';
import {
  CustomHomepageCarouselCard,
  CustomHomepageChoiceViewState
} from '../../../core/customhome/CustomHomepageSettingsViewModel';
import { CustomHomepagePreviewLayoutState } from '../../../core/customhome/CustomHomepagePreviewViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import { HdsImmersiveMaterialSurface } from '../common/HdsImmersiveMaterialSurface';
import { isHdsMaterialAvailable } from '../common/HdsImmersiveMaterialTokens';
import { SiteIconView } from '../common/SiteIconView';
import { HomepagePreviewClosedItem, SystemHomepageLivePreview } from './SystemHomepageLivePreview';

const HOMEPAGE_CARD_STRIP_FRICTION: number = 0.92;
const HOMEPAGE_CARD_PRESSED_SCALE: number = 0.95;

@Component
export struct CustomHomepagePicker {
  private scroller: Scroller = new Scroller();
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F4F6F8';
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop cards: CustomHomepageCarouselCard[] = [];
  @Prop choices: CustomHomepageChoiceViewState[] = [];
  @Prop layoutState: CustomHomepagePreviewLayoutState = {
    cardWidth: 220,
    cardHeight: 460,
    listHeight: 460,
    cardGap: 16,
    cardRadius: 24,
    sidePeek: 28,
    orientation: 'portrait'
  };
  @Prop shortcuts: ShortcutRecord[] = [];
  @Prop showShortcuts: boolean = true;
  @Prop wallpaper: HomeWallpaperPresentationState = DEFAULT_HOME_WALLPAPER_PRESENTATION_STATE;
  @Prop closedItems: HomepagePreviewClosedItem[] = [];
  @Prop showRecentlyClosed: boolean = true;
  @Prop previewRevision: number = 0;
  @Prop pageBackground: string = '';
  @Prop focusedIndex: number = 0;
  @Prop @Watch('jumpToFocusedCard') jumpToken: number = 0;
  @Prop busy: boolean = false;
  @State private appliedJumpToken: number = -1;
  @State private listWidth: number = 0;
  @State private pressedCardKey: string = '';
  private listReady: boolean = false;
  private positionedWidth: number = 0;
  onCardFocus: (index: number) => void = (_index: number) => {};
  onApply: () => void = () => {};
  onOpenSettings: (choice: CustomHomepageChoiceViewState) => void = (_choice: CustomHomepageChoiceViewState) => {};

  build() {
    Column() {
      Column() {
        Text(this.resolveFocusedTitle())
          .width('100%')
          .height(28)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ bottom: 6 })
      .backgroundColor(this.resolveCanvasColor())
      .zIndex(2)

      List({ space: this.layoutState.cardGap, scroller: this.scroller }) {
        ForEach(this.cards, (card: CustomHomepageCarouselCard) => {
          ListItem() {
            Column() {
              this.buildCard(card)
            }
            .width('100%')
            .height('100%')
            .alignItems(HorizontalAlign.Center)
            .justifyContent(FlexAlign.Center)
            .clip(false)
          }
          .width(this.layoutState.cardWidth)
          .height(this.layoutState.cardHeight)
          .clip(false)
        }, (card: CustomHomepageCarouselCard) => this.resolveCardKey(card))
      }
      .width('100%')
      .height(this.layoutState.cardHeight)
      .listDirection(Axis.Horizontal)
      .alignListItem(ListItemAlign.Center)
      .scrollSnapAlign(ScrollSnapAlign.CENTER)
      .contentStartOffset(this.resolveEdgeInset())
      .contentEndOffset(this.resolveEdgeInset())
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .friction(HOMEPAGE_CARD_STRIP_FRICTION)
      .clip(false)
      .onScrollIndex((_start: number, _end: number, center: number) => {
        this.reportCenteredCard(center);
      })
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        this.updateListWidth(newArea);
      })
      .onAppear(() => {
        this.listReady = true;
        this.jumpToFocusedCard();
      })
      .onTouch((event: TouchEvent) => {
        this.updateCardPress(event);
      })

      Row() {
        Button(this.resolveApplyLabel())
          .layoutWeight(1)
          .height(40)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveApplyTextColor())
          .backgroundColor(this.resolveApplyBackgroundColor())
          .borderRadius(20)
          .enabled(this.canApply())
          .opacity(this.busy ? 0.6 : 1)
          .onClick(() => {
            this.onApply();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .margin({ top: 16, bottom: 32 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildCard(card: CustomHomepageCarouselCard) {
    Stack() {
      this.buildCardSurface(card)
    }
    .width(this.layoutState.cardWidth)
    .height(this.layoutState.cardHeight)
    .borderRadius(this.layoutState.cardRadius)
    .scale({
      x: this.resolveCardScale(card),
      y: this.resolveCardScale(card)
    })
    .animation({
      duration: this.isCardPressed(card) ? 120 : 260,
      curve: this.isCardPressed(card) ? Curve.EaseOut : Curve.Friction
    })
    .shadow({
      radius: 42,
      color: '#14000000',
      offsetX: 0,
      offsetY: 16
    })
  }

  @Builder
  private buildCardSurface(card: CustomHomepageCarouselCard) {
    Stack({ alignContent: Alignment.TopEnd }) {
      if (card.kind === 'system') {
        SystemHomepageLivePreview({
          style: card.systemStyle,
          shortcuts: this.shortcuts,
          showShortcuts: this.showShortcuts,
          wallpaper: this.wallpaper,
          closedItems: this.closedItems,
          showRecentlyClosed: this.showRecentlyClosed,
          cardWidth: this.layoutState.cardWidth,
          cardHeight: this.layoutState.cardHeight
        })
      } else {
        this.buildCustomCover(card)
      }
      if (card.kind === 'custom') {
        this.buildCardSettingsButton(card)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(this.layoutState.cardRadius)
    .border({ width: 0.5, color: this.storedDividerColor })
    .clip(true)
  }

  @Builder
  private buildCustomCover(card: CustomHomepageCarouselCard) {
    if (this.resolvePreviewPath(card).length > 0) {
      Image(this.resolvePreviewPath(card))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .interpolation(ImageInterpolation.High)
        .backgroundColor(this.storedControlBackgroundColor)
    } else {
      Column({ space: 12 }) {
        SiteIconView({
          iconUri: this.resolveSiteIconPath(card),
          fallbackLabel: card.title,
          iconSize: Math.max(48, Math.round(this.layoutState.cardWidth * 0.22)),
          cornerRadiusRatio: 0.3,
          frameBorderWidth: 0,
          contentPadding: 0,
          fallbackFontSize: 22,
          containerBackgroundColor: this.storedControlBackgroundColor,
          frameBorderColor: this.storedDividerColor,
          textColor: this.storedSecondaryTextColor,
          fit: ImageFit.Contain,
          hitTestMode: HitTestMode.None
        })
        Text(card.title)
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .padding(16)
      .backgroundColor(this.storedControlBackgroundColor)
    }
  }

  @Builder
  private buildCardSettingsButton(card: CustomHomepageCarouselCard) {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldUseHdsMaterial()) {
        HdsImmersiveMaterialSurface({
          plateWidth: 36,
          plateHeight: 36,
          plateRadius: 18
        })
      }
      Button() {
        AiraIcon({
          airaIconId: 'browser.home.settings',
          iconSize: 18,
          iconColor: $r('sys.color.icon_primary')
        })
      }
      .width(36)
      .height(36)
      .type(ButtonType.Normal)
      .stateEffect(true)
      .backgroundColor(this.resolveCardSettingsBackground())
      .borderRadius(18)
      .accessibilityText('主页设置')
      .enabled(!this.busy)
      .hitTestBehavior(HitTestMode.Default)
      .onClick(() => {
        this.openCardSettings(card);
      })
      .priorityGesture(
        TapGesture({ count: 1 })
          .onAction(() => {
            this.openCardSettings(card);
          }),
        GestureMask.Normal
      )
    }
    .width(36)
    .height(36)
    .margin({ top: 10, right: 10 })
    .borderRadius(18)
    .zIndex(2)
  }

  private shouldUseHdsMaterial(): boolean {
    return isHdsMaterialAvailable();
  }

  private resolveCardSettingsBackground(): ResourceColor {
    return this.shouldUseHdsMaterial() ?
      $r('sys.color.ohos_id_color_background_transparent') : this.storedControlBackgroundColor;
  }

  private jumpToFocusedCard(): void {
    if (!this.listReady || this.listWidth <= 0 || this.cards.length <= 0) {
      return;
    }
    if (this.jumpToken === this.appliedJumpToken && this.positionedWidth === this.listWidth) {
      return;
    }
    this.appliedJumpToken = this.jumpToken;
    this.positionedWidth = this.listWidth;
    const index = Math.min(Math.max(this.focusedIndex, 0), this.cards.length - 1);
    this.scroller.scrollToIndex(index, false, ScrollAlign.CENTER);
  }

  private updateListWidth(area: Area): void {
    const width = Number(area.width);
    if (!Number.isFinite(width) || width <= 0 || width === this.listWidth) {
      return;
    }
    this.listWidth = width;
    this.jumpToFocusedCard();
  }

  private resolveEdgeInset(): number {
    if (this.listWidth > this.layoutState.cardWidth) {
      return Math.max(0, (this.listWidth - this.layoutState.cardWidth) / 2);
    }
    return this.layoutState.sidePeek;
  }

  private resolveCardKey(card: CustomHomepageCarouselCard): string {
    if (card.kind !== 'system') {
      return card.key;
    }
    return `${card.key}:${this.previewRevision}`;
  }

  private updateCardPress(event: TouchEvent): void {
    if (event.type === TouchType.Down) {
      this.pressedCardKey = this.resolveTouchedCardKey(event);
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.pressedCardKey = '';
    }
  }

  private resolveTouchedCardKey(event: TouchEvent): string {
    if (event.touches.length <= 0 || this.cards.length <= 0) {
      return '';
    }
    const stride = this.layoutState.cardWidth + this.layoutState.cardGap;
    if (stride <= 0) {
      return '';
    }
    const contentX = event.touches[0].x + this.resolveScrollOffsetX() - this.resolveEdgeInset();
    if (contentX < 0) {
      return '';
    }
    const index = Math.floor(contentX / stride);
    const withinCard = contentX - index * stride;
    if (index < 0 || index >= this.cards.length || withinCard > this.layoutState.cardWidth) {
      return '';
    }
    return this.resolveCardKey(this.cards[index]);
  }

  private resolveScrollOffsetX(): number {
    return this.scroller.currentOffset().xOffset;
  }

  private isCardPressed(card: CustomHomepageCarouselCard): boolean {
    return this.pressedCardKey.length > 0 && this.pressedCardKey === this.resolveCardKey(card);
  }

  private resolveCardScale(card: CustomHomepageCarouselCard): number {
    return this.isCardPressed(card) ? HOMEPAGE_CARD_PRESSED_SCALE : 1;
  }

  private reportCenteredCard(center: number): void {
    if (center < 0 || center >= this.cards.length || center === this.focusedIndex) {
      return;
    }
    this.onCardFocus(center);
  }

  private openCardSettings(card: CustomHomepageCarouselCard): void {
    if (card.kind !== 'custom' || this.busy) {
      return;
    }
    const choice = this.resolveChoice(card);
    if (choice !== undefined) {
      this.onOpenSettings(choice);
    }
  }

  private resolveFocusedCard(): CustomHomepageCarouselCard | undefined {
    if (this.focusedIndex < 0 || this.focusedIndex >= this.cards.length) {
      return undefined;
    }
    return this.cards[this.focusedIndex];
  }

  private resolveCanvasColor(): string {
    return this.pageBackground.length > 0 ? this.pageBackground : this.storedPageBackgroundColor;
  }

  private resolveFocusedTitle(): string {
    const card = this.resolveFocusedCard();
    return card !== undefined ? card.title : '主页设置';
  }

  private resolveApplyLabel(): string {
    const card = this.resolveFocusedCard();
    if (card !== undefined && card.isCurrent) {
      return '当前主页';
    }
    return '应用主页';
  }

  private canApply(): boolean {
    const card = this.resolveFocusedCard();
    return !this.busy && card !== undefined && !card.isCurrent;
  }

  private resolveApplyTextColor(): ResourceColor {
    return this.canApply() ? this.storedOnPrimaryColor : this.storedSecondaryTextColor;
  }

  private resolveApplyBackgroundColor(): ResourceColor {
    return this.canApply() ? this.storedAccentColor : this.storedControlBackgroundColor;
  }

  private resolveChoice(card: CustomHomepageCarouselCard): CustomHomepageChoiceViewState | undefined {
    return this.choices.find((choice: CustomHomepageChoiceViewState): boolean => choice.id === card.choiceId);
  }

  private resolvePreviewPath(card: CustomHomepageCarouselCard): string {
    const choice = this.resolveChoice(card);
    return choice !== undefined ? choice.previewPath.trim() : '';
  }

  private resolveSiteIconPath(card: CustomHomepageCarouselCard): string {
    const choice = this.resolveChoice(card);
    return choice !== undefined ? choice.siteIconPath : '';
  }
}
