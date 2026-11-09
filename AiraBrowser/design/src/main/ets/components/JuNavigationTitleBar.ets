import {
  BlurStrategy, DividerShowType, HdsNavigationBackgroundStyle, HdsNavigationIconItemStyle, HdsNavigationTitleBarOptions,
  HdsTitleBarContentStyle, ScrollEffectType, TitleBarContentOptions, TitleSize
} from '@kit.UIDesignKit'
import { LengthMetrics, UIContext } from '@kit.ArkUI'
import { juCircleButtonStyle, juCircleMaterial } from './JuCircleAction'

/** 页面与半模态共用的顶部渐进模糊及遮罩，不向业务暴露滤镜参数。 */
export function juImmersiveTitleBar(ui: UIContext, title: string, extra?: TitleBarContentOptions,
  endPadding?: LengthMetrics,
  fadeHeightResource: Resource = $r('app.float.immersive_header_fade_height')): HdsNavigationTitleBarOptions {
  const host = ui.getHostContext()
  let fadeHeight: number = 0
  let blurRadius: number = 0
  if (host !== undefined) {
    try {
      fadeHeight = ui.px2vp(host.resourceManager.getNumber(fadeHeightResource.id))
      blurRadius = host.resourceManager.getNumberByName('immersive_header_blur_radius')
    } catch (_error) {
    }
  }
  return juNavigationTitleBar(title, true, extra, endPadding, {
    backgroundColor: $r('app.color.status_scrim'),
    maskExtraHeight: fadeHeight,
    blurRadius: blurRadius
  })
}

/** 标题栏按官方写法。按钮的玻璃和投影来自 systemMaterialEffect，不自己画圆底。 */
export function juNavigationTitleBar(title: string, scrollBlur: boolean = true,
  extra?: TitleBarContentOptions, endPadding?: LengthMetrics,
  scrollBackground?: HdsNavigationBackgroundStyle): HdsNavigationTitleBarOptions {
    const button: HdsNavigationIconItemStyle = juCircleButtonStyle()
    const content: HdsTitleBarContentStyle = {
      titleStyle: { mainTitleColor: $r('app.color.foreground') },
      backIconStyle: button,
      menuStyle: button
    }
    const background: HdsNavigationBackgroundStyle = { backgroundColor: Color.Transparent }
    // 渐变模糊的初态与终态使用相同覆盖范围，只插值模糊强度和遮罩色。
    if (scrollBackground !== undefined) {
      background.maskExtraHeight = scrollBackground.maskExtraHeight
      background.blurRadius = LengthMetrics.resource($r('app.float.edge_none')).value
    }
    const bar: HdsNavigationTitleBarOptions = {
      // 标题栏仍是组件级安全区，内容停住时从标题下面开始，往上滚才能穿过去。
      enableComponentSafeArea: true,
      avoidLayoutSafeArea: false,
      padding: {
        start: LengthMetrics.resource($r('app.float.sheet_card_inset')),
        end: endPadding ?? LengthMetrics.resource($r('app.float.sheet_card_inset'))
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: scrollBlur,
          scrollEffectType: scrollBackground === undefined ? ScrollEffectType.IMMERSIVE_GRADIENT_BLUR :
            ScrollEffectType.GRADIENT_BLUR,
          blurEffectiveStartOffset: LengthMetrics.resource($r('app.float.edge_none')),
          blurEffectiveEndOffset: LengthMetrics.resource($r('app.float.navigation_title_blur_extent'))
        },
        blurStrategy: BlurStrategy.ADAPTIVE,
        systemMaterialEffect: juCircleMaterial(),
        originalStyle: {
          backgroundStyle: background,
          contentStyle: content
        },
        scrollEffectStyle: {
          backgroundStyle: scrollBackground ?? background,
          contentStyle: content
        }
      }
    }
    const contentOptions: TitleBarContentOptions = {
      title: extra?.title !== undefined ? extra.title :
        { mainTitle: title, mainTitleSize: TitleSize.TITLE_S },
      divider: { showType: DividerShowType.OFF }
    }
    if (extra?.bottomBuilder !== undefined) {
      contentOptions.bottomBuilder = extra.bottomBuilder
    }
    if (extra?.menu !== undefined) {
      contentOptions.menu = extra.menu
    }
    if (extra?.backIcon !== undefined) {
      contentOptions.backIcon = extra.backIcon
    }
    if (extra?.stackBuilder !== undefined) {
      contentOptions.stackBuilder = extra.stackBuilder
    }
    bar.content = contentOptions
    return bar
  }
