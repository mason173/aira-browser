import { AiraSyncProviderKind } from '../../../common/models/AiraSyncModels';
import { SyncExperienceGoalOption } from '../../../core/sync/SyncExperienceViewModel';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import { DEFAULT_THEME_PALETTE } from '../../../features/theme/palettes/DefaultThemePalette';
import { SettingsGroupCard } from '../settings/SettingsLayout';
import { SettingsOptionRow } from '../settings/SettingsRows';
import { BrowserSheetActionButton } from '../browser/BrowserModalBottomSheet';
import {
  SyncSetupStepLayoutMode,
  SyncSetupStepScaffold
} from './SyncSetupStepScaffold';

const AIRA_CLOUD_TUTORIAL_LABEL: string = '查看多端同步教程';

@Component
export struct SyncGoalSelectionSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string =
    DEFAULT_THEME_PALETTE.light.accent;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pressedBackground;
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.surfaceBackground;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textPrimary;
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string =
    DEFAULT_THEME_PALETTE.light.textSecondary;
  @Prop options: SyncExperienceGoalOption[] = [];
  @Prop isBusy: boolean = false;
  @Prop isPrivateSession: boolean = false;
  @Prop showBackButton: boolean = false;
  @Prop layoutMode: SyncSetupStepLayoutMode = 'phone';
  @Prop radioGroup: string = 'sync-goal-selection';
  onBack: () => void = () => {};
  onSelect: (remoteKind: AiraSyncProviderKind) => void = (_remoteKind: AiraSyncProviderKind) => {};
  onOpenTutorial: () => void = () => {};
  onConfigureWebdav: () => void = () => {};
  onClose: () => void = () => {};

  build() {
    SyncSetupStepScaffold({
      title: '同步方式',
      summary: '选择用于同步所选内容的服务。',
      showBackButton: this.showBackButton,
      layoutMode: this.layoutMode,
      isBusy: this.isBusy,
      onBack: () => {
        this.onBack();
      },
      onClose: this.onClose
    }) {
      Column({ space: 12 }) {
        ForEach(this.options, (option: SyncExperienceGoalOption) => {
          Column({ space: 8 }) {
            SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
              SettingsOptionRow({
                title: option.title,
                helperText: '',
                rowPosition: 'single',
                isSelected: option.isSelected,
                isEnabled: !this.isPrivateSession && !this.isBusy,
                radioGroup: this.radioGroup,
                radioValue: option.id,
                membershipBadge: option.requiresPro ? 'pro' : 'none',
                primaryTextColor: this.storedPrimaryTextColor,
                secondaryTextColor: this.storedSecondaryTextColor,
                pressedBackgroundColor: this.storedPressedBackgroundColor,
                selectedIndicatorColor: this.storedAccentColor,
                onAction: () => {
                  if (!this.isPrivateSession && !this.isBusy && !option.isSelected) {
                    this.onSelect(option.id);
                  }
                }
              })
            }

            Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              Text(option.description)
                .fontSize(13)
                .lineHeight(19)
                .fontColor(this.storedSecondaryTextColor)
                .margin({ right: 6, bottom: 4 })

              if (option.id === 'aira_cloud') {
                Text(AIRA_CLOUD_TUTORIAL_LABEL)
                  .fontSize(13)
                  .lineHeight(19)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.storedAccentColor)
                  .margin({ bottom: 4 })
                  .opacity(!this.isPrivateSession && !this.isBusy ? 1 : 0.48)
                  .onClick(() => {
                    if (!this.isPrivateSession && !this.isBusy) {
                      this.onOpenTutorial();
                    }
                  })
              }
            }
            .width('100%')
            .padding({ left: 6, right: 6 })

            if (option.id === 'webdav') {
              BrowserSheetActionButton({
                label: '编辑 WebDAV 配置',
                actionEnabled: !this.isPrivateSession && !this.isBusy,
                fillAvailableWidth: false,
                buttonWidth: '100%',
                buttonHeight: 44,
                fontSize: 15,
                onAction: () => {
                  this.onConfigureWebdav();
                }
              })
            }

            if (option.id === 'self_hosted') {
              BrowserSheetActionButton({
                label: option.isSelected ? '管理个人服务器' : '连接个人服务器',
                actionEnabled: !this.isPrivateSession && !this.isBusy,
                fillAvailableWidth: false,
                buttonWidth: '100%',
                buttonHeight: 44,
                fontSize: 15,
                onAction: () => {
                  this.onSelect(option.id);
                }
              })
            }
          }
          .width('100%')
        }, (option: SyncExperienceGoalOption) => {
          return `${this.radioGroup}:${option.id}:${option.isSelected ? 'selected' : 'idle'}`;
        })
      }
      .width('100%')
    }
  }
}
