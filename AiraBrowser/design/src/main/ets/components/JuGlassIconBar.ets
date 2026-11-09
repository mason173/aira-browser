import { JuCircleAction, juCircleLabel, juCircleSymbol } from './JuCircleAction'
import { JuCircleMaterialPlate } from './JuCircleMaterialPlate'
import { JuIconButton } from './JuIconButton'

/**
 * 悬浮图标胶囊条：一条沉浸光感玻璃胶囊，横排若干个圆形图标操作。
 *
 * 为什么不用 `systemMaterial`：那是普通组件的沉浸光感入口，官方限定它只在
 * Navigation/NavDestination 标题栏里生效；这条胶囊在正文里，所以跟 `JuCircleButton`
 * 一样用 HdsTabs 的悬浮材质——同一档材质、同一个投影，一行排开就是一整条胶囊。
 *
 * 宽度是**算出来的具体 vp**（每项一个 `itemSize` 的方形触控区，两端再加 `barInset`），
 * 不交给百分比：百分比在内容撑开的容器里会解析成"可用宽度"，胶囊就会拉满整行。
 * 高度与圆形操作一致，两者摆在一起才成套。
 */
@Component
export struct JuGlassIconBar {
  /** 胶囊里的圆形操作，顺序即展示顺序。图标与无障碍名称来自 JuCircleAction。 */
  @Prop @Watch('measure') actions: JuCircleAction[] = []
  /** 与 actions 等长时逐项控制可用；长度不等表示都可点。 */
  @Prop available: boolean[] = []
  /** 每个图标的边长＝触控区；默认与圆形操作同高。 */
  @Prop @Watch('measure') itemSize: Resource = $r('app.float.circle_action_size')
  /** 胶囊两端的内距。 */
  @Prop @Watch('measure') barInset: Resource = $r('app.float.gap_title_body')
  onAction: (action: JuCircleAction, index: number) => void =
    (_action: JuCircleAction, _index: number): void => {}
  /** 算出来的胶囊宽度（vp）；0 表示还没量出来。 */
  @State private barWidth: number = 0

  aboutToAppear(): void {
    this.measure()
  }

  private vpOf(res: Resource): number {
    const ui = this.getUIContext()
    const host = ui.getHostContext()
    if (host === undefined) {
      return 0
    }
    try {
      return ui.px2vp(host.resourceManager.getNumber(res.id))
    } catch (_error) {
      return 0
    }
  }

  private measure(): void {
    const item: number = this.vpOf(this.itemSize)
    const inset: number = this.vpOf(this.barInset)
    this.barWidth = this.actions.length * item + 2 * inset
  }

  private enabledAt(index: number): boolean {
    return this.available.length !== this.actions.length || this.available[index]
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      JuCircleMaterialPlate({ widthVp: this.barWidth })

      Row() {
        ForEach(this.actions, (action: JuCircleAction, index: number) => {
          JuIconButton({
            symbol: juCircleSymbol(action),
            side: this.itemSize,
            color: this.enabledAt(index) ? $r('app.color.foreground') : $r('app.color.muted_foreground'),
            onTap: (): void => { if (this.enabledAt(index)) { this.onAction(action, index) } }
          })
            .accessibilityText(juCircleLabel(action))
        }, (action: JuCircleAction, index: number): string => `${index}-${action}`)
      }
      .padding({ left: this.barInset, right: this.barInset })
      .hitTestBehavior(HitTestMode.Transparent)
    }
    .width(this.barWidth)
    .height(this.itemSize)
  }
}
