import { AiraFeatureKey } from '../../common/constants/MembershipFeatureKeys';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import {
  AiraAccountRecognition,
  AiraFeatureQuota,
  AiraLapsedProStateRecord,
  AiraLapsedProView,
  AiraMembershipEntitlementClaims,
  AiraMembershipState,
  AiraNewUserGiftStateRecord,
  AiraNewUserGiftView,
  AiraSubscriptionStatus,
  EntitlementDecision,
  MembershipRepositorySnapshot,
  buildEmptyLapsedProView,
  buildEmptyNewUserGiftView
} from '../../common/models/MembershipModels';
import {
  MembershipRepository,
  MembershipRepositoryCommitGuard,
  MembershipRepositoryStateUpdater
} from '../../data/membership/MembershipRepository';
import {
  EntitlementContext,
  EntitlementService
} from '../../services/membership/EntitlementService';
import { MembershipEntitlementProofService } from '../../services/membership/MembershipEntitlementProofService';
import {
  AiraAccountProfileResponseRecord,
  AiraMembershipGrantResponseRecord,
  AiraMembershipStateFunctionService,
  AiraMembershipStateResponseBody
} from '../../services/membership/AiraMembershipStateFunctionService';
import { MembershipQuotaService } from '../../services/membership/MembershipQuotaService';
import { AiraNewUserGiftFunctionService } from '../../services/membership/AiraNewUserGiftFunctionService';
import {
  AiraComplimentaryClaimFunctionService,
  AiraComplimentaryClaimResponseBody
} from '../../services/membership/AiraComplimentaryClaimFunctionService';
import {
  AiraMembershipRedeemFunctionService,
  AiraMembershipRedeemResponseBody
} from '../../services/membership/AiraMembershipRedeemFunctionService';
import {
  MEMBERSHIP_REFRESH_DEFAULT_FRESH_MS,
  MEMBERSHIP_REFRESH_RETRY_COOLDOWN_MS
} from '../../services/membership/MembershipRefreshPolicyService';
import {
  MembershipAccountPresence,
  MembershipEntitlementRetentionPolicy
} from '../../services/membership/MembershipEntitlementRetentionPolicy';
import { isAiraProLifetimeProductId } from '../../services/membership/HuaweiIapProductCatalog';
import { resolveAiraHuaweiAccountIdentity } from '../../common/models/AiraSyncModels';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import {
  BrowserPrivacyEffectIntent,
  BrowserPrivacyEffectPolicyService,
  BrowserPrivacyEffectTargetScope
} from '../../services/privacy/BrowserPrivacyEffectPolicyService';

const MEMBERSHIP_FEATURE_LOG_DOMAIN: number = 0x0000;
const MEMBERSHIP_FEATURE_LOG_TAG: string = 'MembershipFeature';
export type MembershipStateChangeHandler = (state: AiraMembershipState) => void | Promise<void>;

export interface MembershipStateRefreshOptions {
  force?: boolean;
  minFreshMs?: number;
  loadSyncConfig?: boolean;
}

interface NormalizedMembershipStateRefreshOptions {
  force: boolean;
  minFreshMs: number;
  loadSyncConfig: boolean;
}

interface MembershipAccountScope {
  uid: string;
  generation: number;
}

export interface AiraNewUserGiftEnsureResult {
  ok: boolean;
  code: string;
  message: string;
  state?: AiraMembershipState;
}

export interface AiraComplimentaryClaimResult {
  ok: boolean;
  code: string;
  message: string;
  state?: AiraMembershipState;
}

export interface AiraMembershipRedeemResult {
  ok: boolean;
  code: string;
  message: string;
  kind: string;
  state?: AiraMembershipState;
}

export interface AiraAppSuiteState {
  owned: boolean;
  checked: boolean;
  revision: number;
}

export class MembershipFeature {
  private repository: MembershipRepository;
  private entitlementService: EntitlementService;
  private quotaService: MembershipQuotaService;
  private membershipStateFunctionService: AiraMembershipStateFunctionService;
  private membershipEntitlementProofService: MembershipEntitlementProofService;
  private privacyEffectPolicy: BrowserPrivacyEffectPolicyService;
  private profileBoundaryService: BrowserProfileBoundaryService;
  private newUserGiftService: AiraNewUserGiftFunctionService;
  private complimentaryClaimService: AiraComplimentaryClaimFunctionService;
  private membershipRedeemService: AiraMembershipRedeemFunctionService;
  private retentionPolicy: MembershipEntitlementRetentionPolicy;
  private syncConfigStore?: AiraSyncConfigStore;
  private stateChangeHandler?: MembershipStateChangeHandler;
  private newUserGift: AiraNewUserGiftView = buildEmptyNewUserGiftView();
  private lapsedPro: AiraLapsedProView = buildEmptyLapsedProView();
  private remoteStateRefreshPromise?: Promise<AiraMembershipState>;
  private remoteStateRefreshUid: string = '';
  private remoteStateRefreshAttemptedAt: number = 0;
  private remoteStateRefreshAttemptUid: string = '';
  private suiteUid: string = '';
  private suiteOwned: boolean = false;
  private suiteRevision: number = 0;
  private accountScopeUid: string = '';
  private accountScopeGeneration: number = 0;
  private entitlementRequestGeneration: number = 0;
  private accountProfileRequestGeneration: number = 0;

  constructor(
    repository: MembershipRepository,
    entitlementService: EntitlementService = new EntitlementService(),
    quotaService: MembershipQuotaService = new MembershipQuotaService(),
    membershipStateFunctionService: AiraMembershipStateFunctionService = new AiraMembershipStateFunctionService(),
    syncConfigStore?: AiraSyncConfigStore,
    membershipEntitlementProofService: MembershipEntitlementProofService = new MembershipEntitlementProofService(),
    privacyEffectPolicy: BrowserPrivacyEffectPolicyService = new BrowserPrivacyEffectPolicyService(),
    profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService(),
    newUserGiftService: AiraNewUserGiftFunctionService = new AiraNewUserGiftFunctionService(),
    complimentaryClaimService: AiraComplimentaryClaimFunctionService = new AiraComplimentaryClaimFunctionService(),
    retentionPolicy: MembershipEntitlementRetentionPolicy = new MembershipEntitlementRetentionPolicy(),
    membershipRedeemService: AiraMembershipRedeemFunctionService = new AiraMembershipRedeemFunctionService()
  ) {
    this.repository = repository;
    this.entitlementService = entitlementService;
    this.quotaService = quotaService;
    this.membershipStateFunctionService = membershipStateFunctionService;
    this.membershipEntitlementProofService = membershipEntitlementProofService;
    this.privacyEffectPolicy = privacyEffectPolicy;
    this.profileBoundaryService = profileBoundaryService;
    this.syncConfigStore = syncConfigStore;
    this.newUserGiftService = newUserGiftService;
    this.complimentaryClaimService = complimentaryClaimService;
    this.retentionPolicy = retentionPolicy;
    this.membershipRedeemService = membershipRedeemService;
  }

  setStateChangeHandler(handler: MembershipStateChangeHandler): void {
    this.stateChangeHandler = handler;
  }

