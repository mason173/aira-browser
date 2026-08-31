import { SettingsCenterAppProxyNoticeState } from '../../../core/settings/SettingsCenterViewModel';
import { SettingsCenterSearchState } from '../../../core/settings/SettingsDestinationNavigationOwner';
import { SettingsAppProxyNoticeBanner } from './SettingsAppProxyNoticeBanner';
import { AiraIcon } from '../common/AiraIcon';

@Component
export struct SettingsCenterSearchHeader {
  @Prop showAppProxyNotice: boolean = true;
  @Prop showSearchField: boolean = true;
  @Prop showScanAction: boolean = true;
  @Prop useToolbarSearchStyle: boolean = false;
  @Prop appProxyNotice: SettingsCenterAppProxyNoticeState = {
    shouldShow: false,
    message: ''
  };
  @Prop searchState: SettingsCenterSearchState = {
    query: '',
    isActive: false,
    groups: [],
    resultCount: 0
  };
  @Prop resolvedThemeMode: string = 'light';
  @Prop surfaceColor: ResourceColor = '';
  @Prop primaryTextColor: ResourceColor = '';
  @Prop secondaryTextColor: ResourceColor = '';
  @Prop accentColor: ResourceColor = '';
  @Prop statusColor: ResourceColor = '';
  onOpenAppProxyQuickSheet?: () => void;
  onScanLoginAction?: () => void;
  onSearchQueryChange?: (query: string) => void;

  build() {
    Column() {
      if (this.showAppProxyNotice) {
        this.buildAppProxyNotice()
      }
      if (this.showSearchField) {
        this.buildSearchField()
      }
    }
    .width('100%')
  }

  @Builder
  private buildAppProxyNotice() {
    if (this.appProxyNotice.shouldShow) {
      SettingsAppProxyNoticeBanner({
        message: this.appProxyNotice.message,
        surfaceColor: this.surfaceColor,
        primaryTextColor: this.primaryTextColor,
        accentColor: this.accentColor,
        statusColor: this.statusColor,
        onAction: () => {
          this.onOpenAppProxyQuickSheet?.();
        }
      })
    }
  }

  @Builder
  private buildSearchField() {
    Row({ space: this.useToolbarSearchStyle ? 6 : 8 }) {
      AiraIcon({
        airaIconId: 'settings.search',
        iconSize: this.useToolbarSearchStyle ? 16 : 18,
        iconColor: this.secondaryTextColor
      })

      TextInput({ text: this.searchState.query, placeholder: '搜索设置项' })
        .layoutWeight(1)
        .height(this.useToolbarSearchStyle ? 34 : 40)
        .type(InputType.Normal)
        .enterKeyType(EnterKeyType.Search)
        .enableKeyboardOnFocus(false)
        .fontSize(this.useToolbarSearchStyle ? 14 : 16)
        .fontColor(this.primaryTextColor)
        .placeholderColor(this.secondaryTextColor)
        .caretColor(this.accentColor)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .padding({ left: 0, right: 0 })
        .onChange((value: string) => {
          this.onSearchQueryChange?.(value);
        })

      if (this.searchState.query.length > 0) {
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.clearInput',
            iconSize: this.useToolbarSearchStyle ? 14 : 18,
            iconColor: this.secondaryTextColor
          })
        }
        .width(this.useToolbarSearchStyle ? 28 : 32)
        .height(this.useToolbarSearchStyle ? 28 : 32)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(true)
        .accessibilityText('清除搜索')
        .onClick(() => {
          this.onSearchQueryChange?.('');
        })
      }

      if (this.showScanAction) {
        Button() {
          AiraIcon({
            airaIconId: 'browser.toolbar.scanQr',
            iconSize: 18,
            iconColor: this.primaryTextColor
          })
        }
        .width(32)
        .height(32)
        .type(ButtonType.Circle)
        .buttonStyle(ButtonStyleMode.TEXTUAL)
        .backgroundColor($r('sys.color.ohos_id_color_background_transparent'))
        .stateEffect(true)
        .accessibilityText('扫码登录')
        .onClick(() => {
          this.onScanLoginAction?.();
        })
      }
    }
    .width('100%')
    .height(this.useToolbarSearchStyle ? 36 : 48)
    .padding({
      left: this.useToolbarSearchStyle ? 11 : 14,
      right: this.useToolbarSearchStyle ? 7 : 10
    })
    .backgroundColor(this.surfaceColor)
    .borderRadius(this.useToolbarSearchStyle ? 10 : 18)
    .clip(true)
  }
}
