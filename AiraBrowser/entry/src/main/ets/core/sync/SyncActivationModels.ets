import { AiraSyncSettings } from '../../common/models/AiraSyncModels';

export type SyncBookmarkActivationProvider = 'aira_cloud' | 'huawei_space';
export type SyncActivationProvider = 'webdav' | SyncBookmarkActivationProvider;
export type SyncActivationResultType =
  | 'saved'
  | 'logged-out'
  | 'failed';

export interface SyncActivationWebdavSaveParams {
  endpoint: string;
  username: string;
  password: string;
}

export interface SyncActivationResult {
  type: SyncActivationResultType;
  provider: SyncActivationProvider;
  title: string;
  message: string;
  username: string;
  settings: AiraSyncSettings | null;
  errorCode: string;
}
