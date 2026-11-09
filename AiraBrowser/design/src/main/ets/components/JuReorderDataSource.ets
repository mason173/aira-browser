/** 懒加载排序行的数据源；业务仍只提供稳定 key。 */
export class JuReorderDataSource implements IDataSource {
  private items: string[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number { return this.items.length }
  getData(index: number): string { return this.items[index] }

  replace(items: string[]): void {
    if (items.length === this.items.length && items.every((key: string, index: number): boolean =>
      key === this.items[index])) { return }
    this.items = items.slice()
    this.listeners.forEach((listener: DataChangeListener): void => { listener.onDataReloaded() })
  }

  /** 原生排序已经移动了节点，这里同步数据顺序，不重复发送节点移动通知。 */
  move(from: number, to: number): void {
    if (from === to || from < 0 || to < 0 || from >= this.items.length || to >= this.items.length) { return }
    const moved: string = this.items.splice(from, 1)[0]
    this.items.splice(to, 0, moved)
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener) }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index: number = this.listeners.indexOf(listener)
    if (index >= 0) { this.listeners.splice(index, 1) }
  }
}
