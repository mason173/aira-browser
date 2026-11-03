import { BookmarkSortMode } from '../../common/models/BookmarkSortModels';

export interface BookmarkSortOptionView {
  label: ResourceStr;
  selected: boolean;
  action: () => void;
}

export function resolveBookmarkSortLabel(mode: BookmarkSortMode): ResourceStr {
  switch (mode) {
    case 'newest': return $r('app.string.bookmark_sort_newest');
    case 'oldest': return $r('app.string.bookmark_sort_oldest');
    case 'name_asc': return $r('app.string.bookmark_sort_name_asc');
    case 'name_desc': return $r('app.string.bookmark_sort_name_desc');
    default: return $r('app.string.bookmark_sort_manual');
  }
}

export function buildBookmarkSortOptions(mode: BookmarkSortMode,
  onSelect: (mode: BookmarkSortMode) => void): BookmarkSortOptionView[] {
  const modes: BookmarkSortMode[] = ['manual', 'newest', 'oldest', 'name_asc', 'name_desc'];
  return modes.map((option: BookmarkSortMode): BookmarkSortOptionView => ({
    label: resolveBookmarkSortLabel(option),
    selected: option === mode,
    action: (): void => onSelect(option)
  }));
}
