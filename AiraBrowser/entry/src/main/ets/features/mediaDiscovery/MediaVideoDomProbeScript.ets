import { MediaResourceDomSignal } from '../mediaDiscovery/MediaResourceClassificationModels';

export interface MediaVideoDomProbeResult {
  url: string;
  signal?: MediaResourceDomSignal;
  mimeType?: string;
  posterUrl?: string;
  durationMs?: number;
  width?: number;
  height?: number;
  isPlaying?: boolean;
  hasPlayed?: boolean;
  readyState?: number;
  visible?: boolean;
  fromBlob: boolean;
}

export interface MediaVideoDomProbePayload {
  ok: boolean;
  results: MediaVideoDomProbeResult[];
  error?: string;
}

const DOM_SCAN_SCRIPT: string = `(function () {
  try {
    var results = [];
    var seen = Object.create(null);
    var mediaUrlPattern = /(?:https?:\\/\\/|\\/\\/)[^"'<>\\s]+?\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?/ig;

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

    function normalizeMediaUrl(value) {
      var url = decodeLooseText(value)
        .replace(/\\\\u002[fF]/g, '/')
        .replace(/\\\\+\\//g, '/')
        .replace(/&amp;/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\\u003[dD]/g, '=')
        .replace(/\\\\u003[fF]/g, '?');
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

    function normalizeMediaText(value) {
      return decodeLooseText(value)
        .replace(/\\\\u002[fF]/g, '/')
        .replace(/\\\\+\\//g, '/')
        .replace(/&amp;/g, '&')
        .replace(/\\\\u0026/g, '&')
        .replace(/\\\\u003[dD]/g, '=')
        .replace(/\\\\u003[fF]/g, '?');
    }

    function isLikelyMediaNoiseUrl(value) {
      var raw = String(value || '').toLowerCase();
      var clean = raw.split('?')[0].split('#')[0];
      if (!clean) return true;
      if (/\\.(?:webmanifest|json|map|js|mjs|css|html|htm|xml|wasm|svg|png|jpg|jpeg|webp|gif|ico|avif)(?:$|[?#])/i.test(raw)) return true;
      if (/(?:^|\\/)(?:manifest\\.json|site\\.webmanifest|manifest\\.webmanifest)$/.test(clean)) return true;
      if (clean.indexOf('/favicon') >= 0 || clean.indexOf('/favicons/') >= 0) return true;
      return false;
    }

    function isDeferredMediaFieldMatch(text, index) {
      var prefix = String(text || '').substring(Math.max(0, index - 96), index);
      return /["']?(?:url_next|next_url|urlNext|nextUrl)["']?\\s*[:=]\\s*["']?\\s*$/i.test(prefix);
    }

    function addResult(url, extra) {
      var normalizedUrl = normalizeMediaUrl(url);
      if (!normalizedUrl || seen[normalizedUrl]) return;
      if (!/^(https?:|blob:)/i.test(normalizedUrl)) return;
      if (isLikelyMediaNoiseUrl(normalizedUrl)) return;
      seen[normalizedUrl] = true;
      var fromBlob = normalizedUrl.indexOf('blob:') === 0;
      results.push({
        url: normalizedUrl,
        signal: extra && extra.signal ? extra.signal : undefined,
        mimeType: extra && extra.mimeType ? extra.mimeType : undefined,
        posterUrl: extra && extra.posterUrl ? extra.posterUrl : undefined,
        durationMs: extra && extra.durationMs ? extra.durationMs : undefined,
        width: extra && extra.width ? extra.width : undefined,
        height: extra && extra.height ? extra.height : undefined,
        isPlaying: extra && extra.isPlaying === true ? true : undefined,
        hasPlayed: extra && extra.hasPlayed === true ? true : undefined,
        readyState: extra && typeof extra.readyState === 'number' ? extra.readyState : undefined,
        visible: extra && extra.visible === true ? true : undefined,
        fromBlob: fromBlob
      });
    }

    function scanTextForMediaUrls(text, signal) {
      var normalizedText = normalizeMediaText(text);
      mediaUrlPattern.lastIndex = 0;
      var match;
      while ((match = mediaUrlPattern.exec(normalizedText)) !== null && results.length < 48) {
        if (!isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], { signal: signal || 'script_text' });
        }
      }
      scanStructuredMediaFields(normalizedText, signal || 'script_text');
      scanPlayerMethodMediaUrls(normalizedText, signal || 'script_text');
      scanQueryStyleMediaFields(normalizedText, signal || 'script_text');
      scanEncodedPlayerFields(normalizedText, signal || 'script_text');
    }

    function scanEncodedPlayerFields(text, signal) {
      var fieldPattern = /["'](?:url|src|file|source|sources|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|hls|hls_url|hlsUrl|m3u8|m3u8Url|mpd|mpdUrl|dash|dashUrl)["']\\s*:\\s*["']([A-Za-z0-9+/=_-]{24,})["']/ig;
      var match;
      while ((match = fieldPattern.exec(String(text || ''))) !== null && results.length < 48) {
        var decoded = decodeBase64UrlText(match[1] || '');
        if (decoded) {
          scanDecodedMediaText(decoded, signal || 'script_text');
        }
      }
    }

    function scanDecodedMediaText(text, signal) {
      var normalizedText = normalizeMediaText(text);
      mediaUrlPattern.lastIndex = 0;
      var match;
      while ((match = mediaUrlPattern.exec(normalizedText)) !== null && results.length < 48) {
        if (!isDeferredMediaFieldMatch(normalizedText, match.index)) {
          addResult(match[0], { signal: signal || 'script_text' });
        }
      }
      scanStructuredMediaFields(normalizedText, signal || 'script_text');
      scanPlayerMethodMediaUrls(normalizedText, signal || 'script_text');
      scanQueryStyleMediaFields(normalizedText, signal || 'script_text');
    }

    function inferMimeForMediaField(key, url) {
      var lowerKey = String(key || '').toLowerCase();
      var lowerUrl = String(url || '').toLowerCase();
      if (lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 || /\\.m3u8(?:[?#]|$)/i.test(lowerUrl)) {
        return 'application/vnd.apple.mpegurl';
      }
      if (lowerKey.indexOf('mpd') >= 0 || lowerKey.indexOf('dash') >= 0 || /\\.mpd(?:[?#]|$)/i.test(lowerUrl)) {
        return 'application/dash+xml';
      }
      if (/\\.(?:mp4|m4v|mov)(?:[?#]|$)/i.test(lowerUrl) || /\\/obj\\/[A-Fa-f0-9]{24,}(?:[?#]|$)/.test(lowerUrl)) {
        return 'video/mp4';
      }
      if (/\\.webm(?:[?#]|$)/i.test(lowerUrl)) {
        return 'video/webm';
      }
      return undefined;
    }

    function looksLikeStructuredMediaUrl(key, value) {
      var normalized = normalizeMediaUrl(value);
      if (!/^(https?:|blob:)/i.test(normalized)) return false;
      if (isLikelyMediaNoiseUrl(normalized)) return false;
      if (/\\.(?:m3u8|mpd|mp4|m4v|mov|webm)(?:[?#]|$)/i.test(normalized)) return true;
      if (/\\/obj\\/[A-Fa-f0-9]{24,}(?:[?#]|$)/.test(normalized)) return true;
      if (/(?:\\/media\\/|\\/stream\\/|\\/video\\/)[A-Za-z0-9_-]{32,}(?:[?#]|$)/.test(normalized)) return true;
      if (/googlevideo\\.com\\/videoplayback|\\/videoplayback\\?/i.test(normalized)) return true;
      var lowerKey = String(key || '').toLowerCase();
      return lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 ||
        lowerKey.indexOf('mpd') >= 0 || lowerKey.indexOf('dash') >= 0;
    }

    function scanStructuredMediaFields(text, signal) {
      var resultSignal = (signal === 'video_element' || signal === 'audio_element') ? signal : 'embedded_attribute';
      var fieldPattern = /["']?(url3|url|src|file|fileUrl|file_url|source|sources|sourceUrl|source_url|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|contentUrl|content_url|downloadUrl|download_url|baseUrl|base_url|backupUrl|backup_url|m3u8|m3u8_2|m3u8Url|hls|hlsUrl|hls_url|mpd|mpdUrl|dash|dashUrl|dash_url)["']?\\s*[:=]\\s*["']((?:https?:\\/\\/|\\/\\/|\\/)[^"'<>\\s]{8,2000})["']/ig;
      var match;
      while ((match = fieldPattern.exec(String(text || ''))) !== null && results.length < 48) {
        if (looksLikeStructuredMediaUrl(match[1], match[2])) {
          addResult(match[2], {
            signal: resultSignal,
            mimeType: inferMimeForMediaField(match[1], match[2])
          });
        }
      }
      var relativeFieldPattern = /["']?(url3|url|src|file|fileUrl|file_url|source|sources|sourceUrl|source_url|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|contentUrl|content_url|downloadUrl|download_url|baseUrl|base_url|backupUrl|backup_url|m3u8|m3u8_2|m3u8Url|hls|hlsUrl|hls_url|mpd|mpdUrl|dash|dashUrl|dash_url)["']?\\s*[:=]\\s*["']((?:\\.{1,2}\\/)?[^"'<>\\s\\/][^"'<>\\s]{0,2000}\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?)["']/ig;
      while ((match = relativeFieldPattern.exec(String(text || ''))) !== null && results.length < 48) {
        if (looksLikeStructuredMediaUrl(match[1], match[2])) {
          addResult(match[2], {
            signal: resultSignal,
            mimeType: inferMimeForMediaField(match[1], match[2])
          });
        }
      }
    }

    function scanPlayerMethodMediaUrls(text, signal) {
      var resultSignal = (signal === 'video_element' || signal === 'audio_element') ? signal : 'embedded_attribute';
      var methodPattern = /(?:\\b(?:loadSource|attachSource|load|src)\\s*\\(\\s*|\\b(?:initialize|setup)\\s*\\([^)]{0,240}?)(["'])((?:https?:\\/\\/|\\/\\/|\\/|\\.{1,2}\\/)?[^"'<>\\s]{1,2000}\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\\s])(?:[?#][^"'<>\\s]*)?)\\1/ig;
      var match;
      while ((match = methodPattern.exec(String(text || ''))) !== null && results.length < 48) {
        if (looksLikeStructuredMediaUrl('url', match[2])) {
          addResult(match[2], {
            signal: resultSignal,
            mimeType: inferMimeForMediaField('url', match[2])
          });
        }
      }
    }

    function scanQueryStyleMediaFields(text, signal) {
      var resultSignal = (signal === 'video_element' || signal === 'audio_element') ? signal : 'embedded_attribute';
      var paramPattern = /(?:^|[?&#;,\\s])(?:file|source|src|video_url|video|url|hls|m3u8|mpd|dash)=((?:https?:\\/\\/|\\/\\/|\\/|\\.{1,2}\\/)?[^"'&<>\\s]{1,2000}\\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#&"'<>\\s])(?:\\?[^"'&<>\\s]*)?)/ig;
      var match;
      while ((match = paramPattern.exec(String(text || ''))) !== null && results.length < 48) {
        if (looksLikeStructuredMediaUrl('url', match[1])) {
          addResult(match[1], {
            signal: resultSignal,
            mimeType: inferMimeForMediaField('url', match[1])
          });
        }
      }
    }

    function scanMetaMediaTags() {
      try {
        var metas = document.querySelectorAll('meta[property], meta[name], link[itemprop], [itemprop="contentUrl"], [itemprop="embedUrl"]');
        for (var i = 0; i < metas.length && i < 96 && results.length < 48; i++) {
          var node = metas[i];
          var key = String((node.getAttribute('property') || node.getAttribute('name') || node.getAttribute('itemprop') || '')).toLowerCase();
          if (key.indexOf('og:video') < 0 && key.indexOf('og:audio') < 0 &&
            key.indexOf('twitter:player:stream') < 0 && key !== 'contenturl' && key !== 'embedurl') {
            continue;
          }
          var value = node.getAttribute('content') || node.getAttribute('value') || node.getAttribute('href') || '';
          if (value) {
            scanTextForMediaUrls(value, 'embedded_attribute');
          }
        }
      } catch (e) {
      }
    }

    function scanJsonLdScripts() {
      try {
        var scripts = document.querySelectorAll('script[type*="ld+json"]');
        for (var i = 0; i < scripts.length && i < 16 && results.length < 48; i++) {
          var text = scripts[i].textContent || '';
          if (text.length > 180000) {
            text = text.substring(0, 180000);
          }
          scanTextForMediaUrls(text, 'script_text');
        }
      } catch (e) {
      }
    }

    function scanLikelyPlayerConfigNodes() {
      try {
        var nodes = document.querySelectorAll('[data-setup], [data-config], [data-options], [data-player], [data-video], [data-file], [data-hls], [data-m3u8], [data-src], [data-url], video-js, .video-js, .jwplayer, [id*="player"], [class*="player"]');
        for (var i = 0; i < nodes.length && i < 96 && results.length < 48; i++) {
          var node = nodes[i];
          if (!node || !node.attributes) continue;
          for (var attrIndex = 0; attrIndex < node.attributes.length && attrIndex < 48 && results.length < 48; attrIndex++) {
            var value = node.attributes[attrIndex] ? node.attributes[attrIndex].value : '';
            if (value && /(?:https?:\\/\\/|\\/\\/|\\/|\\.(?:m3u8|mpd|mp4|m4v|mov|webm)|url|src|file|source|video)/i.test(value)) {
              scanTextForMediaUrls(value, 'embedded_attribute');
            }
          }
        }
      } catch (e) {
      }
    }

    function scanKnownGlobalConfigs() {
      try {
        var names = [
          '__INITIAL_STATE__', '__INITIAL_DATA__', '__NEXT_DATA__', '__NUXT__', '__playinfo__',
          'playerConfig', 'videoConfig', 'playConfig', 'playurl', 'playUrlInfo', 'videoData',
          'playerData', 'videoInfo', 'mediaInfo', 'streamInfo', 'playInfo', 'jwplayerConfig',
          'dplayerOptions', 'videoSources', 'mediaSources'
        ];
        for (var i = 0; i < names.length && results.length < 48; i++) {
          var value = window[names[i]];
          if (!value) continue;
          if (typeof value === 'string') {
            scanTextForMediaUrls(value, 'script_text');
          } else if (typeof value === 'object') {
            try {
              var text = JSON.stringify(value);
              if (text.length > 240000) {
                text = text.substring(0, 240000);
              }
              scanTextForMediaUrls(text, 'script_text');
            } catch (e) {
            }
          }
        }
      } catch (e) {
      }
    }

    function mediaSignal(el) {
      return el.tagName && String(el.tagName).toLowerCase() === 'audio' ? 'audio_element' : 'video_element';
    }

    function collectMediaElements(root, output, depth) {
      if (!root || depth > 3 || output.length >= 48) return;
      try {
        var elements = root.querySelectorAll ? root.querySelectorAll('video, audio') : [];
        for (var index = 0; index < elements.length && output.length < 48; index++) {
          output.push(elements[index]);
        }
        var frames = root.querySelectorAll ? root.querySelectorAll('iframe,frame') : [];
        for (var frameIndex = 0; frameIndex < frames.length && output.length < 48; frameIndex++) {
          try {
            var doc = frames[frameIndex].contentDocument;
            if (doc) {
              collectMediaElements(doc, output, depth + 1);
            }
          } catch (e) {
          }
        }
      } catch (e) {
      }
    }

    function isVisibleMedia(el) {
      try {
        var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { width: 0, height: 0 };
        var viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
        var viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
        return rect.width > 8 && rect.height > 8 &&
          rect.bottom > 0 && rect.right > 0 &&
          rect.top < viewportHeight && rect.left < viewportWidth;
      } catch (e) {
        return true;
      }
    }

    function mediaArea(el) {
      try {
        var rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { width: 0, height: 0 };
        return Math.max(0, rect.width || 0) * Math.max(0, rect.height || 0);
      } catch (e) {
        return 0;
      }
    }

    function scoreMedia(el) {
      var score = mediaArea(el);
      if (!el.paused && !el.ended) {
        score += 1000000;
      }
      if ((el.currentTime || 0) > 0) {
        score += 200000;
      }
      if ((el.readyState || 0) >= 2) {
        score += 100000;
      }
      if ((el.videoWidth || 0) > 0 && (el.videoHeight || 0) > 0) {
        score += 50000;
      }
      if (isVisibleMedia(el)) {
        score += 10000;
      }
      return score;
    }

    function addSourceRecord(records, url, mimeType) {
      if (!url) return;
      records.push({
        url: url,
        mimeType: mimeType || undefined
      });
    }

    function collectSourceRecords(el) {
      var records = [];
      addSourceRecord(records, el.currentSrc || '', el.getAttribute ? el.getAttribute('type') : '');
      addSourceRecord(records, el.src || '', el.getAttribute ? el.getAttribute('type') : '');
      addSourceRecord(records, el.getAttribute ? el.getAttribute('src') : '', el.getAttribute ? el.getAttribute('type') : '');
      try {
        var sources = el.querySelectorAll ? el.querySelectorAll('source') : [];
        for (var sourceIndex = 0; sourceIndex < sources.length && sourceIndex < 8; sourceIndex++) {
          addSourceRecord(
            records,
            sources[sourceIndex].src || sources[sourceIndex].getAttribute('src') || '',
            sources[sourceIndex].getAttribute('type') || ''
          );
        }
      } catch (e) {
      }
      var attrNames = ['data-src', 'data-source', 'data-sources', 'data-video', 'data-url', 'data-file',
        'data-stream', 'data-stream-url', 'data-play-url', 'data-playurl', 'data-hls', 'data-m3u8',
        'data-mp4', 'data-dash', 'data-mpd', 'poster'];
      for (var attrIndex = 0; attrIndex < attrNames.length; attrIndex++) {
        addSourceRecord(records, el.getAttribute ? el.getAttribute(attrNames[attrIndex]) : '', '');
      }
      return records;
    }

    function scanNearbyPlayerAttributes(el) {
      var node = el;
      for (var depth = 0; node && depth < 5; depth++) {
        try {
          var signature = String((node.id || '') + ' ' + (node.className || '')).toLowerCase();
          var likelyPlayer = depth === 0 || signature.indexOf('player') >= 0 || signature.indexOf('video') >= 0 ||
            signature.indexOf('dplayer') >= 0 || signature.indexOf('xgplayer') >= 0 ||
            signature.indexOf('artplayer') >= 0 || signature.indexOf('jwplayer') >= 0 ||
            signature.indexOf('prism') >= 0;
          if (likelyPlayer && node.attributes) {
            for (var attrIndex = 0; attrIndex < node.attributes.length && attrIndex < 32; attrIndex++) {
              var value = node.attributes[attrIndex] ? node.attributes[attrIndex].value : '';
              if (value && /(?:https?:\\/\\/|\\/\\/|\\.(?:m3u8|mpd|mp4|webm))/i.test(value)) {
                scanTextForMediaUrls(value, mediaSignal(el));
              }
            }
          }
        } catch (e) {
        }
        node = node.parentElement;
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

    var elements = [];
    collectMediaElements(document, elements, 0);
    elements.sort(function (left, right) {
      return scoreMedia(right) - scoreMedia(left);
    });
    for (var i = 0; i < elements.length && i < 32; i++) {
      var el = elements[i];
      var records = collectSourceRecords(el);
      var signal = mediaSignal(el);
      var extra = {
        posterUrl: el.poster || undefined,
        durationMs: isFinite(el.duration) && el.duration > 0 ? Math.round(el.duration * 1000) : undefined,
        width: el.videoWidth || undefined,
        height: el.videoHeight || undefined,
        isPlaying: !el.paused && !el.ended,
        hasPlayed: (el.currentTime || 0) > 0,
        readyState: el.readyState || 0,
        visible: isVisibleMedia(el)
      };
      for (var recordIndex = 0; recordIndex < records.length && recordIndex < 12; recordIndex++) {
        addResult(records[recordIndex].url, {
          signal: signal,
          mimeType: records[recordIndex].mimeType,
          posterUrl: extra.posterUrl,
          durationMs: extra.durationMs,
          width: extra.width,
          height: extra.height,
          isPlaying: extra.isPlaying,
          hasPlayed: extra.hasPlayed,
          readyState: extra.readyState,
          visible: extra.visible
        });
      }
      scanNearbyPlayerAttributes(el);
    }

    scanTextForMediaUrls(location.href || '', 'location');
    scanMetaMediaTags();
    scanJsonLdScripts();
    scanLikelyPlayerConfigNodes();
    scanKnownGlobalConfigs();

    var scripts = document.querySelectorAll('script:not([src])');
    var scannedChars = 0;
    for (var scriptIndex = 0; scriptIndex < scripts.length && scriptIndex < 32 && scannedChars < 900000; scriptIndex++) {
      var scriptText = scripts[scriptIndex].textContent || '';
      if (!scriptText) continue;
      if (scriptText.length > 240000) {
        scriptText = scriptText.substring(0, 240000);
      }
      scannedChars += scriptText.length;
      scanTextForMediaUrls(scriptText, 'script_text');
      if (results.length >= 48) break;
    }
    return JSON.stringify({ ok: true, results: results });
  } catch (e) {
    return JSON.stringify({ ok: false, results: [], error: String((e && e.message) || e) });
  }
})();`;

