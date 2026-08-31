import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import router from '@ohos.router';
import {
  UserScriptDetailRowView,
  UserScriptDetailState
} from '../../../core/userscripts/UserScriptDetailViewModel';
import {
  ManagementHdsScaffold
} from '../common/ManagementHdsScaffold';
import { SettingsDesktopWorkspaceHeader } from '../settings/SettingsDesktopWorkspaceHeader';
import { SETTINGS_DESKTOP_SCROLLBAR_GUTTER } from '../settings/SettingsLayout';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

@Component
export struct UserScriptDetailScreen {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: UserScriptDetailState = {
    title: '脚本详情',
    subtitle: '',
    enabled: false,
    found: false,
    statusTitle: '',
    statusDescription: '',
    metadataRows: [],
    runtimeRows: [],
    storageRows: [],
    sourcePreview: '',
    actions: {
      editEnabled: false,
      deleteEnabled: false
    }
  };
  onToggleScript: (enabled: boolean) => void = (_enabled: boolean) => {};
  onOpenExtensionsPage: () => void = () => {};
  onDeleteScript: () => void = () => {};
  onBack: () => void = () => {
    router.back();
  };
  @Prop showBackButton: boolean = true;
  @Prop showTitleBar: boolean = true;
  @Prop useTopSafeInset: boolean = true;
  @Prop desktopPresentation: boolean = false;

  build() {
    Column() {
      if (this.desktopPresentation) {
        SettingsDesktopWorkspaceHeader({
          title: '脚本详情',
          showBackButton: true,
          primaryTextColor: this.storedPrimaryTextColor,
          iconColor: this.storedSecondaryTextColor,
          buttonBackgroundColor: this.storedPressedBackgroundColor,
          onBack: () => {
            this.onBack();
          }
        })
      }

      ManagementHdsScaffold({
        title: '脚本详情',
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        showBackButton: this.desktopPresentation ? false : this.showBackButton,
        showTitleBar: this.desktopPresentation ? false : this.showTitleBar,
        useTopSafeInset: this.useTopSafeInset,
        fillRemainingHeight: this.desktopPresentation,
        menuActions: [],
        onBack: () => {
          this.onBack();
        }
      }) {
        Scroll() {
          Column({ space: 18 }) {
            this.buildStatusCard()
            this.buildRowsSection('元数据', this.state.metadataRows)
            this.buildRowsSection('运行诊断', this.state.runtimeRows)
            this.buildRowsSection('脚本存储', this.state.storageRows)
            this.buildSourceSection()
            this.buildBottomDeleteAction()
          }
          .width('100%')
          .constraintSize({ minHeight: '100%' })
          .padding({
            left: this.desktopPresentation ? 0 : 16,
            right: this.desktopPresentation ? SETTINGS_DESKTOP_SCROLLBAR_GUTTER : 16,
            top: 16,
            bottom: 32
          })
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .clip(this.desktopPresentation)
      }
    }
    .width('100%')
    .height('100%')
    .clip(true)
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildStatusCard() {
    Column({ space: 14 }) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.state.title)
            .width('100%')
            .fontSize(this.desktopPresentation ? 15 : 18)
            .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.state.subtitle)
            .width('100%')
            .fontSize(13)
            .lineHeight(18)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.state.enabled })
          .enabled(this.state.found)
          .opacity(this.state.found ? 1 : 0.46)
          .selectedColor(this.storedAccentColor)
          .onChange((enabled: boolean) => {
            this.onToggleScript(enabled);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column({ space: 4 }) {
        Text(this.state.statusTitle)
          .width('100%')
          .fontSize(15)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.state.enabled ? this.storedAccentColor : this.storedSecondaryTextColor)

        Text(this.state.statusDescription)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.storedSecondaryTextColor)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)

      Button('前往扩展页面')
        .width('100%')
        .height(40)
        .type(ButtonType.Normal)
        .fontSize(15)
        .fontColor(this.storedAccentColor)
        .backgroundColor(this.storedPressedBackgroundColor)
        .borderRadius(this.desktopPresentation ? 8 : 20)
        .onClick(() => {
          this.onOpenExtensionsPage();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 16 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(this.resolveGroupRadius())
  }

  @Builder
  private buildRowsSection(title: string, rows: UserScriptDetailRowView[]) {
    if (rows.length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle(title)
        Column({ space: 0 }) {
          ForEach(rows, (row: UserScriptDetailRowView, index: number) => {
            this.buildDetailRow(row, index, rows.length)
          }, (row: UserScriptDetailRowView) => `${row.label}-${row.value}`)
        }
        .width('100%')
        .backgroundColor(this.storedSurfaceBackgroundColor)
        .borderRadius(this.resolveGroupRadius())
      }
      .width('100%')
    }
  }

  @Builder
  private buildSourceSection() {
    if (this.state.sourcePreview.length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle('源码预览')
        Text(this.state.sourcePreview)
          .width('100%')
          .fontSize(12)
          .fontFamily('monospace')
          .lineHeight(17)
          .fontColor(this.storedSecondaryTextColor)
          .padding({ left: 14, right: 14, top: 14, bottom: 14 })
          .backgroundColor(this.storedSurfaceBackgroundColor)
          .borderRadius(this.resolveGroupRadius())
      }
      .width('100%')
    }
  }

  @Builder
  private buildBottomDeleteAction() {
    Button('删除脚本')
      .width('100%')
      .height(44)
      .enabled(this.state.actions.deleteEnabled)
      .opacity(this.state.actions.deleteEnabled ? 1 : 0.46)
      .type(ButtonType.Normal)
      .fontSize(15)
      .fontColor($r('app.color.permission_blocked'))
      .backgroundColor(this.storedSurfaceBackgroundColor)
      .borderRadius(this.resolveGroupRadius())
      .onClick(() => {
        this.onDeleteScript();
      })
  }

  @Builder
  private buildDetailRow(row: UserScriptDetailRowView, index: number, total: number) {
    Column({ space: 0 }) {
      Row({ space: 12 }) {
        Text(row.label)
          .width(76)
          .fontSize(14)
          .fontColor(this.storedSecondaryTextColor)

        Text(row.value)
          .layoutWeight(1)
          .fontSize(14)
          .lineHeight(19)
          .fontColor(this.storedPrimaryTextColor)
          .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 13, bottom: 13 })
      .alignItems(VerticalAlign.Top)

      if (index < total - 1) {
        Divider()
          .width('100%')
          .height(1)
          .color(this.storedDividerColor)
          .margin({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  private buildSectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontColor(this.storedSecondaryTextColor)
      .padding({ left: 4 })
  }

  private resolveGroupRadius(): number {
    return this.desktopPresentation ? 8 : 22;
  }
}
