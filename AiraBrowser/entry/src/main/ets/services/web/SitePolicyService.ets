import { common } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import {
  BrowserDataScope,
  BrowserProfileId,
  DEFAULT_BROWSER_PROFILE_ID,
  SitePermissionDefaultSettings,
  SitePermissionKind,
  SitePermissionRule,
  SitePermissionSettings
} from '../../common/models/BrowserModels';
import { PreferencesRepository } from '../../data/preferences/PreferencesRepository';
import { SiteCapabilityCatalogService } from './SiteCapabilityCatalogService';
import { BrowserProfileBoundaryService } from '../../core/browser/BrowserProfileBoundaryService';
import {
  SystemPermissionGrantResult,
  SystemPermissionService
} from '../system/SystemPermissionService';
import { SiteIdentityService } from './SiteIdentityService';
import { BrowserRuntimeLifecyclePort } from './BrowserRuntimeLifecyclePort';

export interface SiteProtectedResourceDecision {
  origin: string;
  resources: string[];
  kinds: SitePermissionKind[];
  blocked: boolean;
  allowed: boolean;
}

export interface SitePermissionDraft {
  camera: SitePermissionRule;
  microphone: SitePermissionRule;
  location: SitePermissionRule;
  sensor: SitePermissionRule;
  clipboard: SitePermissionRule;
}

export interface SitePermissionSessionCleanupResult {
  profileId: BrowserProfileId;
  removed: number;
  onceRemoved: number;
  before: number;
  after: number;
  summaryLine: string;
}

export interface SitePermissionSessionSnapshot {
  profileId: BrowserProfileId;
  originCount: number;
  allowRuleCount: number;
  blockRuleCount: number;
  totalRuleCount: number;
  summaryLine: string;
}

export interface SitePermissionSessionGrant {
  origin: string;
  kind: SitePermissionKind;
  profileId: BrowserProfileId;
  dataScope: BrowserDataScope;
  createdAt: number;
}

export interface SitePermissionSessionClearOptions {
  origins?: string[];
  kinds?: SitePermissionKind[];
  profileId?: BrowserProfileId;
  dataScope?: BrowserDataScope;
}

export class SitePolicyService {
  private preferencesRepository: PreferencesRepository;
  private capabilityCatalog: SiteCapabilityCatalogService = new SiteCapabilityCatalogService();
  private profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private systemPermissionService: SystemPermissionService = new SystemPermissionService();
  private siteIdentityService: SiteIdentityService = new SiteIdentityService();
  private sessionSitePermissionSettings: SitePermissionSettings[] = [];
  private permissionSessionGrants: SitePermissionSessionGrant[] = [];
  private activePermissionSessionOwners: number = 0;

  constructor(preferencesRepository: PreferencesRepository) {
    this.preferencesRepository = preferencesRepository;
  }

  resolveProtectedResourceDecision(
    origin: string,
    resources: string[],
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): SiteProtectedResourceDecision | undefined {
    const normalizedOrigin = this.normalizeOrigin(origin);
    const resolution = this.capabilityCatalog.resolveProtectedResources(resources);
    if (normalizedOrigin.length === 0 || resources.length === 0 || resolution.kinds.length === 0 ||
      resolution.unsupportedResources.length > 0) {
      return undefined;
    }
    const settings = this.getEffectiveSitePermissionSettings(normalizedOrigin, profileId, dataScope);
    return {
      origin: normalizedOrigin,
      resources: resolution.resources,
      kinds: resolution.kinds,
      blocked: this.shouldBlockSitePermission(settings, resolution.kinds),
      allowed: this.shouldAllowSitePermission(settings, resolution.kinds)
    };
  }

  getEffectiveSitePermissionSettings(
    origin: string,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): SitePermissionSettings {
    const normalizedOrigin = this.normalizeOrigin(origin);
    if (this.profileBoundaryService.resolveSitePermissionScope({ profileId: profileId, dataScope: dataScope }) ===
      'incognito_session_only') {
      const sessionSettings = this.sessionSitePermissionSettings.find((settings: SitePermissionSettings) => {
        return settings.primaryOrigin === normalizedOrigin && settings.profileId === profileId;
      });
      return sessionSettings ?? this.buildDefaultSitePermissionSettings(normalizedOrigin, profileId);
    }
    const storedSettings = this.preferencesRepository.getSitePermissionSettings(normalizedOrigin, profileId);
    if (storedSettings.updatedAt > 0 || this.hasNonDefaultRule(storedSettings)) {
      return storedSettings;
    }
    return this.buildDefaultSitePermissionSettings(normalizedOrigin, profileId);
  }

