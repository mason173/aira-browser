import { HistorySiteAggregate, HistoryVisit } from '../../common/models/BrowserModels';
import { HistoryFeature, HistoryManagementBoundary } from '../../features/history/HistoryFeature';
import {
  HistoryDateGroup,
  HistoryDisplayVisit,
  HistorySiteGroup,
  HistoryViewMode,
  HistoryViewModel
} from '../../features/history/HistoryViewModel';
import {
  HISTORY_NATIVE_TAB_URL,
  browserNativeTabSceneService
} from '../browser/BrowserNativeTabSceneService';

const HISTORY_WORKSPACE_PAGE_SIZE: number = 100;

export type HistoryWorkspaceSelectionMode = 'replace' | 'toggle' | 'range';

export interface HistoryWorkspaceSnapshot {
  revision: number;
  loading: boolean;
  busy: boolean;
  query: string;
  viewMode: HistoryViewMode;
  site: string;
  routeUrl: string;
  visits: HistoryDisplayVisit[];
  groups: HistoryDateGroup[];
  sites: HistorySiteGroup[];
  selectedVisitIds: string[];
  selectionAnchorId: string;
  hasMore: boolean;
  message: string;
}

export function createEmptyHistoryWorkspaceSnapshot(): HistoryWorkspaceSnapshot {
  return {
    revision: 0,
    loading: true,
    busy: false,
    query: '',
    viewMode: 'timeline',
    site: '',
    routeUrl: HISTORY_NATIVE_TAB_URL,
    visits: [],
    groups: [],
    sites: [],
    selectedVisitIds: [],
    selectionAnchorId: '',
    hasMore: true,
    message: ''
  };
}

/**
 * Owns one PC native-History Window Session while the phone controller keeps
 * its touch presentation; both consume the same HistoryFeature domain owner.
 */
export class HistoryWorkspaceSessionCoordinator {
  private readonly historyFeature: HistoryFeature;
  private readonly viewModel: HistoryViewModel = new HistoryViewModel();
  private snapshotState: HistoryWorkspaceSnapshot = createEmptyHistoryWorkspaceSnapshot();
  private rawVisits: HistoryVisit[] = [];
  private rawSites: HistorySiteAggregate[] = [];
  private sourceOffset: number = 0;
  private requestSequence: number = 0;
  private initialized: boolean = false;
  private timelineScrollOffsetY: number = 0;
  private sitesScrollOffsetY: number = 0;
  private readonly managementBoundary: HistoryManagementBoundary;

  constructor(
    historyFeature: HistoryFeature,
    boundary: HistoryManagementBoundary
  ) {
    this.historyFeature = historyFeature;
    this.managementBoundary = boundary;
  }

  getSnapshot(): HistoryWorkspaceSnapshot {
    return {
      revision: this.snapshotState.revision,
      loading: this.snapshotState.loading,
      busy: this.snapshotState.busy,
      query: this.snapshotState.query,
      viewMode: this.snapshotState.viewMode,
      site: this.snapshotState.site,
      routeUrl: this.snapshotState.routeUrl,
      visits: this.snapshotState.visits.slice(),
      groups: this.snapshotState.groups.map((group: HistoryDateGroup): HistoryDateGroup => {
        return {
          key: group.key,
          label: group.label,
          visits: group.visits.slice()
        };
      }),
      sites: this.snapshotState.sites.map((site: HistorySiteGroup): HistorySiteGroup => ({
        key: site.key,
        host: site.host,
        origin: site.origin,
        title: site.title,
        latestTitle: site.latestTitle,
        latestUrl: site.latestUrl,
        latestVisitedAt: site.latestVisitedAt,
        visitCount: site.visitCount,
        uniqueUrlCount: site.uniqueUrlCount,
        visits: site.visits.slice()
      })),
      selectedVisitIds: this.snapshotState.selectedVisitIds.slice(),
      selectionAnchorId: this.snapshotState.selectionAnchorId,
      hasMore: this.snapshotState.hasMore,
      message: this.snapshotState.message
    };
  }

  async activate(routeUrl: string): Promise<HistoryWorkspaceSnapshot> {
    const normalizedRoute = routeUrl.trim().length > 0 ? routeUrl.trim() : HISTORY_NATIVE_TAB_URL;
    if (!this.canReadPersistentData()) {
      return this.activatePrivateBoundary(normalizedRoute);
    }
    if (this.initialized && normalizedRoute === this.snapshotState.routeUrl) {
      return this.getSnapshot();
    }
    return this.loadFirstPage(normalizedRoute, false);
  }

