import { AiraCloudBookmarkV4BootstrapRecord } from '../../common/models/AiraCloudBookmarkV4BootstrapModels';

export type AiraCloudBookmarkV4BootstrapViewStatus = 'required' | 'running' | 'failed' | 'hidden';
export type AiraCloudBookmarkV4BootstrapViewAction = 'start' | 'retry' | 'none';

export interface AiraCloudBookmarkV4BootstrapViewState {
  visible: boolean;
  status: AiraCloudBookmarkV4BootstrapViewStatus;
  primaryAction: AiraCloudBookmarkV4BootstrapViewAction;
  recoveryAvailable: boolean;
  uid: string;
  errorMessage: string;
}

export class AiraCloudBookmarkV4BootstrapViewModelService {
  required(uid: string): AiraCloudBookmarkV4BootstrapViewState {
    return {
      visible: true,
      status: 'required',
      primaryAction: 'start',
      recoveryAvailable: false,
      uid: uid,
      errorMessage: ''
    };
  }

  fromRecord(record: AiraCloudBookmarkV4BootstrapRecord): AiraCloudBookmarkV4BootstrapViewState {
    if (record.status === 'completed' || record.status === 'opted_out') {
      return {
        visible: false,
        status: 'hidden',
        primaryAction: 'none',
        recoveryAvailable: false,
        uid: record.uid,
        errorMessage: ''
      };
    }
    if (record.status === 'failed') {
      return {
        visible: true,
        status: 'failed',
        primaryAction: 'retry',
        recoveryAvailable: record.backupId.length > 0 && record.backupSha256.length > 0,
        uid: record.uid,
        errorMessage: record.errorMessage
      };
    }
    return {
      visible: true,
      status: 'running',
      primaryAction: 'none',
      recoveryAvailable: false,
      uid: record.uid,
      errorMessage: ''
    };
  }
}
