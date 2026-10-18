import { AnimatorResult } from '@kit.ArkUI';
import { resolveAppResourceText } from '../../../core/resources/AppResourceText';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import {
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
  browserSheetHeaderBlurModifier,
  resolveBrowserSheetHeaderBlurRadius
} from '../browser/BrowserModalBottomSheet';
import {
  AppRecommendationEntry,
  AppRecommendationFaq,
  AppRecommendationReview,
  appRecommendationEntryFor,
  buildEmptyAppRecommendationEntry
} from './AppRecommendationContent';

// The card mirrors the recommended app's own product page: an app icon in a
// rounded square, the product name and phrase, a product phrase held by two
// laurel branches, a sample review band, and centred questions. The measurements
// are that page's, so the recommendation and the app it points at read as one
// product family.
//
// Every section is optional. A campaign with no sample reviews, no questions, or
// no laurel phrase simply draws a shorter card instead of an empty one.
const HERO_ICON_SIZE: number = 80;
const HERO_ICON_RADIUS: number = 20;
const HERO_TOP_PADDING: number = 24;
const HERO_ICON_NAME_GAP: number = 20;
const HERO_COPY_GAP: number = 8;
const HERO_BOTTOM_PADDING: number = 32;
const TITLE_FONT_SIZE: number = 24;
const TITLE_LINE_HEIGHT: number = 32;
const BODY_FONT_SIZE: number = 16;
const BODY_LINE_HEIGHT: number = 22;
const SUBTITLE_LINE_HEIGHT: number = 24;
const CAPTION_FONT_SIZE: number = 14;
const CAPTION_LINE_HEIGHT: number = 19;
const SECTION_GAP: number = 32;
const HEADING_TOP_GAP: number = 24;
const HEADING_BOTTOM_GAP: number = 14;
const FAQ_TITLE_GAP: number = 4;
const FAQ_ICON_SIZE: number = 24;
const FAQ_TEXT_INSET: number = 16;
const CONTENT_INSET: number = 16;
const LAUREL_ICON_WIDTH: number = 17;
const LAUREL_ICON_HEIGHT: number = 36;
const LAUREL_COPY_GAP: number = 4;
const LAUREL_ITEM_INSET: number = 6;
const LAUREL_ITEM_BOTTOM: number = 8;
const REVIEW_CARD_WIDTH: number = 272;
const REVIEW_CARD_HEIGHT: number = 208;
const REVIEW_CARD_GAP: number = 12;
const REVIEW_CARD_PADDING: number = 20;
const REVIEW_CARD_RADIUS: number = 24;
const REVIEW_COPY_GAP: number = 8;
const REVIEW_STAR_GAP: number = 2;
const REVIEW_STAR_SIZE: number = 14;
const REVIEW_EDGE_FADE_WIDTH: number = 32;
/** Every sample review is a five-star review, so the band never recomputes a rating. */
const REVIEW_STAR_COUNT: number = 5;
const AVATAR_SIZE: number = 32;
/** The recommended app's own review band moves at a constant 24vp per second. */
const REVIEW_SPEED_VP_PER_SECOND: number = 24;
/** The one action under the card. Height and type match the immersive sheet action. */
const ACTION_HEIGHT: number = 50;
const ACTION_FONT_SIZE: number = 16;
/** The band's stars keep the recommended app's rating orange rather than a themed role. */
const REVIEW_STAR_COLOR: string = '#F58A1F';
const ACCENT_FALLBACK: string = '#0A59F7';

/**
 * The app recommendation card for one campaign. It introduces the app: what it is
 * for, what people say about it, and what it answers. Its one action hands the
 * AppGallery detail page to the store; nothing here installs anything, and the
 * header's close control is how the user says no. The owner records the campaign
 * as spent once this card reveals.
 *
 * Phone only, so the card is always a full-height immersive sheet.
 */
