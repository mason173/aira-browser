import { preferences } from '@kit.ArkData';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import {
  AiraAccountRecognition,
  AiraAccessFlag,
  AiraFeatureQuota,
  AiraMembershipEntitlementProofRecord,
  AiraMembershipState,
  AiraPlan,
  AiraSubscriptionStatus,
  MembershipRepositorySnapshot,
  buildDefaultMembershipState
} from '../../common/models/MembershipModels';

const PREFERENCES_NAME: string = 'aira_browser_membership';
const MEMBERSHIP_STATE_KEY: string = 'aira_membership_state';
const MEMBERSHIP_QUOTAS_KEY: string = 'aira_membership_quota_snapshot';
const RETIRED_MEMBERSHIP_INVITES_KEY: string = 'aira_membership_invite_codes';
const MEMBERSHIP_ENTITLEMENT_PROOFS_KEY: string = 'aira_membership_entitlement_proofs_v1';
const MEMBERSHIP_ENTITLEMENT_PROOF_LIMIT: number = 8;
const MEMBERSHIP_ENTITLEMENT_PROOF_MAX_CHARS: number = 16384;
export type MembershipRepositoryCommitGuard = () => boolean;
export type MembershipRepositoryStateUpdater = (state: AiraMembershipState) => AiraMembershipState;
export type MembershipRepositoryQuotaUpdater = (quotas: AiraFeatureQuota[]) => AiraFeatureQuota[];
export type MembershipRepositorySnapshotUpdater = (
  snapshot: MembershipRepositorySnapshot
) => MembershipRepositorySnapshot;

export class MembershipRepository {
  private store?: preferences.Preferences;
  private storePromise?: Promise<preferences.Preferences>;
  private initializationPromise?: Promise<MembershipRepositorySnapshot>;
  private initialized: boolean = false;
  private state: AiraMembershipState = buildDefaultMembershipState();
  private quotas: AiraFeatureQuota[] = [];
  private entitlementProofs: AiraMembershipEntitlementProofRecord[] = [];

  initialize(): Promise<MembershipRepositorySnapshot> {
    if (this.initialized) {
      return Promise.resolve(this.getSnapshot());
    }
    if (this.initializationPromise === undefined) {
      this.initializationPromise = this.loadPersistedSnapshot()
        .then((snapshot: MembershipRepositorySnapshot) => {
          this.initialized = true;
          return snapshot;
        })
        .catch((error: Error) => {
          this.initializationPromise = undefined;
          throw error;
        });
    }
    return this.initializationPromise;
  }

  getSnapshot(): MembershipRepositorySnapshot {
    return {
      state: this.getState(),
      quotas: this.getQuotaSnapshot()
    };
  }

  getState(): AiraMembershipState {
    return this.cloneState(this.state);
  }

  async loadState(): Promise<AiraMembershipState> {
    return this.getState();
  }

  async updateStateIf(
    guard: MembershipRepositoryCommitGuard,
    updater: MembershipRepositoryStateUpdater
  ): Promise<AiraMembershipState | undefined> {
    const store = await this.getStore();
    if (!guard()) {
      return undefined;
    }
    this.state = this.normalizeState(updater(this.getState()));
    store.putSync(MEMBERSHIP_STATE_KEY, JSON.stringify(this.state));
    store.flushSync();
    return this.getState();
  }

  async clearState(): Promise<void> {
    const store = await this.getStore();
    this.state = buildDefaultMembershipState();
    this.quotas = [];
    this.entitlementProofs = [];
    this.persistAllSync(store);
  }

  getEntitlementProof(uid: string): string {
    const normalizedUid = uid.trim();
    const record = this.entitlementProofs.find((value: AiraMembershipEntitlementProofRecord): boolean => {
      return value.uid === normalizedUid;
    });
    return record?.proof ?? '';
  }

  getQuotaSnapshot(): AiraFeatureQuota[] {
    return this.quotas.map((quota: AiraFeatureQuota) => this.cloneQuota(quota));
  }

  async loadQuotaSnapshot(): Promise<AiraFeatureQuota[]> {
    return this.getQuotaSnapshot();
  }

