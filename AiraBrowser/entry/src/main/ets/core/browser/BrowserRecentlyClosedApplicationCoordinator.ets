import {
  BrowserDataScope,
  BrowserProfileId,
  BrowserSessionPrivacyMode,
  ShortcutRecord
} from '../../common/models/BrowserModels';
import { getBrowserAppRuntimeInitializationPromise } from '../../app/bootstrap/BrowserAppRuntime';
import { RecentlyClosedTabRepository } from '../../data/repositories/BrowserRepositories';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { BrowserClipboardService } from '../../services/share/BrowserClipboardService';
import { BrowserPrivacyEffectPolicyService } from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { HomeShortcutToggleService } from '../../services/shortcuts/HomeShortcutToggleService';
import { SiteClearOnCloseLifecycleService } from '../../services/web/SiteClearOnCloseLifecycleService';
import { BrowserTabState } from '../tabs/TabManager';
import { BrowserConfirmationRequest } from './BrowserConfirmationSink';
import { BrowserHomePresentationViewModel } from './BrowserHomePresentationViewModel';
import {
  HomeContentRecentlyClosedLayoutState,
  HomeRecentlyClosedPresentationState
} from './HomeContentPresentationState';
import {
  HomeRecentlyClosedIconHydrationCallbacks,
  HomeRecentlyClosedIconHydrationCoordinator,
  HomeRecentlyClosedIconHydrationSnapshot,
  HomeRecentlyClosedIconState
} from './HomeRecentlyClosedIconHydrationCoordinator';
import {
  BrowserRecentlyClosedTabRecord,
  BrowserRecentlyClosedTabsService,
  BrowserRestoreRecentlyClosedTabResult
} from './BrowserRecentlyClosedTabsService';

const HOME_RECENTLY_CLOSED_SECTION_ID_PREFIX: string = 'home-recently-closed-section';
const HOME_RECENTLY_CLOSED_SECTION_REBUILD_DELAY_MS: number = 24;
const RECENTLY_CLOSED_SESSION_LIMIT: number = 12;

export interface BrowserRecentlyClosedApplicationFacts {
  currentWindowId: string;
  currentProfileId: BrowserProfileId;
  dataScope: BrowserDataScope;
  privacyMode: BrowserSessionPrivacyMode;
  showHomePage: boolean;
}

export interface BrowserRecentlyClosedApplicationShell {
  resolveFacts: () => BrowserRecentlyClosedApplicationFacts;
  publishSnapshot: (snapshot: BrowserRecentlyClosedApplicationSnapshot) => void;
  presentBoundaryBlock: (eventType: string, summaryLine: string, helperText: string) => void;
  showToast: (message: string) => void;
  showDialog: (title: string, message: string) => void;
  confirmDelete: (confirmation: BrowserConfirmationRequest) => void;
  refreshHomeShortcuts: () => void;
}

export interface BrowserRecentlyClosedApplicationDependencies {
  repository: RecentlyClosedTabRepository;
  preferencesRepository: PreferencesRepository;
  homeShortcutToggleService: HomeShortcutToggleService;
  clipboardService: BrowserClipboardService;
  tabsService: BrowserRecentlyClosedTabsService;
  homePresentationViewModel: BrowserHomePresentationViewModel;
  siteClearOnCloseLifecycleService: SiteClearOnCloseLifecycleService;
}

export interface BrowserRecentlyClosedApplicationSnapshot {
  recordCount: number;
  records: BrowserRecentlyClosedTabRecord[];
  displayRecords: BrowserRecentlyClosedTabRecord[];
  renderVersion: number;
  iconSyncVersion: number;
  icons: HomeRecentlyClosedIconState[];
  showHomeSection: boolean;
  homeSectionExpanded: boolean;
  homeSectionMounted: boolean;
  homeSectionId: string;
  homeDisplayLimit: number;
  homeShortcutRecordIds: string[];
}

export function createBrowserRecentlyClosedApplicationSnapshot(): BrowserRecentlyClosedApplicationSnapshot {
  return {
    recordCount: 0,
    records: [],
    displayRecords: [],
    renderVersion: 0,
    iconSyncVersion: 0,
    icons: [],
    showHomeSection: false,
    homeSectionExpanded: true,
    homeSectionMounted: true,
    homeSectionId: '',
    homeDisplayLimit: 0,
    homeShortcutRecordIds: []
  };
}

