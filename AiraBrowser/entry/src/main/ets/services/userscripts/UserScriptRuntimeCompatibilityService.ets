import { InstalledUserScriptState } from '../../features/userscripts/UserScriptMetadataModels';

export interface UserScriptRuntimeCompatibilityCommand {
  commandId: string;
  commandName: string;
  source: string;
  failureReason: string;
}

export interface UserScriptRuntimeCompatibilityInjectionProfile {
  standaloneOptionsPageUrls: string[];
  bridgeRuntimeSource: string;
  postScriptSource: string;
}

export class UserScriptRuntimeCompatibilityService {
  buildInjectionProfile(script: InstalledUserScriptState): UserScriptRuntimeCompatibilityInjectionProfile {
    const standaloneOptionsPageUrls = this.resolveStandaloneOptionsPageUrls(script);
    return {
      standaloneOptionsPageUrls: standaloneOptionsPageUrls,
      bridgeRuntimeSource: standaloneOptionsPageUrls.length > 0 ? this.buildStandaloneOptionsBridgeRuntimeSource() : '',
      postScriptSource: this.buildPostScriptPatch(script)
    };
  }

  resolveFallbackMenuCommand(script: InstalledUserScriptState): UserScriptRuntimeCompatibilityCommand | undefined {
    if (this.isDarkmodeScript(script)) {
      return {
        commandId: '__aira_darkmode_toggle__',
        commandName: '切换夜间模式',
        source: this.buildDarkmodeToggleScript(),
        failureReason: 'darkmode-toggle-failed'
      };
    }
    if (this.isCircleReaderScript(script)) {
      return {
        commandId: '__aira_circle_reader_entry__',
        commandName: '打开阅读助手入口',
        source: this.buildCircleReaderEntryScript(),
        failureReason: 'circle-reader-entry-failed'
      };
    }
    return undefined;
  }

  resolveMenuCommand(
    script: InstalledUserScriptState,
    commandId: string
  ): UserScriptRuntimeCompatibilityCommand | undefined {
    const command = this.resolveFallbackMenuCommand(script);
    return command?.commandId === commandId.trim() ? command : undefined;
  }

  normalizeRegisteredMenuCommandDisplayName(script: InstalledUserScriptState, name: string): string {
    const normalizedName = name
      .replace(/：$/u, '')
      .replace(/:$/u, '')
      .trim();
    if (this.isDarkmodeScript(script) && normalizedName === '当前网站') {
      return '当前网站夜间模式';
    }
    return normalizedName;
  }

  private buildPostScriptPatch(script: InstalledUserScriptState): string {
    if (!this.isDarkmodeScript(script)) {
      return '';
    }
    return `
    ;(function airaDarkmodeMobilePatch() {
      var patchButton = function() {
        var container = document.getElementById('darkmode-container');
        var button = document.getElementById('darkmode-button');
        if (!container || !button) {
          return false;
        }
        container.style.position = 'fixed';
        container.style.left = 'auto';
        container.style.right = '16px';
        container.style.top = 'auto';
        container.style.bottom = 'calc(16px + env(safe-area-inset-bottom, 0px))';
        container.style.transform = 'none';
        container.style.opacity = '1';
        container.style.pointerEvents = 'auto';
        container.style.zIndex = '2147483647';
        button.style.width = '56px';
        button.style.height = '56px';
        button.style.borderRadius = '999px';
        button.style.boxShadow = '0 10px 28px rgba(0, 0, 0, 0.28)';
        button.style.border = 'none';
        button.style.opacity = '1';
        button.style.transform = 'none';
        button.style.transition = 'none';
        var svgLight = document.getElementById('svg-light');
        var svgDark = document.getElementById('svg-dark');
        if (svgLight) {
          svgLight.style.transform = 'scale(1)';
          svgLight.style.opacity = '1';
        }
        if (svgDark) {
          svgDark.style.transform = 'scale(0)';
          svgDark.style.opacity = '0';
        }
        return true;
      };
      if (!patchButton()) {
        setTimeout(patchButton, 0);
        setTimeout(patchButton, 300);
      }
      var observer = new MutationObserver(function() {
        patchButton();
      });
      observer.observe(document.documentElement || document, {
        childList: true,
        subtree: true
      });
      window.__airaDarkmodeMobilePatchObserver = observer;
    })();
`;
  }

