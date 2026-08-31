import { ExternalAppSearchTarget } from '../../../services/search/ExternalAppSearchService';
import { ExternalAppSearchTargetId } from '../../../common/models/BrowserModels';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  resolveBrowserBottomNeutralContainerColor,
  resolveBrowserBottomNeutralPrimaryColor
} from '../../../core/theme/BrowserBottomPanelNeutralTheme';
import { AppIconResources } from '../../../core/resources/AppIconResources';
import {
  BROWSER_SEARCH_LIST_EXTERNAL_ACTION_SIZE,
  BROWSER_SEARCH_LIST_EXTERNAL_ITEM_CENTER_PITCH,
  BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH,
  BROWSER_SEARCH_LIST_EXTERNAL_STRIP_HEIGHT
} from '../../../core/browser/BrowserSearchListSurfaceLayoutViewModel';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';

const EXTERNAL_APP_SEARCH_ACTION_RADIUS: number = 12;
const EXTERNAL_APP_SEARCH_ICON_SIZE: number = 27;
const EXTERNAL_APP_SEARCH_LABEL_SIZE: number = 11;
const EXTERNAL_APP_SEARCH_LABEL_LINE_HEIGHT: number = 16;
const EXTERNAL_APP_SEARCH_ACTION_GAP: number = 4;
const EXTERNAL_APP_SEARCH_GLASS_OVERLAY_OPACITY: number = 0.72;
const EXTERNAL_APP_SEARCH_PRESSED_SCALE: number = 0.94;
const EXTERNAL_APP_SEARCH_PRESS_DURATION_MS: number = 90;
const EXTERNAL_APP_SEARCH_RELEASE_DURATION_MS: number = 220;
const EXTERNAL_APP_SEARCH_DEFAULT_PAGE_SIZE: number = 4;

interface ExternalAppSearchTargetPage {
  pageIndex: number;
  targets: ExternalAppSearchTarget[];
}

