import { curves } from '@kit.ArkUI'
import { JuIcon } from './JuIcon'

/** 底部导航的一格：常态用描边图标，选中用填充图标。 */
export class TabBarItem {
  icon: Resource
  activeIcon: Resource

  constructor(icon: Resource, activeIcon: Resource) {
    this.icon = icon
    this.activeIcon = activeIcon
  }
}

/** 默认五个 Tab：收集箱、日历、习惯、倒数、专注。加 Tab 时由调用方传 items 覆盖。 */
function defaultItems(): TabBarItem[] {
  return [
    new TabBarItem($r('app.media.inbox'), $r('app.media.inbox_fill')),
    new TabBarItem($r('app.media.calendar_03'), $r('app.media.calendar_03_fill')),
    new TabBarItem($r('app.media.habit'), $r('app.media.habit_fill')),
    new TabBarItem($r('app.media.hourglass'), $r('app.media.hourglass_fill')),
    new TabBarItem($r('app.media.timer_01'), $r('app.media.timer_01_fill'))
  ]
}

/**
 * @deprecated 历史自绘胶囊，仅保留兼容；新 App 底部导航使用官方 HdsTabs 的 JuTabs 入口。
 * 底永远是深色，浅色深色模式一个样；选中项是一颗白色圆形，
 * 圈住当前这一格的图标。胶囊宽度跟页面内容区一样（左右各让 `padding_page_compact`），
 * 屏窄时一起收窄。一次显示几格按宽度断点定（最多 5 / 4 / 3 / 2 / 1），格子等分胶囊宽度；
 * 总格数超过可见格数就横向滑动，切 Tab 时选中的那一格会自己滚进看得见的地方。
 */
@Component
export struct JuTabBar {
  /** 当前选中项。 */
  @Prop @Watch('revealSelected') selected: number = 0
  /** 不传就用默认五个 Tab。 */
  @Prop items: TabBarItem[] = []
  onSelect: (index: number) => void = () => {}

  private scroller: Scroller = new Scroller()
  /** 组件可用的整条宽度，用来算能放下几格。 */
  @State viewWidth: number = 0

