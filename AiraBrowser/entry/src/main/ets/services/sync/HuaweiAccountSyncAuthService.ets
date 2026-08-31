import auth, { AuthUser } from '@hw-agconnect/auth';
import { authentication } from '@kit.AccountKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { AppRuntimeContext } from '../../app/runtime/AppRuntimeContext';
import { HuaweiCloudSyncInitService } from './HuaweiCloudSyncInitService';
import { AIRA_DISTRIBUTION_CAPABILITY_OWNER } from '../../common/config/AiraDistributionCapabilityOwner';

const HUAWEI_ACCOUNT_AUTH_DOMAIN = 0x0000;
const HUAWEI_ACCOUNT_AUTH_TAG = 'HuaweiAccountAuth';

export interface HuaweiAccountSyncIdentity {
  uid: string;
  displayName: string;
  photoUrl: string;
}

export interface HuaweiAccountSyncAuthAdapter {
  signIn(): Promise<HuaweiAccountSyncIdentity>;
  resetSignInState(): Promise<void>;
  getCurrentIdentity(): Promise<HuaweiAccountSyncIdentity | undefined>;
  refreshCurrentIdentityProfile(): Promise<HuaweiAccountSyncIdentity | undefined>;
  signOut(): Promise<void>;
}

class AgcHuaweiAccountSyncAuthAdapter implements HuaweiAccountSyncAuthAdapter {
  async signIn(): Promise<HuaweiAccountSyncIdentity> {
    const current = await this.getCurrentIdentity();
    if (current !== undefined) {
      return this.enrichWithHuaweiProfile(current);
    }
    const result = await auth.signIn({
      autoCreateUser: true,
      credentialInfo: {
        kind: 'hwid'
      }
    });
    const user = result.getUser();
    const uid = this.resolveUid(user.getUid());
    const baseIdentity: HuaweiAccountSyncIdentity = {
      uid: uid,
      displayName: this.resolveDisplayName(user.getDisplayName(), uid),
      photoUrl: this.resolvePhotoUrl(user.getPhotoUrl())
    };
    return this.enrichWithHuaweiProfile(baseIdentity);
  }

  resetSignInState(): Promise<void> {
    return auth.signOut()
      .catch((error: Error) => {
        const detail = error as HuaweiAccountSyncErrorDetail;
        if (detail.code === 1210002 || detail.message === 'no user signed in.') {
          return;
        }
        throw error;
      });
  }

  async getCurrentIdentity(): Promise<HuaweiAccountSyncIdentity | undefined> {
    const user = await auth.getCurrentUser();
    if (user === null) {
      return undefined;
    }
    return this.buildIdentityFromUser(user);
  }

  async refreshCurrentIdentityProfile(): Promise<HuaweiAccountSyncIdentity | undefined> {
    const current = await this.getCurrentIdentity();
    if (current === undefined) {
      return undefined;
    }
    return this.enrichWithHuaweiProfile(current, false);
  }

  signOut(): Promise<void> {
    return auth.signOut();
  }

  private resolveDisplayName(displayName: string | undefined, uid: string | undefined): string {
    const normalizedDisplayName = displayName?.trim() ?? '';
    if (normalizedDisplayName.length > 0) {
      return normalizedDisplayName;
    }
    const normalizedUid = uid?.trim() ?? '';
    const suffix = normalizedUid.length > 6 ? normalizedUid.slice(normalizedUid.length - 6) : normalizedUid;
    return suffix.length > 0 ? `华为账号 ${suffix}` : '华为账号';
  }

  private resolveUid(uid: string | undefined): string {
    return uid?.trim() ?? '';
  }

  private resolvePhotoUrl(photoUrl: string | undefined): string {
    return photoUrl?.trim() ?? '';
  }

  private buildIdentityFromUser(user: AuthUser): HuaweiAccountSyncIdentity {
    const uid = this.resolveUid(user.getUid());
    return {
      uid: uid,
      displayName: this.resolveDisplayName(user.getDisplayName(), uid),
      photoUrl: this.resolvePhotoUrl(user.getPhotoUrl())
    };
  }

  private async enrichWithHuaweiProfile(
    identity: HuaweiAccountSyncIdentity,
    forceAuthorization: boolean = true
  ): Promise<HuaweiAccountSyncIdentity> {
    try {
      const profile = await this.requestHuaweiProfile(forceAuthorization);
      const displayName = profile.nickName.length > 0 ? profile.nickName : identity.displayName;
      const photoUrl = profile.avatarUri.length > 0 ? profile.avatarUri : identity.photoUrl;
      return {
        uid: identity.uid,
        displayName: this.resolveDisplayName(displayName, identity.uid),
        photoUrl: this.resolvePhotoUrl(photoUrl)
      };
    } catch (error) {
      const businessError = error as BusinessError;
      hilog.warn(
        HUAWEI_ACCOUNT_AUTH_DOMAIN,
        HUAWEI_ACCOUNT_AUTH_TAG,
        'profile authorization skipped code=%{public}s message=%{public}s',
        `${businessError.code ?? ''}`,
        businessError.message ?? ''
      );
      return identity;
    }
  }

