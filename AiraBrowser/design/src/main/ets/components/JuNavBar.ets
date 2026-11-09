import { JuIcon } from './JuIcon'

@Component
export struct JuNavBar {
  title: string = ''

  build() {
    Row() {
      JuIcon({
        name: $r('app.media.arrow_left_01'),
        color: $r('app.color.muted_foreground')
      })
      Text(this.title)
        .layoutWeight(1)
        .textAlign(TextAlign.Center)
        .fontSize($r('app.float.font_size_subtitle'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
      Column()
        .width($r('app.float.icon_size'))
        .height($r('app.float.icon_size'))
    }
    .width('100%')
    .padding({
      left: $r('app.float.padding_nav'),
      right: $r('app.float.padding_nav')
    })
  }
}
