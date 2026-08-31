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
    await this.adapter.initializeAuth(context);
    this.authInitialized = true;
  }
}
