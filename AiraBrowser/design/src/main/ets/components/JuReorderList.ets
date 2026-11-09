import { LengthMetrics } from '@kit.ArkUI'
import { BusinessError } from '@kit.BasicServicesKit'
import { vibrator } from '@kit.SensorServiceKit'
import { JuIcon } from './JuIcon'
import { JuReorderDataSource } from './JuReorderDataSource'

/**
 * 通用长按排序。customRows 卡片模式默认可排序，统一卡片边界、抬起圆角和单次振动。
 * 设置行模式保留左滑删除与编辑开关；两种形态共用系统 List 和沉浸滚动。
 */
@Component
export struct JuReorderList {
  @Prop @Watch('syncItems') items: string[] = []
  /** 长列表按视口创建；默认保留现有宿主的 ForEach 行为。 */
  @Prop lazy: boolean = false
  @Prop counts: number[] = []
  /** null 采用模式默认值：卡片直接排序，设置行等待编辑。false 可临时禁用排序。 */
  @Prop editing: boolean | null = null
  /** 自定义卡片行使用 items 作为稳定 key；空数组时显示单个正文槽。 */
  @Prop customRows: boolean = false
  /**
   * 空数组正文槽的替换键。金额变了但没有新增行时，换这个键重建正文。
   * 留空则正文槽保持原来的单行，不参与排序。
   */
  @Prop contentKey: string = ''
  @Prop rowGap: Resource | null = null
  @Prop horizontalInset: Resource | null = null
  /** 排序抬起效果作用在 ListItem 上，圆角需与自定义卡片一致。 */
  @Prop rowRadius: Resource = $r('app.float.list_detail_card_radius')
  @Prop hapticFeedback: boolean = true
  @Prop priorityGestureTags: string[] = []
  @BuilderParam rowContent: (key: string, index: number, radius: Resource) => void = this.EmptyRow
  @BuilderParam content: () => void = this.Empty
  scroller: Scroller = new Scroller()
  @Prop bottomInset: Resource = $r('app.float.padding_screen_bottom')
  onScrollStop: () => void = (): void => {}
  onDelete: (index: number) => void = (_index: number): void => {}
  /**
   * 点一行。设置行模式用，卡片刻意不走这里（卡片自己处理点击，
   * 长按菜单、按压缩放都在卡片内部）。
   */
  onTapRow: (index: number) => void = (_index: number): void => {}
  onMove: (from: number, to: number) => void = (_from: number, _to: number): void => {}
  /**
   * 拖动真正开始（长按后开始移动那一刻）。名字带 Reorder 前缀是必要的：
   * `onDragStart`／`onDrop` 是 ArkUI 通用拖拽属性，组件不能占用同名参数。
   * 宿主用它可以关掉与拖动冲突的面板——
   * 例如长按菜单：菜单已经打开时用户继续拖动，菜单会一直挂在屏幕上。
   */
  onReorderDragStart: (index: number) => void = (_index: number): void => {}
  /** 拖动落下。宿主同样要在这里清一次冲突面板，避免落下后还留着。 */
  onReorderDrop: (index: number) => void = (_index: number): void => {}
  private dataSource: JuReorderDataSource = new JuReorderDataSource()

  aboutToAppear(): void { this.syncItems() }
  private syncItems(): void { this.dataSource.replace(this.items) }
  private moveLazy(from: number, to: number): void {
    this.dataSource.move(from, to)
    this.onMove(from, to)
  }

