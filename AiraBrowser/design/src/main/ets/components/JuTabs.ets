import { SymbolGlyphModifier } from '@kit.ArkUI'
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit'
import { JU_SELECTING_KEY } from '../select/SelectionState'

/** 页签数据只定义业务语义；图标传 sys.symbol，不使用内容区 SVG。 */
export class JuTabItem {
  key: string
  label: string
  symbol: Resource
  selectedSymbol: Resource

  constructor(key: string, label: string, symbol: Resource, selectedSymbol: Resource = symbol) {
    this.key = key
    this.label = label
    this.symbol = symbol
    this.selectedSymbol = selectedSymbol
  }
}

/** 官方 HdsTabs 的统一入口。布局、材质与切换由系统提供。 */
@Component
export struct JuTabs {
  @Prop items: JuTabItem[] = []
  @Prop selected: number = 0
  /** 特殊交互可暂时收起页签，保留当前页面与控制器。 */
  @Prop barVisible: boolean = true
  /** 进入多选（`SelectionState`）时自动收起页签；宿主不想自动收就传 false。 */
  @Prop hideOnSelect: boolean = true
  @StorageProp(JU_SELECTING_KEY) private selectionOn: boolean = false
  onChange: (index: number) => void = (_index: number): void => {}
  @BuilderParam content: (key: string, index: number) => void
  private controller: HdsTabsController = new HdsTabsController()
  @State private materialLevel: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE

  aboutToAppear(): void {
    try {
      const types = hdsMaterial.getSystemMaterialTypes()
      if (types.indexOf(hdsMaterial.MaterialType.IMMERSIVE) >= 0) {
        this.materialLevel = hdsMaterial.MaterialLevel.ADAPTIVE
        return
      }
    } catch (_error) {
    }
    this.materialLevel = hdsMaterial.MaterialLevel.SMOOTH
  }

  private shown(): boolean {
    return this.barVisible && !(this.hideOnSelect && this.selectionOn)
  }

  private icon(symbol: Resource, color: ResourceColor): SymbolGlyphModifier {
    return new SymbolGlyphModifier(symbol)
      .renderingStrategy(SymbolRenderingStrategy.SINGLE)
      .fontColor([color])
  }

  build() {
    HdsTabs({ controller: this.controller, index: this.selected }) {
      ForEach(this.items, (item: JuTabItem, index: number) => {
        TabContent() {
          this.content(item.key, index)
        }
        .clip(false)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .tabBar(new BottomTabBarStyle({
          normal: this.icon(item.symbol, $r('app.color.muted_foreground')),
          selected: this.icon(item.selectedSymbol, $r('app.color.foreground'))
        }, item.label).labelStyle({
          selectedColor: $r('app.color.foreground'),
          unselectedColor: $r('app.color.muted_foreground')
        }))
      }, (item: JuTabItem) => item.key)
    }
    .barOverlap(true)
    .vertical(false)
    .barPosition(BarPosition.End)
    .barHeight(this.shown() ? $r('app.float.tabs_bar_auto_size') : $r('app.float.edge_none'))
    .barWidth(this.shown() ? $r('app.float.tabs_bar_auto_size') : $r('app.float.edge_none'))
    .scrollable(false)
    .onChange((index: number): void => {
      if (index >= 0 && index < this.items.length && Number.isInteger(index)) { this.onChange(index) }
    })
    .barFloatingStyle({
      barOpacity: this.shown() ? 1 : 0,
      barBottomMargin: $r('app.float.tabs_bottom_margin'),
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: this.materialLevel
      }
    })
    .width('100%')
    .height('100%')
    .clip(false)
    .background($r('app.color.canvas'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
