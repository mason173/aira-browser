import { AppEmptyState } from '../common/AppEmptyState';

@Component
export struct CustomHomepageUnavailableSurface {
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  onOpenSettings: () => void = () => {};

  build() {
    Column({ space: 18 }) {
      AppEmptyState({
        icon: $r('sys.symbol.exclamationmark_triangle_fill'),
        title: this.title,
        message: this.message,
        topPadding: 0,
        bottomPadding: 0,
        fillHeight: false,
        primaryTextColor: this.primaryTextColor,
        secondaryTextColor: this.secondaryTextColor
      })

      Button('重新设置')
        .height(38)
        .type(ButtonType.Normal)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.primaryTextColor)
        .onClick(() => {
          this.onOpenSettings();
        })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding({ left: 32, right: 32 })
  }
}
