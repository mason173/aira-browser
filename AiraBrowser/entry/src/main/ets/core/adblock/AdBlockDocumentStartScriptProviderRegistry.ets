import { BrowserTabState } from '../tabs/TabManager';

export interface AdBlockDocumentStartScriptProvider {
  buildForTab(tab: BrowserTabState): ScriptItem[];
  buildCacheKey?: (tab: BrowserTabState) => string;
}

export class AdBlockDocumentStartScriptProviderRegistry implements AdBlockDocumentStartScriptProvider {
  private provider?: AdBlockDocumentStartScriptProvider;

  register(provider: AdBlockDocumentStartScriptProvider): void {
    this.provider = provider;
  }

  buildForTab(tab: BrowserTabState): ScriptItem[] {
    return this.provider?.buildForTab(tab) ?? [];
  }

  buildCacheKey(tab: BrowserTabState): string {
    return this.provider?.buildCacheKey?.(tab) ?? 'adblock-provider-v1';
  }
}

export const sharedAdBlockDocumentStartScriptProviderRegistry: AdBlockDocumentStartScriptProviderRegistry =
  new AdBlockDocumentStartScriptProviderRegistry();
