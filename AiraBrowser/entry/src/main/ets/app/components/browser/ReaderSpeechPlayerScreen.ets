import { ReaderModeArticle, ReaderModeTheme } from '../../../features/reader/ReaderModeModels';
import { ReaderSpeechPlayerAction } from '../../../core/browser/ReaderModeCoordinator';
import { ReaderSpeechState, isReaderSpeechActive } from '../../../features/reader/ReaderSpeechModels';
import {
  ReaderSpeechPlayerSnapshot,
  ReaderSpeechPlayerViewModel
} from '../../../features/reader/ReaderSpeechPlayerViewModel';
import {
  ReaderModePanelThemeTokens,
  resolveReaderModePanelTheme
} from '../../../features/reader/ReaderModePanelThemeResolver';
import { BROWSER_GLOBAL_SYMBOL_WEIGHT } from './BrowserIconStyle';
import { BrowserModalBottomOverlay } from './BrowserModalBottomSheet';
import {
  READER_SPEECH_PLAYER_OVERLAY_ANIMATION_DURATION_MS,
  READER_SPEECH_PLAYER_OVERLAY_ENTER_OFFSET_Y,
  READER_SPEECH_PLAYER_OVERLAY_SHEET_HEIGHT,
  READER_SPEECH_PLAYER_OVERLAY_Z_INDEX
} from './BrowserShellPresentationTokens';

const READER_SPEECH_PLAYER_HORIZONTAL_PADDING: number = 22;
const READER_SPEECH_PLAYER_TOP_BAR_HEIGHT: number = 58;
const READER_SPEECH_PLAYER_ARTICLE_CARD_RADIUS: number = 20;
const READER_SPEECH_PLAYER_MEDIA_RADIUS: number = 18;
const READER_SPEECH_PLAYER_CONTROL_RADIUS: number = 8;
const READER_SPEECH_PLAYER_SHEET_RADIUS: number = 28;
const READER_SPEECH_PLAYER_ICON_BUTTON_SIZE: number = 42;
const READER_SPEECH_PLAYER_SMALL_ICON_SIZE: number = 19;
const READER_SPEECH_PLAYER_MAIN_BUTTON_SIZE: number = 74;
const READER_SPEECH_PLAYER_MAIN_ICON_SIZE: number = 32;
const READER_SPEECH_PLAYER_PROGRESS_HEIGHT: number = 5;
const READER_SPEECH_PLAYER_SPEED_OPTION_HEIGHT: number = 34;
const READER_SPEECH_PLAYER_CURRENT_TEXT_HEIGHT: number = 69;
const READER_SPEECH_PLAYER_CARD_PRESSED_SCALE: number = 0.97;
const READER_SPEECH_PLAYER_CARD_PRESS_DURATION_MS: number = 150;
const READER_SPEECH_PLAYER_CARD_RELEASE_DURATION_MS: number = 420;

@Component
export struct ReaderSpeechPlayerSheet {
  @State private articleCardPressed: boolean = false;
  @Prop article: ReaderModeArticle;
  @Prop chunks: string[] = [];
  @Prop speechState: ReaderSpeechState = {
    status: 'idle',
    currentChunkIndex: 0,
    totalChunks: 0,
    message: ''
  };
  @Prop readerTheme: ReaderModeTheme = 'system';
  @Prop speed: number = 1;
  @Prop voiceLabel: string = '系统默认音色';
  @Prop bottomSafeInsetVp: number = 0;
  private viewModel: ReaderSpeechPlayerViewModel = new ReaderSpeechPlayerViewModel();
  onClose: () => void = () => {};
  onToggleSpeech: () => void = () => {};
  onPreviousChunk: () => void = () => {};
  onNextChunk: () => void = () => {};
  onReplayChunk: () => void = () => {};
  onLocateInReader: () => void = () => {};
  onSpeedChange: (speed: number) => void = (_speed: number) => {};
  onOpenVoicePicker: () => void = () => {};

  build() {
    Column() {
      this.buildTopBar()

      this.buildContent()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.resolveBackgroundColor())
    .borderRadius({
      topLeft: READER_SPEECH_PLAYER_SHEET_RADIUS,
      topRight: READER_SPEECH_PLAYER_SHEET_RADIUS,
      bottomLeft: 0,
      bottomRight: 0
    })
    .clip(true)
  }

