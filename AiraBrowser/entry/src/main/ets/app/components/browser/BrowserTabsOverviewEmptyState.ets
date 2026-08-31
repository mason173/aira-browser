import { BrowserTabsOverviewSection } from '../../../core/browser/tabsOverview/BrowserTabsOverviewSectionPolicy';
import { AiraIcon } from '../common/AiraIcon';

const PRIVACY_EMPTY_STATE_ICON_SIZE: number = 56;
const PRIVACY_EMPTY_STATE_CONTENT_WIDTH: number = 300;

@Component
export struct BrowserTabsOverviewEmptyState {
  @Prop selectedSection: BrowserTabsOverviewSection = 'tabs';
  @Prop textColor: ResourceColor = '';

  build() {
    Column({ space: 14 }) {
      if (this.selectedSection === 'privacy') {
        AiraIcon({
          airaIconId: 'browser.toolbar.privacyMode',
          iconSize: PRIVACY_EMPTY_STATE_ICON_SIZE,
          iconColor: this.textColor
        })
          .margin({ bottom: 4 })

        Text('这里是你的隐私空间')
          .width('100%')
          .constraintSize({ maxWidth: PRIVACY_EMPTY_STATE_CONTENT_WIDTH })
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
          .maxLines(2)

        Text('新打开的网页会使用独立的临时会话，不写入常规浏览历史。关闭全部隐私标签页后，本次会话数据会按你的隐私设置处理。')
          .width('100%')
          .constraintSize({ maxWidth: PRIVACY_EMPTY_STATE_CONTENT_WIDTH })
          .fontSize(14)
          .lineHeight(21)
          .fontColor(this.textColor)
          .textAlign(TextAlign.Center)
      } else {
        Text('暂无标签页')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.textColor)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }
}
