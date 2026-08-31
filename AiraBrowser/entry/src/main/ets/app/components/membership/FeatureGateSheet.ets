import {
  createHiddenFeatureGateSnapshot,
  FeatureGateAction,
  FeatureGateSnapshot
} from '../../../core/membership/FeatureGateCoordinator';
import {
  BROWSER_THEME_STORAGE_ACCENT_KEY,
  BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY,
  BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY
} from '../../../core/theme/BrowserThemeStorageKeys';
import {
  BrowserBottomSheetSurface,
  BrowserSheetActionButton
} from '../browser/BrowserModalBottomSheet';

@Component
export struct FeatureGateSheet {
  @StorageProp(BROWSER_THEME_STORAGE_ACCENT_KEY) private storedAccentColor: string = '#0A59F7';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_PRIMARY_KEY) private storedPrimaryTextColor: string = '#111318';
  @StorageProp(BROWSER_THEME_STORAGE_TEXT_SECONDARY_KEY) private storedSecondaryTextColor: string = '#5F6875';
  @Prop state: FeatureGateSnapshot = createHiddenFeatureGateSnapshot();
  @Prop layoutMode: 'phone' | 'large_screen' = 'phone';
  onAction: (action: FeatureGateAction) => void = (_action: FeatureGateAction) => {};

  build() {
    BrowserBottomSheetSurface({
      presentation: this.layoutMode === 'large_screen' ? 'flat_content' : 'bottom_sheet'
    }) {
      Column({ space: 18 }) {
        Column({ space: 10 }) {
          if (this.layoutMode === 'phone') {
            Text(this.state.title)
              .width('100%')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.storedPrimaryTextColor)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Text(this.state.message)
            .width('100%')
            .fontSize(15)
            .lineHeight(22)
            .fontColor(this.storedSecondaryTextColor)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)

        Row({ space: 12 }) {
          BrowserSheetActionButton({
            label: this.state.secondaryActionTitle,
            onAction: () => {
              this.onAction(this.state.secondaryAction);
            }
          })
          BrowserSheetActionButton({
            label: this.state.primaryActionTitle,
            emphasis: 'primary',
            accentColor: this.storedAccentColor,
            onAction: () => {
              this.onAction(this.state.primaryAction);
            }
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }
}
