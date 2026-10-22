import { common } from '@kit.AbilityKit';
import { DEFAULT_THEME_PALETTE } from '../../features/theme/palettes/DefaultThemePalette';
import {
  AppRecommendationEntry,
  appRecommendationCatalog
} from '../components/onboarding/AppRecommendationContent';
import {
  AppRecommendationAction,
  AppRecommendationOverlay
} from '../components/onboarding/AppRecommendationOverlay';
import { SettingsHdsScaffold } from '../components/settings/SettingsHdsScaffold';
import {
  SettingsGroupCard,
  SettingsGroupDivider,
  SettingsScrollBody
} from '../components/settings/SettingsLayout';
import { SettingsNavigationRow } from '../components/settings/SettingsRows';
import {
  SystemSettingsLaunchService,
  SystemSettingsLaunchResult
} from '../../services/system/SystemSettingsLaunchService';
import { resolveAppResourceText } from '../../core/resources/AppResourceText';
import {
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../core/theme/BrowserThemeStorageKeys';
import { SettingsNavigationCoordinator } from '../router/SettingsNavigationCoordinator';

/** The app icon in a card, matching the store's own artwork proportions. */
const APP_ICON_SIZE: number = 44;
const APP_ICON_RADIUS: number = 11;

/**
 * 设置 → 应用推荐: the apps Aira offers, each as a card that opens that app's own
 * product sheet. The catalog is source data, so putting a different app on offer is a
 * change to `AppRecommendationContent` and nothing else.
 *
 * The card is opened on demand here. Nothing on this page is announced, remembered, or
 * gated: the user came to the page, and tapping a card is what shows it.
 */
@Entry
@Component
struct SettingsAppRecommendationPage {
  private navigationCoordinator: SettingsNavigationCoordinator = new SettingsNavigationCoordinator();
  private systemSettingsLaunchService: SystemSettingsLaunchService = new SystemSettingsLaunchService();
  private apps: AppRecommendationEntry[] = appRecommendationCatalog();
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_PAGE_BACKGROUND_KEY) private storedPageBackgroundColor: string =
    DEFAULT_THEME_PALETTE.light.pageBackground;
  @StorageProp(BROWSER_THEME_STORAGE_PRESSED_BACKGROUND_KEY) private storedPressedBackgroundColor: string = '#DDE4EC';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  /** The app whose sheet is open, or the last one that was; empty until one is opened. */
  @State private sheetAppId: string = '';
  /**
   * The sheet is mounted only once an app has been opened, and stays mounted afterwards so
   * closing it can animate. Mounting it up front would build the card against no app.
   */
  @State private sheetMounted: boolean = false;
  @State private sheetVisible: boolean = false;

  build() {
    Stack() {
      Column() {
        SettingsHdsScaffold({
          title: $r('app.string.settings_app_recommendation'),
          backIconKind: 'back',
          pageBackground: this.storedPageBackgroundColor,
          headerButtonBackground: this.storedPressedBackgroundColor,
          primaryTextColor: this.storedPrimaryTextColor,
          dividerColor: this.storedDividerColor,
          onBack: () => {
            this.navigationCoordinator.back();
          }
        }) {
          SettingsScrollBody({ topPadding: 16 }) {
            SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
              ForEach(this.apps, (entry: AppRecommendationEntry, index: number) => {
                SettingsNavigationRow({
                  title: entry.name,
                  description: entry.tagline,
                  useCustomLeading: true,
                  customLeading: (): void => {
                    this.buildAppIcon(entry)
                  },
                  primaryTextColor: this.storedPrimaryTextColor,
                  secondaryTextColor: this.storedSecondaryTextColor,
                  pressedBackgroundColor: this.storedPressedBackgroundColor,
                  rowPosition: this.resolveRowPosition(index, this.apps.length),
                  onAction: () => {
                    this.openAppDetail(entry)
                  }
                })
                if (index < this.apps.length - 1) {
                  SettingsGroupDivider({ dividerColor: this.storedDividerColor })
                }
              }, (entry: AppRecommendationEntry): string => entry.id)
            }
          }
        }
      }
      .width('100%')
      .height('100%')

      if (this.sheetMounted) {
        AppRecommendationOverlay({
          visible: this.sheetVisible,
          recommendationId: this.sheetAppId,
          onAction: (action: AppRecommendationAction) => {
            this.handleSheetAction(action);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.storedPageBackgroundColor)
  }

  @Builder
  private buildAppIcon(entry: AppRecommendationEntry) {
    Image(entry.icon as Resource)
      .width(APP_ICON_SIZE)
      .height(APP_ICON_SIZE)
      .borderRadius(APP_ICON_RADIUS)
      .clip(true)
      .draggable(false)
      .accessibilityText(resolveAppResourceText(entry.name))
  }

  private openAppDetail(entry: AppRecommendationEntry): void {
    this.sheetAppId = entry.id;
    this.sheetMounted = true;
    this.sheetVisible = true;
  }

  /**
   * Both actions close the card. The app id is kept so the closing animation still draws the
   * card it is dismissing; opening the next app overwrites it.
   */
  private handleSheetAction(action: AppRecommendationAction): void {
    this.sheetVisible = false;
    if (action === 'open_market') {
      this.openAppStorePage(this.sheetAppId);
    }
  }

  /**
   * The offered app is handed to AppGallery, never to Aira. Aira installs nothing and
   * never reads whether the app is already installed, so a store that cannot answer is
   * the only outcome worth reporting.
   */
  private openAppStorePage(appId: string): void {
    const storeId = this.resolveStoreId(appId);
    if (storeId.length === 0) {
      return;
    }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (!context) {
      return;
    }
    void this.systemSettingsLaunchService.openAppGalleryDetailPageForApp(context, storeId)
      .then((result: SystemSettingsLaunchResult): void => {
        if (!result.success) {
          this.showToast(result.message);
        }
      })
      .catch((_error: Error): void => {
      });
  }

  private resolveStoreId(appId: string): string {
    for (let index = 0; index < this.apps.length; index++) {
      if (this.apps[index].id === appId) {
        return this.apps[index].storeId;
      }
    }
    return '';
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({
        message: message,
        duration: 1500
      });
    } catch (_error) {
    }
  }

  private resolveRowPosition(index: number, count: number): 'single' | 'first' | 'middle' | 'last' {
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
}
