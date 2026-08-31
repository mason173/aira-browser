import { AdBlockRepository } from '../../data/adblock/AdBlockRepository';
import urlUtils from '@ohos.url';
import { AdBlockPingRuntimeScriptService } from '../../services/adblock/AdBlockPingRuntimeScriptService';
import { AdBlockCosmeticRuntimeScriptService } from '../../services/adblock/AdBlockCosmeticRuntimeScriptService';
import {
  AdBlockInteractionGuardRuntimeScriptService
} from '../../services/adblock/AdBlockInteractionGuardRuntimeScriptService';
import { AdBlockPolicyService } from '../../services/adblock/AdBlockPolicyService';
import { BrowserTabState } from '../tabs/TabManager';
import { AdBlockDocumentStartScriptProvider } from './AdBlockDocumentStartScriptProviderRegistry';
import { AdBlockRuntimeGenerationCoordinator } from './AdBlockRuntimeGenerationCoordinator';

export class AdBlockDocumentStartCoordinator implements AdBlockDocumentStartScriptProvider {
  private repository: AdBlockRepository;
  private runtimeGeneration: AdBlockRuntimeGenerationCoordinator;
  private cosmeticRuntimeScriptService: AdBlockCosmeticRuntimeScriptService = new AdBlockCosmeticRuntimeScriptService();
  private pingRuntimeScriptService: AdBlockPingRuntimeScriptService = new AdBlockPingRuntimeScriptService();
  private interactionGuardRuntimeScriptService: AdBlockInteractionGuardRuntimeScriptService =
    new AdBlockInteractionGuardRuntimeScriptService();
  private policyService: AdBlockPolicyService = new AdBlockPolicyService();
  private interactionGuardScriptItem?: ScriptItem;
  private pingScriptItem?: ScriptItem;

  constructor(repository: AdBlockRepository) {
    this.repository = repository;
    this.runtimeGeneration = AdBlockRuntimeGenerationCoordinator.forRepository(repository);
  }

  buildForTab(tab: BrowserTabState): ScriptItem[] {
    const settings = this.repository.getSettings();
    if (!settings.preferences.enabled) {
      return [];
    }
    const targetUrl = tab.pendingUrl.trim().length > 0 ? tab.pendingUrl : tab.url;
    const host = this.resolveHost(targetUrl);
    const allowlisted = this.policyService.isHostAllowlisted(settings, host, tab.profileId);
    const resources = allowlisted ? undefined : this.runtimeGeneration.resolveNativeCosmeticResources(targetUrl);
    const scriptletScript = resources?.injectedScript.trim() ?? '';
    const scriptletScriptItem: ScriptItem | undefined = scriptletScript.length <= 0
      ? undefined
      : {
        script: this.cosmeticRuntimeScriptService.buildInjectedScriptExecutionScript(
          scriptletScript,
          host
        ),
        scriptRules: [targetUrl]
      };
    if (this.interactionGuardScriptItem === undefined) {
      this.interactionGuardScriptItem = this.interactionGuardRuntimeScriptService.buildDocumentStartScriptItem();
    }
    if (this.pingScriptItem === undefined) {
      this.pingScriptItem = this.pingRuntimeScriptService.buildDocumentStartScriptItem();
    }
    const scriptItems: ScriptItem[] = [this.interactionGuardScriptItem];
    scriptItems.push(this.pingScriptItem);
    if (scriptletScriptItem !== undefined) {
      scriptItems.push(scriptletScriptItem);
    }
    return scriptItems;
  }

  buildCacheKey(tab: BrowserTabState): string {
    const settings = this.repository.getSettings();
    const targetUrl = tab.pendingUrl.trim().length > 0 ? tab.pendingUrl.trim() : tab.url.trim();
    const host = this.resolveHost(targetUrl);
    const allowlisted = this.policyService.isHostAllowlisted(settings, host, tab.profileId);
    return [
      'adblock-document-start-v2',
      settings.updatedAt,
      settings.preferences.enabled ? 'enabled' : 'disabled',
      settings.lastRuleUpdateAt,
      this.runtimeGeneration.getRuntimeRefreshGeneration(),
      tab.profileId,
      targetUrl,
      allowlisted ? 'allowlisted' : 'filtered'
    ].join('|');
  }

  private resolveHost(url: string): string {
    try {
      return urlUtils.URL.parseURL(url).hostname.trim().toLowerCase();
    } catch (_error) {
      return '';
    }
  }
}
