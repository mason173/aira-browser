import type { Shortcut } from '@/types';
import {
  buildShortcutSearchMatchIndex,
  matchesShortcutSearchQuery,
} from '@/utils/shortcutSearch';
import { getShortcutChildren, isShortcutFolder } from '@/utils/shortcutFolders';

export type DrawerShortcutEntry = {
  shortcut: Shortcut;
  rootIndex: number;
  parentFolderId: string | null;
};

export function buildDrawerShortcutEntries(shortcuts: Shortcut[]): DrawerShortcutEntry[] {
  return shortcuts.map((shortcut, rootIndex) => ({
    shortcut,
    rootIndex,
    parentFolderId: null,
  }));
}

function collectMatchingFolderChildren(
  children: readonly Shortcut[],
  rootIndex: number,
  parentFolderId: string,
  normalizedQuery: string,
): DrawerShortcutEntry[] {
  return children.flatMap((child) => {
    if (isShortcutFolder(child)) {
      return collectMatchingFolderChildren(
        getShortcutChildren(child),
        rootIndex,
        child.id,
        normalizedQuery,
      );
    }

    return matchesShortcutSearchQuery(
      buildShortcutSearchMatchIndex(child),
      normalizedQuery,
    )
      ? [{
          shortcut: child,
          rootIndex,
          parentFolderId,
        }]
      : [];
  });
}

export function searchDrawerShortcutEntries(
  entries: DrawerShortcutEntry[],
  normalizedQuery: string,
): DrawerShortcutEntry[] {
  if (!normalizedQuery) return entries;

  return entries.flatMap((entry) => {
    if (entry.parentFolderId) {
      return matchesShortcutSearchQuery(
        buildShortcutSearchMatchIndex(entry.shortcut),
        normalizedQuery,
      ) ? [entry] : [];
    }

    if (isShortcutFolder(entry.shortcut)) {
      const matchesFolderShell = matchesShortcutSearchQuery(
        buildShortcutSearchMatchIndex(entry.shortcut),
        normalizedQuery,
      );
      const matchingChildren = collectMatchingFolderChildren(
        getShortcutChildren(entry.shortcut),
        entry.rootIndex,
        entry.shortcut.id,
        normalizedQuery,
      );

      return matchesFolderShell ? [entry, ...matchingChildren] : matchingChildren;
    }

    return matchesShortcutSearchQuery(
      buildShortcutSearchMatchIndex(entry.shortcut),
      normalizedQuery,
    ) ? [entry] : [];
  });
}
