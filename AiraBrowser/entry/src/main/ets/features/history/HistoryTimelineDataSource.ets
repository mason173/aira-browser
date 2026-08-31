import { HistoryVisit } from '../../common/models/BrowserModels';
import { HistoryDateGroup, HistoryDisplayVisit } from './HistoryViewModel';

export interface HistoryTimelineIconTarget {
  id: string;
  url: string;
  domain?: string;
}

const EMPTY_SOURCE_VISIT: HistoryVisit = {
  id: '',
  title: '',
  url: '',
  visitedAt: 0,
  dayBucketLabel: '',
  source: 'local',
  deviceId: '',
  sessionId: ''
};

const EMPTY_DISPLAY_VISIT: HistoryDisplayVisit = {
  id: '',
  title: '',
  url: '',
  host: '',
  origin: '',
  visitedAt: 0,
  dayBucketLabel: '',
  visitCount: 0,
  duplicateCount: 0,
  sourceVisitIds: [],
  searchText: '',
  sourceVisit: EMPTY_SOURCE_VISIT
};

export class HistoryTimelineItemDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private visits: HistoryDisplayVisit[] = [];

  constructor(visits: HistoryDisplayVisit[] = []) {
    this.visits = visits.slice();
  }

  totalCount(): number {
    return this.visits.length;
  }

  getData(index: number): HistoryDisplayVisit {
    if (index < 0 || index >= this.visits.length) {
      return EMPTY_DISPLAY_VISIT;
    }
    return this.visits[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replaceVisits(visits: HistoryDisplayVisit[]): void {
    const nextIds = new Set<string>();
    visits.forEach((visit: HistoryDisplayVisit) => nextIds.add(visit.id));
    let structureChanged = false;
    for (let index = this.visits.length - 1; index >= 0; index -= 1) {
      if (!nextIds.has(this.visits[index].id)) {
        this.visits.splice(index, 1);
        this.notifyDataDelete(index);
        structureChanged = true;
      }
    }

    let presentationChanged = false;
    for (let targetIndex = 0; targetIndex < visits.length; targetIndex += 1) {
      const nextVisit = visits[targetIndex];
      if (targetIndex < this.visits.length && this.visits[targetIndex].id === nextVisit.id) {
        if (!this.hasSamePresentation(this.visits[targetIndex], nextVisit)) {
          presentationChanged = true;
        }
        this.visits[targetIndex] = nextVisit;
        continue;
      }
      const existingIndex = this.findVisitIndex(nextVisit.id, targetIndex + 1);
      if (existingIndex >= 0) {
        this.visits.splice(existingIndex, 1);
        this.notifyDataDelete(existingIndex);
        structureChanged = true;
      }
      this.visits.splice(targetIndex, 0, nextVisit);
      this.notifyDataAdd(targetIndex);
      structureChanged = true;
    }
    while (this.visits.length > visits.length) {
      const index = this.visits.length - 1;
      this.visits.splice(index, 1);
      this.notifyDataDelete(index);
      structureChanged = true;
    }
    if (structureChanged || presentationChanged) {
      this.notifyDataReload();
    }
  }

  private findVisitIndex(id: string, startIndex: number): number {
    for (let index = Math.max(0, startIndex); index < this.visits.length; index += 1) {
      if (this.visits[index].id === id) {
        return index;
      }
    }
    return -1;
  }

  private hasSamePresentation(left: HistoryDisplayVisit, right: HistoryDisplayVisit): boolean {
    return left.id === right.id &&
      left.title === right.title &&
      left.url === right.url &&
      left.host === right.host &&
      left.visitedAt === right.visitedAt &&
      left.duplicateCount === right.duplicateCount &&
      left.visitCount === right.visitCount;
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }

  private notifyDataAdd(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(index);
    });
  }

  private notifyDataDelete(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index);
    });
  }
}

export class HistoryTimelineGroup {
  key: string;
  label: string;
  itemDataSource: HistoryTimelineItemDataSource;

  constructor(group: HistoryDateGroup) {
    this.key = group.key;
    this.label = group.label;
    this.itemDataSource = new HistoryTimelineItemDataSource(group.visits);
  }

  update(group: HistoryDateGroup): void {
    this.label = group.label;
    this.itemDataSource.replaceVisits(group.visits);
  }
}

const EMPTY_HISTORY_GROUP: HistoryTimelineGroup = new HistoryTimelineGroup({
  key: '',
  label: '',
  visits: []
});