  async applyRoute(routeUrl: string): Promise<HistoryWorkspaceSnapshot> {
    const normalizedRoute = routeUrl.trim().length > 0 ? routeUrl.trim() : HISTORY_NATIVE_TAB_URL;
    if (this.initialized && normalizedRoute === this.snapshotState.routeUrl) {
      return this.getSnapshot();
    }
    if (!this.canReadPersistentData()) {
      return this.activatePrivateBoundary(normalizedRoute);
    }
    return this.loadFirstPage(normalizedRoute, false);
  }

  async setQuery(query: string): Promise<HistoryWorkspaceSnapshot> {
    const normalizedQuery = query.trim();
    if (this.initialized && normalizedQuery === this.snapshotState.query) {
      return this.getSnapshot();
    }
    const routeUrl = browserNativeTabSceneService.buildHistoryRoute({
      query: normalizedQuery,
      view: this.snapshotState.viewMode,
      site: ''
    });
    return this.canReadPersistentData()
      ? this.loadFirstPage(routeUrl, false)
      : this.activatePrivateBoundary(routeUrl);
  }

  async setViewMode(viewMode: HistoryViewMode): Promise<HistoryWorkspaceSnapshot> {
    if (viewMode === this.snapshotState.viewMode && this.snapshotState.site.length === 0) {
      return this.getSnapshot();
    }
    const routeUrl = browserNativeTabSceneService.buildHistoryRoute({
      query: this.snapshotState.query,
      view: viewMode,
      site: ''
    });
    return this.canReadPersistentData()
      ? this.loadFirstPage(routeUrl, false)
      : this.activatePrivateBoundary(routeUrl);
  }

  async openSite(site: HistorySiteGroup): Promise<HistoryWorkspaceSnapshot> {
    const routeUrl = browserNativeTabSceneService.buildHistoryRoute({
      query: this.snapshotState.query,
      view: 'timeline',
      site: site.host
    });
    return this.canReadPersistentData()
      ? this.loadFirstPage(routeUrl, false)
      : this.activatePrivateBoundary(routeUrl);
  }

  async loadNextPage(): Promise<HistoryWorkspaceSnapshot> {
    if (!this.canReadPersistentData() || this.snapshotState.loading ||
      this.snapshotState.busy || !this.snapshotState.hasMore) {
      return this.getSnapshot();
    }
    const sequence = ++this.requestSequence;
    this.snapshotState.loading = true;
    this.publish();
    try {
      if (this.snapshotState.viewMode === 'sites') {
        const page = await this.historyFeature.refreshSitePageForManagement(
          this.snapshotState.query,
          this.sourceOffset,
          HISTORY_WORKSPACE_PAGE_SIZE,
          this.managementBoundary
        );
        if (sequence !== this.requestSequence) {
          return this.getSnapshot();
        }
        this.sourceOffset += page.length;
        this.rawSites = this.mergeSites(this.rawSites, page);
        this.snapshotState.hasMore = page.length >= HISTORY_WORKSPACE_PAGE_SIZE;
        this.snapshotState.sites = this.viewModel.buildSiteGroupsFromAggregates(this.rawSites);
      } else {
        const effectiveQuery = this.snapshotState.site.length > 0 ? this.snapshotState.site : this.snapshotState.query;
        const page = effectiveQuery.length > 0
          ? await this.historyFeature.refreshSearchPageForManagement(
            effectiveQuery,
            this.sourceOffset,
            HISTORY_WORKSPACE_PAGE_SIZE,
            this.managementBoundary
          )
          : await this.historyFeature.refreshPageForManagement(
            this.sourceOffset,
            HISTORY_WORKSPACE_PAGE_SIZE,
            this.managementBoundary
          );
        if (sequence !== this.requestSequence) {
          return this.getSnapshot();
        }
        this.sourceOffset += page.length;
        this.rawVisits = this.mergeVisits(this.rawVisits, page);
        this.snapshotState.hasMore = page.length >= HISTORY_WORKSPACE_PAGE_SIZE;
        this.rebuildPresentation();
      }
      if (sequence !== this.requestSequence) {
        return this.getSnapshot();
      }
      this.snapshotState.message = '';
    } catch (error) {
      if (sequence === this.requestSequence) {
        this.snapshotState.message = `加载更多历史记录失败：${this.stringifyError(error as Error)}`;
      }
    }
    if (sequence === this.requestSequence) {
      this.snapshotState.loading = false;
      this.publish();
    }
    return this.getSnapshot();
  }

