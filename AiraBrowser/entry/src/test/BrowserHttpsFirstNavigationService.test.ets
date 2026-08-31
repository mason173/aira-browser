import { describe, expect, it } from '@ohos/hypium';
import { BrowserDataBoundaryInput, BrowserProfileId } from '../main/ets/common/models/BrowserModels';
import { BrowserWebSecuritySettings } from '../main/ets/common/models/BrowserWebSecurityModels';
import {
  BrowserHttpsFirstHttpSessionGrantCodec,
  BrowserWebSecuritySettingsRepository
} from '../main/ets/data/preferences/BrowserWebSecuritySettingsRepository';
import {
  BrowserHttpsFirstNavigationService
} from '../main/ets/services/web/BrowserHttpsFirstNavigationService';
import {
  BrowserSslDecisionCacheController,
  BrowserSslDecisionCacheRuntime
} from '../main/ets/services/web/BrowserSslDecisionCacheRuntime';

interface InMemoryHttpsFirstDeclinedRetryRecord {
  tabId: string;
  profileId: BrowserProfileId;
  originalUrl: string;
  upgradedUrl: string;
  source: string;
  expiresAt: number;
}

interface InMemoryHttpsFirstHttpSessionGrantRecord {
  tabId: string;
  profileId: BrowserProfileId;
  anchorHost: string;
  effectivePort: number;
  expiresAt: number;
}

interface InMemoryHttpsFirstHttpSessionGrantPayload {
  version: number;
  records: InMemoryHttpsFirstHttpSessionGrantRecord[];
}

class InMemoryBrowserWebSecuritySettingsRepository extends BrowserWebSecuritySettingsRepository {
  private httpsFirstEnabled: boolean;
  rememberedSiteKey: string = '';
  rememberedSiteExpiresAt: number = 0;
  persistedRetryTabId: string = '';
  persistedRetryProfileId: BrowserProfileId = 'profile-main';
  persistedRetryOriginalUrl: string = '';
  persistedRetryUpgradedUrl: string = '';
  persistedRetrySource: string = '';
  persistedRetryExpiresAt: number = 0;
  persistedGrantTabId: string = '';
  persistedGrantProfileId: BrowserProfileId = 'profile-main';
  persistedGrantAnchorHost: string = '';
  persistedGrantEffectivePort: number = 0;
  persistedGrantExpiresAt: number = 0;

  constructor(httpsFirstEnabled: boolean) {
    super();
    this.httpsFirstEnabled = httpsFirstEnabled;
  }

  getSettings(): BrowserWebSecuritySettings {
    return {
      httpsFirstEnabled: this.httpsFirstEnabled,
      safeBrowsingEnabled: true,
      javaScriptEnabled: true
    };
  }

  setHttpsFirstEnabled(enabled: boolean): void {
    this.httpsFirstEnabled = enabled;
  }

  isHttpFallbackSiteAllowed(
    _profileId: BrowserProfileId,
    siteKey: string,
    now: number = Date.now()
  ): boolean {
    return this.readHttpFallbackSiteExpiration(_profileId, siteKey, now) > 0;
  }

  readHttpFallbackSiteExpiration(
    _profileId: BrowserProfileId,
    siteKey: string,
    now: number = Date.now()
  ): number {
    return siteKey === this.rememberedSiteKey && this.rememberedSiteExpiresAt > now
      ? this.rememberedSiteExpiresAt
      : 0;
  }

  rememberHttpFallbackSite(_profileId: BrowserProfileId, siteKey: string, expiresAt: number): void {
    this.rememberedSiteKey = siteKey;
    this.rememberedSiteExpiresAt = expiresAt;
  }

  rememberHttpsFirstHttpSessionGrant(
    tabId: string,
    profileId: BrowserProfileId,
    anchorHost: string,
    effectivePort: number,
    expiresAt: number
  ): void {
    this.persistedGrantTabId = tabId;
    this.persistedGrantProfileId = profileId;
    this.persistedGrantAnchorHost = anchorHost;
    this.persistedGrantEffectivePort = effectivePort;
    this.persistedGrantExpiresAt = expiresAt;
  }

  readHttpsFirstHttpSessionGrant(
    tabId: string,
    now: number = Date.now()
  ): InMemoryHttpsFirstHttpSessionGrantRecord | undefined {
    if (tabId !== this.persistedGrantTabId || this.persistedGrantExpiresAt <= now) {
      if (tabId === this.persistedGrantTabId) {
        this.clearHttpsFirstHttpSessionGrant(tabId);
      }
      return undefined;
    }
    return {
      tabId: this.persistedGrantTabId,
      profileId: this.persistedGrantProfileId,
      anchorHost: this.persistedGrantAnchorHost,
      effectivePort: this.persistedGrantEffectivePort,
      expiresAt: this.persistedGrantExpiresAt
    };
  }

