import { InstalledUserScriptState } from '../../features/userscripts/UserScriptMetadataModels';
import { USER_SCRIPT_NATIVE_BRIDGE_NAME } from '../../features/userscripts/UserScriptNativeBridgeModels';
import { UserScriptCapabilityContractService } from './UserScriptCapabilityContractService';
import {
  UserScriptRuntimeCompatibilityInjectionProfile,
  UserScriptRuntimeCompatibilityService
} from './UserScriptRuntimeCompatibilityService';

interface UserScriptRuntimeResourceMetadata {
  name: string;
  url: string;
  mimeType: string;
}

export interface UserScriptInjectionRequest {
  script: InstalledUserScriptState;
  valueSnapshotLiteral: string;
  valueRevision: number;
  bridgeToken: string;
}

export class UserScriptInjectionService {
  private capabilityContract: UserScriptCapabilityContractService = new UserScriptCapabilityContractService();
  private compatibilityService: UserScriptRuntimeCompatibilityService = new UserScriptRuntimeCompatibilityService();

  buildDocumentEndScript(requests: UserScriptInjectionRequest[]): string {
    const scripts = requests.map((request: UserScriptInjectionRequest) => this.wrapScript(request)).join('\n');
    return this.buildPreparedDocumentEndBatch(scripts);
  }

  buildPreparedDocumentEndScript(request: UserScriptInjectionRequest): string {
    return this.wrapScript(request);
  }

  buildPreparedDocumentIdleScript(request: UserScriptInjectionRequest): string {
    const scriptIdLiteral = JSON.stringify(request.script.id);
    const preparedBatch = this.buildPreparedDocumentEndBatch(this.wrapScript(request));
    return `
;(function airaScheduleUserScriptDocumentIdle() {
  var scriptId = ${scriptIdLiteral};
  var schedules = window.__airaUserScriptIdleSchedules = window.__airaUserScriptIdleSchedules || {};
  if (schedules[scriptId] === true) {
    return;
  }
  schedules[scriptId] = true;
  var run = function() {
${preparedBatch}
  };
  if (typeof window.requestIdleCallback === 'function') {
    window.requestIdleCallback(run, { timeout: 200 });
    return;
  }
  window.setTimeout(run, 0);
})();
//# sourceURL=aira-userscript-${request.script.id}-idle-scheduler.js
`;
  }

  buildPreparedDocumentEndBatch(preparedScripts: string, expectedDocumentToken: string = ''): string {
    const documentTokenGuard = this.buildExpectedDocumentTokenGuard(expectedDocumentToken);
    return `
;(function airaUserScriptBatch() {
${documentTokenGuard}
${this.buildRuntimeFactoryInstallScript()}
${this.buildUrlMatcherInstallScript()}
  window.__airaUserScriptReports = window.__airaUserScriptReports || [];
${preparedScripts}
  return JSON.stringify(window.__airaUserScriptReports || []);
})();
`;
  }

  buildDocumentExecutionClaimScript(scriptIds: string[], expectedDocumentToken: string = ''): string {
    const normalizedScriptIds: string[] = [];
    scriptIds.forEach((scriptId: string): void => {
      const normalizedScriptId = scriptId.trim();
      if (normalizedScriptId.length > 0 && !normalizedScriptIds.includes(normalizedScriptId)) {
        normalizedScriptIds.push(normalizedScriptId);
      }
    });
    const scriptIdsLiteral = JSON.stringify(normalizedScriptIds);
    const documentTokenGuard = this.buildExpectedDocumentTokenGuard(expectedDocumentToken);
    return `
;(function airaUserScriptClaimDocumentExecution() {
${documentTokenGuard}
  var scriptIds = ${scriptIdsLiteral};
  var executed = window.__airaExecutedUserScripts || {};
  var claims = window.__airaUserScriptExecutionClaims = window.__airaUserScriptExecutionClaims || {};
  var claimed = [];
  scriptIds.forEach(function(scriptId) {
    if (executed[scriptId] === true || claims[scriptId] === true) {
      return;
    }
    claims[scriptId] = true;
    claimed.push(scriptId);
  });
  return JSON.stringify(claimed);
})();
`;
  }


  buildDocumentStartScript(requests: UserScriptInjectionRequest[], disabledHosts: string[] = []): string {
    const scripts = requests.map((request: UserScriptInjectionRequest) => this.wrapScript(request)).join('\n');
    const hostPolicyGuard = this.buildDocumentStartHostPolicyGuard(disabledHosts);
    return `
;(function airaUserScriptDocumentStartBatch() {
  window.__airaUserScriptReports = window.__airaUserScriptReports || [];
${hostPolicyGuard}
${scripts}
})();
`;
  }

  buildDocumentStartApiScript(requests: UserScriptInjectionRequest[], disabledHosts: string[] = []): string {
    const scripts = requests.map((request: UserScriptInjectionRequest) => this.wrapScript(request, true)).join('\n');
    const hostPolicyGuard = this.buildDocumentStartHostPolicyGuard(disabledHosts);
    return `
;(function airaUserScriptDocumentStartApiBatch() {
  window.__airaUserScriptReports = window.__airaUserScriptReports || [];
${hostPolicyGuard}
${scripts}
})();
`;
  }

  buildDocumentIdentityInstallScript(documentSignalSecret: string): string {
    const bridgeNameLiteral = JSON.stringify(USER_SCRIPT_NATIVE_BRIDGE_NAME);
    const signalSecretLiteral = JSON.stringify(documentSignalSecret);
    return `
;(function airaInstallUserScriptDocumentIdentity() {
  if (window.top !== window) {
    return;
  }
  if (typeof window.__airaUserScriptDocumentIdentity === 'string' &&
      window.__airaUserScriptDocumentIdentity.length > 0) {
    return;
  }
  var randomPart = '';
  try {
    var randomBytes = new Uint32Array(4);
    window.crypto.getRandomValues(randomBytes);
    randomPart = Array.prototype.map.call(randomBytes, function(value) {
      return Number(value).toString(36);
    }).join('-');
  } catch (_error) {
    randomPart = String(Math.random()).slice(2) + '-' + String(Date.now());
  }
  Object.defineProperty(window, '__airaUserScriptDocumentIdentity', {
    value: 'd-' + randomPart,
    writable: false,
    configurable: false,
    enumerable: false
  });
  var bridgeName = ${bridgeNameLiteral};
  var signalSecret = ${signalSecretLiteral};
  var nativeBridge = window[bridgeName];
  var nativeRequest = nativeBridge && typeof nativeBridge.request === 'function'
    ? nativeBridge.request.bind(nativeBridge)
    : null;
  var nativeRequestAnimationFrame = typeof window.requestAnimationFrame === 'function'
    ? window.requestAnimationFrame.bind(window)
    : null;
  var nativeAddEventListener = typeof window.addEventListener === 'function'
    ? window.addEventListener.bind(window)
    : null;
  var nativeRemoveEventListener = typeof window.removeEventListener === 'function'
    ? window.removeEventListener.bind(window)
    : null;
  var nativeJsonStringify = JSON && typeof JSON.stringify === 'function'
    ? JSON.stringify.bind(JSON)
    : null;
  var nativeString = String;
  var nativeReadyStateGetter = null;
  try {
    var nativeGetPrototypeOf = Object.getPrototypeOf.bind(Object);
    var nativeGetOwnPropertyDescriptor = Object.getOwnPropertyDescriptor.bind(Object);
    var documentPrototype = nativeGetPrototypeOf(document);
    while (documentPrototype && !nativeReadyStateGetter) {
      var readyStateDescriptor = nativeGetOwnPropertyDescriptor(documentPrototype, 'readyState');
      if (readyStateDescriptor && typeof readyStateDescriptor.get === 'function') {
        nativeReadyStateGetter = readyStateDescriptor.get.bind(document);
        break;
      }
      documentPrototype = nativeGetPrototypeOf(documentPrototype);
    }
  } catch (_error) {
  }
  var readNativeReadyState = function() {
    if (!nativeReadyStateGetter) {
      return '';
    }
    try {
      return nativeString(nativeReadyStateGetter());
    } catch (_error) {
      return '';
    }
  };
  var loadCompleted = readNativeReadyState() === 'complete';
  var documentEndSent = false;
  var postPaintScheduled = false;
  var sendSignal = function(phase) {
    if (!nativeRequest || !nativeJsonStringify ||
        window.__airaUserScriptDocumentIdentity !== 'd-' + randomPart) {
      return;
    }
    try {
      nativeRequest(nativeJsonStringify({
        kind: '__aira_internal_document_lifecycle',
        capability: signalSecret,
        token: 'd-' + randomPart,
        name: phase,
        url: nativeString(window.location && window.location.href || '')
      }));
    } catch (_error) {
    }
  };
  var schedulePostPaint = function() {
    if (!loadCompleted || postPaintScheduled || !nativeRequestAnimationFrame ||
        window.__airaUserScriptDocumentIdentity !== 'd-' + randomPart) {
      return;
    }
    postPaintScheduled = true;
    nativeRequestAnimationFrame(function() {
      nativeRequestAnimationFrame(function() {
        sendSignal('post_paint');
      });
    });
  };
  var sendDocumentEndSignal = function() {
    if (documentEndSent) {
      return;
    }
    documentEndSent = true;
    sendSignal('document_end');
  };
  var readReadyState = function() {
    var state = readNativeReadyState();
    return state === 'interactive' || state === 'complete';
  };
  sendSignal('document_start');
  if (readReadyState()) {
    sendDocumentEndSignal();
  }
  if (!readReadyState() && nativeAddEventListener) {
    var handleDomContentLoaded = function(event) {
      if (!event || event.isTrusted !== true || !readReadyState()) {
        return;
      }
      if (nativeRemoveEventListener) {
        nativeRemoveEventListener('DOMContentLoaded', handleDomContentLoaded);
      }
      sendDocumentEndSignal();
    };
    nativeAddEventListener('DOMContentLoaded', handleDomContentLoaded);
  }
  if (!loadCompleted && nativeAddEventListener) {
    var handleLoad = function(event) {
      if (!event || event.isTrusted !== true || readNativeReadyState() !== 'complete') {
        return;
      }
      loadCompleted = true;
      if (nativeRemoveEventListener) {
        nativeRemoveEventListener('load', handleLoad);
      }
      sendDocumentEndSignal();
      schedulePostPaint();
    };
    nativeAddEventListener('load', handleLoad);
  }
  schedulePostPaint();
})();
`;
  }

  buildExecutionReportReadScript(expectedDocumentToken: string = ''): string {
    const documentTokenGuard = this.buildExpectedDocumentTokenGuard(expectedDocumentToken);
    return `
;(function airaUserScriptReadReports() {
${documentTokenGuard}
  return JSON.stringify(window.__airaUserScriptReports || []);
})();
`;
  }

  private buildExpectedDocumentTokenGuard(expectedDocumentToken: string): string {
    if (expectedDocumentToken.length === 0) {
      return '';
    }
    const expectedDocumentTokenLiteral = JSON.stringify(expectedDocumentToken);
    return `
  if (window.__airaUserScriptDocumentIdentity !== ${expectedDocumentTokenLiteral}) {
    return JSON.stringify({ staleDocument: true });
  }`;
  }

  private buildDocumentStartHostPolicyGuard(disabledHosts: string[]): string {
    const normalizedHosts = disabledHosts
      .map((host: string): string => host.trim().toLowerCase().replace(/^\.+|\.+$/g, ''))
      .filter((host: string) => host.length > 0)
      .sort();
    const disabledHostsLiteral = JSON.stringify(normalizedHosts);
    return `
  var __airaDocumentStartDisabledHosts = ${disabledHostsLiteral};
  var __airaDocumentStartHost = String(window.location && window.location.hostname || '')
    .trim()
    .toLowerCase()
    .replace(/^\\.+|\\.+$/g, '');
  if (__airaDocumentStartDisabledHosts.indexOf(__airaDocumentStartHost) >= 0) {
    return;
  }`;
  }