  async updateQuotaSnapshot(updater: MembershipRepositoryQuotaUpdater): Promise<AiraFeatureQuota[]> {
    const store = await this.getStore();
    this.quotas = this.normalizeQuotas(updater(this.getQuotaSnapshot()));
    store.putSync(MEMBERSHIP_QUOTAS_KEY, JSON.stringify(this.quotas));
    store.flushSync();
    return this.getQuotaSnapshot();
  }

  async updateSnapshotIf(
    guard: MembershipRepositoryCommitGuard,
    updater: MembershipRepositorySnapshotUpdater
  ): Promise<MembershipRepositorySnapshot | undefined> {
    const store = await this.getStore();
    if (!guard()) {
      return undefined;
    }
    const snapshot = updater(this.getSnapshot());
    this.replaceInMemorySnapshot(snapshot.state, snapshot.quotas);
    this.persistAllSync(store);
    return this.getSnapshot();
  }

  async updateSnapshotAndSaveEntitlementProofIf(
    guard: MembershipRepositoryCommitGuard,
    uid: string,
    proof: string,
    updater: MembershipRepositorySnapshotUpdater
  ): Promise<MembershipRepositorySnapshot | undefined> {
    const store = await this.getStore();
    if (!guard()) {
      return undefined;
    }
    const snapshot = updater(this.getSnapshot());
    this.replaceInMemorySnapshot(snapshot.state, snapshot.quotas);
    this.setEntitlementProof(uid, proof);
    this.persistAllSync(store);
    return this.getSnapshot();
  }

  async updateSnapshotAndClearEntitlementProofIf(
    guard: MembershipRepositoryCommitGuard,
    uid: string,
    updater: MembershipRepositorySnapshotUpdater
  ): Promise<MembershipRepositorySnapshot | undefined> {
    const store = await this.getStore();
    if (!guard()) {
      return undefined;
    }
    const snapshot = updater(this.getSnapshot());
    this.replaceInMemorySnapshot(snapshot.state, snapshot.quotas);
    this.clearEntitlementProof(uid);
    this.persistAllSync(store);
    return this.getSnapshot();
  }

  private replaceInMemorySnapshot(
    state: AiraMembershipState,
    quotas: AiraFeatureQuota[]
  ): void {
    this.state = this.normalizeState(state);
    this.quotas = this.normalizeQuotas(quotas);
  }

  private persistAllSync(store: preferences.Preferences): void {
    store.putSync(MEMBERSHIP_STATE_KEY, JSON.stringify(this.state));
    store.putSync(MEMBERSHIP_QUOTAS_KEY, JSON.stringify(this.quotas));
    store.putSync(MEMBERSHIP_ENTITLEMENT_PROOFS_KEY, JSON.stringify(this.entitlementProofs));
    store.flushSync();
  }

  private async loadPersistedSnapshot(): Promise<MembershipRepositorySnapshot> {
    const store = await this.getStore();
    const storedState = String(store.getSync(MEMBERSHIP_STATE_KEY, ''));
    const storedQuotas = String(store.getSync(MEMBERSHIP_QUOTAS_KEY, ''));
    const storedEntitlementProofs = String(store.getSync(MEMBERSHIP_ENTITLEMENT_PROOFS_KEY, ''));
    const removedRetiredInvitePersistence = store.hasSync(RETIRED_MEMBERSHIP_INVITES_KEY);
    if (removedRetiredInvitePersistence) {
      store.deleteSync(RETIRED_MEMBERSHIP_INVITES_KEY);
    }
    this.state = this.normalizeState(this.parseState(storedState));
    this.quotas = this.normalizeQuotas(this.parseQuotas(storedQuotas));
    this.entitlementProofs = this.normalizeEntitlementProofs(storedEntitlementProofs);
    await this.persistNormalizedSnapshotIfChanged(
      store,
      storedState,
      storedQuotas,
      storedEntitlementProofs,
      removedRetiredInvitePersistence
    );
    return this.getSnapshot();
  }

