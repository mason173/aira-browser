import { hilog } from '@kit.PerformanceAnalysisKit';
import { SyncSettingsRefreshSignal } from '../sync/SyncSettingsRefreshSignal';
import { ActivityRepository } from '../../data/activity/ActivityRepository';
import { MembershipFeature } from '../../features/membership/MembershipFeature';

const DOMAIN = 0x0000;
const TAG = 'AccountIdentityChange';

export interface AccountIdentityChangeOptions {
  refreshMembership?: boolean;
  bumpSettingsSignal?: boolean;
  syncPersonalization?: boolean;
}

export type AccountActivityFlushHandler = () => Promise<void>;
export type AccountPersonalizationSyncHandler = () => Promise<void>;
export type AccountIdentityReconcileHandler = (uid: string) => Promise<void>;

export class AccountIdentityChangeCoordinator {
  private membershipFeature: MembershipFeature;
  private activityRepository: ActivityRepository;
  private syncSettingsRefreshSignal: SyncSettingsRefreshSignal;
  private activityFlushHandler?: AccountActivityFlushHandler;
  private personalizationSyncHandler?: AccountPersonalizationSyncHandler;
  private identityReconcileHandler?: AccountIdentityReconcileHandler;
  private changePromise?: Promise<void>;
  private changePromiseUid: string = '';

  constructor(
    membershipFeature: MembershipFeature,
    activityRepository: ActivityRepository,
    syncSettingsRefreshSignal: SyncSettingsRefreshSignal = new SyncSettingsRefreshSignal(),
    activityFlushHandler?: AccountActivityFlushHandler,
    personalizationSyncHandler?: AccountPersonalizationSyncHandler,
    identityReconcileHandler?: AccountIdentityReconcileHandler
  ) {
    this.membershipFeature = membershipFeature;
    this.activityRepository = activityRepository;
    this.syncSettingsRefreshSignal = syncSettingsRefreshSignal;
    this.activityFlushHandler = activityFlushHandler;
    this.personalizationSyncHandler = personalizationSyncHandler;
    this.identityReconcileHandler = identityReconcileHandler;
  }

  handleHuaweiIdentityChanged(uid: string, options: AccountIdentityChangeOptions = {}): Promise<void> {
    const normalizedUid = uid.trim();
    this.membershipFeature.activateAccountScope(normalizedUid);
    if (this.changePromise !== undefined && this.changePromiseUid === normalizedUid) {
      return this.changePromise;
    }
    const promise = this.applyHuaweiIdentityChange(normalizedUid, this.normalizeOptions(options))
      .catch((error: Error) => {
        hilog.warn(
          DOMAIN,
          TAG,
          'identity change reconcile failed uidSuffix=%{public}s error=%{public}s',
          this.maskUid(normalizedUid),
          JSON.stringify(error)
        );
      })
      .finally(() => {
        if (this.changePromise === promise) {
          this.changePromise = undefined;
          this.changePromiseUid = '';
        }
      });
    this.changePromise = promise;
    this.changePromiseUid = normalizedUid;
    return this.changePromise;
  }

  private async applyHuaweiIdentityChange(
    uid: string,
    options: Required<AccountIdentityChangeOptions>
  ): Promise<void> {
    if (uid.length <= 0) {
      await this.activityRepository.ensureAccountScope('');
      await this.membershipFeature.clearAccountBoundState();
      await this.reconcileIdentityDomains(uid);
      this.bumpSettingsSignalIfNeeded(options);
      return;
    }
    await this.flushActivityIfNeeded(options);
    await this.activityRepository.ensureAccountScope(uid);
    if (options.refreshMembership) {
      await this.membershipFeature.refreshState({ force: true });
    }
    await this.reconcileIdentityDomains(uid);
    this.syncPersonalizationIfNeeded(uid, options);
    this.bumpSettingsSignalIfNeeded(options);
  }

  private normalizeOptions(options: AccountIdentityChangeOptions): Required<AccountIdentityChangeOptions> {
    return {
      refreshMembership: options.refreshMembership !== false,
      bumpSettingsSignal: options.bumpSettingsSignal !== false,
      syncPersonalization: options.syncPersonalization === true
    };
  }

  private bumpSettingsSignalIfNeeded(options: Required<AccountIdentityChangeOptions>): void {
    if (!options.bumpSettingsSignal) {
      return;
    }
    this.syncSettingsRefreshSignal.bump();
  }

  private async flushActivityIfNeeded(options: Required<AccountIdentityChangeOptions>): Promise<void> {
    if (this.activityFlushHandler === undefined) {
      return;
    }
    await this.activityFlushHandler();
  }

  private syncPersonalizationIfNeeded(uid: string, options: Required<AccountIdentityChangeOptions>): void {
    if (!options.syncPersonalization || this.personalizationSyncHandler === undefined) {
      return;
    }
    if (this.membershipFeature.getState().plan !== 'pro') {
      return;
    }
    this.personalizationSyncHandler()
      .then(() => {
        this.bumpSettingsSignalIfNeeded(options);
        hilog.info(
          DOMAIN,
          TAG,
          'personalization sync after identity change completed uidSuffix=%{public}s',
          this.maskUid(uid)
        );
      })
      .catch((error: Error) => {
        hilog.warn(
          DOMAIN,
          TAG,
          'personalization sync after identity change skipped uidSuffix=%{public}s error=%{public}s',
          this.maskUid(uid),
          JSON.stringify(error)
        );
      });
  }

  private async reconcileIdentityDomains(uid: string): Promise<void> {
    if (this.identityReconcileHandler === undefined) {
      return;
    }
    await this.identityReconcileHandler(uid);
  }

  private maskUid(uid: string): string {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 6) {
      return normalizedUid;
    }
    return normalizedUid.slice(normalizedUid.length - 6);
  }
}