  private wrapScript(request: UserScriptInjectionRequest, apiOnly: boolean = false): string {
    const script = request.script;
    const scriptId = JSON.stringify(script.id);
    const scriptName = JSON.stringify(script.name);
    const scriptNamespace = JSON.stringify(script.namespace);
    const scriptVersion = JSON.stringify(script.version);
    const scriptDescription = JSON.stringify(script.description);
    const bridgeToken = JSON.stringify(request.bridgeToken);
    const noframesLiteral = script.noframes === true ? 'true' : 'false';
    const capabilityManifest = this.capabilityContract.buildRuntimeManifest(script);
    const grantsLiteral = capabilityManifest.grantFlagsLiteral;
    const nativeRoutesLiteral = capabilityManifest.nativeRoutesLiteral;
    const grantNamesLiteral = JSON.stringify(script.grants);
    const matchesLiteral = JSON.stringify(script.matches);
    const includesLiteral = JSON.stringify(script.includes);
    const excludeMatchesLiteral = JSON.stringify(script.excludeMatches);
    const excludesLiteral = JSON.stringify(script.excludes);
    const resourceMetadata: UserScriptRuntimeResourceMetadata[] = script.resources.map((resource): UserScriptRuntimeResourceMetadata => {
      const metadata: UserScriptRuntimeResourceMetadata = {
        name: resource.name,
        url: resource.url,
        mimeType: resource.mimeType
      };
      return metadata;
    });
    const resourcesMetadataLiteral = JSON.stringify(resourceMetadata);
    const connectRulesLiteral = JSON.stringify(script.connectRules);
    const runAtLiteral = JSON.stringify(script.runAt);
    const valuesLiteral = request.valueSnapshotLiteral.length > 0 ? request.valueSnapshotLiteral : '{}';
    const valueRevisionLiteral = request.valueRevision >= 0 ? String(request.valueRevision) : '0';
    const apiOnlyLiteral = apiOnly ? 'true' : 'false';
    const requiresSource = apiOnly ? '' : script.requireSources.map((source: string, index: number) => {
      // Keep @require sources in the same lexical scope as the main userscript. Libraries may intentionally expose
      // top-level let/const/class bindings, so wrapping an individual dependency in a block changes userscript semantics.
      return `
${source}
//# sourceURL=aira-userscript-${script.id}-require-${index}.js
`;
    }).join('\n');
    const resourcesLiteral = apiOnly ? '{}' : this.buildResourceTextLiteral(script);
    const resourcesUrlLiteral = apiOnly ? '{}' : this.buildResourceUrlLiteral(script);
    const compatibilityProfile: UserScriptRuntimeCompatibilityInjectionProfile =
      this.compatibilityService.buildInjectionProfile(script);
    const standaloneOptionsPageUrlsLiteral = JSON.stringify(compatibilityProfile.standaloneOptionsPageUrls);
    const standaloneOptionsBridgeRuntimeSource = compatibilityProfile.bridgeRuntimeSource;
    const scriptBodySource = apiOnly ? '' : `
${requiresSource}
${script.source}
${compatibilityProfile.postScriptSource}
`;
    return `
;(function airaUserScriptWrapper() {
  var __airaScriptId = ${scriptId};
  var __airaScriptName = ${scriptName};
  var __airaScriptNamespace = ${scriptNamespace};
  var __airaScriptVersion = ${scriptVersion};
  var __airaScriptDescription = ${scriptDescription};
  var __airaNativeBridgeToken = ${bridgeToken};
  var __airaNoFrames = ${noframesLiteral};
  var __airaGrants = ${grantsLiteral};
  var __airaNativeRoutes = ${nativeRoutesLiteral};
  var __airaGrantNames = ${grantNamesLiteral};
  var __airaMatches = ${matchesLiteral};
  var __airaIncludes = ${includesLiteral};
  var __airaExcludeMatches = ${excludeMatchesLiteral};
  var __airaExcludes = ${excludesLiteral};
  var __airaResourcesMetadata = ${resourcesMetadataLiteral};
  var __airaConnectRules = ${connectRulesLiteral};
  var __airaRunAt = ${runAtLiteral};
  var __airaValues = ${valuesLiteral};
  var __airaCommittedValueRevision = ${valueRevisionLiteral};
  var __airaApiOnly = ${apiOnlyLiteral};
  var __airaResources = ${resourcesLiteral};
  var __airaResourceUrls = ${resourcesUrlLiteral};
  var __airaStandaloneOptionsPageUrls = ${standaloneOptionsPageUrlsLiteral};
  var __airaSuccess = true;
  var __airaErrorMessage = '';
  var __airaLocationProtocol = String(window.location && window.location.protocol || '').toLowerCase();
  if (__airaLocationProtocol !== 'http:' && __airaLocationProtocol !== 'https:') {
    return;
  }
  var __airaExclusionMatcher = window.__airaUserScriptIsExcludedV1;
  if (typeof __airaExclusionMatcher !== 'function' || __airaExclusionMatcher(
    String(window.location && window.location.href || ''),
    __airaExcludeMatches,
    __airaExcludes
  )) {
    return;
  }
  var __airaPositiveMatcher = window.__airaUserScriptMatchesV1;
  if (!__airaApiOnly && (typeof __airaPositiveMatcher !== 'function' || !__airaPositiveMatcher(
    String(window.location && window.location.href || ''),
    __airaMatches,
    __airaIncludes
  ))) {
    return;
  }
  window.__airaExecutedUserScripts = window.__airaExecutedUserScripts || {};
  if (__airaNoFrames && window.top !== window.self) {
    window.__airaUserScriptReports = window.__airaUserScriptReports || [];
    window.__airaUserScriptReports.push({
      scriptId: __airaScriptId,
      success: true,
      errorMessage: ''
    });
    return;
  }
  if (!__airaApiOnly && window.__airaExecutedUserScripts[__airaScriptId] === true) {
    window.__airaUserScriptReports = window.__airaUserScriptReports || [];
    window.__airaUserScriptReports.push({
      scriptId: __airaScriptId,
      success: true,
      errorMessage: ''
    });
    return;
  }
  if (!__airaApiOnly) {
    window.__airaExecutedUserScripts[__airaScriptId] = true;
  }
  var __airaExecutionStartedAt = 0;
  var __airaReadExecutionClock = function() {
    try {
      if (typeof performance !== 'undefined' && typeof performance.now === 'function') {
        return Number(performance.now());
      }
    } catch (_error) {
    }
    return Number(Date.now());
  };
  try {
    __airaExecutionStartedAt = __airaReadExecutionClock();
    var __airaRuntimeFactory = window.__airaUserScriptRuntimeFactoryV1;
    if (typeof __airaRuntimeFactory !== 'function') {
      throw new Error('Aira userscript runtime factory unavailable');
    }
    var __airaRuntime = __airaRuntimeFactory({
      scriptId: __airaScriptId,
      scriptName: __airaScriptName,
      scriptNamespace: __airaScriptNamespace,
      scriptVersion: __airaScriptVersion,
      scriptDescription: __airaScriptDescription,
      nativeBridgeToken: __airaNativeBridgeToken,
      noframes: __airaNoFrames,
      grants: __airaGrants,
      nativeRoutes: __airaNativeRoutes,
      grantNames: __airaGrantNames,
      matches: __airaMatches,
      includes: __airaIncludes,
      excludeMatches: __airaExcludeMatches,
      excludes: __airaExcludes,
      resourcesMetadata: __airaResourcesMetadata,
      connectRules: __airaConnectRules,
      runAt: __airaRunAt,
      values: __airaValues,
      valueRevision: __airaCommittedValueRevision,
      resources: __airaResources,
      resourceUrls: __airaResourceUrls
    });
    var unsafeWindow = __airaRuntime.unsafeWindow;
    var GM_info = __airaRuntime.GM_info;
    var GM_script = __airaRuntime.GM_script;
    var GM_addStyle = __airaRuntime.GM_addStyle;
    var GM_addElement = __airaRuntime.GM_addElement;
    var GM_getValue = __airaRuntime.GM_getValue;
    var GM_getValues = __airaRuntime.GM_getValues;
    var GM_setValue = __airaRuntime.GM_setValue;
    var GM_setValues = __airaRuntime.GM_setValues;
    var GM_deleteValue = __airaRuntime.GM_deleteValue;
    var GM_deleteValues = __airaRuntime.GM_deleteValues;
    var GM_listValues = __airaRuntime.GM_listValues;
    var GM_getResourceText = __airaRuntime.GM_getResourceText;
    var GM_getResourceURL = __airaRuntime.GM_getResourceURL;
    var GM_addValueChangeListener = __airaRuntime.GM_addValueChangeListener;
    var GM_removeValueChangeListener = __airaRuntime.GM_removeValueChangeListener;
    var GM_registerMenuCommand = __airaRuntime.GM_registerMenuCommand;
    var GM_unregisterMenuCommand = __airaRuntime.GM_unregisterMenuCommand;
    var GM_openInTab = __airaRuntime.GM_openInTab;
    var GM_notification = __airaRuntime.GM_notification;
    var GM_setClipboard = __airaRuntime.GM_setClipboard;
    var GM_log = __airaRuntime.GM_log;
    var GM_getTab = __airaRuntime.GM_getTab;
    var GM_saveTab = __airaRuntime.GM_saveTab;
    var GM_getTabs = __airaRuntime.GM_getTabs;
    var GM_download = __airaRuntime.GM_download;
    var GM_xmlhttpRequest = __airaRuntime.GM_xmlhttpRequest;
    var GM_xmlHttpRequestPromise = __airaRuntime.GM_xmlHttpRequestPromise;
    var GM_fetch = __airaRuntime.GM_fetch;
    var GM_EX_getSearchEngines = __airaRuntime.GM_EX_getSearchEngines;
    var GM_EX_getAppSearchEngineUrl = __airaRuntime.GM_EX_getAppSearchEngineUrl;
    var GM_EX_TTS = __airaRuntime.GM_EX_TTS;
    var GM_EX_ShareTextToApp = __airaRuntime.GM_EX_ShareTextToApp;
    var GM_EX_sniffMedia = __airaRuntime.GM_EX_sniffMedia;
    var GM_webextPref = __airaRuntime.GM_webextPref;
    var GM = __airaRuntime.GM;
    var __airaGetValuePromise = __airaRuntime.getValuePromise;
    var __airaSetValuePromise = __airaRuntime.setValuePromise;
    var __airaDeleteValuePromise = __airaRuntime.deleteValuePromise;
    window.unsafeWindow = unsafeWindow;
    window.GM = GM;
    window.GM_info = GM_info;
    window.GM_getValue = GM_getValue;
    window.GM_getValues = GM_getValues;
    window.GM_setValue = GM_setValue;
    window.GM_setValues = GM_setValues;
    window.GM_deleteValue = GM_deleteValue;
    window.GM_deleteValues = GM_deleteValues;
    window.GM_listValues = GM_listValues;
    window.GM_fetch = GM_fetch;
    window.GM_xmlhttpRequest = GM_xmlhttpRequest;
    window.GM_xmlHttpRequest = GM_xmlhttpRequest;
    window.GM_script = GM_script;
    window.GM_webextPref = GM_webextPref;
    window.GM_EX_getSearchEngines = GM_EX_getSearchEngines;
    window.GM_EX_getAppSearchEngineUrl = GM_EX_getAppSearchEngineUrl;
    window.GM_EX_TTS = GM_EX_TTS;
    window.GM_EX_ShareTextToApp = GM_EX_ShareTextToApp;
    window.GM_EX_sniffMedia = GM_EX_sniffMedia;
${standaloneOptionsBridgeRuntimeSource}
${scriptBodySource}
  } catch (error) {
    __airaSuccess = false;
    __airaErrorMessage = String(error && (error.stack || error.message || error) || '');
    console.error('[AiraUserScript][' + __airaScriptName + '] ' +
      (error && (error.stack || error.message || String(error))));
  } finally {
    if (!__airaApiOnly) {
      window.__airaUserScriptReports = window.__airaUserScriptReports || [];
      window.__airaUserScriptReports.push({
        scriptId: __airaScriptId,
        success: __airaSuccess,
        errorMessage: __airaErrorMessage,
        durationMs: __airaExecutionStartedAt > 0
          ? Math.max(0, Math.round(__airaReadExecutionClock() - __airaExecutionStartedAt))
          : undefined
      });
    }
  }
})();
//# sourceURL=aira-userscript-${script.id}.js
`;
  }

