import { http } from '@kit.NetworkKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  HOME_WALLPAPER_FOREGROUND_ALGORITHM_VERSION,
  HomeWallpaperForegroundAnalysis,
  HomeWallpaperVisibleCropInput,
  WallpaperAsset,
  WallpaperBingState,
  WallpaperRepositorySnapshot,
  WallpaperSettings
} from '../../common/models/WallpaperModels';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import { WallpaperAssetStore } from '../../data/wallpaper/WallpaperAssetStore';
import { WallpaperForegroundToneService } from './WallpaperForegroundToneService';
import {
  BrowserHomepageBackdropAppearanceEffectInput,
  BrowserHomepageBackdropAppearanceState
} from '../../common/models/BackdropAppearanceModels';
import { BackdropAppearanceSamplingService } from '../appearance/BackdropAppearanceSamplingService';

const BING_METADATA_ENDPOINT: string = 'https://www.bing.com/HPImageArchive.aspx';
const BING_HOST: string = 'https://www.bing.com';
const BING_REQUEST_TIMEOUT_MS: number = 12000;
const MAX_BING_IMAGE_BYTES: number = 15 * 1024 * 1024;
const BING_DAILY_CACHE_ASSET_ID: string = 'bing-daily';
const BING_RETIRED_IMAGE_CLEANUP_DELAY_MS: number = 5000;
const BING_STALE_DAY_RECHECK_INTERVAL_MS: number = 2 * 60 * 60 * 1000;
const BING_WALLPAPER_LOG_DOMAIN: number = 0x0000;
const BING_WALLPAPER_LOG_TAG: string = 'BingWallpaper';

interface BingImageArchiveResponse {
  images?: BingImageArchiveItem[];
}

interface BingImageArchiveItem {
  startdate?: string;
  url?: string;
  title?: string;
  copyright?: string;
}

interface BingWallpaperCandidate {
  id: string;
  dayKey: string;
  imageUrl: string;
  title: string;
  attribution: string;
}

interface BingWallpaperAppearancePair {
  light?: BrowserHomepageBackdropAppearanceState;
  dark?: BrowserHomepageBackdropAppearanceState;
}

interface BingWallpaperAnalyzedImage {
  foreground: HomeWallpaperForegroundAnalysis;
  appearancePair: BingWallpaperAppearancePair;
}

type BingWallpaperRefreshMode = 'home' | 'preview';

export interface BingWallpaperRefreshResult {
  hasCachedImage: boolean;
  failureReason: string;
}

export class BingWallpaperService {
  private repository: WallpaperRepository;
  private assetStore: WallpaperAssetStore;
  private foregroundToneService: WallpaperForegroundToneService;
  private appearanceSamplingService: BackdropAppearanceSamplingService;

  constructor(
    repository: WallpaperRepository,
    assetStore: WallpaperAssetStore = new WallpaperAssetStore(),
    foregroundToneService: WallpaperForegroundToneService = new WallpaperForegroundToneService(),
    appearanceSamplingService: BackdropAppearanceSamplingService = new BackdropAppearanceSamplingService()
  ) {
    this.repository = repository;
    this.assetStore = assetStore;
    this.foregroundToneService = foregroundToneService;
    this.appearanceSamplingService = appearanceSamplingService;
  }

  async refreshIfNeeded(
    snapshot: WallpaperRepositorySnapshot,
    cropInput: HomeWallpaperVisibleCropInput,
    nowMs: number = Date.now()
  ): Promise<BingWallpaperRefreshResult> {
    return this.refreshWithPolicy(snapshot, cropInput, 'home', false, nowMs);
  }

  async refreshPreviewIfNeeded(
    snapshot: WallpaperRepositorySnapshot,
    cropInput: HomeWallpaperVisibleCropInput,
    forceRefresh: boolean = false,
    nowMs: number = Date.now()
  ): Promise<BingWallpaperRefreshResult> {
    return this.refreshWithPolicy(snapshot, cropInput, 'preview', forceRefresh, nowMs);
  }