  activateAccountScope(uid: string): void {
    const normalizedUid = uid.trim();
    if (normalizedUid === this.accountScopeUid) {
      return;
    }
    this.suiteUid = '';
    this.suiteOwned = false;
    this.suiteRevision += 1;
    this.accountScopeUid = normalizedUid;
    this.accountScopeGeneration += 1;
    this.invalidateEntitlementRequests();
    this.accountProfileRequestGeneration += 1;
    if (this.newUserGift.uid !== normalizedUid) {
      this.newUserGift = buildEmptyNewUserGiftView();
    }
    if (this.lapsedPro.uid !== normalizedUid) {
      this.lapsedPro = buildEmptyLapsedProView();
    }
  }

  getAppSuiteState(): AiraAppSuiteState {
    const checked = this.suiteUid.length > 0 && this.suiteUid === this.getHuaweiUid();
    return { owned: checked && this.suiteOwned, checked, revision: this.suiteRevision };
  }

  /** A payment confirmation remains bound to this exact account session, including A→B→A changes. */
  capturePurchaseSessionGuard(uid: string): () => boolean {
    if (uid.trim().length === 0 || uid.trim() !== this.getHuaweiUid()) { return (): boolean => false; }
    const accountScope = this.captureAccountScope(uid.trim());
    return (): boolean => this.isCurrentAccountScope(accountScope);
  }

  getState(): AiraMembershipState {
    return this.resolveEffectiveState(this.repository.getState());
  }

  getQuotaSnapshot(): AiraFeatureQuota[] {
    return this.repository.getQuotaSnapshot();
  }

  /**
   * New-user gift facts as last reported by the hosted service, scoped to the
   * currently resolved account. A different or absent account reads as
   * ineligible so a stale descriptor can never target the wrong uid.
   */
  getNewUserGiftState(): AiraNewUserGiftView {
    if (!this.syncConfigStore?.isInitialized()) {
      return buildEmptyNewUserGiftView();
    }
    const uid = this.getHuaweiUid();
    if (uid.length <= 0 || this.newUserGift.uid !== uid) {
      return buildEmptyNewUserGiftView();
    }
    return {
      uid: this.newUserGift.uid,
      eligible: this.newUserGift.eligible,
      grantedAt: this.newUserGift.grantedAt,
      grantDays: this.newUserGift.grantDays,
      fetchedAt: this.newUserGift.fetchedAt
    };
  }

  /**
   * The account's most recent ended Pro period, as last reported by the hosted
   * service. A lapsed subscription deletes the membership grant, so this is the
   * only signal that separates "used to have Pro" from "never had Pro"; it is
   * reported only while the current plan is not Pro.
   */
  getLapsedProState(): AiraLapsedProView {
    if (!this.syncConfigStore?.isInitialized()) {
      return buildEmptyLapsedProView();
    }
    const uid = this.getHuaweiUid();
    if (uid.length <= 0 || this.lapsedPro.uid !== uid) {
      return buildEmptyLapsedProView();
    }
    return {
      uid: this.lapsedPro.uid,
      expiredAt: this.lapsedPro.expiredAt,
      source: this.lapsedPro.source,
      productId: this.lapsedPro.productId,
      fetchedAt: this.lapsedPro.fetchedAt
    };
  }

  /**
   * Ensures the welcome gift exists for the resolved account. The hosted
   * service grants automatically for an eligible new account, so this is an
   * idempotent ensure rather than a user-triggered award: the presentation
   * never decides whether the user receives the month of Pro.
   */
  async ensureNewUserGift(boundaryInput: BrowserDataBoundaryInput): Promise<AiraNewUserGiftEnsureResult> {
    if (!this.isEffectAllowed('membership_gift_grant', boundaryInput, 'remote_account_sync_state')) {
      return {
        ok: false,
        code: 'private_session_blocked',
        message: resolveAppResourceText($r('app.string.membership_gift_private_session'))
      };
    }
    await this.repository.initialize();
    await this.initializeSyncConfigIfAvailable();
    const uid = this.getHuaweiUid();
    if (uid.length <= 0) {
      return {
        ok: false,
        code: 'login_required',
        message: resolveAppResourceText($r('app.string.membership_login_required'))
      };
    }
    const accountScope = this.captureAccountScope(uid);
    const response = await this.newUserGiftService.ensureNewUserGift(uid);
    if (response.ok !== true) {
      hilog.warn(
        MEMBERSHIP_FEATURE_LOG_DOMAIN,
        MEMBERSHIP_FEATURE_LOG_TAG,
        'new user gift ensure rejected uidSuffix=%{public}s code=%{public}s',
        this.maskUid(uid),
        response.code ?? ''
      );
      return {
        ok: false,
        code: response.code?.trim() ?? 'gift_ensure_failed',
        message: response.message?.trim() ?? resolveAppResourceText($r('app.string.membership_gift_sync_failed'))
      };
    }
    if (!this.isCurrentAccountScope(accountScope)) {
      return {
        ok: false,
        code: 'account_changed',
        message: resolveAppResourceText($r('app.string.membership_account_changed'))
      };
    }
    const committedSnapshot = await this.repository.updateSnapshotIf(
      (): boolean => this.isCurrentAccountScope(accountScope),
      (snapshot: MembershipRepositorySnapshot): MembershipRepositorySnapshot => {
        const accountState = this.buildStateForUid(snapshot.state, uid);
        const nextState = this.buildStateFromGrant(accountState, response.membershipGrant ?? undefined);
        const syncedAt = Date.now();
        nextState.lastSyncedAt = syncedAt;
        nextState.updatedAt = syncedAt;
        return {
          state: nextState,
          quotas: snapshot.quotas
        };
      }
    );
    if (committedSnapshot === undefined || !this.isCurrentAccountScope(accountScope)) {
      return {
        ok: false,
        code: 'account_changed',
        message: resolveAppResourceText($r('app.string.membership_account_changed'))
      };
    }
    // The grant is already committed server-side, so the authoritative
    // descriptor is recorded even if the echoed grant is not Pro; otherwise a
    // consumed one-time grant would be reported as missing on every later read.
    // A response that omits the descriptor still means the grant was applied,
    // so the known eligibility is kept rather than cleared.
    this.captureGrantedNewUserGiftState(
      uid,
      response.newUserGift ?? undefined,
      committedSnapshot.state.plan === 'pro'
    );
    if (committedSnapshot.state.plan !== 'pro') {
      return {
        ok: false,
        code: 'grant_not_applied',
        message: resolveAppResourceText($r('app.string.membership_gift_not_applied'))
      };
    }
    this.notifyStateChanged(committedSnapshot.state);
    return {
      ok: true,
      code: 'gift_granted',
      message: resolveAppResourceText($r('app.string.membership_gift_granted')),
      state: committedSnapshot.state
    };
  }

