const MIXED_CONTENT_IMAGE_UPGRADE_SCRIPT: string = `
(function airaMixedContentResourceUpgradeBootstrap() {
  var pageProtocol = String(window.location && window.location.protocol || '').toLowerCase();
  if (pageProtocol !== 'https:' || window.__airaMixedContentResourceUpgradeInstalled === true) {
    return;
  }
  window.__airaMixedContentResourceUpgradeInstalled = true;

  var originalSetAttribute = null;

  function isAsciiWhitespace(character) {
    var characterCode = String(character).charCodeAt(0);
    return characterCode === 9 || characterCode === 10 || characterCode === 12 ||
      characterCode === 13 || characterCode === 32;
  }

  function upgradeSourceSet(value) {
    var text = String(value);
    var upgraded = '';
    var index = 0;
    while (index < text.length) {
      while (index < text.length) {
        var leadingCharacter = text.charAt(index);
        if (!isAsciiWhitespace(leadingCharacter) && leadingCharacter !== ',') {
          break;
        }
        upgraded += leadingCharacter;
        index += 1;
      }
      if (index >= text.length) {
        break;
      }

      var urlStart = index;
      if (text.slice(index, index + 7).toLowerCase() === 'http://') {
        upgraded += 'https://';
        index += 7;
      }
      while (index < text.length && !isAsciiWhitespace(text.charAt(index))) {
        upgraded += text.charAt(index);
        index += 1;
      }

      var originalUrl = text.slice(urlStart, index);
      if (originalUrl.charAt(originalUrl.length - 1) === ',') {
        continue;
      }
      while (index < text.length) {
        var descriptorCharacter = text.charAt(index);
        upgraded += descriptorCharacter;
        index += 1;
        if (descriptorCharacter === ',') {
          break;
        }
      }
    }
    return upgraded === text ? value : upgraded;
  }

  function upgradeCssUrls(value) {
    var text = String(value);
    var upgraded = text.replace(/(url\\(\\s*["']?)http:\\/\\//ig, '$1https://');
    return upgraded === text ? value : upgraded;
  }

  function upgradeValue(attributeName, value) {
    var normalizedName = String(attributeName || '').toLowerCase();
    var text = String(value);
    if (normalizedName === 'srcset') {
      return upgradeSourceSet(value);
    }
    if (normalizedName === 'style' || normalizedName === 'background' || normalizedName === 'backgroundimage' ||
      normalizedName === 'csstext') {
      return upgradeCssUrls(value);
    }
    var upgraded = text.replace(/^(\\s*)http:\\/\\//i, '$1https://');
    return upgraded === text ? value : upgraded;
  }

  function isImageResourceElement(element) {
    if (!element || !element.tagName) {
      return false;
    }
    var tagName = String(element.tagName).toUpperCase();
    if (tagName === 'IMG') {
      return true;
    }
    if (tagName !== 'SOURCE') {
      return false;
    }
    var parent = element.parentElement || element.parentNode;
    return !!parent && String(parent.tagName || '').toUpperCase() === 'PICTURE';
  }

  function isMediaResourceElement(element) {
    if (!element || !element.tagName) {
      return false;
    }
    var tagName = String(element.tagName).toUpperCase();
    if (tagName === 'VIDEO' || tagName === 'AUDIO') {
      return true;
    }
    if (tagName !== 'SOURCE') {
      return false;
    }
    var parent = element.parentElement || element.parentNode;
    var parentTagName = parent && String(parent.tagName || '').toUpperCase();
    return parentTagName === 'VIDEO' || parentTagName === 'AUDIO';
  }

  function isVideoElement(element) {
    return !!element && String(element.tagName || '').toUpperCase() === 'VIDEO';
  }

  function upgradeAttribute(element, attributeName) {
    if (!originalSetAttribute || !element || !element.hasAttribute(attributeName)) {
      return;
    }
    var normalizedName = String(attributeName || '').toLowerCase();
    var shouldUpgrade = normalizedName === 'style' ||
      (isImageResourceElement(element) && (normalizedName === 'src' || normalizedName === 'srcset')) ||
      (isMediaResourceElement(element) && normalizedName === 'src') ||
      (isVideoElement(element) && normalizedName === 'poster');
    if (!shouldUpgrade) {
      return;
    }
    var current = String(element.getAttribute(normalizedName) || '');
    var upgraded = upgradeValue(normalizedName, current);
    if (upgraded !== current) {
      originalSetAttribute.call(element, normalizedName, upgraded);
    }
  }

  function upgradeElement(element) {
    upgradeAttribute(element, 'src');
    upgradeAttribute(element, 'srcset');
    upgradeAttribute(element, 'poster');
    upgradeAttribute(element, 'style');
  }

  function scan(root) {
    if (!root) {
      return;
    }
    if (root.nodeType === 1) {
      upgradeElement(root);
    }
    if (typeof root.querySelectorAll !== 'function') {
      return;
    }
    var elements = root.querySelectorAll(
      'img[src],img[srcset],picture source[src],picture source[srcset],' +
      'video[src],video[poster],audio[src],video source[src],audio source[src],[style]'
    );
    for (var index = 0; index < elements.length; index += 1) {
      upgradeElement(elements[index]);
    }
  }

  function wrapProperty(prototype, propertyName, shouldUpgrade, upgrade) {
    if (!prototype) {
      return;
    }
    try {
      var descriptor = Object.getOwnPropertyDescriptor(prototype, propertyName);
      if (!descriptor || typeof descriptor.set !== 'function' || typeof descriptor.get !== 'function') {
        return;
      }
      Object.defineProperty(prototype, propertyName, {
        configurable: descriptor.configurable,
        enumerable: descriptor.enumerable,
        get: descriptor.get,
        set: function (value) {
          descriptor.set.call(this, shouldUpgrade(this) ? upgrade(propertyName, value) : value);
        }
      });
    } catch (_error) {
    }
  }

  function installPropertyHooks() {
    if (typeof Element === 'undefined') {
      setTimeout(installPropertyHooks, 0);
      return;
    }
    originalSetAttribute = Element.prototype.setAttribute;
    try {
      Element.prototype.setAttribute = function (name, value) {
        var normalizedName = String(name || '').toLowerCase();
        if (normalizedName === 'style' ||
          (isImageResourceElement(this) && (normalizedName === 'src' || normalizedName === 'srcset')) ||
          (isMediaResourceElement(this) && normalizedName === 'src') ||
          (isVideoElement(this) && normalizedName === 'poster')) {
          return originalSetAttribute.call(this, name, upgradeValue(normalizedName, value));
        }
        return originalSetAttribute.call(this, name, value);
      };
    } catch (_error) {
    }

    wrapProperty(window.HTMLImageElement && window.HTMLImageElement.prototype, 'src',
      isImageResourceElement, upgradeValue);
    wrapProperty(window.HTMLImageElement && window.HTMLImageElement.prototype, 'srcset',
      isImageResourceElement, upgradeValue);
    wrapProperty(window.HTMLSourceElement && window.HTMLSourceElement.prototype, 'src',
      function (element) { return isImageResourceElement(element) || isMediaResourceElement(element); }, upgradeValue);
    wrapProperty(window.HTMLSourceElement && window.HTMLSourceElement.prototype, 'srcset',
      isImageResourceElement, upgradeValue);
    wrapProperty(window.HTMLMediaElement && window.HTMLMediaElement.prototype, 'src',
      isMediaResourceElement, upgradeValue);
    wrapProperty(window.HTMLVideoElement && window.HTMLVideoElement.prototype, 'poster',
      isVideoElement, upgradeValue);

    var stylePrototype = window.CSSStyleDeclaration && window.CSSStyleDeclaration.prototype;
    wrapProperty(stylePrototype, 'background', function () { return true; }, upgradeValue);
    wrapProperty(stylePrototype, 'backgroundImage', function () { return true; }, upgradeValue);
    wrapProperty(stylePrototype, 'cssText', function () { return true; }, upgradeValue);
    if (stylePrototype && typeof stylePrototype.setProperty === 'function') {
      var originalSetProperty = stylePrototype.setProperty;
      try {
        stylePrototype.setProperty = function (name, value, priority) {
          return originalSetProperty.call(this, name, upgradeCssUrls(value), priority);
        };
      } catch (_error) {
      }
    }
  }

  try {
    var observer = new MutationObserver(function (records) {
      for (var recordIndex = 0; recordIndex < records.length; recordIndex += 1) {
        var record = records[recordIndex];
        if (record.type === 'attributes') {
          upgradeAttribute(record.target, String(record.attributeName || ''));
          continue;
        }
        for (var nodeIndex = 0; nodeIndex < record.addedNodes.length; nodeIndex += 1) {
          scan(record.addedNodes[nodeIndex]);
        }
      }
    });
    observer.observe(document, {
      subtree: true,
      childList: true,
      attributes: true,
      attributeFilter: ['src', 'srcset', 'poster', 'style']
    });
  } catch (_error) {
  }

  installPropertyHooks();
  if (document.documentElement) {
    scan(document.documentElement);
  }
  document.addEventListener('DOMContentLoaded', function () {
    scan(document.documentElement);
  }, true);
  window.addEventListener('load', function () {
    scan(document.documentElement);
  }, true);
})();
`;

export class WebMixedContentImageUpgradeScriptService {
  buildDocumentStartScriptItem(): ScriptItem {
    return {
      script: MIXED_CONTENT_IMAGE_UPGRADE_SCRIPT,
      scriptRules: ['*']
    };
  }
}
