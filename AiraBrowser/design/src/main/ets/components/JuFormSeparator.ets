/**
 * 分组表单的行间分隔线。
 *
 * 不公开导出：它只服务 JuFormInput / JuFormTextArea / JuFormSegment 三个行组件。
 *
 * 两个细节与 JuSettingGroup 内部保持一致：
 * - 用一条 `divider_height` 高的 Row + 背景色画线，不用 `Divider`：
 *   `Divider.strokeWidth` 不接受 Resource，线高只能用资源表达。
 * - 左右内缩到卡片内文字基准 `mine_row_padding`，与小标题、卡外说明同一条左基线。
 *   这里直接给在行的 padding 上，不再用 Blank 占位（那是为让开设置行图标用的，表单行没有图标）。
 */
@Builder
function juFormSeparator() {
  Row() {
    Row()
      .layoutWeight(1)
      .height($r('app.float.divider_height'))
      .backgroundColor($r('app.color.setting_separator'))
  }
  .width('100%')
  .padding({
    left: $r('app.float.mine_row_padding'),
    right: $r('app.float.mine_row_padding')
  })
}

export { juFormSeparator }