  clearHttpsFirstHttpSessionGrant(tabId: string): void {
    if (tabId !== this.persistedGrantTabId) {
      return;
    }
    this.persistedGrantTabId = '';
    this.persistedGrantAnchorHost = '';
    this.persistedGrantEffectivePort = 0;
    this.persistedGrantExpiresAt = 0;
  }

  rememberHttpsFirstDeclinedRetry(
    tabId: string,
    profileId: BrowserProfileId,
    originalUrl: string,
    upgradedUrl: string,
    source: string,
    expiresAt: number
  ): void {
    this.persistedRetryTabId = tabId;
    this.persistedRetryProfileId = profileId;
    this.persistedRetryOriginalUrl = originalUrl;
    this.persistedRetryUpgradedUrl = upgradedUrl;
    this.persistedRetrySource = source;
    this.persistedRetryExpiresAt = expiresAt;
  }

  readHttpsFirstDeclinedRetry(tabId: string): InMemoryHttpsFirstDeclinedRetryRecord | undefined {
    if (tabId !== this.persistedRetryTabId || this.persistedRetryExpiresAt <= Date.now()) {
      return undefined;
    }
    return {
      tabId: this.persistedRetryTabId,
      profileId: this.persistedRetryProfileId,
      originalUrl: this.persistedRetryOriginalUrl,
      upgradedUrl: this.persistedRetryUpgradedUrl,
      source: this.persistedRetrySource,
      expiresAt: this.persistedRetryExpiresAt
    };
  }

  clearHttpsFirstDeclinedRetry(tabId: string): void {
    if (tabId !== this.persistedRetryTabId) {
      return;
    }
    this.persistedRetryTabId = '';
    this.persistedRetryOriginalUrl = '';
    this.persistedRetryUpgradedUrl = '';
    this.persistedRetrySource = '';
    this.persistedRetryExpiresAt = 0;
  }

  async clearHttpsFirstSiteDecisions(_profileId: BrowserProfileId): Promise<void> {
    this.rememberedSiteKey = '';
    this.rememberedSiteExpiresAt = 0;
    this.persistedRetryTabId = '';
    this.persistedRetryOriginalUrl = '';
    this.persistedRetryUpgradedUrl = '';
    this.persistedRetrySource = '';
    this.persistedRetryExpiresAt = 0;
    this.persistedGrantTabId = '';
    this.persistedGrantAnchorHost = '';
    this.persistedGrantEffectivePort = 0;
    this.persistedGrantExpiresAt = 0;
  }
}

class InMemorySslDecisionCacheController implements BrowserSslDecisionCacheController {
  clearCount: number = 0;
  rejectClear: boolean = false;

  clearSslCache(): void {
    if (this.rejectClear) {
      throw new Error('controller detached');
    }
    this.clearCount += 1;
  }
}

