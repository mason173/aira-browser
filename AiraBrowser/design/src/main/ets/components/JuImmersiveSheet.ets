import {
  HdsNavDestination, HdsNavDestinationTitleMode, HdsNavigation, HdsNavigationTitleBarOptions,
  HdsNavigationIconOptions, TitleBarContentOptions
} from '@kit.UIDesignKit'
import { JuCircleAction, juCircleAction, juCircleMenu } from './JuCircleAction'
import { JuFloatingFooter } from './JuFloatingFooter'
import { juImmersiveTitleBar } from './JuNavigationTitleBar'
import { JuImmersiveSheetController } from './JuImmersiveSheetController'

/** 沉浸式半模态内容壳。业务只提供标题、正文、关闭及可选底部操作。 */
@Component
export struct JuImmersiveSheet {
  @Prop title: string = ''
  /** 已有宿主导航栈时直接输出子页，避免再嵌套 Navigation。 */
  @Prop asDestination: boolean = false
  @Prop showBack: boolean = false
  /** 简短告知面板可把标题放进正文；不创建第二套滚动容器。 */
  @Prop showTitleBar: boolean = true
  @Prop contentInset: Resource = $r('app.float.sheet_card_inset')
  @Prop contentTopInset: Resource = $r('app.float.edge_none')
  /** 自定义双按钮等操作固定在正文外，短窗口时正文让出操作区。 */
  @Prop fixedFooter: boolean = false
  @BuilderParam footerContent: () => void = this.Empty
  @Prop actions: JuCircleAction[] = [JuCircleAction.Close]
  @Prop footerLabel: string = ''
  /** 双按钮 footer 的左侧按钮；样式与 JuFloatingFooter／订阅详情一致。 */
  @Prop secondaryLabel: string = ''
  @Prop secondaryDanger: boolean = false
  @Prop secondarySolid: boolean = false
  /** 默认只展示按钮，只有显式开启时才响应点击。 */
  @Prop footerTappable: boolean = false
  /** 面板内子页面导航；仅默认模式（面板自建 HDS 导航栈）可用。 */
  controller: JuImmersiveSheetController = new JuImmersiveSheetController()
  /** 子页面正文；按官方案例经 navDestination 路由，系统转场与返回逐级生效。 */
  @BuilderParam subPage: (key: string) => void = this.EmptyKey
  subPageTitle: (key: string) => string = (_key: string): string => ''
  onFooterTap: () => void = (): void => {}
  onSecondaryFooterTap: () => void = (): void => {}
  onClose: () => void = (): void => {}
  onBack: () => void = (): void => {}
  onAction: (action: JuCircleAction) => void = (_action: JuCircleAction): void => {}
  @BuilderParam content: () => void
  private scroller: Scroller = new Scroller()
  private pageScroller: Scroller = new Scroller()
  private stack: NavPathStack = new NavPathStack()

  aboutToAppear(): void {
    this.controller.pushPage = (key: string): void => { this.stack.pushPathByName(key, null, true) }
    this.controller.popPage = (): void => { this.stack.pop() }
  }

  private titleBar(): HdsNavigationTitleBarOptions {
    const content: TitleBarContentOptions = {}
    if (this.showBack) {
      content.backIcon = juCircleAction(JuCircleAction.Back, (): void => { this.onBack() })
    }
    if (this.actions.length > 0) {
      const menus: HdsNavigationIconOptions[] = []
      for (const action of this.actions) {
        menus.push(juCircleAction(action, (): void => {
          if (action === JuCircleAction.Close) { this.onClose() }
          else { this.onAction(action) }
        }))
      }
      content.menu = juCircleMenu(menus)
    }
    return juImmersiveTitleBar(this.getUIContext(), this.title, content, undefined,
      $r('app.float.immersive_sheet_header_fade_height'))
  }

  build() {
    if (this.asDestination) {
      this.Destination()
    } else {
      HdsNavigation(this.stack) {
        this.Destination()
      }
      .hideTitleBar(true)
      .hideToolBar(true)
      .mode(NavigationMode.Stack)
      // 官方路由：NavPathStack 配合 HdsNavDestination 子页面容器。
      .navDestination(this.SubPages)
      .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
      .width('100%')
      .height('100%')
      .clip(false)
      .backgroundColor($r('app.color.canvas'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
  }

  @Builder
  Destination() {
    HdsNavDestination() {
      Column() {
        Stack({ alignContent: Alignment.TopStart }) {
        Scroll(this.scroller) {
          Column() { this.content() }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            // 面板比整页更紧凑；用布局外边距上移正文，滚动范围同步收紧。
            .margin({ top: this.showTitleBar ? $r('app.float.immersive_sheet_content_top_margin') :
              $r('app.float.edge_none') })
            .padding({
              top: this.contentTopInset,
              left: this.contentInset,
              right: this.contentInset,
              bottom: !this.fixedFooter && this.footerLabel.length > 0 ? $r('app.float.sheet_footer_fade_height') :
                $r('app.float.padding_screen_bottom')
            })
          }
          .width('100%')
          .height('100%')
          .align(Alignment.TopStart)
          .scrollBar(BarState.Off)
          .clipContent(ContentClipMode.SAFE_AREA)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })

        if (!this.fixedFooter && this.footerLabel.length > 0) {
          JuFloatingFooter({
            label: this.footerLabel,
            secondaryLabel: this.secondaryLabel,
            secondaryDanger: this.secondaryDanger,
            secondarySolid: this.secondarySolid,
            tappable: this.footerTappable,
            onTap: (): void => { this.onFooterTap() },
            onSecondaryTap: (): void => { this.onSecondaryFooterTap() }
          })
        }
        }
        .width('100%')
        .layoutWeight(1)
        .clip(false)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        if (this.fixedFooter) { this.footerContent() }
      }
      .width('100%')
      .height('100%')
      .clip(false)
      .backgroundColor($r('app.color.canvas'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    }
    .titleBar(this.titleBar())
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .hideBackButton(!this.showBack)
    .hideTitleBar(!this.showTitleBar)
    .bindToScrollable([this.scroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .clip(false)
    .backgroundColor($r('app.color.canvas'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      if (!this.showBack) { return false }
      this.onBack()
      return true
    })
  }

  /** 子页面走官方 navDestination 路由：自带标题栏、系统转场和逐级返回。 */
  @Builder
  SubPages(name: string) {
    HdsNavDestination() {
      Scroll(this.pageScroller) {
        Column() { this.subPage(name) }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .margin({ top: this.showTitleBar ? $r('app.float.immersive_sheet_content_top_margin') :
            $r('app.float.edge_none') })
          .padding({
            top: this.contentTopInset,
            left: this.contentInset,
            right: this.contentInset,
            bottom: $r('app.float.padding_screen_bottom')
          })
      }
      .width('100%')
      .height('100%')
      .align(Alignment.TopStart)
      .scrollBar(BarState.Off)
      .clipContent(ContentClipMode.SAFE_AREA)
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .titleBar(juImmersiveTitleBar(this.getUIContext(), this.subPageTitle(name), {
      backIcon: juCircleAction(JuCircleAction.Back, (): void => { this.stack.pop() })
    }, undefined, $r('app.float.immersive_sheet_header_fade_height')))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.pageScroller])
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .clip(false)
    .backgroundColor($r('app.color.canvas'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .onBackPressed((): boolean => {
      this.stack.pop()
      return true
    })
  }

  @Builder
  Empty() {}

  @Builder
  EmptyKey(_key: string) {}
}
