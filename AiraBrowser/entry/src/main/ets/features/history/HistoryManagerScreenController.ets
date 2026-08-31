import { HistoryVisit } from '../../common/models/BrowserModels';
import { HistoryFeature, HistoryManagementBoundary } from './HistoryFeature';

export interface HistoryTimelineVisibleContent {
  startGroupIndex: number;
  startItemIndex: number;
  endGroupIndex: number;
  endItemIndex: number;
}

export interface HistoryTimelineDeletionTransaction {
  id: number;
  visits: HistoryVisit[];
}

export interface HistoryTimelineDeletionCompletion {
  shouldReload: boolean;
}

interface HistoryTimelineFirstPageRequest {
  query: string;
  limit: number;
  publish: (visits: HistoryVisit[]) => void;
}

interface HistoryTimelinePaginationRequest {
  limit: number;
  previousDisplayCount: number;
  publish: (visits: HistoryVisit[]) => number;
}

const EMPTY_TIMELINE_VISIBLE_CONTENT: HistoryTimelineVisibleContent = {
  startGroupIndex: 0,
  startItemIndex: 0,
  endGroupIndex: 0,
  endItemIndex: 0
};

export class HistoryManagerScreenController {
  private historyFeature: HistoryFeature;
  private backHandler?: () => boolean;
  private timelineScroller: ListScroller = new ListScroller();
  private timelineSwipeActionVisitIds: Set<string> = new Set<string>();
  private timelineRequestSequence: number = 0;
  private timelineQuery: string = '';
  private timelineSourceOffset: number = 0;
  private timelineLoadedVisits: HistoryVisit[] = [];
  private timelineHasLoadedAll: boolean = false;
  private timelineLoading: boolean = false;
  private timelineLoadingListener?: (loading: boolean) => void;
  private timelineDeletionSequence: number = 0;
  private timelineDeletionFailed: boolean = false;
  private timelineDeletionLoadedCounts: Map<number, number> = new Map<number, number>();
  private activeTimelineFirstPageRequest?: HistoryTimelineFirstPageRequest;
  private activeTimelinePaginationRequest?: HistoryTimelinePaginationRequest;
  private pendingTimelineFirstPageRequest?: HistoryTimelineFirstPageRequest;
  private pendingTimelinePaginationRequest?: HistoryTimelinePaginationRequest;
  private managementBoundary?: HistoryManagementBoundary;
  private timelineVisibleContent: HistoryTimelineVisibleContent = {
    startGroupIndex: 0,
    startItemIndex: 0,
    endGroupIndex: 0,
    endItemIndex: 0
  };

  constructor(historyFeature: HistoryFeature) {
    this.historyFeature = historyFeature;
  }

  setManagementBoundary(boundary: HistoryManagementBoundary): void {
    this.managementBoundary = boundary;
  }

  getTimelineScroller(): ListScroller {
    return this.timelineScroller;
  }

  scrollTimelineToStart(): void {
    try {
      this.timelineScroller.scrollToIndex(0);
    } catch (_error) {
    }
  }

  setTimelineLoadingListener(listener: (loading: boolean) => void): void {
    this.timelineLoadingListener = listener;
    this.timelineLoadingListener(this.timelineLoading);
  }

  clearTimelineLoadingListener(): void {
    this.timelineLoadingListener = undefined;
  }

