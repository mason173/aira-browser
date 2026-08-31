import { AppIconResources } from '../../../core/resources/AppIconResources';
import { BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
import { AiraIcon } from '../common/AiraIcon';

@Component
export struct BrowserLoadingReloadIcon {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @Prop iconSize: number = 22;
  @Prop iconOpacity: number = 1;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: 'browser.toolbar.refresh',
        iconSize: this.iconSize,
        iconColor: AppIconResources.chromeStrokeColor(
          AppIconResources.chromeToneForResolvedThemeMode(this.storedResolvedThemeMode)
        )
      })
        .opacity(this.iconOpacity)
    }
    .width(this.iconSize)
    .height(this.iconSize)
  }
}
