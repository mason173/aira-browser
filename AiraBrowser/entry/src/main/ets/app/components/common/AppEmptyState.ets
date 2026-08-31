import {
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { normalizeHomeWallpaperTransitionDuration } from '../../../core/wallpaper/HomeWallpaperPresentationTokens';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from './AiraIcon';

@Component
export struct AppEmptyState {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop icon: Resource = $r('sys.symbol.clock_fill');
  @Prop imageIcon: Resource | undefined = undefined;
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop showIcon: boolean = true;
  @Prop useCustomIcon: boolean = false;
  @Prop title: string = '';
  @Prop message: string = '';
  @Prop topPadding: number = 96;
  @Prop bottomPadding: number = 96;
  @Prop horizontalPadding: number = 24;
  @Prop fillHeight: boolean = false;
  @Prop primaryTextColor: ResourceColor | undefined = undefined;
  @Prop secondaryTextColor: ResourceColor | undefined = undefined;
  @Prop textShadow: Array<ShadowOptions> = [];
  @Prop foregroundTransitionDurationMs: number = 0;
  @BuilderParam customIcon: () => void = this.emptyBuilder;

  build() {
    if (this.fillHeight) {
      Column({ space: 10 }) {
        this.buildContent()
      }
      .width('100%')
      .height('100%')
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
        top: this.topPadding,
        bottom: this.bottomPadding
      })
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    } else {
      Column({ space: 10 }) {
        this.buildContent()
      }
      .width('100%')
      .padding({
        left: this.horizontalPadding,
        right: this.horizontalPadding,
        top: this.topPadding,
        bottom: this.bottomPadding
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  private buildContent() {
    if (this.showIcon) {
      if (this.useCustomIcon) {
        this.customIcon()
      } else if (this.airaIconId !== undefined) {
        AiraIcon({
          airaIconId: this.airaIconId,
          iconSize: 40,
          iconColor: this.resolveSecondaryTextColor()
        })
      } else if (this.imageIcon !== undefined) {
        Image(this.imageIcon as Resource)
          .width(40)
          .height(40)
          .objectFit(ImageFit.Contain)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(38)
          .fontColor([this.resolveSecondaryTextColor()])
          .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
      }
    }

    if (this.title.length > 0) {
      Text(this.title)
        .width('100%')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolvePrimaryTextColor())
        .textShadow(this.textShadow)
        .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
        .textAlign(TextAlign.Center)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }

    if (this.message.length > 0) {
      Text(this.message)
        .width('100%')
        .fontSize(13)
        .lineHeight(19)
        .fontColor(this.resolveSecondaryTextColor())
        .textShadow(this.textShadow)
        .animation({ duration: this.resolveForegroundTransitionDuration(), curve: Curve.EaseInOut })
        .textAlign(TextAlign.Center)
    }
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return this.primaryTextColor === undefined ? this.storedPrimaryTextColor : this.primaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return this.secondaryTextColor === undefined ? this.storedSecondaryTextColor : this.secondaryTextColor;
  }

  private resolveForegroundTransitionDuration(): number {
    return normalizeHomeWallpaperTransitionDuration(this.foregroundTransitionDurationMs);
  }

  @Builder
  private emptyBuilder() {
  }
}
