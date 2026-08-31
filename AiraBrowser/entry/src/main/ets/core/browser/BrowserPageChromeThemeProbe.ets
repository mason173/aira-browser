import { webview } from '@kit.ArkWeb';
import { BrowserTabState } from '../tabs/TabManager';

export interface BrowserPageChromeThemeSnapshot {
  themeColor: string;
  pageBackgroundColor: string;
  prefersDarkScheme: boolean;
  supportsDarkAppearance: boolean;
}

export interface BrowserPageChromeThemeProbeHost {
  applyPageChromeTheme: (tabId: string, snapshot: BrowserPageChromeThemeSnapshot) => void;
}

export interface BrowserPageChromeThemeProbeDispatchHost extends BrowserPageChromeThemeProbeHost {
  resolveTab: (tabId: string) => BrowserTabState | undefined;
  resolveController: (tabId: string) => webview.WebviewController | undefined;
}

export type BrowserPageChromeThemeProbeResult = BrowserPageChromeThemeSnapshot;

export class BrowserPageChromeThemeProbe {
  runPageChromeThemeProbe(
    tabId: string,
    host: BrowserPageChromeThemeProbeDispatchHost
  ): void {
    const tab = host.resolveTab(tabId);
    const controller = host.resolveController(tabId);
    if (tab === undefined || controller === undefined || tab.isHome || tab.runtimeState === 'cold' ||
      tab.runtimeState === 'discarded' || tab.runtimeState === 'suspended') {
      return;
    }
    try {
      controller.runJavaScript(this.buildProbeScript())
        .then((rawResult: string) => {
          const result = this.parseProbeResult(rawResult);
          host.applyPageChromeTheme(tabId, {
            themeColor: result.themeColor,
            pageBackgroundColor: result.pageBackgroundColor,
            prefersDarkScheme: result.prefersDarkScheme,
            supportsDarkAppearance: result.supportsDarkAppearance
          });
        })
        .catch((_error: Error) => {});
    } catch (_error) {
    }
  }

  parseProbeResult(rawResult: string): BrowserPageChromeThemeProbeResult {
    const normalized = this.normalizeRawResult(rawResult);
    if (normalized.length === 0) {
      return this.buildEmptyResult();
    }
    try {
      const parsed = JSON.parse(normalized) as Record<string, string | boolean>;
      const themeColor = this.normalizeColorValue(parsed['themeColor']);
      const pageBackgroundColor = this.normalizeColorValue(parsed['pageBackgroundColor']);
      const prefersDarkScheme = parsed['prefersDarkScheme'] === true;
      const supportsDarkAppearance = parsed['supportsDarkAppearance'] === true;
      return {
        themeColor: themeColor,
        pageBackgroundColor: pageBackgroundColor,
        prefersDarkScheme: prefersDarkScheme,
        supportsDarkAppearance: supportsDarkAppearance
      };
    } catch (_error) {
      return this.buildEmptyResult();
    }
  }

