import { describe, expect, it } from '@ohos/hypium';
import { TabRecord } from '../main/ets/common/models/BrowserModels';
import { BrowserPrivateProfileLifecycleCoordinator } from
  '../main/ets/core/browser/BrowserPrivateProfileLifecycleCoordinator';
import { BrowserTabSessionRestoreService } from '../main/ets/core/browser/BrowserTabSessionRestoreService';

function privateRecord(id: string, webStatePath: string = ''): TabRecord {
  return {
    id: id,
    windowId: 'window-1',
    profileId: 'profile-main',
    title: id,
    url: `https://${id}.example`,
    isActive: true,
    isPinned: false,
    lastActiveAt: 1,
    privacyMode: 'private',
    dataScope: 'session_ephemeral',
    webStatePath: webStatePath
  };
}

function regularRecord(id: string): TabRecord {
  return {
    id: id,
    windowId: 'window-1',
    profileId: 'profile-main',
    title: id,
    url: `https://${id}.example`,
    isActive: false,
    isPinned: false,
    lastActiveAt: 1,
    privacyMode: 'regular',
    dataScope: 'profile_persistent'
  };
}

export default function privateTabPreviewRestorePolicyTest(): void {
  describe('PrivateTabPreviewRestorePolicy', () => {
    it('keeps private tab card images when private tabs are allowed to restore', 0, () => {
      const lifecycle = new BrowserPrivateProfileLifecycleCoordinator();
      const restoreService = new BrowserTabSessionRestoreService();
      const request = lifecycle.buildStartupResidualCleanupRequest(
        [privateRecord('private-tab', '/cache/private-tab.snapshot'), regularRecord('regular-tab')],
        'profile-main',
        false,
        restoreService.shouldPersistPrivateTabs('restore_private_tabs')
      );

      expect(request.tabIds.length).assertEqual(0);
      expect(request.snapshotPaths.length).assertEqual(0);
      expect(request.profileId).assertEqual('profile-main');
    });

    it('still clears private tab card images when restore is off', 0, () => {
      const lifecycle = new BrowserPrivateProfileLifecycleCoordinator();
      const restoreService = new BrowserTabSessionRestoreService();
      const request = lifecycle.buildStartupResidualCleanupRequest(
        [privateRecord('private-tab', '/cache/private-tab.snapshot'), regularRecord('regular-tab')],
        'profile-main',
        true,
        restoreService.shouldPersistPrivateTabs('never_restore')
      );

      expect(request.tabIds.length).assertEqual(1);
      expect(request.tabIds[0]).assertEqual('private-tab');
      expect(request.snapshotPaths.length).assertEqual(1);
      expect(request.snapshotPaths[0]).assertEqual('/cache/private-tab.snapshot');
      expect(request.preserveCookiesOnClose).assertEqual(true);
    });
  });
}
