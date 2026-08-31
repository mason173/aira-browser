import {
  CustomHomepageSettingsScreen
} from '../components/customhome/CustomHomepageSettingsScreen';
import {
  CustomHomepageSettingsPageBinding
} from '../../core/customhome/CustomHomepageSettingsPageBinding';

@Entry
@Component
struct CustomHomepageSettingsPage {
  private pageBinding: CustomHomepageSettingsPageBinding = new CustomHomepageSettingsPageBinding();

  build() {
    Stack() {
      CustomHomepageSettingsScreen({
        presentationMode: 'standalone',
        pageBinding: this.pageBinding
      })
    }
    .width('100%')
    .height('100%')
  }

  onPageShow(): void {
    this.pageBinding.notifyPageShow();
  }

  onBackPress(): boolean {
    return this.pageBinding.dispatchBack();
  }
}
