import { SettingsTextField } from '../settings/SettingsRows';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import { CENTERED_DIALOG_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';

@CustomDialog
export struct CustomHomepageRemoteUrlDialog {
  @Prop accentColor: ResourceColor = '';
  @Prop controlBackgroundColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  controller?: CustomDialogController;
  @Link urlDraft: string;
  @Link errorText: string;
  confirm: () => boolean = (): boolean => true;

  build() {
    Column({ space: 16 }) {
      Text('添加网址主页')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.primaryTextColor)
        .textAlign(TextAlign.Center)

      SettingsTextField({
        text: this.urlDraft,
        placeholder: 'https://example.com',
        helperText: '输入一个网页地址，它会作为主页候选项显示在列表里。',
        errorText: this.errorText,
        controlBackgroundColor: this.controlBackgroundColor,
        primaryTextColor: this.primaryTextColor,
        secondaryTextColor: this.secondaryTextColor,
        onChange: (value: string) => {
          this.urlDraft = value;
          this.errorText = '';
        }
      })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '添加',
          emphasis: 'primary',
          accentColor: this.accentColor,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            if (this.confirm()) {
              this.controller?.close();
            }
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SURFACE_MODIFIER)
  }
}
