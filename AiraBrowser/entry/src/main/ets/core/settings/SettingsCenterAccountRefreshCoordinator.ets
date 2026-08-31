import {
  AiraSyncSettings,
  resolveAiraHuaweiAccountIdentity
} from '../../common/models/AiraSyncModels';
import { BrowserDataBoundaryInput } from '../../common/models/BrowserModels';
import { AiraMembershipState } from '../../common/models/MembershipModels';
import { LocalUserAvatarService } from '../../services/settings/LocalUserAvatarService';
import { MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS } from '../../services/membership/MembershipRefreshPolicyService';
import { AiraSyncConfigStore } from '../../services/sync/AiraSyncConfigStore';
import { MembershipFeature } from '../../features/membership/MembershipFeature';
import { HuaweiAccountMutationCoordinator } from '../account/HuaweiAccountMutationCoordinator';
import {
  SettingsAccountCardState,
  SettingsAccountCardViewModel
} from './SettingsAccountCardViewModel';

export interface SettingsCenterAccountRefreshSnapshot {
  accountCard: SettingsAccountCardState;
  membershipState: AiraMembershipState;
}

export interface SettingsCenterAccountRefreshClock {
  setTimeout(callback: () => void, delayMs: number): number;
  clearTimeout(timerId: number): void;
  now(): number;
}

export interface SettingsCenterAccountRefreshCoordinatorOptions {
  membershipFeature: MembershipFeature;
  syncConfigStore: AiraSyncConfigStore;
  accountMutationCoordinator: HuaweiAccountMutationCoordinator;
  localUserAvatarService?: LocalUserAvatarService;
  viewModel?: SettingsAccountCardViewModel;
  clock?: SettingsCenterAccountRefreshClock;
  onSnapshotChanged?: (snapshot: SettingsCenterAccountRefreshSnapshot) => void;
}

const SETTINGS_CENTER_ACCOUNT_REFRESH_DELAY_MS: number = 520;
const SETTINGS_CENTER_PROFILE_REFRESH_COOLDOWN_MS: number = 6 * 60 * 60 * 1000;

class DefaultSettingsCenterAccountRefreshClock implements SettingsCenterAccountRefreshClock {
  setTimeout(callback: () => void, delayMs: number): number {
    return setTimeout(callback, delayMs);
  }

  clearTimeout(timerId: number): void {
    clearTimeout(timerId);
  }

  now(): number {
    return Date.now();
  }
}

export class SettingsCenterAccountRefreshCoordinator {
  private membershipFeature: MembershipFeature;
  private syncConfigStore: AiraSyncConfigStore;
  private accountMutationCoordinator: HuaweiAccountMutationCoordinator;
  private localUserAvatarService: LocalUserAvatarService;
  private viewModel: SettingsAccountCardViewModel;
  private clock: SettingsCenterAccountRefreshClock;
  private onSnapshotChanged?: (snapshot: SettingsCenterAccountRefreshSnapshot) => void;
  private deferredRefreshTimer: number = -1;
  private refreshSequence: number = 0;
  private isRefreshingDeferredState: boolean = false;
  private pendingDeferredRefreshContext?: SettingsCenterAccountRefreshContext;
  private cachedLocalAvatarUri: string = '';
  private didLoadLocalAvatar: boolean = false;
  private lastProfileRefreshAttemptAt: number = 0;
  private lastSnapshotSignature: string = '';

  constructor(options: SettingsCenterAccountRefreshCoordinatorOptions) {
    this.membershipFeature = options.membershipFeature;
    this.syncConfigStore = options.syncConfigStore;
    this.accountMutationCoordinator = options.accountMutationCoordinator;
    this.localUserAvatarService = options.localUserAvatarService ?? new LocalUserAvatarService();
    this.viewModel = options.viewModel ?? new SettingsAccountCardViewModel();
    this.clock = options.clock ?? new DefaultSettingsCenterAccountRefreshClock();
    this.onSnapshotChanged = options.onSnapshotChanged;
  }

