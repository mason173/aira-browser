import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AiraSyncProviderKind,
  AiraSyncRemoteKind,
  AiraSyncSettings,
  isAiraSyncProviderEnabled,
  resolveAiraHuaweiAccountIdentity,
  resolveAiraSyncDomainRuntimeState
} from '../../common/models/AiraSyncModels';
import {
  BrowserPreferencesChangeOrigin,
  PreferencesRepository
} from '../../data/preferences/PreferencesRepository';
import { SyncExperienceStateStore } from '../../data/sync/SyncExperienceStateStore';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import {
  HistorySyncRunResult
} from '../../common/models/HistorySyncModels';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import {
  HistorySyncService,
  resolveHistorySyncProviderKind
} from '../../services/sync/HistorySyncService';
import { PersonalizationSyncService } from '../../services/sync/PersonalizationSyncService';
import { SyncService } from '../../services/sync/SyncService';
import {
  WebNetworkAvailabilityService,
  WebNetworkAvailabilitySnapshot
} from '../../services/web/WebNetworkAvailabilityService';
import {
  SyncBookmarkDomain,
  SyncBookmarkDomainRunOutcome
} from './SyncBookmarkDomain';
import {
  SyncPersonalizationDomain,
  SyncPersonalizationDomainRunOutcome
} from './SyncPersonalizationDomain';
import { SyncSettingsRefreshSignal } from './SyncSettingsRefreshSignal';

const DOMAIN = 0x0000;
const TAG = 'SyncExperienceAuto';

const BOOKMARK_AUTO_SYNC_DELAY_MS: number = 20000;
const HUAWEI_BOOKMARK_INITIALIZATION_RETRY_DELAYS_MS: number[] = [10000, 30000, 60000, 120000, 300000];
const BOOKMARK_AUTO_SYNC_FOREGROUND_DELAY_MS: number = 30000;
const BOOKMARK_NETWORK_RECOVERY_DELAY_MS: number = 1000;
const BOOKMARK_PERIODIC_SYNC_STARTUP_DELAY_MS: number = 30000;
const BOOKMARK_PERIODIC_SYNC_INTERVAL_MS: number = 180000;
export const HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS: number = 2000;
export const AUTOMATIC_DRAIN_YIELD_MS: number = 16;
const BOOKMARK_WEBDAV_PERIODIC_SYNC_INTERVAL_MS: number = 15 * 60 * 1000;
const BOOKMARK_RETRY_MAX_DELAY_MS: number = 30 * 60 * 1000;

const PERSONALIZATION_HOME_SHORTCUT_CHANGE_DEBOUNCE_MS: number = 800;
const PERSONALIZATION_LOCAL_CHANGE_DEBOUNCE_MS: number = 5000;
const PERSONALIZATION_ACCOUNT_DELAY_MS: number = 5000;
const PERSONALIZATION_FOREGROUND_RECOVERY_DELAY_MS: number = 5000;
const PERSONALIZATION_NETWORK_RECOVERY_DELAY_MS: number = 1000;
const PERSONALIZATION_MIN_SYNC_GAP_MS: number = 5 * 60 * 1000;
const PERSONALIZATION_PERIODIC_SYNC_STARTUP_DELAY_MS: number = 30000;
const PERSONALIZATION_PERIODIC_SYNC_INTERVAL_MS: number = 15 * 60 * 1000;
const PERSONALIZATION_RETRY_START_DELAY_MS: number = 20000;
const PERSONALIZATION_RETRY_MAX_DELAY_MS: number = 30 * 60 * 1000;

const HISTORY_LOCAL_CHANGE_DEBOUNCE_MS: number = 5000;
const HISTORY_FOREGROUND_DELAY_MS: number = 5000;
const HISTORY_NETWORK_RECOVERY_DELAY_MS: number = 1000;
const HISTORY_PERIODIC_STARTUP_DELAY_MS: number = 30000;
const HISTORY_PERIODIC_INTERVAL_MS: number = 3 * 60 * 1000;
const HISTORY_RETRY_START_DELAY_MS: number = 20000;
const HISTORY_RETRY_MAX_DELAY_MS: number = 30 * 60 * 1000;
const MANUAL_RECENT_SUCCESS_WINDOW_MS: number = 30 * 1000;

type SyncExperienceRunMode = 'sync' | 'backup';

type SyncExperienceBookmarkAutomaticReason =
  | 'delayed'
  | 'foreground'
  | 'local_change'
  | 'network_recovery'
  | 'periodic'
  | 'retry';

type SyncExperiencePersonalizationAutomaticReason =
  | 'account'
  | 'home_shortcuts'
  | 'foreground'
  | 'membership'
  | 'network_recovery'
  | 'periodic'
  | 'retry'
  | 'local_change';

type SyncExperienceHistoryAutomaticReason =
  | 'account'
  | 'foreground'
  | 'membership'
  | 'network_recovery'
  | 'periodic'
  | 'retry'
  | 'local_change';

export interface SyncExperienceRuntimeRunResult {
  bookmark?: SyncBookmarkDomainRunOutcome;
  personalization?: SyncPersonalizationDomainRunOutcome;
  history?: HistorySyncRunResult;
}

export interface SyncExperienceAutomaticDomainSelection {
  runBookmarks: boolean;
  runPersonalization: boolean;
  runHistory: boolean;
}

export function isHuaweiSpaceTransportWarmupBeforePeriodicFreshness(): boolean {
  return HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS > 0 &&
    HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS < BOOKMARK_PERIODIC_SYNC_STARTUP_DELAY_MS;
}

export function resolveSyncExperienceAutomaticDomainSelection(
  requested: SyncExperienceAutomaticDomainSelection,
  bookmarkAutomaticAllowed: boolean
): SyncExperienceAutomaticDomainSelection {
  return {
    runBookmarks: requested.runBookmarks && bookmarkAutomaticAllowed,
    runPersonalization: requested.runPersonalization,
    runHistory: requested.runHistory
  };
}

interface SyncExperienceAutomaticClock {
  now(): number;
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(timerId: number): void;
}

type SyncExperienceRuntimeRequestKind = 'manual' | 'automatic';
type SyncExperienceBookmarkExecutionScope = 'enabled-domain' | 'configured-provider';

interface SyncExperienceRuntimeRequest {
  kind: SyncExperienceRuntimeRequestKind;
  automaticGeneration: number;
  enqueuedAt?: number;
  mode: SyncExperienceRunMode;
  runBookmarks: boolean;
  runPersonalization: boolean;
  runHistory: boolean;
  bookmarkExecutionScope: SyncExperienceBookmarkExecutionScope;
  bookmarkReason: SyncExperienceBookmarkAutomaticReason;
  personalizationReason: SyncExperiencePersonalizationAutomaticReason;
  historyReason: SyncExperienceHistoryAutomaticReason;
  bookmarkCompletionSequenceAtEnqueue: number;
  personalizationCompletionSequenceAtEnqueue: number;
  historyCompletionSequenceAtEnqueue: number;
}

class DefaultSyncExperienceAutomaticClock implements SyncExperienceAutomaticClock {
  now(): number {
    return Date.now();
  }

  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs);
  }

  clearTimeout(timerId: number): void {
    clearTimeout(timerId);
  }
}

export class SyncExperienceAutomaticRuntime {
  private syncService: SyncService;
  private personalizationSyncService: PersonalizationSyncService;
  private syncConfigStore: AiraSyncConfigStore;
  private membershipFeature: MembershipFeature;
  private bookmarkDomain: SyncBookmarkDomain;
  private personalizationDomain: SyncPersonalizationDomain;
  private historySyncService: HistorySyncService;
  private experienceStateStore: SyncExperienceStateStore;
  private clock: SyncExperienceAutomaticClock;
  private networkAvailabilityService: WebNetworkAvailabilityService;
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal;
  private bookmarkAutomaticAllowPredicate: () => boolean;