  selectVisit(visitId: string, mode: HistoryWorkspaceSelectionMode = 'replace'): HistoryWorkspaceSnapshot {
    if (this.snapshotState.visits.findIndex((visit: HistoryDisplayVisit): boolean => visit.id === visitId) < 0) {
      return this.getSnapshot();
    }
    if (mode === 'range') {
      this.selectRange(visitId);
    } else if (mode === 'toggle') {
      this.toggleSelection(visitId);
    } else {
      this.snapshotState.selectedVisitIds = [visitId];
      this.snapshotState.selectionAnchorId = visitId;
    }
    this.publish();
    return this.getSnapshot();
  }

  selectAll(): HistoryWorkspaceSnapshot {
    this.snapshotState.selectedVisitIds = this.snapshotState.visits
      .map((visit: HistoryDisplayVisit): string => visit.id);
    this.snapshotState.selectionAnchorId = this.snapshotState.selectedVisitIds[0] ?? '';
    this.publish();
    return this.getSnapshot();
  }

  clearSelection(): HistoryWorkspaceSnapshot {
    if (this.snapshotState.selectedVisitIds.length === 0 && this.snapshotState.selectionAnchorId.length === 0) {
      return this.getSnapshot();
    }
    this.snapshotState.selectedVisitIds = [];
    this.snapshotState.selectionAnchorId = '';
    this.publish();
    return this.getSnapshot();
  }

  findVisit(visitId: string): HistoryDisplayVisit | undefined {
    return this.snapshotState.visits.find((visit: HistoryDisplayVisit): boolean => visit.id === visitId);
  }

  getSelectedVisits(): HistoryDisplayVisit[] {
    const selected = new Set<string>(this.snapshotState.selectedVisitIds);
    return this.snapshotState.visits.filter((visit: HistoryDisplayVisit): boolean => selected.has(visit.id));
  }

  rememberScrollOffset(offsetY: number): void {
    const normalizedOffset = Number.isFinite(offsetY) ? Math.max(0, offsetY) : 0;
    if (this.snapshotState.viewMode === 'sites') {
      this.sitesScrollOffsetY = normalizedOffset;
    } else {
      this.timelineScrollOffsetY = normalizedOffset;
    }
  }

  getScrollOffset(): number {
    return this.snapshotState.viewMode === 'sites' ? this.sitesScrollOffsetY : this.timelineScrollOffsetY;
  }

