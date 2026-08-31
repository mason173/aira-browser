import { UIContext } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { fileIo, fileUri } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  CustomHomepageRemoteWarmupCoordinator,
  CustomHomepageRemoteWarmupResult,
  CustomHomepageRemoteWarmupResultInput,
  CustomHomepageRemoteWarmupTask
} from '../../../core/customhome/CustomHomepageRemoteWarmupCoordinator';
import {
  BrowserTabPreviewCaptureOptions,
  BrowserTabPreviewCaptureService
} from '../../../services/web/BrowserTabPreviewCaptureService';
import {
  BrowserHomepageBackdropAppearanceEffectInput,
  BrowserHomepageBackdropAppearanceState
} from '../../../common/models/BackdropAppearanceModels';
import { BackdropAppearanceSamplingService } from '../../../services/appearance/BackdropAppearanceSamplingService';

type CustomHomepageRemotePreviewTone = 'light' | 'dark';

interface CustomHomepageRemoteWarmupWebState {
  tone: CustomHomepageRemotePreviewTone;
  controller: webview.WebviewController;
  controllerAttached: boolean;
  loading: boolean;
  loaded: boolean;
  failed: boolean;
}

interface CustomHomepageRemoteWarmupPreviewResult {
  lightUri: string;
  darkUri: string;
  lightAppearance?: BrowserHomepageBackdropAppearanceState;
  darkAppearance?: BrowserHomepageBackdropAppearanceState;
}

interface CustomHomepageRemoteWarmupPreviewCaptureResult {
  uri: string;
  appearance?: BrowserHomepageBackdropAppearanceState;
}

const CUSTOM_HOMEPAGE_REMOTE_WARMUP_LIGHT_COMPONENT_ID: string = 'custom-homepage-remote-warmup-web-light';
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_DARK_COMPONENT_ID: string = 'custom-homepage-remote-warmup-web-dark';
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_CACHE_SCOPE_ID: string = 'custom-homepage-preview';
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_VIEWPORT_WIDTH: number = 427;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_VIEWPORT_HEIGHT: number = 844;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_PREVIEW_ASPECT_RATIO: number =
  CUSTOM_HOMEPAGE_REMOTE_WARMUP_VIEWPORT_WIDTH / CUSTOM_HOMEPAGE_REMOTE_WARMUP_VIEWPORT_HEIGHT;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_EDGE_CROP_RATIO: number = 0.012;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_TIMEOUT_MS: number = 9000;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_SETTLE_MS: number = 1200;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_RETRY_MS: number = 900;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_ATTEMPTS: number = 3;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_APPEARANCE_IMAGE_MAX_BYTES: number = 10 * 1024 * 1024;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_APPEARANCE_SAMPLE_WIDTH: number = 96;
const CUSTOM_HOMEPAGE_REMOTE_WARMUP_APPEARANCE_SAMPLE_HEIGHT: number = 144;
const LOG_DOMAIN = 0x0000;
const LOG_TAG = 'HomeWarmup';

@Component
export struct CustomHomepageRemoteWarmupHost {
  @Prop @Watch('handleTaskChanged') task: CustomHomepageRemoteWarmupTask | undefined = undefined;
  @Prop hostIdPrefix: string = 'default';
  private lightWebState: CustomHomepageRemoteWarmupWebState = {
    tone: 'light',
    controller: new webview.WebviewController(),
    controllerAttached: false,
    loading: false,
    loaded: false,
    failed: false
  };
  private darkWebState: CustomHomepageRemoteWarmupWebState = {
    tone: 'dark',
    controller: new webview.WebviewController(),
    controllerAttached: false,
    loading: false,
    loaded: false,
    failed: false
  };
  private previewCaptureService: BrowserTabPreviewCaptureService = new BrowserTabPreviewCaptureService();
  private appearanceSamplingService: BackdropAppearanceSamplingService = new BackdropAppearanceSamplingService();
  private coordinator: CustomHomepageRemoteWarmupCoordinator = new CustomHomepageRemoteWarmupCoordinator();
  private runningTaskId: string = '';
  private timeoutTimer: number = -1;
  private finishing: boolean = false;

  onFinished: (result: CustomHomepageRemoteWarmupResult) => void =
    (_result: CustomHomepageRemoteWarmupResult): void => {};

  aboutToAppear(): void {
    this.tryStartTask();
  }

  aboutToDisappear(): void {
    this.cancelTimeout();
    this.lightWebState.controllerAttached = false;
    this.darkWebState.controllerAttached = false;
  }

  private handleTaskChanged(): void {
    this.tryStartTask();
  }

