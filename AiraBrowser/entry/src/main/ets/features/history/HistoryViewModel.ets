import {
  HistorySiteAggregate,
  HistoryVisit
} from '../../common/models/BrowserModels';

export type HistoryViewMode = 'timeline' | 'sites';

export interface HistoryDisplayVisit {
  id: string;
  title: string;
  url: string;
  host: string;
  origin: string;
  visitedAt: number;
  dayBucketLabel: string;
  visitCount: number;
  duplicateCount: number;
  sourceVisitIds: string[];
  searchText: string;
  sourceVisit: HistoryVisit;
}

export interface HistoryDateGroup {
  key: string;
  label: string;
  visits: HistoryDisplayVisit[];
}

export interface HistorySiteGroup {
  key: string;
  host: string;
  origin: string;
  title: string;
  latestTitle: string;
  latestUrl: string;
  latestVisitedAt: number;
  visitCount: number;
  uniqueUrlCount: number;
  visits: HistoryDisplayVisit[];
}

export interface HistoryDetailRow {
  label: string;
  value: string;
}

export interface HistoryViewState {
  query: string;
  mode: HistoryViewMode;
  visits: HistoryDisplayVisit[];
  groups: HistoryDateGroup[];
  sites: HistorySiteGroup[];
  title: string;
  emptyTitle: string;
  emptyMessage: string;
}

const HISTORY_DIALOG_TITLE_MAX_LENGTH: number = 72;
const HISTORY_DIALOG_URL_MAX_LENGTH: number = 88;

export class HistoryViewModel {
  buildViewState(visits: HistoryVisit[], query: string, mode: HistoryViewMode): HistoryViewState {
    const normalizedQuery = this.normalizeQuery(query);
    const displayVisits = this.deduplicateVisits(visits)
      .filter((visit: HistoryDisplayVisit) => this.matchesQuery(visit, normalizedQuery));
    const groups = this.groupVisits(displayVisits);
    const sites = this.groupSites(displayVisits)
      .filter((site: HistorySiteGroup) => this.matchesSiteQuery(site, normalizedQuery));
    const visibleCount = mode === 'sites' ? sites.length : displayVisits.length;
    return {
      query: query,
      mode: mode,
      visits: displayVisits,
      groups: groups,
      sites: sites,
      title: this.buildTitle(mode, visibleCount, normalizedQuery.length > 0),
      emptyTitle: normalizedQuery.length > 0 ? '没有匹配的历史记录' : '还没有历史记录',
      emptyMessage: normalizedQuery.length > 0 ? '换个关键词试试。' : '从搜索栏打开网页后，这里会自动记录。'
    };
  }

  buildDetailRows(visit: HistoryDisplayVisit): HistoryDetailRow[] {
    return [
      { label: '标题', value: this.buildReadableVisitTitle(visit) },
      { label: '网址', value: this.buildReadableVisitUrl(visit.url) },
      { label: '站点', value: visit.host.length > 0 ? visit.host : '未知站点' },
      { label: '访问时间', value: this.formatFullTime(visit.visitedAt) },
      { label: '站点访问', value: `${visit.visitCount} 次` },
      { label: '展示合并', value: visit.duplicateCount > 1 ? `${visit.duplicateCount} 次同页访问` : '单次访问' }
    ];
  }

  buildSiteGroupsFromAggregates(aggregates: HistorySiteAggregate[]): HistorySiteGroup[] {
    return aggregates.map((site: HistorySiteAggregate): HistorySiteGroup => {
      return {
        key: site.key,
        host: site.host,
        origin: site.origin,
        title: site.title,
        latestTitle: site.latestTitle,
        latestUrl: site.latestUrl,
        latestVisitedAt: site.latestVisitedAt,
        visitCount: site.visitCount,
        uniqueUrlCount: site.uniqueUrlCount,
        visits: []
      };
    });
  }

  buildDeleteVisitMessage(visit: HistoryDisplayVisit): string {
    return `确定删除“${this.buildReadableVisitTitle(visit)}”吗？`;
  }

