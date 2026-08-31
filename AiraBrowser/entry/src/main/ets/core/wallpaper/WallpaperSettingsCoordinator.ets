import {
  HomeWallpaperVisibleCropInput,
  WallpaperMode,
  WallpaperRepositorySnapshot
} from '../../common/models/WallpaperModels';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import { CustomWallpaperService } from '../../services/wallpaper/CustomWallpaperService';
import {
  BingWallpaperRefreshResult,
  BingWallpaperService
} from '../../services/wallpaper/BingWallpaperService';
import { HOME_IMAGE_WALLPAPER_MASK_OPACITY } from '../../services/wallpaper/HomeWallpaperAnalysisPolicy';
import {
  WallpaperBingPreviewStatus,
  WallpaperSettingsViewModel,
  WallpaperSettingsViewState
} from './WallpaperSettingsViewModel';

const WALLPAPER_SETTINGS_PREVIEW_WIDTH: number = 360;
const WALLPAPER_SETTINGS_PREVIEW_HEIGHT: number = 640;

export type WallpaperSettingsStateListener = (state: WallpaperSettingsViewState) => void;

export class WallpaperSettingsCoordinator {
  private repository: WallpaperRepository;
  private viewModel: WallpaperSettingsViewModel;
  private customWallpaperService: CustomWallpaperService;
  private bingWallpaperService: BingWallpaperService;
  private initialized: boolean = false;
  private bingPreviewStatus: WallpaperBingPreviewStatus = 'idle';
  private bingPreviewRefreshTask: Promise<WallpaperSettingsViewState> | undefined = undefined;
  private modeSelectionRevision: number = 0;
  private hasValidatedBingPreview: boolean = false;

  constructor(
    repository: WallpaperRepository,
    viewModel: WallpaperSettingsViewModel = new WallpaperSettingsViewModel(),
    customWallpaperService: CustomWallpaperService = new CustomWallpaperService(repository),
    bingWallpaperService: BingWallpaperService = new BingWallpaperService(repository)
  ) {
    this.repository = repository;
    this.viewModel = viewModel;
    this.customWallpaperService = customWallpaperService;
    this.bingWallpaperService = bingWallpaperService;
  }

  async initialize(): Promise<WallpaperSettingsViewState> {
    const snapshot = await this.repository.initialize();
    this.initialized = true;
    this.syncBingPreviewStatus(snapshot);
    return this.getCurrentState();
  }

  async getState(): Promise<WallpaperSettingsViewState> {
    const snapshot = await this.ensureSnapshot();
    this.syncBingPreviewStatus(snapshot);
    return this.getCurrentState();
  }

  async loadState(onStateChange: WallpaperSettingsStateListener): Promise<WallpaperSettingsViewState> {
    const state = await this.getState();
    onStateChange(state);
    onStateChange(this.beginBingPreviewRefresh());
    const refreshedState = await this.refreshBingPreview(false);
    onStateChange(refreshedState);
    return refreshedState;
  }

  async selectMode(
    mode: WallpaperMode,
    onStateChange: WallpaperSettingsStateListener
  ): Promise<WallpaperSettingsViewState> {
    const revision = ++this.modeSelectionRevision;
    onStateChange(this.buildPendingModeState(mode));
    const state = await this.applyMode(mode, revision);
    if (revision !== this.modeSelectionRevision) {
      return this.getCurrentState();
    }
    onStateChange(state);
    return state;
  }

  async retryBingPreview(onStateChange: WallpaperSettingsStateListener): Promise<WallpaperSettingsViewState> {
    onStateChange(this.beginBingPreviewRefresh());
    const state = await this.refreshBingPreview(true);
    onStateChange(state);
    return state;
  }

  getCurrentState(): WallpaperSettingsViewState {
    const snapshot = this.repository.getSnapshot();
    const status = this.bingPreviewStatus === 'idle' ? this.resolveBingPreviewStatus(snapshot) :
      this.bingPreviewStatus;
    return this.viewModel.buildState(snapshot, status);
  }

  private beginBingPreviewRefresh(): WallpaperSettingsViewState {
    this.bingPreviewStatus = 'loading';
    return this.getCurrentState();
  }

  private refreshBingPreview(forceRefresh: boolean = false): Promise<WallpaperSettingsViewState> {
    if (this.bingPreviewRefreshTask !== undefined) {
      return this.bingPreviewRefreshTask;
    }
    this.bingPreviewStatus = 'loading';
    const task = this.performBingPreviewRefresh(forceRefresh);
    this.bingPreviewRefreshTask = task;
    return task.then(
      (state: WallpaperSettingsViewState): WallpaperSettingsViewState => {
        if (this.bingPreviewRefreshTask === task) {
          this.bingPreviewRefreshTask = undefined;
        }
        return state;
      },
      (error: Error): WallpaperSettingsViewState => {
        if (this.bingPreviewRefreshTask === task) {
          this.bingPreviewRefreshTask = undefined;
        }
        this.bingPreviewStatus = 'error';
        throw error;
      }
    );
  }

