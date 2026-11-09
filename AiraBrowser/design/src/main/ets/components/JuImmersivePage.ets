import { ColorMetrics, LengthMetrics, curves, uiMaterial } from '@kit.ArkUI'
import {
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigation, HdsNavigationIconOptions,
  HdsNavigationTitleBarOptions, HdsNavigationTitleMode,
  TitleBarContentOptions
} from '@kit.UIDesignKit'
import { JuCapsuleTab } from './JuCapsuleTab'
import { JuCircleAction, juCircleAction, juCircleMenu } from './JuCircleAction'
import { JuAvatar } from './JuAvatar'
import { juImmersiveTitleBar } from './JuNavigationTitleBar'
import { JuImmersivePageController } from './JuImmersivePageController'
import { JuFloatingFooter } from './JuFloatingFooter'
import { JU_SELECTING_KEY } from '../select/SelectionState'

/** 松绑后的偏移结果：没绑可滚动容器时这些字段都不存在。 */
interface OffsetResultView {
  xOffset?: number
  yOffset?: number
}

/** 沉浸式滚动页。业务页只提供标题、操作、可选分段与正文，不自行处理滚动和安全区。 */
@Component
export struct JuImmersivePage {
  @Prop title: string = ''
  /** 非空时由导航组件统一管理初始和滚动状态栏前景，避免与窗口颜色设置竞争。 */
  @Prop statusBarContentColor: ResourceColor | undefined = undefined
  /** 已在外部导航栈内时直接作为子页面，不再嵌套 Navigation。 */
  @Prop asDestination: boolean = false
  @Prop showBack: boolean = false
  @Prop actions: JuCircleAction[] = []
  /** 顶栏最右侧的账号圆形操作；空串头像显示人形图标。 */
  @Prop showAccountAction: boolean = false
  @Prop accountAvatar: string = ''
  /**
   * 标题栏左端的文字胶囊（自绘在 stackBuilder 叠加区）。字号固定、宽度随文字自长，
   * 不会像 HDS 文字型返回键那样放不下就缩小。非空时它顶替返回键与标题。
   *
   * 注意：叠加区里的自绘按钮收不到点击，所以它**只做展示**；
   * `onLeading` 仅在叠加区意外可点时生效，真正要按的动作请放在正文里。
   */
  @Prop leadingLabel: string = ''
  /**
   * 宿主声明本页支持多选。
   *
   * 多选状态是全局一份（`SelectionState`），但同一屏可能挂着多个页面（页签）；
   * 只有开了这个开关的页才会跟着换成多选壳，否则整个应用都会一起变。
   */
  @Prop selectEnabled: boolean = false
  /** 多选态左上角文字胶囊的文案（如“全选（3）”）；空串不显示。 */
  @Prop selectLeadingLabel: string = ''
  /** 点左上角文字胶囊（多选态）。 */
  onSelectLeading: () => void = (): void => {}
  /** 多选态左下角：宿主自绘（如 JuGlassIconBar），库负责浮到左下角；不给就什么都不显示。 */
  @BuilderParam selectBottomLeading: () => void = this.EmptySelect
  /** 多选态右下角：宿主自绘（如 JuCircleButton）；不给就什么都不显示。 */
  @BuilderParam selectBottomTrailing: () => void = this.EmptySelect
  /** 多选全局开关；由 SelectionState 维护，页签与页壳都读它。 */
  @StorageProp(JU_SELECTING_KEY) private selectionOn: boolean = false
  /** 空数组不显示分段；顶栏分段沿用 JuCapsuleTab 的紧凑规格。 */
  @Prop tabLabels: string[] = []
  @Prop selectedTab: number = 0
  /** 底部悬浮导航覆盖正文时，在滚动内容末尾留出其空间。 */
  @Prop hasTabBar: boolean = false
  /** 标题下方固定内容的高度；默认不创建该区域。 */
  @Prop headerContentHeight: Resource = $r('app.float.edge_none')
  @Prop footerLabel: string = ''
  @Prop footerTappable: boolean = false
  /** 命中这些内容手势时，外层纵向滚动让出本次识别。普通页面留空。 */
  @Prop priorityGestureTags: string[] = []
  /** 正文是 List 等滚动容器时，由它接管滚动，并接收页面提供的控制器和留白。 */
  @Prop selfScroll: boolean = false
  /**
   * 正文自己做了分页时，把各页的滚动器一并声明出来。
   *
   * 标题栏的渐进模糊／淡出走 `bindToScrollable`：它只知道组件自己的 scroller。
   * 宿主若把正文换成自己的分页容器（每页一个 Scroller），组件那个 scroller 就没人用了，
   * 标题栏于是不再随滚动变化——连"滚回顶部"也一起失效。
   * 把分页的滚动器从这里交回来，两个能力都恢复（2026-10-18）。
   */
  @Prop extraScrollers: Scroller[] = []
  /** 固定数量的横向正文分页；0 保持普通页面，不能与 selfScroll 同用。 */
  @Prop pageCount: number = 0
  @Prop @Watch('syncPage') pageIndex: number = 0
  controller: JuImmersivePageController = new JuImmersivePageController()
  onAction: (action: JuCircleAction) => void = (_action: JuCircleAction): void => {}
  onLeading: () => void = (): void => {}
  onAccount: () => void = (): void => {}
  onTabChange: (index: number) => void = (_index: number): void => {}
  onBack: () => void = (): void => {}
  onFooterTap: () => void = (): void => {}
  /** 多选态右上角那个固定的完成勾。 */
  onSelectDone: () => void = (): void => {}
  onPageChange: (index: number) => void = (_index: number): void => {}
  @BuilderParam content: (scroller: Scroller, bottomInset: Resource, onScrollStop: () => void) => void = this.Empty
  @BuilderParam pageContent: (index: number) => void = this.EmptyPage
  @BuilderParam headerContent: () => void = this.Empty
  private scroller: Scroller = new Scroller()
  private stack: NavPathStack = new NavPathStack()
  private scrollCompletion: ((reachedTop: boolean) => void) | null = null
  private pageScrollers: Scroller[] = []
  private swiperController: SwiperController = new SwiperController()
  private swiperIndex: number = 0
  private pagerReady: boolean = false

