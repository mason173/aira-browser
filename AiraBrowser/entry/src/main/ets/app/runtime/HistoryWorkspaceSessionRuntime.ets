import {
  HistoryWorkspaceSessionCoordinator
} from '../../core/history/HistoryWorkspaceSessionCoordinator';
import { HistoryFeature } from '../../features/history/HistoryFeature';
import { HistoryManagementBoundary } from '../../features/history/HistoryFeature';
import {
  sharedHistoryRepository,
  sharedPreferencesRepository,
  sharedRecentlyClosedTabRepository
} from '../bootstrap/BrowserAppRuntime';

interface HistoryWorkspaceSessionEntry {
  key: string;
  coordinator: HistoryWorkspaceSessionCoordinator;
  lastAccessAt: number;
}

/** Retains native History-tab state while another tab owns the visible stage. */
export class HistoryWorkspaceSessionRuntime {
  private readonly entries: Map<string, HistoryWorkspaceSessionEntry> =
    new Map<string, HistoryWorkspaceSessionEntry>();
  private readonly maximumRetainedSessions: number = 8;
  acquire(tabId: string, privateMode: boolean): HistoryWorkspaceSessionCoordinator {
    const key = `${privateMode ? 'private' : 'regular'}:${tabId.trim()}`;
    const existing = this.entries.get(key);
    if (existing !== undefined) {
      existing.lastAccessAt = Date.now();
      return existing.coordinator;
    }
    const dataScope = privateMode ? 'session_ephemeral' : 'profile_persistent';
    const privacyMode = privateMode ? 'private' : 'regular';
    const coordinator = new HistoryWorkspaceSessionCoordinator(new HistoryFeature(
      sharedHistoryRepository,
      sharedPreferencesRepository,
      sharedRecentlyClosedTabRepository
    ), new HistoryManagementBoundary(dataScope, privacyMode));
    this.entries.set(key, {
      key: key,
      coordinator: coordinator,
      lastAccessAt: Date.now()
    });
    this.prune(key);
    return coordinator;
  }

  private prune(retainedKey: string): void {
    if (this.entries.size <= this.maximumRetainedSessions) {
      return;
    }
    const candidates = Array.from(this.entries.values())
      .filter((entry: HistoryWorkspaceSessionEntry): boolean => entry.key !== retainedKey)
      .sort((left: HistoryWorkspaceSessionEntry, right: HistoryWorkspaceSessionEntry): number =>
        left.lastAccessAt - right.lastAccessAt);
    while (this.entries.size > this.maximumRetainedSessions && candidates.length > 0) {
      const candidate = candidates.shift();
      if (candidate !== undefined) {
        this.entries.delete(candidate.key);
      }
    }
  }
}

export const historyWorkspaceSessionRuntime: HistoryWorkspaceSessionRuntime =
  new HistoryWorkspaceSessionRuntime();