  private async persistNormalizedSnapshotIfChanged(
    store: preferences.Preferences,
    storedState: string,
    storedQuotas: string,
    storedEntitlementProofs: string,
    removedRetiredInvitePersistence: boolean
  ): Promise<void> {
    const normalizedState = JSON.stringify(this.state);
    const normalizedQuotas = JSON.stringify(this.quotas);
    const normalizedEntitlementProofs = JSON.stringify(this.entitlementProofs);
    let changed: boolean = removedRetiredInvitePersistence;
    if (storedState !== normalizedState) {
      store.putSync(MEMBERSHIP_STATE_KEY, normalizedState);
      changed = true;
    }
    if (storedQuotas !== normalizedQuotas) {
      store.putSync(MEMBERSHIP_QUOTAS_KEY, normalizedQuotas);
      changed = true;
    }
    if (storedEntitlementProofs !== normalizedEntitlementProofs) {
      store.putSync(MEMBERSHIP_ENTITLEMENT_PROOFS_KEY, normalizedEntitlementProofs);
      changed = true;
    }
    if (!changed) {
      return;
    }
    await store.flush();
  }

  private parseState(value: string): AiraMembershipState | undefined {
    if (value.trim().length === 0) {
      return undefined;
    }
    try {
      return JSON.parse(value) as AiraMembershipState;
    } catch (_error) {
      return undefined;
    }
  }

  private parseQuotas(value: string): AiraFeatureQuota[] {
    if (value.trim().length === 0) {
      return [];
    }
    try {
      return JSON.parse(value) as AiraFeatureQuota[];
    } catch (_error) {
      return [];
    }
  }

  private normalizeEntitlementProofs(value: string): AiraMembershipEntitlementProofRecord[] {
    if (value.trim().length === 0) {
      return [];
    }
    try {
      const parsed = JSON.parse(value) as AiraMembershipEntitlementProofRecord[];
      const results: AiraMembershipEntitlementProofRecord[] = [];
      (parsed ?? []).forEach((record: AiraMembershipEntitlementProofRecord) => {
        const uid = this.normalizeString(record?.uid, '');
        const proof = this.normalizeString(record?.proof, '');
        if (uid.length <= 0 || proof.length <= 0 || proof.length > MEMBERSHIP_ENTITLEMENT_PROOF_MAX_CHARS) {
          return;
        }
        const existingIndex = results.findIndex((value: AiraMembershipEntitlementProofRecord): boolean => {
          return value.uid === uid;
        });
        if (existingIndex >= 0) {
          results.splice(existingIndex, 1);
        }
        results.push({ uid, proof });
      });
      return results.slice(Math.max(0, results.length - MEMBERSHIP_ENTITLEMENT_PROOF_LIMIT));
    } catch (_error) {
      return [];
    }
  }

  private setEntitlementProof(uid: string, proof: string): void {
    const normalizedUid = uid.trim();
    const normalizedProof = proof.trim();
    if (normalizedUid.length <= 0 || normalizedProof.length <= 0 ||
      normalizedProof.length > MEMBERSHIP_ENTITLEMENT_PROOF_MAX_CHARS) {
      return;
    }
    this.clearEntitlementProof(normalizedUid);
    this.entitlementProofs.push({ uid: normalizedUid, proof: normalizedProof });
    if (this.entitlementProofs.length > MEMBERSHIP_ENTITLEMENT_PROOF_LIMIT) {
      this.entitlementProofs.splice(0, this.entitlementProofs.length - MEMBERSHIP_ENTITLEMENT_PROOF_LIMIT);
    }
  }

  private clearEntitlementProof(uid: string): void {
    const normalizedUid = uid.trim();
    this.entitlementProofs = this.entitlementProofs.filter(
      (record: AiraMembershipEntitlementProofRecord): boolean => record.uid !== normalizedUid
    );
  }

  private normalizeState(value: AiraMembershipState | undefined): AiraMembershipState {
    const fallback = buildDefaultMembershipState();
    const userId = this.normalizeString(value?.userId, fallback.userId);
    const accountRecognition = this.normalizeAccountRecognition(value?.accountRecognition);
    const storedPlan = this.normalizePlan(value?.plan, userId);
    const plan: AiraPlan = accountRecognition === 'aira_insider' ? 'pro' : storedPlan;
    return {
      userId: userId,
      plan: plan,
      accountRecognition: accountRecognition,
      accessFlags: this.normalizeAccessFlags(value?.accessFlags, plan),
      subscriptionStatus: this.normalizeSubscriptionStatus(value?.subscriptionStatus, plan),
      subscriptionProductId: this.normalizeString(value?.subscriptionProductId, ''),
      planExpiresAt: accountRecognition === 'aira_insider' ? 0 : this.normalizeTimestamp(value?.planExpiresAt),
      accountFirstSeenAt: this.normalizeTimestamp(value?.accountFirstSeenAt),
      accountLastSeenAt: this.normalizeTimestamp(value?.accountLastSeenAt),
      lastSyncedAt: this.normalizeTimestamp(value?.lastSyncedAt),
      updatedAt: this.normalizeTimestamp(value?.updatedAt, Date.now())
    };
  }

