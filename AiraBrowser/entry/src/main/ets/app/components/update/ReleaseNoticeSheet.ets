import { ReleaseNoticeUiState } from '../../../core/update/ReleaseNoticeCoordinator';
import {
  ReleaseNoticePresentationAction
} from '../../../core/update/ReleaseNoticePresentationCoordinator';
import {
  DynamicAppIconOption,
  DynamicAppIconQueryResult,
  DynamicAppIconService
} from '../../../services/appicon/DynamicAppIconService';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserSheetActionButton,
  BrowserSheetIconButton
} from '../browser/BrowserModalBottomSheet';
import { APP_STANDARD_HORIZONTAL_PADDING } from '../common/AppLayoutTokens';

const RELEASE_NOTICE_APP_ICON_SIZE: number = 84;
const RELEASE_NOTICE_APP_ICON_RADIUS: number = 21;

@Component
export struct ReleaseNoticeSheet {
  private dynamicAppIconService: DynamicAppIconService = new DynamicAppIconService();
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0F7B6C';
  @StorageProp(BROWSER_THEME_STORAGE_CONTROL_BACKGROUND_KEY) private storedControlBackgroundColor: string = '#EEF2F6';
  @StorageProp(BROWSER_THEME_STORAGE_FLOATING_SURFACE_KEY) private storedFloatingSurfaceColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: ReleaseNoticeUiState = {
    visible: false,
    noticeId: '',
    appName: '',
    versionName: '',
    versionCode: 0,
    title: '',
    updatedAt: '',
    summary: '',
    items: [],
    feedbackText: '',
    actionLabel: ''
  };
  @State private selectedDynamicIconUrl: string = '';
  onAction: (action: ReleaseNoticePresentationAction) => void =
    (_action: ReleaseNoticePresentationAction) => {};

  aboutToAppear(): void {
    this.refreshSelectedAppIcon();
  }

  build() {
    Column({ space: 18 }) {
      Row({ space: 18 }) {
        this.buildAppIcon()

        Column({ space: 4 }) {
          Text(this.resolveAppName())
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.storedPrimaryTextColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Text(this.buildVersionSubtitle())
            .fontSize(15)
            .lineHeight(21)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .margin({ top: 8 })

        BrowserSheetIconButton({
          icon: $r('sys.symbol.xmark'),
          iconSize: 17,
          accessibilityLabel: '关闭更新通知',
          onAction: () => {
            this.onAction('confirm');
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      Stack({ alignContent: Alignment.Bottom }) {
        Scroll() {
          Column({ space: 18 }) {
            Column({ space: 8 }) {
              Text(this.state.title)
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.storedPrimaryTextColor)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')

              Text(this.state.summary)
                .fontSize(15)
                .lineHeight(22)
                .fontColor(this.storedSecondaryTextColor)
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)

            Text('更新日志')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedPrimaryTextColor)
              .width('100%')

            if (this.state.items.length > 0 || this.state.feedbackText.length > 0) {
              Column({ space: 10 }) {
                ForEach(this.state.items, (item: string) => {
                  Row({ space: 8 }) {
                    Text('•')
                      .fontSize(15)
                      .fontColor(this.storedAccentColor)
                      .lineHeight(21)

                    Text(item)
                      .fontSize(14)
                      .fontColor(this.storedPrimaryTextColor)
                      .lineHeight(21)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }, (item: string) => item)

                if (this.state.feedbackText.length > 0) {
                  Row({ space: 8 }) {
                    Text('•')
                      .fontSize(15)
                      .fontColor(this.storedAccentColor)
                      .lineHeight(21)

                    Text(this.state.feedbackText)
                      .fontSize(14)
                      .fontColor(this.storedPrimaryTextColor)
                      .lineHeight(21)
                      .layoutWeight(1)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)
                }
              }
              .width('100%')
            }
          }
          .width('100%')
          .padding({ bottom: 82 })
          .constraintSize({ minHeight: '100%' })
        }
        .width('100%')
        .height('100%')
        .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
        .scrollBar(BarState.Off)

        Row() {
          BrowserSheetActionButton({
            label: this.state.actionLabel,
            emphasis: 'primary',
            accentColor: this.storedAccentColor,
            onAction: () => {
              this.onAction('open_full_changelog');
            }
          })
        }
        .width('100%')
        .padding({ bottom: 8 })
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({
      left: APP_STANDARD_HORIZONTAL_PADDING,
      right: APP_STANDARD_HORIZONTAL_PADDING,
      top: 20,
      bottom: 42
    })
    .backgroundColor(this.storedFloatingSurfaceColor)
  }

  @Builder
  private buildAppIcon() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.selectedDynamicIconUrl.length > 0) {
        Image(this.selectedDynamicIconUrl)
          .width(RELEASE_NOTICE_APP_ICON_SIZE)
          .height(RELEASE_NOTICE_APP_ICON_SIZE)
          .borderRadius(RELEASE_NOTICE_APP_ICON_RADIUS)
          .clip(true)
          .objectFit(ImageFit.Contain)
      } else {
        Image($r('app.media.aira_default_app_icon'))
          .width(RELEASE_NOTICE_APP_ICON_SIZE)
          .height(RELEASE_NOTICE_APP_ICON_SIZE)
          .borderRadius(RELEASE_NOTICE_APP_ICON_RADIUS)
          .clip(true)
          .objectFit(ImageFit.Contain)
      }
    }
    .width(RELEASE_NOTICE_APP_ICON_SIZE)
    .height(RELEASE_NOTICE_APP_ICON_SIZE)
    .borderRadius(RELEASE_NOTICE_APP_ICON_RADIUS)
    .backgroundColor(this.storedControlBackgroundColor)
    .clip(true)
  }

  private refreshSelectedAppIcon(): void {
    this.dynamicAppIconService.queryIcons()
      .then((result: DynamicAppIconQueryResult) => {
        this.selectedDynamicIconUrl = this.resolveSelectedDynamicIconUrl(result.icons);
      })
      .catch((_error: Error) => {
        this.selectedDynamicIconUrl = '';
      });
  }

  private resolveSelectedDynamicIconUrl(icons: DynamicAppIconOption[]): string {
    const selectedIcon = icons.find((icon: DynamicAppIconOption) => {
      return icon.enabled && icon.iconUrl.length > 0;
    });
    return selectedIcon?.iconUrl ?? '';
  }

  private resolveAppName(): string {
    return this.state.appName.length > 0 ? this.state.appName : 'Aira';
  }

  private buildVersionSubtitle(): string {
    const versionText = `版本 ${this.state.versionName} (${this.state.versionCode})`;
    if (this.state.updatedAt.length <= 0) {
      return versionText;
    }
    return `${versionText} · ${this.state.updatedAt}`;
  }
}
