import { ShortcutRecord } from '../../common/models/BrowserModels';
import {
  HomeShortcutLayoutMetrics,
  HomeShortcutLogicService
} from '../../services/shortcuts/HomeShortcutLogicService';
import { HomeShortcutIconState } from './HomeShortcutTypes';

export class HomeShortcutViewModel {
  private readonly logicService: HomeShortcutLogicService;

  constructor(logicService: HomeShortcutLogicService = new HomeShortcutLogicService()) {
    this.logicService = logicService;
  }

  getGridContentHeight(rowCount: number, gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.logicService.getGridContentHeight(rowCount, gridWidth, metrics);
  }

  resolvePresentationShortcuts(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    return this.logicService.resolvePresentationShortcuts(shortcuts);
  }

  buildShortcutOrderSignature(shortcuts: ShortcutRecord[]): string {
    const shortcutIds: string[] = [];
    shortcuts.forEach((shortcut: ShortcutRecord) => {
      shortcutIds.push(shortcut.id);
    });
    return shortcutIds.join('\u0001');
  }

  buildShortcutContentSignature(shortcuts: ShortcutRecord[]): string {
    const parts: string[] = [];
    shortcuts.forEach((shortcut: ShortcutRecord) => {
      parts.push([
        shortcut.id,
        shortcut.kind ?? 'web',
        shortcut.title,
        shortcut.url,
        shortcut.icon ?? '',
        shortcut.iconRendering ?? '',
        shortcut.iconColor ?? '',
        String(shortcut.position),
        String(shortcut.updatedAt ?? 0)
      ].join('\u0002'));
    });
    return parts.join('\u0001');
  }

  reconcileShortcutOrder(
    currentShortcuts: ShortcutRecord[],
    sourceShortcuts: ShortcutRecord[],
    orderSignature: string
  ): ShortcutRecord[] {
    if (orderSignature.length === 0) {
      return this.cloneShortcutList(sourceShortcuts);
    }
    const orderedIds = orderSignature.split('\u0001');
    const nextShortcuts: ShortcutRecord[] = [];
    const usedIds: string[] = [];
    for (let index = 0; index < orderedIds.length; index += 1) {
      const shortcutId = orderedIds[index];
      if (shortcutId.length === 0 || usedIds.indexOf(shortcutId) >= 0) {
        return this.cloneShortcutList(sourceShortcuts);
      }
      const shortcut = this.findShortcutById(sourceShortcuts, shortcutId) ??
        this.findShortcutById(currentShortcuts, shortcutId);
      if (shortcut === undefined) {
        return this.cloneShortcutList(sourceShortcuts);
      }
      usedIds.push(shortcutId);
      nextShortcuts.push(shortcut);
    }
    return nextShortcuts;
  }

  private cloneShortcutList(shortcuts: ShortcutRecord[]): ShortcutRecord[] {
    const cloned: ShortcutRecord[] = [];
    shortcuts.forEach((shortcut: ShortcutRecord) => {
      cloned.push(shortcut);
    });
    return cloned;
  }

  private findShortcutById(shortcuts: ShortcutRecord[], shortcutId: string): ShortcutRecord | undefined {
    return shortcuts.find((shortcut: ShortcutRecord) => shortcut.id === shortcutId);
  }

  buildLayoutVersion(
    dataVersion: number,
    viewportWidth: number,
    viewportHeight: number,
    gridWidth: number,
    metrics: HomeShortcutLayoutMetrics
  ): number {
    const signatureParts: number[] = [
      dataVersion,
      Math.round(viewportWidth),
      Math.round(viewportHeight),
      Math.round(gridWidth),
      Math.max(1, Math.round(metrics.columns)),
      Math.round(metrics.rowGap),
      Math.round(metrics.targetTileSize),
      Math.round(metrics.minimumTileSize),
      Math.round(metrics.titleTopGap),
      Math.round(metrics.titleBlockHeight)
    ];
    let hash = 17;
    signatureParts.forEach((part: number) => {
      hash = (hash * 31 + part) % 2147483647;
    });
    return hash;
  }

  getShortcutTileSize(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.logicService.getTileSize(gridWidth, metrics);
  }

  getShortcutCardHeight(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.logicService.getCardHeight(gridWidth, metrics);
  }

  getShortcutRowHeight(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.logicService.getRowHeight(gridWidth, metrics);
  }

  getAlignedGridColumnGap(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.logicService.getAlignedGridColumnGap(gridWidth, metrics);
  }

  resolveOccupiedColumnCount(itemCount: number, metrics: HomeShortcutLayoutMetrics): number {
    return Math.max(1, Math.min(
      Math.max(1, Math.floor(metrics.columns)),
      Math.max(0, Math.floor(itemCount))
    ));
  }

  getOccupiedGridContentWidth(
    itemCount: number,
    gridWidth: number,
    contentInset: number,
    metrics: HomeShortcutLayoutMetrics
  ): number {
    const contentWidth = Math.max(1, gridWidth - Math.max(0, contentInset) * 2);
    const configuredColumns = Math.max(1, Math.floor(metrics.columns));
    const occupiedColumns = this.resolveOccupiedColumnCount(itemCount, metrics);
    if (occupiedColumns >= configuredColumns) {
      return contentWidth;
    }
    const columnGap = Math.max(
      metrics.columnGap,
      this.getAlignedGridColumnGap(contentWidth, metrics)
    );
    const fullGridGapWidth = columnGap * Math.max(0, configuredColumns - 1);
    const columnWidth = Math.max(1, (contentWidth - fullGridGapWidth) / configuredColumns);
    return Math.min(
      contentWidth,
      columnWidth * occupiedColumns + columnGap * Math.max(0, occupiedColumns - 1)
    );
  }

  getShortcutTitleFontSize(gridWidth: number, metrics: HomeShortcutLayoutMetrics): number {
    return this.logicService.getTitleFontSize(gridWidth, metrics);
  }

  getShortcutFallbackLabel(shortcut: ShortcutRecord): string {
    const title = shortcut.title.trim();
    if (title.length > 0) {
      return title.substring(0, 1).toUpperCase();
    }
    const domain = this.logicService.extractDomainFromUrl(shortcut.url);
    if (domain.length > 0) {
      return domain.substring(0, 1).toUpperCase();
    }
    return 'Q';
  }

  getShortcutResolvedIcon(shortcut: ShortcutRecord, icons: HomeShortcutIconState[]): HomeShortcutIconState | undefined {
    return icons.find((icon: HomeShortcutIconState) => icon.id === shortcut.id);
  }
}