  async deleteVisit(visitId: string): Promise<HistoryWorkspaceSnapshot> {
    if (!this.canWritePersistentData()) {
      return this.getSnapshot();
    }
    const visit = this.findVisit(visitId);
    if (visit === undefined || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    return this.deleteDisplayVisits([visit]);
  }

  async deleteSelection(): Promise<HistoryWorkspaceSnapshot> {
    if (!this.canWritePersistentData()) {
      return this.getSnapshot();
    }
    if (this.snapshotState.selectedVisitIds.length === 0 || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    const selectedLookup = new Set<string>(this.snapshotState.selectedVisitIds);
    const visits = this.snapshotState.visits
      .filter((visit: HistoryDisplayVisit): boolean => selectedLookup.has(visit.id));
    return this.deleteDisplayVisits(visits);
  }

  async deleteSite(host: string): Promise<HistoryWorkspaceSnapshot> {
    const normalizedHost = host.trim();
    if (!this.canWritePersistentData() || normalizedHost.length === 0 || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    this.snapshotState.busy = true;
    this.snapshotState.message = '';
    this.publish();
    try {
      const removed = await this.historyFeature.deleteVisitsByHostForManagement(
        normalizedHost,
        this.managementBoundary
      );
      if (removed <= 0) {
        this.snapshotState.message = '没有删除任何历史记录。';
      } else {
        const currentRoute = this.snapshotState.routeUrl;
        this.snapshotState.busy = false;
        return this.loadFirstPage(currentRoute, false);
      }
    } catch (error) {
      this.snapshotState.message = `删除站点历史记录失败：${this.stringifyError(error as Error)}`;
    }
    this.snapshotState.busy = false;
    this.publish();
    return this.getSnapshot();
  }

  async clearAll(): Promise<HistoryWorkspaceSnapshot> {
    if (!this.canWritePersistentData() || this.snapshotState.busy) {
      return this.getSnapshot();
    }
    this.snapshotState.busy = true;
    this.snapshotState.message = '';
    this.publish();
    try {
      await this.historyFeature.clearVisitsForManagement(this.managementBoundary);
      this.rawVisits = [];
      this.rawSites = [];
      this.sourceOffset = 0;
      this.snapshotState.hasMore = false;
      this.snapshotState.selectedVisitIds = [];
      this.snapshotState.selectionAnchorId = '';
      this.snapshotState.visits = [];
      this.snapshotState.groups = [];
      this.snapshotState.sites = [];
    } catch (error) {
      this.snapshotState.message = `清除历史记录失败：${this.stringifyError(error as Error)}`;
    }
    this.snapshotState.busy = false;
    this.publish();
    return this.getSnapshot();
  }

  private async loadFirstPage(routeUrl: string, preserveSelection: boolean): Promise<HistoryWorkspaceSnapshot> {
    if (!this.canReadPersistentData()) {
      return this.activatePrivateBoundary(routeUrl);
    }
    const sequence = ++this.requestSequence;
    const route = browserNativeTabSceneService.parseHistoryRoute(routeUrl);
    this.snapshotState.query = route.query;
    this.snapshotState.viewMode = route.site.length > 0 ? 'timeline' : route.view;
    this.snapshotState.site = route.site;
    this.snapshotState.routeUrl = browserNativeTabSceneService.buildHistoryRoute(route);
    this.snapshotState.loading = true;
    this.snapshotState.message = '';
    if (!preserveSelection) {
      this.snapshotState.selectedVisitIds = [];
      this.snapshotState.selectionAnchorId = '';
    }
    this.publish();
    try {
      if (this.snapshotState.viewMode === 'sites') {
        const page = await this.historyFeature.refreshSitePageForManagement(
          route.query,
          0,
          HISTORY_WORKSPACE_PAGE_SIZE,
          this.managementBoundary
        );
        if (sequence !== this.requestSequence) {
          return this.getSnapshot();
        }
        this.rawVisits = [];
        this.rawSites = page.slice();
        this.sourceOffset = page.length;
        this.snapshotState.hasMore = page.length >= HISTORY_WORKSPACE_PAGE_SIZE;
        this.snapshotState.visits = [];
        this.snapshotState.groups = [];
        this.snapshotState.sites = this.viewModel.buildSiteGroupsFromAggregates(page);
      } else {
        const effectiveQuery = route.site.length > 0 ? route.site : route.query;
        const page = effectiveQuery.length > 0
          ? await this.historyFeature.refreshSearchPageForManagement(
            effectiveQuery,
            0,
            HISTORY_WORKSPACE_PAGE_SIZE,
            this.managementBoundary
          )
          : await this.historyFeature.refreshPageForManagement(
            0,
            HISTORY_WORKSPACE_PAGE_SIZE,
            this.managementBoundary
          );
        if (sequence !== this.requestSequence) {
          return this.getSnapshot();
        }
        this.rawVisits = page.slice();
        this.rawSites = [];
        this.sourceOffset = page.length;
        this.snapshotState.hasMore = page.length >= HISTORY_WORKSPACE_PAGE_SIZE;
        this.snapshotState.sites = [];
        this.rebuildPresentation();
      }
      if (sequence !== this.requestSequence) {
        return this.getSnapshot();
      }
      this.initialized = true;
      this.pruneSelection();
    } catch (error) {
      if (sequence === this.requestSequence) {
        this.snapshotState.message = `加载历史记录失败：${this.stringifyError(error as Error)}`;
      }
    }
    if (sequence === this.requestSequence) {
      this.snapshotState.loading = false;
      this.publish();
    }
    return this.getSnapshot();
  }

  private async deleteDisplayVisits(visits: HistoryDisplayVisit[]): Promise<HistoryWorkspaceSnapshot> {
    const sourceIds = Array.from(new Set<string>(visits.flatMap((visit: HistoryDisplayVisit): string[] =>
      visit.sourceVisitIds)));
    if (sourceIds.length === 0) {
      return this.getSnapshot();
    }
    this.snapshotState.busy = true;
    this.snapshotState.message = '';
    this.publish();
    try {
      const removed = await this.historyFeature.deleteVisitsByIdsForManagement(sourceIds, this.managementBoundary);
      if (removed <= 0) {
        this.snapshotState.message = '没有删除任何历史记录。';
      } else {
        const sourceLookup = new Set<string>(sourceIds);
        this.rawVisits = this.rawVisits.filter((visit: HistoryVisit): boolean => !sourceLookup.has(visit.id));
        this.sourceOffset = Math.max(0, this.sourceOffset - removed);
        this.snapshotState.selectedVisitIds = [];
        this.snapshotState.selectionAnchorId = '';
        this.rebuildPresentation();
      }
    } catch (error) {
      this.snapshotState.message = `删除历史记录失败：${this.stringifyError(error as Error)}`;
    }
    this.snapshotState.busy = false;
    this.publish();
    return this.getSnapshot();
  }

  private rebuildPresentation(): void {
    const viewState = this.viewModel.buildViewState(this.rawVisits, '', 'timeline');
    this.snapshotState.visits = viewState.visits;
    this.snapshotState.groups = viewState.groups;
  }

  private activatePrivateBoundary(routeUrl: string): HistoryWorkspaceSnapshot {
    const route = browserNativeTabSceneService.parseHistoryRoute(routeUrl);
    this.requestSequence += 1;
    this.initialized = true;
    this.rawVisits = [];
    this.rawSites = [];
    this.sourceOffset = 0;
    this.snapshotState.query = route.query;
    this.snapshotState.viewMode = route.view;
    this.snapshotState.site = route.site;
    this.snapshotState.routeUrl = browserNativeTabSceneService.buildHistoryRoute(route);
    this.snapshotState.loading = false;
    this.snapshotState.busy = false;
    this.snapshotState.visits = [];
    this.snapshotState.groups = [];
    this.snapshotState.sites = [];
    this.snapshotState.selectedVisitIds = [];
    this.snapshotState.selectionAnchorId = '';
    this.snapshotState.hasMore = false;
    this.snapshotState.message = this.buildBoundaryMessage();
    this.publish();
    return this.getSnapshot();
  }

  private canReadPersistentData(): boolean {
    return this.historyFeature.canReadForManagement(this.managementBoundary);
  }

  private canWritePersistentData(): boolean {
    return this.historyFeature.canMutateForManagement(this.managementBoundary);
  }

  private buildBoundaryMessage(): string {
    return '当前会话无法读取常规历史记录。';
  }

  private mergeSites(existing: HistorySiteAggregate[], page: HistorySiteAggregate[]): HistorySiteAggregate[] {
    const byHost = new Map<string, HistorySiteAggregate>();
    existing.forEach((site: HistorySiteAggregate): void => {
      byHost.set(site.host, site);
    });
    page.forEach((site: HistorySiteAggregate): void => {
      byHost.set(site.host, site);
    });
    return Array.from(byHost.values())
      .sort((left: HistorySiteAggregate, right: HistorySiteAggregate): number =>
        right.latestVisitedAt - left.latestVisitedAt);
  }

  private selectRange(visitId: string): void {
    const anchorId = this.snapshotState.selectionAnchorId;
    const anchorIndex = this.snapshotState.visits
      .findIndex((visit: HistoryDisplayVisit): boolean => visit.id === anchorId);
    const targetIndex = this.snapshotState.visits
      .findIndex((visit: HistoryDisplayVisit): boolean => visit.id === visitId);
    if (anchorIndex < 0 || targetIndex < 0) {
      this.snapshotState.selectedVisitIds = [visitId];
      this.snapshotState.selectionAnchorId = visitId;
      return;
    }
    const start = Math.min(anchorIndex, targetIndex);
    const end = Math.max(anchorIndex, targetIndex);
    this.snapshotState.selectedVisitIds = this.snapshotState.visits
      .slice(start, end + 1)
      .map((visit: HistoryDisplayVisit): string => visit.id);
  }

  private toggleSelection(visitId: string): void {
    const selected = new Set<string>(this.snapshotState.selectedVisitIds);
    if (selected.has(visitId)) {
      selected.delete(visitId);
    } else {
      selected.add(visitId);
    }
    this.snapshotState.selectedVisitIds = this.snapshotState.visits
      .filter((visit: HistoryDisplayVisit): boolean => selected.has(visit.id))
      .map((visit: HistoryDisplayVisit): string => visit.id);
    this.snapshotState.selectionAnchorId = visitId;
  }

  private pruneSelection(): void {
    const visibleIds = new Set<string>(this.snapshotState.visits
      .map((visit: HistoryDisplayVisit): string => visit.id));
    this.snapshotState.selectedVisitIds = this.snapshotState.selectedVisitIds
      .filter((id: string): boolean => visibleIds.has(id));
    if (!visibleIds.has(this.snapshotState.selectionAnchorId)) {
      this.snapshotState.selectionAnchorId = this.snapshotState.selectedVisitIds[0] ?? '';
    }
  }

  private mergeVisits(existing: HistoryVisit[], page: HistoryVisit[]): HistoryVisit[] {
    const byId = new Map<string, HistoryVisit>();
    existing.forEach((visit: HistoryVisit): void => {
      byId.set(visit.id, visit);
    });
    page.forEach((visit: HistoryVisit): void => {
      byId.set(visit.id, visit);
    });
    return Array.from(byId.values())
      .sort((left: HistoryVisit, right: HistoryVisit): number => right.visitedAt - left.visitedAt);
  }

  private publish(): void {
    this.snapshotState.revision += 1;
  }

  private stringifyError(error: Error): string {
    return error.message?.trim().length ? error.message : JSON.stringify(error);
  }
}
