import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  AppIconSettingsOptionState,
  AppIconSettingsState,
  AppIconSettingsViewModel
} from '../../core/settings/AppIconSettingsViewModel';
import { DynamicAppIconMutationResult, DynamicAppIconService } from '../../services/appicon/DynamicAppIconService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsFooterText,
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody,
  SettingsSection
} from '../components/settings/SettingsLayout';
import { SettingsRowPosition } from '../components/settings/SettingsRows';

const APP_ICON_OPTION_SIZE: number = 44;
const APP_ICON_OPTION_RADIO_GROUP: string = 'app-icon-options';

@Entry
@Component
struct AppIconSettingsPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private service: DynamicAppIconService = new DynamicAppIconService();
  private viewModel: AppIconSettingsViewModel = new AppIconSettingsViewModel();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string = DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @State private state: AppIconSettingsState = this.viewModel.buildLoadingState();
  @State private isLoading: boolean = true;
  @State private isApplying: boolean = false;
  @State private applyingOptionId: string = '';

  aboutToAppear(): void {
    this.refreshIcons();
  }

  build() {
    Column() {
      SettingsHdsScaffold({
        title: this.state.title,
        backIconKind: 'back',
        pageBackground: this.storedPageBackgroundColor,
        headerButtonBackground: this.storedPressedBackgroundColor,
        primaryTextColor: this.storedPrimaryTextColor,
        dividerColor: this.storedDividerColor,
        contentKind: 'canvas',
        onBack: () => {
          this.navigationCoordinator.back();
        }
      }) {
        SettingsScrollBody({ topPadding: 16, bottomPadding: 26 }) {
          this.buildContent()
        }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildContent() {
    SettingsSection({
      title: '图标',
      secondaryTextColor: this.storedSecondaryTextColor
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.state.options, (option: AppIconSettingsOptionState, index: number) => {
          this.buildIconOption(option, this.resolveRowPosition(index, this.state.options.length))
          if (index < this.state.options.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (option: AppIconSettingsOptionState) => option.id)
      }

      if (this.state.statusText.length > 0) {
        this.buildStatusText()
      }

      SettingsFooterText({
        text: this.state.footerText,
        secondaryTextColor: this.storedSecondaryTextColor
      })
    }
  }

  @Builder
  private buildIconOption(option: AppIconSettingsOptionState, rowPosition: SettingsRowPosition) {
    Row({ space: 12 }) {
      this.buildIconPreview(option)

      Text(option.title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.resolveOptionTextColor(option))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)

      if (this.isOptionApplying(option)) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(this.storedAccentColor)
      } else {
        Radio({
          value: option.id,
          group: APP_ICON_OPTION_RADIO_GROUP
        })
          .checked(option.isSelected)
          .enabled(this.isOptionInteractive(option))
          .hitTestBehavior(HitTestMode.None)
          .radioStyle({
            checkedBackgroundColor: this.storedAccentColor
          })
      }
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .borderRadius(this.resolveRowBorderRadius(rowPosition))
    .backgroundColor(this.storedSurfaceBackgroundColor)
    .alignItems(VerticalAlign.Center)
    .opacity(this.isOptionInteractive(option) || option.isSelected ? 1 : 0.48)
    .onClick(() => {
      this.requestSelectOption(option);
    })
  }

  @Builder
  private buildIconPreview(option: AppIconSettingsOptionState) {
    Stack({ alignContent: Alignment.Center }) {
      if (option.isDefault) {
        Image($r('app.media.aira_default_app_icon'))
          .width(APP_ICON_OPTION_SIZE)
          .height(APP_ICON_OPTION_SIZE)
          .borderRadius(12)
          .clip(true)
          .objectFit(ImageFit.Contain)
      } else if (option.iconUrl.length > 0) {
        Image(option.iconUrl)
          .width(APP_ICON_OPTION_SIZE)
          .height(APP_ICON_OPTION_SIZE)
          .borderRadius(12)
          .clip(true)
          .objectFit(ImageFit.Contain)
      } else {
        Text('A')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.storedSecondaryTextColor)
      }
    }
    .width(APP_ICON_OPTION_SIZE)
    .height(APP_ICON_OPTION_SIZE)
    .borderRadius(12)
    .backgroundColor(this.storedControlBackgroundColor)
    .clip(true)
  }

  @Builder
  private buildStatusText() {
    Row({ space: 8 }) {
      SymbolGlyph(this.resolveStatusIcon())
        .fontSize(16)
        .fontColor([this.storedSecondaryTextColor])

      Text(this.state.statusText)
        .fontSize(13)
        .lineHeight(18)
        .fontColor(this.storedSecondaryTextColor)
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 2 })
    .alignItems(VerticalAlign.Top)
  }

  private refreshIcons(): void {
    this.isLoading = true;
    this.state = this.viewModel.buildLoadingState();
    this.service.queryIcons()
      .then((result) => {
        this.isLoading = false;
        this.state = this.viewModel.buildState(result);
      })
      .catch((_error: Error) => {
        this.isLoading = false;
        this.state = this.viewModel.buildState({
          availability: 'service_unavailable',
          icons: [],
          code: 0,
          message: '图标管理服务暂不可用。'
        });
      });
  }

  private requestSelectOption(option: AppIconSettingsOptionState): void {
    if (!this.isOptionInteractive(option) || option.isSelected) {
      return;
    }
    this.isApplying = true;
    this.applyingOptionId = option.id;
    const task = option.isDefault ? this.service.restoreDefaultIcon() : this.service.selectIcon(option.id);
    task.then((result: DynamicAppIconMutationResult) => {
      this.isApplying = false;
      this.applyingOptionId = '';
      this.showToast(result.message);
      this.refreshIcons();
    }).catch((_error: Error) => {
      this.isApplying = false;
      this.applyingOptionId = '';
      this.showToast('应用图标更新失败。');
      this.refreshIcons();
    });
  }

  private isOptionInteractive(option: AppIconSettingsOptionState): boolean {
    return option.isEnabled && !this.isLoading && !this.isApplying;
  }

  private isOptionApplying(option: AppIconSettingsOptionState): boolean {
    return this.isApplying && this.applyingOptionId === option.id;
  }

  private resolveOptionTextColor(option: AppIconSettingsOptionState): ResourceColor {
    return this.isOptionInteractive(option) || option.isSelected
      ? this.storedPrimaryTextColor
      : this.storedSecondaryTextColor;
  }

  private resolveStatusIcon(): Resource {
    if (this.state.availability === 'loading') {
      return $r('sys.symbol.clock_fill');
    }
    if (this.state.availability === 'empty') {
      return $r('sys.symbol.info_circle_fill');
    }
    return $r('sys.symbol.exclamationmark_circle_fill');
  }

  private resolveRowPosition(index: number, count: number): SettingsRowPosition {
    if (count <= 1) {
      return 'single';
    }
    if (index === 0) {
      return 'first';
    }
    if (index === count - 1) {
      return 'last';
    }
    return 'middle';
  }

  private resolveRowBorderRadius(position: SettingsRowPosition): BorderRadiuses {
    if (position === 'single') {
      return { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 };
    }
    if (position === 'first') {
      return { topLeft: 18, topRight: 18, bottomLeft: 0, bottomRight: 0 };
    }
    if (position === 'last') {
      return { topLeft: 0, topRight: 0, bottomLeft: 18, bottomRight: 18 };
    }
    return { topLeft: 0, topRight: 0, bottomLeft: 0, bottomRight: 0 };
  }

  private showToast(message: string): void {
    if (message.length <= 0) {
      return;
    }
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 2200
      });
    } catch (_error) {
    }
  }
}