  loadTimelineFirstPage(query: string, limit: number, publish: (visits: HistoryVisit[]) => void): void {
    this.resetTimelineSwipeActions();
    const normalizedQuery = query.trim();
    const request: HistoryTimelineFirstPageRequest = {
      query: normalizedQuery,
      limit: limit,
      publish: publish
    };
    if (this.hasPendingTimelineDeletion()) {
      this.pendingTimelineFirstPageRequest = request;
      this.pendingTimelinePaginationRequest = undefined;
      this.setTimelineLoading(true);
      return;
    }
    const sequence = ++this.timelineRequestSequence;
    this.timelineQuery = normalizedQuery;
    this.timelineSourceOffset = 0;
    this.timelineHasLoadedAll = false;
    this.resetTimelineVisibleContent();
    this.setTimelineLoading(true);
    this.activeTimelineFirstPageRequest = request;
    this.activeTimelinePaginationRequest = undefined;

    let task: Promise<HistoryVisit[]>;
    if (normalizedQuery.length > 0) {
      task = this.historyFeature.refreshSearchPageForManagement(
        normalizedQuery,
        0,
        limit,
        this.requireManagementBoundary()
      );
    } else {
      const boundary = this.requireManagementBoundary();
      const cachedVisits = this.historyFeature.listVisitsForManagement(limit, boundary);
      task = cachedVisits.length > 0
        ? Promise.resolve(cachedVisits)
        : this.historyFeature.refreshPreviewForManagement(limit, boundary);
    }
    task
      .then((visits: HistoryVisit[]) => {
        if (!this.isTimelineRequestCurrent(sequence, normalizedQuery)) {
          return;
        }
        this.clearActiveTimelineFirstPageRequest(request);
        this.timelineLoadedVisits = visits.slice();
        this.timelineSourceOffset = visits.length;
        this.timelineHasLoadedAll = visits.length < limit;
        publish(this.timelineLoadedVisits.slice());
        this.setTimelineLoading(false);
      })
      .catch((_error: Error) => {
        if (this.isTimelineRequestCurrent(sequence, normalizedQuery)) {
          this.clearActiveTimelineFirstPageRequest(request);
          this.setTimelineLoading(false);
        }
      });
  }

  requestNextTimelinePages(
    limit: number,
    previousDisplayCount: number,
    publish: (visits: HistoryVisit[]) => number
  ): void {
    const request: HistoryTimelinePaginationRequest = {
      limit: limit,
      previousDisplayCount: previousDisplayCount,
      publish: publish
    };
    if (this.hasPendingTimelineDeletion()) {
      if (this.pendingTimelineFirstPageRequest === undefined) {
        this.pendingTimelinePaginationRequest = request;
      }
      return;
    }
    if (this.timelineHasLoadedAll || this.timelineLoading) {
      return;
    }
    const normalizedQuery = this.timelineQuery;
    const sequence = this.timelineRequestSequence;
    const offset = this.timelineSourceOffset;
    this.setTimelineLoading(true);
    this.activeTimelineFirstPageRequest = undefined;
    this.activeTimelinePaginationRequest = request;
    const boundary = this.requireManagementBoundary();
    const task = normalizedQuery.length > 0 ?
      this.historyFeature.refreshSearchPageForManagement(normalizedQuery, offset, limit, boundary) :
      this.historyFeature.refreshPageForManagement(offset, limit, boundary);
    task
      .then((visits: HistoryVisit[]) => {
        if (!this.isTimelineRequestCurrent(sequence, normalizedQuery)) {
          return;
        }
        this.clearActiveTimelinePaginationRequest(request);
        this.timelineSourceOffset += visits.length;
        this.timelineLoadedVisits = this.mergeLoadedVisits(visits);
        this.timelineHasLoadedAll = visits.length < limit;
        const nextDisplayCount = publish(this.timelineLoadedVisits.slice());
        this.setTimelineLoading(false);
        if (this.shouldContinueTimelinePagination(
          previousDisplayCount,
          nextDisplayCount,
          visits.length,
          limit
        )) {
          this.requestNextTimelinePages(limit, nextDisplayCount, publish);
        }
      })
      .catch((_error: Error) => {
        if (this.isTimelineRequestCurrent(sequence, normalizedQuery)) {
          this.clearActiveTimelinePaginationRequest(request);
          this.setTimelineLoading(false);
        }
      });
  }

  beginTimelineDeletion(visitIds: string[]): HistoryTimelineDeletionTransaction {
    this.preserveActiveTimelineRequestForDeletion();
    this.invalidateTimelineRequests();
    if (this.pendingTimelineFirstPageRequest !== undefined) {
      this.setTimelineLoading(true);
    }
    const removingIds = new Set<string>(visitIds);
    const previousCount = this.timelineLoadedVisits.length;
    this.timelineLoadedVisits = this.timelineLoadedVisits.filter((visit: HistoryVisit) => !removingIds.has(visit.id));
    const removedLoadedCount = previousCount - this.timelineLoadedVisits.length;
    if (visitIds.length === 0) {
      return {
        id: 0,
        visits: this.timelineLoadedVisits.slice()
      };
    }
    const transactionId = ++this.timelineDeletionSequence;
    this.timelineDeletionLoadedCounts.set(transactionId, removedLoadedCount);
    return {
      id: transactionId,
      visits: this.timelineLoadedVisits.slice()
    };
  }