  @Builder
  private buildTopBar() {
    Row() {
      this.buildTopIconButton($r('sys.symbol.chevron_down'), this.onClose)

      Text('听读正文')
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryTextColor())
        .textAlign(TextAlign.Center)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Blank()
        .width(READER_SPEECH_PLAYER_ICON_BUTTON_SIZE)
        .height(READER_SPEECH_PLAYER_ICON_BUTTON_SIZE)
    }
    .height(READER_SPEECH_PLAYER_TOP_BAR_HEIGHT)
    .width('100%')
    .padding({
      left: 10,
      right: 10,
      top: 4,
      bottom: 4
    })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildContent() {
    Column({ space: 18 }) {
      this.buildArticleCard()

      this.buildProgressBlock()

      this.buildPlaybackControls()

      this.buildSpeedControls()

      this.buildSecondaryActions()

      Blank()
    }
    .width('100%')
    .layoutWeight(1)
    .padding({
      left: READER_SPEECH_PLAYER_HORIZONTAL_PADDING,
      right: READER_SPEECH_PLAYER_HORIZONTAL_PADDING,
      top: 12,
      bottom: Math.max(20, this.bottomSafeInsetVp + 12)
    })
  }

  @Builder
  private buildArticleCard() {
    Column({ space: 18 }) {
      Row() {
        Text(this.resolveSnapshotSource())
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Text(this.resolveSnapshotStatusLabel())
          .fontSize(12)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
      }
      .width('100%')

      Stack({ alignContent: Alignment.Center }) {
        if (this.resolveSnapshotCoverImageUrl().length > 0) {
          Image(this.resolveSnapshotCoverImageUrl())
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
        } else {
          SymbolGlyph($r('sys.symbol.doc_text_fill'))
            .fontSize(82)
            .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
            .fontColor([this.resolveDecorativeIconColor()])
        }
      }
      .width('100%')
      .height(128)
      .backgroundColor(this.resolveControlBackgroundColor())
      .borderRadius(READER_SPEECH_PLAYER_MEDIA_RADIUS)
      .clip(true)

      Column({ space: 8 }) {
        Text(this.resolveSnapshotTitle())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        Text(this.resolveSnapshotSubtitle())
          .fontSize(14)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .width('100%')

      Text(this.resolveSnapshotCurrentText())
        .fontSize(15)
        .lineHeight(23)
        .fontColor(this.resolveSecondaryTextColor())
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .height(READER_SPEECH_PLAYER_CURRENT_TEXT_HEIGHT)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(this.resolveCardBackgroundColor())
    .borderRadius(READER_SPEECH_PLAYER_ARTICLE_CARD_RADIUS)
    .scale({
      x: this.articleCardPressed ? READER_SPEECH_PLAYER_CARD_PRESSED_SCALE : 1,
      y: this.articleCardPressed ? READER_SPEECH_PLAYER_CARD_PRESSED_SCALE : 1
    })
    .animation({
      duration: this.articleCardPressed ? READER_SPEECH_PLAYER_CARD_PRESS_DURATION_MS :
      READER_SPEECH_PLAYER_CARD_RELEASE_DURATION_MS,
      curve: this.articleCardPressed ? Curve.EaseOut : 'interpolatingSpring(0, 1, 360, 24)'
    })
    .onTouch((event: TouchEvent) => {
      this.updateArticleCardPressed(event.type);
    })
  }

  @Builder
  private buildProgressBlock() {
    Column({ space: 8 }) {
      Progress({
        value: this.resolveSnapshotProgressPercent(),
        total: 100,
        type: ProgressType.Linear
      })
        .width('100%')
        .height(READER_SPEECH_PLAYER_PROGRESS_HEIGHT)
        .style({ strokeWidth: READER_SPEECH_PLAYER_PROGRESS_HEIGHT, enableSmoothEffect: true })
        .borderRadius(READER_SPEECH_PLAYER_PROGRESS_HEIGHT / 2)
        .color(this.resolvePrimaryTextColor())
        .backgroundColor(this.resolveControlBackgroundColor())

      Row() {
        Text(this.resolveSnapshotProgressLabel())
          .fontSize(12)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .layoutWeight(1)

        Text(this.voiceLabel)
          .fontSize(12)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
          .textAlign(TextAlign.Center)

        Text(this.resolveSpeedLabel(this.speed))
          .fontSize(12)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
      }
      .width('100%')
    }
    .width('100%')
  }

  @Builder
  private buildPlaybackControls() {
    Row() {
      this.buildControlIconButton($r('sys.symbol.arrow_counterclockwise'), this.onReplayChunk, this.chunks.length > 0)

      this.buildControlIconButton(
        $r('sys.symbol.backward_end_fill'),
        this.onPreviousChunk,
        this.canUseChunkControls(),
        this.canUseChunkControls()
      )

      this.buildMainPlaybackButton()

      this.buildControlIconButton($r('sys.symbol.forward_end_fill'), this.onNextChunk, this.canMoveNext())

      this.buildControlIconButton($r('sys.symbol.mic_fill'), this.onOpenVoicePicker, this.chunks.length > 0)
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceBetween)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildMainPlaybackButton() {
    Button({ type: ButtonType.Circle }) {
      if (isReaderSpeechActive(this.speechState)) {
        SymbolGlyph($r('sys.symbol.pause_fill'))
          .fontSize(READER_SPEECH_PLAYER_MAIN_ICON_SIZE)
          .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
          .fontColor([this.resolveBackgroundColor()])
      } else {
        SymbolGlyph($r('sys.symbol.play_fill'))
          .fontSize(READER_SPEECH_PLAYER_MAIN_ICON_SIZE)
          .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
          .fontColor([this.resolveBackgroundColor()])
      }
    }
    .width(READER_SPEECH_PLAYER_MAIN_BUTTON_SIZE)
    .height(READER_SPEECH_PLAYER_MAIN_BUTTON_SIZE)
    .backgroundColor(this.resolvePrimaryTextColor())
    .stateEffect(true)
    .enabled(this.chunks.length > 0 || isReaderSpeechActive(this.speechState))
    .onClick(() => {
      this.onToggleSpeech();
    })
  }

  @Builder
  private buildSpeedControls() {
    Row({ space: 8 }) {
      ForEach([0.8, 1, 1.2, 1.5], (option: number) => {
        this.buildSpeedOption(option)
      }, (option: number): string => option.toString())
    }
    .width('100%')
    .padding(4)
    .backgroundColor(this.resolveControlBackgroundColor())
    .borderRadius((READER_SPEECH_PLAYER_SPEED_OPTION_HEIGHT + 8) / 2)
  }

  @Builder
  private buildSpeedOption(option: number) {
    Button({ type: ButtonType.Normal }) {
      Text(this.resolveSpeedLabel(option))
        .fontSize(13)
        .fontColor(this.isSelectedSpeed(option) ? this.resolveBackgroundColor() : this.resolvePrimaryTextColor())
        .maxLines(1)
    }
      .layoutWeight(1)
      .height(READER_SPEECH_PLAYER_SPEED_OPTION_HEIGHT)
      .backgroundColor(this.isSelectedSpeed(option) ? this.resolvePrimaryTextColor() : '#00000000')
      .borderRadius(READER_SPEECH_PLAYER_SPEED_OPTION_HEIGHT / 2)
      .stateEffect(true)
      .onClick(() => {
        this.onSpeedChange(option);
      })
  }

  @Builder
  private buildSecondaryActions() {
    Button('回到阅读模式')
      .width('100%')
      .height(42)
      .fontSize(14)
      .fontColor(this.resolvePrimaryTextColor())
      .backgroundColor(this.resolveControlBackgroundColor())
      .borderRadius(READER_SPEECH_PLAYER_CONTROL_RADIUS)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .enabled(this.chunks.length > 0)
      .onClick(() => {
        this.onReturnToReader();
      })
  }

  @Builder
  private buildTopIconButton(icon: Resource, action: () => void) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon)
        .fontSize(READER_SPEECH_PLAYER_SMALL_ICON_SIZE)
        .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
        .fontColor([this.resolvePrimaryTextColor()])
    }
    .width(READER_SPEECH_PLAYER_ICON_BUTTON_SIZE)
    .height(READER_SPEECH_PLAYER_ICON_BUTTON_SIZE)
    .backgroundColor('#00000000')
    .stateEffect(true)
    .onClick(() => {
      action();
    })
  }

