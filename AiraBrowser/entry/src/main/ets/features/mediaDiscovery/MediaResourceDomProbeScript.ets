import { MEDIA_LOCATOR_TEXT_RUNTIME } from './MediaLocatorText';
import { MEDIA_TITLE_PROBE_RUNTIME } from './MediaTitleProbeScript';
import { MEDIA_DURATION_PROBE_RUNTIME } from './MediaDurationProbeScript';
import {
  MediaResourceDomSignal,
  MediaResourceFrameType
} from '../mediaDiscovery/MediaResourceClassificationModels';

export interface MediaResourceDomProbeResult {
  url: string;
  mediaTitle?: string;
  signal?: MediaResourceDomSignal;
  mimeType?: string;
  posterUrl?: string;
  durationMs?: number;
  width?: number;
  height?: number;
  totalBytes?: number;
  fromBlob: boolean;
  frameType?: MediaResourceFrameType;
  frameUrl?: string;
}

export interface MediaResourceDomProbePayload {
  ok: boolean;
  pageTitle?: string;
  results: MediaResourceDomProbeResult[];
  error?: string;
}

const DOM_SCAN_SCRIPT: string = `(function () {
  try {
    var results = [];
    var seen = Object.create(null);
    var deadline = Date.now() + 24;
    var scannedChars = 0;
    function hasScanBudget() {
      return results.length < 160 && Date.now() < deadline;
    }
    function selectNodes(selector) {
      return hasScanBudget() ? document.querySelectorAll(selector) : [];
    }
    // Consume each URL token once before classification. A suffix-seeking regex
    // repeatedly backtracks on long tokens containing many scheme-like prefixes.
    var resourcePattern = /(?:https?:\\/\\/|\\/\\/)[^"'<>\\s]+/ig;
    var resourceExtensionPattern = /\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm|flv|hlv|f4v|mkv|avi|wmv|asf|mpeg|mpg|mpeg4|divx|ogv|ts|m4s|mp3|m4a|aac|wav|flac|ogg|weba|opus|wma|jpg|jpeg|png|webp|gif|avif|svg|pdf|zip|rar|7z|apk|hap|doc|docx|xls|xlsx|ppt|pptx|txt|csv|tar|gz)(?:[?#]|$)/i;
    var resourceHintPattern = /playlist|master|m3u8|mpd|hls|dash|stream|video|media|episode|player|index/i;

    ${MEDIA_LOCATOR_TEXT_RUNTIME}
    ${MEDIA_TITLE_PROBE_RUNTIME}
    ${MEDIA_DURATION_PROBE_RUNTIME}
    var pageTitle = hasScanBudget() ? readMediaPageTitle() : undefined;

    function decodeLooseText(value) {
      return normalizeMediaLocatorText(value);
    }

    function normalizeText(value) {
      return normalizeMediaLocatorText(value);
    }

    function normalizeScanText(value) {
      var text = normalizeText(value);
      var trimmed = text.trim();
      if (trimmed.length > 0 && trimmed.length <= 2048 && !/["'<>\\s]/.test(trimmed) &&
        (/^(?:https?:|blob:|\\/\\/|\\/|\\.{1,2}\\/)/i.test(trimmed) ||
          /\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm|flv|mkv|avi|ts|m4s)(?:[?#]|$)/i.test(trimmed))) {
        return normalizeUrl(trimmed);
      }
      return text;
    }

    function normalizeUrl(value) {
      var url = normalizeText(value).trim();
      if (url.indexOf('//') === 0) {
        url = location.protocol + url;
      }
      try {
        if (!/^(https?:|blob:)/i.test(url)) {
          url = new URL(url, document.baseURI || location.href).href;
        }
      } catch (e) {
      }
      return url;
    }

    function isDeferredMediaFieldMatch(text, index) {
      var prefix = String(text || '').substring(Math.max(0, index - 96), index);
      return /["']?(?:url_next|next_url|urlNext|nextUrl)["']?\\s*[:=]\\s*["']?\\s*$/i.test(prefix);
    }

    function addResult(url, signal, extra) {
      if (!hasScanBudget() || !String(url || '').trim() || String(url).length > 16384) return;
      var normalizedUrl = normalizeUrl(url);
      if (!normalizedUrl) return;
      if (!/^(https?:|blob:)/i.test(normalizedUrl)) return;
      if (isUnresolvedMediaUrl(normalizedUrl)) return;
      if (seen[normalizedUrl]) {
        mergeResultExtra(normalizedUrl, extra);
        return;
      }
      seen[normalizedUrl] = results.length + 1;
      var fromBlob = normalizedUrl.indexOf('blob:') === 0;
      results.push({
        url: normalizedUrl,
        signal: signal || 'text_match',
        mediaTitle: extra && extra.mediaTitle ? extra.mediaTitle : undefined,
        mimeType: extra && extra.mimeType ? extra.mimeType : undefined,
        posterUrl: extra && extra.posterUrl ? extra.posterUrl : undefined,
        durationMs: extra && extra.durationMs ? extra.durationMs : undefined,
        width: extra && extra.width ? extra.width : undefined,
        height: extra && extra.height ? extra.height : undefined,
        totalBytes: extra && extra.totalBytes ? extra.totalBytes : undefined,
        frameType: extra && extra.frameType ? extra.frameType : 'dom_document',
        frameUrl: extra && extra.frameUrl ? extra.frameUrl : location.href,
        fromBlob: fromBlob
      });
    }

    function isUnresolvedMediaUrl(url) {
      var text = String(url || '');
      if (/\\\\(?:$|[?#&])/.test(text)) return true;
      if (/(?:^|[\\\\/?&=])\\$(?:&|\\d+|\\{[^}]*\\})(?:$|[\\\\/?&#])/.test(text)) return true;
      return /[?&](?:url|src|file|video)=\\s*(?:\\\\|\\$&|\\$\\d+)(?:$|[&#])/i.test(text);
    }

    function mergeResultExtra(url, extra) {
      if (!extra) return;
      var item = results[seen[url] - 1];
      if (!item) return;
      if (!item.mimeType && extra.mimeType) item.mimeType = extra.mimeType;
      if (!item.mediaTitle && extra.mediaTitle) item.mediaTitle = extra.mediaTitle;
      if (!item.posterUrl && extra.posterUrl) item.posterUrl = extra.posterUrl;
      if (!item.durationMs && extra.durationMs) item.durationMs = extra.durationMs;
      if (!item.width && extra.width) item.width = extra.width;
      if (!item.height && extra.height) item.height = extra.height;
      if (!item.totalBytes && extra.totalBytes) item.totalBytes = extra.totalBytes;
      if (!item.frameType && extra.frameType) item.frameType = extra.frameType;
      if (!item.frameUrl && extra.frameUrl) item.frameUrl = extra.frameUrl;
    }

    function parseBestSrcset(srcset) {
      if (!srcset || String(srcset).length > 16384) return '';
      var bestUrl = '';
      var bestScore = -1;
      String(srcset).split(',').forEach(function(part) {
        var tokens = part.trim().split(/\\s+/);
        var candidateUrl = tokens[0] || '';
        if (!candidateUrl) return;
        var score = 1;
        for (var i = 1; i < tokens.length; i++) {
          var descriptor = tokens[i] || '';
          if (/\\d+w$/i.test(descriptor)) {
            score = parseInt(descriptor, 10) || score;
          } else if (/\\d+(\\.\\d+)?x$/i.test(descriptor)) {
            score = Math.round((parseFloat(descriptor) || 1) * 1000);
          }
        }
        if (score > bestScore) {
          bestScore = score;
          bestUrl = candidateUrl;
        }
      });
      return bestUrl;
    }

    function addImageUrl(value, signal, extra) {
      if (!value) return;
      addResult(value, signal || 'image_element', extra);
    }

    function addImageSrcset(value, signal, extra) {
      var bestUrl = parseBestSrcset(value);
      if (bestUrl) {
        addImageUrl(bestUrl, signal || 'image_element', extra);
      }
    }

    function scanCssImageUrls(value, signal) {
      if (!value || value === 'none' || String(value).length > 16384) return;
      var pattern = /url\\((['"]?)(.*?)\\1\\)/ig;
      var match;
      while ((match = pattern.exec(String(value))) !== null && hasScanBudget()) {
        addResult(match[2] || '', signal || 'css_background');
      }
    }

    function scanText(text, signal) {
      scanTextWithExtra(text, signal, undefined);
    }

    function scanTextWithExtra(text, signal, extra) {
      if (!hasScanBudget() || String(text || '').length > 32768) return;
      var normalizedText = normalizeScanText(text);
      resourcePattern.lastIndex = 0;
      var match;
      while ((match = resourcePattern.exec(normalizedText)) !== null && hasScanBudget()) {
        if (match[0].length <= 16384 &&
          (resourceExtensionPattern.test(match[0]) || resourceHintPattern.test(match[0])) &&
          !isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], signal || 'text_match', extra);
        }
      }

      var queryValues = mediaLocatorQueryValues(normalizedText);
      for (var queryIndex = 0; queryIndex < queryValues.length && hasScanBudget(); queryIndex++) {
        scanDecodedTextWithExtra(queryValues[queryIndex], signal, extra);
      }
      scanEncodedPlayerFields(normalizedText, signal || 'text_match', extra);
    }

    function scanEncodedPlayerFields(text, signal, extra) {
      var fieldPattern = /["'](?:url|src|file|video|hls|m3u8)["']\\s*:\\s*["']([A-Za-z0-9+/=_-]{24,})["']/ig;
      var match;
      while ((match = fieldPattern.exec(String(text || ''))) !== null && hasScanBudget()) {
        var decoded = decodeBase64UrlText(match[1] || '');
        if (decoded) {
          scanDecodedTextWithExtra(decoded, signal, extra);
        }
      }
    }

    function scanDecodedTextWithExtra(text, signal, extra) {
      if (!hasScanBudget() || String(text || '').length > 32768) return;
      var normalizedText = normalizeScanText(text);
      resourcePattern.lastIndex = 0;
      var match;
      while ((match = resourcePattern.exec(normalizedText)) !== null && hasScanBudget()) {
        if (match[0].length <= 16384 &&
          (resourceExtensionPattern.test(match[0]) || resourceHintPattern.test(match[0])) &&
          !isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], signal || 'text_match', extra);
        }
      }

    }

    function scanMetaEmbedEntries() {
      try {
        var metas = selectNodes('meta[property], meta[name], link[itemprop], [itemprop="embedUrl"], [itemprop="contentUrl"]');
        for (var metaIndex = 0; metaIndex < metas.length && metaIndex < 120 && hasScanBudget(); metaIndex++) {
          var node = metas[metaIndex];
          var key = String((node.getAttribute('property') || node.getAttribute('name') || node.getAttribute('itemprop') || '')).toLowerCase();
          if (key.indexOf('twitter:player') < 0 && key.indexOf('og:video') < 0 &&
            key.indexOf('og:audio') < 0 && key !== 'embedurl' && key !== 'contenturl') {
            continue;
          }
          var value = node.getAttribute('content') || node.getAttribute('value') || node.getAttribute('href') || '';
          if (!value) continue;
          if (key === 'embedurl' || key.indexOf('twitter:player') >= 0 || key.indexOf('og:video') >= 0) {
            addResult(value, 'embedded_attribute', { frameType: 'dom_frame', frameUrl: location.href });
          }
          scanText(value, 'embedded_attribute');
        }
      } catch (e) {
      }
    }

    function decodeBase64UrlText(value) {
      try {
        var normalized = String(value || '').replace(/-/g, '+').replace(/_/g, '/');
        if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized) || normalized.length % 4 === 1) {
          return '';
        }
        while (normalized.length % 4 !== 0) {
          normalized += '=';
        }
        var binary = atob(normalized);
        var decoded = '';
        for (var i = 0; i < binary.length; i++) {
          var hex = binary.charCodeAt(i).toString(16);
          decoded += '%' + (hex.length === 1 ? '0' + hex : hex);
        }
        return decodeLooseText(decodeURIComponent(decoded));
      } catch (e) {
        return '';
      }
    }

    function resolveElementFrameType(element) {
      var tag = element && element.tagName ? String(element.tagName).toLowerCase() : '';
      return tag === 'iframe' || tag === 'embed' || tag === 'object' ? 'dom_frame' : 'dom_document';
    }

    function scanAttribute(element, name, signal) {
      var value = element.getAttribute && element.getAttribute(name);
      if (!value) return;
      if (name === 'srcset' || name === 'data-srcset') {
        addImageSrcset(value, signal);
        return;
      }
      if (name === 'data-hls' || name === 'data-m3u8') {
        addResult(value, signal || 'embedded_attribute', { mimeType: 'application/vnd.apple.mpegurl' });
        return;
      }
      var frameType = resolveElementFrameType(element);
      if (frameType === 'dom_frame' && (name === 'src' || name === 'data-src' || name === 'data-url' || name === 'data-player' || name === 'data-embed')) {
        addResult(value, signal || 'embedded_attribute', { frameType: 'dom_frame', frameUrl: location.href });
        return;
      }
      scanText(value, signal);
    }

    function scanImageAttribute(element, name, extra) {
      var value = element.getAttribute && element.getAttribute(name);
      if (!value) return;
      if (name === 'srcset' || name === 'data-srcset') {
        addImageSrcset(value, 'image_element', extra);
        return;
      }
      addImageUrl(value, 'image_element', extra);
    }

    var mediaElements = selectNodes('video, audio');
    for (var i = 0; i < mediaElements.length && i < 32 && hasScanBudget(); i++) {
      var media = mediaElements[i];
      var isAudioElement = media.tagName && String(media.tagName).toLowerCase() === 'audio';
      var src = media.currentSrc || media.src || '';
      var mediaExtra = {
        mediaTitle: readMediaElementTitle(media),
        mimeType: media.getAttribute && media.getAttribute('type') ? media.getAttribute('type') : undefined,
        posterUrl: media.poster || undefined,
        durationMs: mediaElementDurationMs(media, normalizeUrl(src)),
        width: media.videoWidth || undefined,
        height: media.videoHeight || undefined
      };
      if (src) {
        addResult(src, isAudioElement ? 'audio_element' : 'video_element', mediaExtra);
      }
      var mediaSources = media.querySelectorAll('source');
      for (var mediaSourceIndex = 0; mediaSourceIndex < mediaSources.length && mediaSourceIndex < 8 && hasScanBudget(); mediaSourceIndex++) {
        var sourceUrl = mediaSources[mediaSourceIndex].src || mediaSources[mediaSourceIndex].getAttribute('src') || '';
        addResult(sourceUrl,
          isAudioElement ? 'audio_element' : 'video_element', {
            mediaTitle: mediaExtra.mediaTitle,
            mimeType: mediaSources[mediaSourceIndex].getAttribute('type') || undefined,
            posterUrl: mediaExtra.posterUrl,
            durationMs: mediaElementDurationMs(media, normalizeUrl(sourceUrl)),
            width: mediaExtra.width,
            height: mediaExtra.height
          });
      }
    }

    function scanPerformanceEntries(imagesOnly) {
      try {
        var entries = performance && performance.getEntriesByType ? performance.getEntriesByType('resource') : [];
        var first = Math.max(0, entries.length - 320);
        for (var index = entries.length - 1; index >= first && hasScanBudget(); index--) {
          var entry = entries[index];
          var initiator = String(entry.initiatorType || '').toLowerCase();
          var isImage = initiator === 'img' || initiator === 'image';
          if (isImage !== imagesOnly) continue;
          var extra = {
            mimeType: entry.contentType || undefined,
            // Transfer size includes headers; decoded size is not the saved file size.
            totalBytes: entry.encodedBodySize > 0 ? entry.encodedBodySize : undefined
          };
          if (isImage) {
            addResult(entry.name || '', 'image_performance', extra);
          } else if (/^(?:video|audio)\\//i.test(String(entry.contentType || '')) ||
            /^(?:application\\/(?:vnd\\.apple\\.mpegurl|x-mpegurl|dash\\+xml))$/i.test(String(entry.contentType || ''))) {
            addResult(entry.name || '', 'performance_entry', extra);
          } else {
            scanTextWithExtra(entry.name || '', 'performance_entry', extra);
          }
        }
      } catch (e) {
      }
    }
    // Actual media and recent network entries precede decorative images.
    scanPerformanceEntries(false);
    scanMetaEmbedEntries();
    scanText(location.href || '', 'location');
    var scripts = selectNodes('script:not([src])');
    for (var scriptIndex = 0; scriptIndex < scripts.length && scriptIndex < 24 && scannedChars < 131072 && hasScanBudget(); scriptIndex++) {
      var scriptText = scripts[scriptIndex].textContent || '';
      if (!scriptText) continue;
      var remaining = Math.min(32768, 131072 - scannedChars);
      scannedChars += Math.min(scriptText.length, remaining);
      if (scriptText.length > remaining) {
        scriptText = scriptText.substring(0, remaining);
        // Do not turn the last partial signed URL into a broken download.
        var boundary = Math.max(scriptText.lastIndexOf('"'), scriptText.lastIndexOf("'"), scriptText.lastIndexOf('\\n'));
        scriptText = boundary >= 0 ? scriptText.substring(0, boundary + 1) : '';
      }
      scanText(scriptText, 'script_text');
      if (results.length >= 160) break;
    }
    var embeddedElements = selectNodes('iframe, embed, object, source, track, [data-src], [data-srcset], [data-original], [data-original-src], [data-lazy], [data-lazy-src], [data-actualsrc], [data-imageurl], [data-cover], [data-thumb], [data-preview], [data-page-image-url], [data-url], [data-video], [data-file], [data-hls], [data-m3u8], [data-player], [data-embed], [src], [href]');
    for (var embeddedIndex = 0; embeddedIndex < embeddedElements.length && embeddedIndex < 260 && hasScanBudget(); embeddedIndex++) {
      var embedded = embeddedElements[embeddedIndex];
      scanAttribute(embedded, 'src', 'embedded_attribute');
      scanAttribute(embedded, 'href', 'embedded_attribute');
      scanAttribute(embedded, 'data-src', 'embedded_attribute');
      scanAttribute(embedded, 'data-srcset', 'embedded_attribute');
      scanAttribute(embedded, 'data-original', 'embedded_attribute');
      scanAttribute(embedded, 'data-original-src', 'embedded_attribute');
      scanAttribute(embedded, 'data-lazy', 'embedded_attribute');
      scanAttribute(embedded, 'data-lazy-src', 'embedded_attribute');
      scanAttribute(embedded, 'data-actualsrc', 'embedded_attribute');
      scanAttribute(embedded, 'data-imageurl', 'embedded_attribute');
      scanAttribute(embedded, 'data-cover', 'embedded_attribute');
      scanAttribute(embedded, 'data-thumb', 'embedded_attribute');
      scanAttribute(embedded, 'data-preview', 'embedded_attribute');
      scanAttribute(embedded, 'data-page-image-url', 'embedded_attribute');
      scanAttribute(embedded, 'data-url', 'embedded_attribute');
      scanAttribute(embedded, 'data-video', 'embedded_attribute');
      scanAttribute(embedded, 'data-file', 'embedded_attribute');
      scanAttribute(embedded, 'data-hls', 'embedded_attribute');
      scanAttribute(embedded, 'data-m3u8', 'embedded_attribute');
      scanAttribute(embedded, 'data-player', 'embedded_attribute');
      scanAttribute(embedded, 'data-embed', 'embedded_attribute');
    }

    var anchors = selectNodes('a[href]');
    for (var anchorIndex = 0; anchorIndex < anchors.length && anchorIndex < 160 && hasScanBudget(); anchorIndex++) {
      var href = anchors[anchorIndex].href || anchors[anchorIndex].getAttribute('href') || '';
      scanText(href, 'anchor');
    }

    var imageElements = selectNodes('img, picture source');
    for (var imageIndex = 0; imageIndex < imageElements.length && imageIndex < 80 && hasScanBudget(); imageIndex++) {
      var image = imageElements[imageIndex];
      var imageExtra = {
        mimeType: image.getAttribute && image.getAttribute('type') ? image.getAttribute('type') : undefined,
        width: image.naturalWidth || image.width || undefined,
        height: image.naturalHeight || image.height || undefined
      };
      addImageUrl(image.currentSrc || image.src || image.getAttribute('src') || '', 'image_element', imageExtra);
      scanImageAttribute(image, 'data-src', imageExtra);
      scanImageAttribute(image, 'srcset', imageExtra);
      scanImageAttribute(image, 'data-srcset', imageExtra);
      scanImageAttribute(image, 'data-original', imageExtra);
      scanImageAttribute(image, 'data-original-src', imageExtra);
      scanImageAttribute(image, 'data-lazy', imageExtra);
      scanImageAttribute(image, 'data-lazy-src', imageExtra);
      scanImageAttribute(image, 'data-actualsrc', imageExtra);
      scanImageAttribute(image, 'data-imageurl', imageExtra);
      scanImageAttribute(image, 'data-cover', imageExtra);
      scanImageAttribute(image, 'data-thumb', imageExtra);
      scanImageAttribute(image, 'data-preview', imageExtra);
      scanImageAttribute(image, 'data-page-image-url', imageExtra);
    }

    scanPerformanceEntries(true);
    var backgroundElements = selectNodes('[style], [data-bg], [data-background], [data-cover], [data-theme], [class]');
    for (var backgroundIndex = 0; backgroundIndex < backgroundElements.length && backgroundIndex < 48 && hasScanBudget(); backgroundIndex++) {
      var backgroundElement = backgroundElements[backgroundIndex];
      scanCssImageUrls(backgroundElement.getAttribute && backgroundElement.getAttribute('style'), 'css_background');
      scanAttribute(backgroundElement, 'data-bg', 'css_background');
      scanAttribute(backgroundElement, 'data-background', 'css_background');
      scanAttribute(backgroundElement, 'data-cover', 'css_background');
      try {
        scanCssImageUrls(window.getComputedStyle(backgroundElement).backgroundImage, 'css_background');
      } catch (e) {
      }
    }

    return JSON.stringify({ ok: true, pageTitle: pageTitle, results: results.slice(0, 160) });
  } catch (e) {
    return JSON.stringify({ ok: false, results: [], error: String((e && e.message) || e) });
  }
})();`;

export class MediaResourceDomProbeScript {
  build(): string {
    return DOM_SCAN_SCRIPT;
  }

  parse(raw: string): MediaResourceDomProbePayload {
    if (raw.length === 0) {
      return { ok: false, results: [], error: 'empty_result' };
    }
    try {
      const parsed: MediaResourceDomProbePayload = JSON.parse(raw) as MediaResourceDomProbePayload;
      if (typeof parsed.ok !== 'boolean' || !Array.isArray(parsed.results)) {
        return { ok: false, results: [], error: 'bad_shape' };
      }
      return parsed;
    } catch (error) {
      const message = (error as Error)?.message ?? 'parse_error';
      return { ok: false, results: [], error: message };
    }
  }
}
