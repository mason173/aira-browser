export interface YoutubeUrlMatch {
  isYoutubePage: boolean;
  isVideoplayback: boolean;
  videoId?: string;
  surface?: 'watch' | 'shorts' | 'embed' | 'mobile' | 'short_link' | 'music';
}

const VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{8,16}$/;

function parseQueryParam(url: string, name: string): string | undefined {
  const queryIndex = url.indexOf('?');
  if (queryIndex < 0) {
    return undefined;
  }
  const hashIndex = url.indexOf('#', queryIndex);
  const query = hashIndex >= 0 ? url.substring(queryIndex + 1, hashIndex) : url.substring(queryIndex + 1);
  const parts = query.split('&');
  for (let i = 0; i < parts.length; i++) {
    const eq = parts[i].indexOf('=');
    if (eq < 0) {
      continue;
    }
    const key = parts[i].substring(0, eq);
    if (key === name) {
      try {
        return decodeURIComponent(parts[i].substring(eq + 1));
      } catch (_error) {
        return parts[i].substring(eq + 1);
      }
    }
  }
  return undefined;
}

function pathSegmentAfter(url: string, prefix: string): string | undefined {
  const idx = url.indexOf(prefix);
  if (idx < 0) {
    return undefined;
  }
  let tail = url.substring(idx + prefix.length);
  const cuts = ['?', '#', '/'];
  let cut = tail.length;
  for (let i = 0; i < cuts.length; i++) {
    const at = tail.indexOf(cuts[i]);
    if (at >= 0 && at < cut) {
      cut = at;
    }
  }
  tail = tail.substring(0, cut);
  return tail.length > 0 ? tail : undefined;
}

function hostOf(url: string): string {
  try {
    const scheme = url.indexOf('://');
    if (scheme < 0) {
      return '';
    }
    const start = scheme + 3;
    let end = url.length;
    const slash = url.indexOf('/', start);
    if (slash >= 0) {
      end = slash;
    }
    const q = url.indexOf('?', start);
    if (q >= 0 && q < end) {
      end = q;
    }
    return url.substring(start, end).toLowerCase();
  } catch (_error) {
    return '';
  }
}

export class YoutubeUrlMatcher {
  match(url: string): YoutubeUrlMatch {
    const host = hostOf(url);
    if (host.length === 0) {
      return { isYoutubePage: false, isVideoplayback: false };
    }
    if (host.endsWith('googlevideo.com') && url.indexOf('/videoplayback') >= 0) {
      return { isYoutubePage: false, isVideoplayback: true };
    }
    const isHostYoutube =
      host === 'youtube.com' || host.endsWith('.youtube.com') ||
      host === 'youtu.be' || host.endsWith('.youtu.be') ||
      host === 'music.youtube.com';
    if (!isHostYoutube) {
      return { isYoutubePage: false, isVideoplayback: false };
    }
    if (host === 'youtu.be') {
      const id = pathSegmentAfter(url, 'youtu.be/');
      if (id !== undefined && VIDEO_ID_PATTERN.test(id)) {
        return { isYoutubePage: true, isVideoplayback: false, videoId: id, surface: 'short_link' };
      }
      return { isYoutubePage: true, isVideoplayback: false };
    }
    if (url.indexOf('/shorts/') >= 0) {
      const id = pathSegmentAfter(url, '/shorts/');
      if (id !== undefined && VIDEO_ID_PATTERN.test(id)) {
        return { isYoutubePage: true, isVideoplayback: false, videoId: id, surface: 'shorts' };
      }
      return { isYoutubePage: true, isVideoplayback: false, surface: 'shorts' };
    }
    if (url.indexOf('/embed/') >= 0) {
      const id = pathSegmentAfter(url, '/embed/');
      if (id !== undefined && VIDEO_ID_PATTERN.test(id)) {
        return { isYoutubePage: true, isVideoplayback: false, videoId: id, surface: 'embed' };
      }
      return { isYoutubePage: true, isVideoplayback: false, surface: 'embed' };
    }
    if (url.indexOf('/watch') >= 0) {
      const id = parseQueryParam(url, 'v');
      const surface: 'watch' | 'mobile' | 'music' =
        host === 'm.youtube.com' ? 'mobile' : host === 'music.youtube.com' ? 'music' : 'watch';
      if (id !== undefined && VIDEO_ID_PATTERN.test(id)) {
        return { isYoutubePage: true, isVideoplayback: false, videoId: id, surface: surface };
      }
      return { isYoutubePage: true, isVideoplayback: false, surface: surface };
    }
    return { isYoutubePage: true, isVideoplayback: false };
  }

  isVideoIdLike(value: string): boolean {
    return VIDEO_ID_PATTERN.test(value);
  }

  parseQueryParamForTest(url: string, name: string): string | undefined {
    return parseQueryParam(url, name);
  }
}
