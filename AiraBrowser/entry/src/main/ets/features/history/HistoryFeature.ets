import {
  HistoryRepository,
  RecentlyClosedTabRepository
} from '../../data/repositories/BrowserRepositories';
import {
  BrowserDataBoundaryInput,
  CreateHistoryVisitCommand,
  HistoryImportResult,
  HistoryRetentionSettings,
  HistorySiteAggregate,
  HistoryStats,
  HistoryTransferVisit,
  HistoryVisit
} from '../../common/models/BrowserModels';
import {
  DEFAULT_HISTORY_RETENTION_SETTINGS,
  PreferencesRepository
} from '../../data/preferences/PreferencesRepository';
import { BrowserDatabase } from '../../data/database/BrowserDatabase';
import { HistoryTransferCodec } from '../../services/history/HistoryTransferCodec';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectTargetScope
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';

const HISTORY_RETENTION_WRITE_BATCH_SIZE = 20;
const HISTORY_RETENTION_MIN_INTERVAL_MS = 30 * 1000;
const HISTORY_STRESS_PREVIEW_CACHE_LIMIT: number = 100;

export interface HistoryStressSeedResult {
  insertedCount: number;
  targetTotalCount: number;
}

export class HistoryManagementBoundary {
  dataScope: string;
  privacyMode: string;

  constructor(dataScope: string, privacyMode: string) {
    this.dataScope = dataScope;
    this.privacyMode = privacyMode;
  }
}

export class HistoryFeature {
  private repository: HistoryRepository;
  private recentlyClosedTabRepository?: RecentlyClosedTabRepository;
  private preferencesRepository?: PreferencesRepository;
  private transferCodec: HistoryTransferCodec = new HistoryTransferCodec();
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private writesSinceRetentionPolicy: number = 0;
  private lastRetentionPolicyAppliedAt: number = 0;

  constructor(
    repository: HistoryRepository,
    preferencesRepository?: PreferencesRepository,
    recentlyClosedTabRepository?: RecentlyClosedTabRepository,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.repository = repository;
    this.preferencesRepository = preferencesRepository;
    this.recentlyClosedTabRepository = recentlyClosedTabRepository;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  getCount(): number {
    return this.getStats().totalVisits;
  }

  getStats(): HistoryStats {
    const visits = this.repository.listVisits();
    return {
      totalVisits: visits.length,
      latestVisitedAt: visits.length > 0 ? visits[0].visitedAt : 0
    };
  }

  listVisits(limit?: number): HistoryVisit[] {
    return this.repository.listVisits(limit);
  }

  addVisit(command: CreateHistoryVisitCommand): Promise<HistoryVisit> {
    return this.repository.addVisit(command);
  }

  async addVisitIfAllowed(command: CreateHistoryVisitCommand): Promise<HistoryVisit | undefined> {
    if (!this.shouldRecordVisits()) {
      return undefined;
    }
    const visit = await this.repository.addVisit(command);
    await this.applyRetentionPolicyAfterWrite(Date.now());
    return visit;
  }

  shouldRecordVisits(settings?: HistoryRetentionSettings): boolean {
    const resolvedSettings = settings ?? this.getHistoryRetentionSettings();
    return resolvedSettings.enabled;
  }

  deleteVisit(id: string): Promise<boolean> {
    return this.repository.deleteVisit(id);
  }

  deleteVisitsByHost(host: string): Promise<number> {
    return this.repository.deleteVisitsByHost(host);
  }

  deleteVisitsByIds(ids: string[]): Promise<number> {
    return this.repository.deleteVisitsByIds(ids);
  }

  async clearVisits(): Promise<number> {
    const removed = await this.repository.clearVisits();
    await this.recentlyClosedTabRepository?.clearRecords();
    return removed;
  }

  exportVisits(): string {
    return this.transferCodec.encodeVisits(this.repository.listVisits());
  }

  async importVisits(payload: string): Promise<HistoryImportResult> {
    const decoded = this.transferCodec.decodeVisits(payload);
    const deduped = this.deduplicateTransferVisits(decoded);
    const importedCount = await this.repository.importVisits(deduped);
    return {
      importedCount: importedCount,
      skippedCount: decoded.length - deduped.length
    };
  }

  listVisitsForManagement(limit: number | undefined, boundary: HistoryManagementBoundary): HistoryVisit[] {
    this.assertManagementEffectAllowed('regular_profile_management_read', 'regular_profile_data', boundary);
    return this.listVisits(limit);
  }

  refreshPreviewForManagement(limit: number, boundary: HistoryManagementBoundary): Promise<HistoryVisit[]> {
    this.assertManagementEffectAllowed('regular_profile_management_read', 'regular_profile_data', boundary);
    return this.refreshPreview(limit);
  }

  refreshPageForManagement(
    offset: number,
    limit: number,
    boundary: HistoryManagementBoundary
  ): Promise<HistoryVisit[]> {
    this.assertManagementEffectAllowed('regular_profile_management_read', 'regular_profile_data', boundary);
    return this.refreshPage(offset, limit);
  }

  refreshSearchPageForManagement(
    query: string,
    offset: number,
    limit: number,
    boundary: HistoryManagementBoundary
  ): Promise<HistoryVisit[]> {
    this.assertManagementEffectAllowed('regular_profile_management_read', 'regular_profile_data', boundary);
    return this.refreshSearchPage(query, offset, limit);
  }

  refreshSitePageForManagement(
    query: string,
    offset: number,
    limit: number,
    boundary: HistoryManagementBoundary
  ): Promise<HistorySiteAggregate[]> {
    this.assertManagementEffectAllowed('regular_profile_management_read', 'regular_profile_data', boundary);
    return this.refreshSitePage(query, offset, limit);
  }

  deleteVisitsByHostForManagement(host: string, boundary: HistoryManagementBoundary): Promise<number> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', 'regular_profile_data', boundary);
    return this.deleteVisitsByHost(host);
  }

