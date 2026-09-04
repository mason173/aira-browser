import { common } from '@kit.AbilityKit';
import auth from '@hw-agconnect/auth';
import agconnect from '@hw-agconnect/api-ohos';
import '@hw-agconnect/core-ohos';
import buffer from '@ohos.buffer';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

export interface HuaweiCloudSyncInitAdapter {
  initializeAuth(context: common.Context): Promise<void>;
}

class AgcHuaweiCloudSyncInitAdapter implements HuaweiCloudSyncInitAdapter {
  initializeAuth(context: common.Context): Promise<void> {
    const rawFile = context.resourceManager.getRawFileContentSync('agconnect-services.json');
    const json = buffer.from(rawFile.buffer).toString('utf8');
    auth.init(context, json);
    agconnect.instance().init(context, JSON.parse(json));
    return Promise.resolve();
  }
}

export class HuaweiCloudSyncInitService {
  private adapter: HuaweiCloudSyncInitAdapter;
  private authInitialized: boolean = false;
  private authInitializationTask?: Promise<void>;

  constructor(adapter?: HuaweiCloudSyncInitAdapter) {
    this.adapter = adapter ?? new AgcHuaweiCloudSyncInitAdapter();
  }

  async initializeAuth(context: common.Context): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_space')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_space'));
    }
    if (this.authInitialized) {
      return;
    }
    if (this.authInitializationTask === undefined) {
      this.authInitializationTask = this.adapter.initializeAuth(context)
        .then((): void => {
          this.authInitialized = true;
        })
        .catch((error: Error): Promise<void> => {
          this.authInitializationTask = undefined;
          return Promise.reject(error);
        });
    }
    await this.authInitializationTask;
  }
}
