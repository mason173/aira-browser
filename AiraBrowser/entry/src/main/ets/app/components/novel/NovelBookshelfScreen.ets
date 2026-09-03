import { common } from '@kit.AbilityKit';
import { showCenteredAlertDialog } from '../common/CenteredDialogSurface';
import router from '@ohos.router';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  NovelBookshelfController,
  NovelBookshelfRemovalResult
} from '../../../features/novel/NovelBookshelfController';
import {
  NovelBookshelfBook,
  NovelBookshelfCategory,
  NovelBookshelfState
} from '../../../features/novel/NovelLibraryModels';
import {
  NovelBookshelfLayoutMode,
  NovelBookshelfLayoutState,
  NovelBookshelfLayoutViewModel
} from '../../../features/novel/NovelBookshelfLayoutViewModel';
import { AiraIcon } from '../common/AiraIcon';
import { AppEmptyState } from '../common/AppEmptyState';
import { ManagementHdsScaffold } from '../common/ManagementHdsScaffold';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode
} from '../common/FloatingGlassMaterialTokens';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { NovelBookCover } from './NovelBookCover';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import {
  BrowserClipboardCopyResult,
  BrowserClipboardService
} from '../../../services/share/BrowserClipboardService';
import { WebPageShareService } from '../../../services/share/WebPageShareService';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';

const NOVEL_BOOKSHELF_BOTTOM_PADDING: number = 32;
const NOVEL_BOOKSHELF_CONTEXT_MENU_DISMISS_DELAY_MS: number = 120;
const NOVEL_BOOKSHELF_HEADER_TOP_INSET: number = 8;
const NOVEL_BOOKSHELF_HEADER_HEIGHT: number = 40;
const NOVEL_BOOKSHELF_HEADER_TO_TABS_GAP: number = 12;
const NOVEL_BOOKSHELF_TABS_HEIGHT: number = 36;
const NOVEL_BOOKSHELF_TABS_TO_CONTENT_GAP: number = 16;
const NOVEL_BOOKSHELF_TOP_BLUR_RADIUS: number = 20;
const NOVEL_BOOKSHELF_CATEGORY_OPTIONS: SegmentedTabOption[] = [
  { id: 'novel', title: '小说' },
  { id: 'comic', title: '漫画' }
];

