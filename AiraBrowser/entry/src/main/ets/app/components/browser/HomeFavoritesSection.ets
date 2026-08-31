import {
  HomeContentThemePresentationState,
  HomeShortcutPresentationState,
  createDefaultHomeContentThemePresentationState
} from '../../../core/browser/HomeContentPresentationState';
import { HomeShortcutUserAction } from '../../../features/newtab/HomeShortcutTypes';
import { HomeShortcutViewModel } from '../../../features/newtab/HomeShortcutViewModel';
import { HomeExpandableSectionHeader } from './HomeExpandableSectionHeader';
import { HomeShortcutSurface } from './HomeShortcutSurface';

const HOME_SECTION_CONTENT_INSET: number = 10;

@Component
export struct HomeFavoritesSection {
  @Prop expanded: boolean = true;
  @Prop showTitle: boolean = true;
  @Prop minimumWidth: number = 0;
  @Prop alignPartialRowsToStart: boolean = false;
  @Prop shortcuts: HomeShortcutPresentationState = {
    shortcuts: [],
    showAddEntry: false,
    gridWidth: 0,
    gridTopInset: 0,
    layoutVersion: 0,
    iconsVersion: 0,
    icons: [],
    metrics: {
      columns: 4,
      rowGap: 0,
      columnGap: 0,
      targetTileSize: 54,
      minimumTileSize: 41,
      fallbackColumnWidth: 88,
      titleTopGap: 2,
      titleBlockHeight: 18
    }
  };
  @Prop theme: HomeContentThemePresentationState = createDefaultHomeContentThemePresentationState();
  @Link contextMenuShortcutId: string;
  @Link shortcutDragActive: boolean;

  private shortcutViewModel: HomeShortcutViewModel = new HomeShortcutViewModel();

  onToggle: () => void = () => {};
  onShortcutAction: (action: HomeShortcutUserAction) => void = (_action: HomeShortcutUserAction) => {};
  onOpenAddEntry: () => void = () => {};
  onOpenHomeSettings: () => void = () => {};

  build() {
    Column({ space: 0 }) {
      if (this.showTitle) {
        HomeExpandableSectionHeader({
          title: '收藏',
          expanded: this.expanded,
          toggleEnabled: true,
          leftInset: HOME_SECTION_CONTENT_INSET,
          rightInset: HOME_SECTION_CONTENT_INSET,
          primaryTextColor: this.theme.primaryTextColor,
          secondaryTextColor: this.theme.secondaryTextColor,
          pressedBackgroundColor: this.theme.pressedBackgroundColor,
          pressedBackdropBlurRadius: this.theme.pressedBackdropBlurRadius,
          textShadow: this.theme.textShadow,
          onToggle: () => {
            this.onToggle();
          }
        })
      }

      if (this.expanded || !this.showTitle) {
        this.buildShortcutGrid()
      }
    }
    .width(this.resolveSectionWidth())
    .alignSelf(ItemAlign.Center)
  }

  @Builder
  private buildShortcutGrid() {
    Column() {
      HomeShortcutSurface({
        shortcuts: this.shortcuts.shortcuts,
        shortcutOrderSignature: this.shortcutViewModel.buildShortcutOrderSignature(this.shortcuts.shortcuts),
        icons: this.shortcuts.icons,
        iconsVersion: this.shortcuts.iconsVersion,
        metrics: this.shortcuts.metrics,
        contentInset: HOME_SECTION_CONTENT_INSET,
        contentOffsetY: 0,
        primaryTextColor: this.theme.primaryTextColor,
        secondaryTextColor: this.theme.secondaryTextColor,
        textShadow: this.theme.textShadow,
        gridWidth: this.resolveShortcutGridWidth(),
        showAddEntry: this.shortcuts.showAddEntry,
        alignPartialRowsToStart: this.alignPartialRowsToStart,
        contextMenuShortcutId: $contextMenuShortcutId,
        shortcutDragActive: $shortcutDragActive,
        onAction: (action: HomeShortcutUserAction) => {
          this.onShortcutAction(action);
        },
        onOpenAddEntry: () => {
          this.onOpenAddEntry();
        },
        onOpenHomeSettings: () => {
          this.onOpenHomeSettings();
        }
      })
    }
    .width(this.resolveSectionWidth())
    .padding({
      top: this.shortcuts.gridTopInset
    })
  }

  private resolveShortcutGridWidth(): number {
    return Math.max(1, this.shortcuts.gridWidth);
  }

  private resolveSectionWidth(): number {
    const itemCount = this.shortcuts.shortcuts.length + (this.shortcuts.showAddEntry ? 1 : 0);
    const occupiedContentWidth = this.shortcutViewModel.getOccupiedGridContentWidth(
      itemCount,
      this.resolveShortcutGridWidth(),
      HOME_SECTION_CONTENT_INSET,
      this.shortcuts.metrics
    );
    const contentDrivenWidth = occupiedContentWidth + HOME_SECTION_CONTENT_INSET * 2;
    return Math.min(
      this.resolveShortcutGridWidth(),
      Math.max(Math.max(0, this.minimumWidth), contentDrivenWidth)
    );
  }
}
