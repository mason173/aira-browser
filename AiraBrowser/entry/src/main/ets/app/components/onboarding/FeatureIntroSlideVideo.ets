function featureIntroPoster(slideId: string): Resource {
  if (slideId === 'ad_block') {
    return $rawfile('feature_intro_ad_block_poster.jpg');
  }
  if (slideId === 'video_takeover') {
    return $rawfile('feature_intro_video_takeover_poster.jpg');
  }
  if (slideId === 'user_scripts') {
    return $rawfile('feature_intro_user_scripts_poster.jpg');
  }
  return $rawfile('feature_intro_sync_poster.jpg');
}

function featureIntroVideo(slideId: string): Resource {
  if (slideId === 'ad_block') {
    return $rawfile('feature_intro_ad_block.mp4');
  }
  if (slideId === 'video_takeover') {
    return $rawfile('feature_intro_video_takeover.mp4');
  }
  if (slideId === 'user_scripts') {
    return $rawfile('feature_intro_user_scripts.mp4');
  }
  return $rawfile('feature_intro_sync.mp4');
}

@Component
export struct FeatureIntroSlideVideo {
  slideId: string = '';
  controller: VideoController = new VideoController();
  @Prop shown: boolean = false;
  onPrepared: () => void = (): void => undefined;
  onStart: () => void = (): void => undefined;

  build() {
    Stack() {
      Image(featureIntroPoster(this.slideId))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
      Video({
        src: featureIntroVideo(this.slideId),
        controller: this.controller,
        previewUri: featureIntroPoster(this.slideId)
      })
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .muted(true)
        .controls(false)
        .loop(true)
        .autoPlay(false)
        .opacity(this.shown ? 1 : 0)
        .onPrepared((): void => {
          this.onPrepared();
        })
        .onStart((): void => {
          this.onStart();
        })
    }
    .width('100%')
    .height('100%')
  }
}