  private executionTail: Promise<void> = Promise.resolve();
  private executionRunning: boolean = false;
  private manualBookmarkCoverageCount: number = 0;
  private manualPersonalizationCoverageCount: number = 0;
  private manualHistoryCoverageCount: number = 0;
  private bookmarkAutomaticNotBefore: number = 0;
  private personalizationAutomaticNotBefore: number = 0;
  private historyAutomaticNotBefore: number = 0;
  private automaticDrainQueued: boolean = false;
  private automaticDrainTimerId: number = -1;
  private automaticGeneration: number = 0;
  private huaweiTransportWarmupTimerId: number = -1;
  private huaweiTransportWarmupScheduled: boolean = false;
  private pendingBookmarkAutomaticRun: boolean = false;
  private pendingPersonalizationAutomaticRun: boolean = false;
  private pendingHistoryAutomaticRun: boolean = false;
  private pendingBookmarkReason: SyncExperienceBookmarkAutomaticReason = 'delayed';
  private pendingPersonalizationReason: SyncExperiencePersonalizationAutomaticReason = 'local_change';
  private pendingHistoryReason: SyncExperienceHistoryAutomaticReason = 'local_change';

  private appForeground: boolean = true;
  private bookmarkTimerId: number = -1;
  private bookmarkPeriodicTimerId: number = -1;
  private bookmarkHasPendingChanges: boolean = false;
  private bookmarkChangeRevision: number = 0;
  private bookmarkConsecutiveFailureCount: number = 0;
  private bookmarkCompletionSequence: number = 0;
  private bookmarkCompletionCoveredRevision: number = -1;
  private bookmarkCompletionProviderIdentity: string = '';
  private bookmarkCompletionResult: SyncBookmarkDomainRunOutcome | undefined = undefined;
  private bookmarkCompletionAt: number = 0;

  private personalizationTimerId: number = -1;
  private personalizationPeriodicTimerId: number = -1;
  private personalizationScheduledAt: number = 0;
  private personalizationScheduledReason: SyncExperiencePersonalizationAutomaticReason = 'local_change';
  private personalizationRepositoriesReady: boolean = false;
  private networkRecoveryStarted: boolean = false;
  private personalizationPendingAccountSync: boolean = false;
  private personalizationLastAttemptAt: number = 0;
  private personalizationConsecutiveFailureCount: number = 0;
  private personalizationChangeRevision: number = 0;
  private personalizationCompletionSequence: number = 0;
  private personalizationCompletionCoveredRevision: number = -1;
  private personalizationCompletionProviderIdentity: string = '';
  private personalizationCompletionResult: SyncPersonalizationDomainRunOutcome | undefined = undefined;
  private personalizationCompletionAt: number = 0;
  private personalizationLastObservedPlan: string = '';
  private preferencesSubscriptionKey: string = '';
  private corePreferencesFingerprint: string = '';
  private historyTimerId: number = -1;
  private historyPeriodicTimerId: number = -1;
  private historyConsecutiveFailureCount: number = 0;
  private historyChangeRevision: number = 0;
  private historyCompletionSequence: number = 0;
  private historyCompletionCoveredRevision: number = -1;
  private historyCompletionProviderIdentity: string = '';
  private historyCompletionResult: HistorySyncRunResult | undefined = undefined;
  private historyCompletionAt: number = 0;

  constructor(
    syncService: SyncService,
    personalizationSyncService: PersonalizationSyncService,
    syncConfigStore: AiraSyncConfigStore,
    membershipFeature: MembershipFeature,
    bookmarkDomain: SyncBookmarkDomain,
    personalizationDomain: SyncPersonalizationDomain,
    historySyncService: HistorySyncService,
    experienceStateStore: SyncExperienceStateStore,
    clock?: SyncExperienceAutomaticClock,
    networkAvailabilityService: WebNetworkAvailabilityService = new WebNetworkAvailabilityService(),
    syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal(),
    bookmarkAutomaticAllowPredicate: () => boolean = (): boolean => true
  ) {
    this.syncService = syncService;
    this.personalizationSyncService = personalizationSyncService;
    this.syncConfigStore = syncConfigStore;
    this.membershipFeature = membershipFeature;
    this.bookmarkDomain = bookmarkDomain;
    this.personalizationDomain = personalizationDomain;
    this.historySyncService = historySyncService;
    this.experienceStateStore = experienceStateStore;
    this.clock = clock ?? new DefaultSyncExperienceAutomaticClock();
    this.networkAvailabilityService = networkAvailabilityService;
    this.syncSettingsRefreshSignal = syncSettingsRefreshSignal;
    this.bookmarkAutomaticAllowPredicate = bookmarkAutomaticAllowPredicate;
  }

  isRunning(): boolean {
    return this.executionRunning;
  }

  runManual(mode: SyncExperienceRunMode): Promise<SyncExperienceRuntimeRunResult> {
    return this.runManualDomains(mode, true, true, mode === 'sync', 'enabled-domain');
  }

  runManualBookmarkMaintenance(): Promise<SyncExperienceRuntimeRunResult> {
    return this.runManualDomains('sync', true, false, false, 'configured-provider');
  }

  runHistoryNow(): Promise<HistorySyncRunResult> {
    return this.enqueueSerializedOperation((): Promise<HistorySyncRunResult> => this.historySyncService.runNow());
  }

  async runHistoryProviderTransitionWithinCurrentOperation(
    provider: AiraSyncProviderKind,
    currentProvider: AiraSyncRemoteKind
  ): Promise<HistorySyncRunResult | undefined> {
    if (this.experienceStateStore.getState().historySelected !== true) {
      return undefined;
    }
    const target = resolveHistorySyncProviderKind(provider);
    if (target === undefined) {
      return undefined;
    }
    const source = resolveHistorySyncProviderKind(currentProvider);
    if (source === target) {
      return undefined;
    }
    let sourceResult: HistorySyncRunResult | undefined = undefined;
    if (source !== undefined) {
      sourceResult = await this.historySyncService.runForProvider(source, 'source_transition');
      if (!sourceResult.ok) {
        return sourceResult;
      }
    }
    const targetResult = await this.historySyncService.runForProvider(target, 'target_transition');
    if (targetResult.ok) {
      const settings = this.syncConfigStore.getSettings();
      const account = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
      await this.experienceStateStore.setHistorySelected(true, account.uid);
    }
    return {
      ok: targetResult.ok,
      appliedChangeCount: (sourceResult?.appliedChangeCount ?? 0) + targetResult.appliedChangeCount,
      uploadedMutationCount: (sourceResult?.uploadedMutationCount ?? 0) + targetResult.uploadedMutationCount,
      message: targetResult.message
    };
  }

  runProviderTransition<T>(operation: () => Promise<T>): Promise<T> {
    this.invalidateQueuedAutomaticDrain();
    return this.enqueueSerializedOperation(async (): Promise<T> => {
      try {
        return await operation();
      } finally {
        this.schedulePendingAutomaticDrain();
      }
    });
  }

  private runManualDomains(
    mode: SyncExperienceRunMode,
    runBookmarks: boolean,
    runPersonalization: boolean,
    runHistory: boolean,
    bookmarkExecutionScope: SyncExperienceBookmarkExecutionScope
  ): Promise<SyncExperienceRuntimeRunResult> {
    const coversAutomaticFreshness = mode === 'sync';
    if (coversAutomaticFreshness) {
      this.beginManualCoverage(runBookmarks, runPersonalization, runHistory);
    }
    const enqueuedAt = this.clock.now();
    let completedResult: SyncExperienceRuntimeRunResult | undefined = undefined;
    return this.enqueueExecution({
      kind: 'manual',
      automaticGeneration: this.automaticGeneration,
      enqueuedAt,
      mode: mode,
      runBookmarks: runBookmarks,
      runPersonalization: runPersonalization,
      runHistory: runHistory,
      bookmarkExecutionScope: bookmarkExecutionScope,
      bookmarkReason: 'delayed',
      personalizationReason: 'local_change',
      historyReason: 'local_change',
      bookmarkCompletionSequenceAtEnqueue: this.bookmarkCompletionSequence,
      personalizationCompletionSequenceAtEnqueue: this.personalizationCompletionSequence,
      historyCompletionSequenceAtEnqueue: this.historyCompletionSequence
    }).then((result: SyncExperienceRuntimeRunResult): SyncExperienceRuntimeRunResult => {
      completedResult = result;
      return result;
    }).finally((): void => {
      if (!coversAutomaticFreshness) {
        return;
      }
      this.endManualCoverage(runBookmarks, runPersonalization, runHistory);
      this.resumeAutomaticSchedulesAfterManual(
        bookmarkExecutionScope,
        runBookmarks,
        runPersonalization,
        runHistory,
        completedResult
      );
    });
  }

