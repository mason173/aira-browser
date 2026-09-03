import { common } from '@kit.AbilityKit';
import {
  ReaderModeTheme
} from '../../../common/models/BrowserModels';
import {
  NOVEL_CATALOG_RANGE_SIZE,
  NovelReaderAction,
  NovelReaderCatalogEntry,
  NovelReaderControlPanel,
  NovelContentKind,
  NovelReaderPreferences,
  NovelReaderSnapshot,
  NovelReadingPosition,
  resolveNovelModeLabel,
  resolveNovelReadingModeLabel
} from '../../../features/novel/NovelReaderModels';
import {
  buildNovelChapterRenderKey,
  NovelSessionCommittedChapter
} from '../../../features/novel/NovelReadingSessionState';
import { NovelReadingDocumentAdapter } from '../../../features/novel/NovelReadingDocumentAdapter';
import {
  ReadingAnchor,
  ReadingDocument
} from '../../../features/reading/ReadingDocumentModels';
import {
  ReadingSurfaceAction,
  ReadingSurfaceAppearance,
  ReadingSurfaceCommand,
  ReadingSurfaceOptions,
  createDefaultReadingSurfaceCommand
} from '../../../features/reading/ReadingSurfaceModels';
import {
  NovelBookCoverPalette,
  NovelBookPaletteThemeMode,
  buildNovelBookPaletteCacheKey
} from '../../../features/novel/NovelLibraryModels';
import { BrowserStatusBarStyleService } from '../../../services/browser/BrowserStatusBarStyleService';
import {
  NovelReaderLayoutMode,
  NovelReaderLayoutState
} from '../../../core/novel/NovelReaderLayoutViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor
} from '../common/FloatingGlassMaterialTokens';
import { NovelBookCover } from '../novel/NovelBookCover';
import { NovelComicImage } from '../novel/NovelComicImage';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserBottomChromeMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';
import { resolveBrowserBottomFloatingMaterialShadowColor } from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { ReadingSurface } from '../reading/ReadingSurface';
import { ReadingExperienceChrome } from '../reading/ReadingExperienceChrome';
import {
  resolveEffectiveReadingTheme,
  resolveReadingThemeTokens
} from '../reading/ReadingThemeTokenResolver';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';

const NOVEL_READER_H_PADDING: number = 22;
const NOVEL_READER_BOTTOM_GESTURE_GAP: number = 24;
const NOVEL_READER_AUTO_SCROLL_INTERVAL_MS: number = 24;
const NOVEL_READER_AUTO_SPEED_MIN: number = 1;
const NOVEL_READER_AUTO_SPEED_MAX: number = 5;
const NOVEL_READER_STATUS_BAR_STYLE_REASSERT_MS: number = 360;
const NOVEL_BOOK_ACTION_SURFACE_HEIGHT: number = 124;
const NOVEL_BOOK_ACTION_BUTTON_HEIGHT: number = 48;
const NOVEL_BOOK_ACTION_BOTTOM_CONTENT_INSET: number = 18;
const NOVEL_BOOK_ACTION_GAP: number = 10;
const NOVEL_COMIC_IMAGE_MIN_HEIGHT: number = 220;

/**
 * 小说模式外壳。
 * - 默认界面:底部两层(章节行 上一章/章节名/下一章 + 导航行 目录/标签页/主题/设置)。
 * - 点"目录":底部弹出目录 sheet(封面+书名+作者+章节列表,当前章高亮,去当前)。
 * - 小说点"文字"、"主题"、"设置"；漫画点"主题"、"设置"，统一交给浏览器根节点的系统 Sheet 呈现。
 * - 文字章节交给 ReadingSurface 排版，漫画与小说专属导航仍由本外壳承载。
 */