export class MediaVideoDomProbeScript {
  build(): string {
    return DOM_SCAN_SCRIPT;
  }

  parse(raw: string): MediaVideoDomProbePayload {
    if (raw.length === 0) {
      return { ok: false, results: [], error: 'empty_result' };
    }
    try {
      const parsed: MediaVideoDomProbePayload = JSON.parse(raw) as MediaVideoDomProbePayload;
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

export function extractMediaUrlsFromText(text: string): string[] {
  const normalizedText = normalizeMediaText(text);
  const pattern = /(?:https?:\/\/|\/\/)[^"'<>\s]+?\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\s])(?:[?#][^"'<>\s]*)?/ig;
  const results: string[] = [];
  const seen: Record<string, boolean> = {};
  collectMediaUrls(normalizedText, pattern, results, seen, 48);
  collectStructuredMediaFieldUrls(normalizedText, results, seen, 48);
  collectPlayerMethodMediaUrls(normalizedText, results, seen, 48);
  collectQueryStyleMediaFieldUrls(normalizedText, results, seen, 48);
  const encodedFields = extractEncodedPlayerFields(normalizedText);
  for (let i = 0; i < encodedFields.length && results.length < 48; i++) {
    const decoded = decodeBase64MediaText(encodedFields[i]);
    if (decoded.length > 0) {
      const normalizedDecoded = normalizeMediaText(decoded);
      collectMediaUrls(normalizedDecoded, pattern, results, seen, 48);
      collectStructuredMediaFieldUrls(normalizedDecoded, results, seen, 48);
      collectPlayerMethodMediaUrls(normalizedDecoded, results, seen, 48);
      collectQueryStyleMediaFieldUrls(normalizedDecoded, results, seen, 48);
    }
  }
  return results;
}

function collectMediaUrls(
  text: string,
  pattern: RegExp,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  pattern.lastIndex = 0;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    const normalizedUrl = normalizeMediaText(match[0]);
    const finalUrl = normalizedUrl.indexOf('//') === 0 ? `https:${normalizedUrl}` : normalizedUrl;
    if (!isDeferredMediaFieldMatch(text, match.index) &&
      seen[finalUrl] !== true && !isLikelyMediaNoiseUrl(finalUrl)) {
      seen[finalUrl] = true;
      results.push(finalUrl);
    }
    match = pattern.exec(text);
  }
}

function addStructuredMediaUrl(
  key: string,
  url: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  if (results.length >= limit) {
    return;
  }
  const normalizedUrl = normalizeMediaText(url);
  const finalUrl = normalizedUrl.indexOf('//') === 0 ? `https:${normalizedUrl}` : normalizedUrl;
  if (looksLikeStructuredMediaUrl(key, finalUrl) && seen[finalUrl] !== true) {
    seen[finalUrl] = true;
    results.push(finalUrl);
  }
}

function collectStructuredMediaFieldUrls(
  text: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  const pattern =
    /["']?(url3|url|src|file|fileUrl|file_url|source|sources|sourceUrl|source_url|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|contentUrl|content_url|downloadUrl|download_url|baseUrl|base_url|backupUrl|backup_url|m3u8|m3u8_2|m3u8Url|hls|hlsUrl|hls_url|mpd|mpdUrl|dash|dashUrl|dash_url)["']?\s*[:=]\s*["']((?:https?:\/\/|\/\/|\/)[^"'<>\s]{8,2000})["']/ig;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredMediaUrl(match[1], match[2], results, seen, limit);
    match = pattern.exec(text);
  }
  const relativePattern =
    /["']?(url3|url|src|file|fileUrl|file_url|source|sources|sourceUrl|source_url|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|contentUrl|content_url|downloadUrl|download_url|baseUrl|base_url|backupUrl|backup_url|m3u8|m3u8_2|m3u8Url|hls|hlsUrl|hls_url|mpd|mpdUrl|dash|dashUrl|dash_url)["']?\s*[:=]\s*["']((?:\.{1,2}\/)?[^"'<>\s\/][^"'<>\s]{0,2000}\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\s])(?:[?#][^"'<>\s]*)?)["']/ig;
  match = relativePattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredMediaUrl(match[1], match[2], results, seen, limit);
    match = relativePattern.exec(text);
  }
}

function collectPlayerMethodMediaUrls(
  text: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  const pattern =
    /(?:\b(?:loadSource|attachSource|load|src)\s*\(\s*|\b(?:initialize|setup)\s*\([^)]{0,240}?)(["'])((?:https?:\/\/|\/\/|\/|\.{1,2}\/)?[^"'<>\s]{1,2000}\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#"'<>\s])(?:[?#][^"'<>\s]*)?)\1/ig;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredMediaUrl('url', match[2], results, seen, limit);
    match = pattern.exec(text);
  }
}

function collectQueryStyleMediaFieldUrls(
  text: string,
  results: string[],
  seen: Record<string, boolean>,
  limit: number
): void {
  const pattern =
    /(?:^|[?&#;,\s])(?:file|source|src|video_url|video|url|hls|m3u8|mpd|dash)=((?:https?:\/\/|\/\/|\/|\.{1,2}\/)?[^"'&<>\s]{1,2000}\.(?:m3u8|m3u|mpd|mp4|m4v|mov|webm)(?=$|[?#&"'<>\s])(?:\?[^"'&<>\s]*)?)/ig;
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && results.length < limit) {
    addStructuredMediaUrl('url', match[1], results, seen, limit);
    match = pattern.exec(text);
  }
}

function looksLikeStructuredMediaUrl(key: string, url: string): boolean {
  if (/^(https?:|blob:)/i.test(url) !== true && /^[./A-Za-z0-9_-]/.test(url) !== true) {
    return false;
  }
  if (isLikelyMediaNoiseUrl(url)) {
    return false;
  }
  if (/\.(?:m3u8|mpd|mp4|m4v|mov|webm)(?:[?#]|$)/i.test(url)) {
    return true;
  }
  if (/\/obj\/[A-Fa-f0-9]{24,}(?:[?#]|$)/.test(url)) {
    return true;
  }
  if (/(?:\/media\/|\/stream\/|\/video\/)[A-Za-z0-9_-]{32,}(?:[?#]|$)/.test(url)) {
    return true;
  }
  if (/googlevideo\.com\/videoplayback|\/videoplayback\?/i.test(url)) {
    return true;
  }
  const lowerKey = key.toLowerCase();
  return lowerKey.indexOf('m3u8') >= 0 || lowerKey.indexOf('hls') >= 0 ||
    lowerKey.indexOf('mpd') >= 0 || lowerKey.indexOf('dash') >= 0;
}

function isLikelyMediaNoiseUrl(value: string): boolean {
  const raw = value.toLowerCase();
  const clean = raw.split('?')[0].split('#')[0];
  if (clean.length <= 0) {
    return true;
  }
  if (/\.(?:webmanifest|json|map|js|mjs|css|html|htm|xml|wasm|svg|png|jpg|jpeg|webp|gif|ico|avif)(?:$|[?#])/i.test(raw)) {
    return true;
  }
  if (/(?:^|\/)(?:manifest\.json|site\.webmanifest|manifest\.webmanifest)$/.test(clean)) {
    return true;
  }
  return clean.indexOf('/favicon') >= 0 || clean.indexOf('/favicons/') >= 0;
}

function isDeferredMediaFieldMatch(text: string, index: number): boolean {
  const prefix = text.substring(Math.max(0, index - 96), index);
  return /["']?(?:url_next|next_url|urlNext|nextUrl)["']?\s*[:=]\s*["']?\s*$/i.test(prefix);
}

function normalizeMediaText(value: string): string {
  let text = value;
  for (let i = 0; i < 3; i++) {
    try {
      const decoded: string = decodeURIComponent(text);
      if (decoded === text) {
        break;
      }
      text = decoded;
    } catch (_error) {
      break;
    }
  }
  return text
    .replace(/\\u002[fF]/g, '/')
    .replace(/\\\\\//g, '/')
    .replace(/\\\//g, '/')
    .replace(/&amp;/g, '&')
    .replace(/\\u0026/g, '&')
    .replace(/\\u003[dD]/g, '=')
    .replace(/\\u003[fF]/g, '?');
}

function extractEncodedPlayerFields(text: string): string[] {
  const pattern =
    /["'](?:url|src|file|source|sources|video|video_url|videoUrl|play_url|playUrl|playback_url|playbackUrl|stream|stream_url|streamUrl|media_url|mediaUrl|hls|hls_url|hlsUrl|m3u8|m3u8Url|mpd|mpdUrl|dash|dashUrl)["']\s*:\s*["']([A-Za-z0-9+/=_-]{24,})["']/ig;
  const fields: string[] = [];
  let match: RegExpExecArray | null = pattern.exec(text);
  while (match !== null && fields.length < 24) {
    fields.push(match[1]);
    match = pattern.exec(text);
  }
  return fields;
}

function decodeBase64MediaText(value: string): string {
  return normalizeMediaText(decodeBase64Text(value));
}

function decodeBase64Text(value: string): string {
  let normalized = value.replace(/-/g, '+').replace(/_/g, '/');
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalized) || normalized.length % 4 === 1) {
    return '';
  }
  while (normalized.length % 4 !== 0) {
    normalized += '=';
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  let bits = 0;
  let bitCount = 0;
  let output = '';
  for (let i = 0; i < normalized.length; i++) {
    const ch = normalized.charAt(i);
    if (ch === '=') {
      break;
    }
    const valueIndex = alphabet.indexOf(ch);
    if (valueIndex < 0) {
      return '';
    }
    bits = (bits << 6) | valueIndex;
    bitCount += 6;
    if (bitCount >= 8) {
      bitCount -= 8;
      output += String.fromCharCode((bits >> bitCount) & 0xFF);
    }
  }
  return output;
}