  private beginManualCoverage(
    runBookmarks: boolean,
    runPersonalization: boolean,
    runHistory: boolean
  ): void {
    if (runBookmarks) {
      this.manualBookmarkCoverageCount += 1;
      this.pendingBookmarkAutomaticRun = false;
      this.cancelBookmarkTimer();
      this.cancelBookmarkPeriodicSync();
    }
    if (runPersonalization) {
      this.manualPersonalizationCoverageCount += 1;
      this.pendingPersonalizationAutomaticRun = false;
      this.cancelPersonalizationTimer();
      this.cancelPersonalizationPeriodicSync();
    }
    if (runHistory) {
      this.manualHistoryCoverageCount += 1;
      this.pendingHistoryAutomaticRun = false;
      this.cancelHistoryTimer();
      this.cancelHistoryPeriodicSync();
    }
  }

  private endManualCoverage(
    runBookmarks: boolean,
    runPersonalization: boolean,
    runHistory: boolean
  ): void {
    if (runBookmarks) {
      this.manualBookmarkCoverageCount = Math.max(0, this.manualBookmarkCoverageCount - 1);
    }
    if (runPersonalization) {
      this.manualPersonalizationCoverageCount = Math.max(0, this.manualPersonalizationCoverageCount - 1);
    }
    if (runHistory) {
      this.manualHistoryCoverageCount = Math.max(0, this.manualHistoryCoverageCount - 1);
    }
  }

  private resumeAutomaticSchedulesAfterManual(
    bookmarkExecutionScope: SyncExperienceBookmarkExecutionScope,
    runBookmarks: boolean,
    runPersonalization: boolean,
    runHistory: boolean,
    result: SyncExperienceRuntimeRunResult | undefined
  ): void {
    const now = this.clock.now();
    const bookmarkDelay = this.getActiveProviderKind() === 'webdav'
      ? BOOKMARK_WEBDAV_PERIODIC_SYNC_INTERVAL_MS
      : BOOKMARK_PERIODIC_SYNC_INTERVAL_MS;
    const bookmarkSucceeded = bookmarkExecutionScope === 'enabled-domain' && result?.bookmark?.type === 'completed';
    const personalizationSucceeded = result?.personalization?.type === 'sync-completed';
    const historySucceeded = result?.history?.ok === true;
    if (runBookmarks && bookmarkSucceeded && this.manualBookmarkCoverageCount <= 0) {
      this.bookmarkAutomaticNotBefore = now + bookmarkDelay;
    }
    if (runPersonalization && personalizationSucceeded && this.manualPersonalizationCoverageCount <= 0) {
      this.personalizationAutomaticNotBefore = now + PERSONALIZATION_PERIODIC_SYNC_INTERVAL_MS;
    }
    if (runHistory && historySucceeded && this.manualHistoryCoverageCount <= 0) {
      this.historyAutomaticNotBefore = now + HISTORY_PERIODIC_INTERVAL_MS;
    }
    if (!this.appForeground) {
      return;
    }
    if (runBookmarks && this.manualBookmarkCoverageCount <= 0 && this.isBookmarkAutomaticSyncActive()) {
      if (bookmarkSucceeded) {
        this.scheduleBookmarkPeriodicRun(bookmarkDelay);
      } else if (result?.bookmark?.type !== 'blocked') {
        this.scheduleBookmarkAutomaticRun('retry', this.resolveBookmarkDelayedRunDelayMs());
      }
    }
    if (runPersonalization && this.manualPersonalizationCoverageCount <= 0 &&
      this.personalizationRepositoriesReady && this.isPersonalizationAutomaticSyncActive()) {
      if (personalizationSucceeded) {
        this.schedulePersonalizationPeriodicRun(PERSONALIZATION_PERIODIC_SYNC_INTERVAL_MS);
      } else {
        this.schedulePersonalizationIfActive('retry', this.resolvePersonalizationRetryDelayMs());
      }
    }
    if (runHistory && this.manualHistoryCoverageCount <= 0 && this.isHistoryAutomaticSyncActive()) {
      if (historySucceeded) {
        this.scheduleHistoryPeriodicRun(HISTORY_PERIODIC_INTERVAL_MS);
      } else {
        this.scheduleHistoryIfActive('retry', this.resolveHistoryRetryDelayMs());
      }
    }
  }

  bindPreferenceChanges(preferencesRepository: PreferencesRepository): void {
    if (this.preferencesSubscriptionKey.length > 0) {
      return;
    }
    this.corePreferencesFingerprint = this.personalizationSyncService.buildCorePreferencesFingerprint();
    this.preferencesSubscriptionKey = preferencesRepository.subscribe((_preferences, _scope, origin) => {
      this.handlePreferenceChange(origin);
    });
  }

  markRepositoriesReady(): void {
    if (this.personalizationRepositoriesReady) {
      return;
    }
    this.personalizationRepositoriesReady = true;
    this.startNetworkRecovery();
    if (this.appForeground) {
      this.notifyPersonalizationForeground();
      this.schedulePersonalizationPeriodicSync();
    }
    if (this.personalizationPendingAccountSync) {
      this.personalizationPendingAccountSync = false;
      this.schedulePersonalizationIfActive('account', PERSONALIZATION_ACCOUNT_DELAY_MS);
    }
  }

  notifyAppContentReady(): void {
    this.appForeground = true;
    this.startNetworkRecovery();
    this.scheduleHuaweiSpaceTransportWarmup();
    this.runPendingBookmarksOnForeground();
    this.scheduleBookmarkPeriodicSync();
    this.notifyPersonalizationForeground();
    this.schedulePersonalizationPeriodicSync();
    this.scheduleHistoryIfActive('foreground', HISTORY_FOREGROUND_DELAY_MS);
    this.scheduleHistoryPeriodicSync();
  }

  notifyAppForeground(): void {
    this.appForeground = true;
    this.startNetworkRecovery();
    this.scheduleHuaweiSpaceTransportWarmup();
    this.runPendingBookmarksOnForeground();
    this.scheduleBookmarkPeriodicSync();
    this.notifyPersonalizationForeground();
    this.schedulePersonalizationPeriodicSync();
    this.scheduleHistoryIfActive('foreground', HISTORY_FOREGROUND_DELAY_MS);
    this.scheduleHistoryPeriodicSync();
  }

  notifyAppBackground(): void {
    this.appForeground = false;
    this.cancelHuaweiSpaceTransportWarmupTimer();
    this.cancelAutomaticDrainTimer();
    this.automaticDrainQueued = false;
    this.cancelBookmarkAutomaticSync();
    this.cancelPersonalizationAutomaticSync();
    this.cancelHistoryAutomaticSync();
  }

  async recordBookmarkMutation(changedAt: number): Promise<void> {
    this.bookmarkHasPendingChanges = true;
    this.bookmarkChangeRevision += 1;
    await this.syncService.initializeAiraSyncSettings();
    await this.syncService.markBookmarkSyncPending(changedAt > 0 ? changedAt : this.clock.now());
    if (this.isBookmarkAutomaticSyncActive()) {
      this.scheduleBookmarkLocalChangeRun();
    }
  }

  runPendingBookmarksOnForeground(): void {
    this.appForeground = true;
    void this.runPendingBookmarksOnForegroundAsync();
  }

  scheduleBookmarkPeriodicSync(): void {
    if (!this.isBookmarkAutomaticSyncActive()) {
      this.cancelBookmarkPeriodicSync();
      return;
    }
    if (this.bookmarkPeriodicTimerId >= 0) {
      return;
    }
    this.scheduleBookmarkPeriodicRun(Math.max(
      BOOKMARK_PERIODIC_SYNC_STARTUP_DELAY_MS,
      this.remainingAutomaticDelay(this.bookmarkAutomaticNotBefore)
    ));
  }

  schedulePendingBookmarkSync(): void {
    this.bookmarkHasPendingChanges = true;
    this.startNetworkRecovery();
    if (!this.isBookmarkAutomaticSyncActive()) {
      return;
    }
    this.scheduleBookmarkAutomaticRun('delayed', BOOKMARK_NETWORK_RECOVERY_DELAY_MS);
  }

  cancelBookmarkAutomaticSync(): void {
    this.cancelBookmarkTimer();
    this.cancelBookmarkPeriodicSync();
    this.pendingBookmarkAutomaticRun = false;
    this.stopNetworkRecoveryIfInactive();
  }

