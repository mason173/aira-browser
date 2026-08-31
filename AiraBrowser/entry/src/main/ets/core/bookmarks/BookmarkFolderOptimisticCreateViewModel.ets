import { BookmarkNode } from '../../common/models/BrowserModels';
import {
  createLocalBookmarkId,
  sanitizeBookmarkTitle
} from '../../data/repositories/BookmarkRepositoryCore';
import { BookmarkFolderCountState } from './BookmarkFolderCountViewModel';

export interface BookmarkOptimisticFolderInsertResult {
  nodes: BookmarkNode[];
  pendingNode: BookmarkNode;
  folderCountState: BookmarkFolderCountState;
}

export interface BookmarkOptimisticFolderRemoveResult {
  nodes: BookmarkNode[];
  folderCountState: BookmarkFolderCountState;
}

const OPTIMISTIC_FOLDER_DEVICE_ID: string = 'aira-browser-local';
const OPTIMISTIC_FOLDER_ACTOR: string = 'local';

export class BookmarkFolderOptimisticCreateViewModel {
  createPendingFolder(title: string, parentId: string | undefined, siblings: BookmarkNode[]): BookmarkNode {
    const now = Date.now();
    return {
      id: createLocalBookmarkId('folder'),
      type: 'folder',
      parentId: parentId,
      title: sanitizeBookmarkTitle(title, '新建文件夹'),
      position: this.resolveNextPosition(siblings),
      createdAt: now,
      updatedAt: now,
      sync: {
        state: 'pending_push',
        source: 'local',
        lastModifiedAt: now,
        lastModifiedBy: OPTIMISTIC_FOLDER_ACTOR,
        deviceId: OPTIMISTIC_FOLDER_DEVICE_ID
      }
    };
  }

  insertPendingFolder(nodes: BookmarkNode[], pendingNode: BookmarkNode): BookmarkNode[] {
    const nextNodes: BookmarkNode[] = [];
    let inserted = false;
    nodes.forEach((node: BookmarkNode) => {
      if (!inserted && node.type === 'bookmark') {
        nextNodes.push(pendingNode);
        inserted = true;
      }
      if (node.id !== pendingNode.id) {
        nextNodes.push(node);
      }
    });
    if (!inserted) {
      nextNodes.push(pendingNode);
    }
    return nextNodes;
  }

  removePendingFolder(nodes: BookmarkNode[], pendingNodeId: string): BookmarkNode[] {
    return nodes.filter((node: BookmarkNode) => node.id !== pendingNodeId);
  }

  createInsertResult(
    title: string,
    parentId: string | undefined,
    siblings: BookmarkNode[],
    folderCountState: BookmarkFolderCountState
  ): BookmarkOptimisticFolderInsertResult {
    const pendingNode = this.createPendingFolder(title, parentId, siblings);
    const counts = new Map<string, number>(folderCountState.counts);
    counts.set(pendingNode.id, 0);
    return {
      nodes: this.insertPendingFolder(siblings, pendingNode),
      pendingNode: pendingNode,
      folderCountState: {
        ready: true,
        counts: counts,
        loadedFromRealData: folderCountState.loadedFromRealData
      }
    };
  }

  createRemoveResult(
    nodes: BookmarkNode[],
    pendingNodeId: string,
    folderCountState: BookmarkFolderCountState
  ): BookmarkOptimisticFolderRemoveResult {
    const counts = new Map<string, number>(folderCountState.counts);
    counts.delete(pendingNodeId);
    return {
      nodes: this.removePendingFolder(nodes, pendingNodeId),
      folderCountState: {
        ready: folderCountState.ready,
        counts: counts,
        loadedFromRealData: folderCountState.loadedFromRealData
      }
    };
  }

  private resolveNextPosition(siblings: BookmarkNode[]): number {
    if (siblings.length <= 0) {
      return 0;
    }
    let maxPosition = -1;
    siblings.forEach((node: BookmarkNode) => {
      maxPosition = Math.max(maxPosition, node.position);
    });
    return maxPosition + 1;
  }
}