  @Builder
  private buildControlIconButton(icon: Resource, action: () => void, enabled: boolean, active: boolean = enabled) {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph(icon)
        .fontSize(READER_SPEECH_PLAYER_SMALL_ICON_SIZE)
        .fontWeight(BROWSER_GLOBAL_SYMBOL_WEIGHT)
        .fontColor([active ? this.resolvePrimaryTextColor() : this.resolveSecondaryTextColor()])
    }
    .width(READER_SPEECH_PLAYER_ICON_BUTTON_SIZE)
    .height(READER_SPEECH_PLAYER_ICON_BUTTON_SIZE)
    .backgroundColor(this.resolveControlBackgroundColor())
    .opacity(active ? 1 : 0.45)
    .stateEffect(enabled)
    .enabled(enabled)
    .onClick(() => {
      action();
    })
  }

  private buildSnapshot(): ReaderSpeechPlayerSnapshot {
    return this.viewModel.buildSnapshot(this.article, this.chunks, this.speechState);
  }

  private resolveSnapshotTitle(): string {
    return this.buildSnapshot().title;
  }

  private resolveSnapshotSubtitle(): string {
    return this.buildSnapshot().subtitle;
  }

  private resolveSnapshotSource(): string {
    return this.buildSnapshot().source;
  }

  private resolveSnapshotCoverImageUrl(): string {
    return this.buildSnapshot().coverImageUrl;
  }

  private resolveSnapshotCurrentText(): string {
    return this.buildSnapshot().currentText;
  }

  private resolveSnapshotProgressLabel(): string {
    return this.buildSnapshot().progressLabel;
  }

  private resolveSnapshotProgressPercent(): number {
    return this.buildSnapshot().progressPercent;
  }

  private resolveSnapshotStatusLabel(): string {
    return this.buildSnapshot().statusLabel;
  }

  private canMoveNext(): boolean {
    return this.chunks.length > 0 && this.speechState.currentChunkIndex < this.chunks.length;
  }

  private canUseChunkControls(): boolean {
    return this.chunks.length > 0;
  }

  private isSelectedSpeed(option: number): boolean {
    return Math.abs(option - this.speed) < 0.01;
  }

  private resolveSpeedLabel(speed: number): string {
    return speed.toFixed(speed % 1 === 0 ? 0 : 1) + 'x';
  }

  private resolveThemeTokens(): ReaderModePanelThemeTokens {
    return resolveReaderModePanelTheme(this.readerTheme);
  }

  private resolveBackgroundColor(): string {
    return this.resolveThemeTokens().panelBackgroundColor;
  }

  private resolveCardBackgroundColor(): string {
    return this.resolveThemeTokens().cardBackgroundColor;
  }

  private resolveControlBackgroundColor(): string {
    return this.resolveThemeTokens().inputBackgroundColor;
  }

  private resolvePrimaryTextColor(): string {
    return this.resolveThemeTokens().primaryTextColor;
  }

  private resolveSecondaryTextColor(): string {
    return this.resolveThemeTokens().secondaryTextColor;
  }

  private resolveDecorativeIconColor(): string {
    return this.resolveThemeTokens().iconColor;
  }

  private onReturnToReader(): void {
    this.onLocateInReader();
  }

  private updateArticleCardPressed(type: TouchType): void {
    if (type === TouchType.Down) {
      this.articleCardPressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.articleCardPressed = false;
    }
  }
}

