import { AppRecommendationSheet } from './AppRecommendationSheet';
import { BrowserAdaptiveModalOverlay } from '../browser/BrowserAdaptiveModalOverlay';
import {
  BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
  FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
  FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
  FEATURE_GATE_OVERLAY_SHEET_HEIGHT
} from '../browser/BrowserShellPresentationTokens';

/** What the reader of an app's detail card can do with it. */
export type AppRecommendationAction = 'dismiss' | 'open_market';

/**
 * Hosts an app's detail card as a bottom sheet. The scrim does not dismiss it: the
 * card is a product page the user opened on purpose, so a stray tap on the dimmed
 * area must not be what closes it. The sheet's own close control, the system back
 * gesture, and the store action are the way out.
 */
@Component
export struct AppRecommendationOverlay {
  @Prop visible: boolean = false;
  /** The app whose detail sheet is open. The sheet resolves its own content. */
  @Prop recommendationId: string = '';
  onAction: (action: AppRecommendationAction) => void = (_action: AppRecommendationAction): void => {};

  build() {
    BrowserAdaptiveModalOverlay({
      visible: this.visible,
      layoutMode: 'phone',
      title: $r('app.string.app_recommendation_title'),
      dismissOnOutsideTap: false,
      phoneSheetHeight: FEATURE_GATE_OVERLAY_SHEET_HEIGHT,
      phoneEnterOffsetY: FEATURE_GATE_OVERLAY_ENTER_OFFSET_Y,
      animationDurationMs: FEATURE_GATE_OVERLAY_ANIMATION_DURATION_MS,
      zIndexValue: BROWSER_MODAL_BOTTOM_OVERLAY_Z_INDEX,
      tier: 'l',
      onDismiss: (): void => {
        this.onAction('dismiss');
      }
    }) {
      AppRecommendationSheet({
        recommendationId: this.recommendationId,
        onClose: (): void => {
          this.onAction('dismiss');
        },
        onOpenMarket: (): void => {
          this.onAction('open_market');
        }
      })
    }
  }
}
