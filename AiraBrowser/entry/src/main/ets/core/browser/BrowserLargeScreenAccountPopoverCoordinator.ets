import { resolveAiraHuaweiAccountIdentity } from '../../common/models/AiraSyncModels';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { ActivityRepository } from '../../data/activity/ActivityRepository';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS } from '../../services/membership/MembershipRefreshPolicyService';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import {
  HuaweiAccountInfoViewModel,
  HuaweiAccountInfoViewState
} from '../settings/HuaweiAccountInfoViewModel';
import { HuaweiAccountMutationCoordinator } from '../account/HuaweiAccountMutationCoordinator';

const HUAWEI_LOGIN_CANCEL_ERROR_CODE: number = 1001502012;
const HUAWEI_PROFILE_REFRESH_COOLDOWN_MS: number = 6 * 60 * 60 * 1000;

export interface BrowserLargeScreenAccountLoginCredential {
  errorCode: number;
  errorMessage: string;
  authorizationCode: string;
  openId: string;
}

export interface BrowserLargeScreenAccountPopoverSnapshot {
  signedIn: boolean;
  profile: HuaweiAccountInfoViewState;
  busy: boolean;
  revision: number;
}

export interface BrowserLargeScreenAccountPopoverHost {
  publishSnapshot(snapshot: BrowserLargeScreenAccountPopoverSnapshot): void;
  showMessage(message: string): void;
  copyText(text: string): Promise<void>;
  closeSurface(): void;
  notifyAccountChanged(): void;
}

export class BrowserLargeScreenAccountPopoverCoordinator {
  private syncConfigStore: AiraSyncConfigStore;
  private membershipFeature: MembershipFeature;
  private activityRepository: ActivityRepository;
  private accountMutationCoordinator: HuaweiAccountMutationCoordinator;
  private host: BrowserLargeScreenAccountPopoverHost;
  private viewModel: HuaweiAccountInfoViewModel;
  private busy: boolean = false;
  private revision: number = 0;
  private refreshSequence: number = 0;
  private lastProfileRefreshAttemptAt: number = 0;

  constructor(
    syncConfigStore: AiraSyncConfigStore,
    membershipFeature: MembershipFeature,
    activityRepository: ActivityRepository,
    accountMutationCoordinator: HuaweiAccountMutationCoordinator,
    host: BrowserLargeScreenAccountPopoverHost,
    viewModel: HuaweiAccountInfoViewModel = new HuaweiAccountInfoViewModel()
  ) {
    this.syncConfigStore = syncConfigStore;
    this.membershipFeature = membershipFeature;
    this.activityRepository = activityRepository;
    this.accountMutationCoordinator = accountMutationCoordinator;
    this.host = host;
    this.viewModel = viewModel;
  }

  getSnapshot(): BrowserLargeScreenAccountPopoverSnapshot {
    const settings = this.syncConfigStore.getSettings();
    const identity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    const activityState = this.activityRepository.getState();
    return {
      signedIn: identity.uid.length > 0,
      profile: this.viewModel.buildState(
        settings,
        this.membershipFeature.getState(),
        activityState.accountUid === identity.uid ? activityState.totals : []
      ),
      busy: this.busy,
      revision: this.revision
    };
  }

  refresh(boundaryInput: BrowserDataBoundaryInput): void {
    const requestId = ++this.refreshSequence;
    this.publishSnapshot();
    void this.refreshLoadedState(requestId, boundaryInput);
  }

  canSignIn(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.accountMutationCoordinator.canSignIn(boundaryInput);
  }

  canSignOut(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.accountMutationCoordinator.canSignOut(boundaryInput);
  }

  handleLoginCredential(
    credential: BrowserLargeScreenAccountLoginCredential,
    boundaryInput: BrowserDataBoundaryInput
  ): void {
    if (credential.errorCode !== 0) {
      if (credential.errorCode !== HUAWEI_LOGIN_CANCEL_ERROR_CODE) {
        this.host.showMessage(
          credential.errorMessage.trim().length > 0 ? credential.errorMessage : '华为账号登录失败'
        );
      }
      return;
    }
    if (credential.authorizationCode.trim().length <= 0 && credential.openId.trim().length <= 0) {
      this.host.showMessage('华为账号登录未完成');
      return;
    }
    void this.signInHuaweiAccount(boundaryInput);
  }

