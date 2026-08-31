export const BROWSER_BOTTOM_PANEL_GLASS_TINT_ALPHA_HEX: string = 'CC';
export const BROWSER_BOTTOM_PANEL_GLASS_BACKDROP_BLUR_RADIUS: number = 100;

export function withBrowserBottomPanelGlassTint(color: ResourceColor): ResourceColor {
  return withBrowserBottomPanelTintAlpha(color, BROWSER_BOTTOM_PANEL_GLASS_TINT_ALPHA_HEX);
}

function withBrowserBottomPanelTintAlpha(color: ResourceColor, alphaHex: string): ResourceColor {
  const normalizedColor = `${color}`.trim();
  if (!normalizedColor.startsWith('#')) {
    return color;
  }
  const hexColor = normalizedColor.substring(1);
  if (hexColor.length === 6 && isHexColor(hexColor)) {
    return `#${alphaHex}${hexColor}`;
  }
  if (hexColor.length === 8 && isHexColor(hexColor)) {
    return `#${alphaHex}${hexColor.substring(2)}`;
  }
  return color;
}

function isHexColor(value: string): boolean {
  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);
    const isDigit = code >= 48 && code <= 57;
    const isUpperHex = code >= 65 && code <= 70;
    const isLowerHex = code >= 97 && code <= 102;
    if (!isDigit && !isUpperHex && !isLowerHex) {
      return false;
    }
  }
  return true;
}
