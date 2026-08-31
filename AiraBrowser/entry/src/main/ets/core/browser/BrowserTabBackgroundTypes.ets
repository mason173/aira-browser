import { TabDiscardReason, TabRestoreReason, TabRuntimeState } from '../../common/models/BrowserModels';
import { BrowserTabState } from '../tabs/TabManager';
import { WebTabRuntimeRecord } from '../web/WebTabRuntime';

export const BROWSER_TAB_BACKGROUND_POLICY_VERSION: string = 'background-tab-lifecycle-v1';

export type BrowserTabBackgroundTrigger =
  'tab_switch' |
  'tab_created' |
  'tab_closed' |
  'background_tab_created' |
  'overview_open' |
  'overview_close' |
  'cooling_tick' |
  'window_active' |
  'window_hidden' |
  'app_foreground' |
  'app_background' |
  'memory_pressure' |
  'page_signal_changed' |
  'manual_discard' |
  'session_sync';

export type BrowserTabWindowVisibility =
  'active' |
  'visible' |
  'showing' |
  'hidden';

export type BrowserTabAppLifecycleState =
  'foreground' |
  'background';

export type BrowserSystemMemoryPressureLevel =
  'normal' |
  'moderate' |
  'low' |
  'critical';

export type BrowserTabPageBehaviorKind =
  'screen_capture' |
  'media' |
  'editing' |
  'download';

export const PAGE_BEHAVIOR_PRIORITY_SCREEN_CAPTURE: number = 104;
export const PAGE_BEHAVIOR_PRIORITY_MEDIA: number = 103;
export const PAGE_BEHAVIOR_PRIORITY_EDITING: number = 102;
export const PAGE_BEHAVIOR_PRIORITY_DOWNLOAD: number = 101;

export interface BrowserTabPageBehaviorState {
  isScreenCapture: boolean;
  isMediaPlaying: boolean;
  isUserEditing: boolean;
  isDownloading: boolean;
  updatedAt: number;
  source: string;
}

export interface BrowserTabPageBehaviorPatch {
  isScreenCapture?: boolean;
  isMediaPlaying?: boolean;
  isUserEditing?: boolean;
  isDownloading?: boolean;
  source?: string;
}

export interface BrowserTabPageBehaviorPrioritySignal {
  kind: BrowserTabPageBehaviorKind;
  priority: number;
}

export interface BrowserTabPageBehaviorPrioritySummary {
  signals: BrowserTabPageBehaviorPrioritySignal[];
  totalPriority: number;
  primaryKind: BrowserTabPageBehaviorKind | '';
}

export interface BrowserTabPageBehaviorSummary {
  screenCaptureTabIds: string[];
  mediaPlayingTabIds: string[];
  userEditingTabIds: string[];
  downloadingTabIds: string[];
  protectedTabIds: string[];
  maxBehaviorScore: number;
  maxBehaviorSignals: string;
}

export type BrowserTabDiscardIneligibilityReason =
  'missing_context' |
  'tab_missing' |
  'active_tab' |
  'protected' |
  'active_state' |
  'recent_activity_after_queue' |
  'no_longer_candidate' |
  'home_tab' |
  'already_discarded' |
  'no_preview' |
  'no_web_state' |
  'batch_limit';

export interface BrowserTabRuntimeStateCountSummary {
  active: number;
  background: number;
  backgroundHot: number;
  backgroundWarm: number;
  suspended: number;
  cold: number;
  discarded: number;
  loading: number;
  error: number;
  restoring: number;
  crashed: number;
}

export interface BrowserTabDiscardReasonCountSummary {
  retentionCold: number;
  retentionBudget: number;
  retentionStale: number;
  manualHome: number;
  controllerDetached: number;
}

export interface BrowserTabDiscardQueueSummary {
  totalCount: number;
  reasonCounts: BrowserTabDiscardReasonCountSummary;
}

export interface BrowserTabBackgroundDiscardGateSummary {
  protectedTabIds: string[];
  protectedNoWebStateCount: number;
  previewDeferredTabIds: string[];
}

export interface BrowserSystemMemoryPressureSnapshot {
  level: BrowserSystemMemoryPressureLevel;
  revision: number;
  updatedAt: number;
  source: string;
  rawLevel: number;
}

export interface BrowserTabWindowState {
  windowId: string;
  visibility: BrowserTabWindowVisibility;
  isCurrentWindow: boolean;
  appLifecycle: BrowserTabAppLifecycleState;
}

export interface BrowserTabPreviewAssetState {
  tabId: string;
  hasDisplayablePreview: boolean;
  hasPersistedImage: boolean;
  hasMemoryImage: boolean;
  capturedAt: number;
  source: string;
  failureReason: string;
}

export interface BrowserTabPreviewAssetSummary {
  totalTabCount: number;
  displayablePreviewCount: number;
  persistedImageCount: number;
  memoryImageCount: number;
  missingPreviewTabIds: string[];
}

export interface BrowserTabDiscardTask {
  tabId: string;
  reason: TabDiscardReason;
  priority: number;
  queuedAt: number;
}

export interface BrowserTabWebStateRestoreCandidate {
  tabId: string;
  reason: TabRestoreReason;
  priority: number;
  queuedAt: number;
}

export interface BrowserTabBackgroundManagerInput {
  windowId: string;
  activeTabId: string;
  tabs: BrowserTabState[];
  runtimes: WebTabRuntimeRecord[];
  trigger: BrowserTabBackgroundTrigger;
  windowState: BrowserTabWindowState;
  activeDownloadCount: number;
  explicitProtectionReasonsByTabId: Record<string, string>;
  pageBehaviorByTabId: Record<string, BrowserTabPageBehaviorState>;
  protectedReasonsByTabId: Record<string, string>;
  previewAssetsByTabId: Record<string, BrowserTabPreviewAssetState>;
  systemMemoryPressure: BrowserSystemMemoryPressureSnapshot;
  now: number;
}

export interface BrowserTabBackgroundPlan {
  activeTabId: string;
  protectedTabIds: string[];
  liveTabIds: string[];
  hotTabIds: string[];
  warmTabIds: string[];
  suspendedTabIds: string[];
  discardQueue: BrowserTabDiscardTask[];
  webStateRestoreCandidates: BrowserTabWebStateRestoreCandidate[];
  runtimeStatePatchByTabId: Record<string, TabRuntimeState>;
  reasonsByTabId: Record<string, string>;
  pageBehaviorSummary: BrowserTabPageBehaviorSummary;
  previewAssetSummary: BrowserTabPreviewAssetSummary;
  discardGateSummary: BrowserTabBackgroundDiscardGateSummary;
  systemMemoryPressureLevel: BrowserSystemMemoryPressureLevel;
}