@Component
export struct NovelReaderOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) @Watch('onBookThemeModeChanged')
  private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  @Prop @Watch('onSessionStateChanged') state: NovelReaderSnapshot;
  @Prop @Watch('onReaderThemeChanged') readerTheme: ReaderModeTheme = 'system';
  @Prop @Watch('onLayoutStateChanged') layoutState: NovelReaderLayoutState;
  onAction: (action: NovelReaderAction) => void = (_action: NovelReaderAction) => {};

  @State chromeVisible: boolean = true;
  @State autoReadingPaused: boolean = false;
  @State readingSurfaceCommand: ReadingSurfaceCommand = createDefaultReadingSurfaceCommand();
  @State private readingSurfaceDocument: ReadingDocument = {
    id: '',
    title: '',
    subtitle: '',
    blocks: []
  };
  @State private readingSurfaceDocumentSignature: string = '';
  @State private expandedBookCatalogRangeStarts: number[] = [0];
  private readingDocumentAdapter: NovelReadingDocumentAdapter = new NovelReadingDocumentAdapter();
  private comicScroller: Scroller = new Scroller();
  private bookCatalogScroller: Scroller = new Scroller();
  private statusBarStyleService: BrowserStatusBarStyleService = new BrowserStatusBarStyleService();
  private comicScrollResetTimer: number = -1;
  private autoReadingTimer: number = -1;
  private autoReadingStartTimer: number = -1;
  private verticalAppendPending: boolean = false;
  private observedLayoutMode: NovelReaderLayoutMode = 'compact';
  private bookCatalogFirstVisibleEntryIndex: number = 0;
  private bookCatalogRestoreTimer: number = -1;
  private statusBarStyleReassertTimer: number = -1;
  private observedContentRevision: number = -1;
  private observedLoading: boolean = false;
  private observedErrorMessage: string = '';
  private observedExecutorSignature: string = '';
  private observedAutoReadingEnabled: boolean = false;
  private observedBookIdentity: string = '';
  private observedBookPaletteSignature: string = '';
  private observedActiveChapterId: string = '';
  private currentReadingPosition?: NovelReadingPosition;

  aboutToAppear(): void {
    this.observedLayoutMode = this.layoutState.mode;
    this.refreshReadingSurfaceDocument();
    this.captureObservedSessionState();
    this.reconcileRuntimeExecutors();
    this.requestBookPalette();
    this.currentReadingPosition = {
      chapterId: this.state.position.chapterId,
      characterOffset: this.state.position.characterOffset
    };
  }

  aboutToDisappear(): void {
    this.reportCurrentProgress();
    this.stopAutoReading();
    this.stopComicScrollReset();
    this.stopBookCatalogRestore();
    this.stopStatusBarStyleReassertion();
    this.statusBarStyleService.restoreDefaultStyle(this.getAbilityContext());
  }

  build() {
    if (this.state.phase === 'book') {
      this.buildBookDetailScreen()
    } else {
      this.buildReaderScreen()
    }
  }

  @Builder
  buildReaderScreen() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 阅读区
      Column() {
        Stack() {
          if (this.resolveContentKind() === 'comic') {
            this.buildComicScroll()
          }
          if (this.resolveContentKind() !== 'comic') {
            ReadingSurface({
              document: this.readingSurfaceDocument,
              initialAnchor: this.resolveReadingSurfaceAnchor(),
              mode: this.state.preferences.pageMode,
              appearance: this.resolveReadingSurfaceAppearance(),
              activeTheme: this.effectiveTheme(),
              options: this.resolveReadingSurfaceOptions(),
              pagedColumnCount: this.resolveReadingSurfacePagedColumnCount(),
              pagedColumnGap: this.layoutState.readerPagedColumnGap,
              pagedContentWidth: this.layoutState.readerPagedContentWidth,
              contentWidth: this.layoutState.readerContentWidth,
              command: this.readingSurfaceCommand,
              onAction: (action: ReadingSurfaceAction): void => {
                this.handleReadingSurfaceAction(action);
              }
            })
          }

          if (this.resolveContentKind() !== 'comic' &&
            this.readingSurfaceDocument.blocks.length === 0) {
            Text(this.resolveChapterTransitionMessage().length > 0
              ? this.resolveChapterTransitionMessage() : '正在整理正文…')
              .fontSize(15)
              .fontColor(this.resolveTextColor(this.effectiveTheme()))
              .textAlign(TextAlign.Center)
              .padding({ left: NOVEL_READER_H_PADDING, right: NOVEL_READER_H_PADDING })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width(this.resolveReadingSurfaceWidth())
      .height('100%')
      .align(Alignment.Center)

      // 加载圈
      if (this.state.phase === 'detecting' || this.state.chapterTransition.status === 'loading') {
        Column() {
          LoadingProgress()
            .width(44)
            .height(44)
            .color(this.resolveTextColor(this.effectiveTheme()))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .hitTestBehavior(HitTestMode.None)
      }

      // Article and Novel text reading mount the same complete Chrome owner.
      if (this.chromeVisible) {
        ReadingExperienceChrome({
          title: this.state.bookTitle.length > 0 ? this.state.bookTitle : this.resolveReadingModeLabel(),
          closeAccessibilityLabel: `退出${this.resolveReadingModeAccessibilityLabel()}`,
          visible: this.chromeVisible,
          appearance: this.resolveReadingSurfaceAppearance(),
          textActionVisible: this.resolveContentKind() !== 'comic',
          topSafeInset: this.topSafeInsetVp,
          bottomSafeInset: NOVEL_READER_BOTTOM_GESTURE_GAP,
          controlContentWidth: this.resolveReadingChromeControlWidth(),
          contextRowVisible: true,
          primaryActionIcon: 'novelReader.catalog',
          primaryActionLabel: '目录',
          trailingActionVisible: true,
          trailingActionIcon: 'browser.shortcut.home',
          trailingActionLabel: '主页',
          onClose: (): void => {
            this.closeReader();
          },
          topActions: (): void => {
            this.buildReaderOverflowButton()
          },
          onPrimaryAction: (): void => {
            this.openCatalog();
          },
          onTrailingAction: (): void => {
            this.reportCurrentProgress();
            this.onAction({ type: 'suspend_to_home' });
          },
          onPanelRequest: (panel: NovelReaderControlPanel): void => {
            this.reportCurrentProgress();
            this.onAction({ type: 'open_control_panel', panel: panel });
          },
          contextRow: (): void => {
            this.buildChapterNavRow()
          }
        })
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
        .align(Alignment.Center)
      }

      if (this.resolveContentKind() !== 'comic' &&
        this.state.preferences.autoReadingEnabled && this.autoReadingPaused) {
        this.buildAutoReadingSpeedControl()
      }

      if (this.state.chapterTransition.status === 'failed') {
        this.buildChapterTransitionFailure()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBackgroundColor(this.effectiveTheme()))
  }

  @Builder
  private buildReaderOverflowButton() {
    Button() {
      AiraIcon({
        airaIconId: 'browser.toolbar.more',
        iconSize: 18,
        iconColor: this.resolveTextColor(this.effectiveTheme())
      })
    }
    .width(32)
    .height(32)
    .padding(0)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(16)
    .stateEffect(true)
    .accessibilityText(`更多${this.resolveReadingModeLabel()}操作`)
    .bindMenu(this.buildBookOverflowMenu())
  }

  @Builder
  buildChapterTransitionFailure() {
    Column({ space: 8 }) {
      Text(this.resolveChapterTransitionMessage())
        .fontSize(14)
        .fontColor(this.resolveTextColor(this.effectiveTheme()))
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Row({ space: 8 }) {
        if (this.canRetryChapterTransition()) {
          Button('重试')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(this.resolveTextColor(this.effectiveTheme()))
            .onClick(() => {
              this.onAction({ type: 'retry_chapter' });
            })
        }
        Button(this.resolveChapterReturnActionTitle())
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor(this.resolveTextColor(this.effectiveTheme()))
          .onClick(() => {
            this.reportCurrentProgress();
            this.onAction({ type: 'return_to_source' });
          })
      }
    }
    .width('90%')
    .constraintSize({ maxWidth: this.layoutState.readerChromeWidth })
    .padding(12)
    .margin({ bottom: 132 })
    .borderRadius(8)
    .backgroundColor(this.resolveControlBackgroundColor(this.effectiveTheme()))
  }

  @Builder
  buildAutoReadingSpeedControl() {
    Column() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: 112,
        surfaceRadius: 8,
        tintColor: resolveBrowserBottomChromeMaterialTintForMode(this.resolveAutoReadingMaterialMode())
      }) {
        Column() {
          Row({ space: 10 }) {
            AiraIcon({
              airaIconId: 'novelReader.autoSlow',
              iconSize: 22,
              iconColor: this.resolveSecondaryTextColor(this.effectiveTheme())
            })
            Slider({
              value: this.state.preferences.autoReadingSpeed,
              min: NOVEL_READER_AUTO_SPEED_MIN,
              max: NOVEL_READER_AUTO_SPEED_MAX,
              step: 1
            })
              .layoutWeight(1)
              .selectedColor(this.storedAccentColor)
              .onChange((value: number) => {
                const preferences: NovelReaderPreferences = this.copyPreferences();
                preferences.autoReadingSpeed = Math.round(value);
                this.updatePreferences(preferences);
              })
            AiraIcon({
              airaIconId: 'novelReader.autoFast',
              iconSize: 22,
              iconColor: this.storedPrimaryTextColor
            })
          }
          .width('100%')
          .height(64)
          .padding({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)

          Divider()
            .width('88%')
            .color(this.resolveSecondaryTextColor(this.effectiveTheme()))
            .opacity(0.18)

          Button('退出自动阅读')
            .width('100%')
            .height(47)
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontSize(14)
            .fontColor(this.storedAccentColor)
            .onClick(() => {
              this.exitAutoReading();
            })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('92%')
    .constraintSize({ maxWidth: this.layoutState.readerChromeWidth })
    .height(112)
    .margin({
      bottom: this.chromeVisible ? 126 + NOVEL_READER_BOTTOM_GESTURE_GAP : NOVEL_READER_BOTTOM_GESTURE_GAP
    })
    .borderRadius(8)
    .shadow({
      radius: 6,
      color: resolveBrowserBottomFloatingMaterialShadowColor(this.resolveAutoReadingMaterialMode()),
      offsetX: 0,
      offsetY: 0
    })
    .onClick(() => {
      // Consume taps so adjusting the Slider does not resume reading.
    })
  }

  @Builder
  buildComicScroll() {
    List({ scroller: this.comicScroller }) {
      ForEach(this.resolveActiveChapterImages(), (url: string, index: number) => {
        ListItem() {
          NovelComicImage({
            imageUrl: url,
            pageUrl: this.state.pageUrl,
            minHeight: NOVEL_COMIC_IMAGE_MIN_HEIGHT,
            surfaceColor: this.resolveBackgroundColor(this.effectiveTheme()),
            primaryTextColor: this.resolveSecondaryTextColor(this.effectiveTheme())
          })
        }
        .parallelGesture(
          TapGesture({ count: 1, fingers: 1, distanceThreshold: 1 })
            .onAction((): void => {
              this.toggleChrome();
            }),
          GestureMask.Normal
        )
      }, (url: string, index: number): string => `${this.resolveActiveChapterRenderKey()}:${index}:${url}`)
      ListItem() {
        Column() {
          Text(this.state.canNavigateNext ? '继续下一话' : '已经是最后一话')
            .fontSize(15)
            .fontColor('#FFFFFFFF')
        }
        .width('100%')
        .padding({ top: 26, bottom: 40 })
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          if (this.state.canNavigateNext) {
            this.requestNextChapter();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBackgroundColor(this.effectiveTheme()))
    .scrollBar(BarState.Off)
  }

  @Builder
  buildChapterNavRow() {
    Row() {
      Text('上一章')
        .fontSize(15)
        .fontColor(this.state.canNavigatePrevious
          ? this.resolveTextColor(this.effectiveTheme())
          : this.resolveSecondaryTextColor(this.effectiveTheme()))
        .enabled(this.state.canNavigatePrevious)
        .onClick(() => {
          if (this.state.canNavigatePrevious) {
            this.requestPreviousChapter();
          }
        })
      Text(this.resolveActiveChapterTitle().length > 0 ? this.resolveActiveChapterTitle() : '　')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveTextColor(this.effectiveTheme()))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .margin({ left: 12, right: 12 })
      Text('下一章')
        .fontSize(15)
        .fontColor(this.state.canNavigateNext
          ? this.resolveTextColor(this.effectiveTheme())
          : this.resolveSecondaryTextColor(this.effectiveTheme()))
        .enabled(this.state.canNavigateNext)
        .onClick(() => {
          if (this.state.canNavigateNext) {
            this.requestNextChapter();
          }
        })
    }
    .width('100%')
    .height(46)
    .padding({ left: NOVEL_READER_H_PADDING, right: NOVEL_READER_H_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  // ===== 书籍接管页(图四) =====

  @Builder
  buildBookDetailScreen() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.buildBookTopBar()
        if (this.layoutState.mode === 'expanded') {
          this.buildExpandedBookDetail()
        } else {
          this.buildBookCatalogList(true, NOVEL_BOOK_ACTION_SURFACE_HEIGHT + 16)
        }
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)

      if (this.layoutState.mode !== 'expanded') {
        this.buildBookActionBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBookBackgroundColor())
  }

  @Builder
  buildBookTopBar() {
    Row() {
      Button() {
        AiraIcon({
          airaIconId: 'browser.toolbar.back',
          iconSize: 16,
          iconColor: this.resolveBookPrimaryTextColor()
        })
      }
        .width(32)
        .height(32)
        .padding(0)
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(16)
        .accessibilityText(`退出${this.resolveReadingModeAccessibilityLabel()}`)
        .onClick(() => {
          this.closeReader();
        })
      Blank()
      Button() {
        AiraIcon({
          airaIconId: 'browser.toolbar.more',
          iconSize: 18,
          iconColor: this.resolveBookSecondaryTextColor()
        })
      }
        .width(32)
        .height(32)
        .padding(0)
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(16)
        .stateEffect(true)
        .accessibilityText('更多原网页操作')
        .bindMenu(this.buildBookOverflowMenu())
    }
    .width(this.layoutState.bookSurfaceWidth)
    .padding({
      left: NOVEL_READER_H_PADDING,
      right: NOVEL_READER_H_PADDING,
      top: this.topSafeInsetVp,
      bottom: 10
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildExpandedBookDetail() {
    Row({ space: this.layoutState.bookPaneGap }) {
      Column() {
        Scroll() {
          this.buildBookHeader(false)
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)

        this.buildExpandedBookActionBar()
      }
      .width(this.layoutState.bookInfoPaneWidth)
      .height('100%')

      Column() {
        this.buildBookCatalogHeading()
        this.buildBookCatalogList(false, 0)
      }
      .width(this.layoutState.bookCatalogPaneWidth)
      .height('100%')
    }
    .layoutWeight(1)
    .width(this.layoutState.bookSurfaceWidth)
    .padding({ top: 8, bottom: 24 })
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  buildBookCatalogList(includeBookHeader: boolean, contentEndOffset: number) {
    List({ scroller: this.bookCatalogScroller }) {
      if (includeBookHeader) {
        ListItem() {
          this.buildBookHeader(true)
        }
      }
      if (this.state.chapterTransition.status === 'failed') {
        ListItem() {
          this.buildBookChapterTransitionFailure()
        }
      }
      if (this.state.catalogTransition.status === 'failed' && this.state.catalog.length === 0) {
        ListItem() {
          Column({ space: 8 }) {
            Text('章节目录加载失败')
              .fontSize(15)
              .fontColor(this.resolveBookPrimaryTextColor())
            Text('可以稍后重试，当前书籍信息仍然保留。')
              .fontSize(13)
              .fontColor(this.resolveBookSecondaryTextColor())
          }
          .width('100%')
          .height(120)
          .justifyContent(FlexAlign.Center)
          .onClick(() => {
            this.onAction({ type: 'retry_catalog' });
          })
        }
      } else {
        ForEach(this.resolveBookCatalogRangeStarts(), (startOrdinal: number) => {
          ListItemGroup({ header: this.buildBookCatalogRangeHeader(startOrdinal) }) {
            if (this.isBookCatalogRangeExpanded(startOrdinal)) {
              ForEach(this.entriesForBookCatalogRange(startOrdinal), (entry: NovelReaderCatalogEntry) => {
                ListItem() {
                  Text(entry.title)
                    .fontSize(15)
                    .fontColor(this.resolveBookPrimaryTextColor())
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .width('100%')
                    .padding({
                      top: 15,
                      bottom: 15,
                      left: NOVEL_READER_H_PADDING + 12,
                      right: NOVEL_READER_H_PADDING
                    })
                }
                .onClick(() => {
                  this.onAction({ type: 'select_chapter', chapterId: entry.id });
                })
              }, (entry: NovelReaderCatalogEntry): string => entry.id)
              if (this.isBookCatalogRangeLoading(startOrdinal)) {
                ListItem() {
                  Row() {
                    LoadingProgress()
                      .width(24)
                      .height(24)
                      .color(this.resolveBookPrimaryTextColor())
                  }
                  .width('100%')
                  .height(52)
                  .justifyContent(FlexAlign.Center)
                }
              }
            }
          }
          .width('100%')
        }, (startOrdinal: number): string => `book-catalog-range-${startOrdinal}`)
      }
    }
    .layoutWeight(1)
    .width(this.layoutState.mode === 'expanded' ? this.layoutState.bookCatalogPaneWidth :
      this.layoutState.bookSurfaceWidth)
    .contentEndOffset(contentEndOffset)
    .divider({
      strokeWidth: 0.5,
      color: this.resolveBookDividerColor()
    })
    .onScrollIndex((start: number, _end: number) => {
      this.recordBookCatalogScrollIndex(start, includeBookHeader);
    })
  }

  @Builder
  private buildBookCatalogRangeHeader(startOrdinal: number) {
    Row({ space: 10 }) {
      Text(`${startOrdinal + 1}-${this.resolveBookCatalogRangeEnd(startOrdinal) + 1}`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveBookPrimaryTextColor())
        .layoutWeight(1)
      if (this.isBookCatalogRangeLoading(startOrdinal)) {
        LoadingProgress()
          .width(20)
          .height(20)
          .color(this.resolveBookPrimaryTextColor())
      } else {
        AiraIcon({
          airaIconId: 'browser.toolbar.expandHint',
          iconSize: 14,
          iconColor: this.resolveBookSecondaryTextColor()
        })
          .rotate({ angle: this.isBookCatalogRangeExpanded(startOrdinal) ? 180 : 0 })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: NOVEL_READER_H_PADDING, right: NOVEL_READER_H_PADDING })
    .alignItems(VerticalAlign.Center)
    .accessibilityText(this.isBookCatalogRangeExpanded(startOrdinal) ? '折叠章节范围' : '展开章节范围')
    .onClick((): void => {
      this.toggleBookCatalogRange(startOrdinal);
    })
  }

  private toggleBookCatalogRange(startOrdinal: number): void {
    if (this.isBookCatalogRangeExpanded(startOrdinal)) {
      this.expandedBookCatalogRangeStarts = this.expandedBookCatalogRangeStarts.filter(
        (value: number): boolean => value !== startOrdinal
      );
      return;
    }
    this.expandedBookCatalogRangeStarts = this.expandedBookCatalogRangeStarts.concat([startOrdinal]);
    this.onAction({
      type: 'load_catalog_range',
      startOrdinal: startOrdinal,
      endOrdinal: this.resolveBookCatalogRangeEnd(startOrdinal)
    });
  }

  private resolveBookCatalogRangeStarts(): number[] {
    const starts: number[] = [];
    const highestOrdinal: number = this.resolveHighestBookCatalogOrdinal();
    let groupCount: number = Math.max(1, Math.ceil(Math.max(
      this.state.catalogTotalHint,
      this.state.catalogRangeExtentHint,
      highestOrdinal + 1
    ) / NOVEL_CATALOG_RANGE_SIZE));
    if (!this.state.catalogSupportsRandomAccess && this.state.catalogHasMore) {
      const nextSequentialGroup: number = Math.floor((highestOrdinal + 1) / NOVEL_CATALOG_RANGE_SIZE);
      groupCount = Math.max(groupCount, nextSequentialGroup + 1);
    }
    for (let index: number = 0; index < groupCount; index += 1) {
      starts.push(index * NOVEL_CATALOG_RANGE_SIZE);
    }
    return starts;
  }

  private entriesForBookCatalogRange(startOrdinal: number): NovelReaderCatalogEntry[] {
    const endOrdinal: number = this.resolveBookCatalogRangeEnd(startOrdinal);
    return this.state.catalog.filter((entry: NovelReaderCatalogEntry): boolean =>
      entry.ordinal >= startOrdinal && entry.ordinal <= endOrdinal);
  }

  private resolveBookCatalogRangeEnd(startOrdinal: number): number {
    const defaultEnd: number = startOrdinal + NOVEL_CATALOG_RANGE_SIZE - 1;
    return this.state.catalogTotalHint > 0
      ? Math.min(defaultEnd, this.state.catalogTotalHint - 1)
      : defaultEnd;
  }

  private resolveHighestBookCatalogOrdinal(): number {
    let highest: number = -1;
    for (let index: number = 0; index < this.state.catalog.length; index += 1) {
      highest = Math.max(highest, this.state.catalog[index].ordinal);
    }
    return highest;
  }

  private isBookCatalogRangeExpanded(startOrdinal: number): boolean {
    return this.expandedBookCatalogRangeStarts.indexOf(startOrdinal) >= 0;
  }

  private isBookCatalogRangeLoading(startOrdinal: number): boolean {
    return this.state.catalogLoadingMore && this.state.catalogLoadingRangeStart === startOrdinal &&
      this.state.catalogLoadingRangeEnd >= startOrdinal;
  }

  @Builder
  buildBookCatalogHeading() {
    Row() {
      this.buildBookCatalogHeadingLabels()
    }
    .width('100%')
    .height(52)
    .padding({ left: NOVEL_READER_H_PADDING, right: NOVEL_READER_H_PADDING })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  buildBookHeader(showCatalogHeading: boolean) {
    Column() {
      Stack() {
        NovelBookCover({
          coverUrl: this.state.bookCoverUrl,
          detailUrl: this.state.pageUrl,
          title: this.state.bookTitle,
          coverBackgroundColor: this.resolveBookSurfaceColor(),
          fallbackPrimaryTextColor: this.resolveBookPrimaryTextColor(),
          fallbackSecondaryTextColor: this.resolveBookSecondaryTextColor(),
          fallbackDividerColor: this.resolveBookDividerColor(),
          cornerRadius: 8
        })
      }
      .width(120)
      .height(160)
      Text(this.state.bookTitle.length > 0 ? this.state.bookTitle : '本书')
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolveBookPrimaryTextColor())
        .textAlign(TextAlign.Center)
        .margin({ top: 14 })
      if (this.state.sourceHost.length > 0) {
        Text(`来源：${this.state.sourceHost}`)
          .fontSize(13)
          .fontColor(this.resolveBookSecondaryTextColor())
          .margin({ top: 8 })
      }

      // 作者 / 类别 / 最新
      Row() {
        this.buildInfoCol('作者', this.state.bookAuthor.length > 0 ? this.state.bookAuthor : '—')
        this.buildInfoCol('类别', this.state.bookCategory.length > 0 ? this.state.bookCategory : '—')
        this.buildInfoCol('最新', this.state.bookLatest.length > 0 ? this.state.bookLatest : '—')
      }
      .width('100%')
      .margin({ top: 18 })
      .padding({ top: 14, bottom: 14 })
      .backgroundColor(this.resolveBookSurfaceColor())
      .borderRadius(14)

      if (this.state.bookSynopsis.length > 0) {
        Text('简介')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolveBookPrimaryTextColor())
          .width('100%')
          .margin({ top: 22, bottom: 8 })
        Text(this.state.bookSynopsis)
          .fontSize(14)
          .lineHeight(22)
          .fontColor(this.resolveBookSecondaryTextColor())
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }

      if (showCatalogHeading) {
        Row() {
          this.buildBookCatalogHeadingLabels()
        }
        .width('100%')
        .margin({ top: 22, bottom: 4 })
      }
    }
    .width('100%')
    .padding({ left: NOVEL_READER_H_PADDING, right: NOVEL_READER_H_PADDING, top: 6, bottom: 8 })
  }

  @Builder
  buildBookCatalogHeadingLabels() {
    Text('目录')
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.resolveBookPrimaryTextColor())
      .layoutWeight(1)
    Text(this.resolveBookCatalogCount())
      .fontSize(13)
      .fontColor(this.resolveBookSecondaryTextColor())
  }

  @Builder
  buildBookActionBar() {
    Column() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: NOVEL_BOOK_ACTION_SURFACE_HEIGHT,
        surfaceRadius: 0,
        tintColor: this.resolveBookGlassTintColor()
      }) {
        this.buildBookActionContent(this.layoutState.bookSurfaceWidth)
      }
    }
    .width('100%')
    .height(NOVEL_BOOK_ACTION_SURFACE_HEIGHT)
    .shadow({
      radius: 6,
      color: resolveBrowserBottomFloatingMaterialShadowColor(this.storedResolvedThemeMode),
      offsetX: 0,
      offsetY: 0
    })
    .align(Alignment.Bottom)
  }

  @Builder
  buildExpandedBookActionBar() {
    Column() {
      this.buildBookActionContent(this.layoutState.bookInfoPaneWidth)
    }
    .width(this.layoutState.bookInfoPaneWidth)
    .height(NOVEL_BOOK_ACTION_SURFACE_HEIGHT)
  }

  @Builder
  buildBookActionContent(contentWidth: number) {
    Column() {
      if (this.state.resumeHint.length > 0) {
        Text(this.state.resumeHint)
          .fontSize(12)
          .fontColor(this.resolveBookSecondaryTextColor())
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .height(18)
          .margin({ bottom: 6 })
      }
      Row({ space: NOVEL_BOOK_ACTION_GAP }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            if (this.state.bookshelfActionBusy) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.novel_book_action_foreground'))
            }
            Text(this.resolveBookshelfActionTitle())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.novel_book_action_foreground'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .height(NOVEL_BOOK_ACTION_BUTTON_HEIGHT)
        .padding(0)
        .backgroundColor($r('app.color.novel_book_action_background'))
        .border({ width: 1, color: this.storedOutlineColor })
        .borderRadius(NOVEL_BOOK_ACTION_BUTTON_HEIGHT / 2)
        .stateEffect(this.canToggleBookshelf())
        .enabled(this.canToggleBookshelf())
        .accessibilityText(this.resolveBookshelfActionTitle())
        .onClick(() => {
          if (this.canToggleBookshelf()) {
            this.onAction({ type: 'toggle_bookshelf' });
          }
        })

        Button({ type: ButtonType.Normal }) {
          Row({ space: 8 }) {
            if (this.isBookStartActionLoading()) {
              LoadingProgress()
                .width(18)
                .height(18)
                .color($r('app.color.novel_book_action_foreground'))
            }
            Text(this.resolveBookStartActionTitle())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.novel_book_action_foreground'))
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1)
        .height(NOVEL_BOOK_ACTION_BUTTON_HEIGHT)
        .padding(0)
        .backgroundColor($r('app.color.novel_book_action_background'))
        .border({ width: 1, color: this.storedOutlineColor })
        .borderRadius(NOVEL_BOOK_ACTION_BUTTON_HEIGHT / 2)
        .stateEffect(this.canStartBookReading())
        .enabled(this.canStartBookReading())
        .accessibilityText(this.resolveBookStartActionTitle())
        .onClick(() => {
          if (this.canStartBookReading()) {
            this.onAction({ type: 'start_reading' });
          }
        })
      }
    }
    .width('100%')
    .constraintSize({ maxWidth: contentWidth })
    .height('100%')
    .padding({ left: 12, right: 12, bottom: NOVEL_BOOK_ACTION_BOTTOM_CONTENT_INSET })
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  private buildBookOverflowMenu() {
    Menu() {
      if (this.state.bookshelfAvailable) {
        MenuItem({ content: this.resolveBookshelfActionTitle() })
          .onClick(() => {
            if (this.canToggleBookshelf()) {
              this.onAction({ type: 'toggle_bookshelf' });
            }
          })
      }
      MenuItem({ content: '复制链接' })
        .onClick(() => {
          this.onAction({ type: 'copy_source_link' });
        })
      MenuItem({ content: '分享' })
        .onClick(() => {
          this.onAction({ type: 'share_source_link' });
        })
      MenuItem({ content: '访问原网页' })
        .onClick(() => {
          this.reportCurrentProgress();
          this.onAction({ type: 'return_to_source' });
        })
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .systemMaterial(createFloatingGlassMaterialIfAvailable(
      resolveBrowserBottomChromeMaterialTintForMode(this.storedResolvedThemeMode)
    ))
  }

  private onLayoutStateChanged(): void {
    const previousMode: NovelReaderLayoutMode = this.observedLayoutMode;
    this.observedLayoutMode = this.layoutState.mode;
    if (this.state.phase !== 'book' ||
      (previousMode === 'expanded') === (this.layoutState.mode === 'expanded')) {
      return;
    }
    this.scheduleBookCatalogRestore();
  }

  private recordBookCatalogScrollIndex(start: number, includeBookHeader: boolean): void {
    const leadingItemCount: number = this.resolveBookCatalogLeadingItemCount(includeBookHeader);
    this.bookCatalogFirstVisibleEntryIndex = Math.max(0, start - leadingItemCount);
  }

  private scheduleBookCatalogRestore(): void {
    this.stopBookCatalogRestore();
    if (this.state.catalog.length === 0) {
      return;
    }
    const includeBookHeader: boolean = this.layoutState.mode !== 'expanded';
    const leadingItemCount: number = this.resolveBookCatalogLeadingItemCount(includeBookHeader);
    const entryIndex: number = Math.min(
      this.bookCatalogFirstVisibleEntryIndex,
      this.state.catalog.length - 1
    );
    this.bookCatalogRestoreTimer = setTimeout(() => {
      this.bookCatalogRestoreTimer = -1;
      this.bookCatalogScroller.scrollToIndex(
        leadingItemCount + entryIndex,
        false,
        ScrollAlign.START
      );
    }, 0);
  }

  private resolveBookCatalogLeadingItemCount(includeBookHeader: boolean): number {
    let count: number = includeBookHeader ? 1 : 0;
    if (this.state.chapterTransition.status === 'failed') {
      count = count + 1;
    }
    return count;
  }

  private stopBookCatalogRestore(): void {
    if (this.bookCatalogRestoreTimer >= 0) {
      clearTimeout(this.bookCatalogRestoreTimer);
      this.bookCatalogRestoreTimer = -1;
    }
  }

  @Builder
  buildInfoCol(label: string, value: string) {
    Column() {
      Text(label)
        .fontSize(12)
        .fontColor(this.resolveBookSecondaryTextColor())
      Text(value)
        .fontSize(14)
        .fontColor(this.resolveBookPrimaryTextColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .padding({ left: 6, right: 6 })
  }

  private resolveBookCatalogCount(): string {
    if (this.state.catalogTotalHint > this.state.catalog.length) {
      return `${this.state.catalog.length} / ${this.state.catalogTotalHint} 章`;
    }
    if (this.state.catalogHasMore && this.state.catalogTotalHint === 0) {
      return `已载入 ${this.state.catalog.length} 章`;
    }
    return `共 ${this.state.catalog.length} 章`;
  }

  private isBookStartActionLoading(): boolean {
    return this.state.chapterTransition.status === 'loading';
  }

  private resolveBookStartActionTitle(): string {
    if (this.state.chapterTransition.status === 'loading') {
      return '正在打开';
    }
    return '开始阅读';
  }

  private resolveChapterTransitionMessage(): string {
    const code: string = this.state.chapterTransition.failureCode;
    if (code === 'retryable') {
      return '这一章加载失败，请重试。';
    }
    if (code === 'content_rejected') {
      return this.state.contentKind === 'comic' ?
        '这一章漫画图片加载失败，请重试。' : '这一章正文不完整，请重试。';
    }
    if (code === 'identity_mismatch') {
      return '章节身份校验失败，请返回原网页后重试。';
    }
    if (code === 'unsupported_source') {
      return '当前来源暂不支持继续读取。';
    }
    if (code === 'authentication_required') {
      return '请先在来源网站登录，登录后再开始阅读。';
    }
    return '';
  }

  private canRetryChapterTransition(): boolean {
    const code: string = this.state.chapterTransition.failureCode;
    return code === 'retryable' || code === 'content_rejected';
  }

  private resolveChapterReturnActionTitle(): string {
    return this.state.chapterTransition.failureCode === 'authentication_required' ?
      '返回来源网站登录' : '返回原网页';
  }

  private canToggleBookshelf(): boolean {
    return this.state.bookshelfAvailable && !this.state.bookshelfActionBusy &&
      this.state.bookshelfDetailUrl.trim().length > 0 && this.state.bookTitle.trim().length > 0;
  }

  private resolveBookshelfActionTitle(): string {
    if (!this.state.bookshelfAvailable) {
      return '无痕模式不可用';
    }
    if (this.state.bookshelfActionBusy) {
      return this.state.bookInBookshelf ? '正在移出' : '正在加入';
    }
    return this.state.bookInBookshelf ? '移出书架' : '加入书架';
  }

  private canStartBookReading(): boolean {
    return !this.isBookStartActionLoading() && this.state.catalog.length > 0;
  }

  @Builder
  private buildBookChapterTransitionFailure() {
    Column({ space: 8 }) {
      Text(this.resolveChapterTransitionMessage())
        .fontSize(14)
        .fontColor(this.resolveBookPrimaryTextColor())
        .textAlign(TextAlign.Center)
        .maxLines(2)
      Row({ space: 8 }) {
        if (this.canRetryChapterTransition()) {
          Button('重试')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(this.resolveBookPrimaryTextColor())
            .onClick(() => {
              this.onAction({ type: 'retry_chapter' });
            })
        }
        if (this.state.chapterTransition.failureCode === 'authentication_required') {
          Button(this.resolveChapterReturnActionTitle())
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(this.resolveBookPrimaryTextColor())
            .onClick(() => {
              this.onAction({ type: 'return_to_source' });
            })
        }
      }
    }
    .width('100%')
    .padding({ left: NOVEL_READER_H_PADDING, right: NOVEL_READER_H_PADDING, top: 12, bottom: 12 })
    .backgroundColor(this.resolveBookSurfaceColor())
  }

  private refreshReadingSurfaceDocument(): void {
    const signature: string = this.resolveReadingSurfaceDocumentSignature();
    if (signature === this.readingSurfaceDocumentSignature) {
      return;
    }
    if (this.state.preferences.pageMode === 'vertical') {
      this.readingSurfaceDocument = this.readingDocumentAdapter.adaptTrail(
        this.state.chapterTrail,
        this.state.bookTitle
      );
    } else {
      const chapter: NovelSessionCommittedChapter | undefined = this.resolveActiveChapter();
      this.readingSurfaceDocument = chapter === undefined ? {
        id: '',
        title: '',
        subtitle: '',
        blocks: []
      } : this.readingDocumentAdapter.adapt(chapter);
    }
    this.readingSurfaceDocumentSignature = signature;
  }

  private resolveReadingSurfaceDocumentSignature(): string {
    if (this.state.preferences.pageMode !== 'vertical') {
      return `chapter|${this.resolveActiveChapterRenderKey()}`;
    }
    let signature: string = `trail|${this.state.bookTitle.length}:${this.state.bookTitle}|` +
      `${this.state.chapterTrail.length}`;
    for (let index: number = 0; index < this.state.chapterTrail.length; index++) {
      signature = `${signature}|${buildNovelChapterRenderKey(this.state.chapterTrail[index])}`;
    }
    return signature;
  }

  private resolveReadingSurfaceAnchor(): ReadingAnchor {
    const document: ReadingDocument = this.readingSurfaceDocument;
    const position: NovelReadingPosition = this.currentReadingPosition ?? this.state.position;
    if (this.state.preferences.pageMode === 'vertical') {
      const trailAnchor: ReadingAnchor = this.readingDocumentAdapter.trailPositionToAnchor(
        this.state.chapterTrail,
        position
      );
      return trailAnchor;
    }
    return this.readingDocumentAdapter.characterOffsetToAnchor(document, position.characterOffset);
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
    const vertical: boolean = this.state.preferences.pageMode === 'vertical';
    return {
      documentHeaderVisible: false,
      pageHeaderVisible: !vertical && this.state.preferences.chapterNameVisible,
      pageNumberVisible: !vertical && this.state.preferences.pageNumberVisible,
      paragraphIndentVisible: true,
      continuationAvailable: !vertical && this.state.canNavigateNext,
      continuationLabel: '继续下一章',
      contentTopInset: this.layoutState.readerContentTopInset,
      contentBottomInset: this.layoutState.readerContentBottomInset
    };
  }

  private resolveReadingSurfacePagedColumnCount(): number {
    return this.resolveContentKind() === 'comic' || this.state.preferences.pageMode === 'vertical'
      ? 1
      : this.layoutState.readerPagedColumnCount;
  }

  private resolveReadingSurfaceWidth(): Length {
    return this.state.preferences.pageMode === 'vertical' && this.resolveContentKind() !== 'comic'
      ? '100%'
      : this.resolveReadingSurfacePagedColumnCount() > 1
      ? '100%'
      : this.layoutState.readerContentWidth;
  }

  private resolveReadingChromeControlWidth(): number {
    return this.resolveReadingSurfacePagedColumnCount() > 1
      ? this.layoutState.readerChromeControlWidth
      : this.layoutState.readerChromeWidth;
  }

  private handleReadingSurfaceAction(action: ReadingSurfaceAction): void {
    if (action.type === 'anchor_change') {
      const position: NovelReadingPosition | undefined = this.state.preferences.pageMode === 'vertical'
        ? this.readingDocumentAdapter.anchorToTrailPosition(this.state.chapterTrail, action.anchor)
        : this.resolveAnchorPositionForActiveChapter(action.anchor);
      if (position === undefined) {
        return;
      }
      this.currentReadingPosition = position;
      this.onAction({
        type: 'progress_change',
        chapterId: position.chapterId,
        characterOffset: position.characterOffset
      });
      return;
    }
    if (action.type === 'toggle_chrome') {
      if (this.state.preferences.autoReadingEnabled) {
        this.toggleAutoReadingPause();
        return;
      }
      this.toggleChrome();
      return;
    }
    if (action.type === 'reach_end') {
      if (this.state.preferences.pageMode === 'vertical') {
        this.handleVerticalReachEnd();
      } else {
        this.requestNextChapter();
      }
      return;
    }
    if (action.type === 'reach_start' && this.state.preferences.pageMode !== 'vertical') {
      this.requestPreviousChapter();
    }
  }

  private resolveAnchorPositionForActiveChapter(anchor: ReadingAnchor): NovelReadingPosition | undefined {
    const chapter: NovelSessionCommittedChapter | undefined = this.resolveActiveChapter();
    if (chapter === undefined) {
      return undefined;
    }
    return {
      chapterId: chapter.id,
      characterOffset: this.readingDocumentAdapter.anchorToCharacterOffset(
        this.readingDocumentAdapter.adapt(chapter),
        anchor
      )
    };
  }

  private toggleChrome(): void {
    this.chromeVisible = !this.chromeVisible;
  }

  private onSessionStateChanged(): void {
    this.refreshReadingSurfaceDocument();
    const contentChanged: boolean = this.observedContentRevision !== this.resolveActiveChapterRevision();
    const comicChapterChanged: boolean = this.resolveContentKind() === 'comic' &&
      this.state.activeChapterId.length > 0 && this.observedActiveChapterId !== this.state.activeChapterId;
    const loadingChanged: boolean = this.observedLoading !== (this.state.chapterTransition.status === 'loading');
    const errorChanged: boolean = this.observedErrorMessage !== this.state.chapterTransition.failureCode;
    const executorChanged: boolean = this.observedExecutorSignature !== this.resolveExecutorSignature();
    const autoReadingStarted: boolean = !this.observedAutoReadingEnabled &&
      this.state.preferences.autoReadingEnabled;
    const bookChanged: boolean = this.state.bookIdentity.length > 0 &&
      this.observedBookIdentity !== this.state.bookIdentity;
    const bookPaletteChanged: boolean = this.observedBookPaletteSignature !== this.resolveBookPaletteSignature();
    if (contentChanged && this.state.preferences.pageMode !== 'vertical') {
      this.currentReadingPosition = {
        chapterId: this.state.position.chapterId,
        characterOffset: this.state.position.characterOffset
      };
    }
    this.captureObservedSessionState();
    if (comicChapterChanged) {
      this.scheduleComicScrollReset();
    }
    if (contentChanged || (this.verticalAppendPending &&
      ((loadingChanged && this.state.chapterTransition.status !== 'loading') ||
        (errorChanged && this.state.chapterTransition.failureCode.length > 0)))) {
      this.reconcileReadingSourceChange();
    }
    if (executorChanged) {
      this.reconcileRuntimeExecutors();
    }
    if (autoReadingStarted) {
      this.autoReadingPaused = false;
      this.chromeVisible = false;
    }
    if (bookChanged) {
      this.expandedBookCatalogRangeStarts = [0];
    }
    if (bookPaletteChanged) {
      this.requestBookPalette();
    }
  }

  private captureObservedSessionState(): void {
    this.observedContentRevision = this.resolveActiveChapterRevision();
    this.observedActiveChapterId = this.state.activeChapterId;
    this.observedLoading = this.state.chapterTransition.status === 'loading';
    this.observedErrorMessage = this.state.chapterTransition.failureCode;
    this.observedExecutorSignature = this.resolveExecutorSignature();
    this.observedAutoReadingEnabled = this.state.preferences.autoReadingEnabled;
    this.observedBookIdentity = this.state.bookIdentity;
    this.observedBookPaletteSignature = this.resolveBookPaletteSignature();
  }

  private scheduleComicScrollReset(): void {
    this.stopComicScrollReset();
    this.comicScrollResetTimer = setTimeout(() => {
      this.comicScrollResetTimer = -1;
      if (this.resolveContentKind() === 'comic') {
        this.comicScroller.scrollToIndex(0, false, ScrollAlign.START);
      }
    }, 0);
  }

  private stopComicScrollReset(): void {
    if (this.comicScrollResetTimer >= 0) {
      clearTimeout(this.comicScrollResetTimer);
      this.comicScrollResetTimer = -1;
    }
  }

  private onReaderThemeChanged(): void {
    if (this.state.preferences.systemStatusBarVisible) {
      this.syncStatusBarContentStyle();
    }
  }

  private onBookThemeModeChanged(): void {
    this.requestBookPalette();
  }

  private requestBookPalette(): void {
    const signature = this.resolveBookPaletteSignature();
    this.observedBookPaletteSignature = signature;
    if (this.state.phase !== 'book' || this.state.bookCoverUrl.trim().length === 0) {
      return;
    }
    this.onAction({ type: 'resolve_book_palette', themeMode: this.resolveBookPaletteThemeMode() });
  }

  private resolveBookPaletteSignature(): string {
    return `${this.state.phase}|${this.state.bookCoverUrl.trim()}|${this.state.pageUrl.trim()}|` +
      `${this.resolveBookPaletteThemeMode()}`;
  }

  private resolveBookPaletteThemeMode(): NovelBookPaletteThemeMode {
    return this.storedResolvedThemeMode === 'dark' ? 'dark' : 'light';
  }

  private resolveBookBackgroundColor(): ResourceColor {
    return this.resolveActiveBookPalette()?.backgroundColor ?? this.storedSurfaceBackgroundColor;
  }

  private resolveBookSurfaceColor(): ResourceColor {
    return this.resolveActiveBookPalette()?.surfaceColor ?? this.storedControlBackgroundColor;
  }

  private resolveBookPrimaryTextColor(): ResourceColor {
    return this.resolveActiveBookPalette()?.primaryTextColor ?? this.storedPrimaryTextColor;
  }

  private resolveBookSecondaryTextColor(): ResourceColor {
    return this.resolveActiveBookPalette()?.secondaryTextColor ?? this.storedSecondaryTextColor;
  }

  private resolveBookDividerColor(): ResourceColor {
    return this.resolveActiveBookPalette()?.dividerColor ?? this.storedDividerColor;
  }

  private resolveBookGlassTintColor(): ResourceColor {
    return this.resolveActiveBookPalette()?.glassTintColor ??
      resolveBrowserBottomChromeMaterialTintForMode(this.storedResolvedThemeMode);
  }

  private resolveActiveBookPalette(): NovelBookCoverPalette | undefined {
    const expectedKey: string = buildNovelBookPaletteCacheKey(
      this.state.bookCoverUrl,
      this.resolveBookPaletteThemeMode()
    );
    return this.state.bookPaletteKey === expectedKey ? this.state.bookPalette : undefined;
  }

  private reconcileReadingSourceChange(): void {
    if (this.state.chapterTransition.status === 'loading') {
      return;
    }
    this.verticalAppendPending = false;
    if (this.resolveContentKind() !== 'comic' &&
      this.state.preferences.autoReadingEnabled && !this.autoReadingPaused) {
      this.scheduleAutoReading();
    }
  }

  private handleVerticalReachEnd(): void {
    if (this.state.chapterTransition.status === 'loading' || this.verticalAppendPending ||
      !this.state.canNavigateNext) {
      return;
    }
    this.verticalAppendPending = true;
    this.requestVerticalContinuation();
  }

  private setAutoReadingEnabled(enabled: boolean): void {
    this.reportCurrentProgress();
    const preferences: NovelReaderPreferences = this.copyPreferences();
    preferences.autoReadingEnabled = enabled;
    if (!enabled) {
      this.autoReadingPaused = false;
      this.stopAutoReading();
      this.updatePreferences(preferences);
      return;
    }
    this.autoReadingPaused = false;
    preferences.pageMode = 'vertical';
    this.updatePreferences(preferences);
    this.chromeVisible = false;
    this.scheduleAutoReading();
  }

  private openCatalog(): void {
    this.reportCurrentProgress();
    if (this.state.preferences.autoReadingEnabled && !this.autoReadingPaused) {
      this.autoReadingPaused = true;
      this.stopAutoReadingTimerOnly();
    }
    this.onAction({ type: 'open_catalog' });
  }

  private scheduleAutoReading(): void {
    this.stopAutoReadingTimerOnly();
    if (this.resolveContentKind() === 'comic') {
      return;
    }
    this.autoReadingStartTimer = setTimeout(() => {
      this.autoReadingStartTimer = -1;
      if (!this.state.preferences.autoReadingEnabled || this.autoReadingPaused || this.state.preferences.pageMode !== 'vertical') {
        return;
      }
      this.autoReadingTimer = setInterval(() => {
        if (!this.state.preferences.autoReadingEnabled || this.autoReadingPaused || this.state.preferences.pageMode !== 'vertical') {
          return;
        }
        this.issueReadingSurfaceCommand('scroll_step', this.resolveAutoReadingStep());
      }, NOVEL_READER_AUTO_SCROLL_INTERVAL_MS);
    }, 120);
  }

  private stopAutoReadingTimerOnly(): void {
    if (this.autoReadingStartTimer >= 0) {
      clearTimeout(this.autoReadingStartTimer);
      this.autoReadingStartTimer = -1;
    }
    if (this.autoReadingTimer >= 0) {
      clearInterval(this.autoReadingTimer);
      this.autoReadingTimer = -1;
    }
  }

  private stopAutoReading(): void {
    this.stopAutoReadingTimerOnly();
  }

  private toggleAutoReadingPause(): void {
    if (!this.state.preferences.autoReadingEnabled) {
      return;
    }
    this.reportCurrentProgress();
    if (this.autoReadingPaused) {
      this.autoReadingPaused = false;
      this.chromeVisible = false;
      this.scheduleAutoReading();
      return;
    }
    this.autoReadingPaused = true;
    this.chromeVisible = false;
    this.stopAutoReadingTimerOnly();
  }

  private resolveAutoReadingStep(): number {
    if (this.state.preferences.autoReadingSpeed <= 1) {
      return 0.4;
    }
    if (this.state.preferences.autoReadingSpeed === 2) {
      return 0.7;
    }
    if (this.state.preferences.autoReadingSpeed === 4) {
      return 1.4;
    }
    if (this.state.preferences.autoReadingSpeed >= 5) {
      return 1.9;
    }
    return 1;
  }

  private resolveAutoReadingMaterialMode(): string {
    const theme: ReaderModeTheme = this.effectiveTheme();
    return theme === 'dark' || theme === 'charcoal' ? 'dark' : 'light';
  }

  private exitAutoReading(): void {
    this.setAutoReadingEnabled(false);
    this.chromeVisible = true;
  }

  private reconcileRuntimeExecutors(): void {
    if (this.resolveContentKind() !== 'comic' &&
      this.state.preferences.autoReadingEnabled &&
      this.state.preferences.pageMode === 'vertical' && !this.autoReadingPaused) {
      this.scheduleAutoReading();
    } else {
      this.stopAutoReadingTimerOnly();
    }

    if (this.state.preferences.systemStatusBarVisible) {
      this.syncStatusBarContentStyle();
    } else {
      this.stopStatusBarStyleReassertion();
    }
    this.onAction({
      type: 'status_bar_visibility_apply',
      visible: this.state.preferences.systemStatusBarVisible
    });
  }

  private issueReadingSurfaceCommand(
    type: 'page_previous' | 'page_next' | 'scroll_step',
    distance: number
  ): void {
    this.readingSurfaceCommand = {
      version: this.readingSurfaceCommand.version + 1,
      type: type,
      distance: distance
    };
  }

  private setSystemStatusBarVisible(visible: boolean): void {
    if (visible) {
      this.syncStatusBarContentStyle();
    } else {
      this.stopStatusBarStyleReassertion();
    }
    this.onAction({ type: 'status_bar_visibility_change', visible: visible });
  }

  private syncStatusBarContentStyle(): void {
    const theme: ReaderModeTheme = this.effectiveTheme();
    const lightContentActive: boolean = theme === 'dark' || theme === 'charcoal';
    this.stopStatusBarStyleReassertion();
    this.statusBarStyleService.applyLightContentStyle(
      this.getAbilityContext(),
      lightContentActive
    );
    this.statusBarStyleReassertTimer = setTimeout(() => {
      this.statusBarStyleReassertTimer = -1;
      if (!this.state.preferences.systemStatusBarVisible) {
        return;
      }
      this.statusBarStyleService.applyLightContentStyle(
        this.getAbilityContext(),
        lightContentActive,
        true
      );
    }, NOVEL_READER_STATUS_BAR_STYLE_REASSERT_MS);
  }

  private stopStatusBarStyleReassertion(): void {
    if (this.statusBarStyleReassertTimer >= 0) {
      clearTimeout(this.statusBarStyleReassertTimer);
      this.statusBarStyleReassertTimer = -1;
    }
  }

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private closeReader(): void {
    this.reportCurrentProgress();
    this.onAction({ type: 'close' });
  }

  private requestPreviousChapter(): void {
    this.reportCurrentProgress();
    this.onAction({ type: 'previous_chapter' });
  }

  private requestNextChapter(): void {
    this.reportCurrentProgress();
    this.onAction({ type: 'next_chapter' });
  }

  private requestVerticalContinuation(): void {
    this.reportCurrentProgress();
    this.onAction({ type: 'continue_vertical' });
  }

  private reportCurrentProgress(): void {
    if (this.state.phase !== 'reader' || this.resolveContentKind() === 'comic') {
      return;
    }
    const position: NovelReadingPosition | undefined = this.currentReadingPosition;
    if (position === undefined || position.chapterId.length === 0) {
      return;
    }
    this.onAction({
      type: 'progress_change',
      chapterId: position.chapterId,
      characterOffset: position.characterOffset
    });
  }

  private updatePreferences(preferences: NovelReaderPreferences): void {
    this.onAction({ type: 'update_preferences', preferences: preferences });
  }

  private copyPreferences(): NovelReaderPreferences {
    const preferences: NovelReaderPreferences = this.state.preferences;
    return {
      fontSize: preferences.fontSize,
      theme: preferences.theme,
      lineHeight: preferences.lineHeight,
      pageWidth: preferences.pageWidth,
      brightnessMode: preferences.brightnessMode,
      brightnessPercent: preferences.brightnessPercent,
      pageMode: preferences.pageMode,
      autoReadingEnabled: preferences.autoReadingEnabled,
      autoReadingSpeed: preferences.autoReadingSpeed,
      volumeKeyPagingEnabled: preferences.volumeKeyPagingEnabled,
      systemStatusBarVisible: preferences.systemStatusBarVisible,
      chapterNameVisible: preferences.chapterNameVisible,
      pageNumberVisible: preferences.pageNumberVisible
    };
  }

  private resolveActiveChapter(): NovelSessionCommittedChapter | undefined {
    for (let index: number = 0; index < this.state.chapterTrail.length; index++) {
      if (this.state.chapterTrail[index].id === this.state.activeChapterId) {
        return this.state.chapterTrail[index];
      }
    }
    return this.state.chapterTrail.length > 0 ? this.state.chapterTrail[this.state.chapterTrail.length - 1] : undefined;
  }

  private resolveActiveChapterTitle(): string {
    return this.resolveActiveChapter()?.title ?? '';
  }

  private resolveActiveChapterImages(): string[] {
    return this.resolveActiveChapter()?.images ?? [];
  }

  private resolveActiveChapterRevision(): number {
    return this.resolveActiveChapter()?.revision ?? 0;
  }

  private resolveActiveChapterRenderKey(): string {
    const chapter: NovelSessionCommittedChapter | undefined = this.resolveActiveChapter();
    return chapter === undefined ? 'no-active-chapter' : buildNovelChapterRenderKey(chapter);
  }

  private resolveContentKind(): NovelContentKind {
    return this.state.contentKind;
  }

  private resolveReadingModeLabel(): string {
    return resolveNovelModeLabel(this.resolveContentKind());
  }

  private resolveReadingModeAccessibilityLabel(): string {
    return resolveNovelReadingModeLabel(this.resolveContentKind());
  }

  private resolveExecutorSignature(): string {
    return `${this.state.preferences.autoReadingEnabled}|${this.state.preferences.autoReadingSpeed}|` +
      `${this.state.preferences.pageMode}|${this.state.preferences.systemStatusBarVisible}`;
  }

  private effectiveTheme(): ReaderModeTheme {
    return resolveEffectiveReadingTheme(this.readerTheme);
  }

  private resolveBackgroundColor(theme: ReaderModeTheme): ResourceColor {
    return resolveReadingThemeTokens(theme).backgroundColor;
  }

  private resolveControlBackgroundColor(theme: ReaderModeTheme): ResourceColor {
    return resolveReadingThemeTokens(theme).controlBackgroundColor;
  }

  private resolveTextColor(theme: ReaderModeTheme): ResourceColor {
    return resolveReadingThemeTokens(theme).primaryTextColor;
  }

  private resolveSecondaryTextColor(theme: ReaderModeTheme): ResourceColor {
    return resolveReadingThemeTokens(theme).secondaryTextColor;
  }
}
