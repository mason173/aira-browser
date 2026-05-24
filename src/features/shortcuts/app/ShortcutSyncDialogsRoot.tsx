import { Suspense, lazy, memo, useEffect, useState } from 'react';

const ShortcutSyncDialogsContent = lazy(() => import('@/features/shortcuts/app/ShortcutSyncDialogsContent'));

function useKeepMountedAfterFirstOpen(open: boolean) {
  const [hasOpened, setHasOpened] = useState(open);

  useEffect(() => {
    if (open) {
      setHasOpened(true);
    }
  }, [open]);

  return hasOpened || open;
}

export type ShortcutSyncDialogsRootProps = {
  leafTabSyncDialogOpen: boolean;
  setLeafTabSyncDialogOpen: (open: boolean) => void;
  setSyncConfigBackTarget: (target: 'settings' | 'sync-center') => void;
};

export const ShortcutSyncDialogsRoot = memo(function ShortcutSyncDialogsRoot({
  leafTabSyncDialogOpen,
  setLeafTabSyncDialogOpen,
  setSyncConfigBackTarget,
}: ShortcutSyncDialogsRootProps) {
  const shouldMountSyncDialogs = useKeepMountedAfterFirstOpen(leafTabSyncDialogOpen);

  if (!shouldMountSyncDialogs) {
    return null;
  }

  return (
    <Suspense fallback={null}>
      <ShortcutSyncDialogsContent
        leafTabSyncDialogOpen={leafTabSyncDialogOpen}
        setLeafTabSyncDialogOpen={setLeafTabSyncDialogOpen}
        setSyncConfigBackTarget={setSyncConfigBackTarget}
      />
    </Suspense>
  );
});

ShortcutSyncDialogsRoot.displayName = 'ShortcutSyncDialogsRoot';
