import {
  AIRA_ICON_FONT_FAMILY,
  AiraRenderableIconId,
  GeneratedAiraIconCatalog
} from '../../../core/resources/GeneratedAiraIconCatalog';

@Component
export struct AiraIcon {
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop iconSize: number = 18;
  @Prop iconColor: ResourceColor = '';

  build() {
    if (this.airaIconId === undefined) {
      Stack()
        .width(this.iconSize)
        .height(this.iconSize)
    } else if (GeneratedAiraIconCatalog.isFontBacked(this.airaIconId)) {
      Stack({ alignContent: Alignment.Center }) {
        Text(GeneratedAiraIconCatalog.resolveFontGlyph(this.airaIconId))
          .fontFamily(AIRA_ICON_FONT_FAMILY)
          .fontSize(this.iconSize)
          .lineHeight(this.iconSize)
          .minFontScale(1)
          .maxFontScale(1)
          .fontColor(this.iconColor)
          .maxLines(1)
          .textAlign(TextAlign.Center)
      }
      .width(this.iconSize)
      .height(this.iconSize)
    } else if (GeneratedAiraIconCatalog.hasLegacyResource(this.airaIconId)) {
      Image(GeneratedAiraIconCatalog.resolveLegacyResource(this.airaIconId) as Resource)
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
    } else {
      Stack()
        .width(this.iconSize)
        .height(this.iconSize)
    }
  }
}
