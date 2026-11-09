/**
 * 多选状态：全局一份，放在 AppStorage 上共享。
 *
 * 为什么是全局而不是页面内部状态：进入多选要同时协调三件事——
 * ① 页面壳把标题与原本的按钮换成多选壳，② 底部 HDS 页签收掉，
 * ③ 列表行显示/切换勾选。这三处分属不同组件（JuImmersivePage、JuTabs、行组件），
 * 只有共享一份状态才不用层层传参。
 *
 * 限制：同一时刻只能有一个多选上下文。宿主用 `JuImmersivePage.selectEnabled`
 * 声明"这一页支持多选"，避免同屏其它页面也跟着换成多选壳。
 */
export const JU_SELECTING_KEY: string = 'juSelecting'
export const JU_SELECTED_KEY: string = 'juSelected'

/** 当前是否处于多选。 */
export function selectionSelecting(): boolean {
  return AppStorage.get<boolean>(JU_SELECTING_KEY) === true
}

/** 当前已选中的键（拷贝，改它不影响状态）。 */
export function selectionKeys(): string[] {
  const value: string[] | undefined = AppStorage.get<string[]>(JU_SELECTED_KEY)
  return value === undefined ? [] : value.slice()
}

/** 当前已选个数。 */
export function selectionCount(): number {
  return selectionKeys().length
}

/** 某个键是否已选中。 */
export function selectionHas(key: string): boolean {
  return selectionKeys().indexOf(key) >= 0
}

/** 进入多选，并从这里这一项开始选。 */
export function selectionEnter(key: string): void {
  AppStorage.setOrCreate(JU_SELECTING_KEY, true)
  AppStorage.setOrCreate(JU_SELECTED_KEY, [key])
}

/** 切换某一项的勾选（已选则取消）。 */
export function selectionToggle(key: string): void {
  const next: string[] = []
  let removed: boolean = false
  for (const item of selectionKeys()) {
    if (item === key) {
      removed = true
    } else {
      next.push(item)
    }
  }
  if (!removed) {
    next.push(key)
  }
  AppStorage.setOrCreate(JU_SELECTED_KEY, next)
}

/** 直接设定选中的键（全选/全不选都走它）。 */
export function selectionSet(keys: string[]): void {
  AppStorage.setOrCreate(JU_SELECTED_KEY, keys.slice())
}

/** 清空选择但仍在多选态。 */
export function selectionClear(): void {
  AppStorage.setOrCreate(JU_SELECTED_KEY, [])
}

/** 退出多选：状态与选择一起收掉。 */
export function selectionExit(): void {
  AppStorage.setOrCreate(JU_SELECTING_KEY, false)
  AppStorage.setOrCreate(JU_SELECTED_KEY, [])
}
