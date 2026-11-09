/**
 * 分组表单的白卡容器。`JuSettingGroup` 的编辑态对应物：
 * 它装只读设置行，这个装输入行。
 *
 * 一条规则：**卡片就是容器，行里的控件不能再画一层底**。
 * 卡片本身不加 padding —— 文字内距、行高、分割线内缩都由行负责，只在一处定义。
 * 所以行组件（JuFormInput / JuFormTextArea）都必须让内部控件 `bare`。
 *
 * 一个分组 = `JuSettingHeading`（小节标题）+ 本组件 + 卡外 `JuSettingNote`（说明）。
 */
@Component
export struct JuFormGroup {
  @BuilderParam content: () => void = this.Empty

  @Builder
  Empty() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .backgroundColor($r('app.color.card'))
    .borderRadius($r('app.float.list_detail_card_radius'))
    .clip(true)
  }
}
