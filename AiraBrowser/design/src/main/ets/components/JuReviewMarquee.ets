import { AnimatorResult } from '@kit.ArkUI'
import { JuAvatar } from './JuAvatar'
import { JuIcon } from './JuIcon'
import { JuReview } from './JuReviewModels'

/** 等速向左移动的评价带。重复完整周期，避免末尾空白；不创建另一层滚动容器。 */
@Component
export struct JuReviewMarquee {
  @Prop @Watch('rebuild') reviews: JuReview[] = []
  @Prop @Watch('syncPlayback') active: boolean = true
  @State private translationX: number = 0
  @State private cycleWidth: number = 0
  @State private repeatCount: number = 2
  private viewportWidth: number = 0
  private mounted: boolean = false
  private visible: boolean = false
  private touching: boolean = false
  private playing: boolean = false
  private generation: number = 0
  private animator: AnimatorResult | undefined = undefined

  aboutToAppear(): void {
    this.mounted = true
    this.rebuild()
  }

  aboutToDisappear(): void {
    this.mounted = false
    this.visible = false
    this.dispose()
  }

  private number(name: string): number {
    const host = this.getUIContext().getHostContext()
    if (host === undefined) { return 0 }
    try { return host.resourceManager.getNumberByName(name) }
    catch (_error) { return 0 }
  }

  private vp(name: string): number {
    return this.getUIContext().px2vp(this.number(name))
  }

  private copies(): number[] {
    const result: number[] = []
    for (let index = 0; index < this.repeatCount; index++) { result.push(index) }
    return result
  }

  private fitCopies(): void {
    this.repeatCount = this.reviews.length < 2 || this.cycleWidth <= 0 ? 1 :
      Math.max(2, Math.ceil(this.viewportWidth / this.cycleWidth) + 1)
  }

  private measureViewport(width: number): void {
    if (!Number.isFinite(width) || width <= 0 || width === this.viewportWidth) { return }
    this.viewportWidth = width
    this.fitCopies()
    this.syncPlayback()
  }

  private rebuild(): void {
    this.dispose()
    this.translationX = 0
    this.cycleWidth = this.reviews.length * (this.vp('review_card_width') + this.vp('review_card_gap'))
    this.fitCopies()
    this.syncPlayback()
  }

  private canPlay(): boolean {
    return this.mounted && this.visible && this.active && !this.touching &&
      this.reviews.length > 1 && this.cycleWidth > 0 && this.viewportWidth > 0
  }

  private syncPlayback(): void {
    if (!this.canPlay()) {
      if (this.playing) { this.animator?.pause() }
      this.playing = false
      return
    }
    if (this.playing) { return }
    try {
      if (this.animator === undefined) {
        const speed: number = this.number('review_speed_vp_per_second')
        if (speed <= 0) { return }
        const generation: number = this.generation
        this.animator = this.getUIContext().createAnimator({
          duration: Math.round(this.cycleWidth / speed * 1000),
          easing: 'linear', delay: 0, fill: 'forwards', direction: 'normal', iterations: -1,
          begin: 0, end: -this.cycleWidth
        })
        this.animator.onFrame = (value: number): void => {
          if (generation === this.generation && this.canPlay()) { this.translationX = value }
        }
      }
      this.animator.play()
      this.playing = true
    } catch (_error) {
      this.dispose()
    }
  }

  private dispose(): void {
    this.generation++
    this.playing = false
    const previous = this.animator
    this.animator = undefined
    if (previous !== undefined) {
      // Animator 在结束时会补发终点帧；先解绑，避免重建／卸载时跳到终点或更新旧组件。
      previous.onFrame = (_value: number): void => {}
      previous.cancel()
    }
  }

  private stars(review: JuReview): number[] {
    const count: number = Number.isFinite(review.rating) ? Math.max(0, Math.min(5, Math.round(review.rating))) : 0
    const result: number[] = []
    for (let index = 0; index < count; index++) { result.push(index) }
    return result
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Row() {
        ForEach(this.copies(), (copy: number) => {
          Row({ space: $r('app.float.review_card_gap') }) {
            ForEach(this.reviews, (review: JuReview) => {
              this.Card(review, copy)
            }, (review: JuReview): string => review.key)
          }
          .width(this.cycleWidth)
          .padding({ right: $r('app.float.review_card_gap') })
        }, (copy: number): string => copy.toString())
      }
      .width(this.cycleWidth * this.repeatCount)
      .translate({ x: this.translationX })
      if (this.reviews.length > 1) {
        this.EdgeFades()
      }
    }
    .width('100%')
    .height(this.reviews.length > 0 ? $r('app.float.review_card_height') : $r('app.float.edge_none'))
    .clip(true)
    .onAreaChange((_oldArea: Area, area: Area): void => { this.measureViewport(Number(area.width)) })
    .onVisibleAreaChange([0, 0.01], (visible: boolean, ratio: number): void => {
      this.visible = visible && ratio > 0
      this.syncPlayback()
    })
    .onTouch((event: TouchEvent): void => {
      if (event.type === TouchType.Down) { this.touching = true }
      if (event.type === TouchType.Up || event.type === TouchType.Cancel) { this.touching = false }
      this.syncPlayback()
    })
  }

  @Builder
  EdgeFades() {
    Row() {
      Column()
        .width($r('app.float.review_edge_fade_width'))
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [[$r('app.color.canvas'), 0], [$r('app.color.canvas_fade'), 1]]
        })
        .hitTestBehavior(HitTestMode.None)
      Blank().layoutWeight(1)
      Column()
        .width($r('app.float.review_edge_fade_width'))
        .height('100%')
        .linearGradient({
          direction: GradientDirection.Right,
          colors: [[$r('app.color.canvas_fade'), 0], [$r('app.color.canvas'), 1]]
        })
        .hitTestBehavior(HitTestMode.None)
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
    .accessibilityLevel('no-hide-descendants')
  }

  @Builder
  Card(review: JuReview, copy: number) {
    Column({ space: $r('app.float.review_copy_gap') }) {
      Row({ space: $r('app.float.review_star_gap') }) {
        ForEach(this.stars(review), (index: number) => {
          JuIcon({ name: $r('app.media.star_fill'), color: $r('app.color.palette_orange'),
            side: $r('app.float.review_star_size') })
        }, (index: number): string => index.toString())
      }
      .width('100%')
      Text(review.title)
        .width('100%')
        .fontSize($r('app.float.font_size_body'))
        .lineHeight($r('app.float.line_height_body'))
        .fontWeight($r('app.integer.font_weight_semibold'))
        .fontColor($r('app.color.foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(review.message)
        .width('100%')
        .fontSize($r('app.float.font_size_caption'))
        .lineHeight($r('app.float.line_height_caption'))
        .fontColor($r('app.color.muted_foreground'))
        .maxLines(3)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Blank().layoutWeight(1)
      Row({ space: $r('app.float.review_copy_gap') }) {
        JuAvatar({ portrait: review.avatar ?? null })
        Text(review.author)
          .fontSize($r('app.float.font_size_caption'))
          .lineHeight($r('app.float.line_height_caption'))
          .fontColor($r('app.color.muted_foreground'))
      }
      .width('100%')
    }
    .width($r('app.float.review_card_width'))
    .height($r('app.float.review_card_height'))
    .alignItems(HorizontalAlign.Start)
    .padding($r('app.float.review_card_padding'))
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .clip(true)
    .accessibilityLevel(copy === 0 ? 'yes' : 'no-hide-descendants')
    .accessibilityText(`${review.author}，${this.stars(review).length} 星，${review.title}。${review.message}`)
  }
}
