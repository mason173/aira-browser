import {
  ReaderModeAction,
  ReaderModeArticle,
  ReaderModeControlPanel,
  ReaderModeTheme,
  ReaderModeViewState
} from '../../../features/reader/ReaderModeModels';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { ArticleReadingDocumentAdapter } from '../../../features/reader/ArticleReadingDocumentAdapter';
import { ReadingDocument } from '../../../features/reading/ReadingDocumentModels';
import {
  ReadingPresentationMode,
  ReadingSurfaceAction,
  ReadingSurfaceAppearance,
  ReadingSurfaceOptions,
  ReadingSurfaceSearchPresentation
} from '../../../features/reading/ReadingSurfaceModels';
import { ReadingSurface } from '../reading/ReadingSurface';
import {
  ReadingExperienceChrome,
  resolveReadingExperienceBottomChromeHeight,
  resolveReadingExperienceTopChromeHeight
} from '../reading/ReadingExperienceChrome';
import {
  resolveEffectiveReadingTheme,
  resolveReadingThemeTokens
} from '../reading/ReadingThemeTokenResolver';

const READER_IMAGE_PREVIEW_MIN_SCALE: number = 1;
const READER_IMAGE_PREVIEW_MAX_SCALE: number = 3;
const READER_IMAGE_PREVIEW_SCALE_STEP: number = 0.5;
const READER_SEARCH_INPUT_FOCUS_ID: string = 'aira-reader-search-input';
const READER_SEARCH_INPUT_FOCUS_DELAY_MS: number = 48;
const READER_THEME_TRANSITION_DURATION_MS: number = 260;
@Component
export struct ReaderModeOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @Prop state: ReaderModeViewState;
  @Prop topSafeInsetVp: number = 0;
  @Prop bottomSafeInsetVp: number = 0;
  @Prop
  globalImmersionEnabled: boolean = false;
  @Prop
  alwaysTopImmersionEnabled: boolean = false;
  @Prop statusBarVisible: boolean = true;
  @Prop
  @Watch('syncImagePreviewDismissRequest')
  dismissImagePreviewRequestVersion: number = 0;
  @Prop
  @Watch('syncPanelDismissRequest')
  dismissPanelRequestVersion: number = 0;
  @Prop presentationMode: ReadingPresentationMode = 'vertical';
  @State searchDraft: string = '';
  @State previewImageUrl: string = '';
  @State previewImageCaption: string = '';
  @State previewImageScale: number = 1;
  @State searchPanelVisible: boolean = false;
  @State readerChromeVisible: boolean = true;
  private searchInputFocusTimer: number = -1;
  private readingDocumentAdapter: ArticleReadingDocumentAdapter = new ArticleReadingDocumentAdapter();
  private cachedReadingArticle?: ReaderModeArticle;
  private cachedReadingDocument?: ReadingDocument;
  onAction: (action: ReaderModeAction) => void = (_action: ReaderModeAction) => {};

  aboutToDisappear(): void {
    this.clearSearchInputFocusRequest();
    this.restoreReaderChrome('reader-disappear');
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.buildReaderContentLayer()

      if (this.previewImageUrl.length > 0) {
        this.buildImagePreviewOverlay()
      }

    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBackgroundColor())
    .animation(this.resolveThemeTransitionAnimation())
    .zIndex(80)
  }

  @Builder
  private buildReaderContentLayer() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.buildReaderContentBase()
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildReaderContentBase() {
    Column() {
      if (this.state.loading) {
        this.buildLoading()
      } else if (this.state.errorMessage.length > 0) {
        this.buildError()
      } else {
        this.buildArticle()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBackgroundColor())

    if (this.readerChromeVisible) {
      ReadingExperienceChrome({
        title: '',
        closeAccessibilityLabel: '退出阅读模式',
        visible: true,
        appearance: this.resolveReadingSurfaceAppearance(),
        topSafeInset: this.resolveTopSafeInset(),
        bottomSafeInset: this.resolveBottomSafeInset(),
        contextRowVisible: false,
        primaryActionIcon: 'reader.readAloud',
        primaryActionLabel: '朗读',
        topActionsWidth: 68,
        onClose: (): void => {
          this.onAction({ type: 'close' });
        },
        onPrimaryAction: (): void => {
          this.onAction({ type: 'open_speech_player' });
        },
        onPanelRequest: (panel: ReaderModeControlPanel): void => {
          this.onAction({ type: 'open_control_panel', panel: panel });
        },
        topActions: (): void => {
          this.buildArticleTopActions()
        }
      })
      .width('100%')
      .height('100%')
      .hitTestBehavior(HitTestMode.None)
      .zIndex(2)
    }

    if (this.searchPanelVisible && this.readerChromeVisible) {
      this.buildArticleSearchToolbar()
    }
  }

  @Builder
  private buildArticleSearchToolbar() {
    Column() {
      Blank()
        .width('100%')
        .height(this.resolveTopSafeInset())
      this.buildSearchBarContent()
      Blank()
        .width('100%')
        .height(10)
    }
    .width('100%')
    .height(this.resolveReadingTopChromeHeight())
    .backgroundColor(this.resolveControlBackgroundColor())
    .position({ x: 0, y: 0 })
    .zIndex(3)
  }

  @Builder
  private buildArticleTopActions() {
    Row({ space: 4 }) {
      this.buildIconButton('reader.find', (): void => {
        this.openSearchPanel();
      }, 0, '查找正文')
      this.buildIconButton('reader.share', (): void => {
        this.onAction({ type: 'share' });
      }, 0, '分享文章')
    }
    .width(68)
    .height(32)
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildSearchBarContent() {
    Row({ space: 5 }) {
      Stack({ alignContent: Alignment.End }) {
        TextInput({ placeholder: '查找正文', text: this.searchDraft })
          .id(READER_SEARCH_INPUT_FOCUS_ID)
          .width('100%')
          .height(32)
          .fontSize(14)
          .backgroundColor(this.resolveControlBackgroundColor())
          .animation(this.resolveThemeTransitionAnimation())
          .fontColor(this.resolveTextColor())
          .placeholderColor(this.resolveSecondaryTextColor())
          .caretColor(this.storedAccentColor)
          .borderRadius(16)
          .padding({ left: 12, right: 58 })
          .enterKeyType(EnterKeyType.Search)
          .focusOnTouch(true)
          .enableKeyboardOnFocus(true)
          .onAppear(() => {
            this.syncSearchInputFocusRequest();
          })
          .onChange((value: string) => {
            this.searchDraft = value;
            this.onAction({
              type: 'search_change',
              query: value
            });
          })
          .onSubmit((_enterKey: EnterKeyType) => {
            this.onAction({ type: 'search_next' });
          })

        Text(this.resolveSearchSummary())
          .fontSize(12)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(48)
          .textAlign(TextAlign.End)
          .margin({ right: 10 })
          .hitTestBehavior(HitTestMode.None)
      }
      .height(32)
      .layoutWeight(1)

      this.buildIconButton('browser.toolbar.back', (): void => {
        this.onAction({ type: 'search_previous' });
      }, 90, '上一个匹配项')
      this.buildIconButton('browser.toolbar.back', (): void => {
        this.onAction({ type: 'search_next' });
      }, -90, '下一个匹配项')
      this.buildIconButton('browser.toolbar.clearInput', (): void => {
        this.closeSearchPanel();
      }, 0, '关闭查找')
    }
    .width('100%')
    .height(32)
    .padding({ left: 22, right: 22 })
    .animation(this.resolveThemeTransitionAnimation())
  }

  @Builder
  private buildArticle() {
    ReadingSurface({
      document: this.resolveReadingDocument(),
      mode: this.presentationMode,
      appearance: this.resolveReadingSurfaceAppearance(),
      activeTheme: this.resolveEffectiveTheme(),
      options: this.resolveReadingSurfaceOptions(),
      search: this.resolveReadingSurfaceSearch(),
      onAction: (action: ReadingSurfaceAction): void => {
        this.handleReadingSurfaceAction(action);
      }
    })
    .width('100%')
    .height('100%')
    .padding({
      top: this.resolveContentTopInset(),
      bottom: this.resolveContentBottomInset()
    })
  }

  private resolveReadingDocument(): ReadingDocument {
    if (this.cachedReadingDocument !== undefined && this.cachedReadingArticle === this.state.article) {
      return this.cachedReadingDocument;
    }
    this.cachedReadingArticle = this.state.article;
    this.cachedReadingDocument = this.readingDocumentAdapter.adapt(this.state.article);
    return this.cachedReadingDocument;
  }

  private resolveReadingSurfaceAppearance(): ReadingSurfaceAppearance {
    return {
      fontSize: this.state.preferences.fontSize,
      theme: this.state.preferences.theme,
      lineHeight: this.state.preferences.lineHeight,
      pageWidth: this.state.preferences.pageWidth,
      brightnessMode: this.state.preferences.brightnessMode,
      brightnessPercent: this.state.preferences.brightnessPercent
    };
  }

  private resolveReadingSurfaceOptions(): ReadingSurfaceOptions {
    return {
      documentHeaderVisible: true,
      pageHeaderVisible: true,
      pageNumberVisible: true,
      paragraphIndentVisible: false,
      continuationAvailable: false,
      continuationLabel: '继续阅读',
      contentTopInset: 0,
      contentBottomInset: 0
    };
  }

  private resolveReadingSurfaceSearch(): ReadingSurfaceSearchPresentation {
    return {
      query: this.state.search.query,
      activeBlockId: this.state.search.activeBlockId,
      activeMatchIndexInBlock: this.resolveActiveLocalMatchIndex(this.state.search.activeBlockId)
    };
  }

  private handleReadingSurfaceAction(action: ReadingSurfaceAction): void {
    if (action.type === 'anchor_change') {
      return;
    }
    if (action.type === 'layout_failure') {
      this.onAction({ type: 'reading_layout_failure' });
      return;
    }
    if (action.type === 'open_link') {
      this.onAction({ type: 'open_link', url: action.url });
      return;
    }
    if (action.type === 'preview_image') {
      this.openImagePreview(action.url, action.caption);
      return;
    }
    if (action.type === 'toggle_chrome') {
      this.toggleReaderChrome();
    }
  }

  private toggleReaderChrome(): void {
    if (this.searchPanelVisible) {
      this.closeSearchPanel();
      return;
    }
    const visible: boolean = !this.readerChromeVisible;
    this.readerChromeVisible = visible;
    this.onAction({
      type: 'status_bar_visibility_change',
      visible: visible,
      source: 'reader-tap'
    });
  }

  @Builder
  private buildLoading() {
    Column({ space: 12 }) {
      LoadingProgress()
        .width(36)
        .height(36)
      Text('正在整理正文...')
        .fontSize(15)
        .fontColor(this.resolveSecondaryTextColor())
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      top: this.resolveContentTopInset(),
      bottom: this.resolveContentBottomInset()
    })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildError() {
    Column({ space: 12 }) {
      Text(this.state.errorMessage)
        .fontSize(15)
        .fontColor(this.resolveTextColor())
        .textAlign(TextAlign.Center)
      Button('返回网页')
        .onClick(() => {
          this.onAction({ type: 'close' });
        })
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: 32,
      right: 32,
      top: this.resolveContentTopInset(),
      bottom: this.resolveContentBottomInset()
    })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildIconButton(
    iconId: AiraRenderableIconId,
    action: () => void,
    rotationAngle: number = 0,
    accessibilityLabel: string = ''
  ) {
    Button() {
      this.buildReaderIconImage(iconId, 16, rotationAngle)
    }
    .width(32)
    .height(32)
    .padding(0)
    .type(ButtonType.Normal)
    .borderRadius(16)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .animation(this.resolveThemeTransitionAnimation())
    .accessibilityText(accessibilityLabel)
    .onClick(action)
  }

  private resolveSearchSummary(): string {
    if (this.state.search.query.trim().length <= 0) {
      return '';
    }
    if (this.state.search.matches <= 0) {
      return '0/0';
    }
    return `${this.state.search.activeIndex + 1}/${this.state.search.matches}`;
  }

  private resolveThemeTransitionAnimation(): AnimateParam {
    return {
      duration: READER_THEME_TRANSITION_DURATION_MS,
      curve: Curve.EaseInOut
    };
  }

  @Builder
  private buildImagePreviewOverlay() {
    Stack({ alignContent: Alignment.TopEnd }) {
      Column() {
        Blank()
        Image(this.previewImageUrl)
          .width('100%')
          .height('72%')
          .objectFit(ImageFit.Contain)
          .scale({ x: this.previewImageScale, y: this.previewImageScale })
          .onClick(() => {
            this.closeImagePreview();
          })
        Text(this.previewImageCaption)
          .fontSize(13)
          .fontColor($r('app.color.reader_image_preview_text'))
          .textAlign(TextAlign.Center)
          .maxLines(2)
          .visibility(this.previewImageCaption.length > 0 ? Visibility.Visible : Visibility.None)
        .padding({ left: 24, right: 24, top: 12 })
        Row({ space: 12 }) {
          this.buildPreviewButton('reader.decreaseFont', () => {
            this.zoomImagePreview(-READER_IMAGE_PREVIEW_SCALE_STEP);
          })
          this.buildPreviewButton('reader.refresh', () => {
            this.resetImagePreviewZoom();
          })
          this.buildPreviewButton('reader.increaseFont', () => {
            this.zoomImagePreview(READER_IMAGE_PREVIEW_SCALE_STEP);
          })
        }
        .padding({ top: 18, bottom: 24 })
        Blank()
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

      Button() {
        this.buildReaderIconImage('browser.toolbar.clearInput', 24)
      }
      .width(44)
      .height(44)
      .type(ButtonType.Normal)
      .borderRadius(22)
      .backgroundColor($r('app.color.reader_image_preview_control_background'))
      .margin({ top: 14, right: 14 })
      .onClick(() => {
        this.closeImagePreview();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.reader_image_preview_scrim'))
    .zIndex(120)
  }

  @Builder
  private buildPreviewButton(iconId: AiraRenderableIconId, action: () => void) {
    Button() {
      this.buildReaderIconImage(iconId, 24)
    }
    .width(42)
    .height(42)
    .type(ButtonType.Normal)
    .borderRadius(21)
    .backgroundColor($r('app.color.reader_image_preview_control_background'))
    .onClick(action)
  }

  @Builder
  private buildReaderIconImage(
    iconId: AiraRenderableIconId,
    size: number,
    rotationAngle: number = 0,
    iconColor: ResourceColor | undefined = undefined
  ) {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: iconId,
        iconSize: size,
        iconColor: iconColor === undefined ? this.resolveTextColor() : iconColor
      })
    }
    .width(size)
    .height(size)
    .rotate({ angle: rotationAngle })
  }

  private openImagePreview(imageUrl: string, caption: string): void {
    if (imageUrl.length <= 0) {
      return;
    }
    this.previewImageUrl = imageUrl;
    this.previewImageCaption = caption;
    this.previewImageScale = 1;
    this.onAction({
      type: 'image_preview_visibility_change',
      visible: true
    });
  }

  private closeImagePreview(): void {
    if (this.previewImageUrl.length <= 0) {
      return;
    }
    this.previewImageUrl = '';
    this.previewImageCaption = '';
    this.previewImageScale = 1;
    this.onAction({
      type: 'image_preview_visibility_change',
      visible: false
    });
  }

  private syncImagePreviewDismissRequest(): void {
    this.closeImagePreview();
  }

  private zoomImagePreview(delta: number): void {
    this.previewImageScale = Math.max(
      READER_IMAGE_PREVIEW_MIN_SCALE,
      Math.min(READER_IMAGE_PREVIEW_MAX_SCALE, this.previewImageScale + delta)
    );
  }

  private resetImagePreviewZoom(): void {
    this.previewImageScale = 1;
  }

  private openSearchPanel(): void {
    this.searchPanelVisible = true;
    this.reportPanelVisibility();
    this.syncSearchInputFocusRequest();
  }

  private closeSearchPanel(): void {
    this.clearSearchInputFocusRequest();
    if (this.searchDraft.length > 0 || this.state.search.query.length > 0) {
      this.searchDraft = '';
      this.onAction({
        type: 'search_change',
        query: ''
      });
    }
    this.searchPanelVisible = false;
    this.reportPanelVisibility();
    this.restoreReaderChrome('search-close');
  }

  private syncPanelDismissRequest(): void {
    if (this.searchPanelVisible) {
      this.closeSearchPanel();
    }
  }

  private reportPanelVisibility(): void {
    this.onAction({
      type: 'panel_visibility_change',
      visible: this.searchPanelVisible
    });
  }

  private restoreReaderChrome(source: string): void {
    this.readerChromeVisible = true;
    this.onAction({
      type: 'status_bar_visibility_change',
      visible: true,
      source: source
    });
  }

  private syncSearchInputFocusRequest(): void {
    this.clearSearchInputFocusRequest();
    if (!this.searchPanelVisible) {
      return;
    }
    this.searchInputFocusTimer = setTimeout(() => {
      this.searchInputFocusTimer = -1;
      if (this.searchPanelVisible) {
        focusControl.requestFocus(READER_SEARCH_INPUT_FOCUS_ID);
      }
    }, READER_SEARCH_INPUT_FOCUS_DELAY_MS);
  }

  private clearSearchInputFocusRequest(): void {
    if (this.searchInputFocusTimer >= 0) {
      clearTimeout(this.searchInputFocusTimer);
      this.searchInputFocusTimer = -1;
    }
  }

  private getBlockMatchCount(blockId: string): number {
    return this.state.search.blockMatchCounts[blockId] ?? 0;
  }

  private resolveActiveLocalMatchIndex(blockId: string): number {
    if (this.state.search.activeBlockId !== blockId || this.state.search.activeIndex < 0) {
      return -1;
    }
    let matchesBeforeBlock = 0;
    for (let index = 0; index < this.state.article.blocks.length; index += 1) {
      const block = this.state.article.blocks[index];
      if (block.id === blockId) {
        return this.state.search.activeIndex - matchesBeforeBlock;
      }
      matchesBeforeBlock += this.getBlockMatchCount(block.id);
    }
    return -1;
  }

  private resolveBackgroundColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).backgroundColor;
  }

  private resolveControlBackgroundColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).controlBackgroundColor;
  }

  private resolveTopSafeInset(): number {
    if (this.alwaysTopImmersionEnabled) {
      return 0;
    }
    if (this.globalImmersionEnabled && !this.statusBarVisible) {
      return 0;
    }
    return Math.max(0, Math.ceil(this.topSafeInsetVp));
  }

  private resolveBottomSafeInset(): number {
    return Math.max(0, Math.ceil(this.bottomSafeInsetVp));
  }

  private resolveContentTopInset(): number {
    return this.readerChromeVisible ? this.resolveReadingTopChromeHeight() : 0;
  }

  private resolveContentBottomInset(): number {
    return this.readerChromeVisible ? this.resolveReadingBottomChromeHeight() : this.resolveBottomSafeInset();
  }

  private resolveReadingTopChromeHeight(): number {
    return resolveReadingExperienceTopChromeHeight(this.resolveTopSafeInset());
  }

  private resolveReadingBottomChromeHeight(): number {
    return resolveReadingExperienceBottomChromeHeight(this.resolveBottomSafeInset(), false);
  }

  private resolveTextColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return resolveReadingThemeTokens(this.resolveEffectiveTheme()).secondaryTextColor;
  }

  private resolveEffectiveTheme(): ReaderModeTheme {
    return resolveEffectiveReadingTheme(this.state.preferences.theme);
  }

}
