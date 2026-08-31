import { YoutubeVideoplaybackHint } from './YoutubeModels';

function parseQueryParams(url: string): Record<string, string> {
  const params: Record<string, string> = {};
  const q = url.indexOf('?');
  if (q < 0) {
    return params;
  }
  const hash = url.indexOf('#', q);
  const query = hash >= 0 ? url.substring(q + 1, hash) : url.substring(q + 1);
  const parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    const eq = parts[i].indexOf('=');
    if (eq < 0) {
      continue;
    }
    const key = parts[i].substring(0, eq);
    const raw = parts[i].substring(eq + 1);
    try {
      params[key] = decodeURIComponent(raw);
    } catch (_error) {
      params[key] = raw;
    }
  }
  return params;
}

export class YoutubeVideoplaybackUrlParser {
  parse(url: string): YoutubeVideoplaybackHint {
    const params = parseQueryParams(url);
    const itagRaw = params['itag'];
    const itag = itagRaw !== undefined ? parseInt(itagRaw, 10) : NaN;
    const mime = params['mime'];
    const clenRaw = params['clen'];
    const contentLength = clenRaw !== undefined ? parseInt(clenRaw, 10) : NaN;
    const durRaw = params['dur'];
    const durationMs = durRaw !== undefined ? Math.round(parseFloat(durRaw) * 1000) : NaN;
    const expireRaw = params['expire'];
    const expireSeconds = expireRaw !== undefined ? parseInt(expireRaw, 10) : NaN;
    return {
      url: url,
      itag: !isNaN(itag) ? itag : undefined,
      mime: mime,
      contentLength: !isNaN(contentLength) ? contentLength : undefined,
      durationMs: !isNaN(durationMs) ? durationMs : undefined,
      expireSeconds: !isNaN(expireSeconds) ? expireSeconds : undefined
    };
  }
}
