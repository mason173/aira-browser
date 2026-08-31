import urlUtils from '@ohos.url';
import { BookmarkNode, SyncMetadata } from '../../common/models/BrowserModels';

export interface BookmarkListIconTarget {
  id: string;
  url: string;
  domain?: string;
}

function createEmptyBookmarkNode(): BookmarkNode {
  const sync: SyncMetadata = {
    state: 'local_only',
    source: 'local',
    lastModifiedAt: 0,
    lastModifiedBy: '',
    deviceId: ''
  };
  const node: BookmarkNode = {
    id: '',
    type: 'bookmark',
    parentId: '',
    title: '',
    url: '',
    position: 0,
    createdAt: 0,
    updatedAt: 0,
    sync: sync
  };
  return node;
}

const EMPTY_BOOKMARK_NODE: BookmarkNode = createEmptyBookmarkNode();

export class BookmarkListDataSource implements IDataSource {
  private listeners: DataChangeListener[] = [];
  private nodes: BookmarkNode[] = [];

  totalCount(): number {
    return this.nodes.length;
  }

  getData(index: number): BookmarkNode {
    if (index < 0 || index >= this.nodes.length) {
      return EMPTY_BOOKMARK_NODE;
    }
    return this.nodes[index];
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

  replaceNodes(nodes: BookmarkNode[]): void {
    const seenIds = new Set<string>();
    const uniqueNodes: BookmarkNode[] = [];
    nodes.forEach((node: BookmarkNode) => {
      if (node.id.length <= 0 || seenIds.has(node.id)) {
        return;
      }
      seenIds.add(node.id);
      uniqueNodes.push(node);
    });
    this.nodes = uniqueNodes;
    this.notifyDataReload();
  }

  getIconTargetsAround(startIndex: number, endIndex: number, bufferRows: number): BookmarkListIconTarget[] {
    const safeStart = Math.max(0, Math.min(startIndex, endIndex) - bufferRows);
    const safeEnd = Math.min(this.nodes.length - 1, Math.max(startIndex, endIndex) + bufferRows);
    const targets: BookmarkListIconTarget[] = [];
    for (let index = safeStart; index <= safeEnd; index += 1) {
      const node = this.nodes[index];
      if (node.type === 'bookmark' && node.url !== undefined && node.url.length > 0) {
        targets.push({
          id: node.id,
          url: node.url,
          domain: this.resolveDomainHint(node.url)
        });
      }
    }
    return targets;
  }

  private resolveDomainHint(url: string): string {
    try {
      const parsed = urlUtils.URL.parseURL(this.toNavigableUrl(url.trim()));
      let normalized = parsed.hostname.trim().toLowerCase();
      if (normalized.startsWith('www.')) {
        normalized = normalized.slice(4);
      }
      return normalized;
    } catch (_error) {
      return '';
    }
  }

  private toNavigableUrl(input: string): string {
    if (/^[a-z][a-z0-9+.-]*:\/\//i.test(input)) {
      return input;
    }
    return `https://${input}`;
  }

  private notifyDataReload(): void {
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}
