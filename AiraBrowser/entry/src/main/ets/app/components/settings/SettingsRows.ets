import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_OUTLINE_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY,
  BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  AiraAccountRecognitionBadgeKind,
  AiraMembershipBadgeKind
} from '../../../common/models/MembershipModels';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { SettingsDetailOption } from '../../../core/settings/SettingsDetailViewModel';
import { AiraIcon } from '../common/AiraIcon';
import {
  createFloatingGlassMaterialIfAvailable,
  resolveFloatingGlassMaterialBackgroundColor,
  resolveFloatingGlassMaterialTintForMode,
  systemMaterialModifier
} from '../common/FloatingGlassMaterialTokens';

export type SettingsRowPosition = 'single' | 'first' | 'middle' | 'last';
export type SettingsActionButtonEmphasis = 'primary' | 'danger';
export type SettingsActionButtonVariant = 'tonal' | 'filled';

const SETTINGS_ROW_CORNER_RADIUS = 18;
const SETTINGS_ROW_HORIZONTAL_PADDING = 16;
const SETTINGS_ROW_VERTICAL_PADDING = 14;
const SETTINGS_ROW_SPACE = 12;
const SETTINGS_ACTION_BUTTON_HEIGHT = 44;
const SETTINGS_TEXT_FIELD_HEIGHT = 46;
const SETTINGS_ROW_ICON_SIZE = 34;
const SETTINGS_ROW_OPTION_ICON_SIZE = 38;
const SETTINGS_DROPDOWN_MENU_MIN_WIDTH = 232;
const SETTINGS_DROPDOWN_MENU_ITEM_HEIGHT = 48;

export type SettingsMembershipBadgeKind = AiraMembershipBadgeKind;

@Component
export struct SettingsAccountRecognitionBadge {
  @Prop kind: AiraAccountRecognitionBadgeKind = 'none';
  @Prop badgeBackgroundColor: ResourceColor = '';
  @Prop badgeTextColor: ResourceColor = '';

  build() {
    if (this.kind === 'insider') {
      Text('INSIDER')
        .fontSize(10)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.badgeTextColor)
        .maxLines(1)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .backgroundColor(this.badgeBackgroundColor)
        .borderRadius(7)
    }
  }
}

@Component
export struct SettingsInfoTooltipButton {
  @Prop tooltipIcon: Resource = $r('sys.symbol.info_circle');
  @Prop tooltipMessage: string = '';
  @Prop tooltipAccessibilityLabel: string = '';
  @Prop tooltipIconColor: ResourceColor = '';
  @Prop tooltipBackgroundColor: ResourceColor = '';
  @Prop tooltipTextColor: ResourceColor = '';
  @Prop isEnabled: boolean = true;
  @State private tooltipVisible: boolean = false;

  build() {
    Button() {
      SymbolGlyph(this.tooltipIcon)
        .fontSize(17)
        .fontColor([this.tooltipIconColor])
    }
    .width(28)
    .height(28)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.TEXTUAL)
    .stateEffect(true)
    .enabled(this.isEnabled)
    .accessibilityText(this.tooltipAccessibilityLabel)
    .onClick(() => {
      if (this.isEnabled && this.tooltipMessage.trim().length > 0) {
        this.tooltipVisible = !this.tooltipVisible;
      }
    })
    .bindPopup(this.tooltipVisible, {
      message: this.tooltipMessage,
      placement: Placement.Top,
      enableArrow: true,
      autoCancel: true,
      mask: false,
      targetSpace: 8,
      popupColor: this.tooltipBackgroundColor,
      messageOptions: {
        textColor: this.tooltipTextColor,
        font: {
          size: 13,
          weight: FontWeight.Regular
        }
      },
      radius: 14,
      width: 246,
      onStateChange: (event: PopupStateChangeParam) => {
        if (!event.isVisible) {
          this.tooltipVisible = false;
        }
      }
    })
  }
}

@Component
export struct SettingsMembershipBadge {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop kind: SettingsMembershipBadgeKind = 'none';

  build() {
    if (this.kind !== 'none') {
      Text(this.resolveLabel())
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveTextColor())
        .maxLines(1)
        .padding({ left: 7, right: 7, top: 2, bottom: 2 })
        .backgroundColor(this.resolveBackgroundColor())
        .border({
          width: this.kind === 'pro' || this.kind === 'long_term' ? 0 : 1,
          color: this.resolveBorderColor()
        })
        .borderRadius(7)
    }
  }

  private resolveLabel(): string {
    if (this.kind === 'long_term') {
      return 'LIFETIME';
    }
    if (this.kind === 'pro') {
      return 'PRO';
    }
    return 'Club';
  }

  private resolveTextColor(): ResourceColor {
    if (this.kind === 'pro' || this.kind === 'long_term') {
      return this.storedSurfaceBackgroundColor;
    }
    if (this.kind === 'club') {
      return this.storedAccentColor;
    }
    return this.storedSecondaryTextColor;
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.kind === 'pro' || this.kind === 'long_term') {
      return this.storedPrimaryTextColor;
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveBorderColor(): ResourceColor {
    if (this.kind === 'club') {
      return this.storedAccentColor;
    }
    return this.storedOutlineColor;
  }
}

