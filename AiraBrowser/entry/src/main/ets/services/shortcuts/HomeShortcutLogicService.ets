import {
  ShortcutKind,
  ShortcutRecord,
  ShortcutScenarioRecord
} from '../../common/models/BrowserModels';
import {
  resolveHomeShortcutKind,
  resolveHomeSystemShortcutTarget
} from './HomeSystemShortcutCatalog';

export interface HomeShortcutMoveRequest {
  shortcutId: string;
  expectedFromIndex: number;
  targetIndex: number;
}

export interface HomeShortcutTreeRemovalResult {
  shortcuts: ShortcutRecord[];
  removed: boolean;
}

export interface HomeShortcutTreeMutationResult {
  shortcuts: ShortcutRecord[];
  changed: boolean;
}

export interface HomeShortcutReorderResult extends HomeShortcutTreeMutationResult {
  valid: boolean;
}

export interface HomeShortcutDestinationConvergenceResult {
  shortcuts: ShortcutRecord[];
  changed: boolean;
  duplicateIds: string[];
}

export type HomeShortcutMoveBoundary = 'top' | 'bottom';
export type HomeShortcutMoveStep = 'up' | 'down';

export interface HomeShortcutLayoutMetrics {
  columns: number;
  rowGap: number;
  columnGap: number;
  targetTileSize: number;
  minimumTileSize: number;
  fallbackColumnWidth: number;
  titleTopGap: number;
  titleBlockHeight: number;
}

export class HomeShortcutLogicService {
  buildAvailableScenarios(
    shortcuts: ShortcutRecord[],
    scenarios: ShortcutScenarioRecord[],
    defaultScenarioId: string
  ): ShortcutScenarioRecord[] {
    const activeScenarios = scenarios
      .filter((scenario: ShortcutScenarioRecord) => !scenario.archived)
      .slice()
      .sort((left: ShortcutScenarioRecord, right: ShortcutScenarioRecord) => left.position - right.position);
    const knownScenarioIds = scenarios.map((scenario: ShortcutScenarioRecord) => scenario.id);
    const fallbackScenarios: ShortcutScenarioRecord[] = [];
    this.flattenToLinkShortcuts(shortcuts)
      .filter((shortcut: ShortcutRecord) => shortcut.sync?.deletedAt === undefined)
      .slice()
      .sort((left: ShortcutRecord, right: ShortcutRecord) => left.position - right.position)
      .forEach((shortcut: ShortcutRecord) => {
        const scenarioId = this.resolveShortcutScenarioId(shortcut, defaultScenarioId);
        if (knownScenarioIds.indexOf(scenarioId) >= 0 ||
          fallbackScenarios.some((scenario: ShortcutScenarioRecord) => scenario.id === scenarioId)) {
          return;
        }
        fallbackScenarios.push(this.buildFallbackScenario(shortcut, scenarioId, defaultScenarioId,
          activeScenarios.length + fallbackScenarios.length));
      });
    return activeScenarios.concat(fallbackScenarios);
  }

  hasLiveShortcutInScenario(shortcuts: ShortcutRecord[], scenarioId: string, defaultScenarioId: string): boolean {
    const targetScenarioId = scenarioId.length > 0 ? scenarioId : defaultScenarioId;
    return this.flattenToLinkShortcuts(shortcuts).some((shortcut: ShortcutRecord) => {
      return shortcut.sync?.deletedAt === undefined &&
        this.resolveShortcutScenarioId(shortcut, defaultScenarioId) === targetScenarioId;
    });
  }

  resolveScenarioId(
    shortcuts: ShortcutRecord[],
    scenarios: ShortcutScenarioRecord[] | undefined,
    defaultScenarioId: string
  ): string {
    const flatShortcuts = this.flattenToLinkShortcuts(shortcuts);
    const orderedScenarioId = (scenarios ?? [])
      .filter((scenario: ShortcutScenarioRecord) => !scenario.archived)
      .map((scenario: ShortcutScenarioRecord) => scenario.id)
      .find((scenarioId: string) => {
        return flatShortcuts.some((shortcut: ShortcutRecord) => {
          return (shortcut.scenarioId ?? defaultScenarioId) === scenarioId;
        });
      });
    if (orderedScenarioId !== undefined && orderedScenarioId.length > 0) {
      return orderedScenarioId;
    }

    const firstShortcutScenarioId = flatShortcuts.find((shortcut: ShortcutRecord) => {
      return (shortcut.scenarioId ?? '').length > 0;
    })?.scenarioId;
    if (firstShortcutScenarioId !== undefined && firstShortcutScenarioId.length > 0) {
      return firstShortcutScenarioId;
    }

    return defaultScenarioId;
  }

