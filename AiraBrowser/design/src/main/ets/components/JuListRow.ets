import { JuIcon } from './JuIcon'

@Component
export struct JuListRow {
  title: string = ''
  value: string = ''
  icon: Resource = $r('app.media.star')

  build() {
    Column() {
      Row() {
        JuIcon({
          name: this.icon,
          color: $r('app.color.muted_foreground')
        })
        Text(this.title)
          .fontSize($r('app.float.font_size_body'))
          .fontWeight($r('app.integer.font_weight_semibold'))
          .fontColor($r('app.color.foreground'))
          .margin({ left: $r('app.float.gap_list') })
        Blank()
        if (this.value.length > 0) {
          Text(this.value)
            .fontSize($r('app.float.font_size_body'))
            .fontWeight($r('app.integer.font_weight_semibold'))
            .fontColor($r('app.color.foreground'))
        }
      }
      .width('100%')
      .height($r('app.float.row_height_settings'))
      .padding({
        left: $r('app.float.padding_list'),
        right: $r('app.float.padding_nav')
      })

      Row()
        .width('100%')
        .height($r('app.float.divider_height'))
        .margin({ left: $r('app.float.padding_list_text') })
        .backgroundColor($r('app.color.divider'))
    }
    .width('100%')
  }
}