  buildRuntimeFactoryInstallScript(): string {
    const valueBridgeName = JSON.stringify(USER_SCRIPT_NATIVE_BRIDGE_NAME);
    return `${this.buildUrlMatcherInstallScript()}
;(function airaInstallUserScriptRuntimeFactory() {
  if (typeof window.__airaUserScriptRuntimeFactoryV1 === 'function') {
    return 'ready';
  }
  window.__airaUserScriptRuntimeFactoryV1 = function(__airaConfig) {
  var __airaScriptId = String(__airaConfig.scriptId || '');
  var __airaScriptName = String(__airaConfig.scriptName || '');
  var __airaScriptNamespace = String(__airaConfig.scriptNamespace || '');
  var __airaScriptVersion = String(__airaConfig.scriptVersion || '');
  var __airaScriptDescription = String(__airaConfig.scriptDescription || '');
  var __airaNativeBridgeToken = String(__airaConfig.nativeBridgeToken || '');
  var __airaNoFrames = __airaConfig.noframes === true;
  var __airaGrants = __airaConfig.grants || {};
  var __airaNativeRoutes = __airaConfig.nativeRoutes || {};
  var __airaGrantNames = Array.isArray(__airaConfig.grantNames) ? __airaConfig.grantNames : [];
  var __airaMatches = Array.isArray(__airaConfig.matches) ? __airaConfig.matches : [];
  var __airaIncludes = Array.isArray(__airaConfig.includes) ? __airaConfig.includes : [];
  var __airaExcludeMatches = Array.isArray(__airaConfig.excludeMatches) ? __airaConfig.excludeMatches : [];
  var __airaExcludes = Array.isArray(__airaConfig.excludes) ? __airaConfig.excludes : [];
  var __airaResourcesMetadata = Array.isArray(__airaConfig.resourcesMetadata) ? __airaConfig.resourcesMetadata : [];
  var __airaConnectRules = Array.isArray(__airaConfig.connectRules) ? __airaConfig.connectRules : [];
  var __airaRunAt = String(__airaConfig.runAt || 'document-end');
  var __airaValues = __airaConfig.values || {};
  var __airaCommittedValueRevision = Number(__airaConfig.valueRevision || 0);
  var __airaCommittedValues = {};
  var __airaCommittedValueJson = {};
  var __airaLoadedValueKeys = {};
  Object.keys(__airaValues).forEach(function(key) {
    __airaCommittedValues[key] = __airaValues[key];
    try {
      var valueJson = JSON.stringify(__airaValues[key]);
      if (typeof valueJson === 'string') {
        __airaCommittedValueJson[key] = valueJson;
      }
    } catch (_error) {}
    __airaLoadedValueKeys[key] = true;
  });
  var __airaProvisionalValueCommands = [];
  var __airaResources = __airaConfig.resources || {};
  var __airaResourceUrls = __airaConfig.resourceUrls || {};
  var __airaValueListeners = {};
  var __airaMenuCommands = {};
  var __airaNextListenerId = 1;
  var __airaNextMenuCommandId = 1;
  var __airaNextNativeRequestId = 1;
  var __airaNativeValueReadTimeoutMs = 5000;
  var __airaRequireGrant = function(grantName, allowed) {
    if (!allowed) {
      throw new Error('Missing userscript grant: ' + grantName);
    }
  };
  var __airaNotifyValueListeners = function(key, oldValue, newValue) {
    Object.keys(__airaValueListeners).forEach(function(listenerId) {
      var listener = __airaValueListeners[listenerId];
      if (!listener || listener.key !== key) {
        return;
      }
      try {
        listener.callback(key, oldValue, newValue, false);
      } catch (error) {
        console.error('[AiraUserScript][value-listener] ' + (error && (error.stack || error.message || String(error))));
      }
    });
  };
  var __airaCloneValueMap = function(source) {
    var clone = {};
    Object.keys(source || {}).forEach(function(key) {
      clone[key] = source[key];
    });
    return clone;
  };
  var __airaApplyValueMutationToMap = function(target, mutation) {
    if (!mutation || !mutation.key) {
      return;
    }
    if (mutation.operation === 'delete') {
      delete target[mutation.key];
      return;
    }
    target[mutation.key] = mutation.value;
  };
  var __airaRebuildProvisionalValueView = function() {
    var nextValues = __airaCloneValueMap(__airaCommittedValues);
    __airaProvisionalValueCommands.forEach(function(command) {
      (command && command.mutations || []).forEach(function(mutation) {
        __airaApplyValueMutationToMap(nextValues, mutation);
      });
    });
    __airaValues = nextValues;
  };
  var __airaHasPendingValueMutationForKey = function(key) {
    return __airaProvisionalValueCommands.some(function(command) {
      return (command && command.mutations || []).some(function(mutation) {
        return mutation && mutation.key === key;
      });
    });
  };
  var __airaDrainSettledProvisionalValueCommands = function() {
    var drained = false;
    while (__airaProvisionalValueCommands.length > 0) {
      var command = __airaProvisionalValueCommands[0];
      if (!command || command.settled !== true) {
        break;
      }
      __airaProvisionalValueCommands.shift();
      if (command.success === true) {
        __airaApplyCommittedValueResult(command.event);
      }
      drained = true;
    }
    if (drained) {
      __airaRebuildProvisionalValueView();
    }
  };
  var __airaParseCommittedValueJson = function(valueJson, fallbackValue) {
    try {
      return JSON.parse(String(valueJson || ''));
    } catch (_error) {
      return fallbackValue;
    }
  };
  var __airaApplyCommittedValueResult = function(event) {
    var commit = event && event.commit;
    var revision = Number(commit && commit.revision);
    if (!commit || !isFinite(revision) || revision <= __airaCommittedValueRevision) {
      return;
    }
    var transitions = Array.isArray(commit.transitions) ? commit.transitions : [];
    transitions.forEach(function(transition) {
      if (!transition || String(transition.scriptId || '') !== __airaScriptId) {
        return;
      }
      var key = String(transition.key || '');
      if (!key) {
        return;
      }
      var oldValue = transition.hasOldValue === true ?
        __airaParseCommittedValueJson(transition.oldValueJson, undefined) : undefined;
      var newValue = transition.hasNewValue === true ?
        __airaParseCommittedValueJson(transition.newValueJson, undefined) : undefined;
      if (transition.hasNewValue === true) {
        __airaCommittedValues[key] = newValue;
        __airaCommittedValueJson[key] = String(transition.newValueJson || '');
      } else {
        delete __airaCommittedValues[key];
        delete __airaCommittedValueJson[key];
      }
      __airaLoadedValueKeys[key] = true;
      __airaNotifyValueListeners(key, oldValue, newValue);
    });
    __airaCommittedValueRevision = revision;
  };
  var unsafeWindow = window;
    var GM_info = {
      script: {
        id: __airaScriptId,
        name: __airaScriptName,
        namespace: __airaScriptNamespace,
        version: __airaScriptVersion,
        description: __airaScriptDescription,
        matches: __airaMatches.slice(),
        includes: __airaIncludes.slice(),
        excludeMatches: __airaExcludeMatches.slice(),
        excludes: __airaExcludes.slice(),
        resources: __airaResourcesMetadata.slice(),
        grants: __airaGrantNames.slice(),
        connect: __airaConnectRules.slice(),
        runAt: __airaRunAt,
        noframes: __airaNoFrames
      },
      scriptMetaStr: '',
      scriptHandler: 'Aira',
      version: '0.1',
      platform: {
        arch: '',
        browserName: 'Aira',
        browserVersion: '',
        os: 'HarmonyOS'
      },
      downloadMode: 'native'
    };
    var GM_script = GM_info.script;
    var GM_addStyle = function(css) {
      __airaRequireGrant('GM_addStyle', __airaGrants.addStyle);
      var style = document.createElement('style');
      style.setAttribute('data-aira-userscript-id', __airaScriptId);
      style.textContent = String(css || '');
      (document.head || document.documentElement).appendChild(style);
      return style;
    };
    var GM_addElement = function(parentOrTagName, tagNameOrAttributes, attributes) {
      __airaRequireGrant('GM_addElement', __airaGrants.addElement);
      var parent = document.head || document.documentElement;
      var tagName = '';
      var elementAttributes = {};
      if (typeof parentOrTagName === 'string') {
        tagName = parentOrTagName;
        elementAttributes = tagNameOrAttributes || {};
      } else {
        parent = parentOrTagName || parent;
        tagName = String(tagNameOrAttributes || '');
        elementAttributes = attributes || {};
      }
      if (!tagName) {
        throw new Error('GM_addElement requires a tag name');
      }
      var element = document.createElement(tagName);
      Object.keys(elementAttributes || {}).forEach(function(name) {
        var value = elementAttributes[name];
        if (value === undefined || value === null) {
          return;
        }
        if (name === 'textContent') {
          element.textContent = String(value);
          return;
        }
        if (name === 'innerHTML') {
          element.innerHTML = String(value);
          return;
        }
        if (name === 'style' && typeof value === 'object') {
          Object.keys(value).forEach(function(styleName) {
            try {
              element.style[styleName] = String(value[styleName]);
            } catch (_error) {}
          });
          return;
        }
        if (name.indexOf('on') === 0 && typeof value === 'function') {
          element[name] = value;
          return;
        }
        element.setAttribute(name, String(value));
      });
      parent.appendChild(element);
      return element;
    };
    var GM_getValue = function(key, defaultValue) {
      __airaRequireGrant('GM_getValue', __airaGrants.getValue);
      var normalizedKey = String(key || '');
      if (__airaLoadedValueKeys[normalizedKey] === true) {
        return Object.prototype.hasOwnProperty.call(__airaValues, normalizedKey) ?
          __airaValues[normalizedKey] : defaultValue;
      }
      var committedValue = __airaReadCommittedValueSyncForKey(__airaNativeRoutes.getValue, normalizedKey);
      if (committedValue.available) {
        return committedValue.found ? committedValue.value : defaultValue;
      }
      if (Object.prototype.hasOwnProperty.call(__airaValues, normalizedKey)) {
        return __airaValues[normalizedKey];
      }
      return defaultValue;
    };
    var GM_getValues = function(keysOrDefaults) {
      __airaRequireGrant('GM_getValues', __airaGrants.getValues);
      var result = {};
      if (Array.isArray(keysOrDefaults)) {
        keysOrDefaults.forEach(function(key) {
          var normalizedKey = String(key || '');
          if (__airaLoadedValueKeys[normalizedKey] === true) {
            if (Object.prototype.hasOwnProperty.call(__airaValues, normalizedKey)) {
              result[normalizedKey] = __airaValues[normalizedKey];
            }
            return;
          }
          var committedValue = __airaReadCommittedValueSyncForKey(__airaNativeRoutes.getValues, normalizedKey);
          if (committedValue.available) {
            if (committedValue.found) {
              result[normalizedKey] = committedValue.value;
            }
            return;
          }
          if (Object.prototype.hasOwnProperty.call(__airaValues, normalizedKey)) {
            result[normalizedKey] = __airaValues[normalizedKey];
          }
        });
        return result;
      }
      Object.keys(keysOrDefaults || {}).forEach(function(key) {
        var defaultValue = keysOrDefaults[key];
        if (__airaLoadedValueKeys[key] === true) {
          result[key] = Object.prototype.hasOwnProperty.call(__airaValues, key) ? __airaValues[key] : defaultValue;
          return;
        }
        var committedValue = __airaReadCommittedValueSyncForKey(__airaNativeRoutes.getValues, key);
        if (committedValue.available) {
          result[key] = committedValue.found ? committedValue.value : defaultValue;
          return;
        }
        result[key] = Object.prototype.hasOwnProperty.call(__airaValues, key) ? __airaValues[key] : defaultValue;
      });
      return result;
    };
    var __airaRequestNativeBridge = function(route, payload) {
      var bridge = window.__airaUserScriptNativeBridge;
      if (!route || !bridge || typeof bridge.request !== 'function' || !__airaNativeBridgeToken) {
        return false;
      }
      payload.kind = route.requestKind;
      payload.capability = route.capability;
      payload.scriptId = __airaScriptId;
      payload.token = __airaNativeBridgeToken;
      bridge.request(JSON.stringify(payload));
      return true;
    };
    var __airaRequestNativeOpenInTab = function(route, url, active) {
      var bridge = window.__airaUserScriptNativeBridge;
      if (!route || !bridge || typeof bridge.openInTab !== 'function' || !__airaNativeBridgeToken) {
        return false;
      }
      bridge.openInTab(JSON.stringify({
        kind: route.requestKind,
        capability: route.capability,
        url: String(url || ''),
        active: active !== false,
        scriptId: __airaScriptId,
        token: __airaNativeBridgeToken
      }));
      return true;
    };
    var __airaPersistValueMutation = function(route, operation, key, value) {
      var payload = {
        key: key
      };
      if (operation !== 'delete') {
        var valueJson = JSON.stringify(value);
        if (__airaLoadedValueKeys[key] === true && !__airaHasPendingValueMutationForKey(key) &&
          typeof valueJson === 'string' && __airaCommittedValueJson[key] === valueJson) {
          return Promise.resolve();
        }
        payload.valueJson = valueJson;
      } else if (__airaLoadedValueKeys[key] === true && !__airaHasPendingValueMutationForKey(key) &&
        !Object.prototype.hasOwnProperty.call(__airaCommittedValues, key)) {
        return Promise.resolve();
      }
      return __airaSubmitProvisionalValueCommand(route, payload, [{
        operation: operation,
        key: key,
        value: value
      }]);
    };
    window.__airaUserScriptValueCallbacks = window.__airaUserScriptValueCallbacks || {};
    window.__airaUserScriptValueDispatch = window.__airaUserScriptValueDispatch || function(event) {
      var callbacks = window.__airaUserScriptValueCallbacks || {};
      var requestCallbacks = callbacks[String(event && event.id || '')];
      if (!requestCallbacks) {
        return;
      }
      delete callbacks[String(event.id || '')];
      if (typeof requestCallbacks.timeoutId === 'number') {
        clearTimeout(requestCallbacks.timeoutId);
      }
      if (event && event.success === true) {
        try {
          if (typeof requestCallbacks.onSuccess === 'function') {
            requestCallbacks.onSuccess(event || {});
          }
          requestCallbacks.resolve(event || {});
        } catch (error) {
          requestCallbacks.reject(error);
        }
        return;
      }
      if (typeof requestCallbacks.onFailure === 'function') {
        try {
          requestCallbacks.onFailure(event || {});
        } catch (_error) {}
      }
      requestCallbacks.reject(new Error(String(event && event.error || 'value-mutation-failed')));
    };
    var __airaRequestNativeValueRequest = function(route, payload, lifecycle) {
      var bridge = window.__airaUserScriptNativeBridge;
      if (!route || !bridge || typeof bridge.request !== 'function' || !__airaNativeBridgeToken) {
        var bridgeFailure = !route ? 'route-missing' :
          (!bridge ? 'proxy-missing' :
            (typeof bridge.request !== 'function' ? 'request-method-' + typeof bridge.request : 'token-missing'));
        if (lifecycle && typeof lifecycle.onFailure === 'function') {
          try {
            lifecycle.onFailure({ error: 'userscript-native-bridge-unavailable:' + bridgeFailure });
          } catch (_error) {}
        }
        return Promise.reject(new Error('userscript-native-bridge-unavailable:' + bridgeFailure));
      }
      var requestId = __airaScriptId + '-value-' + (__airaNextNativeRequestId++);
      return new Promise(function(resolve, reject) {
        var waitForFinalAck = lifecycle && lifecycle.waitForFinalAck === true;
        var timeoutId = waitForFinalAck ? undefined : setTimeout(function() {
          delete window.__airaUserScriptValueCallbacks[requestId];
          reject(new Error('value-request-timeout'));
        }, __airaNativeValueReadTimeoutMs);
        window.__airaUserScriptValueCallbacks[requestId] = {
          resolve: resolve,
          reject: reject,
          timeoutId: timeoutId,
          onSuccess: lifecycle && lifecycle.onSuccess,
          onFailure: lifecycle && lifecycle.onFailure
        };
        try {
          payload.kind = route.requestKind;
          payload.capability = route.capability;
          payload.id = requestId;
          payload.scriptId = __airaScriptId;
          payload.token = __airaNativeBridgeToken;
          bridge.request(JSON.stringify(payload));
        } catch (error) {
          delete window.__airaUserScriptValueCallbacks[requestId];
          if (typeof timeoutId === 'number') {
            clearTimeout(timeoutId);
          }
          if (lifecycle && typeof lifecycle.onFailure === 'function') {
            try {
              lifecycle.onFailure({ error: 'userscript-native-bridge-failed' });
            } catch (_error) {}
          }
          reject(error);
        }
      });
    };
    var __airaReadCommittedValueSync = function(route, payload) {
      var bridge = window[${valueBridgeName}];
      if (!route || !bridge || typeof bridge.readValue !== 'function' || !__airaNativeBridgeToken) {
        return undefined;
      }
      payload = payload || {};
      payload.kind = route.requestKind;
      payload.capability = route.capability;
      payload.scriptId = __airaScriptId;
      payload.token = __airaNativeBridgeToken;
      try {
        var event = JSON.parse(String(bridge.readValue(JSON.stringify(payload)) || ''));
        return event && event.success === true ? event : undefined;
      } catch (_error) {
        return undefined;
      }
    };
    var __airaReadCommittedValueSyncForKey = function(route, key) {
      var normalizedKey = String(key || '');
      if (!normalizedKey) {
        return {
          available: true,
          found: false,
          value: undefined
        };
      }
      var event = __airaReadCommittedValueSync(route, {
        key: normalizedKey
      });
      if (!event) {
        return {
          available: false,
          found: false,
          value: undefined
        };
      }
      if (event.found !== true) {
        delete __airaValues[normalizedKey];
        delete __airaCommittedValues[normalizedKey];
        delete __airaCommittedValueJson[normalizedKey];
        __airaLoadedValueKeys[normalizedKey] = true;
        return {
          available: true,
          found: false,
          value: undefined
        };
      }
      try {
        var valueJson = String(event.valueJson || '');
        var value = JSON.parse(valueJson);
        __airaValues[normalizedKey] = value;
        __airaCommittedValues[normalizedKey] = value;
        __airaCommittedValueJson[normalizedKey] = valueJson;
        __airaLoadedValueKeys[normalizedKey] = true;
        return {
          available: true,
          found: true,
          value: value
        };
      } catch (_error) {
        return {
          available: false,
          found: false,
          value: undefined
        };
      }
    };
    var __airaSubmitProvisionalValueCommand = function(route, payload, mutations) {
      var command = {
        mutations: Array.isArray(mutations) ? mutations : [],
        settled: false,
        success: false,
        event: undefined
      };
      command.mutations.forEach(function(mutation) {
        if (mutation && mutation.key) {
          __airaLoadedValueKeys[mutation.key] = true;
        }
      });
      __airaProvisionalValueCommands.push(command);
      __airaRebuildProvisionalValueView();
      return __airaRequestNativeValueRequest(route, payload, {
        waitForFinalAck: true,
        onSuccess: function(event) {
          command.settled = true;
          command.success = true;
          command.event = event;
          __airaDrainSettledProvisionalValueCommands();
        },
        onFailure: function() {
          command.settled = true;
          command.success = false;
          command.event = undefined;
          __airaDrainSettledProvisionalValueCommands();
        }
      }).then(function() {});
    };
    var __airaGetValuePromiseForRoute = function(key, defaultValue, route) {
      var normalizedKey = String(key || '');
      if (!normalizedKey) {
        return Promise.resolve(defaultValue);
      }
      return __airaRequestNativeValueRequest(route, {
        key: normalizedKey
      }).then(function(event) {
        if (!event || event.found !== true) {
          if (!__airaHasPendingValueMutationForKey(normalizedKey)) {
            delete __airaValues[normalizedKey];
            delete __airaCommittedValues[normalizedKey];
            delete __airaCommittedValueJson[normalizedKey];
            __airaLoadedValueKeys[normalizedKey] = true;
          }
          return defaultValue;
        }
        try {
          var valueJson = String(event.valueJson || '');
          var value = JSON.parse(valueJson);
          if (!__airaHasPendingValueMutationForKey(normalizedKey)) {
            __airaValues[normalizedKey] = value;
            __airaCommittedValues[normalizedKey] = value;
            __airaCommittedValueJson[normalizedKey] = valueJson;
            __airaLoadedValueKeys[normalizedKey] = true;
          }
          return value;
        } catch (_error) {
          return defaultValue;
        }
      }).catch(function(_error) {
        return Object.prototype.hasOwnProperty.call(__airaValues, normalizedKey) ?
          __airaValues[normalizedKey] : defaultValue;
      });
    };
    var __airaGetValuePromise = function(key, defaultValue) {
      __airaRequireGrant('GM_getValue', __airaGrants.getValue);
      return __airaGetValuePromiseForRoute(key, defaultValue, __airaNativeRoutes.getValue);
    };
    var __airaGetValuesPromise = function(keysOrDefaults) {
      __airaRequireGrant('GM_getValues', __airaGrants.getValues);
      if (Array.isArray(keysOrDefaults)) {
        return Promise.all(keysOrDefaults.map(function(key) {
          return __airaGetValuePromiseForRoute(key, undefined, __airaNativeRoutes.getValues).then(function(value) {
            return { key: String(key || ''), value: value, found: value !== undefined };
          });
        })).then(function(entries) {
          var result = {};
          entries.forEach(function(entry) {
            if (entry.key && entry.found) {
              result[entry.key] = entry.value;
            }
          });
          return result;
        });
      }
      var defaults = keysOrDefaults || {};
      return Promise.all(Object.keys(defaults).map(function(key) {
        return __airaGetValuePromiseForRoute(key, defaults[key], __airaNativeRoutes.getValues).then(function(value) {
          return { key: key, value: value };
        });
      })).then(function(entries) {
        var result = {};
        entries.forEach(function(entry) {
          result[entry.key] = entry.value;
        });
        return result;
      });
    };
    var __airaListValuesPromise = function() {
      __airaRequireGrant('GM_listValues', __airaGrants.listValues);
      return __airaRequestNativeValueRequest(__airaNativeRoutes.listValues, {}).then(function(event) {
        if (!event || event.found !== true) {
          return Object.keys(__airaValues);
        }
        try {
          var keys = JSON.parse(String(event.valueJson || '[]'));
          return Array.isArray(keys) ? keys.map(function(key) { return String(key || ''); }).filter(function(key) {
            return key.length > 0;
          }) : Object.keys(__airaValues);
        } catch (_error) {
          return Object.keys(__airaValues);
        }
      }).catch(function(_error) {
        return Object.keys(__airaValues);
      });
    };
    var __airaLogValuePersistFailure = function(error) {
      console.warn('[AiraUserScript][value][' + __airaScriptName + '] ' +
        (error && (error.message || String(error)) || 'value-persist-failed'));
    };
    var __airaSetValuePromise = function(key, value) {
      __airaRequireGrant('GM_setValue', __airaGrants.setValue);
      return __airaSetValueInternal(String(key || ''), value, __airaNativeRoutes.setValue);
    };
    var GM_setValue = function(key, value) {
      return __airaSetValuePromise(key, value).catch(function(error) {
        __airaLogValuePersistFailure(error);
        throw error;
      });
    };
    var __airaSetValueInternal = function(normalizedKey, value, route) {
      normalizedKey = String(normalizedKey || '');
      if (!normalizedKey) {
        return Promise.resolve();
      }
      return __airaPersistValueMutation(route, 'set', normalizedKey, value);
    };
    var __airaSetValuesPromise = function(values) {
      __airaRequireGrant('GM_setValues', __airaGrants.setValues);
      return Promise.all(Object.keys(values || {}).map(function(key) {
        return __airaSetValueInternal(String(key || ''), values[key], __airaNativeRoutes.setValues);
      })).then(function() {});
    };
    var GM_setValues = function(values) {
      return __airaSetValuesPromise(values).catch(function(error) {
        __airaLogValuePersistFailure(error);
        throw error;
      });
    };
    var __airaDeleteValuePromise = function(key) {
      __airaRequireGrant('GM_deleteValue', __airaGrants.deleteValue);
      var normalizedKey = String(key || '');
      if (!normalizedKey) {
        return Promise.resolve();
      }
      return __airaPersistValueMutation(__airaNativeRoutes.deleteValue, 'delete', normalizedKey);
    };
    var GM_deleteValue = function(key) {
      return __airaDeleteValuePromise(key).catch(function(error) {
        __airaLogValuePersistFailure(error);
        throw error;
      });
    };
    var __airaDeleteValuesPromise = function(keys) {
      __airaRequireGrant('GM_deleteValues', __airaGrants.deleteValues);
      var deleteMutations = [];
      (Array.isArray(keys) ? keys : Object.keys(keys || {})).forEach(function(key) {
        var normalizedKey = String(key || '');
        if (!normalizedKey) {
          return;
        }
        var mutation = {
          operation: 'delete',
          key: normalizedKey,
          valueJson: '',
          value: undefined
        };
        deleteMutations.push(mutation);
      });
      if (deleteMutations.length === 0) {
        return Promise.resolve();
      }
      return __airaSubmitProvisionalValueCommand(__airaNativeRoutes.deleteValues, {
          mutations: deleteMutations
      }, deleteMutations);
    };
    var GM_deleteValues = function(keys) {
      return __airaDeleteValuesPromise(keys).catch(function(error) {
        __airaLogValuePersistFailure(error);
        throw error;
      });
    };
    var GM_listValues = function() {
      __airaRequireGrant('GM_listValues', __airaGrants.listValues);
      var committedValues = __airaReadCommittedValueSync(__airaNativeRoutes.listValues, {});
      if (committedValues && committedValues.found === true) {
        try {
          var committedKeys = JSON.parse(String(committedValues.valueJson || '[]'));
          if (Array.isArray(committedKeys)) {
            return committedKeys.map(function(key) { return String(key || ''); }).filter(function(key) {
              return key.length > 0;
            });
          }
        } catch (_error) {
        }
      }
      return Object.keys(__airaValues);
    };
    var GM_getResourceText = function(name) {
      __airaRequireGrant('GM_getResourceText', __airaGrants.getResourceText);
      return __airaResources[String(name || '')] || '';
    };
    var GM_getResourceURL = function(name) {
      __airaRequireGrant('GM_getResourceURL', __airaGrants.getResourceURL);
      return __airaResourceUrls[String(name || '')] || '';
    };
    var GM_addValueChangeListener = function(key, callback) {
      __airaRequireGrant('GM_addValueChangeListener', __airaGrants.addValueChangeListener);
      var listenerId = String(__airaNextListenerId++);
      __airaValueListeners[listenerId] = {
        key: String(key || ''),
        callback: callback
      };
      return listenerId;
    };
    var GM_removeValueChangeListener = function(listenerId) {
      __airaRequireGrant('GM_removeValueChangeListener', __airaGrants.removeValueChangeListener);
      delete __airaValueListeners[String(listenerId || '')];
    };
    var GM_registerMenuCommand = function(name, callback, options) {
      __airaRequireGrant('GM_registerMenuCommand', __airaGrants.registerMenuCommand);
      var commandId = String(__airaNextMenuCommandId++);
      var commandOptions = options || {};
      __airaMenuCommands[commandId] = {
        name: String(name || ''),
        callback: callback,
        id: String(commandOptions.id || commandId),
        accessKey: String(commandOptions.accessKey || commandOptions.accesskey || ''),
        autoClose: commandOptions.autoClose !== false,
        title: String(commandOptions.title || '')
      };
      window.__airaUserScriptMenus = window.__airaUserScriptMenus || {};
      window.__airaUserScriptMenus[__airaScriptId] = __airaMenuCommands;
      return commandId;
    };
    var GM_unregisterMenuCommand = function(commandId) {
      __airaRequireGrant('GM_unregisterMenuCommand', __airaGrants.unregisterMenuCommand);
      delete __airaMenuCommands[String(commandId || '')];
    };
    var GM_openInTab = function(url, options) {
      __airaRequireGrant('GM_openInTab', __airaGrants.openInTab);
      var targetUrl = String(url || '');
      if (targetUrl.length === 0) {
        return null;
      }
      var nativeOpened = __airaRequestNativeOpenInTab(
        __airaNativeRoutes.openInTab,
        targetUrl,
        !(options && options.active === false)
      );
      var openedWindow = nativeOpened ? null : window.open(targetUrl, '_blank');
      return {
        close: function() {
          if (openedWindow && typeof openedWindow.close === 'function') {
            openedWindow.close();
          }
        },
        closed: nativeOpened ? false : (openedWindow ? openedWindow.closed === true : true)
      };
    };
    var GM_notification = function(details, ondone) {
      __airaRequireGrant('GM_notification', __airaGrants.notification);
      var notificationDetails = typeof details === 'string' ? { text: details } : (details || {});
      var requestId = __airaScriptId + '-notification-' + (__airaNextNativeRequestId++);
      window.__airaUserScriptNotificationCallbacks = window.__airaUserScriptNotificationCallbacks || {};
      window.__airaUserScriptNotificationCallbacks[requestId] = {
        ondone: typeof ondone === 'function' ? ondone : notificationDetails.ondone
      };
      var text = String(notificationDetails.text || notificationDetails.title || '');
      if (!__airaRequestNativeBridge(__airaNativeRoutes.notification, {
        id: requestId,
        title: String(notificationDetails.title || ''),
        text: String(notificationDetails.text || '')
      }) && text.length > 0) {
        console.info('[AiraUserScript][notification][' + __airaScriptName + '] ' + text);
      }
      if (typeof notificationDetails.onclick === 'function') {
        window.__airaLastUserScriptNotificationClick = notificationDetails.onclick;
      }
      if (!window.__airaUserScriptNativeBridge && typeof ondone === 'function') {
        setTimeout(function() {
          delete window.__airaUserScriptNotificationCallbacks[requestId];
          ondone();
        }, 0);
      }
    };
    window.__airaUserScriptNotificationDispatch = window.__airaUserScriptNotificationDispatch || function(event) {
      var callbacks = window.__airaUserScriptNotificationCallbacks || {};
      var requestCallbacks = callbacks[String(event && event.id || '')];
      if (!requestCallbacks) {
        return;
      }
      delete callbacks[String(event.id || '')];
      if (typeof requestCallbacks.ondone === 'function') {
        requestCallbacks.ondone();
      }
    };
    var GM_setClipboard = function(data) {
      __airaRequireGrant('GM_setClipboard', __airaGrants.setClipboard);
      __airaRequestNativeBridge(__airaNativeRoutes.setClipboard, {
        text: String(data || '')
      });
    };
    var GM_log = function(message) {
      __airaRequireGrant('GM_log', __airaGrants.log);
      console.log('[AiraUserScript][' + __airaScriptName + '] ' + String(message || ''));
    };
    window.__airaUserScriptTabStorageCallbacks = window.__airaUserScriptTabStorageCallbacks || {};
    window.__airaUserScriptTabStorageDispatch = window.__airaUserScriptTabStorageDispatch || function(event) {
      var callbacks = window.__airaUserScriptTabStorageCallbacks || {};
      var callback = callbacks[String(event && event.id || '')];
      if (!callback) {
        return;
      }
      delete callbacks[String(event.id || '')];
      callback(event);
    };
    var __airaRequestTabStorage = function(route, value) {
      var bridge = window.__airaUserScriptNativeBridge;
      if (!route || !bridge || typeof bridge.request !== 'function' || !__airaNativeBridgeToken) {
        return Promise.reject(new Error('userscript-native-bridge-unavailable'));
      }
      var requestId = __airaScriptId + '-tab-' + (__airaNextNativeRequestId++);
      return new Promise(function(resolve, reject) {
        window.__airaUserScriptTabStorageCallbacks[requestId] = function(event) {
          if (event && event.success === true) {
            resolve(event.value || {});
            return;
          }
          reject(new Error(String(event && event.error || 'tab-storage-failed')));
        };
        bridge.request(JSON.stringify({
          kind: route.requestKind,
          id: requestId,
          scriptId: __airaScriptId,
          token: __airaNativeBridgeToken,
          capability: route.capability,
          tab: value || {}
        }));
      });
    };
    var GM_getTab = function(callback) {
      __airaRequireGrant('GM_getTab', __airaGrants.getTab);
      var promise = __airaRequestTabStorage(__airaNativeRoutes.getTab, {});
      if (typeof callback === 'function') {
        promise.then(function(tab) { callback(tab); }).catch(function() { callback({}); });
      }
      return promise;
    };
    var GM_saveTab = function(tab) {
      __airaRequireGrant('GM_saveTab', __airaGrants.saveTab);
      return __airaRequestTabStorage(__airaNativeRoutes.saveTab, tab || {});
    };
    var GM_getTabs = function(callback) {
      __airaRequireGrant('GM_getTabs', __airaGrants.getTabs);
      var promise = __airaRequestTabStorage(__airaNativeRoutes.getTabs, {});
      if (typeof callback === 'function') {
        promise.then(function(tabs) { callback(tabs); }).catch(function() { callback({}); });
      }
      return promise;
    };
    window.__airaUserScriptDownloadCallbacks = window.__airaUserScriptDownloadCallbacks || {};
    window.__airaUserScriptDownloadDispatch = window.__airaUserScriptDownloadDispatch || function(event) {
      var callbacks = window.__airaUserScriptDownloadCallbacks || {};
      var requestCallbacks = callbacks[String(event && event.id || '')];
      if (!requestCallbacks) {
        return;
      }
      var downloadEvent = {
        statusText: String(event && event.statusText || ''),
        loaded: Number(event && event.loaded || 0),
        total: Number(event && event.total || 0),
        lengthComputable: event && event.lengthComputable === true,
        status: String(event && event.status || '')
      };
      if (event && event.type === 'progress') {
        if (typeof requestCallbacks.onprogress === 'function') {
          requestCallbacks.onprogress(downloadEvent);
        }
        return;
      }
      delete callbacks[String(event.id || '')];
      if (event && event.type === 'load') {
        if (typeof requestCallbacks.onload === 'function') {
          requestCallbacks.onload(downloadEvent);
        }
        requestCallbacks.resolve(downloadEvent);
        return;
      }
      var error = downloadEvent;
      if (!error.statusText) {
        error.statusText = 'download-failed';
      }
      if (typeof requestCallbacks.onerror === 'function') {
        requestCallbacks.onerror(error);
        requestCallbacks.resolve(error);
        return;
      }
      requestCallbacks.reject(error);
    };
    var GM_download = function(details, name) {
      __airaRequireGrant('GM_download', __airaGrants.download);
      var downloadDetails = typeof details === 'string' ? { url: details, name: name } : (details || {});
      var bridge = window.__airaUserScriptNativeBridge;
      var route = __airaNativeRoutes.download;
      if (!route || !bridge || typeof bridge.request !== 'function' || !__airaNativeBridgeToken) {
        var bridgeError = { statusText: 'userscript-native-bridge-unavailable' };
        if (typeof downloadDetails.onerror === 'function') {
          setTimeout(function() { downloadDetails.onerror(bridgeError); }, 0);
        }
        return { abort: function() {} };
      }
      var requestId = __airaScriptId + '-download-' + (__airaNextNativeRequestId++);
      var promise = new Promise(function(resolve, reject) {
        window.__airaUserScriptDownloadCallbacks[requestId] = {
          onload: downloadDetails.onload,
          onerror: downloadDetails.onerror,
          onprogress: downloadDetails.onprogress,
          resolve: resolve,
          reject: reject
        };
        bridge.request(JSON.stringify({
          kind: route.requestKind,
          id: requestId,
          scriptId: __airaScriptId,
          token: __airaNativeBridgeToken,
          capability: route.capability,
          url: String(downloadDetails.url || ''),
          name: String(downloadDetails.name || ''),
          headers: __airaCollectHeaders(downloadDetails.headers)
        }));
      });
      promise.abort = function() {
        delete window.__airaUserScriptDownloadCallbacks[requestId];
      };
      return promise;
    };
    window.__airaUserScriptNativeRequestCallbacks = window.__airaUserScriptNativeRequestCallbacks || {};
    window.__airaUserScriptNativeRequestDispatch = window.__airaUserScriptNativeRequestDispatch || function(event) {
      var callbacks = window.__airaUserScriptNativeRequestCallbacks || {};
      var requestCallbacks = callbacks[String(event && event.id || '')];
      if (!requestCallbacks) {
        return;
      }
      var base64ToArrayBuffer = function(base64) {
        var normalized = String(base64 || '');
        if (!normalized) {
          return new ArrayBuffer(0);
        }
        var binary = atob(normalized);
        var bytes = new Uint8Array(binary.length);
        for (var index = 0; index < binary.length; index += 1) {
          bytes[index] = binary.charCodeAt(index);
        }
        return bytes.buffer;
      };
      var findHeader = function(headers, name) {
        var target = String(name || '').toLowerCase();
        var lines = String(headers || '').split(/\\r?\\n/);
        for (var index = 0; index < lines.length; index += 1) {
          var line = lines[index];
          var separator = line.indexOf(':');
          if (separator <= 0) {
            continue;
          }
          if (line.slice(0, separator).trim().toLowerCase() === target) {
            return line.slice(separator + 1).trim();
          }
        }
        return '';
      };
      var responseText = String(event.responseText || '');
      var response = responseText;
      if (event.responseType === 'json') {
        try {
          response = responseText.length > 0 ? JSON.parse(responseText) : null;
        } catch (_error) {
          response = null;
        }
      } else if (event.responseType === 'arraybuffer') {
        response = base64ToArrayBuffer(event.responseBase64);
      } else if (event.responseType === 'blob') {
        var contentType = findHeader(event.responseHeaders, 'content-type');
        response = new Blob([base64ToArrayBuffer(event.responseBase64)], contentType ? { type: contentType } : undefined);
      } else if (event.responseType === 'base64') {
        response = String(event.responseBase64 || '');
      }
      var normalizedResponse = {
        finalUrl: event.finalUrl || '',
        responseURL: event.finalUrl || '',
        readyState: event.readyState || 4,
        status: event.status || 0,
        statusText: event.statusText || '',
        responseHeaders: event.responseHeaders || '',
        response: response,
        responseText: responseText
      };
      if (typeof requestCallbacks.onreadystatechange === 'function') {
        requestCallbacks.onreadystatechange(normalizedResponse);
      }
      if (event.type === 'load' && typeof requestCallbacks.onload === 'function') {
        requestCallbacks.onload(normalizedResponse);
      } else if (event.type === 'timeout' && typeof requestCallbacks.ontimeout === 'function') {
        requestCallbacks.ontimeout(normalizedResponse);
      } else if (event.type === 'abort' && typeof requestCallbacks.onabort === 'function') {
        requestCallbacks.onabort(normalizedResponse);
      } else if (event.type !== 'load' && typeof requestCallbacks.onerror === 'function') {
        requestCallbacks.onerror(normalizedResponse);
      }
      if (event.type === 'load' || event.type === 'timeout' || event.type === 'abort' || event.type === 'error') {
        if (typeof requestCallbacks.onloadend === 'function') {
          requestCallbacks.onloadend(normalizedResponse);
        }
        delete callbacks[String(event.id || '')];
      }
    };
    var __airaHasHeader = function(headers, targetName) {
      var target = String(targetName || '').toLowerCase();
      return Object.keys(headers || {}).some(function(name) {
        return String(name || '').toLowerCase() === target;
      });
    };
    var __airaSetHeaderIfMissing = function(headers, name, value) {
      if (!__airaHasHeader(headers, name) && String(value || '').length > 0) {
        headers[name] = String(value);
      }
    };
    var __airaCollectHeaders = function(sourceHeaders) {
      var headers = {};
      if (!sourceHeaders) {
        return headers;
      }
      if (typeof sourceHeaders.forEach === 'function') {
        sourceHeaders.forEach(function(value, name) {
          headers[String(name)] = String(value);
        });
        return headers;
      }
      Object.keys(sourceHeaders || {}).forEach(function(name) {
        var value = sourceHeaders[name];
        if (value === undefined || value === null) {
          return;
        }
        if (Array.isArray(value)) {
          headers[String(name)] = value.map(function(item) { return String(item); }).join(', ');
          return;
        }
        headers[String(name)] = String(value);
      });
      return headers;
    };
    var __airaEncodeTextBytes = function(text) {
      if (typeof TextEncoder === 'function') {
        return new TextEncoder().encode(String(text));
      }
      var encoded = unescape(encodeURIComponent(String(text)));
      var bytes = new Uint8Array(encoded.length);
      for (var index = 0; index < encoded.length; index += 1) {
        bytes[index] = encoded.charCodeAt(index);
      }
      return bytes;
    };
    var __airaBytesToBase64 = function(bytes) {
      var binary = '';
      var chunkSize = 0x8000;
      for (var offset = 0; offset < bytes.length; offset += chunkSize) {
        var chunk = bytes.subarray(offset, Math.min(offset + chunkSize, bytes.length));
        binary += String.fromCharCode.apply(null, Array.prototype.slice.call(chunk));
      }
      return btoa(binary);
    };
    var __airaArrayBufferToBase64 = function(buffer) {
      return __airaBytesToBase64(new Uint8Array(buffer || new ArrayBuffer(0)));
    };
    var __airaReadBlobAsArrayBuffer = function(blob) {
      if (blob && typeof blob.arrayBuffer === 'function') {
        return blob.arrayBuffer();
      }
      return new Promise(function(resolve, reject) {
        var reader = new FileReader();
        reader.onload = function() { resolve(reader.result || new ArrayBuffer(0)); };
        reader.onerror = function() { reject(reader.error || new Error('blob-read-failed')); };
        reader.readAsArrayBuffer(blob);
      });
    };
    var __airaConcatBytes = function(chunks) {
      var total = chunks.reduce(function(sum, chunk) { return sum + chunk.length; }, 0);
      var result = new Uint8Array(total);
      var offset = 0;
      chunks.forEach(function(chunk) {
        result.set(chunk, offset);
        offset += chunk.length;
      });
      return result;
    };
    var __airaBuildMultipartBody = function(formData, headers) {
      var boundary = '----aira-userscript-' + Date.now() + '-' + Math.random().toString(16).slice(2);
      __airaSetHeaderIfMissing(headers, 'Content-Type', 'multipart/form-data; boundary=' + boundary);
      var chunks = [];
      var pending = Promise.resolve();
      formData.forEach(function(value, name) {
        pending = pending.then(function() {
          var disposition = '--' + boundary + '\\r\\nContent-Disposition: form-data; name="' +
            String(name).replace(/"/g, '%22') + '"';
          if (value instanceof Blob) {
            var filename = value.name || 'blob';
            var contentType = value.type || 'application/octet-stream';
            chunks.push(__airaEncodeTextBytes(disposition + '; filename="' +
              String(filename).replace(/"/g, '%22') + '"\\r\\nContent-Type: ' + contentType + '\\r\\n\\r\\n'));
            return __airaReadBlobAsArrayBuffer(value).then(function(buffer) {
              chunks.push(new Uint8Array(buffer));
              chunks.push(__airaEncodeTextBytes('\\r\\n'));
            });
          }
          chunks.push(__airaEncodeTextBytes(disposition + '\\r\\n\\r\\n' + String(value) + '\\r\\n'));
          return undefined;
        });
      });
      return pending.then(function() {
        chunks.push(__airaEncodeTextBytes('--' + boundary + '--\\r\\n'));
        return {
          bodyKind: 'base64',
          data: __airaBytesToBase64(__airaConcatBytes(chunks))
        };
      });
    };
    var __airaPrepareNativeBody = function(requestDetails, headers) {
      var requestData = requestDetails.data;
      if ((requestData === undefined || requestData === null) && requestDetails.body !== undefined) {
        requestData = requestDetails.body;
      }
      if (requestData === undefined || requestData === null) {
        return Promise.resolve({ bodyKind: 'none', data: '' });
      }
      if (typeof requestData === 'string') {
        return Promise.resolve({ bodyKind: 'text', data: requestData });
      }
      if (typeof URLSearchParams === 'function' && requestData instanceof URLSearchParams) {
        __airaSetHeaderIfMissing(headers, 'Content-Type', 'application/x-www-form-urlencoded;charset=UTF-8');
        return Promise.resolve({ bodyKind: 'text', data: requestData.toString() });
      }
      if (typeof FormData === 'function' && requestData instanceof FormData) {
        return __airaBuildMultipartBody(requestData, headers);
      }
      if (requestData instanceof ArrayBuffer) {
        return Promise.resolve({ bodyKind: 'base64', data: __airaArrayBufferToBase64(requestData) });
      }
      if (ArrayBuffer.isView && ArrayBuffer.isView(requestData)) {
        var viewBuffer = requestData.buffer.slice(requestData.byteOffset, requestData.byteOffset + requestData.byteLength);
        return Promise.resolve({ bodyKind: 'base64', data: __airaArrayBufferToBase64(viewBuffer) });
      }
      if (typeof Blob === 'function' && requestData instanceof Blob) {
        __airaSetHeaderIfMissing(headers, 'Content-Type', requestData.type || 'application/octet-stream');
        return __airaReadBlobAsArrayBuffer(requestData).then(function(buffer) {
          return { bodyKind: 'base64', data: __airaArrayBufferToBase64(buffer) };
        });
      }
      if (typeof requestData === 'object') {
        __airaSetHeaderIfMissing(headers, 'Content-Type', 'application/json;charset=UTF-8');
        return Promise.resolve({ bodyKind: 'json', data: JSON.stringify(requestData) });
      }
      return Promise.resolve({ bodyKind: 'text', data: String(requestData) });
    };
    var __airaDispatchNativePreparationFailure = function(requestId, requestDetails, error) {
      window.__airaUserScriptNativeRequestDispatch({
        id: requestId,
        type: 'error',
        finalUrl: String(requestDetails.url || ''),
        readyState: 4,
        status: 0,
        statusText: 'body-serialization-failed: ' + (error && (error.message || String(error)) || 'unknown'),
        responseHeaders: '',
        responseText: '',
        responseBase64: '',
        responseType: String(requestDetails.responseType || '').toLowerCase()
      });
    };
    var __airaTryNativeXmlHttpRequest = function(requestDetails, route) {
      var bridge = window.__airaUserScriptNativeBridge;
      if (!route || !bridge || typeof bridge.request !== 'function' || !__airaNativeBridgeToken) {
        return null;
      }
      var requestId = __airaScriptId + '-' + (__airaNextNativeRequestId++);
      var aborted = false;
      window.__airaUserScriptNativeRequestCallbacks[requestId] = {
        onload: requestDetails.onload,
        onerror: requestDetails.onerror,
        ontimeout: requestDetails.ontimeout,
        onabort: requestDetails.onabort,
        onreadystatechange: requestDetails.onreadystatechange,
        onloadend: requestDetails.onloadend
      };
      var headers = __airaCollectHeaders(requestDetails.headers);
      __airaPrepareNativeBody(requestDetails, headers).then(function(body) {
        if (aborted) {
          return;
        }
        bridge.request(JSON.stringify({
          kind: route.requestKind,
          id: requestId,
          scriptId: __airaScriptId,
          token: __airaNativeBridgeToken,
          capability: route.capability,
          url: String(requestDetails.url || ''),
          method: String(requestDetails.method || 'GET').toUpperCase(),
          data: body.data,
          bodyKind: body.bodyKind,
          headers: headers,
          timeout: typeof requestDetails.timeout === 'number' ? requestDetails.timeout : 0,
          responseType: String(requestDetails.responseType || '').toLowerCase(),
          anonymous: requestDetails.anonymous === true || requestDetails.mozAnon === true,
          withCredentials: requestDetails.withCredentials === true,
          credentials: String(requestDetails.credentials || ''),
          redirect: String(requestDetails.redirect || '')
        }));
      }).catch(function(error) {
        if (!aborted) {
          __airaDispatchNativePreparationFailure(requestId, requestDetails, error);
        }
      });
      return {
        abort: function() {
          aborted = true;
          delete window.__airaUserScriptNativeRequestCallbacks[requestId];
          if (bridge && typeof bridge.abort === 'function') {
            bridge.abort(JSON.stringify({
              kind: route.requestKind,
              id: requestId,
              scriptId: __airaScriptId,
              token: __airaNativeBridgeToken,
              capability: route.capability
            }));
          }
        }
      };
    };
    var GM_xmlhttpRequest = function(details, skipGrantCheck, nativeRoute) {
      if (skipGrantCheck !== true) {
        __airaRequireGrant('GM_xmlhttpRequest', __airaGrants.xmlhttpRequest);
      }
      var requestDetails = details || {};
      var nativeRequest = __airaTryNativeXmlHttpRequest(
        requestDetails,
        nativeRoute || __airaNativeRoutes.xmlhttpRequest
      );
      if (nativeRequest !== null) {
        return nativeRequest;
      }
      var xhr = new XMLHttpRequest();
      var method = String(requestDetails.method || 'GET').toUpperCase();
      xhr.open(method, String(requestDetails.url || ''), true, requestDetails.user, requestDetails.password);
      Object.keys(requestDetails.headers || {}).forEach(function(name) {
        try {
          xhr.setRequestHeader(name, String(requestDetails.headers[name]));
        } catch (error) {}
      });
      if (requestDetails.responseType) {
        try {
          xhr.responseType = requestDetails.responseType;
        } catch (error) {}
      }
      if (typeof requestDetails.timeout === 'number') {
        xhr.timeout = requestDetails.timeout;
      }
      if (typeof requestDetails.withCredentials === 'boolean') {
        xhr.withCredentials = requestDetails.withCredentials;
      }
      var buildResponse = function() {
        return {
          finalUrl: xhr.responseURL || requestDetails.url || '',
          readyState: xhr.readyState,
          status: xhr.status,
          statusText: xhr.statusText,
          responseHeaders: xhr.getAllResponseHeaders ? xhr.getAllResponseHeaders() : '',
          response: xhr.response,
          responseText: typeof xhr.responseText === 'string' ? xhr.responseText : ''
        };
      };
      xhr.onreadystatechange = function() {
        if (typeof requestDetails.onreadystatechange === 'function') {
          requestDetails.onreadystatechange(buildResponse());
        }
      };
      xhr.onload = function() {
        if (typeof requestDetails.onload === 'function') {
          requestDetails.onload(buildResponse());
        }
      };
      xhr.onerror = function() {
        if (typeof requestDetails.onerror === 'function') {
          requestDetails.onerror(buildResponse());
        }
      };
      xhr.ontimeout = function() {
        if (typeof requestDetails.ontimeout === 'function') {
          requestDetails.ontimeout(buildResponse());
        }
      };
      var fallbackData = requestDetails.data;
      if ((fallbackData === undefined || fallbackData === null) && requestDetails.body !== undefined) {
        fallbackData = requestDetails.body;
      }
      xhr.send(fallbackData);
      return {
        abort: function() {
          xhr.abort();
        }
      };
    };
    var GM_xmlHttpRequestPromise = function(details, skipGrantCheck, nativeRoute) {
      var requestDetails = details || {};
      var nativeRequest = null;
      var promise = new Promise(function(resolve, reject) {
        var originalOnload = requestDetails.onload;
        var originalOnerror = requestDetails.onerror;
        var originalOntimeout = requestDetails.ontimeout;
        var originalOnabort = requestDetails.onabort;
        var wrappedDetails = {};
        Object.keys(requestDetails).forEach(function(key) {
          wrappedDetails[key] = requestDetails[key];
        });
        wrappedDetails.onload = function(response) {
          if (typeof originalOnload === 'function') {
            originalOnload.call(this, response);
          }
          resolve(response);
        };
        wrappedDetails.onerror = function(response) {
          if (typeof originalOnerror === 'function') {
            originalOnerror.call(this, response);
            resolve(response);
            return;
          }
          reject(response);
        };
        wrappedDetails.ontimeout = function(response) {
          if (typeof originalOntimeout === 'function') {
            originalOntimeout.call(this, response);
            resolve(response);
            return;
          }
          reject(response);
        };
        wrappedDetails.onabort = function(response) {
          if (typeof originalOnabort === 'function') {
            originalOnabort.call(this, response);
            resolve(response);
            return;
          }
          reject(response);
        };
        nativeRequest = GM_xmlhttpRequest(wrappedDetails, skipGrantCheck === true, nativeRoute);
      });
      promise.abort = function() {
        if (nativeRequest && typeof nativeRequest.abort === 'function') {
          nativeRequest.abort();
        }
      };
      return promise;
    };
    var __airaBuildFetchHeaders = function(responseHeaders) {
      var headerMap = {};
      String(responseHeaders || '').split(/\\r?\\n/).forEach(function(line) {
        var separator = line.indexOf(':');
        if (separator <= 0) {
          return;
        }
        var name = line.slice(0, separator).trim().toLowerCase();
        var value = line.slice(separator + 1).trim();
        if (!name) {
          return;
        }
        if (headerMap[name]) {
          headerMap[name] = headerMap[name] + ', ' + value;
          return;
        }
        headerMap[name] = value;
      });
      return {
        get: function(name) {
          return headerMap[String(name || '').toLowerCase()] || null;
        },
        has: function(name) {
          return Object.prototype.hasOwnProperty.call(headerMap, String(name || '').toLowerCase());
        },
        forEach: function(callback) {
          Object.keys(headerMap).forEach(function(name) {
            callback(headerMap[name], name);
          });
        },
        entries: function() {
          return Object.keys(headerMap).map(function(name) {
            return [name, headerMap[name]];
          })[Symbol.iterator]();
        },
        keys: function() {
          return Object.keys(headerMap)[Symbol.iterator]();
        },
        values: function() {
          return Object.keys(headerMap).map(function(name) {
            return headerMap[name];
          })[Symbol.iterator]();
        }
      };
    };
    var __airaBuildFetchResponse = function(xhrResponse) {
      var bodyText = String(xhrResponse && xhrResponse.responseText || '');
      var bodyValue = xhrResponse && xhrResponse.response !== undefined && xhrResponse.response !== null ?
        xhrResponse.response : bodyText;
      var headers = __airaBuildFetchHeaders(xhrResponse && xhrResponse.responseHeaders || '');
      return {
        ok: Number(xhrResponse && xhrResponse.status || 0) >= 200 && Number(xhrResponse && xhrResponse.status || 0) < 300,
        status: Number(xhrResponse && xhrResponse.status || 0),
        statusText: String(xhrResponse && xhrResponse.statusText || ''),
        url: String(xhrResponse && (xhrResponse.finalUrl || xhrResponse.responseURL) || ''),
        redirected: false,
        type: 'basic',
        headers: headers,
        clone: function() {
          return __airaBuildFetchResponse(xhrResponse || {});
        },
        text: function() {
          return Promise.resolve(bodyText);
        },
        json: function() {
          return Promise.resolve(bodyText.length > 0 ? JSON.parse(bodyText) : null);
        },
        arrayBuffer: function() {
          if (bodyValue instanceof ArrayBuffer) {
            return Promise.resolve(bodyValue);
          }
          if (bodyValue instanceof Blob && typeof bodyValue.arrayBuffer === 'function') {
            return bodyValue.arrayBuffer();
          }
          return Promise.resolve(__airaEncodeTextBytes(bodyText).buffer);
        },
        blob: function() {
          if (bodyValue instanceof Blob) {
            return Promise.resolve(bodyValue);
          }
          return Promise.resolve(new Blob([bodyValue instanceof ArrayBuffer ? bodyValue : bodyText]));
        }
      };
    };
    var GM_fetch = function(input, init) {
      __airaRequireGrant('GM_fetch', __airaGrants.fetch);
      var requestInit = init || {};
      var requestUrl = '';
      if (typeof input === 'string') {
        requestUrl = input;
      } else if (input && input.url !== undefined) {
        requestUrl = String(input.url || '');
      } else if (requestInit.url !== undefined) {
        requestUrl = String(requestInit.url || '');
      }
      var requestDetails = {
        url: requestUrl,
        method: String(requestInit.method || (input && input.method) || 'GET'),
        headers: requestInit.headers || (input && input.headers) || {},
        data: requestInit.body !== undefined ? requestInit.body : requestInit.data,
        timeout: typeof requestInit.timeout === 'number' ? requestInit.timeout : 0,
        responseType: requestInit.responseType || '',
        anonymous: requestInit.anonymous === true,
        withCredentials: requestInit.credentials === 'include' || requestInit.withCredentials === true,
        credentials: String(requestInit.credentials || '')
      };
      return GM_xmlHttpRequestPromise(requestDetails, true, __airaNativeRoutes.fetch).then(function(response) {
        return __airaBuildFetchResponse(response);
      });
    };
    var __airaSearchEngines = [
      { name: 'Bing', host: 'bing.com', url: 'https://www.bing.com/search?q=%keywords%' },
      { name: '百度', host: 'baidu.com', url: 'https://www.baidu.com/s?word=%keywords%' },
      { name: 'Google', host: 'google.com', url: 'https://www.google.com/search?q=%keywords%' },
      { name: 'DuckDuckGo', host: 'duckduckgo.com', url: 'https://duckduckgo.com/?q=%keywords%' },
      { name: '360搜索', host: 'so.com', url: 'https://www.so.com/s?q=%keywords%' },
      { name: '神马', host: 'sm.cn', url: 'https://m.sm.cn/s?q=%keywords%' }
    ];
    var GM_EX_getSearchEngines = function() {
      __airaRequireGrant('GM_EX_getSearchEngines', __airaGrants.exGetSearchEngines);
      return JSON.stringify(__airaSearchEngines);
    };
    var GM_EX_getAppSearchEngineUrl = function(text) {
      __airaRequireGrant('GM_EX_getAppSearchEngineUrl', __airaGrants.exGetAppSearchEngineUrl);
      var query = encodeURIComponent(String(text || ''));
      return __airaSearchEngines[0].url.replace('%keywords%', query);
    };
    var GM_EX_TTS = function(text) {
      __airaRequireGrant('GM_EX_TTS', __airaGrants.exTts);
      var spokenText = String(text || '').trim();
      if (spokenText.length === 0) {
        return false;
      }
      if (window.speechSynthesis && typeof SpeechSynthesisUtterance === 'function') {
        window.speechSynthesis.speak(new SpeechSynthesisUtterance(spokenText));
        return true;
      }
      console.info('[AiraUserScript][tts][' + __airaScriptName + '] ' + spokenText);
      return false;
    };
    var GM_EX_ShareTextToApp = function(text) {
      __airaRequireGrant('GM_EX_ShareTextToApp', __airaGrants.exShareTextToApp);
      var sharedText = String(text || '').trim();
      if (sharedText.length === 0) {
        return false;
      }
      if (navigator.share) {
        navigator.share({ text: sharedText }).catch(function(error) {
          console.warn('[AiraUserScript][share] ' + (error && (error.message || String(error)) || 'share-failed'));
        });
        return true;
      }
      if (navigator.clipboard && typeof navigator.clipboard.writeText === 'function') {
        navigator.clipboard.writeText(sharedText).catch(function(error) {
          console.warn('[AiraUserScript][share-copy] ' + (error && (error.message || String(error)) || 'copy-failed'));
        });
        return true;
      }
      console.info('[AiraUserScript][share][' + __airaScriptName + '] ' + sharedText);
      return false;
    };
    var GM_EX_sniffMedia = function() {
      __airaRequireGrant('GM_EX_sniffMedia', __airaGrants.exSniffMedia);
      return __airaRequestNativeBridge(__airaNativeRoutes.exSniffMedia, {});
    };
    var GM_webextPref = function(options) {
      return {
        get: function(key, defaultValue) {
          return GM_getValue(key, defaultValue);
        },
        set: function(key, value) {
          return __airaSetValuePromise(key, value);
        },
        delete: function(key) {
          return __airaDeleteValuePromise(key);
        },
        options: options || {}
      };
    };
    var GM = {
      addStyle: GM_addStyle,
      addElement: GM_addElement,
      getValue: __airaGetValuePromise,
      getValues: __airaGetValuesPromise,
      setValue: __airaSetValuePromise,
      setValues: __airaSetValuesPromise,
      deleteValue: __airaDeleteValuePromise,
      deleteValues: __airaDeleteValuesPromise,
      listValues: __airaListValuesPromise,
      getResourceText: function(name) { return Promise.resolve(GM_getResourceText(name)); },
      getResourceUrl: function(name) { return Promise.resolve(GM_getResourceURL(name)); },
      xmlHttpRequest: GM_xmlHttpRequestPromise,
      xmlhttpRequest: GM_xmlHttpRequestPromise,
      fetch: GM_fetch,
      download: GM_download,
      openInTab: GM_openInTab,
      getTab: GM_getTab,
      saveTab: GM_saveTab,
      getTabs: GM_getTabs,
      addValueChangeListener: GM_addValueChangeListener,
      removeValueChangeListener: GM_removeValueChangeListener,
      setClipboard: function(data, type) { GM_setClipboard(data, type); return Promise.resolve(); },
      log: GM_log,
      notification: GM_notification,
      registerMenuCommand: GM_registerMenuCommand,
      unregisterMenuCommand: GM_unregisterMenuCommand,
      info: GM_info
    };
    return {
      unsafeWindow: unsafeWindow,
      GM_info: GM_info,
      GM_script: GM_script,
      GM_addStyle: GM_addStyle,
      GM_addElement: GM_addElement,
      GM_getValue: GM_getValue,
      GM_getValues: GM_getValues,
      GM_setValue: GM_setValue,
      GM_setValues: GM_setValues,
      GM_deleteValue: GM_deleteValue,
      GM_deleteValues: GM_deleteValues,
      GM_listValues: GM_listValues,
      GM_getResourceText: GM_getResourceText,
      GM_getResourceURL: GM_getResourceURL,
      GM_addValueChangeListener: GM_addValueChangeListener,
      GM_removeValueChangeListener: GM_removeValueChangeListener,
      GM_registerMenuCommand: GM_registerMenuCommand,
      GM_unregisterMenuCommand: GM_unregisterMenuCommand,
      GM_openInTab: GM_openInTab,
      GM_notification: GM_notification,
      GM_setClipboard: GM_setClipboard,
      GM_log: GM_log,
      GM_getTab: GM_getTab,
      GM_saveTab: GM_saveTab,
      GM_getTabs: GM_getTabs,
      GM_download: GM_download,
      GM_xmlhttpRequest: GM_xmlhttpRequest,
      GM_xmlHttpRequestPromise: GM_xmlHttpRequestPromise,
      GM_fetch: GM_fetch,
      GM_EX_getSearchEngines: GM_EX_getSearchEngines,
      GM_EX_getAppSearchEngineUrl: GM_EX_getAppSearchEngineUrl,
      GM_EX_TTS: GM_EX_TTS,
      GM_EX_ShareTextToApp: GM_EX_ShareTextToApp,
      GM_EX_sniffMedia: GM_EX_sniffMedia,
      GM_webextPref: GM_webextPref,
      GM: GM,
      getValuePromise: __airaGetValuePromise,
      setValuePromise: __airaSetValuePromise,
      deleteValuePromise: __airaDeleteValuePromise
    };
  };
  return 'installed';
})();
//# sourceURL=aira-userscript-runtime-factory.js
`;
  }

