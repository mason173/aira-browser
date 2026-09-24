// 界面上的 100% 是页面刚打开时的样子，不是引擎的绝对 page scale 100。
// 宽页面刚打开就会停在内容宽度下限，大约 72%。把这个下限当成 90% 去 zoom()，画面会反而变大。
// 唯一决策是 resolveWebZoomPlan：低于 100% 用 CSS zoom，比例是目标百分比 / 100；
// 高于或等于 100% 用 zoom()，目标是基准 page scale * 百分比 / 100。协调器只执行这个计划。
export type BrowserLargeScreenWebZoomMechanism = 'document' | 'page';

export interface BrowserLargeScreenWebZoomPlan {
  mechanism: BrowserLargeScreenWebZoomMechanism;
  pageScaleTarget: number;
  cssRatio: number;
  clearCss: boolean;
  zoomFactor: number;
}

const WEB_ZOOM_PAGE_SCALE_RESET_SLACK: number = 1.02;

export function resolveWebZoomPlan(
  baselinePercent: number,
  pageScalePercent: number,
  targetPercent: number
): BrowserLargeScreenWebZoomPlan {
  const invalidPlan: BrowserLargeScreenWebZoomPlan = {
    mechanism: 'page',
    pageScaleTarget: 0,
    cssRatio: 0,
    clearCss: false,
    zoomFactor: 0
  };
  if (!Number.isFinite(baselinePercent) || !Number.isFinite(pageScalePercent) || !Number.isFinite(targetPercent) ||
    baselinePercent <= 0 || pageScalePercent <= 0 || targetPercent <= 0) {
    return invalidPlan;
  }
  if (targetPercent + 0.5 < 100) {
    const cssRatio = targetPercent / 100;
    if (cssRatio <= 0 || cssRatio >= 1) {
      return invalidPlan;
    }
    let zoomFactor = 1;
    if (pageScalePercent > baselinePercent * WEB_ZOOM_PAGE_SCALE_RESET_SLACK) {
      zoomFactor = resolveRelativeWebZoomFactor(pageScalePercent, baselinePercent);
    }
    const documentPlan: BrowserLargeScreenWebZoomPlan = {
      mechanism: 'document',
      pageScaleTarget: baselinePercent,
      cssRatio: cssRatio,
      clearCss: false,
      zoomFactor: zoomFactor
    };
    return documentPlan;
  }
  const pageScaleTarget = baselinePercent * targetPercent / 100;
  const pagePlan: BrowserLargeScreenWebZoomPlan = {
    mechanism: 'page',
    pageScaleTarget: pageScaleTarget,
    cssRatio: 0,
    clearCss: true,
    zoomFactor: resolveRelativeWebZoomFactor(pageScalePercent, pageScaleTarget)
  };
  return pagePlan;
}

export function shouldUseDocumentZoom(targetPercent: number): boolean {
  return resolveWebZoomPlan(100, 100, targetPercent).mechanism === 'document';
}

export function resolveBaselinePageScale(storedBaseline: number, pageScale: number): number {
  if (Number.isFinite(storedBaseline) && storedBaseline > 0) {
    return storedBaseline;
  }
  if (Number.isFinite(pageScale) && pageScale > 0) {
    return pageScale;
  }
  return 0;
}

export function resolveDesiredPageScale(baselinePercent: number, targetPercent: number): number {
  if (!Number.isFinite(baselinePercent) || baselinePercent <= 0) {
    return 0;
  }
  return resolveWebZoomPlan(baselinePercent, baselinePercent, targetPercent).pageScaleTarget;
}

export function resolveOwnedDocumentZoomRatio(targetPercent: number): number {
  return resolveWebZoomPlan(100, 100, targetPercent).cssRatio;
}

export function buildPageScaleReadScript(): string {
  return '(function(){var scale=1;if(window.visualViewport&&typeof window.visualViewport.scale===\'number\'&&isFinite(window.visualViewport.scale)&&window.visualViewport.scale>0){scale=window.visualViewport.scale;}return String(scale);})()';
}

