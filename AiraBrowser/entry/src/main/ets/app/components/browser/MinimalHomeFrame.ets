import { ExternalAppSearchTargetId, SearchSuggestion } from '../../../common/models/BrowserModels';
import {
  createDefaultHomeContentSectionsPresentationState,
  createDefaultHomeContentThemePresentationState,
  HomeContentSectionsPresentationState,
  HomeContentThemePresentationState
} from '../../../core/browser/HomeContentPresentationState';
import { BrowserTabHomeContentAction } from '../../../core/browser/BrowserTabHomeCoordinator';
import { SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP } from '../../../core/browser/BrowserToolbarChromeStylePolicy';
import {
  HOME_LOGO_SCALE_DEFAULT_RATIO,
  resolveHomeLogoHeightVp
} from '../../../core/settings/HomeLogoSettingsPolicy';
import { HOME_PAGE_PRESENTATION_HOME_LOGO_SCALE_RATIO_KEY } from
  '../../../common/constants/HomePagePresentationStorageKeys';
import {
  CenteredHomeFrame as WordmarkHomeFrameMetrics,
  CENTERED_HOME_WORDMARK_HEIGHT,
  resolveCenteredHomeFrame,
  resolveMeasuredCenteredSurfaceHeight
} from '../../../features/newtab/CenteredHomeShortcutLayoutPolicy';
import { WordmarkHomeHeaderBlock } from './WordmarkHomeHeaderBlock';

/**
 * 极简主页. Same wordmark family as 简约, but its own component: no shortcut grid, no scroller,
 * and a measured height that cannot be the one 简约 just used.
 */
@Component
export struct MinimalHomeFrame {
  @StorageProp(HOME_PAGE_PRESENTATION_HOME_LOGO_SCALE_RATIO_KEY)
  private storedLogoScaleRatio: number = HOME_LOGO_SCALE_DEFAULT_RATIO;
  @Prop presentation: HomeContentSectionsPresentationState =
    createDefaultHomeContentSectionsPresentationState();
  @Prop theme: HomeContentThemePresentationState = createDefaultHomeContentThemePresentationState();
  @Prop searchPresented: boolean = false;
  @Prop searchGeometryEnabled: boolean = true;
  @Prop inlineSearch: boolean = false;
  @Prop inlineSearchActive: boolean = false;
  @Prop searchSuggestions: SearchSuggestion[] = [];
  @Prop searchDismissVersion: number = 0;
  @Prop viewportHeight: number = 0;
  @Prop topSafeInset: number = 0;
  @Prop bottomReserve: number = 0;
  @State private surfaceHeight: number = 0;

  onAction: (action: BrowserTabHomeContentAction) => void = (_action: BrowserTabHomeContentAction) => {};
  onOpenSearch: () => void = () => {};
  onScan: () => void = () => {};
  onInlineSearchSession: (active: boolean, query: string) => void =
    (_active: boolean, _query: string) => {};
  onSubmitSearch: (query: string) => void = (_query: string) => {};
  onOpenSearchSuggestion: (suggestion: SearchSuggestion) => void =
    (_suggestion: SearchSuggestion) => {};
  onDeleteSearchSuggestion: (suggestion: SearchSuggestion) => void =
    (_suggestion: SearchSuggestion) => {};
  onClearSearchSuggestions: () => void = () => {};
  onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string) => void =
    (_targetId: ExternalAppSearchTargetId, _query: string) => {};
  onDismissInlineSearch: () => void = () => {};

  build() {
    Column() {
      Column()
        .width('100%')
        .height(this.resolveFrame().headerTop)

      WordmarkHomeHeaderBlock({
        theme: this.theme,
        horizontalPadding: this.presentation.horizontalPadding,
        searchPresented: this.searchPresented,
        searchGeometryEnabled: this.searchGeometryEnabled,
        inlineSearch: this.inlineSearch,
        inlineSearchActive: this.inlineSearchActive,
        searchSuggestions: this.searchSuggestions,
        searchViewportHeight: this.viewportHeight,
        searchPopupReservedTop: this.topSafeInset,
        searchDismissVersion: this.searchDismissVersion,
        showScanButton: false,
        softenSearchBorder: true,
        searchSideInset: this.resolveSearchSideInset(),
        wordmarkOpensSettings: true,
        onAction: (action: BrowserTabHomeContentAction) => {
          this.onAction(action);
        },
        onOpenSearch: () => {
          this.onOpenSearch();
        },
        onScan: () => {
          this.onScan();
        },
        onInlineSearchSession: (active: boolean, query: string): void => {
          this.onInlineSearchSession(active, query);
        },
        onSubmitSearch: (query: string): void => {
          this.onSubmitSearch(query);
        },
        onOpenSearchSuggestion: (suggestion: SearchSuggestion): void => {
          this.onOpenSearchSuggestion(suggestion);
        },
        onDeleteSearchSuggestion: (suggestion: SearchSuggestion): void => {
          this.onDeleteSearchSuggestion(suggestion);
        },
        onClearSearchSuggestions: (): void => {
          this.onClearSearchSuggestions();
        },
        onExternalSearch: (targetId: ExternalAppSearchTargetId, query: string): void => {
          this.onExternalSearch(targetId, query);
        }
      })

      Stack() {
        if (this.inlineSearch && this.inlineSearchActive) {
          Column()
            .width('100%')
            .height('100%')
            .hitTestBehavior(HitTestMode.Default)
            .onClick(() => {
              this.onDismissInlineSearch();
            })
        }
      }
      .layoutWeight(1)
      .width('100%')

      Column()
        .width('100%')
        .height(Math.max(0, this.bottomReserve))
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.updateSurfaceHeight(newArea);
    })
  }

  private resolveSearchSideInset(): number {
    return Math.max(0, SPLIT_TOOLBAR_ADDRESS_HORIZONTAL_MARGIN_VP - this.presentation.horizontalPadding);
  }

  private resolveFrame(): WordmarkHomeFrameMetrics {
    return resolveCenteredHomeFrame({
      viewportHeight: resolveMeasuredCenteredSurfaceHeight(this.surfaceHeight, this.viewportHeight),
      topSafeInset: this.topSafeInset,
      bottomChromeReserve: Math.max(0, this.bottomReserve),
      logoHeightVp: resolveHomeLogoHeightVp(CENTERED_HOME_WORDMARK_HEIGHT, this.storedLogoScaleRatio)
    });
  }

  private updateSurfaceHeight(area: Area): void {
    const height = parseAreaLength(area.height);
    // Parent and child area callbacks have no fixed order during fullscreen rotation.
    // Keep the raw measurement; resolveFrame clamps it against the latest viewport.
    if (height > 0 && height !== this.surfaceHeight) {
      this.surfaceHeight = height;
    }
  }
}

function parseAreaLength(value: Length): number {
  const parsed = Number(`${value}`.replace('vp', '').replace('px', '').trim());
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
}