  private buildUrlMatcherInstallScript(): string {
    return `
;(function airaInstallUserScriptUrlMatcher() {
  if (typeof window.__airaUserScriptIsExcludedV1 === 'function' &&
    typeof window.__airaUserScriptMatchesV1 === 'function') {
    return 'ready';
  }
  var parseTarget = function(url) {
    var value = String(url || '').trim();
    var targetUrl;
    try {
      targetUrl = new URL(value);
    } catch (_error) {
      return undefined;
    }
    return {
      url: value,
      scheme: String(targetUrl.protocol || '').replace(/:$/, '').toLowerCase(),
      host: String(targetUrl.hostname || '').toLowerCase(),
      path: String(targetUrl.pathname || '/') + String(targetUrl.search || '') +
        String(targetUrl.hash || '')
    };
  };
  var regexSpecialCharacters = '.+?^$(){}|[]\\\\';
  var matcherRegexCache = Object.create(null);
  var matcherRegexCacheSize = 0;
  var matcherRegexCacheLimit = 512;
  var getCachedMatcherRegex = function(key, source, flags) {
    var cached = matcherRegexCache[key];
    if (cached) {
      return cached;
    }
    try {
      var compiled = new RegExp(source, flags || '');
      if (matcherRegexCacheSize < matcherRegexCacheLimit) {
        matcherRegexCache[key] = compiled;
        matcherRegexCacheSize += 1;
      }
      return compiled;
    } catch (_error) {
      return undefined;
    }
  };
  var escapeRegex = function(input) {
    return String(input || '').split('').map(function(character) {
      return regexSpecialCharacters.indexOf(character) >= 0 ? '\\\\' + character : character;
    }).join('');
  };
  var wildcardTest = function(pattern, input) {
    var normalizedPattern = String(pattern || '');
    var regex = getCachedMatcherRegex(
      'wildcard:' + normalizedPattern,
      '^' + escapeRegex(normalizedPattern).split('*').join('.*') + '$',
      ''
    );
    if (!regex) {
      return false;
    }
    return regex.test(input);
  };
  var matchPatternTest = function(target, pattern) {
    var rule = String(pattern || '').trim();
    if (rule === '<all_urls>') {
      return target.scheme === 'http' || target.scheme === 'https';
    }
    var separatorIndex = rule.indexOf('://');
    if (separatorIndex <= 0) {
      return false;
    }
    var schemeRule = rule.slice(0, separatorIndex).toLowerCase();
    var remainder = rule.slice(separatorIndex + 3);
    var slashIndex = remainder.indexOf('/');
    var hostRule = (slashIndex < 0 ? remainder : remainder.slice(0, slashIndex)).toLowerCase();
    var pathRule = slashIndex < 0 ? '/*' : remainder.slice(slashIndex);
    var schemeMatches = schemeRule === '*' || schemeRule === target.scheme;
    var hostMatches = hostRule === '*' || hostRule === target.host;
    if (!hostMatches && hostRule.indexOf('*.') === 0) {
      var suffix = hostRule.slice(2);
      hostMatches = target.host === suffix || target.host.endsWith('.' + suffix);
    }
    return schemeMatches && hostMatches && wildcardTest(pathRule, target.path);
  };
  var includePatternTest = function(value, pattern) {
    var rule = String(pattern || '').trim();
    var lastSlashIndex = rule.lastIndexOf('/');
    if (rule.length >= 2 && rule.indexOf('/') === 0 && lastSlashIndex > 0) {
      var source = rule.slice(1, lastSlashIndex);
      var flags = rule.slice(lastSlashIndex + 1).replace(/[^dgimsuvy]/g, '');
      var regex = getCachedMatcherRegex('regex:' + source + '\\u0000' + flags, source, flags);
      if (!regex) {
        return false;
      }
      regex.lastIndex = 0;
      return regex.test(value);
    }
    return wildcardTest(rule, value);
  };
  window.__airaUserScriptIsExcludedV1 = function(url, excludeMatches, excludes) {
    var target = parseTarget(url);
    if (!target) {
      return true;
    }
    return (Array.isArray(excludeMatches) && excludeMatches.some(function(pattern) {
      return matchPatternTest(target, pattern);
    })) || (Array.isArray(excludes) && excludes.some(function(pattern) {
      return includePatternTest(target.url, pattern);
    }));
  };
  window.__airaUserScriptMatchesV1 = function(url, matches, includes) {
    var target = parseTarget(url);
    if (!target || (target.scheme !== 'http' && target.scheme !== 'https')) {
      return false;
    }
    var compatibleTargets = [target];
    if (target.host === 'wk.baidu.com' && target.path.indexOf('/tfview/') === 0) {
      var compatiblePath = '/view/' + target.path.slice('/tfview/'.length);
      compatibleTargets.push({
        url: target.url.slice(0, target.url.length - target.path.length) + compatiblePath,
        scheme: target.scheme,
        host: target.host,
        path: compatiblePath
      });
    }
    return compatibleTargets.some(function(candidate) {
      return (Array.isArray(matches) && matches.some(function(pattern) {
        return matchPatternTest(candidate, pattern);
      })) || (Array.isArray(includes) && includes.some(function(pattern) {
        return includePatternTest(candidate.url, pattern);
      }));
    });
  };
  return 'installed';
})();
//# sourceURL=aira-userscript-url-matcher.js
`;
  }


