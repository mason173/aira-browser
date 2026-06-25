import type { LeafTabSyncEngineResult, LeafTabSyncInitialChoice } from './engine';
import type { LeafTabSyncSnapshot } from './schema';

export type LeafTabSyncRemoteKind = 'webdav' | 'aira-cloud';

export type LeafTabSyncTriggerProvider = LeafTabSyncRemoteKind | undefined;

export type LeafTabSyncRoute =
  | {
      kind: 'none';
      reason: 'disabled' | 'missing-cloud-account' | 'missing-webdav-config';
    }
  | {
      kind: 'single';
      remoteKind: LeafTabSyncRemoteKind;
    }
  | {
      kind: 'dual';
      primaryRemoteKind: LeafTabSyncRemoteKind;
      secondaryRemoteKind: LeafTabSyncRemoteKind;
      secondaryPolicy: 'mirror-primary' | 'mirror-if-primary-pulled';
    };

export const resolveLeafTabSyncRoute = (params: {
  cloudEnabled: boolean;
  cloudAvailable: boolean;
  webdavEnabled: boolean;
  webdavAvailable: boolean;
  preferredPrimaryRemoteKind?: LeafTabSyncRemoteKind;
  triggerProvider?: LeafTabSyncTriggerProvider;
}): LeafTabSyncRoute => {
  const cloudActive = params.cloudEnabled && params.cloudAvailable;
  const webdavActive = params.webdavEnabled && params.webdavAvailable;

  if (cloudActive && webdavActive) {
    const preferredPrimaryRemoteKind = params.preferredPrimaryRemoteKind === 'webdav'
      ? 'webdav'
      : 'aira-cloud';
    return {
      kind: 'dual',
      primaryRemoteKind: preferredPrimaryRemoteKind,
      secondaryRemoteKind: preferredPrimaryRemoteKind === 'aira-cloud' ? 'webdav' : 'aira-cloud',
      secondaryPolicy: 'mirror-primary',
    };
  }

  if (cloudActive) {
    return {
      kind: 'single',
      remoteKind: 'aira-cloud',
    };
  }

  if (webdavActive) {
    return {
      kind: 'single',
      remoteKind: 'webdav',
    };
  }

  if (params.cloudEnabled && !params.cloudAvailable) {
    return {
      kind: 'none',
      reason: 'missing-cloud-account',
    };
  }

  if (params.webdavEnabled && !params.webdavAvailable) {
    return {
      kind: 'none',
      reason: 'missing-webdav-config',
    };
  }

  return {
    kind: 'none',
    reason: 'disabled',
  };
};

export const shouldMirrorLeafTabPrimarySyncResult = (
  route: Extract<LeafTabSyncRoute, { kind: 'dual' }>,
  result: LeafTabSyncEngineResult,
) => {
  if (route.secondaryPolicy === 'mirror-primary') return true;
  return result.kind === 'pull' || result.kind === 'merge';
};

export const shouldBuildLeafTabPrimaryLocalSnapshot = (hasPendingLocalChanges: boolean) => {
  return hasPendingLocalChanges;
};

export type LeafTabDualSecondarySyncPlan = {
  mode: Extract<LeafTabSyncInitialChoice, 'push-local'>;
  snapshot: LeafTabSyncSnapshot;
};

export const createLeafTabDualSecondarySyncPlan = (
  route: Extract<LeafTabSyncRoute, { kind: 'dual' }>,
  result: LeafTabSyncEngineResult,
): LeafTabDualSecondarySyncPlan => {
  if (!shouldMirrorLeafTabPrimarySyncResult(route, result)) {
    return {
      mode: 'push-local',
      snapshot: result.snapshot,
    };
  }
  return {
    mode: 'push-local',
    snapshot: result.snapshot,
  };
};