  build() {
    if (this.task !== undefined) {
      this.buildWarmupWeb(this.lightWebState)
      this.buildWarmupWeb(this.darkWebState)
    }
  }

  @Builder
  private buildWarmupWeb(state: CustomHomepageRemoteWarmupWebState) {
    Web({
      src: '',
      controller: state.controller
    })
      .id(this.resolveComponentId(state))
      .width(CUSTOM_HOMEPAGE_REMOTE_WARMUP_VIEWPORT_WIDTH)
      .height(CUSTOM_HOMEPAGE_REMOTE_WARMUP_VIEWPORT_HEIGHT)
      .backgroundColor(state.tone === 'dark' ? '#000000' : '#FFFFFF')
      .opacity(1)
      .zIndex(-100)
      .hitTestBehavior(HitTestMode.None)
      .darkMode(state.tone === 'dark' ? WebDarkMode.On : WebDarkMode.Off)
      .forceDarkAccess(state.tone === 'dark')
      .javaScriptAccess(true)
      .domStorageAccess(true)
      .databaseAccess(true)
      .imageAccess(true)
      .onlineImageAccess(true)
      .zoomAccess(false)
      .onControllerAttached(() => {
        state.controllerAttached = true;
        this.tryStartTask();
      })
      .onPageEnd((event: OnPageEndEvent) => {
        this.handlePageEnd(state, event.url);
      })
      .onLoadFinished(() => {
        this.handleWebLoaded(state, false);
      })
      .onErrorReceive((event: OnErrorReceiveEvent) => {
        if (event.request.isMainFrame()) {
          this.handleWebLoaded(state, true);
        }
      })
  }