export type BrowserRecentlyClosedRecordUserActionType =
  'copy_record_url' |
  'request_delete_record' |
  'confirm_delete_record' |
  'toggle_home_shortcut';

export interface BrowserRecentlyClosedToggleHomeSectionAction {
  type: 'toggle_home_section';
}

export interface BrowserRecentlyClosedRecordUserAction {
  type: BrowserRecentlyClosedRecordUserActionType;
  recordId: string;
}

export type BrowserRecentlyClosedUserAction =
  BrowserRecentlyClosedToggleHomeSectionAction | BrowserRecentlyClosedRecordUserAction;

export interface BrowserRecentlyClosedRecordOutcome {
  recorded: boolean;
  reason: string;
  summaryLine: string;
}

export interface BrowserRecentlyClosedBoundaryDecision {
  allowed: boolean;
  helperText: string;
  summaryLine: string;
}

type BrowserRecentlyClosedBoundaryAction =
  'restore_recently_closed_tab' |
  'copy_recently_closed_tab_url' |
  'delete_recently_closed_tab';

interface BrowserRecentlyClosedRecordLookup {
  found: boolean;
  title: string;
  url: string;
  originalTabId: string;
  missingMessage: string;
}

export class BrowserRecentlyClosedApplicationCoordinator {
  private readonly dependencies: BrowserRecentlyClosedApplicationDependencies;
  private readonly shell: BrowserRecentlyClosedApplicationShell;
  private readonly iconHydrationCoordinator: HomeRecentlyClosedIconHydrationCoordinator =
    new HomeRecentlyClosedIconHydrationCoordinator();
  private readonly privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService();
  private readonly iconHydrationCallbacks: HomeRecentlyClosedIconHydrationCallbacks;

  private records: BrowserRecentlyClosedTabRecord[] = [];
  private displayRecords: BrowserRecentlyClosedTabRecord[] = [];
  private icons: HomeRecentlyClosedIconState[] = [];
  private renderVersion: number = 0;
  private iconSyncVersion: number = 0;
  private showHomeSection: boolean;
  private homeSectionExpanded: boolean = true;
  private homeSectionMounted: boolean = true;
  private homeSectionRevision: number = 0;
  private homeDisplayLimit: number;
  private homeShortcutRecordIds: string[] = [];
  private homeShortcuts: ShortcutRecord[] = [];
  private homeShortcutGroupId: string = '';
  private primeGeneration: number = 0;
  private mutationGeneration: number = 0;
  private sectionRebuildGeneration: number = 0;
  private sectionRebuildTimer: number = -1;

  constructor(
    dependencies: BrowserRecentlyClosedApplicationDependencies,
    shell: BrowserRecentlyClosedApplicationShell
  ) {
    this.dependencies = dependencies;
    this.shell = shell;
    const preferences = dependencies.preferencesRepository.getPreferences();
    this.showHomeSection = preferences.appearance.showHomeRecentlyClosed;
    this.homeDisplayLimit = preferences.appearance.homeRecentlyClosedLimit;
    this.iconHydrationCallbacks = {
      applySnapshot: (snapshot: HomeRecentlyClosedIconHydrationSnapshot): void => {
        this.applyIconHydrationSnapshot(snapshot);
      },
      persistResolvedIcon: (recordId: string, iconPath: string): void => {
        this.persistResolvedIcon(recordId, iconPath);
      }
    };
  }

  getSnapshot(): BrowserRecentlyClosedApplicationSnapshot {
    const facts = this.shell.resolveFacts();
    const policy = this.privacyEffectPolicy.resolveDataPolicy('recently_closed_tab', {
      dataScope: facts.dataScope,
      privacyMode: facts.privacyMode
    });
    const persistentReadAllowed = policy.persistentReadAllowed;
    return {
      recordCount: persistentReadAllowed ? this.records.length : 0,
      records: persistentReadAllowed ? this.records.slice() : [],
      displayRecords: persistentReadAllowed ? this.displayRecords.slice() : [],
      renderVersion: this.renderVersion,
      iconSyncVersion: this.iconSyncVersion,
      icons: persistentReadAllowed ? this.icons.slice() : [],
      showHomeSection: persistentReadAllowed && this.showHomeSection,
      homeSectionExpanded: this.homeSectionExpanded,
      homeSectionMounted: this.homeSectionMounted,
      homeSectionId: `${HOME_RECENTLY_CLOSED_SECTION_ID_PREFIX}-${this.homeSectionRevision}`,
      homeDisplayLimit: this.homeDisplayLimit,
      homeShortcutRecordIds: persistentReadAllowed ? this.homeShortcutRecordIds.slice() : []
    };
  }

