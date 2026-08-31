import {
  BrowserDataScope,
  BrowserPrivateTabRestorePolicy,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  BrowserTabAutoClosePolicy,
  TabRecord,
  TabRuntimeState,
  buildBrowserDataBoundaryFromTabLike,
  normalizeBrowserDataScope,
  normalizeBrowserProfileId,
  normalizeBrowserSessionPrivacyMode
} from '../../common/models/BrowserModels';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserTabSessionRestorePreparation {
  records: TabRecord[];
  droppedEphemeralCount: number;
  droppedAutoClosedCount: number;
  activeRecordId: string;
}

export interface BrowserTabSessionPersistencePreparation {
  records: TabRecord[];
  droppedEphemeralCount: number;
  droppedAutoClosedCount: number;
}

export interface BrowserTabSessionFilterOptions {
  tabAutoClosePolicy?: BrowserTabAutoClosePolicy;
}

export interface BrowserTabSessionPersistenceOptions extends BrowserTabSessionFilterOptions {
  persistPrivateTabs?: boolean;
}

export interface BrowserTabSessionRestoreOptions extends BrowserTabSessionPersistenceOptions {
}

export interface BrowserTabSessionEmptyState {
  profileId: BrowserProfileId;
  privacyMode: BrowserSessionPrivacyMode;
  dataScope: BrowserDataScope;
}

export interface BrowserTabSessionDropDiagnostic {
  eventName: string;
  message: string;
}

export class BrowserTabSessionRestoreService {
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  constructor(privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService()) {
    this.privacyEffectPolicy = privacyEffectPolicy;
  }

  buildOptions(
    tabAutoClosePolicy: BrowserTabAutoClosePolicy | undefined,
    privateTabRestorePolicy: BrowserPrivateTabRestorePolicy | string | undefined
  ): BrowserTabSessionRestoreOptions {
    return {
      tabAutoClosePolicy: tabAutoClosePolicy,
      persistPrivateTabs: this.shouldPersistPrivateTabs(privateTabRestorePolicy)
    };
  }

  shouldPersistPrivateTabs(privateTabRestorePolicy: BrowserPrivateTabRestorePolicy | string | undefined): boolean {
    return privateTabRestorePolicy === 'restore_private_tabs';
  }

  prepareRecordsForColdRestore(
    records: TabRecord[],
    options: BrowserTabSessionRestoreOptions = {}
  ): BrowserTabSessionRestorePreparation {
    const persistentRecords = this.normalizePersistentRecords(records, options);
    const droppedAutoClosedCount = this.countAutoClosedRecords(records, options.tabAutoClosePolicy);
    if (persistentRecords.length === 0) {
      return {
        records: [],
        droppedEphemeralCount: Math.max(0, records.length - droppedAutoClosedCount),
        droppedAutoClosedCount: droppedAutoClosedCount,
        activeRecordId: ''
      };
    }

    const activeRecord = this.resolveActiveRecord(persistentRecords);
    const restoredRecords = persistentRecords.map((record: TabRecord): TabRecord => {
      return this.copyRecord(record, record.id === activeRecord.id);
    });
    return {
      records: restoredRecords,
      droppedEphemeralCount: Math.max(0, records.length - persistentRecords.length - droppedAutoClosedCount),
      droppedAutoClosedCount: droppedAutoClosedCount,
      activeRecordId: activeRecord.id
    };
  }

  prepareRecordsForPersistence(
    records: TabRecord[],
    options: BrowserTabSessionPersistenceOptions = {}
  ): BrowserTabSessionPersistencePreparation {
    const persistentRecords = this.normalizePersistentRecords(records, options);
    const droppedAutoClosedCount = this.countAutoClosedRecords(records, options.tabAutoClosePolicy);
    if (persistentRecords.length === 0) {
      return {
        records: [],
        droppedEphemeralCount: Math.max(0, records.length - droppedAutoClosedCount),
        droppedAutoClosedCount: droppedAutoClosedCount
      };
    }
    const activeRecord = this.resolveActiveRecord(persistentRecords);
    return {
      records: persistentRecords.map((record: TabRecord): TabRecord => this.copyRecord(record, record.id === activeRecord.id)),
      droppedEphemeralCount: Math.max(0, records.length - persistentRecords.length - droppedAutoClosedCount),
      droppedAutoClosedCount: droppedAutoClosedCount
    };
  }

  buildEmptyStateBoundary(options: Partial<BrowserTabSessionEmptyState> = {}): BrowserTabSessionEmptyState {
    const privacyMode = normalizeBrowserSessionPrivacyMode(options.privacyMode);
    return {
      profileId: normalizeBrowserProfileId(options.profileId),
      privacyMode: privacyMode,
      dataScope: normalizeBrowserDataScope(options.dataScope, privacyMode)
    };
  }

  buildDroppedRecordDiagnostics(
    preparation: BrowserTabSessionRestorePreparation | BrowserTabSessionPersistencePreparation
  ): BrowserTabSessionDropDiagnostic[] {
    const diagnostics: BrowserTabSessionDropDiagnostic[] = [];
    if (preparation.droppedEphemeralCount > 0) {
      diagnostics.push({
        eventName: 'tab_session_ephemeral_skipped',
        message: `冷启动已忽略 ${preparation.droppedEphemeralCount} 个私密/临时标签页。`
      });
    }
    if (preparation.droppedAutoClosedCount > 0) {
      diagnostics.push({
        eventName: 'tab_session_auto_closed',
        message: `冷启动已自动关闭 ${preparation.droppedAutoClosedCount} 个过期标签页。`
      });
    }
    return diagnostics;
  }