  build() {
    List({ scroller: this.scroller, space: LengthMetrics.resource(this.listGap()).value }) {
      if (this.customRows && this.items.length === 0) {
        if (this.contentKey.length === 0) {
          ListItem() {
            this.content()
          }
        } else {
          ForEach([this.contentKey], (key: string) => {
            ListItem() {
              this.content()
            }
          }, (key: string): string => key)
        }
      } else if (this.lazy && this.sortEnabled()) {
        LazyForEach(this.dataSource, (name: string, index: number) => {
          this.Item(name, index)
        }, (name: string): string => name)
          .onMove((from: number, to: number): void => { this.moveLazy(from, to) }, {
            onLongPress: (index: number): void => { this.handleLongPress(index) },
            onDragStart: (index: number): void => { this.onReorderDragStart(index) },
            onDrop: (index: number): void => { this.onReorderDrop(index) }
          })
      } else if (this.lazy) {
        LazyForEach(this.dataSource, (name: string, index: number) => {
          this.Item(name, index)
        }, (name: string): string => name)
      } else if (this.sortEnabled()) {
        ForEach(this.items, (name: string, index: number) => {
          this.Item(name, index)
        }, (name: string): string => name)
          .onMove((from: number, to: number): void => { this.onMove(from, to) }, {
            onLongPress: (index: number): void => { this.handleLongPress(index) },
            onDragStart: (index: number): void => { this.onReorderDragStart(index) },
            onDrop: (index: number): void => { this.onReorderDrop(index) }
          })
      } else {
        ForEach(this.items, (name: string, index: number) => {
          this.Item(name, index)
        }, (name: string): string => name)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    // 放开裁剪还不够：滚出 List 视口、进入标题安全区的行也必须继续绘制。
    .clip(false)
    .cachedCount(this.cachedRows(), true)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .contentEndOffset(this.bottomInset)
    .onScrollStop((): void => { this.onScrollStop() })
    .onGestureRecognizerJudgeBegin((_event: BaseGestureEvent, current: GestureRecognizer,
      others: GestureRecognizer[]): GestureJudgeResult => this.judgeListPan(current, others))
    .padding({
      left: this.listInset(),
      right: this.listInset(),
      top: $r('app.float.gap_row')
    })
  }

  @Builder
  Item(name: string, index: number) {
    // onMove 只给每次迭代直接生成的 ListItem 注册拖动。
    // 条件必须放在 ListItem 内，不能在它外面生成 If 节点。
    ListItem() {
      if (this.customRows) {
        Stack() {
          this.rowContent(name, index, this.rowRadius)
        }
        .width('100%')
        .borderRadius(this.rowRadius)
        .clip(true)
      } else {
        this.Row(name, index)
      }
    }
    .id(this.itemId(name))
    .borderRadius(this.customRows ? this.rowRadius : this.corners(index))
    .swipeAction({
      end: this.customRows ? undefined : {
        builder: (): void => { this.DeleteAction(index) },
        onAction: (): void => { this.onDelete(index) }
      },
      edgeEffect: SwipeEdgeEffect.None
    })
  }

  @Builder
  EmptyRow(_key: string, _index: number, _radius: Resource) {}

  @Builder
  Empty() {}

  @Builder
  Row(name: string, index: number) {
    Column() {
      Row() {
      if (this.editing) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width($r('app.float.reorder_minus_size'))
            .height($r('app.float.reorder_minus_size'))
            .borderRadius($r('app.float.reorder_minus_radius'))
            .backgroundColor($r('app.color.destructive'))
          JuIcon({
            name: $r('app.media.fab_minus'),
            color: $r('app.color.mine_icon_mark'),
            side: $r('app.float.icon_size_secondary')
          })
        }
        // 视觉 22vp，点击区仍然给到 48vp（thumb 大小）——**用 responseRegion 撑，
        // 不用宽高撑**。用宽高撑的话，编辑态这一行的最高元素就变成 48vp，
        // 整行从 50vp 跳到 76vp：点一下「编辑」每行都长高一块（2026-10-18 修）。
        .width($r('app.float.reorder_minus_size'))
        .height($r('app.float.reorder_minus_size'))
        .responseRegion(this.minusTouch())
        .margin({ right: $r('app.float.gap_button_text') })
        .onClick((): void => { this.revealDelete(name) })
      }

      Text(name)
        .layoutWeight(1)
        .fontSize($r('app.float.font_size_body'))
        .fontWeight($r('app.integer.font_weight_regular'))
        .fontColor($r('app.color.foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(`${this.countAt(index)}`)
        .fontSize($r('app.float.font_size_body'))
        .fontColor($r('app.color.section'))
        .margin({ right: this.editing ? $r('app.float.gap_button_text') : $r('app.float.edge_none') })

      if (this.editing) {
        JuIcon({
          name: $r('app.media.drag_handle'),
          color: $r('app.color.section'),
          side: $r('app.float.icon_size_secondary')
        })
      }
    }
    .width('100%')
    .padding($r('app.float.mine_row_padding'))

    if (index < this.items.length - 1) {
      Row()
        .width('100%')
        .height($r('app.float.divider_height'))
        .margin({ left: $r('app.float.mine_row_padding'), right: $r('app.float.mine_row_padding') })
        .backgroundColor($r('app.color.setting_separator'))
    }
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius(this.corners(index))
    .clip(true)
    .onClick((): void => {
      // 编辑态（正在拖动、正在删）点行不响应，避免误触。
      if (!this.editing) {
        this.onTapRow(index)
      }
    })
  }

  @Builder
  DeleteAction(index: number) {
    Row() {
      Text('删除')
        .fontSize($r('app.float.font_size_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.destructive_foreground'))
    }
    .width($r('app.float.swipe_action_width'))
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.destructive'))
    .borderRadius($r('app.float.reorder_delete_radius'))
    .margin({ left: $r('app.float.gap_button_text') })
    .onClick((): void => { this.onDelete(index) })
  }

  private countAt(index: number): number {
    return index >= 0 && index < this.counts.length ? this.counts[index] : 0
  }

  private sortEnabled(): boolean {
    return this.items.length > 1 && (this.editing === null ? this.customRows : this.editing)
  }

  private listGap(): Resource {
    return this.rowGap ?? (this.customRows ? $r('app.float.reorder_card_gap') : $r('app.float.edge_none'))
  }

  private listInset(): Resource {
    // 空 key 列表的正文槽负责自己的排版，切回堆叠时不重复添加卡片留白。
    if (this.customRows && this.items.length === 0) { return $r('app.float.edge_none') }
    return this.horizontalInset ?? (this.customRows ?
      $r('app.float.padding_page_compact') : $r('app.float.sheet_card_inset'))
  }

  /** 使用系统排序的长按回调；移动、换位和松手不重复振动。 */
  private handleLongPress(index: number): void {
    if (!this.hapticFeedback || !this.sortEnabled() || index < 0 || index >= this.items.length) { return }
    const host = this.getUIContext().getHostContext()
    if (host === undefined) { return }
    try {
      const duration: number = host.resourceManager.getNumberByName('reorder_long_press_vibration_duration')
      vibrator.startVibration({ type: 'time', duration: duration }, { usage: 'touch' })
        .catch((_error: BusinessError): void => {})
    } catch (_error) {
      // 没有振动器或系统不允许振动时，排序仍正常响应。
    }
  }

  private judgeListPan(current: GestureRecognizer, others: GestureRecognizer[]): GestureJudgeResult {
    if (this.priorityGestureTags.length === 0 || !current.isBuiltIn() ||
      current.getType() !== GestureControl.GestureType.PAN_GESTURE) {
      return GestureJudgeResult.CONTINUE
    }
    for (const recognizer of others) {
      if (this.priorityGestureTags.indexOf(recognizer.getTag()) >= 0) { return GestureJudgeResult.REJECT }
    }
    return GestureJudgeResult.CONTINUE
  }

  private cachedRows(): number {
    const host = this.getUIContext().getHostContext()
    if (host === undefined) { return 0 }
    try { return host.resourceManager.getNumberByName('reorder_visible_cache_rows') }
    catch (_error) { return 0 }
  }

  /** 首行只圆上角，末行只圆下角，中间贴齐，看起来是一张卡。 */
  private corners(index: number): BorderRadiuses {
    const round: Length = $r('app.float.list_detail_card_radius')
    const flat: Length = $r('app.float.edge_none')
    const first: boolean = index === 0
    const last: boolean = index === this.items.length - 1
    const radii: BorderRadiuses = {
      topLeft: first ? round : flat,
      topRight: first ? round : flat,
      bottomLeft: last ? round : flat,
      bottomRight: last ? round : flat
    }
    return radii
  }

  private itemId(name: string): string {
    return `reorder-${name}`
  }

  /**
   * 减号的点击区：比视觉大一圈，居中套在它外面。
   * 布局尺寸仍是 `reorder_minus_size`，所以行高不随编辑态变化。
   */
  private minusTouch(): Rectangle {
    const tap: number = this.readFloat('icon_button_size')
    const visual: number = this.readFloat('reorder_minus_size')
    if (tap <= 0 || visual <= 0) {
      return { x: 0, y: 0, width: 0, height: 0 }
    }
    const outset: number = (tap - visual) / 2
    return { x: -outset, y: -outset, width: tap, height: tap }
  }

  /** 取尺寸资源的 vp 值。数值参数（如 responseRegion 的负偏移）只能吃数字。 */
  private readFloat(name: string): number {
    const host = this.getUIContext().getHostContext()
    if (!host) {
      return 0
    }
    try {
      return this.getUIContext().px2vp(host.resourceManager.getNumberByName(name))
    } catch (_error) {
      return 0
    }
  }

  /** 点减号等于把这一行左滑打开，删除还是同一条。 */
  private revealDelete(name: string): void {
    const node: FrameNode | null = this.getUIContext().getAttachedFrameNodeById(this.itemId(name))
    if (node === null) { return }
    ListItemSwipeActionManager.expand(node, ListItemSwipeActionDirection.END)
  }
}
