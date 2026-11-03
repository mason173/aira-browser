import { intl } from '@kit.LocalizationKit';
import { BookmarkNode } from '../../common/models/BrowserModels';
import { BookmarkSortMode } from '../../common/models/BookmarkSortModels';

/** Sorts a management view without changing the stored or synchronized order. */
export class BookmarkDisplaySortService {
  private readonly collator: intl.Collator = new intl.Collator('zh-CN-u-co-pinyin', {
    usage: 'sort', sensitivity: 'base', numeric: true
  });

  sort(nodes: BookmarkNode[], mode: BookmarkSortMode): BookmarkNode[] {
    return nodes.slice().sort((left: BookmarkNode, right: BookmarkNode): number => {
      if (left.type !== right.type) {
        return left.type === 'folder' ? -1 : 1;
      }
      let compared: number = 0;
      if (mode === 'newest' || mode === 'oldest') {
        const leftCreated = Number.isFinite(left.createdAt) ? left.createdAt : 0;
        const rightCreated = Number.isFinite(right.createdAt) ? right.createdAt : 0;
        compared = mode === 'newest' ? rightCreated - leftCreated : leftCreated - rightCreated;
      } else if (mode === 'name_asc' || mode === 'name_desc') {
        compared = this.collator.compare(left.title.trim(), right.title.trim());
        if (mode === 'name_desc') {
          compared = -compared;
        }
      }
      if (compared !== 0) {
        return compared;
      }
      return left.position - right.position || (left.id < right.id ? -1 : (left.id > right.id ? 1 : 0));
    });
  }
}
