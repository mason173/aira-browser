import { useMemo, type MutableRefObject, type ReactNode } from 'react';
import { getStrictContext } from '@/lib/get-strict-context';
import type { ContextMenuState, ScenarioMode, ScenarioShortcuts, Shortcut, ShortcutDraft } from '@/types';
import type { UseShortcutStoreResult } from '@/features/shortcuts/model/types';
import type { useShortcutUiState } from '@/features/shortcuts/model/useShortcutUiState';
import type { useShortcutActions } from '@/hooks/useShortcutActions';

type ShortcutUiStateResult = ReturnType<typeof useShortcutUiState>;
type ShortcutActionsResult = ReturnType<typeof useShortcutActions>;

export type ShortcutDomainState = Pick<
  UseShortcutStoreResult,
  | 'scenarioModes'
  | 'selectedScenarioId'
  | 'scenarioShortcuts'
  | 'shortcuts'
  | 'totalShortcuts'
>;

export type ShortcutUiState = Pick<
  ShortcutUiStateResult,
  | 'contextMenu'
  | 'shortcutEditOpen'
  | 'shortcutModalMode'
  | 'shortcutDeleteOpen'
  | 'selectedShortcut'
  | 'editingTitle'
  | 'editingUrl'
  | 'currentEditScenarioId'
  | 'currentInsertIndex'
  | 'scenarioModeOpen'
  | 'scenarioCreateOpen'
  | 'scenarioEditOpen'
> & {
  isDragging: boolean;
};

export type ShortcutDomainActions = Pick<
  UseShortcutStoreResult,
  | 'setScenarioModes'
  | 'setSelectedScenarioId'
  | 'setScenarioShortcuts'
>;

export type ShortcutUiActions = Pick<
  ShortcutUiStateResult,
  | 'setContextMenu'
  | 'setShortcutEditOpen'
  | 'setShortcutModalMode'
  | 'setShortcutDeleteOpen'
  | 'setSelectedShortcut'
  | 'setEditingTitle'
  | 'setEditingUrl'
  | 'setCurrentEditScenarioId'
  | 'setCurrentInsertIndex'
  | 'setScenarioModeOpen'
  | 'setScenarioCreateOpen'
  | 'setScenarioEditOpen'
> & {
  setIsDragging: (dragging: boolean) => void;
};

export type ShortcutFeatureActions = ShortcutActionsResult;

export type ShortcutAppMeta = {
  contextMenuRef: ShortcutUiStateResult['contextMenuRef'];
  localDirtyRef: MutableRefObject<boolean>;
};

export type ShortcutAppController =
  & ShortcutDomainState
  & ShortcutUiState
  & ShortcutDomainActions
  & ShortcutUiActions
  & ShortcutFeatureActions
  & ShortcutAppMeta;

export type {
  ContextMenuState,
  ScenarioMode,
  ScenarioShortcuts,
  Shortcut,
  ShortcutDraft,
};

export type ShortcutAppContextValue = {
  state: {
    domain: ShortcutDomainState;
    ui: ShortcutUiState;
  };
  actions: {
    domain: ShortcutDomainActions;
    ui: ShortcutUiActions;
    shortcuts: ShortcutFeatureActions;
  };
  meta: ShortcutAppMeta;
};

type ShortcutDomainContextValue = {
  state: ShortcutDomainState;
  actions: ShortcutDomainActions;
};

type ShortcutUiContextValue = {
  state: ShortcutUiState;
  actions: ShortcutUiActions;
};

const [ShortcutDomainProvider, useShortcutDomainContext] =
  getStrictContext<ShortcutDomainContextValue>('ShortcutDomainProvider');
const [ShortcutUiProvider, useShortcutUiContext] =
  getStrictContext<ShortcutUiContextValue>('ShortcutUiProvider');
const [ShortcutFeatureActionsProvider, useShortcutFeatureActionsContext] =
  getStrictContext<ShortcutFeatureActions>('ShortcutFeatureActionsProvider');
const [ShortcutMetaProvider, useShortcutMetaContext] =
  getStrictContext<ShortcutAppMeta>('ShortcutMetaProvider');

export {
  useShortcutDomainContext,
  useShortcutUiContext,
  useShortcutFeatureActionsContext,
  useShortcutMetaContext,
};

