import { display, UIContext, window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  BrowserTabPreviewImageService,
  BrowserTabSharedSnapshotNormalizeOptions
} from './BrowserTabPreviewImageService';
import {
  DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID,
  BrowserTabPreviewCacheStore
} from './BrowserTabPreviewCacheStore';
import {
  BrowserTabPreviewCaptureScope,
  BrowserTabPreviewCaptureSource,
  BrowserTabPreviewTransitionSource
} from './BrowserTabPreviewTypes';
import {
  BROWSER_TAB_PREVIEW_PIXEL_HEIGHT,
  BROWSER_TAB_PREVIEW_PIXEL_WIDTH
} from '../../core/browser/BrowserTabPreviewMetrics';
import { sharedBrowserTabPreviewMetrics } from '../../core/browser/BrowserTabPreviewMetricsService';

const PREVIEW_CAPTURE_TIMEOUT_MS: number = 1800;
const VISIBLE_COMPONENT_SNAPSHOT_SETTLE_MS: number = 16;
const VISIBLE_COMPONENT_SNAPSHOT_SCALE: number = 0.7;
const BLANK_SNAPSHOT_SAMPLE_WIDTH: number = 36;
const BLANK_SNAPSHOT_SAMPLE_HEIGHT: number = 48;
const BLANK_SNAPSHOT_MIN_LUMINANCE_RANGE: number = 0.035;
const BLANK_SNAPSHOT_MIN_COLOR_RANGE: number = 0.035;
const BLANK_SNAPSHOT_BLACK_LUMINANCE: number = 0.05;
const BLANK_SNAPSHOT_WHITE_LUMINANCE: number = 0.97;
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'TabPreviewCapture';

export { BrowserTabPreviewCaptureSource } from './BrowserTabPreviewTypes';

export function buildBrowserTabPreviewComponentSnapshotId(tabId: string): string {
  return buildBrowserTabPageSnapshotContainerId(tabId);
}

export function buildBrowserTabPageSnapshotContainerId(tabId: string): string {
  return `browser-tab-page-${sanitizeBrowserTabSnapshotId(tabId)}`;
}

export function buildBrowserTabWebComponentSnapshotId(tabId: string): string {
  return `browser-tab-web-${sanitizeBrowserTabSnapshotId(tabId)}`;
}

export function buildBrowserTabPreviewVisibleSnapshotId(tabId: string): string {
  return `browser-tab-visible-preview-${sanitizeBrowserTabSnapshotId(tabId)}`;
}

export function buildBrowserTabPreviewVisibleSurfaceSnapshotId(tabId: string): string {
  return `browser-tab-visible-surface-preview-${sanitizeBrowserTabSnapshotId(tabId)}`;
}

function sanitizeBrowserTabSnapshotId(tabId: string): string {
  return tabId.trim().replace(/[^a-zA-Z0-9._-]/g, '_');
}

export interface BrowserTabPreviewCaptureOptions {
  uiContext?: UIContext;
  componentSnapshotId?: string;
  webComponentSnapshotId?: string;
  componentSnapshotOnly?: boolean;
  // The snapshot id points at the full visible shell surface (page + top
  // chrome). That tree hosts the ArkWeb same-layer surface, which the
  // component snapshot can only capture with waitUntilRenderFinished=false —
  // the synchronous-wait path fails with error 100001 (verified on the
  // large-screen shell; the overview entry pipeline uses false for the same
  // node and succeeds).
  captureVisibleTabSurface?: boolean;
  allowWindowSnapshot?: boolean;
  allowSurfaceSnapshot?: boolean;
  preferVisibleSnapshot?: boolean;
  rejectLowDetailSnapshot?: boolean;
  requireSharedSnapshot?: boolean;
  persistSharedSnapshot?: boolean;
  cacheScopeId?: string;
  visibleSnapshotTopCropPx?: number;
  sharedSnapshotNormalizeOptions?: BrowserTabSharedSnapshotNormalizeOptions;
  // Host-provided viewport (vp) for webPageSnapshot. webPageSnapshot re-lays the
  // page out at the given size, so this must be the REAL web viewport: without
  // it the size is probed via window.innerWidth, which reads 390×838 while the
  // tab is detached/unsettled (e.g. right after "+" returns home on large
  // screen) and the engine then renders a phone-layout thumbnail.
  preferredWebViewportSnapshotSize?: BrowserTabPreviewWebViewportSize;
}

export interface BrowserTabPreviewCaptureResult {
  snapshot?: image.PixelMap;
  sharedSnapshotImageUri?: string;
  sharedSnapshotWidth?: number;
  sharedSnapshotHeight?: number;
  sharedSnapshotImageBytes?: number;
  source: BrowserTabPreviewCaptureSource;
  transitionSource?: BrowserTabPreviewTransitionSource;
  failureReason: string;
  stageLine?: string;
}

interface BrowserTabPreviewPersistedImageResult {
  uri?: string;
  bytes: number;
  packDurationMs?: number;
  writeDurationMs?: number;
  totalDurationMs?: number;
}