  getSitePermissionRule(settings: SitePermissionSettings, kind: SitePermissionKind): SitePermissionRule {
    if (kind === 'camera') {
      return settings.camera;
    }
    if (kind === 'microphone') {
      return settings.microphone;
    }
    if (kind === 'location') {
      return settings.location;
    }
    if (kind === 'sensor') {
      return settings.sensor;
    }
    return settings.clipboard;
  }

  getSitePermissionKindsLabel(kinds: SitePermissionKind[]): string {
    return this.capabilityCatalog.getPermissionKindsLabel(kinds);
  }

  stopActiveCameraCaptureFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    controllerAttached: boolean
  ): void {
    if (!controllerAttached) {
      return;
    }
    const controller = runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return;
    }
    try {
      controller.stopCamera();
    } catch (_error) {
    }
    try {
      controller.closeCamera();
    } catch (_error) {
    }
  }

  stopActiveMicrophoneCaptureFromLifecyclePort(
    runtimeLifecyclePort: BrowserRuntimeLifecyclePort,
    controllerAttached: boolean
  ): void {
    if (!controllerAttached) {
      return;
    }
    const controller = runtimeLifecyclePort.resolveActiveController();
    if (controller === undefined) {
      return;
    }
    try {
      controller.stopMicrophone();
    } catch (_error) {
    }
  }

  async requestAppPermissionsForKinds(
    context: common.UIAbilityContext,
    kinds: SitePermissionKind[]
  ): Promise<SystemPermissionGrantResult> {
    return this.systemPermissionService.requestAppPermissionsForKinds(context, kinds);
  }

  async requestAppPermissionSettingsForKinds(
    context: common.UIAbilityContext,
    kinds: SitePermissionKind[]
  ): Promise<SystemPermissionGrantResult> {
    return this.systemPermissionService.requestAppPermissionSettingsForKinds(context, kinds);
  }

  async persistPermissionRuleForOrigins(
    origins: string[],
    kinds: SitePermissionKind[],
    rule: SitePermissionRule,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): Promise<SitePermissionSettings> {
    let latestSettings: SitePermissionSettings = this.getEffectiveSitePermissionSettings(origins[0] ?? '', profileId, dataScope);
    for (let originIndex = 0; originIndex < origins.length; originIndex += 1) {
      const origin = this.normalizeOrigin(origins[originIndex]);
      if (origin.length === 0) {
        continue;
      }
      for (let kindIndex = 0; kindIndex < kinds.length; kindIndex += 1) {
        if (rule !== 'allow') {
          this.clearPermissionSessionGrants({
            origins: [origin],
            kinds: [kinds[kindIndex]],
            profileId: profileId,
            dataScope: dataScope
          });
        }
        if (this.profileBoundaryService.resolveSitePermissionScope({ profileId: profileId, dataScope: dataScope }) ===
          'incognito_session_only') {
          latestSettings = this.updateSessionPermissionRule(origin, kinds[kindIndex], rule, profileId);
        } else {
          latestSettings =
            await this.preferencesRepository.updateSitePermissionRule(origin, kinds[kindIndex], rule, profileId);
        }
      }
    }
    return latestSettings;
  }

  async persistPermissionDraftForOrigins(
    origins: string[],
    draft: SitePermissionDraft,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): Promise<SitePermissionSettings> {
    let latestSettings: SitePermissionSettings = this.getEffectiveSitePermissionSettings(origins[0] ?? '', profileId, dataScope);
    for (let originIndex = 0; originIndex < origins.length; originIndex += 1) {
      const origin = this.normalizeOrigin(origins[originIndex]);
      if (origin.length === 0) {
        continue;
      }
      if (this.profileBoundaryService.resolveSitePermissionScope({ profileId: profileId, dataScope: dataScope }) ===
        'incognito_session_only') {
        this.clearNonAllowDraftSessionGrants(origin, draft, profileId, dataScope);
        latestSettings = this.updateSessionPermissionDraft(origin, draft, profileId);
      } else {
        this.clearNonAllowDraftSessionGrants(origin, draft, profileId, dataScope);
        latestSettings = await this.preferencesRepository.updateSitePermissionRule(origin, 'camera', draft.camera, profileId);
        latestSettings =
          await this.preferencesRepository.updateSitePermissionRule(origin, 'microphone', draft.microphone, profileId);
        latestSettings =
          await this.preferencesRepository.updateSitePermissionRule(origin, 'location', draft.location, profileId);
        latestSettings =
          await this.preferencesRepository.updateSitePermissionRule(origin, 'sensor', draft.sensor, profileId);
        latestSettings =
          await this.preferencesRepository.updateSitePermissionRule(origin, 'clipboard', draft.clipboard, profileId);
      }
    }
    return latestSettings;
  }

  clearSessionSitePermissionSettings(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SitePermissionSessionCleanupResult {
    const before = this.sessionSitePermissionSettings.length;
    this.sessionSitePermissionSettings = this.sessionSitePermissionSettings.filter((settings: SitePermissionSettings) => {
      return settings.profileId !== profileId;
    });
    const after = this.sessionSitePermissionSettings.length;
    const removed = before - after;
    const onceRemoved = this.clearPermissionSessionGrants({
      profileId: profileId,
      dataScope: 'session_ephemeral'
    });
    return {
      profileId: profileId,
      removed: removed,
      onceRemoved: onceRemoved,
      before: before,
      after: after,
      summaryLine:
        `sessionPermissionCleanup profile=${profileId} removed=${removed} onceRemoved=${onceRemoved} before=${before} after=${after}`
    };
  }

  clearSessionSitePermissionSettingsForOrigins(
    origins: string[],
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SitePermissionSessionCleanupResult {
    const normalizedOrigins = origins
      .map((origin: string) => this.normalizeOrigin(origin))
      .filter((origin: string) => origin.length > 0);
    const before = this.sessionSitePermissionSettings.length;
    if (normalizedOrigins.length > 0) {
      this.sessionSitePermissionSettings = this.sessionSitePermissionSettings.filter((settings: SitePermissionSettings) => {
        if (settings.profileId !== profileId) {
          return true;
        }
        return normalizedOrigins.indexOf(settings.primaryOrigin) < 0;
      });
    }
    const after = this.sessionSitePermissionSettings.length;
    const removed = before - after;
    const onceRemoved = this.clearPermissionSessionGrants({
      origins: normalizedOrigins,
      profileId: profileId,
      dataScope: 'session_ephemeral'
    });
    return {
      profileId: profileId,
      removed: removed,
      onceRemoved: onceRemoved,
      before: before,
      after: after,
      summaryLine:
        `sessionPermissionOriginCleanup profile=${profileId} removed=${removed} onceRemoved=${onceRemoved} ` +
          `origins=${normalizedOrigins.length} before=${before} after=${after}`
    };
  }

  buildSessionSitePermissionSnapshot(
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID
  ): SitePermissionSessionSnapshot {
    const settings = this.sessionSitePermissionSettings.filter((item: SitePermissionSettings) => {
      return item.profileId === profileId;
    });
    let allowRuleCount = 0;
    let blockRuleCount = 0;
    settings.forEach((item: SitePermissionSettings) => {
      [item.camera, item.microphone, item.location, item.sensor, item.clipboard].forEach((rule: SitePermissionRule) => {
        if (rule === 'allow') {
          allowRuleCount += 1;
        } else if (rule === 'block') {
          blockRuleCount += 1;
        }
      });
    });
    const totalRuleCount = allowRuleCount + blockRuleCount;
    return {
      profileId: profileId,
      originCount: settings.length,
      allowRuleCount: allowRuleCount,
      blockRuleCount: blockRuleCount,
      totalRuleCount: totalRuleCount,
      summaryLine: `sessionPermissionSnapshot profile=${profileId} origins=${settings.length} ` +
        `allow=${allowRuleCount} block=${blockRuleCount} totalRules=${totalRuleCount}`
    };
  }

  acquirePermissionSession(): void {
    this.activePermissionSessionOwners += 1;
  }

  releasePermissionSession(): number {
    this.activePermissionSessionOwners = Math.max(0, this.activePermissionSessionOwners - 1);
    if (this.activePermissionSessionOwners > 0) {
      return 0;
    }
    return this.clearPermissionSessionGrants();
  }

  clearArkWebGeolocationPermissions(incognito: boolean): void {
    try {
      webview.GeolocationPermissions.deleteAllGeolocation(incognito);
    } catch (_error) {
    }
  }

  normalizeOrigin(origin: string): string {
    return this.siteIdentityService.resolve(origin).primaryOrigin;
  }

  shouldBlockSitePermission(settings: SitePermissionSettings, kinds: SitePermissionKind[]): boolean {
    return kinds.some((kind: SitePermissionKind) => this.getSitePermissionRule(settings, kind) === 'block');
  }

  shouldAllowSitePermission(settings: SitePermissionSettings, kinds: SitePermissionKind[]): boolean {
    return kinds.every((kind: SitePermissionKind) => this.getSitePermissionRule(settings, kind) === 'allow');
  }

  setPermissionAllowedForSessionForOrigins(
    origins: string[],
    kinds: SitePermissionKind[],
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): void {
    const cacheableKinds = kinds.filter((kind: SitePermissionKind) => this.canCachePermissionForSession(kind));
    if (cacheableKinds.length === 0) {
      return;
    }
    origins.forEach((origin: string) => {
      const normalizedOrigin = this.normalizeOrigin(origin);
      if (normalizedOrigin.length === 0) {
        return;
      }
      const settings = this.getEffectiveSitePermissionSettings(normalizedOrigin, profileId, dataScope);
      const grantKinds = cacheableKinds.filter((kind: SitePermissionKind) => {
        return this.getSitePermissionRule(settings, kind) !== 'block';
      });
      if (grantKinds.length === 0) {
        return;
      }
      this.clearPermissionSessionGrants({
        origins: [normalizedOrigin],
        kinds: grantKinds,
        profileId: profileId,
        dataScope: dataScope
      });
      const grants = grantKinds.map((kind: SitePermissionKind) => {
        return {
          origin: normalizedOrigin,
          kind: kind,
          profileId: profileId,
          dataScope: dataScope,
          createdAt: Date.now()
        } as SitePermissionSessionGrant;
      });
      this.permissionSessionGrants = this.permissionSessionGrants.concat(grants);
    });
  }

  isPermissionAllowedForSession(
    origin: string,
    kind: SitePermissionKind,
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): boolean {
    if (!this.canCachePermissionForSession(kind)) {
      return false;
    }
    const normalizedOrigin = this.normalizeOrigin(origin);
    if (normalizedOrigin.length === 0) {
      return false;
    }
    return this.permissionSessionGrants.some((grant: SitePermissionSessionGrant) => {
      return grant.origin === normalizedOrigin &&
        grant.kind === kind &&
        grant.profileId === profileId &&
        grant.dataScope === dataScope;
    });
  }

  arePermissionsAllowedForSession(
    origin: string,
    kinds: SitePermissionKind[],
    profileId: BrowserProfileId = DEFAULT_BROWSER_PROFILE_ID,
    dataScope: BrowserDataScope = 'profile_persistent'
  ): boolean {
    const cacheableKinds = kinds.filter((kind: SitePermissionKind) => this.canCachePermissionForSession(kind));
    if (cacheableKinds.length === 0 || cacheableKinds.length !== kinds.length) {
      return false;
    }
    return cacheableKinds.every((kind: SitePermissionKind) => {
      return this.isPermissionAllowedForSession(origin, kind, profileId, dataScope);
    });
  }

  clearPermissionSessionGrants(options: SitePermissionSessionClearOptions = {}): number {
    const normalizedOrigins = (options.origins ?? [])
      .map((origin: string) => this.normalizeOrigin(origin))
      .filter((origin: string) => origin.length > 0);
    const kinds = options.kinds ?? [];
    const before = this.permissionSessionGrants.length;
    this.permissionSessionGrants = this.permissionSessionGrants.filter((grant: SitePermissionSessionGrant) => {
      if (options.profileId !== undefined && grant.profileId !== options.profileId) {
        return true;
      }
      if (options.dataScope !== undefined && grant.dataScope !== options.dataScope) {
        return true;
      }
      if (normalizedOrigins.length > 0 && normalizedOrigins.indexOf(grant.origin) < 0) {
        return true;
      }
      if (kinds.length > 0 && kinds.indexOf(grant.kind) < 0) {
        return true;
      }
      return false;
    });
    return before - this.permissionSessionGrants.length;
  }

  private updateSessionPermissionRule(
    origin: string,
    kind: SitePermissionKind,
    rule: SitePermissionRule,
    profileId: BrowserProfileId
  ): SitePermissionSettings {
    const currentSettings = this.getEffectiveSitePermissionSettings(origin, profileId, 'session_ephemeral');
    const identity = this.siteIdentityService.resolve(origin);
    const nextSettings: SitePermissionSettings = {
      profileId: profileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      camera: kind === 'camera' ? rule : currentSettings.camera,
      microphone: kind === 'microphone' ? rule : currentSettings.microphone,
      location: kind === 'location' ? rule : currentSettings.location,
      sensor: kind === 'sensor' ? rule : currentSettings.sensor,
      clipboard: kind === 'clipboard' ? rule : currentSettings.clipboard,
      updatedAt: Date.now()
    };
    this.sessionSitePermissionSettings = this.sessionSitePermissionSettings.filter((settings: SitePermissionSettings) => {
      return settings.primaryOrigin !== identity.primaryOrigin || settings.profileId !== profileId;
    });
    if (!this.isDefaultSitePermissionSettings(nextSettings)) {
      this.sessionSitePermissionSettings = this.sessionSitePermissionSettings.concat([nextSettings]);
    }
    return nextSettings;
  }

  private updateSessionPermissionDraft(
    origin: string,
    draft: SitePermissionDraft,
    profileId: BrowserProfileId
  ): SitePermissionSettings {
    const identity = this.siteIdentityService.resolve(origin);
    const nextSettings: SitePermissionSettings = {
      profileId: profileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      camera: draft.camera,
      microphone: draft.microphone,
      location: draft.location,
      sensor: draft.sensor,
      clipboard: draft.clipboard,
      updatedAt: Date.now()
    };
    this.sessionSitePermissionSettings = this.sessionSitePermissionSettings.filter((settings: SitePermissionSettings) => {
      return settings.primaryOrigin !== identity.primaryOrigin || settings.profileId !== profileId;
    });
    if (!this.isDefaultSitePermissionSettings(nextSettings)) {
      this.sessionSitePermissionSettings = this.sessionSitePermissionSettings.concat([nextSettings]);
    }
    return nextSettings;
  }

  private buildDefaultSitePermissionSettings(origin: string, profileId: BrowserProfileId): SitePermissionSettings {
    const defaults: SitePermissionDefaultSettings = this.preferencesRepository.getPreferences().sitePermissionDefaults;
    const identity = this.siteIdentityService.resolve(origin);
    return {
      profileId: profileId,
      origin: identity.primaryOrigin,
      siteKey: identity.siteKey,
      displayHost: identity.displayHost,
      primaryOrigin: identity.primaryOrigin,
      camera: defaults.camera,
      microphone: defaults.microphone,
      location: defaults.location,
      sensor: defaults.sensor,
      clipboard: defaults.clipboard,
      updatedAt: 0
    };
  }

  private hasNonDefaultRule(settings: SitePermissionSettings): boolean {
    const defaults: SitePermissionDefaultSettings = this.preferencesRepository.getPreferences().sitePermissionDefaults;
    return settings.camera !== defaults.camera || settings.microphone !== defaults.microphone ||
      settings.location !== defaults.location || settings.sensor !== defaults.sensor ||
      settings.clipboard !== defaults.clipboard;
  }

  private isDefaultSitePermissionSettings(settings: SitePermissionSettings): boolean {
    return settings.camera === 'ask' && settings.microphone === 'ask' && settings.location === 'ask' &&
      settings.sensor === 'ask' && settings.clipboard === 'ask';
  }

  private clearNonAllowDraftSessionGrants(
    origin: string,
    draft: SitePermissionDraft,
    profileId: BrowserProfileId,
    dataScope: BrowserDataScope
  ): void {
    const kinds: SitePermissionKind[] = [];
    if (draft.camera !== 'allow') {
      kinds.push('camera');
    }
    if (draft.microphone !== 'allow') {
      kinds.push('microphone');
    }
    if (draft.location !== 'allow') {
      kinds.push('location');
    }
    if (draft.sensor !== 'allow') {
      kinds.push('sensor');
    }
    if (draft.clipboard !== 'allow') {
      kinds.push('clipboard');
    }
    if (kinds.length === 0) {
      return;
    }
    this.clearPermissionSessionGrants({
      origins: [origin],
      kinds: kinds,
      profileId: profileId,
      dataScope: dataScope
    });
  }

  private canCachePermissionForSession(_kind: SitePermissionKind): boolean {
    return true;
  }

  resolveSitePermissionKinds(resources: string[]): SitePermissionKind[] {
    return this.capabilityCatalog.resolveSitePermissionKinds(resources);
  }
}