  private normalizePersistentRecords(
    records: TabRecord[],
    options: BrowserTabSessionPersistenceOptions = {}
  ): TabRecord[] {
    return records
      .filter((record: TabRecord) => this.shouldPersistRecord(record, options))
      .map((record: TabRecord): TabRecord => this.copyRecord(record, record.isActive));
  }

  private shouldPersistRecord(record: TabRecord, options: BrowserTabSessionPersistenceOptions = {}): boolean {
    if (this.shouldDropForAutoClosePolicy(record, options.tabAutoClosePolicy)) {
      return false;
    }
    const boundary = buildBrowserDataBoundaryFromTabLike({
      id: record.id,
      profileId: record.profileId,
      privacyMode: record.privacyMode,
      dataScope: record.dataScope
    });
    if (this.profileBoundaryService.isSessionEphemeral(boundary) && options.persistPrivateTabs === true) {
      return true;
    }
    return this.privacyEffectPolicy.shouldWritePersistentDataForBoundary('tab_session_restore', boundary);
  }

  private shouldDropForAutoClosePolicy(
    record: TabRecord,
    policy: BrowserTabAutoClosePolicy | undefined
  ): boolean {
    const normalizedPolicy = policy ?? 'manual';
    if (normalizedPolicy === 'manual') {
      return false;
    }
    if (normalizedPolicy === 'on_app_exit') {
      return true;
    }
    if (record.isActive) {
      return false;
    }
    if (record.isPinned) {
      return false;
    }
    const maxAgeMs = this.resolveAutoCloseMaxAgeMs(normalizedPolicy);
    if (maxAgeMs <= 0) {
      return false;
    }
    const lastActiveAt = this.resolveRecordLastUsedAt(record);
    return Date.now() - lastActiveAt >= maxAgeMs;
  }

  private countAutoClosedRecords(records: TabRecord[], policy: BrowserTabAutoClosePolicy | undefined): number {
    return records.filter((record: TabRecord) => this.shouldDropForAutoClosePolicy(record, policy)).length;
  }

  private resolveAutoCloseMaxAgeMs(policy: BrowserTabAutoClosePolicy): number {
    switch (policy) {
      case 'after_15_days':
        return 15 * 24 * 60 * 60 * 1000;
      case 'after_7_days':
        return 7 * 24 * 60 * 60 * 1000;
      case 'after_3_days':
        return 3 * 24 * 60 * 60 * 1000;
      case 'after_1_day':
        return 24 * 60 * 60 * 1000;
      case 'manual':
      case 'on_app_exit':
      default:
        return 0;
    }
  }

  private resolveRecordLastUsedAt(record: TabRecord): number {
    const candidates: number[] = [
      record.lastActiveAt,
      record.lastLoadedAt ?? 0,
      record.webStateUpdatedAt ?? 0
    ];
    const sorted = candidates
      .filter((value: number) => Number.isFinite(value) && value > 0)
      .sort((left: number, right: number) => right - left);
    return sorted[0] ?? 0;
  }

  private resolveActiveRecord(records: TabRecord[]): TabRecord {
    const markedActive = records.find((record: TabRecord) => record.isActive);
    if (markedActive !== undefined) {
      return markedActive;
    }
    const sorted = records.slice().sort((left: TabRecord, right: TabRecord) => {
      return right.lastActiveAt - left.lastActiveAt;
    });
    return sorted[0];
  }

  private copyRecord(record: TabRecord, isActive: boolean): TabRecord {
    const privacyMode = normalizeBrowserSessionPrivacyMode(record.privacyMode);
    const dataScope = normalizeBrowserDataScope(record.dataScope, privacyMode);
    const copied: TabRecord = {
      id: record.id,
      windowId: record.windowId,
      profileId: normalizeBrowserProfileId(record.profileId),
      title: record.title,
      url: record.url,
      isActive: isActive,
      isPinned: record.isPinned,
      lastActiveAt: record.lastActiveAt,
      tabOrder: record.tabOrder,
      isHome: record.isHome,
      pendingUrl: record.pendingUrl,
      navigationHistory: record.navigationHistory === undefined ? undefined : record.navigationHistory.slice(),
      navigationIndex: record.navigationIndex,
      runtimeState: this.resolvePersistedRuntimeState(record.runtimeState, isActive, record.isHome === true),
      lastError: record.lastError,
      lastRestoreReason: record.lastRestoreReason,
      lastDiscardReason: record.lastDiscardReason,
      lastCrashReason: record.lastCrashReason,
      lastLoadedAt: record.lastLoadedAt,
      webStatePath: record.webStatePath,
      webStateUpdatedAt: record.webStateUpdatedAt,
      scrollOffsetY: record.scrollOffsetY,
      lastGoodUrl: record.lastGoodUrl,
      lastGoodTitle: record.lastGoodTitle,
      lastRestoreType: record.lastRestoreType,
      privacyMode: privacyMode,
      dataScope: dataScope,
      launchSourceType: record.launchSourceType,
      launchSourceId: record.launchSourceId,
      launchSourceUrl: record.launchSourceUrl,
      launchKey: record.launchKey
    };
    return copied;
  }

  private resolvePersistedRuntimeState(
    runtimeState: TabRuntimeState | undefined,
    isActive: boolean,
    isHome: boolean
  ): TabRuntimeState | undefined {
    if (runtimeState === undefined) {
      return undefined;
    }
    if (isActive) {
      return runtimeState;
    }
    if (isHome && runtimeState === 'active') {
      return 'background';
    }
    if (!isHome && (runtimeState === 'active' || runtimeState === 'loading' || runtimeState === 'restoring')) {
      return 'suspended';
    }
    return runtimeState;
  }
}