  notifyAccountChanged(): Promise<void> {
    this.startNetworkRecovery();
    this.scheduleHistoryIfActive('account', HISTORY_FOREGROUND_DELAY_MS);
    if (!this.personalizationRepositoriesReady) {
      this.personalizationPendingAccountSync = true;
      return Promise.resolve();
    }
    this.schedulePersonalizationIfActive('account', PERSONALIZATION_ACCOUNT_DELAY_MS);
    return Promise.resolve();
  }

  notifyPersonalizationLocalSettingsChanged(): void {
    if (!this.personalizationRepositoriesReady) {
      return;
    }
    this.personalizationChangeRevision += 1;
    this.startNetworkRecovery();
    this.schedulePersonalizationIfActive('local_change', PERSONALIZATION_LOCAL_CHANGE_DEBOUNCE_MS);
  }

  notifyHomeShortcutsChanged(): void {
    if (!this.personalizationRepositoriesReady) {
      return;
    }
    this.personalizationChangeRevision += 1;
    this.startNetworkRecovery();
    this.schedulePersonalizationIfActive(
      'home_shortcuts',
      PERSONALIZATION_HOME_SHORTCUT_CHANGE_DEBOUNCE_MS
    );
  }

  notifyHistoryLocalChanged(): void {
    this.historyChangeRevision += 1;
    this.startNetworkRecovery();
    this.scheduleHistoryIfActive('local_change', HISTORY_LOCAL_CHANGE_DEBOUNCE_MS);
  }

  notifyHistoryProviderChanged(): void {
    if (!this.isHistoryAutomaticSyncActive()) {
      this.cancelHistoryAutomaticSync();
      return;
    }
    this.startNetworkRecovery();
    this.scheduleHistoryPeriodicSync();
  }

  notifyMembershipStateChanged(): void {
    const plan = this.membershipFeature.getState().plan;
    const becamePro = plan === 'pro' && this.personalizationLastObservedPlan !== 'pro';
    this.personalizationLastObservedPlan = plan;
    if (this.isHistoryAutomaticSyncActive()) {
      this.startNetworkRecovery();
      this.scheduleHistoryIfActive('membership', HISTORY_FOREGROUND_DELAY_MS);
    } else {
      this.cancelHistoryAutomaticSync();
    }
    if (!this.isPersonalizationAutomaticSyncActive()) {
      this.cancelPersonalizationTimer();
      this.personalizationPendingAccountSync = false;
      return;
    }
    if (!this.personalizationRepositoriesReady) {
      this.personalizationPendingAccountSync = becamePro;
      return;
    }
    this.startNetworkRecovery();
    if (becamePro) {
      this.schedulePersonalizationIfActive('membership', PERSONALIZATION_ACCOUNT_DELAY_MS);
    }
  }

  cancelPersonalizationAutomaticSync(): void {
    this.cancelPersonalizationTimer();
    this.cancelPersonalizationPeriodicSync();
    this.personalizationPendingAccountSync = false;
    this.pendingPersonalizationAutomaticRun = false;
    this.stopNetworkRecoveryIfInactive();
  }

  cancelHistoryAutomaticSync(): void {
    this.cancelHistoryTimer();
    this.cancelHistoryPeriodicSync();
    this.pendingHistoryAutomaticRun = false;
    this.stopNetworkRecoveryIfInactive();
  }

  async clearHistorySelectionForWebdav(): Promise<void> {
    if (this.experienceStateStore.getState().historySelected) {
      await this.experienceStateStore.setHistorySelected(false);
    }
    this.cancelHistoryAutomaticSync();
  }

  private enqueueExecution(
    request: SyncExperienceRuntimeRequest
  ): Promise<SyncExperienceRuntimeRunResult> {
    return this.enqueueSerializedOperation(
      (): Promise<SyncExperienceRuntimeRunResult> => this.executeRequest(request)
    );
  }

  private enqueueSerializedOperation<T>(operation: () => Promise<T>): Promise<T> {
    const queued = this.executionTail.then(async (): Promise<T> => {
      this.executionRunning = true;
      try {
        return await operation();
      } finally {
        this.executionRunning = false;
        try {
          this.syncSettingsRefreshSignal.bump();
        } catch (_error) {
        }
      }
    });
    this.executionTail = queued.then(
      (): void => {},
      (_error: Error): void => {}
    );
    return queued;
  }

  private async executeRequest(
    request: SyncExperienceRuntimeRequest
  ): Promise<SyncExperienceRuntimeRunResult> {
    if (request.kind === 'automatic' && request.automaticGeneration !== this.automaticGeneration) {
      return {};
    }
    let runBookmarks = request.runBookmarks;
    let runPersonalization = request.runPersonalization;
    let runHistory = request.runHistory;
    let bookmarkReason = request.bookmarkReason;
    let personalizationReason = request.personalizationReason;
    let historyReason = request.historyReason;
    if (request.kind === 'automatic') {
      this.automaticDrainQueued = false;
      runBookmarks = this.pendingBookmarkAutomaticRun;
      runPersonalization = this.pendingPersonalizationAutomaticRun;
      runHistory = this.pendingHistoryAutomaticRun;
      bookmarkReason = this.pendingBookmarkReason;
      personalizationReason = this.pendingPersonalizationReason;
      historyReason = this.pendingHistoryReason;
      this.pendingBookmarkAutomaticRun = false;
      this.pendingPersonalizationAutomaticRun = false;
      this.pendingHistoryAutomaticRun = false;
      const selection = resolveSyncExperienceAutomaticDomainSelection({
        runBookmarks: runBookmarks,
        runPersonalization: runPersonalization,
        runHistory: runHistory
      }, this.isAutomaticBookmarkGateOpen());
      runBookmarks = selection.runBookmarks;
      runPersonalization = selection.runPersonalization;
      runHistory = selection.runHistory;
    }

    const settings = await this.syncService.initializeAiraSyncSettings();
    const result: SyncExperienceRuntimeRunResult = {};
    if (this.yieldStaleAutomaticRemainder(
      request,
      runBookmarks,
      runPersonalization,
      runHistory,
      bookmarkReason,
      personalizationReason,
      historyReason
    )) {
      return result;
    }
    const bookmarkReady = settings.bookmarkSyncEnabled === true ||
      request.bookmarkExecutionScope === 'configured-provider';
    if (runBookmarks && bookmarkReady && settings.remoteKind !== 'none') {
      this.consumeAutomaticIntentBeforeManualDomain(request, 'bookmark');
      const adoptedBookmark = this.resolveAdoptedBookmarkCompletion(request);
      const bookmarkOutcome = adoptedBookmark ?? await this.executeBookmarkDomain(
          request.mode,
          request.kind === 'automatic',
          bookmarkReason,
          request.bookmarkExecutionScope
        );
      if (bookmarkOutcome !== undefined) {
        result.bookmark = bookmarkOutcome;
      }
    }
    runBookmarks = false;
    if (this.yieldStaleAutomaticRemainder(
      request,
      runBookmarks,
      runPersonalization,
      runHistory,
      bookmarkReason,
      personalizationReason,
      historyReason
    )) {
      return result;
    }
    const refreshedSettings = this.syncConfigStore.getSettings();
    if (runPersonalization && refreshedSettings.personalizationSyncEnabled === true &&
      refreshedSettings.remoteKind !== 'none') {
      this.consumeAutomaticIntentBeforeManualDomain(request, 'personalization');
      result.personalization = this.resolveAdoptedPersonalizationCompletion(request) ??
        await this.executePersonalizationDomain(
          request.mode,
          request.kind === 'automatic',
          personalizationReason
        );
    }
    runPersonalization = false;
    if (this.yieldStaleAutomaticRemainder(
      request,
      runBookmarks,
      runPersonalization,
      runHistory,
      bookmarkReason,
      personalizationReason,
      historyReason
    )) {
      return result;
    }
    if (runHistory && request.mode === 'sync' && this.isHistoryDomainEnabled()) {
      this.consumeAutomaticIntentBeforeManualDomain(request, 'history');
      result.history = this.resolveAdoptedHistoryCompletion(request) ??
        await this.executeHistoryDomain(request.kind === 'automatic', historyReason);
    }
    return result;
  }

