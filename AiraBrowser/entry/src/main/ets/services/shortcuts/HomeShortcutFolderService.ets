import { ShortcutRecord } from '../../common/models/BrowserModels';

export type HomeShortcutFolderOperation = 'merge' | 'move' | 'reorder' | 'rename' | 'resize' | 'dissolve' | 'extract';

export interface HomeShortcutFolderCommand {
  operation: HomeShortcutFolderOperation;
  shortcutId: string;
  targetId?: string;
  parentId?: string;
  orderedIds?: string[];
  title?: string;
  large?: boolean;
  createdFolderId?: string;
  dropOperation?: 'merge' | 'move';
}

export interface HomeShortcutFolderMutation {
  shortcuts: ShortcutRecord[];
  changed: boolean;
}

/** One flat aggregate: membership and identity survive moves; position orders every container. */
export class HomeShortcutFolderService {
  isFolder(shortcut: ShortcutRecord): boolean {
    return shortcut.kind === 'folder';
  }

  resolveParentId(shortcut: ShortcutRecord, records: ShortcutRecord[]): string {
    if (this.isFolder(shortcut) || !shortcut.parentId) {
      return '';
    }
    const parent = records.find((item: ShortcutRecord): boolean => item.id === shortcut.parentId &&
      item.kind === 'folder' && item.sync?.deletedAt === undefined &&
      (item.scenarioId ?? '') === (shortcut.scenarioId ?? ''));
    return parent?.id ?? '';
  }

  listContainer(records: ShortcutRecord[], parentId: string = ''): ShortcutRecord[] {
    return records.filter((item: ShortcutRecord): boolean => item.sync?.deletedAt === undefined &&
      this.resolveParentId(item, records) === parentId)
      .slice().sort((left: ShortcutRecord, right: ShortcutRecord): number => left.position - right.position);
  }

  apply(records: ShortcutRecord[], command: HomeShortcutFolderCommand, folderId: string, now: number): HomeShortcutFolderMutation {
    if (command.operation === 'extract') return this.extract(records, command, folderId, now);
    let next = records.map((item: ShortcutRecord): ShortcutRecord => this.clone(item));
    const active = next.find((item: ShortcutRecord): boolean => item.id === command.shortcutId);
    if (!active || active.sync?.deletedAt !== undefined) {
      return { shortcuts: records, changed: false };
    }
    const previousParent = this.resolveParentId(active, next);
    if (command.operation === 'merge') {
      const target = next.find((item: ShortcutRecord): boolean => item.id === command.targetId);
      if (!target || target.id === active.id || this.isFolder(active) || this.isFolder(target) ||
        this.resolveParentId(target, next) !== previousParent) {
        return { shortcuts: records, changed: false };
      }
      // Only one folder level. Children can be moved, but cannot form nested folders.
      if (previousParent.length > 0) {
        return { shortcuts: records, changed: false };
      }
      const folder: ShortcutRecord = {
        id: folderId, scenarioId: target.scenarioId, kind: 'folder', title: command.title?.trim() || 'Folder',
        url: '', folderName: '首页', position: target.position, folderDisplayMode: 'small',
        createdAt: now, updatedAt: now,
        sync: { state: 'pending_push', source: 'local', lastModifiedAt: now,
          lastModifiedBy: 'aira-shortcut-manager', deviceId: target.sync?.deviceId ?? 'aira-phone-local', originId: folderId }
      };
      next.splice(next.findIndex((item: ShortcutRecord): boolean => item.id === target.id), 0, folder);
      active.scenarioId = target.scenarioId;
      active.parentId = folderId;
      target.parentId = folderId;
      next = this.reorderContainer(next, folderId, [target.id, active.id]) ?? next;
    } else if (command.operation === 'move') {
      if (this.isFolder(active)) {
        return { shortcuts: records, changed: false };
      }
      const parentId = command.parentId ?? '';
      if (parentId === previousParent) {
        return { shortcuts: records, changed: false };
      }
      const parent = next.find((item: ShortcutRecord): boolean => item.id === parentId &&
        item.kind === 'folder' && item.sync?.deletedAt === undefined);
      if (parentId.length > 0 && !parent) {
        return { shortcuts: records, changed: false };
      }
      if (parent !== undefined) active.scenarioId = parent.scenarioId;
      active.parentId = parentId.length > 0 ? parentId : undefined;
      if (previousParent.length > 0) {
        next = this.dissolveSmallSource(next, previousParent);
      }
      if (parentId.length > 0 && command.orderedIds === undefined) {
        const children = this.listContainer(next, parentId).filter((item: ShortcutRecord): boolean => item.id !== active.id);
        next = this.reorderContainer(next, parentId, children.map((item: ShortcutRecord): string => item.id).concat([active.id])) ?? next;
      }
      if (command.orderedIds !== undefined) {
        const reordered = this.reorderContainer(next, parentId, command.orderedIds);
        if (reordered === undefined) return { shortcuts: records, changed: false };
        next = reordered;
      }
    } else if (command.operation === 'reorder') {
      const reordered = this.reorderContainer(next, command.parentId ?? '', command.orderedIds ?? []);
      if (reordered === undefined) return { shortcuts: records, changed: false };
      next = reordered;
    } else {
      if (!this.isFolder(active)) {
        return { shortcuts: records, changed: false };
      }
      if (command.operation === 'rename') {
        const title = (command.title ?? '').trim();
        if (title.length === 0 || title === active.title) return { shortcuts: records, changed: false };
        active.title = title;
      } else if (command.operation === 'resize') {
        const mode = command.large ? 'large' : 'small';
        if (active.folderDisplayMode === mode) return { shortcuts: records, changed: false };
        active.folderDisplayMode = mode;
      } else if (command.operation === 'dissolve') {
        next = this.dissolve(next, active.id);
      }
    }
    next.forEach((item: ShortcutRecord, index: number): void => { item.position = index; });
    const changed = JSON.stringify(next) !== JSON.stringify(records);
    return { shortcuts: next, changed: changed };
  }

