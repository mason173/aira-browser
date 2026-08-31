import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const SYNC_FORM_FIELD_HEIGHT: number = 48;
const SYNC_FORM_FIELD_RADIUS: number = 18;

@Component
export struct SyncFormField {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop label: ResourceStr = '';
  @Prop placeholder: ResourceStr = '';
  @Link text: string;
  @Prop secure: boolean = false;
  @Prop inputType: InputType = InputType.Normal;
  @Prop helperText: ResourceStr = '';
  @Prop isEnabled: boolean = true;
  @Prop inputBackgroundColor: string = '';
  onChange: (value: string) => void = (_value: string) => {};

  build() {
    Column({ space: 8 }) {
      Text(this.label)
        .width('100%')
        .fontSize(14)
        .fontColor(this.storedSecondaryTextColor)

      TextInput({ text: $$this.text, placeholder: this.placeholder })
        .width('100%')
        .height(SYNC_FORM_FIELD_HEIGHT)
        .type(this.secure ? InputType.Password : this.inputType)
        .showPasswordIcon(this.secure)
        .fontSize(16)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .caretColor(this.storedAccentColor)
        .backgroundColor(this.inputBackgroundColor.length > 0 ? this.inputBackgroundColor : this.storedSurfaceBackgroundColor)
        .borderRadius(SYNC_FORM_FIELD_RADIUS)
        .padding({ left: 14, right: 14 })
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.48)
        .onChange((value: string) => {
          if (this.isEnabled) {
            this.onChange(value);
          }
        })

      if (`${this.helperText}`.length > 0) {
        Text(this.helperText)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.storedSecondaryTextColor)
      }
    }
    .width('100%')
  }
}
