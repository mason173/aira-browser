import {
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { FloatingGlassMaterialSurface } from './FloatingGlassMaterialSurface';
import { resolveFloatingGlassMaterialTintForMode } from './FloatingGlassMaterialTokens';

export interface SegmentedTabOption {
  id: string;
  title: string;
}

@Component
export struct SegmentedTabs {
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop options: SegmentedTabOption[] = [];
  @Prop selectedId: string = '';
  @Prop barHeight: number = 36;
  @Prop itemHeight: number = 30;
  @Prop fontSize: number = 14;
  @Prop barPadding: number = 3;
  @Prop indicatorBackgroundColor: ResourceColor = '';
  @Prop selectedTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @State private barWidth: number = 0;
  onSelect: (id: string) => void = (_id: string) => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      FloatingGlassMaterialSurface({
        surfaceWidth: '100%',
        surfaceHeight: this.barHeight,
        surfaceRadius: this.barHeight / 2,
        tintColor: resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
      }) {
        Stack({ alignContent: Alignment.Start }) {
          if (this.options.length > 0) {
            Row() {
              Blank()
            }
            .width(this.resolveIndicatorWidth())
            .height(this.itemHeight)
            .margin({ left: this.barPadding })
            .backgroundColor(this.resolveIndicatorBackgroundColor())
            .borderRadius(this.itemHeight / 2)
            .offset({ x: this.resolveIndicatorOffset() })
            .animation({
              duration: 260,
              curve: Curve.Friction
            })
          }

          Row() {
            ForEach(this.options, (option: SegmentedTabOption) => {
              Button(option.title)
                .layoutWeight(1)
                .height(this.itemHeight)
                .type(ButtonType.Normal)
                .fontSize(this.fontSize)
                .fontWeight(this.selectedId === option.id ? FontWeight.Medium : FontWeight.Regular)
                .fontColor(this.selectedId === option.id
                  ? this.resolveSelectedTextColor()
                  : this.resolveSecondaryTextColor())
                .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
                .borderRadius(this.itemHeight / 2)
                .onClick(() => {
                  this.onSelect(option.id);
                })
            }, (option: SegmentedTabOption) => option.id)
          }
          .width('100%')
          .height(this.barHeight)
          .padding(this.barPadding)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(this.barHeight)
      }
    }
    .width('100%')
    .height(this.barHeight)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextWidth = Number(newArea.width);
      this.barWidth = Number.isFinite(nextWidth) ? nextWidth : 0;
    })
  }

  private resolveIndicatorWidth(): number {
    if (this.options.length <= 0 || this.barWidth <= this.barPadding * 2) {
      return 0;
    }
    return (this.barWidth - this.barPadding * 2) / this.options.length;
  }

  private resolveIndicatorOffset(): number {
    return this.resolveIndicatorWidth() * this.resolveSelectedIndex();
  }

  private resolveSelectedIndex(): number {
    const selectedIndex = this.options.findIndex((option: SegmentedTabOption) => option.id === this.selectedId);
    return selectedIndex >= 0 ? selectedIndex : 0;
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