@Component
export struct AppRecommendationSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = ACCENT_FALLBACK;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop recommendationId: string = '';
  onClose: () => void = (): void => {};
  onOpenMarket: () => void = (): void => {};
  @State private sheetHeaderBlurRadius: number = 0;
  // Resolved once, before the first frame. An id the catalog does not know leaves
  // the empty entry in place, and the card then draws only its header.
  private entry: AppRecommendationEntry = buildEmptyAppRecommendationEntry();
  private scroller: Scroller = new Scroller();
  private sheetScrollOffset: number = 0;

  aboutToAppear(): void {
    const resolved = appRecommendationEntryFor(this.recommendationId);
    this.entry = resolved !== undefined ? resolved : buildEmptyAppRecommendationEntry();
  }

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: 'bottom_sheet',
      horizontalPadding: 0,
      topPadding: 0,
      bottomPadding: 0,
      surfaceColor: this.storedPageBackgroundColor
    }) {
      BrowserImmersiveSheetLayout({
        closeVisible: true,
        closeAccessibilityLabel: $r('app.string.app_recommendation_close'),
        footerVisible: this.entry.storeId.length > 0,
        footerBottomPadding: BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
        onClose: (): void => {
          this.onClose();
        },
        scrollContent: () => {
          this.buildScrollContent()
        },
        header: () => {
          this.buildHeader()
        },
        footer: () => {
          this.buildFooter()
        }
      })
    }
  }

  @Builder
  private buildHeader() {
    BrowserFeatureSheetHeader({
      title: $r('app.string.app_recommendation_title')
    })
  }

  /**
   * The card's only action. It hands the store page over and nothing else: the
   * recommended app's install, and whether it is already installed, stay the
   * store's business.
   */
  @Builder
  private buildFooter() {
    Column() {
      BrowserSheetActionButton({
        label: $r('app.string.app_recommendation_open_market'),
        emphasis: 'primary',
        stacked: true,
        accentColor: this.resolveAccentColor(),
        buttonHeight: ACTION_HEIGHT,
        fontSize: ACTION_FONT_SIZE,
        onAction: (): void => {
          this.onOpenMarket();
        }
      })
    }
    .width('100%')
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  private buildScrollContent() {
    Scroll(this.scroller) {
      Column({ space: 0 }) {
        this.Hero()
        if (this.entry.badges.length > 0) {
          AppRecommendationLaurelBadges({ labels: this.entry.badges })
        }
        if (this.entry.reviews.length > 0) {
          this.SectionHeading(this.entry.reviewsTitle)
          AppRecommendationReviewMarquee({ reviews: this.entry.reviews })
        }
        if (this.entry.faqs.length > 0) {
          this.SectionHeading(this.entry.faqsTitle)
          this.Faqs()
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: CONTENT_INSET,
        right: CONTENT_INSET,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        // The floating action covers the tail of the scroll, so the last question
        // clears it instead of hiding under it.
        bottom: this.entry.storeId.length > 0
          ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING + ACTION_HEIGHT
          : BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .attributeModifier(browserSheetHeaderBlurModifier(this.sheetHeaderBlurRadius))
    .onAppear(() => {
      this.resetSheetHeaderBlur();
    })
    .onDidScroll((_xOffset: number, _yOffset: number) => {
      this.noteSheetScrollOffset(this.scroller.currentOffset().yOffset);
    })
  }

  private noteSheetScrollOffset(offset: number): void {
    if (!Number.isFinite(offset)) {
      return;
    }
    const next = Math.max(0, offset);
    if (next === this.sheetScrollOffset) {
      return;
    }
    this.sheetScrollOffset = next;
    this.sheetHeaderBlurRadius = resolveBrowserSheetHeaderBlurRadius(next);
  }

  private resetSheetHeaderBlur(): void {
    this.sheetScrollOffset = 0;
    this.sheetHeaderBlurRadius = 0;
  }

  @Builder
  private Hero() {
    Column() {
      if (`${this.entry.icon}`.length > 0) {
        // Aira's image slots take a plain Resource; the catalog always supplies one
        // for a campaign the owner decided to show, and the guard keeps an unresolved
        // id from reserving an empty artwork box.
        Image(this.entry.icon as Resource)
          .width(HERO_ICON_SIZE)
          .height(HERO_ICON_SIZE)
          .objectFit(ImageFit.Contain)
          .borderRadius(HERO_ICON_RADIUS)
          .draggable(false)
          .accessibilityText(resolveAppResourceText(this.entry.name))
      }
      Text(this.entry.name)
        .width('100%')
        .fontSize(TITLE_FONT_SIZE)
        .lineHeight(TITLE_LINE_HEIGHT)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)
        .margin({ top: HERO_ICON_NAME_GAP })
      Text(this.entry.tagline)
        .width('100%')
        .fontSize(BODY_FONT_SIZE)
        .lineHeight(SUBTITLE_LINE_HEIGHT)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Center)
        .margin({ top: HERO_COPY_GAP })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ top: HERO_TOP_PADDING, bottom: HERO_BOTTOM_PADDING })
  }

  @Builder
  private SectionHeading(title: ResourceStr) {
    Text(title)
      .width('100%')
      .fontSize(BODY_FONT_SIZE)
      .lineHeight(BODY_LINE_HEIGHT)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedPrimaryTextColor)
      .padding({ top: HEADING_TOP_GAP, bottom: HEADING_BOTTOM_GAP })
  }

  @Builder
  private Faqs() {
    Column({ space: SECTION_GAP }) {
      ForEach(this.entry.faqs, (faq: AppRecommendationFaq) => {
        Column({ space: FAQ_TITLE_GAP }) {
          SymbolGlyph(faq.icon)
            .fontSize(FAQ_ICON_SIZE)
            .fontColor([this.resolveAccentColor()])
          Text(faq.title)
            .fontSize(BODY_FONT_SIZE)
            .lineHeight(BODY_LINE_HEIGHT)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)
          Text(faq.text)
            .fontSize(CAPTION_FONT_SIZE)
            .lineHeight(CAPTION_LINE_HEIGHT)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Center)
            .padding({ left: FAQ_TEXT_INSET, right: FAQ_TEXT_INSET })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
      }, (faq: AppRecommendationFaq): string => faq.key)
    }
    .width('100%')
  }

  private resolveAccentColor(): ResourceColor {
    return this.storedAccentColor.length > 0 ? this.storedAccentColor : ACCENT_FALLBACK;
  }
}