  private async refreshWithPolicy(
    snapshot: WallpaperRepositorySnapshot,
    cropInput: HomeWallpaperVisibleCropInput,
    mode: BingWallpaperRefreshMode,
    forceRefresh: boolean,
    nowMs: number
  ): Promise<BingWallpaperRefreshResult> {
    const todayKey = this.buildTodayKey(nowMs);
    let currentSnapshot = snapshot;
    let cachedAsset = this.findCachedBingAsset(currentSnapshot);
    if (cachedAsset !== undefined && !(await this.isCachedAssetReadable(cachedAsset))) {
      await this.repository.removeAsset(cachedAsset.id);
      currentSnapshot = this.repository.getSnapshot();
      cachedAsset = undefined;
    }
    if (!forceRefresh && cachedAsset !== undefined &&
      this.isRefreshCheckFresh(currentSnapshot.settings.bing, todayKey, nowMs)) {
      if (mode === 'preview') {
        return this.buildRefreshResult(currentSnapshot);
      }
      if (currentSnapshot.settings.bing.currentAssetId === BING_DAILY_CACHE_ASSET_ID &&
        this.hasUsableForegroundAnalysis(cachedAsset, cropInput)) {
        return this.buildRefreshResult(currentSnapshot);
      }
      if (this.hasReusableContentIdentity(cachedAsset)) {
        return this.refreshCachedAssetAnalysis(currentSnapshot.settings, cachedAsset, cropInput, nowMs);
      }
    }
    if (!forceRefresh && this.isFailureRetryDeferred(currentSnapshot.settings.bing, nowMs)) {
      if (mode === 'home' && cachedAsset !== undefined &&
        this.hasReusableContentIdentity(cachedAsset) &&
        !this.hasUsableForegroundAnalysis(cachedAsset, cropInput)) {
        return this.refreshCachedAssetAnalysis(currentSnapshot.settings, cachedAsset, cropInput, nowMs);
      }
      return this.buildRefreshResult(currentSnapshot);
    }
    return this.refresh(currentSnapshot.settings, cropInput, todayKey, nowMs);
  }

  async hasUsableCachedImage(snapshot: WallpaperRepositorySnapshot): Promise<boolean> {
    const asset = this.findCachedBingAsset(snapshot);
    return asset !== undefined && await this.isCachedAssetReadable(asset);
  }

  isSnapshotReady(
    snapshot: WallpaperRepositorySnapshot,
    cropInput: HomeWallpaperVisibleCropInput
  ): boolean {
    const selectedAssetId = snapshot.settings.bingWallpaperId.trim().length > 0 ?
      snapshot.settings.bingWallpaperId : snapshot.settings.bing.currentAssetId;
    const asset = snapshot.assets.find((candidate: WallpaperAsset) => {
      return candidate.id === selectedAssetId && candidate.source === 'bing';
    });
    return asset !== undefined && this.hasUsableForegroundAnalysis(asset, cropInput);
  }

  private async refresh(
    settings: WallpaperSettings,
    cropInput: HomeWallpaperVisibleCropInput,
    todayKey: string,
    nowMs: number
  ): Promise<BingWallpaperRefreshResult> {
    try {
      const candidate = await this.fetchCandidate(settings.bing.market, todayKey);
      const bytes = await this.downloadImage(candidate.imageUrl);
      const contentSignature = this.buildContentSignature(bytes);
      const analyzed = await this.analyzeImagePayload(
        bytes,
        cropInput,
        contentSignature,
        candidate.id,
        candidate.dayKey,
        nowMs
      );
      const asset = await this.assetStore.saveDownloadedImage(
        'bing',
        BING_DAILY_CACHE_ASSET_ID,
        bytes,
        candidate.title,
        candidate.attribution,
        analyzed.foreground,
        analyzed.appearancePair.light,
        analyzed.appearancePair.dark,
        nowMs
      );
      await this.repository.commitBingAppearance(
        asset,
        this.buildBingSuccessState(settings.bing, asset, candidate.dayKey, nowMs),
        nowMs
      );
      this.scheduleObsoleteImageCleanup(asset);
      return this.buildRefreshResult(this.repository.getSnapshot());
    } catch (error) {
      hilog.warn(
        BING_WALLPAPER_LOG_DOMAIN,
        BING_WALLPAPER_LOG_TAG,
        'Bing wallpaper refresh failed: %{public}s',
        JSON.stringify(error)
      );
      await this.repository.updateSettings({
        bing: this.buildBingFailureState(settings.bing, nowMs)
      });
      return this.buildRefreshResult(this.repository.getSnapshot());
    }
  }

