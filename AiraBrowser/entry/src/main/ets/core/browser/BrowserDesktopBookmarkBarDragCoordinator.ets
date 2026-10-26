import { BookmarkNode, BookmarkStorageScope } from '../../common/models/BrowserModels';
import {
  BrowserDesktopBookmarkBarDropTarget,
  BrowserDesktopBookmarkBarReorderAction,
  BrowserDesktopBookmarkBarSnapshot,
  BrowserDesktopBookmarkBarViewModel
} from './BrowserDesktopBookmarkBarViewModel';

/** Rebase the drop against current siblings, including items hidden by overflow. */
export function planDesktopBookmarkBarReorder(
  siblings: BookmarkNode[],
  nodeId: string,
  anchorId: string,
  placement: 'before' | 'after'
): string[] | undefined {
  if (nodeId === anchorId || !siblings.some((node: BookmarkNode): boolean => node.id === nodeId)) {
    return undefined;
  }
  const orderedIds = siblings.filter((node: BookmarkNode): boolean => node.id !== nodeId)
    .map((node: BookmarkNode): string => node.id);
  const anchorIndex = orderedIds.indexOf(anchorId);
  if (anchorIndex < 0) {
    return undefined;
  }
  orderedIds.splice(anchorIndex + (placement === 'after' ? 1 : 0), 0, nodeId);
  return orderedIds.every((id: string, index: number): boolean => siblings[index].id === id)
    ? undefined
    : orderedIds;
}

/** A drag belongs to one bar and privacy scope; hover never writes bookmark data. */
export class BrowserDesktopBookmarkBarDragCoordinator {
  private readonly viewModel: BrowserDesktopBookmarkBarViewModel;
  private nodeId: string = '';
  private rootId: string = '';
  private scope: BookmarkStorageScope = 'regular';

  constructor(viewModel: BrowserDesktopBookmarkBarViewModel) {
    this.viewModel = viewModel;
  }

  begin(snapshot: BrowserDesktopBookmarkBarSnapshot, nodeId: string): boolean {
    this.cancel();
    if (snapshot.rootId.length === 0 || !snapshot.visibleItems.some((node: BookmarkNode): boolean => {
      return node.id === nodeId && node.parentId === snapshot.rootId && node.sync.deletedAt === undefined;
    })) {
      return false;
    }
    this.nodeId = nodeId;
    this.rootId = snapshot.rootId;
    this.scope = snapshot.scope;
    return true;
  }

  isActive(snapshot: BrowserDesktopBookmarkBarSnapshot): boolean {
    return this.nodeId.length > 0 && snapshot.rootId === this.rootId && snapshot.scope === this.scope &&
      snapshot.visibleItems.some((node: BookmarkNode): boolean => node.id === this.nodeId) &&
      snapshot.allItems.some((node: BookmarkNode): boolean => {
        return node.id === this.nodeId && node.parentId === this.rootId && node.sync.deletedAt === undefined;
      });
  }

  update(snapshot: BrowserDesktopBookmarkBarSnapshot, offsetXVp: number): BrowserDesktopBookmarkBarDropTarget | undefined {
    if (!this.isActive(snapshot)) {
      return undefined;
    }
    const target = this.viewModel.resolveDropTarget(snapshot, offsetXVp);
    if (target === undefined || planDesktopBookmarkBarReorder(
      snapshot.allItems, this.nodeId, target.anchorId, target.placement
    ) === undefined) {
      return undefined;
    }
    return target;
  }

  finish(snapshot: BrowserDesktopBookmarkBarSnapshot, offsetXVp: number): BrowserDesktopBookmarkBarReorderAction | undefined {
    const target = this.update(snapshot, offsetXVp);
    const action: BrowserDesktopBookmarkBarReorderAction | undefined = target === undefined ? undefined : {
      kind: 'reorder_node', scope: this.scope, nodeId: this.nodeId,
      anchorId: target.anchorId, placement: target.placement
    };
    this.cancel();
    return action;
  }

  cancel(): void {
    this.nodeId = '';
    this.rootId = '';
    this.scope = 'regular';
  }
}