  private buildResourceTextLiteral(script: InstalledUserScriptState): string {
    return JSON.stringify(script.resources.reduce((accumulator: Record<string, string>, resource) => {
      accumulator[resource.name] = resource.text;
      return accumulator;
    }, {} as Record<string, string>));
  }

  private buildResourceUrlLiteral(script: InstalledUserScriptState): string {
    return JSON.stringify(script.resources.reduce((accumulator: Record<string, string>, resource) => {
      const mimeType = this.normalizeResourceMimeType(resource.mimeType);
      const contentBase64 = resource.contentBase64?.trim() ?? '';
      accumulator[resource.name] = resource.contentBase64 !== undefined
        ? `data:${mimeType};base64,${contentBase64}`
        : `data:${mimeType};charset=utf-8,${this.encodeResourceTextForDataUrl(resource.text)}`;
      return accumulator;
    }, {} as Record<string, string>));
  }

  private encodeResourceTextForDataUrl(value: string): string {
    try {
      return encodeURIComponent(this.replaceUnpairedSurrogates(value));
    } catch (_error) {
      return '';
    }
  }

  private replaceUnpairedSurrogates(value: string): string {
    let normalized = '';
    for (let index = 0; index < value.length; index++) {
      const current = value.charCodeAt(index);
      if (current >= 0xD800 && current <= 0xDBFF) {
        const next = index + 1 < value.length ? value.charCodeAt(index + 1) : -1;
        if (next >= 0xDC00 && next <= 0xDFFF) {
          normalized += value.charAt(index) + value.charAt(index + 1);
          index++;
        } else {
          normalized += '\uFFFD';
        }
      } else if (current >= 0xDC00 && current <= 0xDFFF) {
        normalized += '\uFFFD';
      } else {
        normalized += value.charAt(index);
      }
    }
    return normalized;
  }

  private normalizeResourceMimeType(value: string): string {
    const normalized = value.trim().toLowerCase().split(';')[0].trim();
    return /^[a-z0-9][a-z0-9!#$&^_.+-]*\/[a-z0-9][a-z0-9!#$&^_.+-]*$/.test(normalized)
      ? normalized
      : 'application/octet-stream';
  }

}
