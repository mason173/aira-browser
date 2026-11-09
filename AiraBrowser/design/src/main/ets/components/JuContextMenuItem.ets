/**
 * 长按菜单里的一项。
 *
 * `danger` 为真表示危险操作（红色），并会与上面的常规项之间自动加一条分割线——
 * 与常见的系统长按菜单一致：常规操作在上，危险操作单独一组放在下面。
 */
export class JuContextMenuItem {
  /** 稳定唯一的 key，宿主按它分发动作。 */
  key: string = ''
  label: string = ''
  /** 内容图标，用库内 SVG（`JuIcon` 的同一套）。 */
  icon: Resource | null = null
  danger: boolean = false

  constructor(key: string, label: string, icon: Resource | null = null, danger: boolean = false) {
    this.key = key
    this.label = label
    this.icon = icon
    this.danger = danger
  }
}
