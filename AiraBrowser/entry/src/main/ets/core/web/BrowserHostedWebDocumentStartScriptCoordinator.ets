import { SitePermissionRule } from '../../common/models/BrowserModels';
import { BrowserProfileBoundaryService } from '../browser/BrowserProfileBoundaryService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BrowserTabState } from '../tabs/TabManager';
import {
  UserScriptDocumentStartScriptBundle,
  UserScriptRuntimeCoordinator
} from '../userscripts/UserScriptRuntimeCoordinator';
import { SiteInteractionLogicService } from '../../services/web/SiteInteractionLogicService';
import { SitePolicyService } from '../../services/web/SitePolicyService';
import { WebClipboardPermissionScriptService } from '../../services/web/WebClipboardPermissionScriptService';
import { WebMixedContentImageUpgradeScriptService } from '../../services/web/WebMixedContentImageUpgradeScriptService';
import { BrowserWebLocalScrollSignalService } from '../../services/web/BrowserWebLocalScrollSignalService';
import { BrowserMediaFrameRuntimeCoordinator } from '../browser/media/BrowserMediaFrameRuntimeCoordinator';
import {
  sharedAdBlockDocumentStartScriptProviderRegistry
} from '../adblock/AdBlockDocumentStartScriptProviderRegistry';
import { WebBackForwardCacheCoordinator } from './WebBackForwardCacheCoordinator';
import { WebSwipeNavigationScriptService } from '../../services/web/WebSwipeNavigationScriptService';
import { AiraWebFreezeProbe } from '../../common/debug/AiraWebFreezeProbe';

const BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN: number = 0x0000;
const BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG: string = 'HomeSearchDiag';

/**
 * Temporary [DEBUG-web-freeze-9f2a]. Labels an injected script so trace and long-animation-frame
 * attribution name it instead of reporting an anonymous source. Remove with the freeze probe.
 */
function labelInjectedScript(item: ScriptItem, label: string): ScriptItem {
  const source = String(item.script ?? '');
  return {
    script: source.includes('//# sourceURL=') ? source : `${source}\n//# sourceURL=aira-injected-${label}.js\n`,
    scriptRules: item.scriptRules
  };
}

export interface BrowserHostedWebDocumentScripts {
  documentStartScripts: ScriptItem[];
  documentStartScriptKey?: string;
  documentEndScripts: ScriptItem[];
  documentEndScriptKey?: string;
  /** Character count of the native Web document-start payload, for bounded diagnostics only. */
  documentStartScriptChars?: number;
}

export interface BrowserHostedWebDocumentScriptProvider {
  buildForTab(tab: BrowserTabState): BrowserHostedWebDocumentScripts;
}

