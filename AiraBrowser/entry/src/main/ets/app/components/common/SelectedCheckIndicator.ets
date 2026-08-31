import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct SelectedCheckIndicator {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop indicatorSize: number = 22;
  @Prop checkmarkSize: number = 13;
  @Prop isEnabled: boolean = true;
  @Prop indicatorColor: ResourceColor = '';
  @Prop checkmarkColor: ResourceColor = '';

  build() {
    Row() {
      SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(this.checkmarkSize)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.resolveCheckmarkColor()])
    }
    .width(this.indicatorSize)
    .height(this.indicatorSize)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.resolveBackgroundColor())
    .borderRadius(this.indicatorSize / 2)
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.isEnabled
      ? this.resolveIndicatorColor()
      : this.storedSecondaryTextColor;
  }

  private resolveIndicatorColor(): ResourceColor {
    return `${this.indicatorColor}`.length > 0 ? this.indicatorColor : this.storedAccentColor;
  }

  private resolveCheckmarkColor(): ResourceColor {
    return `${this.checkmarkColor}`.length > 0 ? this.checkmarkColor : this.storedOnPrimaryColor;
  }
}