  buildHomePresentationState(
    snapshot: BrowserRecentlyClosedApplicationSnapshot,
    layout: HomeContentRecentlyClosedLayoutState
  ): HomeRecentlyClosedPresentationState {
    return {
      sectionId: snapshot.homeSectionId,
      records: snapshot.displayRecords,
      limit: snapshot.homeDisplayLimit,
      columns: layout.columns,
      columnGap: layout.columnGap,
      rowGap: layout.rowGap,
      renderVersion: snapshot.renderVersion,
      iconSyncVersion: snapshot.iconSyncVersion,
      icons: snapshot.icons,
      homeShortcutRecordIds: snapshot.homeShortcutRecordIds
    };
  }

  shouldShowHomeSection(snapshot: BrowserRecentlyClosedApplicationSnapshot, privateMode: boolean): boolean {
    return snapshot.showHomeSection && !privateMode && snapshot.homeSectionMounted;
  }

  refreshAppearance(): void {
    const preferences = this.dependencies.preferencesRepository.getPreferences();
    const nextShowHomeSection = preferences.appearance.showHomeRecentlyClosed;
    const nextDisplayLimit = preferences.appearance.homeRecentlyClosedLimit;
    if (this.showHomeSection === nextShowHomeSection && this.homeDisplayLimit === nextDisplayLimit) {
      this.publishSnapshot();
      return;
    }
    const displayLimitChanged = this.homeDisplayLimit !== nextDisplayLimit;
    this.showHomeSection = nextShowHomeSection;
    this.homeDisplayLimit = nextDisplayLimit;
    if (!nextShowHomeSection) {
      void this.clearDisabledRecords();
      return;
    }
    if (displayLimitChanged) {
      this.displayRecords = this.buildDisplayRecords(this.records, this.homeDisplayLimit);
      this.resolveIconsForDisplayRecords();
    }
    this.publishSnapshot();
  }

  synchronizeHomeShortcuts(shortcuts: ShortcutRecord[], groupId: string): void {
    this.homeShortcuts = shortcuts.slice();
    this.homeShortcutGroupId = groupId;
    const nextRecordIds = this.buildHomeShortcutRecordIds();
    if (this.areStringListsEqual(this.homeShortcutRecordIds, nextRecordIds)) {
      return;
    }
    this.homeShortcutRecordIds = nextRecordIds;
    this.publishSnapshot();
  }

  handleUserAction(action: BrowserRecentlyClosedUserAction): void {
    switch (action.type) {
      case 'toggle_home_section':
        this.homeSectionExpanded = !this.homeSectionExpanded;
        this.publishSnapshot();
        return;
      case 'copy_record_url':
        this.copyRecordUrl(action.recordId);
        return;
      case 'request_delete_record':
        this.requestDeleteRecord(action.recordId);
        return;
      case 'confirm_delete_record':
        this.deleteRecord(action.recordId);
        return;
      case 'toggle_home_shortcut':
        this.toggleHomeShortcut(action.recordId);
        return;
    }
  }

  recordClosedTab(tab: BrowserTabState | undefined): BrowserRecentlyClosedRecordOutcome {
    if (!this.isRecentlyClosedEnabled()) {
      if (this.hasRecordsForCurrentBoundary()) {
        void this.clearDisabledRecords();
      }
      return {
        recorded: false,
        reason: 'setting_disabled',
        summaryLine: 'recentlyClosedRecord recorded=0 reason=setting_disabled total=0'
      };
    }
    const windowId = this.shell.resolveFacts().currentWindowId;
    const result = this.dependencies.tabsService.recordClosedTab(
      this.records,
      tab,
      windowId,
      RECENTLY_CLOSED_SESSION_LIMIT
    );
    if (result.recorded) {
      this.applyMutation(result.records);
    }
    return {
      recorded: result.recorded,
      reason: result.reason,
      summaryLine: result.summaryLine
    };
  }

