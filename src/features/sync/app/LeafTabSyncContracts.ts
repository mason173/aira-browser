import type {
  LeafTabSyncAnalysis,
  LeafTabSyncEngineResult,
  LeafTabSyncInitialChoice,
} from '@/sync/leaftab';
import type { SyncState } from '@/sync/stateMachine';
import type { WebdavConfig } from '@/types/webdav';
import type { LeafTabSyncRunnerOptionsBase } from '@/hooks/useLeafTabSyncRunner';

export type LeafTabTopNavSyncStatus = 'idle' | 'syncing' | 'error' | 'conflict';

export type LeafTabSyncWebdavActionOptions = LeafTabSyncRunnerOptionsBase & {
  enableAfterSuccess?: boolean;
  allowConfigPrompt?: boolean;
};

export type LeafTabSyncStatusState = {
  leafTabSyncState: SyncState;
  topNavSyncStatus: LeafTabTopNavSyncStatus;
};

export type LeafTabSyncConfigState = {
  leafTabSyncAnalysis: LeafTabSyncAnalysis | null;
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
  handleWebdavRefreshAnalysis: () => Promise<LeafTabSyncAnalysis | null>;
  handleWebdavOverwriteFromCenter: (mode: Extract<LeafTabSyncInitialChoice, 'pull-remote' | 'push-local'>) => Promise<boolean>;
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
