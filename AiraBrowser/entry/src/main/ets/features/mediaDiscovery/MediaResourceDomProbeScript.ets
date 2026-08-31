import {
  MediaResourceDomSignal,
  MediaResourceFrameType
} from '../mediaDiscovery/MediaResourceClassificationModels';

export interface MediaResourceDomProbeResult {
  url: string;
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
  results: MediaResourceDomProbeResult[];
  error?: string;
}

const DOM_SCAN_SCRIPT: string = `(function () {
  try {
    var results = [];
    var seen = Object.create(null);
    var mediaFallbackExtra = undefined;
    var resourcePattern = /(?:https?:\\/\\/|\\/\\/)[^"'<>\\s]+?\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm|flv|hlv|f4v|mkv|avi|wmv|asf|mpeg|mpg|mpeg4|divx|ogv|ts|m4s|mp3|m4a|aac|wav|flac|ogg|weba|opus|wma|jpg|jpeg|png|webp|gif|avif|svg|pdf|zip|rar|7z|apk|hap|doc|docx|xls|xlsx|ppt|pptx)(?=$|[?#"'<>\\s])/ig;
    var resourceHintPattern = /(?:https?:\\/\\/|\\/\\/)[^"'<>\\s]+?(?:playlist|master|m3u8|mpd|hls|dash|stream|video|media|episode|player|index)(?:[^"'<>\\s]*)/ig;

    function decodeLooseText(value) {
      var text = String(value || '');
      for (var i = 0; i < 3; i++) {
        try {
          var decoded = decodeURIComponent(text);
          if (decoded === text) break;
          text = decoded;
        } catch (e) {
          break;
        }
      }
      return text;
    }

    function normalizeText(value) {
      return decodeLooseText(value)
        .replace(/\\\\u002[fF]/g, '/')
        .replace(/\\\\+\\//g, '/')
        .replace(/&amp;/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\\u003[dD]/g, '=')
        .replace(/\\\\u003[fF]/g, '?');
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
      var url = normalizeText(value);
      if (url.indexOf('//') === 0) {
        url = location.protocol + url;
      }
      try {
        if (!/^(https?:|blob:)/i.test(url)) {
          url = new URL(url, location.href).href;
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
	      var normalizedUrl = normalizeUrl(url);
	      if (!normalizedUrl) return;
      if (!/^(https?:|blob:)/i.test(normalizedUrl)) return;
      if (isUnresolvedMediaUrl(normalizedUrl)) return;
      var mergedExtra = mergeVideoFallbackExtra(normalizedUrl, signal, extra);
      if (seen[normalizedUrl]) {
        mergeResultExtra(normalizedUrl, mergedExtra);
        return;
      }
      seen[normalizedUrl] = true;
      var fromBlob = normalizedUrl.indexOf('blob:') === 0;
      results.push({
        url: normalizedUrl,
        signal: signal || 'text_match',
        mimeType: mergedExtra && mergedExtra.mimeType ? mergedExtra.mimeType : undefined,
        posterUrl: mergedExtra && mergedExtra.posterUrl ? mergedExtra.posterUrl : undefined,
        durationMs: mergedExtra && mergedExtra.durationMs ? mergedExtra.durationMs : undefined,
        width: mergedExtra && mergedExtra.width ? mergedExtra.width : undefined,
        height: mergedExtra && mergedExtra.height ? mergedExtra.height : undefined,
        totalBytes: mergedExtra && mergedExtra.totalBytes ? mergedExtra.totalBytes : undefined,
        frameType: mergedExtra && mergedExtra.frameType ? mergedExtra.frameType : 'dom_document',
        frameUrl: mergedExtra && mergedExtra.frameUrl ? mergedExtra.frameUrl : location.href,
        fromBlob: fromBlob
	      });
	    }

    function isUnresolvedMediaUrl(url) {
      var text = String(url || '');
      if (/\\\\(?:$|[?#&])/.test(text)) return true;
      if (/(?:^|[\\\\/?&=])\\$(?:&|\\d+|\\{[^}]*\\})(?:$|[\\\\/?&#])/.test(text)) return true;
      return /[?&](?:url|src|file|video)=\\s*(?:\\\\|\\$&|\\$\\d+)(?:$|[&#])/i.test(text);
    }

    function mergeVideoFallbackExtra(url, signal, extra) {
      if (!mediaFallbackExtra || !isLikelyVideoUrl(url, signal)) {
        return extra;
      }
      var merged = {};
      copyExtra(merged, mediaFallbackExtra);
      copyExtra(merged, extra);
      return merged;
    }

    function copyExtra(target, source) {
      if (!source) return;
      if (source.mimeType) target.mimeType = source.mimeType;
      if (source.posterUrl) target.posterUrl = source.posterUrl;
      if (source.durationMs) target.durationMs = source.durationMs;
      if (source.width) target.width = source.width;
      if (source.height) target.height = source.height;
      if (source.totalBytes) target.totalBytes = source.totalBytes;
      if (source.frameType) target.frameType = source.frameType;
      if (source.frameUrl) target.frameUrl = source.frameUrl;
    }

    function isLikelyVideoUrl(url, signal) {
      if (signal === 'video_element') return true;
      var text = String(url || '').toLowerCase();
      return /\\.(m3u8|m3u|mpd|mp4|m4v|mov|webm|flv|hlv|f4v|mkv|avi|wmv|asf|mpeg|mpg|mpeg4|divx|ogv|ts|m4s)(?:$|[?#])/.test(text) ||
        text.indexOf('/video/') >= 0 || text.indexOf('/media/') >= 0 || text.indexOf('/upgcxcode/') >= 0 ||
        text.indexOf('upos-') >= 0;
    }

    function mergeResultExtra(url, extra) {
      if (!extra) return;
      for (var i = 0; i < results.length; i++) {
        if (results[i].url !== url) continue;
        if (!results[i].mimeType && extra.mimeType) results[i].mimeType = extra.mimeType;
        if (!results[i].posterUrl && extra.posterUrl) results[i].posterUrl = extra.posterUrl;
        if (!results[i].durationMs && extra.durationMs) results[i].durationMs = extra.durationMs;
        if (!results[i].width && extra.width) results[i].width = extra.width;
        if (!results[i].height && extra.height) results[i].height = extra.height;
        if (!results[i].totalBytes && extra.totalBytes) results[i].totalBytes = extra.totalBytes;
        if (!results[i].frameType && extra.frameType) results[i].frameType = extra.frameType;
        if (!results[i].frameUrl && extra.frameUrl) results[i].frameUrl = extra.frameUrl;
        return;
      }
    }

	    function parseBestSrcset(srcset) {
	      if (!srcset) return '';
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
	      if (!value || value === 'none') return;
	      var pattern = /url\\((['"]?)(.*?)\\1\\)/ig;
	      var match;
	      while ((match = pattern.exec(String(value))) !== null && results.length < 160) {
	        addResult(match[2] || '', signal || 'css_background');
	      }
	    }

    function scanText(text, signal) {
      scanTextWithExtra(text, signal, undefined);
    }

    function scanTextWithExtra(text, signal, extra) {
      var normalizedText = normalizeScanText(text);
      resourcePattern.lastIndex = 0;
      var match;
      while ((match = resourcePattern.exec(normalizedText)) !== null && results.length < 160) {
        if (!isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], signal || 'text_match', extra);
        }
      }
      resourceHintPattern.lastIndex = 0;
      while ((match = resourceHintPattern.exec(normalizedText)) !== null && results.length < 160) {
        if (!isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], signal || 'text_match', extra);
        }
      }
      scanEncodedPlayerFields(normalizedText, signal || 'text_match', extra);
    }

    function scanEncodedPlayerFields(text, signal, extra) {
      var fieldPattern = /["'](?:url|src|file|video|hls|m3u8)["']\\s*:\\s*["']([A-Za-z0-9+/=_-]{24,})["']/ig;
      var match;
      while ((match = fieldPattern.exec(String(text || ''))) !== null && results.length < 160) {
        var decoded = decodeBase64UrlText(match[1] || '');
        if (decoded) {
          scanDecodedTextWithExtra(decoded, signal, extra);
        }
      }
    }

    function scanDecodedTextWithExtra(text, signal, extra) {
      var normalizedText = normalizeScanText(text);
      resourcePattern.lastIndex = 0;
      var match;
      while ((match = resourcePattern.exec(normalizedText)) !== null && results.length < 160) {
        if (!isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], signal || 'text_match', extra);
        }
      }
      resourceHintPattern.lastIndex = 0;
      while ((match = resourceHintPattern.exec(normalizedText)) !== null && results.length < 160) {
        if (!isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], signal || 'text_match', extra);
        }
      }
    }

    function scanMetaEmbedEntries() {
      try {
        var metas = document.querySelectorAll('meta[property], meta[name], link[itemprop], [itemprop="embedUrl"], [itemprop="contentUrl"]');
        for (var metaIndex = 0; metaIndex < metas.length && metaIndex < 120 && results.length < 160; metaIndex++) {
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

    var mediaElements = document.querySelectorAll('video, audio');
    for (var i = 0; i < mediaElements.length && i < 32; i++) {
      var media = mediaElements[i];
      var isAudioElement = media.tagName && String(media.tagName).toLowerCase() === 'audio';
      var mediaExtra = {
        mimeType: media.getAttribute && media.getAttribute('type') ? media.getAttribute('type') : undefined,
        posterUrl: media.poster || undefined,
        durationMs: isFinite(media.duration) && media.duration > 0 ? Math.round(media.duration * 1000) : undefined,
        width: media.videoWidth || undefined,
        height: media.videoHeight || undefined
      };
      if (!isAudioElement && !mediaFallbackExtra && (mediaExtra.durationMs || mediaExtra.width || mediaExtra.height || mediaExtra.posterUrl)) {
        mediaFallbackExtra = mediaExtra;
      }
      var src = media.currentSrc || media.src || '';
      if (src) {
        addResult(src, isAudioElement ? 'audio_element' : 'video_element', mediaExtra);
      }
      var mediaSources = media.querySelectorAll('source');
      for (var mediaSourceIndex = 0; mediaSourceIndex < mediaSources.length && mediaSourceIndex < 8; mediaSourceIndex++) {
        addResult(mediaSources[mediaSourceIndex].src || mediaSources[mediaSourceIndex].getAttribute('src') || '',
          isAudioElement ? 'audio_element' : 'video_element', {
            mimeType: mediaSources[mediaSourceIndex].getAttribute('type') || undefined,
            posterUrl: mediaExtra.posterUrl,
            durationMs: mediaExtra.durationMs,
            width: mediaExtra.width,
            height: mediaExtra.height
          });
      }
    }

	    var imageElements = document.querySelectorAll('img, picture source');
	    for (var imageIndex = 0; imageIndex < imageElements.length && imageIndex < 80; imageIndex++) {
	      var image = imageElements[imageIndex];
	      var imageExtra = {
	        mimeType: image.getAttribute && image.getAttribute('type') ? image.getAttribute('type') : undefined,
	        width: image.naturalWidth || image.width || undefined,
	        height: image.naturalHeight || image.height || undefined
	      };
	      addImageUrl(image.currentSrc || image.src || image.getAttribute('src') || '', 'image_element', imageExtra);
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

	    var backgroundElements = document.querySelectorAll('[style], [data-bg], [data-background], [data-cover], [data-theme], [class]');
	    for (var backgroundIndex = 0; backgroundIndex < backgroundElements.length && backgroundIndex < 180; backgroundIndex++) {
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

	    var embeddedElements = document.querySelectorAll('iframe, embed, object, source, track, [data-src], [data-srcset], [data-original], [data-original-src], [data-lazy], [data-lazy-src], [data-actualsrc], [data-imageurl], [data-cover], [data-thumb], [data-preview], [data-page-image-url], [data-url], [data-video], [data-file], [data-hls], [data-m3u8], [data-player], [data-embed], [src], [href]');
	    for (var embeddedIndex = 0; embeddedIndex < embeddedElements.length && embeddedIndex < 260; embeddedIndex++) {
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

    try {
	      var performanceEntries = performance && performance.getEntriesByType ? performance.getEntriesByType('resource') : [];
	      for (var performanceIndex = 0; performanceIndex < performanceEntries.length && performanceIndex < 320; performanceIndex++) {
	        var entry = performanceEntries[performanceIndex];
	        var initiatorType = String(entry.initiatorType || '').toLowerCase();
	        if (initiatorType === 'img' || initiatorType === 'image') {
	          addResult(entry.name || '', 'image_performance', {
	            totalBytes: entry.encodedBodySize || entry.decodedBodySize || entry.transferSize || undefined
	          });
	        } else {
	          scanTextWithExtra(entry.name || '', 'performance_entry', {
	            totalBytes: entry.encodedBodySize || entry.decodedBodySize || entry.transferSize || undefined
	          });
	        }
	      }
    } catch (e) {
    }

    var anchors = document.querySelectorAll('a[href]');
    for (var anchorIndex = 0; anchorIndex < anchors.length && anchorIndex < 160; anchorIndex++) {
      var href = anchors[anchorIndex].href || anchors[anchorIndex].getAttribute('href') || '';
      scanText(href, 'anchor');
    }

    scanMetaEmbedEntries();
    scanText(location.href || '', 'location');

    var scripts = document.querySelectorAll('script:not([src])');
    var scannedChars = 0;
    for (var scriptIndex = 0; scriptIndex < scripts.length && scriptIndex < 24 && scannedChars < 700000; scriptIndex++) {
      var scriptText = scripts[scriptIndex].textContent || '';
      if (!scriptText) continue;
      if (scriptText.length > 180000) {
        scriptText = scriptText.substring(0, 180000);
      }
      scannedChars += scriptText.length;
      scanText(scriptText, 'script_text');
      if (results.length >= 160) break;
    }
    return JSON.stringify({ ok: true, results: results.slice(0, 160) });
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
