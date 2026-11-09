/** 业务只请求回到顶部并接收结果，不接触页面内部的 Scroller。 */
export class JuImmersivePageController {
  /** @internal 由挂载的页面绑定；未挂载时立即报告未到达。 */
  scrollToTopAction: (onFinish: (reachedTop: boolean) => void) => void =
    (onFinish: (reachedTop: boolean) => void): void => { onFinish(false) }

  scrollToTop(onFinish: (reachedTop: boolean) => void): void {
    this.scrollToTopAction(onFinish)
  }
}