  prepareRestoreByRecordId(
    tabs: BrowserTabState[],
    activeTabId: string,
    recordId: string
  ): BrowserRestoreRecentlyClosedTabResult {
    const records = this.isRecentlyClosedEnabled() ? this.records : [];
    return this.dependencies.tabsService.restoreByRecordId(tabs, activeTabId, records, recordId);
  }

  buildRestoreBoundaryDecision(
    dataScope: BrowserDataScope,
    privacyMode: BrowserSessionPrivacyMode
  ): BrowserRecentlyClosedBoundaryDecision {
    return this.buildBoundaryDecision('restore_recently_closed_tab', dataScope, privacyMode);
  }

  prepareRestoreLatest(tabs: BrowserTabState[], activeTabId: string): BrowserRestoreRecentlyClosedTabResult {
    const records = this.isRecentlyClosedEnabled() ? this.records : [];
    return this.dependencies.tabsService.restoreLatest(tabs, activeTabId, records);
  }

  acceptRestoredRecords(records: BrowserRecentlyClosedTabRecord[]): void {
    this.applyMutation(records);
  }

  removeRecordsForHost(targetHost: string): number {
    const normalizedHost = targetHost.trim();
    if (normalizedHost.length === 0) {
      return 0;
    }
    const nextRecords = this.records.filter((record: BrowserRecentlyClosedTabRecord) => {
      return !this.dependencies.siteClearOnCloseLifecycleService.matchesHost(
        this.resolveRecordUrl(record),
        '',
        normalizedHost
      );
    });
    const removed = this.records.length - nextRecords.length;
    if (removed > 0) {
      this.applyMutation(nextRecords);
    }
    return removed;
  }

  activateWindow(profileId: BrowserProfileId): void {
    if (!this.isRecentlyClosedEnabled()) {
      void this.clearDisabledRecords();
      return;
    }
    const primeGeneration = this.primeGeneration + 1;
    this.primeGeneration = primeGeneration;
    const mutationGeneration = this.mutationGeneration;
    const windowId = this.shell.resolveFacts().currentWindowId;
    const cachedRecords = this.dependencies.repository.listRecords(windowId, profileId);
    if (cachedRecords.length > 0) {
      this.applyRecordsSnapshot(cachedRecords);
    }
    void this.dependencies.repository.primeFromSnapshot(windowId, profileId)
      .then((records: BrowserRecentlyClosedTabRecord[]) => {
        if (!this.isCurrentLoad(primeGeneration, mutationGeneration)) {
          return;
        }
        if (records.length > 0) {
          this.applyRecordsSnapshot(records);
        }
      })
      .catch((_error: Error) => {
      });
    void this.load(profileId, false, primeGeneration);
    this.refreshAfterRuntimeReady(profileId);
  }

  loadForStartup(profileId: BrowserProfileId): Promise<void> {
    if (!this.isRecentlyClosedEnabled()) {
      return this.clearDisabledRecords();
    }
    return this.load(profileId, true, -1);
  }

  flushForWindowSwitch(): void {
    this.persist();
  }

  private refreshAfterRuntimeReady(profileId: BrowserProfileId): void {
    const runtimeInitialization = getBrowserAppRuntimeInitializationPromise();
    if (runtimeInitialization === undefined) {
      return;
    }
    const expectedWindowId = this.shell.resolveFacts().currentWindowId;
    const primeGeneration = this.primeGeneration;
    runtimeInitialization
      .then(() => {
        const facts = this.shell.resolveFacts();
        if (facts.currentWindowId !== expectedWindowId || this.primeGeneration !== primeGeneration) {
          return;
        }
        void this.load(profileId, true, primeGeneration);
      })
      .catch((_error: Error) => {
      });
  }

