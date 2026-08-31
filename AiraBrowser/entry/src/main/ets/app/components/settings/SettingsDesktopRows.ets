import {
  SettingsDetailActionButtonEmphasis,
  SettingsDetailOption
} from '../../../core/settings/SettingsDetailViewModel';
import {
  BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP,
  BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP,
  BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
  BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP,
  BROWSER_DESKTOP_MENU_TEXT_SIZE_FP,
  BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP
} from '../../../core/browser/BrowserDesktopMenuPresentationTokens';
import { AiraIcon } from '../common/AiraIcon';
import { BrowserDesktopContextMenu } from '../browser/BrowserDesktopContextMenu';

const DESKTOP_SETTINGS_ROW_HEIGHT: number = 44;
const DESKTOP_SETTINGS_ROW_RADIUS: number = 8;
const DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING: number = 12;
const DESKTOP_SETTINGS_ROW_CONTENT_SPACE: number = 10;
const DESKTOP_SETTINGS_FOCUS_WIDTH: number = 2;
const DESKTOP_SETTINGS_GROUP_RADIUS: number = 8;

@Component
export struct SettingsDesktopGroup {
  @Prop surfaceColor: ResourceColor = '';
  @BuilderParam content: () => void = this.emptyContent;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(2)
    .backgroundColor(this.surfaceColor)
    .borderRadius(DESKTOP_SETTINGS_GROUP_RADIUS)
    .clip(true)
  }

  @Builder
  private emptyContent() {
  }
}

@Component
export struct SettingsDesktopDivider {
  @Prop dividerColor: ResourceColor = '';

  build() {
    Divider()
      .width('100%')
      .height(1)
      .color(this.dividerColor)
      .margin({ left: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING, right: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING })
  }
}

@Component
export struct SettingsDesktopNavigationRow {
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop valueSwatchColor: ResourceColor = '';
  @Prop isEnabled: boolean = true;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop hoverBackgroundColor: ResourceColor = '';
  @Prop focusColor: ResourceColor = '';
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private pressed: boolean = false;
  onAction?: () => void;