/** The two-laurel product phrase. Copy comes from the catalog; no award or rank is implied. */
@Component
export struct AppRecommendationLaurelBadges {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop labels: ResourceStr[] = [];

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.labels, (label: ResourceStr, index: number) => {
        Row({ space: LAUREL_COPY_GAP }) {
          Image($r('app.media.app_recommendation_laurel_left'))
            .width(LAUREL_ICON_WIDTH)
            .height(LAUREL_ICON_HEIGHT)
            .fillColor(this.storedPrimaryTextColor)
            .draggable(false)
            .accessibilityLevel('no-hide-descendants')
          Text(label)
            .fontSize(CAPTION_FONT_SIZE)
            .lineHeight(CAPTION_LINE_HEIGHT)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Center)
            .maxLines(1)
          Image($r('app.media.app_recommendation_laurel_right'))
            .width(LAUREL_ICON_WIDTH)
            .height(LAUREL_ICON_HEIGHT)
            .fillColor(this.storedPrimaryTextColor)
            .draggable(false)
            .accessibilityLevel('no-hide-descendants')
        }
        .width('50%')
        .padding({ left: LAUREL_ITEM_INSET, right: LAUREL_ITEM_INSET, bottom: LAUREL_ITEM_BOTTOM })
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .accessibilityLevel('yes')
        .accessibilityText(resolveAppResourceText(label))
      }, (_label: ResourceStr, index: number): string => index.toString())
    }
    .width('100%')
  }
}