  private resolveAdoptedBookmarkCompletion(
    request: SyncExperienceRuntimeRequest
  ): SyncBookmarkDomainRunOutcome | undefined {
    const completedAfterRequest = this.bookmarkCompletionSequence > request.bookmarkCompletionSequenceAtEnqueue;
    const recentlyCompletedBeforeRequest = this.isRecentCompletionAvailable(request, this.bookmarkCompletionAt);
    if (request.kind !== 'manual' || request.mode !== 'sync' ||
      request.bookmarkExecutionScope !== 'enabled-domain' ||
      (!completedAfterRequest && !recentlyCompletedBeforeRequest) ||
      this.bookmarkCompletionCoveredRevision !== this.bookmarkChangeRevision ||
      this.bookmarkCompletionProviderIdentity !== this.resolveDomainProviderIdentity('bookmark') ||
      this.bookmarkCompletionResult?.type !== 'completed') {
      return undefined;
    }
    return this.bookmarkCompletionResult;
  }

  private resolveAdoptedPersonalizationCompletion(
    request: SyncExperienceRuntimeRequest
  ): SyncPersonalizationDomainRunOutcome | undefined {
    const completedAfterRequest =
      this.personalizationCompletionSequence > request.personalizationCompletionSequenceAtEnqueue;
    const recentlyCompletedBeforeRequest = this.isRecentCompletionAvailable(request, this.personalizationCompletionAt);
    if (request.kind !== 'manual' || request.mode !== 'sync' ||
      (!completedAfterRequest && !recentlyCompletedBeforeRequest) ||
      this.personalizationCompletionCoveredRevision !== this.personalizationChangeRevision ||
      this.personalizationCompletionProviderIdentity !== this.resolveDomainProviderIdentity('personalization') ||
      this.personalizationCompletionResult?.type !== 'sync-completed') {
      return undefined;
    }
    return this.personalizationCompletionResult;
  }

  private resolveAdoptedHistoryCompletion(
    request: SyncExperienceRuntimeRequest
  ): HistorySyncRunResult | undefined {
    const completedAfterRequest = this.historyCompletionSequence > request.historyCompletionSequenceAtEnqueue;
    const recentlyCompletedBeforeRequest = this.isRecentCompletionAvailable(request, this.historyCompletionAt);
    if (request.kind !== 'manual' || request.mode !== 'sync' ||
      (!completedAfterRequest && !recentlyCompletedBeforeRequest) ||
      this.historyCompletionCoveredRevision !== this.historyChangeRevision ||
      this.historyCompletionProviderIdentity !== this.resolveHistoryProviderIdentity() ||
      this.historyCompletionResult?.ok !== true) {
      return undefined;
    }
    return this.historyCompletionResult;
  }

  private isRecentCompletionAvailable(request: SyncExperienceRuntimeRequest, completedAt: number): boolean {
    const requestedAt = request.enqueuedAt ?? 0;
    return requestedAt > 0 && completedAt > 0 && requestedAt >= completedAt &&
      requestedAt - completedAt <= MANUAL_RECENT_SUCCESS_WINDOW_MS;
  }

  private consumeAutomaticIntentBeforeManualDomain(
    request: SyncExperienceRuntimeRequest,
    domain: 'bookmark' | 'personalization' | 'history'
  ): void {
    if (request.kind !== 'manual' || request.mode !== 'sync') {
      return;
    }
    if (domain === 'bookmark') {
      this.pendingBookmarkAutomaticRun = false;
      this.cancelBookmarkTimer();
      return;
    }
    if (domain === 'personalization') {
      this.pendingPersonalizationAutomaticRun = false;
      this.cancelPersonalizationTimer();
      return;
    }
    this.pendingHistoryAutomaticRun = false;
    this.cancelHistoryTimer();
  }

  private async executeBookmarkDomain(
    mode: SyncExperienceRunMode,
    automatic: boolean,
    reason: SyncExperienceBookmarkAutomaticReason,
    executionScope: SyncExperienceBookmarkExecutionScope
  ): Promise<SyncBookmarkDomainRunOutcome | undefined> {
    if (automatic && reason !== 'periodic' && !await this.hasBookmarkPendingChanges()) {
      this.stopNetworkRecoveryIfInactive();
      return undefined;
    }
    const startRevision = this.bookmarkChangeRevision;
    const providerIdentity = this.resolveDomainProviderIdentity('bookmark');
    const outcome = await this.bookmarkDomain.runImmediateSync(
      undefined,
      mode === 'backup',
      executionScope === 'configured-provider' ? 'configured-provider-maintenance' : 'enabled-domain',
      automatic
    );
    if (outcome.type === 'completed') {
      this.bookmarkConsecutiveFailureCount = 0;
      if (mode === 'sync' && executionScope === 'enabled-domain') {
        this.bookmarkCompletionSequence += 1;
        this.bookmarkCompletionCoveredRevision = startRevision;
        this.bookmarkCompletionProviderIdentity = providerIdentity;
        this.bookmarkCompletionResult = outcome;
        this.bookmarkCompletionAt = this.clock.now();
      }
      this.bookmarkHasPendingChanges = this.bookmarkChangeRevision !== startRevision;
      if (this.bookmarkHasPendingChanges && this.appForeground) {
        this.scheduleBookmarkLocalChangeRun();
      } else if (automatic && mode === 'sync' && executionScope === 'enabled-domain') {
        this.pendingBookmarkAutomaticRun = false;
        this.cancelBookmarkTimer();
        if (this.manualBookmarkCoverageCount <= 0 && this.isBookmarkAutomaticSyncActive()) {
          const interval = this.getActiveProviderKind() === 'webdav'
            ? BOOKMARK_WEBDAV_PERIODIC_SYNC_INTERVAL_MS
            : BOOKMARK_PERIODIC_SYNC_INTERVAL_MS;
          this.bookmarkAutomaticNotBefore = this.bookmarkCompletionAt + interval;
          this.scheduleBookmarkPeriodicRun(interval);
        }
      }
      this.stopNetworkRecoveryIfInactive();
      return outcome;
    }
    this.bookmarkHasPendingChanges = true;
    if (outcome.type === 'blocked') {
      this.stopNetworkRecoveryIfInactive();
      return outcome;
    }
    this.bookmarkConsecutiveFailureCount += 1;
    this.bookmarkAutomaticNotBefore = 0;
    if (automatic && this.manualBookmarkCoverageCount <= 0 && this.appForeground &&
      this.isBookmarkAutomaticSyncActive()) {
      this.scheduleBookmarkRetryRun();
    }
    hilog.warn(
      DOMAIN,
      TAG,
      'bookmark sync failed reason=%{public}s error=%{public}s',
      reason,
      outcome.message
    );
    this.stopNetworkRecoveryIfInactive();
    return outcome;
  }

  private async executePersonalizationDomain(
    mode: SyncExperienceRunMode,
    automatic: boolean,
    reason: SyncExperiencePersonalizationAutomaticReason
  ): Promise<SyncPersonalizationDomainRunOutcome> {
    this.personalizationLastAttemptAt = this.clock.now();
    const startRevision = this.personalizationChangeRevision;
    const providerIdentity = this.resolveDomainProviderIdentity('personalization');
    const outcome = await this.personalizationDomain.syncDomainNow(mode === 'backup');
    if (outcome.type === 'sync-completed') {
      this.personalizationConsecutiveFailureCount = 0;
      if (mode === 'sync') {
        this.personalizationCompletionSequence += 1;
        this.personalizationCompletionCoveredRevision = startRevision;
        this.personalizationCompletionProviderIdentity = providerIdentity;
        this.personalizationCompletionResult = outcome;
        this.personalizationCompletionAt = this.clock.now();
      }
      if (automatic && mode === 'sync' && this.personalizationChangeRevision === startRevision) {
        this.pendingPersonalizationAutomaticRun = false;
        this.cancelPersonalizationTimer();
        if (this.manualPersonalizationCoverageCount <= 0 && this.personalizationRepositoriesReady &&
          this.isPersonalizationAutomaticSyncActive()) {
          this.personalizationAutomaticNotBefore =
            this.personalizationCompletionAt + PERSONALIZATION_PERIODIC_SYNC_INTERVAL_MS;
          this.schedulePersonalizationPeriodicRun(PERSONALIZATION_PERIODIC_SYNC_INTERVAL_MS);
        }
      }
      return outcome;
    }
    this.personalizationConsecutiveFailureCount += 1;
    this.personalizationAutomaticNotBefore = 0;
    if (automatic) {
      if (this.manualPersonalizationCoverageCount <= 0 && this.isPersonalizationAutomaticSyncActive()) {
        this.schedulePersonalizationIfActive('retry', this.resolvePersonalizationRetryDelayMs());
      }
      hilog.warn(
        DOMAIN,
        TAG,
        'personalization sync failed reason=%{public}s error=%{public}s',
        reason,
        outcome.message
      );
    }
    return outcome;
  }