  private async requestHuaweiProfile(forceAuthorization: boolean): Promise<HuaweiAccountProfile> {
    const request = new authentication.HuaweiIDProvider()
      .createAuthorizationWithHuaweiIDRequest();
    request.scopes = ['profile'];
    request.forceAuthorization = forceAuthorization;
    request.state = util.generateRandomUUID();

    const controller = new authentication.AuthenticationController(AppRuntimeContext.getUIAbilityContext());
    const response = await controller.executeRequest(request) as authentication.AuthorizationWithHuaweiIDResponse;
    if (response.state !== undefined && response.state !== request.state) {
      throw new Error('Huawei profile authorization state mismatch.');
    }

    const credential = response.data;
    if (credential === undefined) {
      return {
        nickName: '',
        avatarUri: ''
      };
    }
    return {
      nickName: credential.nickName?.trim() ?? '',
      avatarUri: credential.avatarUri?.trim() ?? ''
    };
  }
}

interface HuaweiAccountProfile {
  nickName: string;
  avatarUri: string;
}

export class HuaweiAccountSyncAuthService {
  private adapter: HuaweiAccountSyncAuthAdapter;
  private initService: HuaweiCloudSyncInitService;

  constructor(adapter?: HuaweiAccountSyncAuthAdapter, initService?: HuaweiCloudSyncInitService) {
    this.adapter = adapter ?? new AgcHuaweiAccountSyncAuthAdapter();
    this.initService = initService ?? new HuaweiCloudSyncInitService();
  }

  async getCurrentAccessToken(forceRefresh: boolean = false): Promise<string> {
    this.requireHuaweiAccountCapability();
    await this.ensureAuthInitializedIfPossible();
    const token = await this.getSignedInUserAccessToken(forceRefresh);
    return token.tokenString;
  }

  async getCurrentAccessTokenForUid(uid: string, forceRefresh: boolean = false): Promise<string> {
    this.requireHuaweiAccountCapability();
    const expectedUid = uid.trim();
    if (expectedUid.length <= 0) {
      return '';
    }
    await this.ensureAuthInitializedIfPossible();
    const current = await this.adapter.getCurrentIdentity();
    if (current === undefined) {
      hilog.warn(
        HUAWEI_ACCOUNT_AUTH_DOMAIN,
        HUAWEI_ACCOUNT_AUTH_TAG,
        'token current identity missing uidSuffix=%{public}s',
        this.maskUid(expectedUid)
      );
      const identity = await this.adapter.signIn();
      if (identity.uid.trim() !== expectedUid) {
        hilog.warn(
          HUAWEI_ACCOUNT_AUTH_DOMAIN,
          HUAWEI_ACCOUNT_AUTH_TAG,
          'token sign-in uid mismatch expected=%{public}s actual=%{public}s',
          this.maskUid(expectedUid),
          this.maskUid(identity.uid)
        );
        throw new Error('Huawei account identity mismatch.');
      }
    } else if (current.uid.trim() !== expectedUid) {
      hilog.warn(
        HUAWEI_ACCOUNT_AUTH_DOMAIN,
        HUAWEI_ACCOUNT_AUTH_TAG,
        'token current uid mismatch expected=%{public}s actual=%{public}s',
        this.maskUid(expectedUid),
        this.maskUid(current.uid)
      );
      throw new Error('Huawei account identity mismatch.');
    } else {
    }
    const token = await this.getSignedInUserAccessToken(forceRefresh);
    return token.tokenString;
  }

  async signInForBookmarkSync(forceNewSession: boolean = false): Promise<HuaweiAccountSyncIdentity> {
    this.requireHuaweiAccountCapability();
    if (forceNewSession) {
      await this.resetSignInState();
    }
    return this.adapter.signIn();
  }

  resetSignInState(): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_account')) {
      return Promise.resolve();
    }
    return this.adapter.resetSignInState();
  }

  async getCurrentIdentity(): Promise<HuaweiAccountSyncIdentity | undefined> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_account')) {
      return undefined;
    }
    await this.ensureAuthInitializedIfPossible();
    return this.adapter.getCurrentIdentity();
  }

  async refreshCurrentIdentityProfile(): Promise<HuaweiAccountSyncIdentity | undefined> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_account')) {
      return undefined;
    }
    await this.ensureAuthInitializedIfPossible();
    return this.adapter.refreshCurrentIdentityProfile();
  }

  signOut(): Promise<void> {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_account')) {
      return Promise.resolve();
    }
    return this.adapter.signOut();
  }

  private requireHuaweiAccountCapability(): void {
    if (!AIRA_DISTRIBUTION_CAPABILITY_OWNER.isAvailable('huawei_account')) {
      throw new Error(AIRA_DISTRIBUTION_CAPABILITY_OWNER.resolveUnavailableReason('huawei_account'));
    }
  }

  private async ensureAuthInitializedIfPossible(): Promise<void> {
    if (!AppRuntimeContext.hasUIAbilityContext()) {
      return;
    }
    await this.initService.initializeAuth(AppRuntimeContext.getUIAbilityContext());
  }

  private async getSignedInUserAccessToken(forceRefresh: boolean): Promise<HuaweiAccountSyncAccessToken> {
    const user = await auth.getCurrentUser();
    if (user === null) {
      throw new Error('No AGC user signed in.');
    }
    const token = await user.getToken(forceRefresh);
    return {
      tokenString: token.getString().trim(),
      expiration: token.getExpirePeriod()
    };
  }

  private maskUid(uid: string): string {
    const normalizedUid = uid.trim();
    if (normalizedUid.length <= 6) {
      return normalizedUid;
    }
    return normalizedUid.slice(normalizedUid.length - 6);
  }
}

interface HuaweiAccountSyncErrorDetail {
  code?: number | string;
  message?: string;
}

interface HuaweiAccountSyncAccessToken {
  tokenString: string;
  expiration: number;
}