@Component
export struct ExternalAppSearchStrip {
  private swiperController: SwiperController = new SwiperController();
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @State private pressedTargetId: string = '';
  @State private pageIndex: number = 0;
  @Prop targets: ExternalAppSearchTarget[] = [];
  @Prop query: string = '';
  @Prop labelColor: ResourceColor | undefined = undefined;
  @Prop stripHeight: number = BROWSER_SEARCH_LIST_EXTERNAL_STRIP_HEIGHT;
  @Prop itemWidth: number = BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH;
  @Prop actionSize: number = BROWSER_SEARCH_LIST_EXTERNAL_ACTION_SIZE;
  @Prop columnGap: number = BROWSER_SEARCH_LIST_EXTERNAL_ITEM_CENTER_PITCH -
    BROWSER_SEARCH_LIST_EXTERNAL_ITEM_WIDTH;
  @Prop pageSize: number = EXTERNAL_APP_SEARCH_DEFAULT_PAGE_SIZE;
  onSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};

  build() {
    if (this.targets.length > 0) {
      ForEach([this.buildLayoutRenderKey()], (_layoutKey: string) => {
        Swiper(this.swiperController) {
          ForEach(this.resolveTargetPages(), (page: ExternalAppSearchTargetPage) => {
            this.buildTargetPage(page)
          }, (page: ExternalAppSearchTargetPage) => this.buildPageRenderKey(page))
        }
        .index(this.resolvePageIndex())
        .indicator(false)
        .loop(false)
        .cachedCount(1)
        .width('100%')
        .height(this.stripHeight)
        .onChange((index: number) => {
          this.pageIndex = this.clampPageIndex(index);
        })
      }, (layoutKey: string) => layoutKey)
    } else {
      Blank()
        .width('100%')
        .height(0)
        .hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  private buildTargetPage(page: ExternalAppSearchTargetPage) {
    if (this.isFullTargetPage(page)) {
      this.buildFullTargetPage(page)
    } else {
      this.buildPartialTargetPage(page)
    }
  }

  @Builder
  private buildFullTargetPage(page: ExternalAppSearchTargetPage) {
    Row() {
      this.buildTargetButtons(page)
    }
    .width('100%')
    .height(this.stripHeight)
    .justifyContent(FlexAlign.SpaceBetween)
  }

  @Builder
  private buildPartialTargetPage(page: ExternalAppSearchTargetPage) {
    Row({ space: this.columnGap }) {
      this.buildTargetButtons(page)
    }
    .width('100%')
    .height(this.stripHeight)
    .justifyContent(FlexAlign.Start)
  }

  @Builder
  private buildTargetButtons(page: ExternalAppSearchTargetPage) {
    ForEach(page.targets, (target: ExternalAppSearchTarget) => {
      this.buildTargetButton(target)
    }, (target: ExternalAppSearchTarget) => target.id)
  }

  @Builder
  private buildTargetButton(target: ExternalAppSearchTarget) {
    Button() {
      Column({ space: EXTERNAL_APP_SEARCH_ACTION_GAP }) {
        if (target.iconTargetId !== undefined) {
          Image(AppIconResources.externalAppSearch(target.iconTargetId))
            .width(this.actionSize)
            .height(this.actionSize)
            .objectFit(ImageFit.Cover)
            .borderRadius(EXTERNAL_APP_SEARCH_ACTION_RADIUS)
            .clip(true)
        } else {
          BrowserFloatingGlassMaterialSurface({
            surfaceWidth: this.actionSize,
            surfaceHeight: this.actionSize,
            surfaceRadius: EXTERNAL_APP_SEARCH_ACTION_RADIUS,
            tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
            overlayColor: resolveBrowserBottomNeutralContainerColor(this.storedResolvedThemeMode),
            overlayOpacity: EXTERNAL_APP_SEARCH_GLASS_OVERLAY_OPACITY
          }) {
            this.buildTargetMark(target)
          }
        }

        Text(target.title)
          .width('100%')
          .fontSize(EXTERNAL_APP_SEARCH_LABEL_SIZE)
          .lineHeight(EXTERNAL_APP_SEARCH_LABEL_LINE_HEIGHT)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveLabelColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height(this.stripHeight)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(this.itemWidth)
    .height(this.stripHeight)
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .stateEffect(false)
    .hoverEffect(HoverEffect.None)
    .focusable(false)
    .focusOnTouch(false)
    .accessibilityText(target.accessibilityText)
    .scale({
      x: this.pressedTargetId === target.id ? EXTERNAL_APP_SEARCH_PRESSED_SCALE : 1,
      y: this.pressedTargetId === target.id ? EXTERNAL_APP_SEARCH_PRESSED_SCALE : 1
    })
    .animation({
      duration: this.pressedTargetId === target.id ? EXTERNAL_APP_SEARCH_PRESS_DURATION_MS :
        EXTERNAL_APP_SEARCH_RELEASE_DURATION_MS,
      curve: this.pressedTargetId === target.id ? Curve.EaseOut : 'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressedTarget(target.id, event.type);
    })
    .onClick(() => {
      this.pressedTargetId = '';
      this.onSearch(target.id, this.query);
    })
  }

  @Builder
  private buildTargetMark(target: ExternalAppSearchTarget) {
    Text(target.markText)
      .width(EXTERNAL_APP_SEARCH_ICON_SIZE)
      .height(EXTERNAL_APP_SEARCH_ICON_SIZE)
      .fontSize(14)
      .lineHeight(EXTERNAL_APP_SEARCH_ICON_SIZE)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.resolveLabelColor())
      .maxLines(1)
      .textAlign(TextAlign.Center)
  }

  private updatePressedTarget(targetId: ExternalAppSearchTargetId, touchType: TouchType): void {
    if (touchType === TouchType.Down) {
      this.pressedTargetId = targetId;
      return;
    }
    if (touchType === TouchType.Up || touchType === TouchType.Cancel) {
      this.pressedTargetId = '';
    }
  }

  private resolveTargetPages(): ExternalAppSearchTargetPage[] {
    const pageSize = this.resolvePageSize();
    const pages: ExternalAppSearchTargetPage[] = [];
    for (let index = 0; index < this.targets.length; index += pageSize) {
      pages.push({
        pageIndex: pages.length,
        targets: this.targets.slice(index, index + pageSize)
      });
    }
    return pages;
  }

  private resolvePageSize(): number {
    return Math.max(1, Math.floor(this.pageSize));
  }

  private isFullTargetPage(page: ExternalAppSearchTargetPage): boolean {
    return page.targets.length === this.resolvePageSize();
  }

  private resolvePageIndex(): number {
    return this.clampPageIndex(this.pageIndex);
  }

  private clampPageIndex(index: number): number {
    return Math.max(0, Math.min(Math.floor(index), Math.max(0, this.resolveTargetPages().length - 1)));
  }

  private buildLayoutRenderKey(): string {
    return `external-app-search:${this.resolvePageSize()}:` +
      `${Math.round(this.stripHeight)}:${Math.round(this.itemWidth)}:` +
      `${Math.round(this.actionSize)}:${Math.round(this.columnGap)}:` +
      this.targets.map((target: ExternalAppSearchTarget) => target.id).join('|');
  }

  private buildPageRenderKey(page: ExternalAppSearchTargetPage): string {
    return `${this.buildLayoutRenderKey()}:page:${page.pageIndex}:` +
      page.targets.map((target: ExternalAppSearchTarget) => target.id).join('|');
  }

  private resolveLabelColor(): ResourceColor {
    return this.labelColor === undefined ?
      resolveBrowserBottomNeutralPrimaryColor(this.storedResolvedThemeMode) : this.labelColor;
  }
}