  private async refreshCachedAssetAnalysis(
    settings: WallpaperSettings,
    asset: WallpaperAsset,
    cropInput: HomeWallpaperVisibleCropInput,
    nowMs: number
  ): Promise<BingWallpaperRefreshResult> {
    let file: fileIo.File | undefined = undefined;
    let imageSource: image.ImageSource | undefined = undefined;
    let sample: image.PixelMap | undefined = undefined;
    try {
      file = await fileIo.open(asset.originalPath, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(file.fd);
      sample = await this.foregroundToneService.createVisibleCropSample(imageSource, cropInput);
      const foreground = await this.foregroundToneService.resolveToneFromPixelMap(
        sample,
        cropInput,
        asset.contentSignature
      );
      const appearancePair = await this.resolveAppearancePairFromPixelMap(
        sample,
        asset.id,
        settings.bing.lastRefreshDay,
        nowMs
      );
      const refreshedAsset: WallpaperAsset = {
        id: asset.id,
        source: asset.source,
        mediaType: asset.mediaType,
        originalPath: asset.originalPath,
        displayPath: asset.displayPath,
        thumbPath: asset.thumbPath,
        contentSignature: asset.contentSignature,
        foregroundTone: foreground.foregroundTone,
        foregroundToneContentSignature: foreground.contentSignature,
        foregroundToneCropSignature: foreground.cropSignature,
        foregroundToneSampleSignature: foreground.sampleSignature,
        foregroundToneAlgorithmVersion: foreground.algorithmVersion,
        appearanceLight: appearancePair.light ?? asset.appearanceLight,
        appearanceDark: appearancePair.dark ?? asset.appearanceDark,
        width: asset.width,
        height: asset.height,
        mimeType: asset.mimeType,
        byteSize: asset.byteSize,
        title: asset.title,
        attribution: asset.attribution,
        createdAt: asset.createdAt,
        updatedAt: nowMs,
        isFavorite: asset.isFavorite
      };
      await this.repository.commitBingAppearance(
        refreshedAsset,
        this.buildBingAnalysisState(settings.bing, refreshedAsset),
        nowMs
      );
      return this.buildRefreshResult(this.repository.getSnapshot());
    } catch (error) {
      hilog.warn(
        BING_WALLPAPER_LOG_DOMAIN,
        BING_WALLPAPER_LOG_TAG,
        'Cached Bing wallpaper analysis failed: %{public}s',
        JSON.stringify(error)
      );
      await this.repository.updateSettings({
        bing: this.buildBingFailureState(settings.bing, nowMs)
      });
      return this.buildRefreshResult(this.repository.getSnapshot());
    } finally {
      if (sample !== undefined) {
        await sample.release().catch((_error: Error) => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {});
      }
      if (file !== undefined) {
        await fileIo.close(file).catch((_error: Error) => {});
      }
    }
  }

  private async fetchCandidate(market: string, fallbackDayKey: string): Promise<BingWallpaperCandidate> {
    const request = http.createHttp();
    try {
      const response = await request.request(this.buildMetadataUrl(market), {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: BING_REQUEST_TIMEOUT_MS,
        readTimeout: BING_REQUEST_TIMEOUT_MS,
        usingCache: true,
        header: {
          'Accept': 'application/json',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || typeof response.result !== 'string') {
        throw new Error('bing-metadata-http');
      }
      const payload = JSON.parse(response.result) as BingImageArchiveResponse;
      const item = payload.images?.[0];
      const imageUrl = this.resolveImageUrl(item?.url ?? '');
      if (imageUrl.length === 0) {
        throw new Error('bing-image-url-missing');
      }
      const dayKey = this.normalizeDayKey(item?.startdate ?? fallbackDayKey, fallbackDayKey);
      return {
        id: BING_DAILY_CACHE_ASSET_ID,
        dayKey: dayKey,
        imageUrl: imageUrl,
        title: item?.title ?? 'Bing 每日壁纸',
        attribution: item?.copyright ?? ''
      };
    } finally {
      request.destroy();
    }
  }

  private findCachedBingAsset(snapshot: WallpaperRepositorySnapshot): WallpaperAsset | undefined {
    return snapshot.assets.find((asset: WallpaperAsset) => {
      return asset.id === BING_DAILY_CACHE_ASSET_ID && asset.source === 'bing' &&
        asset.originalPath.trim().length > 0 && this.resolveCachedPreviewPath(asset).length > 0;
    });
  }

  private resolveCachedPreviewPath(asset: WallpaperAsset): string {
    const thumbPath = asset.thumbPath.trim();
    return thumbPath.length > 0 ? thumbPath : asset.displayPath.trim();
  }

  private async isCachedAssetReadable(asset: WallpaperAsset): Promise<boolean> {
    let file: fileIo.File | undefined = undefined;
    try {
      file = await fileIo.open(this.resolveCachedPreviewPath(asset), fileIo.OpenMode.READ_ONLY);
      return true;
    } catch (_error) {
      return false;
    } finally {
      if (file !== undefined) {
        await fileIo.close(file).catch((_error: Error) => {});
      }
    }
  }

  private hasUsableForegroundAnalysis(
    asset: WallpaperAsset,
    cropInput: HomeWallpaperVisibleCropInput
  ): boolean {
    return asset.foregroundToneAlgorithmVersion === HOME_WALLPAPER_FOREGROUND_ALGORITHM_VERSION &&
      this.hasReusableContentIdentity(asset) &&
      asset.foregroundToneContentSignature === asset.contentSignature &&
      asset.foregroundToneCropSignature === this.foregroundToneService.buildCropSignature(cropInput) &&
      asset.foregroundToneSampleSignature.trim().length > 0;
  }

  private hasReusableContentIdentity(asset: WallpaperAsset): boolean {
    const contentSignature = asset.contentSignature.trim();
    return contentSignature.length > 0 && asset.originalPath.indexOf(`-${contentSignature}.jpg`) >= 0;
  }

  private async downloadImage(imageUrl: string): Promise<ArrayBuffer> {
    const request = http.createHttp();
    try {
      const response = await request.request(imageUrl, {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        connectTimeout: BING_REQUEST_TIMEOUT_MS,
        readTimeout: BING_REQUEST_TIMEOUT_MS,
        usingCache: true,
        header: {
          'Accept': 'image/jpeg,image/webp,image/*;q=0.8',
          'User-Agent': 'AiraBrowser/1.0'
        }
      });
      if (response.responseCode < 200 || response.responseCode >= 300 || !(response.result instanceof ArrayBuffer)) {
        throw new Error('bing-image-http');
      }
      if (response.result.byteLength <= 0 || response.result.byteLength > MAX_BING_IMAGE_BYTES) {
        throw new Error('bing-image-size');
      }
      return response.result;
    } finally {
      request.destroy();
    }
  }

  private async analyzeImagePayload(
    payload: ArrayBuffer,
    cropInput: HomeWallpaperVisibleCropInput,
    contentSignature: string,
    assetId: string,
    dayKey: string,
    nowMs: number
  ): Promise<BingWallpaperAnalyzedImage> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      imageSource = image.createImageSource(payload);
      pixelMap = await this.foregroundToneService.createVisibleCropSample(imageSource, cropInput);
      const foreground = await this.foregroundToneService.resolveToneFromPixelMap(
        pixelMap,
        cropInput,
        contentSignature
      );
      const appearancePair = await this.resolveAppearancePairFromPixelMap(pixelMap, assetId, dayKey, nowMs);
      return {
        foreground: foreground,
        appearancePair: appearancePair
      };
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release().catch((_error: Error) => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {});
      }
    }
  }