  remove(records: ShortcutRecord[], shortcutId: string): ShortcutRecord[] {
    const item = records.find((record: ShortcutRecord): boolean => record.id === shortcutId);
    if (!item) return records;
    if (this.isFolder(item)) return this.dissolve(records, item.id);
    const parent = this.resolveParentId(item, records);
    const next = records.filter((record: ShortcutRecord): boolean => record.id !== shortcutId);
    return parent.length > 0 ? this.dissolveSmallSource(next, parent) : next;
  }

  private dissolveSmallSource(records: ShortcutRecord[], folderId: string): ShortcutRecord[] {
    return this.listContainer(records, folderId).length <= 1 ? this.dissolve(records, folderId) : records;
  }

  private extract(records: ShortcutRecord[], command: HomeShortcutFolderCommand, folderId: string, now: number): HomeShortcutFolderMutation {
    const active = records.find((item: ShortcutRecord): boolean => item.id === command.shortcutId);
    if (!active || this.resolveParentId(active, records).length === 0) return { shortcuts: records, changed: false };
    const moved = this.apply(records, { operation: 'move', shortcutId: active.id, parentId: '' }, '', now);
    if (!moved.changed) return { shortcuts: records, changed: false };
    let next = moved.shortcuts;
    if (command.dropOperation !== undefined) {
      const dropped = this.apply(next, { operation: command.dropOperation, shortcutId: active.id,
        targetId: command.targetId, parentId: command.parentId, title: command.title }, folderId, now);
      if (!dropped.changed) return { shortcuts: records, changed: false };
      next = dropped.shortcuts;
    }
    const root = this.listContainer(next);
    const ordered = (command.orderedIds ?? this.listContainer(moved.shortcuts).map((item: ShortcutRecord): string => item.id))
      .map((id: string): string => command.dropOperation === 'merge' && id === command.targetId ? folderId : id)
      .filter((id: string): boolean => root.some((item: ShortcutRecord): boolean => item.id === id));
    const reordered = this.reorderContainer(next, '', ordered);
    if (!reordered) return { shortcuts: records, changed: false };
    reordered.forEach((item: ShortcutRecord, index: number): void => { item.position = index; });
    return { shortcuts: reordered, changed: true };
  }

  private reorderContainer(records: ShortcutRecord[], parentId: string, ordered: string[]): ShortcutRecord[] | undefined {
    const container = this.listContainer(records, parentId);
    if (ordered.length !== container.length || new Set(ordered).size !== ordered.length ||
      ordered.some((id: string): boolean => !container.some((item: ShortcutRecord): boolean => item.id === id))) return undefined;
    let cursor = 0;
    const members = new Map<string, ShortcutRecord>();
    container.forEach((item: ShortcutRecord): void => { members.set(item.id, item); });
    return records.map((item: ShortcutRecord): ShortcutRecord => members.has(item.id)
      ? members.get(ordered[cursor++]) ?? item : item);
  }

  private dissolve(records: ShortcutRecord[], folderId: string): ShortcutRecord[] {
    return records.filter((item: ShortcutRecord): boolean => item.id !== folderId)
      .map((item: ShortcutRecord): ShortcutRecord => this.promoteMember(item, folderId));
  }
  private promoteMember(item: ShortcutRecord, folderId: string): ShortcutRecord {
    if (item.parentId !== folderId) return item;
    const promoted = this.clone(item);
    promoted.parentId = undefined;
    return promoted;
  }

  private clone(item: ShortcutRecord): ShortcutRecord {
    return {
      id: item.id, scenarioId: item.scenarioId, kind: item.kind, title: item.title, url: item.url,
      folderName: item.folderName, position: item.position, parentId: item.parentId,
      folderDisplayMode: item.folderDisplayMode, icon: item.icon, description: item.description,
      useOfficialIcon: item.useOfficialIcon, autoUseOfficialIcon: item.autoUseOfficialIcon,
      officialIconAvailableAtSave: item.officialIconAvailableAtSave,
      officialIconColorOverride: item.officialIconColorOverride, iconRendering: item.iconRendering,
      iconColor: item.iconColor, createdAt: item.createdAt, updatedAt: item.updatedAt, sync: item.sync
    };
  }

}
