import {
  HomeWallpaperPresentationState,
  HomeWallpaperVisibleCropInput,
  WallpaperRepositorySnapshot,
  WallpaperSettings,
  cloneHomeWallpaperPresentationState,
  isSameHomeWallpaperPresentationState
} from '../../common/models/WallpaperModels';
import { WallpaperRepository } from '../../data/wallpaper/WallpaperRepository';
import { BingWallpaperService } from '../../services/wallpaper/BingWallpaperService';
import { WallpaperPresentationService } from '../../services/wallpaper/WallpaperPresentationService';
import { HOME_IMAGE_WALLPAPER_MASK_OPACITY } from '../../services/wallpaper/HomeWallpaperAnalysisPolicy';
import { CustomWallpaperService } from '../../services/wallpaper/CustomWallpaperService';
import {
  BrowserViewportStabilityPolicy,
  BrowserViewportState
} from '../browser/BrowserViewportStabilityPolicy';

interface HomeWallpaperViewportInput {
  viewportWidth: number;
  viewportHeight: number;
}

export interface HomeWallpaperRefreshResult {
  state: HomeWallpaperPresentationState;
  presentationChanged: boolean;
}

export class HomeWallpaperCoordinator {
  private repository: WallpaperRepository;
  private presentationService: WallpaperPresentationService;
  private bingWallpaperService: BingWallpaperService;
  private customWallpaperService: CustomWallpaperService;
  private initialized: boolean = false;
  private presentationState: HomeWallpaperPresentationState;
  private lastViewportInput: HomeWallpaperViewportInput | undefined = undefined;
  private stableViewport: BrowserViewportState = { width: 0, height: 0 };
  private viewportStabilityPolicy: BrowserViewportStabilityPolicy;
  private refreshQueue: Promise<void> = Promise.resolve();

  constructor(
    repository: WallpaperRepository,
    presentationService: WallpaperPresentationService = new WallpaperPresentationService(),
    bingWallpaperService: BingWallpaperService = new BingWallpaperService(repository),
    customWallpaperService: CustomWallpaperService = new CustomWallpaperService(repository),
    viewportStabilityPolicy: BrowserViewportStabilityPolicy = new BrowserViewportStabilityPolicy()
  ) {
    this.repository = repository;
    this.presentationService = presentationService;
    this.bingWallpaperService = bingWallpaperService;
    this.customWallpaperService = customWallpaperService;
    this.viewportStabilityPolicy = viewportStabilityPolicy;
    this.presentationState = this.presentationService.buildDefaultPresentationState();
  }

  async initialize(): Promise<HomeWallpaperPresentationState> {
    const snapshot = await this.repository.initialize();
    this.initialized = true;
    this.presentationState = snapshot.settings.mode === 'bing' ?
      this.presentationService.buildDefaultPresentationState() :
      this.presentationService.buildPresentationState(snapshot);
    return this.getPresentationState();
  }

  async refreshForHomeVisible(
    viewportWidth: number,
    viewportHeight: number,
    keepViewportStableOnShrink: boolean = false,
    nowMs: number = Date.now()
  ): Promise<HomeWallpaperRefreshResult> {
    const viewportInput = this.resolveStableViewportInput(
      viewportWidth,
      viewportHeight,
      keepViewportStableOnShrink
    );
    this.lastViewportInput = this.cloneViewportInput(viewportInput);
    return this.runSerializedRefresh(async (): Promise<HomeWallpaperRefreshResult> => {
      const previousState = this.getPresentationState();
      let snapshot = await this.ensureSnapshot();
      if (snapshot.settings.mode === 'bing') {
        const cropInput = this.buildVisibleCropInput(viewportInput);
        await this.bingWallpaperService.refreshIfNeeded(snapshot, cropInput, nowMs);
        snapshot = this.repository.getSnapshot();
        if (!this.bingWallpaperService.isSnapshotReady(snapshot, cropInput)) {
          return {
            state: previousState,
            presentationChanged: false
          };
        }
      } else if (snapshot.settings.mode === 'custom') {
        const cropInput = this.buildVisibleCropInput(viewportInput);
        await this.customWallpaperService.refreshAnalysisIfNeeded(snapshot, cropInput, nowMs);
        snapshot = this.repository.getSnapshot();
      }
      this.presentationState = this.presentationService.buildPresentationState(snapshot, nowMs);
      const state = this.getPresentationState();
      return {
        state: state,
        presentationChanged: !isSameHomeWallpaperPresentationState(previousState, state)
      };
    });
  }

  async saveSettings(settings: WallpaperSettings): Promise<HomeWallpaperPresentationState> {
    await this.repository.saveSettings(settings);
    if (this.lastViewportInput !== undefined) {
      return (await this.refreshForHomeVisible(
        this.lastViewportInput.viewportWidth,
        this.lastViewportInput.viewportHeight
      )).state;
    }
    this.presentationState = this.presentationService.buildPresentationState(this.repository.getSnapshot());
    return this.getPresentationState();
  }

  getPresentationState(): HomeWallpaperPresentationState {
    return cloneHomeWallpaperPresentationState(this.presentationState);
  }

  private buildVisibleCropInput(viewportInput: HomeWallpaperViewportInput): HomeWallpaperVisibleCropInput {
    return {
      viewportWidth: viewportInput.viewportWidth,
      viewportHeight: viewportInput.viewportHeight,
      maskOpacity: HOME_IMAGE_WALLPAPER_MASK_OPACITY
    };
  }

  private resolveStableViewportInput(
    viewportWidth: number,
    viewportHeight: number,
    keepStableOnShrink: boolean
  ): HomeWallpaperViewportInput {
    this.stableViewport = this.viewportStabilityPolicy.resolve({
      nextWidth: viewportWidth,
      nextHeight: viewportHeight,
      currentViewport: this.stableViewport,
      keepStableOnShrink
    });
    return {
      viewportWidth: this.stableViewport.width,
      viewportHeight: this.stableViewport.height
    };
  }

  private cloneViewportInput(viewportInput: HomeWallpaperViewportInput): HomeWallpaperViewportInput {
    return {
      viewportWidth: viewportInput.viewportWidth,
      viewportHeight: viewportInput.viewportHeight
    };
  }

  private async runSerializedRefresh<T>(task: () => Promise<T>): Promise<T> {
    const previous = this.refreshQueue;
    let releaseQueue = (): void => {};
    this.refreshQueue = new Promise<void>((resolve: () => void) => {
      releaseQueue = resolve;
    });
    await previous;
    try {
      return await task();
    } finally {
      releaseQueue();
    }
  }

  private async ensureSnapshot(): Promise<WallpaperRepositorySnapshot> {
    if (!this.initialized) {
      return this.repository.initialize().then((snapshot: WallpaperRepositorySnapshot) => {
        this.initialized = true;
        return snapshot;
      });
    }
    return Promise.resolve(this.repository.getSnapshot());
  }
}
