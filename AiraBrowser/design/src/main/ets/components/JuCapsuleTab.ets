import { CapsuleSegmentButtonV2, ColorMetrics, SegmentButtonV2ItemOptions, SegmentButtonV2Items, uiMaterial } from '@kit.ArkUI'

/**
 * 胶囊 Tab。官方胶囊分段，超薄沉浸光感，选中项白底黑字。
 * 材质自带的投影关着，外面另画一层浅的圆角投影。
 * icons 和 labels 等长时只显示图标。选中和未选中用同一张图、同一种颜色，
 * 避免系统把选中项换成填充。
 */
@Component
export struct JuCapsuleTab {
  @Prop @Watch('syncItems') labels: string[] = []
  @Prop @Watch('syncItems') icons: Resource[] = []
  /** 系统 Symbol。和 icons 互斥，优先用这个。 */
  @Prop @Watch('syncItems') symbols: Resource[] = []
  @Prop selected: number = 0
  /** 顶栏用的小尺寸，宽 `capsule_tab_compact_width`。 */
  @Prop compact: boolean = false
  /** 传入后按这个宽度显示。不传时 compact 用 104vp，否则拉满。 */
  @Prop tabWidth: Length = ''
  onSelect: (index: number) => void = () => {}
  private items: SegmentButtonV2Items = new SegmentButtonV2Items([])
  private itemKey: string = ''

  aboutToAppear(): void {
    this.syncItems()
  }

  private syncItems(): void {
    const next: string = `${this.labels.join('\u0000')}\u0001${this.icons.length}\u0001${this.symbols.length}`
    if (next === this.itemKey) {
      return
    }
    this.itemKey = next
    const options: SegmentButtonV2ItemOptions[] = []
    const iconOnly: boolean = this.icons.length === this.labels.length && this.icons.length > 0
    const symbolOnly: boolean = this.symbols.length === this.labels.length && this.symbols.length > 0
    for (let index = 0; index < this.labels.length; index++) {
      if (symbolOnly) {
        options.push({
          symbol: this.symbols[index],
          accessibilityText: this.labels[index]
        })
      } else if (iconOnly) {
        options.push({
          icon: this.icons[index],
          accessibilityText: this.labels[index]
        })
      } else {
        options.push({ text: this.labels[index] })
      }
    }
    this.items = new SegmentButtonV2Items(options)
  }

  build() {
    CapsuleSegmentButtonV2({
      items: this.items,
      selectedIndex: this.selected,
      $selectedIndex: (index: number): void => { this.onSelect(index) },
      // 选中胶囊用专门的 token，不再借用 card：卡片是纯白，铺在近乎白的分段底上
      // 几乎看不出选中（2026-10-18 改）。浅色更深、深色更亮，方向相反但作用一样——
      // 都是"和轨道拉开差距"。
      itemSelectedBackgroundColor: ColorMetrics.resourceColor($r('app.color.capsule_tab_selected')),
      itemSelectedFontColor: ColorMetrics.resourceColor($r('app.color.foreground')),
      itemIconFillColor: ColorMetrics.resourceColor($r('app.color.foreground')),
      itemSelectedIconFillColor: ColorMetrics.resourceColor($r('app.color.foreground')),
      itemSymbolFontColor: ColorMetrics.resourceColor($r('app.color.foreground')),
      itemSelectedSymbolFontColor: ColorMetrics.resourceColor($r('app.color.foreground')),
      itemShadow: {
        radius: $r('app.float.edge_none'),
        color: Color.Transparent,
        offsetX: $r('app.float.edge_none'),
        offsetY: $r('app.float.edge_none')
      },
      backgroundSystemMaterial: new uiMaterial.ImmersiveMaterial({
        style: uiMaterial.ImmersiveStyle.ULTRA_THIN,
        applyShadow: false
      })
    })
      .width(this.tabWidth !== '' ? this.tabWidth :
        this.compact ? $r('app.float.capsule_tab_compact_width') : '100%')
      .borderRadius($r('sys.float.segment_button_v2_background_corner_radius'))
      .shadow({
        radius: $r('app.float.segment_shadow_radius'),
        color: $r('app.color.segment_shadow'),
        offsetX: $r('app.float.edge_none'),
        offsetY: $r('app.float.segment_shadow_offset')
      })
  }
}