  resolvePresentationShortcuts(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    return this.flattenToLinkShortcuts(shortcuts)
      .slice()
      .sort((left: ShortcutRecord, right: ShortcutRecord) => left.position - right.position);
  }

  resolveDestinationIdentity(kind: ShortcutKind | undefined, url: string): string {
    if (resolveHomeShortcutKind(kind) === 'system') {
      const target = resolveHomeSystemShortcutTarget(url);
      return target === undefined ? '' : `system:${target}`;
    }
    const normalizedUrl = this.normalizeUrlKey(url);
    return normalizedUrl.length <= 0 ? '' : `web:${normalizedUrl}`;
  }

  resolveShortcutDestinationIdentity(shortcut: ShortcutRecord): string {
    return this.resolveDestinationIdentity(shortcut.kind, shortcut.url);
  }

  projectUniqueActiveDestinations(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    const activeShortcuts = shortcuts
      .filter((shortcut: ShortcutRecord): boolean => shortcut.sync?.deletedAt === undefined)
      .map((shortcut: ShortcutRecord): ShortcutRecord => this.cloneRecord(shortcut));
    const winnerByIdentity = this.resolveDestinationWinners(activeShortcuts);
    return activeShortcuts.filter((shortcut: ShortcutRecord): boolean => {
      const identity = this.resolveShortcutDestinationIdentity(shortcut);
      return identity.length <= 0 || winnerByIdentity.get(identity)?.id === shortcut.id;
    });
  }

  convergeDuplicateDestinations(shortcuts: ShortcutRecord[]): HomeShortcutDestinationConvergenceResult {
    const activeShortcuts = shortcuts.filter((shortcut: ShortcutRecord): boolean => {
      return shortcut.sync?.deletedAt === undefined;
    });
    const winnerByIdentity = this.resolveDestinationWinners(activeShortcuts);
    const duplicateRevisionById: Map<string, number> = new Map();
    const groupsByIdentity: Map<string, ShortcutRecord[]> = new Map();
    activeShortcuts.forEach((shortcut: ShortcutRecord): void => {
      const identity = this.resolveShortcutDestinationIdentity(shortcut);
      if (identity.length <= 0) {
        return;
      }
      const group = groupsByIdentity.get(identity) ?? [];
      group.push(shortcut);
      groupsByIdentity.set(identity, group);
    });
    groupsByIdentity.forEach((group: ShortcutRecord[], identity: string): void => {
      if (group.length <= 1) {
        return;
      }
      const winner = winnerByIdentity.get(identity);
      const revision = this.resolveDuplicateTombstoneRevision(group);
      group.forEach((shortcut: ShortcutRecord): void => {
        if (shortcut.id !== winner?.id) {
          duplicateRevisionById.set(shortcut.id, revision);
        }
      });
    });
    const duplicateIds = Array.from(duplicateRevisionById.keys()).sort();
    return {
      shortcuts: shortcuts.map((shortcut: ShortcutRecord): ShortcutRecord => {
        const revision = duplicateRevisionById.get(shortcut.id);
        return revision === undefined
          ? this.cloneRecord(shortcut)
          : this.buildDuplicateDestinationTombstone(shortcut, revision);
      }),
      changed: duplicateIds.length > 0,
      duplicateIds: duplicateIds
    };
  }

