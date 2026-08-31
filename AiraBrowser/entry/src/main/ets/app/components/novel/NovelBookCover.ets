import { image } from '@kit.ImageKit';
import { sharedNovelBookCoverImageService } from '../../../services/novel/NovelBookCoverImageService';
import { AiraIcon } from '../common/AiraIcon';

@Component
export struct NovelBookCover {
  @Prop @Watch('handleSourceChanged') coverUrl: string = '';
  @Prop detailUrl: string = '';
  @Prop persistentlyCached: boolean = false;
  @Prop title: string = '';
  @Prop coverBackgroundColor: ResourceColor;
  @Prop fallbackPrimaryTextColor: ResourceColor;
  @Prop fallbackSecondaryTextColor: ResourceColor;
  @Prop fallbackDividerColor: ResourceColor;
  @Prop cornerRadius: number = 6;
  @State private pixelMap: image.PixelMap | undefined = undefined;
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.loadCover();
  }

  aboutToDisappear(): void {
    this.loadGeneration += 1;
    this.releaseCurrentPixelMap();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      this.buildFallbackCover()
      if (this.pixelMap !== undefined) {
        Image(this.pixelMap as image.PixelMap)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.coverBackgroundColor)
    .border({ width: 1, color: this.fallbackDividerColor })
    .borderRadius(this.cornerRadius)
    .clip(true)
  }

  @Builder
  private buildFallbackCover() {
    Column() {
      Row({ space: 4 }) {
        AiraIcon({
          airaIconId: 'browser.toolbar.bookshelf',
          iconSize: 14,
          iconColor: this.fallbackSecondaryTextColor
        })
        Text('AIRA')
          .fontSize(9)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.fallbackSecondaryTextColor)
      }
      .justifyContent(FlexAlign.Center)

      Column({ space: 7 }) {
        Text(this.resolveFallbackTitle())
          .width('100%')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.fallbackPrimaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Divider()
          .width(24)
          .strokeWidth(1)
          .color(this.fallbackDividerColor)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text('小说阅读')
        .fontSize(10)
        .fontColor(this.fallbackSecondaryTextColor)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 12, right: 10, bottom: 10, left: 10 })
    .alignItems(HorizontalAlign.Center)
  }

  private handleSourceChanged(): void {
    this.loadCover();
  }

  private resolveFallbackTitle(): string {
    const normalized: string = this.title.trim();
    return normalized.length > 0 ? normalized : '未命名小说';
  }

  private loadCover(): void {
    const generation: number = this.loadGeneration + 1;
    this.loadGeneration = generation;
    this.releaseCurrentPixelMap();
    const coverUrl: string = this.coverUrl.trim();
    if (coverUrl.length === 0) {
      return;
    }
    void sharedNovelBookCoverImageService.load(coverUrl, this.detailUrl, this.persistentlyCached)
      .then((loaded: image.PixelMap | undefined): void => {
        if (generation !== this.loadGeneration) {
          this.releasePixelMap(loaded);
          return;
        }
        this.pixelMap = loaded;
      });
  }

  private releaseCurrentPixelMap(): void {
    const current: image.PixelMap | undefined = this.pixelMap;
    this.pixelMap = undefined;
    this.releasePixelMap(current);
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    if (pixelMap === undefined) {
      return;
    }
    void pixelMap.release().catch((_error: Error): void => {});
  }
}
