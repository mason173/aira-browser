import { BookmarkNode, BookmarkStorageScope } from '../../common/models/BrowserModels';
import {
  BOOKMARK_TOOLBAR_ROOT_ID,
  PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID
} from '../../data/repositories/BookmarkRepositoryCore';
import { BookmarkRepository } from '../../data/repositories/BrowserRepositories';

export interface BrowserDesktopBookmarkBarManagerAction {
  kind: 'open_bookmarks';
}

export interface BrowserDesktopBookmarkBarOpenAction {
  kind: 'open_bookmark';
  node: BookmarkNode;
  target: 'current' | 'new' | 'background';
}

export type BrowserDesktopBookmarkBarAction =
  BrowserDesktopBookmarkBarManagerAction | BrowserDesktopBookmarkBarOpenAction;

export interface BrowserDesktopBookmarkBarSnapshot {
  scope: BookmarkStorageScope;
  rootId: string;
  allItems: BookmarkNode[];
  visibleItems: BookmarkNode[];
  overflowItems: BookmarkNode[];
}

const BAR_LEADING_ENTRY_WIDTH_VP: number = 42;
const BAR_ITEM_MIN_WIDTH_VP: number = 84;
const BAR_ITEM_MAX_WIDTH_VP: number = 180;
const BAR_ITEM_GAP_VP: number = 2;
const BAR_OVERFLOW_ENTRY_WIDTH_VP: number = 38;
const BAR_HORIZONTAL_INSET_VP: number = 6;
const BAR_ITEM_CHROME_WIDTH_VP: number = 38;
const BAR_ITEM_TEXT_UNIT_WIDTH_VP: number = 7;
const BAR_MENU_TITLE_MAX_UNITS: number = 22;

/**
 * Projects the current privacy boundary's toolbar root into stable Large-Screen
 * chrome data. It deliberately has no ArkUI or tab-navigation responsibilities.
 */
export class BrowserDesktopBookmarkBarViewModel {
  private readonly repository: BookmarkRepository;

  constructor(repository: BookmarkRepository) {
    this.repository = repository;
  }

  async prepare(): Promise<void> {
    await this.repository.initialize();
  }

  buildSnapshot(scope: BookmarkStorageScope, availableWidthVp: number): BrowserDesktopBookmarkBarSnapshot {
    const normalizedScope: BookmarkStorageScope = scope === 'private' ? 'private' : 'regular';
    const rootId = normalizedScope === 'private' ? PRIVATE_BOOKMARK_TOOLBAR_ROOT_ID : BOOKMARK_TOOLBAR_ROOT_ID;
    const allItems = this.repository.listChildren(rootId, normalizedScope)
      .filter((node: BookmarkNode): boolean => node.sync.deletedAt === undefined);
    const available = Math.max(0, Math.floor(availableWidthVp));
    const contentWidth = Math.max(0, available - BAR_HORIZONTAL_INSET_VP * 2);
    const visibleItems = this.resolveVisibleItems(allItems, contentWidth);
    const overflowItems = allItems.slice(visibleItems.length);
    return {
      scope: normalizedScope,
      rootId: rootId,
      allItems: allItems,
      visibleItems: visibleItems,
      overflowItems: overflowItems
    };
  }

  resolveItemWidth(node: BookmarkNode): number {
    const title = node.title.trim();
    let titleUnits = 0;
    for (let index = 0; index < title.length; index += 1) {
      titleUnits += this.resolveTitleCharacterUnits(title.charAt(index));
    }
    const estimatedWidth = BAR_ITEM_CHROME_WIDTH_VP + Math.max(1, titleUnits) * BAR_ITEM_TEXT_UNIT_WIDTH_VP;
    return Math.min(BAR_ITEM_MAX_WIDTH_VP, Math.max(BAR_ITEM_MIN_WIDTH_VP, estimatedWidth));
  }

  resolveMenuTitle(title: string): string {
    const normalized = title.trim();
    let units = 0;
    for (let index = 0; index < normalized.length; index += 1) {
      units += this.resolveTitleCharacterUnits(normalized.charAt(index));
    }
    if (units <= BAR_MENU_TITLE_MAX_UNITS) {
      return normalized;
    }

    let visible = '';
    units = 0;
    for (let index = 0; index < normalized.length; index += 1) {
      const character = normalized.charAt(index);
      const characterUnits = this.resolveTitleCharacterUnits(character);
      if (units + characterUnits + 3 > BAR_MENU_TITLE_MAX_UNITS) {
        break;
      }
      visible += character;
      units += characterUnits;
    }
    return `${visible}...`;
  }

  private resolveVisibleItems(allItems: BookmarkNode[], contentWidth: number): BookmarkNode[] {
    let allItemsWidth = BAR_LEADING_ENTRY_WIDTH_VP;
    allItems.forEach((node: BookmarkNode): void => {
      allItemsWidth += BAR_ITEM_GAP_VP + this.resolveItemWidth(node);
    });
    if (allItemsWidth <= contentWidth) {
      return allItems;
    }

    const visibleItems: BookmarkNode[] = [];
    let usedWidth = BAR_LEADING_ENTRY_WIDTH_VP + BAR_ITEM_GAP_VP + BAR_OVERFLOW_ENTRY_WIDTH_VP;
    for (let index = 0; index < allItems.length; index += 1) {
      const node = allItems[index];
      const nextWidth = usedWidth + BAR_ITEM_GAP_VP + this.resolveItemWidth(node);
      if (nextWidth > contentWidth) {
        break;
      }
      visibleItems.push(node);
      usedWidth = nextWidth;
    }
    return visibleItems;
  }

  private resolveTitleCharacterUnits(character: string): number {
    const codePoint = character.charCodeAt(0);
    const isWideCharacter = (codePoint >= 0x2e80 && codePoint <= 0x9fff) ||
      (codePoint >= 0xac00 && codePoint <= 0xd7af) ||
      (codePoint >= 0xf900 && codePoint <= 0xfaff) ||
      (codePoint >= 0xff01 && codePoint <= 0xff60);
    return isWideCharacter ? 2 : 1;
  }
}

export interface DesktopBookmarkBarLayout {
  heightVp: number;
  leadingEntryWidthVp: number;
  itemGapVp: number;
  overflowEntryWidthVp: number;
  horizontalInsetVp: number;
}

export const DESKTOP_BOOKMARK_BAR_LAYOUT: DesktopBookmarkBarLayout = {
  heightVp: 36,
  leadingEntryWidthVp: BAR_LEADING_ENTRY_WIDTH_VP,
  itemGapVp: BAR_ITEM_GAP_VP,
  overflowEntryWidthVp: BAR_OVERFLOW_ENTRY_WIDTH_VP,
  horizontalInsetVp: BAR_HORIZONTAL_INSET_VP
};
