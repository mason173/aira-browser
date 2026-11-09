import { JuIcon } from './JuIcon'

/** 双麦穗装饰的产品短语。内容由宿主提供，不预设奖项、名次或外部推荐。 */
@Component
export struct JuLaurelBadges {
  @Prop labels: string[] = []

  build() {
    Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Center }) {
      ForEach(this.labels, (label: string) => {
        Row({ space: $r('app.float.laurel_copy_gap') }) {
          JuIcon({ name: $r('app.media.laurel_left'), color: $r('app.color.foreground'),
            side: $r('app.float.laurel_height'), iconWidth: $r('app.float.laurel_width') })
            .accessibilityLevel('no-hide-descendants')
          Text(label)
            .fontSize($r('app.float.font_size_caption'))
            .lineHeight($r('app.float.line_height_caption'))
            .fontWeight($r('app.integer.font_weight_semibold'))
            .fontColor($r('app.color.foreground'))
            .textAlign(TextAlign.Center)
          JuIcon({ name: $r('app.media.laurel_right'), color: $r('app.color.foreground'),
            side: $r('app.float.laurel_height'), iconWidth: $r('app.float.laurel_width') })
            .accessibilityLevel('no-hide-descendants')
        }
        .width('50%')
        .padding({ left: $r('app.float.laurel_item_inset'), right: $r('app.float.laurel_item_inset'),
          bottom: $r('app.float.laurel_item_bottom') })
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .accessibilityLevel('yes')
        .accessibilityText(label)
      }, (label: string): string => label)
    }
    .width('100%')
  }
}