  getVisitSourceIds(visit: HistoryDisplayVisit): string[] {
    return visit.sourceVisitIds.slice();
  }

  private deduplicateVisits(visits: HistoryVisit[]): HistoryDisplayVisit[] {
    const sorted = visits
      .slice()
      .sort((left: HistoryVisit, right: HistoryVisit) => right.visitedAt - left.visitedAt);
    const results: HistoryDisplayVisit[] = [];
    const visitsByDayAndUrl = new Map<string, HistoryDisplayVisit>();
    sorted.forEach((visit: HistoryVisit) => {
      const host = this.resolveHost(visit);
      const normalizedUrl = this.normalizeUrl(visit.url);
      const dayLabel = visit.dayBucketLabel.length > 0 ? visit.dayBucketLabel : this.formatDate(visit.visitedAt);
      const groupUrlKey = normalizedUrl.length > 0 ? normalizedUrl : visit.id;
      const groupKey = `${dayLabel}|${groupUrlKey}`;
      const existing = visitsByDayAndUrl.get(groupKey);
      if (existing !== undefined) {
        existing.duplicateCount += 1;
        existing.sourceVisitIds.push(visit.id);
        existing.searchText = `${existing.searchText} ${this.buildVisitSearchText(visit, host)}`;
        return;
      }
      const displayVisit: HistoryDisplayVisit = {
        id: visit.id,
        title: this.resolveTitle(visit),
        url: visit.url,
        host: host,
        origin: visit.origin ?? '',
        visitedAt: visit.visitedAt,
        dayBucketLabel: dayLabel,
        visitCount: visit.visitCount ?? 1,
        duplicateCount: 1,
        sourceVisitIds: [visit.id],
        searchText: this.buildVisitSearchText(visit, host),
        sourceVisit: visit
      };
      visitsByDayAndUrl.set(groupKey, displayVisit);
      results.push(displayVisit);
    });
    return results;
  }

  private groupVisits(visits: HistoryDisplayVisit[]): HistoryDateGroup[] {
    const groups: HistoryDateGroup[] = [];
    visits.forEach((visit: HistoryDisplayVisit) => {
      const label = visit.dayBucketLabel.length > 0 ? visit.dayBucketLabel : this.formatDate(visit.visitedAt);
      const existing = groups.find((group: HistoryDateGroup) => group.label === label);
      if (existing === undefined) {
        groups.push({
          key: this.buildDateGroupKey(label),
          label: label,
          visits: [visit]
        });
      } else {
        existing.visits.push(visit);
      }
    });
    return groups;
  }

  private groupSites(visits: HistoryDisplayVisit[]): HistorySiteGroup[] {
    const groupsByHost = new Map<string, HistorySiteGroup>();
    const uniqueUrlsByHost = new Map<string, Set<string>>();
    visits.forEach((visit: HistoryDisplayVisit) => {
      const host = visit.host.length > 0 ? visit.host : '未知站点';
      let group = groupsByHost.get(host);
      if (group === undefined) {
        group = {
          key: host,
          host: host,
          origin: visit.origin,
          title: host,
          latestTitle: visit.title,
          latestUrl: visit.url,
          latestVisitedAt: visit.visitedAt,
          visitCount: 0,
          uniqueUrlCount: 0,
          visits: []
        };
        groupsByHost.set(host, group);
        uniqueUrlsByHost.set(host, new Set<string>());
      }
      group.visits.push(visit);
      group.visitCount += visit.duplicateCount;
      uniqueUrlsByHost.get(host)?.add(this.normalizeUrl(visit.url));
      if (visit.visitedAt > group.latestVisitedAt) {
        group.latestVisitedAt = visit.visitedAt;
        group.latestTitle = visit.title;
        group.latestUrl = visit.url;
      }
    });
    const groups = Array.from(groupsByHost.values());
    groups.forEach((group: HistorySiteGroup) => {
      group.uniqueUrlCount = uniqueUrlsByHost.get(group.host)?.size ?? 0;
      group.key = `${group.host}:${group.visitCount}:${group.latestVisitedAt}`;
    });
    return groups.sort((left: HistorySiteGroup, right: HistorySiteGroup) => right.latestVisitedAt - left.latestVisitedAt);
  }

