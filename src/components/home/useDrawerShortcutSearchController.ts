import {
  useCallback,
  useDeferredValue,
  useEffect,
  useMemo,
  useRef,
  useState,
  type MouseEvent as ReactMouseEvent,
} from 'react';
import type { RootShortcutGridProps } from '@/features/shortcuts/components/RootShortcutGrid';
import type { Shortcut } from '@/types';
import {
  buildDrawerShortcutEntries,
  searchDrawerShortcutEntries,
} from '@/components/home/drawerShortcutFiltering';

type UseDrawerShortcutSearchControllerParams = {
  enabled: boolean;
  interactionDisabled?: boolean;
  shortcutGridProps: RootShortcutGridProps;
  onFolderChildShortcutContextMenu?: (
    event: ReactMouseEvent<HTMLDivElement>,
    folderId: string,
    shortcut: Shortcut,
  ) => void;
};

export function useDrawerShortcutSearchController({
  enabled,
  interactionDisabled = false,
  shortcutGridProps,
  onFolderChildShortcutContextMenu,
}: UseDrawerShortcutSearchControllerParams) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [searchValue, setSearchValue] = useState('');
  const deferredShortcutSearchValue = useDeferredValue(searchValue);
  const normalizedShortcutSearchQuery = deferredShortcutSearchValue.trim().toLocaleLowerCase();
  const active = enabled && !interactionDisabled;
  const searchingShortcuts = active && normalizedShortcutSearchQuery.length > 0;
  const drawerShortcutEntries = useMemo(
    () => (active ? buildDrawerShortcutEntries(shortcutGridProps.shortcuts) : []),
    [active, shortcutGridProps.shortcuts],
  );

  const searchedShortcutEntries = useMemo(() => {
    if (!searchingShortcuts) return drawerShortcutEntries;
    return searchDrawerShortcutEntries(drawerShortcutEntries, normalizedShortcutSearchQuery);
  }, [drawerShortcutEntries, normalizedShortcutSearchQuery, searchingShortcuts]);

  const filteredShortcutEntries = searchedShortcutEntries;
  const filteredShortcuts = useMemo(
    () => filteredShortcutEntries.map((entry) => entry.shortcut),
    [filteredShortcutEntries],
  );
  const showShortcutSearchEmptyState = searchingShortcuts && filteredShortcuts.length === 0;

  const handleFilteredShortcutContextMenu = useCallback((
    event: ReactMouseEvent<HTMLDivElement>,
    shortcutIndex: number,
    shortcut: Shortcut,
  ) => {
    const entry = filteredShortcutEntries[shortcutIndex];
    if (!entry) return;

    if (entry.parentFolderId) {
      if (onFolderChildShortcutContextMenu) {
        onFolderChildShortcutContextMenu(event, entry.parentFolderId, shortcut);
        return;
      }
      event.preventDefault();
      event.stopPropagation();
      return;
    }

    shortcutGridProps.onShortcutContextMenu(event, entry.rootIndex, shortcut);
  }, [filteredShortcutEntries, onFolderChildShortcutContextMenu, shortcutGridProps]);

  const filteredShortcutGridProps = useMemo(() => (
    searchingShortcuts
      ? {
          ...shortcutGridProps,
          shortcuts: filteredShortcuts,
          disableReorderAnimation: true,
          onShortcutContextMenu: handleFilteredShortcutContextMenu,
          onShortcutReorder: () => {},
          onShortcutDropIntent: undefined,
          onGridContextMenu: () => {},
          onDragStart: undefined,
          onDragEnd: undefined,
          selectionMode: false,
          selectedShortcutIndexes: undefined,
          onToggleShortcutSelection: undefined,
          externalDragSession: null,
          onExternalDragSessionConsumed: undefined,
        }
      : shortcutGridProps
  ), [
    filteredShortcuts,
    handleFilteredShortcutContextMenu,
    searchingShortcuts,
    shortcutGridProps,
  ]);

  useEffect(() => {
    if (enabled) return;
    setSearchValue('');
    inputRef.current?.blur();
  }, [enabled]);

  useEffect(() => {
    if (!interactionDisabled) return;
    inputRef.current?.blur();
  }, [interactionDisabled]);

  return {
    inputRef,
    searchValue,
    setSearchValue,
    normalizedShortcutSearchQuery,
    filteredShortcutGridProps,
    showShortcutSearchEmptyState,
  };
}
