import type { CSSProperties } from 'react';
import { IS_LITE_BUILD } from '@/config/distribution';
import type { ViewportRect } from '@/hooks/useLiveViewportRect';

function readViewportSize() {
  if (typeof window === 'undefined') {
    return {
      width: 1280,
      height: 720,
    };
  }

  return {
    width: Math.max(1, window.innerWidth),
    height: Math.max(1, window.innerHeight),
  };
}

export function buildViewportImageSliceBackgroundStyle({
  rect,
  imageSrc,
  overscanPx = 0,
  scale = 1,
  blurPx = 0,
  preferFixedAttachment = true,
}: {
  rect: ViewportRect;
  imageSrc: string;
  overscanPx?: number;
  scale?: number;
  blurPx?: number;
  preferFixedAttachment?: boolean;
}): CSSProperties {
  const safeScale = Number.isFinite(scale) && scale > 0 ? scale : 1;
  if (preferFixedAttachment && IS_LITE_BUILD && blurPx <= 0 && Math.abs(safeScale - 1) < 0.001) {
    return {
      position: 'absolute',
      inset: `${-overscanPx}px`,
      backgroundImage: `url(${JSON.stringify(imageSrc)})`,
      backgroundAttachment: 'fixed',
      backgroundRepeat: 'no-repeat',
      backgroundPosition: 'center center',
      backgroundSize: 'cover',
    };
  }

  const viewportSize = readViewportSize();
  const baseWidthPx = viewportSize.width + overscanPx * 2;
  const baseHeightPx = viewportSize.height + overscanPx * 2;
  const backgroundWidthPx = baseWidthPx * safeScale;
  const backgroundHeightPx = baseHeightPx * safeScale;
  const scaleOffsetX = (backgroundWidthPx - baseWidthPx) / 2;
  const scaleOffsetY = (backgroundHeightPx - baseHeightPx) / 2;

  return {
    position: 'absolute',
    left: `${-rect.left - overscanPx - scaleOffsetX}px`,
    top: `${-rect.top - overscanPx - scaleOffsetY}px`,
    width: `${backgroundWidthPx}px`,
    height: `${backgroundHeightPx}px`,
    backgroundImage: `url(${JSON.stringify(imageSrc)})`,
    backgroundRepeat: 'no-repeat',
    backgroundPosition: 'center center',
    backgroundSize: 'cover',
    filter: blurPx > 0 ? `blur(${blurPx}px)` : undefined,
    WebkitFilter: blurPx > 0 ? `blur(${blurPx}px)` : undefined,
  };
}

export function buildViewportGradientSliceStyle({
  rect,
  overscanPx = 0,
  blurPx = 0,
}: {
  rect: ViewportRect;
  overscanPx?: number;
  blurPx?: number;
}): CSSProperties {
  return {
    position: 'absolute',
    left: `${-rect.left - overscanPx}px`,
    top: `${-rect.top - overscanPx}px`,
    width: `calc(100vw + ${overscanPx * 2}px)`,
    height: `calc(100vh + ${overscanPx * 2}px)`,
    maxWidth: 'none',
    filter: blurPx > 0 ? `blur(${blurPx}px)` : undefined,
    WebkitFilter: blurPx > 0 ? `blur(${blurPx}px)` : undefined,
  };
}
