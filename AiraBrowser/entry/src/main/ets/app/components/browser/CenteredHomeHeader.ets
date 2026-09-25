import {
  CENTERED_HOME_HEADER_BOTTOM_GAP,
  CENTERED_HOME_SEARCH_HEIGHT,
  CENTERED_HOME_WORDMARK_HEIGHT,
  CENTERED_HOME_WORDMARK_SEARCH_GAP,
  CENTERED_HOME_WORDMARK_WIDTH
} from '../../../features/newtab/CenteredHomeShortcutLayoutPolicy';
import { AiraIcon } from '../common/AiraIcon';

const CENTERED_HOME_SEARCH_RADIUS: number = 24;
const CENTERED_HOME_SEARCH_BORDER_WIDTH: number = 2;

/**
 * Wordmark and search field for the centered homepage.
 *
 * The field does not own a search page. Tapping it asks the shell to open the same top search
 * session used by the split toolbar. Scan reuses the existing QR action.
 */
@Component
export struct CenteredHomeHeader {
  @Prop textColor: ResourceColor = '#111111';
  @Prop secondaryTextColor: ResourceColor = '#8A8A8E';
  @Prop fieldBackgroundColor: ResourceColor = Color.Transparent;
  onOpenSearch: () => void = () => {};
  onScan: () => void = () => {};

  build() {
    Column({ space: CENTERED_HOME_WORDMARK_SEARCH_GAP }) {
      Image($rawfile('home_centered_wordmark.svg'))
        .width(CENTERED_HOME_WORDMARK_WIDTH)
        .height(CENTERED_HOME_WORDMARK_HEIGHT)
        .objectFit(ImageFit.Contain)
        .fillColor(this.textColor)
        .draggable(false)

      Stack() {
        Row()
          .width('100%')
          .height('100%')
          .onClick(() => {
            this.onOpenSearch();
          })

        Row() {
          Text('搜索或输入网址')
            .layoutWeight(1)
            .fontSize(16)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textAlign(TextAlign.Start)
            .hitTestBehavior(HitTestMode.None)

          Button() {
            AiraIcon({
              airaIconId: 'browser.toolbar.scanQr',
              iconSize: 20,
              iconColor: this.textColor
            })
          }
          .width(36)
          .height(36)
          .type(ButtonType.Circle)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .backgroundColor(Color.Transparent)
          .stateEffect(false)
          .onClick(() => {
            this.onScan();
          })
        }
        .width('100%')
        .height('100%')
        .padding({ left: 18, right: 6 })
        .alignItems(VerticalAlign.Center)
        .hitTestBehavior(HitTestMode.Transparent)
      }
      .width('100%')
      .height(CENTERED_HOME_SEARCH_HEIGHT)
      .border({ width: CENTERED_HOME_SEARCH_BORDER_WIDTH, color: this.textColor })
      .borderRadius(CENTERED_HOME_SEARCH_RADIUS)
      .backgroundColor(this.fieldBackgroundColor)
      .clip(true)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding({ bottom: CENTERED_HOME_HEADER_BOTTOM_GAP })
  }
}