  private buildPendingModeState(mode: WallpaperMode): WallpaperSettingsViewState {
    if (mode === 'custom') {
      return this.getCurrentState();
    }
    const snapshot = this.repository.getSnapshot();
    if (mode === 'bing' && !this.hasValidatedBingPreview) {
      return this.viewModel.buildState(snapshot, 'loading');
    }
    return this.viewModel.buildState({
      settings: this.viewModel.buildSettingsWithMode(snapshot.settings, mode),
      assets: snapshot.assets
    }, mode === 'bing' ? 'loading' : this.bingPreviewStatus);
  }

  private async applyMode(mode: WallpaperMode, revision: number): Promise<WallpaperSettingsViewState> {
    if (mode === 'bing') {
      return this.applyBingMode(revision);
    }
    const snapshot = await this.ensureSnapshot();
    if (revision !== this.modeSelectionRevision) {
      return this.getCurrentState();
    }
    if (mode === 'custom') {
      const reusableAsset = snapshot.assets.find((asset) => {
        return asset.source === 'custom' && asset.id === snapshot.settings.customWallpaperId;
      });
      if (snapshot.settings.mode !== 'custom' && reusableAsset !== undefined) {
        await this.repository.saveSettings(this.viewModel.buildSettingsWithMode(snapshot.settings, mode));
        return this.getState();
      }
      await this.customWallpaperService.selectAndApply();
      return this.getState();
    }
    await this.repository.saveSettings(this.viewModel.buildSettingsWithMode(snapshot.settings, mode));
    return this.getState();
  }

  private async applyBingMode(revision: number): Promise<WallpaperSettingsViewState> {
    await this.ensureSnapshot();
    if (revision !== this.modeSelectionRevision) {
      return this.getCurrentState();
    }
    let snapshot = this.repository.getSnapshot();
    const hadCachedImage = await this.bingWallpaperService.hasUsableCachedImage(snapshot);
    this.hasValidatedBingPreview = hadCachedImage;
    if (hadCachedImage) {
      await this.repository.saveSettings(this.viewModel.buildSettingsWithMode(snapshot.settings, 'bing'));
      return this.getCurrentState();
    }
    await this.refreshBingPreview(false);
    if (revision !== this.modeSelectionRevision) {
      return this.getCurrentState();
    }
    snapshot = this.repository.getSnapshot();
    if (!(await this.bingWallpaperService.hasUsableCachedImage(snapshot))) {
      this.hasValidatedBingPreview = false;
      this.bingPreviewStatus = 'error';
      return this.getCurrentState();
    }
    this.hasValidatedBingPreview = true;
    await this.repository.saveSettings(this.viewModel.buildSettingsWithMode(snapshot.settings, 'bing'));
    return this.getCurrentState();
  }

  private async performBingPreviewRefresh(forceRefresh: boolean): Promise<WallpaperSettingsViewState> {
    const snapshot = await this.ensureSnapshot();
    const result = await this.bingWallpaperService.refreshPreviewIfNeeded(
      snapshot,
      this.buildPreviewCropInput(),
      forceRefresh
    );
    await this.applyBingRefreshResult(result);
    return this.getCurrentState();
  }

  private async applyBingRefreshResult(result: BingWallpaperRefreshResult): Promise<void> {
    this.hasValidatedBingPreview = result.hasCachedImage;
    if (!result.hasCachedImage) {
      const snapshot = this.repository.getSnapshot();
      if (snapshot.settings.mode === 'bing') {
        await this.repository.saveSettings(
          this.viewModel.buildSettingsWithMode(snapshot.settings, 'theme'),
          'system'
        );
      }
    }
    this.bingPreviewStatus = result.failureReason.trim().length > 0 || !result.hasCachedImage ? 'error' : 'ready';
  }

  private buildPreviewCropInput(): HomeWallpaperVisibleCropInput {
    return {
      viewportWidth: WALLPAPER_SETTINGS_PREVIEW_WIDTH,
      viewportHeight: WALLPAPER_SETTINGS_PREVIEW_HEIGHT,
      maskOpacity: HOME_IMAGE_WALLPAPER_MASK_OPACITY
    };
  }

  private syncBingPreviewStatus(snapshot: WallpaperRepositorySnapshot): void {
    if (this.bingPreviewStatus === 'idle' || this.bingPreviewStatus === 'ready') {
      this.bingPreviewStatus = this.resolveBingPreviewStatus(snapshot);
    }
  }

  private resolveBingPreviewStatus(snapshot: WallpaperRepositorySnapshot): WallpaperBingPreviewStatus {
    if (snapshot.settings.bing.failureReason.trim().length > 0) {
      return 'error';
    }
    return this.hasValidatedBingPreview ? 'ready' : 'idle';
  }

  private async ensureSnapshot(): Promise<WallpaperRepositorySnapshot> {
    if (!this.initialized) {
      const snapshot = await this.repository.initialize();
      this.initialized = true;
      return snapshot;
    }
    return Promise.resolve(this.repository.getSnapshot());
  }
}