  normalizeUrlKey(url: string): string {
    const normalizedUrl = this.normalizeShortcutUrl(url);
    if (normalizedUrl.length <= 0 || normalizedUrl === 'about:blank') {
      return '';
    }
    const schemeIndex = normalizedUrl.indexOf('://');
    if (schemeIndex < 0) {
      return normalizedUrl.toLowerCase();
    }
    const scheme = normalizedUrl.substring(0, schemeIndex).toLowerCase();
    const afterScheme = normalizedUrl.substring(schemeIndex + 3);
    const pathStart = this.findPathStart(afterScheme);
    const rawHost = pathStart >= 0 ? afterScheme.substring(0, pathStart) : afterScheme;
    const rawPath = pathStart >= 0 ? afterScheme.substring(pathStart) : '';
    const host = this.normalizeHost(rawHost, scheme);
    const path = this.normalizePath(rawPath);
    return `${scheme}://${host}${path}`;
  }

  normalizeShortcutUrl(url: string): string {
    const trimmed = url.trim();
    if (trimmed.length === 0) {
      return '';
    }
    if (trimmed.indexOf('://') >= 0 || trimmed.startsWith('about:')) {
      return trimmed;
    }
    return `https://${trimmed}`;
  }

  private getGridColumnWidth(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    if (gridWidth <= 0 || metrics.columns <= 0) {
      return metrics.fallbackColumnWidth;
    }
    const availableWidth = gridWidth - metrics.columnGap * Math.max(0, metrics.columns - 1);
    return Math.max(1, availableWidth / metrics.columns);
  }

  private getAlignedGridColumnWidth(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.getTileSize(gridWidth, metrics);
  }

  getAlignedGridColumnGap(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    const columns = Math.max(1, metrics.columns);
    if (columns <= 1 || gridWidth <= 0) {
      return 0;
    }
    const itemWidth = this.getAlignedGridColumnWidth(gridWidth, metrics);
    const availableGap = gridWidth - itemWidth * columns;
    return Math.max(0, availableGap / Math.max(1, columns - 1));
  }

  getRowHeight(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.getTileSize(gridWidth, metrics) + metrics.titleTopGap + metrics.titleBlockHeight;
  }

  getTileSize(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    const gridColumnWidth = this.getGridColumnWidth(gridWidth, metrics);
    return Math.max(
      metrics.minimumTileSize,
      Math.min(metrics.targetTileSize, Math.floor(gridColumnWidth))
    );
  }

  getGridContentHeight(rowCount: number, gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    const rows = Math.max(1, rowCount);
    return rows * this.getRowHeight(gridWidth, metrics) +
      Math.max(0, rows - 1) * metrics.rowGap;
  }

  getCardHeight(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.getTileSize(gridWidth, metrics) + metrics.titleTopGap + metrics.titleBlockHeight;
  }

  getTitleFontSize(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    const titleBlockHeight = Math.max(12, Math.round(this.getRowHeight(gridWidth, metrics) * 0.2));
    return Math.max(12, Math.min(13, Math.round(titleBlockHeight * 0.62)));
  }

  findById(shortcuts: ShortcutRecord[], shortcutId: string): ShortcutRecord | undefined {
    return this.flattenToLinkShortcuts(shortcuts).find((shortcut: ShortcutRecord) => shortcut.id === shortcutId);
  }

  mapList(
    shortcuts: ShortcutRecord[],
    transform: (shortcut: ShortcutRecord) => ShortcutRecord
  ): ShortcutRecord[] {
    return this.flattenToLinkShortcuts(shortcuts).map((shortcut: ShortcutRecord) => transform(this.cloneRecord(shortcut)));
  }

  removeById(shortcuts: ShortcutRecord[], shortcutId: string): HomeShortcutTreeRemovalResult {
    const flatShortcuts = this.flattenToLinkShortcuts(shortcuts);
    const nextShortcuts = flatShortcuts.filter((shortcut: ShortcutRecord) => shortcut.id !== shortcutId);
    return {
      shortcuts: nextShortcuts,
      removed: nextShortcuts.length !== flatShortcuts.length
    };
  }