/**
 * The sample review band. It scrolls at a constant speed and repeats the whole
 * cycle, so the row never shows a gap at its end. It is a display band, not a
 * second scroller: the surrounding sheet keeps its own Scroll.
 */
@Component
export struct AppRecommendationReviewMarquee {
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop @Watch('rebuild') reviews: AppRecommendationReview[] = [];
  @State private translationX: number = 0;
  @State private cycleWidth: number = 0;
  @State private repeatCount: number = 2;
  private viewportWidth: number = 0;
  private mounted: boolean = false;
  private visible: boolean = false;
  private touching: boolean = false;
  private playing: boolean = false;
  private generation: number = 0;
  private animator: AnimatorResult | undefined = undefined;

  aboutToAppear(): void {
    this.mounted = true;
    this.rebuild();
  }

  aboutToDisappear(): void {
    this.mounted = false;
    this.visible = false;
    this.dispose();
  }

  private copies(): number[] {
    const result: number[] = [];
    for (let index = 0; index < this.repeatCount; index++) {
      result.push(index);
    }
    return result;
  }

  private stars(): number[] {
    const result: number[] = [];
    for (let index = 0; index < REVIEW_STAR_COUNT; index++) {
      result.push(index);
    }
    return result;
  }

  private rebuild(): void {
    this.dispose();
    this.translationX = 0;
    this.cycleWidth = this.reviews.length * (REVIEW_CARD_WIDTH + REVIEW_CARD_GAP);
    this.fitCopies();
    this.syncPlayback();
  }

  private fitCopies(): void {
    this.repeatCount = this.reviews.length < 2 || this.cycleWidth <= 0 ? 1 :
      Math.max(2, Math.ceil(this.viewportWidth / this.cycleWidth) + 1);
  }

  private measureViewport(width: number): void {
    if (!Number.isFinite(width) || width <= 0 || width === this.viewportWidth) {
      return;
    }
    this.viewportWidth = width;
    this.fitCopies();
    this.syncPlayback();
  }

  private canPlay(): boolean {
    return this.mounted && this.visible && !this.touching &&
      this.reviews.length > 1 && this.cycleWidth > 0 && this.viewportWidth > 0;
  }

  private syncPlayback(): void {
    if (!this.canPlay()) {
      if (this.playing) {
        this.animator?.pause();
      }
      this.playing = false;
      return;
    }
    if (this.playing) {
      return;
    }
    try {
      if (this.animator === undefined) {
        const generation: number = this.generation;
        this.animator = this.getUIContext().createAnimator({
          duration: Math.round(this.cycleWidth / REVIEW_SPEED_VP_PER_SECOND * 1000),
          easing: 'linear',
          delay: 0,
          fill: 'forwards',
          direction: 'normal',
          iterations: -1,
          begin: 0,
          end: -this.cycleWidth
        });
        this.animator.onFrame = (value: number): void => {
          if (generation === this.generation && this.canPlay()) {
            this.translationX = value;
          }
        };
      }
      this.animator.play();
      this.playing = true;
    } catch (_error) {
      this.dispose();
    }
  }

  private dispose(): void {
    this.generation++;
    this.playing = false;
    const previous = this.animator;
    this.animator = undefined;
    if (previous !== undefined) {
      // An Animator re-delivers its end frame while it unwinds. Detach the callback
      // first, so a rebuild or an unmount cannot snap the band to the end.
      previous.onFrame = (_value: number): void => {};
      previous.cancel();
    }
  }