@Component
export struct NovelBookshelfScreen {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = DEFAULT_THEME_PALETTE.light.divider;
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY)
  private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY)
  private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY)
  private storedSecondaryTextColor: string = DEFAULT_THEME_PALETTE.light.textSecondary;
  @State private state: NovelBookshelfState = new NovelBookshelfController().createLoadingState();
  @State private selectedCategory: NovelBookshelfCategory = 'novel';
  @State private contextMenuBookId: string = '';
  @State private listRenderVersion: number = 0;
  @State private contentWidth: number = 390;
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private topSafeInsetVp: number = 0;
  private readonly controller: NovelBookshelfController = new NovelBookshelfController();
  private readonly layoutViewModel: NovelBookshelfLayoutViewModel = new NovelBookshelfLayoutViewModel();
  private readonly clipboardService: BrowserClipboardService = new BrowserClipboardService();
  private readonly shareService: WebPageShareService = new WebPageShareService();
  private readonly gridScroller: Scroller = new Scroller();
  @Prop persistentAccessAllowed: boolean = false;
  @Prop layoutMode: NovelBookshelfLayoutMode = 'phone';
  onOpenBook: (book: NovelBookshelfBook) => void = (_book: NovelBookshelfBook): void => {};
  onOpenOriginalPage: (book: NovelBookshelfBook) => void = (_book: NovelBookshelfBook): void => {};

  aboutToAppear(): void {
    this.refresh();
  }

  build() {
    Column() {
      ManagementHdsScaffold({
        title: '我的书架',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        immersiveContent: true,
        topSafeInsetVpOverride: this.topSafeInsetVp,
        scrollers: [this.gridScroller],
        onBack: (): void => {
          router.back();
        }
      }) {
        if (!this.persistentAccessAllowed) {
          this.buildStatus('隐私模式下不可用', '')
        } else if (this.state.loading) {
          this.buildStatus('正在加载书架', '')
        } else if (this.state.errorMessage.length > 0) {
          this.buildStatus('书架暂时不可用', this.state.errorMessage)
        } else if (this.state.novels.length === 0 && this.state.comics.length === 0) {
          this.buildStatus('暂无收藏', '')
        } else {
          this.buildBookContent()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }

  @Builder
  private buildStatus(title: string, message: string) {
    AppEmptyState({
      airaIconId: 'browser.toolbar.reader',
      title: title,
      message: message,
      fillHeight: true
    })
  }

  @Builder
  private buildBookContent() {
    Row() {
      Stack({ alignContent: Alignment.TopStart }) {
        if (this.selectedCategory === 'comic') {
          if (this.state.comics.length === 0) {
            this.buildCategoryStatus('暂无漫画收藏')
          } else {
            this.buildBookGrid(this.state.comics)
          }
        } else {
          if (this.state.novels.length === 0) {
            this.buildCategoryStatus('暂无小说收藏')
          } else {
            this.buildBookGrid(this.state.novels)
          }
        }

        Row() {
          SegmentedTabs({
            options: NOVEL_BOOKSHELF_CATEGORY_OPTIONS,
            selectedId: this.selectedCategory,
            onSelect: (id: string): void => {
              this.selectedCategory = id === 'comic' ? 'comic' : 'novel';
            }
          })
          .width('100%')
          .constraintSize({ maxWidth: this.resolveCategoryControlMaxWidth() })
        }
        .width('100%')
        .height(NOVEL_BOOKSHELF_TABS_HEIGHT)
        .padding({
          left: this.resolveLayoutState().horizontalPadding,
          right: this.resolveLayoutState().horizontalPadding
        })
        .position({ x: 0, y: this.resolveTabsTopInset() })
        .justifyContent(FlexAlign.Center)
        .zIndex(2)
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: this.resolveContentMaxWidth() })
      .onAreaChange((_oldArea: Area, newArea: Area): void => {
        const nextWidth = Math.max(1, Math.round(this.parseAreaDimension(newArea.width)));
        if (nextWidth !== this.contentWidth) {
          this.contentWidth = nextWidth;
        }
      })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  private buildCategoryStatus(title: string) {
    Column() {
      AppEmptyState({
        airaIconId: 'browser.toolbar.reader',
        title: title,
        message: '',
        fillHeight: true
      })
    }
    .width('100%')
    .height('100%')
    .padding({ top: this.resolveGridContentTopInset() })
  }

  @Builder
  private buildBookGrid(books: NovelBookshelfBook[]) {
    Grid(this.gridScroller) {
      ForEach(books, (book: NovelBookshelfBook) => {
        GridItem() {
          Button({ type: ButtonType.Normal }) {
            Column({ space: 9 }) {
              Stack() {
                NovelBookCover({
                  coverUrl: book.coverUrl,
                  detailUrl: book.detailUrl,
                  persistentlyCached: true,
                  title: book.title,
                  coverBackgroundColor: this.storedControlBackgroundColor,
                  fallbackPrimaryTextColor: this.storedPrimaryTextColor,
                  fallbackSecondaryTextColor: this.storedSecondaryTextColor,
                  fallbackDividerColor: this.storedDividerColor
                })
              }
              .width('100%')
              .aspectRatio(0.72)
              Text(book.title)
                .width('100%')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.storedPrimaryTextColor)
                .textAlign(TextAlign.Start)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding(0)
          .backgroundColor(Color.Transparent)
          .stateEffect(true)
          .accessibilityText(`打开${book.title}`)
          .gesture(
            GestureGroup(
              GestureMode.Exclusive,
              LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
                .onAction((): void => {
                  this.contextMenuBookId = book.id;
                }),
              TapGesture()
                .onAction((): void => {
                  this.onOpenBook(book);
                })
            )
          )
          .bindContextMenu(this.contextMenuBookId === book.id, this.buildBookContextMenu(book), {
            preview: this.buildBookContextPreview(book),
            previewBorderRadius: 8,
            onDisappear: (): void => {
              this.contextMenuBookId = '';
            }
          })
        }
      }, (book: NovelBookshelfBook): string => `${book.id}:${this.listRenderVersion}`)
    }
    .width('100%')
    .height('100%')
    .columnsTemplate(this.resolveLayoutState().columnsTemplate)
    .columnsGap(this.resolveLayoutState().columnGap)
    .rowsGap(this.resolveLayoutState().rowGap)
    .padding({
      left: this.resolveLayoutState().horizontalPadding,
      right: this.resolveLayoutState().horizontalPadding,
      top: this.resolveGridContentTopInset(),
      bottom: NOVEL_BOOKSHELF_BOTTOM_PADDING
    })
    .linearGradientBlur(NOVEL_BOOKSHELF_TOP_BLUR_RADIUS, {
      fractionStops: [[1, 0], [1, 0.05], [0, 0.14], [0, 1]],
      direction: GradientDirection.Bottom
    })
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .scrollBar(BarState.Auto)
    .expandSafeArea(
      [SafeAreaType.SYSTEM, SafeAreaType.CUTOUT],
      [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM]
    )
  }

  private resolveTabsTopInset(): number {
    return Math.max(0, Math.ceil(this.topSafeInsetVp)) + NOVEL_BOOKSHELF_HEADER_TOP_INSET +
      NOVEL_BOOKSHELF_HEADER_HEIGHT + NOVEL_BOOKSHELF_HEADER_TO_TABS_GAP;
  }

  private resolveGridContentTopInset(): number {
    return this.resolveTabsTopInset() + NOVEL_BOOKSHELF_TABS_HEIGHT + NOVEL_BOOKSHELF_TABS_TO_CONTENT_GAP;
  }

  private resolveLayoutState(): NovelBookshelfLayoutState {
    return this.layoutViewModel.buildState({
      layoutMode: this.layoutMode,
      contentWidth: this.contentWidth
    });
  }

  private resolveContentMaxWidth(): Length {
    const maxWidth = this.resolveLayoutState().contentMaxWidth;
    return maxWidth > 0 ? maxWidth : '100%';
  }

  private resolveCategoryControlMaxWidth(): Length {
    const maxWidth = this.resolveLayoutState().categoryControlMaxWidth;
    return maxWidth > 0 ? maxWidth : '100%';
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  @Builder
  private buildBookContextPreview(book: NovelBookshelfBook) {
    Column({ space: 9 }) {
      NovelBookCover({
        coverUrl: book.coverUrl,
        detailUrl: book.detailUrl,
        persistentlyCached: true,
        title: book.title,
        coverBackgroundColor: this.storedControlBackgroundColor,
        fallbackPrimaryTextColor: this.storedPrimaryTextColor,
        fallbackSecondaryTextColor: this.storedSecondaryTextColor,
        fallbackDividerColor: this.storedDividerColor
      })
      .width(128)
      .aspectRatio(0.72)

      Text(book.title)
        .width(128)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .padding(8)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(this.storedPageBackgroundColor)
    .borderRadius(8)
  }

  @Builder
  private buildBookContextMenu(book: NovelBookshelfBook) {
    Menu() {
      MenuItem({ content: '查看原网页' })
        .onClick((): void => {
          this.runAfterContextMenuDismiss((): void => {
            this.onOpenOriginalPage(book);
          });
        })
      MenuItem({ content: '分享' })
        .onClick((): void => {
          this.runAfterContextMenuDismiss((): void => {
            this.shareBook(book);
          });
        })
      MenuItem({ content: '复制链接' })
        .onClick((): void => {
          this.runAfterContextMenuDismiss((): void => {
            this.copyBookLink(book);
          });
        })
      MenuItem({ content: '移出书架' })
        .onClick((): void => {
          this.runAfterContextMenuDismiss((): void => {
            this.confirmRemoveBook(book);
          });
        })
    }
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .systemMaterial(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    ))
  }

  private runAfterContextMenuDismiss(action: () => void): void {
    this.contextMenuBookId = '';
    setTimeout((): void => {
      action();
    }, NOVEL_BOOKSHELF_CONTEXT_MENU_DISMISS_DELAY_MS);
  }

  private shareBook(book: NovelBookshelfBook): void {
    void this.shareService.shareWebPage(this.getAbilityContext(), {
      title: book.title,
      url: book.detailUrl
    }).catch((_error: Error): void => {
      this.showToast('分享失败，请稍后重试。');
    });
  }

  private copyBookLink(book: NovelBookshelfBook): void {
    void this.clipboardService.copyText({
      value: book.detailUrl.trim(),
      emptyMessage: '当前没有可复制的链接。',
      successMessage: '链接已复制。'
    }).then((result: BrowserClipboardCopyResult): void => {
      this.showToast(result.message);
    });
  }

  private confirmRemoveBook(book: NovelBookshelfBook): void {
    showCenteredAlertDialog({
      title: '移出书架',
      message: `确定将“${book.title}”移出书架吗？`,
      autoCancel: true,
      primaryButton: {
        value: '取消',
        action: (): void => {}
      },
      secondaryButton: {
        value: '移出',
        fontColor: $r('app.color.permission_blocked'),
        action: (): void => {
          void this.removeBook(book);
        }
      }
    });
  }

  private async removeBook(book: NovelBookshelfBook): Promise<void> {
    const result: NovelBookshelfRemovalResult = await this.controller.removeFromBookshelf(book.detailUrl);
    if (!result.success) {
      this.showToast(result.message);
      return;
    }
    this.contextMenuBookId = '';
    this.listRenderVersion += 1;
    this.state = result.state;
    this.showToast(result.message);
  }

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private refresh(): void {
    if (!this.persistentAccessAllowed) {
      this.state = {
        loading: false,
        novels: [],
        comics: [],
        errorMessage: ''
      };
      return;
    }
    this.state = this.controller.createLoadingState();
    void this.controller.load().then((state: NovelBookshelfState): void => {
      this.state = state;
      this.reconcileSelectedCategory(state);
    });
  }

  private reconcileSelectedCategory(state: NovelBookshelfState): void {
    const selectedBooks: NovelBookshelfBook[] = this.selectedCategory === 'comic' ? state.comics : state.novels;
    if (selectedBooks.length > 0) {
      return;
    }
    this.selectedCategory = state.novels.length > 0 ? 'novel' : 'comic';
  }
}