interface BrowserTabPreviewTimedSnapshotResult {
  pixelMap?: image.PixelMap;
  durationMs: number;
}

export interface BrowserTabPreviewWebViewportSize {
  width: number;
  height: number;
}

export class BrowserTabPreviewCaptureService {
  private imageService: BrowserTabPreviewImageService = new BrowserTabPreviewImageService();
  private cacheScopeId: string = DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID;

  setCacheScopeId(scopeId: string): void {
    const normalizedScopeId = scopeId.trim();
    this.cacheScopeId = normalizedScopeId.length > 0 ? normalizedScopeId : DEFAULT_BROWSER_TAB_PREVIEW_SCOPE_ID;
  }

  async captureWebPage(
    controller: webview.WebviewController,
    tabId: string,
    options: BrowserTabPreviewCaptureOptions = {}
  ): Promise<BrowserTabPreviewCaptureResult> {
    const startedAt = Date.now();
    const failures: string[] = [];

    if (options.componentSnapshotOnly === true) {
      const componentOnlyOptions: BrowserTabPreviewCaptureOptions = {
        uiContext: options.uiContext,
        componentSnapshotId: options.componentSnapshotId,
        webComponentSnapshotId: options.webComponentSnapshotId,
        componentSnapshotOnly: true,
        captureVisibleTabSurface: options.captureVisibleTabSurface,
        allowWindowSnapshot: false,
        allowSurfaceSnapshot: false,
        preferVisibleSnapshot: true,
        rejectLowDetailSnapshot: options.rejectLowDetailSnapshot,
        requireSharedSnapshot: options.requireSharedSnapshot,
        persistSharedSnapshot: false,
        cacheScopeId: options.cacheScopeId,
        visibleSnapshotTopCropPx: options.visibleSnapshotTopCropPx,
        sharedSnapshotNormalizeOptions: options.sharedSnapshotNormalizeOptions
      };
      const componentResult = await this.captureCandidate('component', 'full-surface',
        () => this.captureComponentSnapshot(componentOnlyOptions, tabId), tabId, componentOnlyOptions);
      if (componentResult.snapshot !== undefined) {
        this.recordCaptureMetric(tabId, componentResult, startedAt);
        return componentResult;
      }
      this.recordCaptureMetric(tabId, componentResult, startedAt);
      return componentResult;
    }

    if (options.preferVisibleSnapshot === true) {
      const visibleResult = await this.captureVisibleSnapshot(controller, tabId, options);
      if (visibleResult.snapshot !== undefined) {
        this.recordCaptureMetric(tabId, visibleResult, startedAt);
        return visibleResult;
      }
      failures.push(visibleResult.failureReason);
    }

    const webResult = await this.captureCandidate('web', 'web-content',
      () => this.captureWebPageSnapshot(controller, tabId, options), tabId, options);
    if (webResult.snapshot !== undefined) {
      if (await this.acceptCaptureCandidate(webResult, options, tabId)) {
        this.recordCaptureMetric(tabId, webResult, startedAt);
        return webResult;
      }
      failures.push(`${webResult.source}-missing-shared`);
    } else {
      failures.push(webResult.failureReason);
    }

    if (options.allowWindowSnapshot === true) {
      const windowResult = await this.captureCandidate('window', 'full-surface',
        () => this.captureWindowSnapshot(options, tabId), tabId, options);
      if (windowResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(windowResult, options, tabId)) {
          this.recordCaptureMetric(tabId, windowResult, startedAt);
          return windowResult;
        }
        failures.push(`${windowResult.source}-missing-shared`);
      } else {
        failures.push(windowResult.failureReason);
      }
    }

    const componentResult = await this.captureCandidate('component', 'full-surface',
      () => this.captureComponentSnapshot(options, tabId), tabId, options);
    if (componentResult.snapshot !== undefined) {
      if (await this.acceptCaptureCandidate(componentResult, options, tabId)) {
        this.recordCaptureMetric(tabId, componentResult, startedAt);
        return componentResult;
      }
      failures.push(`${componentResult.source}-missing-shared`);
    } else {
      failures.push(componentResult.failureReason);
    }

    if (options.allowSurfaceSnapshot !== false) {
      const surfaceRegionResult = await this.captureCandidate('surface-region', 'full-surface',
        () => this.captureSurfaceRegionSnapshot(controller, tabId, options), tabId, options);
      if (surfaceRegionResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(surfaceRegionResult, options, tabId)) {
          this.recordCaptureMetric(tabId, surfaceRegionResult, startedAt);
          return surfaceRegionResult;
        }
        failures.push(`${surfaceRegionResult.source}-missing-shared`);
      } else {
        failures.push(surfaceRegionResult.failureReason);
      }