export default function browserHttpsFirstNavigationServiceTest(): void {
  describe('BrowserHttpsFirstNavigationService', () => {
    it('normalizes expired persisted HTTP grants into a rewriteable storage payload', 0, () => {
      const codec = new BrowserHttpsFirstHttpSessionGrantCodec();
      const now = 1000;
      const payload: InMemoryHttpsFirstHttpSessionGrantPayload = {
        version: 1,
        records: [
          {
            tabId: 'tab-expired-storage',
            profileId: 'profile-main',
            anchorHost: 'expired.example',
            effectivePort: 80,
            expiresAt: now
          },
          {
            tabId: 'tab-valid-storage',
            profileId: 'profile-main',
            anchorHost: 'Valid.Example',
            effectivePort: 80,
            expiresAt: now + 1000
          }
        ]
      };
      const storage = codec.decodeStorage(JSON.stringify(payload), now);

      expect(storage.requiresRewrite).assertTrue();
      expect(storage.records.length).assertEqual(1);
      expect(storage.records[0].tabId).assertEqual('tab-valid-storage');
      expect(storage.records[0].anchorHost).assertEqual('valid.example');
      expect(codec.decodeStorage(storage.serialized, now).requiresRewrite).assertFalse();

      const malformedStorage = codec.decodeStorage('{"version":1,"records":[null]}', now);
      expect(malformedStorage.requiresRewrite).assertTrue();
      expect(malformedStorage.records.length).assertEqual(0);
    });

    it('requires one HTTP confirmation for a strict protocol failure across both ArkWeb callbacks', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      let executedFallbackUrl: string = '';
      const registered = service.registerBrowserGeneratedUpgrade(
        'tab-1',
        'https://121.43.251.222:5244',
        'http://121.43.251.222:5244',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, fallbackUrl: string): boolean => {
          executedFallbackUrl = fallbackUrl;
          return true;
        }
      );
      service.bindNavigationAttempt('tab-1', 'https://121.43.251.222:5244/', 101);

      const resourceDecision = service.resolveResourceFailureDecision('tab-1', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 101
      });
      const duplicateSslDecision = service.resolveSslFailureDecision('tab-1', {
        requestUrl: 'https://121.43.251.222:5244',
        isMainFrame: true,
        isFatalError: true,
        navigationId: 101
      });

      expect(registered).assertTrue();
      expect(resourceDecision.action).assertEqual('require_http_confirmation');
      expect(resourceDecision.delivery).assertEqual('apply');
      expect(resourceDecision.fallbackUrl).assertEqual('http://121.43.251.222:5244');
      expect(duplicateSslDecision.action).assertEqual('require_http_confirmation');
      expect(duplicateSslDecision.delivery).assertEqual('suppress_duplicate');
      expect(duplicateSslDecision.attemptId).assertEqual(resourceDecision.attemptId);
      service.finishNavigation('tab-1', 'https://121.43.251.222:5244/');
      const prepared = service.prepareFallback('tab-1', resourceDecision.attemptId);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(service.executePreparedFallback(prepared)).assertTrue();
      }
      expect(executedFallbackUrl).assertEqual('http://121.43.251.222:5244');
    });

    it('automatically falls back for a compatibility upgrade when HTTPS-First is disabled', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(false)
      );
      service.registerBrowserGeneratedUpgrade(
        'tab-2',
        'https://legacy.example',
        'http://legacy.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-2', 'https://legacy.example/', 201);

      const decision = service.resolveResourceFailureDecision('tab-2', {
        requestUrl: 'https://legacy.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 201
      });

      expect(decision.action).assertEqual('automatic_http_fallback');
      expect(decision.delivery).assertEqual('apply');
    });

    it('never synthesizes HTTP fallback provenance for an explicit HTTPS failure', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );

      const decision = service.resolveResourceFailureDecision('tab-explicit', {
        requestUrl: 'https://secure.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 202
      });

      expect(decision.action).assertEqual('normal_failure');
      expect(decision.fallbackUrl).assertEqual('');
    });

    it('rejects a stale confirmation after a newer upgrade replaces the tab attempt', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      service.registerBrowserGeneratedUpgrade(
        'tab-3',
        'https://first.example',
        'http://first.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-3', 'https://first.example/', 301);
      const firstDecision = service.resolveResourceFailureDecision('tab-3', {
        requestUrl: 'https://first.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 301
      });
      service.registerBrowserGeneratedUpgrade(
        'tab-3',
        'https://second.example',
        'http://second.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-3', 'https://second.example/', 302);

      expect(service.declineFallback('tab-3', firstDecision.attemptId)).assertFalse();
      expect(service.prepareFallback('tab-3', firstDecision.attemptId) === undefined).assertTrue();
    });

    it('keeps an attempt available when a non-fallback resource error precedes the SSL callback', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      service.registerBrowserGeneratedUpgrade(
        'tab-4',
        'https://ordered.example',
        'http://ordered.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-4', 'https://ordered.example/', 401);

      const resourceDecision = service.resolveResourceFailureDecision('tab-4', {
        requestUrl: 'https://ordered.example/',
        isMainFrame: true,
        errorCode: -1,
        navigationId: 401
      });
      service.finishNavigation('tab-4', 'https://ordered.example/');
      const sslDecision = service.resolveSslFailureDecision('tab-4', {
        requestUrl: 'https://ordered.example/',
        isMainFrame: true,
        isFatalError: false,
        navigationId: 401
      });

      expect(resourceDecision.action).assertEqual('normal_failure');
      expect(sslDecision.action).assertEqual('require_http_confirmation');
      expect(sslDecision.delivery).assertEqual('apply');
    });

    it('rejects a failure carrying an explicitly stale navigation id', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      service.registerBrowserGeneratedUpgrade(
        'tab-5',
        'https://same.example',
        'http://same.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-5', 'https://same.example/', 501);
      service.registerBrowserGeneratedUpgrade(
        'tab-5',
        'https://same.example',
        'http://same.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-5', 'https://same.example/', 502);

      const staleDecision = service.resolveResourceFailureDecision('tab-5', {
        requestUrl: 'https://same.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 501
      });
      const currentDecision = service.resolveResourceFailureDecision('tab-5', {
        requestUrl: 'https://same.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 502
      });

      expect(staleDecision.action).assertEqual('normal_failure');
      expect(currentDecision.action).assertEqual('require_http_confirmation');
      expect(currentDecision.delivery).assertEqual('apply');
    });

    it('rearms the declined HTTP fallback provenance when the user retries the failed HTTPS URL', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      let executedFallbackUrl: string = '';
      service.registerBrowserGeneratedUpgrade(
        'tab-retry',
        'https://121.43.251.222:5244',
        'http://121.43.251.222:5244',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, fallbackUrl: string): boolean => {
          executedFallbackUrl = fallbackUrl;
          return true;
        }
      );
      service.bindNavigationAttempt('tab-retry', 'https://121.43.251.222:5244/', 601);
      const firstDecision = service.resolveResourceFailureDecision('tab-retry', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 601
      });

      expect(service.declineFallback('tab-retry', firstDecision.attemptId)).assertTrue();
      service.finishNavigation('tab-retry', 'https://121.43.251.222:5244/');
      expect(service.prepareFallback('tab-retry', firstDecision.attemptId) === undefined).assertTrue();
      expect(service.rearmDeclinedRetry('tab-retry', 'https://121.43.251.222:5244/')).assertTrue();
      service.bindNavigationAttempt('tab-retry', 'https://121.43.251.222:5244/', 602);
      const retryDecision = service.resolveResourceFailureDecision('tab-retry', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 602
      });

      expect(retryDecision.action).assertEqual('require_http_confirmation');
      expect(retryDecision.delivery).assertEqual('apply');
      expect(retryDecision.attemptId === firstDecision.attemptId).assertFalse();
      expect(service.prepareFallback('tab-retry', firstDecision.attemptId) === undefined).assertTrue();
      const prepared = service.prepareFallback('tab-retry', retryDecision.attemptId, true);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(service.executePreparedFallback(prepared)).assertTrue();
      }
      expect(executedFallbackUrl).assertEqual('http://121.43.251.222:5244');
      expect(repository.rememberedSiteKey).assertEqual('121.43.251.222|5244');
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      expect(service.beginMainFrameNavigation('tab-retry', 'http://121.43.251.222:5244/', boundary)).assertTrue();
      service.finishNavigation('tab-retry', 'http://121.43.251.222:5244/');
      expect(service.beginMainFrameNavigation('tab-retry', 'http://121.43.251.222:5244/', boundary)).assertTrue();
    });

    it('keeps HTTPS retry provenance when the local error document finishes before the user cancels', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      service.registerBrowserGeneratedUpgrade(
        'tab-error-document-retry',
        'https://121.43.251.222:5244',
        'http://121.43.251.222:5244',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-error-document-retry', 'https://121.43.251.222:5244/', 651);
      const firstDecision = service.resolveResourceFailureDecision('tab-error-document-retry', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 651
      });

      service.beginMainFrameNavigation(
        'tab-error-document-retry',
        'data:text/html;charset=utf-8,error-document',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' }
      );
      service.finishNavigation('tab-error-document-retry', 'data:text/html;charset=utf-8,error-document');

      expect(service.declineFallback('tab-error-document-retry', firstDecision.attemptId)).assertTrue();
      expect(service.rearmDeclinedRetry(
        'tab-error-document-retry',
        'https://121.43.251.222:5244/'
      )).assertTrue();
      service.bindNavigationAttempt('tab-error-document-retry', 'https://121.43.251.222:5244/', 652);
      const retryDecision = service.resolveResourceFailureDecision('tab-error-document-retry', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 652
      });
      expect(retryDecision.action).assertEqual('require_http_confirmation');
      expect(retryDecision.delivery).assertEqual('apply');
    });

    it('keeps one confirmed HTTP site family usable within the current tab', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      service.registerBrowserGeneratedUpgrade(
        'tab-http-family',
        'https://shengxuxu.info/',
        'http://shengxuxu.info/',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-http-family', 'https://shengxuxu.info/', 671);
      const decision = service.resolveSslFailureDecision('tab-http-family', {
        requestUrl: 'https://shengxuxu.info/',
        isMainFrame: true,
        isFatalError: false,
        navigationId: 671
      });
      const prepared = service.prepareFallback('tab-http-family', decision.attemptId, true);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(service.executePreparedFallback(prepared)).assertTrue();
      }

      expect(service.beginMainFrameNavigation('tab-http-family', 'http://shengxuxu.info/', boundary)).assertTrue();
      service.finishNavigation('tab-http-family', 'http://shengxuxu.info/');
      expect(service.beginMainFrameNavigation('tab-http-family', 'http://www.shengxuxu.info/', boundary)).assertTrue();
      service.finishNavigation('tab-http-family', 'http://www.shengxuxu.info/');
      expect(service.beginMainFrameNavigation(
        'tab-http-family',
        'http://m.shengxuxu.info/87687/',
        boundary
      )).assertTrue();
      expect(service.beginMainFrameNavigation(
        'tab-http-family',
        'http://notshengxuxu.info/',
        boundary
      )).assertFalse();
      expect(service.beginMainFrameNavigation(
        'tab-http-family',
        'http://m.shengxuxu.info/87687/',
        boundary
      )).assertFalse();

      service.registerBrowserGeneratedUpgrade(
        'tab-http-family-port',
        'https://shengxuxu.info/',
        'http://shengxuxu.info/',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-http-family-port', 'https://shengxuxu.info/', 672);
      const portDecision = service.resolveSslFailureDecision('tab-http-family-port', {
        requestUrl: 'https://shengxuxu.info/',
        isMainFrame: true,
        isFatalError: false,
        navigationId: 672
      });
      const portPrepared = service.prepareFallback('tab-http-family-port', portDecision.attemptId, true);
      expect(portPrepared !== undefined).assertTrue();
      if (portPrepared !== undefined) {
        expect(service.executePreparedFallback(portPrepared)).assertTrue();
      }
      expect(service.beginMainFrameNavigation(
        'tab-http-family-port',
        'http://m.shengxuxu.info:8080/',
        boundary
      )).assertFalse();
    });

    it('seeds a remembered HTTP site family before a programmatic root load redirects to www', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      repository.rememberHttpFallbackSite(
        'profile-main',
        'shengxuxu.info|80',
        Date.now() + 15 * 24 * 60 * 60 * 1000
      );
      const service = new BrowserHttpsFirstNavigationService(repository);
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      const rememberedUrl = service.resolveRememberedHttpFallbackUrl('http://shengxuxu.info/', boundary);

      expect(rememberedUrl).assertEqual('http://shengxuxu.info/');
      expect(service.prepareProgrammaticNavigation(
        'tab-remembered-programmatic',
        rememberedUrl,
        '',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      )).assertTrue();
      expect(service.beginMainFrameNavigation(
        'tab-remembered-programmatic',
        'http://www.shengxuxu.info/',
        boundary
      )).assertTrue();
    });

    it('restores a confirmed HTTP site family for the same tab after process recreation', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      const firstService = new BrowserHttpsFirstNavigationService(repository);
      firstService.registerBrowserGeneratedUpgrade(
        'tab-http-family-restart',
        'https://shengxuxu.info/',
        'http://shengxuxu.info/',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      firstService.bindNavigationAttempt('tab-http-family-restart', 'https://shengxuxu.info/', 675);
      const decision = firstService.resolveSslFailureDecision('tab-http-family-restart', {
        requestUrl: 'https://shengxuxu.info/',
        isMainFrame: true,
        isFatalError: false,
        navigationId: 675
      });
      const prepared = firstService.prepareFallback('tab-http-family-restart', decision.attemptId, true);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(firstService.executePreparedFallback(prepared)).assertTrue();
      }
      expect(firstService.beginMainFrameNavigation(
        'tab-http-family-restart',
        'http://m.shengxuxu.info/',
        boundary
      )).assertTrue();

      const restartedService = new BrowserHttpsFirstNavigationService(repository);

      expect(restartedService.prepareProgrammaticNavigation(
        'tab-http-family-restart',
        'http://m.shengxuxu.info/',
        '',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      )).assertTrue();
    });

    it('does not let another tab consume a persisted HTTP site-family grant', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const expiresAt = Date.now() + 15 * 24 * 60 * 60 * 1000;
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      repository.rememberHttpFallbackSite('profile-main', 'shengxuxu.info|80', expiresAt);
      repository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-owner',
        'profile-main',
        'shengxuxu.info',
        80,
        expiresAt
      );
      const restartedService = new BrowserHttpsFirstNavigationService(repository);

      expect(restartedService.beginMainFrameNavigation(
        'tab-http-other',
        'http://m.shengxuxu.info/',
        boundary
      )).assertFalse();
      expect(repository.persistedGrantTabId).assertEqual('tab-http-owner');
      expect(restartedService.beginMainFrameNavigation(
        'tab-http-owner',
        'http://m.shengxuxu.info/',
        boundary
      )).assertTrue();
    });

    it('rejects a persisted HTTP site-family grant in a private boundary', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const expiresAt = Date.now() + 15 * 24 * 60 * 60 * 1000;
      repository.rememberHttpFallbackSite('profile-main', 'shengxuxu.info|80', expiresAt);
      repository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-boundary',
        'profile-main',
        'shengxuxu.info',
        80,
        expiresAt
      );
      const restartedService = new BrowserHttpsFirstNavigationService(repository);

      expect(restartedService.beginMainFrameNavigation(
        'tab-http-boundary',
        'http://m.shengxuxu.info/',
        { profileId: 'profile-main', privacyMode: 'private', dataScope: 'session_ephemeral' }
      )).assertFalse();
      expect(repository.persistedGrantTabId).assertEqual('');
    });

    it('rejects a persisted HTTP site-family grant in a regular ephemeral data scope', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const expiresAt = Date.now() + 15 * 24 * 60 * 60 * 1000;
      repository.rememberHttpFallbackSite('profile-main', 'shengxuxu.info|80', expiresAt);
      repository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-ephemeral',
        'profile-main',
        'shengxuxu.info',
        80,
        expiresAt
      );
      const restartedService = new BrowserHttpsFirstNavigationService(repository);

      expect(restartedService.beginMainFrameNavigation(
        'tab-http-ephemeral',
        'http://m.shengxuxu.info/',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'session_ephemeral' }
      )).assertFalse();
      expect(repository.persistedGrantTabId).assertEqual('');
    });

    it('rejects expired or orphaned persisted HTTP site-family grants', 0, () => {
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      const expiredRepository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      expiredRepository.rememberHttpFallbackSite(
        'profile-main',
        'shengxuxu.info|80',
        Date.now() + 15 * 24 * 60 * 60 * 1000
      );
      expiredRepository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-expired',
        'profile-main',
        'shengxuxu.info',
        80,
        Date.now() - 1
      );
      const expiredService = new BrowserHttpsFirstNavigationService(expiredRepository);

      expect(expiredService.beginMainFrameNavigation(
        'tab-http-expired',
        'http://m.shengxuxu.info/',
        boundary
      )).assertFalse();
      expect(expiredRepository.persistedGrantTabId).assertEqual('');

      const orphanedRepository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      orphanedRepository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-orphaned',
        'profile-main',
        'shengxuxu.info',
        80,
        Date.now() + 15 * 24 * 60 * 60 * 1000
      );
      const orphanedService = new BrowserHttpsFirstNavigationService(orphanedRepository);

      expect(orphanedService.beginMainFrameNavigation(
        'tab-http-orphaned',
        'http://m.shengxuxu.info/',
        boundary
      )).assertFalse();
      expect(orphanedRepository.persistedGrantTabId).assertEqual('');
    });

    it('clears a persisted HTTP site-family grant on family exit or port mismatch', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const expiresAt = Date.now() + 15 * 24 * 60 * 60 * 1000;
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      repository.rememberHttpFallbackSite('profile-main', 'shengxuxu.info|80', expiresAt);
      repository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-exit',
        'profile-main',
        'shengxuxu.info',
        80,
        expiresAt
      );
      const familyExitService = new BrowserHttpsFirstNavigationService(repository);

      expect(familyExitService.beginMainFrameNavigation(
        'tab-http-exit',
        'http://example.com/',
        boundary
      )).assertFalse();
      expect(repository.persistedGrantTabId).assertEqual('');

      repository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-port-exit',
        'profile-main',
        'shengxuxu.info',
        80,
        expiresAt
      );
      const portExitService = new BrowserHttpsFirstNavigationService(repository);

      expect(portExitService.beginMainFrameNavigation(
        'tab-http-port-exit',
        'http://m.shengxuxu.info:8080/',
        boundary
      )).assertFalse();
      expect(repository.persistedGrantTabId).assertEqual('');
    });

    it('clears a persisted HTTP site-family grant when its tab closes', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const expiresAt = Date.now() + 15 * 24 * 60 * 60 * 1000;
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      repository.rememberHttpFallbackSite('profile-main', 'shengxuxu.info|80', expiresAt);
      repository.rememberHttpsFirstHttpSessionGrant(
        'tab-http-close',
        'profile-main',
        'shengxuxu.info',
        80,
        expiresAt
      );
      const service = new BrowserHttpsFirstNavigationService(repository);

      service.clearTab('tab-http-close');

      expect(repository.persistedGrantTabId).assertEqual('');
      expect(new BrowserHttpsFirstNavigationService(repository).beginMainFrameNavigation(
        'tab-http-close',
        'http://m.shengxuxu.info/',
        boundary
      )).assertFalse();
    });

    it('does not persist a private HTTP site-family grant across process recreation', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'private',
        dataScope: 'session_ephemeral'
      };
      const firstService = new BrowserHttpsFirstNavigationService(repository);
      firstService.registerBrowserGeneratedUpgrade(
        'tab-private-http-restart',
        'https://private-restart.example/',
        'http://private-restart.example/',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      firstService.bindNavigationAttempt('tab-private-http-restart', 'https://private-restart.example/', 677);
      const decision = firstService.resolveSslFailureDecision('tab-private-http-restart', {
        requestUrl: 'https://private-restart.example/',
        isMainFrame: true,
        isFatalError: false,
        navigationId: 677
      });
      const prepared = firstService.prepareFallback('tab-private-http-restart', decision.attemptId, true);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(firstService.executePreparedFallback(prepared)).assertTrue();
      }
      expect(repository.persistedGrantTabId).assertEqual('');

      expect(new BrowserHttpsFirstNavigationService(repository).beginMainFrameNavigation(
        'tab-private-http-restart',
        'http://private-restart.example/',
        boundary
      )).assertFalse();
    });

    it('defers SSL decision-cache clearing until an attached controller is available', 0, () => {
      const runtime = new BrowserSslDecisionCacheRuntime();
      const detachedController = new InMemorySslDecisionCacheController();
      detachedController.rejectClear = true;
      const attachedController = new InMemorySslDecisionCacheController();

      expect(runtime.requestClear()).assertEqual('deferred');
      expect(runtime.isClearPending()).assertTrue();
      expect(runtime.handleControllerAttached(detachedController)).assertEqual('deferred');
      expect(runtime.isClearPending()).assertTrue();
      expect(runtime.handleControllerAttached(attachedController)).assertEqual('applied');
      expect(runtime.isClearPending()).assertFalse();
      expect(attachedController.clearCount).assertEqual(1);
      expect(runtime.requestClear()).assertEqual('applied');
      expect(attachedController.clearCount).assertEqual(2);
    });

    it('clears remembered and current-tab HTTP decisions with browsing site permissions', 0, async () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'regular',
        dataScope: 'profile_persistent'
      };
      service.registerBrowserGeneratedUpgrade(
        'tab-clear-http',
        'https://clear-http.example/',
        'http://clear-http.example/',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-clear-http', 'https://clear-http.example/', 676);
      const decision = service.resolveSslFailureDecision('tab-clear-http', {
        requestUrl: 'https://clear-http.example/',
        isMainFrame: true,
        isFatalError: false,
        navigationId: 676
      });
      const prepared = service.prepareFallback('tab-clear-http', decision.attemptId, true);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(service.executePreparedFallback(prepared)).assertTrue();
      }
      expect(service.beginMainFrameNavigation('tab-clear-http', 'http://clear-http.example/', boundary)).assertTrue();

      await service.clearSiteDecisions(boundary);

      expect(repository.rememberedSiteKey).assertEqual('');
      expect(repository.persistedGrantTabId).assertEqual('');
      expect(service.beginMainFrameNavigation(
        'tab-clear-http',
        'http://clear-http.example/',
        boundary
      )).assertFalse();
      expect(new BrowserHttpsFirstNavigationService(repository).beginMainFrameNavigation(
        'tab-clear-http',
        'http://clear-http.example/',
        boundary
      )).assertFalse();
    });

    it('restores a regular declined retry after the service is recreated', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const firstService = new BrowserHttpsFirstNavigationService(repository);
      firstService.registerBrowserGeneratedUpgrade(
        'tab-process-restart',
        'https://121.43.251.222:5244',
        'http://121.43.251.222:5244',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      firstService.bindNavigationAttempt('tab-process-restart', 'https://121.43.251.222:5244/', 681);
      const firstDecision = firstService.resolveResourceFailureDecision('tab-process-restart', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 681
      });
      expect(firstService.declineFallback('tab-process-restart', firstDecision.attemptId)).assertTrue();

      const restartedService = new BrowserHttpsFirstNavigationService(repository);
      expect(restartedService.rearmDeclinedRetry(
        'tab-process-restart',
        'https://121.43.251.222:5244/'
      )).assertTrue();
      restartedService.attachFallbackExecutor(
        'tab-process-restart',
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      restartedService.bindNavigationAttempt('tab-process-restart', 'https://121.43.251.222:5244/', 682);
      const retryDecision = restartedService.resolveResourceFailureDecision('tab-process-restart', {
        requestUrl: 'https://121.43.251.222:5244/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 682
      });

      expect(retryDecision.action).assertEqual('require_http_confirmation');
      expect(retryDecision.delivery).assertEqual('apply');
    });

    it('does not persist a private declined retry across service recreation', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const firstService = new BrowserHttpsFirstNavigationService(repository);
      firstService.registerBrowserGeneratedUpgrade(
        'tab-private-restart',
        'https://private-restart.example',
        'http://private-restart.example',
        { profileId: 'profile-main', privacyMode: 'private', dataScope: 'session_ephemeral' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      firstService.bindNavigationAttempt('tab-private-restart', 'https://private-restart.example/', 691);
      const decision = firstService.resolveResourceFailureDecision('tab-private-restart', {
        requestUrl: 'https://private-restart.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 691
      });
      expect(firstService.declineFallback('tab-private-restart', decision.attemptId)).assertTrue();
      expect(repository.persistedRetryTabId).assertEqual('');

      const restartedService = new BrowserHttpsFirstNavigationService(repository);
      expect(restartedService.rearmDeclinedRetry(
        'tab-private-restart',
        'https://private-restart.example/'
      )).assertFalse();
    });

    it('allocates a fresh attempt for every repeated cancel and retry cycle', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      service.registerBrowserGeneratedUpgrade(
        'tab-repeat',
        'https://repeat.example',
        'http://repeat.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-repeat', 'https://repeat.example/', 701);
      const first = service.resolveResourceFailureDecision('tab-repeat', {
        requestUrl: 'https://repeat.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 701
      });
      expect(service.declineFallback('tab-repeat', first.attemptId)).assertTrue();
      expect(service.rearmDeclinedRetry('tab-repeat', 'https://repeat.example/')).assertTrue();
      service.bindNavigationAttempt('tab-repeat', 'https://repeat.example/', 702);
      const second = service.resolveResourceFailureDecision('tab-repeat', {
        requestUrl: 'https://repeat.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 702
      });
      expect(service.declineFallback('tab-repeat', second.attemptId)).assertTrue();
      expect(service.rearmDeclinedRetry('tab-repeat', 'https://repeat.example/')).assertTrue();
      service.bindNavigationAttempt('tab-repeat', 'https://repeat.example/', 703);
      const third = service.resolveResourceFailureDecision('tab-repeat', {
        requestUrl: 'https://repeat.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 703
      });

      expect(first.attemptId === second.attemptId).assertFalse();
      expect(second.attemptId === third.attemptId).assertFalse();
      expect(third.action).assertEqual('require_http_confirmation');
      expect(third.delivery).assertEqual('apply');
    });

    it('refreshes HTTPS-First mode when a declined attempt is retried', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      service.registerBrowserGeneratedUpgrade(
        'tab-mode',
        'https://mode.example',
        'http://mode.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-mode', 'https://mode.example/', 801);
      const first = service.resolveResourceFailureDecision('tab-mode', {
        requestUrl: 'https://mode.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 801
      });
      expect(service.declineFallback('tab-mode', first.attemptId)).assertTrue();

      repository.setHttpsFirstEnabled(false);
      expect(service.rearmDeclinedRetry('tab-mode', 'https://mode.example/')).assertTrue();
      service.bindNavigationAttempt('tab-mode', 'https://mode.example/', 802);
      const retry = service.resolveResourceFailureDecision('tab-mode', {
        requestUrl: 'https://mode.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 802
      });

      expect(retry.action).assertEqual('automatic_http_fallback');
      expect(retry.delivery).assertEqual('apply');
    });

    it('does not rearm arbitrary HTTPS and clears declined provenance on an unrelated navigation', 0, () => {
      const service = new BrowserHttpsFirstNavigationService(
        new InMemoryBrowserWebSecuritySettingsRepository(true)
      );
      expect(service.rearmDeclinedRetry('tab-explicit-retry', 'https://secure.example/')).assertFalse();
      service.registerBrowserGeneratedUpgrade(
        'tab-unrelated',
        'https://old.example',
        'http://old.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-unrelated', 'https://old.example/', 901);
      const decision = service.resolveResourceFailureDecision('tab-unrelated', {
        requestUrl: 'https://old.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 901
      });
      expect(service.declineFallback('tab-unrelated', decision.attemptId)).assertTrue();

      expect(service.rearmDeclinedRetry('tab-unrelated', 'https://new.example/')).assertFalse();
      expect(service.rearmDeclinedRetry('tab-unrelated', 'https://old.example/')).assertFalse();
    });

    it('clears declined retry provenance when the tab is closed', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      service.registerBrowserGeneratedUpgrade(
        'tab-close',
        'https://close.example',
        'http://close.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-close', 'https://close.example/', 1001);
      const decision = service.resolveResourceFailureDecision('tab-close', {
        requestUrl: 'https://close.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 1001
      });
      expect(service.declineFallback('tab-close', decision.attemptId)).assertTrue();

      service.clearTab('tab-close');

      expect(service.rearmDeclinedRetry('tab-close', 'https://close.example/')).assertFalse();
      expect(repository.persistedRetryTabId).assertEqual('');
    });

    it('clears declined provenance when an explicit new navigation replaces the error-page retry', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      service.registerBrowserGeneratedUpgrade(
        'tab-explicit-replace',
        'https://replace.example',
        'http://replace.example',
        { profileId: 'profile-main', privacyMode: 'regular', dataScope: 'profile_persistent' },
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-explicit-replace', 'https://replace.example/', 1101);
      const decision = service.resolveResourceFailureDecision('tab-explicit-replace', {
        requestUrl: 'https://replace.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 1101
      });
      expect(service.declineFallback('tab-explicit-replace', decision.attemptId)).assertTrue();

      service.cancelAttempt('tab-explicit-replace');

      expect(service.rearmDeclinedRetry('tab-explicit-replace', 'https://replace.example/')).assertFalse();
      expect(repository.persistedRetryTabId).assertEqual('');
    });

    it('keeps a private HTTP exception in memory only until private-session cleanup', 0, () => {
      const repository = new InMemoryBrowserWebSecuritySettingsRepository(true);
      const service = new BrowserHttpsFirstNavigationService(repository);
      const boundary: BrowserDataBoundaryInput = {
        profileId: 'profile-main',
        privacyMode: 'private',
        dataScope: 'session_ephemeral'
      };
      service.registerBrowserGeneratedUpgrade(
        'tab-private',
        'https://private.example',
        'http://private.example',
        boundary,
        (_tabId: string, _fallbackUrl: string): boolean => true
      );
      service.bindNavigationAttempt('tab-private', 'https://private.example/', 1201);
      const decision = service.resolveResourceFailureDecision('tab-private', {
        requestUrl: 'https://private.example/',
        isMainFrame: true,
        errorCode: -107,
        navigationId: 1201
      });
      const prepared = service.prepareFallback('tab-private', decision.attemptId, true);
      expect(prepared !== undefined).assertTrue();
      if (prepared !== undefined) {
        expect(service.executePreparedFallback(prepared)).assertTrue();
      }
      expect(repository.rememberedSiteKey).assertEqual('');
      expect(service.beginMainFrameNavigation('tab-private', 'http://private.example/', boundary)).assertTrue();
      service.finishNavigation('tab-private', 'http://private.example/');
      expect(service.beginMainFrameNavigation('tab-private', 'http://private.example/', boundary)).assertTrue();

      service.clearPrivateSessionExceptions('profile-main');

      expect(service.beginMainFrameNavigation('tab-private', 'http://private.example/', boundary)).assertFalse();
    });
  });
}