  moveById(
    shortcuts: ShortcutRecord[],
    shortcutId: string,
    boundary: HomeShortcutMoveBoundary
  ): HomeShortcutTreeMutationResult {
    const flatShortcuts = this.flattenToLinkShortcuts(shortcuts);
    const currentIndex = flatShortcuts.findIndex((shortcut: ShortcutRecord) => shortcut.id === shortcutId);
    if (currentIndex < 0) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    const targetIndex = boundary === 'top' ? 0 : flatShortcuts.length - 1;
    if (currentIndex === targetIndex) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    const nextShortcuts = flatShortcuts.map((shortcut: ShortcutRecord) => this.cloneRecord(shortcut));
    const removedShortcuts = nextShortcuts.splice(currentIndex, 1);
    const targetShortcut = removedShortcuts.length > 0 ? removedShortcuts[0] : undefined;
    if (targetShortcut === undefined) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    if (boundary === 'top') {
      nextShortcuts.unshift(targetShortcut);
    } else {
      nextShortcuts.push(targetShortcut);
    }
    const result: HomeShortcutTreeMutationResult = { shortcuts: nextShortcuts, changed: true };
    return result;
  }

  moveByIdStep(
    shortcuts: ShortcutRecord[],
    shortcutId: string,
    step: HomeShortcutMoveStep
  ): HomeShortcutTreeMutationResult {
    const flatShortcuts = this.flattenToLinkShortcuts(shortcuts);
    const currentIndex = flatShortcuts.findIndex((shortcut: ShortcutRecord) => shortcut.id === shortcutId);
    if (currentIndex < 0) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    const targetIndex = step === 'up' ? currentIndex - 1 : currentIndex + 1;
    if (targetIndex < 0 || targetIndex >= flatShortcuts.length) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    const nextShortcuts = flatShortcuts.map((shortcut: ShortcutRecord) => this.cloneRecord(shortcut));
    const currentShortcut = nextShortcuts[currentIndex];
    nextShortcuts[currentIndex] = nextShortcuts[targetIndex];
    nextShortcuts[targetIndex] = currentShortcut;
    return { shortcuts: nextShortcuts, changed: true };
  }

  moveFromTo(
    shortcuts: ShortcutRecord[],
    request: HomeShortcutMoveRequest
  ): HomeShortcutTreeMutationResult {
    const flatShortcuts = this.flattenToLinkShortcuts(shortcuts);
    const fromIndex = request.expectedFromIndex;
    if (fromIndex < 0 || fromIndex >= flatShortcuts.length) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    if (flatShortcuts[fromIndex].id !== request.shortcutId) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    const targetIndex = Math.max(0, Math.min(request.targetIndex, flatShortcuts.length - 1));
    if (targetIndex === fromIndex) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    const nextShortcuts = flatShortcuts.map((shortcut: ShortcutRecord) => this.cloneRecord(shortcut));
    const movedShortcuts = nextShortcuts.splice(fromIndex, 1);
    const movedShortcut = movedShortcuts.length > 0 ? movedShortcuts[0] : undefined;
    if (movedShortcut === undefined) {
      return { shortcuts: flatShortcuts, changed: false };
    }
    nextShortcuts.splice(targetIndex, 0, movedShortcut);
    return { shortcuts: nextShortcuts, changed: true };
  }

  reorderByIds(
    shortcuts: ShortcutRecord[],
    orderedShortcutIds: string[]
  ): HomeShortcutReorderResult {
    const flatShortcuts = this.flattenToLinkShortcuts(shortcuts);
    const currentShortcuts = flatShortcuts;
    const normalizedIds = orderedShortcutIds.map((shortcutId: string): string => shortcutId.trim());
    const seenIds = new Set<string>();
    for (const shortcutId of normalizedIds) {
      if (shortcutId.length === 0 || seenIds.has(shortcutId)) {
        return { shortcuts: flatShortcuts, changed: false, valid: false };
      }
      seenIds.add(shortcutId);
    }
    if (seenIds.size !== currentShortcuts.length) {
      return { shortcuts: flatShortcuts, changed: false, valid: false };
    }
    for (const shortcut of currentShortcuts) {
      if (!seenIds.has(shortcut.id)) {
        return { shortcuts: flatShortcuts, changed: false, valid: false };
      }
    }

    const shortcutById = new Map<string, ShortcutRecord>();
    currentShortcuts.forEach((shortcut: ShortcutRecord): void => {
      shortcutById.set(shortcut.id, shortcut);
    });
    let orderedIndex = 0;
    const nextShortcuts = flatShortcuts.map((shortcut: ShortcutRecord): ShortcutRecord => {
      const reorderedShortcut = shortcutById.get(normalizedIds[orderedIndex]);
      orderedIndex += 1;
      return reorderedShortcut === undefined
        ? this.cloneRecord(shortcut)
        : this.cloneRecord(reorderedShortcut);
    });
    const changed = nextShortcuts.some((shortcut: ShortcutRecord, index: number): boolean => {
      return shortcut.id !== flatShortcuts[index].id;
    });
    return { shortcuts: nextShortcuts, changed: changed, valid: true };
  }

