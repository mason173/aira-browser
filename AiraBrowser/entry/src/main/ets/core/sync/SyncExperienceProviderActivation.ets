import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { AiraSyncSettings } from '../../common/models/AiraSyncModels';
import { SyncService } from '../../services/sync/SyncService';
import {
  AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
} from '../../services/sync/AiraSyncConfigStore';
import { HuaweiAccountSyncAuthService } from '../../services/sync/HuaweiAccountSyncAuthService';
import { AiraAccountUnionLinkFunctionService } from '../../services/account/AiraAccountUnionLinkFunctionService';
import { HuaweiCloudSyncErrorMessageService } from '../../services/sync/HuaweiCloudSyncErrorMessageService';
import { HuaweiCloudSyncInitService } from '../../services/sync/HuaweiCloudSyncInitService';
import {
  HuaweiAccountOperationError,
  HuaweiAccountOperationStage
} from '../../services/sync/HuaweiAccountOperationError';
import {
  SyncActivationProvider,
  SyncActivationResult,
  SyncActivationResultType,
  SyncActivationWebdavSaveParams
} from './SyncActivationModels';

export type SyncExperienceHuaweiIdentityChangeHandler = (uid: string) => Promise<void>;

const SYNC_PROVIDER_ACTIVATION_DOMAIN: number = 0x0000;
const SYNC_PROVIDER_ACTIVATION_TAG: string = 'SyncProviderActivation';

export class SyncExperienceProviderActivation {
  private syncService: SyncService;
  private huaweiAuthService: HuaweiAccountSyncAuthService = new HuaweiAccountSyncAuthService();
  private huaweiCloudSyncInitService: HuaweiCloudSyncInitService = new HuaweiCloudSyncInitService();
  private huaweiCloudErrorMessageService: HuaweiCloudSyncErrorMessageService =
    new HuaweiCloudSyncErrorMessageService();
  private accountUnionLinkService: AiraAccountUnionLinkFunctionService = new AiraAccountUnionLinkFunctionService();
  private huaweiIdentityChangeHandler?: SyncExperienceHuaweiIdentityChangeHandler;

  constructor(syncService: SyncService, huaweiIdentityChangeHandler?: SyncExperienceHuaweiIdentityChangeHandler) {
    this.syncService = syncService;
    this.huaweiIdentityChangeHandler = huaweiIdentityChangeHandler;
  }

  async saveWebdavConfig(params: SyncActivationWebdavSaveParams): Promise<SyncActivationResult> {
    try {
      await this.syncService.initializeAiraSyncSettings();
      if (params.endpoint.trim().length <= 0) {
        return this.failed('webdav', '信息不完整', '请填写 WebDAV 地址。', 'invalid-config');
      }
      if (params.username.trim().length <= 0 || params.password.length <= 0) {
        return this.failed('webdav', '信息不完整', '请填写 WebDAV 用户名和密码。', 'invalid-config');
      }
      const settings = await this.syncService.saveAiraWebdavConfig(
        params.endpoint,
        params.username,
        params.password
      );
      return this.baseResult('saved', 'webdav', '配置已保存', 'WebDAV 配置已保存。', settings);
    } catch (error) {
      return this.failed('webdav', '保存失败', this.stringifyError(error as Error), 'save-failed');
    }
  }

  async signInHuaweiAccountOnly(): Promise<SyncActivationResult> {
    let stage: HuaweiAccountOperationStage = 'settings-initialize';
    try {
      await this.syncService.initializeAiraSyncSettings();
      stage = 'auth-initialize';
      await this.ensureHuaweiAuthInitialized();
      stage = 'agc-sign-in';
      const identity = await this.huaweiAuthService.signInForBookmarkSync(true);
      stage = 'settings-save';
      const settings = await this.syncService.saveHuaweiCloudConfig(
        identity.uid,
        identity.displayName,
        identity.photoUrl
      );
      stage = 'identity-change';
      await this.handleHuaweiIdentityChanged(identity.uid);
      this.linkUnionIdBestEffort(identity.uid);
      return this.baseResult(
        'saved',
        'aira_cloud',
        '华为账号已登录',
        '当前已成为 Aira Club。需要时可再开启书签同步或升级 Pro。',
        settings
      );
    } catch (error) {
      hilog.warn(
        SYNC_PROVIDER_ACTIVATION_DOMAIN,
        SYNC_PROVIDER_ACTIVATION_TAG,
        'huawei account sign-in failed error=%{public}s',
        HuaweiAccountOperationError.from(stage, error as Object).technicalMessage()
      );
      return this.failed('aira_cloud', '登录失败',
        this.huaweiCloudErrorMessageService.formatForAccountOperation(error as Object, stage), 'huawei-auth-failed');
    }
  }