  finishTimelineDeletion(transactionId: number, committed: boolean): HistoryTimelineDeletionCompletion {
    if (transactionId <= 0) {
      return { shouldReload: !committed };
    }
    const removedLoadedCount = this.timelineDeletionLoadedCounts.get(transactionId);
    if (removedLoadedCount === undefined) {
      return { shouldReload: false };
    }
    this.timelineDeletionLoadedCounts.delete(transactionId);
    if (committed) {
      this.timelineSourceOffset = Math.max(0, this.timelineSourceOffset - removedLoadedCount);
    } else {
      this.timelineDeletionFailed = true;
    }
    if (this.hasPendingTimelineDeletion()) {
      return { shouldReload: false };
    }

    if (this.timelineDeletionFailed) {
      this.timelineDeletionFailed = false;
      this.pendingTimelineFirstPageRequest = undefined;
      this.pendingTimelinePaginationRequest = undefined;
      return { shouldReload: true };
    }

    const pendingFirstPage = this.pendingTimelineFirstPageRequest;
    const pendingPagination = this.pendingTimelinePaginationRequest;
    this.pendingTimelineFirstPageRequest = undefined;
    this.pendingTimelinePaginationRequest = undefined;
    if (pendingFirstPage !== undefined) {
      this.loadTimelineFirstPage(pendingFirstPage.query, pendingFirstPage.limit, pendingFirstPage.publish);
    } else if (pendingPagination !== undefined) {
      this.requestNextTimelinePages(
        pendingPagination.limit,
        pendingPagination.previousDisplayCount,
        pendingPagination.publish
      );
    }
    return { shouldReload: false };
  }

  hasLoadedTimelineVisits(): boolean {
    return this.timelineLoadedVisits.length > 0;
  }

  clearTimelineState(): void {
    this.cancelTimelineRequests();
    this.timelineQuery = '';
    this.timelineSourceOffset = 0;
    this.timelineLoadedVisits = [];
    this.timelineHasLoadedAll = false;
    this.resetTimelineVisibleContent();
    this.resetTimelineSwipeActions();
  }

  cancelTimelineRequests(): void {
    this.activeTimelineFirstPageRequest = undefined;
    this.activeTimelinePaginationRequest = undefined;
    this.pendingTimelineFirstPageRequest = undefined;
    this.pendingTimelinePaginationRequest = undefined;
    this.invalidateTimelineRequests();
  }

  private invalidateTimelineRequests(): void {
    this.timelineRequestSequence += 1;
    this.setTimelineLoading(false);
  }

  updateTimelineVisibleContent(content: HistoryTimelineVisibleContent): boolean {
    if (this.timelineVisibleContent.startGroupIndex === content.startGroupIndex &&
      this.timelineVisibleContent.startItemIndex === content.startItemIndex &&
      this.timelineVisibleContent.endGroupIndex === content.endGroupIndex &&
      this.timelineVisibleContent.endItemIndex === content.endItemIndex) {
      return false;
    }
    this.timelineVisibleContent = {
      startGroupIndex: content.startGroupIndex,
      startItemIndex: content.startItemIndex,
      endGroupIndex: content.endGroupIndex,
      endItemIndex: content.endItemIndex
    };
    return true;
  }

  getTimelineVisibleContent(): HistoryTimelineVisibleContent {
    return {
      startGroupIndex: this.timelineVisibleContent.startGroupIndex,
      startItemIndex: this.timelineVisibleContent.startItemIndex,
      endGroupIndex: this.timelineVisibleContent.endGroupIndex,
      endItemIndex: this.timelineVisibleContent.endItemIndex
    };
  }

  setTimelineSwipeActionOpen(visitId: string, open: boolean): void {
    if (open) {
      this.timelineSwipeActionVisitIds.add(visitId);
    } else {
      this.timelineSwipeActionVisitIds.delete(visitId);
    }
  }

