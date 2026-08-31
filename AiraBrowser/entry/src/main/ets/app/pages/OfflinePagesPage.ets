import router from '@ohos.router';
import { OfflinePagesScreen } from '../components/offline/OfflinePagesScreen';

interface OfflinePagesPageParams {
  dataScope?: string;
  privacyMode?: string;
}

@Entry
@Component
struct OfflinePagesPage {
  @State private dataScope: string = '';
  @State private privacyMode: string = '';

  aboutToAppear(): void {
    this.refreshParams();
  }

  onPageShow(): void {
    this.refreshParams();
  }

  build() {
    Column() {
      OfflinePagesScreen({
        dataScope: this.dataScope,
        privacyMode: this.privacyMode
      })
    }
    .width('100%')
    .height('100%')
  }

  private refreshParams(): void {
    const params = router.getParams() as OfflinePagesPageParams | undefined;
    this.dataScope = params?.dataScope ?? '';
    this.privacyMode = params?.privacyMode ?? '';
  }
}
