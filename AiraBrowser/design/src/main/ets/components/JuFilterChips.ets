import { uiMaterial } from '@kit.ArkUI'
import { ThemeRoles, THEME_HUE_KEY, THEME_HUE_DEFAULT, themeRoles } from '../theme/ThemeColor'

export interface JuFilterChipOption {
  /** 稳定且唯一的筛选值；允许空字符串表示业务自己的「全部」。 */
  value: string
  label: ResourceStr
}

/** 单选横向筛选栏。选中状态由调用方持有，组件统一材质、滚动和投影留白。 */
@Component
export struct JuFilterChips {
  @Prop items: JuFilterChipOption[] = []
  @Prop selectedValue: string = ''
  @StorageProp(THEME_HUE_KEY) themeHue: number = THEME_HUE_DEFAULT
  onSelect: (value: string) => void = (_value: string): void => {}

  private roles(): ThemeRoles {
    return themeRoles(this.themeHue, this.getUIContext().getHostContext())
  }

  build() {
    Scroll() {
      Row() {
        ForEach(this.items, (item: JuFilterChipOption) => {
          this.Chip(item)
        }, (item: JuFilterChipOption) => item.value)
      }
      .height($r('app.float.filter_chips_height'))
      .alignItems(VerticalAlign.Center)
      .padding({
        left: $r('app.float.sheet_card_inset'),
        right: $r('app.float.sheet_card_inset'),
        top: $r('app.float.filter_chips_top_inset'),
        bottom: $r('app.float.filter_chips_shadow_space')
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .clip(false)
    .width('100%')
    .height($r('app.float.filter_chips_height'))
  }

  @Builder
  Chip(item: JuFilterChipOption) {
    Column() {
      Text(item.label)
        .fontSize($r('app.float.font_size_body'))
        .fontWeight(this.selectedValue === item.value ?
          $r('app.integer.font_weight_semibold') : $r('app.integer.font_weight_medium'))
        .fontColor(this.selectedValue === item.value ?
          this.roles().onPrimary : $r('app.color.foreground'))
    }
    .height($r('app.float.filter_chip_height'))
    .justifyContent(FlexAlign.Center)
    .padding({
      left: $r('app.float.padding_input'),
      right: $r('app.float.padding_input')
    })
    .margin({ right: $r('app.float.gap_button_text') })
    .backgroundColor(this.selectedValue === item.value ? this.roles().primary : Color.Transparent)
    .systemMaterial(this.selectedValue === item.value ? uiMaterial.Material.empty :
      new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.REGULAR }))
    .borderRadius($r('app.float.button_radius'))
    .onClick((): void => { this.onSelect(item.value) })
  }
}