@Component
export struct SettingsAccountCardRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop subtitle: ResourceStr = '';
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  @Prop avatarBackgroundColor: ResourceColor = '';
  @Prop avatarIconColor: ResourceColor = '';
  @Prop avatarUri: string = '';
  @Prop membershipBadge: SettingsMembershipBadgeKind = 'none';
  @Prop recognitionBadge: AiraAccountRecognitionBadgeKind = 'none';
  @State pressed: boolean = false;
  onAction?: () => void;

  build() {
    Row({ space: SETTINGS_ROW_SPACE }) {
      this.buildAvatar()

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor(
              this.isEnabled
                ? this.resolvePrimaryTextColor()
                : this.resolveSecondaryTextColor()
            )
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: 180 })

          this.buildAccountBadges()
        }
        .constraintSize({ maxWidth: '100%' })
        .alignItems(VerticalAlign.Center)

      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.resolveSecondaryTextColor()])
    }
    .width('100%')
    .backgroundColor(this.resolvePressedBackgroundColor())
    .borderRadius(this.resolveBorderRadius())
    .clip(true)
    .padding({
      left: SETTINGS_ROW_HORIZONTAL_PADDING,
      right: SETTINGS_ROW_HORIZONTAL_PADDING,
      top: SETTINGS_ROW_VERTICAL_PADDING,
      bottom: SETTINGS_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
  }

  @Builder
  private buildAccountBadges() {
    if (this.recognitionBadge !== 'none' || this.membershipBadge !== 'none') {
      Row({ space: 4 }) {
        SettingsAccountRecognitionBadge({
          kind: this.recognitionBadge,
          badgeBackgroundColor: this.resolveAvatarBackgroundColor(),
          badgeTextColor: this.resolveAvatarIconColor()
        })
        SettingsMembershipBadge({ kind: this.membershipBadge })
      }
      .alignItems(VerticalAlign.Center)
    }
  }

  @Builder
  private buildAvatar() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.avatarUri.trim().length > 0) {
        Image(this.avatarUri)
          .width(46)
          .height(46)
          .borderRadius(23)
          .clip(true)
          .objectFit(ImageFit.Cover)
      } else {
        SymbolGlyph($r('sys.symbol.person_fill'))
          .fontSize(25)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.resolveAvatarIconColor()])
      }
    }
    .width(46)
    .height(46)
    .borderRadius(23)
    .backgroundColor(this.resolveAvatarBackgroundColor())
    .clip(true)
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    if (this.pressed && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveBorderRadius(): BorderRadiuses {
    return resolveSettingsRowBorderRadius(this.rowPosition);
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : this.storedPressedBackgroundColor;
  }

  private resolveAvatarBackgroundColor(): ResourceColor {
    return `${this.avatarBackgroundColor}`.length > 0 ? this.avatarBackgroundColor : this.storedAccentColor;
  }

  private resolveAvatarIconColor(): ResourceColor {
    return `${this.avatarIconColor}`.length > 0 ? this.avatarIconColor : this.storedSettingsIconForegroundColor;
  }

}