export function resolvePageScalePercentFromViewport(raw: string): number {
  const numeric = Number(unwrapJavaScriptStringResult(raw));
  if (!Number.isFinite(numeric) || numeric <= 0) {
    return 0;
  }
  if (numeric <= 10) {
    return numeric * 100;
  }
  return numeric;
}

export function resolveDocumentZoomRatio(pageScalePercent: number, targetPercent: number): number {
  if (!Number.isFinite(pageScalePercent) || !Number.isFinite(targetPercent) ||
    pageScalePercent <= 0 || targetPercent <= 0) {
    return 0;
  }
  return targetPercent / pageScalePercent;
}

export function formatDocumentZoomRatio(ratio: number): string {
  if (!Number.isFinite(ratio) || ratio <= 0) {
    return '';
  }
  return (Math.round(ratio * 1000000) / 1000000).toString();
}

export function buildDocumentZoomScript(ratio: number): string {
  const zoom = formatDocumentZoomRatio(ratio);
  if (zoom.length === 0) {
    return '';
  }
  return "(function(){var root=document.documentElement;if(!root){return 'missing';}" +
    "root.style.setProperty('zoom','" + zoom + "','important');" +
    "var applied=window.getComputedStyle(root).zoom;return applied===undefined?'':String(applied);})()";
}

function unwrapJavaScriptStringResult(raw: string): string {
  let normalized = raw.trim();
  while (normalized.length >= 2 &&
    normalized.charAt(0) === '"' &&
    normalized.charAt(normalized.length - 1) === '"') {
    normalized = normalized.substring(1, normalized.length - 1).trim();
  }
  return normalized;
}

export function isDocumentZoomApplied(raw: string, ratio: number): boolean {
  const expected = formatDocumentZoomRatio(ratio);
  // runJavaScript 回调是 JSON 字符串，实测是 "0.9" 而不是 0.9。引号留着会把成功写成失败。
  const normalized = unwrapJavaScriptStringResult(raw).toLowerCase();
  if (expected.length === 0 || normalized.length === 0 || normalized === 'missing' || normalized === 'normal') {
    return false;
  }
  if (normalized === expected) {
    return true;
  }
  const numeric = Number(normalized.endsWith('%') ? normalized.slice(0, normalized.length - 1) : normalized);
  if (!Number.isFinite(numeric)) {
    return false;
  }
  if (normalized.endsWith('%')) {
    return Math.abs(numeric - ratio * 100) < 0.6;
  }
  return Math.abs(numeric - ratio) < 0.006;
}

// 引擎没有回报新比例时，不能把请求的档位当成已经生效。否则下次相对缩放会按假比例连乘。
export function resolveCommittedWebZoomPercent(
  currentPercent: number,
  observedPercent: number
): number {
  const observed = normalizeObservedWebZoomPercent(observedPercent);
  if (observed > 0) {
    return observed;
  }
  return currentPercent > 0 ? currentPercent : 0;
}

// WebviewController.zoom(factor) 相对当前页面比例，不是绝对目标比例。
// 官方公式：factor = 100 * targetFactor / pageFactor。
// targetFactor 是目标倍数（1 = 100%），pageFactor 是 onScaleChange 的百分比。
// 等价于 factor = targetPercent / currentPercent。取值范围 (0, 100]。
export function resolveRelativeWebZoomFactor(currentPercent: number, targetPercent: number): number {
  if (!Number.isFinite(currentPercent) || !Number.isFinite(targetPercent) ||
    currentPercent <= 0 || targetPercent <= 0) {
    return 0;
  }
  const factor = targetPercent / currentPercent;
  if (!Number.isFinite(factor) || factor <= 0 || factor > 100) {
    return 0;
  }
  return factor;
}

// OnScaleChangeEvent.newScale 是显示比例百分比，可能带小数。界面按四舍五入的整数显示。
export function normalizeObservedWebZoomPercent(scalePercent: number): number {
  if (!Number.isFinite(scalePercent) || scalePercent <= 0) {
    return 0;
  }
  return Math.round(scalePercent);
}