  deleteVisitsByIdsForManagement(ids: string[], boundary: HistoryManagementBoundary): Promise<number> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', 'regular_profile_data', boundary);
    return this.deleteVisitsByIds(ids);
  }

  clearVisitsForManagement(boundary: HistoryManagementBoundary): Promise<number> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', 'regular_profile_data', boundary);
    return this.clearVisits();
  }

  importVisitsForManagement(
    payload: string,
    boundary: HistoryManagementBoundary
  ): Promise<HistoryImportResult> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', 'regular_profile_data', boundary);
    return this.importVisits(payload);
  }

  exportVisitsForManagement(boundary: HistoryManagementBoundary): string {
    this.assertManagementEffectAllowed(
      'regular_profile_management_export',
      'user_selected_external_location',
      boundary
    );
    return this.exportVisits();
  }

  authorizeNavigationForManagement(boundary: HistoryManagementBoundary): void {
    this.assertManagementEffectAllowed(
      'regular_profile_management_navigation',
      'regular_profile_data',
      boundary
    );
  }

  authorizeShareForManagement(boundary: HistoryManagementBoundary): void {
    this.assertManagementEffectAllowed(
      'regular_profile_management_share',
      'regular_profile_data',
      boundary
    );
  }

  async seedStressFixtureForManagement(
    database: BrowserDatabase,
    targetTotalCount: number,
    boundary: HistoryManagementBoundary
  ): Promise<HistoryStressSeedResult> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', 'regular_profile_data', boundary);
    const safeTarget = Math.max(0, Math.floor(targetTotalCount));
    await this.updateHistoryRetentionSettingsForBoundary({
      enabled: true,
      maxAgeDays: 90,
      maxRows: 50000
    }, {
      dataScope: boundary.dataScope,
      privacyMode: boundary.privacyMode
    });
    const insertedCount = await database.seedHistoryStressFixture(safeTarget);
    await this.refreshPreviewForManagement(HISTORY_STRESS_PREVIEW_CACHE_LIMIT, boundary);
    return {
      insertedCount: insertedCount,
      targetTotalCount: safeTarget
    };
  }

  canReadForManagement(boundary: HistoryManagementBoundary): boolean {
    return this.isManagementEffectAllowed(
      'regular_profile_management_read',
      'regular_profile_data',
      boundary
    );
  }

  canMutateForManagement(boundary: HistoryManagementBoundary): boolean {
    return this.isManagementEffectAllowed(
      'regular_profile_management_mutation',
      'regular_profile_data',
      boundary
    );
  }

  getHistoryRetentionSettings(): HistoryRetentionSettings {
    const preferences = this.preferencesRepository?.getPreferences();
    if (preferences !== undefined) {
      return preferences.historyRetention;
    }
    return DEFAULT_HISTORY_RETENTION_SETTINGS;
  }

  async updateHistoryRetentionSettings(settings: HistoryRetentionSettings): Promise<HistoryRetentionSettings> {
    if (this.preferencesRepository === undefined) {
      return settings;
    }
    const preferences = await this.preferencesRepository.updateHistoryRetentionSettings(settings);
    return preferences.historyRetention;
  }

  async updateHistoryRetentionSettingsForBoundary(
    settings: HistoryRetentionSettings,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<HistoryRetentionSettings> {
    const decision = this.privacyEffectPolicy.decide({
      intent: 'settings_device_preference_write',
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'device_preferences',
      targetIsClear: true
    });
    if (decision.outcome !== 'allow') {
      throw new Error('History retention device preference write privacy effect was not allowed.');
    }
    return this.updateHistoryRetentionSettings(settings);
  }

  applyRetentionPolicy(settings?: HistoryRetentionSettings): Promise<number> {
    this.writesSinceRetentionPolicy = 0;
    this.lastRetentionPolicyAppliedAt = Date.now();
    const resolvedSettings = settings ?? this.getHistoryRetentionSettings();
    if (!resolvedSettings.enabled) {
      return this.repository.clearVisits('retention');
    }
    const visits = this.repository.listVisits();
    const deletingIds = this.resolveRetentionDeletingIds(visits, resolvedSettings);
    if (deletingIds.length === 0) {
      return Promise.resolve(0);
    }
    return this.repository.deleteVisitsByIds(deletingIds, 'retention');
  }

  applyRetentionPolicyForManagement(
    settings: HistoryRetentionSettings,
    boundary: HistoryManagementBoundary
  ): Promise<number> {
    this.assertManagementEffectAllowed('regular_profile_management_mutation', 'regular_profile_data', boundary);
    return this.applyRetentionPolicy(settings);
  }

  private applyRetentionPolicyAfterWrite(now: number): Promise<number> {
    this.writesSinceRetentionPolicy += 1;
    if (this.lastRetentionPolicyAppliedAt <= 0 ||
      now - this.lastRetentionPolicyAppliedAt >= HISTORY_RETENTION_MIN_INTERVAL_MS ||
      this.writesSinceRetentionPolicy >= HISTORY_RETENTION_WRITE_BATCH_SIZE) {
      return this.applyRetentionPolicy();
    }
    return Promise.resolve(0);
  }

  listSuggestions(limit?: number): HistoryVisit[] {
    return this.repository.listSuggestions(limit);
  }

  refresh(): Promise<HistoryVisit[]> {
    return this.repository.refresh();
  }

  refreshPreview(limit: number): Promise<HistoryVisit[]> {
    return this.repository.refreshPreview(limit);
  }

  refreshPage(offset: number, limit: number): Promise<HistoryVisit[]> {
    return this.repository.refreshPage(offset, limit);
  }

  refreshSearchPage(query: string, offset: number, limit: number): Promise<HistoryVisit[]> {
    return this.repository.refreshSearchPage(query, offset, limit);
  }

  refreshSitePage(query: string, offset: number, limit: number): Promise<HistorySiteAggregate[]> {
    return this.repository.refreshSitePage(query, offset, limit);
  }

  private assertManagementEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    targetScope: BrowserPrivacyEffectTargetScope,
    boundary: HistoryManagementBoundary
  ): void {
    if (!this.isManagementEffectAllowed(intent, targetScope, boundary)) {
      throw new Error('History management privacy effect was not allowed.');
    }
  }

  private isManagementEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    targetScope: BrowserPrivacyEffectTargetScope,
    boundary: HistoryManagementBoundary
  ): boolean {
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary({
        dataScope: boundary.dataScope,
        privacyMode: boundary.privacyMode
      }),
      targetScope: targetScope,
      targetIsClear: true
    }).outcome === 'allow';
  }

  private resolveRetentionDeletingIds(
    visits: HistoryVisit[],
    settings: HistoryRetentionSettings
  ): string[] {
    const now = Date.now();
    const maxAgeMs = Math.max(1, settings.maxAgeDays) * 24 * 60 * 60 * 1000;
    const cutoff = now - maxAgeMs;
    const ordered = visits
      .slice()
      .sort((left: HistoryVisit, right: HistoryVisit) => right.visitedAt - left.visitedAt);
    const deletingIds: string[] = [];
    ordered.forEach((visit: HistoryVisit, index: number) => {
      if (visit.visitedAt < cutoff || index >= settings.maxRows) {
        deletingIds.push(visit.id);
      }
    });
    return Array.from(new Set<string>(deletingIds));
  }

  private deduplicateTransferVisits(visits: HistoryTransferVisit[]): HistoryTransferVisit[] {
    const existingKeys = new Set<string>(this.repository.listVisits().map((visit: HistoryVisit) => {
      return this.buildTransferVisitKey(visit.url, visit.visitedAt);
    }));
    const seenKeys = new Set<string>();
    const deduped: HistoryTransferVisit[] = [];
    visits.forEach((visit: HistoryTransferVisit) => {
      const key = this.buildTransferVisitKey(visit.url, visit.visitedAt);
      if (existingKeys.has(key) || seenKeys.has(key)) {
        return;
      }
      seenKeys.add(key);
      deduped.push(visit);
    });
    return deduped;
  }

  private buildTransferVisitKey(url: string, visitedAt: number): string {
    return `${url.trim().toLowerCase()}@${Math.round(visitedAt)}`;
  }
}
