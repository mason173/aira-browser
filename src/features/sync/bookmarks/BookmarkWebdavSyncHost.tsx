import { memo, useEffect, useMemo } from 'react';
import { ShortcutSyncDialogsRoot } from '@/features/shortcuts/app/ShortcutSyncDialogsRoot';
import { LeafTabSyncProvider } from '@/features/sync/app/LeafTabSyncContext';
import { useLeafTabSyncRuntimeController } from '@/features/sync/bookmarks/useBookmarkWebdavSyncRuntimeController';
import type { WebdavConfigDialogProps } from '@/components/WebdavConfigDialog';
import type { LeafTabDangerousSyncDialogState } from '@/features/sync/app/LeafTabSyncContracts';

export type BookmarkWebdavSyncHostProps = {
  leafTabSyncDialogOpen: boolean;
  webdavDialogOpen: boolean;
  webdavEnableAfterConfigSave: boolean;
  webdavShowConnectionFields: boolean;
  syncConfigBackTarget: 'settings' | 'sync-center';
  setLeafTabSyncDialogOpen: (open: boolean) => void;
  setWebdavDialogOpen: (open: boolean) => void;
  setWebdavEnableAfterConfigSave: (open: boolean) => void;
  setWebdavShowConnectionFields: (open: boolean) => void;
  setSyncConfigBackTarget: (target: 'settings' | 'sync-center') => void;
  setSettingsOpen: (open: boolean) => void;
  setConfirmDisableWebdavSyncOpen: (open: boolean) => void;
  isDragging?: boolean;
  onWebdavConfigDialogPropsChange: (props: WebdavConfigDialogProps) => void;
  onDangerousSyncDialogStateChange: (state: LeafTabDangerousSyncDialogState | null) => void;
  onDisableWebdavSyncChange: (handler: (() => void) | null) => void;
};

export const BookmarkWebdavSyncHost = memo(function BookmarkWebdavSyncHost({
  leafTabSyncDialogOpen,
  webdavDialogOpen,
  webdavEnableAfterConfigSave,
  webdavShowConnectionFields,
  syncConfigBackTarget,
  setLeafTabSyncDialogOpen,
  setWebdavDialogOpen,
  setWebdavEnableAfterConfigSave,
  setWebdavShowConnectionFields,
  setSyncConfigBackTarget,
  setSettingsOpen,
  setConfirmDisableWebdavSyncOpen,
  isDragging = false,
  onWebdavConfigDialogPropsChange,
  onDangerousSyncDialogStateChange,
  onDisableWebdavSyncChange,
}: BookmarkWebdavSyncHostProps) {
  const controller = useLeafTabSyncRuntimeController({
    setWebdavDialogOpen,
    setLeafTabSyncDialogOpen,
    leafTabSyncDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
    setSyncConfigBackTarget,
    isDragging,
  });

  const webdavConfigDialogProps = useMemo<WebdavConfigDialogProps>(() => ({
    open: webdavDialogOpen,
    onBackToParent: () => {
      setWebdavDialogOpen(false);
      if (syncConfigBackTarget === 'sync-center') {
        setLeafTabSyncDialogOpen(true);
        return;
      }
      setSettingsOpen(true);
    },
    onOpenChange: (open: boolean) => {
      setWebdavDialogOpen(open);
      if (!open) {
        setWebdavEnableAfterConfigSave(false);
        setWebdavShowConnectionFields(false);
      }
    },
    enableAfterSave: webdavEnableAfterConfigSave,
    showConnectionFields: webdavShowConnectionFields,
    onEnableAfterSave: async () => {
      setWebdavEnableAfterConfigSave(false);
      setWebdavShowConnectionFields(false);
      await controller.actions.handleEnableWebdavSync();
    },
    onSaveSuccess: async () => {
      if (!controller.state.leafTabWebdavEnabled) return;
      if (controller.state.leafTabSyncState.status === 'syncing') return;
      await controller.actions.handleLeafTabAutoSync();
    },
    onDisableSync: async () => {
      setConfirmDisableWebdavSyncOpen(true);
    },
  }), [
    controller.actions,
    controller.state.leafTabSyncState.status,
    controller.state.leafTabWebdavEnabled,
    setConfirmDisableWebdavSyncOpen,
    setLeafTabSyncDialogOpen,
    setSettingsOpen,
    setWebdavDialogOpen,
    setWebdavEnableAfterConfigSave,
    setWebdavShowConnectionFields,
    syncConfigBackTarget,
    webdavDialogOpen,
    webdavEnableAfterConfigSave,
    webdavShowConnectionFields,
  ]);

  useEffect(() => {
    onWebdavConfigDialogPropsChange(webdavConfigDialogProps);
  }, [onWebdavConfigDialogPropsChange, webdavConfigDialogProps]);

  useEffect(() => {
    onDangerousSyncDialogStateChange(controller.state.dangerousSyncDialogState);
  }, [controller.state.dangerousSyncDialogState, onDangerousSyncDialogStateChange]);

  useEffect(() => {
    onDisableWebdavSyncChange(() => {
      void controller.actions.handleDisableWebdavSync();
    });
    return () => onDisableWebdavSyncChange(null);
  }, [controller.actions, onDisableWebdavSyncChange]);

  if (!leafTabSyncDialogOpen && !controller.state.dangerousSyncDialogState?.open) {
    return null;
  }

  return (
    <LeafTabSyncProvider value={controller}>
      <ShortcutSyncDialogsRoot
        leafTabSyncDialogOpen={leafTabSyncDialogOpen}
        setLeafTabSyncDialogOpen={setLeafTabSyncDialogOpen}
        setSyncConfigBackTarget={setSyncConfigBackTarget}
      />
    </LeafTabSyncProvider>
  );
});