  private tryStartTask(): void {
    const currentTask = this.task;
    if (currentTask === undefined ||
      !this.lightWebState.controllerAttached ||
      !this.darkWebState.controllerAttached ||
      currentTask.id === this.runningTaskId) {
      return;
    }
    this.runningTaskId = currentTask.id;
    this.finishing = false;
    this.resetWebState(this.lightWebState);
    this.resetWebState(this.darkWebState);
    this.cancelTimeout();
    try {
      this.loadWebState(this.lightWebState, currentTask.url);
      this.loadWebState(this.darkWebState, currentTask.url);
      this.timeoutTimer = setTimeout(() => {
        this.finishCurrentTask(!this.hasAnyLoadedWebState());
      }, CUSTOM_HOMEPAGE_REMOTE_WARMUP_TIMEOUT_MS);
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'warmup load failed url=%{public}s error=%{public}s',
        currentTask.url, JSON.stringify(error));
      this.finishCurrentTask(true);
    }
  }

  private loadWebState(state: CustomHomepageRemoteWarmupWebState, url: string): void {
    try {
      state.loading = true;
      state.controller.loadUrl(url);
    } catch (error) {
      state.loading = false;
      state.failed = true;
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'warmup load failed tone=%{public}s url=%{public}s error=%{public}s',
        state.tone, url, JSON.stringify(error));
    }
  }

  private handlePageEnd(state: CustomHomepageRemoteWarmupWebState, pageUrl: string): void {
    if (this.task === undefined || this.finishing || pageUrl.trim().length <= 0) {
      return;
    }
    this.handleWebLoaded(state, false);
  }

  private handleWebLoaded(state: CustomHomepageRemoteWarmupWebState, failed: boolean): void {
    if (this.task === undefined || this.finishing || !state.loading) {
      return;
    }
    state.loading = false;
    state.loaded = !failed;
    state.failed = failed;
    if (!this.lightWebState.loading && !this.darkWebState.loading) {
      this.finishCurrentTask(!this.hasAnyLoadedWebState());
    }
  }

  private finishCurrentTask(failed: boolean): void {
    const currentTask = this.task;
    if (currentTask === undefined || this.finishing) {
      return;
    }
    this.finishing = true;
    this.cancelTimeout();
    void this.finishCurrentTaskAsync(currentTask, failed);
  }

  private async finishCurrentTaskAsync(task: CustomHomepageRemoteWarmupTask, failed: boolean): Promise<void> {
    await this.waitForCaptureSettle();
    let previewResult: CustomHomepageRemoteWarmupPreviewResult = {
      lightUri: '',
      darkUri: ''
    };
    if (!failed) {
      previewResult = await this.capturePreviews(task);
    }
    const resultInput: CustomHomepageRemoteWarmupResultInput = {
      itemId: task.itemId,
      previewUri: previewResult.lightUri.length > 0 ? previewResult.lightUri : previewResult.darkUri,
      previewLightUri: previewResult.lightUri,
      previewDarkUri: previewResult.darkUri,
      previewLightAppearance: previewResult.lightAppearance,
      previewDarkAppearance: previewResult.darkAppearance,
      failed: failed
    };
    this.onFinished(this.coordinator.buildResult(resultInput));
  }

  private async capturePreviews(task: CustomHomepageRemoteWarmupTask): Promise<CustomHomepageRemoteWarmupPreviewResult> {
    const lightResult: CustomHomepageRemoteWarmupPreviewCaptureResult = this.lightWebState.loaded ?
      await this.capturePreview(task, this.lightWebState) :
      this.buildEmptyPreviewCaptureResult();
    const darkResult: CustomHomepageRemoteWarmupPreviewCaptureResult = this.darkWebState.loaded ?
      await this.capturePreview(task, this.darkWebState) :
      this.buildEmptyPreviewCaptureResult();
    return {
      lightUri: lightResult.uri,
      darkUri: darkResult.uri,
      lightAppearance: lightResult.appearance,
      darkAppearance: darkResult.appearance
    };
  }

  private buildEmptyPreviewCaptureResult(): CustomHomepageRemoteWarmupPreviewCaptureResult {
    return {
      uri: ''
    };
  }

  private async capturePreview(
    task: CustomHomepageRemoteWarmupTask,
    state: CustomHomepageRemoteWarmupWebState
  ): Promise<CustomHomepageRemoteWarmupPreviewCaptureResult> {
    const options: BrowserTabPreviewCaptureOptions = {
      uiContext: this.getUIContext() as UIContext,
      componentSnapshotId: this.resolveComponentId(state),
      allowWindowSnapshot: false,
      allowSurfaceSnapshot: true,
      preferVisibleSnapshot: true,
      requireSharedSnapshot: true,
      persistSharedSnapshot: true,
      cacheScopeId: CUSTOM_HOMEPAGE_REMOTE_WARMUP_CACHE_SCOPE_ID,
      sharedSnapshotNormalizeOptions: {
        targetAspectRatio: CUSTOM_HOMEPAGE_REMOTE_WARMUP_PREVIEW_ASPECT_RATIO,
        edgeCropRatio: CUSTOM_HOMEPAGE_REMOTE_WARMUP_EDGE_CROP_RATIO
      }
    };
    for (let attempt = 1; attempt <= CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_ATTEMPTS; attempt += 1) {
      try {
        const captureId = `${task.itemId}-${state.tone}`;
        const result = await this.previewCaptureService.captureWebPage(state.controller, captureId, options);
        const previewUri = result.sharedSnapshotImageUri?.trim() ?? '';
        let appearance = result.snapshot !== undefined ?
          await this.samplePreviewAppearance(task, state, result.snapshot) :
          undefined;
        if (result.snapshot !== undefined) {
          await result.snapshot.release().catch((_error: Error) => {});
        }
        if (previewUri.length > 0) {
          const previewImageAppearance = await this.samplePreviewAppearanceFromImageUri(task, state, previewUri);
          const resolvedAppearance = previewImageAppearance ?? appearance;
          hilog.info(LOG_DOMAIN, LOG_TAG,
            'warmup preview appearance item=%{public}s tone=%{public}s raw=%{public}s image=%{public}s final=%{public}s uri=%{public}s',
            task.itemId,
            state.tone,
            this.resolveAppearanceLogStatus(appearance),
            this.resolveAppearanceLogStatus(previewImageAppearance),
            this.resolveAppearanceLogStatus(resolvedAppearance),
            previewUri);
          return {
            uri: previewUri,
            appearance: resolvedAppearance
          };
        }
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'warmup preview capture empty item=%{public}s tone=%{public}s attempt=%{public}d reason=%{public}s',
          task.itemId, state.tone, attempt, result.failureReason);
      } catch (error) {
        hilog.warn(LOG_DOMAIN, LOG_TAG,
          'warmup preview capture failed item=%{public}s tone=%{public}s attempt=%{public}d error=%{public}s',
          task.itemId, state.tone, attempt, JSON.stringify(error));
      }
      if (attempt < CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_ATTEMPTS) {
        await this.waitForCaptureRetry();
      }
    }
    return {
      uri: ''
    };
  }

  private async samplePreviewAppearance(
    task: CustomHomepageRemoteWarmupTask,
    state: CustomHomepageRemoteWarmupWebState,
    pixelMap: image.PixelMap
  ): Promise<BrowserHomepageBackdropAppearanceState | undefined> {
    return await this.appearanceSamplingService.sample({
      pixelMap: pixelMap,
      sourceKey: `customHomepagePreview:${task.itemId}:${state.tone}:${task.url}`,
      effect: this.buildPreviewAppearanceEffect(state.tone),
      volatileOnly: false
    });
  }

  private async samplePreviewAppearanceFromImageUri(
    task: CustomHomepageRemoteWarmupTask,
    state: CustomHomepageRemoteWarmupWebState,
    previewUri: string
  ): Promise<BrowserHomepageBackdropAppearanceState | undefined> {
    let imageSource: image.ImageSource | undefined = undefined;
    let pixelMap: image.PixelMap | undefined = undefined;
    try {
      const payload = await this.readPreviewImagePayload(previewUri);
      imageSource = image.createImageSource(payload);
      pixelMap = await imageSource.createPixelMap({
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: CUSTOM_HOMEPAGE_REMOTE_WARMUP_APPEARANCE_SAMPLE_WIDTH,
          height: CUSTOM_HOMEPAGE_REMOTE_WARMUP_APPEARANCE_SAMPLE_HEIGHT
        }
      });
      return await this.appearanceSamplingService.sample({
        pixelMap: pixelMap,
        sourceKey: `customHomepagePreviewImage:${task.itemId}:${state.tone}:${previewUri}`,
        effect: this.buildPreviewAppearanceEffect(state.tone),
        volatileOnly: false
      });
    } catch (error) {
      hilog.warn(LOG_DOMAIN, LOG_TAG,
        'warmup preview appearance image sample failed item=%{public}s tone=%{public}s error=%{public}s',
        task.itemId, state.tone, JSON.stringify(error));
      return undefined;
    } finally {
      if (pixelMap !== undefined) {
        await pixelMap.release().catch((_error: Error) => {});
      }
      if (imageSource !== undefined) {
        await imageSource.release().catch((_error: Error) => {});
      }
    }
  }

  private async readPreviewImagePayload(previewUri: string): Promise<ArrayBuffer> {
    const path = new fileUri.FileUri(previewUri).path;
    const stat = await fileIo.stat(path);
    if (stat.isDirectory() || stat.size <= 0 ||
      stat.size > CUSTOM_HOMEPAGE_REMOTE_WARMUP_APPEARANCE_IMAGE_MAX_BYTES) {
      throw new Error('preview-image-size');
    }
    const file = await fileIo.open(path, fileIo.OpenMode.READ_ONLY);
    try {
      const data = new ArrayBuffer(Math.max(1, Math.floor(stat.size)));
      const readLength = await fileIo.read(file.fd, data);
      if (readLength <= 0) {
        throw new Error('preview-image-read');
      }
      return data;
    } finally {
      await fileIo.close(file);
    }
  }

  private buildPreviewAppearanceEffect(
    tone: CustomHomepageRemotePreviewTone
  ): BrowserHomepageBackdropAppearanceEffectInput {
    const resolvedThemeMode = tone === 'dark' ? 'dark' : 'light';
    return {
      resolvedThemeMode: resolvedThemeMode,
      tintColor: '#000000',
      tintOpacity: 0,
      effectSignature: `custom-homepage-preview:v1:${resolvedThemeMode}`
    };
  }

  private resolveAppearanceLogStatus(appearance: BrowserHomepageBackdropAppearanceState | undefined): string {
    if (appearance === undefined) {
      return 'missing';
    }
    return appearance.available ? `available:${appearance.toolbarForegroundTone}` : 'unavailable';
  }

  private async waitForCaptureSettle(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_SETTLE_MS);
    });
  }

  private async waitForCaptureRetry(): Promise<void> {
    await new Promise<void>((resolve: () => void) => {
      setTimeout(() => {
        resolve();
      }, CUSTOM_HOMEPAGE_REMOTE_WARMUP_CAPTURE_RETRY_MS);
    });
  }

  private cancelTimeout(): void {
    if (this.timeoutTimer >= 0) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
  }

  private resetWebState(state: CustomHomepageRemoteWarmupWebState): void {
    state.loading = false;
    state.loaded = false;
    state.failed = false;
  }

  private hasAnyLoadedWebState(): boolean {
    return this.lightWebState.loaded || this.darkWebState.loaded;
  }

  private resolveComponentId(state: CustomHomepageRemoteWarmupWebState): string {
    const baseId = state.tone === 'dark' ?
      CUSTOM_HOMEPAGE_REMOTE_WARMUP_DARK_COMPONENT_ID :
      CUSTOM_HOMEPAGE_REMOTE_WARMUP_LIGHT_COMPONENT_ID;
    return `${baseId}-${this.normalizeHostIdPrefix()}`;
  }

  private normalizeHostIdPrefix(): string {
    const normalized = this.hostIdPrefix.trim().replace(/[^A-Za-z0-9_-]/g, '-');
    return normalized.length > 0 ? normalized : 'default';
  }

}
