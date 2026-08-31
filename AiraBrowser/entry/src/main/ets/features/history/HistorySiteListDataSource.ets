import { HistorySiteGroup } from './HistoryViewModel';

export interface HistorySiteIconTarget {
  id: string;
  url: string;
  domain?: string;
}

const EMPTY_HISTORY_SITE: HistorySiteGroup = {
  key: '',
  host: '',
  origin: '',
  title: '',
  latestTitle: '',
  latestUrl: '',
  latestVisitedAt: 0,
  visitCount: 0,
  uniqueUrlCount: 0,
  visits: []
};

export class HistorySiteListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private sites: HistorySiteGroup[] = [];

  totalCount(): number {
    return this.sites.length;
  }

  getData(index: number): HistorySiteGroup {
    if (index < 0 || index >= this.sites.length) {
      return EMPTY_HISTORY_SITE;
    }
    return this.sites[index];
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

  replaceSites(sites: HistorySiteGroup[]): void {
    this.sites = sites.slice();
    this.notifyDataReload();
  }

  getIconTargetsAround(startIndex: number, endIndex: number, bufferRows: number): HistorySiteIconTarget[] {
    const safeStart = Math.max(0, Math.min(startIndex, endIndex) - bufferRows);
    const safeEnd = Math.min(this.sites.length - 1, Math.max(startIndex, endIndex) + bufferRows);
    const targets: HistorySiteIconTarget[] = [];
    for (let index = safeStart; index <= safeEnd; index += 1) {
      const site = this.sites[index];
      if (site.latestUrl.length > 0) {
        targets.push({
          id: site.key,
          url: site.latestUrl,
          domain: this.resolveDomainHint(site.host)
        });
      }
    }
    return targets;
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

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}