@Component
export struct ReaderSpeechPlayerOverlay {
  @Prop visible: boolean = false;
  @Prop article: ReaderModeArticle;
  @Prop chunks: string[] = [];
  @Prop speechState: ReaderSpeechState = {
    status: 'idle',
    currentChunkIndex: 0,
    totalChunks: 0,
    message: ''
  };
  @Prop readerTheme: ReaderModeTheme = 'system';
  @Prop speed: number = 1;
  @Prop voiceLabel: string = '系统默认音色';
  @Prop bottomSafeInsetVp: number = 0;
  onAction: (action: ReaderSpeechPlayerAction) => void = (_action: ReaderSpeechPlayerAction) => {};

  build() {
    BrowserModalBottomOverlay({
      visible: this.visible,
      sheetHeight: READER_SPEECH_PLAYER_OVERLAY_SHEET_HEIGHT,
      enterOffsetY: READER_SPEECH_PLAYER_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: READER_SPEECH_PLAYER_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: READER_SPEECH_PLAYER_OVERLAY_Z_INDEX,
      onDismiss: () => {
        this.onAction({ type: 'dismiss' });
      }
    }) {
      ReaderSpeechPlayerSheet({
        article: this.article,
        chunks: this.chunks,
        speechState: this.speechState,
        readerTheme: this.readerTheme,
        speed: this.speed,
        voiceLabel: this.voiceLabel,
        bottomSafeInsetVp: this.bottomSafeInsetVp,
        onClose: () => {
          this.onAction({ type: 'dismiss' });
        },
        onToggleSpeech: () => {
          this.onAction({ type: 'toggle' });
        },
        onPreviousChunk: () => {
          this.onAction({ type: 'previous' });
        },
        onNextChunk: () => {
          this.onAction({ type: 'next' });
        },
        onReplayChunk: () => {
          this.onAction({ type: 'replay' });
        },
        onLocateInReader: () => {
          this.onAction({ type: 'locate' });
        },
        onSpeedChange: (speed: number) => {
          this.onAction({ type: 'change_speed', speed: speed });
        },
        onOpenVoicePicker: () => {
          this.onAction({ type: 'open_voice_picker' });
        }
      })
    }
  }
}
