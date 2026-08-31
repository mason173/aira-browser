import { display } from '@kit.ArkUI';

export interface BookmarkFolderIconMaskState {
  backCommands: string;
  frontCommands: string;
  paperCommands: string;
  widthPx: number;
  heightPx: number;
}

export interface BookmarkFolderIconPaletteState {
  backColor: string;
  frontColor: string;
  paperColor: string;
}

interface BookmarkFolderIconRgb {
  r: number;
  g: number;
  b: number;
}

interface BookmarkFolderIconHsl {
  h: number;
  s: number;
  l: number;
}

const BOOKMARK_FOLDER_SOURCE_WIDTH: number = 30;
const BOOKMARK_FOLDER_SOURCE_HEIGHT: number = 24;
const BOOKMARK_FOLDER_FALLBACK_ACCENT_COLOR: string = '#0A59F7';
const BOOKMARK_FOLDER_PAPER_COLOR: string = '#FFFFFF';
const BOOKMARK_FOLDER_BACK_PATH: string =
  'M14.3535 3H27.1426C28.7205 3 30 4.27505 30 5.84766V21.1523C30 22.725 28.7205 24 27.1426 24H2.85742C1.27947 24 0 22.725 0 21.1523V3.29395C0.0000853062 1.47474 1.35067 0 3.0166 0H11.6064L14.3535 3Z';
const BOOKMARK_FOLDER_FRONT_PATH: string =
  'M0 5.84746C0 4.27485 1.27919 3 2.85714 3H27.1429C28.7208 3 30 4.27485 30 5.84746V21.1525C30 22.7251 28.7208 24 27.1429 24H2.85714C1.27919 24 0 22.7251 0 21.1525V5.84746Z';
const BOOKMARK_FOLDER_PAPER_PATH: string =
  'M1.9 6.7C1.9 5.5 2.81 4.48 4.01 4.35L26.63 1.98C28.13 1.82 29.43 3 29.43 4.52V15.72C29.43 17.18 28.25 18.36 26.79 18.36H4.3C2.97 18.36 1.9 17.28 1.9 15.96V6.7Z';

export class BookmarkFolderIconViewModel {
  buildCountLabel(count: number): string {
    if (count < 0) {
      return '';
    }
    if (count > 99) {
      return '99+';
    }
    return `${Math.floor(count)}`;
  }

  buildPaletteState(accentColor: string): BookmarkFolderIconPaletteState {
    const fallbackRgb = this.parseHexColor(BOOKMARK_FOLDER_FALLBACK_ACCENT_COLOR) as BookmarkFolderIconRgb;
    const accentRgb = this.parseHexColor(accentColor) ?? fallbackRgb;
    const accentHsl = this.rgbToHsl(accentRgb);
    const folderHue = this.wrapHue(accentHsl.h + 2);
    const folderSaturation = this.clamp(Math.max(0.58, accentHsl.s * 1.02), 0.5, 0.9);

    return {
      backColor: this.hslToHex({
        h: this.wrapHue(folderHue - 3),
        s: folderSaturation,
        l: this.clamp(accentHsl.l - 0.07, 0.36, 0.5)
      }),
      frontColor: this.hslToHex({
        h: this.wrapHue(folderHue + 5),
        s: this.clamp(folderSaturation * 0.96, 0.5, 0.86),
        l: this.clamp(accentHsl.l + 0.13, 0.56, 0.72)
      }),
      paperColor: BOOKMARK_FOLDER_PAPER_COLOR
    };
  }

  buildMaskState(widthVp: number): BookmarkFolderIconMaskState {
    const safeWidthVp = Math.max(1, widthVp);
    const heightVp = this.resolveHeightVp(safeWidthVp);
    const density = this.resolveDensity();
    const widthPx = safeWidthVp * density;
    const heightPx = heightVp * density;
    const scale = widthPx / BOOKMARK_FOLDER_SOURCE_WIDTH;

    return {
      backCommands: this.scalePathCommands(BOOKMARK_FOLDER_BACK_PATH, scale),
      frontCommands: this.scalePathCommands(BOOKMARK_FOLDER_FRONT_PATH, scale),
      paperCommands: this.scalePathCommands(BOOKMARK_FOLDER_PAPER_PATH, scale),
      widthPx: widthPx,
      heightPx: heightPx
    };
  }

