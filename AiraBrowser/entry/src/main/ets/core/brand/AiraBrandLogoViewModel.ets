export interface AiraBrandLogoGradientState {
  colors: Array<[ResourceColor, number]>;
  maskCommands: string;
}

interface AiraBrandLogoRgb {
  r: number;
  g: number;
  b: number;
}

interface AiraBrandLogoHsl {
  h: number;
  s: number;
  l: number;
}

const AIRA_LOGO_SOURCE_SIZE: number = 1024;
const AIRA_LOGO_PATH_COMMANDS: string =
  'M511.999 0C581.749 0 648.241 13.9481 708.839 39.2058C687.9 115.571 645.299 210.187 507.819 226.53C352.069 228.766 226.5 355.718 226.5 511.999C226.5 669.676 354.322 797.499 511.999 797.499C669.677 797.499 797.5 669.677 797.5 511.999C797.5 485.732 793.951 460.294 787.308 436.136C783.709 423.05 777.387 410.723 768.507 400.458C663.676 279.27 504.671 386.718 511.981 462.795C498.4 361.817 593.013 281.296 625.842 250.117C625.886 250.129 625.929 250.14 625.972 250.151C659.581 213.081 728.052 132.619 709.293 39.3966C894.121 116.645 1024 299.154 1024 511.999C1024 794.769 794.769 1024 511.999 1024C229.23 1024 0 794.769 0 511.999C0 229.23 229.23 0.000175463 511.999 0Z';

export class AiraBrandLogoViewModel {
  buildGradientState(accentColor: string, sizeVp: number): AiraBrandLogoGradientState {
    const accentRgb = this.parseHexColor(accentColor) ?? this.parseHexColor('#0A59F7') as AiraBrandLogoRgb;
    const accentHsl = this.rgbToHsl(accentRgb);
    const base = this.hslToHex({
      h: accentHsl.h,
      s: Math.max(0.66, accentHsl.s * 0.98),
      l: this.clamp(accentHsl.l - 0.04, 0.38, 0.52)
    });
    const softSheen = this.hslToHex({
      h: this.wrapHue(accentHsl.h + 10),
      s: Math.max(0.58, accentHsl.s * 0.9),
      l: this.clamp(accentHsl.l + 0.1, 0.56, 0.68)
    });
    const peakSheen = this.hslToHex({
      h: this.wrapHue(accentHsl.h + 16),
      s: Math.max(0.6, accentHsl.s * 0.88),
      l: this.clamp(accentHsl.l + 0.16, 0.64, 0.76)
    });

    return {
      colors: [
        [base, 0.0],
        [softSheen, 0.34],
        [peakSheen, 0.5],
        [softSheen, 0.66],
        [base, 1.0]
      ],
      maskCommands: this.buildMaskCommands(sizeVp)
    };
  }

  private buildMaskCommands(sizeVp: number): string {
    const scale = Math.max(1, sizeVp) / AIRA_LOGO_SOURCE_SIZE;
    return this.scalePathCommands(AIRA_LOGO_PATH_COMMANDS, scale);
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

  private parseHexColor(value: string): AiraBrandLogoRgb | undefined {
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

  private rgbToHsl(rgb: AiraBrandLogoRgb): AiraBrandLogoHsl {
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

  private hslToHex(hsl: AiraBrandLogoHsl): string {
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