  buildCachedSnapshot(dataScope: string, privacyMode: string): SettingsCenterAccountRefreshSnapshot {
    const snapshot = this.buildSnapshot(dataScope, privacyMode, this.cachedLocalAvatarUri);
    this.lastSnapshotSignature = this.buildSnapshotSignature(snapshot);
    return snapshot;
  }

  scheduleDeferredRefresh(dataScope: string, privacyMode: string): void {
    this.cancelDeferredRefresh();
    this.refreshSequence += 1;
    const requestId = this.refreshSequence;
    this.deferredRefreshTimer = this.clock.setTimeout(() => {
      this.deferredRefreshTimer = -1;
      void this.refreshDeferredState(dataScope, privacyMode, requestId);
    }, SETTINGS_CENTER_ACCOUNT_REFRESH_DELAY_MS);
  }

  cancelDeferredRefresh(): void {
    if (this.deferredRefreshTimer < 0) {
      return;
    }
    this.clock.clearTimeout(this.deferredRefreshTimer);
    this.deferredRefreshTimer = -1;
  }

  resetSnapshotSignature(): void {
    this.lastSnapshotSignature = '';
  }

  private async refreshDeferredState(
    dataScope: string,
    privacyMode: string,
    requestId: number
  ): Promise<void> {
    if (requestId !== this.refreshSequence) {
      return;
    }
    if (this.isRefreshingDeferredState) {
      this.pendingDeferredRefreshContext = {
        dataScope,
        privacyMode,
        requestId
      };
      return;
    }
    this.isRefreshingDeferredState = true;
    try {
      await this.refreshLocalAvatarIfNeeded(requestId);
      await this.refreshHuaweiAccountProfileIfNeeded(requestId, dataScope, privacyMode);
      await this.refreshMembershipStateIfNeeded(requestId, dataScope, privacyMode);
      if (requestId === this.refreshSequence) {
        this.emitIfChanged(this.buildSnapshot(dataScope, privacyMode, this.cachedLocalAvatarUri));
      }
    } finally {
      this.isRefreshingDeferredState = false;
      this.flushPendingDeferredRefresh();
    }
  }

  private async refreshLocalAvatarIfNeeded(requestId: number): Promise<void> {
    if (this.didLoadLocalAvatar || requestId !== this.refreshSequence) {
      return;
    }
    this.didLoadLocalAvatar = true;
    try {
      this.cachedLocalAvatarUri = await this.localUserAvatarService.getAvatarImageUri();
    } catch (_error) {
      this.cachedLocalAvatarUri = '';
    }
  }

  private async refreshHuaweiAccountProfileIfNeeded(
    requestId: number,
    dataScope: string,
    privacyMode: string
  ): Promise<void> {
    if (requestId !== this.refreshSequence || !this.shouldRefreshHuaweiAccountProfile()) {
      return;
    }
    const now = this.clock.now();
    if (this.lastProfileRefreshAttemptAt > 0 &&
      now - this.lastProfileRefreshAttemptAt < SETTINGS_CENTER_PROFILE_REFRESH_COOLDOWN_MS) {
      return;
    }
    const boundaryInput: BrowserDataBoundaryInput = {
      dataScope: dataScope,
      privacyMode: privacyMode
    };
    if (!this.accountMutationCoordinator.canRefreshIdentityProfile(boundaryInput)) {
      return;
    }
    this.lastProfileRefreshAttemptAt = now;
    await this.accountMutationCoordinator.refreshIdentityProfile(boundaryInput);
  }

  private async refreshMembershipStateIfNeeded(
    requestId: number,
    dataScope: string,
    privacyMode: string
  ): Promise<void> {
    if (requestId !== this.refreshSequence || !this.isHuaweiAccountSignedIn()) {
      return;
    }
    const boundaryInput: BrowserDataBoundaryInput = {
      dataScope: dataScope,
      privacyMode: privacyMode
    };
    await this.accountMutationCoordinator.refreshAiraAccountProfile(boundaryInput);
    await this.membershipFeature.refreshStateForBoundary(boundaryInput, {
      minFreshMs: MEMBERSHIP_REFRESH_ACCOUNT_VISIBLE_FRESH_MS
    });
  }

