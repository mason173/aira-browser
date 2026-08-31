import { image } from '@kit.ImageKit';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from './AiraIcon';

const DEFAULT_SITE_ICON_CORNER_RADIUS_RATIO: number = 0.3;

@Component
export struct SiteIconView {
  @Prop iconUri: string = '';
  @Prop iconPixelMap: image.PixelMap | undefined = undefined;
  @Prop fallbackLabel: string = '#';
  @Prop fallbackAiraIconId: AiraRenderableIconId | undefined = undefined;
  @Prop fallbackIconSize: number = 0;
  @Prop iconSize: number = 40;
  @Prop cornerRadius: number = 0;
  @Prop cornerRadiusRatio: number = DEFAULT_SITE_ICON_CORNER_RADIUS_RATIO;
  @Prop frameBorderWidth: number = 1;
  @Prop contentPadding: number = 0;
  @Prop imageContentScale: number = 1;
  @Prop imageCornerRadius: number = 0;
  @Prop fallbackFontSize: number = 16;
  @Prop fallbackFontWeight: FontWeight = FontWeight.Bolder;
  @Prop containerBackgroundColor: ResourceColor = '#FFFFFF';
  @Prop frameBorderColor: ResourceColor = '#26000000';
  @Prop textColor: ResourceColor = '#111318';
  @Prop fit: ImageFit = ImageFit.Cover;
  @Prop syncLoad: boolean = false;
  @Prop preferPixelMap: boolean = false;
  @Prop sourceRevision: number = 0;
  @Prop hitTestMode: HitTestMode = HitTestMode.Default;
  @State private failedIconKey: string = '';
  @State private failedPixelMapKey: string = '';
  onIconLoadError: (iconUri: string, sourceRevision: number) => void =
    (_iconUri: string, _sourceRevision: number) => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.shouldRenderPreferredPixelMap()) {
        Image(this.iconPixelMap as image.PixelMap)
          .width(this.resolveImageContentSize())
          .height(this.resolveImageContentSize())
          .objectFit(this.fit)
          .borderRadius(this.resolveImageContentCornerRadius())
          .clip(true)
          .syncLoad(this.syncLoad)
          .hitTestBehavior(this.hitTestMode)
          .onError(() => {
            this.failedPixelMapKey = this.resolvePixelMapFailureKey();
          })
      } else if (this.shouldRenderIconUri()) {
        Image(this.resolveIconUri())
          .width(this.resolveImageContentSize())
          .height(this.resolveImageContentSize())
          .objectFit(this.fit)
          .borderRadius(this.resolveImageContentCornerRadius())
          .clip(true)
          .syncLoad(this.syncLoad)
          .hitTestBehavior(this.hitTestMode)
          .onError(() => {
            this.failedIconKey = this.resolveIconFailureKey();
            this.onIconLoadError(this.resolveIconUri(), Math.max(0, Math.floor(this.sourceRevision)));
          })
      } else if (this.shouldRenderFallbackPixelMap()) {
        Image(this.iconPixelMap as image.PixelMap)
          .width(this.resolveImageContentSize())
          .height(this.resolveImageContentSize())
          .objectFit(this.fit)
          .borderRadius(this.resolveImageContentCornerRadius())
          .clip(true)
          .syncLoad(this.syncLoad)
          .hitTestBehavior(this.hitTestMode)
      } else if (this.fallbackAiraIconId !== undefined) {
        AiraIcon({
          airaIconId: this.fallbackAiraIconId,
          iconSize: this.resolveFallbackIconSize(),
          iconColor: this.textColor
        })
          .hitTestBehavior(this.hitTestMode)
      } else {
        Text(this.resolveFallbackLabel())
          .fontSize(this.fallbackFontSize)
          .fontWeight(this.fallbackFontWeight)
          .fontColor(this.textColor)
          .maxLines(1)
          .hitTestBehavior(this.hitTestMode)
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
    .backgroundColor(this.containerBackgroundColor)
    .borderWidth(this.frameBorderWidth)
    .borderColor(this.frameBorderColor)
    .borderRadius(this.resolveContainerCornerRadius())
    .clip(true)
    .hitTestBehavior(this.hitTestMode)
  }

  private shouldRenderIconUri(): boolean {
    const uri = this.resolveIconUri();
    return uri.length > 0 && this.failedIconKey !== this.resolveIconFailureKey();
  }

  private shouldRenderPreferredPixelMap(): boolean {
    if (!this.preferPixelMap || this.iconPixelMap === undefined) {
      return false;
    }
    return this.failedPixelMapKey !== this.resolvePixelMapFailureKey();
  }

  private shouldRenderFallbackPixelMap(): boolean {
    if (this.iconPixelMap === undefined) {
      return false;
    }
    if (!this.preferPixelMap) {
      return true;
    }
    return this.failedPixelMapKey !== this.resolvePixelMapFailureKey();
  }

  private resolveIconUri(): string {
    return this.iconUri.trim();
  }

  private resolveIconFailureKey(): string {
    return `${this.resolveIconUri()}|${Math.max(0, Math.floor(this.sourceRevision))}`;
  }

  private resolvePixelMapFailureKey(): string {
    const uri = this.resolveIconUri();
    const sourceKey = uri.length > 0 ? uri : '#pixelmap';
    return `${sourceKey}|${Math.max(0, Math.floor(this.sourceRevision))}`;
  }

  private resolveContentSize(): number {
    return Math.max(0, this.iconSize - this.contentPadding * 2);
  }

  private resolveContentCornerRadius(): number {
    return Math.max(0, this.resolveContainerCornerRadius() - this.contentPadding);
  }

  private resolveContainerCornerRadius(): number {
    if (this.cornerRadius > 0) {
      return this.cornerRadius;
    }
    return Math.round(this.iconSize * this.resolveCornerRadiusRatio());
  }

  private resolveCornerRadiusRatio(): number {
    return Math.max(0.12, Math.min(0.5, this.cornerRadiusRatio));
  }

  private resolveImageContentSize(): number {
    const scale = Math.max(0, Math.min(1, this.imageContentScale));
    return Math.round(this.resolveContentSize() * scale);
  }

  private resolveImageContentCornerRadius(): number {
    if (this.imageCornerRadius > 0) {
      return this.imageCornerRadius;
    }
    const scale = Math.max(0, Math.min(1, this.imageContentScale));
    return Math.round(this.resolveContentCornerRadius() * scale);
  }

  private resolveFallbackLabel(): string {
    const normalized = this.fallbackLabel.trim();
    if (normalized.length === 0) {
      return '#';
    }
    return normalized.substring(0, 1).toUpperCase();
  }

  private resolveFallbackIconSize(): number {
    if (this.fallbackIconSize > 0) {
      return this.fallbackIconSize;
    }
    return Math.max(16, Math.round(this.iconSize * 0.55));
  }
}