@Component
export struct SettingsNavigationRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop valueSwatchColor: ResourceColor = '';
  @Prop description: ResourceStr = '';
  @Prop icon?: Resource = undefined;
  @Prop imageIcon: Resource | undefined = undefined;
  @Prop airaIconId: AiraRenderableIconId | undefined = undefined;
  @Prop iconBackgroundColor?: ResourceColor = undefined;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  @Prop iconColor: ResourceColor = '';
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop isSelected: boolean = false;
  @Prop selectedBackgroundColor: ResourceColor = '';
  @Prop membershipBadge: SettingsMembershipBadgeKind = 'none';
  @Prop useCustomLeading: boolean = false;
  @State pressed: boolean = false;
  onAction?: () => void;
  @BuilderParam customLeading: () => void = this.emptyBuilder;

  build() {
    Row({ space: SETTINGS_ROW_SPACE }) {
      if (this.useCustomLeading) {
        this.customLeading()
      } else if (this.icon || this.airaIconId !== undefined) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(SETTINGS_ROW_ICON_SIZE)
            .height(SETTINGS_ROW_ICON_SIZE)
            .fill(this.resolveIconBackgroundColor())

          if (this.airaIconId !== undefined) {
            AiraIcon({
              airaIconId: this.airaIconId as AiraRenderableIconId,
              iconSize: 18,
              iconColor: this.resolveIconColor()
            })
          } else if (this.imageIcon !== undefined) {
            Image(this.imageIcon as Resource)
              .width(18)
              .height(18)
              .objectFit(ImageFit.Contain)
          } else {
            SymbolGlyph(this.icon)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.resolveIconColor()])
          }
        }
        .width(SETTINGS_ROW_ICON_SIZE)
        .height(SETTINGS_ROW_ICON_SIZE)
      }

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(this.desktopPresentation ? 15 : 16)
            .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
            .fontColor(
              this.isEnabled
                ? this.resolvePrimaryTextColor()
                : this.resolveSecondaryTextColor()
            )
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .constraintSize({ maxWidth: '100%' })

          SettingsMembershipBadge({ kind: this.membershipBadge })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

      Row({ space: 4 }) {
        if (this.hasValueSwatch()) {
          Circle()
            .width(20)
            .height(20)
            .fill(this.valueSwatchColor)
            .stroke(this.storedOutlineColor)
            .strokeWidth(0.5)
        }

        Text(this.value)
          .fontSize(this.desktopPresentation ? 13 : 14)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor([this.resolveSecondaryTextColor()])
      }
      .constraintSize({ maxWidth: 220 })
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .backgroundColor(this.resolvePressedBackgroundColor())
    .borderRadius(this.resolveBorderRadius())
    .clip(true)
    .padding({
      left: SETTINGS_ROW_HORIZONTAL_PADDING,
      right: SETTINGS_ROW_HORIZONTAL_PADDING,
      top: SETTINGS_ROW_VERTICAL_PADDING,
      bottom: SETTINGS_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
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
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    if (this.pressed && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    if (this.isSelected) {
      return this.resolveSelectedBackgroundColor();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveIconBackgroundColor(): ResourceColor {
    return this.iconBackgroundColor === undefined ?
      $r('sys.color.ohos_id_color_background_transparent') :
      this.iconBackgroundColor;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : this.storedPressedBackgroundColor;
  }

  private resolveSelectedBackgroundColor(): ResourceColor {
    return `${this.selectedBackgroundColor}`.length > 0 ?
      this.selectedBackgroundColor :
      this.storedPressedBackgroundColor;
  }

  private resolveIconColor(): ResourceColor {
    return `${this.iconColor}`.length > 0 ? this.iconColor : this.storedSettingsIconForegroundColor;
  }

  private resolveBorderRadius(): BorderRadiuses {
    return resolveSettingsRowBorderRadius(this.rowPosition);
  }

  private hasValueSwatch(): boolean {
    return `${this.valueSwatchColor}`.length > 0;
  }

  @Builder
  private emptyBuilder() {
  }
}

@Component
export struct SettingsDropdownRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_RESOLVED_MODE_KEY) private storedResolvedThemeMode: string = 'light';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop options: SettingsDetailOption[] = [];
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  @State pressed: boolean = false;
  @State hovered: boolean = false;
  onSelect?: (optionId: string) => void;

  build() {
    Row({ space: SETTINGS_ROW_SPACE }) {
      Column({ space: 4 }) {
        Text(this.title)
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(this.isEnabled ? this.resolvePrimaryTextColor() : this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Row({ space: 4 }) {
        Text(this.value)
          .fontSize(this.desktopPresentation ? 13 : 14)
          .fontColor(this.resolveSecondaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.End)

        SymbolGlyph($r('sys.symbol.chevron_down'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.resolveSecondaryTextColor()])
      }
      .constraintSize({ maxWidth: 240 })
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .backgroundColor(this.resolveBackgroundColor())
    .borderRadius(this.resolveBorderRadius())
    .clip(true)
    .padding({
      left: SETTINGS_ROW_HORIZONTAL_PADDING,
      right: SETTINGS_ROW_HORIZONTAL_PADDING,
      top: SETTINGS_ROW_VERTICAL_PADDING,
      bottom: SETTINGS_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onHover((isHover: boolean) => {
      this.hovered = isHover && this.isEnabled;
    })
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .bindMenu(this.buildOptionsMenu(), {
      placement: Placement.BottomRight,
      enableArrow: false,
      showInSubWindow: false,
      borderRadius: 14
    })
  }

  @Builder
  private buildOptionsMenu() {
    Menu() {
      ForEach(this.options, (option: SettingsDetailOption) => {
        this.buildOptionMenuItem(option)
      }, (option: SettingsDetailOption) => `settings-dropdown-${option.id}-${option.isSelected ? '1' : '0'}`)
    }
    .constraintSize({ minWidth: SETTINGS_DROPDOWN_MENU_MIN_WIDTH })
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
    .radius(14)
    .backgroundColor(resolveFloatingGlassMaterialBackgroundColor(
      $r('app.color.surface_floating_background')
    ))
    .attributeModifier(systemMaterialModifier(createFloatingGlassMaterialIfAvailable(
      resolveFloatingGlassMaterialTintForMode(this.storedResolvedThemeMode)
    )))
  }

  @Builder
  private buildOptionMenuItem(option: SettingsDetailOption) {
    MenuItem(() => {
      this.buildOptionMenuItemContent(option)
    })
    .enabled(option.isEnabled)
    .padding(0)
    .borderRadius(10)
    .clip(true)
    .hoverEffect(option.isEnabled ? HoverEffect.Highlight : HoverEffect.None)
    .onClick(() => {
      if (option.isEnabled && !option.isSelected) {
        this.onSelect?.(option.id);
      }
    })
  }

  @Builder
  private buildOptionMenuItemContent(option: SettingsDetailOption) {
    Row({ space: 10 }) {
      Column({ space: 2 }) {
        Text(option.label)
          .fontSize(15)
          .fontWeight(option.isSelected ? FontWeight.Medium : FontWeight.Regular)
          .fontColor(this.resolvePrimaryTextColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (`${option.helperText}`.length > 0) {
          Text(option.helperText)
            .fontSize(12)
            .fontColor(this.resolveSecondaryTextColor())
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (option.isSelected) {
        SymbolGlyph($r('sys.symbol.checkmark'))
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor([this.storedAccentColor])
      }
    }
    .constraintSize({ minWidth: SETTINGS_DROPDOWN_MENU_MIN_WIDTH - 24 })
    .height(`${option.helperText}`.length > 0 ? SETTINGS_DROPDOWN_MENU_ITEM_HEIGHT + 8 : SETTINGS_DROPDOWN_MENU_ITEM_HEIGHT)
    .padding({ left: 12, right: 12 })
    .alignItems(VerticalAlign.Center)
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.pressed && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    if (this.hovered && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveBorderRadius(): BorderRadiuses {
    return resolveSettingsRowBorderRadius(this.rowPosition);
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : this.storedPressedBackgroundColor;
  }
}

@Component
export struct SettingsStaticValueRow {
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop value: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop valueMaxLines: number = 1;
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop valueClickable: boolean = false;
  @Prop pressedBackgroundColor: ResourceColor = '';
  @State valuePressed: boolean = false;
  onValueAction?: () => void;

  build() {
    Row({ space: SETTINGS_ROW_SPACE }) {
      Column({ space: 4 }) {
        Text(this.title)
          .width('100%')
          .fontSize(this.desktopPresentation ? 15 : 16)
          .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
          .fontColor(
            this.isEnabled
              ? this.resolvePrimaryTextColor()
              : this.resolveSecondaryTextColor()
          )
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

      }
        .layoutWeight(1)
        .constraintSize({ minWidth: 96 })
        .alignItems(HorizontalAlign.Start)

      Text(this.value)
        .fontSize(this.desktopPresentation ? 13 : 14)
        .fontColor(this.resolveValueTextColor())
        .maxLines(this.resolveValueMaxLines())
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .padding(this.valueClickable ? { left: 7, right: 7, top: 4, bottom: 4 } : {
          left: 0,
          right: 0,
          top: 0,
          bottom: 0
        })
        .backgroundColor(this.resolveValueBackgroundColor())
        .borderRadius(this.valueClickable ? 8 : 0)
        .constraintSize({ maxWidth: '62%' })
        .enabled(this.isEnabled && this.valueClickable)
        .onTouch((event: TouchEvent) => {
          this.updateValuePressed(event.type);
        })
        .onClick(() => {
          if (this.isEnabled && this.valueClickable) {
            this.onValueAction?.();
          }
        })
    }
    .width('100%')
    .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
    .borderRadius(this.resolveBorderRadius())
    .clip(true)
    .padding({
      left: SETTINGS_ROW_HORIZONTAL_PADDING,
      right: SETTINGS_ROW_HORIZONTAL_PADDING,
      top: SETTINGS_ROW_VERTICAL_PADDING,
      bottom: SETTINGS_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .opacity(this.isEnabled ? 1 : 0.48)
  }

  private resolveBorderRadius(): BorderRadiuses {
    return resolveSettingsRowBorderRadius(this.rowPosition);
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolveValueMaxLines(): number {
    return this.valueMaxLines > 0 ? this.valueMaxLines : 1;
  }

  private updateValuePressed(type: TouchType): void {
    if (!this.isEnabled || !this.valueClickable) {
      this.valuePressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.valuePressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.valuePressed = false;
    }
  }

  private resolveValueTextColor(): ResourceColor {
    if (this.valueClickable && this.isEnabled) {
      return this.resolvePrimaryTextColor();
    }
    return this.resolveSecondaryTextColor();
  }

  private resolveValueBackgroundColor(): ResourceColor {
    if (this.valuePressed && this.isEnabled && this.valueClickable) {
      return this.resolvePressedBackgroundColorValue();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : $r('sys.color.ohos_id_color_background_transparent');
  }
}

@Component
export struct SettingsSwitchRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#ECEDEF';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop description: ResourceStr = '';
  @Prop checked: boolean = false;
  @Prop icon?: Resource = undefined;
  @Prop imageIcon: Resource | undefined = undefined;
  @Prop imageIconSize: number = 18;
  @Prop imageIconCircular: boolean = false;
  @Prop imageIconCornerRadius: number = 0;
  @Prop iconBackgroundColor?: ResourceColor = undefined;
  @Prop iconColor: ResourceColor = '';
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  @Prop titleActionIcon?: Resource = undefined;
  @Prop titlePopupText: string = '';
  @Prop titleActionAccessibilityText: string = '';
  @Prop dragHandleIcon?: Resource = undefined;
  @Prop dragHandleAccessibilityText: string = '';
  @Prop dragHandleBackgroundColor?: ResourceColor = undefined;
  @Prop trailingActionIcon?: Resource = undefined;
  @Prop membershipBadge: SettingsMembershipBadgeKind = 'none';
  @State pressed: boolean = false;
  onChange?: (checked: boolean) => void;
  onDragHandleStart?: () => void;
  onDragHandleUpdate?: (event: GestureEvent) => void;
  onDragHandleEnd?: () => void;
  onDragHandleCancel?: () => void;
  onTrailingAction?: () => void;

  build() {
    Row({ space: SETTINGS_ROW_SPACE }) {
      if (this.icon || this.imageIcon !== undefined) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(SETTINGS_ROW_ICON_SIZE)
            .height(SETTINGS_ROW_ICON_SIZE)
            .fill(this.resolveIconBackgroundColor())

          if (this.imageIcon !== undefined) {
            Image(this.imageIcon as Resource)
              .width(this.imageIconSize)
              .height(this.imageIconSize)
              .objectFit(this.imageIconCircular || this.imageIconCornerRadius > 0 ? ImageFit.Cover : ImageFit.Contain)
              .borderRadius(this.imageIconCircular ? this.imageIconSize / 2 : this.imageIconCornerRadius)
              .clip(this.imageIconCircular || this.imageIconCornerRadius > 0)
          } else if (this.icon) {
            SymbolGlyph(this.icon as Resource)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.resolveIconColor()])
          }
        }
        .width(SETTINGS_ROW_ICON_SIZE)
        .height(SETTINGS_ROW_ICON_SIZE)
      }

      Column({ space: 4 }) {
        this.buildTitleRow()

        if (`${this.description}`.length > 0) {
          Text(this.description)
            .fontSize(13)
            .fontColor(this.resolveSecondaryTextColor())
            .lineHeight(18)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (this.dragHandleIcon !== undefined) {
        this.buildDragHandle()
      }

      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.48)
        .selectedColor(this.storedAccentColor)
        .onChange((value: boolean) => {
          if (this.isEnabled && this.checked !== value) {
            this.onChange?.(value);
          }
        })

      if (this.trailingActionIcon) {
        Button() {
          SymbolGlyph(this.trailingActionIcon)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.resolveSecondaryTextColor()])
        }
        .width(36)
        .height(36)
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(18)
        .stateEffect(false)
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.48)
        .onClick(() => {
          if (this.isEnabled) {
            this.onTrailingAction?.();
          }
        })
      }
    }
    .width('100%')
    .backgroundColor(this.resolvePressedBackgroundColor())
    .borderRadius(this.resolveBorderRadius())
    .clip(true)
    .padding({
      left: SETTINGS_ROW_HORIZONTAL_PADDING,
      right: SETTINGS_ROW_HORIZONTAL_PADDING,
      top: SETTINGS_ROW_VERTICAL_PADDING,
      bottom: SETTINGS_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
  }

  @Builder
  private buildDragHandle() {
    Button() {
      SymbolGlyph(this.dragHandleIcon as Resource)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.resolveSecondaryTextColor()])
    }
    .width(34)
    .height(34)
    .type(ButtonType.Circle)
    .buttonStyle(ButtonStyleMode.NORMAL)
    .backgroundColor(this.resolveDragHandleBackgroundColor())
    .enabled(this.isEnabled)
    .accessibilityText(this.dragHandleAccessibilityText)
    .gesture(
      PanGesture({ direction: PanDirection.Vertical, distance: 1 })
        .onActionStart(() => {
          this.onDragHandleStart?.();
        })
        .onActionUpdate((event: GestureEvent) => {
          this.onDragHandleUpdate?.(event);
        })
        .onActionEnd(() => {
          this.onDragHandleEnd?.();
        })
        .onActionCancel(() => {
          this.onDragHandleCancel?.();
        }),
      GestureMask.Normal
    )
  }

  @Builder
  private buildTitleRow() {
    Row({ space: this.titleActionIcon === undefined ? 8 : 4 }) {
      Text(this.title)
        .fontSize(this.desktopPresentation ? 15 : 16)
        .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
        .fontColor(
          this.isEnabled
            ? this.resolvePrimaryTextColor()
            : this.resolveSecondaryTextColor()
        )
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(this.titleActionIcon === undefined ? 1 : 0)
        .constraintSize({ maxWidth: this.titleActionIcon === undefined ? '100%' : 180 })

      if (this.titleActionIcon !== undefined) {
        this.buildTitleActionButton()
      }

      SettingsMembershipBadge({ kind: this.membershipBadge })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private buildTitleActionButton() {
    SettingsInfoTooltipButton({
      tooltipIcon: this.titleActionIcon as Resource,
      tooltipMessage: this.titlePopupText,
      tooltipAccessibilityLabel: this.titleActionAccessibilityText,
      tooltipIconColor: this.resolveSecondaryTextColor(),
      tooltipBackgroundColor: this.storedSurfaceBackgroundColor,
      tooltipTextColor: this.resolveSecondaryTextColor(),
      isEnabled: this.isEnabled
    })
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    if (this.pressed && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveBorderRadius(): BorderRadiuses {
    return resolveSettingsRowBorderRadius(this.rowPosition);
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolveIconBackgroundColor(): ResourceColor {
    return this.iconBackgroundColor === undefined ?
      $r('sys.color.ohos_id_color_background_transparent') :
      this.iconBackgroundColor;
  }

  private resolveIconColor(): ResourceColor {
    return `${this.iconColor}`.length > 0 ? this.iconColor : this.storedSettingsIconForegroundColor;
  }

  private resolveDragHandleBackgroundColor(): ResourceColor {
    return this.dragHandleBackgroundColor === undefined ?
      this.storedControlBackgroundColor :
      this.dragHandleBackgroundColor;
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : this.storedPressedBackgroundColor;
  }
}

@Component
export struct SettingsOptionRow {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_SETTINGS_ICON_FOREGROUND_KEY) private storedSettingsIconForegroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_OUTLINE_KEY) private storedOutlineColor: string = '#26000000';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop title: ResourceStr = '';
  @Prop helperText: ResourceStr = '';
  @Prop leadingAiraIconId: AiraRenderableIconId | undefined = undefined;
  @Prop leadingIcon?: Resource = undefined;
  @Prop leadingImage?: Resource = undefined;
  @Prop rowPosition: SettingsRowPosition = 'single';
  @Prop isSelected: boolean = false;
  @Prop isEnabled: boolean = true;
  @Prop desktopPresentation: boolean = false;
  @Prop radioGroup: string = '';
  @Prop radioValue: string = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  @Prop selectedIndicatorColor: ResourceColor = '';
  @Prop trailingActionIcon?: Resource = undefined;
  @Prop isTrailingActionEnabled: boolean = true;
  @Prop membershipBadge: SettingsMembershipBadgeKind = 'none';
  @State pressed: boolean = false;
  onAction?: () => void;
  onTrailingAction?: () => void;
  onLongPressAction?: () => void;

  build() {
    Row({ space: SETTINGS_ROW_SPACE }) {
      if (this.leadingAiraIconId !== undefined || this.leadingIcon) {
        Stack({ alignContent: Alignment.Center }) {
          Circle()
            .width(SETTINGS_ROW_OPTION_ICON_SIZE)
            .height(SETTINGS_ROW_OPTION_ICON_SIZE)
            .fill(this.storedAccentColor)

          if (this.leadingAiraIconId !== undefined) {
            AiraIcon({
              airaIconId: this.leadingAiraIconId as AiraRenderableIconId,
              iconSize: 18,
              iconColor: this.storedSettingsIconForegroundColor
            })
          } else {
            SymbolGlyph(this.leadingIcon)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.storedSettingsIconForegroundColor])
          }
        }
        .width(SETTINGS_ROW_OPTION_ICON_SIZE)
        .height(SETTINGS_ROW_OPTION_ICON_SIZE)
      } else if (this.leadingImage) {
        Stack() {
          Circle()
            .width(SETTINGS_ROW_OPTION_ICON_SIZE)
            .height(SETTINGS_ROW_OPTION_ICON_SIZE)
            .fill(this.storedSurfaceBackgroundColor)
            .stroke(this.storedOutlineColor)
            .strokeWidth(1)

          Image(this.leadingImage)
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)
        }
        .width(SETTINGS_ROW_OPTION_ICON_SIZE)
        .height(SETTINGS_ROW_OPTION_ICON_SIZE)
      }

      Column({ space: 4 }) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(this.desktopPresentation ? 15 : 16)
            .fontWeight(this.desktopPresentation ? FontWeight.Regular : FontWeight.Medium)
            .fontColor(
              this.isEnabled
                ? this.resolvePrimaryTextColor()
                : this.resolveSecondaryTextColor()
            )
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .constraintSize({ maxWidth: '100%' })

          SettingsMembershipBadge({ kind: this.membershipBadge })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({
        value: this.resolveRadioValue(),
        group: this.resolveRadioGroup()
      })
        .checked(this.isSelected)
        .enabled(this.isEnabled)
        .hitTestBehavior(HitTestMode.None)
        .radioStyle({
          checkedBackgroundColor: this.resolveSelectedIndicatorColor()
        })

      if (this.trailingActionIcon) {
        Button() {
          SymbolGlyph(this.trailingActionIcon)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.resolveSecondaryTextColor()])
        }
        .width(36)
        .height(36)
        .type(ButtonType.Normal)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .borderRadius(18)
        .stateEffect(false)
        .enabled(this.isTrailingActionEnabled)
        .opacity(this.isTrailingActionEnabled ? 1 : 0.48)
        .onClick(() => {
          if (this.isTrailingActionEnabled) {
            this.onTrailingAction?.();
          }
        })
      }
    }
    .width('100%')
    .backgroundColor(this.resolvePressedBackgroundColor())
    .borderRadius(this.resolveBorderRadius())
    .clip(true)
    .padding({
      left: SETTINGS_ROW_HORIZONTAL_PADDING,
      right: SETTINGS_ROW_HORIZONTAL_PADDING,
      top: SETTINGS_ROW_VERTICAL_PADDING,
      bottom: SETTINGS_ROW_VERTICAL_PADDING
    })
    .alignItems(VerticalAlign.Center)
    .enabled(this.isEnabled || this.isTrailingActionEnabled)
    .opacity(this.isEnabled ? 1 : 0.48)
    .onTouch((event: TouchEvent) => {
      this.updatePressed(event.type);
    })
    .onClick(() => {
      if (this.isEnabled) {
        this.onAction?.();
      }
    })
    .gesture(
      LongPressGesture({ fingers: 1, repeat: false, duration: 450 })
        .onAction(() => {
          if (this.isEnabled) {
            this.onLongPressAction?.();
          }
        })
    )
  }

  private updatePressed(type: TouchType): void {
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolvePressedBackgroundColor(): ResourceColor {
    if (this.pressed && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    return $r('sys.color.ohos_id_color_background_transparent');
  }

  private resolveBorderRadius(): BorderRadiuses {
    return resolveSettingsRowBorderRadius(this.rowPosition);
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : this.storedPressedBackgroundColor;
  }

  private resolveSelectedIndicatorColor(): ResourceColor {
    return `${this.selectedIndicatorColor}`.length > 0 ? this.selectedIndicatorColor : this.storedAccentColor;
  }

  private resolveRadioGroup(): string {
    return this.radioGroup.length > 0 ? this.radioGroup : `settings-option-row-${this.resolveRadioValue()}`;
  }

  private resolveRadioValue(): string {
    return this.radioValue.length > 0 ? this.radioValue : `${this.title}`;
  }
}

@Component
export struct SettingsActionButton {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Prop title: ResourceStr = '';
  @Prop emphasis: SettingsActionButtonEmphasis = 'primary';
  @Prop variant: SettingsActionButtonVariant = 'tonal';
  @Prop isEnabled: boolean = true;
  @Prop accentColor: ResourceColor = '';
  @Prop pressedBackgroundColor: ResourceColor = '';
  @Prop membershipBadge: SettingsMembershipBadgeKind = 'none';
  @State pressed: boolean = false;
  onAction?: () => void;

  build() {
    Button() {
      Row({ space: 8 }) {
        Text(this.title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.resolveForegroundColor())
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        SettingsMembershipBadge({ kind: this.membershipBadge })
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .constraintSize({ maxWidth: '100%' })
    }
      .width('100%')
      .height(SETTINGS_ACTION_BUTTON_HEIGHT)
      .type(ButtonType.Normal)
      .buttonStyle(ButtonStyleMode.NORMAL)
      .backgroundColor(this.resolveBackgroundColor())
      .borderRadius(SETTINGS_ACTION_BUTTON_HEIGHT / 2)
      .padding({ left: 14, right: 14 })
      .stateEffect(false)
      .enabled(this.isEnabled)
      .opacity(this.isEnabled ? 1 : 0.48)
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
    if (!this.isEnabled) {
      this.pressed = false;
      return;
    }
    if (type === TouchType.Down) {
      this.pressed = true;
      return;
    }
    if (type === TouchType.Up || type === TouchType.Cancel) {
      this.pressed = false;
    }
  }

  private resolveForegroundColor(): ResourceColor {
    if (this.emphasis === 'danger') {
      return $r('app.color.permission_blocked');
    }
    if (this.variant === 'filled') {
      return this.storedSurfaceBackgroundColor;
    }
    return this.resolveAccentColor();
  }

  private resolveBackgroundColor(): ResourceColor {
    if (this.emphasis === 'danger') {
      return this.resolvePressedBackgroundColorValue();
    }
    if (this.variant === 'filled') {
      return this.resolveAccentColor();
    }
    if (this.pressed && this.isEnabled) {
      return this.resolvePressedBackgroundColorValue();
    }
    return this.resolvePressedBackgroundColorValue();
  }

  private resolveAccentColor(): ResourceColor {
    return `${this.accentColor}`.length > 0 ? this.accentColor : this.storedAccentColor;
  }

  private resolvePressedBackgroundColorValue(): ResourceColor {
    return `${this.pressedBackgroundColor}`.length > 0 ? this.pressedBackgroundColor : this.storedPressedBackgroundColor;
  }
}

@Component
export struct SettingsTextField {
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop label: ResourceStr = '';
  @Prop text: string = '';
  @Prop placeholder: ResourceStr = '';
  @Prop helperText: ResourceStr = '';
  @Prop errorText: ResourceStr = '';
  @Prop isEnabled: boolean = true;
  @Prop secure: boolean = false;
  @Prop inputType: InputType = InputType.Normal;
  @Prop maxLength: number = 0;
  @Prop controlBackgroundColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop desktopPresentation: boolean = false;
  @Prop underlineStyle: boolean = false;
  onChange: (value: string) => void = (_value: string) => {};

  build() {
    Column({ space: 8 }) {
      if (`${this.label}`.length > 0) {
        Text(this.label)
          .width('100%')
          .fontSize(this.desktopPresentation ? 13 : 14)
          .fontColor(this.resolveSecondaryTextColor())
      }

      TextInput({ text: this.text, placeholder: this.placeholder })
        .width('100%')
        .height(SETTINGS_TEXT_FIELD_HEIGHT)
        .fontSize(15)
        .fontColor(this.resolvePrimaryTextColor())
        .placeholderColor(this.resolveSecondaryTextColor())
        .type(this.resolveInputType())
        .maxLength(this.resolveMaxLength())
        .backgroundColor(this.resolveControlBackgroundColor())
        .border({
          width: { bottom: this.underlineStyle ? 1 : 0 },
          color: this.storedDividerColor
        })
        .borderRadius(this.underlineStyle ? 0 : (this.desktopPresentation ? 8 : 14))
        .padding({ left: this.underlineStyle ? 0 : 12, right: this.underlineStyle ? 0 : 12 })
        .enabled(this.isEnabled)
        .opacity(this.isEnabled ? 1 : 0.48)
        .onChange((nextValue: string) => {
          if (this.isEnabled) {
            this.onChange(nextValue);
          }
        })

      if (`${this.errorText}`.length > 0) {
        Text(this.errorText)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor($r('app.color.permission_blocked'))
      } else if (`${this.helperText}`.length > 0) {
        Text(this.helperText)
          .width('100%')
          .fontSize(13)
          .lineHeight(18)
          .fontColor(this.resolveSecondaryTextColor())
      }
    }
    .width('100%')
  }

  private resolveMaxLength(): number {
    return this.maxLength > 0 ? this.maxLength : 100000;
  }

  private resolveInputType(): InputType {
    if (this.secure) {
      return InputType.Password;
    }
    return this.inputType;
  }

  private resolveControlBackgroundColor(): ResourceColor {
    if (this.underlineStyle) {
      return $r('sys.color.ohos_id_color_background_transparent');
    }
    return `${this.controlBackgroundColor}`.length > 0 ? this.controlBackgroundColor : this.storedControlBackgroundColor;
  }

  private resolvePrimaryTextColor(): ResourceColor {
    return `${this.primaryTextColor}`.length > 0 ? this.primaryTextColor : this.storedPrimaryTextColor;
  }

  private resolveSecondaryTextColor(): ResourceColor {
    return `${this.secondaryTextColor}`.length > 0 ? this.secondaryTextColor : this.storedSecondaryTextColor;
  }
}

function resolveSettingsRowBorderRadius(_position: SettingsRowPosition): BorderRadiuses {
  return {
    topLeft: SETTINGS_ROW_CORNER_RADIUS,
    topRight: SETTINGS_ROW_CORNER_RADIUS,
    bottomLeft: SETTINGS_ROW_CORNER_RADIUS,
    bottomRight: SETTINGS_ROW_CORNER_RADIUS
  };
}
