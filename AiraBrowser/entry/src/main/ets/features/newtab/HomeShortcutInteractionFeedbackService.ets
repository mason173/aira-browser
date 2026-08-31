import vibrator from '@ohos.vibrator';

const HOME_SHORTCUT_CONTEXT_MENU_HAPTIC_INTENSITY: number = 100;
const HOME_SHORTCUT_CONTEXT_MENU_FALLBACK_DURATION_MS: number = 42;

export class HomeShortcutInteractionFeedbackService {
  static performContextMenuFeedback(): void {
    HomeShortcutInteractionFeedbackService.performPresetFeedback(
      vibrator.HapticFeedback.EFFECT_HARD,
      HOME_SHORTCUT_CONTEXT_MENU_HAPTIC_INTENSITY,
      HOME_SHORTCUT_CONTEXT_MENU_FALLBACK_DURATION_MS
    );
  }

  private static performPresetFeedback(effectId: string, intensity: number, fallbackDurationMs: number): void {
    try {
      vibrator.startVibration({
        type: 'preset',
        effectId: effectId,
        count: 1,
        intensity: intensity
      }, {
        usage: 'touch'
      }).catch((_error: Error) => {
        HomeShortcutInteractionFeedbackService.performTimedFallback(fallbackDurationMs);
      });
    } catch (_error) {
      HomeShortcutInteractionFeedbackService.performTimedFallback(fallbackDurationMs);
    }
  }

  private static performTimedFallback(durationMs: number): void {
    try {
      vibrator.startVibration({
        type: 'time',
        duration: durationMs
      }, {
        usage: 'touch'
      }).catch((_error: Error) => {
      });
    } catch (_error) {
    }
  }
}
