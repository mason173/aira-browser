import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';
import { FloatingGlassMaterialSurface } from '../common/FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from '../common/FloatingGlassMaterialTokens';

const HISTORY_SEARCH_INPUT_FOCUS_ID: string = 'aira-history-search-input';
const HISTORY_SEARCH_INPUT_FOCUS_DELAY_MS: number = 48;

@Component
export struct HistoryManagerSearchHeader {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  private inputFocusTimer: number = -1;
  @Prop query: string = '';
  onQueryChange: (query: string) => void = (_query: string) => {};
  onClose: () => void = () => {};

  aboutToAppear(): void {
    this.scheduleInputFocus();
  }

  aboutToDisappear(): void {
    this.clearInputFocusTimer();
  }

  build() {
    Row({ space: 8 }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: 40,
        surfaceHeight: 40,
        surfaceRadius: 20,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Button() {
          SymbolGlyph($r('sys.symbol.chevron_left'))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.storedPrimaryTextColor])
        }
        .width('100%')
        .height('100%')
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(20)
        .accessibilityText('退出历史搜索')
        .stateEffect(true)
        .onClick(() => {
          this.onClose();
        })
      }

      Stack({ alignContent: Alignment.Center }) {
        FloatingGlassMaterialSurface({
          surfaceWidth: '100%',
          surfaceHeight: 48,
          surfaceRadius: 18,
          tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
        }) {
          Row({ space: 8 }) {
            SymbolGlyph($r('sys.symbol.magnifyingglass'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .fontColor([this.storedSecondaryTextColor])

            TextInput({ text: this.query, placeholder: '搜索历史记录' })
              .id(HISTORY_SEARCH_INPUT_FOCUS_ID)
              .layoutWeight(1)
              .height(40)
              .type(InputType.Normal)
              .enterKeyType(EnterKeyType.Search)
              .fontSize(15)
              .fontColor(this.storedPrimaryTextColor)
              .placeholderColor(this.storedSecondaryTextColor)
              .caretColor(this.storedAccentColor)
              .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
              .padding({ left: 0, right: 0 })
              .focusOnTouch(true)
              .enableKeyboardOnFocus(true)
              .onAppear(() => {
                this.scheduleInputFocus();
              })
              .onChange((value: string) => {
                this.onQueryChange(value);
              })

            if (this.query.length > 0) {
              Button() {
                SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
                  .fontSize(18)
                  .fontWeight(FontWeight.Medium)
                  .fontColor([this.storedSecondaryTextColor])
              }
              .width(32)
              .height(32)
              .type(ButtonType.Circle)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
              .accessibilityText('清除历史搜索')
              .stateEffect(true)
              .onClick(() => {
                this.onQueryChange('');
              })
            }
          }
          .width('100%')
          .height(48)
          .padding({ left: 14, right: 10 })
        }
      }
      .layoutWeight(1)
      .height(48)
      .borderRadius(18)
    }
    .width('100%')
    .height(64)
    .padding({
      left: APP_STANDARD_HORIZONTAL_PADDING,
      right: APP_STANDARD_HORIZONTAL_PADDING,
      top: 8,
      bottom: 8
    })
  }

  private scheduleInputFocus(): void {
    this.clearInputFocusTimer();
    this.inputFocusTimer = setTimeout(() => {
      this.inputFocusTimer = -1;
      focusControl.requestFocus(HISTORY_SEARCH_INPUT_FOCUS_ID);
    }, HISTORY_SEARCH_INPUT_FOCUS_DELAY_MS);
  }

  private clearInputFocusTimer(): void {
    if (this.inputFocusTimer < 0) {
      return;
    }
    clearTimeout(this.inputFocusTimer);
    this.inputFocusTimer = -1;
  }
}
