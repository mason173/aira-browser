import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import { AiraIcon } from '../common/AiraIcon';
import {
  BrowserDesktopContextMenu,
  BrowserDesktopContextMenuItem
} from '../browser/BrowserDesktopContextMenu';

export interface SettingsDesktopWorkspaceHeaderAction {
  label: string;
  action: () => void;
}

const SETTINGS_DESKTOP_WORKSPACE_HEADER_HEIGHT: number = 52;
const SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE: number = 36;

@Component
export struct SettingsDesktopWorkspaceHeader {
  @Prop title: string = '';
  @Prop showTitle: boolean = true;
  @Prop showBackButton: boolean = false;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop iconColor: ResourceColor = '';
  @Prop buttonBackgroundColor: ResourceColor = '';
  @Prop primaryActionIconId: AiraRenderableIconId | undefined = undefined;
  @Prop primaryActionText: string = '';
  @Prop primaryActionLabel: string = '';
  @Prop primaryActionEnabled: boolean = true;
  @Prop menuActions: SettingsDesktopWorkspaceHeaderAction[] = [];
  onBack?: () => void;
  onPrimaryAction?: () => void;

  build() {
    Row({ space: 10 }) {
      if (this.showBackButton) {
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.back',
            iconSize: 17,
            iconColor: this.iconColor
          })
        }
        .width(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
        .height(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(this.buttonBackgroundColor)
        .stateEffect(true)
        .focusable(true)
        .accessibilityText('返回上一级设置')
        .onClick(() => {
          this.onBack?.();
        })
      }

      if (this.showTitle && !this.showBackButton) {
        Text(this.title)
          .layoutWeight(1)
          .constraintSize({ minWidth: 0 })
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.primaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      } else {
        Blank()
          .layoutWeight(1)
      }

      if (this.primaryActionIconId !== undefined) {
        Button() {
          AiraIcon({
            airaIconId: this.primaryActionIconId as AiraRenderableIconId,
            iconSize: 18,
            iconColor: this.iconColor
          })
        }
        .width(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
        .height(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(this.buttonBackgroundColor)
        .stateEffect(true)
        .focusable(true)
        .enabled(this.primaryActionEnabled)
        .opacity(this.primaryActionEnabled ? 1 : 0.48)
        .accessibilityText(this.primaryActionLabel)
        .onClick(() => {
          this.onPrimaryAction?.();
        })
      } else if (this.primaryActionText.length > 0) {
        Button(this.primaryActionText)
          .height(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
          .constraintSize({ minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .type(ButtonType.Normal)
          .buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontSize(14)
          .fontColor(this.iconColor)
          .backgroundColor(this.buttonBackgroundColor)
          .stateEffect(true)
          .focusable(true)
          .enabled(this.primaryActionEnabled)
          .opacity(this.primaryActionEnabled ? 1 : 0.48)
          .accessibilityText(this.primaryActionLabel.length > 0
            ? this.primaryActionLabel
            : this.primaryActionText)
          .onClick(() => {
            this.onPrimaryAction?.();
          })
      }

      if (this.menuActions.length > 0) {
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.more',
            iconSize: 18,
            iconColor: this.iconColor
          })
        }
        .width(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
        .height(SETTINGS_DESKTOP_WORKSPACE_HEADER_BUTTON_SIZE)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor(this.buttonBackgroundColor)
        .stateEffect(true)
        .focusable(true)
        .accessibilityText('更多操作')
        .bindMenu(this.buildActionMenu(), {
          placement: Placement.BottomRight,
          enableArrow: false,
          showInSubWindow: false,
          borderRadius: BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP
        })
      }
    }
    .width('100%')
    .height(SETTINGS_DESKTOP_WORKSPACE_HEADER_HEIGHT)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildActionMenu() {
    BrowserDesktopContextMenu() {
      ForEach(this.menuActions, (action: SettingsDesktopWorkspaceHeaderAction) => {
        BrowserDesktopContextMenuItem({
          label: action.label,
          onAction: () => {
            action.action();
          }
        })
      }, (action: SettingsDesktopWorkspaceHeaderAction) => `settings-workspace-action-${action.label}`)
    }
  }
}