  cloneRecord(shortcut: ShortcutRecord): ShortcutRecord {
    const cloned: ShortcutRecord = {
      id: shortcut.id,
      scenarioId: shortcut.scenarioId,
      kind: shortcut.kind,
      title: shortcut.title,
      url: shortcut.url,
      folderName: shortcut.folderName,
      position: shortcut.position,
      icon: shortcut.icon,
      description: shortcut.description,
      useOfficialIcon: shortcut.useOfficialIcon,
      autoUseOfficialIcon: shortcut.autoUseOfficialIcon,
      officialIconAvailableAtSave: shortcut.officialIconAvailableAtSave,
      officialIconColorOverride: shortcut.officialIconColorOverride,
      iconRendering: shortcut.iconRendering,
      iconColor: shortcut.iconColor,
      createdAt: shortcut.createdAt,
      updatedAt: shortcut.updatedAt,
      sync: shortcut.sync
    };
    return cloned;
  }

  cloneList(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    return this.flattenToLinkShortcuts(shortcuts).map((shortcut: ShortcutRecord) => this.cloneRecord(shortcut));
  }

  normalizeListPositions(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    return this.flattenToLinkShortcuts(shortcuts).map((shortcut: ShortcutRecord, index: number) => {
      const nextShortcut = this.cloneRecord(shortcut);
      nextShortcut.position = index;
      return nextShortcut;
    });
  }

  flattenToLinkShortcuts(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    const activeShortcuts = shortcuts
      .filter((shortcut: ShortcutRecord) => {
        return shortcut.sync?.deletedAt === undefined && this.isAppOwnedShortcut(shortcut);
      })
      .map((shortcut: ShortcutRecord) => this.cloneRecord(shortcut));
    return this.projectUniqueActiveDestinations(activeShortcuts);
  }

  filterAppOwnedShortcuts(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    return this.flattenToLinkShortcuts(shortcuts);
  }