  private async executeHistoryDomain(
    automatic: boolean,
    reason: SyncExperienceHistoryAutomaticReason
  ): Promise<HistorySyncRunResult> {
    const startRevision = this.historyChangeRevision;
    const providerIdentity = this.resolveHistoryProviderIdentity();
    const result = await this.historySyncService.runNow();
    if (result.ok) {
      this.historyConsecutiveFailureCount = 0;
      this.historyCompletionSequence += 1;
      this.historyCompletionCoveredRevision = startRevision;
      this.historyCompletionProviderIdentity = providerIdentity;
      this.historyCompletionResult = result;
      this.historyCompletionAt = this.clock.now();
      if (automatic && this.historyChangeRevision === startRevision) {
        this.pendingHistoryAutomaticRun = false;
        this.cancelHistoryTimer();
        if (this.manualHistoryCoverageCount <= 0 && this.isHistoryAutomaticSyncActive()) {
          this.historyAutomaticNotBefore = this.historyCompletionAt + HISTORY_PERIODIC_INTERVAL_MS;
          this.scheduleHistoryPeriodicRun(HISTORY_PERIODIC_INTERVAL_MS);
        }
      }
      this.stopNetworkRecoveryIfInactive();
      return result;
    }
    this.historyConsecutiveFailureCount += 1;
    this.historyAutomaticNotBefore = 0;
    if (automatic) {
      if (this.manualHistoryCoverageCount <= 0) {
        this.scheduleHistoryIfActive('retry', this.resolveHistoryRetryDelayMs());
      }
      hilog.warn(
        DOMAIN,
        TAG,
        'history sync failed reason=%{public}s error=%{public}s',
        reason,
        result.message
      );
    }
    this.stopNetworkRecoveryIfInactive();
    return result;
  }

  private resolveDomainProviderIdentity(domain: 'bookmark' | 'personalization'): string {
    const remoteKind = this.syncConfigStore.getSettings().remoteKind;
    if (remoteKind === 'none') {
      return '';
    }
    return this.syncConfigStore.getProviderRuntimeIdentity(remoteKind, domain);
  }

  private resolveHistoryProviderIdentity(): string {
    const identity = this.historySyncService.resolveCurrentIdentity();
    if (identity === undefined) {
      return '';
    }
    return identity.provider + '\n' + identity.accountUid + '\n' + identity.clientId;
  }

  private requestUnifiedAutomaticFreshnessRun(): void {
    this.requestAutomaticRun(
      this.isBookmarkAutomaticSyncActive(),
      this.personalizationRepositoriesReady && this.isPersonalizationAutomaticSyncActive(),
      'periodic',
      'periodic',
      this.isHistoryAutomaticSyncActive(),
      'periodic'
    );
  }

  private requestAutomaticRun(
    runBookmarks: boolean,
    runPersonalization: boolean,
    bookmarkReason: SyncExperienceBookmarkAutomaticReason,
    personalizationReason: SyncExperiencePersonalizationAutomaticReason,
    runHistory: boolean = false,
    historyReason: SyncExperienceHistoryAutomaticReason = 'local_change'
  ): void {
    if (runBookmarks) {
      this.pendingBookmarkAutomaticRun = true;
      this.pendingBookmarkReason = bookmarkReason;
    }
    if (runPersonalization) {
      this.pendingPersonalizationAutomaticRun = true;
      this.pendingPersonalizationReason = personalizationReason;
    }
    if (runHistory) {
      this.pendingHistoryAutomaticRun = true;
      this.pendingHistoryReason = historyReason;
    }
    this.schedulePendingAutomaticDrain();
  }

  private yieldStaleAutomaticRemainder(
    request: SyncExperienceRuntimeRequest,
    runBookmarks: boolean,
    runPersonalization: boolean,
    runHistory: boolean,
    bookmarkReason: SyncExperienceBookmarkAutomaticReason,
    personalizationReason: SyncExperiencePersonalizationAutomaticReason,
    historyReason: SyncExperienceHistoryAutomaticReason
  ): boolean {
    if (request.kind !== 'automatic' || request.automaticGeneration === this.automaticGeneration) {
      return false;
    }
    if (runBookmarks && !this.pendingBookmarkAutomaticRun) {
      this.pendingBookmarkAutomaticRun = true;
      this.pendingBookmarkReason = bookmarkReason;
    }
    if (runPersonalization && !this.pendingPersonalizationAutomaticRun) {
      this.pendingPersonalizationAutomaticRun = true;
      this.pendingPersonalizationReason = personalizationReason;
    }
    if (runHistory && !this.pendingHistoryAutomaticRun) {
      this.pendingHistoryAutomaticRun = true;
      this.pendingHistoryReason = historyReason;
    }
    this.schedulePendingAutomaticDrain();
    return true;
  }

  private invalidateQueuedAutomaticDrain(): void {
    this.automaticGeneration += 1;
    this.automaticDrainQueued = false;
    this.cancelAutomaticDrainTimer();
  }

  private schedulePendingAutomaticDrain(): void {
    if (this.automaticDrainQueued || (!this.pendingBookmarkAutomaticRun &&
      !this.pendingPersonalizationAutomaticRun && !this.pendingHistoryAutomaticRun)) {
      return;
    }
    this.automaticDrainQueued = true;
    this.automaticDrainTimerId = this.clock.setTimeout((): void => {
      this.automaticDrainTimerId = -1;
      void this.enqueueExecution({
        kind: 'automatic',
        automaticGeneration: this.automaticGeneration,
        mode: 'sync',
        runBookmarks: false,
        runPersonalization: false,
        runHistory: false,
        bookmarkExecutionScope: 'enabled-domain',
        bookmarkReason: this.pendingBookmarkReason,
        personalizationReason: this.pendingPersonalizationReason,
        historyReason: this.pendingHistoryReason,
        bookmarkCompletionSequenceAtEnqueue: this.bookmarkCompletionSequence,
        personalizationCompletionSequenceAtEnqueue: this.personalizationCompletionSequence,
        historyCompletionSequenceAtEnqueue: this.historyCompletionSequence
      }).catch((error: Error): void => {
        hilog.warn(DOMAIN, TAG, 'automatic sync queue failed: %{public}s', JSON.stringify(error));
      });
    }, AUTOMATIC_DRAIN_YIELD_MS);
  }

  private cancelAutomaticDrainTimer(): void {
    if (this.automaticDrainTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.automaticDrainTimerId);
    this.automaticDrainTimerId = -1;
  }

  private scheduleHuaweiSpaceTransportWarmup(): void {
    if (this.huaweiTransportWarmupScheduled || this.huaweiTransportWarmupTimerId >= 0) {
      return;
    }
    this.huaweiTransportWarmupTimerId = this.clock.setTimeout((): void => {
      this.huaweiTransportWarmupTimerId = -1;
      this.huaweiTransportWarmupScheduled = true;
      void this.syncService.warmupHuaweiSpaceTransport();
    }, HUAWEI_SPACE_TRANSPORT_WARMUP_DELAY_MS);
  }

  private cancelHuaweiSpaceTransportWarmupTimer(): void {
    if (this.huaweiTransportWarmupTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.huaweiTransportWarmupTimerId);
    this.huaweiTransportWarmupTimerId = -1;
  }

