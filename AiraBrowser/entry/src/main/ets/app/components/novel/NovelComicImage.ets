import { image } from '@kit.ImageKit';
import { sharedNovelComicImageService } from '../../../services/novel/NovelComicImageService';

type NovelComicImageLoadState = 'loading' | 'loaded' | 'failed';

@Component
export struct NovelComicImage {
  @Prop @Watch('handleSourceChanged') imageUrl: string = '';
  @Prop @Watch('handleSourceChanged') pageUrl: string = '';
  @Prop minHeight: number = 220;
  @Prop surfaceColor: ResourceColor;
  @Prop primaryTextColor: ResourceColor;
  @State private pixelMap: image.PixelMap | undefined = undefined;
  @State private loadState: NovelComicImageLoadState = 'loading';
  private loadGeneration: number = 0;

  aboutToAppear(): void {
    this.loadImage();
  }

  aboutToDisappear(): void {
    this.loadGeneration += 1;
    this.releaseCurrentPixelMap();
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.loadState === 'loaded' && this.pixelMap !== undefined) {
        Image(this.pixelMap as image.PixelMap)
          .width('100%')
          .objectFit(ImageFit.Contain)
          .autoResize(true)
          .draggable(false)
      } else if (this.loadState === 'failed') {
        Text('图片加载失败')
          .fontSize(14)
          .fontColor(this.primaryTextColor)
      } else {
        LoadingProgress()
          .width(30)
          .height(30)
          .color(this.primaryTextColor)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: this.minHeight })
    .backgroundColor(this.surfaceColor)
  }

  private handleSourceChanged(): void {
    this.loadImage();
  }

  private loadImage(): void {
    const generation: number = this.loadGeneration + 1;
    this.loadGeneration = generation;
    this.releaseCurrentPixelMap();
    this.loadState = 'loading';
    const imageUrl: string = this.imageUrl.trim();
    if (imageUrl.length === 0) {
      this.loadState = 'failed';
      return;
    }
    void sharedNovelComicImageService.load(imageUrl, this.pageUrl.trim())
      .then((loaded: image.PixelMap | undefined): void => {
        if (generation !== this.loadGeneration) {
          this.releasePixelMap(loaded);
          return;
        }
        if (loaded === undefined) {
          this.loadState = 'failed';
          return;
        }
        this.pixelMap = loaded;
        this.loadState = 'loaded';
      })
      .catch((_error: Error): void => {
        if (generation === this.loadGeneration) {
          this.loadState = 'failed';
        }
      });
  }

  private releaseCurrentPixelMap(): void {
    const current: image.PixelMap | undefined = this.pixelMap;
    this.pixelMap = undefined;
    this.releasePixelMap(current);
  }

  private releasePixelMap(pixelMap: image.PixelMap | undefined): void {
    if (pixelMap !== undefined) {
      void pixelMap.release().catch((_error: Error): void => {});
    }
  }
}