  private async resolveAppearancePairFromPixelMap(
    pixelMap: image.PixelMap,
    assetId: string,
    dayKey: string,
    nowMs: number
  ): Promise<BingWallpaperAppearancePair> {
    try {
      const light = await this.appearanceSamplingService.sample({
        pixelMap: pixelMap,
        sourceKey: `wallpaperImage:${assetId}:light:${dayKey}`,
        effect: this.buildWallpaperAppearanceEffect('light'),
        volatileOnly: false,
        nowMs: nowMs
      });
      const dark = await this.appearanceSamplingService.sample({
        pixelMap: pixelMap,
        sourceKey: `wallpaperImage:${assetId}:dark:${dayKey}`,
        effect: this.buildWallpaperAppearanceEffect('dark'),
        volatileOnly: false,
        nowMs: nowMs
      });
      return {
        light: light,
        dark: dark
      };
    } catch (_error) {
      return this.buildEmptyAppearancePair();
    }
  }

  private buildEmptyAppearancePair(): BingWallpaperAppearancePair {
    return {};
  }

  private buildWallpaperAppearanceEffect(mode: 'light' | 'dark'): BrowserHomepageBackdropAppearanceEffectInput {
    return {
      resolvedThemeMode: mode,
      tintColor: '#000000',
      tintOpacity: 0,
      effectSignature: `wallpaper-image:v1:${mode}`
    };
  }

