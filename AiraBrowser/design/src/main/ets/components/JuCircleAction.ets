import {
  hdsMaterial, HdsNavigationIconItemStyle, HdsNavigationIconOptions, HdsNavigationMenuContentOptions,
  HdsNavigationMenuItemOptions, SystemMaterialParams
} from '@kit.UIDesignKit'

/** 圆形操作的唯一图标与语义来源；页面只选择操作并提供回调。
 * 无障碍名称必须与具体业务无关：这里是通用组件，文案由调用方场景决定，
 * 不能写死成某个 App 的用词（历史上写死过订阅场景的名词，2FA 应用会被读成「新增订阅」）。
 */
export enum JuCircleAction {
  Add,
  Expand,
  Collapse,
  Charts,
  Back,
  Search,
  Done,
  Close,
  Edit,
  Create,
  SignOut,
  RestorePurchase,
  SelectAll,
  Delete,
  Move,
  Export,
  Settings
}

export function juCircleSymbol(action: JuCircleAction): Resource {
  switch (action) {
    case JuCircleAction.Add: return $r('sys.symbol.plus')
    case JuCircleAction.Expand: return $r('sys.symbol.chevron_down')
    case JuCircleAction.Collapse: return $r('sys.symbol.chevron_up')
    case JuCircleAction.Charts: return $r('sys.symbol.data_proportion')
    case JuCircleAction.Back: return $r('sys.symbol.chevron_left')
    case JuCircleAction.Search: return $r('sys.symbol.magnifyingglass')
    case JuCircleAction.Done: return $r('sys.symbol.checkmark')
    case JuCircleAction.Close: return $r('sys.symbol.xmark')
    case JuCircleAction.Edit: return $r('sys.symbol.square_and_pencil')
    case JuCircleAction.Create: return $r('sys.symbol.plus')
    case JuCircleAction.SignOut: return $r('sys.symbol.power')
    case JuCircleAction.RestorePurchase: return $r('sys.symbol.arrow_clockwise')
    case JuCircleAction.SelectAll: return $r('sys.symbol.checkmark_circle')
    case JuCircleAction.Delete: return $r('sys.symbol.trash')
    case JuCircleAction.Move: return $r('sys.symbol.move')
    case JuCircleAction.Export: return $r('sys.symbol.share')
    case JuCircleAction.Settings: return $r('sys.symbol.gearshape')
    default: return $r('sys.symbol.xmark')
  }
}

export function juCircleLabel(action: JuCircleAction): string {
  switch (action) {
    case JuCircleAction.Add: return '新增'
    case JuCircleAction.Expand: return '展开'
    case JuCircleAction.Collapse: return '收起'
    case JuCircleAction.Charts: return '打开支出统计'
    case JuCircleAction.Back: return '返回'
    case JuCircleAction.Search: return '搜索'
    case JuCircleAction.Done: return '完成'
    case JuCircleAction.Close: return '关闭'
    case JuCircleAction.Edit: return '编辑'
    case JuCircleAction.Create: return '新建'
    case JuCircleAction.SignOut: return '退出登录'
    case JuCircleAction.RestorePurchase: return '恢复购买'
    case JuCircleAction.SelectAll: return '全选'
    case JuCircleAction.Delete: return '删除'
    case JuCircleAction.Move: return '移动'
    case JuCircleAction.Export: return '导出'
    case JuCircleAction.Settings: return '设置'
    default: return '关闭'
  }
}

/** 官方导航菜单和返回键的适配器；不接收 SVG 或页面自定义底色。 */
export function juCircleAction(kind: JuCircleAction, onTap: () => void,
  enabled: boolean = true): HdsNavigationIconOptions {
  return {
    icon: juCircleSymbol(kind),
    label: juCircleLabel(kind),
    isEnabled: enabled,
    action: (): void => { if (enabled) { onTap() } }
  }
}

export function juCircleMenu(actions: HdsNavigationIconOptions[]): HdsNavigationMenuContentOptions {
  const items: HdsNavigationMenuItemOptions[] = []
  for (let index = 0; index < actions.length; index++) {
    items.push({ content: actions[index] })
  }
  return { maxCount: items.length, value: items }
}

export function juCircleButtonStyle(): HdsNavigationIconItemStyle {
  return { iconColor: $r('app.color.foreground') }
}

/** 标题栏与独立圆形按钮共用材质分级策略，圆底和投影交给系统。 */
export function juCircleMaterial(
  level: hdsMaterial.MaterialLevel = hdsMaterial.MaterialLevel.ADAPTIVE): SystemMaterialParams {
  return { materialType: hdsMaterial.MaterialType.ADAPTIVE, materialLevel: level }
}
