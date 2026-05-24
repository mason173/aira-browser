import { useMemo, type ReactNode } from 'react';
import { getStrictContext } from '@/lib/get-strict-context';
import type {
  LeafTabSyncActions,
  LeafTabSyncConfigState,
  LeafTabSyncFacade,
  LeafTabSyncMeta,
  LeafTabSyncStatusState,
} from '@/features/sync/app/LeafTabSyncContracts';

export type {
  LeafTabSyncActions,
  LeafTabSyncConfigState,
  LeafTabSyncFacade,
  LeafTabSyncMeta,
  LeafTabSyncStatusState,
} from '@/features/sync/app/LeafTabSyncContracts';

const [LeafTabSyncControllerProvider, useLeafTabSyncContext] =
  getStrictContext<LeafTabSyncFacade>('LeafTabSyncProvider');
const [LeafTabSyncStatusProvider, useLeafTabSyncStatusContext] =
  getStrictContext<LeafTabSyncStatusState>('LeafTabSyncStatusProvider');
const [LeafTabSyncConfigProvider, useLeafTabSyncConfigContext] =
  getStrictContext<LeafTabSyncConfigState>('LeafTabSyncConfigProvider');
const [LeafTabSyncActionsProvider, useLeafTabSyncActionsContext] =
  getStrictContext<LeafTabSyncActions>('LeafTabSyncActionsProvider');
const [LeafTabSyncMetaProvider, useLeafTabSyncMetaContext] =
  getStrictContext<LeafTabSyncMeta>('LeafTabSyncMetaProvider');

export {
  useLeafTabSyncContext,
  useLeafTabSyncStatusContext,
  useLeafTabSyncConfigContext,
  useLeafTabSyncActionsContext,
  useLeafTabSyncMetaContext,
};

export function LeafTabSyncProvider({
  value,
  children,
}: {
  value: LeafTabSyncFacade;
  children: ReactNode;
}) {
  const status = useMemo<LeafTabSyncStatusState>(() => ({
    leafTabSyncState: value.state.leafTabSyncState,
    topNavSyncStatus: value.state.topNavSyncStatus,
  }), [
    value.state.leafTabSyncState,
    value.state.topNavSyncStatus,
  ]);

  const config = useMemo<LeafTabSyncConfigState>(() => ({
    leafTabSyncAnalysis: value.state.leafTabSyncAnalysis,
    leafTabSyncHasConfig: value.state.leafTabSyncHasConfig,
    leafTabSyncReady: value.state.leafTabSyncReady,
    leafTabSyncLastResult: value.state.leafTabSyncLastResult,
    leafTabSyncWebdavConfig: value.state.leafTabSyncWebdavConfig,
    webdavSyncBookmarksEnabled: value.state.webdavSyncBookmarksEnabled,
    leafTabWebdavConfigured: value.state.leafTabWebdavConfigured,
    leafTabWebdavEnabled: value.state.leafTabWebdavEnabled,
    leafTabWebdavProfileLabel: value.state.leafTabWebdavProfileLabel,
    leafTabWebdavLastSyncLabel: value.state.leafTabWebdavLastSyncLabel,
    leafTabWebdavNextSyncLabel: value.state.leafTabWebdavNextSyncLabel,
    leafTabBookmarkSyncScopeLabel: value.state.leafTabBookmarkSyncScopeLabel,
  }), [
    value.state.leafTabSyncAnalysis,
    value.state.leafTabSyncHasConfig,
    value.state.leafTabSyncReady,
    value.state.leafTabSyncLastResult,
    value.state.leafTabSyncWebdavConfig,
    value.state.webdavSyncBookmarksEnabled,
    value.state.leafTabWebdavConfigured,
    value.state.leafTabWebdavEnabled,
    value.state.leafTabWebdavProfileLabel,
    value.state.leafTabWebdavLastSyncLabel,
    value.state.leafTabWebdavNextSyncLabel,
    value.state.leafTabBookmarkSyncScopeLabel,
  ]);

  const actions = useMemo<LeafTabSyncActions>(() => value.actions, [value.actions]);
  const meta = useMemo<LeafTabSyncMeta>(() => value.meta, [value.meta]);

  return (
    <LeafTabSyncControllerProvider value={value}>
      <LeafTabSyncStatusProvider value={status}>
        <LeafTabSyncConfigProvider value={config}>
          <LeafTabSyncActionsProvider value={actions}>
            <LeafTabSyncMetaProvider value={meta}>
              {children}
            </LeafTabSyncMetaProvider>
          </LeafTabSyncActionsProvider>
        </LeafTabSyncConfigProvider>
      </LeafTabSyncStatusProvider>
    </LeafTabSyncControllerProvider>
  );
}
