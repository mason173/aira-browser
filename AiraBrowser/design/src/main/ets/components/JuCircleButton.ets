import { JuIconButton } from './JuIconButton'
import { JuCircleAction, juCircleLabel, juCircleSymbol } from './JuCircleAction'
import { JuCircleMaterialPlate } from './JuCircleMaterialPlate'

/** 标题栏以外的圆形操作。与官方菜单共用图标、语义和材质策略。 */
@Component
export struct JuCircleButton {
  @Prop action: JuCircleAction = JuCircleAction.Close
  @Prop available: boolean = true
  onTap: () => void = (): void => {}

  build() {
    Stack({ alignContent: Alignment.Center }) {
      JuCircleMaterialPlate()
      JuIconButton({
        symbol: juCircleSymbol(this.action),
        onTap: (): void => { if (this.available) { this.onTap() } }
      })
    }
    .width($r('app.float.icon_button_size'))
    .height($r('app.float.icon_button_size'))
    .enabled(this.available)
    .accessibilityText(juCircleLabel(this.action))
  }
}
