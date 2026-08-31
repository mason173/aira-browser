import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { TopFloatingSurface } from './TopFloatingSurface';
import { FloatingGlassMaterialSurface } from './FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from './FloatingGlassMaterialTokens';

export const FLOATING_PROMPT_CARD_HEIGHT: number = 68;
export const FLOATING_PROMPT_CARD_ICON_SIZE: number = 40;
export const FLOATING_PROMPT_CARD_ACTION_HEIGHT: number = 34;
export const FLOATING_PROMPT_CARD_ACTION_WIDTH: number = 64;
export const FLOATING_PROMPT_CARD_PROGRESS_HEIGHT: number = 4;
export const FLOATING_PROMPT_CARD_TITLE_SIZE: number = 15;
export const FLOATING_PROMPT_CARD_SUBTITLE_SIZE: number = 12;
export const FLOATING_PROMPT_CARD_ICON_RADIUS: number = 12;
export const FLOATING_PROMPT_CARD_TOP_GAP: number = 32;
export const FLOATING_PROMPT_CARD_HORIZONTAL_MARGIN: number = 14;
export const FLOATING_PROMPT_CARD_HIDDEN_OFFSET_Y: number = -72;
export const FLOATING_PROMPT_CARD_STACK_GAP: number = 10;
export const FLOATING_PROMPT_CARD_ANIMATION_MS: number = 520;

@Component
export struct FloatingPromptCard {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  @Prop subtitleMaxLines: number = 1;
  @Prop loading: boolean = false;
  @Prop progress: number = 0;
  @BuilderParam leading: () => void = this.emptyBuilder;
  @BuilderParam trailing: () => void = this.emptyBuilder;

  build() {
    TopFloatingSurface({
      heightVp: FLOATING_PROMPT_CARD_HEIGHT,
      paddingLeftVp: 12,
      paddingRightVp: 10,
      paddingTopVp: 12,
      paddingBottomVp: 12
    }) {
      Row({ space: 10 }) {
        this.leading()

        Column({ space: this.loading ? 8 : 3 }) {
          Text(this.title)
            .width('100%')
            .fontSize(FLOATING_PROMPT_CARD_TITLE_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          if (this.loading) {
            this.buildProgressTrack()
          } else {
            Text(this.subtitle)
              .width('100%')
              .fontSize(FLOATING_PROMPT_CARD_SUBTITLE_SIZE)
              .fontColor(this.storedSecondaryTextColor)
              .maxLines(this.resolveSubtitleMaxLines())
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        this.trailing()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private buildProgressTrack() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(FLOATING_PROMPT_CARD_PROGRESS_HEIGHT)
        .borderRadius(FLOATING_PROMPT_CARD_PROGRESS_HEIGHT / 2)
        .backgroundColor(this.storedPressedBackgroundColor)

      Row()
        .width(`${this.resolveProgressPercent()}%`)
        .height(FLOATING_PROMPT_CARD_PROGRESS_HEIGHT)
        .borderRadius(FLOATING_PROMPT_CARD_PROGRESS_HEIGHT / 2)
        .backgroundColor(this.storedAccentColor)
    }
    .width('100%')
    .height(FLOATING_PROMPT_CARD_PROGRESS_HEIGHT)
    .animation({
      duration: 160,
      curve: Curve.EaseOut
    })
  }

  private resolveProgressPercent(): number {
    return Math.max(3, Math.min(100, Math.round(this.progress)));
  }

  private resolveSubtitleMaxLines(): number {
    return Math.max(1, Math.round(this.subtitleMaxLines));
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
export struct FloatingPromptActionButton {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop text: string = '';
  @Prop actionEnabled: boolean = true;
  onAction: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: FLOATING_PROMPT_CARD_ACTION_WIDTH,
        surfaceHeight: FLOATING_PROMPT_CARD_ACTION_HEIGHT,
        surfaceRadius: FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Button(this.text)
          .width('100%')
          .height('100%')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedAccentColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .borderRadius(FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2)
          .stateEffect(true)
          .enabled(this.actionEnabled)
          .onClick(() => {
            if (this.actionEnabled) {
              this.onAction();
            }
          })
      }
    }
    .width(FLOATING_PROMPT_CARD_ACTION_WIDTH)
    .height(FLOATING_PROMPT_CARD_ACTION_HEIGHT)
    .opacity(this.actionEnabled ? 1 : 0.42)
  }
}

@Component
export struct FloatingPromptMenuButton {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop text: string = '';
  @BuilderParam menuContent: () => void = this.emptyBuilder;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: FLOATING_PROMPT_CARD_ACTION_WIDTH,
        surfaceHeight: FLOATING_PROMPT_CARD_ACTION_HEIGHT,
        surfaceRadius: FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Button(this.text)
          .width('100%')
          .height('100%')
          .type(ButtonType.Normal)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedAccentColor)
          .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
          .borderRadius(FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2)
          .stateEffect(true)
          .bindMenu(this.menuContent())
      }
    }
    .width(FLOATING_PROMPT_CARD_ACTION_WIDTH)
    .height(FLOATING_PROMPT_CARD_ACTION_HEIGHT)
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
export struct FloatingPromptCloseButton {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  onAction: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: FLOATING_PROMPT_CARD_ACTION_HEIGHT,
        surfaceHeight: FLOATING_PROMPT_CARD_ACTION_HEIGHT,
        surfaceRadius: FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Button() {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.storedPrimaryTextColor])
        }
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(FLOATING_PROMPT_CARD_ACTION_HEIGHT / 2)
        .stateEffect(true)
        .onClick(() => {
          this.onAction();
        })
      }
    }
    .width(FLOATING_PROMPT_CARD_ACTION_HEIGHT)
    .height(FLOATING_PROMPT_CARD_ACTION_HEIGHT)
  }
}