  private matchesQuery(visit: HistoryDisplayVisit, normalizedQuery: string): boolean {
    if (normalizedQuery.length === 0) {
      return true;
    }
    return this.normalizeQuery(visit.searchText).includes(normalizedQuery);
  }

  private matchesSiteQuery(site: HistorySiteGroup, normalizedQuery: string): boolean {
    if (normalizedQuery.length === 0) {
      return true;
    }
    return this.normalizeQuery(site.host).includes(normalizedQuery) ||
      this.normalizeQuery(site.latestTitle).includes(normalizedQuery) ||
      this.normalizeQuery(site.latestUrl).includes(normalizedQuery);
  }

  private resolveTitle(visit: HistoryVisit): string {
    const title = visit.title.trim();
    return title.length > 0 ? title : visit.url;
  }

  private buildVisitSearchText(visit: HistoryVisit, host: string): string {
    return `${this.resolveTitle(visit)} ${visit.url} ${host}`;
  }

  private buildReadableVisitTitle(visit: HistoryDisplayVisit): string {
    const title = visit.title.trim();
    if (title.length === 0) {
      return this.buildUrlDisplayValue(visit.url, false, HISTORY_DIALOG_TITLE_MAX_LENGTH);
    }
    if (!this.shouldSummarizeTitle(title, visit.url)) {
      return this.truncateMiddle(title, HISTORY_DIALOG_TITLE_MAX_LENGTH);
    }
    const host = visit.host.length > 0 ? visit.host : this.extractHost(visit.url);
    const path = this.extractPath(visit.url);
    const summary = `${host}${path}`.trim();
    if (summary.length > 0) {
      return this.truncateMiddle(summary, HISTORY_DIALOG_TITLE_MAX_LENGTH);
    }
    return this.buildUrlDisplayValue(visit.url, false, HISTORY_DIALOG_TITLE_MAX_LENGTH);
  }

  private buildReadableVisitUrl(url: string): string {
    return this.buildUrlDisplayValue(url, true, HISTORY_DIALOG_URL_MAX_LENGTH);
  }

  private shouldSummarizeTitle(title: string, url: string): boolean {
    if (this.isUrlLike(title)) {
      return true;
    }
    const normalizedTitle = this.normalizeUrl(title);
    const normalizedUrl = this.normalizeUrl(url);
    return normalizedTitle.length > 0 && normalizedTitle === normalizedUrl;
  }

