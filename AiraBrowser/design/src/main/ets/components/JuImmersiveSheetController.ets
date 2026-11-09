/** 沉浸面板内的子页面导航。宿主持有实例；面板挂载后 pushPage/popPage 生效。 */
export class JuImmersiveSheetController {
  /** 推入一个子页面；带系统转场，系统返回先弹回首页再关面板。 */
  pushPage: (key: string) => void = (_key: string): void => {}
  /** 弹出当前子页面。 */
  popPage: () => void = (): void => {}
}
