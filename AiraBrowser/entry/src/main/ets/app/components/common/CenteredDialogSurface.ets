import { uiMaterial } from '@kit.ArkUI';

export const CENTERED_DIALOG_HORIZONTAL_MARGIN_VP: number = 12;
export const CENTERED_DIALOG_MAX_WIDTH_VP: number = 420;
export const CENTERED_DIALOG_CORNER_RADIUS_VP: number = 28;
export const CENTERED_DIALOG_CONTENT_GAP_VP: number = 16;
export const CENTERED_DIALOG_HORIZONTAL_PADDING_VP: number = 20;
export const CENTERED_DIALOG_TOP_PADDING_VP: number = 22;
export const CENTERED_DIALOG_BOTTOM_PADDING_VP: number = 18;
export const CENTERED_DIALOG_TITLE_FONT_SIZE_FP: number = 20;
export const CENTERED_DIALOG_ACTION_GAP_VP: number = 10;
export const CENTERED_DIALOG_ACTION_HEIGHT_VP: number = 44;
export const CENTERED_DIALOG_ACTION_FONT_SIZE_FP: number = 15;
const CENTERED_DIALOG_WIDTH: string =
  `calc(100% - ${CENTERED_DIALOG_HORIZONTAL_MARGIN_VP * 2}vp)`;
// AlertDialog.width accepts Dimension (not calc expressions); 90% preserves the centered 12vp contract on phones.
const CENTERED_DIALOG_ALERT_WIDTH: Dimension = '90%';
const CENTERED_DIALOG_TALL_HEIGHT: string = 'calc(100% - 48vp)';
const CENTERED_DIALOG_TALL_MAX_HEIGHT_VP: number = 720;

export function createCenteredDialogMaterial(): uiMaterial.ImmersiveMaterial {
  return new uiMaterial.ImmersiveMaterial({
    style: uiMaterial.ImmersiveStyle.THICK,
    applyShadow: true,
    interactive: false
  });
}

export type CenteredAlertDialogParams =
  AlertDialogParamWithConfirm | AlertDialogParamWithButtons | AlertDialogParamWithOptions;

/** Applies the shared API 26 material contract while retaining AlertDialog's native behavior. */
export function showCenteredAlertDialog(params: CenteredAlertDialogParams): void {
  params.width = CENTERED_DIALOG_ALERT_WIDTH;
  params.cornerRadius = CENTERED_DIALOG_CORNER_RADIUS_VP;
  params.systemMaterial = createCenteredDialogMaterial();
  AlertDialog.show(params);
}

class CenteredDialogSurfaceModifier implements AttributeModifier<CommonAttribute> {
  private readonly fillHeight: boolean;
  private readonly boundHeight: boolean;
  private readonly contentPadding: boolean;
  private readonly paddingTop: number;
  private readonly paddingBottom: number;

  constructor(
    fillHeight: boolean,
    boundHeight: boolean = false,
    contentPadding: boolean = false,
    paddingTop: number = CENTERED_DIALOG_TOP_PADDING_VP,
    paddingBottom: number = CENTERED_DIALOG_BOTTOM_PADDING_VP
  ) {
    this.fillHeight = fillHeight;
    this.boundHeight = boundHeight;
    this.contentPadding = contentPadding;
    this.paddingTop = paddingTop;
    this.paddingBottom = paddingBottom;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    instance.width(CENTERED_DIALOG_WIDTH)
    if (this.fillHeight) {
      instance.height(CENTERED_DIALOG_TALL_HEIGHT)
      instance.constraintSize({
        maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP,
        maxHeight: CENTERED_DIALOG_TALL_MAX_HEIGHT_VP
      })
    } else if (this.boundHeight) {
      instance.constraintSize({
        maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP,
        maxHeight: CENTERED_DIALOG_TALL_HEIGHT
      })
    } else {
      instance.constraintSize({ maxWidth: CENTERED_DIALOG_MAX_WIDTH_VP })
    }
    instance.systemMaterial(createCenteredDialogMaterial())
    instance.borderRadius(CENTERED_DIALOG_CORNER_RADIUS_VP)
    instance.clip(true)
    if (this.contentPadding) {
      instance.padding({
        left: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        right: CENTERED_DIALOG_HORIZONTAL_PADDING_VP,
        top: this.paddingTop,
        bottom: this.paddingBottom
      })
    }
  }
}

export const CENTERED_DIALOG_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true);
export const CENTERED_DIALOG_COMPACT_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, false, true, 16, 12);
export const CENTERED_DIALOG_TALL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true);
export const CENTERED_DIALOG_TALL_PADDED_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(true, false, true);
export const CENTERED_DIALOG_SCROLL_SURFACE_MODIFIER: AttributeModifier<CommonAttribute> =
  new CenteredDialogSurfaceModifier(false, true);

@Component
export struct CenteredDialogSurface {
  @Prop fillHeight: boolean = false;
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    if (this.fillHeight) {
      this.buildTallSurface()
    } else {
      this.buildCompactSurface()
    }
  }

  @Builder
  private buildCompactSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }

  @Builder
  private buildTallSurface() {
    Stack({ alignContent: Alignment.TopStart }) {
      this.content()
    }
    .attributeModifier(CENTERED_DIALOG_TALL_SURFACE_MODIFIER)
  }

  @Builder
  private emptyContent() {
  }
}
