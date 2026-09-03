import { BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY } from '../../../core/theme/BrowserThemeStorageKeys';
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
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop options: SegmentedTabOption[] = [];
  @Prop
  @Watch('syncSelectedIndex')
  selectedId: string = '';
  @Prop barHeight: number = 36;
  @Prop itemHeight: number = 30;
  @Prop fontSize: number = 14;
  @Prop barPadding: number = 3;
  @Prop indicatorBackgroundColor: ResourceColor = '';
  @Prop selectedTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop fallbackColor: ResourceColor = $r('app.color.surface_glass_background');
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
      this.isMaterialAvailable() ? BlurStyle.NONE : BlurStyle.COMPONENT_THIN
    )
    .blurStrategy(BlurStrategy.ADAPTIVE)
    .barFloatingStyle(this.resolveBarFloatingStyle())
    .onChange((index: number) => {
      this.handleTabChange(index);
    })
    .width('100%')
    .height(this.barHeight)
    .clip(true)
  }

  @Builder
  private buildTabBar(option: SegmentedTabOption) {
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
    .width('100%')
    .height(this.itemHeight)
    .padding({ left: this.barPadding, right: this.barPadding })
    .backgroundColor(this.isSelected(option.id) ? this.resolveIndicatorBackgroundColor() :
      $r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(this.itemHeight / 2)
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

  private resolveBarBackgroundColor(): ResourceColor {
    return this.isMaterialAvailable() ? Color.Transparent : this.fallbackColor;
  }

  private resolveBarFloatingStyle(): HdsTabsFloatingStyle {
    const style: HdsTabsFloatingStyle = {
      barSideMargin: 0,
      barBottomMargin: 0,
      barOpacity: 1
    };
    if (this.isMaterialAvailable()) {
      style.systemMaterialEffect = {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      };
    }
    return style;
  }

  private resolveIndicatorBackgroundColor(): ResourceColor {
    return `${this.indicatorBackgroundColor}`.length > 0
      ? this.indicatorBackgroundColor
      : $r('app.color.glass_segment_selected_background');
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolveSelectedTextColor(): ResourceColor {
    return `${this.selectedTextColor}`.length > 0
      ? this.selectedTextColor
      : $r('app.color.glass_segment_selected_text');
  }
}
