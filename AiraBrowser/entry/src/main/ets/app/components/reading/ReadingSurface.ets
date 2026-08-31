import { ReaderModeTheme } from '../../../common/models/BrowserModels';
import { BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY } from '../../../core/browser/BrowserSystemFontScaleCoordinator';
import {
  ReadingAnchor,
  ReadingDocument,
  ReadingDocumentBlock,
  createReadingAnchor
} from '../../../features/reading/ReadingDocumentModels';
import {
  ReadingBlockMeasurement,
  ReadingDocumentPaginator,
  ReadingPage,
  ReadingPageFragment,
  ReadingPageMetrics
} from '../../../features/reading/ReadingDocumentPaginator';
import {
  ReadingDocumentFlow,
  ReadingSearchTextSegment,
  ReadingVerticalFragment
} from '../../../features/reading/ReadingDocumentFlow';
import {
  ReadingPresentationMode,
  ReadingSurfaceAction,
  ReadingSurfaceAppearance,
  ReadingSurfaceCommand,
  ReadingSurfaceOptions,
  ReadingSurfaceSearchPresentation,
  createDefaultReadingSurfaceAppearance,
  createDefaultReadingSurfaceCommand,
  createDefaultReadingSurfaceOptions,
  createDefaultReadingSurfaceSearchPresentation
} from '../../../features/reading/ReadingSurfaceModels';
import {
  resolveEffectiveReadingTheme,
  resolveReadingThemeTokens
} from './ReadingThemeTokenResolver';

const READING_SURFACE_HORIZONTAL_PADDING: number = 22;
const READING_SURFACE_PAGE_HEADER_HEIGHT: number = 72;
const READING_SURFACE_PAGE_FOOTER_HEIGHT: number = 56;
const READING_SURFACE_PAGE_VERTICAL_PADDING: number = 12;
const READING_SURFACE_PAGE_META_FONT_SIZE: number = 12;
const READING_SURFACE_BLOCK_SPACING: number = 10;
const READING_SURFACE_DEFAULT_IMAGE_HEIGHT: number = 180;
const READING_SURFACE_MAX_IMAGE_HEIGHT: number = 520;
const READING_SURFACE_IMAGE_FALLBACK_HEIGHT: number = 148;
const READING_SURFACE_IMAGE_COMPACT_FALLBACK_HEIGHT: number = 46;
const READING_SURFACE_PAGE_ANIMATION_DURATION_MS: number = 240;
const READING_SURFACE_PARAGRAPH_INDENT: string = '　　';
const READING_SURFACE_INITIAL_PAGINATION_BLOCK_COUNT: number = 24;
const READING_SURFACE_VERTICAL_FRAGMENT_MAX_CHARACTERS: number = 512;
const READING_SURFACE_CACHED_PAGE_COUNT: number = 2;

type ReadingPageSpreadSlotKind = 'page' | 'continuation' | 'empty';

interface ReadingPageSpreadSlot {
  readonly kind: ReadingPageSpreadSlotKind;
  readonly pageIndex: number;
}

interface ReadingPageSpread {
  readonly index: number;
  readonly slots: ReadingPageSpreadSlot[];
}

@Component
export struct ReadingSurface {
  @Prop @Watch('onDocumentChanged') document: ReadingDocument;
  @Prop initialAnchor: ReadingAnchor = createReadingAnchor('', '', 0);
  @Prop @Watch('onPresentationChanged') mode: ReadingPresentationMode = 'vertical';
  @Prop @Watch('onPresentationChanged') appearance: ReadingSurfaceAppearance =
    createDefaultReadingSurfaceAppearance();
  @Prop @Watch('onPresentationChanged') activeTheme: ReaderModeTheme = 'system';
  @Prop @Watch('onPresentationChanged') options: ReadingSurfaceOptions = createDefaultReadingSurfaceOptions();
  @Prop @Watch('onPresentationChanged') pagedColumnCount: number = 1;
  @Prop @Watch('onPresentationChanged') pagedColumnGap: number = 0;
  @Prop @Watch('onPresentationChanged') pagedContentWidth: number = 0;
  /** Optional bounded text rail when the vertical surface also owns full-width touch input. */
  @Prop @Watch('onPresentationChanged') contentWidth: number = 0;
  @Prop @Watch('onCommandChanged') command: ReadingSurfaceCommand = createDefaultReadingSurfaceCommand();
  @Prop @Watch('onSearchChanged') search: ReadingSurfaceSearchPresentation =
    createDefaultReadingSurfaceSearchPresentation();
  @StorageProp(BROWSER_SYSTEM_FONT_SIZE_SCALE_STORAGE_KEY) @Watch('onPresentationChanged')
  private systemFontSizeScale: number = 1;
  onAction: (action: ReadingSurfaceAction) => void = (_action: ReadingSurfaceAction): void => {};

  @State private pages: ReadingPage[] = [];
  @State private currentPage: number = 0;
  @State private paginationRevision: number = 0;
  @State private failedImageUrls: string[] = [];
  @State private paginationComplete: boolean = true;
  private readonly paginator: ReadingDocumentPaginator = new ReadingDocumentPaginator();
  private readonly documentFlow: ReadingDocumentFlow = new ReadingDocumentFlow();
  private readonly swiperController: SwiperController = new SwiperController();
  private readonly verticalScroller: Scroller = new Scroller();
  private contentWidthVp: number = 0;
  private contentHeightVp: number = 0;
  private restoreTimer: number = -1;
  private paginationTimer: number = -1;
  private paginationGeneration: number = 0;
  private lastLayoutFailureSignature: string = '';
  private observedCommandVersion: number = 0;
  private observedDocument?: ReadingDocument;
  private observedPresentationSignature: string = '';
  private observedSearchSignature: string = '';
  private cachedVerticalDocument?: ReadingDocument;
  private cachedVerticalFragments: ReadingVerticalFragment[] = [];
  private currentAnchor: ReadingAnchor = createReadingAnchor('', '', 0);
  private lastReportedAnchorSignature: string = '';
  private livePositionEstablished: boolean = false;

  aboutToAppear(): void {
    this.observedCommandVersion = this.command.version;
    this.observedDocument = this.document;
    this.observedPresentationSignature = this.buildPresentationSignature();
    this.observedSearchSignature = this.buildSearchSignature();
    this.livePositionEstablished = this.isAnchorUsable(this.initialAnchor);
    this.currentAnchor = this.resolveUsableAnchor(this.initialAnchor);
    this.lastReportedAnchorSignature = this.buildAnchorSignatureFor(this.currentAnchor);
    if (this.livePositionEstablished) {
      this.scheduleAnchorRestore(this.currentAnchor);
    }
  }

  aboutToDisappear(): void {
    this.clearRestoreTimer();
    this.cancelDeferredPagination();
    this.paginator.clearCache();
  }