  private buildContentSignature(payload: ArrayBuffer): string {
    const bytes = new Uint8Array(payload);
    let hash = 2166136261;
    for (let index = 0; index < bytes.length; index += 1) {
      hash = Math.imul(hash ^ bytes[index], 16777619);
    }
    return `fnv1a-${(hash >>> 0).toString(16)}-${bytes.length}`;
  }

  private scheduleObsoleteImageCleanup(activeAsset: WallpaperAsset): void {
    setTimeout(() => {
      void this.assetStore.pruneObsoleteDownloadedImages(activeAsset).catch((_error: Error) => {});
    }, BING_RETIRED_IMAGE_CLEANUP_DELAY_MS);
  }

  private buildBingSuccessState(
    current: WallpaperBingState,
    asset: WallpaperAsset,
    dayKey: string,
    nowMs: number
  ): WallpaperBingState {
    return {
      currentAssetId: asset.id,
      market: current.market,
      lastRefreshDay: dayKey,
      lastRefreshAt: nowMs,
      manualRefreshAvailableAt: nowMs,
      failureReason: ''
    };
  }

  private buildBingFailureState(current: WallpaperBingState, nowMs: number): WallpaperBingState {
    return {
      currentAssetId: current.currentAssetId,
      market: current.market,
      lastRefreshDay: current.lastRefreshDay,
      lastRefreshAt: current.lastRefreshAt,
      manualRefreshAvailableAt: nowMs + 30 * 60 * 1000,
      failureReason: '刷新失败，继续使用缓存或默认壁纸'
    };
  }

  private buildBingAnalysisState(current: WallpaperBingState, asset: WallpaperAsset): WallpaperBingState {
    return {
      currentAssetId: asset.id,
      market: current.market,
      lastRefreshDay: current.lastRefreshDay,
      lastRefreshAt: current.lastRefreshAt,
      manualRefreshAvailableAt: current.manualRefreshAvailableAt,
      failureReason: current.failureReason
    };
  }

  private buildRefreshResult(snapshot: WallpaperRepositorySnapshot): BingWallpaperRefreshResult {
    return {
      hasCachedImage: this.hasCachedImageRecord(snapshot),
      failureReason: snapshot.settings.bing.failureReason
    };
  }

  private hasCachedImageRecord(snapshot: WallpaperRepositorySnapshot): boolean {
    return this.findCachedBingAsset(snapshot) !== undefined;
  }

  private isRefreshCheckFresh(state: WallpaperBingState, todayKey: string, nowMs: number): boolean {
    if (state.lastRefreshDay === todayKey) {
      return true;
    }
    if (state.lastRefreshAt <= 0 || nowMs < state.lastRefreshAt) {
      return false;
    }
    return nowMs - state.lastRefreshAt < BING_STALE_DAY_RECHECK_INTERVAL_MS;
  }

  private isFailureRetryDeferred(state: WallpaperBingState, nowMs: number): boolean {
    return state.failureReason.trim().length > 0 && nowMs < state.manualRefreshAvailableAt;
  }

  private buildMetadataUrl(market: string): string {
    const normalizedMarket = market.trim().length > 0 ? market.trim() : 'zh-CN';
    return `${BING_METADATA_ENDPOINT}?format=js&idx=0&n=1&mkt=${encodeURIComponent(normalizedMarket)}`;
  }

  private resolveImageUrl(value: string): string {
    const trimmedValue = value.trim();
    if (trimmedValue.startsWith('https://') || trimmedValue.startsWith('http://')) {
      return trimmedValue;
    }
    if (trimmedValue.startsWith('/')) {
      return `${BING_HOST}${trimmedValue}`;
    }
    return '';
  }

  private normalizeDayKey(value: string, fallback: string): string {
    const normalized = value.replace(/[^0-9]/g, '');
    return normalized.length >= 8 ? normalized.substring(0, 8) : fallback;
  }

  private buildTodayKey(nowMs: number): string {
    const now = new Date(nowMs);
    const year = now.getFullYear();
    const month = `${now.getMonth() + 1}`.padStart(2, '0');
    const day = `${now.getDate()}`.padStart(2, '0');
    return `${year}${month}${day}`;
  }
}