  requestCopyAccountId(): void {
    const settings = this.syncConfigStore.getSettings();
    const uid = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
    if (uid.length <= 0) {
      this.host.showMessage('当前没有可复制的账号 ID');
      return;
    }
    this.host.copyText(uid)
      .then(() => {
        this.host.showMessage('账号 ID 已复制');
      })
      .catch((_error: Error) => {
        this.host.showMessage('复制失败，请稍后重试');
      });
  }

  signOutHuaweiAccount(boundaryInput: BrowserDataBoundaryInput): void {
    if (this.busy || !this.getSnapshot().signedIn) {
      return;
    }
    this.setBusy(true);
    this.accountMutationCoordinator.signOut(boundaryInput)
      .then((result) => {
        if (!result.ok) {
          this.host.showMessage(result.message.length > 0 ? result.message : result.title);
          return;
        }
        this.host.notifyAccountChanged();
        this.host.showMessage(result.title);
        this.host.closeSurface();
      })
      .catch((error: Error) => {
        this.host.showMessage(error.message.length > 0 ? error.message : '退出失败');
      })
      .finally(() => {
        this.setBusy(false);
      });
  }

  private async signInHuaweiAccount(boundaryInput: BrowserDataBoundaryInput): Promise<void> {
    if (this.busy) {
      return;
    }
    this.setBusy(true);
    try {
      const result = await this.accountMutationCoordinator.signIn(boundaryInput);
      if (result.type === 'failed') {
        this.host.showMessage(result.message.length > 0 ? result.message : result.title);
        return;
      }
      this.host.notifyAccountChanged();
      try {
        await this.refreshAccountDependentState(boundaryInput);
      } catch (_refreshError) {
      }
      this.host.showMessage(result.title);
    } catch (_error) {
      this.host.showMessage('华为账号登录失败');
    } finally {
      this.setBusy(false);
    }
  }

  private async refreshLoadedState(
    requestId: number,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<void> {
    try {
      await this.syncConfigStore.initialize();
      await this.activityRepository.initialize();
      if (requestId !== this.refreshSequence) {
        return;
      }
      await this.refreshAccountDependentState(boundaryInput);
    } catch (_error) {
    } finally {
      if (requestId === this.refreshSequence) {
        this.publishSnapshot();
      }
    }
  }

  private async refreshAccountDependentState(boundaryInput: BrowserDataBoundaryInput): Promise<void> {
    if (!this.isSignedIn()) {
      return;
    }
    if (this.shouldRefreshHuaweiProfile() &&
      this.accountMutationCoordinator.canRefreshIdentityProfile(boundaryInput)) {
      this.lastProfileRefreshAttemptAt = Date.now();
      await this.accountMutationCoordinator.refreshIdentityProfile(boundaryInput);
    }
    await this.accountMutationCoordinator.refreshAiraAccountProfile(boundaryInput);
    await this.membershipFeature.refreshStateForBoundary(boundaryInput, {
      minFreshMs: MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS
    });
    this.publishSnapshot();
  }

  private isSignedIn(): boolean {
    const settings = this.syncConfigStore.getSettings();
    return resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid.length > 0;
  }

  private shouldRefreshHuaweiProfile(): boolean {
    if (this.lastProfileRefreshAttemptAt > 0 &&
      Date.now() - this.lastProfileRefreshAttemptAt < HUAWEI_PROFILE_REFRESH_COOLDOWN_MS) {
      return false;
    }
    const settings = this.syncConfigStore.getSettings();
    const identity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    if (identity.uid.length <= 0) {
      return false;
    }
    if (identity.photoUrl.length <= 0 || identity.displayName.length <= 0 || identity.displayName === '华为账号') {
      return true;
    }
    const suffix = identity.uid.length > 6 ? identity.uid.slice(identity.uid.length - 6) : identity.uid;
    return identity.displayName === `华为账号 ${suffix}`;
  }

  private setBusy(busy: boolean): void {
    this.busy = busy;
    this.publishSnapshot();
  }

  private publishSnapshot(): void {
    this.revision += 1;
    this.host.publishSnapshot(this.getSnapshot());
  }
}
