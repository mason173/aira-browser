import {
  SyncFirstActivationItemId,
  SyncFirstActivationItemState,
  SyncFirstActivationItemsState
} from '../../../core/sync/SyncFirstActivationItemsCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_DIVIDER_KEY,
  BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  SettingsGroupCard,
  SettingsGroupDivider
} from '../settings/SettingsLayout';
import {
  BrowserSettingsIconBackgroundTokenSet,
  DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS
} from '../../../features/theme/BrowserThemePaletteModels';
import { SettingsColoredTileIconResources } from '../../../core/resources/SettingsColoredTileIconResources';
import { AiraRenderableIconId } from '../../../core/resources/GeneratedAiraIconCatalog';
import { AiraIcon } from '../common/AiraIcon';
import {
  SyncSetupStepLayoutMode,
  SyncSetupStepScaffold
} from './SyncSetupStepScaffold';

const FIRST_ACTIVATION_ROW_ICON_SIZE: number = 38;
const FIRST_ACTIVATION_ROW_HORIZONTAL_PADDING: number = 8;
const FIRST_ACTIVATION_ROW_VERTICAL_PADDING: number = 12;

@Component
export struct SyncFirstActivationItemsSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_DIVIDER_KEY) private storedDividerColor: string = '#E3E8EF';
  @StorageProp(BROWSER_THEME_STORAGE_SURFACE_BACKGROUND_KEY) private storedSurfaceBackgroundColor: string = '#FFFFFF';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @Link state: SyncFirstActivationItemsState;
  @Prop isBusy: boolean = false;
  @Prop canSubmit: boolean = true;
  @Prop layoutMode: SyncSetupStepLayoutMode = 'phone';
  @Prop submitLabel: string = '立即同步';
  @Prop settingsIconBackgrounds: BrowserSettingsIconBackgroundTokenSet =
    DEFAULT_BROWSER_SETTINGS_ICON_BACKGROUND_TOKENS;
  onToggle?: (id: SyncFirstActivationItemId, enabled: boolean) => void;
  onSubmit?: () => void;
  onClose: () => void = () => {};

  build() {
    SyncSetupStepScaffold({
      title: this.state.title,
      summary: this.state.summary,
      layoutMode: this.layoutMode,
      showSubmitButton: true,
      submitLabel: this.submitLabel,
      isBusy: this.isBusy,
      canSubmit: this.canSubmit,
      onSubmit: () => {
        this.onSubmit?.();
      },
      onClose: this.onClose
    }) {
      SettingsGroupCard({ surfaceColor: this.storedSurfaceBackgroundColor }) {
        ForEach(this.state.items, (item: SyncFirstActivationItemState, index: number) => {
          this.buildItemRow(item, this.resolveRowPosition(index, this.state.items.length))
          if (index < this.state.items.length - 1) {
            SettingsGroupDivider({ dividerColor: this.storedDividerColor })
          }
        }, (item: SyncFirstActivationItemState) => `${item.id}-${item.enabled}`)
      }
    }
  }

  @Builder
  private buildItemRow(item: SyncFirstActivationItemState, rowPosition: 'single' | 'first' | 'middle' | 'last') {
    Row({ space: 12 }) {
      Stack({ alignContent: Alignment.Center }) {
        AiraIcon({
          airaIconId: this.resolveItemIcon(item),
          iconSize: item.kind === 'bookmarks' ? 21 : 20,
          iconColor: SettingsColoredTileIconResources.foregroundColor()
        })
      }
      .width(FIRST_ACTIVATION_ROW_ICON_SIZE)
      .height(FIRST_ACTIVATION_ROW_ICON_SIZE)
      .borderRadius(12)
      .backgroundColor(this.resolveItemIconBackground(item))

      Text(item.title)
        .layoutWeight(1)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.storedPrimaryTextColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.Start)

      Toggle({ type: ToggleType.Switch, isOn: item.enabled })
        .enabled(!this.isBusy)
        .selectedColor(this.storedAccentColor)
        .onChange((value: boolean) => {
          if (!this.isBusy) {
            this.onToggle?.(item.id, value);
          }
        })
    }
    .width('100%')
    .padding({
      left: FIRST_ACTIVATION_ROW_HORIZONTAL_PADDING,
      right: FIRST_ACTIVATION_ROW_HORIZONTAL_PADDING,
      top: FIRST_ACTIVATION_ROW_VERTICAL_PADDING,
      bottom: FIRST_ACTIVATION_ROW_VERTICAL_PADDING
    })
    .borderRadius(this.resolveRowBorderRadius(rowPosition))
    .alignItems(VerticalAlign.Center)
    .opacity(this.isBusy ? 0.58 : 1)
  }

  private resolveItemIcon(item: SyncFirstActivationItemState): AiraRenderableIconId {
    if (item.kind === 'bookmarks') {
      return 'browser.shortcut.bookmarks';
    }
    if (item.id === 'home_shortcuts') {
      return 'browser.shortcut.home';
    }
    if (item.id === 'core_preferences') {
      return 'settings.general';
    }
    if (item.id === 'activity_heatmap') {
      return 'sync.firstActivation.activityHeatmap';
    }
    if (item.id === 'search') {
      return 'settings.search';
    }
    return 'settings.sync';
  }

  private resolveItemIconBackground(item: SyncFirstActivationItemState): ResourceColor {
    if (item.kind === 'bookmarks') {
      return this.settingsIconBackgrounds.sync;
    }
    if (item.id === 'home_shortcuts') {
      return this.settingsIconBackgrounds.sync;
    }
    if (item.id === 'core_preferences') {
      return this.settingsIconBackgrounds.appearance;
    }
    if (item.id === 'activity_heatmap') {
      return this.settingsIconBackgrounds.about;
    }
    if (item.id === 'search') {
      return this.settingsIconBackgrounds.search;
    }
    return this.settingsIconBackgrounds.general;
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

  private resolveRowBorderRadius(rowPosition: 'single' | 'first' | 'middle' | 'last'): BorderRadiuses {
    if (rowPosition === 'single') {
      return { topLeft: 18, topRight: 18, bottomLeft: 18, bottomRight: 18 };
    }
    if (rowPosition === 'first') {
      return { topLeft: 18, topRight: 18, bottomLeft: 4, bottomRight: 4 };
    }
    if (rowPosition === 'last') {
      return { topLeft: 4, topRight: 4, bottomLeft: 18, bottomRight: 18 };
    }
    return { topLeft: 4, topRight: 4, bottomLeft: 4, bottomRight: 4 };
  }
}