  resolveStandaloneOptionsPageUrls(script: InstalledUserScriptState): string[] {
    const scriptName = script.name.toLowerCase();
    const source = script.source;
    const isKissTranslator = scriptName.indexOf('kiss translator') >= 0 ||
      source.indexOf('KISS Translator') >= 0 ||
      source.indexOf('kiss-translator') >= 0;
    if (!isKissTranslator || source.indexOf('APP_INFO') < 0) {
      return [];
    }
    const urls: string[] = [];
    const knownOptionsUrl = 'https://fishjar.github.io/kiss-translator/options.html';
    if (source.indexOf(knownOptionsUrl) >= 0 || scriptName.indexOf('kiss translator') >= 0) {
      urls.push(knownOptionsUrl);
    }
    return urls;
  }

  private isDarkmodeScript(script: InstalledUserScriptState): boolean {
    const normalizedName = script.name.trim();
    const normalizedId = script.id.trim();
    return normalizedId === 'darkmode' || normalizedName === '夜间模式助手';
  }

  private isCircleReaderScript(script: InstalledUserScriptState): boolean {
    const normalizedName = script.name.trim();
    const normalizedId = script.id.trim();
    const normalizedNamespace = script.namespace.trim();
    return normalizedId === 'circle-reader' ||
      normalizedName === 'Circle 阅读助手' ||
      normalizedNamespace === 'https://circlereader.com';
  }

  private buildDarkmodeToggleScript(): string {
    return `
;(function airaNativeDarkmodeToggle() {
  try {
    var button = document.getElementById('darkmode-button');
    if (button && typeof button.click === 'function') {
      button.click();
      return JSON.stringify({ success: true, errorMessage: '' });
    }
    var existing = document.getElementById('aira-native-darkmode-style');
    if (existing && existing.parentNode) {
      existing.parentNode.removeChild(existing);
      document.documentElement.style.backgroundColor = '';
      return JSON.stringify({ success: true, errorMessage: '' });
    }
    var style = document.createElement('style');
    style.id = 'aira-native-darkmode-style';
    style.textContent = [
      'html{filter:invert(0.86) hue-rotate(180deg) contrast(0.92) !important;background:#111 !important;}',
      'img,video,canvas,svg,image,picture,iframe{filter:invert(1) hue-rotate(180deg) contrast(1.08) !important;}',
      'html,body{background-color:#111 !important;}'
    ].join('\\n');
    (document.head || document.documentElement).appendChild(style);
    return JSON.stringify({ success: true, errorMessage: '' });
  } catch (error) {
    return JSON.stringify({
      success: false,
      errorMessage: String(error && (error.stack || error.message || error) || 'darkmode-toggle-failed')
    });
  }
})();
`;
  }

  private buildCircleReaderEntryScript(): string {
    return `
;(function airaNativeCircleReaderEntry() {
  try {
    var findEntry = function() {
      var host = document.getElementById('circlereader-entry');
      if (host && host.shadowRoot) {
        var shadowEntry = host.shadowRoot.querySelector('.entry-root');
        if (shadowEntry) {
          return shadowEntry;
        }
      }
      if (host) {
        return host;
      }
      var entries = Array.prototype.slice.call(document.querySelectorAll('*'));
      for (var index = 0; index < entries.length; index += 1) {
        var item = entries[index];
        if (item && item.shadowRoot) {
          var nested = item.shadowRoot.querySelector('#circlereader-entry, .entry-root');
          if (nested) {
            return nested;
          }
        }
      }
      return document.querySelector('.entry-root');
    };
    var entry = findEntry();
    if (!entry) {
      return JSON.stringify({ success: false, errorMessage: 'circle-reader-entry-not-found' });
    }
    var rect = entry.getBoundingClientRect ? entry.getBoundingClientRect() : { left: 0, top: 0, width: 1, height: 1 };
    var x = rect.left + Math.max(1, rect.width / 2);
    var y = rect.top + Math.max(1, rect.height / 2);
    var createMouseEvent = function(type) {
      return new MouseEvent(type, {
        bubbles: true,
        cancelable: true,
        view: window,
        clientX: x,
        clientY: y,
        button: 0,
        buttons: type === 'mouseup' ? 0 : 1
      });
    };
    entry.dispatchEvent(createMouseEvent('mousedown'));
    document.dispatchEvent(createMouseEvent('mouseup'));
    if (typeof entry.click === 'function') {
      entry.click();
    }
    return JSON.stringify({ success: true, errorMessage: '' });
  } catch (error) {
    return JSON.stringify({
      success: false,
      errorMessage: String(error && (error.stack || error.message || error) || 'circle-reader-entry-failed')
    });
  }
})();
`;
  }