  build() {
    Stack() {
      if (this.mode === 'vertical') {
        this.buildVerticalDocument()
      } else {
        this.buildPagedDocument()
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBackgroundColor())
    .onAreaChange((_oldValue: Area, newValue: Area): void => {
      this.handleAreaChange(newValue);
    })
  }

  @Builder
  private buildPagedDocument() {
    Swiper(this.swiperController) {
      ForEach(this.resolvePageSpreads(), (spread: ReadingPageSpread) => {
        this.buildPageSpread(spread)
      }, (spread: ReadingPageSpread): string =>
        `${this.document.id}:spread:${spread.index}:${this.resolvePagedColumnCount()}:` +
          `${this.pages.length}:${this.paginationComplete}:${this.paginationRevision}:` +
          `${this.buildContentRenderSignature()}`)
    }
    .loop(false)
    .indicator(false)
    .index($$this.currentPage)
    .cachedCount(READING_SURFACE_CACHED_PAGE_COUNT)
    .duration(this.mode === 'horizontalFast' ? 0 : READING_SURFACE_PAGE_ANIMATION_DURATION_MS)
    .curve(Curve.EaseOut)
    .disableSwipe(this.mode === 'horizontalFast')
    .width('100%')
    .height('100%')
    .onChange((index: number): void => {
      this.handlePageChange(index);
    })
    .onClick((event: ClickEvent): void => {
      this.handleReadingTap(event);
    })
  }

  @Builder
  private buildPageSpread(spread: ReadingPageSpread) {
    Row({ space: this.resolvePagedColumnGap() }) {
      ForEach(spread.slots, (slot: ReadingPageSpreadSlot, slotIndex: number) => {
        if (slot.kind === 'page') {
          this.buildPage(this.pages[slot.pageIndex], slotIndex)
        } else if (slot.kind === 'continuation') {
          this.buildContinuationPage()
        } else {
          this.buildEmptyPage()
        }
      }, (slot: ReadingPageSpreadSlot, slotIndex: number): string =>
        `${this.document.id}:spread:${spread.index}:slot:${slotIndex}:${slot.kind}:${slot.pageIndex}`)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildPage(page: ReadingPage, spreadSlotIndex: number) {
    Column() {
      if (this.options.pageHeaderVisible) {
        Row() {
          Text(this.document.title)
            .fontSize(READING_SURFACE_PAGE_META_FONT_SIZE)
            .fontColor(this.resolveSecondaryTextColor())
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .height(READING_SURFACE_PAGE_HEADER_HEIGHT + this.options.contentTopInset)
        .padding({
          left: READING_SURFACE_HORIZONTAL_PADDING,
          right: READING_SURFACE_HORIZONTAL_PADDING,
          top: 12 + this.options.contentTopInset
        })
        .alignItems(VerticalAlign.Center)
      }

      Column() {
        ForEach(page.fragments, (fragment: ReadingPageFragment, fragmentIndex: number) => {
          this.buildFragment(fragment, fragmentIndex, spreadSlotIndex)
        }, (fragment: ReadingPageFragment, fragmentIndex: number): string =>
          `${this.document.id}:${page.index}:${fragment.blockId}:${fragment.startCharacterOffset}:` +
            `${fragmentIndex}:${this.buildContentRenderSignature()}`)
      }
      .width(this.resolveContentWidth())
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .clip(true)
      .padding({
        left: READING_SURFACE_HORIZONTAL_PADDING,
        right: READING_SURFACE_HORIZONTAL_PADDING,
        top: READING_SURFACE_PAGE_VERTICAL_PADDING,
        bottom: READING_SURFACE_PAGE_VERTICAL_PADDING
      })

      if (this.options.pageNumberVisible) {
        Row() {
          Blank()
          Text(this.paginationComplete ? `${page.index + 1} / ${this.pages.length}` : `${page.index + 1} / …`)
            .fontSize(READING_SURFACE_PAGE_META_FONT_SIZE)
            .fontColor(this.resolveSecondaryTextColor())
        }
        .width('100%')
        .height(READING_SURFACE_PAGE_FOOTER_HEIGHT + this.options.contentBottomInset)
        .padding({
          left: READING_SURFACE_HORIZONTAL_PADDING,
          right: READING_SURFACE_HORIZONTAL_PADDING,
          bottom: 12 + this.options.contentBottomInset
        })
        .alignItems(VerticalAlign.Center)
      }
    }
    .width(this.resolvePagedLeafWidth())
    .height('100%')
  }

  @Builder
  private buildContinuationPage() {
    Column({ space: 10 }) {
      Text('▼')
        .fontSize(22)
        .fontColor(this.resolveSecondaryTextColor())
      Text(this.options.continuationLabel)
        .fontSize(15)
        .fontColor(this.resolveSecondaryTextColor())
    }
    .width(this.resolvePagedLeafWidth())
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildEmptyPage() {
    Blank()
      .width(this.resolvePagedLeafWidth())
      .height('100%')
  }

  @Builder
  private buildVerticalDocument() {
    List({ space: 0, scroller: this.verticalScroller }) {
      if (this.options.documentHeaderVisible) {
        ListItem() {
          Column({ space: 8 }) {
            Text(this.document.title.length > 0 ? this.document.title : '未命名文章')
              .fontSize(this.appearance.fontSize + 8)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.resolveTextColor())
              .lineHeight((this.appearance.fontSize + 8) * 1.28)
              .copyOption(CopyOptions.LocalDevice)

            Text(this.document.subtitle)
              .fontSize(13)
              .fontColor(this.resolveSecondaryTextColor())
              .copyOption(CopyOptions.LocalDevice)
              .visibility(this.document.subtitle.length > 0 ? Visibility.Visible : Visibility.None)
          }
          .width('100%')
          .padding({ top: 28, bottom: 12 })
        }
        .parallelGesture(
          TapGesture({ count: 1, fingers: 1, distanceThreshold: 1 })
            .onAction((): void => {
              this.onAction({ type: 'toggle_chrome' });
            }),
          GestureMask.Normal
        )
      }

      ForEach(this.resolveVerticalFragments(), (fragment: ReadingVerticalFragment) => {
        ListItem() {
          this.buildBlock(
            this.document.blocks[fragment.blockIndex],
            fragment.startCharacterOffset,
            fragment.endCharacterOffset
          )
        }
        .margin({ bottom: fragment.lastInBlock ? READING_SURFACE_BLOCK_SPACING : 0 })
        .parallelGesture(
          TapGesture({ count: 1, fingers: 1, distanceThreshold: 1 })
            .onAction((): void => {
              this.handleVerticalContentTap(this.document.blocks[fragment.blockIndex]);
            }),
          GestureMask.Normal
        )
      }, (fragment: ReadingVerticalFragment): string =>
        `${this.document.id}:vertical:${fragment.blockId}:${fragment.startCharacterOffset}:` +
          `${this.buildContentRenderSignature()}`)
    }
    .width(this.resolveContentWidth())
    .height('100%')
    .padding({
      left: this.resolveVerticalListHorizontalPadding(),
      right: this.resolveVerticalListHorizontalPadding(),
      top: (this.options.documentHeaderVisible ? 0 : 28) + this.options.contentTopInset,
      bottom: this.options.contentBottomInset
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
    .scrollBar(BarState.Off)
    .onScrollIndex((start: number, _end: number): void => {
      this.reportVerticalAnchor(start);
    })
    .onReachStart((): void => {
      this.onAction({ type: 'reach_start' });
    })
    .onReachEnd((): void => {
      this.onAction({ type: 'reach_end' });
    })
    .onClick((_event: ClickEvent): void => {
      this.onAction({ type: 'toggle_chrome' });
    })
  }

  @Builder
  private buildFragment(fragment: ReadingPageFragment, fragmentIndex: number, spreadSlotIndex: number) {
    Column() {
      this.buildBlock(
        this.document.blocks[fragment.blockIndex],
        fragment.startCharacterOffset,
        fragment.endCharacterOffset
      )
    }
    .width('100%')
    .margin({ top: fragmentIndex > 0 ? READING_SURFACE_BLOCK_SPACING : 0 })
    .parallelGesture(
      TapGesture({ count: 1, fingers: 1, distanceThreshold: 1 })
        .onAction((event: GestureEvent): void => {
          this.handlePagedContentTap(this.document.blocks[fragment.blockIndex], event, spreadSlotIndex);
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildBlock(block: ReadingDocumentBlock, startOffset: number, endOffset: number) {
    if (block.type === 'image') {
      this.buildImageBlock(block)
    } else if (block.type === 'heading') {
      this.buildRichText(
        block,
        startOffset,
        endOffset,
        this.resolveBlockFontSize(block),
        this.resolveTextColor(),
        this.resolveBlockLineHeight(block),
        this.resolveBlockFontWeight(block),
        this.resolveBlockFontFamily(block)
      )
    } else if (block.type === 'link') {
      Button() {
        this.buildRichText(
          block,
          startOffset,
          endOffset,
          this.resolveBlockFontSize(block),
          $r('app.color.reader_surface_link_text'),
          this.resolveBlockLineHeight(block),
          this.resolveBlockFontWeight(block),
          this.resolveBlockFontFamily(block)
        )
      }
      .width('100%')
      .type(ButtonType.Normal)
      .backgroundColor(this.resolveControlBackgroundColor())
      .borderRadius(8)
      .padding(10)
      .onClick((): void => {
        this.onAction({ type: 'open_link', blockId: block.id, url: block.url ?? '' });
      })
    } else if (block.type === 'quote') {
      Column() {
        this.buildRichText(
          block,
          startOffset,
          endOffset,
          this.resolveBlockFontSize(block),
          this.resolveSecondaryTextColor(),
          this.resolveBlockLineHeight(block),
          this.resolveBlockFontWeight(block),
          this.resolveBlockFontFamily(block)
        )
      }
        .width('100%')
        .padding({ left: 16, top: 2, bottom: 2 })
        .border({ width: { left: 3 }, color: this.resolveSecondaryTextColor() })
    } else if (block.type === 'code') {
      Column() {
        this.buildRichText(
          block,
          startOffset,
          endOffset,
          this.resolveBlockFontSize(block),
          this.resolveTextColor(),
          this.resolveBlockLineHeight(block),
          this.resolveBlockFontWeight(block),
          this.resolveBlockFontFamily(block)
        )
      }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.resolveControlBackgroundColor())
        .borderRadius(8)
    } else {
      this.buildRichText(
        block,
        startOffset,
        endOffset,
        this.resolveBlockFontSize(block),
        this.resolveTextColor(),
        this.resolveBlockLineHeight(block),
        this.resolveBlockFontWeight(block),
        this.resolveBlockFontFamily(block)
      )
    }
  }

  @Builder
  private buildRichText(
    block: ReadingDocumentBlock,
    startOffset: number,
    endOffset: number,
    fontSize: number,
    fontColor: ResourceColor,
    lineHeight: number,
    fontWeight: FontWeight,
    fontFamily: string
  ) {
    if (this.search.query.trim().length > 0) {
      Text() {
        if (this.resolveFragmentPrefix(block, startOffset).length > 0) {
          Span(this.resolveFragmentPrefix(block, startOffset))
            .fontColor(fontColor)
        }
        ForEach(
          this.documentFlow.buildSearchSegments(
            block.text,
            this.search.query,
            startOffset,
            endOffset,
            block.id === this.search.activeBlockId ? this.search.activeMatchIndexInBlock : -1
          ),
          (segment: ReadingSearchTextSegment, index: number) => {
          Span(segment.text)
            .fontColor(segment.highlighted ? this.resolveSearchHighlightTextColor(segment.active) : fontColor)
            .textBackgroundStyle({
              color: segment.highlighted ? this.resolveSearchHighlightColor(segment.active) :
                $r('sys.color.ohos_id_color_background_transparent'),
              radius: segment.highlighted ? 4 : 0
            })
          }, (segment: ReadingSearchTextSegment, index: number): string =>
            `${block.id}:${this.search.query}:${this.search.activeMatchIndexInBlock}:${index}:${segment.text}`
        )
      }
      .fontSize(`${this.resolveScaledTextMetricVp(fontSize)}vp`)
      .fontColor(fontColor)
      .fontWeight(fontWeight)
      .fontFamily(fontFamily)
      .lineHeight(`${this.resolveScaledTextMetricVp(lineHeight)}vp`)
      .wordBreak(WordBreak.BREAK_WORD)
      .lineBreakStrategy(LineBreakStrategy.GREEDY)
      .width('100%')
      .textAlign(TextAlign.Start)
      .copyOption(CopyOptions.LocalDevice)
    } else {
      Text(`${this.resolveFragmentPrefix(block, startOffset)}${block.text.substring(startOffset, endOffset)}`)
        .fontSize(`${this.resolveScaledTextMetricVp(fontSize)}vp`)
        .fontColor(fontColor)
        .fontWeight(fontWeight)
        .fontFamily(fontFamily)
        .lineHeight(`${this.resolveScaledTextMetricVp(lineHeight)}vp`)
        .wordBreak(WordBreak.BREAK_WORD)
        .lineBreakStrategy(LineBreakStrategy.GREEDY)
        .width('100%')
        .textAlign(TextAlign.Start)
        .copyOption(CopyOptions.LocalDevice)
    }
  }

  @Builder
  private buildImageBlock(block: ReadingDocumentBlock) {
    Column({ space: 6 }) {
      if (this.shouldShowImage(block)) {
        Image(this.resolveImageUrl(block))
          .width('100%')
          .height(this.resolveImageHeight(block, this.resolveAvailableContentWidth()))
          .objectFit(ImageFit.Contain)
          .borderRadius(8)
          .draggable(false)
          .onClick((): void => {
            this.onAction({
              type: 'preview_image',
              blockId: block.id,
              url: this.resolveImageUrl(block),
              caption: this.resolveImageCaption(block)
            });
          })
          .onError((): void => {
            this.markImageFailed(this.resolveImageUrl(block));
          })
      } else if (this.shouldShowImageFallback(block)) {
        Row() {
          Text('图片未加载')
            .fontSize(12)
            .fontColor(this.resolveSecondaryTextColor())
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height(this.resolveImageFallbackHeight(block))
        .padding({ left: 12, right: 12 })
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.resolveControlBackgroundColor())
        .borderRadius(8)
      }

      Text(this.resolveImageCaption(block))
        .fontSize(12)
        .fontColor(this.resolveSecondaryTextColor())
        .lineHeight(18)
        .textAlign(TextAlign.Center)
        .width('100%')
        .copyOption(CopyOptions.LocalDevice)
        .visibility(this.resolveImageCaption(block).length > 0 ? Visibility.Visible : Visibility.None)
    }
    .width('100%')
  }

  private handleAreaChange(area: Area): void {
    const width: number = area.width as number;
    const height: number = area.height as number;
    if (width <= 0 || height <= 0) {
      return;
    }
    const widthChanged: boolean = Math.abs(width - this.contentWidthVp) > 0.5;
    const heightChanged: boolean = Math.abs(height - this.contentHeightVp) > 0.5;
    if (!widthChanged && !heightChanged) {
      return;
    }
    const pagedSpreadWidthChanged: boolean = Math.abs(
      this.resolvePagedSpreadWidthFor(width) - this.resolvePagedSpreadWidth()
    ) > 0.5;
    this.contentWidthVp = width;
    this.contentHeightVp = height;
    if (!heightChanged && (this.mode !== 'vertical' ? !pagedSpreadWidthChanged : !widthChanged)) {
      return;
    }
    const preservedAnchor: ReadingAnchor = this.resolveCurrentAnchor();
    this.repaginate(preservedAnchor);
  }

  private onDocumentChanged(): void {
    if (this.observedDocument === this.document) {
      return;
    }
    const preservesLivePosition: boolean = this.livePositionEstablished &&
      this.currentAnchor.documentId === this.document.id && this.isAnchorUsable(this.currentAnchor);
    const hasInitialRestore: boolean = this.isAnchorUsable(this.initialAnchor);
    const preservedAnchor: ReadingAnchor = this.resolveUsableAnchor(
      preservesLivePosition ? this.currentAnchor : this.initialAnchor
    );
    this.observedDocument = this.document;
    this.failedImageUrls = [];
    this.pages = [];
    this.currentPage = 0;
    this.cachedVerticalDocument = undefined;
    this.cachedVerticalFragments = [];
    this.currentAnchor = preservedAnchor;
    this.lastReportedAnchorSignature = this.buildAnchorSignatureFor(preservedAnchor);
    this.livePositionEstablished = preservesLivePosition || hasInitialRestore;
    this.repaginate(preservedAnchor);
    if (this.livePositionEstablished) {
      this.scheduleAnchorRestore(preservedAnchor);
    }
  }

  private onPresentationChanged(): void {
    const signature: string = this.buildPresentationSignature();
    if (signature === this.observedPresentationSignature) {
      return;
    }
    this.observedPresentationSignature = signature;
    const preservedAnchor: ReadingAnchor = this.resolveCurrentAnchor();
    this.currentAnchor = preservedAnchor;
    this.repaginate(preservedAnchor);
    if (this.livePositionEstablished) {
      this.scheduleAnchorRestore(preservedAnchor);
    }
  }

  private onCommandChanged(): void {
    if (this.command.version <= this.observedCommandVersion) {
      return;
    }
    this.observedCommandVersion = this.command.version;
    if (this.command.type === 'scroll_step') {
      if (this.mode !== 'vertical') {
        return;
      }
      if (this.verticalScroller.isAtEnd()) {
        this.onAction({ type: 'reach_end' });
      }
      this.verticalScroller.scrollBy(0, this.command.distance);
      return;
    }
    if (this.mode === 'vertical') {
      const distance: number = Math.max(1, this.contentHeightVp * 0.9);
      this.verticalScroller.scrollBy(0, this.command.type === 'page_next' ? distance : -distance);
      return;
    }
    this.turnPage(this.command.type === 'page_next');
  }

  private onSearchChanged(): void {
    const signature: string = this.buildSearchSignature();
    if (signature === this.observedSearchSignature) {
      return;
    }
    this.observedSearchSignature = signature;
    if (this.search.query.trim().length <= 0 || this.search.activeBlockId.length <= 0) {
      return;
    }
    const target: ReadingAnchor = this.documentFlow.createAnchor(
      this.document,
      this.search.activeBlockId,
      this.resolveActiveSearchCharacterOffset()
    );
    this.currentAnchor = this.resolveUsableAnchor(target);
    this.livePositionEstablished = true;
    if (this.mode === 'vertical') {
      this.clearRestoreTimer();
      this.restoreTimer = setTimeout((): void => {
        this.restoreTimer = -1;
        const fragmentIndex: number = this.findVerticalFragmentIndex(target);
        if (fragmentIndex >= 0) {
          this.verticalScroller.scrollToIndex(
            fragmentIndex + (this.options.documentHeaderVisible ? 1 : 0),
            true,
            ScrollAlign.CENTER
          );
        }
      }, 0);
      return;
    }
    if (!this.paginationComplete) {
      this.repaginate(target);
    }
    const leafPage: number = this.paginator.findPageForAnchor(this.pages, target);
    this.currentPage = this.resolveSpreadIndexForLeafPage(leafPage);
  }

  private buildAnchorSignatureFor(anchor: ReadingAnchor): string {
    return this.documentFlow.buildAnchorSignature(anchor);
  }

  private buildPresentationSignature(): string {
    return `${this.mode}|${this.appearance.fontSize}|${this.resolveEffectiveTheme()}|` +
      `${this.appearance.lineHeight}|${this.appearance.pageWidth}|` +
      `${this.options.documentHeaderVisible}|${this.options.pageHeaderVisible}|` +
      `${this.options.pageNumberVisible}|${this.options.paragraphIndentVisible}|` +
      `${this.options.continuationAvailable}|${this.options.continuationLabel}|` +
      `${this.options.contentTopInset}|${this.options.contentBottomInset}|` +
      `${this.resolvePagedColumnCount()}|${this.resolvePagedColumnGap()}|${this.resolvePagedSpreadWidth()}|` +
      `${this.contentWidth}|` +
      `${this.systemFontSizeScale}`;
  }

  private buildContentRenderSignature(): string {
    return `${this.appearance.fontSize}|${this.resolveEffectiveTheme()}|${this.appearance.lineHeight}|` +
      `${this.appearance.pageWidth}|${this.options.paragraphIndentVisible}|` +
      `${this.contentWidth}|${this.systemFontSizeScale}`;
  }

  private buildSearchSignature(): string {
    return `${this.search.query}|${this.search.activeBlockId}|${this.search.activeMatchIndexInBlock}`;
  }

  private repaginate(preservedAnchor: ReadingAnchor): void {
    this.cancelDeferredPagination();
    const generation: number = this.paginationGeneration + 1;
    this.paginationGeneration = generation;
    if (this.mode === 'vertical' || this.contentWidthVp <= 0 || this.contentHeightVp <= 0 ||
      this.document.blocks.length === 0) {
      this.paginationComplete = true;
      if (this.mode === 'vertical') {
        this.lastLayoutFailureSignature = '';
      }
      return;
    }
    const metrics: ReadingPageMetrics = {
      contentWidth: this.resolveAvailableContentWidth(),
      contentHeight: Math.max(1, this.contentHeightVp - this.resolvePageChromeHeight() -
        READING_SURFACE_PAGE_VERTICAL_PADDING * 2 - this.resolvePaginationSafetyHeight()),
      blockSpacing: READING_SURFACE_BLOCK_SPACING
    };
    try {
      const initialBlockCount: number = this.documentFlow.resolveInitialPaginationBlockCount(
        this.document,
        preservedAnchor,
        READING_SURFACE_INITIAL_PAGINATION_BLOCK_COUNT
      );
      const progressive: boolean = initialBlockCount < this.document.blocks.length;
      const initialDocument: ReadingDocument = progressive
        ? this.buildPaginationDocumentPrefix(initialBlockCount)
        : this.document;
      this.pages = this.paginateDocument(initialDocument, metrics);
      this.paginationRevision += 1;
      this.paginationComplete = !progressive;
      this.lastLayoutFailureSignature = '';
      const targetLeafPage: number = this.paginator.findPageForAnchor(this.pages, preservedAnchor);
      this.currentPage = this.resolveSpreadIndexForLeafPage(targetLeafPage);
      if (progressive) {
        this.scheduleCompletePagination(metrics, generation);
      }
    } catch (_error) {
      this.handleLayoutFailure(preservedAnchor);
    }
  }

  private paginateDocument(document: ReadingDocument, metrics: ReadingPageMetrics): ReadingPage[] {
    const measurementCache: Map<string, ReadingBlockMeasurement> = new Map();
    return this.paginator.paginateCached(
      document,
      metrics,
      this.buildPaginationCacheSignature(),
      (
        block: ReadingDocumentBlock,
        startOffset: number,
        endOffset: number,
        innerMetrics: ReadingPageMetrics
      ): ReadingBlockMeasurement => {
        const cacheKey: string = `${block.id}\u001f${startOffset}\u001f${endOffset}`;
        const cached: ReadingBlockMeasurement | undefined = measurementCache.get(cacheKey);
        if (cached !== undefined) {
          return cached;
        }
        const measurement: ReadingBlockMeasurement = this.measureBlock(block, startOffset, endOffset, innerMetrics);
        measurementCache.set(cacheKey, measurement);
        return measurement;
      }
    ).pages;
  }

  private buildPaginationCacheSignature(): string {
    return `${this.buildContentRenderSignature()}|${this.failedImageUrls.join('\u001f')}`;
  }

  private buildPaginationDocumentPrefix(blockCount: number): ReadingDocument {
    return {
      id: this.document.id,
      title: this.document.title,
      subtitle: this.document.subtitle,
      blocks: this.document.blocks.slice(0, blockCount)
    };
  }

  private scheduleCompletePagination(metrics: ReadingPageMetrics, generation: number): void {
    this.paginationTimer = setTimeout((): void => {
      this.paginationTimer = -1;
      if (generation !== this.paginationGeneration || this.mode === 'vertical') {
        return;
      }
      const preservedAnchor: ReadingAnchor = this.resolveCurrentAnchor();
      try {
        this.pages = this.paginateDocument(this.document, metrics);
        this.paginationRevision += 1;
        this.paginationComplete = true;
        this.lastLayoutFailureSignature = '';
        const targetLeafPage: number = this.paginator.findPageForAnchor(this.pages, preservedAnchor);
        this.currentPage = this.resolveSpreadIndexForLeafPage(targetLeafPage);
      } catch (_error) {
        this.handleLayoutFailure(preservedAnchor);
      }
    }, 0);
  }

  private cancelDeferredPagination(): void {
    if (this.paginationTimer >= 0) {
      clearTimeout(this.paginationTimer);
      this.paginationTimer = -1;
    }
  }

  private handleLayoutFailure(preservedAnchor: ReadingAnchor): void {
    this.cancelDeferredPagination();
    this.pages = [];
    this.currentPage = 0;
    this.paginationComplete = true;
    if (this.mode === 'vertical') {
      return;
    }
    const signature: string = `${this.document.id}|${this.buildPresentationSignature()}`;
    if (signature === this.lastLayoutFailureSignature) {
      return;
    }
    this.lastLayoutFailureSignature = signature;
    this.onAction({ type: 'layout_failure', anchor: preservedAnchor });
  }

  private measureBlock(
    block: ReadingDocumentBlock,
    startOffset: number,
    endOffset: number,
    metrics: ReadingPageMetrics
  ): ReadingBlockMeasurement {
    if (block.type === 'image') {
      const captionHeight: number = this.resolveImageCaption(block).length > 0 ? 24 : 0;
      return {
        height: this.resolveImageHeight(block, metrics.contentWidth) + captionHeight,
        estimatedLineCount: 0
      };
    }
    const measuredFontSizeVp: number = this.resolveScaledTextMetricVp(this.resolveBlockFontSize(block));
    const measuredLineHeightVp: number = this.resolveScaledTextMetricVp(this.resolveBlockLineHeight(block));
    const size = this.getUIContext().getMeasureUtils().measureTextSize({
      textContent: this.resolveFragmentText(block, startOffset, endOffset),
      constraintWidth: `${this.resolveBlockMeasureWidth(block, metrics.contentWidth)}vp`,
      fontSize: `${measuredFontSizeVp}vp`,
      fontWeight: this.resolveBlockFontWeight(block),
      fontFamily: this.resolveBlockFontFamily(block),
      lineHeight: `${measuredLineHeightVp}vp`,
      textAlign: TextAlign.Start,
      wordBreak: WordBreak.BREAK_WORD
    });
    const heightPx: number = size.height === undefined ? 0 : size.height as number;
    const textHeightVp: number = Math.max(0, this.getUIContext().px2vp(heightPx));
    const measuredText: string = this.resolveFragmentText(block, startOffset, endOffset);
    const estimatedLineCount: number = measuredText.length > 0
      ? Math.max(1, Math.round(textHeightVp / Math.max(1, measuredLineHeightVp)))
      : 0;
    return {
      height: Math.max(
        measuredLineHeightVp,
        textHeightVp + this.resolveBlockVerticalPadding(block)
      ),
      estimatedLineCount: estimatedLineCount
    };
  }

  private handlePageChange(index: number): void {
    const pageSpreadCount: number = this.resolvePageSpreadCount();
    if (this.paginationComplete && this.options.continuationAvailable &&
      index >= pageSpreadCount && this.pages.length > 0) {
      this.onAction({ type: 'reach_end' });
      return;
    }
    const leafPageIndex: number = this.resolveFirstLeafPageIndexForSpread(index);
    if (leafPageIndex < 0 || leafPageIndex >= this.pages.length) {
      return;
    }
    if (this.isAnchorWithinSpread(this.currentAnchor, index)) {
      return;
    }
    this.reportPageAnchor(leafPageIndex);
  }

  private handleReadingTap(event: ClickEvent): void {
    this.handleReadingTapAtX(event.x);
  }

  private handleVerticalContentTap(block: ReadingDocumentBlock): void {
    if (this.isInteractiveContentBlock(block)) {
      return;
    }
    this.onAction({ type: 'toggle_chrome' });
  }

  private handlePagedContentTap(
    block: ReadingDocumentBlock,
    event: GestureEvent,
    spreadSlotIndex: number
  ): void {
    if (this.isInteractiveContentBlock(block) || event.fingerList.length <= 0) {
      return;
    }
    const pageWidth: number = this.resolvePagedLeafWidth();
    const spreadWidth: number = pageWidth * this.resolvePagedColumnCount() +
      this.resolvePagedColumnGap() * Math.max(0, this.resolvePagedColumnCount() - 1);
    const spreadLeft: number = Math.max(0, (this.contentWidthVp - spreadWidth) / 2);
    const pageLeft: number = spreadLeft + spreadSlotIndex * (pageWidth + this.resolvePagedColumnGap());
    const pageContentLeft: number = Math.max(0, (pageWidth - this.resolveAvailableContentWidth()) / 2);
    this.handleReadingTapAtX(pageLeft + pageContentLeft + event.fingerList[0].localX);
  }

  private isInteractiveContentBlock(block: ReadingDocumentBlock): boolean {
    return block.type === 'link' || block.type === 'image';
  }

  private handleReadingTapAtX(x: number): void {
    const width: number = this.contentWidthVp;
    if (width <= 0) {
      this.onAction({ type: 'toggle_chrome' });
      return;
    }
    if (x < width * 0.3) {
      this.turnPage(false);
      return;
    }
    if (x > width * 0.7) {
      this.turnPage(true);
      return;
    }
    this.onAction({ type: 'toggle_chrome' });
  }

  private turnPage(next: boolean): void {
    const pageSpreadCount: number = this.resolvePageSpreadCount();
    const lastIndex: number = this.paginationComplete && this.options.continuationAvailable
      ? pageSpreadCount
      : pageSpreadCount - 1;
    // A progressive page list is only a prefix, so its last page is not a document boundary.
    if (next && !this.paginationComplete && this.currentPage >= lastIndex) {
      return;
    }
    if ((next && this.currentPage >= lastIndex) || (!next && this.currentPage <= 0)) {
      this.onAction({ type: next ? 'reach_end' : 'reach_start' });
      return;
    }
    if (this.mode === 'horizontalFast') {
      const target: number = Math.max(0, Math.min(lastIndex, this.currentPage + (next ? 1 : -1)));
      this.currentPage = target;
      const targetLeafPage: number = this.resolveFirstLeafPageIndexForSpread(target);
      if (targetLeafPage >= 0 && targetLeafPage < this.pages.length) {
        this.reportPageAnchor(targetLeafPage);
      }
      return;
    }
    if (next) {
      this.swiperController.showNext();
    } else {
      this.swiperController.showPrevious();
    }
  }

  private reportPageAnchor(index: number): void {
    if (index < 0 || index >= this.pages.length || this.pages[index].fragments.length === 0) {
      return;
    }
    const fragment: ReadingPageFragment = this.pages[index].fragments[0];
    this.publishAnchorChange(
      this.documentFlow.createAnchor(this.document, fragment.blockId, fragment.startCharacterOffset)
    );
  }

  private reportVerticalAnchor(start: number): void {
    const headerOffset: number = this.options.documentHeaderVisible ? 1 : 0;
    const fragmentIndex: number = Math.max(0, start - headerOffset);
    const fragments: ReadingVerticalFragment[] = this.resolveVerticalFragments();
    if (fragmentIndex >= fragments.length) {
      return;
    }
    const fragment: ReadingVerticalFragment = fragments[fragmentIndex];
    this.publishAnchorChange(this.documentFlow.createAnchor(
      this.document,
      fragment.blockId,
      fragment.startCharacterOffset
    ));
  }

  private publishAnchorChange(anchor: ReadingAnchor): void {
    const current: ReadingAnchor = this.resolveUsableAnchor(anchor);
    const signature: string = this.buildAnchorSignatureFor(current);
    this.currentAnchor = current;
    if (signature === this.lastReportedAnchorSignature) {
      return;
    }
    this.lastReportedAnchorSignature = signature;
    this.livePositionEstablished = true;
    this.onAction({ type: 'anchor_change', anchor: current });
  }

  private resolveCurrentAnchor(): ReadingAnchor {
    if (this.isAnchorUsable(this.currentAnchor)) {
      return this.resolveUsableAnchor(this.currentAnchor);
    }
    const leafPageIndex: number = this.resolveFirstLeafPageIndexForSpread(this.currentPage);
    if (this.mode !== 'vertical' && leafPageIndex >= 0 && leafPageIndex < this.pages.length &&
      this.pages[leafPageIndex].fragments.length > 0) {
      const fragment: ReadingPageFragment = this.pages[leafPageIndex].fragments[0];
      return this.documentFlow.createAnchor(this.document, fragment.blockId, fragment.startCharacterOffset);
    }
    return this.resolveUsableAnchor(this.currentAnchor);
  }

  private resolveUsableAnchor(candidate: ReadingAnchor): ReadingAnchor {
    return this.documentFlow.resolveAnchor(this.document, candidate);
  }

  private isAnchorUsable(candidate: ReadingAnchor): boolean {
    return this.documentFlow.isAnchorRecoverable(this.document, candidate);
  }

  private scheduleAnchorRestore(anchor: ReadingAnchor): void {
    const targetAnchor: ReadingAnchor = this.resolveUsableAnchor(anchor);
    this.clearRestoreTimer();
    this.restoreTimer = setTimeout((): void => {
      this.restoreTimer = -1;
      if (targetAnchor.documentId !== this.document.id) {
        return;
      }
      if (this.mode === 'vertical') {
        this.restoreVerticalAnchor(targetAnchor);
        return;
      }
      const targetLeafPage: number = this.paginator.findPageForAnchor(this.pages, targetAnchor);
      this.currentPage = this.resolveSpreadIndexForLeafPage(targetLeafPage);
    }, 0);
  }

  private restoreVerticalAnchor(anchor: ReadingAnchor): void {
    const fragmentIndex: number = this.findVerticalFragmentIndex(anchor);
    if (fragmentIndex < 0) {
      return;
    }
    const headerOffset: number = this.options.documentHeaderVisible ? 1 : 0;
    this.verticalScroller.scrollToIndex(fragmentIndex + headerOffset, false, ScrollAlign.START);
  }

  private clearRestoreTimer(): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
  }

  private resolveVerticalFragments(): ReadingVerticalFragment[] {
    if (this.cachedVerticalDocument === this.document) {
      return this.cachedVerticalFragments;
    }
    this.cachedVerticalDocument = this.document;
    this.cachedVerticalFragments = this.documentFlow.buildVerticalFragments(
      this.document,
      READING_SURFACE_VERTICAL_FRAGMENT_MAX_CHARACTERS
    );
    return this.cachedVerticalFragments;
  }

  private findVerticalFragmentIndex(anchor: ReadingAnchor): number {
    const fragments: ReadingVerticalFragment[] = this.resolveVerticalFragments();
    let lastMatchingIndex: number = -1;
    for (let index: number = 0; index < fragments.length; index++) {
      const fragment: ReadingVerticalFragment = fragments[index];
      if (fragment.blockId !== anchor.blockId) {
        continue;
      }
      lastMatchingIndex = index;
      if (fragment.atomic ||
        (anchor.characterOffset >= fragment.startCharacterOffset &&
          anchor.characterOffset < fragment.endCharacterOffset)) {
        return index;
      }
      if (anchor.characterOffset === fragment.startCharacterOffset) {
        return index;
      }
    }
    return lastMatchingIndex;
  }

  private resolveFragmentPrefix(block: ReadingDocumentBlock, startOffset: number): string {
    if (startOffset === 0 && this.options.paragraphIndentVisible && block.type === 'paragraph') {
      return READING_SURFACE_PARAGRAPH_INDENT;
    }
    if (startOffset === 0 && block.type === 'list_item') {
      return '• ';
    }
    return '';
  }

  private resolveFragmentText(block: ReadingDocumentBlock, startOffset: number, endOffset: number): string {
    return this.resolveFragmentPrefix(block, startOffset) + block.text.substring(startOffset, endOffset);
  }

  private resolveActiveSearchCharacterOffset(): number {
    const blockIndex: number = this.documentFlow.findBlockIndex(this.document, this.search.activeBlockId);
    if (blockIndex < 0) {
      return 0;
    }
    return this.documentFlow.resolveMatchCharacterOffset(
      this.document.blocks[blockIndex].text,
      this.search.query,
      this.search.activeMatchIndexInBlock
    );
  }

  private resolveSearchHighlightColor(active: boolean): ResourceColor {
    return active ? $r('app.color.reader_surface_search_active_background') :
      $r('app.color.reader_surface_search_match_background');
  }

  private resolveSearchHighlightTextColor(active: boolean): ResourceColor {
    return active ? $r('app.color.reader_surface_search_active_text') :
      $r('app.color.reader_surface_search_match_text');
  }

  private resolveBlockFontSize(block: ReadingDocumentBlock): number {
    if (block.type === 'heading') {
      const level: number = block.level ?? 2;
      return this.appearance.fontSize + (level <= 1 ? 8 : (level === 2 ? 6 : 4));
    }
    if (block.type === 'code') {
      return Math.max(13, this.appearance.fontSize - 2);
    }
    return this.appearance.fontSize;
  }

  private resolveBlockLineHeight(block: ReadingDocumentBlock): number {
    if (block.type === 'code') {
      return this.resolveBlockFontSize(block) * 1.45;
    }
    return this.resolveBlockFontSize(block) * this.resolveLineHeightRatio();
  }

  private resolveBlockFontWeight(block: ReadingDocumentBlock): FontWeight {
    return block.type === 'heading' ? FontWeight.Bold : FontWeight.Regular;
  }

  private resolveBlockFontFamily(block: ReadingDocumentBlock): string {
    return block.type === 'code' ? 'monospace' : '';
  }

  private resolvePaginationSafetyHeight(): number {
    return this.resolveScaledTextMetricVp(this.appearance.fontSize * this.resolveLineHeightRatio());
  }

  private resolveScaledTextMetricVp(value: number): number {
    const fontSizeScale: number = this.systemFontSizeScale > 0 ? this.systemFontSizeScale : 1;
    return value * fontSizeScale;
  }

  private resolveBlockMeasureWidth(block: ReadingDocumentBlock, contentWidth: number): number {
    if (block.type === 'link') {
      return Math.max(1, contentWidth - 20);
    }
    if (block.type === 'quote') {
      return Math.max(1, contentWidth - 16);
    }
    if (block.type === 'code') {
      return Math.max(1, contentWidth - 24);
    }
    return contentWidth;
  }

  private resolveBlockVerticalPadding(block: ReadingDocumentBlock): number {
    if (block.type === 'link' || block.type === 'code') {
      return 20;
    }
    return block.type === 'quote' ? 4 : 0;
  }

  private resolveLineHeightRatio(): number {
    if (this.appearance.lineHeight === 'compact') {
      return 1.45;
    }
    if (this.appearance.lineHeight === 'loose') {
      return 1.9;
    }
    return 1.65;
  }

  private resolvePageSpreads(): ReadingPageSpread[] {
    const spreads: ReadingPageSpread[] = [];
    const columnCount: number = this.resolvePagedColumnCount();
    const spreadCount: number = this.resolvePageSpreadCount();
    for (let spreadIndex: number = 0; spreadIndex < spreadCount; spreadIndex++) {
      const slots: ReadingPageSpreadSlot[] = [];
      for (let slotIndex: number = 0; slotIndex < columnCount; slotIndex++) {
        const pageIndex: number = spreadIndex * columnCount + slotIndex;
        slots.push({
          kind: pageIndex < this.pages.length ? 'page' : 'empty',
          pageIndex: pageIndex < this.pages.length ? pageIndex : -1
        });
      }
      spreads.push({ index: spreadIndex, slots: slots });
    }
    if (this.paginationComplete && this.options.continuationAvailable && this.pages.length > 0) {
      const continuationSlots: ReadingPageSpreadSlot[] = [];
      for (let slotIndex: number = 0; slotIndex < columnCount; slotIndex++) {
        continuationSlots.push({
          kind: slotIndex === 0 ? 'continuation' : 'empty',
          pageIndex: -1
        });
      }
      spreads.push({ index: spreadCount, slots: continuationSlots });
    }
    return spreads;
  }

  private resolvePagedColumnCount(): number {
    if (this.mode === 'vertical') {
      return 1;
    }
    return Math.max(1, Math.min(2, Math.floor(this.pagedColumnCount)));
  }

  private resolvePagedColumnGap(): number {
    return this.resolvePagedColumnCount() > 1 ? Math.max(0, this.pagedColumnGap) : 0;
  }

  private resolvePagedLeafWidth(): number {
    const columnCount: number = this.resolvePagedColumnCount();
    const totalGap: number = this.resolvePagedColumnGap() * Math.max(0, columnCount - 1);
    return Math.max(1, (this.resolvePagedSpreadWidth() - totalGap) / columnCount);
  }

  private resolvePagedSpreadWidth(): number {
    return this.resolvePagedSpreadWidthFor(this.contentWidthVp);
  }

  private resolvePagedSpreadWidthFor(contentWidthVp: number): number {
    if (this.mode === 'vertical' && this.contentWidth > 0) {
      return Math.min(contentWidthVp, this.contentWidth);
    }
    if (this.pagedContentWidth <= 0) {
      return contentWidthVp;
    }
    return Math.min(contentWidthVp, this.pagedContentWidth);
  }

  private resolvePageSpreadCount(): number {
    if (this.pages.length <= 0) {
      return 0;
    }
    return Math.ceil(this.pages.length / this.resolvePagedColumnCount());
  }

  private resolveSpreadIndexForLeafPage(leafPageIndex: number): number {
    return Math.max(0, Math.floor(Math.max(0, leafPageIndex) / this.resolvePagedColumnCount()));
  }

  private resolveFirstLeafPageIndexForSpread(spreadIndex: number): number {
    if (spreadIndex < 0) {
      return -1;
    }
    return spreadIndex * this.resolvePagedColumnCount();
  }

  private isAnchorWithinSpread(anchor: ReadingAnchor, spreadIndex: number): boolean {
    if (!this.isAnchorUsable(anchor) || this.pages.length <= 0 || spreadIndex < 0) {
      return false;
    }
    const leafPageIndex: number = this.paginator.findPageForAnchor(this.pages, anchor);
    return this.resolveSpreadIndexForLeafPage(leafPageIndex) === spreadIndex;
  }

  private resolveContentWidth(): string {
    if (this.shouldUseFullWidthVerticalSurface()) {
      return '100%';
    }
    if (this.appearance.pageWidth === 'narrow') {
      return '82%';
    }
    if (this.appearance.pageWidth === 'wide') {
      return '100%';
    }
    return '92%';
  }

  private shouldUseFullWidthVerticalSurface(): boolean {
    return this.mode === 'vertical' && this.contentWidth > 0;
  }

  private resolveVerticalListHorizontalPadding(): number {
    if (!this.shouldUseFullWidthVerticalSurface() || this.contentWidthVp <= 0) {
      return READING_SURFACE_HORIZONTAL_PADDING;
    }
    return READING_SURFACE_HORIZONTAL_PADDING + this.resolveVerticalRailInset();
  }

  private resolveVerticalRailInset(): number {
    if (this.contentWidthVp <= 0) {
      return 0;
    }
    const boundedWidth: number = Math.min(this.contentWidthVp, this.contentWidth);
    const railWidth: number = boundedWidth * this.resolvePageWidthRatio();
    return Math.max(0, (this.contentWidthVp - railWidth) / 2);
  }

  private resolvePageWidthRatio(): number {
    return this.appearance.pageWidth === 'narrow' ? 0.82 :
      (this.appearance.pageWidth === 'wide' ? 1 : 0.92);
  }

  private resolveAvailableContentWidth(): number {
    return Math.max(1, this.resolvePagedLeafWidth() * this.resolvePageWidthRatio() -
      READING_SURFACE_HORIZONTAL_PADDING * 2);
  }

  private resolvePageChromeHeight(): number {
    return (this.options.pageHeaderVisible ? READING_SURFACE_PAGE_HEADER_HEIGHT : 0) +
      (this.options.pageNumberVisible ? READING_SURFACE_PAGE_FOOTER_HEIGHT : 0) +
      this.options.contentTopInset + this.options.contentBottomInset;
  }

  private resolveImageUrl(block: ReadingDocumentBlock): string {
    const urls: string[] = this.collectImageUrls(block);
    for (let index: number = 0; index < urls.length; index++) {
      if (this.failedImageUrls.indexOf(urls[index]) < 0) {
        return urls[index];
      }
    }
    return urls.length > 0 ? urls[0] : '';
  }

  private resolveImageCaption(block: ReadingDocumentBlock): string {
    const caption: string = block.caption?.trim() ?? '';
    return caption.length > 0 ? caption : (block.alt?.trim() ?? '');
  }

  private resolveImageHeight(block: ReadingDocumentBlock, width: number): number {
    const sourceWidth: number = this.resolvePositiveImageMetric(block.width, block.renderedWidth);
    const sourceHeight: number = this.resolvePositiveImageMetric(block.height, block.renderedHeight);
    if (sourceWidth > 0 && sourceHeight > 0) {
      return Math.min(READING_SURFACE_MAX_IMAGE_HEIGHT, Math.max(72, width * sourceHeight / sourceWidth));
    }
    return Math.min(READING_SURFACE_MAX_IMAGE_HEIGHT, READING_SURFACE_DEFAULT_IMAGE_HEIGHT);
  }

  private shouldShowImage(block: ReadingDocumentBlock): boolean {
    const url: string = this.resolveImageUrl(block);
    return url.length > 0 && this.failedImageUrls.indexOf(url) < 0;
  }

  private shouldShowImageFallback(block: ReadingDocumentBlock): boolean {
    const policy: string = block.imageFailurePolicy ?? '';
    if (policy === 'hide' || policy === 'caption_only') {
      return false;
    }
    if (this.resolveImageCaption(block).length > 0 && (block.qualityScore ?? 0) < 76) {
      return false;
    }
    return true;
  }

  private resolveImageFallbackHeight(block: ReadingDocumentBlock): number {
    if ((block.imageFailurePolicy ?? '') === 'compact_placeholder' || (block.qualityScore ?? 0) >= 76) {
      return READING_SURFACE_IMAGE_COMPACT_FALLBACK_HEIGHT;
    }
    return READING_SURFACE_IMAGE_FALLBACK_HEIGHT;
  }

  private collectImageUrls(block: ReadingDocumentBlock): string[] {
    const urls: string[] = [];
    this.appendImageUrl(urls, block.url ?? '');
    this.appendImageUrl(urls, block.originalUrl ?? '');
    const fallbackUrls: string[] = block.fallbackUrls ?? [];
    for (let index: number = 0; index < fallbackUrls.length; index++) {
      this.appendImageUrl(urls, fallbackUrls[index]);
    }
    return urls;
  }

  private appendImageUrl(urls: string[], value: string): void {
    const normalized: string = value.trim();
    if (normalized.length > 0 && urls.indexOf(normalized) < 0) {
      urls.push(normalized);
    }
  }

  private resolvePositiveImageMetric(primary: number | undefined, fallback: number | undefined): number {
    if (primary !== undefined && primary > 0) {
      return primary;
    }
    return fallback !== undefined && fallback > 0 ? fallback : 0;
  }

  private markImageFailed(url: string): void {
    if (url.length === 0 || this.failedImageUrls.indexOf(url) >= 0) {
      return;
    }
    this.failedImageUrls = this.failedImageUrls.concat([url]);
  }

  private resolveEffectiveTheme(): ReaderModeTheme {
    return resolveEffectiveReadingTheme(this.activeTheme);
  }

  private resolveBackgroundColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).backgroundColor;
  }

  private resolveControlBackgroundColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).controlBackgroundColor;
  }

  private resolveTextColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).secondaryTextColor;
  }
}
