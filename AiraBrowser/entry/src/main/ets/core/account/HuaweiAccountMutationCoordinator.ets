import auth from '@hw-agconnect/auth';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { AccountIdentityChangeCoordinator } from './AccountIdentityChangeCoordinator';
import { SyncActivationResult } from '../sync/SyncActivationModels';
import { SyncExperienceCoordinator } from '../sync/SyncExperienceCoordinator';
import { sharedCrossDeviceTabPresenceCoordinator } from '../deviceTabs/CrossDeviceTabPresenceCoordinator';

export interface HuaweiAccountSignOutResult {
  ok: boolean;
  title: string;
  message: string;
}

export class HuaweiAccountMutationCoordinator {
  private syncExperienceCoordinator: SyncExperienceCoordinator;
  private accountIdentityChangeCoordinator: AccountIdentityChangeCoordinator;
  private membershipFeature: MembershipFeature;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;

  constructor(
    syncExperienceCoordinator: SyncExperienceCoordinator,
    accountIdentityChangeCoordinator: AccountIdentityChangeCoordinator,
    membershipFeature: MembershipFeature,
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService()
  ) {
    this.syncExperienceCoordinator = syncExperienceCoordinator;
    this.accountIdentityChangeCoordinator = accountIdentityChangeCoordinator;
    this.membershipFeature = membershipFeature;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
  }

  canSignIn(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.isEffectAllowed('huawei_account_login', boundaryInput);
  }

  canSignOut(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.isEffectAllowed('huawei_account_sign_out', boundaryInput);
  }

  canRefreshIdentityProfile(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.isEffectAllowed('huawei_account_identity_reconcile', boundaryInput);
  }

  canRefreshAiraAccountProfile(boundaryInput: BrowserDataBoundaryInput): boolean {
    return this.isEffectAllowed('membership_account_profile_reconcile', boundaryInput);
  }

  async reconcileIdentity(uid: string, boundaryInput: BrowserDataBoundaryInput): Promise<void> {
    if (!this.isEffectAllowed('huawei_account_identity_reconcile', boundaryInput)) {
      return;
    }
    await this.accountIdentityChangeCoordinator.handleHuaweiIdentityChanged(uid);
    await this.refreshAiraAccountProfile(boundaryInput);
  }

  async signIn(boundaryInput: BrowserDataBoundaryInput): Promise<SyncActivationResult> {
    if (!this.canSignIn(boundaryInput)) {
      return {
        type: 'failed',
        provider: 'aira_cloud',
        title: '私密会话不修改账号状态',
        message: '请回到普通会话后登录华为账号。',
        username: '',
        settings: null,
        errorCode: 'private-account-login-blocked'
      };
    }
    const result = await this.syncExperienceCoordinator.signInHuaweiAccount();
    if (result.type !== 'failed') {
      await this.refreshAiraAccountProfile(boundaryInput);
    }
    return result;
  }

  async refreshIdentityProfile(boundaryInput: BrowserDataBoundaryInput): Promise<SyncActivationResult> {
    if (!this.canRefreshIdentityProfile(boundaryInput)) {
      return {
        type: 'failed',
        provider: 'aira_cloud',
        title: '私密会话不修改账号状态',
        message: '请回到普通会话后刷新华为账号资料。',
        username: '',
        settings: null,
        errorCode: 'private-account-identity-refresh-blocked'
      };
    }
    return this.syncExperienceCoordinator.refreshHuaweiAccountIdentity();
  }

  async refreshAiraAccountProfile(boundaryInput: BrowserDataBoundaryInput): Promise<void> {
    if (!this.canRefreshAiraAccountProfile(boundaryInput)) {
      return;
    }
    await this.membershipFeature.refreshAccountProfileForBoundary(boundaryInput);
  }

  async signOut(boundaryInput: BrowserDataBoundaryInput): Promise<HuaweiAccountSignOutResult> {
    if (!this.canSignOut(boundaryInput)) {
      return {
        ok: false,
        title: '私密会话不修改账号状态',
        message: '请回到普通会话后退出华为账号。'
      };
    }
    await sharedCrossDeviceTabPresenceCoordinator.clearCurrentAccountSnapshot()
      .catch((_error: Error): void => {
      });
    await this.syncExperienceCoordinator.clearHuaweiAccountIdentity();
    await auth.signOut().catch((_error: Error) => Promise.resolve());
    return {
      ok: true,
      title: '已退出华为账号',
      message: ''
    };
  }

  private isEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    boundaryInput: BrowserDataBoundaryInput
  ): boolean {
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: this.profileBoundaryService.buildBoundary(boundaryInput),
      targetScope: 'remote_account_sync_state',
      targetIsClear: true
    }).outcome === 'allow';
  }
}
