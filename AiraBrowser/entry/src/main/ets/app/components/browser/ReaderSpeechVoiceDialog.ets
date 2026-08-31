import { ReaderSpeechVoiceOption } from '../../../features/reader/ReaderSpeechModels';
import { ReaderModeSpeechVoiceDialogPresentation } from '../../../core/browser/ReaderModeCoordinator';
import {
  ReaderModePanelThemeTokens,
  resolveReaderModePanelTheme
} from '../../../features/reader/ReaderModePanelThemeResolver';
import {
  SettingsRowPosition
} from '../settings/SettingsRows';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import { BrowserSheetActionButton } from './BrowserModalBottomSheet';
import { CENTERED_DIALOG_TALL_PADDED_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

const READER_SPEECH_VOICE_RADIO_GROUP: string = 'reader-speech-voice';
const READER_SPEECH_VOICE_DIALOG_MAX_LIST_HEIGHT: number = 320;
const READER_SPEECH_VOICE_ROW_HORIZONTAL_PADDING: number = 16;
const READER_SPEECH_VOICE_ROW_VERTICAL_PADDING: number = 14;
const READER_SPEECH_VOICE_ROW_SPACE: number = 12;

@CustomDialog
export struct ReaderSpeechVoiceDialog {
  controller?: CustomDialogController;
  @Link presentation: ReaderModeSpeechVoiceDialogPresentation;
  @State private pressedVoiceId: string = '';
  onSelectVoiceId: (voiceId: string) => void = (_voiceId: string) => {};

  build() {
    Column({ space: 16 }) {
      Text('选择音色')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.resolvePrimaryTextColor())
        .textAlign(TextAlign.Center)

      Column() {
        this.buildDialogContent()
      }
      .layoutWeight(1)
      .width('100%')

      Row() {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })
      }
        .width('100%')
        .height(44)
    }
    .attributeModifier(CENTERED_DIALOG_TALL_PADDED_SURFACE_MODIFIER)
  }

  @Builder
  private buildDialogContent() {
    if (this.presentation.loading) {
      this.buildStateText('正在读取系统音色...')
    } else if (this.presentation.errorMessage.length > 0) {
      this.buildStateText(this.presentation.errorMessage)
    } else {
      Scroll() {
        SettingsGroupCard({ surfaceColor: this.resolveCardBackgroundColor() }) {
          ForEach(this.presentation.options, (option: ReaderSpeechVoiceOption, index: number) => {
            this.buildVoiceRow(option, index, this.presentation.options.length)
            if (index < this.presentation.options.length - 1) {
              SettingsGroupDivider({ dividerColor: this.resolveControlBackgroundColor() })
            }
          }, (option: ReaderSpeechVoiceOption) => `${option.id}:${this.isSelected(option) ? 'selected' : 'idle'}`)
        }
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxHeight: READER_SPEECH_VOICE_DIALOG_MAX_LIST_HEIGHT })
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: false })
    }
  }

  @Builder
  private buildVoiceRow(option: ReaderSpeechVoiceOption, index: number, total: number) {
    Row({ space: READER_SPEECH_VOICE_ROW_SPACE }) {
      Column({ space: 4 }) {
        Text(option.title)
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(option.isAvailable ? this.resolvePrimaryTextColor() : this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(option.helperText)
          .width('100%')
          .fontSize(12)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({
        value: option.id,
        group: READER_SPEECH_VOICE_RADIO_GROUP
      })
        .checked(this.isSelected(option))
        .enabled(option.isAvailable)
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({
          checkedBackgroundColor: this.resolvePrimaryTextColor()
        })
    }
    .width('100%')
    .backgroundColor(this.resolveRowBackgroundColor(option))
    .borderRadius(this.resolveRowBorderRadius(index, total))
    .clip(true)
    .padding({
      left: READER_SPEECH_VOICE_ROW_HORIZONTAL_PADDING,
      right: READER_SPEECH_VOICE_ROW_HORIZONTAL_PADDING,
      top: READER_SPEECH_VOICE_ROW_VERTICAL_PADDING,
      bottom: READER_SPEECH_VOICE_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(option.isAvailable)
    .opacity(option.isAvailable ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressedVoice(option, event.type);
    })
    .onClick(() => {
      this.selectVoice(option);
    })
  }

  @Builder
  private buildStateText(message: string) {
    Text(message)
      .width('100%')
      .fontSize(14)
      .fontColor(this.resolveSecondaryTextColor())
      .textAlign(TextAlign.Center)
      .padding({ top: 10, bottom: 10 })
  }

  private isSelected(option: ReaderSpeechVoiceOption): boolean {
    return this.presentation.selectedVoiceId === option.id;
  }

  private selectVoice(option: ReaderSpeechVoiceOption): void {
    if (!option.isAvailable || this.isSelected(option)) {
      return;
    }
    this.onSelectVoiceId(option.id);
    this.controller?.close();
  }

  private updatePressedVoice(option: ReaderSpeechVoiceOption, type: TouchType): void {
    if (!option.isAvailable) {
      this.pressedVoiceId = '';
      return;
    }
    if (type === TouchType.Down) {
      this.pressedVoiceId = option.id;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressedVoiceId = '';
    }
  }

  private resolveRowBackgroundColor(option: ReaderSpeechVoiceOption): ResourceColor {
    if (option.isAvailable && this.pressedVoiceId === option.id) {
      return this.resolvePressedBackgroundColor();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveThemeTokens(): ReaderModePanelThemeTokens {
    return resolveReaderModePanelTheme(this.presentation.readerTheme);
  }

  private resolveCardBackgroundColor(): string {
    return this.resolveThemeTokens().cardBackgroundColor;
  }

  private resolveControlBackgroundColor(): string {
    return this.resolveThemeTokens().inputBackgroundColor;
  }

  private resolvePressedBackgroundColor(): string {
    return this.resolveThemeTokens().pressedBackgroundColor;
  }

  private resolvePrimaryTextColor(): string {
    return this.resolveThemeTokens().primaryTextColor;
  }

  private resolveSecondaryTextColor(): string {
    return this.resolveThemeTokens().secondaryTextColor;
  }

  private resolveRowBorderRadius(index: number, total: number): BorderRadiuses {
    return this.resolveBorderRadius(this.resolveRowPosition(index, total));
  }

  private resolveBorderRadius(position: SettingsRowPosition): BorderRadiuses {
    if (position === 'single') {
      return { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 };
    }
    if (position === 'first') {
      return { topLeft: 18, topRight: 18, bottomLeft: 0, bottomRight: 0 };
    }
    if (position === 'last') {
      return { topLeft: 0, topRight: 0, bottomLeft: 18, bottomRight: 18 };
    }
    return { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 };
  }

  private resolveRowPosition(index: number, total: number): SettingsRowPosition {
    if (total <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === total - 1) {
      return 'last';
    }
    return 'middle';
  }
}