  private buildUrlDisplayValue(url: string, includeProtocol: boolean, maxLength: number): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    const protocol = includeProtocol ? this.extractProtocol(trimmed) : '';
    const host = this.extractHost(trimmed);
    const path = this.extractPath(trimmed);
    const hasQuery = trimmed.indexOf('?') >= 0;
    const hasHash = trimmed.indexOf('#') >= 0;
    let summary = `${protocol}${host}${path}`;
    if (summary.length === 0) {
      summary = trimmed;
    }
    if ((hasQuery || hasHash) && summary !== trimmed) {
      summary += hasQuery ? '?…' : '#…';
    }
    return this.truncateMiddle(summary, maxLength);
  }

  private extractProtocol(url: string): string {
    const protocolMatch = url.match(/^[a-z][a-z0-9+.-]*:\/\//i);
    return protocolMatch !== null ? protocolMatch[0].toLowerCase() : '';
  }

  private resolveHost(visit: HistoryVisit): string {
    const host = (visit.host ?? '').trim();
    if (host.length > 0) {
      return host;
    }
    const normalizedUrl = this.normalizeUrl(visit.url);
    const protocolIndex = normalizedUrl.indexOf('://');
    const start = protocolIndex >= 0 ? protocolIndex + 3 : 0;
    const pathIndex = normalizedUrl.indexOf('/', start);
    const hostWithPort = pathIndex >= 0 ? normalizedUrl.substring(start, pathIndex) : normalizedUrl.substring(start);
    const portIndex = hostWithPort.indexOf(':');
    return portIndex >= 0 ? hostWithPort.substring(0, portIndex) : hostWithPort;
  }

  private normalizeQuery(value: string): string {
    return value.trim().toLowerCase().replace(/\s+/g, ' ');
  }

  private extractHost(url: string): string {
    const trimmedUrl = url.trim();
    const protocolIndex = trimmedUrl.indexOf('://');
    const start = protocolIndex >= 0 ? protocolIndex + 3 : 0;
    const end = this.findHostBoundary(trimmedUrl, start);
    let host = trimmedUrl.substring(start, end);
    const atIndex = host.lastIndexOf('@');
    if (atIndex >= 0) {
      host = host.substring(atIndex + 1);
    }
    const portIndex = host.indexOf(':');
    if (portIndex >= 0 && !host.startsWith('[')) {
      host = host.substring(0, portIndex);
    }
    return host;
  }

  private extractPath(url: string): string {
    const trimmedUrl = url.trim();
    const protocolIndex = trimmedUrl.indexOf('://');
    const start = protocolIndex >= 0 ? protocolIndex + 3 : 0;
    const hostEnd = this.findHostBoundary(trimmedUrl, start);
    if (hostEnd >= trimmedUrl.length) {
      return '';
    }
    const queryIndex = trimmedUrl.indexOf('?', hostEnd);
    const hashIndex = trimmedUrl.indexOf('#', hostEnd);
    let pathEnd = trimmedUrl.length;
    if (queryIndex >= 0) {
      pathEnd = queryIndex;
    }
    if (hashIndex >= 0 && hashIndex < pathEnd) {
      pathEnd = hashIndex;
    }
    const path = trimmedUrl.substring(hostEnd, pathEnd);
    if (path.length === 0) {
      return '';
    }
    return path === '/' ? '' : path;
  }

  private findHostBoundary(url: string, start: number): number {
    const slashIndex = url.indexOf('/', start);
    const queryIndex = url.indexOf('?', start);
    const hashIndex = url.indexOf('#', start);
    let boundary = url.length;
    if (slashIndex >= 0 && slashIndex < boundary) {
      boundary = slashIndex;
    }
    if (queryIndex >= 0 && queryIndex < boundary) {
      boundary = queryIndex;
    }
    if (hashIndex >= 0 && hashIndex < boundary) {
      boundary = hashIndex;
    }
    return boundary;
  }

  private normalizeUrl(value: string): string {
    const normalized = value.trim().toLowerCase();
    if (normalized.endsWith('/') && normalized.indexOf('?') < 0 && normalized.indexOf('#') < 0) {
      return normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  private buildTitle(mode: HistoryViewMode, count: number, filtered: boolean): string {
    if (mode === 'sites') {
      return filtered ? `站点 · ${count}` : '按站点';
    }
    return filtered ? `搜索结果 · ${count}` : '历史记录';
  }

  private buildDateGroupKey(label: string): string {
    return label;
  }

  private isUrlLike(value: string): boolean {
    const normalized = value.trim().toLowerCase();
    return normalized.startsWith('http://') ||
      normalized.startsWith('https://') ||
      normalized.startsWith('file://') ||
      normalized.startsWith('about:') ||
      normalized.startsWith('data:') ||
      normalized.startsWith('blob:');
  }

  private truncateMiddle(value: string, maxLength: number): string {
    if (value.length <= maxLength || maxLength < 5) {
      return value;
    }
    const visible = maxLength - 1;
    const headLength = Math.ceil(visible / 2);
    const tailLength = Math.floor(visible / 2);
    return `${value.substring(0, headLength)}…${value.substring(value.length - tailLength)}`;
  }

  private formatDate(visitedAt: number): string {
    const date = new Date(visitedAt);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  private formatFullTime(visitedAt: number): string {
    const date = new Date(visitedAt);
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    const hour = `${date.getHours()}`.padStart(2, '0');
    const minute = `${date.getMinutes()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day} ${hour}:${minute}`;
  }
}