export function ShortcutAppProvider({
  value,
  children,
}: {
  value: ShortcutAppController;
  children?: ReactNode;
}) {
  const domain = useMemo<ShortcutDomainContextValue>(() => ({
    state: {
      scenarioModes: value.scenarioModes,
      selectedScenarioId: value.selectedScenarioId,
      scenarioShortcuts: value.scenarioShortcuts,
      shortcuts: value.shortcuts,
      totalShortcuts: value.totalShortcuts,
    },
    actions: {
      setScenarioModes: value.setScenarioModes,
      setSelectedScenarioId: value.setSelectedScenarioId,
      setScenarioShortcuts: value.setScenarioShortcuts,
    },
  }), [
    value.scenarioModes,
    value.selectedScenarioId,
    value.scenarioShortcuts,
    value.shortcuts,
    value.totalShortcuts,
    value.setScenarioModes,
    value.setSelectedScenarioId,
    value.setScenarioShortcuts,
  ]);

  const ui = useMemo<ShortcutUiContextValue>(() => ({
    state: {
      contextMenu: value.contextMenu,
      shortcutEditOpen: value.shortcutEditOpen,
      shortcutModalMode: value.shortcutModalMode,
      shortcutDeleteOpen: value.shortcutDeleteOpen,
      selectedShortcut: value.selectedShortcut,
      editingTitle: value.editingTitle,
      editingUrl: value.editingUrl,
      isDragging: value.isDragging,
      currentEditScenarioId: value.currentEditScenarioId,
      currentInsertIndex: value.currentInsertIndex,
      scenarioModeOpen: value.scenarioModeOpen,
      scenarioCreateOpen: value.scenarioCreateOpen,
      scenarioEditOpen: value.scenarioEditOpen,
    },
    actions: {
      setContextMenu: value.setContextMenu,
      setShortcutEditOpen: value.setShortcutEditOpen,
      setShortcutModalMode: value.setShortcutModalMode,
      setShortcutDeleteOpen: value.setShortcutDeleteOpen,
      setSelectedShortcut: value.setSelectedShortcut,
      setEditingTitle: value.setEditingTitle,
      setEditingUrl: value.setEditingUrl,
      setIsDragging: value.setIsDragging,
      setCurrentEditScenarioId: value.setCurrentEditScenarioId,
      setCurrentInsertIndex: value.setCurrentInsertIndex,
      setScenarioModeOpen: value.setScenarioModeOpen,
      setScenarioCreateOpen: value.setScenarioCreateOpen,
      setScenarioEditOpen: value.setScenarioEditOpen,
    },
  }), [
    value.contextMenu,
    value.shortcutEditOpen,
    value.shortcutModalMode,
    value.shortcutDeleteOpen,
    value.selectedShortcut,
    value.editingTitle,
    value.editingUrl,
    value.isDragging,
    value.currentEditScenarioId,
    value.currentInsertIndex,
    value.scenarioModeOpen,
    value.scenarioCreateOpen,
    value.scenarioEditOpen,
    value.setContextMenu,
    value.setShortcutEditOpen,
    value.setShortcutModalMode,
    value.setShortcutDeleteOpen,
    value.setSelectedShortcut,
    value.setEditingTitle,
    value.setEditingUrl,
    value.setIsDragging,
    value.setCurrentEditScenarioId,
    value.setCurrentInsertIndex,
    value.setScenarioModeOpen,
    value.setScenarioCreateOpen,
    value.setScenarioEditOpen,
  ]);

  const shortcutActions = useMemo<ShortcutFeatureActions>(() => ({
    handleCreateScenarioMode: value.handleCreateScenarioMode,
    handleOpenEditScenarioMode: value.handleOpenEditScenarioMode,
    handleUpdateScenarioMode: value.handleUpdateScenarioMode,
    handleDeleteScenarioMode: value.handleDeleteScenarioMode,
    handleShortcutOpen: value.handleShortcutOpen,
    handleShortcutContextMenu: value.handleShortcutContextMenu,
    handleGridContextMenu: value.handleGridContextMenu,
    handleSaveShortcutEdit: value.handleSaveShortcutEdit,
    handleConfirmDeleteShortcut: value.handleConfirmDeleteShortcut,
    handleConfirmDeleteShortcuts: value.handleConfirmDeleteShortcuts,
    handleShortcutReorder: value.handleShortcutReorder,
  }), [
    value.handleCreateScenarioMode,
    value.handleOpenEditScenarioMode,
    value.handleUpdateScenarioMode,
    value.handleDeleteScenarioMode,
    value.handleShortcutOpen,
    value.handleShortcutContextMenu,
    value.handleGridContextMenu,
    value.handleSaveShortcutEdit,
    value.handleConfirmDeleteShortcut,
    value.handleConfirmDeleteShortcuts,
    value.handleShortcutReorder,
  ]);

  const meta = useMemo<ShortcutAppMeta>(() => ({
    contextMenuRef: value.contextMenuRef,
    localDirtyRef: value.localDirtyRef,
  }), [value.contextMenuRef, value.localDirtyRef]);

  return (
    <ShortcutDomainProvider value={domain}>
      <ShortcutUiProvider value={ui}>
        <ShortcutFeatureActionsProvider value={shortcutActions}>
          <ShortcutMetaProvider value={meta}>
            {children}
          </ShortcutMetaProvider>
        </ShortcutFeatureActionsProvider>
      </ShortcutUiProvider>
    </ShortcutDomainProvider>
  );
}
