import { lazy, memo, Suspense, useEffect, type ReactNode, type RefObject } from 'react';
import { ShortcutSelectionProvider } from '@/features/shortcuts/selection/ShortcutSelectionContext';
import { useShortcutSelectionController } from '@/features/shortcuts/selection/useShortcutSelectionController';
import type { ContextMenuState, Shortcut } from '@/types';

const LazyShortcutSelectionContextMenu = lazy(() => import('@/features/shortcuts/selection/ShortcutSelectionContextMenu').then((module) => ({
  default: module.ShortcutSelectionContextMenu,
})));
const LazyShortcutSelectionToolbar = lazy(() => import('@/features/shortcuts/selection/ShortcutSelectionToolbar').then((module) => ({
  default: module.ShortcutSelectionToolbar,
})));
const LazyShortcutSelectionBulkDeleteDialog = lazy(() => import('@/features/shortcuts/selection/ShortcutSelectionBulkDeleteDialog').then((module) => ({
  default: module.ShortcutSelectionBulkDeleteDialog,
})));

export type ShortcutSelectionShellProps = {
  contextMenu: ContextMenuState | null;
  setContextMenu: (value: ContextMenuState | null) => void;
  contextMenuRef: RefObject<HTMLDivElement | null>;
  shortcuts: Shortcut[];
  onCreateShortcut: (insertIndex: number) => void;
  onEditShortcut: (shortcutIndex: number, shortcut: Shortcut) => void;
  onEditFolderShortcut: (folderId: string, shortcut: Shortcut) => void;
  onDeleteShortcut: (shortcutIndex: number, shortcut: Shortcut) => void;
  onDeleteFolderShortcut: (folderId: string, shortcut: Shortcut) => void;
  onShortcutOpen: (shortcut: Shortcut) => void;
  onDeleteSelectedShortcuts: (selectedIndexes: number[]) => void;
  onCreateFolder: (selectedIndexes: number[]) => void;
  onPinSelectedShortcuts: (selectedIndexes: number[], position: 'top' | 'bottom') => number[] | void;
  onMoveSelectedShortcutsToFolder: (selectedIndexes: number[], targetFolderId: string) => void;
  onDissolveFolder: (shortcutIndex: number, shortcut: Shortcut) => void;
  onSetFolderDisplayMode?: (shortcutIndex: number, shortcut: Shortcut, mode: 'small' | 'large') => void;
  children: ReactNode;
};

