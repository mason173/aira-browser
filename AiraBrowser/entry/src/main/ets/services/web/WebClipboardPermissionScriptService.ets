import { SitePermissionRule } from '../../common/models/BrowserModels';

export class WebClipboardPermissionScriptService {
  buildDocumentStartScriptItem(rule: SitePermissionRule): ScriptItem {
    return {
      script: this.buildDocumentStartScript(rule),
      scriptRules: ['.*']
    };
  }

  buildDocumentStartScript(rule: SitePermissionRule): string {
    const ruleLiteral = JSON.stringify(rule);
    return `
(function airaClipboardPermissionBootstrap() {
  var rule = ${ruleLiteral};
  if (window.__airaClipboardPermissionRule === rule) {
    return;
  }
  window.__airaClipboardPermissionRule = rule;
  if (rule !== 'block') {
    return;
  }
  var clipboard = navigator.clipboard;
  if (!clipboard) {
    return;
  }
  function createBlockedError() {
    try {
      return new DOMException('Clipboard access is blocked by site settings.', 'NotAllowedError');
    } catch (error) {
      var fallback = new Error('Clipboard access is blocked by site settings.');
      fallback.name = 'NotAllowedError';
      return fallback;
    }
  }
  function rejectBlocked() {
    return Promise.reject(createBlockedError());
  }
  ['read', 'readText', 'write', 'writeText'].forEach(function (name) {
    try {
      Object.defineProperty(clipboard, name, {
        configurable: true,
        enumerable: false,
        writable: true,
        value: rejectBlocked
      });
    } catch (error) {
      try {
        clipboard[name] = rejectBlocked;
      } catch (ignored) {
      }
    }
  });
})();
`;
  }
}
