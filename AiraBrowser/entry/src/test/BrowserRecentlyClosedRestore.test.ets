import { describe, expect, it } from '@ohos/hypium';
import { BrowserTabState } from '../main/ets/core/tabs/TabManager';
import { BrowserDownloadNavigationStateCoordinator } from
  '../main/ets/core/browser/BrowserDownloadNavigationStateCoordinator';
import {
  BrowserRecentlyClosedTabRecord,
  BrowserRecentlyClosedTabsService
} from '../main/ets/core/browser/BrowserRecentlyClosedTabsService';
import {
  BrowserNonRestorableNavigationGuardRecord,
  BrowserNonRestorableNavigationGuardStore
} from '../main/ets/data/browser/BrowserNonRestorableNavigationGuardStore';

class MemoryNonRestorableNavigationGuardStore implements BrowserNonRestorableNavigationGuardStore {
  async loadRecords(): Promise<BrowserNonRestorableNavigationGuardRecord[]> {
    return [];
  }

  async saveRecords(_records: BrowserNonRestorableNavigationGuardRecord[]): Promise<void> {
  }
}

function buildClosedTab(id: string, url: string): BrowserTabState {
  return {
    id: id,
    profileId: 'profile-main',
    title: 'Example',
    url: url,
    isHome: false,
    lastActiveAt: 1,
    pendingUrl: url,
    navigationHistory: [url],
    navigationIndex: 0,
    runtimeState: 'suspended',
    lastError: '',
    lastRestoreReason: '',
    lastDiscardReason: '',
    lastCrashReason: '',
    lastLoadedAt: 1,
    webStatePath: '',
    webStateUpdatedAt: 0,
    scrollOffsetY: 0,
    lastGoodUrl: url,
    lastGoodTitle: 'Example',
    lastRestorableUrl: url,
    lastRestorableTitle: 'Example',
    lastRestoreType: 'reload',
    privacyMode: 'regular',
    dataScope: 'profile_persistent',
    launchContext: {
      sourceType: '',
      sourceId: '',
      sourceUrl: '',
      key: ''
    },
    openerTabId: '',
    openSource: '',
    openedByNewWindow: false,
    pinned: false,
    muted: false,
    audible: false
  };
}

function buildRecord(id: string, url: string): BrowserRecentlyClosedTabRecord {
  return {
    id: id,
    originalTabId: id,
    closedAt: 1,
    windowId: 'window-main',
    tab: buildClosedTab(id, url)
  };
}

export default function browserRecentlyClosedRestoreTest(): void {
  describe('BrowserRecentlyClosed restore', () => {
    it('restores a stored page even after that URL becomes a download guard', 0, () => {
      const coordinator = new BrowserDownloadNavigationStateCoordinator(
        new MemoryNonRestorableNavigationGuardStore()
      );
      const service = new BrowserRecentlyClosedTabsService(coordinator);
      const pageUrl = 'https://example.com/article';
      const records = [
        buildRecord('closed-page', pageUrl),
        buildRecord('closed-sibling', 'https://example.com/other')
      ];
      coordinator.markDownloadUrlHandled(pageUrl);

      const restored = service.restoreByRecordId([], '', records, 'closed-page');

      expect(restored.restored).assertTrue();
      expect(restored.tabs.length).assertEqual(1);
      expect(restored.tabs[0].url).assertEqual(pageUrl);
      expect(coordinator.resolveRestorableNavigation(restored.tabs[0]).url).assertEqual(pageUrl);
      expect(restored.remainingRecords.length).assertEqual(1);
      expect(restored.remainingRecords[0].id).assertEqual('closed-sibling');
    });

    it('keeps the list when the clicked record is gone or has no page URL', 0, () => {
      const service = new BrowserRecentlyClosedTabsService(
        new BrowserDownloadNavigationStateCoordinator(new MemoryNonRestorableNavigationGuardStore())
      );
      const records = [buildRecord('closed-internal', 'aira://downloads')];

      const missing = service.restoreByRecordId([], '', records, 'closed-missing');
      const emptyUrl = service.restoreByRecordId([], '', records, 'closed-internal');

      expect(missing.restored).assertFalse();
      expect(missing.remainingRecords.length).assertEqual(1);
      expect(emptyUrl.restored).assertFalse();
      expect(emptyUrl.remainingRecords[0].id).assertEqual('closed-internal');
    });
  });
}
