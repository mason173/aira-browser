import { CustomHomepageSettingsPageBinding } from '../../../core/customhome/CustomHomepageSettingsPageBinding';
import {
  createDefaultSettingsCenterPresentationSnapshot,
  SettingsCenterPresentationIntent,
  SettingsCenterPresentationIntentDispatcher,
  SettingsCenterPresentationSnapshot
} from './SettingsCenterPresentationContract';
import { SettingsLargeScreenShell } from './SettingsLargeScreenShell';
import { SettingsTouchPresentationAdapter } from './SettingsTouchPresentationAdapter';

@Component
export struct SettingsCenterPresentationHost {
  customHomepagePageBinding: CustomHomepageSettingsPageBinding = new CustomHomepageSettingsPageBinding();
  @Prop snapshot: SettingsCenterPresentationSnapshot = createDefaultSettingsCenterPresentationSnapshot();
  onIntent: SettingsCenterPresentationIntentDispatcher =
    (_intent: SettingsCenterPresentationIntent): void => {};

  build() {
    if (this.snapshot.shellFamily === 'large_screen') {
      SettingsLargeScreenShell({
        customHomepagePageBinding: this.customHomepagePageBinding,
        snapshot: this.snapshot,
        onIntent: (intent: SettingsCenterPresentationIntent) => {
          this.onIntent(intent);
        }
      })
    } else {
      SettingsTouchPresentationAdapter({
        snapshot: this.snapshot,
        onIntent: (intent: SettingsCenterPresentationIntent) => {
          this.onIntent(intent);
        }
      })
    }
  }
}