export class HistoryTimelineDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private groups: HistoryTimelineGroup[] = [];

  totalCount(): number {
    return this.groups.length;
  }

  getData(index: number): HistoryTimelineGroup {
    if (index < 0 || index >= this.groups.length) {
      return EMPTY_HISTORY_GROUP;
    }
    return this.groups[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  replaceGroups(groups: HistoryDateGroup[]): void {
    const existingByKey = new Map<string, HistoryTimelineGroup>();
    this.groups.forEach((group: HistoryTimelineGroup) => {
      existingByKey.set(group.key, group);
    });
    const nextGroups: HistoryTimelineGroup[] = groups.map((group: HistoryDateGroup): HistoryTimelineGroup => {
      const existing = existingByKey.get(group.key);
      if (existing !== undefined) {
        existing.update(group);
        return existing;
      }
      return new HistoryTimelineGroup(group);
    });
    const nextKeys = new Set<string>();
    nextGroups.forEach((group: HistoryTimelineGroup) => nextKeys.add(group.key));
    this.groups.forEach((group: HistoryTimelineGroup) => {
      if (!nextKeys.has(group.key)) {
        group.itemDataSource.replaceVisits([]);
      }
    });
    this.reconcileGroups(nextGroups);
  }

  getIconTargetsAroundVisibleContent(
    startGroupIndex: number,
    startItemIndex: number,
    endGroupIndex: number,
    endItemIndex: number,
    bufferItems: number
  ): HistoryTimelineIconTarget[] {
    const visitCount = this.totalVisitCount();
    if (visitCount === 0) {
      return [];
    }
    const startOffset = this.resolveFlatVisitIndex(startGroupIndex, startItemIndex, false);
    const endOffset = this.resolveFlatVisitIndex(endGroupIndex, endItemIndex, true);
    const safeStart = Math.max(0, Math.min(startOffset, endOffset) - bufferItems);
    const safeEnd = Math.min(visitCount - 1, Math.max(startOffset, endOffset) + bufferItems);
    const targets: HistoryTimelineIconTarget[] = [];
    let flatIndex = 0;
    for (let groupIndex = 0; groupIndex < this.groups.length; groupIndex += 1) {
      const itemDataSource = this.groups[groupIndex].itemDataSource;
      for (let itemIndex = 0; itemIndex < itemDataSource.totalCount(); itemIndex += 1) {
        if (flatIndex >= safeStart && flatIndex <= safeEnd) {
          const visit = itemDataSource.getData(itemIndex);
          if (visit.url.length > 0) {
            targets.push({
              id: visit.id,
              url: visit.url,
              domain: this.resolveDomainHint(visit.host)
            });
          }
        }
        flatIndex += 1;
        if (flatIndex > safeEnd) {
          return targets;
        }
      }
    }
    return targets;
  }

  private totalVisitCount(): number {
    let count = 0;
    this.groups.forEach((group: HistoryTimelineGroup) => {
      count += group.itemDataSource.totalCount();
    });
    return count;
  }

  private resolveFlatVisitIndex(groupIndex: number, itemIndex: number, preferGroupEnd: boolean): number {
    const safeGroupIndex = Math.max(0, Math.min(groupIndex, this.groups.length - 1));
    let offset = 0;
    for (let index = 0; index < safeGroupIndex; index += 1) {
      offset += this.groups[index].itemDataSource.totalCount();
    }
    const itemCount = this.groups[safeGroupIndex].itemDataSource.totalCount();
    if (itemCount === 0) {
      return offset;
    }
    const fallbackItemIndex = preferGroupEnd ? itemCount - 1 : 0;
    const safeItemIndex = itemIndex < 0 ? fallbackItemIndex : Math.max(0, Math.min(itemIndex, itemCount - 1));
    return offset + safeItemIndex;
  }

  private reconcileGroups(nextGroups: HistoryTimelineGroup[]): void {
    const nextKeys = new Set<string>();
    nextGroups.forEach((group: HistoryTimelineGroup) => nextKeys.add(group.key));

    for (let index = this.groups.length - 1; index >= 0; index -= 1) {
      if (!nextKeys.has(this.groups[index].key)) {
        this.groups.splice(index, 1);
        this.notifyDataDelete(index);
      }
    }

    for (let targetIndex = 0; targetIndex < nextGroups.length; targetIndex += 1) {
      const target = nextGroups[targetIndex];
      if (targetIndex < this.groups.length && this.groups[targetIndex].key === target.key) {
        continue;
      }
      const existingIndex = this.findGroupIndex(target.key, targetIndex + 1);
      if (existingIndex >= 0) {
        const movingGroup = this.groups[existingIndex];
        this.groups.splice(existingIndex, 1);
        this.notifyDataDelete(existingIndex);
        this.groups.splice(targetIndex, 0, movingGroup);
        this.notifyDataAdd(targetIndex);
      } else {
        this.groups.splice(targetIndex, 0, target);
        this.notifyDataAdd(targetIndex);
      }
    }
  }

  private findGroupIndex(key: string, startIndex: number): number {
    for (let index = Math.max(0, startIndex); index < this.groups.length; index += 1) {
      if (this.groups[index].key === key) {
        return index;
      }
    }
    return -1;
  }

  private resolveDomainHint(host: string): string {
    let normalized = host.trim().toLowerCase();
    if (normalized.startsWith('www.')) {
      normalized = normalized.slice(4);
    }
    if (normalized.length === 0 || normalized === '未知站点' || !/^[a-z0-9.-]+$/.test(normalized)) {
      return '';
    }
    return normalized;
  }

  private notifyDataAdd(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataAdd(index);
    });
  }

  private notifyDataDelete(index: number): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataDelete(index);
    });
  }
}
