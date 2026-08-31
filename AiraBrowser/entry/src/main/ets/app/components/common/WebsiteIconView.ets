import { image } from '@kit.ImageKit';
import { SiteIconView } from './SiteIconView';

export type WebsiteIconVariant = 'grid' | 'list' | 'compact';

const WEBSITE_ICON_LIST_SIZE: number = 34;
const WEBSITE_ICON_LIST_FALLBACK_FONT_SIZE: number = 15;
const WEBSITE_ICON_GRID_FALLBACK_FONT_SIZE: number = 20;
const WEBSITE_ICON_COMPACT_SIZE: number = 30;
const WEBSITE_ICON_COMPACT_FALLBACK_FONT_SIZE: number = 14;
export const DEFAULT_WEBSITE_ICON_CONTENT_RATIO: number = 0.6;
const WEBSITE_ICON_LIGHT_BORDER_COLOR: string = '#12000000';

@Component
export struct WebsiteIconView {
  @Prop iconUri: string = '';
  @Prop iconPixelMap: image.PixelMap | undefined = undefined;
  @Prop fallbackLabel: string = '#';
  @Prop variant: WebsiteIconVariant = 'list';
  @Prop iconSize: number = 0;
  @Prop cornerRadius: number = 0;
  @Prop cornerRadiusRatio: number = 0.3;
  @Prop fallbackFontSize: number = 0;
  @Prop fallbackFontWeight: FontWeight = FontWeight.Bolder;
  @Prop frameBorderWidth: number = 0;
  @Prop contentRatio: number = DEFAULT_WEBSITE_ICON_CONTENT_RATIO;
  @Prop imageContentScale: number = 1;
  @Prop imageCornerRadius: number = 0;
  @Prop containerBackgroundColor: ResourceColor = '#EEF2F6';
  @Prop frameBorderColor: ResourceColor = WEBSITE_ICON_LIGHT_BORDER_COLOR;
  @Prop textColor: ResourceColor = '#111318';
  @Prop fit: ImageFit = ImageFit.Contain;
  @Prop syncLoad: boolean = false;
  @Prop preferPixelMap: boolean = false;
  @Prop sourceRevision: number = 0;
  @Prop hitTestMode: HitTestMode = HitTestMode.Default;
  onIconLoadError: (iconUri: string, sourceRevision: number) => void =
    (_iconUri: string, _sourceRevision: number) => {};

  build() {
    SiteIconView({
      iconUri: this.iconUri,
      iconPixelMap: this.iconPixelMap,
      fallbackLabel: this.fallbackLabel,
      iconSize: this.resolveIconSize(),
      cornerRadius: this.resolveCornerRadius(),
      cornerRadiusRatio: this.cornerRadiusRatio,
      frameBorderWidth: this.frameBorderWidth,
      contentPadding: this.resolveContentPadding(),
      imageContentScale: this.imageContentScale,
      imageCornerRadius: this.imageCornerRadius,
      fallbackFontSize: this.resolveFallbackFontSize(),
      fallbackFontWeight: this.fallbackFontWeight,
      containerBackgroundColor: this.containerBackgroundColor,
      frameBorderColor: this.frameBorderColor,
      textColor: this.textColor,
      fit: this.fit,
      syncLoad: this.syncLoad,
      preferPixelMap: this.preferPixelMap,
      sourceRevision: this.sourceRevision,
      hitTestMode: this.hitTestMode,
      onIconLoadError: (iconUri: string, sourceRevision: number) => {
        this.onIconLoadError(iconUri, sourceRevision);
      }
    })
    .hitTestBehavior(this.hitTestMode)
  }

  private resolveIconSize(): number {
    if (this.iconSize > 0) {
      return this.iconSize;
    }
    if (this.variant === 'compact') {
      return WEBSITE_ICON_COMPACT_SIZE;
    }
    return WEBSITE_ICON_LIST_SIZE;
  }

  private resolveCornerRadius(): number {
    if (this.cornerRadius > 0) {
      return this.cornerRadius;
    }
    return 0;
  }

  private resolveFallbackFontSize(): number {
    if (this.fallbackFontSize > 0) {
      return this.fallbackFontSize;
    }
    if (this.variant === 'grid') {
      return WEBSITE_ICON_GRID_FALLBACK_FONT_SIZE;
    }
    if (this.variant === 'compact') {
      return WEBSITE_ICON_COMPACT_FALLBACK_FONT_SIZE;
    }
    return WEBSITE_ICON_LIST_FALLBACK_FONT_SIZE;
  }

  private resolveContentPadding(): number {
    const size = this.resolveIconSize();
    const ratio = Math.max(0, Math.min(1, this.contentRatio));
    return Math.max(0, Math.round(size * (1 - ratio) / 2));
  }
}