  buildProbeScript(): string {
    return `
(() => {
  try {
    const toHex = (value, minimumAlpha) => {
      const normalized = String(value || '').trim();
      const alphaFloor = typeof minimumAlpha === 'number' ? minimumAlpha : 0.96;
      if (normalized.length === 0) {
        return '';
      }
      const probe = document.createElement('span');
      probe.style.color = '';
      probe.style.color = normalized;
      if (!probe.style.color) {
        return '';
      }
      (document.body || document.documentElement).appendChild(probe);
      const resolved = window.getComputedStyle(probe).color || '';
      probe.remove();
      const match = resolved.match(/rgba?\\(([^)]+)\\)/i);
      if (!match) {
        return '';
      }
      const parts = match[1].split(',').map((part) => part.trim());
      const red = Number.parseInt(parts[0], 10);
      const green = Number.parseInt(parts[1], 10);
      const blue = Number.parseInt(parts[2], 10);
      const alpha = parts.length > 3 ? Number.parseFloat(parts[3]) : 1;
      if ([red, green, blue].some((item) => Number.isNaN(item)) || Number.isNaN(alpha) || alpha < alphaFloor) {
        return '';
      }
      const channelToHex = (channel) => Math.max(0, Math.min(255, channel)).toString(16).padStart(2, '0');
      return '#' + channelToHex(red) + channelToHex(green) + channelToHex(blue);
    };
    const readMetaThemeColor = () => {
      const metaNodes = Array.from(document.querySelectorAll('meta[name="theme-color"]'));
      let fallback = '';
      for (let index = metaNodes.length - 1; index >= 0; index -= 1) {
        const node = metaNodes[index];
        const content = String(node.getAttribute('content') || '').trim();
        if (content.length === 0) {
          continue;
        }
        const media = String(node.getAttribute('media') || '').trim();
        if (media.length === 0) {
          if (fallback.length === 0) {
            fallback = content;
          }
          continue;
        }
        try {
          if (window.matchMedia(media).matches) {
            return content;
          }
        } catch (error) {
        }
      }
      return fallback;
    };
    const hasDarkToken = (value) => {
      return String(value || '').toLowerCase().split(/\\s+/).includes('dark');
    };
    const resolveSupportsDarkAppearance = () => {
      const meta = document.querySelector('meta[name="color-scheme"]');
      if (meta && hasDarkToken(meta.getAttribute('content') || '')) {
        return true;
      }
      const rootScheme = window.getComputedStyle(document.documentElement).colorScheme || '';
      if (hasDarkToken(rootScheme)) {
        return true;
      }
      if (document.body) {
        const bodyScheme = window.getComputedStyle(document.body).colorScheme || '';
        if (hasDarkToken(bodyScheme)) {
          return true;
        }
      }
      return false;
    };
    const resolveDeclaredPageBackgroundColor = () => {
      const nodes = [document.documentElement, document.body];
      for (const node of nodes) {
        if (!node) {
          continue;
        }
        const backgroundColor = window.getComputedStyle(node).backgroundColor || '';
        const hex = toHex(backgroundColor, 0.8);
        if (hex.length > 0) {
          return hex;
        }
      }
      return '';
    };
    const resolveNodeBackgroundColor = (node) => {
      let current = node;
      while (current && current !== document) {
        const backgroundColor = window.getComputedStyle(current).backgroundColor || '';
        const hex = toHex(backgroundColor, 0.8);
        if (hex.length > 0) {
          return hex;
        }
        current = current.parentElement;
      }
      return '';
    };
    const resolveViewportBackgroundColor = () => {
      const width = Math.max(1, window.innerWidth || document.documentElement.clientWidth || 1);
      const height = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 1);
      const sampleXFactors = [0.2, 0.5, 0.8];
      const sampleYFactors = [0.08, 0.24, 0.48];
      const counts = {};
      let bestColor = '';
      let bestCount = 0;
      for (const sampleYFactor of sampleYFactors) {
        const sampleY = Math.max(1, Math.min(height - 1, Math.floor(height * sampleYFactor)));
        for (const sampleXFactor of sampleXFactors) {
          const sampleX = Math.max(0, Math.min(width - 1, Math.floor(width * sampleXFactor)));
          const color = resolveNodeBackgroundColor(document.elementFromPoint(sampleX, sampleY));
          if (color.length <= 0) {
            continue;
          }
          counts[color] = (counts[color] || 0) + 1;
          if (counts[color] > bestCount) {
            bestCount = counts[color];
            bestColor = color;
          }
        }
      }
      return bestCount >= 2 ? bestColor : '';
    };
    const resolvePageBackgroundColor = () => {
      return resolveViewportBackgroundColor() || resolveDeclaredPageBackgroundColor();
    };
    const prefersDarkScheme = !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    const themeColor = toHex(readMetaThemeColor());
    const pageBackgroundColor = resolvePageBackgroundColor();
    const supportsDarkAppearance = resolveSupportsDarkAppearance();
    return JSON.stringify({
      themeColor,
      pageBackgroundColor,
      prefersDarkScheme,
      supportsDarkAppearance
    });
  } catch (error) {
    return '';
  }
})()
`;
  }

  private normalizeRawResult(rawResult: string): string {
    const trimmed = rawResult.trim();
    if (trimmed.length === 0 || trimmed === 'null' || trimmed === 'undefined') {
      return '';
    }
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      try {
        const parsed = JSON.parse(trimmed) as string;
        if (typeof parsed === 'string') {
          return parsed.trim();
        }
      } catch (_error) {
        return trimmed.substring(1, trimmed.length - 1).trim();
      }
    }
    return trimmed;
  }

  private normalizeColorValue(value: string | boolean | undefined): string {
    if (typeof value !== 'string') {
      return '';
    }
    const normalized = value.trim().toUpperCase();
    return /^#[0-9A-F]{6}$/.test(normalized) ? normalized : '';
  }

  private buildEmptyResult(): BrowserPageChromeThemeProbeResult {
    return {
      themeColor: '',
      pageBackgroundColor: '',
      prefersDarkScheme: false,
      supportsDarkAppearance: false
    };
  }
}
