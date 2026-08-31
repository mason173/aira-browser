import {
  BrowserLargeScreenWebZoomSnapshot,
  createBrowserLargeScreenWebZoomSnapshot
} from '../../../core/browser/BrowserLargeScreenWebZoomCoordinator';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_MIN_WIDTH_VP: number = 136;
const LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_MAX_WIDTH_VP: number = 240;
const LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_HORIZONTAL_PADDING_VP: number = 18;
const LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_VERTICAL_PADDING_VP: number = 10;
const LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_RADIUS_VP: number = 8;

@Component
export struct BrowserLargeScreenWebZoomNotification {
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY)
  private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY)
  private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY)
  private storedPrimaryTextColor: string = '#111318';
  @Prop snapshot: BrowserLargeScreenWebZoomSnapshot = createBrowserLargeScreenWebZoomSnapshot();

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Row() {
        Text(this.snapshot.shortcutNotificationLabel)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .constraintSize({
        minWidth: LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_MIN_WIDTH_VP,
        maxWidth: LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_MAX_WIDTH_VP
      })
      .padding({
        left: LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_HORIZONTAL_PADDING_VP,
        right: LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_HORIZONTAL_PADDING_VP,
        top: LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_VERTICAL_PADDING_VP,
        bottom: LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_VERTICAL_PADDING_VP
      })
      .backgroundColor(this.storedFloatingSurfaceColor)
      .border({ width: 1, color: this.storedDividerColor })
      .borderRadius(LARGE_SCREEN_WEB_ZOOM_NOTIFICATION_RADIUS_VP)
      .visibility(this.snapshot.shortcutNotificationVisible ? Visibility.Visible : Visibility.Hidden)
      .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
