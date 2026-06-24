import type {
  LeafTabSyncAnalysis,
  LeafTabSyncEngineProgress,
  LeafTabSyncEngineResult,
  LeafTabSyncInitialChoice,
} from '@/sync/leaftab';
import type { SyncState } from '@/sync/stateMachine';
import type { WebdavConfig } from '@/types/webdav';
import type { LeafTabSyncRunnerOptionsBase } from '@/hooks/useLeafTabSyncRunner';

export type LeafTabTopNavSyncStatus = 'idle' | 'syncing' | 'error' | 'conflict';
export type LeafTabSyncRemoteKind = 'webdav' | 'aira-cloud';

export type LeafTabSyncWebdavActionOptions = LeafTabSyncRunnerOptionsBase & {
  enableAfterSuccess?: boolean;
  allowConfigPrompt?: boolean;
  remoteKind?: LeafTabSyncRemoteKind;
};

export type LeafTabInitialSyncChoiceRequest = {
  localSummary: LeafTabSyncAnalysis['localSummary'];
  remoteSummary: LeafTabSyncAnalysis['remoteSummary'];
};

export type LeafTabSyncProgressState = {
  open: boolean;
  inProgress: boolean;
  title: string;
  detail: string;
  progress: number;
  latestProgress: LeafTabSyncEngineProgress | null;
};

export type LeafTabSyncStatusState = {
  leafTabSyncState: SyncState;
  topNavSyncStatus: LeafTabTopNavSyncStatus;
};

export type LeafTabSyncConfigState = {
  leafTabSyncAnalysis: LeafTabSyncAnalysis | null;
  leafTabSyncAnalysisRemoteKind: LeafTabSyncRemoteKind | null;
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
  leafTabWebdavNextSyncLabel: string;
  leafTabBookmarkSyncScopeLabel: string;
  leafTabCloudLoggedIn: boolean;
  leafTabCloudSyncEnabled: boolean;
  leafTabCloudLastSyncLabel: string;
  leafTabCloudUserId: string;
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
  handleLeafTabAutoSync: () => Promise<boolean>;
  handleWebdavSyncNowFromCenter: () => Promise<boolean>;
  handleActiveSyncNowFromCenter: () => Promise<boolean>;
  handleDismissSyncProgress: () => void;
  handleWebdavRefreshAnalysis: () => Promise<LeafTabSyncAnalysis | null>;
  handleWebdavOverwriteFromCenter: (mode: Extract<LeafTabSyncInitialChoice, 'pull-remote' | 'push-local'>) => Promise<boolean>;
  handleCloudSyncNowFromCenter: () => Promise<boolean>;
  handleEnableCloudSync: () => Promise<boolean>;
  handleDisableCloudSync: () => Promise<void>;
  handleCloudRefreshAnalysis: () => Promise<LeafTabSyncAnalysis | null>;
  handleCloudOverwriteFromCenter: (mode: Extract<LeafTabSyncInitialChoice, 'pull-remote' | 'push-local'>) => Promise<boolean>;
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
