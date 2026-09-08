import {
  BlurStrategy,
  HdsTabs,
  HdsTabsController,
  HdsTabsFloatingStyle,
  hdsMaterial
} from '@kit.UIDesignKit';

export interface SegmentedTabOption {
  id: string;
  title: string;
}

@Component
export struct SegmentedTabs {
  @Prop options: SegmentedTabOption[] = [];
  @Prop
  @Watch('syncSelectedIndex')
  selectedId: string = '';
  @Prop barHeight: number = 36;
  @Prop itemHeight: number = 30;
  @Prop fontSize: number = 14;
  @Prop barPadding: number = 3;
  @Prop indicatorBackgroundColor: ResourceColor = $r('sys.color.comp_background_primary');
  @Prop selectedTextColor: ResourceColor = $r('sys.color.font_primary');
  @Prop secondaryTextColor: ResourceColor = $r('sys.color.font_secondary');
  @Prop fallbackColor: ResourceColor = $r('app.color.surface_glass_background');
  @Prop barMaterialEnabled: boolean = true;
  @State private selectedIndex: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  private synchronizingController: boolean = false;
  private cachedHdsMaterialAvailable: boolean | undefined = undefined;
  onSelect: (id: string) => void = (_id: string) => {};

  aboutToAppear(): void {
    this.syncSelectedIndex();
  }

  build() {
    HdsTabs({ controller: this.tabsController }) {
      ForEach(this.options, (option: SegmentedTabOption) => {
        TabContent() {
          // SegmentedTabs is embedded beside the page content. HdsTabs owns the
          // tab semantics and bar, while the caller owns the selected content.
          Column() {
            Blank()
              .width(1)
              .height(0)
          }
        }
          .tabBar(this.buildTabBar(option))
      }, (option: SegmentedTabOption) => option.id)
    }
    .vertical(false)
    .scrollable(false)
    .barMode(BarMode.Fixed)
    .barPosition(BarPosition.End)
    .barHeight(this.barHeight)
    .barBackgroundColor(this.resolveBarBackgroundColor())
    .barBackgroundBlurStyle(
      this.shouldApplyBarBackgroundBlur() ? BlurStyle.COMPONENT_THIN : BlurStyle.NONE
    )
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .barFloatingStyle(this.resolveBarFloatingStyle())
    .onChange((index: number) => {
      this.handleTabChange(index);
    })
    .width('100%')
    .height(this.barHeight)
    .borderRadius(this.barHeight / 2)
    .clip(true)
  }

  @Builder
  private buildTabBar(option: SegmentedTabOption) {
    Row() {
      Stack({ alignContent: Alignment.Center }) {
        Text(option.title)
          .fontSize(this.fontSize)
          .fontWeight(this.isSelected(option.id) ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.isSelected(option.id)
            ? this.resolveSelectedTextColor()
            : this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
          .hitTestBehavior(HitTestMode.None)
      }
      .layoutWeight(1)
      .height(this.itemHeight)
      .backgroundColor(this.isSelected(option.id) ? this.resolveIndicatorBackgroundColor() :
        $r('sys.color.ohos_id_color_background_transparent'))
      .borderRadius(this.itemHeight / 2)
    }
    .width('100%')
    .height(this.barHeight)
    .padding({ left: this.barPadding, right: this.barPadding })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }

  private handleTabChange(index: number): void {
    if (index < 0 || index >= this.options.length) {
      return;
    }
    this.selectedIndex = index;
    if (this.synchronizingController) {
      return;
    }
    this.onSelect(this.options[index].id);
  }

  private resolveSelectedIndex(): number {
    const selectedIndex = this.options.findIndex((option: SegmentedTabOption) => option.id === this.selectedId);
    return selectedIndex >= 0 ? selectedIndex : 0;
  }

  private isSelected(id: string): boolean {
    return this.options.length > 0 && this.options[this.selectedIndex]?.id === id;
  }

  private syncSelectedIndex(): void {
    const nextIndex = this.resolveSelectedIndex();
    if (nextIndex === this.selectedIndex) {
      return;
    }
    this.selectedIndex = nextIndex;
    this.synchronizingController = true;
    this.tabsController.changeIndex(nextIndex);
    this.synchronizingController = false;
  }

  private isMaterialAvailable(): boolean {
    if (this.cachedHdsMaterialAvailable !== undefined) {
      return this.cachedHdsMaterialAvailable;
    }
    try {
      this.cachedHdsMaterialAvailable = hdsMaterial.getSystemMaterialTypes()
        .indexOf(hdsMaterial.MaterialType.ADAPTIVE) >= 0;
    } catch (_error) {
      this.cachedHdsMaterialAvailable = false;
    }
    return this.cachedHdsMaterialAvailable;
  }

  private shouldApplyBarMaterial(): boolean {
    return this.barMaterialEnabled && this.isMaterialAvailable();
  }

  private shouldApplyBarBackgroundBlur(): boolean {
    return this.barMaterialEnabled && !this.shouldApplyBarMaterial();
  }

  private resolveBarBackgroundColor(): ResourceColor {
    if (!this.barMaterialEnabled) {
      return $r('sys.color.ohos_id_color_background_transparent');
    }
    return this.shouldApplyBarMaterial() ? Color.Transparent : this.fallbackColor;
  }

  private resolveBarFloatingStyle(): HdsTabsFloatingStyle {
    const style: HdsTabsFloatingStyle = {
      barSideMargin: 0,
      barBottomMargin: 0,
      barOpacity: 1
    };
    if (this.shouldApplyBarMaterial()) {
      style.systemMaterialEffect = {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      };
    }
    return style;
  }

  private resolveIndicatorBackgroundColor(): ResourceColor {
    return this.indicatorBackgroundColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor;
  }

  private resolveSelectedTextColor(): ResourceColor {
    return this.selectedTextColor;
  }
}