  async signInHuaweiSpaceAccountOnly(): Promise<SyncActivationResult> {
    let stage: HuaweiAccountOperationStage = 'settings-initialize';
    try {
      await this.syncService.initializeAiraSyncSettings();
      stage = 'auth-initialize';
      await this.ensureHuaweiAuthInitialized();
      stage = 'agc-sign-in';
      const identity = await this.huaweiAuthService.signInForBookmarkSync(true);
      stage = 'huawei-space-capability';
      await this.syncService.checkHuaweiSpaceCapability(
        identity.uid,
        AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
      );
      stage = 'settings-save';
      const settings = await this.syncService.saveHuaweiSpaceConfig(
        identity.uid,
        identity.displayName,
        identity.photoUrl,
        AIRA_HUAWEI_SPACE_BOOKMARK_DATABASE_NAME
      );
      stage = 'identity-change';
      await this.handleHuaweiIdentityChanged(identity.uid);
      return this.baseResult(
        'saved',
        'huawei_space',
        '华为云空间可用',
        '已登录华为账号并通过本机云空间同步能力检查。请选择同步方式后再开启。',
        settings
      );
    } catch (error) {
      hilog.warn(
        SYNC_PROVIDER_ACTIVATION_DOMAIN,
        SYNC_PROVIDER_ACTIVATION_TAG,
        'huawei space readiness failed error=%{public}s',
        HuaweiAccountOperationError.from(stage, error as Object).technicalMessage()
      );
      return this.failed('huawei_space', '华为云空间暂不可用',
        this.huaweiCloudErrorMessageService.formatForAccountOperation(error as Object, stage), 'huawei-space-readiness-failed');
    }
  }

  async refreshHuaweiAccountIdentity(): Promise<SyncActivationResult> {
    try {
      await this.syncService.initializeAiraSyncSettings();
      await this.ensureHuaweiAuthInitialized();
      const identity = await this.huaweiAuthService.refreshCurrentIdentityProfile();
      if (identity === undefined) {
        return this.failed('aira_cloud', '未登录华为账号', '请先使用华为账号登录。', 'not-signed-in');
      }
      const settings = await this.syncService.saveHuaweiCloudConfig(
        identity.uid,
        identity.displayName,
        identity.photoUrl
      );
      await this.handleHuaweiIdentityChanged(identity.uid);
      return this.baseResult(
        'saved',
        'aira_cloud',
        '华为账号信息已更新',
        '已刷新头像和昵称。',
        settings
      );
    } catch (error) {
      hilog.warn(
        SYNC_PROVIDER_ACTIVATION_DOMAIN,
        SYNC_PROVIDER_ACTIVATION_TAG,
        'huawei account identity refresh failed error=%{public}s',
        JSON.stringify(error)
      );
      return this.failed('aira_cloud', '账号信息刷新失败', this.stringifyError(error as Error), 'huawei-auth-failed');
    }
  }

  async clearHuaweiAccountIdentity(): Promise<void> {
    await this.syncService.initializeAiraSyncSettings();
    await this.syncService.clearHuaweiIdentity();
    await this.handleHuaweiIdentityChanged('');
  }

  private baseResult(
    type: SyncActivationResultType,
    provider: SyncActivationProvider,
    title: string,
    message: string,
    settings: AiraSyncSettings | null
  ): SyncActivationResult {
    return {
      type: type,
      provider: provider,
      title: title,
      message: message,
      username: '',
      settings: settings,
      errorCode: ''
    };
  }

  private failed(provider: SyncActivationProvider, title: string, message: string, errorCode: string): SyncActivationResult {
    const result = this.baseResult('failed', provider, title, message, null);
    result.errorCode = errorCode;
    return result;
  }

  private async handleHuaweiIdentityChanged(uid: string): Promise<void> {
    if (this.huaweiIdentityChangeHandler === undefined) {
      return;
    }
    await this.huaweiIdentityChangeHandler(uid);
  }

  /**
   * Records the account's Huawei UnionID on the backend so a sibling App can be
   * recognized as the same person. Best-effort and non-blocking: a failure only
   * delays the cross-App link to the next sign-in and never affects login.
   */
  private linkUnionIdBestEffort(uid: string): void {
    this.accountUnionLinkService.linkUnionId(uid)
      .then((_linked: boolean): void => {
      })
      .catch((_error: Object): void => {
      });
  }

  private async ensureHuaweiAuthInitialized(): Promise<void> {
    await this.huaweiCloudSyncInitService.initializeAuth(
      AppRuntimeContext.getUIAbilityContext()
    );
  }

  private stringifyError(error: Error): string {
    return this.huaweiCloudErrorMessageService.formatForDialog(error);
  }
}
