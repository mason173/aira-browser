import {
  SettingsCenterScreen,
  SettingsCenterScreenController
} from '../components/settings/SettingsCenterScreen';

@Entry
@Component
struct SettingsCenterPage {
  private controller: SettingsCenterScreenController = new SettingsCenterScreenController();

  onPageShow(): void {
    this.controller.notifyPageShow();
  }

  onBackPress(): boolean {
    return this.controller.handleBackPress();
  }

  build() {
    Column() {
      SettingsCenterScreen({
        controller: this.controller,
        presentationMode: 'page'
      })
        .width('100%')
        .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