  private normalizeQuotas(values: AiraFeatureQuota[] | undefined): AiraFeatureQuota[] {
    const results: AiraFeatureQuota[] = [];
    (values ?? []).forEach((value: AiraFeatureQuota) => {
      const featureKey = this.normalizeString(value?.featureKey, '');
      if (featureKey.length <= 0) {
        return;
      }
      results.push({
        featureKey: featureKey,
        used: this.normalizeInteger(value?.used, 0),
        limit: this.normalizeInteger(value?.limit, 0),
        resetAt: this.normalizeTimestamp(value?.resetAt)
      });
    });
    return results;
  }

  private normalizePlan(value: AiraPlan | undefined, userId: string): AiraPlan {
    if (value === 'guest' || value === 'club' || value === 'pro') {
      return value;
    }
    return userId === 'local' || userId.length <= 0 ? 'guest' : 'club';
  }

  private normalizeAccountRecognition(value: AiraAccountRecognition | undefined): AiraAccountRecognition {
    return value === 'aira_insider' ? 'aira_insider' : 'none';
  }

  private normalizeSubscriptionStatus(value: AiraSubscriptionStatus | undefined, plan: AiraPlan): AiraSubscriptionStatus {
    if (plan === 'pro' && value === undefined) {
      return 'active';
    }
    if (value === 'active' || value === 'grace_period' || value === 'expired' ||
      value === 'cancelled' || value === 'unknown') {
      return value;
    }
    return 'none';
  }

  private normalizeAccessFlags(values: AiraAccessFlag[] | undefined, plan: AiraPlan): AiraAccessFlag[] {
    const results: AiraAccessFlag[] = [];
    (values ?? []).forEach((value: AiraAccessFlag) => {
      if ((value === 'club' || value === 'founder') && !results.includes(value)) {
        results.push(value);
      }
    });
    if ((plan === 'club' || plan === 'pro') && !results.includes('club')) {
      results.push('club');
    }
    return results;
  }

  private normalizeString(value: string | undefined, fallback: string): string {
    const normalized = `${value ?? ''}`.trim();
    return normalized.length > 0 ? normalized : fallback;
  }

  private normalizeInteger(value: number | undefined, fallback: number): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return fallback;
    }
    return Math.max(0, Math.floor(value));
  }

  private normalizeTimestamp(value: number | undefined, fallback: number = 0): number {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      return fallback;
    }
    return Math.max(0, Math.floor(value));
  }

  private cloneState(state: AiraMembershipState): AiraMembershipState {
    return {
      userId: state.userId,
      plan: state.plan,
      accountRecognition: state.accountRecognition,
      accessFlags: state.accessFlags.concat(),
      subscriptionStatus: state.subscriptionStatus,
      subscriptionProductId: state.subscriptionProductId,
      planExpiresAt: state.planExpiresAt,
      accountFirstSeenAt: state.accountFirstSeenAt,
      accountLastSeenAt: state.accountLastSeenAt,
      lastSyncedAt: state.lastSyncedAt,
      updatedAt: state.updatedAt
    };
  }

  private cloneQuota(quota: AiraFeatureQuota): AiraFeatureQuota {
    return {
      featureKey: quota.featureKey,
      used: quota.used,
      limit: quota.limit,
      resetAt: quota.resetAt
    };
  }

  private async getStore(): Promise<preferences.Preferences> {
    if (this.store !== undefined) {
      return this.store;
    }
    if (this.storePromise === undefined) {
      this.storePromise = preferences.getPreferences(AppRuntimeContext.getApplicationContext(), PREFERENCES_NAME)
        .then((store: preferences.Preferences) => {
          this.store = store;
          return store;
        });
    }
    return this.storePromise;
  }
}
