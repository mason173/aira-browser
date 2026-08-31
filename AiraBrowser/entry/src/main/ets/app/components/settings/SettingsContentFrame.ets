import {
  SettingsContentKind,
  SettingsContentLayoutPolicy,
  SettingsContentLayoutState
} from '../../../core/settings/SettingsContentLayoutPolicy';

@Component
export struct SettingsContentFrame {
  private layoutPolicy: SettingsContentLayoutPolicy = new SettingsContentLayoutPolicy();
  @Prop kind: SettingsContentKind = 'standard';
  @State private containerWidth: number = 390;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Row() {
      Column() {
        this.content()
      }
      .width('100%')
      .height('100%')
      .constraintSize({ maxWidth: this.resolveContentMaxWidth() })
    }
    .width('100%')
    .height('100%')
    .padding({
      left: this.resolveLayoutState().horizontalInset,
      right: this.resolveLayoutState().horizontalInset
    })
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Top)
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      const nextWidth = Math.max(1, Math.round(this.parseAreaDimension(newArea.width)));
      if (nextWidth !== this.containerWidth) {
        this.containerWidth = nextWidth;
      }
    })
  }

  private resolveLayoutState(): SettingsContentLayoutState {
    return this.layoutPolicy.resolve({
      containerWidth: this.containerWidth,
      kind: this.kind
    });
  }

  private resolveContentMaxWidth(): Length {
    const maxWidth = this.resolveLayoutState().maxWidth;
    return maxWidth > 0 ? maxWidth : '100%';
  }

  private parseAreaDimension(value: Length): number {
    const parsed = Number.parseFloat(`${value}`);
    return Number.isFinite(parsed) ? parsed : 0;
  }

  @Builder
  private emptyContent() {
  }
}
