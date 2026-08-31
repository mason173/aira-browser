import { AdBlockRequestEvaluationInput } from './AdBlockRequestEvaluationModels';

interface AdBlockNativeModule {
  buildEngine(rulesetPath: string): Promise<AdBlockNativeAuthorityBuildResult>;
  releaseEngine(handle: number): void;
  checkRequest(
    handle: number,
    url: string,
    sourceUrl: string,
    requestType: string,
    method: string,
    includeCsp: boolean
  ): AdBlockNativeAuthorityEvaluation;
  getCosmeticResources(
    handle: number,
    url: string,
    classesJson: string,
    idsJson: string
  ): AdBlockNativeCosmeticResources;
  backendVersion(): string;
}

export interface AdBlockNativeAuthorityEvaluation {
  shouldBlock: boolean;
  cspDirectives: string;
  redirectDataUrl: string;
  rewrittenUrl: string;
}

export interface AdBlockNativeCosmeticResources {
  hideSelectorsJson: string;
  proceduralActionsJson: string;
  exceptionsJson: string;
  injectedScript: string;
  generichide: boolean;
}

export interface AdBlockNativeAuthorityBuildResult {
  handle: number;
  networkRuleCount: number;
  cosmeticRuleCount: number;
  ruleCount: number;
}

interface AdBlockNativeModuleNamespace {
  default: AdBlockNativeModule;
}

export class AdBlockNativeAuthorityEngineService {
  private nativeModule?: AdBlockNativeModule;
  private nativeModuleTask?: Promise<AdBlockNativeModule>;

  async buildEngine(rulesetPath: string): Promise<AdBlockNativeAuthorityBuildResult> {
    const nativeModule = await this.loadNativeModule();
    return nativeModule.buildEngine(rulesetPath);
  }

  releaseEngine(handle: number): void {
    const nativeModule = this.requireLoadedNativeModule();
    nativeModule.releaseEngine(handle);
  }

  isEligible(input: AdBlockRequestEvaluationInput): boolean {
    const normalizedUrl = input.url.trim().toLowerCase();
    return input.enabled && (!input.isMainFrame || input.resourceType === 'document') &&
      (normalizedUrl.startsWith('http://') || normalizedUrl.startsWith('https://'));
  }

  evaluate(handle: number, input: AdBlockRequestEvaluationInput): AdBlockNativeAuthorityEvaluation {
    if (!this.isEligible(input)) {
      return {
        shouldBlock: false,
        cspDirectives: '',
        redirectDataUrl: '',
        rewrittenUrl: ''
      };
    }
    const requestType = input.resourceType ?? (input.isMainFrame ? 'document' : 'other');
    const normalizedRequestType = requestType === 'popup' ? 'document' : requestType;
    const normalizedMethod = input.method.trim().toUpperCase() || 'GET';
    const includeCsp = input.includeResponseEvaluation && normalizedMethod === 'GET' &&
      (normalizedRequestType === 'document' || normalizedRequestType === 'subdocument');
    const nativeModule = this.requireLoadedNativeModule();
    return nativeModule.checkRequest(
      handle,
      input.url,
      input.pageUrl,
      normalizedRequestType,
      normalizedMethod,
      includeCsp
    );
  }

  getCosmeticResources(
    handle: number,
    url: string,
    classesJson: string = '[]',
    idsJson: string = '[]'
  ): AdBlockNativeCosmeticResources {
    return this.requireLoadedNativeModule().getCosmeticResources(handle, url, classesJson, idsJson);
  }

  backendVersion(): string {
    const nativeModule = this.requireLoadedNativeModule();
    return nativeModule.backendVersion();
  }

  private loadNativeModule(): Promise<AdBlockNativeModule> {
    if (this.nativeModule !== undefined) {
      return Promise.resolve(this.nativeModule);
    }
    if (this.nativeModuleTask === undefined) {
      this.nativeModuleTask = import('libaira_adblock.so')
        .then((module: AdBlockNativeModuleNamespace): AdBlockNativeModule => {
          this.nativeModule = module.default;
          return module.default;
        })
        .catch((_error: Error): AdBlockNativeModule => {
          this.nativeModuleTask = undefined;
          throw new Error('Ad-block native authority module could not be loaded.');
        });
    }
    return this.nativeModuleTask;
  }

  private requireLoadedNativeModule(): AdBlockNativeModule {
    if (this.nativeModule === undefined) {
      throw new Error('Ad-block native authority module is unavailable.');
    }
    return this.nativeModule;
  }
}