export class BrowserHostedWebDocumentStartScriptCoordinator
  implements BrowserHostedWebDocumentScriptProvider {
  private readonly userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator;
  private readonly sitePolicyService: SitePolicyService;
  private readonly profileBoundaryService: BrowserProfileBoundaryService = new BrowserProfileBoundaryService();
  private readonly siteInteractionLogicService: SiteInteractionLogicService = new SiteInteractionLogicService();
  private readonly clipboardPermissionScriptService: WebClipboardPermissionScriptService =
    new WebClipboardPermissionScriptService();
  private readonly backForwardCacheCoordinator: WebBackForwardCacheCoordinator =
    new WebBackForwardCacheCoordinator();
  private readonly mixedContentImageUpgradeScriptService: WebMixedContentImageUpgradeScriptService =
    new WebMixedContentImageUpgradeScriptService();
  private readonly localScrollSignalService: BrowserWebLocalScrollSignalService =
    new BrowserWebLocalScrollSignalService();
  private readonly mediaFrameRuntimeCoordinator: BrowserMediaFrameRuntimeCoordinator;
  private readonly isSwipeNavigationEnabled: () => boolean;
  private cachedDocumentScripts?: BrowserHostedWebDocumentScripts;

  constructor(
    userScriptRuntimeCoordinator: UserScriptRuntimeCoordinator,
    sitePolicyService: SitePolicyService,
    mediaFrameRuntimeCoordinator: BrowserMediaFrameRuntimeCoordinator,
    isSwipeNavigationEnabled: () => boolean = (): boolean => false
  ) {
    this.isSwipeNavigationEnabled = isSwipeNavigationEnabled;
    this.userScriptRuntimeCoordinator = userScriptRuntimeCoordinator;
    this.sitePolicyService = sitePolicyService;
    this.mediaFrameRuntimeCoordinator = mediaFrameRuntimeCoordinator;
  }

  buildForTab(tab: BrowserTabState): BrowserHostedWebDocumentScripts {
    const startedAt = Date.now();
    const privateMode = this.profileBoundaryService.isSessionEphemeral({
      profileId: tab.profileId,
      privacyMode: tab.privacyMode,
      dataScope: tab.dataScope,
      sessionId: tab.id
    });
    const swipeNavigationEnabled = this.isSwipeNavigationEnabled();
    const clipboardPermissionRule = this.resolveClipboardPermissionRule(tab);
    const userScriptBundle: UserScriptDocumentStartScriptBundle =
      this.userScriptRuntimeCoordinator.buildDocumentStartScriptBundle(privateMode);
    const documentStartScriptKey = [
      'browser-document-start-v3',
      'freeze-loaf-9f2a',
      swipeNavigationEnabled ? 'swipe-navigation-on' : 'swipe-navigation-off',
      privateMode ? 'private' : 'regular',
      tab.profileId,
      this.resolveTabUrl(tab),
      clipboardPermissionRule,
      sharedAdBlockDocumentStartScriptProviderRegistry.buildCacheKey(tab),
      userScriptBundle.key
    ].join('|');
    const cached = this.cachedDocumentScripts;
    if (cached !== undefined && cached.documentStartScriptKey === documentStartScriptKey) {
      hilog.info(
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
        BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
        '[DIAG-home-submit-20260828] document_scripts cache=hit tab=%{public}s urlLength=%{public}d start=%{public}d end=%{public}d startChars=%{public}d elapsedMs=%{public}d',
        tab.id,
        this.resolveTabUrl(tab).length,
        cached.documentStartScripts.length,
        cached.documentEndScripts.length,
        cached.documentStartScriptChars ?? 0,
        Date.now() - startedAt
      );
      return {
        documentStartScripts: this.cloneScriptItems(cached.documentStartScripts),
        documentStartScriptKey: cached.documentStartScriptKey,
        documentEndScripts: [],
        documentEndScriptKey: cached.documentEndScriptKey,
        documentStartScriptChars: cached.documentStartScriptChars
      };
    }
    const adBlockScripts = sharedAdBlockDocumentStartScriptProviderRegistry.buildForTab(tab);
    const browserScripts = [
      labelInjectedScript(this.backForwardCacheCoordinator.buildCompatibilityDocumentStartScriptItem(),
        'bfcache-compat'),
      labelInjectedScript(this.mixedContentImageUpgradeScriptService.buildDocumentStartScriptItem(),
        'mixed-content-upgrade'),
      labelInjectedScript(this.mediaFrameRuntimeCoordinator.buildDocumentStartScriptItem(),
        'media-frame-runtime'),
      labelInjectedScript(this.localScrollSignalService.buildDocumentStartScriptItem(),
        'local-scroll-signal'),
      // Temporary [DEBUG-web-freeze-9f2a]. Remove with the probe.
      labelInjectedScript(AiraWebFreezeProbe.buildDocumentStartScriptItem(), 'freeze-diag'),
      labelInjectedScript(this.clipboardPermissionScriptService.buildDocumentStartScriptItem(
        clipboardPermissionRule
      ), 'clipboard-permission')
    ].concat(userScriptBundle.items);
    if (swipeNavigationEnabled) {
      browserScripts.push(labelInjectedScript(new WebSwipeNavigationScriptService().buildDocumentStartScriptItem(),
        'swipe-navigation'));
    }
    const documentStartScripts = browserScripts.concat(adBlockScripts);
    const result: BrowserHostedWebDocumentScripts = {
      documentStartScripts: documentStartScripts,
      documentStartScriptKey: documentStartScriptKey,
      // Multi-megabyte end/idle payloads block ArkWeb before page_begin. The renderer lifecycle owner
      // matches the final URL, claims each script once, and executes prepared sources after post-paint.
      documentEndScripts: [],
      documentEndScriptKey: 'browser-document-end-empty-v1',
      documentStartScriptChars: this.sumScriptItemChars(documentStartScripts)
    };
    this.cachedDocumentScripts = {
      documentStartScripts: this.cloneScriptItems(result.documentStartScripts),
      documentStartScriptKey: result.documentStartScriptKey,
      documentEndScripts: [],
      documentEndScriptKey: result.documentEndScriptKey,
      documentStartScriptChars: result.documentStartScriptChars
    };
    hilog.info(
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_DOMAIN,
      BROWSER_HOME_SUBMIT_DIAGNOSTIC_TAG,
      '[DIAG-home-submit-20260828] document_scripts cache=miss tab=%{public}s urlLength=%{public}d start=%{public}d end=%{public}d startChars=%{public}d elapsedMs=%{public}d keyLength=%{public}d',
      tab.id,
      this.resolveTabUrl(tab).length,
      result.documentStartScripts.length,
      result.documentEndScripts.length,
      result.documentStartScriptChars ?? 0,
      Date.now() - startedAt,
      documentStartScriptKey.length
    );
    return result;
  }

  private sumScriptItemChars(items: ScriptItem[]): number {
    return items.reduce((total: number, item: ScriptItem): number => {
      return total + String(item.script ?? '').length;
    }, 0);
  }

  private cloneScriptItems(items: ScriptItem[]): ScriptItem[] {
    return items.map((item: ScriptItem): ScriptItem => {
      return {
        script: item.script,
        scriptRules: (item.scriptRules ?? []).slice()
      };
    });
  }

  private resolveClipboardPermissionRule(tab: BrowserTabState): SitePermissionRule {
    const origin = this.siteInteractionLogicService.resolveOrigin(this.resolveTabUrl(tab));
    if (origin.length === 0) {
      return 'ask';
    }
    const settings = this.sitePolicyService.getEffectiveSitePermissionSettings(
      origin,
      tab.profileId,
      tab.dataScope
    );
    return this.sitePolicyService.getSitePermissionRule(settings, 'clipboard');
  }

  private resolveTabUrl(tab: BrowserTabState): string {
    const pendingUrl = tab.pendingUrl.trim();
    return pendingUrl.length > 0 ? pendingUrl : tab.url.trim();
  }
}
