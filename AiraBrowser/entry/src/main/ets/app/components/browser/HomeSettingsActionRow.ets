import {
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { BrowserFloatingGlassMaterialSurface } from './BrowserFloatingGlassMaterialSurface';
import { resolveBrowserFloatingGlassMaterialTintForMode } from './BrowserFloatingGlassMaterialTokens';

const HOME_SETTINGS_ACTION_CONTENT_INSET: number = 10;
const HOME_SETTINGS_ACTION_BUTTON_WIDTH: number = 78;
const HOME_SETTINGS_ACTION_BUTTON_HEIGHT: number = 32;

@Component
export struct HomeSettingsActionRow {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop contentWidth: number = 1;

  onOpenSettings: () => void = () => {};

  build() {
    Row() {
      Button() {
        BrowserFloatingGlassMaterialSurface({
          surfaceWidth: HOME_SETTINGS_ACTION_BUTTON_WIDTH,
          surfaceHeight: HOME_SETTINGS_ACTION_BUTTON_HEIGHT,
          surfaceRadius: HOME_SETTINGS_ACTION_BUTTON_HEIGHT / 2,
          tintColor: resolveBrowserFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
        }) {
          Text('设置')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
        }
      }
        .width(HOME_SETTINGS_ACTION_BUTTON_WIDTH)
        .height(HOME_SETTINGS_ACTION_BUTTON_HEIGHT)
        .padding(0)
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(HOME_SETTINGS_ACTION_BUTTON_HEIGHT / 2)
        .stateEffect(true)
        .onClick(() => {
          this.onOpenSettings();
        })
    }
    .width(Math.max(1, this.contentWidth))
    .alignSelf(ItemAlign.Center)
    .padding({
      left: HOME_SETTINGS_ACTION_CONTENT_INSET,
      right: HOME_SETTINGS_ACTION_CONTENT_INSET,
      top: 2,
      bottom: 14
    })
    .justifyContent(FlexAlign.Center)
  }
}
