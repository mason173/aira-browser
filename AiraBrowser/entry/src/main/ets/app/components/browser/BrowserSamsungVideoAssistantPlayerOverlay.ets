import { common } from '@kit.AbilityKit';
import vibrator from '@ohos.vibrator';
import {
  BrowserArkWebMediaAssistantPlayerAction,
  BrowserArkWebMediaWebLiveCommand
} from '../../../core/browser/media/BrowserArkWebMediaTakeoverCoordinator';
import { BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY } from '../../../core/browser/BrowserWindowAvoidAreaCoordinator';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import { BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import {
  createInactiveVideoAssistantState,
  VideoAssistantScaleMode,
  VideoAssistantState
} from '../../../features/videoAssistant/VideoAssistantModels';
import {
  WebVideoSystemControlKind,
  WebVideoSystemControlService
} from '../../../services/video/WebVideoSystemControlService';
import {
  BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
} from './BrowserFloatingGlassMaterialTokens';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';

const SAMSUNG_PLAYER_TITLE_HEIGHT: number = 64;
const SAMSUNG_PLAYER_TITLE_HORIZONTAL_INSET: number = 24;
const SAMSUNG_PLAYER_TITLE_TEXT_SIZE: number = 21;
const SAMSUNG_PLAYER_TITLE_MIN_TOP_INSET: number = 16;
const SAMSUNG_PLAYER_TITLE_SAFE_TOP_GAP: number = 4;
const SAMSUNG_PLAYER_TITLE_BUTTON_GAP: number = 8;
const SAMSUNG_PLAYER_BACK_BUTTON_SIZE: number = 40;
const SAMSUNG_PLAYER_BACK_ICON_SIZE: number = 22;
const SAMSUNG_PLAYER_CENTER_PLAY_SIZE: number = 54;
const SAMSUNG_PLAYER_SEEK_BUTTON_SIZE: number = 36;
const SAMSUNG_PLAYER_CENTER_CONTROL_GAP: number = 35;
const SAMSUNG_PLAYER_PORTRAIT_PROGRESS_HEIGHT: number = 72;
const SAMSUNG_PLAYER_LANDSCAPE_PROGRESS_HEIGHT: number = 48;
const SAMSUNG_PLAYER_PORTRAIT_FEATURE_HEIGHT: number = 64;
const SAMSUNG_PLAYER_LANDSCAPE_FEATURE_HEIGHT: number = 52;
const SAMSUNG_PLAYER_PORTRAIT_BOTTOM_INSET: number = 12;
const SAMSUNG_PLAYER_LANDSCAPE_BOTTOM_INSET: number = 8;
const SAMSUNG_PLAYER_PORTRAIT_SECTION_GAP: number = 16;
const SAMSUNG_PLAYER_LANDSCAPE_SECTION_GAP: number = 10;
const SAMSUNG_PLAYER_PROGRESS_HORIZONTAL_INSET: number = 28;
const SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE: number = 24;
const SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE: number = 40;
const SAMSUNG_PLAYER_SPEED_DIALOG_MAX_WIDTH: number = 280;
const SAMSUNG_PLAYER_SPEED_DIALOG_MAX_HEIGHT: number = 336;
const SAMSUNG_PLAYER_SPEED_DIALOG_EDGE_INSET: number = 24;
const SAMSUNG_PLAYER_SPEED_DIALOG_HEADER_HEIGHT: number = 50;
const SAMSUNG_PLAYER_SPEED_DIALOG_ROW_HEIGHT: number = 48;
const SAMSUNG_PLAYER_SPEED_DIALOG_CORNER_RADIUS: number = 20;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_WIDTH: number = 64;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_MAX_HEIGHT: number = 190;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_MIN_HEIGHT: number = 132;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_CENTER_GAP: number = 24;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_VERTICAL_INSET: number = 32;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_RADIUS: number = 32;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_SIZE: number = 24;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_BOTTOM_INSET: number = 15;
const SAMSUNG_PLAYER_SURFACE_PAN_DISTANCE: number = 8;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_DRAG_RANGE: number = 360;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_APPLY_INTERVAL_MS: number = 48;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_DISMISS_MS: number = 720;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_ROTATION_DEGREES: number = 360;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_HAPTIC_STEP_COUNT: number = 20;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_HAPTIC_DURATION_MS: number = 8;
const SAMSUNG_PLAYER_SYSTEM_CONTROL_HAPTIC_MIN_INTERVAL_MS: number = 42;
const SAMSUNG_PLAYER_CONTROLS_AUTO_HIDE_MS: number = 3000;
const SAMSUNG_PLAYER_LOADING_INDICATOR_DELAY_MS: number = 150;
const SAMSUNG_PLAYER_MOUSE_POKE_THROTTLE_MS: number = 400;
const SAMSUNG_PLAYER_MOUSE_MOVE_MIN_DISTANCE: number = 3;
const SAMSUNG_PLAYER_SEEK_STEP_SECONDS: number = 10;
const SAMSUNG_PLAYER_CENTER_PLAY_ICON_SIZE: number = 42;
const SAMSUNG_PLAYER_SEEK_ICON_SIZE: number = 32;
const SAMSUNG_PLAYER_SEEK_GESTURE_MIN_RANGE_SECONDS: number = 60;
const SAMSUNG_PLAYER_SEEK_GESTURE_MAX_RANGE_SECONDS: number = 300;
const SAMSUNG_PLAYER_SEEK_GESTURE_DURATION_FACTOR: number = 0.25;
const SAMSUNG_PLAYER_SEEK_GESTURE_INDICATOR_WIDTH: number = 236;
const SAMSUNG_PLAYER_SEEK_GESTURE_INDICATOR_HEIGHT: number = 60;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_LONG_PRESS_MS: number = 450;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MAX_RATE: number = 10;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MIN_RATE: number = 0.25;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_RATE_STEP: number = 0.1;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_RATE_STEP_DISTANCE: number = 24;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_WIDTH: number = 220;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_HEIGHT: number = 58;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_TOP_INSET: number = 24;
const SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_RADIUS: number = 29;
const SAMSUNG_PLAYER_SPEED_OPTIONS: number[] = [
  0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0, 4.0, 5.0
];

@Component
export struct BrowserSamsungVideoAssistantPlayerOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedSpeedDialogTextColor: string = '#111318';
  @LocalStorageProp(BROWSER_WINDOW_SAFE_TOP_INSET_STORAGE_KEY) private storedTopSafeInsetVp: number = 0;
  @Prop @Watch('handlePlayerStateChange') playerState: VideoAssistantState =
    createInactiveVideoAssistantState();
  @Prop playerBackgroundColor: ResourceColor = '';
  @Prop playerControlColor: ResourceColor = '';
  @Prop playerControlScrimColor: ResourceColor = '';
  @Prop playerProgressTrackColor: ResourceColor = '';
  @Prop playerTransparentColor: ResourceColor = '';
  @Prop webLiveTransitionPending: boolean = false;
  private controlsHideTimer: number = -1;
  private controlsHideGeneration: number = 0;
  private loadingIndicatorTimer: number = -1;
  private loadingIndicatorGeneration: number = 0;
  private systemControlService: WebVideoSystemControlService = new WebVideoSystemControlService();
  private systemControlTouchStartX: number = -1;
  private systemControlDragStartValue: number = 0;
  private systemControlLastAppliedAt: number = 0;
  private systemControlLastHapticStep: number = -1;
  private systemControlLastHapticAt: number = 0;
  private systemControlDismissTimer: number = -1;
  private systemControlDismissGeneration: number = 0;
  private surfacePanMode: 'pending' | 'seek' | 'system_control' | 'temporary_speed' | '' = '';
  private screenSeekDragStartPositionSeconds: number = 0;
  private temporaryFastPlaybackRestoreRate: number = 1.0;
  private temporaryFastPlaybackDragStartRate: number = 1.0;
  private mouseMoveAnchorX: number = -1;
  private mouseMoveAnchorY: number = -1;
  private mouseControlsPokeAt: number = 0;
  @State private stageWidth: number = 0;
  @State private stageHeight: number = 0;
  @State private controlsVisible: boolean = true;
  @State private loadingIndicatorVisible: boolean = false;
  @State private controlsLocked: boolean = false;
  @State private scrubberActive: boolean = false;
  @State private scrubberPositionSeconds: number = 0;
  @State private playbackSpeedRate: number = 1.0;
  @State private speedPanelVisible: boolean = false;
  @State private videoScaleMode: VideoAssistantScaleMode = 'contain';
  @State private systemControlGestureKind: WebVideoSystemControlKind | '' = '';
  @State private systemControlGestureValue: number = 0;
  @State private systemControlIconRotationAngle: number = 0;
  @State private screenSeekGestureActive: boolean = false;
  @State private screenSeekDeltaSeconds: number = 0;
  @State private temporaryFastPlaybackActive: boolean = false;
  @State private temporaryFastPlaybackRate: number = 1.0;
  onAction: (action: BrowserArkWebMediaAssistantPlayerAction) => void =
    (_action: BrowserArkWebMediaAssistantPlayerAction): void => {};

  aboutToAppear(): void {
    this.warmSystemControlValues();
    this.syncLoadingIndicatorVisibility();
    this.showControlsTemporarily();
  }

  aboutToDisappear(): void {
    this.endTemporaryFastPlayback(false);
    this.clearControlsHideTimer();
    this.clearLoadingIndicatorTimer();
    this.clearSystemControlDismissTimer();
    this.surfacePanMode = '';
    this.screenSeekGestureActive = false;
    this.scrubberActive = false;
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.buildVideoStage()
      if (!this.webLiveTransitionPending) {
        this.buildTouchLayer()
      }
      if (!this.webLiveTransitionPending && this.shouldShowFullControls()) {
        this.buildBottomControlScrim()
        this.buildProgressLayer()
        if (!this.screenSeekGestureActive) {
          this.buildTopFeatureLayer()
          if (!this.isPlayerLoading()) {
            this.buildCenterMediaControls()
          }
          this.buildBottomFeatureLayer()
          if (this.speedPanelVisible) {
            this.buildPlaybackSpeedDialogBackdrop()
            this.buildPlaybackSpeedPanel()
          }
        }
      } else if (!this.webLiveTransitionPending && this.controlsLocked && this.controlsVisible) {
        this.buildLockedControl()
      }
      if (!this.webLiveTransitionPending && this.loadingIndicatorVisible) {
        this.buildBufferingState()
      }
      if (!this.webLiveTransitionPending && this.playerState.playbackStatus === 'error') {
        this.buildErrorState()
      }
      if (!this.webLiveTransitionPending && this.systemControlGestureKind.length > 0) {
        this.buildSystemControlIndicator()
      }
      if (!this.webLiveTransitionPending && this.screenSeekGestureActive) {
        this.buildScreenSeekIndicator()
      }
      if (!this.webLiveTransitionPending && this.temporaryFastPlaybackActive) {
        this.buildTemporaryFastPlaybackIndicator()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolvePlayerStageBackground())
    .hitTestBehavior(HitTestMode.BLOCK_HIERARCHY)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.stageWidth = Math.max(0, Math.round(this.parseAreaDimension(newArea.width)));
      this.stageHeight = Math.max(0, Math.round(this.parseAreaDimension(newArea.height)));
    })
    .onMouse((event: MouseEvent) => {
      this.handleMouseActivity(event);
    })
  }

  @Builder
  private buildVideoStage() {
    Stack({ alignContent: Alignment.Center }) {
      Stack()
        .width('100%')
        .height('100%')
        .backgroundColor(this.resolvePlayerStageBackground())
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolvePlayerStageBackground())
    .hitTestBehavior(HitTestMode.None)
  }

  @Builder
  private buildTouchLayer() {
    Stack()
      .width('100%')
      .height('100%')
      .backgroundColor(this.playerTransparentColor)
      .hitTestBehavior(HitTestMode.Default)
      .onTouch((event: TouchEvent) => {
        this.rememberSystemControlTouchStart(event);
      })
      .gesture(
        GestureGroup(
          GestureMode.Parallel,
          PanGesture({
            direction: PanDirection.All,
            distance: SAMSUNG_PLAYER_SURFACE_PAN_DISTANCE
          })
            .onActionStart(() => {
              this.beginSurfacePanGesture();
            })
            .onActionUpdate((event: GestureEvent) => {
              this.updateSurfacePanGesture(event);
            })
            .onActionEnd((event: GestureEvent) => {
              this.endSurfacePanGesture(event);
            })
            .onActionCancel(() => {
              this.cancelSurfacePanGesture();
            }),
          LongPressGesture({
            fingers: 1,
            repeat: false,
            duration: SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_LONG_PRESS_MS
          })
            .onAction(() => {
              this.beginTemporaryFastPlayback();
            })
            .onActionEnd(() => {
              this.endTemporaryFastPlayback();
            })
            .onActionCancel(() => {
              this.endTemporaryFastPlayback();
            }),
          GestureGroup(
            GestureMode.Exclusive,
            TapGesture({ count: 2, fingers: 1 })
              .onAction(() => {
                this.togglePlayback();
              }),
            TapGesture({ count: 1, fingers: 1 })
              .onAction(() => {
                this.toggleControls();
              })
          )
        ),
        GestureMask.Normal
      )
      .zIndex(2)
  }

  @Builder
  private buildSystemControlIndicator() {
    Stack() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: SAMSUNG_PLAYER_SYSTEM_CONTROL_WIDTH,
        surfaceHeight: this.resolveSystemControlIndicatorHeight(),
        surfaceRadius: SAMSUNG_PLAYER_SYSTEM_CONTROL_RADIUS,
        tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
      }) {
        Stack({ alignContent: Alignment.Bottom }) {
          Stack()
            .width('100%')
            .height(this.resolveSystemControlFillHeight())
            .backgroundColor(this.playerControlColor)
            .hitTestBehavior(HitTestMode.None)

          Stack({ alignContent: Alignment.Center }) {
            AiraIcon({
              airaIconId: this.resolveSystemControlIcon(),
              iconSize: SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_SIZE,
              iconColor: $r('app.color.browser_video_assistant_system_control_icon')
            })
          }
          .width(SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_SIZE)
          .height(SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_SIZE)
          .rotate({ angle: this.resolveSystemControlIconRotationAngle() })
          .position({
            x: (SAMSUNG_PLAYER_SYSTEM_CONTROL_WIDTH - SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_SIZE) / 2,
            y: this.resolveSystemControlIndicatorHeight() - SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_SIZE -
              SAMSUNG_PLAYER_SYSTEM_CONTROL_ICON_BOTTOM_INSET
          })
          .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width(SAMSUNG_PLAYER_SYSTEM_CONTROL_WIDTH)
    .height(this.resolveSystemControlIndicatorHeight())
    .borderRadius(SAMSUNG_PLAYER_SYSTEM_CONTROL_RADIUS)
    .position({
      x: this.resolveSystemControlIndicatorLeft(),
      y: Math.max(0, (this.stageHeight - this.resolveSystemControlIndicatorHeight()) / 2)
    })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(12)
  }

  @Builder
  private buildScreenSeekIndicator() {
    Text(`${this.formatSeconds(this.scrubberPositionSeconds)} / ${this.formatSeconds(this.resolveDurationSeconds())}`)
      .fontSize(24)
      .fontWeight(FontWeight.Bold)
      .fontColor(this.playerControlColor)
      .maxLines(1)
    .width(SAMSUNG_PLAYER_SEEK_GESTURE_INDICATOR_WIDTH)
    .height(SAMSUNG_PLAYER_SEEK_GESTURE_INDICATOR_HEIGHT)
    .textAlign(TextAlign.Center)
    .textVerticalAlign(TextVerticalAlign.CENTER)
    .position({
      x: Math.max(0, (this.stageWidth - SAMSUNG_PLAYER_SEEK_GESTURE_INDICATOR_WIDTH) / 2),
      y: Math.max(0, (this.stageHeight - SAMSUNG_PLAYER_SEEK_GESTURE_INDICATOR_HEIGHT) / 2)
    })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(13)
  }

  @Builder
  private buildTemporaryFastPlaybackIndicator() {
    Stack() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_WIDTH,
        surfaceHeight: SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_HEIGHT,
        surfaceRadius: SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_RADIUS,
        tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
      }) {
        Column({ space: 2 }) {
          Text(`${this.formatPlaybackSpeed(this.temporaryFastPlaybackRate)} 倍速播放中`)
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.playerControlColor)
            .maxLines(1)

          Text('左右滑动可微调速度')
            .fontSize(11)
            .fontWeight(FontWeight.Regular)
            .fontColor(this.playerControlColor)
            .opacity(0.72)
            .maxLines(1)
        }
        .width('100%')
        .height('100%')
        .padding({ left: 18, right: 18, top: 8, bottom: 8 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width(SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_WIDTH)
    .height(SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_HEIGHT)
    .borderRadius(SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_RADIUS)
    .position({
      x: Math.max(0, (this.stageWidth - SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_WIDTH) / 2),
      y: SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_INDICATOR_TOP_INSET
    })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(14)
  }

  @Builder
  private buildBottomControlScrim() {
    Column() {
    }
    .width('100%')
    .height(this.resolveBottomScrimHeight())
    .linearGradient({
      angle: 0,
      colors: [[this.playerControlScrimColor, 0], [this.playerTransparentColor, 1]]
    })
    .position({ x: 0, y: this.resolveProgressLayerTop() })
    .hitTestBehavior(HitTestMode.None)
    .zIndex(4)
  }

  @Builder
  private buildTopFeatureLayer() {
    Row({ space: SAMSUNG_PLAYER_TITLE_BUTTON_GAP }) {
      this.buildPlayerGlassIconButton(
        'browser.toolbar.back',
        SAMSUNG_PLAYER_BACK_ICON_SIZE,
        SAMSUNG_PLAYER_BACK_BUTTON_SIZE,
        '返回网页',
        () => {
        this.closePlayer();
        }
      )

      Text(this.resolvePlayerTitle())
        .fontSize(SAMSUNG_PLAYER_TITLE_TEXT_SIZE)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.playerControlColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .height(this.resolveTopFeatureLayerHeight())
    .padding({
      left: SAMSUNG_PLAYER_TITLE_HORIZONTAL_INSET,
      right: 20,
      top: this.resolveTitleTopInset()
    })
    .alignItems(VerticalAlign.Center)
    .linearGradient({
      angle: 180,
      colors: [[this.playerControlScrimColor, 0], [this.playerTransparentColor, 1]]
    })
    .position({ x: 0, y: 0 })
    .zIndex(5)
  }

  @Builder
  private buildCenterMediaControls() {
    Row({ space: SAMSUNG_PLAYER_CENTER_CONTROL_GAP }) {
      this.buildTenSecondSeekButton(false)

      this.buildPlayerGlassIconButton(
        this.isPlaying() ? 'videoAssistant.pause' : 'videoAssistant.play',
        SAMSUNG_PLAYER_CENTER_PLAY_ICON_SIZE,
        SAMSUNG_PLAYER_CENTER_PLAY_SIZE,
        this.isPlaying() ? '暂停' : '播放',
        () => {
          this.togglePlayback();
        }
      )

      this.buildTenSecondSeekButton(true)
    }
    .alignItems(VerticalAlign.Center)
    .position({
      x: this.resolveCenterControlsLeft(),
      y: this.resolveCenterControlsTop()
    })
    .zIndex(6)
  }

  @Builder
  private buildTenSecondSeekButton(forward: boolean) {
    this.buildPlayerGlassIconButton(
      forward ? 'videoAssistant.seekForward10' : 'videoAssistant.seekBackward10',
      SAMSUNG_PLAYER_SEEK_ICON_SIZE,
      SAMSUNG_PLAYER_SEEK_BUTTON_SIZE,
      forward ? '快进 10 秒' : '后退 10 秒',
      () => {
        this.seekBySeconds(forward ? SAMSUNG_PLAYER_SEEK_STEP_SECONDS : -SAMSUNG_PLAYER_SEEK_STEP_SECONDS);
      }
    )
  }

  @Builder
  private buildProgressLayer() {
    if (this.isLandscape()) {
      Row({ space: 10 }) {
        Text(this.formatSeconds(this.resolveDisplayPositionSeconds()))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.playerControlColor)
          .maxLines(1)

        this.buildTimeline()

        Text(this.formatSeconds(this.resolveDurationSeconds()))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.playerControlColor)
          .maxLines(1)
      }
      .width('100%')
      .height(SAMSUNG_PLAYER_LANDSCAPE_PROGRESS_HEIGHT)
      .padding({
        left: SAMSUNG_PLAYER_PROGRESS_HORIZONTAL_INSET,
        right: SAMSUNG_PLAYER_PROGRESS_HORIZONTAL_INSET,
        top: 4,
        bottom: 4
      })
      .alignItems(VerticalAlign.Center)
      .position({ x: 0, y: this.resolveProgressLayerTop() })
      .zIndex(5)
    } else {
      Column({ space: 6 }) {
        Row() {
          Text(this.formatSeconds(this.resolveDisplayPositionSeconds()))
            .fontSize(12)
            .fontColor(this.playerControlColor)
            .maxLines(1)
          Blank()
          Text(this.formatSeconds(this.resolveDurationSeconds()))
            .fontSize(12)
            .fontColor(this.playerControlColor)
            .maxLines(1)
        }
        .width('100%')

        this.buildTimeline()
      }
      .width('100%')
      .height(SAMSUNG_PLAYER_PORTRAIT_PROGRESS_HEIGHT)
      .padding({
        left: SAMSUNG_PLAYER_PROGRESS_HORIZONTAL_INSET,
        right: SAMSUNG_PLAYER_PROGRESS_HORIZONTAL_INSET,
        top: 4,
        bottom: 4
      })
      .position({ x: 0, y: this.resolveProgressLayerTop() })
      .zIndex(5)
    }
  }

  @Builder
  private buildTimeline() {
    Slider({
      value: this.resolveTimelineValue(),
      min: 0,
      max: Math.max(1, this.resolveDurationSeconds()),
      step: 1,
      style: SliderStyle.OutSet
    })
      .layoutWeight(1)
      .height(22)
      .selectedColor(this.playerControlColor)
      .blockColor(this.playerControlColor)
      .trackColor(this.playerProgressTrackColor)
      .onChange((value: number, mode: SliderChangeMode) => {
        this.handleTimelineChange(value, mode);
      })
  }

  @Builder
  private buildBottomFeatureLayer() {
    Row() {
      this.buildPlayerGlassIconButton(
        'videoAssistant.control.aspectRatio',
        SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE,
        SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE,
        '切换画面比例',
        () => {
          this.cycleVideoScaleMode();
        }
      )

      this.buildPlayerGlassIconButton(
        'settings.downloads',
        SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE,
        SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE,
        '下载当前视频',
        () => {
          this.speedPanelVisible = false;
          this.onAction({ type: 'download' });
          this.showControlsTemporarily();
        }
      )

      this.buildPlayerGlassIconButton(
        'videoAssistant.control.playbackSpeed',
        SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE,
        SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE,
        '播放速度',
        () => {
          this.togglePlaybackSpeedPanel();
        }
      )

      this.buildPlayerGlassIconButton(
        'videoAssistant.control.rotate',
        SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE,
        SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE,
        '旋转画面',
        () => {
          this.requestRotate();
        }
      )

      this.buildPlayerGlassIconButton(
        'videoAssistant.unlock',
        SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE,
        SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE,
        '锁定播放器控制',
        () => {
          this.controlsLocked = true;
          this.controlsVisible = true;
          this.speedPanelVisible = false;
          this.scheduleControlsHideIfIdle(true);
        }
      )
    }
    .width('100%')
    .height(this.resolveBottomControlRegionHeight())
    .padding({ left: this.resolveBottomFeatureInset(), right: this.resolveBottomFeatureInset() })
    .alignItems(VerticalAlign.Center)
    .justifyContent(FlexAlign.SpaceAround)
    .position({ x: 0, y: this.resolveBottomControlRegionTop() })
    .zIndex(7)
  }

  @Builder
  private buildPlayerGlassIconButton(
    iconId: AiraRenderableIconId,
    iconSize: number,
    buttonSize: number,
    accessibilityLabel: string,
    action: () => void
  ) {
    Stack({ alignContent: Alignment.Center }) {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: buttonSize,
        surfaceHeight: buttonSize,
        surfaceRadius: buttonSize / 2,
        tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
      }) {
        AiraIcon({
          airaIconId: iconId,
          iconSize: iconSize,
          iconColor: this.playerControlColor
        })
        .hitTestBehavior(HitTestMode.None)
      }

      Button({ type: ButtonType.Circle })
        .width('100%')
        .height('100%')
        .backgroundColor(this.playerTransparentColor)
        .accessibilityText(accessibilityLabel)
        .onClick(() => {
          action();
        })
    }
    .width(buttonSize)
    .height(buttonSize)
    .borderRadius(buttonSize / 2)
  }

  @Builder
  private buildPlaybackSpeedDialogBackdrop() {
    Column() {
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.playerBackgroundColor)
    .opacity(0.42)
    .position({ x: 0, y: 0 })
    .onClick(() => {
      this.closePlaybackSpeedPanel();
    })
    .zIndex(8)
  }

  @Builder
  private buildPlaybackSpeedPanel() {
    Stack() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: this.resolvePlaybackSpeedPanelWidth(),
        surfaceHeight: this.resolvePlaybackSpeedPanelHeight(),
        surfaceRadius: SAMSUNG_PLAYER_SPEED_DIALOG_CORNER_RADIUS,
        tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
      }) {
        Column() {
          Row() {
            Text('播放速度')
              .fontSize(17)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedSpeedDialogTextColor)
          }
          .width('100%')
          .height(SAMSUNG_PLAYER_SPEED_DIALOG_HEADER_HEIGHT)
          .padding({ left: 20, right: 20 })
          .alignItems(VerticalAlign.Center)

          Scroll() {
            Column() {
              ForEach(SAMSUNG_PLAYER_SPEED_OPTIONS, (rate: number) => {
                this.buildPlaybackSpeedChoiceRow(rate)
              }, (rate: number) => rate.toString())
            }
            .width('100%')
          }
          .width('100%')
          .layoutWeight(1)
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Auto)
        }
        .width('100%')
        .height('100%')
      }
    }
    .width(this.resolvePlaybackSpeedPanelWidth())
    .height(this.resolvePlaybackSpeedPanelHeight())
    .borderRadius(SAMSUNG_PLAYER_SPEED_DIALOG_CORNER_RADIUS)
    .position({
      x: this.resolvePlaybackSpeedPanelLeft(),
      y: this.resolvePlaybackSpeedPanelTop()
    })
    .zIndex(9)
  }

  @Builder
  private buildPlaybackSpeedChoiceRow(rate: number) {
    Row() {
      Text(this.formatPlaybackSpeedChoice(rate))
        .fontSize(16)
        .fontWeight(rate === this.playbackSpeedRate ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.storedSpeedDialogTextColor)
        .layoutWeight(1)

      if (rate === this.playbackSpeedRate) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.storedSpeedDialogTextColor])
          .hitTestBehavior(HitTestMode.None)
      }
    }
    .width('100%')
    .height(SAMSUNG_PLAYER_SPEED_DIALOG_ROW_HEIGHT)
    .padding({ left: 20, right: 16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.playerTransparentColor)
    .onClick(() => {
      this.selectPlaybackSpeed(rate);
    })
  }

  @Builder
  private buildLockedControl() {
    Stack() {
      this.buildPlayerGlassIconButton(
        'videoAssistant.lock',
        SAMSUNG_PLAYER_FEATURE_BUTTON_SIZE,
        SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE,
        '解锁播放器控制',
        () => {
          this.controlsLocked = false;
          this.showControlsTemporarily();
        }
      )
    }
    .width(SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE)
    .height(SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE)
    .position({
      x: Math.max(0, this.stageWidth - SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE - this.resolveBottomFeatureInset()),
      y: Math.max(0, this.resolveBottomControlRegionTop() +
        (this.resolveBottomControlRegionHeight() - SAMSUNG_PLAYER_FEATURE_TOUCH_SIZE) / 2)
    })
    .zIndex(8)
  }

  @Builder
  private buildBufferingState() {
    LoadingProgress()
      .width(40)
      .height(40)
      .color(this.playerControlColor)
      .position({
        x: Math.max(0, (this.stageWidth - 40) / 2),
        y: Math.max(0, (this.stageHeight - 40) / 2)
      })
      .hitTestBehavior(HitTestMode.None)
      .zIndex(9)
  }

  @Builder
  private buildErrorState() {
    Stack() {
      BrowserFloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: '100%',
        surfaceRadius: 20,
        tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
      }) {
        Column({ space: 14 }) {
          SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
            .fontSize(32)
            .fontColor([this.playerControlColor])
          Text(this.playerState.errorMessage.length > 0 ? this.playerState.errorMessage : '视频打开失败。')
            .fontSize(14)
            .fontColor(this.playerControlColor)
            .textAlign(TextAlign.Center)
            .maxLines(3)

          Stack({ alignContent: Alignment.Center }) {
            BrowserFloatingGlassMaterialSurface({
              surfaceWidth: 88,
              surfaceHeight: 40,
              surfaceRadius: 20,
              tintColor: BROWSER_FLOATING_GLASS_MATERIAL_DARK_TINT
            }) {
              Text('关闭')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.playerControlColor)
                .hitTestBehavior(HitTestMode.None)
            }

            Button({ type: ButtonType.Capsule })
              .width('100%')
              .height('100%')
              .backgroundColor(this.playerTransparentColor)
              .accessibilityText('关闭视频播放器')
              .onClick(() => {
                this.onAction({ type: 'close' });
              })
          }
          .width(88)
          .height(40)
          .borderRadius(20)
        }
        .width('100%')
        .height('100%')
        .padding(20)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('78%')
    .height(170)
    .constraintSize({ maxWidth: 360 })
    .borderRadius(20)
    .position({
      x: Math.max(0, this.stageWidth * 0.11),
      y: Math.max(0, (this.stageHeight - 170) / 2)
    })
    .zIndex(10)
  }

  private handlePlayerStateChange(): void {
    this.syncLoadingIndicatorVisibility();
    if (this.temporaryFastPlaybackActive && this.playerState.playbackStatus !== 'playing') {
      this.endTemporaryFastPlayback(false);
    }
    if (this.isPlayerLoading() || this.playerState.playbackStatus === 'error') {
      this.controlsVisible = true;
      this.clearControlsHideTimer();
      return;
    }
    if (this.playerState.playbackStatus === 'paused' || this.playerState.playbackStatus === 'ended') {
      this.showControlsTemporarily();
      return;
    }
    this.scheduleControlsHideIfIdle(false);
  }

  private warmSystemControlValues(): void {
    try {
      const context = this.getAbilityContext();
      this.systemControlService.read(context, 'brightness');
      this.systemControlService.read(context, 'volume');
    } catch (_error) {
    }
  }

  private rememberSystemControlTouchStart(event: TouchEvent): void {
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.endTemporaryFastPlayback();
      return;
    }
    if (event.type !== TouchType.Down) {
      return;
    }
    if (event.touches.length > 0) {
      this.systemControlTouchStartX = Number(event.touches[0].x);
      return;
    }
    if (event.changedTouches.length > 0) {
      this.systemControlTouchStartX = Number(event.changedTouches[0].x);
      return;
    }
    this.systemControlTouchStartX = -1;
  }

  private beginSurfacePanGesture(): void {
    this.surfacePanMode = 'pending';
  }

  private updateSurfacePanGesture(event: GestureEvent): void {
    if (this.temporaryFastPlaybackActive) {
      this.surfacePanMode = 'temporary_speed';
      this.updateTemporaryFastPlaybackRate(event);
      return;
    }
    if (this.surfacePanMode === 'pending') {
      const nextMode = this.resolveSurfacePanMode(event);
      if (nextMode === 'seek') {
        this.surfacePanMode = this.beginScreenSeekGesture() ? 'seek' : '';
      } else if (nextMode === 'system_control') {
        this.beginSystemControlGesture();
        this.surfacePanMode = this.systemControlGestureKind.length > 0 ? 'system_control' : '';
      }
    }
    if (this.surfacePanMode === 'seek') {
      this.updateScreenSeekGesture(event);
    } else if (this.surfacePanMode === 'system_control') {
      this.updateSystemControlGesture(event);
    }
  }

  private endSurfacePanGesture(event: GestureEvent): void {
    if (this.temporaryFastPlaybackActive) {
      this.updateTemporaryFastPlaybackRate(event);
      this.surfacePanMode = '';
      return;
    }
    if (this.surfacePanMode === 'pending') {
      this.updateSurfacePanGesture(event);
    }
    if (this.surfacePanMode === 'seek') {
      this.updateScreenSeekGesture(event);
      this.endScreenSeekGesture();
    } else if (this.surfacePanMode === 'system_control') {
      this.endSystemControlGesture(event);
    }
    this.surfacePanMode = '';
  }

  private cancelSurfacePanGesture(): void {
    if (this.surfacePanMode === 'seek') {
      this.cancelScreenSeekGesture();
    } else if (this.surfacePanMode === 'system_control') {
      this.cancelSystemControlGesture();
    }
    this.surfacePanMode = '';
  }

  private resolveSurfacePanMode(event: GestureEvent): 'seek' | 'system_control' | '' {
    const offsetX = Number(event.offsetX);
    const offsetY = Number(event.offsetY);
    if (!Number.isFinite(offsetX) || !Number.isFinite(offsetY)) {
      return '';
    }
    const horizontalDistance = Math.abs(offsetX);
    const verticalDistance = Math.abs(offsetY);
    if (horizontalDistance <= 0 && verticalDistance <= 0) {
      return '';
    }
    return horizontalDistance >= verticalDistance ? 'seek' : 'system_control';
  }

  private beginScreenSeekGesture(): boolean {
    const duration = this.resolveDurationSeconds();
    if (this.controlsLocked || duration <= 0 || this.stageWidth <= 0) {
      return false;
    }
    this.clearControlsHideTimer();
    this.clearSystemControlDismissTimer();
    this.systemControlGestureKind = '';
    this.speedPanelVisible = false;
    this.controlsVisible = true;
    this.screenSeekDragStartPositionSeconds = this.clampSeconds(this.resolveDisplayPositionSeconds());
    this.scrubberPositionSeconds = this.screenSeekDragStartPositionSeconds;
    this.screenSeekDeltaSeconds = 0;
    this.screenSeekGestureActive = true;
    this.scrubberActive = true;
    return true;
  }

  private updateScreenSeekGesture(event: GestureEvent): void {
    if (!this.screenSeekGestureActive || this.stageWidth <= 0) {
      return;
    }
    const offsetX = Number(event.offsetX);
    if (!Number.isFinite(offsetX)) {
      return;
    }
    const target = this.clampSeconds(
      this.screenSeekDragStartPositionSeconds +
        offsetX / this.stageWidth * this.resolveScreenSeekRangeSeconds()
    );
    this.scrubberPositionSeconds = target;
    this.screenSeekDeltaSeconds = target - this.screenSeekDragStartPositionSeconds;
  }

  private endScreenSeekGesture(): void {
    if (!this.screenSeekGestureActive) {
      return;
    }
    const target = this.scrubberPositionSeconds;
    this.screenSeekGestureActive = false;
    this.screenSeekDeltaSeconds = 0;
    this.commitSeek(target);
  }

  private cancelScreenSeekGesture(): void {
    if (!this.screenSeekGestureActive) {
      return;
    }
    this.screenSeekGestureActive = false;
    this.screenSeekDeltaSeconds = 0;
    this.scrubberActive = false;
    this.scrubberPositionSeconds = this.clampSeconds(this.playerState.positionSeconds);
    this.showControlsTemporarily();
  }

  private resolveScreenSeekRangeSeconds(): number {
    const duration = this.resolveDurationSeconds();
    return Math.min(
      duration,
      Math.max(
        SAMSUNG_PLAYER_SEEK_GESTURE_MIN_RANGE_SECONDS,
        Math.min(
          SAMSUNG_PLAYER_SEEK_GESTURE_MAX_RANGE_SECONDS,
          duration * SAMSUNG_PLAYER_SEEK_GESTURE_DURATION_FACTOR
        )
      )
    );
  }

  private resolveScreenSeekDeltaLabel(): string {
    const roundedDelta = Math.round(this.screenSeekDeltaSeconds);
    if (roundedDelta > 0) {
      return `快进 +${roundedDelta} 秒`;
    }
    if (roundedDelta < 0) {
      return `后退 ${Math.abs(roundedDelta)} 秒`;
    }
    return '拖动进度';
  }

  private beginSystemControlGesture(): void {
    if (!Number.isFinite(this.systemControlTouchStartX) || this.systemControlTouchStartX < 0 ||
      this.stageWidth <= 0) {
      this.systemControlGestureKind = '';
      return;
    }
    const kind: WebVideoSystemControlKind = this.systemControlTouchStartX < this.stageWidth / 2 ?
      'brightness' : 'volume';
    const snapshot = this.systemControlService.read(this.getAbilityContext(), kind);
    this.clearSystemControlDismissTimer();
    this.clearControlsHideTimer();
    this.systemControlGestureKind = kind;
    this.systemControlGestureValue = this.clampSystemControlValue(snapshot.value);
    this.systemControlDragStartValue = this.systemControlGestureValue;
    this.systemControlLastAppliedAt = 0;
    this.systemControlLastHapticStep = this.resolveSystemControlHapticStep(this.systemControlGestureValue);
    this.systemControlLastHapticAt = 0;
    this.systemControlIconRotationAngle = 0;
  }

  private updateSystemControlGesture(event: GestureEvent): void {
    if (this.systemControlGestureKind.length <= 0) {
      return;
    }
    const offsetY = Number(event.offsetY);
    if (!Number.isFinite(offsetY)) {
      return;
    }
    const nextValue = this.clampSystemControlValue(
      this.systemControlDragStartValue - offsetY / SAMSUNG_PLAYER_SYSTEM_CONTROL_DRAG_RANGE
    );
    this.updateSystemControlGestureFeedback(nextValue);
    this.systemControlGestureValue = nextValue;
    this.applySystemControlValue(nextValue, false);
  }

  private endSystemControlGesture(event: GestureEvent): void {
    if (this.systemControlGestureKind.length <= 0) {
      return;
    }
    const offsetY = Number(event.offsetY);
    if (Number.isFinite(offsetY)) {
      const finalValue = this.clampSystemControlValue(
        this.systemControlDragStartValue - offsetY / SAMSUNG_PLAYER_SYSTEM_CONTROL_DRAG_RANGE
      );
      this.updateSystemControlGestureFeedback(finalValue);
      this.systemControlGestureValue = finalValue;
    }
    this.applySystemControlValue(this.systemControlGestureValue, true);
    this.scheduleSystemControlDismiss();
    if (this.controlsVisible) {
      this.scheduleControlsHideIfIdle(true);
    }
  }

  private cancelSystemControlGesture(): void {
    if (this.systemControlGestureKind.length <= 0) {
      return;
    }
    this.applySystemControlValue(this.systemControlGestureValue, true);
    this.scheduleSystemControlDismiss();
    if (this.controlsVisible) {
      this.scheduleControlsHideIfIdle(true);
    }
  }

  private applySystemControlValue(value: number, force: boolean): void {
    const kind = this.systemControlGestureKind;
    if (kind !== 'brightness' && kind !== 'volume') {
      return;
    }
    const now = Date.now();
    if (!force && now - this.systemControlLastAppliedAt < SAMSUNG_PLAYER_SYSTEM_CONTROL_APPLY_INTERVAL_MS) {
      return;
    }
    this.systemControlLastAppliedAt = now;
    const snapshot = this.systemControlService.set(this.getAbilityContext(), kind, value);
    this.systemControlGestureValue = this.clampSystemControlValue(snapshot.value);
  }

  private scheduleSystemControlDismiss(): void {
    this.clearSystemControlDismissTimer();
    const generation = ++this.systemControlDismissGeneration;
    this.systemControlDismissTimer = setTimeout(() => {
      if (generation !== this.systemControlDismissGeneration) {
        return;
      }
      this.systemControlGestureKind = '';
      this.systemControlDismissTimer = -1;
    }, SAMSUNG_PLAYER_SYSTEM_CONTROL_DISMISS_MS);
  }

  private clearSystemControlDismissTimer(): void {
    if (this.systemControlDismissTimer >= 0) {
      clearTimeout(this.systemControlDismissTimer);
      this.systemControlDismissTimer = -1;
    }
    this.systemControlDismissGeneration += 1;
  }

  private clampSystemControlValue(value: number): number {
    if (!Number.isFinite(value)) {
      return 0;
    }
    return Math.max(0, Math.min(1, value));
  }

  private updateSystemControlGestureFeedback(nextValue: number): void {
    if (this.systemControlGestureKind !== 'brightness' && this.systemControlGestureKind !== 'volume') {
      return;
    }
    const normalizedValue = this.clampSystemControlValue(nextValue);
    if (this.systemControlGestureKind === 'brightness') {
      this.systemControlIconRotationAngle =
        (normalizedValue - this.systemControlDragStartValue) *
        SAMSUNG_PLAYER_SYSTEM_CONTROL_ROTATION_DEGREES;
    }
    const nextStep = this.resolveSystemControlHapticStep(normalizedValue);
    if (nextStep === this.systemControlLastHapticStep) {
      return;
    }
    this.systemControlLastHapticStep = nextStep;
    const now = Date.now();
    if (now - this.systemControlLastHapticAt < SAMSUNG_PLAYER_SYSTEM_CONTROL_HAPTIC_MIN_INTERVAL_MS) {
      return;
    }
    this.systemControlLastHapticAt = now;
    vibrator.startVibration({
      type: 'time',
      duration: SAMSUNG_PLAYER_SYSTEM_CONTROL_HAPTIC_DURATION_MS
    }, {
      usage: 'touch'
    }).catch((_error: Error) => {
    });
  }

  private resolveSystemControlHapticStep(value: number): number {
    return Math.floor(
      this.clampSystemControlValue(value) * SAMSUNG_PLAYER_SYSTEM_CONTROL_HAPTIC_STEP_COUNT + 0.000001
    );
  }

  private resolveSystemControlIndicatorHeight(): number {
    return Math.max(
      SAMSUNG_PLAYER_SYSTEM_CONTROL_MIN_HEIGHT,
      Math.min(
        SAMSUNG_PLAYER_SYSTEM_CONTROL_MAX_HEIGHT,
        this.stageHeight - SAMSUNG_PLAYER_SYSTEM_CONTROL_VERTICAL_INSET * 2
      )
    );
  }

  private resolveSystemControlFillHeight(): number {
    return this.resolveSystemControlIndicatorHeight() *
      this.clampSystemControlValue(this.systemControlGestureValue);
  }

  private resolveSystemControlIndicatorLeft(): number {
    const centerX = this.stageWidth / 2;
    if (this.systemControlGestureKind === 'brightness') {
      return Math.max(
        0,
        centerX - SAMSUNG_PLAYER_SYSTEM_CONTROL_CENTER_GAP - SAMSUNG_PLAYER_SYSTEM_CONTROL_WIDTH
      );
    }
    return Math.max(
      0,
      Math.min(
        this.stageWidth - SAMSUNG_PLAYER_SYSTEM_CONTROL_WIDTH,
        centerX + SAMSUNG_PLAYER_SYSTEM_CONTROL_CENTER_GAP
      )
    );
  }

  private resolveSystemControlIcon(): AiraRenderableIconId {
    if (this.systemControlGestureKind === 'brightness') {
      return 'videoAssistant.gesture.brightness';
    }
    if (this.systemControlGestureValue <= 0.001) {
      return 'videoAssistant.gesture.volumeMuted';
    }
    if (this.systemControlGestureValue < 0.34) {
      return 'videoAssistant.gesture.volumeLow';
    }
    if (this.systemControlGestureValue < 0.67) {
      return 'videoAssistant.gesture.volumeMedium';
    }
    return 'videoAssistant.gesture.volumeHigh';
  }

  private resolveSystemControlIconRotationAngle(): number {
    if (this.systemControlGestureKind !== 'brightness') {
      return 0;
    }
    return this.systemControlIconRotationAngle;
  }

  private getAbilityContext(): common.UIAbilityContext {
    return this.getUIContext().getHostContext() as common.UIAbilityContext;
  }

  private togglePlayback(): void {
    this.showControlsTemporarily();
    this.dispatchWebLiveCommand({ action: 'toggle' });
  }

  private beginTemporaryFastPlayback(): void {
    if (this.temporaryFastPlaybackActive || this.controlsLocked || !this.isPlaying() ||
      this.webLiveTransitionPending) {
      return;
    }
    const restoreRate = Math.max(SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MIN_RATE, Math.min(
      SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MAX_RATE,
      this.playbackSpeedRate
    ));
    const temporaryRate = Math.max(SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MIN_RATE, Math.min(
      SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MAX_RATE,
      restoreRate * 2
    ));
    this.temporaryFastPlaybackRestoreRate = restoreRate;
    this.temporaryFastPlaybackDragStartRate = temporaryRate;
    this.temporaryFastPlaybackRate = temporaryRate;
    this.temporaryFastPlaybackActive = true;
    this.clearControlsHideTimer();
    this.dispatchWebLiveCommand({ action: 'rate', value: temporaryRate });
  }

  private endTemporaryFastPlayback(scheduleControls: boolean = true): void {
    if (!this.temporaryFastPlaybackActive) {
      return;
    }
    const restoreRate = this.temporaryFastPlaybackRestoreRate;
    this.temporaryFastPlaybackActive = false;
    this.temporaryFastPlaybackRate = restoreRate;
    this.dispatchWebLiveCommand({ action: 'rate', value: restoreRate });
    if (scheduleControls) {
      this.scheduleControlsHideIfIdle(true);
    }
  }

  private updateTemporaryFastPlaybackRate(event: GestureEvent): void {
    if (!this.temporaryFastPlaybackActive) {
      return;
    }
    const offsetX = Number(event.offsetX);
    if (!Number.isFinite(offsetX)) {
      return;
    }
    const steps = Math.round(offsetX / SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_RATE_STEP_DISTANCE);
    const nextRate = this.normalizeTemporaryFastPlaybackRate(
      this.temporaryFastPlaybackDragStartRate + steps * SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_RATE_STEP
    );
    if (Math.abs(nextRate - this.temporaryFastPlaybackRate) < 0.001) {
      return;
    }
    this.temporaryFastPlaybackRate = nextRate;
    this.dispatchWebLiveCommand({ action: 'rate', value: nextRate });
  }

  private normalizeTemporaryFastPlaybackRate(rate: number): number {
    if (!Number.isFinite(rate)) {
      return SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MIN_RATE;
    }
    const clampedRate = Math.max(
      SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MIN_RATE,
      Math.min(SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_MAX_RATE, rate)
    );
    return Math.round(clampedRate / SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_RATE_STEP) *
      SAMSUNG_PLAYER_TEMPORARY_FAST_PLAYBACK_RATE_STEP;
  }

  private seekBySeconds(deltaSeconds: number): void {
    this.commitSeek(this.resolveDisplayPositionSeconds() + deltaSeconds);
  }

  private handleTimelineChange(value: number, mode: SliderChangeMode): void {
    const next = this.clampSeconds(value);
    this.scrubberPositionSeconds = next;
    this.scrubberActive = mode === SliderChangeMode.Begin || mode === SliderChangeMode.Moving;
    this.controlsVisible = true;
    if (this.scrubberActive) {
      this.clearControlsHideTimer();
      return;
    }
    if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
      this.commitSeek(next);
    }
  }

  private commitSeek(seconds: number): void {
    const next = this.clampSeconds(seconds);
    this.scrubberPositionSeconds = next;
    this.scrubberActive = false;
    this.dispatchWebLiveCommand({ action: 'seek', value: next });
    this.showControlsTemporarily();
  }

  private closePlayer(): void {
    this.speedPanelVisible = false;
    this.endTemporaryFastPlayback(false);
    this.onAction({ type: 'close' });
  }

  private cycleVideoScaleMode(): void {
    if (this.videoScaleMode === 'contain') {
      this.videoScaleMode = 'crop';
    } else if (this.videoScaleMode === 'crop') {
      this.videoScaleMode = 'stretch';
    } else {
      this.videoScaleMode = 'contain';
    }
    this.dispatchWebLiveCommand({ action: 'scale', value: this.resolveWebLiveScaleModeValue() });
    this.showPlayerToast(this.resolveVideoScaleModeLabel());
    this.showControlsTemporarily();
  }

  private togglePlaybackSpeedPanel(): void {
    this.speedPanelVisible = !this.speedPanelVisible;
    this.controlsVisible = true;
    if (this.speedPanelVisible) {
      this.clearControlsHideTimer();
      return;
    }
    this.scheduleControlsHideIfIdle(true);
  }

  private closePlaybackSpeedPanel(): void {
    this.speedPanelVisible = false;
    this.showControlsTemporarily();
  }

  private selectPlaybackSpeed(rate: number): void {
    this.endTemporaryFastPlayback(false);
    this.playbackSpeedRate = rate;
    this.speedPanelVisible = false;
    this.dispatchWebLiveCommand({ action: 'rate', value: rate });
    this.showControlsTemporarily();
  }

  private requestRotate(): void {
    this.speedPanelVisible = false;
    this.onAction({ type: 'rotate', landscape: !this.isLandscape() });
    this.showControlsTemporarily();
  }

  private dispatchWebLiveCommand(command: BrowserArkWebMediaWebLiveCommand): void {
    this.onAction({ type: 'web_live_command', command: command });
  }

  private handleMouseActivity(event: MouseEvent): void {
    if (event.action !== MouseAction.Move) {
      return;
    }
    const nextX = Number(event.x);
    const nextY = Number(event.y);
    if (!Number.isFinite(nextX) || !Number.isFinite(nextY)) {
      return;
    }
    if (this.mouseMoveAnchorX < 0 && this.mouseMoveAnchorY < 0) {
      this.mouseMoveAnchorX = nextX;
      this.mouseMoveAnchorY = nextY;
      return;
    }
    if (Math.abs(nextX - this.mouseMoveAnchorX) < SAMSUNG_PLAYER_MOUSE_MOVE_MIN_DISTANCE &&
      Math.abs(nextY - this.mouseMoveAnchorY) < SAMSUNG_PLAYER_MOUSE_MOVE_MIN_DISTANCE) {
      return;
    }
    const now = Date.now();
    if (this.controlsVisible && now - this.mouseControlsPokeAt < SAMSUNG_PLAYER_MOUSE_POKE_THROTTLE_MS) {
      return;
    }
    this.mouseMoveAnchorX = nextX;
    this.mouseMoveAnchorY = nextY;
    this.mouseControlsPokeAt = now;
    this.showControlsTemporarily();
  }

  private toggleControls(): void {
    if (this.controlsLocked) {
      this.controlsVisible = !this.controlsVisible;
      if (this.controlsVisible) {
        this.scheduleControlsHideIfIdle(true);
      } else {
        this.clearControlsHideTimer();
      }
      return;
    }
    if (this.speedPanelVisible) {
      this.speedPanelVisible = false;
      this.controlsVisible = true;
      this.scheduleControlsHideIfIdle(true);
      return;
    }
    this.controlsVisible = !this.controlsVisible;
    if (this.controlsVisible) {
      this.scheduleControlsHideIfIdle(true);
    } else {
      this.clearControlsHideTimer();
    }
  }

  private showControlsTemporarily(): void {
    if (this.controlsLocked) {
      return;
    }
    this.controlsVisible = true;
    this.scheduleControlsHideIfIdle(true);
  }

  private scheduleControlsHideIfIdle(resetTimer: boolean): void {
    if (!this.controlsVisible || this.scrubberActive || this.speedPanelVisible ||
      this.isPlayerLoading() || this.playerState.playbackStatus === 'error') {
      return;
    }
    if (!resetTimer && this.controlsHideTimer >= 0) {
      return;
    }
    this.clearControlsHideTimer();
    const generation = ++this.controlsHideGeneration;
    this.controlsHideTimer = setTimeout(() => {
      if (generation !== this.controlsHideGeneration || this.scrubberActive) {
        return;
      }
      this.controlsVisible = false;
      this.controlsHideTimer = -1;
    }, SAMSUNG_PLAYER_CONTROLS_AUTO_HIDE_MS);
  }

  private clearControlsHideTimer(): void {
    if (this.controlsHideTimer >= 0) {
      clearTimeout(this.controlsHideTimer);
      this.controlsHideTimer = -1;
    }
    this.controlsHideGeneration += 1;
  }

  private syncLoadingIndicatorVisibility(): void {
    if (!this.isPlayerLoading()) {
      this.clearLoadingIndicatorTimer();
      this.loadingIndicatorVisible = false;
      return;
    }
    if (this.loadingIndicatorVisible || this.loadingIndicatorTimer >= 0) {
      return;
    }
    const generation = ++this.loadingIndicatorGeneration;
    this.loadingIndicatorTimer = setTimeout(() => {
      if (generation !== this.loadingIndicatorGeneration || !this.isPlayerLoading()) {
        return;
      }
      this.loadingIndicatorTimer = -1;
      this.loadingIndicatorVisible = true;
    }, SAMSUNG_PLAYER_LOADING_INDICATOR_DELAY_MS);
  }

  private clearLoadingIndicatorTimer(): void {
    if (this.loadingIndicatorTimer >= 0) {
      clearTimeout(this.loadingIndicatorTimer);
      this.loadingIndicatorTimer = -1;
    }
    this.loadingIndicatorGeneration += 1;
  }

  private shouldShowFullControls(): boolean {
    return !this.controlsLocked && (this.controlsVisible || this.isPlayerLoading() ||
      this.playerState.playbackStatus === 'error');
  }

  private isPlayerLoading(): boolean {
    return this.playerState.loadingReason.length > 0 || this.playerState.playbackStatus === 'loading';
  }

  private isPlaying(): boolean {
    return this.playerState.playbackStatus === 'playing';
  }

  private resolvePlayerStageBackground(): ResourceColor {
    if (!this.webLiveTransitionPending) {
      return this.playerTransparentColor;
    }
    return this.playerBackgroundColor;
  }

  private isLandscape(): boolean {
    return this.stageWidth > this.stageHeight;
  }

  private resolvePlayerTitle(): string {
    const title = this.playerState.item.title.trim();
    return title.length > 0 ? title : '网页视频';
  }

  private resolveTopFeatureLayerHeight(): number {
    return this.resolveTitleTopInset() + SAMSUNG_PLAYER_TITLE_HEIGHT;
  }

  private resolveTitleTopInset(): number {
    const safeInset = Math.max(0, Math.ceil(this.storedTopSafeInsetVp));
    return Math.max(SAMSUNG_PLAYER_TITLE_MIN_TOP_INSET, safeInset + SAMSUNG_PLAYER_TITLE_SAFE_TOP_GAP);
  }

  private resolveCenterControlsLeft(): number {
    const width = SAMSUNG_PLAYER_SEEK_BUTTON_SIZE * 2 + SAMSUNG_PLAYER_CENTER_PLAY_SIZE +
      SAMSUNG_PLAYER_CENTER_CONTROL_GAP * 2;
    return Math.max(0, (this.stageWidth - width) / 2);
  }

  private resolveCenterControlsTop(): number {
    return Math.max(0, (this.stageHeight - SAMSUNG_PLAYER_CENTER_PLAY_SIZE) / 2);
  }

  private resolveBottomControlRegionHeight(): number {
    return this.isLandscape() ? SAMSUNG_PLAYER_LANDSCAPE_FEATURE_HEIGHT :
      SAMSUNG_PLAYER_PORTRAIT_FEATURE_HEIGHT;
  }

  private resolveBottomControlRegionTop(): number {
    return Math.max(0, this.stageHeight - this.resolveBottomInset() - this.resolveBottomControlRegionHeight());
  }

  private resolveBottomFeatureInset(): number {
    return this.isLandscape() ? 24 : 18;
  }

  private resolveBottomInset(): number {
    return this.isLandscape() ? SAMSUNG_PLAYER_LANDSCAPE_BOTTOM_INSET :
      SAMSUNG_PLAYER_PORTRAIT_BOTTOM_INSET;
  }

  private resolveBottomSectionGap(): number {
    return this.isLandscape() ? SAMSUNG_PLAYER_LANDSCAPE_SECTION_GAP :
      SAMSUNG_PLAYER_PORTRAIT_SECTION_GAP;
  }

  private resolvePlaybackSpeedPanelLeft(): number {
    return Math.max(0, (this.stageWidth - this.resolvePlaybackSpeedPanelWidth()) / 2);
  }

  private resolvePlaybackSpeedPanelTop(): number {
    return Math.max(0, (this.stageHeight - this.resolvePlaybackSpeedPanelHeight()) / 2);
  }

  private resolvePlaybackSpeedPanelWidth(): number {
    return Math.min(
      SAMSUNG_PLAYER_SPEED_DIALOG_MAX_WIDTH,
      Math.max(240, this.stageWidth - SAMSUNG_PLAYER_SPEED_DIALOG_EDGE_INSET * 2)
    );
  }

  private resolvePlaybackSpeedPanelHeight(): number {
    return Math.min(
      SAMSUNG_PLAYER_SPEED_DIALOG_MAX_HEIGHT,
      Math.max(220, this.stageHeight - SAMSUNG_PLAYER_SPEED_DIALOG_EDGE_INSET * 2)
    );
  }

  private resolveVideoScaleModeLabel(): string {
    if (this.videoScaleMode === 'crop') {
      return '裁剪填满';
    }
    if (this.videoScaleMode === 'stretch') {
      return '拉伸填满';
    }
    return '适应屏幕';
  }

  private resolveWebLiveScaleModeValue(): number {
    if (this.videoScaleMode === 'crop') {
      return 1;
    }
    if (this.videoScaleMode === 'stretch') {
      return 2;
    }
    return 0;
  }

  private formatPlaybackSpeed(rate: number): string {
    return rate.toFixed(2).replace(/0$/, '') + 'x';
  }

  private formatPlaybackSpeedChoice(rate: number): string {
    if (rate === 1.0) {
      return '1.0x（正常）';
    }
    return rate.toString() + 'x';
  }

  private resolveProgressLayerTop(): number {
    const height = this.isLandscape() ? SAMSUNG_PLAYER_LANDSCAPE_PROGRESS_HEIGHT :
      SAMSUNG_PLAYER_PORTRAIT_PROGRESS_HEIGHT;
    return Math.max(0, this.resolveBottomControlRegionTop() - this.resolveBottomSectionGap() - height);
  }

  private resolveBottomScrimHeight(): number {
    return Math.max(0, this.stageHeight - this.resolveProgressLayerTop());
  }

  private resolveDisplayPositionSeconds(): number {
    return this.scrubberActive ? this.scrubberPositionSeconds : Math.max(0, this.playerState.positionSeconds);
  }

  private resolveDurationSeconds(): number {
    return Math.max(0, this.playerState.durationSeconds);
  }

  private resolveTimelineValue(): number {
    return this.clampSeconds(this.resolveDisplayPositionSeconds());
  }

  private clampSeconds(seconds: number): number {
    const normalized = Math.max(0, Math.floor(seconds));
    const duration = this.resolveDurationSeconds();
    return duration > 0 ? Math.min(duration, normalized) : normalized;
  }

  private formatSeconds(seconds: number): string {
    const normalized = Math.max(0, Math.floor(seconds));
    const hours = Math.floor(normalized / 3600);
    const minutes = Math.floor((normalized % 3600) / 60);
    const remainingSeconds = normalized % 60;
    const minuteText = hours > 0 ? minutes.toString().padStart(2, '0') : minutes.toString();
    const secondText = remainingSeconds.toString().padStart(2, '0');
    return hours > 0 ? hours.toString() + ':' + minuteText + ':' + secondText : minuteText + ':' + secondText;
  }

  private showPlayerToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message,
        duration: 2200
      });
    } catch (_error) {
    }
  }

  private parseAreaDimension(value: Length): number {
    if (typeof value === 'number') {
      return value;
    }
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
