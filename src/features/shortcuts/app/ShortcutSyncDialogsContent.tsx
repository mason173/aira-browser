import { Suspense, lazy, memo, useEffect, useState } from 'react';
import {
  useLeafTabSyncActionsContext,
  useLeafTabSyncConfigContext,
  useLeafTabSyncStatusContext,
} from '@/features/sync/app/LeafTabSyncContext';

const LazyLeafTabSyncDialog = lazy(() => import('@/components/sync/LeafTabSyncDialog').then((module) => ({
  default: module.LeafTabSyncDialog,
})));

function useKeepMountedAfterFirstOpen(open: boolean) {
  const [hasOpened, setHasOpened] = useState(open);

  useEffect(() => {
    if (open) {
      setHasOpened(true);
    }
  }, [open]);

  return hasOpened || open;
}

export type ShortcutSyncDialogsContentProps = {
  leafTabSyncDialogOpen: boolean;
  setLeafTabSyncDialogOpen: (open: boolean) => void;
  setSyncConfigBackTarget: (target: 'settings' | 'sync-center') => void;
};

const ShortcutSyncDialogsContent = memo(function ShortcutSyncDialogsContent({
  leafTabSyncDialogOpen,
  setLeafTabSyncDialogOpen,
  setSyncConfigBackTarget,
}: ShortcutSyncDialogsContentProps) {
  const syncStatusState = useLeafTabSyncStatusContext();
  const syncConfigState = useLeafTabSyncConfigContext();
  const syncActions = useLeafTabSyncActionsContext();
  const shouldMountLeafTabSyncDialog = useKeepMountedAfterFirstOpen(leafTabSyncDialogOpen);

  const leafTabSyncDialogProps = {
    open: leafTabSyncDialogOpen,
    onOpenChange: syncActions.handleLeafTabSyncDialogOpenChange,
    webdavAnalysis: syncConfigState.leafTabSyncAnalysis,
    syncState: syncStatusState.leafTabSyncState,
    ready: syncConfigState.leafTabSyncReady,
    hasConfig: syncConfigState.leafTabSyncHasConfig,
    busy: syncStatusState.leafTabSyncState.status === 'syncing',
    bookmarkScopeLabel: syncConfigState.leafTabBookmarkSyncScopeLabel,
    summaryText: syncConfigState.leafTabSyncLastResult?.summaryText || '',
    webdavConfigured: syncConfigState.leafTabWebdavConfigured,
    webdavEnabled: syncConfigState.leafTabWebdavEnabled,
    webdavSyncBookmarksEnabled: syncConfigState.webdavSyncBookmarksEnabled,
    webdavProfileLabel: syncConfigState.leafTabWebdavProfileLabel,
    webdavUrlLabel: syncConfigState.leafTabSyncWebdavConfig?.url || '',
    webdavLastSyncLabel: syncConfigState.leafTabWebdavLastSyncLabel,
    webdavNextSyncLabel: syncConfigState.leafTabWebdavNextSyncLabel,
    onSyncNow: () => {
      setSyncConfigBackTarget('sync-center');
      setLeafTabSyncDialogOpen(false);
      void syncActions.handleWebdavSyncNowFromCenter();
    },
    onOpenConfig: () => {
      syncActions.handleOpenWebdavConfigFromSyncCenter();
    },
    onOpenSetupConfig: () => {
      syncActions.handleOpenWebdavConfigFromSyncCenter({
        showConnectionFields: true,
        enableAfterSave: true,
      });
    },
    onWebdavRepairPull: () => {
      void syncActions.handleWebdavRepairFromCenter('pull-remote');
    },
    onWebdavRepairPush: () => {
      void syncActions.handleWebdavRepairFromCenter('push-local');
    },
  };

  return (
    shouldMountLeafTabSyncDialog ? (
      <Suspense fallback={null}>
        <LazyLeafTabSyncDialog {...leafTabSyncDialogProps} />
      </Suspense>
    ) : null
  );
});

export default ShortcutSyncDialogsContent;
