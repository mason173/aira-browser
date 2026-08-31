import { BrowserDownloadManagementScreen } from '../components/browser/BrowserDownloadManagementScreen';

@Entry({ useSharedStorage: true })
@Component
struct DownloadManagementPage {
  build() {
    Column() {
      BrowserDownloadManagementScreen({ presentationMode: 'page' })
    }
    .width('100%')
    .height('100%')
  }
}