      const surfaceResult = await this.captureCandidate('surface', 'full-surface',
        () => this.captureSurfaceSnapshot(controller, tabId), tabId, options);
      if (surfaceResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(surfaceResult, options, tabId)) {
          this.recordCaptureMetric(tabId, surfaceResult, startedAt);
          return surfaceResult;
        }
        failures.push(`${surfaceResult.source}-missing-shared`);
      } else {
        failures.push(surfaceResult.failureReason);
      }

      const transformedSurfaceResult = await this.captureCandidate('surface-transform', 'full-surface',
        () => this.captureTransformedSurfaceSnapshot(controller, tabId), tabId, options);
      if (transformedSurfaceResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(transformedSurfaceResult, options, tabId)) {
          this.recordCaptureMetric(tabId, transformedSurfaceResult, startedAt);
          return transformedSurfaceResult;
        }
        failures.push(`${transformedSurfaceResult.source}-missing-shared`);
      } else {
        failures.push(transformedSurfaceResult.failureReason);
      }
    }

    const failedResult: BrowserTabPreviewCaptureResult = {
      source: 'none',
      failureReason: this.compactFailureReasons(failures)
    };
    this.recordCaptureMetric(tabId, failedResult, startedAt);
    return failedResult;
  }

  private async captureVisibleSnapshot(
    controller: webview.WebviewController,
    tabId: string,
    options: BrowserTabPreviewCaptureOptions
  ): Promise<BrowserTabPreviewCaptureResult> {
    const failures: string[] = [];
    const componentResult = await this.captureCandidate('component', 'full-surface',
      () => this.captureComponentSnapshot(options, tabId), tabId, options);
    if (componentResult.snapshot !== undefined) {
      if (await this.acceptCaptureCandidate(componentResult, options, tabId)) {
        return componentResult;
      }
      failures.push(`${componentResult.source}-missing-shared`);
    } else {
      failures.push(componentResult.failureReason);
    }

    if (options.allowSurfaceSnapshot !== false) {
      const surfaceRegionResult = await this.captureCandidate('surface-region', 'full-surface',
        () => this.captureSurfaceRegionSnapshot(controller, tabId, options), tabId, options);
      if (surfaceRegionResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(surfaceRegionResult, options, tabId)) {
          return surfaceRegionResult;
        }
        failures.push(`${surfaceRegionResult.source}-missing-shared`);
      } else {
        failures.push(surfaceRegionResult.failureReason);
      }

      const surfaceResult = await this.captureCandidate('surface', 'full-surface',
        () => this.captureSurfaceSnapshot(controller, tabId), tabId, options);
      if (surfaceResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(surfaceResult, options, tabId)) {
          return surfaceResult;
        }
        failures.push(`${surfaceResult.source}-missing-shared`);
      } else {
        failures.push(surfaceResult.failureReason);
      }

      const transformedSurfaceResult = await this.captureCandidate('surface-transform', 'full-surface',
        () => this.captureTransformedSurfaceSnapshot(controller, tabId), tabId, options);
      if (transformedSurfaceResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(transformedSurfaceResult, options, tabId)) {
          return transformedSurfaceResult;
        }
        failures.push(`${transformedSurfaceResult.source}-missing-shared`);
      } else {
        failures.push(transformedSurfaceResult.failureReason);
      }
    }

    if (options.allowWindowSnapshot === true) {
      const windowResult = await this.captureCandidate('window', 'full-surface',
        () => this.captureWindowSnapshot(options, tabId), tabId, options);
      if (windowResult.snapshot !== undefined) {
        if (await this.acceptCaptureCandidate(windowResult, options, tabId)) {
          return windowResult;
        }
        failures.push(`${windowResult.source}-missing-shared`);
      } else {
        failures.push(windowResult.failureReason);
      }
    }

    return {
      source: 'none',
      failureReason: this.compactFailureReasons(failures)
    };
  }

  private async acceptCaptureCandidate(
    result: BrowserTabPreviewCaptureResult,
    options: BrowserTabPreviewCaptureOptions,
    tabId: string
  ): Promise<boolean> {
    if (options.persistSharedSnapshot === false && result.snapshot !== undefined) {
      return true;
    }
    if ((result.sharedSnapshotImageUri?.trim().length ?? 0) > 0) {
      return true;
    }
    if (result.snapshot !== undefined) {
      await this.releaseUnusedCandidateSnapshot(result.snapshot, tabId, result.source, 'missing-shared');
    }
    return false;
  }

  private async captureWindowSnapshot(
    options: BrowserTabPreviewCaptureOptions,
    tabId: string
  ): Promise<image.PixelMap | undefined> {
    const hostContext = options.uiContext?.getHostContext();
    if (hostContext === undefined) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'window snapshot skipped tab=%{public}s reason=no-host-context', tabId);
      return undefined;
    }
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'window snapshot start tab=%{public}s', tabId);
      const currentWindow = await window.getLastWindow(hostContext);
      const snapshot = await currentWindow.snapshot();
      hilog.info(LOG_DOMAIN, LOG_TAG, 'window snapshot success tab=%{public}s', tabId);
      return snapshot;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'window snapshot failed tab=%{public}s error=%{public}s',
        tabId, JSON.stringify(error));
      return undefined;
    }
  }

  private async captureCandidate(
    source: BrowserTabPreviewCaptureSource,
    captureScope: BrowserTabPreviewCaptureScope,
    capture: () => Promise<image.PixelMap | undefined>,
    tabId: string,
    options: BrowserTabPreviewCaptureOptions
  ): Promise<BrowserTabPreviewCaptureResult> {
    const captureStartedAt = Date.now();
    const rawResult = await this.captureTimedSnapshot(capture);
    if (rawResult.pixelMap === undefined) {
      return {
        source: 'none',
        failureReason: `${source}-empty`,
        stageLine: this.buildStageLine(source, rawResult.durationMs, 0, {
          bytes: 0
        })
      };
    }
    const rawPixelMap = rawResult.pixelMap;
    const visiblePixelMap = await this.prepareRawSnapshotForSource(rawPixelMap, source, options, tabId);
    if (await this.isBlankSnapshot(visiblePixelMap, tabId, source, options)) {
      await this.releaseUnusedCandidateSnapshot(visiblePixelMap, tabId, source, 'blank-snapshot');
      return {
        source: 'none',
        failureReason: `${source}-blank`,
        stageLine: this.buildStageLine(source, rawResult.durationMs, 0, {
          bytes: 0
        }, Date.now() - captureStartedAt)
      };
    }
    const normalizeStartedAt = Date.now();
    const transitionSource = this.buildTransitionSource(source, captureScope);
    const sharedSnapshotPixelMap = await this.imageService.normalizeForSharedSnapshot(visiblePixelMap, tabId, source,
      options.sharedSnapshotNormalizeOptions);
    const normalizeDurationMs = Date.now() - normalizeStartedAt;
    const sharedInfo = this.resolvePixelMapSize(sharedSnapshotPixelMap);
    let sharedSnapshotImage: BrowserTabPreviewPersistedImageResult = {
      bytes: 0
    };
    if (options.persistSharedSnapshot !== false) {
      sharedSnapshotImage = await this.savePreviewImageWithBytes(sharedSnapshotPixelMap, `${tabId}-shared`,
        transitionSource,
        options.cacheScopeId);
      if ((sharedSnapshotImage.uri?.trim().length ?? 0) <= 0) {
        if (sharedSnapshotPixelMap !== undefined && sharedSnapshotPixelMap !== visiblePixelMap) {
          await this.releaseGeneratedSharedSnapshot(sharedSnapshotPixelMap, tabId, source);
        }
        await this.releaseUnusedCandidateSnapshot(visiblePixelMap, tabId, source, 'shared-persist-failed');
        return {
          source: 'none',
          failureReason: `${source}-shared-persist-failed`,
          stageLine: this.buildStageLine(source, rawResult.durationMs, normalizeDurationMs, sharedSnapshotImage,
            Date.now() - captureStartedAt)
        };
      }
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'candidate accepted tab=%{public}s source=%{public}s width=%{public}d height=%{public}d',
      tabId, source, sharedInfo.width, sharedInfo.height);
    if (sharedSnapshotPixelMap !== visiblePixelMap) {
      await this.releaseGeneratedSharedSnapshot(sharedSnapshotPixelMap, tabId, source);
    }
    return {
      snapshot: visiblePixelMap,
      sharedSnapshotImageUri: sharedSnapshotImage.uri,
      sharedSnapshotWidth: sharedInfo.width,
      sharedSnapshotHeight: sharedInfo.height,
      sharedSnapshotImageBytes: sharedSnapshotImage.bytes,
      source: source,
      transitionSource: transitionSource,
      failureReason: '',
      stageLine: this.buildStageLine(source, rawResult.durationMs, normalizeDurationMs, sharedSnapshotImage,
        Date.now() - captureStartedAt)
    };
  }

  private async captureTimedSnapshot(capture: () => Promise<image.PixelMap | undefined>): Promise<BrowserTabPreviewTimedSnapshotResult> {
    const startedAt = Date.now();
    const pixelMap = await capture();
    return {
      pixelMap: pixelMap,
      durationMs: Date.now() - startedAt
    };
  }

  private async prepareRawSnapshotForSource(
    rawPixelMap: image.PixelMap,
    _source: BrowserTabPreviewCaptureSource,
    _options: BrowserTabPreviewCaptureOptions,
    _tabId: string
  ): Promise<image.PixelMap> {
    return rawPixelMap;
  }

  private async savePreviewImageWithBytes(
    pixelMap: image.PixelMap,
    tabId: string,
    transitionSource: BrowserTabPreviewTransitionSource,
    cacheScopeId?: string
  ): Promise<BrowserTabPreviewPersistedImageResult> {
    const normalizedScopeId = cacheScopeId?.trim() ?? '';
    const saveScopeId = normalizedScopeId.length > 0 ? normalizedScopeId : this.cacheScopeId;
    const cacheStore = new BrowserTabPreviewCacheStore();
    cacheStore.setScopeId(saveScopeId);
    const result = await cacheStore.savePreviewImageWithStats(pixelMap, tabId, transitionSource);
    return {
      uri: result.uri,
      bytes: result.bytes,
      packDurationMs: result.packDurationMs,
      writeDurationMs: result.writeDurationMs,
      totalDurationMs: result.totalDurationMs
    };
  }

  private buildTransitionSource(
    source: BrowserTabPreviewCaptureSource,
    captureScope: BrowserTabPreviewCaptureScope
  ): BrowserTabPreviewTransitionSource {
    return {
      captureSource: source,
      captureScope: captureScope,
      transitionFrame: 'current-web'
    };
  }

  private recordCaptureMetric(
    tabId: string,
    result: BrowserTabPreviewCaptureResult,
    startedAt: number
  ): void {
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[THUMB-DIAG] capture-final tab=%{public}s source=%{public}s ok=%{public}s shared=%{public}s fail=%{public}s',
      tabId,
      result.source,
      `${result.snapshot !== undefined}`,
      `${(result.sharedSnapshotImageUri?.trim().length ?? 0) > 0}:${result.sharedSnapshotWidth ?? 0}x${result.sharedSnapshotHeight ?? 0}`,
      result.failureReason);
    sharedBrowserTabPreviewMetrics.recordCapture({
      tabId: tabId,
      source: result.source,
      success: result.snapshot !== undefined,
      failureReason: result.failureReason,
      durationMs: Date.now() - startedAt,
      sharedPersisted: (result.sharedSnapshotImageUri?.trim().length ?? 0) > 0,
      sharedBytes: result.sharedSnapshotImageBytes ?? 0,
      stageLine: result.stageLine
    });
  }

  private buildStageLine(
    source: BrowserTabPreviewCaptureSource,
    captureMs: number,
    normalizeMs: number,
    persist: BrowserTabPreviewPersistedImageResult,
    totalMs?: number
  ): string {
    const parts: string[] = [
      `${source}Ms=${this.normalizeDuration(captureMs)}`,
      `normalizeMs=${this.normalizeDuration(normalizeMs)}`
    ];
    if (persist.totalDurationMs !== undefined) {
      parts.push(`persistMs=${this.normalizeDuration(persist.totalDurationMs)}`);
    }
    if (persist.packDurationMs !== undefined) {
      parts.push(`packMs=${this.normalizeDuration(persist.packDurationMs)}`);
    }
    if (persist.writeDurationMs !== undefined) {
      parts.push(`writeMs=${this.normalizeDuration(persist.writeDurationMs)}`);
    }
    parts.push(`bytes=${this.normalizeDuration(persist.bytes)}`);
    if (totalMs !== undefined) {
      parts.push(`candidateMs=${this.normalizeDuration(totalMs)}`);
    }
    return parts.join(',');
  }

  private normalizeDuration(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.round(value));
  }

  private resolvePixelMapSize(pixelMap: image.PixelMap): BrowserTabPreviewWebViewportSize {
    try {
      const imageInfo = pixelMap.getImageInfoSync();
      return {
        width: Math.max(1, Math.floor(imageInfo.size.width)),
        height: Math.max(1, Math.floor(imageInfo.size.height))
      };
    } catch (_error) {
      return {
        width: BROWSER_TAB_PREVIEW_PIXEL_WIDTH,
        height: BROWSER_TAB_PREVIEW_PIXEL_HEIGHT
      };
    }
  }

  private async captureSurfaceSnapshot(
    controller: webview.WebviewController,
    tabId: string
  ): Promise<image.PixelMap | undefined> {
    const surfaceId = this.resolveSurfaceId(controller, tabId, 'surface');
    if (surfaceId.length <= 0) {
      return undefined;
    }
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'surface snapshot start tab=%{public}s surface=%{public}s', tabId, surfaceId);
      const pixelMap = await image.createPixelMapFromSurface(surfaceId);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'surface snapshot success tab=%{public}s surface=%{public}s', tabId, surfaceId);
      return pixelMap;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'surface snapshot failed tab=%{public}s surface=%{public}s error=%{public}s',
        tabId, surfaceId, JSON.stringify(error));
      return undefined;
    }
  }

  private async captureSurfaceRegionSnapshot(
    controller: webview.WebviewController,
    tabId: string,
    options: BrowserTabPreviewCaptureOptions
  ): Promise<image.PixelMap | undefined> {
    const surfaceId = this.resolveSurfaceId(controller, tabId, 'surface-region');
    if (surfaceId.length <= 0) {
      return undefined;
    }
    // First candidate: the REAL web viewport (host-provided, vp → surface px).
    // The legacy hardcoded portrait regions below are phone-sized; on a large
    // screen they crop a phone-shaped strip out of the landscape surface, which
    // is exactly the "mobile-looking thumbnail" bug. Keep them only as final
    // fallbacks for hosts that did not provide a viewport.
    const regions: image.Region[] = [];
    const preferredViewport = options.preferredWebViewportSnapshotSize;
    if (preferredViewport !== undefined && preferredViewport.width > 1 && preferredViewport.height > 1) {
      const density = this.resolveDisplayDensity();
      const preferredWidthPx = Math.max(1, Math.floor(preferredViewport.width * density));
      const preferredHeightPx = Math.max(1, Math.floor(preferredViewport.height * density));
      regions.push({
        x: 0,
        y: 0,
        size: { width: preferredWidthPx, height: preferredHeightPx }
      });
      // Rounding slack: if the exact region overshoots the surface by a pixel
      // or two the capture throws, and falling straight through to the legacy
      // phone regions would reintroduce the portrait crop.
      regions.push({
        x: 0,
        y: 0,
        size: { width: Math.max(1, preferredWidthPx - 4), height: Math.max(1, preferredHeightPx - 4) }
      });
    }
    regions.push(
      { x: 0, y: 0, size: { width: 1320, height: 2086 } },
      { x: 0, y: 0, size: { width: 1320, height: 2592 } },
      { x: 0, y: 0, size: { width: BROWSER_TAB_PREVIEW_PIXEL_WIDTH, height: BROWSER_TAB_PREVIEW_PIXEL_HEIGHT } }
    );
    for (let index = 0; index < regions.length; index += 1) {
      const region = regions[index];
      try {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'surface region snapshot start tab=%{public}s surface=%{public}s index=%{public}d width=%{public}d height=%{public}d',
          tabId, surfaceId, index, region.size.width, region.size.height);
        const pixelMap = await image.createPixelMapFromSurface(surfaceId, region);
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'surface region snapshot success tab=%{public}s surface=%{public}s index=%{public}d',
          tabId, surfaceId, index);
        return pixelMap;
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'surface region snapshot failed tab=%{public}s surface=%{public}s index=%{public}d error=%{public}s',
          tabId, surfaceId, index, JSON.stringify(error));
      }
    }
    return undefined;
  }

  private async captureTransformedSurfaceSnapshot(
    controller: webview.WebviewController,
    tabId: string
  ): Promise<image.PixelMap | undefined> {
    const surfaceId = this.resolveSurfaceId(controller, tabId, 'surface-transform');
    if (surfaceId.length <= 0) {
      return undefined;
    }
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'transformed surface snapshot start tab=%{public}s surface=%{public}s',
        tabId, surfaceId);
      const pixelMap = await image.createPixelMapFromSurfaceWithTransformation(surfaceId, true);
      hilog.info(LOG_DOMAIN, LOG_TAG, 'transformed surface snapshot success tab=%{public}s surface=%{public}s',
        tabId, surfaceId);
      return pixelMap;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'transformed surface snapshot failed tab=%{public}s surface=%{public}s error=%{public}s',
        tabId, surfaceId, JSON.stringify(error));
      return undefined;
    }
  }

  private async captureWebPageSnapshot(
    controller: webview.WebviewController,
    tabId: string,
    options: BrowserTabPreviewCaptureOptions
  ): Promise<image.PixelMap | undefined> {
    const viewportSize = await this.resolveWebViewportSnapshotSize(
      controller,
      tabId,
      options.preferredWebViewportSnapshotSize
    );
    const webSnapshotId = options.webComponentSnapshotId ?? options.componentSnapshotId ?? '';
    return await new Promise((resolve: (value: image.PixelMap | undefined) => void) => {
      let settled = false;
      const timeoutId = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'web snapshot timeout tab=%{public}s', tabId);
        resolve(undefined);
      }, PREVIEW_CAPTURE_TIMEOUT_MS);

      try {
        hilog.info(LOG_DOMAIN, LOG_TAG,
          'web snapshot start tab=%{public}s id=%{public}s width=%{public}d height=%{public}d',
          tabId, webSnapshotId, viewportSize.width, viewportSize.height);
        controller.webPageSnapshot({
          id: webSnapshotId,
          size: {
            width: `${viewportSize.width}vp`,
            height: `${viewportSize.height}vp`
          }
        }, (error, result) => {
          if (settled) {
            return;
          }
          settled = true;
          clearTimeout(timeoutId);
          if (error !== undefined) {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'web snapshot callback error tab=%{public}s code=%{public}d',
              tabId, error.code ?? -1);
          }
          if (result?.status !== true || result.imagePixelMap === undefined) {
            hilog.warn(LOG_DOMAIN, LOG_TAG,
              'web snapshot empty tab=%{public}s status=%{public}s width=%{public}s height=%{public}s',
              tabId,
              `${result?.status ?? false}`,
              `${result?.size?.width ?? 0}`,
              `${result?.size?.height ?? 0}`);
            resolve(undefined);
            return;
          }
          hilog.info(LOG_DOMAIN, LOG_TAG,
            'web snapshot success tab=%{public}s width=%{public}s height=%{public}s',
            tabId,
            `${result.size?.width ?? 0}`,
            `${result.size?.height ?? 0}`);
          resolve(result.imagePixelMap);
        });
      } catch (error) {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timeoutId);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'web snapshot throw tab=%{public}s error=%{public}s',
          tabId, JSON.stringify(error));
        resolve(undefined);
      }
    });
  }

  private async captureComponentSnapshot(
    options: BrowserTabPreviewCaptureOptions,
    tabId: string
  ): Promise<image.PixelMap | undefined> {
    const snapshotId = options.componentSnapshotId ?? '';
    if (options.uiContext === undefined || snapshotId.trim().length === 0) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'component snapshot skipped tab=%{public}s id=%{public}s',
        tabId, snapshotId);
      return undefined;
    }
    try {
      hilog.info(LOG_DOMAIN, LOG_TAG, 'component snapshot start tab=%{public}s id=%{public}s', tabId, snapshotId);
      await this.waitForVisibleSnapshotSettle();
      const pixelMap = await options.uiContext.getComponentSnapshot().get(snapshotId, {
        scale: VISIBLE_COMPONENT_SNAPSHOT_SCALE,
        waitUntilRenderFinished: options.captureVisibleTabSurface !== true
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, 'component snapshot success tab=%{public}s id=%{public}s', tabId, snapshotId);
      return pixelMap;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'component snapshot failed tab=%{public}s id=%{public}s error=%{public}s',
        tabId, snapshotId, JSON.stringify(error));
      return undefined;
    }
  }

  private async waitForVisibleSnapshotSettle(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, VISIBLE_COMPONENT_SNAPSHOT_SETTLE_MS);
    });
  }

  private async resolveWebViewportSnapshotSize(
    controller: webview.WebviewController,
    tabId: string,
    preferredSize?: BrowserTabPreviewWebViewportSize
  ): Promise<BrowserTabPreviewWebViewportSize> {
    // The host knows the real web viewport; trust it over probing the page.
    // Probing reads phone defaults (390-wide) while the tab is detached, which
    // makes webPageSnapshot render a mobile-layout thumbnail on large screens.
    if (preferredSize !== undefined && preferredSize.width > 1 && preferredSize.height > 1) {
      hilog.info(LOG_DOMAIN, LOG_TAG, '[THUMB-DIAG] viewport-size tab=%{public}s used=preferred %{public}s',
        tabId, `${Math.round(preferredSize.width)}x${Math.round(preferredSize.height)}`);
      return {
        width: Math.min(16000, Math.max(1, Math.round(preferredSize.width))),
        height: Math.min(16000, Math.max(1, Math.round(preferredSize.height)))
      };
    }
    const fallbackSize: BrowserTabPreviewWebViewportSize = {
      width: BROWSER_TAB_PREVIEW_PIXEL_WIDTH,
      height: Math.max(BROWSER_TAB_PREVIEW_PIXEL_HEIGHT, Math.round(BROWSER_TAB_PREVIEW_PIXEL_WIDTH * 2.15))
    };
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '[THUMB-DIAG] viewport-size tab=%{public}s preferred=%{public}s probing-js fallback=%{public}s',
      tabId,
      preferredSize === undefined ? 'none' : `${preferredSize.width}x${preferredSize.height}`,
      `${fallbackSize.width}x${fallbackSize.height}`);
    const script = `JSON.stringify({
      width: Math.max(1, Math.round(window.innerWidth || document.documentElement.clientWidth || 390)),
      height: Math.max(1, Math.round(window.innerHeight || document.documentElement.clientHeight || 844))
    })`;
    try {
      const rawValue = await controller.runJavaScript(script);
      const parsedValue = JSON.parse(rawValue) as BrowserTabPreviewWebViewportSize;
      const width = Math.round(parsedValue.width);
      const height = Math.round(parsedValue.height);
      if (Number.isFinite(width) && Number.isFinite(height) && width > 0 && height > 0) {
        hilog.info(LOG_DOMAIN, LOG_TAG, '[THUMB-DIAG] viewport-size tab=%{public}s used=js-probe %{public}s',
          tabId, `${width}x${height}`);
        return {
          width: Math.min(16000, Math.max(1, width)),
          height: Math.min(16000, Math.max(1, height))
        };
      }
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'web viewport size fallback tab=%{public}s error=%{public}s',
        tabId, JSON.stringify(error));
    }
    hilog.warn(LOG_DOMAIN, LOG_TAG, '[THUMB-DIAG] viewport-size tab=%{public}s used=fallback %{public}s',
      tabId, `${fallbackSize.width}x${fallbackSize.height}`);
    return fallbackSize;
  }

  private resolveDisplayDensity(): number {
    try {
      const density = display.getDefaultDisplaySync().densityPixels;
      return Number.isFinite(density) && density > 0 ? density : 1;
    } catch (_error) {
      return 1;
    }
  }

  private resolveSurfaceId(
    controller: webview.WebviewController,
    tabId: string,
    source: BrowserTabPreviewCaptureSource
  ): string {
    try {
      const surfaceId = controller.getSurfaceId();
      if (surfaceId.trim().length <= 0) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'surface id empty tab=%{public}s source=%{public}s', tabId, source);
        return '';
      }
      return surfaceId;
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'surface id failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
      return '';
    }
  }

  private async releaseUnusedCandidateSnapshot(
    pixelMap: image.PixelMap,
    tabId: string,
    source: BrowserTabPreviewCaptureSource,
    reason: string
  ): Promise<void> {
    try {
      await pixelMap.release();
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'release unused candidate failed tab=%{public}s source=%{public}s reason=%{public}s error=%{public}s',
        tabId, source, reason, JSON.stringify(error));
    }
  }

  private async releaseGeneratedSharedSnapshot(
    pixelMap: image.PixelMap,
    tabId: string,
    source: BrowserTabPreviewCaptureSource
  ): Promise<void> {
    try {
      await pixelMap.release();
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'release generated shared snapshot failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
    }
  }

  private async isBlankSnapshot(
    pixelMap: image.PixelMap,
    tabId: string,
    source: BrowserTabPreviewCaptureSource,
    options: BrowserTabPreviewCaptureOptions
  ): Promise<boolean> {
    let sample: image.PixelMap | undefined = undefined;
    try {
      const imageInfo = pixelMap.getImageInfoSync();
      const width = Math.max(1, Math.floor(imageInfo.size.width));
      const height = Math.max(1, Math.floor(imageInfo.size.height));
      const targetWidth = Math.min(BLANK_SNAPSHOT_SAMPLE_WIDTH, width);
      const targetHeight = Math.min(BLANK_SNAPSHOT_SAMPLE_HEIGHT, height);
      sample = await pixelMap.createCroppedAndScaledPixelMap({
        x: 0,
        y: 0,
        size: {
          width: width,
          height: height
        }
      }, targetWidth / width, targetHeight / height, image.AntiAliasingLevel.LOW);
      const buffer = new ArrayBuffer(sample.getPixelBytesNumber());
      await sample.readPixelsToBuffer(buffer);
      return this.isBlankRgbaBuffer(buffer, tabId, source, options);
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'blank snapshot check failed tab=%{public}s source=%{public}s error=%{public}s',
        tabId, source, JSON.stringify(error));
      return false;
    } finally {
      if (sample !== undefined && sample !== pixelMap) {
        await sample.release().catch((_error: Error) => {});
      }
    }
  }

  private isBlankRgbaBuffer(
    buffer: ArrayBuffer,
    tabId: string,
    source: BrowserTabPreviewCaptureSource,
    options: BrowserTabPreviewCaptureOptions
  ): boolean {
    const pixels = new Uint8Array(buffer);
    if (pixels.length < 4) {
      return true;
    }
    let minLuminance = 1;
    let maxLuminance = 0;
    let minRed = 1;
    let maxRed = 0;
    let minGreen = 1;
    let maxGreen = 0;
    let minBlue = 1;
    let maxBlue = 0;
    let luminanceTotal = 0;
    let visiblePixels = 0;
    for (let index = 0; index + 3 < pixels.length; index += 4) {
      const alpha = pixels[index + 3] / 255;
      if (alpha <= 0.05) {
        continue;
      }
      const red = pixels[index] / 255;
      const green = pixels[index + 1] / 255;
      const blue = pixels[index + 2] / 255;
      const luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue;
      minLuminance = Math.min(minLuminance, luminance);
      maxLuminance = Math.max(maxLuminance, luminance);
      minRed = Math.min(minRed, red);
      maxRed = Math.max(maxRed, red);
      minGreen = Math.min(minGreen, green);
      maxGreen = Math.max(maxGreen, green);
      minBlue = Math.min(minBlue, blue);
      maxBlue = Math.max(maxBlue, blue);
      luminanceTotal += luminance;
      visiblePixels += 1;
    }
    if (visiblePixels <= 0) {
      return true;
    }
    const averageLuminance = luminanceTotal / visiblePixels;
    const luminanceRange = maxLuminance - minLuminance;
    const colorRange = Math.max(maxRed - minRed, maxGreen - minGreen, maxBlue - minBlue);
    const lowDetail = luminanceRange < BLANK_SNAPSHOT_MIN_LUMINANCE_RANGE &&
      colorRange < BLANK_SNAPSHOT_MIN_COLOR_RANGE;
    const blank = lowDetail &&
      (averageLuminance <= BLANK_SNAPSHOT_BLACK_LUMINANCE ||
        averageLuminance >= BLANK_SNAPSHOT_WHITE_LUMINANCE);
    const rejected = blank || (options.rejectLowDetailSnapshot === true && lowDetail);
    if (rejected) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'blank snapshot rejected tab=%{public}s source=%{public}s avg=%{public}s lumRange=%{public}s colorRange=%{public}s',
        tabId, source, `${averageLuminance}`, `${luminanceRange}`, `${colorRange}`);
    }
    return rejected;
  }

  private compactFailureReasons(failures: string[]): string {
    const compacted = failures
      .filter((reason: string) => reason.trim().length > 0)
      .slice(0, 4)
      .join('/');
    return compacted.length > 0 ? compacted : 'snapshot-empty';
  }
}