  private pageIndices(): number[] {
    const indices: number[] = []
    for (let index = 0; index < this.pageCount; index++) { indices.push(index) }
    return indices
  }

  private pageScroller(index: number): Scroller {
    while (this.pageScrollers.length <= index) { this.pageScrollers.push(new Scroller()) }
    return this.pageScrollers[index]
  }

  private scrollSources(): Scroller[] {
    if (this.pageCount > 0) {
      return this.pageIndices().map((index: number): Scroller => this.pageScroller(index))
    }
    // 宿主自带分页时用它的滚动器：标题栏的模糊与淡出要跟着真正在滚的那个走。
    return this.extraScrollers.length > 0 ? this.extraScrollers : [this.scroller]
  }

  private currentScroller(): Scroller {
    return this.pageCount > 0 ? this.pageScroller(this.pageIndex) : this.scroller
  }

  private syncPage(): void {
    this.completeReturn(false)
    if (this.pagerReady && this.pageIndex !== this.swiperIndex) {
      this.swiperIndex = this.pageIndex
      this.swiperController.changeIndex(this.pageIndex, true)
    }
  }

  aboutToAppear(): void {
    this.controller.scrollToTopAction = (onFinish: (reachedTop: boolean) => void): void => {
      this.completeReturn(false)
      if (this.offsetTop(this.currentScroller()) <= 0) {
        onFinish(true)
        return
      }
      this.scrollCompletion = onFinish
      this.currentScroller().scrollTo({
        xOffset: 0,
        yOffset: 0,
        animation: {
          duration: this.number('motion_content_forward_duration'),
          curve: curves.cubicBezierCurve(this.number('motion_content_curve_x1'),
            this.number('motion_content_curve_y1'), this.number('motion_content_curve_x2'),
            this.number('motion_content_curve_y2'))
        }
      })
    }
  }

  aboutToDisappear(): void {
    this.pagerReady = false
    this.controller.scrollToTopAction = (onFinish: (reachedTop: boolean) => void): void => { onFinish(false) }
    this.completeReturn(false)
  }

  private completeReturn(reachedTop: boolean): void {
    const callback = this.scrollCompletion
    this.scrollCompletion = null
    if (callback !== null) { callback(reachedTop) }
  }

  private handleScrollStop(scroller: Scroller = this.currentScroller()): void {
    if (scroller !== this.currentScroller()) { return }
    this.completeReturn(this.offsetTop(scroller) <= 0)
  }

