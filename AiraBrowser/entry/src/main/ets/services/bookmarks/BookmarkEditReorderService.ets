import { BookmarkNode } from '../../common/models/BrowserModels';

export interface BookmarkEditReorderPlan {
  sourceIndex: number;
  targetIndex: number;
  changed: boolean;
  orderedNodes: BookmarkNode[];
  orderedNodeIds: string[];
}

/** Owns edit-mode bookmark reorder policy, including the folder/bookmark partition. */
export class BookmarkEditReorderService {
  planMoveByOffset(
    nodes: BookmarkNode[],
    nodeId: string,
    offsetY: number,
    rowStride: number
  ): BookmarkEditReorderPlan {
    const sourceIndex = this.findNodeIndex(nodes, nodeId);
    if (sourceIndex < 0 || rowStride <= 0) {
      return this.buildUnchangedPlan(nodes, sourceIndex);
    }
    const requestedIndex = sourceIndex + Math.round(offsetY / rowStride);
    return this.planMoveToIndex(nodes, nodeId, requestedIndex);
  }

  planMoveToIndex(nodes: BookmarkNode[], nodeId: string, requestedIndex: number): BookmarkEditReorderPlan {
    const sourceIndex = this.findNodeIndex(nodes, nodeId);
    if (sourceIndex < 0) {
      return this.buildUnchangedPlan(nodes, sourceIndex);
    }
    const source = nodes[sourceIndex];
    const bounds = this.resolveTypeBounds(nodes, source.type);
    if (bounds.startIndex < 0 || bounds.endIndex < bounds.startIndex) {
      return this.buildUnchangedPlan(nodes, sourceIndex);
    }
    const targetIndex = Math.max(bounds.startIndex, Math.min(requestedIndex, bounds.endIndex));
    if (targetIndex === sourceIndex) {
      return this.buildUnchangedPlan(nodes, sourceIndex);
    }
    const orderedNodes = nodes.slice();
    const movedNodes = orderedNodes.splice(sourceIndex, 1);
    const movedNode = movedNodes.length > 0 ? movedNodes[0] : undefined;
    if (movedNode === undefined) {
      return this.buildUnchangedPlan(nodes, sourceIndex);
    }
    orderedNodes.splice(targetIndex, 0, movedNode);
    return {
      sourceIndex: sourceIndex,
      targetIndex: targetIndex,
      changed: true,
      orderedNodes: orderedNodes,
      orderedNodeIds: orderedNodes.map((node: BookmarkNode) => node.id)
    };
  }

  resolvePreviewIndex(index: number, sourceIndex: number, targetIndex: number): number {
    if (index < 0 || sourceIndex < 0 || targetIndex < 0 || index === sourceIndex) {
      return index;
    }
    if (targetIndex > sourceIndex && index > sourceIndex && index <= targetIndex) {
      return index - 1;
    }
    if (targetIndex < sourceIndex && index >= targetIndex && index < sourceIndex) {
      return index + 1;
    }
    return index;
  }

  private resolveTypeBounds(nodes: BookmarkNode[], type: 'folder' | 'bookmark'): TypeBounds {
    let startIndex = -1;
    let endIndex = -1;
    for (let index = 0; index < nodes.length; index += 1) {
      if (nodes[index].type !== type) {
        continue;
      }
      if (startIndex < 0) {
        startIndex = index;
      }
      endIndex = index;
    }
    return {
      startIndex: startIndex,
      endIndex: endIndex
    };
  }

  private findNodeIndex(nodes: BookmarkNode[], nodeId: string): number {
    for (let index = 0; index < nodes.length; index += 1) {
      if (nodes[index].id === nodeId) {
        return index;
      }
    }
    return -1;
  }

  private buildUnchangedPlan(nodes: BookmarkNode[], sourceIndex: number): BookmarkEditReorderPlan {
    return {
      sourceIndex: sourceIndex,
      targetIndex: sourceIndex,
      changed: false,
      orderedNodes: nodes.slice(),
      orderedNodeIds: nodes.map((node: BookmarkNode) => node.id)
    };
  }
}

interface TypeBounds {
  startIndex: number;
  endIndex: number;
}
