import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  DocumentViewerFileInfo,
  DocumentViewerInfoRow
} from '../../../services/viewer/DocumentViewerService';
import {
  SiteReportReasonId,
  SiteReportReasonOption
} from '../../../core/browser/SiteReportDialogViewModel';
import {
  BrowserHttpAuthDialogPresentation,
  BrowserWebPromptDialogPresentation
} from '../../../core/browser/BrowserWebCapabilityPromptApplicationCoordinator';
import {
  WebAppInstallDialogAction,
  WebAppInstallDialogSnapshot
} from '../../../core/webapps/WebAppInstallCoordinator';
import { HomeShortcutEditDraft } from '../../../features/newtab/HomeShortcutTypes';
import { SiteIconView } from '../common/SiteIconView';
import { CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER } from '../common/CenteredDialogSurface';
import { BrowserSheetActionButton } from './BrowserModalBottomSheet';

@CustomDialog
export struct DocumentViewerFileInfoDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link fileInfo: DocumentViewerFileInfo;

  build() {
    Column({ space: 16 }) {
      Text('文件信息')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Column({ space: 12 }) {
        ForEach(this.fileInfo.rows, (row: DocumentViewerInfoRow) => {
          this.buildInfoRow(row)
        }, (row: DocumentViewerInfoRow) => row.label)
      }
      .width('100%')

      BrowserSheetActionButton({
        label: '知道了',
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        fillAvailableWidth: false,
        buttonWidth: '100%',
        buttonHeight: 44,
        fontSize: 15,
        onAction: () => {
          this.controller?.close();
        }
      })
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildInfoRow(row: DocumentViewerInfoRow) {
    Row({ space: 12 }) {
      Text(row.label)
        .width(72)
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .textAlign(TextAlign.Start)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(row.value)
        .layoutWeight(1)
        .fontSize(13)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.End)
        .maxLines(row.multiline ? 2 : 1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }
}

@CustomDialog
export struct HomeShortcutEditDialog {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link draft: HomeShortcutEditDraft;
  confirm: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      this.buildIcon()

      Text('编辑快捷方式')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.draft.title, placeholder: '名称' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          const nextDraft: HomeShortcutEditDraft = {
            shortcutId: this.draft.shortcutId,
            title: value,
            url: this.draft.url,
            iconPath: this.draft.iconPath
          };
          this.draft = nextDraft;
        })

      TextInput({ text: this.draft.url, placeholder: '网址' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          const nextDraft: HomeShortcutEditDraft = {
            shortcutId: this.draft.shortcutId,
            title: this.draft.title,
            url: value,
            iconPath: this.draft.iconPath
          };
          this.draft = nextDraft;
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
          label: '保存',
          emphasis: 'primary',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildIcon() {
    Row() {
      if (this.draft.iconPath.length > 0) {
        Image(this.draft.iconPath)
          .width(34)
          .height(34)
          .objectFit(ImageFit.Contain)
      } else {
        SymbolGlyph($r('sys.symbol.bookmark_fill'))
          .fontSize(32)
          .fontColor([this.storedSecondaryTextColor])
      }
    }
    .width(56)
    .height(56)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedControlBackgroundColor)
    .borderRadius(18)
  }
}

@CustomDialog
export struct SiteReportDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link selectedReasonId: SiteReportReasonId;
  @Link remark: string;
  reasons: SiteReportReasonOption[] = [];
  confirm: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Row() {
        SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
          .fontSize(30)
          .fontColor([this.storedAccentColor])
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.storedControlBackgroundColor)
      .borderRadius(18)

      Text('举报网站')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      Column({ space: 0 }) {
        ForEach(this.reasons, (reason: SiteReportReasonOption, index: number) => {
          this.buildReasonRow(reason, index)
        }, (reason: SiteReportReasonOption) => reason.id)
      }
      .width('100%')
      .backgroundColor(this.storedFloatingSurfaceColor)
      .borderRadius(16)
      .clip(true)

      TextArea({ text: this.remark, placeholder: '备注（选填）' })
        .width('100%')
        .height(88)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0, top: 10, bottom: 10 })
        .onChange((value: string) => {
          this.remark = value;
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
          label: '确定',
          emphasis: 'primary',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm();
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }

  @Builder
  private buildReasonRow(reason: SiteReportReasonOption, index: number) {
    Row({ space: 10 }) {
      Text(reason.label)
        .layoutWeight(1)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Radio({
        value: reason.id,
        group: 'site-report-reason'
      })
        .checked(this.selectedReasonId === reason.id)
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({
          checkedBackgroundColor: this.storedAccentColor
        })
    }
    .width('100%')
    .height(48)
    .padding({ left: 14, right: 12 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(this.storedFloatingSurfaceColor)
    .border({
      width: { bottom: index < this.reasons.length - 1 ? 0.5 : 0 },
      color: this.storedControlBackgroundColor
    })
    .onClick(() => {
      this.selectedReasonId = reason.id;
    })
  }
}

@CustomDialog
export struct DesktopShortcutNameDialog {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#D5DBE4';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link snapshot: WebAppInstallDialogSnapshot;
  onAction: (action: WebAppInstallDialogAction) => void = (_action: WebAppInstallDialogAction): void => {};

  build() {
    Column({ space: 16 }) {
      Column({ space: 4 }) {
        Button() {
          Stack({ alignContent: Alignment.Center }) {
            SiteIconView({
              iconUri: this.snapshot.iconUri,
              fallbackLabel: this.snapshot.title,
              iconSize: 64,
              cornerRadius: 18,
              frameBorderWidth: 0.5,
              imageContentScale: 1,
              fallbackFontSize: 24,
              containerBackgroundColor: this.storedControlBackgroundColor,
              frameBorderColor: this.storedOutlineColor,
              textColor: this.storedSecondaryTextColor,
              fit: this.snapshot.iconCustomized ? ImageFit.Cover : ImageFit.Contain,
              syncLoad: true,
              hitTestMode: HitTestMode.None
            })

            if (this.snapshot.iconProcessing) {
              LoadingProgress()
                .width(24)
                .height(24)
                .color(this.storedAccentColor)
            }
          }
          .width(64)
          .height(64)
        }
        .width(64)
        .height(64)
        .padding(0)
        .type(ButtonType.Normal)
        .backgroundColor(this.storedFloatingSurfaceColor)
        .borderRadius(18)
        .enabled(!this.snapshot.iconProcessing)
        .accessibilityText('更换应用图标')
        .onClick(() => {
          this.onAction({ type: 'select_icon' });
        })

        Text(this.snapshot.iconProcessing
          ? '正在处理图标...'
          : (this.snapshot.iconCustomized ? '点击可重新选择' : '点击图标可从相册更换'))
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
          .maxLines(1)

        if (this.snapshot.iconCustomized && !this.snapshot.iconProcessing) {
          BrowserSheetActionButton({
            label: '恢复网站图标',
            fillAvailableWidth: false,
            buttonWidth: 136,
            buttonHeight: 44,
            fontSize: 15,
            onAction: () => {
              this.onAction({ type: 'restore_default_icon' });
            }
          })
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text('作为应用安装')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      TextInput({ text: this.snapshot.title, placeholder: '网页名称' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.onAction({ type: 'update_title', title: value });
        })

      Text(this.snapshot.url)
        .width('100%')
        .fontSize(13)
        .fontColor(this.storedSecondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor(this.storedControlBackgroundColor)
        .borderRadius(14)

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
          label: '安装',
          emphasis: 'primary',
          actionEnabled: !this.snapshot.iconProcessing,
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.onAction({ type: 'confirm' });
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}

@CustomDialog
export struct BrowserShellWebPromptDialog {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link presentation: BrowserWebPromptDialogPresentation;
  confirm: (value: string) => void = (_value: string) => {};
  cancel: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text(this.presentation.title.length > 0 ? this.presentation.title : '网页提示')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      if (this.presentation.message.length > 0) {
        Text(this.presentation.message)
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
      }

      TextInput({ text: this.presentation.inputValue, placeholder: this.presentation.defaultValue })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.presentation = {
            title: this.presentation.title,
            message: this.presentation.message,
            defaultValue: this.presentation.defaultValue,
            inputValue: value
          };
        })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.cancel();
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '确定',
          emphasis: 'primary',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm(this.presentation.inputValue);
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}

@CustomDialog
export struct BrowserShellHttpAuthDialog {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  controller?: CustomDialogController;
  @Link presentation: BrowserHttpAuthDialogPresentation;
  confirm: (username: string, password: string) => void = (_username: string, _password: string) => {};
  cancel: () => void = () => {};

  build() {
    Column({ space: 16 }) {
      Text(this.presentation.host.length > 0 ? this.presentation.host : '网页身份验证')
        .width('100%')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.storedPrimaryTextColor)
        .textAlign(TextAlign.Center)

      if (this.presentation.realm.length > 0) {
        Text(this.presentation.realm)
          .width('100%')
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.storedSecondaryTextColor)
          .textAlign(TextAlign.Center)
      }

      TextInput({ text: this.presentation.username, placeholder: '用户名' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .enabled(!this.presentation.usernameLocked)
        .onChange((value: string) => {
          this.presentation = {
            host: this.presentation.host,
            realm: this.presentation.realm,
            username: value,
            password: this.presentation.password,
            usernameLocked: this.presentation.usernameLocked
          };
        })

      TextInput({ text: this.presentation.password, placeholder: '密码' })
        .width('100%')
        .height(44)
        .fontSize(15)
        .fontColor(this.storedPrimaryTextColor)
        .placeholderColor(this.storedSecondaryTextColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .border({ width: { bottom: 1 }, color: this.storedDividerColor })
        .borderRadius(0)
        .padding({ left: 0, right: 0 })
        .type(InputType.Password)
        .onChange((value: string) => {
          this.presentation = {
            host: this.presentation.host,
            realm: this.presentation.realm,
            username: this.presentation.username,
            password: value,
            usernameLocked: this.presentation.usernameLocked
          };
        })

      Row({ space: 10 }) {
        BrowserSheetActionButton({
          label: '取消',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.cancel();
            this.controller?.close();
          }
        })

        BrowserSheetActionButton({
          label: '登录',
          emphasis: 'primary',
          buttonHeight: 44,
          fontSize: 15,
          onAction: () => {
            this.confirm(this.presentation.username, this.presentation.password);
            this.controller?.close();
          }
        })
      }
      .width('100%')
    }
    .attributeModifier(CENTERED_DIALOG_SYSTEM_SURFACE_MODIFIER)
  }
}