  resolveHeightVp(widthVp: number): number {
    return Math.max(1, widthVp) * BOOKMARK_FOLDER_SOURCE_HEIGHT / BOOKMARK_FOLDER_SOURCE_WIDTH;
  }

  private resolveDensity(): number {
    try {
      return display.getDefaultDisplaySync().densityPixels;
    } catch (_error) {
      return 1;
    }
  }

  private scalePathCommands(commands: string, scale: number): string {
    return commands.replace(/-?\d+(?:\.\d+)?/g, (value: string): string => {
      const scaled = Number(value) * scale;
      return this.formatPathNumber(scaled);
    });
  }

  private formatPathNumber(value: number): string {
    const normalized = Math.abs(value) < 0.0001 ? 0 : value;
    return normalized.toFixed(4).replace(/\.?0+$/, '');
  }

  private parseHexColor(value: string): BookmarkFolderIconRgb | undefined {
    const normalized = value.trim().replace('#', '');
    if (!/^[0-9a-fA-F]{6}$/.test(normalized)) {
      return undefined;
    }
    return {
      r: Number.parseInt(normalized.substring(0, 2), 16),
      g: Number.parseInt(normalized.substring(2, 4), 16),
      b: Number.parseInt(normalized.substring(4, 6), 16)
    };
  }

  private rgbToHsl(rgb: BookmarkFolderIconRgb): BookmarkFolderIconHsl {
    const r = rgb.r / 255;
    const g = rgb.g / 255;
    const b = rgb.b / 255;
    const max = Math.max(r, g, b);
    const min = Math.min(r, g, b);
    const l = (max + min) / 2;
    if (max === min) {
      return { h: 216, s: 0.72, l: l };
    }
    const delta = max - min;
    const s = l > 0.5 ? delta / (2 - max - min) : delta / (max + min);
    let h = 0;
    if (max === r) {
      h = (g - b) / delta + (g < b ? 6 : 0);
    } else if (max === g) {
      h = (b - r) / delta + 2;
    } else {
      h = (r - g) / delta + 4;
    }
    return {
      h: h * 60,
      s: s,
      l: l
    };
  }

  private hslToHex(hsl: BookmarkFolderIconHsl): string {
    const c = (1 - Math.abs(2 * hsl.l - 1)) * hsl.s;
    const h = this.wrapHue(hsl.h) / 60;
    const x = c * (1 - Math.abs(h % 2 - 1));
    let r1 = 0;
    let g1 = 0;
    let b1 = 0;
    if (h >= 0 && h < 1) {
      r1 = c;
      g1 = x;
    } else if (h < 2) {
      r1 = x;
      g1 = c;
    } else if (h < 3) {
      g1 = c;
      b1 = x;
    } else if (h < 4) {
      g1 = x;
      b1 = c;
    } else if (h < 5) {
      r1 = x;
      b1 = c;
    } else {
      r1 = c;
      b1 = x;
    }
    const m = hsl.l - c / 2;
    return `#${this.toHexChannel((r1 + m) * 255)}${this.toHexChannel((g1 + m) * 255)}${this.toHexChannel((b1 + m) * 255)}`;
  }

  private toHexChannel(value: number): string {
    const clamped = Math.round(this.clamp(value, 0, 255));
    return clamped.toString(16).padStart(2, '0').toUpperCase();
  }

  private wrapHue(value: number): number {
    return ((value % 360) + 360) % 360;
  }

  private clamp(value: number, min: number, max: number): number {
    return Math.max(min, Math.min(max, value));
  }
}
