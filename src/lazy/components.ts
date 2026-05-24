import { lazyWithPageReload } from './lazyWithPageReload';

const importShortcutFolderCompactOverlay = () => import('../components/ShortcutFolderCompactOverlay');
const importShortcutFolderNameDialog = () => import('../components/ShortcutFolderNameDialog');

export const LazyShortcutFolderCompactOverlay = lazyWithPageReload(
  'shortcut-folder-compact-overlay',
  importShortcutFolderCompactOverlay,
  (module) => module.ShortcutFolderCompactOverlay,
);

export function preloadShortcutFolderCompactOverlay() {
  return importShortcutFolderCompactOverlay();
}

export const LazyShortcutFolderNameDialog = lazyWithPageReload(
  'shortcut-folder-name-dialog',
  importShortcutFolderNameDialog,
  (module) => module.ShortcutFolderNameDialog,
);
