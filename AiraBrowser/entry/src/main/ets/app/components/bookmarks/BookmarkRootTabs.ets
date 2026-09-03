import { BookmarkStorageScope } from '../../../common/models/BrowserModels';
import { SegmentedTabOption, SegmentedTabs } from '../common/SegmentedTabs';
import {
  BOOKMARK_OTHER_ROOT_ID,
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_OTHER_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../../data/repositories/BookmarkRepositoryCore';

/** Shared root-folder tab chrome for the phone bookmark manager. */
@Component
export struct BookmarkRootTabs {
  @Prop scope: BookmarkStorageScope = 'regular';
  @Prop selectedId: string = '';
  @Prop tabsTopInset: number = 0;
  onSelect: (id: string) => void = (_id: string): void => {};
  @BuilderParam content: () => void = this.emptyBuilder;
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()

      Row() {
        SegmentedTabs({
          options: this.buildOptions(),
          selectedId: this.selectedId,
          barHeight: 36,
          itemHeight: 30,
          fontSize: 14,
          barPadding: 3,
          onSelect: (id: string): void => {
            this.onSelect(id);
          }
        })
        .width('100%')
        .height(36)
        .borderRadius(18)
        .clip(true)
      }
      .width('100%')
      .height(36)
      .padding({ left: 16, right: 16 })
      .borderRadius(18)
      .clip(true)
      .position({ x: 0, y: this.tabsTopInset })
      .zIndex(2)
    }
    .width('100%')
    .height('100%')
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