  /**
   * 当前纵向偏移；**没绑到任何可滚动容器时返回 0**（当作"已在顶部"）。
   *
   * 为什么不能直接写 `scroller.currentOffset().yOffset`：这个组件把 scroller 交给
   * 正文用，正文可以不用它——例如每页各自持有 Scroller 的分页页面（令牌页就是这样）。
   * 那时这个 scroller 是"空"的，`currentOffset()` 返回 undefined，取 `.yOffset`
   * 会把进程带走（2026-10-18 修：列表滚动一停就闪退）。
   * 返回 0 而不是抛错，是让它退化成"没有可滚动内容"，调用方的语义仍然成立。
   */
  private offsetTop(scroller: Scroller): number {
    const result = scroller.currentOffset() as Object as OffsetResultView | undefined
    if (result === undefined || result.yOffset === undefined) {
      return 0
    }
    return result.yOffset
  }

  private bottomInset(): Resource {
    if (this.inSelect()) { return $r('app.float.select_bar_reserved_height') }
    return this.footerLabel.length > 0 ? $r('app.float.sheet_footer_fade_height') :
      this.hasTabBar ? $r('app.float.tab_bar_reserved_height') : $r('app.float.padding_screen_bottom')
  }

  /** 本页是否正处于多选态（全局开关 + 本页声明支持）。 */
  private inSelect(): boolean {
    return this.selectEnabled && this.selectionOn
  }

  /** 多选态下左上角的文案；非多选态用页面自己的 leadingLabel。 */
  private effectiveLeading(): string {
    return this.inSelect() ? this.selectLeadingLabel : this.leadingLabel
  }

  /** 多选态下右上角固定一个完成勾；其余时候用页面自己的操作。 */
  private effectiveActions(): JuCircleAction[] {
    return this.inSelect() ? [JuCircleAction.Done] : this.actions
  }