  build() {
    Column() {
      // 胶囊本体。整条 Scroll 铺满胶囊宽度，唯一的裁剪就是这颗圆角胶囊的圆角裁剪，
      // 滑到两端也是顺着圆角裁，不会露出直角。两端留白放在滚动内容里，不在胶囊上。
      Row() {
        Scroll(this.scroller) {
          Stack({ alignContent: Alignment.TopStart }) {
            // 白圆是单独一层，用 translate 滑到选中的那一格，切 Tab 时位移过去，不是跳过去。
            // 放在滚动内容里，跟着内容一起滚。压在图标行下面，图标画在圆上。
            Column()
              .width($r('app.float.tab_bar_plate_size'))
              .height($r('app.float.tab_bar_plate_size'))
              .borderRadius($r('app.float.tab_bar_plate_size'))
              .backgroundColor($r('app.color.tab_bar_plate'))
              .translate({ x: this.plateX(), y: this.plateY() })
              // 带一丢丢弹性：springMotion 阻尼比低于默认 0.86，滑过去会轻微过冲再回稳。
              .animation({ curve: curves.springMotion(0.35, 0.72) })
              .hitTestBehavior(HitTestMode.None)

            Row() {
              ForEach(this.list(), (item: TabBarItem, index: number) => {
                this.TabCell(item, index)
              }, (_item: TabBarItem, index: number) => `${index}`)
            }
            .width(this.contentWidth())
            .height('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width(this.contentWidth())
          .height('100%')
        }
        .width('100%')
        .height('100%')
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height($r('app.float.tab_bar_height'))
      .borderRadius($r('app.float.tab_bar_radius'))
      .backgroundColor($r('app.color.tab_bar_background'))
      .clip(true)
      .shadow({
        radius: this.readFloat('menu_shadow_radius'),
        color: $r('app.color.menu_shadow'),
        offsetX: 0,
        offsetY: this.readFloat('menu_shadow_offset')
      })
    }
    .width('100%')
    .height($r('app.float.tab_bar_reserved_height'))
    // 左右各让出内容区边距，胶囊宽度就跟列表内容区一样，屏窄时跟着收窄。
    .padding({
      left: $r('app.float.padding_page_compact'),
      right: $r('app.float.padding_page_compact')
    })
    .onAreaChange((_old: Area, next: Area) => {
      const width = this.areaNumber(next.width)
      if (width > 0 && width !== this.viewWidth) {
        this.viewWidth = width
        this.revealSelected()
      }
    })
  }

  @Builder
  TabCell(item: TabBarItem, index: number) {
    Column() {
      // 白圆单独一层画在下面，这里只放图标；选中格换成填充图标 + 深色，画在白圆上。
      JuIcon({
        name: this.selected === index ? item.activeIcon : item.icon,
        color: this.selected === index ? $r('app.color.tab_bar_active') : $r('app.color.tab_bar_inactive'),
        side: $r('app.float.tab_icon_size')
      })
    }
    .width(this.slotWidth())
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.onSelect(index)
    })
  }

  private list(): TabBarItem[] {
    return this.items.length > 0 ? this.items : defaultItems()
  }

  /** 胶囊宽度：组件宽减掉左右内容区边距。 */
  private capsuleWidth(): number {
    return this.viewWidth - this.readFloat('padding_page_compact') * 2
  }

  /** 一次显示几格：按胶囊宽度落断点，最少 1 格，最多不超过实际 Tab 数。 */
  private visibleCount(): number {
    const total = this.list().length
    if (total <= 0) {
      return 0
    }
    const cap = this.capsuleWidth()
    if (cap <= 0) {
      return Math.min(5, total)
    }
    let fit = 1
    if (cap >= this.readFloat('tab_bar_break_5')) {
      fit = 5
    } else if (cap >= this.readFloat('tab_bar_break_4')) {
      fit = 4
    } else if (cap >= this.readFloat('tab_bar_break_3')) {
      fit = 3
    } else if (cap >= this.readFloat('tab_bar_break_2')) {
      fit = 2
    }
    return Math.max(1, Math.min(fit, total))
  }

  /** 每格宽度：可见格数等分胶囊宽度。 */
  private slotWidth(): number {
    const visible = this.visibleCount()
    if (visible <= 0) {
      return 0
    }
    const cap = this.capsuleWidth()
    if (cap <= 0) {
      return this.readFloat('tab_bar_plate_size')
    }
    return cap / visible
  }

  /** 整条内容的宽（全部 Tab），用来算最大滚动量。 */
  private contentWidth(): number {
    return this.list().length * this.slotWidth()
  }

  /** 白圆在内容里的横坐标：让圆心对齐选中格的中心。 */
  private plateX(): number {
    const slot = this.slotWidth()
    const plate = this.readFloat('tab_bar_plate_size')
    return this.selected * slot + (slot - plate) / 2
  }

  /** 白圆纵向居中：(胶囊高 − 圆直径) / 2。 */
  private plateY(): number {
    const height = this.readFloat('tab_bar_height')
    const plate = this.readFloat('tab_bar_plate_size')
    const y = (height - plate) / 2
    return y > 0 ? y : 0
  }

  /** 把选中格滚进看得见的地方，能居中就居中，两端贴边。 */
  private revealSelected(): void {
    const total = this.list().length
    const visible = this.visibleCount()
    const cap = this.capsuleWidth()
    const slot = this.slotWidth()
    if (total <= 0 || visible <= 0 || cap <= 0 || slot <= 0) {
      return
    }
    const max = Math.max(0, total * slot - cap)
    let target = this.selected * slot - (cap - slot) / 2
    target = Math.max(0, Math.min(target, max))
    const shown = this.scroller.currentOffset().xOffset
    if (Math.abs(target - shown) < 1) {
      return
    }
    this.scroller.scrollTo({
      xOffset: target,
      yOffset: 0,
      animation: { duration: 280, curve: Curve.EaseOut }
    })
  }

  private readFloat(name: string): number {
    const host = this.getUIContext().getHostContext()
    if (!host) {
      return 0
    }
    try {
      return this.getUIContext().px2vp(host.resourceManager.getNumberByName(name))
    } catch (_err) {
      return 0
    }
  }

  private areaNumber(value: Length): number {
    if (typeof value === 'number') {
      return value
    }
    const parsed = parseFloat(`${value}`)
    return Number.isFinite(parsed) ? parsed : 0
  }
}
