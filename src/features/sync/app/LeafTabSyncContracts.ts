import type {
  LeafTabSyncAnalysis,
  LeafTabSyncDataSummary,
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
  LeafTabSyncInitialChoice,
  LeafTabSyncSnapshot,
} from '@/sync/leaftab';
import type { SyncState } from '@/sync/stateMachine';
import type { WebdavConfig } from '@/types/webdav';
import type { LeafTabSyncRunnerOptionsBase } from '@/hooks/useLeafTabSyncRunner';

export type LeafTabTopNavSyncStatus = 'idle' | 'syncing' | 'error' | 'conflict';
export type LeafTabSyncRemoteKind = 'webdav' | 'aira-cloud';
export type LeafTabPrimarySyncSwitchStrategy = 'merge' | 'upload-local' | 'use-remote';

export type LeafTabRemoteAutoSyncDiagnostic = {
  lastCheckedAt: string;
  lastProvider: LeafTabSyncRemoteKind | '';
  lastBaselineCommitId: string;
  lastRemoteCommitId: string;
  lastRemoteFolders: number;
  lastRemoteItems: number;
  lastRemoteTombstones: number;
  lastHadChanges: boolean;
  lastSyncAttempted: boolean;
  lastSyncSucceeded: boolean | null;
  lastError: string;
};

export type LeafTabRemoteAutoSyncProbeResult = {
  hasChanges: boolean;
  provider?: LeafTabSyncRemoteKind;
  baselineCommitId?: string | null;
  remoteCommitId?: string | null;
  remoteFolders?: number;
  remoteItems?: number;
  remoteTombstones?: number;
  error?: string;
};

export type LeafTabSyncWebdavActionOptions = LeafTabSyncRunnerOptionsBase & {
  enableAfterSuccess?: boolean;
  allowConfigPrompt?: boolean;
  remoteKind?: LeafTabSyncRemoteKind;
  localSnapshotOverride?: LeafTabSyncSnapshot;
  webdavRequestTimeoutMs?: number;
};

export type LeafTabInitialSyncChoiceRequest = {
  localSummary: LeafTabSyncAnalysis['localSummary'];
  remoteSummary: LeafTabSyncAnalysis['remoteSummary'];
  localCheckedAt: string | null;
  remoteCheckedAt: string | null;
};

export type LeafTabSyncProgressState = {
  open: boolean;
  inProgress: boolean;
  title: string;
  detail: string;
  progress: number;
  remoteKind: LeafTabSyncRemoteKind | 'dual' | null;
  latestProgress: LeafTabSyncEngineProgress | null;
};

export type LeafTabSyncStatusState = {
  leafTabSyncState: SyncState;
  topNavSyncStatus: LeafTabTopNavSyncStatus;
};

export type LeafTabSyncConfigState = {
  leafTabSyncAnalysis: LeafTabSyncAnalysis | null;
  leafTabSyncAnalysisRemoteKind: LeafTabSyncRemoteKind | null;
  leafTabLocalBookmarkSummary: LeafTabSyncDataSummary | null;
  leafTabWebdavRemoteSummary: LeafTabSyncDataSummary | null;
  leafTabCloudRemoteSummary: LeafTabSyncDataSummary | null;
  leafTabWebdavSyncAnalysis: LeafTabSyncAnalysis | null;
  leafTabCloudSyncAnalysis: LeafTabSyncAnalysis | null;
  leafTabSyncProgress: LeafTabSyncProgressState;
  leafTabInitialSyncChoiceRequest: LeafTabInitialSyncChoiceRequest | null;
  leafTabSyncHasConfig: boolean;
  leafTabSyncReady: boolean;
  leafTabSyncLastResult: LeafTabSyncEngineResult | null;
  leafTabSyncWebdavConfig: WebdavConfig | null;
  webdavSyncBookmarksEnabled: boolean;
  leafTabWebdavConfigured: boolean;
  leafTabWebdavEnabled: boolean;
  leafTabWebdavProfileLabel: string;
  leafTabWebdavLastSyncLabel: string;
  leafTabWebdavAnalysisCheckedAt: string;
  leafTabWebdavNextSyncLabel: string;
  leafTabBookmarkSyncScopeLabel: string;
  leafTabLocalSummaryCheckedAt: string;
  leafTabCloudLoggedIn: boolean;
  leafTabCloudSyncEnabled: boolean;
  leafTabCloudLastSyncLabel: string;
  leafTabCloudAnalysisCheckedAt: string;
  leafTabCloudUserId: string;
  leafTabPrimaryRemoteKind: LeafTabSyncRemoteKind | null;
  leafTabRemoteAutoSyncDiagnostic: LeafTabRemoteAutoSyncDiagnostic | null;
};

export type LeafTabSyncState =
  & LeafTabSyncStatusState
  & LeafTabSyncConfigState;

export type LeafTabSyncActions = {
  handleLeafTabSync: (options?: LeafTabSyncWebdavActionOptions) => Promise<LeafTabSyncEngineResult | null>;
  handleEnableWebdavSync: () => Promise<void>;
  handleDisableWebdavSync: (options?: { clearLocal?: boolean }) => Promise<void>;
  handleOpenWebdavConfig: (options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => boolean;
  handleOpenWebdavConfigFromSyncCenter: (options?: { enableAfterSave?: boolean; showConnectionFields?: boolean }) => void;
  handleLeafTabSyncDialogOpenChange: (open: boolean) => void;
  handleLeafTabAutoSync: (trigger?: LeafTabRemoteAutoSyncProbeResult) => Promise<boolean>;
  handleWebdavSyncNowFromCenter: () => Promise<boolean>;
  handleActiveSyncNowFromCenter: (options?: {
    auto?: boolean;
    trigger?: LeafTabRemoteAutoSyncProbeResult;
  }) => Promise<boolean>;
  handleDismissSyncProgress: () => void;
  handleWebdavRefreshAnalysis: () => Promise<LeafTabSyncAnalysis | null>;
  handleWebdavOverwriteFromCenter: (mode: Extract<LeafTabSyncInitialChoice, 'pull-remote' | 'push-local'>) => Promise<boolean>;
  handleCloudSyncNowFromCenter: () => Promise<boolean>;
  handleEnableCloudSync: (options?: { confirmedPrimarySwitch?: boolean }) => Promise<boolean>;
  handleDisableCloudSync: () => Promise<void>;
  handleCloudRefreshAnalysis: () => Promise<LeafTabSyncAnalysis | null>;
  handleCloudOverwriteFromCenter: (mode: Extract<LeafTabSyncInitialChoice, 'pull-remote' | 'push-local'>) => Promise<boolean>;
  handleSetPrimaryRemoteKind: (
    remoteKind: LeafTabSyncRemoteKind,
    strategy: LeafTabPrimarySyncSwitchStrategy,
  ) => Promise<boolean>;
  resolveLeafTabInitialSyncChoice: (choice: LeafTabSyncInitialChoice | null) => void;
  resolveWebdavConflict: (config: WebdavConfig) => Promise<void>;
};

export type LeafTabSyncMeta = {
  resolveLeafTabSyncRootPath: (config: WebdavConfig | null) => string;
};

export type LeafTabSyncFacade = {
  state: LeafTabSyncState;
  actions: LeafTabSyncActions;
  meta: LeafTabSyncMeta;
};