  closeTimelineSwipeActions(): boolean {
    if (this.timelineSwipeActionVisitIds.size === 0) {
      return false;
    }
    this.timelineSwipeActionVisitIds.clear();
    try {
      this.timelineScroller.closeAllSwipeActions();
    } catch (_error) {
    }
    return true;
  }

  resetTimelineSwipeActions(): void {
    if (this.timelineSwipeActionVisitIds.size === 0) {
      return;
    }
    this.timelineSwipeActionVisitIds.clear();
    try {
      this.timelineScroller.closeAllSwipeActions();
    } catch (_error) {
    }
  }

  setBackHandler(handler: () => boolean): void {
    this.backHandler = handler;
  }

  clearBackHandler(): void {
    this.backHandler = undefined;
    this.clearTimelineLoadingListener();
    this.cancelTimelineRequests();
    this.resetTimelineSwipeActions();
  }

  handleBackPress(): boolean {
    if (this.backHandler === undefined) {
      return false;
    }
    return this.backHandler();
  }

  private isTimelineRequestCurrent(sequence: number, query: string): boolean {
    return sequence === this.timelineRequestSequence && query === this.timelineQuery;
  }

  private hasPendingTimelineDeletion(): boolean {
    return this.timelineDeletionLoadedCounts.size > 0;
  }

  private preserveActiveTimelineRequestForDeletion(): void {
    if (this.activeTimelineFirstPageRequest !== undefined) {
      this.pendingTimelineFirstPageRequest = this.activeTimelineFirstPageRequest;
      this.pendingTimelinePaginationRequest = undefined;
    } else if (this.activeTimelinePaginationRequest !== undefined &&
      this.pendingTimelineFirstPageRequest === undefined) {
      this.pendingTimelinePaginationRequest = this.activeTimelinePaginationRequest;
    }
    this.activeTimelineFirstPageRequest = undefined;
    this.activeTimelinePaginationRequest = undefined;
  }

  private clearActiveTimelineFirstPageRequest(request: HistoryTimelineFirstPageRequest): void {
    if (this.activeTimelineFirstPageRequest === request) {
      this.activeTimelineFirstPageRequest = undefined;
    }
  }

  private clearActiveTimelinePaginationRequest(request: HistoryTimelinePaginationRequest): void {
    if (this.activeTimelinePaginationRequest === request) {
      this.activeTimelinePaginationRequest = undefined;
    }
  }

  private shouldContinueTimelinePagination(
    previousDisplayCount: number,
    nextDisplayCount: number,
    pageCount: number,
    pageSize: number
  ): boolean {
    return !this.timelineHasLoadedAll && pageCount >= pageSize && nextDisplayCount <= previousDisplayCount;
  }

  private setTimelineLoading(loading: boolean): void {
    if (this.timelineLoading === loading) {
      return;
    }
    this.timelineLoading = loading;
    this.timelineLoadingListener?.(loading);
  }

  private resetTimelineVisibleContent(): void {
    this.timelineVisibleContent = {
      startGroupIndex: EMPTY_TIMELINE_VISIBLE_CONTENT.startGroupIndex,
      startItemIndex: EMPTY_TIMELINE_VISIBLE_CONTENT.startItemIndex,
      endGroupIndex: EMPTY_TIMELINE_VISIBLE_CONTENT.endGroupIndex,
      endItemIndex: EMPTY_TIMELINE_VISIBLE_CONTENT.endItemIndex
    };
  }

  private mergeLoadedVisits(visits: HistoryVisit[]): HistoryVisit[] {
    const visitsById = new Map<string, HistoryVisit>();
    this.timelineLoadedVisits.forEach((visit: HistoryVisit) => {
      visitsById.set(visit.id, visit);
    });
    visits.forEach((visit: HistoryVisit) => {
      visitsById.set(visit.id, visit);
    });
    return Array.from(visitsById.values())
      .sort((left: HistoryVisit, right: HistoryVisit) => right.visitedAt - left.visitedAt);
  }

  private requireManagementBoundary(): HistoryManagementBoundary {
    if (this.managementBoundary === undefined) {
      throw new Error('History management boundary is required.');
    }
    return this.managementBoundary;
  }
}
