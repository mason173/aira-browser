import { JuIcon } from './JuIcon'

/**
 * 圆形头像。账号头像统一走这一个：有头像图就铺满裁圆，没有就回落到人像图标。
 * 侧栏那颗按钮和设置页顶部都用它，保证两处长得一样，不要在页面里各画一套。
 * 默认尺寸是侧栏那颗的大小（32vp 圆），设置页顶部也用这个默认值，两处一样大。
 */
@Component
export struct JuAvatar {
  /** 头像图地址。空则显示人像图标。 */
  @Prop url: string = ''
  /** 本地图像资源；优先显示已有 url，均未传时保留默认人像。 */
  @Prop portrait: Resource | null = null
  @Prop side: Resource = $r('app.float.sidebar_avatar_size')
  @Prop radius: Resource = $r('app.float.sidebar_avatar_radius')
  /** 圆底颜色。没头像时露出来当图标底。 */
  @Prop plate: ResourceColor = $r('app.color.secondary')
  /** 没头像时那颗人像图标的颜色。 */
  @Prop iconColor: ResourceColor = $r('app.color.muted_foreground')
  @Prop iconSide: Length = $r('app.float.icon_size_secondary')

  build() {
    Column() {
      if (this.url.length > 0) {
        Image(this.url)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.radius)
      } else if (this.portrait !== null) {
        Image(this.portrait)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.radius)
      } else {
        JuIcon({
          name: $r('app.media.user_fill'),
          color: this.iconColor,
          side: this.iconSide
        })
      }
    }
    .width(this.side)
    .height(this.side)
    .borderRadius(this.radius)
    .backgroundColor(this.plate)
    .clip(true)
    .justifyContent(FlexAlign.Center)
  }
}
