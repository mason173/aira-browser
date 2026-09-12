import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';

// A play/pause icon changes while the overlay stays mounted. Icon identifiers must therefore travel as
// reactive @Prop inputs rather than as by-value @Builder arguments, which do not refresh their content.
@Component
export struct BrowserVideoAssistantPlayerIconButton {
  @Prop airaIconId: AiraRenderableIconId = 'videoAssistant.play';
  @Prop iconSize: number = 24;
  @Prop buttonSize: number = 40;
  @Prop iconColor: ResourceColor = '';
  @Prop buttonColor: ResourceColor = '';
  @Prop accessibilityLabel: string = '';
  onPress: () => void = () => {};

  build() {
    Stack({ alignContent: Alignment.Center }) {
      AiraIcon({
        airaIconId: this.airaIconId,
        iconSize: this.iconSize,
        iconColor: this.iconColor
      })
        .hitTestBehavior(HitTestMode.None)

      Button({ type: ButtonType.Circle })
        .width('100%')
        .height('100%')
        .backgroundColor(this.buttonColor)
        .accessibilityText(this.accessibilityLabel)
        .onClick(() => {
          this.onPress();
        })
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .borderRadius(this.buttonSize / 2)
  }
}
