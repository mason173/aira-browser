import { HdsTabs, HdsTabsController, HdsTabsFloatingStyle, hdsMaterial } from '@kit.UIDesignKit'
import { juCircleMaterial } from './JuCircleAction'

/**
 * 独立圆形按钮的内部材质底。仅在此处适配官方底部浮动材质，不对页面导出。
 *
 * 尺寸与投影跟标题栏里的圆形操作对齐：用 `circle_action_size`（44vp，比 48 的图标按钮小一档、
 * 比 40 的悬浮按钮大一档，实测与标题栏里的打勾同一个大小），加一个軽的弥散投影
 * （`ShadowStyle.OUTER_DEFAULT_SM`，LG 太深）。否则标题栏以外的圆钮会跟标题栏里的不一样大小、不一样重。
 */
@Component
export struct JuCircleMaterialPlate {
  /**
   * 胶囊模式：>0 时按这个 vp 宽度画一条胶囊（高度仍是 circle_action_size）。
   * 传具体数字而不是 '100%'：百分比在内容撑开的容器里会按“可用宽度”解析，
   * 结果就是一条拉满整行的长胶囊（踩过）。0 = 圆形。
   */
  @Prop widthVp: number = 0
  private controller: HdsTabsController = new HdsTabsController()
  @State plateSize: number = 0
  @State materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE

  aboutToAppear(): void {
    const ui = this.getUIContext()
    const host = ui.getHostContext()
    if (host !== undefined) {
      try {
        this.plateSize = ui.px2vp(host.resourceManager.getNumberByName('circle_action_size'))
      } catch (_error) {
        this.materialLevel = hdsMaterial.MaterialLevel.SMOOTH
      }
    }
    const types: Array<hdsMaterial.MaterialType> = hdsMaterial.getSystemMaterialTypes()
    if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) < 0) {
      this.materialLevel = hdsMaterial.MaterialLevel.SMOOTH
    }
  }

  build() {
    HdsTabs({ controller: this.controller }) {
      TabContent() {
        Column().width('100%').height('100%')
      }
      .tabBar(this.PlateBar)
    }
    .vertical(false)
    .scrollable(false)
    .barMode(BarMode.Fixed)
    .barPosition(BarPosition.End)
    .barOverlap(true)
    .barWidth(this.widthVp > 0 ? this.widthVp : this.plateSize)
    .barHeight(this.plateSize)
    .barBackgroundColor(Color.Transparent)
    .barBackgroundBlurStyle(BlurStyle.NONE)
    .barFloatingStyle(this.plateStyle())
    .width(this.widthVp > 0 ? this.widthVp : $r('app.float.circle_action_size'))
    .height($r('app.float.circle_action_size'))
    .borderRadius($r('app.float.circle_action_radius'))
    .shadow(ShadowStyle.OUTER_DEFAULT_SM)
    .clip(true)
    .backgroundColor(this.materialLevel === hdsMaterial.MaterialLevel.SMOOTH ?
      $r('app.color.secondary') : Color.Transparent)
    .backgroundBlurStyle(this.materialLevel === hdsMaterial.MaterialLevel.SMOOTH ?
      BlurStyle.Thin : BlurStyle.NONE)
    .hitTestBehavior(HitTestMode.BLOCK_DESCENDANTS)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  PlateBar() {
    Column().width('100%').height('100%').backgroundColor(Color.Transparent)
  }

  private plateStyle(): HdsTabsFloatingStyle {
    const side: number = this.plateSize
    const width: Length = this.widthVp > 0 ? this.widthVp : side
    const style: HdsTabsFloatingStyle = {
      barSideMargin: 0,
      barBottomMargin: 0,
      barOpacity: 1,
      barWidth: { smallWidth: width, mediumWidth: width, largeWidth: width }
    }
    style.systemMaterialEffect = juCircleMaterial(this.materialLevel)
    return style
  }
}