  private load(
    profileId: BrowserProfileId,
    allowEmptyOverwrite: boolean,
    expectedPrimeGeneration: number
  ): Promise<void> {
    const mutationGeneration = this.mutationGeneration;
    const windowId = this.shell.resolveFacts().currentWindowId;
    return this.dependencies.repository.refresh(windowId, profileId)
      .then((records: BrowserRecentlyClosedTabRecord[]) => {
        if (expectedPrimeGeneration >= 0 && this.primeGeneration !== expectedPrimeGeneration) {
          return;
        }
        if (this.mutationGeneration !== mutationGeneration) {
          return;
        }
        if (records.length <= 0 && !allowEmptyOverwrite && this.records.length > 0) {
          return;
        }
        this.applyRecordsSnapshot(records);
      })
      .catch((_error: Error) => {
        if (!allowEmptyOverwrite || this.mutationGeneration !== mutationGeneration) {
          return;
        }
        this.applyRecordsSnapshot([]);
      });
  }

  private cache(): void {
    const facts = this.shell.resolveFacts();
    this.dependencies.repository.replaceCachedRecords(
      this.records,
      facts.currentWindowId,
      facts.currentProfileId
    );
  }

  private persist(): void {
    const facts = this.shell.resolveFacts();
    this.cache();
    this.dependencies.repository.replaceRecords(
      this.records,
      facts.currentWindowId,
      facts.currentProfileId
    )
      .catch((_error: Error) => {
      });
  }

  resetForWindowSwitch(): void {
    this.primeGeneration += 1;
    this.mutationGeneration += 1;
    const remountWasPending = !this.homeSectionMounted;
    this.cancelSectionRebuild();
    if (remountWasPending) {
      this.homeSectionExpanded = true;
      this.homeSectionMounted = true;
    }
    this.records = [];
    this.displayRecords = [];
    this.homeShortcutRecordIds = [];
    this.renderVersion += 1;
    this.iconHydrationCoordinator.clear(this.iconHydrationCallbacks);
    this.publishSnapshot();
  }

  private copyRecordUrl(recordId: string): void {
    if (!this.allowManagementAccess('copy_recently_closed_tab_url')) {
      return;
    }
    const lookup = this.buildRecordLookup(recordId);
    if (!lookup.found) {
      this.shell.showToast(lookup.missingMessage);
      return;
    }
    this.dependencies.clipboardService.copyText({
      value: lookup.url,
      emptyMessage: '当前没有可复制的链接。',
      successMessage: '链接已复制。'
    })
      .then((result) => {
        this.shell.showToast(result.message);
      })
      .catch((_error: Error) => {
        this.shell.showToast('复制失败，请稍后重试。');
      });
  }

  private requestDeleteRecord(recordId: string): void {
    if (!this.allowManagementAccess('delete_recently_closed_tab')) {
      return;
    }
    const lookup = this.buildRecordLookup(recordId);
    if (!lookup.found) {
      this.shell.showToast(lookup.missingMessage);
      return;
    }
    this.shell.confirmDelete({
      title: '删除最近记录',
      message: `确定删除“${lookup.title}”吗？此操作无法撤销。`,
      cancelLabel: '取消',
      confirmLabel: '删除',
      confirmTone: 'alert',
      onConfirm: (): void => {
        this.handleUserAction({ type: 'confirm_delete_record', recordId: recordId });
      }
    });
  }

  private deleteRecord(recordId: string): void {
    if (!this.allowManagementAccess('delete_recently_closed_tab')) {
      return;
    }
    const lookup = this.buildRecordLookup(recordId);
    if (!lookup.found) {
      this.shell.showToast(lookup.missingMessage);
      return;
    }
    const nextRecords = this.records.filter((record: BrowserRecentlyClosedTabRecord) => record.id !== recordId);
    this.applyMutation(nextRecords);
    this.shell.showToast('记录已删除。');
  }

  private toggleHomeShortcut(recordId: string): void {
    if (!this.allowHomeShortcutWrite()) {
      return;
    }
    const lookup = this.buildRecordLookup(recordId);
    if (!lookup.found) {
      this.shell.showToast(lookup.missingMessage);
      return;
    }
    this.dependencies.homeShortcutToggleService.toggle({
      title: lookup.title,
      url: lookup.url,
      scenarioId: this.homeShortcutGroupId
    })
      .then((result) => {
        this.shell.refreshHomeShortcuts();
        this.shell.showToast(result.added ? '已添加到主页。' : '已从主页移除。');
      })
      .catch((error: Error) => {
        this.shell.showDialog('操作失败', `更新主页快捷方式失败：${this.stringifyError(error)}`);
      });
  }

