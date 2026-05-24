import { describe, expect, it } from 'vitest';
import type { Shortcut } from '@/types';
import {
  buildDrawerShortcutEntries,
  searchDrawerShortcutEntries,
} from '@/components/home/drawerShortcutFiltering';

function createShortcut(overrides: Partial<Shortcut> = {}): Shortcut {
  return {
    id: overrides.id || 'shortcut-1',
    title: overrides.title || '',
    url: overrides.url || '',
    icon: overrides.icon || '',
    kind: overrides.kind,
    children: overrides.children,
    folderDisplayMode: overrides.folderDisplayMode,
    iconRendering: overrides.iconRendering,
    iconColor: overrides.iconColor,
  };
}

describe('drawerShortcutFiltering', () => {
  it('keeps top-level shortcuts searchable by original root index', () => {
    const shortcuts = [
      createShortcut({ id: 'root-a', title: 'Apple' }),
      createShortcut({ id: 'root-b', title: 'Banana' }),
    ];

    expect(buildDrawerShortcutEntries(shortcuts)).toEqual([
      { shortcut: shortcuts[0], rootIndex: 0, parentFolderId: null },
      { shortcut: shortcuts[1], rootIndex: 1, parentFolderId: null },
    ]);
  });

  it('matches folder children by plain title or URL in drawer search', () => {
    const shortcuts = [
      createShortcut({ id: 'root-a', title: 'Apple' }),
      createShortcut({
        id: 'folder-1',
        title: '常用合集',
        kind: 'folder',
        children: [
          createShortcut({ id: 'child-wxds', title: '微信读书', url: 'https://weread.qq.com' }),
          createShortcut({ id: 'child-zh', title: '知乎', url: 'https://zhihu.com' }),
        ],
      }),
    ];

    const entries = buildDrawerShortcutEntries(shortcuts);

    expect(
      searchDrawerShortcutEntries(entries, '微信').map((entry) => entry.shortcut.id),
    ).toEqual(['child-wxds']);
    expect(
      searchDrawerShortcutEntries(entries, 'weread').map((entry) => entry.shortcut.id),
    ).toEqual(['child-wxds']);
    expect(
      searchDrawerShortcutEntries(entries, '知乎').map((entry) => entry.shortcut.id),
    ).toEqual(['child-zh']);
  });

  it('keeps folder shells searchable by their own titles', () => {
    const shortcuts = [
      createShortcut({
        id: 'folder-1',
        title: '常用合集',
        kind: 'folder',
        children: [
          createShortcut({ id: 'child-1', title: '微信', url: 'https://weixin.qq.com' }),
        ],
      }),
    ];

    expect(
      searchDrawerShortcutEntries(buildDrawerShortcutEntries(shortcuts), '常用').map((entry) => entry.shortcut.id),
    ).toEqual(['folder-1']);
  });

  it('tolerates whitespace differences when searching drawer shortcuts', () => {
    const shortcuts = [
      createShortcut({ id: 'radius', title: '图标圆角', url: 'https://leaftab.app/icon-radius' }),
    ];

    expect(
      searchDrawerShortcutEntries(buildDrawerShortcutEntries(shortcuts), '图标 圆角').map((entry) => entry.shortcut.id),
    ).toEqual(['radius']);
  });
});