  build() {
    Button() {
      Row({ space: DESKTOP_SETTINGS_ROW_CONTENT_SPACE }) {
        Text(this.title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.isEnabled ? this.primaryTextColor : this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        if (this.hasValueSwatch()) {
          Circle()
            .width(16)
            .height(16)
            .fill(this.valueSwatchColor)
        }

        if (`${this.value}`.length > 0) {
          Text(this.value)
            .fontSize(13)
            .fontColor(this.secondaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .textAlign(TextAlign.End)
            .constraintSize({ maxWidth: 260 })
        }

        AiraIcon({
          airaIconId: 'browser.toolbar.forward',
          iconSize: 14,
          iconColor: this.secondaryTextColor
        })
      }
      .width('100%')
      .height('100%')
      .padding({ left: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING, right: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(DESKTOP_SETTINGS_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.resolveBackgroundColor())
    .border({ width: this.focused ? DESKTOP_SETTINGS_FOCUS_WIDTH : 0, color: this.focusColor })
    .borderRadius(DESKTOP_SETTINGS_ROW_RADIUS)
    .clip(true)
    .enabled(this.isEnabled)
    .focusable(true)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onHover((hovered: boolean) => {
      this.hovered = hovered && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  private updatePressed(type: TouchType): void {
    this.pressed = this.isEnabled && type === TouchType.Down;
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.pressed || this.hovered || this.focused
      ? this.hoverBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent');
  }

  private hasValueSwatch(): boolean {
    return `${this.valueSwatchColor}`.length > 0;
  }
}

@Component
export struct SettingsDesktopDropdownRow {
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop options: SettingsDetailOption[] = [];
  @Prop menuRadioGroup: string = '';
  @Prop isEnabled: boolean = true;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop hoverBackgroundColor: ResourceColor = '';
  @Prop focusColor: ResourceColor = '';
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private pressed: boolean = false;
  onSelect?: (optionId: string) => void;

  build() {
    Button() {
      Row({ space: DESKTOP_SETTINGS_ROW_CONTENT_SPACE }) {
        Text(this.title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.isEnabled ? this.primaryTextColor : this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        Text(this.value)
          .fontSize(13)
          .fontColor(this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)
          .constraintSize({ maxWidth: 260 })

        AiraIcon({
          airaIconId: 'browser.toolbar.forward',
          iconSize: 13,
          iconColor: this.secondaryTextColor
        })
        .rotate({ angle: 90 })
      }
      .width('100%')
      .height('100%')
      .padding({ left: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING, right: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(DESKTOP_SETTINGS_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.resolveBackgroundColor())
    .border({ width: this.focused ? DESKTOP_SETTINGS_FOCUS_WIDTH : 0, color: this.focusColor })
    .borderRadius(DESKTOP_SETTINGS_ROW_RADIUS)
    .clip(true)
    .enabled(this.isEnabled)
    .focusable(true)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onHover((hovered: boolean) => {
      this.hovered = hovered && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onTouch((event: TouchEvent) => {
      this.pressed = this.isEnabled && event.type === TouchType.Down;
    })
    .bindMenu(this.buildOptionsMenu(), {
      placement: Placement.BottomRight,
      enableArrow: false,
      showInSubWindow: false,
      borderRadius: BROWSER_DESKTOP_MENU_CORNER_RADIUS_VP
    })
  }

  @Builder
  private buildOptionsMenu() {
    BrowserDesktopContextMenu({ menuWidthVp: BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP }) {
      ForEach(this.options, (option: SettingsDetailOption) => {
        MenuItem(() => {
          this.buildOptionsMenuItem(option)
        })
        .enabled(option.isEnabled)
        .padding(0)
        .borderRadius(BROWSER_DESKTOP_MENU_ITEM_CORNER_RADIUS_VP)
        .clip(true)
        .hoverEffect(option.isEnabled ? HoverEffect.Highlight : HoverEffect.None)
        .onClick(() => {
          if (option.isEnabled && !option.isSelected) {
            this.onSelect?.(option.id);
          }
        })
      }, (option: SettingsDetailOption) => `desktop-settings-option-${option.id}-${option.isSelected ? '1' : '0'}`)
    }
  }

  @Builder
  private buildOptionsMenuItem(option: SettingsDetailOption) {
    Row({ space: 10 }) {
      Text(option.label)
        .layoutWeight(1)
        .constraintSize({ minWidth: 0 })
        .fontSize(BROWSER_DESKTOP_MENU_TEXT_SIZE_FP)
        .lineHeight(BROWSER_DESKTOP_MENU_TEXT_LINE_HEIGHT_VP)
        .fontWeight(option.isSelected ? FontWeight.Medium : FontWeight.Regular)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Radio({ value: option.id, group: this.menuRadioGroup })
        .checked(option.isSelected)
        .enabled(option.isEnabled)
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({ checkedBackgroundColor: this.focusColor })
    }
    .width(BROWSER_DESKTOP_MENU_WIDE_WIDTH_VP - BROWSER_DESKTOP_MENU_HORIZONTAL_INSET_VP * 2)
    .height(BROWSER_DESKTOP_MENU_ITEM_HEIGHT_VP)
    .padding({
      left: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP,
      right: BROWSER_DESKTOP_MENU_ITEM_HORIZONTAL_PADDING_VP
    })
    .alignItems(VerticalAlign.Center)
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.pressed || this.hovered || this.focused
      ? this.hoverBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent');
  }
}

@Component
export struct SettingsDesktopSwitchRow {
  @Prop title: ResourceStr = '';
  @Prop checked: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop hoverBackgroundColor: ResourceColor = '';
  @Prop focusColor: ResourceColor = '';
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private pressed: boolean = false;
  onChange?: (checked: boolean) => void;

  build() {
    Button() {
      Row({ space: DESKTOP_SETTINGS_ROW_CONTENT_SPACE }) {
        Text(this.title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.isEnabled ? this.primaryTextColor : this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        Toggle({ type: ToggleType.Switch, isOn: this.checked })
          .enabled(this.isEnabled)
          .selectedColor(this.focusColor)
          .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height('100%')
      .padding({ left: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING, right: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(DESKTOP_SETTINGS_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.resolveBackgroundColor())
    .border({ width: this.focused ? DESKTOP_SETTINGS_FOCUS_WIDTH : 0, color: this.focusColor })
    .borderRadius(DESKTOP_SETTINGS_ROW_RADIUS)
    .clip(true)
    .enabled(this.isEnabled)
    .focusable(true)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onHover((hovered: boolean) => {
      this.hovered = hovered && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onTouch((event: TouchEvent) => {
      this.pressed = this.isEnabled && event.type === TouchType.Down;
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onChange?.(!this.checked);
      }
    })
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.pressed || this.hovered || this.focused
      ? this.hoverBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent');
  }
}

@Component
export struct SettingsDesktopOptionRow {
  @Prop title: ResourceStr = '';
  @Prop isSelected: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop radioGroup: string = '';
  @Prop radioValue: string = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop hoverBackgroundColor: ResourceColor = '';
  @Prop focusColor: ResourceColor = '';
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  @State private pressed: boolean = false;
  onAction?: () => void;

  build() {
    Button() {
      Row({ space: DESKTOP_SETTINGS_ROW_CONTENT_SPACE }) {
        Text(this.title)
          .layoutWeight(1)
          .fontSize(15)
          .fontWeight(FontWeight.Regular)
          .fontColor(this.isEnabled ? this.primaryTextColor : this.secondaryTextColor)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Start)

        Radio({ value: this.radioValue, group: this.radioGroup })
          .checked(this.isSelected)
          .enabled(this.isEnabled)
          .hitTestBehavior(HitTestMode.None)
          .radioStyle({ checkedBackgroundColor: this.focusColor })
      }
      .width('100%')
      .height('100%')
      .padding({ left: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING, right: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(DESKTOP_SETTINGS_ROW_HEIGHT)
    .type(ButtonType.Normal)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(false)
    .backgroundColor(this.resolveBackgroundColor())
    .border({ width: this.focused ? DESKTOP_SETTINGS_FOCUS_WIDTH : 0, color: this.focusColor })
    .borderRadius(DESKTOP_SETTINGS_ROW_RADIUS)
    .clip(true)
    .enabled(this.isEnabled)
    .focusable(true)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onHover((hovered: boolean) => {
      this.hovered = hovered && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onTouch((event: TouchEvent) => {
      this.pressed = this.isEnabled && event.type === TouchType.Down;
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  private resolveBackgroundColor(): ResourceColor {
    return this.pressed || this.hovered || this.focused
      ? this.hoverBackgroundColor
      : $r('sys.color.ohos_id_color_background_transparent');
  }
}

@Component
export struct SettingsDesktopStaticValueRow {
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';

  build() {
    Row({ space: DESKTOP_SETTINGS_ROW_CONTENT_SPACE }) {
      Text(this.title)
        .layoutWeight(1)
        .fontSize(15)
        .fontWeight(FontWeight.Regular)
        .fontColor(this.primaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.value)
        .fontSize(13)
        .fontColor(this.secondaryTextColor)
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .constraintSize({ maxWidth: 360 })
    }
    .width('100%')
    .height(DESKTOP_SETTINGS_ROW_HEIGHT)
    .padding({ left: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING, right: DESKTOP_SETTINGS_ROW_HORIZONTAL_PADDING })
    .alignItems(VerticalAlign.Center)
  }
}

@Component
export struct SettingsDesktopActionButton {
  @Prop title: ResourceStr = '';
  @Prop emphasis: SettingsDetailActionButtonEmphasis = 'primary';
  @Prop isEnabled: boolean = true;
  @Prop accentColor: ResourceColor = '';
  @Prop onAccentColor: ResourceColor = '';
  @Prop hoverBackgroundColor: ResourceColor = '';
  @Prop dangerColor: ResourceColor = '';
  @State private hovered: boolean = false;
  @State private focused: boolean = false;
  onAction?: () => void;

  build() {
    Button() {
      Text(this.title)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveForegroundColor())
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .height(36)
    .constraintSize({ minWidth: 112, maxWidth: 280 })
    .type(ButtonType.Normal)
    .buttonStyle(this.emphasis === 'danger' ? ButtonStyleMode.TEXTUAL : ButtonStyleMode.NORMAL)
    .stateEffect(this.isEnabled)
    .backgroundColor(this.resolveBackgroundColor())
    .border({ width: this.focused ? DESKTOP_SETTINGS_FOCUS_WIDTH : 0, color: this.resolveFocusColor() })
    .borderRadius(6)
    .padding({ left: 16, right: 16 })
    .enabled(this.isEnabled)
    .focusable(true)
    .opacity(this.isEnabled ? (this.hovered && this.emphasis === 'primary' ? 0.86 : 1) : 0.48)
    .onHover((hovered: boolean) => {
      this.hovered = hovered && this.isEnabled;
    })
    .onFocus(() => {
      this.focused = this.isEnabled;
    })
    .onBlur(() => {
      this.focused = false;
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  private resolveForegroundColor(): ResourceColor {
    return this.emphasis === 'danger' ? this.dangerColor : this.onAccentColor;
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.emphasis === 'danger') {
      return this.hovered || this.focused
        ? this.hoverBackgroundColor
        : $r('sys.color.ohos_id_color_background_transparent');
    }
    return this.accentColor;
  }

  private resolveFocusColor(): ResourceColor {
    return this.emphasis === 'danger' ? this.dangerColor : this.onAccentColor;
  }
}