  /**
   * Claims the user-triggered 15-day Pro period. The hosted service is the
   * authority: a current permanent or subscription member is refused, an
   * unexpired claim cannot be repeated, and an expired claim can be taken
   * again. This never invents a local grant.
   */
  async claimComplimentaryMembership(
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<AiraComplimentaryClaimResult> {
    if (!this.isEffectAllowed('membership_complimentary_claim', boundaryInput, 'remote_account_sync_state')) {
      return {
        ok: false,
        code: 'private_session_blocked',
        message: resolveAppResourceText($r('app.string.membership_claim_private_session'))
      };
    }
    await this.repository.initialize();
    await this.initializeSyncConfigIfAvailable();
    const uid = this.getHuaweiUid();
    if (uid.length <= 0) {
      return {
        ok: false,
        code: 'login_required',
        message: resolveAppResourceText($r('app.string.membership_login_required'))
      };
    }
    const accountScope = this.captureAccountScope(uid);
    const response = await this.complimentaryClaimService.claim(uid);
    if (!this.isCurrentAccountScope(accountScope)) {
      return {
        ok: false,
        code: 'account_changed',
        message: resolveAppResourceText($r('app.string.membership_account_changed'))
      };
    }
    if (response.ok !== true) {
      await this.commitComplimentaryClaimGrant(accountScope, response);
      return {
        ok: false,
        code: response.code?.trim() ?? 'complimentary_claim_failed',
        message: response.message?.trim() ?? resolveAppResourceText($r('app.string.settings_pro_claim_failed'))
      };
    }
    const committedSnapshot = await this.commitComplimentaryClaimGrant(accountScope, response);
    if (!this.isCurrentAccountScope(accountScope)) {
      return {
        ok: false,
        code: 'account_changed',
        message: resolveAppResourceText($r('app.string.membership_account_changed'))
      };
    }
    if (committedSnapshot === undefined) {
      return {
        ok: false,
        code: 'grant_not_applied',
        message: resolveAppResourceText($r('app.string.membership_claim_not_applied'))
      };
    }
    if (committedSnapshot.state.plan !== 'pro') {
      return {
        ok: false,
        code: 'grant_not_applied',
        message: resolveAppResourceText($r('app.string.membership_claim_not_applied'))
      };
    }
    this.notifyStateChanged(committedSnapshot.state);
    return {
      ok: true,
      code: 'complimentary_claim_granted',
      message: response.message?.trim() ?? resolveAppResourceText($r('app.string.membership_claim_granted')),
      state: committedSnapshot.state
    };
  }

  /**
   * Redeems one membership code. The hosted service is the authority: it
   * checks the code, decides whether to consume it, and returns the grant.
   * This never invents a local grant.
   */
  async redeemMembershipCode(
    code: string,
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<AiraMembershipRedeemResult> {
    if (!this.isEffectAllowed('membership_redeem', boundaryInput, 'remote_account_sync_state')) {
      return {
        ok: false,
        code: 'private_session_blocked',
        message: resolveAppResourceText($r('app.string.membership_redeem_private_session')),
        kind: ''
      };
    }
    const normalizedCode = code.trim();
    if (normalizedCode.length <= 0) {
      return {
        ok: false,
        code: 'invalid_format',
        message: resolveAppResourceText($r('app.string.settings_pro_redeem_invalid')),
        kind: ''
      };
    }
    await this.repository.initialize();
    await this.initializeSyncConfigIfAvailable();
    const uid = this.getHuaweiUid();
    if (uid.length <= 0) {
      return {
        ok: false,
        code: 'login_required',
        message: resolveAppResourceText($r('app.string.membership_login_required')),
        kind: ''
      };
    }
    const accountScope = this.captureAccountScope(uid);
    const response = await this.membershipRedeemService.redeem(uid, normalizedCode);
    if (!this.isCurrentAccountScope(accountScope)) {
      return {
        ok: false,
        code: 'account_changed',
        message: resolveAppResourceText($r('app.string.membership_account_changed')),
        kind: ''
      };
    }
    const kind = response.kind?.trim() ?? '';
    if (response.ok !== true) {
      await this.commitComplimentaryClaimGrant(accountScope, response);
      return {
        ok: false,
        code: response.code?.trim() ?? 'membership_redeem_failed',
        message: response.message?.trim() ?? resolveAppResourceText($r('app.string.settings_pro_redeem_failed')),
        kind: ''
      };
    }
    const committedSnapshot = await this.commitComplimentaryClaimGrant(accountScope, response);
    if (!this.isCurrentAccountScope(accountScope)) {
      return {
        ok: false,
        code: 'account_changed',
        message: resolveAppResourceText($r('app.string.membership_account_changed')),
        kind: ''
      };
    }
    if (committedSnapshot === undefined || committedSnapshot.state.plan !== 'pro') {
      return {
        ok: false,
        code: 'grant_not_applied',
        message: resolveAppResourceText($r('app.string.membership_redeem_not_applied')),
        kind: ''
      };
    }
    this.notifyStateChanged(committedSnapshot.state);
    return {
      ok: true,
      code: 'membership_redeemed',
      message: response.message?.trim() ?? resolveAppResourceText($r('app.string.membership_redeem_granted')),
      kind: kind,
      state: committedSnapshot.state
    };
  }

  private async commitComplimentaryClaimGrant(
    accountScope: MembershipAccountScope,
    response: AiraComplimentaryClaimResponseBody | AiraMembershipRedeemResponseBody
  ): Promise<MembershipRepositorySnapshot | undefined> {
    const grant = response.membershipGrant ?? undefined;
    if (grant === undefined) {
      return undefined;
    }
    const committedSnapshot = await this.repository.updateSnapshotIf(
      (): boolean => this.isCurrentAccountScope(accountScope),
      (snapshot: MembershipRepositorySnapshot): MembershipRepositorySnapshot => {
        const accountState = this.buildStateForUid(snapshot.state, accountScope.uid);
        const nextState = this.buildStateFromGrant(accountState, grant);
        const syncedAt = Date.now();
        nextState.lastSyncedAt = syncedAt;
        nextState.updatedAt = syncedAt;
        return {
          state: nextState,
          quotas: snapshot.quotas
        };
      }
    );
    if (committedSnapshot !== undefined) {
      this.notifyStateChanged(committedSnapshot.state);
    }
    return committedSnapshot;
  }

  async loadState(): Promise<AiraMembershipState> {
    await this.initializeSyncConfigIfAvailable();
    await this.repository.initialize();
    return this.resolveEffectiveState(await this.repository.loadState());
  }

  async refreshState(options: MembershipStateRefreshOptions = {}): Promise<AiraMembershipState> {
    return this.refreshStateInternal(options);
  }

  private async refreshStateInternal(options: MembershipStateRefreshOptions): Promise<AiraMembershipState> {
    await this.repository.initialize();
    const currentState = this.repository.getState();
    const refreshOptions = this.normalizeRefreshOptions(options);
    if (this.syncConfigStore === undefined) {
      const state = this.resolveLocalPlanExpiration(currentState);
      return await this.commitUnconfirmedState(
        currentState,
        state,
        (): boolean => true,
        (latestState: AiraMembershipState): AiraMembershipState => this.resolveLocalPlanExpiration(latestState)
      );
    }
    if (refreshOptions.loadSyncConfig) {
      await this.initializeSyncConfigIfAvailable();
    } else if (!this.syncConfigStore.isInitialized()) {
      const state = this.resolveLocalPlanExpiration(currentState);
      return await this.commitUnconfirmedState(
        currentState,
        state,
        (): boolean => true,
        (latestState: AiraMembershipState): AiraMembershipState => this.resolveLocalPlanExpiration(latestState)
      );
    }
    const uid = this.getHuaweiUid();
    const accountScope = this.captureAccountScope(uid);
    if (uid.length <= 0) {
      // Sign-out clears the stored grant itself. A refresh that cannot see an
      // account must not overwrite the last confirmed Pro.
      return this.getState();
    }
    const initialAccountState = currentState.userId === uid
      ? currentState
      : this.buildStateForUid(currentState, uid);
    const accountState = this.restoreVerifiedEntitlement(initialAccountState, uid);
    const shouldVerifyExpiredPro = this.isStoredProExpired(accountState);
    const resolvedState = this.resolveLocalPlanExpiration(accountState);
    const state = await this.commitUnconfirmedState(
      currentState,
      resolvedState,
      (): boolean => this.isCurrentAccountScope(accountScope),
      (latestState: AiraMembershipState): AiraMembershipState => {
        const latestAccountState = this.buildStateForUid(latestState, uid);
        return this.resolveLocalPlanExpiration(this.restoreVerifiedEntitlement(latestAccountState, uid));
      }
    );
    if (!refreshOptions.force && !shouldVerifyExpiredPro && this.isRemoteStateFresh(state, refreshOptions.minFreshMs)) {
      return state;
    }
    if (this.remoteStateRefreshPromise !== undefined) {
      if (this.remoteStateRefreshUid === uid) {
        return this.remoteStateRefreshPromise;
      }
      return state;
    }
    const now = Date.now();
    if (!refreshOptions.force && this.isRemoteRetryCoolingDown(uid, now)) {
      return state;
    }
    this.remoteStateRefreshAttemptedAt = now;
    this.remoteStateRefreshAttemptUid = uid;
    this.remoteStateRefreshUid = uid;
    const entitlementRequestGeneration = this.beginEntitlementRequest();
    const refreshPromise = this.fetchRemoteState(uid, accountScope, entitlementRequestGeneration)
      .finally(() => {
        if (this.remoteStateRefreshPromise === refreshPromise) {
          this.remoteStateRefreshPromise = undefined;
          this.remoteStateRefreshUid = '';
        }
      });
    this.remoteStateRefreshPromise = refreshPromise;
    return this.remoteStateRefreshPromise;
  }

  async refreshStateForBoundary(
    boundaryInput: BrowserDataBoundaryInput,
    options: MembershipStateRefreshOptions = {}
  ): Promise<AiraMembershipState> {
    if (!this.isEffectAllowed('membership_entitlement_read', boundaryInput, 'private_session_state')) {
      return this.getState();
    }
    return this.refreshStateInternal({
      force: options.force,
      minFreshMs: options.minFreshMs,
      loadSyncConfig: options.loadSyncConfig
    });
  }

  async refreshAccountProfileForBoundary(
    boundaryInput: BrowserDataBoundaryInput
  ): Promise<AiraMembershipState> {
    if (!this.isEffectAllowed(
      'membership_account_profile_reconcile',
      boundaryInput,
      'remote_account_sync_state'
    )) {
      return this.getState();
    }
    await this.repository.initialize();
    await this.initializeSyncConfigIfAvailable();
    const uid = this.getHuaweiUid();
    if (uid.length <= 0) {
      return this.getState();
    }
    const accountScope = this.captureAccountScope(uid);
    const accountProfileRequestGeneration = this.beginAccountProfileRequest();
    try {
      const remote = await this.membershipStateFunctionService.fetchAccountProfile(uid);
      if (remote.ok !== true) {
        throw this.buildMembershipStateFunctionError(remote);
      }
      const accountProfile = remote.accountProfile ?? undefined;
      if (accountProfile === undefined || !this.isAuthoritativeAccountProfile(accountProfile, uid)) {
        throw new Error('invalid_account_profile: ' +
          resolveAppResourceText($r('app.string.membership_account_profile_invalid')));
      }
      if (!this.isCurrentAccountProfileRequest(accountScope, accountProfileRequestGeneration)) {
        return this.getState();
      }
      const committedState = await this.repository.updateStateIf(
        (): boolean => this.isCurrentAccountProfileRequest(accountScope, accountProfileRequestGeneration),
        (latestState: AiraMembershipState): AiraMembershipState => {
          return this.buildStateWithAccountProfile(this.buildStateForUid(latestState, uid), accountProfile);
        }
      );
      if (committedState === undefined ||
        !this.isCurrentAccountProfileRequest(accountScope, accountProfileRequestGeneration)) {
        return this.getState();
      }
      this.notifyStateChanged(committedState);
      return committedState;
    } catch (error) {
      hilog.warn(
        MEMBERSHIP_FEATURE_LOG_DOMAIN,
        MEMBERSHIP_FEATURE_LOG_TAG,
        'account profile reconcile failed uidSuffix=%{public}s error=%{public}s',
        this.maskUid(uid),
        this.stringifyError(error as Error)
      );
      return this.getState();
    }
  }

  private async fetchRemoteState(
    uid: string,
    accountScope: MembershipAccountScope,
    entitlementRequestGeneration: number
  ): Promise<AiraMembershipState> {
    try {
      const remoteState = await this.membershipStateFunctionService.fetchEntitlementState(uid);
      if (remoteState.ok !== true) {
        throw this.buildMembershipStateFunctionError(remoteState);
      }
      if (!this.isAuthoritativeMembershipGrant(remoteState.membershipGrant ?? undefined, uid)) {
        throw new Error('invalid_membership_grant: ' +
          resolveAppResourceText($r('app.string.membership_grant_invalid')));
      }
      if (!this.isCurrentEntitlementRequest(accountScope, entitlementRequestGeneration)) {
        return this.getState();
      }
      const committedSnapshot = await this.persistAuthoritativeRemoteState(
        uid,
        remoteState,
        accountScope,
        entitlementRequestGeneration
      );
      if (committedSnapshot === undefined ||
        !this.isCurrentEntitlementRequest(accountScope, entitlementRequestGeneration)) {
        return this.getState();
      }
      if (typeof remoteState.appSuite?.owned === 'boolean') {
        this.suiteUid = uid;
        this.suiteOwned = remoteState.appSuite.owned === true;
        this.suiteRevision += 1;
      }
      this.captureNewUserGiftState(uid, remoteState.newUserGift ?? undefined, Date.now());
      this.captureLapsedProState(uid, remoteState.lapsedPro ?? undefined, Date.now());
      hilog.info(
        MEMBERSHIP_FEATURE_LOG_DOMAIN,
        MEMBERSHIP_FEATURE_LOG_TAG,
        'membership state query uidSuffix=%{public}s found=%{public}d plan=%{public}s',
        this.maskUid(uid),
        remoteState.membershipGrant === undefined || remoteState.membershipGrant === null ? 0 : 1,
        remoteState.membershipGrant?.plan ?? ''
      );
      this.notifyStateChanged(committedSnapshot.state);
      return committedSnapshot.state;
    } catch (error) {
      hilog.error(
        MEMBERSHIP_FEATURE_LOG_DOMAIN,
        MEMBERSHIP_FEATURE_LOG_TAG,
        'membership state query failed uidSuffix=%{public}s error=%{public}s',
        this.maskUid(uid),
        this.stringifyError(error)
      );
      if (!this.isCurrentEntitlementRequest(accountScope, entitlementRequestGeneration)) {
        return this.getState();
      }
      this.notifyStateChanged(this.repository.getState());
      return this.getState();
    }
  }

  private async persistAuthoritativeRemoteState(
    uid: string,
    remoteState: AiraMembershipStateResponseBody,
    accountScope: MembershipAccountScope,
    entitlementRequestGeneration: number
  ): Promise<MembershipRepositorySnapshot | undefined> {
    const updater = (snapshot: MembershipRepositorySnapshot): MembershipRepositorySnapshot => {
      return this.buildAuthoritativeRemoteSnapshot(snapshot, uid, remoteState);
    };
    const verificationState = updater(this.repository.getSnapshot()).state;
    if (verificationState.plan !== 'pro') {
      return await this.repository.updateSnapshotAndClearEntitlementProofIf(
        (): boolean => this.isCurrentEntitlementRequest(accountScope, entitlementRequestGeneration),
        uid,
        updater
      );
    }
    const proof = remoteState.entitlementProof?.trim() ?? '';
    if (proof.length > 0) {
      const verification = this.membershipEntitlementProofService.verify(proof, uid);
      if (verification.valid === true && verification.claims !== undefined &&
        this.entitlementProofMatchesState(verification.claims, verificationState)) {
        return await this.repository.updateSnapshotAndSaveEntitlementProofIf(
          (): boolean => this.isCurrentEntitlementRequest(accountScope, entitlementRequestGeneration),
          uid,
          proof,
          updater
        );
      }
      hilog.warn(
        MEMBERSHIP_FEATURE_LOG_DOMAIN,
        MEMBERSHIP_FEATURE_LOG_TAG,
        'membership entitlement proof rejected uidSuffix=%{public}s reason=%{public}s',
        this.maskUid(uid),
        verification.reason
      );
    }
    return await this.repository.updateSnapshotIf(
      (): boolean => this.isCurrentEntitlementRequest(accountScope, entitlementRequestGeneration),
      updater
    );
  }

  private buildAuthoritativeRemoteSnapshot(
    snapshot: MembershipRepositorySnapshot,
    uid: string,
    remoteState: AiraMembershipStateResponseBody
  ): MembershipRepositorySnapshot {
    const accountState = this.buildStateForUid(snapshot.state, uid);
    const grantState = this.buildStateFromGrant(accountState, remoteState.membershipGrant ?? undefined);
    const nextState = this.buildStateWithRecognitions(grantState, remoteState.recognitions);
    const syncedAt = Date.now();
    nextState.lastSyncedAt = syncedAt;
    nextState.updatedAt = syncedAt;
    return {
      state: nextState,
      quotas: snapshot.quotas
    };
  }

  private isAuthoritativeMembershipGrant(
    grant: AiraMembershipGrantResponseRecord | undefined,
    uid: string
  ): boolean {
    const plan = grant?.plan?.trim().toLowerCase() ?? '';
    return grant !== undefined && grant.uid?.trim() === uid && (plan === 'club' || plan === 'pro');
  }

  private isAuthoritativeAccountProfile(profile: AiraAccountProfileResponseRecord, uid: string): boolean {
    const firstSeenAt = Math.max(0, Math.floor(profile.firstSeenAt ?? 0));
    const lastSeenAt = Math.max(0, Math.floor(profile.lastSeenAt ?? 0));
    return profile.uid?.trim() === uid && firstSeenAt > 0 && lastSeenAt >= firstSeenAt;
  }

  private entitlementProofMatchesState(
    claims: AiraMembershipEntitlementClaims,
    state: AiraMembershipState
  ): boolean {
    return claims.sub === state.userId &&
      claims.plan === state.plan &&
      claims.accountRecognition === state.accountRecognition &&
      claims.productId === state.subscriptionProductId &&
      claims.subscriptionStatus === state.subscriptionStatus &&
      claims.grantExpiresAt === state.planExpiresAt;
  }

  async canUse(featureKey: AiraFeatureKey, context: EntitlementContext): Promise<EntitlementDecision> {
    if (!this.hasResolvedEntitlementBoundary(context) || !this.isEffectAllowed(
      'membership_entitlement_read',
      context,
      'private_session_state'
    )) {
      return {
        featureKey: featureKey,
        allowed: false,
        reason: 'unsupported_context',
        title: resolveAppResourceText($r('app.string.membership_entitlement_private_title')),
        message: resolveAppResourceText($r('app.string.membership_entitlement_private_message')),
        primaryAction: 'none'
      };
    }
    await this.initializeSyncConfigIfAvailable();
    const uid = this.getHuaweiUid();
    const effectiveState = this.resolveEffectiveState(this.repository.getState());
    const effectiveContext: EntitlementContext = {
      dataScope: context.dataScope,
      privacyMode: context.privacyMode,
      loggedIn: this.syncConfigStore === undefined ? context.loggedIn : uid.length > 0,
      currentUsage: context.currentUsage
    };
    return this.entitlementService.canUse(
      featureKey,
      effectiveState,
      this.repository.getQuotaSnapshot(),
      effectiveContext,
      this.getLapsedProState()
    );
  }

  async recordUsage(featureKey: AiraFeatureKey, amount: number = 1): Promise<void> {
    await this.repository.updateQuotaSnapshot((latestQuotas: AiraFeatureQuota[]): AiraFeatureQuota[] => {
      return this.quotaService.recordUsage(latestQuotas, featureKey, amount);
    });
  }

  async enableDevProOverride(): Promise<void> {
    await this.refreshState({ force: true });
  }

  async clearDevOverride(): Promise<void> {
    await this.repository.clearState();
    this.notifyStateChanged(this.repository.getState());
  }

  async clearAccountBoundState(): Promise<void> {
    const accountScope = this.captureAccountScope('');
    const committedSnapshot = await this.repository.updateSnapshotIf(
      (): boolean => this.isCurrentAccountScope(accountScope),
      (snapshot: MembershipRepositorySnapshot): MembershipRepositorySnapshot => {
        return {
          state: this.buildLoggedOutState(snapshot.state),
          quotas: snapshot.quotas
        };
      }
    );
    if (committedSnapshot === undefined || !this.isCurrentAccountScope(accountScope)) {
      return;
    }
    this.notifyStateChanged(committedSnapshot.state);
  }

  async applyVerifiedIapGrant(productId: string, expiresAt: number): Promise<AiraMembershipState> {
    await this.initializeSyncConfigIfAvailable();
    const uid = this.getHuaweiUid();
    if (uid.length <= 0 || (expiresAt > 0 && expiresAt <= Date.now())) {
      return this.getState();
    }
    const accountScope = this.captureAccountScope(uid);
    this.invalidateEntitlementRequests();
    const committedSnapshot = await this.repository.updateSnapshotIf(
      (): boolean => this.isCurrentAccountScope(accountScope),
      (snapshot: MembershipRepositorySnapshot): MembershipRepositorySnapshot => {
        const currentState = this.buildStateForUid(snapshot.state, uid);
        return {
          state: this.buildProStateFromVerifiedIap(currentState, productId, expiresAt),
          quotas: snapshot.quotas
        };
      }
    );
    if (committedSnapshot === undefined || !this.isCurrentAccountScope(accountScope)) {
      return this.getState();
    }
    this.notifyStateChanged(committedSnapshot.state);
    return committedSnapshot.state;
  }

  private isEffectAllowed(
    intent: BrowserPrivacyEffectIntent,
    context: BrowserDataBoundaryInput | EntitlementContext,
    targetScope: BrowserPrivacyEffectTargetScope
  ): boolean {
    const requestingBoundary = this.profileBoundaryService.buildBoundary({
      dataScope: context.dataScope,
      privacyMode: context.privacyMode
    });
    return this.privacyEffectPolicy.decide({
      intent: intent,
      requestingBoundary: requestingBoundary,
      targetScope: targetScope,
      targetIsClear: true
    }).outcome === 'allow';
  }

  private hasResolvedEntitlementBoundary(context: EntitlementContext): boolean {
    return (context.dataScope === 'profile_persistent' || context.dataScope === 'session_ephemeral') &&
      (context.privacyMode === 'regular' || context.privacyMode === 'private');
  }

  private normalizeRefreshOptions(options: MembershipStateRefreshOptions): NormalizedMembershipStateRefreshOptions {
    const minFreshMs = typeof options.minFreshMs === 'number' && Number.isFinite(options.minFreshMs)
      ? Math.max(0, Math.floor(options.minFreshMs))
      : MEMBERSHIP_REFRESH_DEFAULT_FRESH_MS;
    return {
      force: options.force === true,
      minFreshMs: minFreshMs,
      loadSyncConfig: options.loadSyncConfig !== false
    };
  }

  private isRemoteStateFresh(state: AiraMembershipState, minFreshMs: number): boolean {
    if (state.userId !== this.getHuaweiUid()) {
      return false;
    }
    const lastSyncedAt = state.lastSyncedAt ?? 0;
    return lastSyncedAt > 0 && Date.now() - lastSyncedAt < minFreshMs;
  }

  private isRemoteRetryCoolingDown(uid: string, now: number): boolean {
    return this.remoteStateRefreshAttemptUid === uid &&
      this.remoteStateRefreshAttemptedAt > 0 &&
      now - this.remoteStateRefreshAttemptedAt < MEMBERSHIP_REFRESH_RETRY_COOLDOWN_MS;
  }

  private buildMembershipStateFunctionError(result: AiraMembershipStateResponseBody): Error {
    const code = result.code?.trim() ?? 'membership_state_failed';
    const message = result.message?.trim() ??
      resolveAppResourceText($r('app.string.membership_state_refresh_failed'));
    return new Error(`${code}: ${message}`);
  }

  private getHuaweiUid(): string {
    const settings = this.syncConfigStore?.getSettings();
    if (settings === undefined) {
      return '';
    }
    const resolvedUid = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid;
    const presence: MembershipAccountPresence = {
      cloudUid: settings.huaweiCloud.uid.trim(),
      spaceUid: settings.huaweiSpace.uid.trim(),
      resolvedUid: resolvedUid
    };
    return this.retentionPolicy.retainQueryUid(this.repository.getState(), presence, Date.now());
  }

  /**
   * Writes a local resolution only when it does not take Pro away. The
   * membership endpoint is the only path that may do that, after it succeeds.
   */
  private async commitUnconfirmedState(
    currentState: AiraMembershipState,
    nextState: AiraMembershipState,
    guard: MembershipRepositoryCommitGuard,
    updater: MembershipRepositoryStateUpdater
  ): Promise<AiraMembershipState> {
    if (!this.shouldPersistEffectiveState(currentState, nextState) ||
      !this.retentionPolicy.allowsUnconfirmedPersist(currentState, nextState)) {
      return nextState.plan === 'pro' ? nextState : this.resolveEffectiveState(currentState);
    }
    const committedState = await this.repository.updateStateIf(guard, updater);
    if (committedState === undefined) {
      return this.getState();
    }
    this.notifyStateChanged(committedState);
    return committedState;
  }

  private captureAccountScope(uid: string): MembershipAccountScope {
    this.activateAccountScope(uid);
    return {
      uid: this.accountScopeUid,
      generation: this.accountScopeGeneration
    };
  }

  private isCurrentAccountScope(accountScope: MembershipAccountScope): boolean {
    return accountScope.uid === this.getHuaweiUid() &&
      accountScope.uid === this.accountScopeUid &&
      accountScope.generation === this.accountScopeGeneration;
  }

  private beginEntitlementRequest(): number {
    this.entitlementRequestGeneration += 1;
    return this.entitlementRequestGeneration;
  }

  private isCurrentEntitlementRequest(
    accountScope: MembershipAccountScope,
    requestGeneration: number
  ): boolean {
    return this.isCurrentAccountScope(accountScope) &&
      requestGeneration === this.entitlementRequestGeneration;
  }

  private invalidateEntitlementRequests(): void {
    this.entitlementRequestGeneration += 1;
    this.remoteStateRefreshPromise = undefined;
    this.remoteStateRefreshUid = '';
    this.remoteStateRefreshAttemptedAt = 0;
    this.remoteStateRefreshAttemptUid = '';
  }

  private beginAccountProfileRequest(): number {
    this.accountProfileRequestGeneration += 1;
    return this.accountProfileRequestGeneration;
  }

  private isCurrentAccountProfileRequest(
    accountScope: MembershipAccountScope,
    requestGeneration: number
  ): boolean {
    return this.isCurrentAccountScope(accountScope) &&
      requestGeneration === this.accountProfileRequestGeneration;
  }

  private async initializeSyncConfigIfAvailable(): Promise<void> {
    if (this.syncConfigStore === undefined) {
      return;
    }
    await this.syncConfigStore.initialize();
  }

  private notifyStateChanged(state: AiraMembershipState): void {
    if (this.stateChangeHandler === undefined) {
      return;
    }
    Promise.resolve(this.stateChangeHandler(state)).catch((error: Error) => {
      hilog.warn(
        MEMBERSHIP_FEATURE_LOG_DOMAIN,
        MEMBERSHIP_FEATURE_LOG_TAG,
        'membership state change handler failed: %{public}s',
        this.stringifyError(error)
      );
    });
  }

  private buildStateForUid(previous: AiraMembershipState, uid: string): AiraMembershipState {
    if (previous.userId === uid) {
      return previous;
    }
    return this.buildDefaultClubStateForUid(previous, uid);
  }

  private restoreVerifiedEntitlement(
    previous: AiraMembershipState,
    uid: string
  ): AiraMembershipState {
    if (previous.userId === uid && previous.plan === 'pro' &&
      (previous.planExpiresAt === 0 || previous.planExpiresAt > Date.now())) {
      return previous;
    }
    const proof = this.repository.getEntitlementProof(uid);
    if (proof.length <= 0) {
      return previous;
    }
    const verification = this.membershipEntitlementProofService.verify(proof, uid);
    if (verification.valid !== true || verification.claims === undefined) {
      return previous;
    }
    return this.buildStateFromEntitlementClaims(previous, verification.claims);
  }

  private buildStateFromEntitlementClaims(
    previous: AiraMembershipState,
    claims: AiraMembershipEntitlementClaims
  ): AiraMembershipState {
    return {
      userId: claims.sub,
      plan: 'pro',
      accountRecognition: claims.accountRecognition,
      accessFlags: ['club'],
      subscriptionStatus: claims.subscriptionStatus,
      subscriptionProductId: claims.productId,
      planExpiresAt: claims.grantExpiresAt,
      accountFirstSeenAt: previous.accountFirstSeenAt,
      accountLastSeenAt: previous.accountLastSeenAt,
      lastSyncedAt: previous.lastSyncedAt,
      updatedAt: Date.now()
    };
  }

  private buildDefaultClubStateForUid(previous: AiraMembershipState, uid: string): AiraMembershipState {
    return {
      userId: uid,
      plan: 'club',
      accountRecognition: 'none',
      accessFlags: ['club'],
      subscriptionStatus: 'none',
      subscriptionProductId: '',
      planExpiresAt: 0,
      accountFirstSeenAt: 0,
      accountLastSeenAt: 0,
      lastSyncedAt: 0,
      updatedAt: Date.now()
    };
  }

  private resolveEffectiveState(state: AiraMembershipState): AiraMembershipState {
    if (this.syncConfigStore === undefined) {
      return this.resolveLocalPlanExpiration(state);
    }
    if (!this.syncConfigStore.isInitialized()) {
      return this.resolveLocalPlanExpiration(state);
    }
    const uid = this.getHuaweiUid();
    if (uid.length <= 0) {
      return this.buildLoggedOutState(state);
    }
    if (state.userId !== uid) {
      return this.resolveLocalPlanExpiration(
        this.restoreVerifiedEntitlement(this.buildStateForUid(state, uid), uid)
      );
    }
    return this.resolveLocalPlanExpiration(state);
  }

  private resolveLocalPlanExpiration(state: AiraMembershipState): AiraMembershipState {
    const restoredState = state.userId === 'local'
      ? state
      : this.restoreVerifiedEntitlement(state, state.userId);
    if (restoredState !== state) {
      return restoredState;
    }
    if (!this.isStoredProExpired(restoredState)) {
      return restoredState;
    }
    return this.buildLocallyExpiredProClubState(restoredState);
  }

  private isStoredProExpired(state: AiraMembershipState): boolean {
    return state.plan === 'pro' && state.planExpiresAt > 0 && state.planExpiresAt <= Date.now();
  }

  private buildLocallyExpiredProClubState(previous: AiraMembershipState): AiraMembershipState {
    const wasIapSubscription = previous.subscriptionStatus === 'active' ||
      previous.subscriptionStatus === 'grace_period' ||
      previous.subscriptionProductId.trim().length > 0;
    return {
      userId: previous.userId,
      plan: 'club',
      accountRecognition: previous.accountRecognition,
      accessFlags: ['club'],
      subscriptionStatus: wasIapSubscription ? 'expired' : 'none',
      subscriptionProductId: wasIapSubscription ? previous.subscriptionProductId : '',
      planExpiresAt: previous.planExpiresAt,
      accountFirstSeenAt: previous.accountFirstSeenAt,
      accountLastSeenAt: previous.accountLastSeenAt,
      lastSyncedAt: previous.lastSyncedAt,
      updatedAt: Date.now()
    };
  }

  private buildLoggedOutState(previous: AiraMembershipState): AiraMembershipState {
    return {
      userId: 'local',
      plan: 'guest',
      accountRecognition: 'none',
      accessFlags: [],
      subscriptionStatus: 'none',
      subscriptionProductId: '',
      planExpiresAt: 0,
      accountFirstSeenAt: 0,
      accountLastSeenAt: 0,
      lastSyncedAt: 0,
      updatedAt: Date.now()
    };
  }

  private shouldPersistEffectiveState(previous: AiraMembershipState, next: AiraMembershipState): boolean {
    return previous.userId !== next.userId ||
      previous.plan !== next.plan ||
      previous.accountRecognition !== next.accountRecognition ||
      previous.subscriptionStatus !== next.subscriptionStatus ||
      previous.subscriptionProductId !== next.subscriptionProductId ||
      previous.planExpiresAt !== next.planExpiresAt ||
      previous.accountFirstSeenAt !== next.accountFirstSeenAt ||
      previous.accountLastSeenAt !== next.accountLastSeenAt ||
      previous.accessFlags.join('|') !== next.accessFlags.join('|');
  }

  private buildStateFromGrant(
    previous: AiraMembershipState,
    grant: AiraMembershipGrantResponseRecord | undefined
  ): AiraMembershipState {
    const uid = grant?.uid?.trim() ?? '';
    if (grant === undefined || uid.length <= 0) {
      return this.buildDefaultClubStateForUid(previous, previous.userId);
    }
    const plan = grant.plan?.trim().toLowerCase() ?? '';
    const source = grant.source?.trim().toLowerCase() ?? '';
    const productId = grant.productId?.trim() ?? '';
    const expiresAt = grant.expiresAt ?? 0;
    const subscriptionStatus = this.resolveRemoteSubscriptionStatus(grant, source, productId);
    if (plan === 'pro') {
      if (!this.isGrantActive(grant)) {
        return this.buildExpiredProClubState(previous, grant);
      }
      return {
        userId: previous.userId,
        plan: 'pro',
        accountRecognition: previous.accountRecognition,
        accessFlags: ['club'],
        subscriptionStatus: subscriptionStatus,
        subscriptionProductId: productId.length > 0
          ? productId
          : (subscriptionStatus !== 'none' ? previous.subscriptionProductId : ''),
        planExpiresAt: expiresAt,
        accountFirstSeenAt: previous.accountFirstSeenAt,
        accountLastSeenAt: previous.accountLastSeenAt,
        lastSyncedAt: previous.lastSyncedAt,
        updatedAt: Date.now()
      };
    }
    if (plan === 'club') {
      return {
        userId: previous.userId,
        plan: 'club',
        accountRecognition: previous.accountRecognition,
        accessFlags: ['club'],
        subscriptionStatus: 'none',
        subscriptionProductId: '',
        planExpiresAt: expiresAt,
        accountFirstSeenAt: previous.accountFirstSeenAt,
        accountLastSeenAt: previous.accountLastSeenAt,
        lastSyncedAt: previous.lastSyncedAt,
        updatedAt: Date.now()
      };
    }
    return this.buildDefaultClubStateForUid(previous, previous.userId);
  }

  private buildExpiredProClubState(
    previous: AiraMembershipState,
    grant: AiraMembershipGrantResponseRecord
  ): AiraMembershipState {
    const source = grant.source?.trim().toLowerCase() ?? '';
    const expiresAt = grant.expiresAt ?? 0;
    return {
      userId: previous.userId,
      plan: 'club',
      accountRecognition: previous.accountRecognition,
      accessFlags: ['club'],
      subscriptionStatus: source === 'iap' ? 'expired' : 'none',
      subscriptionProductId: source === 'iap' ? previous.subscriptionProductId : '',
      planExpiresAt: expiresAt,
      accountFirstSeenAt: previous.accountFirstSeenAt,
      accountLastSeenAt: previous.accountLastSeenAt,
      lastSyncedAt: previous.lastSyncedAt,
      updatedAt: Date.now()
    };
  }

  private buildProStateFromVerifiedIap(
    previous: AiraMembershipState,
    productId: string,
    expiresAt: number
  ): AiraMembershipState {
    return {
      userId: previous.userId,
      plan: 'pro',
      accountRecognition: previous.accountRecognition,
      accessFlags: ['club'],
      subscriptionStatus: isAiraProLifetimeProductId(productId) ? 'none' : 'active',
      subscriptionProductId: productId.trim(),
      planExpiresAt: expiresAt,
      accountFirstSeenAt: previous.accountFirstSeenAt,
      accountLastSeenAt: previous.accountLastSeenAt,
      lastSyncedAt: previous.lastSyncedAt,
      updatedAt: Date.now()
    };
  }

  private isGrantActive(grant: AiraMembershipGrantResponseRecord): boolean {
    const uid = grant.uid?.trim() ?? '';
    const expiresAt = grant.expiresAt ?? 0;
    if (uid.length <= 0) {
      return false;
    }
    return expiresAt === 0 || expiresAt > Date.now();
  }

  private resolveRemoteSubscriptionStatus(
    grant: AiraMembershipGrantResponseRecord,
    source: string,
    productId: string
  ): AiraSubscriptionStatus {
    if (isAiraProLifetimeProductId(productId)) {
      return 'none';
    }
    const remoteStatus = grant.subscriptionStatus?.trim().toLowerCase() ?? '';
    if (remoteStatus === 'canceled' || remoteStatus === 'cancelled') {
      return 'cancelled';
    }
    if (remoteStatus === 'active' || remoteStatus === 'grace_period' ||
      remoteStatus === 'expired' || remoteStatus === 'unknown') {
      return remoteStatus as AiraSubscriptionStatus;
    }
    if (remoteStatus === 'none') {
      return 'none';
    }
    return source === 'iap' || productId.length > 0 ? 'active' : 'none';
  }

  private maskUid(uid: string): string {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 6) {
      return normalizedUid;
    }
    return normalizedUid.slice(normalizedUid.length - 6);
  }

  private stringifyError(error: Error): string {
    return `${error.name}: ${error.message}`;
  }

  private buildStateWithAccountProfile(
    state: AiraMembershipState,
    profile: AiraAccountProfileResponseRecord
  ): AiraMembershipState {
    const remoteFirstSeenAt = Math.max(0, Math.floor(profile.firstSeenAt ?? 0));
    const currentFirstSeenAt = Math.max(0, Math.floor(state.accountFirstSeenAt ?? 0));
    return {
      userId: state.userId,
      plan: state.plan,
      accountRecognition: state.accountRecognition,
      accessFlags: state.accessFlags.concat(),
      subscriptionStatus: state.subscriptionStatus,
      subscriptionProductId: state.subscriptionProductId,
      planExpiresAt: state.planExpiresAt,
      accountFirstSeenAt: currentFirstSeenAt > 0
        ? Math.min(currentFirstSeenAt, remoteFirstSeenAt)
        : remoteFirstSeenAt,
      accountLastSeenAt: Math.max(
        Math.max(0, Math.floor(state.accountLastSeenAt ?? 0)),
        Math.max(0, Math.floor(profile.lastSeenAt ?? 0))
      ),
      lastSyncedAt: state.lastSyncedAt,
      updatedAt: Date.now()
    };
  }

  private buildStateWithRecognitions(
    previous: AiraMembershipState,
    recognitions: string[] | undefined
  ): AiraMembershipState {
    const accountRecognition = this.resolveAccountRecognition(recognitions);
    const isInsider = accountRecognition === 'aira_insider';
    const accessFlags = previous.accessFlags.concat();
    if (isInsider && !accessFlags.includes('club')) {
      accessFlags.push('club');
    }
    return {
      userId: previous.userId,
      plan: isInsider ? 'pro' : previous.plan,
      accountRecognition: accountRecognition,
      accessFlags: accessFlags,
      subscriptionStatus: previous.subscriptionStatus,
      subscriptionProductId: previous.subscriptionProductId,
      planExpiresAt: isInsider ? 0 : previous.planExpiresAt,
      accountFirstSeenAt: previous.accountFirstSeenAt,
      accountLastSeenAt: previous.accountLastSeenAt,
      lastSyncedAt: previous.lastSyncedAt,
      updatedAt: Date.now()
    };
  }

  private captureNewUserGiftState(
    uid: string,
    record: AiraNewUserGiftStateRecord | undefined,
    fetchedAt: number
  ): void {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      this.newUserGift = buildEmptyNewUserGiftView();
      return;
    }
    this.newUserGift = {
      uid: normalizedUid,
      eligible: record?.eligible === true,
      grantedAt: this.normalizeGiftTimestamp(record?.grantedAt),
      grantDays: this.normalizeGiftDays(record?.grantDays),
      fetchedAt: fetchedAt
    };
  }

