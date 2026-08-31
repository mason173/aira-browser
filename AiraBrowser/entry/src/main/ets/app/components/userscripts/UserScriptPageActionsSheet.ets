import {
  UserScriptPageActionsState,
  UserScriptPageMenuCommandView,
  UserScriptPageScriptStatusView
} from '../../../features/userscripts/UserScriptRuntimeModels';
import {
  BrowserUserScriptApplicationAction
} from '../../../core/userscripts/BrowserUserScriptApplicationCoordinator';
import {
  BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
  BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
  BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
  BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING,
  BrowserBottomSheetSurface,
  BrowserFeatureSheetHeader,
  BrowserImmersiveSheetLayout,
  BrowserSheetActionButton,
  BrowserSheetIconButton
} from '../browser/BrowserModalBottomSheet';
import { AppEmptyState } from '../common/AppEmptyState';
import { SiteIconView } from '../common/SiteIconView';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_ON_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';

const USER_SCRIPT_PAGE_ACTIONS_FOOTER_SPACE: number = 68;

@Component
export struct UserScriptPageActionsSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_ON_PRIMARY_KEY) private storedOnPrimaryColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private selectedScriptId: string = '';
  @Prop state: UserScriptPageActionsState = {
    url: '',
    message: '打开网页后会显示当前页脚本菜单。',
    hasPage: false,
    hasMatchingScripts: false,
    hasMenuCommands: false,
    matchingScriptCount: 0,
    commands: [],
    scripts: []
  };
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  @Prop showHeader: boolean = false;
  onAction: (action: BrowserUserScriptApplicationAction) => void =
    (_action: BrowserUserScriptApplicationAction): void => {};

  build() {
    BrowserBottomSheetSurface({
      fullHeight: true,
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet',
      horizontalPadding: this.layoutMode === 'phone' ? 0 : 16,
      topPadding: this.layoutMode === 'phone' ? 0 : 26,
      bottomPadding: this.layoutMode === 'phone' ? 0 : 24
    }) {
      if (this.layoutMode === 'phone') {
        this.buildImmersivePhoneLayout()
      } else {
        this.buildLargeScreenLayout()
      }
    }
  }

  @Builder
  private buildImmersivePhoneLayout() {
    BrowserImmersiveSheetLayout({
      footerVisible: !this.isScriptDetailVisible(),
      scrollContent: () => {
        this.buildPhoneScrollContent()
      },
      header: () => {
        this.buildPhoneHeader()
      },
      footer: () => {
        if (!this.isScriptDetailVisible()) {
          this.buildFooter()
        }
      }
    })
  }

  @Builder
  private buildPhoneScrollContent() {
    Scroll() {
      Column({ space: 16 }) {
        if (this.state.scripts.length > 0) {
          if (this.isScriptDetailVisible()) {
            this.buildSelectedScriptCommands()
          } else {
            this.buildScriptList()
          }
        } else {
          AppEmptyState({
            airaIconId: 'settings.userScripts',
            title: this.resolveEmptyTitle(),
            message: this.state.message,
            fillHeight: true
          })
        }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .padding({
        left: 16,
        right: 16,
        top: BROWSER_IMMERSIVE_SHEET_HEADER_CONTENT_TOP_INSET,
        bottom: this.isScriptDetailVisible()
          ? BROWSER_SHEET_IMMERSIVE_BOTTOM_PADDING
          : USER_SCRIPT_PAGE_ACTIONS_FOOTER_SPACE
      })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }

  @Builder
  private buildLargeScreenLayout() {
    Column({ space: 18 }) {
      if (this.showHeader) {
        this.buildLargeScreenHeader()
      }

      if (this.state.scripts.length > 0) {
        Scroll() {
          Column({ space: 16 }) {
            if (this.isScriptDetailVisible()) {
              this.buildSelectedScriptCommands()
            } else {
              this.buildScriptList()
            }
          }
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
      } else {
        AppEmptyState({
          airaIconId: 'settings.userScripts',
          title: this.resolveEmptyTitle(),
          message: this.state.message,
          fillHeight: true
        })
        .layoutWeight(1)
      }

      if (!this.isScriptDetailVisible()) {
        this.buildFooter()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildSectionTitle(title: string) {
    Text(title)
      .width('100%')
      .fontSize(13)
      .fontWeight(FontWeight.Medium)
      .fontColor(this.storedSecondaryTextColor)
      .padding({ left: 2, right: 2 })
  }

  @Builder
  private buildPhoneHeader() {
    BrowserFeatureSheetHeader({
      title: this.resolveHeaderTitle(),
      titleColor: this.storedPrimaryTextColor,
      leadingAccessibilityLabel: this.isScriptDetailVisible() ? '返回当前页脚本' : '关闭当前页脚本',
      trailingVisible: !this.isScriptDetailVisible(),
      trailing: () => {
        this.buildPhoneHeaderTrailingAction()
      },
      onLeadingAction: () => {
        if (this.isScriptDetailVisible()) {
          this.selectedScriptId = '';
        } else {
          this.onAction({ type: 'dismiss_page_actions' });
        }
      }
    })
  }

  @Builder
  private buildPhoneHeaderTrailingAction() {
    BrowserSheetIconButton({
      icon: $r('sys.symbol.arrow_clockwise'),
      iconSize: BROWSER_FEATURE_SHEET_HEADER_ICON_SIZE,
      buttonSize: BROWSER_FEATURE_SHEET_HEADER_BUTTON_SIZE,
      accessibilityLabel: '刷新',
      onAction: () => {
        this.onAction({ type: 'refresh_page_actions' });
      }
    })
  }

  @Builder
  private buildLargeScreenHeader() {
    Row({ space: 12 }) {
      if (this.isScriptDetailVisible()) {
        BrowserSheetIconButton({
          icon: $r('sys.symbol.chevron_left'),
          accessibilityLabel: '返回当前页脚本',
          onAction: () => {
            this.selectedScriptId = '';
          }
        })
      }

      Column({ space: 3 }) {
        Text(this.resolveHeaderTitle())
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(this.resolveSubtitle())
          .fontSize(12)
          .fontColor(this.storedSecondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (!this.isScriptDetailVisible()) {
        BrowserSheetIconButton({
          icon: $r('sys.symbol.arrow_clockwise'),
          accessibilityLabel: '刷新',
          onAction: () => {
            this.onAction({ type: 'refresh_page_actions' });
          }
        })
      }

      BrowserSheetIconButton({
        icon: $r('sys.symbol.xmark'),
        iconSize: 17,
        accessibilityLabel: '关闭',
        onAction: () => {
          this.onAction({ type: 'dismiss_page_actions' });
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildScriptList() {
    Column({ space: 0 }) {
      ForEach(this.state.scripts, (script: UserScriptPageScriptStatusView, index: number) => {
        this.buildScriptItem(script, index, this.state.scripts.length)
      }, (script: UserScriptPageScriptStatusView) => script.scriptId)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4, bottom: 4 })
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .borderRadius(22)
    .clip(true)
  }

  @Builder
  private buildSelectedScriptCommands() {
    if (this.resolveSelectedCommands().length > 0) {
      Column({ space: 8 }) {
        this.buildSectionTitle('脚本功能')
        Column({ space: 0 }) {
          ForEach(this.resolveSelectedCommands(), (command: UserScriptPageMenuCommandView, index: number) => {
            this.buildCommandItem(command, index, this.resolveSelectedCommands().length)
          }, (command: UserScriptPageMenuCommandView) => command.id)
        }
        .width('100%')
        .padding({ left: 4, right: 4, top: 4, bottom: 4 })
        .backgroundColor(this.storedSurfaceBackgroundColor)
        .borderRadius(22)
        .clip(true)
      }
      .width('100%')
    } else {
      AppEmptyState({
        airaIconId: 'settings.userScripts',
        title: '暂无可用功能',
        message: '这个脚本当前没有可执行的菜单功能。',
        fillHeight: true
      })
    }
  }

  @Builder
  private buildScriptItem(script: UserScriptPageScriptStatusView, index: number, total: number) {
    Column({ space: 0 }) {
      Button() {
        Row({ space: 12 }) {
          SiteIconView({
            iconUri: script.iconUrl,
            fallbackAiraIconId: 'userscripts.defaultIcon',
            iconSize: 40,
            cornerRadius: 10,
            fit: ImageFit.Contain,
            containerBackgroundColor: this.storedSurfaceBackgroundColor,
            frameBorderColor: this.storedDividerColor,
            textColor: this.storedPrimaryTextColor
          })

          Text(script.scriptName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.storedSecondaryTextColor])
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      .type(ButtonType.Normal)
      .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
      .borderRadius(this.resolveRowBorderRadius(index, total))
      .padding({ left: 12, right: 16, top: 10, bottom: 10 })
      .onClick(() => {
        this.selectedScriptId = script.scriptId;
      })

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
  private buildCommandItem(command: UserScriptPageMenuCommandView, index: number, total: number) {
    Button() {
      Row({ space: 12 }) {
        Text(command.commandName)
          .width('100%')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.storedPrimaryTextColor)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.storedSecondaryTextColor])
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .type(ButtonType.Normal)
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(this.resolveRowBorderRadius(index, total))
    .padding({ left: 16, right: 16, top: 14, bottom: 14 })
    .onClick(() => {
      this.onAction({
        type: 'run_page_command',
        scriptId: command.scriptId,
        commandId: command.commandId
      });
    })

    if (index < total - 1) {
      Divider()
        .width('100%')
        .height(1)
        .color(this.storedDividerColor)
        .margin({ left: 16, right: 16 })
    }
  }

  @Builder
  private buildFooter() {
    Row() {
      BrowserSheetActionButton({
        label: '管理脚本',
        emphasis: 'primary',
        accentColor: this.storedAccentColor,
        textColor: this.storedOnPrimaryColor,
        buttonHeight: 48,
        onAction: () => {
          this.onAction({ type: 'open_manager' });
        }
      })
    }
    .width('100%')
  }

  private isScriptDetailVisible(): boolean {
    return this.resolveSelectedScript() !== undefined;
  }

  private resolveSelectedScript(): UserScriptPageScriptStatusView | undefined {
    return this.state.scripts.find((script: UserScriptPageScriptStatusView) => {
      return script.scriptId === this.selectedScriptId;
    });
  }

  private resolveSelectedCommands(): UserScriptPageMenuCommandView[] {
    return this.state.commands.filter((command: UserScriptPageMenuCommandView) => {
      return command.scriptId === this.selectedScriptId;
    });
  }

  private resolveHeaderTitle(): string {
    return this.resolveSelectedScript()?.scriptName ?? '当前页脚本';
  }

  private resolveRowBorderRadius(index: number, total: number): BorderRadiuses {
    if (total <= 1) {
      return { topLeft: 20, topRight: 20, bottomLeft: 20, bottomRight: 20 };
    }
    if (index === 0) {
      return { topLeft: 20, topRight: 20, bottomLeft: 0, bottomRight: 0 };
    }
    if (index === total - 1) {
      return { topLeft: 0, topRight: 0, bottomLeft: 20, bottomRight: 20 };
    }
    return { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 };
  }

  private resolveSubtitle(): string {
    if (this.state.url.length === 0) {
      return '当前页';
    }
    return this.state.url;
  }

  private resolveEmptyTitle(): string {
    if (!this.state.hasPage) {
      return '当前没有网页';
    }
    if (!this.state.hasMatchingScripts) {
      return '没有匹配脚本';
    }
    return '没有脚本菜单';
  }

}
