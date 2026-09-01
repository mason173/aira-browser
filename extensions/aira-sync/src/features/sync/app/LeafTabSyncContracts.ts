import type {
  LeafTabSyncDataSummary,
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
} from '@/sync/leaftab/engine';
import type {
  LeafTabPendingBookmarkConflict,
  LeafTabSyncRemoteKind,
} from '@/sync/leaftab/source';
import type { AiraDesktopSyncStatus } from '@/features/sync/bookmarks/desktopSyncEligibility';

export type {
  LeafTabPendingBookmarkConflict,
  LeafTabSyncRemoteKind,
} from '@/sync/leaftab/source';

export type LeafTabTopNavSyncStatus = 'idle' | 'syncing' | 'error' | 'conflict';

export type LeafTabSyncProgressState = {
  open: boolean;
  inProgress: boolean;
  title: string;
  detail: string;
  progress: number;
  remoteKind: LeafTabSyncRemoteKind | null;
  latestProgress: LeafTabSyncEngineProgress | null;
};

export type LeafTabSyncState = {
  topNavSyncStatus: LeafTabTopNavSyncStatus;
  leafTabSyncProgress: LeafTabSyncProgressState;
  leafTabPendingBookmarkConflict: LeafTabPendingBookmarkConflict | null;
  leafTabSyncHasConfig: boolean;
  leafTabSyncLastResult: LeafTabSyncEngineResult | null;
  leafTabLocalSummary: LeafTabSyncDataSummary | null;
  leafTabRemoteSummary: LeafTabSyncDataSummary | null;
  leafTabSummaryLoading: boolean;
  leafTabWebdavConfigured: boolean;
  leafTabWebdavProfileLabel: string;
  leafTabWebdavLastSyncLabel: string;
  leafTabPersonalServerConfigured: boolean;
  leafTabPersonalServerProfileLabel: string;
  leafTabPersonalServerLastSyncLabel: string;
  leafTabCloudLoggedIn: boolean;
  leafTabCloudSyncEnabled: boolean;
  leafTabCloudSyncStatus: AiraDesktopSyncStatus;
  leafTabCloudLastSyncLabel: string;
  leafTabSelectedSyncSource: LeafTabSyncRemoteKind | null;
  leafTabAutoSyncLastProbeLabel: string;
  leafTabAutoSyncNextProbeLabel: string;
  leafTabAutoSyncError: string;
};

export type LeafTabSyncActions = {
  handleSelectSyncSource: (remoteKind: LeafTabSyncRemoteKind) => Promise<boolean>;
  handleSaveAndSelectWebdav: (candidate: {
    profileName: string;
    url: string;
    username: string;
    password: string;
  }) => Promise<boolean>;
  handleActiveSyncNowFromCenter: () => Promise<boolean>;
  handleDismissSyncProgress: () => void;
  handleResolveBookmarkConflict: (choice: 'computer' | 'current-source') => Promise<boolean>;
};

export type LeafTabSyncFacade = {
  state: LeafTabSyncState;
  actions: LeafTabSyncActions;
};