  private buildSnapshot(
    dataScope: string,
    privacyMode: string,
    avatarUri: string
  ): SettingsCenterAccountRefreshSnapshot {
    const membershipState = this.membershipFeature.getState();
    return {
      accountCard: this.viewModel.buildMembershipState(
        membershipState,
        dataScope,
        privacyMode,
        avatarUri,
        this.syncConfigStore.getSettings()
      ),
      membershipState
    };
  }

  private emitIfChanged(snapshot: SettingsCenterAccountRefreshSnapshot): void {
    const signature = this.buildSnapshotSignature(snapshot);
    if (signature === this.lastSnapshotSignature) {
      return;
    }
    this.lastSnapshotSignature = signature;
    this.onSnapshotChanged?.(snapshot);
  }

  private shouldRefreshHuaweiAccountProfile(): boolean {
    const settings = this.syncConfigStore.getSettings();
    const identity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    const uid = identity.uid;
    if (uid.length <= 0) {
      return false;
    }
    if (identity.photoUrl.length <= 0) {
      return true;
    }
    return this.isFallbackHuaweiDisplayName(identity.displayName, uid);
  }

  private isFallbackHuaweiDisplayName(displayName: string, uid: string): boolean {
    const normalizedUid = uid.trim();
    const suffix = normalizedUid.length > 6 ? normalizedUid.slice(normalizedUid.length - 6) : normalizedUid;
    return displayName.length <= 0 || displayName === '华为账号' ||
      (suffix.length > 0 && displayName === `华为账号 ${suffix}`);
  }

  private isHuaweiAccountSignedIn(): boolean {
    const settings = this.syncConfigStore.getSettings();
    return resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace).uid.length > 0;
  }

  private buildSnapshotSignature(snapshot: SettingsCenterAccountRefreshSnapshot): string {
    const settings = this.syncConfigStore.getSettings();
    return [
      this.buildAccountCardSignature(snapshot.accountCard),
      this.buildMembershipSignature(snapshot.membershipState),
      this.buildHuaweiCloudSignature(settings)
    ].join('||');
  }

  private buildAccountCardSignature(state: SettingsAccountCardState): string {
    return [
      state.title,
      state.subtitle,
      state.isLoggedIn ? '1' : '0',
      state.avatarUri,
      state.membershipBadge,
      state.recognitionBadge
    ].join('|');
  }

  private buildMembershipSignature(state: AiraMembershipState): string {
    return [
      state.userId,
      state.plan,
      state.accountRecognition,
      state.subscriptionStatus,
      state.subscriptionProductId,
      `${state.planExpiresAt}`,
      `${state.lastSyncedAt}`,
      state.accessFlags.join(',')
    ].join('|');
  }

  private buildHuaweiCloudSignature(settings: AiraSyncSettings): string {
    const identity = resolveAiraHuaweiAccountIdentity(settings.huaweiCloud, settings.huaweiSpace);
    const webdav = settings.webdav;
    return [
      identity.uid,
      identity.displayName,
      identity.photoUrl,
      settings.remoteKind,
      settings.additionalBackupEnabled ? '1' : '0',
      settings.additionalBackupRemoteKinds.join(','),
      webdav.endpoint,
      webdav.username
    ].join('|');
  }

  private flushPendingDeferredRefresh(): void {
    const pending = this.pendingDeferredRefreshContext;
    this.pendingDeferredRefreshContext = undefined;
    if (pending === undefined || pending.requestId !== this.refreshSequence) {
      return;
    }
    void this.refreshDeferredState(pending.dataScope, pending.privacyMode, pending.requestId);
  }
}

interface SettingsCenterAccountRefreshContext {
  dataScope: string;
  privacyMode: string;
  requestId: number;
}
