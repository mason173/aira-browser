import { BrowserDataScope } from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from './BrowserProfileBoundaryService';

export interface BrowserPrivateBoundaryRouteParams {
  dataScope?: BrowserDataScope | string;
  privacyMode?: string;
  boundarySource?: string;
}

export type BrowserPrivateSyncBoundaryAction =
  'read_status' |
  'save_webdav_config' |
  'test_webdav' |
  'read_webdav_remote' |
  'write_local_baseline' |
  'import_bookmark_bundle' |
  'export_bookmark_bundle' |
  'push_webdav' |
  'pull_webdav' |
  'merge_webdav' |
  'resolve_conflict' |
  'continue_destructive' |
  'clear_baseline';

export interface BrowserPrivateSyncBoundaryPlan {
  action: BrowserPrivateSyncBoundaryAction;
  dataScope: BrowserDataScope | string;
  privacyMode: string;
  allowed: boolean;
  reason: string;
  touchesPersistentData: boolean;
  touchesRemoteData: boolean;
  helperText: string;
  summaryLine: string;
}

export class BrowserPrivateBoundaryNavigationService {
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();

  buildRouteParams(dataScope: BrowserDataScope, privacyMode: string = ''): BrowserPrivateBoundaryRouteParams {
    return {
      dataScope: dataScope,
      privacyMode: privacyMode,
      boundarySource: this.isSessionEphemeralBoundary(dataScope, privacyMode) ? 'private_session' : 'profile'
    };
  }

  buildSyncBoundaryPlan(
    action: BrowserPrivateSyncBoundaryAction,
    dataScope: BrowserDataScope | string,
    privacyMode: string = ''
  ): BrowserPrivateSyncBoundaryPlan {
    const normalizedDataScope = String(dataScope ?? '').trim();
    const normalizedPrivacyMode = String(privacyMode ?? '').trim();
    const isSessionEphemeral = this.isSessionEphemeralBoundary(dataScope, privacyMode);
    const touchesRemoteData = this.syncActionTouchesRemoteData(action);
    const touchesPersistentData = true;
    const allowed = !isSessionEphemeral;
    const reason = allowed ? 'allowed' : 'session_ephemeral_boundary';
    const helperText = allowed
      ? '同步操作可访问当前常规浏览资料中的书签、配置和同步基线。'
      : '当前私密会话不会读取或写入常规书签、同步配置、同步基线，也不会触达同步远端。';
    return {
      action: action,
      dataScope: dataScope,
      privacyMode: privacyMode,
      allowed: allowed,
      reason: reason,
      touchesPersistentData: touchesPersistentData,
      touchesRemoteData: touchesRemoteData,
      helperText: helperText,
      summaryLine: `syncBoundary action=${action} dataScope=${normalizedDataScope || 'unknown'} ` +
        `privacy=${normalizedPrivacyMode || 'unknown'} allowed=${allowed ? 1 : 0} reason=${reason} ` +
        `persistent=${touchesPersistentData ? 1 : 0} remote=${touchesRemoteData ? 1 : 0}`
    };
  }

  isSessionEphemeralRoute(params: BrowserPrivateBoundaryRouteParams | undefined): boolean {
    return this.isSessionEphemeralBoundary(params?.dataScope, params?.privacyMode) ||
      String(params?.boundarySource ?? '').trim() === 'private_session';
  }

  private isSessionEphemeralBoundary(
    dataScope: BrowserDataScope | string | undefined,
    privacyMode: string = ''
  ): boolean {
    return this.profileBoundaryService.isSessionEphemeral({
      dataScope: dataScope,
      privacyMode: privacyMode
    });
  }

  private syncActionTouchesRemoteData(action: BrowserPrivateSyncBoundaryAction): boolean {
    return action === 'test_webdav' ||
      action === 'read_webdav_remote' ||
      action === 'push_webdav' ||
      action === 'pull_webdav' ||
      action === 'merge_webdav' ||
      action === 'resolve_conflict' ||
      action === 'continue_destructive';
  }

}