  private judgePagePan(current: GestureRecognizer, others: GestureRecognizer[]): GestureJudgeResult {
    if (this.priorityGestureTags.length === 0 || !current.isBuiltIn() ||
      current.getType() !== GestureControl.GestureType.PAN_GESTURE) {
      return GestureJudgeResult.CONTINUE
    }
    for (const recognizer of others) {
      if (this.priorityGestureTags.indexOf(recognizer.getTag()) >= 0) {
        return GestureJudgeResult.REJECT
      }
    }
    return GestureJudgeResult.CONTINUE
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

  private headerInset(): number {
    const edge: number = this.vp('padding_page_compact')
    let inset = edge
    if (this.tabLabels.length > 0) {
      inset += this.vp('capsule_tab_compact_width') +
        (this.actions.length > 0 ? this.vp('navigation_header_action_gap') : 0)
    }
    if (this.showAccountAction) {
      inset += this.vp('sidebar_avatar_size') + this.vp('navigation_header_action_gap')
    }
    return inset
  }

  private titleBar(): HdsNavigationTitleBarOptions {
    const selecting: boolean = this.inSelect()
    const leading: string = this.effectiveLeading()
    const content: TitleBarContentOptions = {}
    if (this.showBack && leading.length === 0) {
      content.backIcon = juCircleAction(JuCircleAction.Back, (): void => { this.onBack() })
    }
    const actions: JuCircleAction[] = this.effectiveActions()
    if (actions.length > 0) {
      const menus: HdsNavigationIconOptions[] = []
      for (const action of actions) {
        menus.push(juCircleAction(action, (): void => {
          if (selecting) {
            if (action === JuCircleAction.Done) { this.onSelectDone() }
            return
          }
          this.onAction(action)
        }))
      }
      content.menu = juCircleMenu(menus)
    }
    if (this.tabLabels.length > 0 || this.showAccountAction || leading.length > 0) {
      content.stackBuilder = (): void => { this.HeaderOverlay() }
    }
    if (LengthMetrics.resource(this.headerContentHeight).value > 0) {
      content.bottomBuilder = {
        builder: (): void => { this.headerContent() },
        height: this.headerContentHeight
      }
    }
    return juImmersiveTitleBar(this.getUIContext(), selecting ? '' : this.title, content,
      LengthMetrics.vp(this.headerInset()))
  }

  private systemBarStyle(): SystemBarStyle | undefined {
    if (this.statusBarContentColor === undefined) { return undefined }
    return { statusBarContentColor: ColorMetrics.resourceColor(this.statusBarContentColor).color }
  }

  build() {
    if (this.asDestination) {
      HdsNavDestination() {
        this.Body()
      }
      .titleBar(this.titleBar())
      .systemBarStyle(this.systemBarStyle(), this.systemBarStyle())
      .titleMode(HdsNavDestinationTitleMode.MINI)
      .hideBackButton(this.effectiveLeading().length > 0 || !this.showBack)
      .hideTitleBar(false)
      .bindToScrollable(this.scrollSources())
      // 子页继承宿主的顶部布局安全区，不能照搬根 Navigation 的顶部忽略配置。
      // expandSafeArea 保留向状态栏绘制的范围，标题仍按原布局位置显示。
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.canvas'))
      .onBackPressed((): boolean => {
        if (!this.showBack) { return false }
        this.onBack()
        return true
      })
    } else {
      HdsNavigation(this.stack) {
        this.Body()
      }
      .hideToolBar(true)
      .mode(NavigationMode.Stack)
      .titleBar(this.titleBar())
      .systemBarStyle(this.systemBarStyle(), this.systemBarStyle())
      .titleMode(HdsNavigationTitleMode.MINI)
      .hideBackButton(this.effectiveLeading().length > 0 || !this.showBack)
      .bindToScrollable(this.scrollSources())
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .clip(false)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor($r('app.color.canvas'))
    }
  }

  @Builder
  Body() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (this.pageCount > 0) {
        this.PagedBody()
      } else if (this.selfScroll) {
        this.content(this.scroller, this.bottomInset(), (): void => { this.handleScrollStop() })
      } else {
        this.ScrolledBody()
      }

      if (this.footerLabel.length > 0) {
        JuFloatingFooter({ label: this.footerLabel, tappable: this.footerTappable,
          lift: this.hasTabBar ? $r('app.float.tab_bar_reserved_height') : $r('app.float.edge_none'),
          onTap: (): void => { this.onFooterTap() } })
      }

      if (this.inSelect()) {
        this.SelectCornerBar()
      }
    }
    .width('100%')
    .height('100%')
    .clip(false)
  }

  /**
   * 多选态底部两个角：左上/右上是标题栏槽位，这里只放左下与右下。
   *
   * 两个角都是宿主自绘（不给就什么都不显示），库只负责把它们浮到底部两端、
   * 避让左右页边距与底部安全区；正文底部也已按 `select_bar_reserved_height` 留白，
   * 所以最后一行不会被盖住。
   */
  @Builder
  SelectCornerBar() {
    Column() {
      Blank().layoutWeight(1)
      Row() {
        this.selectBottomLeading()
        Blank().layoutWeight(1)
        this.selectBottomTrailing()
      }
      .width('100%')
      .padding({
        left: $r('app.float.padding_page_edge'),
        right: $r('app.float.padding_page_edge'),
        // 与 JuFloatingFooter 同一档：足够跨过底部手势条，又不'贴着屏幕底'。
        bottom: $r('app.float.gap_section')
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  ScrolledBody(page: number = -1) {
    Scroll(page < 0 ? this.scroller : this.pageScroller(page)) {
        Column() {
          if (page < 0) {
            this.content(this.scroller, this.bottomInset(), (): void => { this.handleScrollStop() })
          } else {
            this.pageContent(page)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ bottom: this.bottomInset() })
        // 底栏抬升避开页签后，滚动正文也要多留出页签的高度。
        .margin({ bottom: this.hasTabBar && this.footerLabel.length > 0 ?
          $r('app.float.tab_bar_reserved_height') : $r('app.float.edge_none') })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .clipContent(ContentClipMode.SAFE_AREA)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .onGestureRecognizerJudgeBegin((_event: BaseGestureEvent, current: GestureRecognizer,
        others: GestureRecognizer[]): GestureJudgeResult => this.judgePagePan(current, others))
      .onScrollStop(() => { this.handleScrollStop(page < 0 ? this.scroller : this.pageScroller(page)) })
  }

  @Builder
  PagedBody() {
    Swiper(this.swiperController) {
      ForEach(this.pageIndices(), (index: number) => {
        this.ScrolledBody(index)
      }, (index: number): string => index.toString())
    }
    .width('100%')
    .height('100%')
    .vertical(false)
    .loop(false)
    .indicator(false)
    .cachedCount(this.number('immersive_page_cached_pages'))
    .duration(this.number('motion_membership_page_duration'))
    .curve(Curve.EaseInOut)
    .clip(false)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onAppear((): void => {
      this.pagerReady = true
      this.swiperIndex = this.pageIndex
      this.swiperController.changeIndex(this.pageIndex, false)
    })
    .onChange((index: number): void => {
      if (!this.pagerReady) { return }
      this.completeReturn(false)
      this.swiperIndex = index
      this.onPageChange(index)
    })
  }

  @Builder
  Empty() {}

  @Builder
  EmptyPage(_index: number) {}

  @Builder
  EmptySelect() {}

  @Builder
  HeaderOverlay() {
    Row() {
      if (this.effectiveLeading().length > 0) {
        this.LeadingCapsule()
      }
      // 分段靠**最右**，官方菜单按钮由标题栏 `endPadding` 让位到它左侧：
      // 模块按 `padding_page_compact + capsule_tab_compact_width`（有按钮再
      // `+ navigation_header_action_gap`）给标题栏算右边距，分段必须落在
      // 这段预留区内。把分段放到左边（2026-10-18 多选那次重构试过）会让按钮
      // 悬在中间、右边空一条，分段还会盖住标题——恢复这段前请先看
      // docs/组件.md 的「按钮用官方标题栏菜单，Tab 位于其右侧」。
      Blank().layoutWeight(1)
      if (this.tabLabels.length > 0) {
        JuCapsuleTab({
          labels: this.tabLabels,
          selected: this.selectedTab,
          compact: true,
          onSelect: (index: number): void => { this.onTabChange(index) }
        })
      }
      if (this.showAccountAction) {
        // 自绘圆形头像：HDS 菜单图标不认头像地址，JuAvatar 负责圆形裁剪与人形回落。
        Column() {
          JuAvatar({ url: this.accountAvatar })
        }
        .onClick((): void => { this.onAccount() })
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(VerticalAlign.Center)
    // 与 HDS 标题栏自己的左右内距对齐（juNavigationTitleBar 的 padding.start）：
    // 叠加区里的文字胶囊要落在和返回键／标题一样的位置上。
    .padding({ left: $r('app.float.sheet_card_inset'), right: $r('app.float.sheet_card_inset') })
    .hitTestBehavior(HitTestMode.Transparent)
  }

  /**
   * 标题栏左端的文字胶囊。
   *
   * 不用 HDS 的文字型返回键（`TextStyleMode.NORMAL`）：那个超宽就把字号缩小，
   * 而这里要的是「字号不变、胶囊变长」。
   *
   * 玻璃材质走官方通用属性 `systemMaterial(new uiMaterial.ImmersiveMaterial(...))`：
   * 官方文档明确，沉浸光感的普通组件只在 Navigation/NavDestination 标题栏内生效，
   * 而这个胶囊正好画在标题栏的 `stackBuilder` 叠加区里，所以能拿到真正的沉浸光感。
   * 高度取 `circle_action_size`：与标题栏里那个圆形操作同高，两者才配套。
   * 材质自带投影（`applyShadow` 默认 true），不再额外加 `shadow`。
   *
   * 叠加区的自绘内容收不到点击，所以只做展示；选中全部的动作在正文里的圆钮上。
   */
  @Builder
  LeadingCapsule() {
    Row() {
      Text(this.effectiveLeading())
        .fontSize($r('app.float.font_size_body'))
        .fontColor($r('app.color.foreground'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Clip })
    }
    .height($r('app.float.circle_action_size'))
    .padding({ left: $r('app.float.gap_header'), right: $r('app.float.gap_header') })
    .borderRadius($r('app.float.circle_action_radius'))
    .systemMaterial(new uiMaterial.ImmersiveMaterial({
      style: uiMaterial.ImmersiveStyle.ULTRA_THIN
    }))
    // 多选态与普通态分别走各自的回调：左上胶囊的点击不由宿主两处分别接，
    // 否则换成多选壳时很容易漏掉一边（踩过：全选点了没反应）。
    .onClick((): void => {
      if (this.inSelect()) {
        this.onSelectLeading()
        return
      }
      this.onLeading()
    })
  }
}