  extractDomainFromUrl(url: string): string {
    const normalized = url.trim();
    if (normalized.length === 0) {
      return '';
    }
    const withoutProtocol = normalized.replace(/^https?:\/\//, '');
    const slashIndex = withoutProtocol.indexOf('/');
    const host = slashIndex >= 0 ? withoutProtocol.substring(0, slashIndex) : withoutProtocol;
    return host.replace(/^www\./, '');
  }

  private buildFallbackScenario(
    shortcut: ShortcutRecord,
    scenarioId: string,
    defaultScenarioId: string,
    position: number
  ): ShortcutScenarioRecord {
    const now = Date.now();
    const timestamp = shortcut.updatedAt ?? shortcut.createdAt ?? shortcut.sync?.lastModifiedAt ?? now;
    const sync = shortcut.sync;
    return {
      id: scenarioId,
      name: this.resolveFallbackScenarioName(shortcut, scenarioId, defaultScenarioId),
      color: '#3f7d5f',
      icon: 'sparkles',
      position: position,
      archived: false,
      createdAt: shortcut.createdAt ?? timestamp,
      updatedAt: timestamp,
      sync: {
        state: sync?.state ?? 'synced',
        source: sync?.source ?? 'cloud_sync',
        lastModifiedAt: sync?.lastModifiedAt ?? timestamp,
        lastModifiedBy: sync?.lastModifiedBy ?? 'aira-browser',
        deviceId: sync?.deviceId ?? 'aira-browser',
        originId: scenarioId
      }
    };
  }

  private resolveFallbackScenarioName(
    shortcut: ShortcutRecord,
    scenarioId: string,
    defaultScenarioId: string
  ): string {
    const folderName = (shortcut.folderName ?? '').trim();
    if (folderName.length > 0 && folderName !== '首页' && folderName !== 'Aira') {
      return folderName;
    }
    return scenarioId === defaultScenarioId ? '主页收藏' : '主页收藏';
  }

  private resolveShortcutScenarioId(shortcut: ShortcutRecord, defaultScenarioId: string): string {
    const scenarioId = (shortcut.scenarioId ?? '').trim();
    return scenarioId.length > 0 ? scenarioId : defaultScenarioId;
  }

  private resolveDestinationWinners(shortcuts: ShortcutRecord[]): Map<string, ShortcutRecord> {
    const winnerByIdentity: Map<string, ShortcutRecord> = new Map();
    shortcuts.forEach((shortcut: ShortcutRecord): void => {
      const identity = this.resolveShortcutDestinationIdentity(shortcut);
      if (identity.length <= 0) {
        return;
      }
      const currentWinner = winnerByIdentity.get(identity);
      if (currentWinner === undefined || this.compareDestinationWinner(shortcut, currentWinner) < 0) {
        winnerByIdentity.set(identity, shortcut);
      }
    });
    return winnerByIdentity;
  }

  private compareDestinationWinner(left: ShortcutRecord, right: ShortcutRecord): number {
    const positionDelta = left.position - right.position;
    if (positionDelta !== 0) {
      return positionDelta;
    }
    const createdAtDelta = this.normalizeTimestamp(left.createdAt) - this.normalizeTimestamp(right.createdAt);
    if (createdAtDelta !== 0) {
      return createdAtDelta;
    }
    return this.compareStableString(left.id, right.id);
  }

  private resolveDuplicateTombstoneRevision(shortcuts: ShortcutRecord[]): number {
    const latestRevision = shortcuts.reduce((latest: number, shortcut: ShortcutRecord): number => {
      return Math.max(
        latest,
        this.normalizeTimestamp(shortcut.sync?.lastModifiedAt),
        this.normalizeTimestamp(shortcut.updatedAt),
        this.normalizeTimestamp(shortcut.createdAt)
      );
    }, 0);
    return latestRevision + 1;
  }

  private buildDuplicateDestinationTombstone(shortcut: ShortcutRecord, revision: number): ShortcutRecord {
    const tombstone = this.cloneRecord(shortcut);
    tombstone.updatedAt = revision;
    tombstone.sync = {
      state: 'pending_push',
      source: 'local',
      lastModifiedAt: revision,
      lastModifiedBy: 'aira-home-shortcut-identity',
      deviceId: shortcut.sync?.deviceId ?? 'aira-browser',
      originId: shortcut.sync?.originId ?? shortcut.id,
      deletedAt: revision
    };
    return tombstone;
  }

  private normalizeTimestamp(value: number | undefined): number {
    const normalized = Number(value ?? 0);
    return Number.isFinite(normalized) && normalized >= 0 ? Math.floor(normalized) : 0;
  }

  private compareStableString(left: string, right: string): number {
    if (left === right) {
      return 0;
    }
    return left < right ? -1 : 1;
  }

  private findPathStart(value: string): number {
    const slashIndex = value.indexOf('/');
    const queryIndex = value.indexOf('?');
    const hashIndex = value.indexOf('#');
    const candidates = [slashIndex, queryIndex, hashIndex].filter((index: number) => index >= 0);
    return candidates.length <= 0 ? -1 : Math.min(...candidates);
  }

  private normalizeHost(host: string, scheme: string): string {
    const lowerHost = host.toLowerCase();
    if (scheme === 'http' && lowerHost.endsWith(':80')) {
      return lowerHost.substring(0, lowerHost.length - 3);
    }
    if (scheme === 'https' && lowerHost.endsWith(':443')) {
      return lowerHost.substring(0, lowerHost.length - 4);
    }
    return lowerHost;
  }

  private normalizePath(path: string): string {
    if (path.length <= 0 || path === '/') {
      return '';
    }
    const hashIndex = path.indexOf('#');
    const withoutHash = hashIndex >= 0 ? path.substring(0, hashIndex) : path;
    return withoutHash === '/' ? '' : withoutHash;
  }

  private isAppOwnedShortcut(shortcut: ShortcutRecord): boolean {
    const source = shortcut.sync?.source;
    return source === undefined || source === 'seed' || source === 'local';
  }
}
