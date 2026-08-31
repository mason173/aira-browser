import { MediaSessionEvidenceProjection } from '../../features/mediaDiscovery/MediaEvidenceGraphModels';
import { MediaSessionResolutionSnapshot } from '../../features/mediaDiscovery/MediaSessionResolutionModels';
import { MediaSessionResolutionService } from './MediaSessionResolutionService';

export interface MediaSessionResolutionRuntimeInput {
  tabId: string;
  evidence: MediaSessionEvidenceProjection;
  now: number;
}

/**
 * Owns the latest immutable Session Resolution Snapshot for each tab.
 * Resolution errors fail closed for only the affected tab.
 */
export class MediaSessionResolutionRuntimeService {
  private readonly resolver: MediaSessionResolutionService;
  private snapshotByTabId: Map<string, MediaSessionResolutionSnapshot> = new Map();

  constructor(resolver: MediaSessionResolutionService = new MediaSessionResolutionService()) {
    this.resolver = resolver;
  }

  resolve(input: MediaSessionResolutionRuntimeInput): MediaSessionResolutionSnapshot | undefined {
    const tabId = input.tabId.trim();
    try {
      if (tabId.length <= 0 || input.evidence.scope.tabId.trim() !== tabId) {
        throw new Error('session_resolution_scope_mismatch');
      }
      const snapshot = this.resolver.resolve(input.evidence, input.now, this.snapshotByTabId.get(tabId));
      this.snapshotByTabId.set(tabId, snapshot);
      return snapshot;
    } catch (_error) {
      this.snapshotByTabId.delete(tabId);
      return undefined;
    }
  }

  getSnapshot(tabId: string): MediaSessionResolutionSnapshot | undefined {
    return this.snapshotByTabId.get(tabId.trim());
  }

  clearTab(tabId: string): void {
    this.snapshotByTabId.delete(tabId.trim());
  }
}
