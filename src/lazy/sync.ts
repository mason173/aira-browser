import { useEffect, useState } from 'react';

export type LeafTabSyncRuntimeModule = typeof import('@/sync/leaftab/runtime');

let syncRuntimePromise: Promise<LeafTabSyncRuntimeModule> | null = null;

export const importLeafTabSyncRuntime = () => {
  if (!syncRuntimePromise) {
    syncRuntimePromise = import('@/sync/leaftab/runtime');
  }
  return syncRuntimePromise;
};

export function useLeafTabSyncRuntime(enabled: boolean) {
  const [runtime, setRuntime] = useState<LeafTabSyncRuntimeModule | null>(null);

  useEffect(() => {
    if (!enabled) return;

    let disposed = false;
    void importLeafTabSyncRuntime().then((loaded) => {
      if (!disposed) {
        setRuntime(loaded);
      }
    });

    return () => {
      disposed = true;
    };
  }, [enabled]);

  return runtime;
}
