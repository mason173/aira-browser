export interface AiraAdBlockNativeModule {
  buildEngine(rulesetPath: string): Promise<{
    handle: number;
    networkRuleCount: number;
    cosmeticRuleCount: number;
    ruleCount: number;
  }>;
  releaseEngine(handle: number): void;
  checkRequest(
    handle: number,
    url: string,
    sourceUrl: string,
    requestType: string,
    method: string,
    includeCsp: boolean
  ): {
    shouldBlock: boolean;
    cspDirectives: string;
    redirectDataUrl: string;
    rewrittenUrl: string;
  };
  getCosmeticResources(
    handle: number,
    url: string,
    classesJson: string,
    idsJson: string
  ): {
    hideSelectorsJson: string;
    proceduralActionsJson: string;
    exceptionsJson: string;
    injectedScript: string;
    generichide: boolean;
  };
  backendVersion(): string;
}

declare const nativeAdBlock: AiraAdBlockNativeModule;
export default nativeAdBlock;