  /**
   * Records the descriptor returned by a successful grant. The grant already
   * happened, so a response without an echoed descriptor must not look like a
   * non-new account, which would drop the announcement for a real new user.
   * `grantedAt` is only advanced when the committed plan really is Pro, so the
   * announcement can never claim a grant that did not land.
   */
  private captureGrantedNewUserGiftState(
    uid: string,
    record: AiraNewUserGiftStateRecord | undefined,
    planIsPro: boolean
  ): void {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      this.newUserGift = buildEmptyNewUserGiftView();
      return;
    }
    const previous = this.newUserGift.uid === normalizedUid ? this.newUserGift : undefined;
    const echoedGrantedAt = this.normalizeGiftTimestamp(record?.grantedAt);
    const grantedAt = echoedGrantedAt > 0
      ? echoedGrantedAt
      : (planIsPro ? (previous?.grantedAt !== undefined && previous.grantedAt > 0 ? previous.grantedAt : Date.now()) : 0);
    this.newUserGift = {
      uid: normalizedUid,
      eligible: record === undefined ? previous?.eligible === true : record.eligible !== false,
      grantedAt: grantedAt,
      grantDays: record?.grantDays !== undefined && record.grantDays > 0
        ? this.normalizeGiftDays(record.grantDays)
        : (previous?.grantDays ?? 0),
      fetchedAt: Date.now()
    };
  }

  private captureLapsedProState(
    uid: string,
    record: AiraLapsedProStateRecord | undefined,
    fetchedAt: number
  ): void {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 0) {
      this.lapsedPro = buildEmptyLapsedProView();
      return;
    }
    this.lapsedPro = {
      uid: normalizedUid,
      expiredAt: this.normalizeGiftTimestamp(record?.expiresAt),
      source: `${record?.source ?? ''}`.trim().toLowerCase(),
      productId: `${record?.productId ?? ''}`.trim(),
      fetchedAt: fetchedAt
    };
  }

  private normalizeGiftTimestamp(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private normalizeGiftDays(value: number | undefined): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.floor(value));
  }

  private resolveAccountRecognition(
    values: string[] | undefined
  ): AiraAccountRecognition {
    return (values ?? []).some((value: string): boolean => value.trim().toLowerCase() === 'aira_insider')
      ? 'aira_insider'
      : 'none';
  }
}