  /** The sheet color at zero alpha, so the band fades into the surface it sits on. */
  private fadeColor(): string {
    const color = this.storedPageBackgroundColor;
    if (color.length === 7 && color.startsWith('#')) {
      return `#00${color.substring(1)}`;
    }
    if (color.length === 9 && color.startsWith('#')) {
      return `#00${color.substring(3)}`;
    }
    return '#00000000';
  }

  private reviewAccessibilityText(review: AppRecommendationReview): string {
    return resolveAppResourceText($r('app.string.app_recommendation_review_a11y',
      resolveAppResourceText(review.author),
      REVIEW_STAR_COUNT,
      resolveAppResourceText(review.title),
      resolveAppResourceText(review.message)));
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        ForEach(this.copies(), (copy: number) => {
          Row({ space: REVIEW_CARD_GAP }) {
            ForEach(this.reviews, (review: AppRecommendationReview) => {
              this.Card(review, copy)
            }, (review: AppRecommendationReview): string => review.key)
          }
          .width(this.cycleWidth)
          .padding({ right: REVIEW_CARD_GAP })
        }, (copy: number): string => copy.toString())
      }
      .width(this.cycleWidth * this.repeatCount)
      .translate({ x: this.translationX })

      if (this.reviews.length > 1) {
        this.EdgeFades()
      }
    }
    .width('100%')
    .height(this.reviews.length > 0 ? REVIEW_CARD_HEIGHT : 0)
    .clip(true)
    .onAreaChange((_oldArea: Area, area: Area): void => {
      this.measureViewport(Number(area.width));
    })
    .onVisibleAreaChange([0, 0.01], (visible: boolean, ratio: number): void => {
      this.visible = visible && ratio > 0;
      this.syncPlayback();
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) {
        this.touching = true;
      }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.touching = false;
      }
      this.syncPlayback();
    })
  }

  @Builder
  EdgeFades() {
    Row() {
      Column()
        .width(REVIEW_EDGE_FADE_WIDTH)
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [[this.storedPageBackgroundColor, 0], [this.fadeColor(), 1]]
        })
        .hitTestBehavior(HitTestMode.None)
      Blank().layoutWeight(1)
      Column()
        .width(REVIEW_EDGE_FADE_WIDTH)
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [[this.fadeColor(), 0], [this.storedPageBackgroundColor, 1]]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  Card(review: AppRecommendationReview, copy: number) {
    Column({ space: REVIEW_COPY_GAP }) {
      Row({ space: REVIEW_STAR_GAP }) {
        ForEach(this.stars(), (index: number) => {
          SymbolGlyph($r('sys.symbol.star_fill'))
            .fontSize(REVIEW_STAR_SIZE)
            .fontColor([REVIEW_STAR_COLOR])
        }, (index: number): string => index.toString())
      }
      .width('100%')

      Text(review.title)
        .width('100%')
        .fontSize(BODY_FONT_SIZE)
        .lineHeight(BODY_LINE_HEIGHT)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(review.message)
        .width('100%')
        .fontSize(CAPTION_FONT_SIZE)
        .lineHeight(CAPTION_LINE_HEIGHT)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank().layoutWeight(1)
      Row({ space: REVIEW_COPY_GAP }) {
        Image(review.avatar)
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .objectFit(ImageFit.Cover)
          .borderRadius(AVATAR_SIZE / 2)
          .draggable(false)
          .accessibilityLevel('no-hide-descendants')
        Text(review.author)
          .layoutWeight(1)
          .fontSize(CAPTION_FONT_SIZE)
          .lineHeight(CAPTION_LINE_HEIGHT)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
    }
    .width(REVIEW_CARD_WIDTH)
    .height(REVIEW_CARD_HEIGHT)
    .alignItems(HorizontalAlign.Start)
    .padding(REVIEW_CARD_PADDING)
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(REVIEW_CARD_RADIUS)
    .clip(true)
    .accessibilityLevel(copy === 0 ? 'yes' : 'no-hide-descendants')
    .accessibilityText(this.reviewAccessibilityText(review))
  }
}