  private async runPendingBookmarksOnForegroundAsync(): Promise<void> {
    try {
      await this.syncService.initializeAiraSyncSettings();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'bookmark foreground recovery failed: %{public}s', this.stringifyError(error as Error));
      return;
    }
    this.startNetworkRecovery();
    if (!this.isBookmarkAutomaticSyncActive()) {
      this.cancelBookmarkTimer();
      return;
    }
    if (!await this.hasBookmarkPendingChanges()) {
      return;
    }
    this.bookmarkHasPendingChanges = true;
    this.scheduleBookmarkForegroundRun();
  }

  private scheduleBookmarkLocalChangeRun(): void {
    this.scheduleBookmarkAutomaticRun('local_change', BOOKMARK_AUTO_SYNC_DELAY_MS);
  }

  private scheduleBookmarkRetryRun(): void {
    this.scheduleBookmarkAutomaticRun('retry', this.resolveBookmarkDelayedRunDelayMs());
  }

  private scheduleBookmarkForegroundRun(): void {
    this.scheduleBookmarkAutomaticRun('foreground', BOOKMARK_AUTO_SYNC_FOREGROUND_DELAY_MS);
  }

  private scheduleBookmarkAutomaticRun(
    reason: SyncExperienceBookmarkAutomaticReason,
    delayMs: number
  ): void {
    if (this.manualBookmarkCoverageCount > 0 && reason !== 'local_change') {
      return;
    }
    const effectiveDelay = reason === 'local_change'
      ? delayMs
      : Math.max(delayMs, this.remainingAutomaticDelay(this.bookmarkAutomaticNotBefore));
    this.cancelBookmarkTimer();
    this.bookmarkTimerId = this.clock.setTimeout(() => {
      this.bookmarkTimerId = -1;
      this.requestAutomaticRun(true, false, reason, 'local_change');
    }, effectiveDelay);
  }

  private async hasBookmarkPendingChanges(): Promise<boolean> {
    if (this.bookmarkHasPendingChanges) {
      return true;
    }
    return (this.syncService.getAiraSyncSettings().pendingBookmarkSyncAt ?? 0) > 0;
  }

  private isBookmarkAutomaticSyncActive(): boolean {
    if (!this.isAutomaticBookmarkGateOpen()) {
      return false;
    }
    const settings = this.syncService.getAiraSyncSettings();
    if (settings.remoteKind === 'huawei_space' &&
      resolveAiraSyncDomainRuntimeState(settings, 'huawei_space', 'bookmark').blocked) {
      return false;
    }
    return this.appForeground && settings.bookmarkSyncEnabled === true &&
      this.countEnabledProviders(settings) > 0;
  }

  private isAutomaticBookmarkGateOpen(): boolean {
    try {
      return this.bookmarkAutomaticAllowPredicate();
    } catch (_error) {
      return false;
    }
  }

  private countEnabledProviders(settings: AiraSyncSettings): number {
    let count = 0;
    if (isAiraSyncProviderEnabled(settings, 'aira_cloud') && settings.huaweiCloud.uid.trim().length > 0) {
      count += 1;
    }
    if (isAiraSyncProviderEnabled(settings, 'webdav') && settings.webdav.endpoint.trim().length > 0) {
      count += 1;
    }
    if (isAiraSyncProviderEnabled(settings, 'huawei_space') && settings.huaweiSpace.uid.trim().length > 0) {
      count += 1;
    }
    const selfHosted = settings.selfHosted;
    if (isAiraSyncProviderEnabled(settings, 'self_hosted') && selfHosted !== undefined &&
      selfHosted.instanceId.trim().length > 0 && selfHosted.deviceToken.trim().length > 0) {
      count += 1;
    }
    return count;
  }

  private resolveBookmarkDelayedRunDelayMs(): number {
    if (this.isHuaweiBookmarkInitializationPending()) {
      const retryIndex = Math.min(
        Math.max(0, this.bookmarkConsecutiveFailureCount - 1),
        HUAWEI_BOOKMARK_INITIALIZATION_RETRY_DELAYS_MS.length - 1
      );
      return HUAWEI_BOOKMARK_INITIALIZATION_RETRY_DELAYS_MS[retryIndex];
    }
    if (this.bookmarkConsecutiveFailureCount <= 0) {
      return BOOKMARK_AUTO_SYNC_DELAY_MS;
    }
    const exponent = Math.min(6, this.bookmarkConsecutiveFailureCount);
    return Math.min(
      BOOKMARK_RETRY_MAX_DELAY_MS,
      BOOKMARK_AUTO_SYNC_DELAY_MS * Math.pow(2, exponent)
    );
  }

  private getActiveProviderKind(): AiraSyncRemoteKind {
    return this.syncService.getAiraSyncSettings().remoteKind;
  }

  private scheduleBookmarkPeriodicRun(delayMs: number): void {
    this.cancelBookmarkPeriodicSync();
    this.bookmarkPeriodicTimerId = this.clock.setTimeout(() => {
      this.bookmarkPeriodicTimerId = -1;
      this.runBookmarkPeriodicSyncNow();
    }, delayMs);
  }

  private runBookmarkPeriodicSyncNow(): void {
    if (!this.isBookmarkAutomaticSyncActive() &&
      !(this.personalizationRepositoriesReady && this.isPersonalizationAutomaticSyncActive()) &&
      !this.isHistoryAutomaticSyncActive()) {
      this.cancelBookmarkPeriodicSync();
      return;
    }
    this.requestUnifiedAutomaticFreshnessRun();
    const nextDelay = this.getActiveProviderKind() === 'webdav'
      ? BOOKMARK_WEBDAV_PERIODIC_SYNC_INTERVAL_MS
      : BOOKMARK_PERIODIC_SYNC_INTERVAL_MS;
    this.scheduleBookmarkPeriodicRun(nextDelay);
  }

  private cancelBookmarkTimer(): void {
    if (this.bookmarkTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.bookmarkTimerId);
    this.bookmarkTimerId = -1;
  }

  private cancelBookmarkPeriodicSync(): void {
    if (this.bookmarkPeriodicTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.bookmarkPeriodicTimerId);
    this.bookmarkPeriodicTimerId = -1;
  }

  private notifyPersonalizationForeground(): void {
    this.startNetworkRecovery();
    if (this.personalizationRepositoriesReady) {
      this.schedulePersonalizationIfActive(
        'foreground',
        PERSONALIZATION_FOREGROUND_RECOVERY_DELAY_MS
      );
    }
  }

  private startNetworkRecovery(): void {
    if (this.networkRecoveryStarted ||
      (!this.personalizationRepositoriesReady && !this.hasPendingHuaweiBookmarkSync() &&
        !this.isHistoryAutomaticSyncActive())) {
      return;
    }
    this.networkRecoveryStarted = true;
    this.networkAvailabilityService.start((snapshot: WebNetworkAvailabilitySnapshot): void => {
      if (!snapshot.reliable || !snapshot.available) {
        return;
      }
      this.scheduleBookmarkNetworkRecovery();
      if (this.personalizationRepositoriesReady) {
        this.schedulePersonalizationIfActive('network_recovery', PERSONALIZATION_NETWORK_RECOVERY_DELAY_MS);
      }
      this.scheduleHistoryIfActive('network_recovery', HISTORY_NETWORK_RECOVERY_DELAY_MS);
    });
  }

  private scheduleBookmarkNetworkRecovery(): void {
    const settings = this.syncService.getAiraSyncSettings();
    if (settings.remoteKind !== 'huawei_space' || !this.isBookmarkAutomaticSyncActive()) {
      return;
    }
    void this.hasBookmarkPendingChanges().then((pending: boolean): void => {
      if (!pending || this.syncService.getAiraSyncSettings().remoteKind !== 'huawei_space' ||
        !this.isBookmarkAutomaticSyncActive()) {
        return;
      }
      this.bookmarkHasPendingChanges = true;
      this.scheduleBookmarkAutomaticRun('network_recovery', BOOKMARK_NETWORK_RECOVERY_DELAY_MS);
    });
  }

  private hasPendingHuaweiBookmarkSync(): boolean {
    const settings = this.syncService.getAiraSyncSettings();
    return settings.remoteKind === 'huawei_space' && (settings.pendingBookmarkSyncAt ?? 0) > 0;
  }

  private isHuaweiBookmarkInitializationPending(): boolean {
    const settings = this.syncService.getAiraSyncSettings();
    if (settings.remoteKind !== 'huawei_space' || settings.bookmarkSyncEnabled !== true ||
      (settings.pendingBookmarkSyncAt ?? 0) <= 0) {
      return false;
    }
    return resolveAiraSyncDomainRuntimeState(settings, 'huawei_space', 'bookmark').lastSuccessAt <= 0;
  }

  private stopNetworkRecoveryIfInactive(): void {
    if (!this.networkRecoveryStarted) {
      return;
    }
    const personalizationActive = this.personalizationRepositoriesReady &&
      this.isPersonalizationAutomaticSyncActive();
    const huaweiBookmarkActive = this.hasPendingHuaweiBookmarkSync() &&
      this.isBookmarkAutomaticSyncActive();
    if (personalizationActive || huaweiBookmarkActive || this.isHistoryAutomaticSyncActive()) {
      return;
    }
    this.networkAvailabilityService.stop();
    this.networkRecoveryStarted = false;
  }

  private handlePreferenceChange(origin: BrowserPreferencesChangeOrigin): void {
    const nextFingerprint = this.personalizationSyncService.buildCorePreferencesFingerprint();
    if (nextFingerprint === this.corePreferencesFingerprint) {
      return;
    }
    this.corePreferencesFingerprint = nextFingerprint;
    if (origin === 'local') {
      this.notifyPersonalizationLocalSettingsChanged();
    }
  }

  private schedulePersonalizationIfActive(
    reason: SyncExperiencePersonalizationAutomaticReason,
    delayMs: number
  ): void {
    if (!this.isPersonalizationAutomaticSyncActive()) {
      return;
    }
    if (this.manualPersonalizationCoverageCount > 0 &&
      reason !== 'local_change' && reason !== 'home_shortcuts') {
      return;
    }
    const manualDelay = reason === 'local_change' || reason === 'home_shortcuts'
      ? 0
      : this.remainingAutomaticDelay(this.personalizationAutomaticNotBefore);
    const scheduledAt = this.resolvePersonalizationDeadline(reason, Math.max(delayMs, manualDelay));
    this.schedulePersonalizationAt(reason, scheduledAt);
  }

  private schedulePersonalizationPeriodicSync(): void {
    if (!this.personalizationRepositoriesReady || !this.isPersonalizationAutomaticSyncActive()) {
      this.cancelPersonalizationPeriodicSync();
      return;
    }
    if (this.personalizationPeriodicTimerId >= 0) {
      return;
    }
    this.schedulePersonalizationPeriodicRun(Math.max(
      PERSONALIZATION_PERIODIC_SYNC_STARTUP_DELAY_MS,
      this.remainingAutomaticDelay(this.personalizationAutomaticNotBefore)
    ));
  }

  private schedulePersonalizationPeriodicRun(delayMs: number): void {
    this.cancelPersonalizationPeriodicSync();
    this.personalizationPeriodicTimerId = this.clock.setTimeout(() => {
      this.personalizationPeriodicTimerId = -1;
      this.runPersonalizationPeriodicSyncNow();
    }, delayMs);
  }

  private runPersonalizationPeriodicSyncNow(): void {
    if (!this.personalizationRepositoriesReady || !this.isPersonalizationAutomaticSyncActive()) {
      this.cancelPersonalizationPeriodicSync();
      return;
    }
    this.requestUnifiedAutomaticFreshnessRun();
    this.schedulePersonalizationPeriodicRun(PERSONALIZATION_PERIODIC_SYNC_INTERVAL_MS);
  }

  private resolvePersonalizationRetryDelayMs(): number {
    const exponent = Math.min(6, Math.max(0, this.personalizationConsecutiveFailureCount - 1));
    return Math.min(
      PERSONALIZATION_RETRY_MAX_DELAY_MS,
      PERSONALIZATION_RETRY_START_DELAY_MS * Math.pow(2, exponent)
    );
  }

  private resolvePersonalizationDeadline(
    reason: SyncExperiencePersonalizationAutomaticReason,
    delayMs: number
  ): number {
    const now = this.clock.now();
    const remainingGap = this.isPersonalizationLocalContentReason(reason)
      ? 0
      : Math.max(0, PERSONALIZATION_MIN_SYNC_GAP_MS - (now - this.personalizationLastAttemptAt));
    return now + Math.max(delayMs, remainingGap);
  }

  private schedulePersonalizationAt(
    reason: SyncExperiencePersonalizationAutomaticReason,
    scheduledAt: number
  ): void {
    if (this.personalizationTimerId >= 0) {
      const sameReason = reason === this.personalizationScheduledReason;
      if (!sameReason && this.personalizationScheduledAt <= scheduledAt) {
        return;
      }
    }
    this.cancelPersonalizationTimer();
    this.personalizationScheduledAt = scheduledAt;
    this.personalizationScheduledReason = reason;
    this.personalizationTimerId = this.clock.setTimeout(() => {
      this.personalizationTimerId = -1;
      this.personalizationScheduledAt = 0;
      this.personalizationScheduledReason = 'local_change';
      this.requestAutomaticRun(false, true, 'delayed', reason);
    }, Math.max(0, scheduledAt - this.clock.now()));
  }

  private isPersonalizationLocalContentReason(
    reason: SyncExperiencePersonalizationAutomaticReason
  ): boolean {
    return reason === 'local_change' || reason === 'home_shortcuts' || reason === 'network_recovery' ||
      reason === 'retry';
  }

  private isPersonalizationAutomaticSyncActive(): boolean {
    const settings = this.syncConfigStore.getSettings();
    return this.appForeground && settings.personalizationSyncEnabled === true && settings.remoteKind !== 'none';
  }

  private cancelPersonalizationTimer(): void {
    if (this.personalizationTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.personalizationTimerId);
    this.personalizationTimerId = -1;
    this.personalizationScheduledAt = 0;
    this.personalizationScheduledReason = 'local_change';
  }

  private cancelPersonalizationPeriodicSync(): void {
    if (this.personalizationPeriodicTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.personalizationPeriodicTimerId);
    this.personalizationPeriodicTimerId = -1;
  }

  private scheduleHistoryIfActive(reason: SyncExperienceHistoryAutomaticReason, delayMs: number): void {
    if (!this.isHistoryAutomaticSyncActive()) {
      return;
    }
    if (this.manualHistoryCoverageCount > 0 && reason !== 'local_change') {
      return;
    }
    const effectiveDelay = reason === 'local_change'
      ? delayMs
      : Math.max(delayMs, this.remainingAutomaticDelay(this.historyAutomaticNotBefore));
    this.cancelHistoryTimer();
    this.historyTimerId = this.clock.setTimeout(() => {
      this.historyTimerId = -1;
      this.requestAutomaticRun(false, false, 'delayed', 'local_change', true, reason);
    }, effectiveDelay);
  }

  private scheduleHistoryPeriodicSync(): void {
    if (!this.isHistoryAutomaticSyncActive()) {
      this.cancelHistoryPeriodicSync();
      return;
    }
    if (this.historyPeriodicTimerId >= 0) {
      return;
    }
    this.scheduleHistoryPeriodicRun(Math.max(
      HISTORY_PERIODIC_STARTUP_DELAY_MS,
      this.remainingAutomaticDelay(this.historyAutomaticNotBefore)
    ));
  }

  private scheduleHistoryPeriodicRun(delayMs: number): void {
    this.cancelHistoryPeriodicSync();
    this.historyPeriodicTimerId = this.clock.setTimeout(() => {
      this.historyPeriodicTimerId = -1;
      if (!this.isHistoryAutomaticSyncActive()) {
        return;
      }
      this.requestUnifiedAutomaticFreshnessRun();
      this.scheduleHistoryPeriodicRun(HISTORY_PERIODIC_INTERVAL_MS);
    }, delayMs);
  }

  private resolveHistoryRetryDelayMs(): number {
    const exponent = Math.min(6, Math.max(0, this.historyConsecutiveFailureCount - 1));
    return Math.min(HISTORY_RETRY_MAX_DELAY_MS, HISTORY_RETRY_START_DELAY_MS * Math.pow(2, exponent));
  }

  private isHistoryDomainEnabled(): boolean {
    const experienceState = this.experienceStateStore.getState();
    const provider = resolveHistorySyncProviderKind(this.syncConfigStore.getSettings().remoteKind);
    if (experienceState.historySelected !== true || provider === undefined ||
      (provider === 'aira_cloud' && this.membershipFeature.getState().plan !== 'pro')) {
      return false;
    }
    const identity = this.historySyncService.resolveCurrentIdentity();
    return identity !== undefined && identity.accountUid === experienceState.historyAccountUid;
  }

  private isHistoryAutomaticSyncActive(): boolean {
    return this.appForeground && !this.experienceStateStore.getState().suspended &&
      this.isHistoryDomainEnabled();
  }

  private cancelHistoryTimer(): void {
    if (this.historyTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.historyTimerId);
    this.historyTimerId = -1;
  }

  private cancelHistoryPeriodicSync(): void {
    if (this.historyPeriodicTimerId < 0) {
      return;
    }
    this.clock.clearTimeout(this.historyPeriodicTimerId);
    this.historyPeriodicTimerId = -1;
  }

  private remainingAutomaticDelay(notBefore: number): number {
    return Math.max(0, notBefore - this.clock.now());
  }

  private stringifyError(error: Error): string {
    return error.message !== undefined && error.message.length > 0 ? error.message : JSON.stringify(error);
  }
}
