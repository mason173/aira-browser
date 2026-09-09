import { BookmarkStorageScope } from '../../../common/models/BrowserModels';
import {
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../../data/repositories/BookmarkRepositoryCore';

/** Shared root-folder tab chrome for the phone bookmark manager. */
@Component
export struct BookmarkRootTabs {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY)
  private storedControlBackgroundColor: string = DEFAULT_THEME_PALETTE.light.controlBackground;
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop scope: BookmarkStorageScope = 'regular';
  @Prop selectedId: string = '';
  @Prop tabsTopInset: number = 0;
  onSelect: (id: string) => void = (_id: string): void => {};
  @BuilderParam content: () => void = this.emptyBuilder;
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()

      Column() {
        this.buildRootTabBar()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 0, bottom: 8 })
      .position({ x: 0, y: this.tabsTopInset })
      .zIndex(2)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildRootTabBar() {
    FloatingGlassMaterialSurface({
      surfaceWidth: '100%',
      surfaceHeight: 36,
      surfaceRadius: 18,
      tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode),
      fallbackColor: this.storedControlBackgroundColor,
      backgroundBlurEnabled: false
    }) {
      SegmentedTabs({
        options: this.buildOptions(),
        selectedId: this.selectedId,
        barHeight: 36,
        itemHeight: 30,
        fontSize: 14,
        barPadding: 3,
        fallbackColor: $r('sys.color.ohos_id_color_background_transparent'),
        barMaterialEnabled: false,
        onSelect: (id: string): void => {
          this.onSelect(id);
        }
      })
        .width('100%')
        .height(36)
    }
  }

  @Builder
  private emptyBuilder() {
    Blank();
  }

  private buildOptions(): SegmentedTabOption[] {
    return [
      {
        id: this.resolveToolbarRootId(),
        title: this.scope === 'private' ? '隐私书签栏' : '书签栏'
      },
      {
        id: this.resolveOtherRootId(),
        title: this.scope === 'private' ? '其他隐私书签' : '其他书签'
      }
    ];
  }

  private resolveToolbarRootId(): string {
    return this.scope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
  }

  private resolveOtherRootId(): string {
    return this.scope === 'private' ? PRIVATE_BOOKMARK_OTHER_ROOT_ID : BOOKMARK_OTHER_ROOT_ID;
  }
}
