import {
  AiraCloudBookmarkV4BootstrapViewState
} from '../../../core/sync/AiraCloudBookmarkV4BootstrapViewModelService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_ON_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const HIDDEN_BOOTSTRAP_STATE: AiraCloudBookmarkV4BootstrapViewState = {
  visible: false,
  status: 'hidden',
  primaryAction: 'none',
  recoveryAvailable: false,
  uid: '',
  errorMessage: ''
};

@Component
export struct AiraCloudBookmarkV4BootstrapOverlay {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_ON_ACCENT_KEY) private storedOnAccentColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = '#F2F3F5';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: AiraCloudBookmarkV4BootstrapViewState = HIDDEN_BOOTSTRAP_STATE;
  onStart: () => void = (): void => {};
  onRetry: () => void = (): void => {};
  onRestore: () => void = (): void => {};

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Scroll() {
        Column({ space: 0 }) {
          this.buildStatusMark()

          Text(this.resolveTitle())
            .width('100%')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .textAlign(TextAlign.Start)
            .margin({ top: 24 })

          Text(this.resolveMessage())
            .width('100%')
            .fontSize(16)
            .lineHeight(24)
            .fontColor(this.storedSecondaryTextColor)
            .textAlign(TextAlign.Start)
            .margin({ top: 12 })

          if (this.state.status === 'required') {
            this.buildPreparationDetails()
          }

          if (this.state.status === 'failed' && this.state.errorMessage.length > 0) {
            Text(this.state.errorMessage)
              .width('100%')
              .fontSize(14)
              .lineHeight(21)
              .fontColor('#B42318')
              .textAlign(TextAlign.Start)
              .padding(14)
              .backgroundColor('#FFF1F0')
              .borderRadius(6)
              .margin({ top: 20 })
          }

          if (this.state.status !== 'running') {
            this.buildActions()
          }
        }
        .width('100%')
        .constraintSize({ minHeight: '100%', maxWidth: 560 })
        .justifyContent(FlexAlign.Start)
        .alignItems(HorizontalAlign.Start)
        .padding({ left: 24, right: 24, top: 72, bottom: 36 })
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  private buildStatusMark() {
    if (this.state.status === 'running') {
      LoadingProgress()
        .width(56)
        .height(56)
        .color(this.storedAccentColor)
    } else {
      Column() {
        Text(this.state.status === 'failed' ? '!' : 'A')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.state.status === 'failed' ? '#B42318' : this.storedOnAccentColor)
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .backgroundColor(this.state.status === 'failed' ? '#FEE4E2' : this.storedAccentColor)
      .borderRadius(8)
    }
  }

  @Builder
  private buildPreparationDetails() {
    Column({ space: 12 }) {
      this.buildDetailRow('1', '导出本机书签备份到你选择的位置')
      this.buildDetailRow('2', '清空本机书签')
      this.buildDetailRow('3', '从云端同步一份完整书签')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 24, bottom: 4 })
  }

  @Builder
  private buildDetailRow(index: string, label: string) {
    Row({ space: 12 }) {
      Text(index)
        .width(28)
        .height(28)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedAccentColor)
        .textAlign(TextAlign.Center)
        .backgroundColor(this.storedSurfaceColor)
        .borderRadius(6)

      Text(label)
        .layoutWeight(1)
        .fontSize(15)
        .lineHeight(22)
        .fontColor(this.storedPrimaryTextColor)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildActions() {
    Column({ space: 10 }) {
      Button(this.state.primaryAction === 'retry' ? '重试' : '备份并更新')
        .width('100%')
        .height(50)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedOnAccentColor)
        .backgroundColor(this.storedAccentColor)
        .borderRadius(8)
        .onClick((): void => this.handlePrimaryAction())

    }
    .width('100%')
    .margin({ top: 32 })
  }

  private handlePrimaryAction(): void {
    if (this.state.primaryAction === 'retry') {
      this.onRetry();
      return;
    }
    if (this.state.primaryAction === 'start') {
      this.onStart();
    }
  }

  private resolveTitle(): string {
    if (this.state.status === 'running') {
      return '正在备份并更新书签';
    }
    if (this.state.status === 'failed') {
      return '书签更新未完成';
    }
    return '更新 Aira 云书签';
  }

  private resolveMessage(): string {
    if (this.state.status === 'running') {
      return '请保持 Aira 在前台。完成前不会启动自动书签同步。';
    }
    if (this.state.status === 'failed') {
      return '本机书签备份已经保存。请重试，用云端书签覆盖本机。';
    }
    return '此版本使用全新的 Aira 云书签基线。请先把本机书签导出为本地备份；备份成功后会清空本机书签，再从云端同步一份。';
  }
}