  private allowManagementAccess(action: BrowserRecentlyClosedBoundaryAction): boolean {
    const facts = this.shell.resolveFacts();
    const decision = this.buildBoundaryDecision(
      action,
      facts.dataScope,
      facts.privacyMode
    );
    if (!decision.allowed) {
      this.shell.presentBoundaryBlock(
        'private_recently_closed_access_blocked',
        decision.summaryLine,
        decision.helperText
      );
    }
    return decision.allowed;
  }

  private allowHomeShortcutWrite(): boolean {
    const facts = this.shell.resolveFacts();
    const policy = this.privacyEffectPolicy.resolveDataPolicy('home_shortcuts', {
      dataScope: facts.dataScope,
      privacyMode: facts.privacyMode
    });
    if (!policy.persistentWriteAllowed) {
      this.shell.presentBoundaryBlock(
        'private_persistent_write_blocked',
        policy.summaryLine,
        '当前私密会话不可修改常规首页快捷方式。'
      );
    }
    return policy.persistentWriteAllowed;
  }

  private buildBoundaryDecision(
    action: BrowserRecentlyClosedBoundaryAction,
    dataScope: BrowserDataScope,
    privacyMode: BrowserSessionPrivacyMode
  ): BrowserRecentlyClosedBoundaryDecision {
    const policy = this.privacyEffectPolicy.resolveDataPolicy('recently_closed_tab', {
      dataScope: dataScope,
      privacyMode: privacyMode
    });
    const mutation = action === 'delete_recently_closed_tab';
    const allowed = mutation
      ? policy.persistentReadAllowed && policy.persistentWriteAllowed
      : policy.persistentReadAllowed;
    return {
      allowed: allowed,
      helperText: allowed
        ? '最近关闭操作可访问当前常规浏览资料。'
        : '当前私密会话不会展示、恢复或修改常规最近关闭记录。',
      summaryLine: `recentlyClosedBoundary action=${action} dataScope=${dataScope} privacy=${privacyMode} ` +
        `allowed=${allowed ? 1 : 0} read=${policy.persistentReadAllowed ? 1 : 0} ` +
        `write=${policy.persistentWriteAllowed ? 1 : 0}`
    };
  }

  private applyMutation(records: BrowserRecentlyClosedTabRecord[]): void {
    this.mutationGeneration += 1;
    this.applyRecordsSnapshot(records);
    this.persist();
  }

  private isRecentlyClosedEnabled(): boolean {
    return this.dependencies.preferencesRepository.getPreferences().appearance.showHomeRecentlyClosed;
  }

  private hasRecordsForCurrentBoundary(): boolean {
    if (this.records.length > 0) {
      return true;
    }
    const facts = this.shell.resolveFacts();
    return this.dependencies.repository.listRecords(
      facts.currentWindowId,
      facts.currentProfileId
    ).length > 0;
  }

  private clearDisabledRecords(): Promise<void> {
    this.mutationGeneration += 1;
    this.applyRecordsSnapshot([]);
    return this.dependencies.repository.clearAllRecords()
      .then((): void => undefined)
      .catch((_error: Error): void => undefined);
  }

  private applyRecordsSnapshot(records: BrowserRecentlyClosedTabRecord[]): void {
    const previousRecords = this.records.slice();
    this.records = records.slice();
    this.displayRecords = this.buildDisplayRecords(this.records, this.homeDisplayLimit);
    this.renderVersion += 1;
    this.homeShortcutRecordIds = this.buildHomeShortcutRecordIds();
    this.prepareHomeSectionRemount(previousRecords, this.records);
    this.publishSnapshot();
    this.resolveIconsForDisplayRecords();
  }

