import { useEffect, useState } from 'react';
import { createLiteDisplayWallpaperObjectUrl } from '@/utils/liteWallpaperImage';

type UseLiteDisplayWallpaperSrcOptions = {
  sourceUrl: string;
  enabled: boolean;
};

const liteDisplayWallpaperCache = new Map<string, string>();

function revokeLiteDisplayWallpaperUrl(url: string) {
  try {
    URL.revokeObjectURL(url);
  } catch {}
}

function pruneLiteDisplayWallpaperCache(preserveSourceUrl: string) {
  for (const [sourceUrl, objectUrl] of liteDisplayWallpaperCache) {
    if (sourceUrl === preserveSourceUrl) continue;
    liteDisplayWallpaperCache.delete(sourceUrl);
    revokeLiteDisplayWallpaperUrl(objectUrl);
  }
}

function clearLiteDisplayWallpaperCache() {
  for (const objectUrl of liteDisplayWallpaperCache.values()) {
    revokeLiteDisplayWallpaperUrl(objectUrl);
  }
  liteDisplayWallpaperCache.clear();
}

export function useLiteDisplayWallpaperSrc({
  sourceUrl,
  enabled,
}: UseLiteDisplayWallpaperSrcOptions) {
  const normalizedSourceUrl = sourceUrl.trim();
  const [displayWallpaperSrc, setDisplayWallpaperSrc] = useState('');

  useEffect(() => {
    if (!enabled || !normalizedSourceUrl || typeof document === 'undefined') {
      clearLiteDisplayWallpaperCache();
      setDisplayWallpaperSrc('');
      return;
    }

    const cached = liteDisplayWallpaperCache.get(normalizedSourceUrl);
    if (cached) {
      setDisplayWallpaperSrc(cached);
      pruneLiteDisplayWallpaperCache(normalizedSourceUrl);
      return;
    }

    let cancelled = false;
    setDisplayWallpaperSrc('');
    void createLiteDisplayWallpaperObjectUrl(normalizedSourceUrl)
      .then((objectUrl) => {
        if (cancelled) {
          revokeLiteDisplayWallpaperUrl(objectUrl);
          return;
        }
        liteDisplayWallpaperCache.set(normalizedSourceUrl, objectUrl);
        pruneLiteDisplayWallpaperCache(normalizedSourceUrl);
        setDisplayWallpaperSrc(objectUrl);
      })
      .catch(() => {
        if (!cancelled) setDisplayWallpaperSrc(normalizedSourceUrl);
      });

    return () => {
      cancelled = true;
    };
  }, [enabled, normalizedSourceUrl]);

  return displayWallpaperSrc;
}
