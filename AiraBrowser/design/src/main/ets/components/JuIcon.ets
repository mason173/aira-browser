import { drawing } from '@kit.ArkGraphics2D'

@Component
export struct JuIcon {
  @Prop name: Resource = $r('app.media.star')
  @Prop color: ResourceColor = $r('app.color.foreground')
  @Prop side: Length = $r('app.float.icon_size')
  /** 非正方形 SVG 的宽度；留空时沿用 side，side 仍决定高度。 */
  @Prop iconWidth: Length = ''

  build() {
    Image(this.name)
      .width(this.iconWidth === '' ? this.side : this.iconWidth)
      .height(this.side)
      .objectFit(ImageFit.Contain)
      .draggable(false)
      .supportSvg2(true)
      .colorFilter(drawing.ColorFilter.createBlendModeColorFilter(
        drawing.Tool.makeColorFromResourceColor(this.color),
        drawing.BlendMode.SRC_IN
      ))
  }
}