  private prepareHomeSectionRemount(
    previousRecords: BrowserRecentlyClosedTabRecord[],
    nextRecords: BrowserRecentlyClosedTabRecord[]
  ): void {
    const facts = this.shell.resolveFacts();
    if (!this.dependencies.homePresentationViewModel.shouldRemountRecentlyClosedSection({
      showHomePage: facts.showHomePage,
      recentlyClosedExpanded: this.homeSectionExpanded,
      sectionMounted: this.homeSectionMounted,
      previousRecords: previousRecords,
      nextRecords: nextRecords,
      displayLimit: this.homeDisplayLimit
    })) {
      return;
    }
    this.cancelSectionRebuild();
    const rebuildGeneration = this.sectionRebuildGeneration + 1;
    this.sectionRebuildGeneration = rebuildGeneration;
    const restoreExpanded = this.homeSectionExpanded;
    this.homeSectionExpanded = false;
    this.homeSectionMounted = false;
    this.homeSectionRevision += 1;
    this.sectionRebuildTimer = setTimeout(() => {
      this.sectionRebuildTimer = -1;
      if (this.sectionRebuildGeneration !== rebuildGeneration) {
        return;
      }
      this.homeSectionExpanded = restoreExpanded;
      this.homeSectionMounted = true;
      this.publishSnapshot();
    }, HOME_RECENTLY_CLOSED_SECTION_REBUILD_DELAY_MS);
  }

  private cancelSectionRebuild(): void {
    if (this.sectionRebuildTimer >= 0) {
      clearTimeout(this.sectionRebuildTimer);
      this.sectionRebuildTimer = -1;
    }
    this.sectionRebuildGeneration += 1;
  }

  private resolveIconsForDisplayRecords(): void {
    this.iconHydrationCoordinator.resolveFor(this.displayRecords, this.iconHydrationCallbacks);
  }

  private applyIconHydrationSnapshot(snapshot: HomeRecentlyClosedIconHydrationSnapshot): void {
    this.icons = snapshot.icons.slice();
    this.iconSyncVersion += 1;
    this.publishSnapshot();
  }

  private persistResolvedIcon(recordId: string, iconPath: string): void {
    const result = this.dependencies.tabsService.updateRecordSiteIcon(this.records, recordId, iconPath);
    if (!result.updated) {
      return;
    }
    this.applyMutation(result.records);
  }

  private buildRecordLookup(recordId: string): BrowserRecentlyClosedRecordLookup {
    const record = this.records.find((item: BrowserRecentlyClosedTabRecord) => item.id === recordId);
    if (record === undefined) {
      return {
        found: false,
        title: '',
        url: '',
        originalTabId: '',
        missingMessage: '这个记录已经不存在。'
      };
    }
    const url = this.resolveRecordUrl(record);
    const title = record.tab.title.trim().length > 0 ? record.tab.title.trim() : record.tab.url.trim();
    return {
      found: true,
      title: title.length > 0 ? title : '未命名标签页',
      url: url,
      originalTabId: record.originalTabId,
      missingMessage: ''
    };
  }

  private resolveRecordUrl(record: BrowserRecentlyClosedTabRecord): string {
    if (record.tab.url.trim().length > 0) {
      return record.tab.url.trim();
    }
    if (record.tab.lastGoodUrl.trim().length > 0) {
      return record.tab.lastGoodUrl.trim();
    }
    return record.tab.pendingUrl.trim();
  }

  private buildDisplayRecords(
    records: BrowserRecentlyClosedTabRecord[],
    limit: number
  ): BrowserRecentlyClosedTabRecord[] {
    return records
      .slice()
      .sort((left: BrowserRecentlyClosedTabRecord, right: BrowserRecentlyClosedTabRecord) => right.closedAt - left.closedAt)
      .slice(0, Math.max(0, Math.floor(limit)));
  }

  private buildHomeShortcutRecordIds(): string[] {
    const recordIds: string[] = [];
    this.displayRecords.forEach((record: BrowserRecentlyClosedTabRecord) => {
      if (this.dependencies.homeShortcutToggleService.isUrlAddedToScenario(
        this.resolveRecordUrl(record),
        this.homeShortcuts,
        this.homeShortcutGroupId
      )) {
        recordIds.push(record.id);
      }
    });
    return recordIds;
  }

  private publishSnapshot(): void {
    this.shell.publishSnapshot(this.getSnapshot());
  }

  private isCurrentLoad(primeGeneration: number, mutationGeneration: number): boolean {
    return this.primeGeneration === primeGeneration && this.mutationGeneration === mutationGeneration;
  }

  private areStringListsEqual(left: string[], right: string[]): boolean {
    if (left.length !== right.length) {
      return false;
    }
    for (let index = 0; index < left.length; index += 1) {
      if (left[index] !== right[index]) {
        return false;
      }
    }
    return true;
  }

  private stringifyError(error: Error): string {
    return error.message.length > 0 ? error.message : `${error}`;
  }
}