  private buildStandaloneOptionsBridgeRuntimeSource(): string {
    return `
    var __airaKissOptionsEventName = '__aira_kiss_options_' + __airaScriptId;
    var __airaDispatchKissOptionsEvent = function(pong, data, error) {
      if (!pong) {
        return;
      }
      try {
        window.dispatchEvent(new CustomEvent(pong, {
          detail: error ? { error: String(error && (error.message || error)) } : { data: data }
        }));
      } catch (_error) {}
    };
    var __airaKissOptionsRequests = {};
    var __airaKissOptionsSupportedRequestCallbacks = [
      'onreadystatechange',
      'onload',
      'onerror',
      'onabort',
      'ontimeout',
      'onloadend'
    ];
    var __airaKissOptionsTerminalCallbacks = {
      onload: true,
      onerror: true,
      onabort: true,
      ontimeout: true
    };
    var __airaDispatchKissOptionsRequestCallback = function(pong, callbackName, data) {
      if (!pong) {
        return;
      }
      try {
        window.dispatchEvent(new CustomEvent(pong, {
          detail: { callback: callbackName, data: data }
        }));
      } catch (_error) {}
    };
    var __airaStartKissOptionsXmlHttpRequest = function(pong, args) {
      if (!pong) {
        return;
      }
      var requestDetails = {};
      Object.keys(args && args.details || {}).forEach(function(key) {
        requestDetails[key] = args.details[key];
      });
      var requestState = {
        handle: null,
        url: String(requestDetails.url || ''),
        terminal: false,
        ended: false
      };
      __airaKissOptionsRequests[pong] = requestState;
      __airaKissOptionsSupportedRequestCallbacks.forEach(function(callbackName) {
        requestDetails[callbackName] = function(data) {
          if (requestState.ended) {
            return;
          }
          if (callbackName === 'onloadend') {
            requestState.terminal = true;
            requestState.ended = true;
            delete __airaKissOptionsRequests[pong];
          } else if (__airaKissOptionsTerminalCallbacks[callbackName] === true) {
            if (requestState.terminal) {
              return;
            }
            requestState.terminal = true;
          } else if (requestState.terminal) {
            return;
          }
          __airaDispatchKissOptionsRequestCallback(pong, callbackName, data);
        };
      });
      try {
        requestState.handle = GM_xmlhttpRequest(requestDetails);
      } catch (error) {
        requestState.terminal = true;
        requestState.ended = true;
        delete __airaKissOptionsRequests[pong];
        __airaDispatchKissOptionsEvent(pong, undefined, error);
      }
    };
    var __airaAbortKissOptionsXmlHttpRequest = function(requestId) {
      var normalizedRequestId = String(requestId || '');
      var requestState = __airaKissOptionsRequests[normalizedRequestId];
      if (!requestState || requestState.terminal || requestState.ended) {
        return;
      }
      requestState.terminal = true;
      requestState.ended = true;
      delete __airaKissOptionsRequests[normalizedRequestId];
      if (requestState.handle && typeof requestState.handle.abort === 'function') {
        requestState.handle.abort();
      }
      var response = {
        finalUrl: requestState.url,
        responseURL: requestState.url,
        readyState: 0,
        status: 0,
        statusText: '',
        responseHeaders: '',
        response: null,
        responseText: ''
      };
      __airaDispatchKissOptionsRequestCallback(normalizedRequestId, 'onabort', response);
      __airaDispatchKissOptionsRequestCallback(normalizedRequestId, 'onloadend', response);
    };
    var __airaBuildKissOptionsAppInfo = function(eventName, value, exposeEventName) {
      var nextInfo = {};
      Object.keys(value || {}).forEach(function(key) {
        nextInfo[key] = value[key];
      });
      nextInfo.name = nextInfo.name || __airaScriptName;
      nextInfo.version = nextInfo.version || __airaScriptVersion;
      if (exposeEventName !== false) {
        nextInfo.eventName = nextInfo.eventName || eventName;
      } else {
        try {
          delete nextInfo.eventName;
        } catch (_error) {
          nextInfo.eventName = undefined;
        }
      }
      return nextInfo;
    };
    var __airaProtectKissOptionsAppInfo = function(eventName, exposeEventName) {
      eventName = String(eventName || '');
      if (!eventName || window.__airaKissOptionsAppInfoEventName === eventName) {
        return;
      }
      window.__airaKissOptionsAppInfoEventName = eventName;
      var appInfo = __airaBuildKissOptionsAppInfo(eventName, window.APP_INFO || {}, exposeEventName);
      try {
        Object.defineProperty(window, 'APP_INFO', {
          configurable: true,
          enumerable: true,
          get: function() {
            return appInfo;
          },
          set: function(value) {
            appInfo = __airaBuildKissOptionsAppInfo(eventName, value || {}, exposeEventName);
          }
        });
      } catch (_error) {
        window.APP_INFO = appInfo;
      }
    };
    var __airaRunKissOptionsTask = function(action, args) {
      args = args || {};
      if (action === 'setValue') {
        return __airaSetValuePromise(args.key, args.val);
      }
      if (action === 'getValue') {
        return __airaGetValuePromise(args.key, undefined);
      }
      if (action === 'deleteValue') {
        return __airaDeleteValuePromise(args.key);
      }
      if (action === 'info') {
        return Promise.resolve(GM_info);
      }
      return null;
    };
    var __airaInstallKissOptionsEventBridge = function(eventName) {
      eventName = String(eventName || '');
      if (!eventName || window.__airaKissOptionsEventBridgeName === eventName) {
        return;
      }
      if (window.__airaKissOptionsEventBridgeName) {
        return;
      }
      window.__airaKissOptionsEventBridgeName = eventName;
      window.addEventListener(eventName, function(event) {
        var detail = event && event.detail || {};
        var args = detail.args || {};
        var pong = String(detail.pong || '');
        var action = String(detail.action || '');
        if (action === 'xmlHttpRequest') {
          if (Object.prototype.hasOwnProperty.call(args, 'input')) {
            GM_fetch(args.input, args.init || {}).then(function(value) {
              __airaDispatchKissOptionsEvent(pong, value, '');
            }).catch(function(error) {
              __airaDispatchKissOptionsEvent(pong, undefined, error);
            });
            return;
          }
          __airaStartKissOptionsXmlHttpRequest(pong, args);
          return;
        }
        if (action === 'xmlHttpRequestAbort') {
          __airaAbortKissOptionsXmlHttpRequest(args.requestId);
          return;
        }
        var task = __airaRunKissOptionsTask(action, args);
        if (!task) {
          __airaDispatchKissOptionsEvent(pong, undefined, 'unsupported-kiss-options-action:' + action);
          return;
        }
        task.then(function(value) {
          __airaDispatchKissOptionsEvent(pong, value, '');
        }).catch(function(error) {
          __airaDispatchKissOptionsEvent(pong, undefined, error);
        });
      });
    };
    var __airaInstallKissOptionsDomBridge = function(eventName) {
      eventName = String(eventName || '');
      if (!eventName || window.__airaKissOptionsDomBridgeName === eventName) {
        return;
      }
      window.__airaKissOptionsDomBridgeName = eventName;
      var selector = '[data-aira-kiss-options-request="1"]';
      var respond = function(node, response) {
        try {
          node.textContent = JSON.stringify(response || {});
          node.setAttribute('data-aira-kiss-options-response-ready', '1');
        } catch (_error) {}
      };
      var processNode = function(node) {
        if (!node || node.nodeType !== 1 || typeof node.getAttribute !== 'function') {
          return;
        }
        var element = node;
        var candidates = [];
        if (element.getAttribute('data-aira-kiss-options-request') === '1') {
          candidates.push(element);
        }
        if (typeof element.querySelectorAll === 'function') {
          var nested = element.querySelectorAll(selector);
          for (var index = 0; index < nested.length; index += 1) {
            candidates.push(nested[index]);
          }
        }
        candidates.forEach(function(candidate) {
          if (candidate.getAttribute('data-aira-kiss-options-event') !== eventName ||
            candidate.getAttribute('data-aira-kiss-options-processing') === '1') {
            return;
          }
          candidate.setAttribute('data-aira-kiss-options-processing', '1');
          var request = {};
          try {
            request = JSON.parse(String(candidate.textContent || '{}'));
          } catch (_error) {
            respond(candidate, { id: '', error: 'invalid-dom-request' });
            return;
          }
          var action = String(request.action || '');
          var task = __airaRunKissOptionsTask(action, request.args || {});
          if (!task) {
            respond(candidate, { id: String(request.id || ''), error: 'unsupported-kiss-options-action:' + action });
            return;
          }
          task.then(function(value) {
            respond(candidate, { id: String(request.id || ''), data: value });
          }).catch(function(error) {
            respond(candidate, {
              id: String(request.id || ''),
              error: String(error && (error.message || error) || 'kiss-options-dom-bridge-failed')
            });
          });
        });
      };
      var observeRoot = function() {
        var root = document.documentElement || document.body;
        if (!root || typeof MutationObserver !== 'function') {
          setTimeout(observeRoot, 50);
          return;
        }
        processNode(root);
        var observer = new MutationObserver(function(mutations) {
          mutations.forEach(function(mutation) {
            for (var index = 0; index < mutation.addedNodes.length; index += 1) {
              processNode(mutation.addedNodes[index]);
            }
          });
        });
        observer.observe(root, { childList: true, subtree: true });
      };
      observeRoot();
    };
    var __airaInstallKissOptionsMessageBridge = function(eventName) {
      eventName = String(eventName || '');
      if (!eventName || window.__airaKissOptionsMessageBridgeName === eventName) {
        return;
      }
      window.__airaKissOptionsMessageBridgeName = eventName;
      window.addEventListener('message', function(event) {
        var request = event && event.data || {};
        if (!request || request.__airaKissOptionsRequest !== true || request.eventName !== eventName) {
          return;
        }
        var id = String(request.id || '');
        var action = String(request.action || '');
        var task = __airaRunKissOptionsTask(action, request.args || {});
        var respond = function(response) {
          try {
            window.postMessage(Object.assign({
              __airaKissOptionsResponse: true,
              eventName: eventName,
              id: id
            }, response || {}), '*');
          } catch (_error) {}
        };
        if (!task) {
          respond({ error: 'unsupported-kiss-options-action:' + action });
          return;
        }
        task.then(function(value) {
          respond({ data: value });
        }).catch(function(error) {
          respond({ error: String(error && (error.message || error) || 'kiss-options-message-bridge-failed') });
        });
      });
    };
    var __airaInstallKissOptionsPageBridge = function(eventName) {
      eventName = String(eventName || '');
      if (!eventName) {
        return;
      }
      var source = ';(function airaKissOptionsPageBridge(){' +
        'var eventName=' + JSON.stringify(eventName) + ';' +
        'if(!eventName||window.__airaKissOptionsPageBridgeName===eventName){return;}' +
        'window.__airaKissOptionsPageBridgeName=eventName;' +
        'function buildAppInfo(value){var next={};Object.keys(value||{}).forEach(function(key){next[key]=value[key];});next.name=next.name||' + JSON.stringify(__airaScriptName) + ';next.version=next.version||' + JSON.stringify(__airaScriptVersion) + ';next.eventName=next.eventName||eventName;return next;}' +
        'function protectAppInfo(){var info=buildAppInfo(window.APP_INFO||{});try{Object.defineProperty(window,"APP_INFO",{configurable:true,enumerable:true,get:function(){return info;},set:function(value){info=buildAppInfo(value||{});}});}catch(_error){window.APP_INFO=info;}}' +
        'var previousKiss=window.KISS_GM||{};' +
        'var currentKiss=null;' +
        'var nextId=1;' +
        'var scriptId=' + JSON.stringify(__airaScriptId) + ';' +
        'var nativeToken=' + JSON.stringify(__airaNativeBridgeToken) + ';' +
        'var nativeRoutes=' + JSON.stringify(__airaNativeRoutes) + ';' +
        'function debug(_action,_key,_message){}' +
        'function buildNativePayload(action,args,id){var route=nativeRoutes[String(action||"")];if(!route){return null;}return{kind:route.requestKind,id:id,capability:route.capability,key:String(args&&args.key||""),val:args?args.val:undefined,scriptId:scriptId,token:nativeToken};}' +
        'window.__airaUserScriptValueCallbacks=window.__airaUserScriptValueCallbacks||{};' +
        'window.__airaUserScriptValueDispatch=window.__airaUserScriptValueDispatch||function(event){var callbacks=window.__airaUserScriptValueCallbacks||{};var requestCallbacks=callbacks[String(event&&event.id||"")];if(!requestCallbacks){return;}delete callbacks[String(event.id||"")];clearTimeout(requestCallbacks.timeoutId);if(event&&event.success===true){requestCallbacks.resolve(event||{});return;}requestCallbacks.reject(new Error(String(event&&event.error||"value-mutation-failed")));};' +
        'function dispatchPong(pong,data,error){if(!pong){return;}try{window.dispatchEvent(new CustomEvent(pong,{detail:error?{error:String(error&&error.message||error)}:{data:data}}));}catch(_error){}}' +
        'function resolveNativeValue(action,event){if(action==="getValue"){return event&&event.found===true?JSON.parse(String(event.valueJson||"null")):undefined;}return undefined;}' +
        'function requestMessage(action,args,timeout){return new Promise(function(resolve,reject){try{var id="__aira_kiss_options_message_"+Date.now()+"_"+(nextId++);var timer=setTimeout(function(){cleanup();reject(new Error("timeout"));},timeout||1500);function cleanup(){clearTimeout(timer);window.removeEventListener("message",onMessage);}function onMessage(event){var detail=event&&event.data||{};if(!detail||detail.__airaKissOptionsResponse!==true||detail.eventName!==eventName||detail.id!==id){return;}cleanup();if(detail.error){reject(new Error(String(detail.error)));return;}resolve(detail.data);}window.addEventListener("message",onMessage);window.postMessage({__airaKissOptionsRequest:true,eventName:eventName,id:id,action:action,args:args||{}},"*");}catch(error){reject(error);}});}' +
        'function requestDom(action,args,timeout){return new Promise(function(resolve,reject){try{var root=document.documentElement||document.body;if(!root){reject(new Error("document-not-ready"));return;}var id="__aira_kiss_options_dom_"+Date.now()+"_"+(nextId++);var node=document.createElement("div");node.style.display="none";node.setAttribute("data-aira-kiss-options-request","1");node.setAttribute("data-aira-kiss-options-event",eventName);node.setAttribute("data-aira-kiss-options-id",id);node.textContent=JSON.stringify({id:id,action:action,args:args||{}});var observer=new MutationObserver(function(){if(node.getAttribute("data-aira-kiss-options-response-ready")!=="1"){return;}cleanup();try{var detail=JSON.parse(String(node.textContent||"{}"));if(detail.error){reject(new Error(String(detail.error)));return;}resolve(detail.data);}catch(parseError){reject(parseError);}});function cleanup(){clearTimeout(timer);observer.disconnect();if(node.parentNode){node.parentNode.removeChild(node);}}var timer=setTimeout(function(){cleanup();reject(new Error("timeout"));},timeout||5000);observer.observe(node,{attributes:true,attributeFilter:["data-aira-kiss-options-response-ready"]});root.appendChild(node);}catch(error){reject(error);}});}' +
        'function requestNative(action,args,timeout){return new Promise(function(resolve,reject){' +
          'var bridge=window.__airaUserScriptNativeBridge;' +
          'if(!(action==="setValue"||action==="getValue"||action==="deleteValue")||!bridge||typeof bridge.request!=="function"||!nativeToken){debug("native-unavailable",args&&args.key,"bridge="+!!bridge+",token="+!!nativeToken);reject(new Error("userscript-native-bridge-unavailable"));return;}' +
          'try{var id="__aira_kiss_options_native_"+Date.now()+"_"+(nextId++);var payload=buildNativePayload(action,args||{},id);if(!payload){reject(new Error("unsupported-userscript-native-route"));return;}var timer=setTimeout(function(){delete window.__airaUserScriptValueCallbacks[id];reject(new Error("timeout"));},timeout||5000);window.__airaUserScriptValueCallbacks[id]={resolve:function(event){clearTimeout(timer);try{resolve(resolveNativeValue(action,event));}catch(parseError){reject(parseError);}},reject:function(error){clearTimeout(timer);reject(error);},timeoutId:timer};bridge.request(JSON.stringify(payload));}catch(nativeError){reject(nativeError);}' +
        '});}' +
        'function requestRelay(action,args,timeout){return requestMessage(action,args,1500).catch(function(){return requestDom(action,args,timeout);});}' +
        'function runRequest(action,args,timeout){var bridge=window.__airaUserScriptNativeBridge;if((action==="setValue"||action==="getValue"||action==="deleteValue")&&bridge&&typeof bridge.request==="function"&&nativeToken){return requestNative(action,args,timeout).catch(function(){return requestRelay(action,args,timeout);});}return requestRelay(action,args,timeout);}' +
        'function installPageEventBridge(){if(window.__airaKissOptionsPageEventBridgeName===eventName){return;}window.__airaKissOptionsPageEventBridgeName=eventName;debug("page-bridge-ready","",JSON.stringify({eventName:eventName,hasNativeBridge:!!window.__airaUserScriptNativeBridge,hasToken:!!nativeToken}));window.addEventListener(eventName,function(event){var detail=event&&event.detail||{};var action=String(detail.action||"");var args=detail.args||{};var pong=String(detail.pong||"");debug("page-event:"+action,args&&args.key,"pong="+!!pong+",hasNativeBridge="+!!window.__airaUserScriptNativeBridge);if(action==="info"){dispatchPong(pong,window.GM_info||window.GM&&window.GM.info,"");return;}if(action==="xmlHttpRequest"||action==="xmlHttpRequestAbort"){return;}runRequest(action,args,5000).then(function(value){dispatchPong(pong,value,"");}).catch(function(error){dispatchPong(pong,undefined,error);});});}' +
        'function request(action,args,timeout){return new Promise(function(resolve,reject){' +
          'runRequest(action,args,timeout).then(resolve).catch(function(){' +
            'var pong="__aira_kiss_options_pong_"+Date.now()+"_"+(nextId++);' +
            'var timer=setTimeout(function(){window.removeEventListener(pong,onPong);reject(new Error("timeout"));},timeout||5000);' +
            'function onPong(event){window.removeEventListener(pong,onPong);clearTimeout(timer);var detail=event&&event.detail||{};if(detail.error){reject(new Error(String(detail.error)));return;}resolve(detail.data);}' +
            'window.addEventListener(pong,onPong);' +
            'window.dispatchEvent(new CustomEvent(eventName,{detail:{action:action,args:args||{},pong:pong}}));' +
          '});' +
        '});}' +
        'function isKissStorageKey(key){key=String(key||"");return key==="KISS-Translator_setting"||key==="KISS-Translator_setting_v2"||key==="KISS-Translator_setting_v2_backup_v1_before_v2"||key==="KISS-Translator_rules"||key==="KISS-Translator_rules_v2"||key==="KISS-Translator_words"||key==="KISS-Translator_sync"||key==="KISS-Translator_fab"||key==="KISS-Translator_tranbox"||key==="KISS-Translator_disabled_sub_rules"||key==="KISS-Translator_msauth"||key==="KISS-Translator_bdauth"||key.indexOf("KISS-Translator_rulescache_")===0||key==="KISS Translator_setting"||key==="KISS Translator_setting_v2"||key==="KISS Translator_setting_v2_backup_v1_before_v2"||key==="KISS Translator_rules"||key==="KISS Translator_rules_v2"||key==="KISS Translator_words"||key==="KISS Translator_sync"||key==="KISS Translator_fab"||key==="KISS Translator_tranbox"||key==="KISS Translator_disabled_sub_rules"||key==="KISS Translator_msauth"||key==="KISS Translator_bdauth"||key.indexOf("KISS Translator_rulescache_")===0;}' +
        'function syncStorageKey(key,val,source){key=String(key||"");if(!isKissStorageKey(key)){return;}debug("sync-storage:"+String(source||""),key,String(val||"").slice(0,120));request("setValue",{key:key,val:String(val==null?"":val)},5000).catch(function(error){debug("sync-storage-failed:"+String(source||""),key,String(error&&error.message||error));});}' +
        'function deleteStorageKey(key,source){key=String(key||"");if(!isKissStorageKey(key)){return;}debug("delete-storage:"+String(source||""),key,"");request("deleteValue",{key:key},5000).catch(function(error){debug("delete-storage-failed:"+String(source||""),key,String(error&&error.message||error));});}' +
        'function wrapKissApi(value){var base=value||{};return Object.assign({},base,{fetch:base.fetch||function(input,init){return fetch(input,init);},xmlHttpRequest:base.xmlHttpRequest,setValue:function(key,val){debug("kiss-setValue",key,String(val||"").slice(0,120));return request("setValue",{key:key,val:val});},getValue:function(key){debug("kiss-getValue",key,"");return request("getValue",{key:key});},deleteValue:function(key){debug("kiss-deleteValue",key,"");return request("deleteValue",{key:key});},getInfo:function(){return request("info",{});}});}' +
        'function protectKissGm(){currentKiss=wrapKissApi(previousKiss);try{Object.defineProperty(window,"KISS_GM",{configurable:true,enumerable:true,get:function(){return currentKiss;},set:function(value){debug("kiss-gm-assigned","",String(!!value));currentKiss=wrapKissApi(value||{});}});}catch(_error){window.KISS_GM=currentKiss;}}' +
        'function installLocalStorageMirror(){try{var storage=window.localStorage;if(!storage||window.__airaKissOptionsLocalStorageMirror===true){return;}window.__airaKissOptionsLocalStorageMirror=true;var originalSet=storage.setItem;var originalRemove=storage.removeItem;storage.setItem=function(key,val){var result=originalSet.apply(storage,arguments);syncStorageKey(key,val,"localStorage");return result;};storage.removeItem=function(key){var result=originalRemove.apply(storage,arguments);deleteStorageKey(key,"localStorage");return result;};for(var i=0;i<storage.length;i+=1){var key=storage.key(i);if(isKissStorageKey(key)){syncStorageKey(key,storage.getItem(key),"localStorage-scan");}}}catch(error){debug("localStorage-mirror-failed","",String(error&&error.message||error));}}' +
        'protectKissGm();' +
        'var kiss=currentKiss;' +
        'window.GM=Object.assign({},window.GM||{},{setValue:kiss.setValue,getValue:kiss.getValue,deleteValue:kiss.deleteValue,info:{script:{name:' + JSON.stringify(__airaScriptName) + ',version:' + JSON.stringify(__airaScriptVersion) + '}}});' +
        'window.GM_info=window.GM_info||window.GM.info;' +
        'protectAppInfo();' +
        'installPageEventBridge();' +
        'installLocalStorageMirror();' +
      '})();';
      try {
        var element = document.createElement('script');
        element.textContent = source;
        (document.documentElement || document.head || document.body).appendChild(element);
        if (element.parentNode) {
          element.parentNode.removeChild(element);
        }
      } catch (_error) {
        try {
          window.eval(source);
        } catch (_evalError) {}
      }
    };
    var __airaIsStandaloneOptionsPage = function() {
      if (!__airaStandaloneOptionsPageUrls || __airaStandaloneOptionsPageUrls.length <= 0) {
        return false;
      }
      var href = String(window.location && window.location.href || '');
      var hashIndex = href.indexOf('#');
      var queryIndex = href.indexOf('?');
      var endIndex = href.length;
      if (hashIndex >= 0 && hashIndex < endIndex) {
        endIndex = hashIndex;
      }
      if (queryIndex >= 0 && queryIndex < endIndex) {
        endIndex = queryIndex;
      }
      var normalizedHref = href.slice(0, endIndex);
      return __airaStandaloneOptionsPageUrls.some(function(optionsUrl) {
        return normalizedHref === String(optionsUrl || '');
      });
    };
    var __airaInstallStandaloneOptionsBridge = function() {
      __airaProtectKissOptionsAppInfo(__airaKissOptionsEventName, true);
      __airaInstallKissOptionsEventBridge(__airaKissOptionsEventName);
      __airaInstallKissOptionsDomBridge(__airaKissOptionsEventName);
      __airaInstallKissOptionsMessageBridge(__airaKissOptionsEventName);
      __airaInstallKissOptionsPageBridge(__airaKissOptionsEventName);
      window.APP_INFO = {
        name: __airaScriptName,
        version: __airaScriptVersion,
        eventName: __airaKissOptionsEventName
      };
    };
    window.KISS_GM = {
      fetch: GM_fetch,
      xmlHttpRequest: GM_xmlHttpRequestPromise,
      setValue: __airaSetValuePromise,
      getValue: __airaGetValuePromise,
      deleteValue: __airaDeleteValuePromise,
      getInfo: function() { return Promise.resolve(GM_info); }
    };
    if (__airaApiOnly) {
      if (__airaIsStandaloneOptionsPage()) {
        __airaInstallStandaloneOptionsBridge();
      }
      return;
    }
    if (__airaIsStandaloneOptionsPage()) {
      __airaInstallStandaloneOptionsBridge();
      return;
    }
`;
  }
}
