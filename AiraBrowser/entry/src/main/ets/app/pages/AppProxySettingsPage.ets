import { AppProxySettingsScreen } from '../components/settings/AppProxySettingsScreen';

@Entry
@Component
struct AppProxySettingsPage {
  @State private refreshRevision: number = 0;

  onPageShow(): void {
    this.refreshRevision += 1;
  }

  build() {
    Column() {
      AppProxySettingsScreen({
        presentationMode: 'page',
        refreshRevision: this.refreshRevision
      })
    }
    .width('100%')
    .height('100%')
  }
}