export const ShortcutSelectionShell = memo(function ShortcutSelectionShell({
  contextMenu,
  setContextMenu,
  contextMenuRef,
  shortcuts,
  onCreateShortcut,
  onEditShortcut,
  onEditFolderShortcut,
  onDeleteShortcut,
  onDeleteFolderShortcut,
  onShortcutOpen,
  onDeleteSelectedShortcuts,
  onCreateFolder,
  onPinSelectedShortcuts,
  onMoveSelectedShortcutsToFolder,
  onDissolveFolder,
  onSetFolderDisplayMode,
  children,
}: ShortcutSelectionShellProps) {
  const {
    t,
    shortcutMultiSelectMode,
    selectedShortcutIndexes,
    selectedShortcutCount,
    moveTargetFolders,
    selectedLinkCount,
    selectedFolderCount,
    pinTopDisabled,
    pinBottomDisabled,
    selectAllDisabled,
    bulkShortcutDeleteOpen,
    setBulkShortcutDeleteOpen,
    multiSelectFolderOpen,
    setMultiSelectFolderOpen,
    multiSelectFolderRef,
    clearShortcutMultiSelect,
    openShortcutMultiSelect,
    toggleShortcutMultiSelect,
    selectAllShortcuts,
    requestBulkDeleteShortcuts,
    handleConfirmBulkDeleteShortcuts,
    handlePinSelectedShortcuts,
    handleCreateFolder,
    handleMoveSelectedShortcutsToFolder,
    handleCopyShortcutLink,
  } = useShortcutSelectionController({
    setContextMenu,
    shortcuts,
    onCreateFolder,
    onDeleteSelectedShortcuts,
    onMoveSelectedShortcutsToFolder,
    onPinSelectedShortcuts,
  });

  useEffect(() => {
    if (!shortcutMultiSelectMode) return;

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      if (event.key !== 'Escape') return;
      event.preventDefault();
      event.stopPropagation();
      clearShortcutMultiSelect();
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [clearShortcutMultiSelect, shortcutMultiSelectMode]);

  useEffect(() => {
    if (!contextMenu) return;

    const handlePointerDownOutside = (event: PointerEvent) => {
      const contextMenuNode = contextMenuRef.current;
      const eventTarget = event.target;

      if (!contextMenuNode || !(eventTarget instanceof Node) || !contextMenuNode.contains(eventTarget)) {
        setContextMenu(null);
      }
    };

    document.addEventListener('pointerdown', handlePointerDownOutside, true);
    return () => document.removeEventListener('pointerdown', handlePointerDownOutside, true);
  }, [contextMenu, contextMenuRef, setContextMenu]);

  return (
    <ShortcutSelectionProvider value={{
      selectionMode: shortcutMultiSelectMode,
      selectedShortcutIndexes,
      onToggleShortcutSelection: toggleShortcutMultiSelect,
      }}>
      {children}

      {contextMenu ? (
        <Suspense fallback={null}>
          <LazyShortcutSelectionContextMenu
            t={t}
            contextMenu={contextMenu}
            contextMenuRef={contextMenuRef}
            shortcuts={shortcuts}
            selectedShortcutCount={selectedShortcutCount}
            shortcutMultiSelectMode={shortcutMultiSelectMode}
            onCreateShortcut={onCreateShortcut}
            onEditShortcut={onEditShortcut}
            onEditFolderShortcut={onEditFolderShortcut}
            onDeleteShortcut={onDeleteShortcut}
            onDeleteFolderShortcut={onDeleteFolderShortcut}
            onShortcutOpen={onShortcutOpen}
            onDissolveFolder={onDissolveFolder}
            onSetFolderDisplayMode={onSetFolderDisplayMode}
            onToggleShortcutMultiSelect={toggleShortcutMultiSelect}
            onOpenShortcutMultiSelect={openShortcutMultiSelect}
            onRequestBulkDeleteShortcuts={requestBulkDeleteShortcuts}
            onClearShortcutMultiSelect={clearShortcutMultiSelect}
            onCopyShortcutLink={handleCopyShortcutLink}
            onCloseContextMenu={() => setContextMenu(null)}
            selectedShortcutIndexes={selectedShortcutIndexes}
          />
        </Suspense>
      ) : null}

      {shortcutMultiSelectMode ? (
        <Suspense fallback={null}>
          <LazyShortcutSelectionToolbar
            t={t}
            selectedShortcutCount={selectedShortcutCount}
            moveTargetFolders={moveTargetFolders}
            selectedLinkCount={selectedLinkCount}
            selectedFolderCount={selectedFolderCount}
            pinTopDisabled={pinTopDisabled}
            pinBottomDisabled={pinBottomDisabled}
            selectAllDisabled={selectAllDisabled}
            multiSelectFolderOpen={multiSelectFolderOpen}
            setMultiSelectFolderOpen={setMultiSelectFolderOpen}
            multiSelectFolderRef={multiSelectFolderRef}
            onHandleMoveSelectedShortcutsToFolder={handleMoveSelectedShortcutsToFolder}
            onHandleCreateFolder={handleCreateFolder}
            onHandlePinSelectedShortcuts={handlePinSelectedShortcuts}
            onSelectAllShortcuts={selectAllShortcuts}
            onRequestBulkDeleteShortcuts={requestBulkDeleteShortcuts}
            onClearShortcutMultiSelect={clearShortcutMultiSelect}
          />
        </Suspense>
      ) : null}

      {bulkShortcutDeleteOpen ? (
        <Suspense fallback={null}>
          <LazyShortcutSelectionBulkDeleteDialog
            t={t}
            open={bulkShortcutDeleteOpen}
            selectedShortcutCount={selectedShortcutCount}
            onOpenChange={setBulkShortcutDeleteOpen}
            onConfirm={handleConfirmBulkDeleteShortcuts}
          />
        </Suspense>
      ) : null}
    </ShortcutSelectionProvider>
  );
});
