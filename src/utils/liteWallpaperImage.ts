const LITE_WALLPAPER_DISPLAY_MAX_EDGE_PX = 960;
const LITE_WALLPAPER_CUSTOM_MAX_EDGE_PX = 1280;
const LITE_WALLPAPER_WEBP_QUALITY = 0.78;

type BitmapSource = ImageBitmap | HTMLImageElement;

function releaseObjectUrl(url: string) {
  try {
    URL.revokeObjectURL(url);
  } catch {}
}

function resolveTargetSize(width: number, height: number, maxEdge: number) {
  const safeWidth = Math.max(1, Math.round(width));
  const safeHeight = Math.max(1, Math.round(height));
  const longestEdge = Math.max(safeWidth, safeHeight);
  const scale = Math.min(1, maxEdge / longestEdge);
  return {
    width: Math.max(1, Math.round(safeWidth * scale)),
    height: Math.max(1, Math.round(safeHeight * scale)),
  };
}

async function loadBitmapFromBlob(blob: Blob): Promise<BitmapSource> {
  if (typeof createImageBitmap === 'function') {
    try {
      return await createImageBitmap(blob);
    } catch {}
  }

  const objectUrl = URL.createObjectURL(blob);
  try {
    return await new Promise<HTMLImageElement>((resolve, reject) => {
      const image = new Image();
      image.decoding = 'async';
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error('lite-wallpaper-image-load-failed'));
      image.src = objectUrl;
    });
  } finally {
    releaseObjectUrl(objectUrl);
  }
}

function getBitmapDimensions(bitmap: BitmapSource) {
  if (typeof ImageBitmap !== 'undefined' && bitmap instanceof ImageBitmap) {
    return {
      width: bitmap.width,
      height: bitmap.height,
    };
  }
  const image = bitmap as HTMLImageElement;
  return {
    width: image.naturalWidth || image.width,
    height: image.naturalHeight || image.height,
  };
}

async function canvasToBlob(canvas: HTMLCanvasElement): Promise<Blob> {
  const blob = await new Promise<Blob | null>((resolve) => {
    canvas.toBlob(resolve, 'image/webp', LITE_WALLPAPER_WEBP_QUALITY);
  });
  if (blob) return blob;

  const fallbackBlob = await new Promise<Blob | null>((resolve) => {
    canvas.toBlob(resolve, 'image/jpeg', 0.88);
  });
  if (fallbackBlob) return fallbackBlob;

  throw new Error('lite-wallpaper-blob-unavailable');
}

async function downsampleWallpaperBlob(blob: Blob, maxEdge: number): Promise<Blob> {
  let bitmap: BitmapSource | null = null;
  try {
    bitmap = await loadBitmapFromBlob(blob);
    const dimensions = getBitmapDimensions(bitmap);
    const targetSize = resolveTargetSize(dimensions.width, dimensions.height, maxEdge);
    const canvas = document.createElement('canvas');
    canvas.width = targetSize.width;
    canvas.height = targetSize.height;
    const context = canvas.getContext('2d', { alpha: false });
    if (!context) throw new Error('lite-wallpaper-canvas-unavailable');
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = 'high';
    context.drawImage(bitmap, 0, 0, targetSize.width, targetSize.height);
    return await canvasToBlob(canvas);
  } finally {
    if (typeof ImageBitmap !== 'undefined' && bitmap instanceof ImageBitmap) {
      bitmap.close();
    }
  }
}

export async function createLiteDisplayWallpaperObjectUrl(src: string): Promise<string> {
  const response = await fetch(src);
  if (!response.ok) {
    throw new Error(`lite-wallpaper-fetch-failed-${response.status}`);
  }
  const sourceBlob = await response.blob();
  const displayBlob = await downsampleWallpaperBlob(sourceBlob, LITE_WALLPAPER_DISPLAY_MAX_EDGE_PX);
  return URL.createObjectURL(displayBlob);
}

export async function readLiteCustomWallpaperFile(file: File): Promise<Blob> {
  return downsampleWallpaperBlob(file, LITE_WALLPAPER_CUSTOM_MAX_EDGE_PX);
}
